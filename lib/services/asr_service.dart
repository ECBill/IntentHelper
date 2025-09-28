import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:app/constants/prompt_constants.dart';
import 'package:app/constants/wakeword_constants.dart';
import 'package:app/services/cloud_asr.dart';
import 'package:app/services/cloud_tts.dart';
import 'package:app/services/latency_logger.dart';
import 'package:app/services/streaming_asr_service.dart';
import 'package:app/services/summary.dart';
import 'package:app/utils/text_process_utils.dart';
import 'package:app/utils/asr_utils.dart';
import 'package:app/utils/audio_process_util.dart';
import 'package:app/utils/wav/audio_save_util.dart';
import 'package:app/utils/text_utils.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:linalg/linalg.dart';

import '../constants/voice_constants.dart';
import '../constants/record_constants.dart';
import '../models/record_entity.dart';
import '../models/summary_entity.dart';
import '../models/speaker_entity.dart';
import '../services/ble_service.dart';
import '../services/objectbox_service.dart';
import '../services/chat_manager.dart';

const int nDct = 257; // DCT矩阵维度
const int nPca = 47;  // PCA矩阵维度
const int nPackageByte = 244; // BLE音频包字节数
final Float32List silence = Float32List((16000 * 5).toInt()); // 5秒静音缓冲区

@pragma('vm:entry-point')
void startRecordService() {
  FlutterForegroundTask.setTaskHandler(RecordServiceHandler());
}

class RecordServiceHandler extends TaskHandler {
  // 核心组件
  AudioRecorder _record = AudioRecorder();
  sherpa_onnx.VoiceActivityDetector? _vad;
  sherpa_onnx.SpeakerEmbeddingExtractor? _extractor;
  sherpa_onnx.SpeakerEmbeddingManager? _manager;
  StreamingAsrService _streamingAsr = StreamingAsrService();

  // 服务实例
  final ObjectBoxService _objectBoxService = ObjectBoxService();
  final CloudTts _cloudTts = CloudTts();
  final CloudAsr _cloudAsr = CloudAsr();
  final ChatManager _chatManager = ChatManager();
  late FlutterTts _flutterTts;

  // 状态变量
  bool _inDialogMode = false;
  bool _isUsingCloudServices = true;
  bool _isNeedVoiceprintInit = false;
  bool _isInitialized = false;
  bool _isBoneConductionActive = true;
  bool _onRecording = true;
  bool _onMicrophone = false;
  RecordState? _recordState; // 添加缺失的录音状态变量

  // 声纹相关
  int currentStep = 0;
  String currentSpeaker = '';

  // 流订阅
  StreamSubscription<RecordState>? _recordSub;
  StreamSubscription<Uint8List>? _bleDataSubscription;
  StreamSubscription<Uint8List>? _bleAudioStreamSubscription;
  StreamSubscription? _currentSubscription;
  Stream<Uint8List>? _recordStream;

  // BLE相关
  int _lastDataReceivedTimestamp = 0;
  int _boneDataReceivedTimestamp = 0;
  final StreamController<Uint8List> _bleAudioStreamController = StreamController<Uint8List>();

  // 音频处理
  Matrix iDctWeightMatrix = Matrix.fill(nDct, nDct, 0.0);
  Matrix iPcaWeightMatrix = Matrix.fill(nPca, nDct, 0.0);
  List<double> combinedAudio = [];
  bool _lastVadState = false;

  // 对话总结相关
  Timer? _summaryTimer;
  int _lastSpeechTimestamp = 0;
  int _currentDialogueCharCount = 0;
  int? _currentDialogueStartTime;

  static const int minCharLimit = 100;
  static const int maxCharLimit = 2000;
  static const String _selectedModel = 'gpt-4o';

  // 说话人识别历史
  List<double> _userSimilarityHistory = [];
  List<double> _othersSimilarityHistory = [];

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 服务启动时初始化各项资源
    print('[onStart] 🚀 === FOREGROUND SERVICE STARTING ===');

    try {
      print('[onStart] 🔧 Initializing ObjectBoxService...');
      await ObjectBoxService.initialize();
      print('[onStart] ✅ ObjectBoxService initialized');

      print('[onStart] 🤖 Initializing ChatManager...');
      await _chatManager.init(selectedModel: _selectedModel, systemPrompt: '$systemPromptOfChat\n\n${systemPromptOfScenario['voice']}');
      print('[onStart] ✅ ChatManager initialized');

      print('[onStart] 📊 Loading matrix data...');
      iDctWeightMatrix = await loadRealMatrixFromJson(
          'assets/idct_weight.json',
          nDct, nDct
      );
      iPcaWeightMatrix = await loadRealMatrixFromJson(
          'assets/ipca_weight.json',
          nPca, nDct
      );
      print('[onStart] ✅ Matrix data loaded');

      print('[onStart] 🎤 Starting recording...');
      await _startRecord();
      print('[onStart] ✅ Recording started');

      print('[onStart] ��️ Initializing TTS...');
      await _initTts();
      print('[onStart] ✅ TTS initialized');

      print('[onStart] 📡 Initializing BLE...');
      _initBle();
      print('[onStart] ✅ BLE initialized');

      print('[onStart] ☁��������� Initializing cloud services...');
      await _cloudAsr.init();
      await _cloudTts.init();
      print('[onStart] ✅ Cloud services initialized');

      _isUsingCloudServices = _cloudAsr.isAvailable && _cloudTts.isAvailable;
      print('[onStart] 🌐 Using cloud services: $_isUsingCloudServices');

      print('[onStart] ⏰ Creating summary timer...');
      _summaryTimer = Timer.periodic(Duration(seconds: 30), (_) {
        print('[onStart] ⏰ Timer triggered - calling _checkAndSummarizeDialogue()');
        _checkAndSummarizeDialogue();
      });
      print('[onStart] ✅ Summary timer created successfully');

      print('[onStart] 🎉 === FOREGROUND SERVICE STARTED SUCCESSFULLY ===');
    } catch (e) {
      print('[onStart] ❌ Error during startup: $e');
      rethrow;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 定时事件（可用于对话总结等）
    // Perform conversation summarization repeatedly
    // DialogueSummary.start();
    // TodoManager.start();
  }

