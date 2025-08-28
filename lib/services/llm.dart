import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../constants/prompt_constants.dart';

class LLM {
  String modelName;
  late String apiKey;
  late String baseUrl;
  late String systemPrompt;

  // 使用你的代理服务器
  static final String defaultBaseUrl = 'https://xiaomi.dns.navy/v1/chat/completions';

  // 静态缓存API key，避免后台任务中访问dotenv的问题
  static String? _cachedApiKey;

  // 从环境变量获取API key，如果没有则使用本地备用key
  static String get localApiKey {
    // 如果已经缓存，直接返回
    if (_cachedApiKey != null) {
      return _cachedApiKey!;
    }

    try {
      // 检查dotenv是否已初始化
      if (!dotenv.isInitialized) {
        print('[LLM] dotenv未初始化，尝试重新加载');
        // 在后台任务中，可能需要重新加载dotenv
        return '';
      }
      final apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
      // 缓存API key以供后续使用
      if (apiKey.isNotEmpty) {
        _cachedApiKey = apiKey;
        print('[LLM] 成功从dotenv获取并缓存API key');
      }
      return apiKey;
    } catch (e) {
      print('[LLM] 获取API key时发生错误: $e');
      return '';
    }
  }

  // 手动设置API key（用于初始化时缓存）
  static void cacheApiKey(String apiKey) {
    _cachedApiKey = apiKey;
    print('[LLM] API key已缓存');
  }

  LLM._(this.modelName, this.apiKey, this.baseUrl, this.systemPrompt);

  static Future<LLM> create(String modelName, {String? systemPrompt}) async {
    final prompt = systemPrompt ?? systemPromptOfChat;
    final apiKey = localApiKey;

    // 如果API key为空，尝试重新加载dotenv
    if (apiKey.isEmpty) {
      print('[LLM] API key为空，尝试重新加载dotenv...');
      try {
        await dotenv.load(fileName: ".env");
        final retryApiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
        if (retryApiKey.isNotEmpty) {
          _cachedApiKey = retryApiKey;
          print('[LLM] 重新加载dotenv成功，获取到API key');
          return LLM._(modelName, retryApiKey, defaultBaseUrl, prompt);
        }
      } catch (e) {
        print('[LLM] 重新加载dotenv失败: $e');
      }

      print('[LLM] API key为空，无法创建LLM实例');
      throw Exception('API key not available. Please check .env configuration.');
    }

    print('[LLM] 成功获取API key，创建LLM实例');
    return LLM._(modelName, apiKey, defaultBaseUrl, prompt);
  }

  // Sends a request to the LLM with user input
  Future<String> createRequest({required String content}) async {
    final url = Uri.parse(baseUrl);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    final body = jsonEncode({
      'model': modelName,
      'messages': [{"role": "system", "content": systemPrompt}, {"role": "user", "content": content}],
    });

    final response = await http.post(url, headers: headers, body: body);
    return _handleResponse(response);
  }

  String _handleResponse(http.Response response) {
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes))['choices'][0]['message'];
      try {
        return data['content'];
      } catch (e) {
        throw Exception('Json decode failed.');
      }
    } else {
      throw Exception('Failed to fetch response from LLM');
    }
  }

  Stream<String> createStreamingRequest({String? content, List<Map<String, String>>? messages, Object? jsonSchema}) {
    final url = Uri.parse(baseUrl);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    if (messages != null && messages.isNotEmpty) {
      if (messages[0]["role"] != "system") {
        messages.insert(0, {"role": "system", "content": systemPrompt});
      }
    } else {
      messages = [{"role": "system", "content": systemPrompt}, {"role": "user", "content": content!}];
    }

    final Map<String, Object> responseFormat = {'type': 'json_object'};
    if (jsonSchema != null) {
      responseFormat['json_schema'] = jsonSchema;
    }

    final body = jsonEncode({
      'model': modelName,
      'messages': messages,
      'stream': true,
      'response_format': responseFormat
    });

    return _handleStreamingResponse(url, headers, body);
  }

  Stream<String> _handleStreamingResponse(Uri url, Map<String, String> headers, String body) async* {
    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = body;

    final response = await request.send();

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch streaming response from LLM');
    }

    final responseStream = response.stream.transform(utf8.decoder);
    StringBuffer buffer = StringBuffer();

    await for (var chunk in responseStream) {
      try {
        List<String> jsonParts = chunk.toString().split('\n');

        for (String part in jsonParts) {
          if (part.length > 6 && part != "data:[DONE]") {
            try {
              var content = jsonDecode(part.substring(5))["choices"][0]["delta"]["content"];
              if (content != null) {
                buffer.write(content);
                yield buffer.toString();
              }
            } catch (e) {
              continue;
            }
          }
        }
      } catch (e) {
        print(e.toString());
      }
    }
  }

  void setSystemPrompt({required String systemPrompt}) {
    this.systemPrompt = systemPrompt;
  }
}
