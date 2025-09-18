import 'package:flutter/material.dart';
import 'package:app/services/embedding_service.dart';
import 'dart:io';

class OnnxDebugPage extends StatefulWidget {
  const OnnxDebugPage({super.key});

  @override
  State<OnnxDebugPage> createState() => _OnnxDebugPageState();
}

class _OnnxDebugPageState extends State<OnnxDebugPage> {
  final List<String> _logs = [];
  final EmbeddingService _embeddingService = EmbeddingService();
  bool _isInitializing = false;
  bool _modelLoaded = false;

  @override
  void initState() {
    super.initState();
    _addLog('🔄 ONNX调试页面启动');
    _addLog('📱 当前平台: ${Platform.operatingSystem}');
    _addLog('🏗️ 架构: ${Platform.version}');
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('${DateTime.now().toString().substring(11, 19)} $message');
    });
    print('[OnnxDebug] $message');
  }

  Future<void> _runDiagnostic() async {
    if (_isInitializing) return;

    setState(() {
      _isInitializing = true;
      _logs.clear();
    });

    _addLog('🔍 开始全面诊断...');

    try {
      // 检查ONNX模型文件
      _addLog('📂 检查模型文件路径...');
      final modelFilePath = _embeddingService.getModelFilePath();
      _addLog('   - 模型文件路径: $modelFilePath');

      // 检查平台兼容性
      _addLog('🛠️ 检查平台兼容性...');
      final isSupportedPlatform = _embeddingService.checkPlatformCompatibility();
      if (isSupportedPlatform) {
        _addLog('✅ ��台兼容性通过');
      } else {
        _addLog('❌ 不支持的操作系统或架构');
      }

      // 检查依赖库
      _addLog('📦 检查依赖库...');
      final dependencies = await _embeddingService.checkDependencies();
      for (final dep in dependencies) {
        _addLog('   - $dep');
      }

      // 检查网络连接（如果需要）
      _addLog('🌐 检查网络连接...');
      final hasInternet = await _embeddingService.checkInternetConnection();
      if (hasInternet) {
        _addLog('✅ 网络连接正常');
      } else {
        _addLog('❌ 网络连接异常，请检查您的网络设置');
      }

      // 尝试初始化模型
      _addLog('⚙️ 尝试初始化ONNX模型...');
      final initResult = await _embeddingService.initialize();
      if (initResult) {
        _addLog('✅ 模型初始化成功');
        _modelLoaded = true;
        await _testModelInference();
      } else {
        _addLog('❌ 模型初始化失败');
        _modelLoaded = false;
        await _testFallbackMethod();
      }

    } catch (e, stackTrace) {
      _addLog('💥 诊断过程中发生异常: $e');
      _addLog('🔍 堆栈跟踪: ${stackTrace.toString().substring(0, 200)}...');
    }

    setState(() {
      _isInitializing = false;
    });
  }

  Future<void> _testModelInitialization() async {
    if (_isInitializing) return;

    setState(() {
      _isInitializing = true;
      _logs.clear();
    });

    _addLog('🚀 开始ONNX模型初始化测试...');

    try {
      // 清理之前的状态
      _embeddingService.dispose();
      _addLog('🧹 已清理之前的模型状态');

      // 尝试初始化模型
      _addLog('⚙️ 正在初始化模型...');
      final result = await _embeddingService.initialize();

      if (result) {
        _addLog('✅ 模型初始化成功！');
        _modelLoaded = true;

        // 测试模型推理
        await _testModelInference();
      } else {
        _addLog('❌ 模型初始化失败，将使用备用方案');
        _modelLoaded = false;

        // 测试备用方案
        await _testFallbackMethod();
      }

      // 获取缓存统计
      final stats = _embeddingService.getCacheStats();
      _addLog('📊 缓存统计: $stats');

    } catch (e, stackTrace) {
      _addLog('💥 初始化过程中发生异常: $e');
      _addLog('🔍 堆栈跟踪: ${stackTrace.toString().substring(0, 200)}...');
    }

    setState(() {
      _isInitializing = false;
    });
  }

  Future<void> _testModelInference() async {
    _addLog('🧪 测试模型推理...');

    try {
      const testTexts = [
        '简单测试文本',
        'Hello world test',
        '这是一个包含中文的测试文本，用于验证模型的中文处理能力',
        'This is an English test text with multiple words to verify tokenization',
      ];

      for (int i = 0; i < testTexts.length; i++) {
        final text = testTexts[i];
        // 修复：安全地截取字符串，避免索引越界
        final displayText = text.length > 20 ? '${text.substring(0, 20)}...' : text;
        _addLog('📝 测试文本 ${i + 1}: $displayText');

        final stopwatch = Stopwatch()..start();
        final embedding = await _embeddingService.generateTextEmbedding(text);
        stopwatch.stop();

        if (embedding != null) {
          _addLog('✅ 生成成功: ${embedding.length}维, 耗时: ${stopwatch.elapsedMilliseconds}ms');
          _addLog('📊 向量范围: [${embedding.reduce((a, b) => a < b ? a : b).toStringAsFixed(4)}, ${embedding.reduce((a, b) => a > b ? a : b).toStringAsFixed(4)}]');
        } else {
          _addLog('❌ 生成失败');
        }

        // 小延迟避免过快
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      _addLog('💥 推理测试失败: $e');
    }
  }

  Future<void> _testFallbackMethod() async {
    _addLog('🔄 测试备用方案的文本处理能力...');

    try {
      const testText = '测试备用方案的文本处理能力';

      final stopwatch = Stopwatch()..start();
      final embedding = await _embeddingService.generateTextEmbedding(testText);
      stopwatch.stop();

      if (embedding != null) {
        _addLog('✅ 备用方案工作正常: ${embedding.length}维, 耗时: ${stopwatch.elapsedMilliseconds}ms');

        // 测试相似度计算
        final embedding2 = await _embeddingService.generateTextEmbedding(testText);
        if (embedding2 != null) {
          final similarity = _embeddingService.calculateCosineSimilarity(embedding, embedding2);
          _addLog('🔍 相同文本相似度: ${similarity.toStringAsFixed(4)} (应该接近1.0)');
        }
      } else {
        _addLog('❌ 备用方案也失败了');
      }
    } catch (e) {
      _addLog('💥 备用方案测试失败: $e');
    }
  }

  Future<void> _testPerformance() async {
    _addLog('⚡ 开始性能测试...');

    try {
      final texts = List.generate(10, (i) => '性能测试文本 $i: 这是第${i}个测试用例');

      // 批量测试
      final stopwatch = Stopwatch()..start();
      int successCount = 0;

      for (final text in texts) {
        final embedding = await _embeddingService.generateTextEmbedding(text);
        if (embedding != null) successCount++;
      }

      stopwatch.stop();

      _addLog('📈 性能测试结果:');
      _addLog('   - 总数: ${texts.length}');
      _addLog('   - 成功: $successCount');
      _addLog('   - 失败: ${texts.length - successCount}');
      _addLog('   - 总耗时: ${stopwatch.elapsedMilliseconds}ms');
      _addLog('   - 平均耗时: ${stopwatch.elapsedMilliseconds / texts.length}ms/个');

      // 缓存性能测试
      _addLog('🗄️ 测试缓存性能...');
      const cacheTestText = '缓存性能测试文本';

      final stopwatch1 = Stopwatch()..start();
      await _embeddingService.generateTextEmbedding(cacheTestText);
      stopwatch1.stop();

      final stopwatch2 = Stopwatch()..start();
      await _embeddingService.generateTextEmbedding(cacheTestText);
      stopwatch2.stop();

      _addLog('   - 首次生成: ${stopwatch1.elapsedMicroseconds}μs');
      _addLog('   - 缓存命中: ${stopwatch2.elapsedMicroseconds}μs');
      _addLog('   - 性能提升: ${(stopwatch1.elapsedMicroseconds / stopwatch2.elapsedMicroseconds).toStringAsFixed(1)}x');

    } catch (e) {
      _addLog('💥 性能测试失败: $e');
    }
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  void _copyLogs() {
    // 这里可以实现复制日志到剪贴板的功能
    final logsText = _logs.join('\n');
    _addLog('📋 日志已准备复制 (${logsText.length} 字符)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ONNX模型调试'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _clearLogs,
            tooltip: '清空日志',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyLogs,
            tooltip: '复制日志',
          ),
        ],
      ),
      body: Column(
        children: [
          // 状态信息
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _modelLoaded ? Colors.green.shade100 : Colors.orange.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '模型状态: ${_modelLoaded ? "✅ 已加载" : "❌ 未加载"}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('平台: ${Platform.operatingSystem}'),
                Text('日志条数: ${_logs.length}'),
              ],
            ),
          ),

          // 控制按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isInitializing ? null : _runDiagnostic,
                        icon: _isInitializing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search),
                        label: Text(_isInitializing ? '诊断中...' : '全面诊断'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isInitializing ? null : _testModelInitialization,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('测试模型'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isInitializing ? null : _testPerformance,
                        icon: const Icon(Icons.speed),
                        label: const Text('性能测试'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isInitializing ? null : _testFallbackMethod,
                        icon: const Icon(Icons.backup),
                        label: const Text('备用方案'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 日志显示
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  Color? textColor;

                  if (log.contains('✅')) {
                    textColor = Colors.green;
                  } else if (log.contains('❌') || log.contains('💥')) {
                    textColor = Colors.red;
                  } else if (log.contains('⚠️')) {
                    textColor = Colors.orange;
                  } else if (log.contains('🔍') || log.contains('📊')) {
                    textColor = Colors.blue;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      log,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: textColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _embeddingService.dispose();
    super.dispose();
  }
}