  @override
  void onReceiveData(Object data) async {
    // 处理主线程发送过来的各种控制信号
    print('[onReceiveData] 📩 Received data: $data');

    if (data == voice_constants.voiceprintDone) {
      print('[onReceiveData] 🏁 Voiceprint done signal received');
      _isNeedVoiceprintInit = false;
    } else if (data == voice_constants.voiceprintStart) {
      print('[onReceiveData] 🗣️ Voiceprint start signal received!');
      _startVoiceprint();
    } else if (data == 'startRecording') {
      print('[onReceiveData] 🎤 Start recording signal received');
      _onRecording = true;
    } else if (data == 'stopRecording') {
      print('[onReceiveData] 🛑 Stop recording signal received');
      _onRecording = false;
    } else if (data == 'device') {
      print('[onReceiveData] 📱 Device connection signal received');
      var remoteId = await FlutterForegroundTask.getData(key: 'deviceRemoteId');
      if (remoteId != null) {
        await BleService().getAndConnect(remoteId);
        BleService().listenToConnectionState();
      }
    } else if (data == Constants.actionStartMicrophone) {
      print('[onReceiveData] 🎙️ Start microphone signal received');
      FlutterForegroundTask.sendDataToMain({
        // 'isMeeting': false, // 移除会议模式
      });
      await _startMicrophone();
    } else if (data == Constants.actionStopMicrophone) {
      print('[onReceiveData] 🎙️ Stop microphone signal received');
      await _stopMicrophone();
    }
    FlutterForegroundTask.sendDataToMain(Constants.actionDone);
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // 服务销毁时释放资源
    await _stopRecord();
    _bleDataSubscription?.cancel();
    _bleAudioStreamSubscription?.cancel();
    _summaryTimer?.cancel();
    BleService().dispose();
  }

