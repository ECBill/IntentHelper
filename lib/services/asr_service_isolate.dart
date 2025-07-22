import 'dart:isolate';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../utils/asr_utils.dart';
import 'asr_service.dart';

class AsrServiceIsolate{
  late SendPort sendPort;
  late Isolate _isolate;
  bool isInitialized = false;
  RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;

  // 将 OfflineRecognizer 移到主线程
  sherpa_onnx.OfflineRecognizer? _mainThreadRecognizer;

  Future init()async{
    // 先测试 Whisper 模型加载
    print('[AsrServiceIsolate] Testing Whisper model loading...');
    try {
      final testRecognizer = await createNonstreamingRecognizer();
      print('[AsrServiceIsolate] ✅ Whisper model test PASSED - can create OfflineRecognizer');
      testRecognizer.free();
    } catch (e, st) {
      print('[AsrServiceIsolate] ❌ Whisper model test FAILED: $e');
      print('[AsrServiceIsolate] Stack trace: $st');
      // 继续执行，但记录错误
    }

    // 在主线程初始化 OfflineRecognizer
    print('[AsrServiceIsolate] Creating OfflineRecognizer in main thread...');
    _mainThreadRecognizer = await createNonstreamingRecognizer();
    print('[AsrServiceIsolate] OfflineRecognizer created successfully in main thread');

    var receivePort = ReceivePort();
    await getNonstreamingModelConfig();
    _isolate = await Isolate.spawn(_handle, receivePort.sendPort);
    sendPort = await receivePort.first;
    receivePort.close();
    final task = Task("init", "");
    sendPort.send(task.toList());
    await task.response.first;
    isInitialized=true;
  }

  _handle(SendPort sendPort)async{
    // 移除 Isolate 中的 OfflineRecognizer 初始化
    var receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    await for(var msg in receivePort){
      if(msg is List<Object>){
        final action = msg[0] as String;
        final sendPort = msg[2] as SendPort;
        if(action=='init'){
          try {
            print('[AsrServiceIsolate] Starting init in isolate...');

            print('[AsrServiceIsolate] Calling sherpa_onnx.initBindings()...');
            sherpa_onnx.initBindings();
            print('[AsrServiceIsolate] sherpa_onnx.initBindings() completed successfully');

            print('[AsrServiceIsolate] Calling BackgroundIsolateBinaryMessenger.ensureInitialized()...');
            BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
            print('[AsrServiceIsolate] BackgroundIsolateBinaryMessenger.ensureInitialized() completed successfully');

            // 不再在 Isolate 中创建 OfflineRecognizer
            sendPort.send("initialized");
            print('[AsrServiceIsolate] Init completed successfully');
          } catch (e, st) {
            print('[AsrServiceIsolate] Init failed with error: $e');
            print('[AsrServiceIsolate] Stack trace: $st');
            sendPort.send("init_failed: $e");
          }
        }else if(action =='stopRecord'){
          try {
            print('[AsrServiceIsolate] Stopping record...');
            // 不需要在 Isolate 中释放，主线程负责
            sendPort.send("stopped");
            print('[AsrServiceIsolate] Stop record completed');
          } catch (e, st) {
            print('[AsrServiceIsolate] Stop record failed: $e');
            print('[AsrServiceIsolate] Stack trace: $st');
            sendPort.send("stop_failed: $e");
          }
        }else if(action =='sendData'){
          // sendData 逻辑移到主线程处理
          sendPort.send("sendData_not_supported_in_isolate");
        }
      }
    }
  }

  Future<String> sendData(Float32List data)async{
    // 在主线程直接处理 ASR
    try {
      print('[AsrServiceIsolate] Processing sendData in main thread...');
      if (_mainThreadRecognizer == null) {
        throw Exception('OfflineRecognizer not initialized');
      }

      final nonstreamStream = _mainThreadRecognizer!.createStream();
      nonstreamStream.acceptWaveform(samples: data, sampleRate: 16000);
      _mainThreadRecognizer!.decode(nonstreamStream);
      final result = _mainThreadRecognizer!.getResult(nonstreamStream).text;
      nonstreamStream.free();
      print('[AsrServiceIsolate] sendData completed in main thread, result: $result');
      return result;
    } catch (e, st) {
      print('[AsrServiceIsolate] sendData failed in main thread: $e');
      print('[AsrServiceIsolate] Stack trace: $st');
      return "sendData_failed: $e";
    }
  }

  Future stopRecord()async{
    try {
      print('[AsrServiceIsolate] Stopping record in main thread...');
      _mainThreadRecognizer?.free();
      _mainThreadRecognizer = null;

      final task = Task("stopRecord", "");
      sendPort.send(task.toList());
      await task.response.first;
      print('[AsrServiceIsolate] Stop record completed in main thread');
    } catch (e, st) {
      print('[AsrServiceIsolate] Stop record failed in main thread: $e');
      print('[AsrServiceIsolate] Stack trace: $st');
    }
  }
}

class Task{
  final String action;
  final dynamic data;
  final ReceivePort  response = ReceivePort();
  Task(this.action, this.data);

  List<Object> toList()=>[action,data,response.sendPort];
}

Future<sherpa_onnx.OfflineRecognizer> createNonstreamingRecognizer() async {
  print('[createNonstreamingRecognizer] Getting model config...');
  final modelConfig = await getNonstreamingModelConfig();
  print('[createNonstreamingRecognizer] Model config obtained successfully');

  print('[createNonstreamingRecognizer] Creating OfflineRecognizerConfig...');
  final config = sherpa_onnx.OfflineRecognizerConfig(
    model: modelConfig,
    // 尝试不传递 ruleFsts 参数，或者传递 null
    // ruleFsts: '',
  );
  print('[createNonstreamingRecognizer] OfflineRecognizerConfig created successfully');

  print('[createNonstreamingRecognizer] Creating OfflineRecognizer...');
  final recognizer = sherpa_onnx.OfflineRecognizer(config);
  print('[createNonstreamingRecognizer] OfflineRecognizer created successfully');

  return recognizer;
}

Future<sherpa_onnx.OfflineModelConfig> getNonstreamingModelConfig() async {
  const modelDir = 'assets/sherpa-onnx-whisper-tiny.en';
  final encoderPath = await copyAssetFile('$modelDir/tiny.en-encoder.int8.onnx');
  final decoderPath = await copyAssetFile('$modelDir/tiny.en-decoder.int8.onnx');
  final tokensPath = await copyAssetFile('$modelDir/tiny.en-tokens.txt');

  print('[getNonstreamingModelConfig] encoder: $encoderPath');
  print('[getNonstreamingModelConfig] decoder: $decoderPath');
  print('[getNonstreamingModelConfig] tokens: $tokensPath');

  return sherpa_onnx.OfflineModelConfig(
    tokens: tokensPath,
    whisper: sherpa_onnx.OfflineWhisperModelConfig(
      encoder: encoderPath,
      decoder: decoderPath,
      // 尝试去掉 tailPaddings 或设为 0
      // tailPaddings: 1000,
    ),
    modelType: "whisper",
  );
}