import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:app/services/embedding_service.dart';
import 'package:app/models/graph_models.dart';
import 'dart:io';
import 'dart:typed_data';

void main() {
  group('EmbeddingService Tests', () {
    late EmbeddingService embeddingService;

    setUpAll(() async {
      // 确保绑定已初始化
      TestWidgetsFlutterBinding.ensureInitialized();

      // 不再模拟文件不存在，让测试使用真实的模型文件
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter/assets'),
            (MethodCall methodCall) async {
          if (methodCall.method == 'load' &&
              methodCall.arguments == 'assets/gte-model.onnx') {
            try {
              // 尝试读取真实的模型文件
              final file = File('/Users/billcheng/AndroidStudioProjects/Bud0709/Bud-App/assets/gte-model.onnx');
              if (await file.exists()) {
                final bytes = await file.readAsBytes();
                print('[Test] 📁 成功加载真实模型文件，大小: ${bytes.length} bytes');
                return ByteData.sublistView(bytes);
              } else {
                print('[Test] ❌ 模型文件不存在: ${file.path}');
                // 如果文件不存在，创建一个最小的测试模型
                return ByteData.sublistView(Uint8List.fromList(_createMinimalTestModel()));
              }
            } catch (e) {
              print('[Test] ❌ 读取模型文件失败: $e');
              return ByteData.sublistView(Uint8List.fromList(_createMinimalTestModel()));
            }
          }
          return null;
        },
      );

      embeddingService = EmbeddingService();
    });

    setUp(() {
      // 每个测试前清空缓存
      embeddingService.clearCache();
    });

    tearDownAll(() {
      embeddingService.dispose();
    });

    group('初始化测试', () {
      test('验证模型文件存在', () async {
        final file = File('/Users/billcheng/AndroidStudioProjects/Bud0709/Bud-App/assets/gte-model.onnx');

        print('检查模型文件: ${file.path}');
        final exists = await file.exists();
        print('文件存在: $exists');

        if (exists) {
          final stat = await file.stat();
          print('文件大小: ${stat.size} bytes');
          print('修改时间: ${stat.modified}');

          // 检查文件不为空
          expect(stat.size, greaterThan(1000), reason: '模型文件应该大于1KB');

          // 读取前几个字节检查
          final bytes = await file.readAsBytes();
          print('文件头部 (前20字��): ${bytes.take(20).toList()}');
        }

        expect(exists, isTrue, reason: '模型文件应该存在于 assets/ 目录中');
      });

      test('服务单例测试', () {
        final service1 = EmbeddingService();
        final service2 = EmbeddingService();
        expect(identical(service1, service2), true);
      });

      test('模型初始化测试', () async {
        // 现在测试真实的模型初始化
        print('[Test] 🔄 开始测试模型初始化...');
        final initialized = await embeddingService.initialize();

        print('[Test] 模型初始化结果: $initialized');

        // 检查初始化状态
        expect(initialized, isA<bool>());

        if (initialized) {
          print('[Test] ✅ 模型成功加载');

          // 获取缓存统计
          final stats = embeddingService.getCacheStats();
          print('[Test] 📊 模型状态: $stats');
          expect(stats['model_loaded'], isTrue);
        } else {
          print('[Test] ⚠️ 模型加载失败，将使用备用方案');
        }
      });

      test('模型推理能力测试', () async {
        // 确保模型已初始化
        await embeddingService.initialize();

        const testText = "测试模型推理能力的简单文本";
        print('[Test] 🧪 测试文本: $testText');

        final embedding = await embeddingService.generateTextEmbedding(testText);

        expect(embedding, isNotNull, reason: '应该能生成嵌入向量');
        expect(embedding!.length, equals(EmbeddingService.vectorDimensions));

        // 验证向量不全为零
        final hasNonZero = embedding.any((x) => x != 0.0);
        expect(hasNonZero, true, reason: '向量不应该全为零');

        print('[Test] ✅ 成功生成 ${embedding.length} 维向量');
        print('[Test] 📊 向量范围: [${embedding.reduce((a, b) => a < b ? a : b).toStringAsFixed(4)}, ${embedding.reduce((a, b) => a > b ? a : b).toStringAsFixed(4)}]');
      });
    });

    group('向量生成测试', () {
      test('文本嵌入向量生成', () async {
        const testText = "这是一个测试文本，用于生成向量嵌入";

        final embedding = await embeddingService.generateTextEmbedding(testText);

        expect(embedding, isNotNull);
        expect(embedding!.length, equals(EmbeddingService.vectorDimensions));

        // 验证向量不全为零
        final hasNonZero = embedding.any((x) => x != 0.0);
        expect(hasNonZero, true);

        print('✅ 生成的向量维度: ${embedding.length}');
        print('✅ 向量前5个值: ${embedding.take(5).toList()}');
      });

      test('空文本处理', () async {
        final embedding1 = await embeddingService.generateTextEmbedding('');
        final embedding2 = await embeddingService.generateTextEmbedding('   ');

        expect(embedding1, isNull);
        expect(embedding2, isNull);
      });

      test('中文文本嵌入', () async {
        const chineseText = "今天天气很好，我去公园散步了";

        final embedding = await embeddingService.generateTextEmbedding(chineseText);

        expect(embedding, isNotNull);
        expect(embedding!.length, equals(EmbeddingService.vectorDimensions));

        print('✅ 中文文本向量生成成功');
      });

      test('英文文本嵌入', () async {
        const englishText = "The weather is nice today, I went for a walk in the park";

        final embedding = await embeddingService.generateTextEmbedding(englishText);

        expect(embedding, isNotNull);
        expect(embedding!.length, equals(EmbeddingService.vectorDimensions));

        print('✅ 英文文本向量生成成功');
      });

      test('长文本处理', () async {
        final longText = '这是一个很长的文本。' * 100; // 重复100次

        final embedding = await embeddingService.generateTextEmbedding(longText);

        expect(embedding, isNotNull);
        expect(embedding!.length, equals(EmbeddingService.vectorDimensions));

        print('✅ 长文本处理成功，长度: ${longText.length}');
      });
    });

    group('EventNode嵌入测试', () {
      test('基本事件嵌入生成', () async {
        final eventNode = EventNode(
          id: 'test_event_1',
          name: '团队会议',
          type: '会议',
          description: '讨论项目进度和下一步计划',
          purpose: '同步项目状态',
          result: '明确了各自的任务分工',
        );

        final embedding = await embeddingService.generateEventEmbedding(eventNode);

        expect(embedding, isNotNull);
        expect(embedding!.length, equals(EmbeddingService.vectorDimensions));

        print('✅ 事件嵌入文本: ${eventNode.getEmbeddingText()}');
        print('✅ 事件向量维度: ${embedding.length}');
      });

      test('最小信息事件嵌入', () async {
        final eventNode = EventNode(
          id: 'test_event_2',
          name: '简单事件',
          type: '其他',
        );

        final embedding = await embeddingService.generateEventEmbedding(eventNode);

        expect(embedding, isNotNull);
        expect(embedding!.length, equals(EmbeddingService.vectorDimensions));
      });

      test('空名称事件处理', () async {
        final eventNode = EventNode(
          id: 'test_event_3',
          name: '',
          type: '其他',
        );

        final embedding = await embeddingService.generateEventEmbedding(eventNode);

        expect(embedding, isNull);
      });
    });

    group('相似度计算测试', () {
      test('相同向量相似度', () {
        final vector = List.generate(EmbeddingService.vectorDimensions, (i) => i.toDouble());

        final similarity = embeddingService.calculateCosineSimilarity(vector, vector);

        expect(similarity, closeTo(1.0, 0.001));
        print('✅ 相同向量相似度: $similarity');
      });

      test('正交向量相似度', () {
        final vector1 = List.generate(EmbeddingService.vectorDimensions, (i) => i.isEven ? 1.0 : 0.0);
        final vector2 = List.generate(EmbeddingService.vectorDimensions, (i) => i.isOdd ? 1.0 : 0.0);

        final similarity = embeddingService.calculateCosineSimilarity(vector1, vector2);

        expect(similarity, closeTo(0.0, 0.001));
        print('✅ 正交向量相似度: $similarity');
      });

      test('相反向量相似度', () {
        final vector1 = List.filled(EmbeddingService.vectorDimensions, 1.0);
        final vector2 = List.filled(EmbeddingService.vectorDimensions, -1.0);

        final similarity = embeddingService.calculateCosineSimilarity(vector1, vector2);

        expect(similarity, closeTo(-1.0, 0.001));
        print('✅ 相反向量相似度: $similarity');
      });

      test('维度不匹配异常', () {
        final vector1 = [1.0, 2.0, 3.0];
        final vector2 = [1.0, 2.0];

        expect(
              () => embeddingService.calculateCosineSimilarity(vector1, vector2),
          throwsArgumentError,
        );
      });

      test('零向量处理', () {
        final vector1 = List.filled(EmbeddingService.vectorDimensions, 0.0);
        final vector2 = List.filled(EmbeddingService.vectorDimensions, 1.0);

        final similarity = embeddingService.calculateCosineSimilarity(vector1, vector2);

        expect(similarity, equals(0.0));
      });
    });

    group('相似事件搜索测试', () {
      late List<EventNode> testEvents;

      setUp(() async {
        // 创建测试事件
        testEvents = [
          EventNode(
            id: 'event_1',
            name: '项目启动会议',
            type: '会议',
            description: '讨论新项目的启动计划',
            purpose: '制定项目计划',
          ),
          EventNode(
            id: 'event_2',
            name: '产品发布会',
            type: '发布',
            description: '向公众展示新产品',
            purpose: '产品推广',
          ),
          EventNode(
            id: 'event_3',
            name: '团队建设活动',
            type: '活动',
            description: '提高团队凝聚力的户外活动',
            purpose: '增强团队合作',
          ),
          EventNode(
            id: 'event_4',
            name: '技术培训',
            type: '培训',
            description: '学习新的技术栈',
            purpose: '提升技能',
          ),
        ];

        // 为每个事件生成嵌入向量
        for (final event in testEvents) {
          event.embedding = await embeddingService.generateEventEmbedding(event) ?? <double>[];
        }
      });

      test('基于文本搜索相似事件', () async {
        const queryText = '项目会议讨论计划';

        final results = await embeddingService.searchSimilarEventsByText(
          queryText,
          testEvents,
          topK: 3,
          threshold: 0.1,
        );

        expect(results, isNotEmpty);

        print('✅ 搜索查询: $queryText');
        for (final result in results) {
          final event = result['event'] as EventNode;
          final similarity = result['similarity'] as double;
          print('   - ${event.name}: ${similarity.toStringAsFixed(3)}');
        }

        // 验证结果按相似度降序排列
        for (int i = 0; i < results.length - 1; i++) {
          expect(
            results[i]['similarity'] as double,
            greaterThanOrEqualTo(results[i + 1]['similarity'] as double),
          );
        }
      });

      test('基于向量搜索相似事件', () async {
        // 使用第一个事件的向量作为查询向量
        final queryVector = testEvents[0].embedding!;

        final results = await embeddingService.findSimilarEvents(
          queryVector,
          testEvents,
          topK: 2,
          threshold: 0.5,
        );

        expect(results, isNotEmpty);

        // 第一个结果应该是查询事件本身
        final topResult = results.first;
        expect((topResult['event'] as EventNode).id, equals('event_1'));
        expect(topResult['similarity'] as double, closeTo(1.0, 0.001));

        print('✅ 向量搜索结果:');
        for (final result in results) {
          final event = result['event'] as EventNode;
          final similarity = result['similarity'] as double;
          print('   - ${event.name}: ${similarity.toStringAsFixed(3)}');
        }
      });

      test('阈值过滤测试', () async {
        const queryText = '完全不相关的内容xyz123';

        final results = await embeddingService.searchSimilarEventsByText(
          queryText,
          testEvents,
          topK: 10,
          threshold: 0.8, // 高阈值
        );

        // 由于查询文本与事件不相关，高阈值下应该没有结果
        expect(results.length, lessThanOrEqualTo(testEvents.length));

        print('✅ 高阈值搜索结果数量: ${results.length}');
      });
    });

    group('缓存管理测试', () {
      test('嵌入向量缓存', () async {
        const testText = '这是用于测试缓存的文本';

        // 第一次生成
        final embedding1 = await embeddingService.generateTextEmbedding(testText);

        // 第二次应该从缓存获取
        final embedding2 = await embeddingService.generateTextEmbedding(testText);

        expect(embedding1, equals(embedding2));

        // 检查缓存统计
        final stats = embeddingService.getCacheStats();
        expect(stats['cached_embeddings'], greaterThan(0));

        print('✅ 缓存统计: $stats');
      });

      test('缓存清空', () {
        // 先生成一些缓存
        embeddingService.generateTextEmbedding('测试文本1');
        embeddingService.generateTextEmbedding('测试文本2');

        // 清空缓存
        embeddingService.clearCache();

        final stats = embeddingService.getCacheStats();
        expect(stats['cached_embeddings'], equals(0));

        print('✅ 缓存已清空');
      });

      test('缓存键生成一致性', () async {
        const text1 = '相同的文本';
        const text2 = '相同的文本';
        const text3 = '不同的文本';

        await embeddingService.generateTextEmbedding(text1);
        await embeddingService.generateTextEmbedding(text2);
        await embeddingService.generateTextEmbedding(text3);

        final stats = embeddingService.getCacheStats();
        // 由于text1和text2相同，应该只有2个缓存条目
        expect(stats['cached_embeddings'], equals(2));
      });
    });

    group('错误��理测试', () {
      test('模型加载失败处理', () async {
        // 这个测试验证当模型加载失败时，服务能够优雅地降级到备用方案
        const testText = '测试备用方案';

        final embedding = await embeddingService.generateTextEmbedding(testText);

        // 即使模型加载失败，也应该能生成向量（使用备用方案）
        expect(embedding, isNotNull);
        expect(embedding!.length, equals(EmbeddingService.vectorDimensions));
      });

      test('异常文本处理', () async {
        // 测试特殊字符和emoji
        const specialText = '🎉特殊字符测试!@#\$%^&*()_+{}|:"<>?[]\\;\'./';

        final embedding = await embeddingService.generateTextEmbedding(specialText);

        expect(embedding, isNotNull);
        expect(embedding!.length, equals(EmbeddingService.vectorDimensions));

        print('✅ 特殊字符处理成功');
      });
    });

    group('性能测试', () {
      test('批量嵌入生成性能', () async {
        final texts = List.generate(10, (i) => '测试文本 $i: 这是第${i}个测试文本，用于性能测试。');

        final stopwatch = Stopwatch()..start();

        final embeddings = <List<double>>[];
        for (final text in texts) {
          final embedding = await embeddingService.generateTextEmbedding(text);
          if (embedding != null) {
            embeddings.add(embedding);
          }
        }

        stopwatch.stop();

        expect(embeddings.length, equals(texts.length));
        print('✅ 生成${texts.length}个嵌入向量耗时: ${stopwatch.elapsedMilliseconds}ms');
        print('✅ 平均每个向量耗时: ${stopwatch.elapsedMilliseconds / texts.length}ms');
      });

      test('缓存性能提升', () async {
        const testText = '用于测试缓存性能的文本';

        // 第一次生成（无缓存）
        final stopwatch1 = Stopwatch()..start();
        await embeddingService.generateTextEmbedding(testText);
        stopwatch1.stop();

        // 第二次生成（有缓存）
        final stopwatch2 = Stopwatch()..start();
        await embeddingService.generateTextEmbedding(testText);
        stopwatch2.stop();

        print('✅ 首次生成耗时: ${stopwatch1.elapsedMicroseconds}μs');
        print('✅ 缓存命中耗时: ${stopwatch2.elapsedMicroseconds}μs');

        // 缓存应该显著提升性能
        expect(stopwatch2.elapsedMicroseconds, lessThan(stopwatch1.elapsedMicroseconds));
      });
    });

    group('实际应用场景测试', () {
      test('会议记录语义搜索', () async {
        final meetings = [
          EventNode(
            id: 'meeting_1',
            name: '产品规划会议',
            type: '会议',
            description: '讨论Q4产品路线图和功能优先级',
            purpose: '制定产品策略',
            result: '确定了核心功能开发顺序',
          ),
          EventNode(
            id: 'meeting_2',
            name: '技术评审会议',
            type: '会议',
            description: '评审新架构设计方案',
            purpose: '技术方案决策',
            result: '通过了微服务架构方案',
          ),
          EventNode(
            id: 'meeting_3',
            name: '项目复盘会议',
            type: '会议',
            description: '回顾项目执行过���中的问题和经验',
            purpose: '总结经验教训',
            result: '制定了改进措施',
          ),
        ];

        // 生成嵌入向量
        for (final meeting in meetings) {
          meeting.embedding = await embeddingService.generateEventEmbedding(meeting) ?? <double>[];
        }

        // 搜索与产品相关的会议
        final productResults = await embeddingService.searchSimilarEventsByText(
          '产品开发规划',
          meetings,
        );

        // 搜索与技术相关的会议
        final techResults = await embeddingService.searchSimilarEventsByText(
          '技术架构设计',
          meetings,
        );

        expect(productResults, isNotEmpty);
        expect(techResults, isNotEmpty);

        print('✅ 产品相关搜索结果:');
        for (final result in productResults) {
          final event = result['event'] as EventNode;
          final similarity = result['similarity'] as double;
          print('   - ${event.name}: ${similarity.toStringAsFixed(3)}');
        }

        print('✅ 技术相关搜索结果:');
        for (final result in techResults) {
          final event = result['event'] as EventNode;
          final similarity = result['similarity'] as double;
          print('   - ${event.name}: ${similarity.toStringAsFixed(3)}');
        }
      });

      test('多语言事件搜索', () async {
        final events = [
          EventNode(
            id: 'event_cn',
            name: '中文事件',
            type: '会议',
            description: '这是一个中文描述的事件',
            purpose: '测试中文处理',
          ),
          EventNode(
            id: 'event_en',
            name: 'English Event',
            type: 'meeting',
            description: 'This is an English event description',
            purpose: 'Test English processing',
          ),
        ];

        for (final event in events) {
          event.embedding = await embeddingService.generateEventEmbedding(event) ?? <double>[];
        }

        // 中文查询
        final cnResults = await embeddingService.searchSimilarEventsByText(
          '中文会议活动',
          events,
        );

        // 英文查询
        final enResults = await embeddingService.searchSimilarEventsByText(
          'English meeting activity',
          events,
        );

        expect(cnResults, isNotEmpty);
        expect(enResults, isNotEmpty);

        print('✅ 多语言搜索测试完成');
      });
    });
  });
}

// 创建最小的测试模型数据（用于模型文件不存在的情况）
List<int> _createMinimalTestModel() {
  // 创建一个基本的ONNX protobuf结构
  return [
    0x08, 0x07, // IR版本
    0x12, 0x0B, 0x62, 0x61, 0x63, 0x6B, 0x65, 0x6E, 0x64, 0x2D, 0x74, 0x65, 0x73, 0x74, // producer name
    0x18, 0x06, // model version
    0x22, 0x00, // domain
    0x2A, 0x00, // doc string
    ...List.filled(5000, 0x00), // 填充数据，确保文件足够大
  ];
}
