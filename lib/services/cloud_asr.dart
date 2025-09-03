import 'dart:typed_data';

import 'package:app/models/llm_config.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wav/wav.dart';


class CloudAsr {
  String _openaiApiKey = ''; // 改为可空字符串，提供默认值
  static const String defaultBaseUrl = 'https://one-api.bud.inc/v1/audio/transcriptions';

  bool get isAvailable => _openaiApiKey.isNotEmpty;

  Future<void> init() async {
    try {
      print('[CloudAsr] 🔄 开始初始化 CloudAsr...');

      LlmConfigEntity? config = ObjectBoxService().getConfigsByProvider("OpenAI");
      if (config != null && config.apiKey != null && config.baseUrl != null) {
        _openaiApiKey = config.apiKey!;
        print('[CloudAsr] ✅ 从数据库获取到 OpenAI API Key');
      } else {
        // 添加null检查和默认值处理
        final tokenData = await FlutterForegroundTask.getData(key: 'llmToken');
        _openaiApiKey = tokenData ?? ''; // 如果为null，使用空字符串

        if (_openaiApiKey.isEmpty) {
          print('[CloudAsr] ⚠️ 未找到 OpenAI API Key，CloudAsr 将不可用');
        } else {
          print('[CloudAsr] ✅ 从 FlutterForegroundTask 获取到 API Key');
        }
      }

      print('[CloudAsr] ✅ CloudAsr 初始化完成，isAvailable: $isAvailable');
    } catch (e) {
      print('[CloudAsr] ❌ CloudAsr 初始化失败: $e');
      _openaiApiKey = ''; // 出错时设置为空字符串
    }
  }

  Future<File> _writeAudioToFile(Float32List audioData) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${tempDir.path}/recorded_audio_$timestamp.wav');

    final wav = Wav([Float64List.fromList(audioData)], 16000);
    await file.writeAsBytes(wav.write());
    return file;
  }

  Future<String> _sendToWhisperApi(File audioFile) async {
    // final uri = Uri.parse(defaultBaseUrl);
    final uri = Uri.parse(defaultBaseUrl);
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_openaiApiKey'
      ..fields['model'] = 'whisper-1'
      ..fields['language'] = 'en'
      ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));
    
    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.bytesToString();
      final result = json.decode(responseData);
      await audioFile.delete();
      return result['text'];
    } else {
      await audioFile.delete();
      throw Exception('Failed to transcribe audio: ${response.reasonPhrase} ${await response.stream.bytesToString()}');
    }
  }

  Future<String> recognize(Float32List audioData) async {
    final audioFile = await _writeAudioToFile(audioData);
    try {
      final transcription = await _sendToWhisperApi(audioFile);
      dev.log("Whisper API result: $transcription");
      return transcription;
    } catch (error) {
      dev.log("Recognition error: $error");
      throw error;
    }
  }
}