  @override
  void onNotificationButtonPressed(String id) async {
    // 处理通知栏按钮点击事件
    if (id == Constants.actionStopRecord) {
      await _stopRecord();
      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.stopService();
      }
    }
  }

  // 初始化BLE服务，监听BLE数据流
  void _initBle() async {
    await BleService().init();
    _bleDataSubscription?.cancel();
    _bleDataSubscription = BleService().dataStream.listen((value) {
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      if (value.length == nPackageByte) {
        if (value[0] == 0xff || value[0] == 0xfe) {
          // 会议模式相关逻辑移除
          _decodeAndProcessBlePackage(value, currentTime);
        } else if (value[0] == 0x01) {
          if (!_isBoneConductionActive) {
            _isBoneConductionActive = true;
            FlutterForegroundTask.sendDataToMain({'isBoneConductionActive': true});
          }
          _boneDataReceivedTimestamp = currentTime;
        } else if (value[0] == 0x00) {
          if (_isBoneConductionActive && currentTime - _boneDataReceivedTimestamp > 2000) {
            _isBoneConductionActive = false;
            FlutterForegroundTask.sendDataToMain({'isBoneConductionActive': false});
          }
        }
      } else {
        if (kDebugMode) {
          print("Unexpected BLE data length: {value.length}");
        }
      }
    });

    _bleAudioStreamSubscription?.cancel();
    _bleAudioStreamSubscription = _bleAudioStreamController.stream.listen((bleAudioClip) {
      _processAudioData(bleAudioClip);
    });
  }

  // 解码并处理BLE音频包
  void _decodeAndProcessBlePackage(Uint8List value, int currentTime) async {
    // 会议模式相关逻辑移除
    _lastDataReceivedTimestamp = currentTime;
    for (var i = 0; i < 3; i++) {
      var audioSlice = AudioProcessingUtil.processSinglePackage(
          value.sublist(1 + i * 80, 1 + (i + 1) * 80),
          iPcaWeightMatrix,
          iDctWeightMatrix
      );
      combinedAudio.addAll(audioSlice);
      if (combinedAudio.length == 512) {
        Uint8List data = Uint8List(512 * 2);
        for (var j = 0; j < 512; j++) {
          data[j * 2] = (combinedAudio[j] * 32767).toInt();
          data[j * 2 + 1] = (combinedAudio[j] * 32767).toInt() >> 8;
        }
        _bleAudioStreamController.add(data);
        combinedAudio.clear();
      }
    }
  }

  // 初始化TTS（本地或云端）
  Future<void> _initTts() async {
    try {
      print('[_initTts] 🔄 Starting TTS initialization...');

      _flutterTts = FlutterTts();

      if (Platform.isAndroid) {
        await _flutterTts.setQueueMode(1);

        try {
          await _flutterTts.setLanguage("en-US");
          print('[_initTts] 🗣️ Language set to en-US');
        } catch (langError) {
          print('[_initTts] ⚠�� Failed to set language: $langError');
        }
      }

      await _flutterTts.awaitSpeakCompletion(true);

      print('[_initTts] ✅ TTS initialized successfully');
    } catch (e) {
      print('[_initTts] ❌ TTS initialization error: $e');
      try {
        _flutterTts = FlutterTts();
      } catch (fallbackError) {
        print('[_initTts] ❌ Fallback TTS creation also failed: $fallbackError');
      }
    }
  }

  // 初始化ASR（VAD、本地ASR、声纹识别等）
  Future<void> _initAsr() async {
    if (!_isInitialized) {

      sherpa_onnx.initBindings();

      _vad = await initVad();

      // 初始化流式ASR服务
      print('[_initAsr] 🎯 Initializing streaming ASR service...');
      await _streamingAsr.init();

      // 应用性能优化设置 - 优先速度，保持准确性
      _streamingAsr.setPerformanceMode(
        enableAudioEnhancement: false,      // 关闭音频增强以提升速度
        enablePartialCorrection: false,     // 只对最终结果纠错
        enableTextCorrection: true,         // 保持纠错功能以维持准确性
      );

      print('[_initAsr] ✅ Streaming ASR service initialized with optimized settings');

      await _initSpeakerRecognition();

      _recordSub = _record.onStateChanged().listen((recordState) {
        _recordState = recordState;
      });

      _isInitialized = true;
    }
  }

  // 初始化声纹识别模型和管理器
  Future<void> _initSpeakerRecognition() async {
    try {
      print('[_initSpeakerRecognition] 🔄 开始初始化声纹识别系统...');

      // 尝试获取声纹模型文件
      String? modelPath = await _ensureSpeakerModelExists();

      if (modelPath == null) {
        print('[_initSpeakerRecognition] ❌ 无法获取声纹模型文件，声纹识别将被禁用');
        _extractor = null;
        _manager = null;
        return;
      }

      print('[_initSpeakerRecognition] 📁 使用模型文件: $modelPath');

      // 创建声纹提取器配置
      final config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(model: modelPath);
      _extractor = sherpa_onnx.SpeakerEmbeddingExtractor(config: config);

      if (_extractor == null) {
        print('[_initSpeakerRecognition] ❌ 声纹提取器创建失败');
        return;
      }

      // 创建声纹管理器
      _manager = sherpa_onnx.SpeakerEmbeddingManager(_extractor!.dim);
      print('[_initSpeakerRecognition] ✅ 声纹管理器创建成功，维度: ${_extractor!.dim}');

      // 加载已注册的用户声纹
      await _loadRegisteredSpeakers();

      print('[_initSpeakerRecognition] ✅ 声纹识别系统初始化完成');
    } catch (e) {
      print('[_initSpeakerRecognition] ❌ 声纹识别初始化失败: $e');
      print('[_initSpeakerRecognition] 🔄 声纹识别将被禁用...');

      // 完全禁用声纹识别，避免创建虚拟manager
      _extractor = null;
      _manager = null;
    }
  }

  // 确保声纹模型文件存在
  Future<String?> _ensureSpeakerModelExists() async {
    try {
      // 按优先级尝试不同的模型文件
      final modelCandidates = [
        'assets/3dspeaker_speech_eres2net_base_200k_sv_zh-cn_16k-common.onnx', // 用户新下载的3dspeaker模型 (第一优先级)
        'assets/voxceleb_resnet34_LM.onnx',          // WeSpeaker ResNet34 Large-Margin 备用
        'assets/wespeaker_resnet34.onnx',           // WeSpeaker ResNet34 备用
        'assets/speaker_embedding.onnx',             // 通用声纹模型
        'assets/cam++_voxceleb.onnx',               // CAM++ VoxCeleb
      ];

      for (String modelAssetPath in modelCandidates) {
        try {
          final modelPath = await copyAssetFile(modelAssetPath);
          print('[_ensureSpeakerModelExists] ✅ 成功加载模型: $modelAssetPath');
          return modelPath;
        } catch (e) {
          print('[_ensureSpeakerModelExists] ⚠️ 模型文件不存在: $modelAssetPath');
          continue;
        }
      }

      print('[_ensureSpeakerModelExists] ❌ 所有预设模型文件都不存在');
      return null;
    } catch (e) {
      print('[_ensureSpeakerModelExists] ❌ 获取模型文件时发生错误: $e');
      return null;
    }
  }

  // 从网络下载声纹模型 (暂时保留接口)
  Future<String?> _downloadSpeakerModel() async {
    try {
      print('[_downloadSpeakerModel] 🌐 开始下载声纹模型文件...');

      // 这里可以添加实际的下载逻辑
      // 推荐下载地址：
      // ECAPA-TDNN: https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb
      // WeSpeaker: https://github.com/wenet-e2e/wespeaker

      print('[_downloadSpeakerModel] ⚠️ 网络下载功能暂未实现');
      return null;
    } catch (e) {
      print('[_downloadSpeakerModel] ❌ 下载模型文件失败: $e');
      return null;
    }
  }

  // 加载已注册的说话人
  Future<void> _loadRegisteredSpeakers() async {
    try {
      final speakers = _objectBoxService.getUserSpeaker();
      if (speakers == null || speakers.isEmpty) {
        print('[_loadRegisteredSpeakers] ℹ️ 没有已注册的用户声纹');
        return;
      }

      int loadedCount = 0;
      for (var speaker in speakers) {
        if (speaker.name != null && speaker.embedding != null && speaker.embedding!.isNotEmpty) {
          try {
            _manager!.add(name: speaker.name!, embedding: Float32List.fromList(speaker.embedding!));
            loadedCount++;
            print('[_loadRegisteredSpeakers] ✅ 加载用户声纹: ${speaker.name}');
          } catch (addError) {
            print('[_loadRegisteredSpeakers] ⚠️ 加载用户声纹失败 ${speaker.name}: $addError');
          }
        }
      }

      print('[_loadRegisteredSpeakers] 📊 总共加载了 $loadedCount 个用户声纹');
    } catch (e) {
      print('[_loadRegisteredSpeakers] ❌ 加载已注册说话人失败: $e');
    }
  }

  // 启动录音流程
  Future<void> _startRecord() async {
    await _initAsr();

    // 移除蓝牙限制，直接启动麦克风
    print('[_startRecord] 🎤 Starting microphone recording...');
    _startMicrophone();

    FlutterForegroundTask.saveData(key: 'isRecording', value: true);
    // create stop action button
    FlutterForegroundTask.updateService(
      notificationText: 'Recording...',
      notificationButtons: [
        const NotificationButton(id: Constants.actionStopRecord, text: 'stop'),
      ],
    );
  }

  // 启动麦克风录音
  Future<void> _startMicrophone() async {
    print('[_startMicrophone] 🎙️ === MICROPHONE START ATTEMPT ===');
    print('[_startMicrophone] Current state: _onMicrophone = $_onMicrophone');
    print('[_startMicrophone] Current recordStream: ${_recordStream != null ? "EXISTS" : "NULL"}');

    if (_onMicrophone) {
      print('[_startMicrophone] ⚠️ Microphone already on, returning');
      return;
    }

    if (_recordStream != null) {
      print('[_startMicrophone] ⚠️ Record stream already exists, returning');
      return;
    }

    _onMicrophone = true;
    print('[_startMicrophone] 🔄 Setting _onMicrophone = true');

    const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1
    );
    print('[_startMicrophone] 🔧 Created RecordConfig: ${config.toString()}');

    try {
      _record = AudioRecorder();
      print('[_startMicrophone] 📱 AudioRecorder created');

      // 尝试直接启动录音，而不是先检查权限
      print('[_startMicrophone] 🚀 Attempting to start audio stream directly...');

      try {
        _recordStream = await _record.startStream(config);
        print('[_startMicrophone] ✅ Audio stream started successfully!');

        _recordStream?.listen(
                (data) {
              // print('[_startMicrophone] 🎵 Audio data received: ${data.length} bytes');
              _processAudioData(data);
            },
            onError: (error) {
              print('[_startMicrophone] ❌ Audio stream error: $error');
            },
            onDone: () {
              // print('[_startMicrophone] 🏁 Audio stream ended');
            }
        );

        // print('[_startMicrophone] 🎤 === MICROPHONE STARTED SUCCESSFULLY ===');
      } catch (recordError) {
        print('[_startMicrophone] ❌ Failed to start recording: $recordError');

        // 如��直接启动失败，再检查权限
        print('[_startMicrophone] 🔐 Checking permissions after failure...');
        bool hasPermission = await _record.hasPermission();
        print('[_startMicrophone] 🔐 Microphone permission check result: $hasPermission');

        if (!hasPermission) {
          print('[_startMicrophone] ❌ No microphone permission! Requesting...');
          hasPermission = await _record.hasPermission();
          print('[_startMicrophone] 🔐 Permission after request: $hasPermission');
        }

        _onMicrophone = false;
        _recordStream = null;
      }
    } catch (e) {
      print('[_startMicrophone] ❌ Failed to create AudioRecorder: $e');
      _onMicrophone = false;
      _recordStream = null;
    }
  }

  // 处理音频数据�������VAD、ASR、声纹识别等主流程）
  void _processAudioData(data, {String category = RecordEntity.categoryDefault}) async {
    // print('[_processAudioData] 🎤 Received audio data: ${data.length} bytes');

    if (_vad == null || !_streamingAsr.isInitialized) {
      print('[_processAudioData] ❌ VAD is null: ${_vad == null}, Streaming ASR not initialized: ${!_streamingAsr.isInitialized}');
      return;
    }

    FileService.highSaveWav(
      startMeetingTime: null, // 会议相关参数移除
      onRecording: false, // 会议相关参数移除
      data: data,
      numChannels: 1,
      sampleRate: 16000,
    );

    if (!_onRecording) {
      print('[_processAudioData] ❌ Recording is disabled (_onRecording = false)');
      return;
    }

    // print('[_processAudioData] 🔄 Converting audio to Float32...');
    final samplesFloat32 = convertBytesToFloat32(Uint8List.fromList(data));
    // print('[_processAudioData] ✅ Converted to ${samplesFloat32.length} float32 samples');

    // print('[_processAudioData] 🎯 Feeding audio to VAD...');
    _vad!.acceptWaveform(samplesFloat32);

    if (_vad!.isDetected() && _isBoneConductionActive && _inDialogMode) {
      print('[_processAudioData] 🔇 VAD detected speech during dialog mode, stopping TTS...');
      if (_isUsingCloudServices) {
        if (_cloudTts.isPlaying) {
          _cloudTts.stop();
          AudioPlayer().play(AssetSource('audios/interruption.wav'));
        }
      } else {
        _flutterTts.stop();
      }
    }

    final vadDetected = _vad!.isDetected();
    if (vadDetected) {
      print('[_processAudioData] 🗣️ VAD DETECTED SPEECH! Sending to main...');
      FlutterForegroundTask.sendDataToMain({'isVadDetected': true});
    } else {
      // 只在状态变化时打印，避免日志过多
      if (_lastVadState != vadDetected) {
        print('[_processAudioData] 🔇 VAD: No speech detected');
        _lastVadState = vadDetected;
      }
      FlutterForegroundTask.sendDataToMain({'isVadDetected': false});
    }

    var text = '';
    int segmentCount = 0;

    // print('[_processAudioData] 📦 Checking VAD queue... isEmpty: ${_vad!.isEmpty()}');

    while (!_vad!.isEmpty()) {
      segmentCount++;
      // print('[_processAudioData] 🎵 Processing audio segment #$segmentCount');

      final samples = _vad!.front().samples;
      // print('[_processAudioData] 📏 Segment has ${samples.length} samples (required: ${_vad!.config.sileroVad.windowSize})');

      if (samples.length < _vad!.config.sileroVad.windowSize) {
        print('[_processAudioData] ⚠️ Segment too short, skipping...');
        break;
      }
      _vad!.pop();

      // print('[_processAudioData] 🔧 Adding silence padding...');
      Float32List paddedSamples = await _addSilencePadding(samples);
      // print('[_processAudioData] ✅ Padded samples: ${paddedSamples.length}');

      var segment = '';
      if (_inDialogMode && _isUsingCloudServices) {
        print('[_processAudioData] ☁️ Using cloud ASR for recognition...');
        segment = await _cloudAsr.recognize(paddedSamples);
      } else {
        // print('[_processAudioData] 🎯 Using streaming paraformer ASR for recognition...');
        segment = await _streamingAsr.processAudio(paddedSamples);
      }

      // print('[_processAudioData] 📝 ASR result: "$segment"');

      segment = segment.replaceFirst('Buddy', 'Buddie').replaceFirst('buddy', 'buddie');
      // print('[_processAudioData] 🔄 After replacement: "$segment"');

      text += segment;
      print('[_processAudioData] 📑 Accumulated text: "$text"');

      _processIntermediateResult(segment);

      print('[_processAudioData] 🎭 Extracting speaker embedding...');
      final embedding = getSpeakerEmbedding(samples);
      print('[_processAudioData] ✅ Speaker embedding extracted: ${embedding.length}');

      // 修复声纹录制��辑：只有在有文本时才进行声纹验证
      if (_isNeedVoiceprintInit) {
        print('[_processAudioData] 🗣️ VOICEPRINT MODE: _isNeedVoiceprintInit = true');
        if (text.trim().isNotEmpty) {
          print('[_processAudioData] ✅ Processing voiceprint with text: "$text"');
          _initVoiceprint(text: text, embedding: embedding);
          return;
        } else {
          print('[_processAudioData] ⚠️ Voiceprint mode but no text yet, continuing...');
        }
      } else {
        print('[_processAudioData] 👤 Normal mode: identifying speaker...');
        // 🔧 FIX: 简化声纹识别逻辑，避免阻塞ASR
        try {
          // 检查声纹质量
          if (!_isEmbeddingQualityGood(embedding)) {
            print('[_processAudioData] ⚠️ 声纹质量不佳，默认为user');
            currentSpeaker = 'user'; // 默认为用户，避免阻塞
          } else {
            // 使用改进的说话人识别，但不阻塞ASR
            currentSpeaker = _identifySpeaker(embedding);
            print('[_processAudioData] 🎯 Speaker identified as: $currentSpeaker');
          }
        } catch (speakerError) {
          print('[_processAudioData] ⚠️ Speaker identification failed: $speakerError, defaulting to user');
          currentSpeaker = 'user'; // 识别失败时默认为用户
        }
      }
    }

    print('[_processAudioData] 🏁 Processed $segmentCount segments, final text: "$text"');
    print('[_processAudioData] 📊 Mode check - _isNeedVoiceprintInit: $_isNeedVoiceprintInit, text.isNotEmpty: ${text.isNotEmpty}');

    // 只有在非声纹初始化模式或没有获得文本时才继续处理
    if (text.isNotEmpty && !_isNeedVoiceprintInit) {
      print('[_processAudioData] ✅ Calling _processFinalResult with text: "$text", speaker: "$currentSpeaker"');
      _processFinalResult(text, currentSpeaker, category: category);
    } else if (text.isEmpty) {
      print('[_processAudioData] ℹ️ No text generated from this audio segment');
    } else if (_isNeedVoiceprintInit) {
      print('[_processAudioData] ℹ️ In voiceprint mode, waiting for more audio...');
    }
  }

  // 处理ASR中间结果，实时返回文本
  void _processIntermediateResult(String text) {
    if (text.isEmpty) return;
    if (text.trim().isNotEmpty) {
      FlutterForegroundTask.sendDataToMain({
        'text': text,
        'isEndpoint': false,
        'inDialogMode': _inDialogMode,
      });
    }
  }

  // 处理ASR最终结果，存储文本、管理对话状态
  void _processFinalResult(String text, String speaker, {String category = RecordEntity.categoryDefault, String? operationId}) {
    if (text.isEmpty) return;

    if (!_inDialogMode && speaker == 'user' && wakeword_constants.wakeWordStartDialog.any((keyword) => text.toLowerCase().contains(keyword))) {
      _inDialogMode = true;
    }

    text = text.trim();
    text = TextProcessUtils.removeBracketsContent(text);
    text = TextProcessUtils.clearIfRepeatedMoreThanFiveTimes(text);
    text = text.trim();

    if (text.isEmpty) {
      return;
    }

    // === 新增：对话统计逻辑 ===
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastSpeechTimestamp = now;
    _currentDialogueCharCount += text.length;
    // 只有在分段后才重置_startTime，正常语音进来时才赋值
    if (_currentDialogueStartTime == null) {
      _currentDialogueStartTime = now;
    }
    // ======================

    if (text.trim().isNotEmpty) {
      FlutterForegroundTask.sendDataToMain({
        'text': text,
        'isEndpoint': true,
        'inDialogMode': _inDialogMode,
        'speaker': speaker,
      });
    }

    // 会议相关插入逻辑移除，统一插入默认/对话记录
    if (speaker != 'user') {
      _objectBoxService.insertDefaultRecord(RecordEntity(role: 'others', content: text));
      _chatManager.addChatSession('others', text);
    } else {
      if (_inDialogMode) {
        _objectBoxService.insertDialogueRecord(RecordEntity(role: 'user', content: text));
        _chatManager.addChatSession('user', text);
        if (wakeword_constants.wakeWordEndDialog.any((keyword) => text.toLowerCase().contains(keyword))) {
          _inDialogMode = false;
          _vad!.clear();
          if (_isUsingCloudServices) {
            _cloudTts.stop();
          } else {
            _flutterTts.stop();
          }
          AudioPlayer().play(AssetSource('audios/beep.wav'));
        }
      } else {
        _objectBoxService.insertDefaultRecord(RecordEntity(role: 'user', content: text));
        _chatManager.addChatSession('user', text);
      }
    }

    if (_inDialogMode) {
      _currentSubscription?.cancel();
      _currentSubscription = _chatManager.createStreamingRequest(text: text).listen((response) {
        final res = jsonDecode(response);
        final content = res['content'] ?? res['delta'];
        final isFinished = res['isFinished'];

        if (operationId != null) {
          LatencyLogger.recordEnd(operationId, phase: 'llm');
        }

        if (text.trim().isNotEmpty) {
          FlutterForegroundTask.sendDataToMain({
            'currentText': text,
            'isFinished': false,
            'content': res['delta'],
          });
        }
        if (!_isUsingCloudServices) {
          _flutterTts.speak(res['delta']);
        }

        if (_isUsingCloudServices) {
          _cloudTts.speak(res['delta'], operationId: operationId);
        }

        if (isFinished) {
          _objectBoxService.insertDialogueRecord(RecordEntity(role: 'assistant', content: content));
          _chatManager.addChatSession('assistant', content);
        }
      });
    }
  }

  // 声纹注册流程
  void _initVoiceprint({
    required String text,
    required dynamic embedding,
  }) {
    print('[_initVoiceprint] 🗣️ 开始声纹注册流程...');
    print('[_initVoiceprint] 📝 文本: "$text"');
    print('[_initVoiceprint] 🎭 当前步骤: $currentStep/${wakeword_constants.welcomePhrases.length}');

    FlutterForegroundTask.sendDataToMain({
      'isEndpoint': true,
    });

    // 确保有可用的manager和有效的embedding
    if (_manager == null) {
      print('[_initVoiceprint] ❌ 声纹管理器不可用');
      FlutterForegroundTask.sendDataToMain({'status': 'error', 'message': '声纹系统未初始化'});
      return;
    }

    if (embedding is! Float32List || embedding.isEmpty) {
      print('[_initVoiceprint] ❌ 无效的声纹特征');
      FlutterForegroundTask.sendDataToMain({'status': 'error', 'message': '声纹特征无效'});
      return;
    }

    // 检查步骤是否越界
    if (currentStep >= wakeword_constants.welcomePhrases.length) {
      print('[_initVoiceprint] ✅ 声纹注册已完成');
      FlutterForegroundTask.sendDataToMain({'status': 'completed'});
      _isNeedVoiceprintInit = false;
      return;
    }

    // 计算文本相似度
    double similarity = calculateEditDistance(text, wakeword_constants.welcomePhrases[currentStep]);
    print('[_initVoiceprint] 📊 文本相似度: $similarity (要求: >= 0.5)');

    if (similarity >= 0.5) {
      try {
        // 成功匹配，进入下一步
        currentStep++;
        print('[_initVoiceprint] ✅ 步骤 ${currentStep-1} 完成�����进入步骤 $currentStep');

        // 清空旧的用户声纹
        final existingNames = _manager!.allSpeakerNames.toList();
        for (String name in existingNames) {
          if (name == 'user' || name == 'main_user') {
            _manager!.remove(name);
            print('[_initVoiceprint] 🗑️ 移除旧声纹: $name');
          }
        }

        // 添加新的用户声纹
        _manager!.add(name: 'user', embedding: embedding);
        print('[_initVoiceprint] ➕ 添加用户声纹到管理器');

        // 保存到数据库
        _objectBoxService.insertSpeaker(SpeakerEntity(
          name: 'user',
          model: '3dspeaker_eres2net_base_200k', // 更新为新的3dspeaker模型名称
          embedding: embedding.toList()
        ));
        print('[_initVoiceprint] 💾 保存声纹到数据库');

        // 检查是否完成所有步骤
        if (currentStep >= wakeword_constants.welcomePhrases.length) {
          print('[_initVoiceprint] 🎉 声纹注册全部完成！');
          FlutterForegroundTask.sendDataToMain({'status': 'completed'});
          _isNeedVoiceprintInit = false;
        } else {
          FlutterForegroundTask.sendDataToMain({'status': 'success', 'step': currentStep});
        }
      } catch (e) {
        print('[_initVoiceprint] ❌ 声纹注册过程出错: $e');
        FlutterForegroundTask.sendDataToMain({'status': 'error', 'message': '声纹注册失败: $e'});
      }
    } else {
      print('[_initVoiceprint] ❌ 文本不匹配，需要重试');
      FlutterForegroundTask.sendDataToMain({'status': 'failure', 'similarity': similarity});
    }
  }

  // 启动声纹注册模式
  void _startVoiceprint(){
    print('[_startVoiceprint] 🗣️ Starting voiceprint initialization...');

    if (_cloudTts.isPlaying) {
      print('[_startVoiceprint] 🔇 Stopping cloud TTS...');
      _cloudTts.stop();
    }

    print('[_startVoiceprint] 🔄 Resetting states...');
    _inDialogMode = false;

    print('[_startVoiceprint] 🧹 Clearing existing speakers...');
    _manager?.allSpeakerNames.forEach((name) {
      _manager?.remove(name);
    });

    currentStep = 0;
    _isNeedVoiceprintInit = true;

    // print('[_startVoiceprint] ✅ Voiceprint mode enabled: _isNeedVoiceprintInit = $_isNeedVoiceprintInit');
    // print('[_startVoiceprint] 📊 Current state: _onRecording = $_onRecording, _onMicrophone = $_onMicrophone');
  }

  // 停止录音并释放资源
  Future<void> _stopRecord() async {
    if (_recordStream != null) {
      await _record.stop();
      await _record.dispose();
      _recordStream = null;
    }

    _recordSub?.cancel();
    _currentSubscription?.cancel();
    _vad?.free();

    // 释放流式ASR服务资源
    _streamingAsr.dispose();

    _manager?.free();
    _extractor?.free();

    _isInitialized = false;

    FlutterForegroundTask.saveData(key: 'isRecording', value: false);
    FlutterForegroundTask.updateService(
        notificationText: 'Tap to return to the app'
    );
  }

  // 停止麦克风录音
  Future<void> _stopMicrophone() async {
    if (!_onMicrophone) return;
    if (_recordStream != null) {
      await _record.stop();
      await _record.dispose();
      _recordStream = null;
      _onMicrophone = false;
    }
  }

  // 获取说话人embedding（声纹特征）
  Float32List getSpeakerEmbedding(samplesBuffer) {
    // 检查 _extractor 是否可用
    if (_extractor == null) {
      print('[getSpeakerEmbedding] ⚠️ Speaker extractor not available, returning dummy embedding');
      // 返回一个虚拟的embedding，避免null错误
      return Float32List(512); // 创建一个512维的零向量
    }

    try {
      final speakerStream = _extractor!.createStream();
      speakerStream.acceptWaveform(samples: Float32List.fromList(samplesBuffer), sampleRate: 16000);
      final embedding = _extractor!.compute(speakerStream);
      speakerStream.free();

      // 验证embedding质量
      if (embedding.isEmpty) {
        print('[getSpeakerEmbedding] ⚠️ Empty embedding returned');
        return Float32List(512);
      }

      print('[getSpeakerEmbedding] ✅ 成功提取声纹特征，维度: ${embedding.length}');
      print('[getSpeakerEmbedding] 📊 Embedding preview: ${embedding.length > 10 ? embedding.sublist(0, 10) : embedding}');

      return embedding;
    } catch (e) {
      print('[getSpeakerEmbedding] ❌ 声纹提取失败: $e');
      return Float32List(512);
    }
  }

  // 改进的说话人识别逻辑 - 专注于区分"我"和"别人"
  String _identifySpeaker(Float32List embedding) {
    print('[_identifySpeaker] 🔍 开始说话人识别...');

    // 检查是否有��注册的用户声纹
    final userSpeakers = _objectBoxService.getUserSpeaker();
    if (userSpeakers == null || userSpeakers.isEmpty) {
      print('[_identifySpeaker] ⚠️ 没有注册的用户声纹，返回 others');
      return 'others';
    }

    // 获取主用户的声纹（假设第一个是主用户）
    var mainUser = userSpeakers.firstWhere(
            (speaker) => speaker.name == 'user' || speaker.name == 'main_user',
        orElse: () => userSpeakers.first
    );

    if (mainUser.embedding == null || mainUser.embedding!.isEmpty) {
      print('[_identifySpeaker] ⚠️ 主用户声纹为空，返回 others');
      return 'others';
    }

    // 计算与主用户的相似度
    final userEmbedding = Float32List.fromList(mainUser.embedding!);
    final similarity = _improvedCosineSimilarity(embedding, userEmbedding);

    print('[_identifySpeaker] 📊 与主用户相��度: $similarity');

    // 动态阈值调整 - 根据历史数据调整
    double threshold = _calculateDynamicThreshold();
    print('[_identifySpeaker] 🎯 使用阈值: $threshold');

    if (similarity >= threshold) {
      print('[_identifySpeaker] ✅ 识别为用户本人');
      _updateSpeakerHistory(true, similarity);
      return 'user';
    } else {
      print('[_identifySpeaker] ❌ 识别为其他人');
      _updateSpeakerHistory(false, similarity);
      return 'others';
    }
  }

  // 改进的余弦相似度计算，增加数值稳定性
  double _improvedCosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) {
      print('[_improvedCosineSimilarity] ⚠️ 向量长度不匹配: ${a.length} vs ${b.length}');
      return -1.0;
    }

    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    // 添加小的epsilon避免除零
    const double epsilon = 1e-10;
    normA = math.sqrt(normA + epsilon);
    normB = math.sqrt(normB + epsilon);

    if (normA < epsilon || normB < epsilon) {
      print('[_improvedCosineSimilarity] ⚠️ 向量范数过小');
      return -1.0;
    }

    double similarity = dot / (normA * normB);

    // 确保相似度在合理范围内
    return similarity.clamp(-1.0, 1.0);
  }

  // 动态阈值计算 - 根据历史识别数据调整
  double _calculateDynamicThreshold() {
    // 获取历史识别��据
    final recentRecords = _objectBoxService.getRecentRecords(limit: 50);
    if (recentRecords == null || recentRecords.isEmpty) {
      return 0.65; // 默认阈值
    }

    // 统计用户和其他人的��录比例
    int userCount = recentRecords.where((r) => r.role == 'user').length;
    int othersCount = recentRecords.where((r) => r.role == 'others').length;

    double userRatio = userCount / (userCount + othersCount);

    // 根据使用模式调整阈值
    if (userRatio > 0.8) {
      // 主要是用户自己使用，提高阈值避免误识别
      return 0.75;
    } else if (userRatio < 0.3) {
      // 多人环境，降低阈值确保能识别到用户
      return 0.55;
    } else {
      // 平衡环境，使用中等阈值
      return 0.65;
    }
  }

  void _updateSpeakerHistory(bool isUser, double similarity) {
    if (isUser) {
      _userSimilarityHistory.add(similarity);
      if (_userSimilarityHistory.length > 20) {
        _userSimilarityHistory.removeAt(0);
      }
    } else {
      _othersSimilarityHistory.add(similarity);
      if (_othersSimilarityHistory.length > 20) {
        _othersSimilarityHistory.removeAt(0);
      }
    }
  }

  // 声纹质量评估
  bool _isEmbeddingQualityGood(Float32List embedding) {
    if (embedding.isEmpty) return false;

    // 检查是否全为零或接近零
    double magnitude = 0.0;
    for (double value in embedding) {
      magnitude += value * value;
    }
    magnitude = math.sqrt(magnitude);

    // 如果向量幅度太小，认为质量不好
    if (magnitude < 0.01) {
      print('[_isEmbeddingQualityGood] ⚠️ 声纹向量幅度过小: $magnitude');
      return false;
    }

    // 检查方差，避免向量过于平坦
    double mean = embedding.reduce((a, b) => a + b) / embedding.length;
    double variance = 0.0;
    for (double value in embedding) {
      variance += (value - mean) * (value - mean);
    }
    variance /= embedding.length;

    if (variance < 0.001) {
      print('[_isEmbeddingQualityGood] ⚠️ 声纹向量方差过小: $variance');
      return false;
    }

    return true;
  }

  void _checkAndSummarizeDialogue() {
    final now = DateTime.now().millisecondsSinceEpoch;
    print('[自动总结] 检查条件：当前累计字数=$_currentDialogueCharCount，最后说话时间=$_lastSpeechTimestamp，当前时间=$now');
    // 1. 超过最大字数强制分段
    if (_currentDialogueCharCount >= maxCharLimit) {
      print('[自动总结] 超过最大字数，强制分段总结...');
      DialogueSummary.start(
        startTime: _currentDialogueStartTime,
        onSummaryCallback: _handleSummaryGenerated,
      );
      _currentDialogueCharCount = 0;
      _lastSpeechTimestamp = 0;
      _currentDialogueStartTime = null;
      return;
    }
    // 2. 正常对话分段逻辑
    if (_currentDialogueCharCount >= minCharLimit &&
        _lastSpeechTimestamp > 0 &&
        now - _lastSpeechTimestamp > 0.25 * 60 * 1000) {
      print('[自动总结] 满足条件，开始自动整理对话内容...');
      DialogueSummary.start(
        startTime: _currentDialogueStartTime,
        onSummaryCallback: _handleSummaryGenerated,
      );
      _currentDialogueCharCount = 0;
      _lastSpeechTimestamp = 0;
      _currentDialogueStartTime = null;
    } else {
      print('[自动总结] 未满足自动总结条件');
    }
  }

  // 🔥 新增：处理摘要生成完成的回调
  void _handleSummaryGenerated(List<SummaryEntity> summaries) {
    print('[ASR] 📋 收到摘要生成完成通知，摘要数量: ${summaries.length}');

    if (summaries.isEmpty) return;

    try {
      // 构建摘要显示内容
      String summaryContent = _formatSummaryForDisplay(summaries);

      // 通过FlutterForegroundTask发送摘要消息到主界面
      FlutterForegroundTask.sendDataToMain({
        'text': summaryContent,
        'isEndpoint': true,
        'speaker': 'system',
        'isSummary': true, // 标识这是摘要消息
      });

      print('[ASR] ✅ 摘要消息已发送到主界面');

    } catch (e) {
      print('[ASR] ❌ 处理摘要显示时出错: $e');
    }
  }

  // 🔥 新增：格式化摘要内容用于显示
  String _formatSummaryForDisplay(List<SummaryEntity> summaries) {
    StringBuffer buffer = StringBuffer();
    buffer.writeln('📋 **对话总结**');
    buffer.writeln('');

    for (int i = 0; i < summaries.length; i++) {
      SummaryEntity summary = summaries[i];

      // 格式化时间
      String startTimeStr = DateFormat('HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(summary.startTime)
      );
      String endTimeStr = DateFormat('HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(summary.endTime)
      );

      buffer.writeln('**${i + 1}. ${summary.subject}** (${startTimeStr}-${endTimeStr})');
      buffer.writeln(summary.content);

      if (i < summaries.length - 1) {
        buffer.writeln('');
      }
    }

    return buffer.toString();
  }
}

// // 新版本
// Future<sherpa_onnx.VoiceActivityDetector> initVad() async =>
//     sherpa_onnx.VoiceActivityDetector(
//       config: sherpa_onnx.VadModelConfig(
//         sileroVad: sherpa_onnx.SileroVadModelConfig(
//           model: await copyAssetFile('assets/silero_vad.onnx'),
//           threshold: 0.5,
//           minSilenceDuration: 0.25,
//           minSpeechDuration: 0.5,
//           maxSpeechDuration: 5.0,
//           windowSize: 512,
//         ),
//         sampleRate: 16000,
//         numThreads: 1,
//         provider: "cpu",
//         debug: true,
//       ),
//       bufferSizeInSeconds: 2.0,
//     );
// 旧版本
Future<sherpa_onnx.VoiceActivityDetector> initVad() async =>
    sherpa_onnx.VoiceActivityDetector(
      config: sherpa_onnx.VadModelConfig(
        sileroVad: sherpa_onnx.SileroVadModelConfig(
          model: await copyAssetFile('assets/silero_vad.onnx'),
          minSilenceDuration: 0.25,
          minSpeechDuration: 0.5,
          maxSpeechDuration: 5.0,
        ),
        numThreads: 1,
        debug: true,
      ),
      bufferSizeInSeconds: 2.0,
    );

Future<List<List<double>>> loadMatrixFromJson(String assetPath, int rows, int cols) async {
  // 从json加载矩阵（List<List<double>>）
  String jsonString = await rootBundle.loadString(assetPath);
  List<dynamic> jsonData = jsonDecode(jsonString);
  print('Loaded JSON data type: ${jsonData.runtimeType}');
  print('Number of elements in jsonData: ${jsonData.length}');
  // Check if jsonData is empty
  if (jsonData.isEmpty) {
    print('jsonData is empty!');
    return [];
  }
  // Check if the length of jsonData matches the expected size
  if (jsonData.length != rows * cols) {
    print('Warning: jsonData length (${jsonData.length}) does not match expected size ($rows * $cols).');
    return [];
  }
  List<List<double>> matrix = List.generate(rows, (i) {
    return List.generate(cols, (j) {
      return jsonData[i * cols + j].toDouble();
    });
  });
  return matrix;
}

Future<Matrix> loadRealMatrixFromJson(String assetPath, int rows, int cols) async {
  // 从json加载矩阵（Matrix对象）
  String jsonString = await rootBundle.loadString(assetPath);
  List<dynamic> jsonData = jsonDecode(jsonString);
  debugPrint('Loaded JSON data type: ${jsonData.runtimeType}');
  debugPrint('Number of elements in jsonData: ${jsonData.length}');

  Matrix matrix = Matrix.fill(rows, cols, 0.0);
  if (jsonData.isEmpty) { // Check if jsonData is empty
    debugPrint('jsonData is empty!');
  } else if (jsonData.length != rows * cols) { // Check if the length of jsonData matches the expected size
    debugPrint('Warning: jsonData length (${jsonData.length}) does not match expected size ($rows * $cols).');
  } else {
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        matrix[i][j] = jsonData[i * cols + j].toDouble();
      }
    }
  }

  return matrix;
}

Future<Float32List> _addSilencePadding(Float32List samples) async {
  // 为音频添加静音padding
  int totalLength = silence.length * 2 + samples.length;

  Float32List paddedSamples = Float32List(totalLength);

  paddedSamples.setAll(silence.length, samples);

  return paddedSamples;
}

// 在文件末尾添加余弦相似度函数

double _cosineSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length) return -1.0;
  double dot = 0.0;
  double normA = 0.0;
  double normB = 0.0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return -1.0;
  return dot / (math.sqrt(normA) * math.sqrt(normB)); // ← 使用math.sqrt
}











































































