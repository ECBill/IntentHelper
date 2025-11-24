import 'package:app/models/graph_models.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/services/embedding_service.dart';
import 'package:app/services/llm.dart';

/// 语义聚类服务 - 实现增量式聚类机制
/// 
/// 核心功能：
/// 1. 增量聚类：只处理新增或最近修改的事件节点
/// 2. 向量聚类：基于embedding的余弦相似度
/// 3. 时间约束：限制聚类成员在30天时间窗口内
/// 4. 智能摘要：使用GPT-4o-mini生成聚类标题
class SemanticClusteringService {
  static final SemanticClusteringService _instance = SemanticClusteringService._internal();
  factory SemanticClusteringService() => _instance;
  SemanticClusteringService._internal();
  
  final EmbeddingService _embeddingService = EmbeddingService();
  
  // 聚类参数
  // 单阶段参数（保留兼容性）
  static const double SIMILARITY_THRESHOLD = 0.85;  // 余弦相似度阈值
  static const int TEMPORAL_WINDOW_DAYS = 30;       // 时间窗口（天）
  static const int MIN_CLUSTER_SIZE = 2;            // 最小聚类大小
  static const int MAX_CLUSTER_SIZE = 20;           // 最大聚类大小
  
  // 两阶段聚类参数
  // 第一阶段：主题粗分（生活/学业/娱乐/技术/工作等）
  static const double STAGE1_SIMILARITY_THRESHOLD = 0.70;  // 较低阈值，容纳更多主题变化
  static const int STAGE1_MIN_CLUSTER_SIZE = 3;            // 主题簇至少3个事件
  static const int STAGE1_MAX_CLUSTER_SIZE = 100;          // 主题簇可以很大
  
  // 第二阶段：类内细分（饮食/游戏/论文/婚礼等细粒度主题）
  static const double STAGE2_SIMILARITY_THRESHOLD = 0.85;  // 较高阈值，区分细节
  static const int STAGE2_MIN_CLUSTER_SIZE = 2;            // 细分簇至少2个事件
  static const int STAGE2_MAX_CLUSTER_SIZE = 15;           // 细分簇不宜过大
  
  // 簇合并与纯度检查
  static const double MERGE_SIMILARITY_THRESHOLD = 0.86;   // 合并现有簇的阈值
  static const double PURITY_THRESHOLD = 0.72;             // 成员与中心相似度下限
  
  // 联合嵌入权重
  static const double TITLE_WEIGHT = 0.7;    // 标题权重
  static const double CONTENT_WEIGHT = 0.3;  // 内容权重
  
  /// 生成联合嵌入：标题+内容的加权组合
  Future<List<double>?> _generateJointEmbedding(EventNode event) async {
    try {
      // 如果事件已有embedding且内容未变，直接使用
      final existingEmbedding = _embeddingService.getEventEmbedding(event);
      if (existingEmbedding != null && existingEmbedding.isNotEmpty) {
        return existingEmbedding;
      }
      
      // 生成标题embedding
      final titleEmbedding = await _embeddingService.generateTextEmbedding(event.name);
      if (titleEmbedding == null) return null;
      
      // 生成内容embedding（描述+目的+结果）
      final contentText = event.getEmbeddingText();
      List<double>? contentEmbedding;
      if (contentText != event.name && contentText.isNotEmpty) {
        contentEmbedding = await _embeddingService.generateTextEmbedding(contentText);
      }
      
      // 如果没有额外内容，只使用标题
      if (contentEmbedding == null) {
        return titleEmbedding;
      }
      
      // 加权组合并归一化
      final jointEmbedding = <double>[];
      for (int i = 0; i < titleEmbedding.length; i++) {
        jointEmbedding.add(
          TITLE_WEIGHT * titleEmbedding[i] + CONTENT_WEIGHT * contentEmbedding[i]
        );
      }
      
      return _embeddingService.calculateCosineSimilarity(jointEmbedding, jointEmbedding) > 0 
          ? jointEmbedding 
          : titleEmbedding;
    } catch (e) {
      print('[SemanticClusteringService] ⚠️ 生成联合嵌入失败: $e');
      final existingEmbedding = _embeddingService.getEventEmbedding(event);
      return existingEmbedding != null && existingEmbedding.isNotEmpty ? existingEmbedding : null;
    }
  }

  /// 主要聚类方法：对知识图谱执行增量聚类
  /// 
  /// 支持单阶段（兼容旧版）或两阶段聚类
  /// 
  /// 返回聚类结果摘要
  Future<Map<String, dynamic>> organizeGraph({
    bool forceRecluster = false,
    bool useTwoStage = true, // 默认使用两阶段聚类
    Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('开始语义聚类...');
      final startTime = DateTime.now();
      
      // 1. 获取候选事件（增量策略）
      final candidates = await _getIncrementalCandidates(forceRecluster);
      onProgress?.call('找到 ${candidates.length} 个候选事件');
      
      if (candidates.isEmpty) {
        return {
          'success': true,
          'message': '没有需要聚类的事件',
          'clusters_created': 0,
          'events_processed': 0,
        };
      }
      
      // 2. 更新联合嵌入
      if (useTwoStage) {
        onProgress?.call('更新联合嵌入...');
        await _updateJointEmbeddings(candidates, onProgress: onProgress);
      }
      
      // 3. 执行聚类（选择单阶段或两阶段）
      int clustersCreated = 0;
      int eventsClustered = 0;
      
      if (useTwoStage) {
        // 使用两阶段聚类
        onProgress?.call('执行两阶段聚类...');
        final result = await _performTwoStageClustering(
          candidates,
          onProgress: onProgress,
        );
        
        // 获取所有level=2的聚类节点
        final allClusters = await getAllClusters();
        final finalClusters = allClusters.where((c) => c.level == 2).toList();
        clustersCreated = finalClusters.length;
        eventsClustered = finalClusters.fold(0, (sum, c) => sum + c.memberCount);
      } else {
        // 使用单阶段聚类（向后兼容）
        onProgress?.call('正在聚类...');
        final clusters = await _clusterEvents(candidates, onProgress: onProgress);
        onProgress?.call('生成了 ${clusters.length} 个聚类');
        
        final clusterNodes = <ClusterNode>[];
        int processedClusters = 0;
        
        for (final cluster in clusters) {
          if (cluster['members'].length < MIN_CLUSTER_SIZE) {
            continue;
          }
          
          processedClusters++;
          onProgress?.call('生成聚类摘要 $processedClusters/${clusters.length}...');
          
          final clusterNode = await _createClusterSummary(cluster);
          clusterNodes.add(clusterNode);
          
          await _updateMemberEvents(cluster['members'], clusterNode.id);
        }
        
        if (clusterNodes.isNotEmpty) {
          ObjectBoxService.clusterNodeBox.putMany(clusterNodes);
        }
        
        clustersCreated = clusterNodes.length;
        eventsClustered = clusterNodes.fold(0, (sum, c) => sum + c.memberCount);
      }

      final duration = DateTime.now().difference(startTime);
      onProgress?.call('聚类完成！耗时 ${duration.inSeconds} 秒');
      
      return {
        'success': true,
        'message': '聚类完成',
        'clusters_created': clustersCreated,
        'events_processed': candidates.length,
        'events_clustered': eventsClustered,
        'duration_seconds': duration.inSeconds,
      };
      
    } catch (e, stackTrace) {
      print('[SemanticClusteringService] ❌ 聚类错误: $e');
      print(stackTrace);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  /// 获取增量聚类候选事件
  Future<List<EventNode>> _getIncrementalCandidates(
    bool forceRecluster, {
    bool useTemporalConstraint = true,
  }) async {
    final allEvents = ObjectBoxService.eventNodeBox.getAll();

    if (forceRecluster) {
      // 强制重新聚类所有事件
      return allEvents.where((e) {
        final embedding = _embeddingService.getEventEmbedding(e);
        return embedding != null && embedding.isNotEmpty;
      }).toList();
    }
    
    if (!useTemporalConstraint) {
      // 不使用时间约束：只处理未聚类的事件
      return allEvents.where((e) {
        final embedding = _embeddingService.getEventEmbedding(e);
        return embedding != null && embedding.isNotEmpty && e.clusterId == null;
      }).toList();
    }
    
    // 增量策略：只处理未聚类或最近更新的事件
    final now = DateTime.now();
    final cutoffTime = now.subtract(Duration(days: TEMPORAL_WINDOW_DAYS));
    
    return allEvents.where((e) {
      // 必须有embedding
      final embedding = _embeddingService.getEventEmbedding(e);
      if (embedding == null || embedding.isEmpty) return false;
      
      // 未被聚类的事件
      if (e.clusterId == null) return true;
      
      // 最近更新的事件（可能需要重新聚类）
      if (e.lastUpdated.isAfter(cutoffTime)) return true;
      
      // 最近被访问的事件
      if (e.lastSeenTime != null && e.lastSeenTime!.isAfter(cutoffTime)) return true;
      
      return false;
    }).toList();
  }
  
  /// 执行聚类算法（凝聚层次聚类 + 余弦相似度）
  Future<List<Map<String, dynamic>>> _clusterEvents(
    List<EventNode> events,
    {Function(String)? onProgress}
  ) async {
    if (events.isEmpty) return [];
    
    // 使用简化的凝聚层次聚类
    final clusters = <Map<String, dynamic>>[];
    final assigned = <int>{};
    
    for (int i = 0; i < events.length; i++) {
      if (assigned.contains(i)) continue;
      
      final cluster = <EventNode>[events[i]];
      assigned.add(i);
      
      // 找到所有相似的事件
      for (int j = i + 1; j < events.length; j++) {
        if (assigned.contains(j)) continue;
        
        // 获取事件嵌入向量
        final embeddingI = _embeddingService.getEventEmbedding(events[i]);
        final embeddingJ = _embeddingService.getEventEmbedding(events[j]);
        
        if (embeddingI == null || embeddingJ == null) continue;
        
        // 跳过旧的384维向量（已废弃的embedding模型），避免维度不匹配错误
        if (embeddingI.length == 384 || embeddingJ.length == 384) continue;
        
        // 检查相似度
        final similarity = _embeddingService.calculateCosineSimilarity(
          embeddingI,
          embeddingJ,
        );
        
        if (similarity >= SIMILARITY_THRESHOLD) {
          // 检查时间约束
          if (_checkTemporalConstraint(cluster + [events[j]])) {
            cluster.add(events[j]);
            assigned.add(j);
            
            // 限制聚类大小
            if (cluster.length >= MAX_CLUSTER_SIZE) break;
          }
        }
      }
      
      // 只保留符合最小大小的聚类
      if (cluster.length >= MIN_CLUSTER_SIZE) {
        clusters.add({
          'members': cluster,
          'center_index': i,
        });
      }
    }
    
    return clusters;
  }
  
  /// 检查聚类成员是否满足时间约束（30天窗口）
  bool _checkTemporalConstraint(List<EventNode> members) {
    if (members.length < 2) return true;
    
    DateTime? earliest;
    DateTime? latest;
    
    for (final event in members) {
      final eventTime = event.startTime ?? event.lastUpdated;
      
      if (earliest == null || eventTime.isBefore(earliest)) {
        earliest = eventTime;
      }
      if (latest == null || eventTime.isAfter(latest)) {
        latest = eventTime;
      }
    }
    
    if (earliest != null && latest != null) {
      final span = latest.difference(earliest).inDays;
      return span <= TEMPORAL_WINDOW_DAYS;
    }
    
    return true;
  }
  
  /// 创建聚类摘要节点
  Future<ClusterNode> _createClusterSummary(
    Map<String, dynamic> cluster, {
    int level = 2,
    bool isFinalCluster = true,
    String? parentClusterId,
  }) async {
    final members = cluster['members'] as List<EventNode>;
    
    // 1. 生成聚类中心向量（成员embedding的均值）
    final memberEmbeddings = members
        .map((e) => _embeddingService.getEventEmbedding(e))
        .where((emb) => emb != null && emb.isNotEmpty)
        .cast<List<double>>()
        .toList();
    final centroid = _calculateCentroid(memberEmbeddings);
    
    // 2. 计算平均相似度
    final avgSimilarity = _calculateAvgSimilarity(members);
    
    // 3. 生成聚类标题（使用GPT-4o-mini）
    final title = await _generateClusterTitle(members, level: level);
    
    // 4. 生成聚类描述
    final description = _generateClusterDescription(members);
    
    // 5. 获取时间范围
    DateTime? earliestTime;
    DateTime? latestTime;
    
    for (final event in members) {
      final eventTime = event.startTime ?? event.lastUpdated;
      if (earliestTime == null || eventTime.isBefore(earliestTime)) {
        earliestTime = eventTime;
      }
      if (latestTime == null || eventTime.isAfter(latestTime)) {
        latestTime = eventTime;
      }
    }
    
    // 6. 创建聚类节点
    final clusterId = 'cluster_${level}_${DateTime.now().millisecondsSinceEpoch}';
    final clusterNode = ClusterNode(
      id: clusterId,
      name: title,
      type: 'cluster',
      description: description,
      embedding: centroid,
      memberCount: members.length,
      avgSimilarity: avgSimilarity,
      earliestEventTime: earliestTime,
      latestEventTime: latestTime,
      level: level,
      parentClusterId: parentClusterId,
    );
    
    clusterNode.memberIds = members.map((e) => e.id).toList();
    
    return clusterNode;
  }
  
  /// 计算向量中心（均值）
  List<double> _calculateCentroid(List<List<double>> vectors) {
    if (vectors.isEmpty) return [];
    
    final dim = vectors.first.length;
    final centroid = List<double>.filled(dim, 0.0);
    
    for (final vec in vectors) {
      for (int i = 0; i < dim; i++) {
        centroid[i] += vec[i];
      }
    }
    
    for (int i = 0; i < dim; i++) {
      centroid[i] /= vectors.length;
    }
    
    return centroid;
  }
  
  /// 计算聚类成员间的平均相似度
  double _calculateAvgSimilarity(List<EventNode> members) {
    if (members.length < 2) return 1.0;
    
    double totalSimilarity = 0.0;
    int pairCount = 0;
    
    for (int i = 0; i < members.length - 1; i++) {
      for (int j = i + 1; j < members.length; j++) {
        final embeddingI = _embeddingService.getEventEmbedding(members[i]);
        final embeddingJ = _embeddingService.getEventEmbedding(members[j]);
        
        if (embeddingI == null || embeddingJ == null) continue;
        
        // 跳过旧的384维向量（已废弃的embedding模型），避免维度不匹配错误
        if (embeddingI.length == 384 || embeddingJ.length == 384) continue;
        
        final similarity = _embeddingService.calculateCosineSimilarity(
          embeddingI,
          embeddingJ,
        );
        totalSimilarity += similarity;
        pairCount++;
      }
    }
    
    return pairCount > 0 ? totalSimilarity / pairCount : 1.0;
  }
  
  /// 使用GPT-4o-mini生成聚类标题
  Future<String> _generateClusterTitle(List<EventNode> members, {int level = 2}) async {
    try {
      // 收集事件标题和描述用于生成摘要
      final eventTitles = members.take(10).map((e) => e.name).join('\n• ');
      
      // 收集事件内容的关键词
      final eventContents = members.take(5).map((e) {
        final content = e.getEmbeddingText();
        return content.length > 50 ? '${content.substring(0, 50)}...' : content;
      }).join('\n  ');
      
      final String levelGuidance;
      final String exampleTitles;
      
      if (level == 1) {
        // 第一层：主题粗分，要求更宽泛的分类
        levelGuidance = '''
这是主题粗分层聚类，请生成一个宽泛的主题分类标题（8-12字）。
主题应该是高层次的分类，如："生活类"、"学业研究"、"娱乐休闲"、"技术工作"、"社交活动"等。
避免过于具体的细节。
''';
        exampleTitles = '''
• 生活与日常事务
• 学业与学术研究
• 娱乐与休闲活动
• 技术与工作事项
• 社交与人际交往
''';
      } else {
        // 第二层：细分主题，要求更具体的描述
        levelGuidance = '''
这是细分层聚类，请生成一个具体而有区分度的标题（8-15字）。
标题应该明确指出具体的主题或活动，如："饮食·海底捞讨论"、"游戏·连段技巧"、"论文·XX方向研究"等。
使用"·"分隔主类别和子类别，使标题更具层次感和可读性。
避免使用"讨论"、"交流"、"事务"等泛化词汇作为主要内容。
''';
        exampleTitles = '''
• 饮食·火锅餐厅体验
• 游戏·装备与技巧
• 论文·深度学习研究
• 旅行·酒店预订计划
• 编程·项目开发记录
''';
      }
      
      final prompt = '''
请为以下事件生成一个聚类标题：

$levelGuidance

事件标题：
• $eventTitles

事件内容摘要：
$eventContents

要求：
1. 标题应该准确概括这些事件的共同主题
2. 标题要有区分度，避免与其他常见主题混淆
3. 优先使用事件中的关键实体或活动名称
4. 只返回标题文本，不要其他内容

示例标题：
$exampleTitles
''';
      
      final llm = await LLM.create('gpt-4o-mini');
      final response = await llm.createRequest(content: prompt);

      // 清理响应，只保留标题
      String title = response.trim()
          .replaceAll(RegExp(r'^[\s•\-\*]+'), '')
          .replaceAll(RegExp('["\']'), '');

      // 限制长度
      if (level == 1) {
        title = title.length > 15 ? title.substring(0, 15) + '...' : title;
      } else {
        title = title.length > 20 ? title.substring(0, 20) + '...' : title;
      }
      
      return title;
      
    } catch (e) {
      print('[SemanticClusteringService] ⚠️ 生成标题失败，使用默认标题: $e');
      // 降级策略：使用第一个事件的类型 + 数量
      if (level == 1) {
        return '${members.first.type}类事件';
      } else {
        return '${members.first.type}·${members.first.name}等';
      }
    }
  }
  
  /// 生成聚类描述
  String _generateClusterDescription(List<EventNode> members) {
    final types = <String, int>{};
    for (final event in members) {
      types[event.type] = (types[event.type] ?? 0) + 1;
    }
    
    final topTypes = types.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final typesSummary = topTypes.take(3)
        .map((e) => '${e.key}(${e.value}个)')
        .join('、');
    
    return '包含 ${members.length} 个相关事件：$typesSummary';
  }
  
  /// 更新聚类成员事件的clusterId
  Future<void> _updateMemberEvents(List<EventNode> members, String clusterId) async {
    for (final event in members) {
      event.clusterId = clusterId;
      ObjectBoxService.eventNodeBox.put(event);
    }
  }

  /// 获取所有聚类节点
  Future<List<ClusterNode>> getAllClusters() async {
    try {
      return ObjectBoxService.clusterNodeBox.getAll();
    } catch (e) {
      print('[SemanticClusteringService] 获取聚类失败: $e');
      return <ClusterNode>[];
    }
  }
  
  /// 获取特定聚类的成员事件
  Future<List<EventNode>> getClusterMembers(String clusterId) async {
    final allEvents = ObjectBoxService.eventNodeBox.getAll();
    return allEvents.where((e) => e.clusterId == clusterId).toList();
  }
  
  /// 获取未聚类的事件
  Future<List<EventNode>> getUnclusteredEvents() async {
    final allEvents = ObjectBoxService.eventNodeBox.getAll();
    return allEvents.where((e) {
      final embedding = _embeddingService.getEventEmbedding(e);
      return embedding != null && embedding.isNotEmpty && e.clusterId == null;
    }).toList();
  }

  /// 全量初始化聚类：对所有历史事件执行两阶段聚类
  Future<Map<String, dynamic>> clusterInitAll({
    Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('开始全量初始化聚类...');
      final startTime = DateTime.now();
      
      // 1. 获取所有有embedding的事件
      final allEvents = ObjectBoxService.eventNodeBox.getAll()
          .where((e) {
            final embedding = _embeddingService.getEventEmbedding(e);
            return embedding != null && embedding.isNotEmpty;
          })
          .toList();
      
      onProgress?.call('找到 ${allEvents.length} 个事件');
      
      if (allEvents.isEmpty) {
        return {
          'success': true,
          'message': '没有可聚类的事件',
          'stage1_clusters': 0,
          'stage2_clusters': 0,
        };
      }
      
      // 2. 更新联合嵌入
      onProgress?.call('更新联合嵌入...');
      await _updateJointEmbeddings(allEvents, onProgress: onProgress);
      
      // 3. 执行两阶段聚类
      onProgress?.call('执行两阶段聚类...');
      final result = await _performTwoStageClustering(
        allEvents,
        onProgress: onProgress,
      );
      
      final duration = DateTime.now().difference(startTime);
      onProgress?.call('全量聚类完成！耗时 ${duration.inSeconds} 秒');
      
      return {
        'success': true,
        'message': '全量聚类完成',
        'stage1_clusters': result['stage1_clusters'],
        'stage2_clusters': result['stage2_clusters'],
        'events_processed': allEvents.length,
        'duration_seconds': duration.inSeconds,
      };
      
    } catch (e, stackTrace) {
      print('[SemanticClusteringService] ❌ 全量聚类错误: $e');
      print(stackTrace);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 按日期范围聚类：对指定时间段内的事件聚类并合并入既有结构
  Future<Map<String, dynamic>> clusterByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('开始日期范围聚类...');
      final startTime = DateTime.now();
      
      // 1. 获取日期范围内的事件
      final allEvents = ObjectBoxService.eventNodeBox.getAll();
      final rangeEvents = allEvents.where((e) {
        final embedding = _embeddingService.getEventEmbedding(e);
        if (embedding == null || embedding.isEmpty) return false;
        final eventTime = e.startTime ?? e.lastUpdated;
        return eventTime.isAfter(startDate) && eventTime.isBefore(endDate);
      }).toList();
      
      onProgress?.call('找到 ${rangeEvents.length} 个范围内的事件');
      
      if (rangeEvents.isEmpty) {
        return {
          'success': true,
          'message': '日期范围内没有可聚类的事件',
          'new_clusters': 0,
          'merged_events': 0,
        };
      }
      
      // 2. 更新联合嵌入
      onProgress?.call('更新联合嵌入...');
      await _updateJointEmbeddings(rangeEvents, onProgress: onProgress);
      
      // 3. 获取现有聚类
      final existingClusters = await getAllClusters();
      
      // 4. 尝试合并到现有聚类
      onProgress?.call('合并到现有聚类...');
      int mergedCount = 0;
      final unmergedEvents = <EventNode>[];
      
      for (final event in rangeEvents) {
        bool merged = false;
        
        // 尝试找到最相似的现有聚类
        double bestSimilarity = 0;
        ClusterNode? bestCluster;
        
        for (final cluster in existingClusters) {
          if (cluster.level != 2) continue; // 只合并到细分层
          final clusterEmbedding = cluster.embeddingV2 ?? cluster.embedding;
          if (clusterEmbedding.isEmpty) continue;
          
          final eventEmbedding = _embeddingService.getEventEmbedding(event);
          if (eventEmbedding == null) continue;
          
          // 跳过旧的384维向量（已废弃的embedding模型），避免维度不匹配错误
          if (eventEmbedding.length == 384 || clusterEmbedding.length == 384) continue;
          
          final similarity = _embeddingService.calculateCosineSimilarity(
            eventEmbedding,
            clusterEmbedding,
          );
          
          if (similarity > bestSimilarity && similarity >= MERGE_SIMILARITY_THRESHOLD) {
            bestSimilarity = similarity;
            bestCluster = cluster;
          }
        }
        
        // 如果找到合适的聚类，合并
        if (bestCluster != null) {
          event.clusterId = bestCluster.id;
          ObjectBoxService.eventNodeBox.put(event);
          
          // 更新聚类信息
          final memberIds = bestCluster.memberIds;
          if (!memberIds.contains(event.id)) {
            memberIds.add(event.id);
            bestCluster.memberIds = memberIds;
            bestCluster.lastUpdated = DateTime.now();
            ObjectBoxService.clusterNodeBox.put(bestCluster);
          }
          
          mergedCount++;
          merged = true;
        }
        
        if (!merged) {
          unmergedEvents.add(event);
        }
      }
      
      onProgress?.call('已合并 $mergedCount 个事件到现有聚类');
      
      // 5. 对未合并的事件执行新聚类
      int newClusters = 0;
      if (unmergedEvents.isNotEmpty) {
        onProgress?.call('对 ${unmergedEvents.length} 个未合并事件执行聚类...');
        final result = await _performTwoStageClustering(
          unmergedEvents,
          onProgress: onProgress,
        );
        newClusters = result['stage2_clusters'] as int;
      }
      
      final duration = DateTime.now().difference(startTime);
      onProgress?.call('日期范围聚类完成！耗时 ${duration.inSeconds} 秒');
      
      return {
        'success': true,
        'message': '日期范围聚类完成',
        'events_processed': rangeEvents.length,
        'merged_events': mergedCount,
        'new_clusters': newClusters,
        'duration_seconds': duration.inSeconds,
      };
      
    } catch (e, stackTrace) {
      print('[SemanticClusteringService] ❌ 日期范围聚类错误: $e');
      print(stackTrace);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 更新事件的联合嵌入
  Future<void> _updateJointEmbeddings(
    List<EventNode> events,
    {Function(String)? onProgress}
  ) async {
    int updated = 0;
    for (final event in events) {
      final jointEmbedding = await _generateJointEmbedding(event);
      final currentEmbedding = _embeddingService.getEventEmbedding(event);
      if (jointEmbedding != null && jointEmbedding != currentEmbedding) {
        _embeddingService.setEventEmbedding(event, jointEmbedding);
        ObjectBoxService.eventNodeBox.put(event);
        updated++;
      }
      
      if (updated % 10 == 0) {
        onProgress?.call('已更新 $updated/${events.length} 个嵌入向量');
      }
    }
    onProgress?.call('联合嵌入更新完成：$updated 个');
  }

  /// 执行两阶段聚类
  Future<Map<String, dynamic>> _performTwoStageClustering(
    List<EventNode> events,
    {Function(String)? onProgress}
  ) async {
    // 第一阶段：主题粗分
    onProgress?.call('第一阶段：主题粗分...');
    final stage1Clusters = await _clusterEventsStage1(events, onProgress: onProgress);
    onProgress?.call('生成了 ${stage1Clusters.length} 个主题簇');
    
    // 保存第一阶段聚类节点
    final stage1Nodes = <ClusterNode>[];
    for (final cluster in stage1Clusters) {
      if (cluster['members'].length < STAGE1_MIN_CLUSTER_SIZE) continue;
      
      final clusterNode = await _createClusterSummary(
        cluster,
        level: 1,
        isFinalCluster: false,
      );
      stage1Nodes.add(clusterNode);
    }
    
    if (stage1Nodes.isNotEmpty) {
      ObjectBoxService.clusterNodeBox.putMany(stage1Nodes);
    }
    
    // 第二阶段：在每个主题簇内进行细分
    onProgress?.call('第二阶段：类内细分...');
    int totalStage2Clusters = 0;
    final stage2Nodes = <ClusterNode>[];
    
    for (int i = 0; i < stage1Clusters.length; i++) {
      final stage1Cluster = stage1Clusters[i];
      final stage1Members = stage1Cluster['members'] as List<EventNode>;
      
      if (stage1Members.length < STAGE1_MIN_CLUSTER_SIZE) continue;
      
      onProgress?.call('细分主题簇 ${i+1}/${stage1Clusters.length} (${stage1Members.length}个成员)...');
      
      // 在主题簇内进行细分聚类
      final stage2Clusters = await _clusterEventsStage2(
        stage1Members,
        parentClusterId: stage1Nodes.length > i ? stage1Nodes[i].id : null,
        onProgress: onProgress,
      );
      
      for (final cluster in stage2Clusters) {
        if (cluster['members'].length < STAGE2_MIN_CLUSTER_SIZE) continue;
        
        final clusterNode = await _createClusterSummary(
          cluster,
          level: 2,
          isFinalCluster: true,
          parentClusterId: stage1Nodes.length > i ? stage1Nodes[i].id : null,
        );
        stage2Nodes.add(clusterNode);
        
        // 更新成员事件的聚类信息
        await _updateMemberEvents(cluster['members'], clusterNode.id);
      }
      
      totalStage2Clusters += stage2Clusters.length;
    }
    
    if (stage2Nodes.isNotEmpty) {
      ObjectBoxService.clusterNodeBox.putMany(stage2Nodes);
    }
    
    // 记录聚类元数据
    final meta = ClusteringMeta(
      clusteringTime: DateTime.now(),
      totalEvents: events.length,
      clustersCreated: stage2Nodes.length,
      eventsClustered: stage2Nodes.fold(0, (sum, c) => sum + c.memberCount),
      eventsUnclustered: events.length - stage2Nodes.fold(0, (sum, c) => sum + c.memberCount),
      algorithmUsed: 'two-stage-agglomerative',
      avgClusterSize: stage2Nodes.isEmpty ? 0 : 
        stage2Nodes.fold(0.0, (sum, c) => sum + c.memberCount) / stage2Nodes.length,
      avgIntraClusterSimilarity: stage2Nodes.isEmpty ? 0 :
        stage2Nodes.fold(0.0, (sum, c) => sum + c.avgSimilarity) / stage2Nodes.length,
    );
    meta.parameters = {
      'stage1_similarity_threshold': STAGE1_SIMILARITY_THRESHOLD,
      'stage2_similarity_threshold': STAGE2_SIMILARITY_THRESHOLD,
      'stage1_min_cluster_size': STAGE1_MIN_CLUSTER_SIZE,
      'stage2_min_cluster_size': STAGE2_MIN_CLUSTER_SIZE,
    };
    ObjectBoxService.clusteringMetaBox.put(meta);
    
    return {
      'stage1_clusters': stage1Nodes.length,
      'stage2_clusters': stage2Nodes.length,
    };
  }

  /// 第一阶段聚类：主题粗分
  Future<List<Map<String, dynamic>>> _clusterEventsStage1(
    List<EventNode> events,
    {Function(String)? onProgress}
  ) async {
    if (events.isEmpty) return [];
    
    final clusters = <Map<String, dynamic>>[];
    final assigned = <int>{};
    
    for (int i = 0; i < events.length; i++) {
      if (assigned.contains(i)) continue;
      
      final cluster = <EventNode>[events[i]];
      assigned.add(i);
      
      // 找到所有相似的事件（较低阈值）
      for (int j = i + 1; j < events.length; j++) {
        if (assigned.contains(j)) continue;
        
        final embeddingI = _embeddingService.getEventEmbedding(events[i]);
        final embeddingJ = _embeddingService.getEventEmbedding(events[j]);
        if (embeddingI == null || embeddingJ == null) continue;
        
        // 跳过旧的384维向量（已废弃的embedding模型），避免维度不匹配错误
        if (embeddingI.length == 384 || embeddingJ.length == 384) continue;
        
        final similarity = _embeddingService.calculateCosineSimilarity(
          embeddingI,
          embeddingJ,
        );
        
        if (similarity >= STAGE1_SIMILARITY_THRESHOLD) {
          cluster.add(events[j]);
          assigned.add(j);
          
          if (cluster.length >= STAGE1_MAX_CLUSTER_SIZE) break;
        }
      }
      
      if (cluster.length >= STAGE1_MIN_CLUSTER_SIZE) {
        clusters.add({
          'members': cluster,
          'center_index': i,
        });
      }
    }
    
    return clusters;
  }

  /// 第二阶段聚类：类内细分
  Future<List<Map<String, dynamic>>> _clusterEventsStage2(
    List<EventNode> events,
    {String? parentClusterId, Function(String)? onProgress}
  ) async {
    if (events.isEmpty) return [];
    
    final clusters = <Map<String, dynamic>>[];
    final assigned = <int>{};
    
    for (int i = 0; i < events.length; i++) {
      if (assigned.contains(i)) continue;
      
      final cluster = <EventNode>[events[i]];
      assigned.add(i);
      
      // 找到所有相似的事件（较高阈值）
      for (int j = i + 1; j < events.length; j++) {
        if (assigned.contains(j)) continue;
        
        final embeddingI = _embeddingService.getEventEmbedding(events[i]);
        final embeddingJ = _embeddingService.getEventEmbedding(events[j]);
        if (embeddingI == null || embeddingJ == null) continue;
        
        // 跳过旧的384维向量（已废弃的embedding模型），避免维度不匹配错误
        if (embeddingI.length == 384 || embeddingJ.length == 384) continue;
        
        final similarity = _embeddingService.calculateCosineSimilarity(
          embeddingI,
          embeddingJ,
        );
        
        if (similarity >= STAGE2_SIMILARITY_THRESHOLD) {
          // 检查纯度（确保新成员与簇中心足够相似）
          if (_checkPurity(cluster, events[j])) {
            cluster.add(events[j]);
            assigned.add(j);
            
            if (cluster.length >= STAGE2_MAX_CLUSTER_SIZE) break;
          }
        }
      }
      
      if (cluster.length >= STAGE2_MIN_CLUSTER_SIZE) {
        clusters.add({
          'members': cluster,
          'center_index': i,
          'parent_id': parentClusterId,
        });
      }
    }
    
    return clusters;
  }

  /// 检查簇纯度：新成员与簇中心的相似度
  bool _checkPurity(List<EventNode> cluster, EventNode newMember) {
    if (cluster.isEmpty) return true;
    
    // 计算当前簇中心
    final embeddings = cluster
        .map((e) => _embeddingService.getEventEmbedding(e))
        .where((e) => e != null && e.isNotEmpty && e.length != 384) // 跳过384维旧向量
        .cast<List<double>>()
        .toList();
    if (embeddings.isEmpty) return true;
    
    final centroid = _calculateCentroid(embeddings);
    
    // 检查新成员与中心的相似度
    final newMemberEmbedding = _embeddingService.getEventEmbedding(newMember);
    if (newMemberEmbedding == null) return false;
    
    // 跳过旧的384维向量（已废弃的embedding模型），避免维度不匹配错误
    if (newMemberEmbedding.length == 384 || centroid.length == 384) return false;
    
    final similarity = _embeddingService.calculateCosineSimilarity(
      newMemberEmbedding,
      centroid,
    );
    
    return similarity >= PURITY_THRESHOLD;
  }

  /// 获取聚类质量监控指标
  Future<Map<String, dynamic>> getClusteringQualityMetrics() async {
    try {
      final allClusters = await getAllClusters();
      final finalClusters = allClusters.where((c) => c.level == 2).toList();
      
      if (finalClusters.isEmpty) {
        return {
          'total_clusters': 0,
          'avg_intra_similarity': 0.0,
          'avg_cluster_size': 0.0,
          'outlier_ratio': 0.0,
        };
      }
      
      // 计算平均类内相似度
      double totalIntraSim = 0;
      for (final cluster in finalClusters) {
        totalIntraSim += cluster.avgSimilarity;
      }
      final avgIntraSim = totalIntraSim / finalClusters.length;
      
      // 计算平均聚类大小
      double totalSize = 0;
      for (final cluster in finalClusters) {
        totalSize += cluster.memberCount;
      }
      final avgSize = totalSize / finalClusters.length;
      
      // 检测离群点
      int totalMembers = 0;
      int outliers = 0;
      
      for (final cluster in finalClusters) {
        final clusterEmbedding = _embeddingService.getClusterEmbedding(cluster);
        if (clusterEmbedding == null || clusterEmbedding.isEmpty) continue;
        
        final members = await getClusterMembers(cluster.id);
        totalMembers += members.length;
        
        for (final member in members) {
          final memberEmbedding = _embeddingService.getEventEmbedding(member);
          if (memberEmbedding == null || memberEmbedding.isEmpty) continue;
          
          // 跳过旧的384维向量（已废弃的embedding模型），避免维度不匹配错误
          if (memberEmbedding.length == 384 || clusterEmbedding.length == 384) continue;
          
          final similarity = _embeddingService.calculateCosineSimilarity(
            memberEmbedding,
            clusterEmbedding,
          );
          
          if (similarity < PURITY_THRESHOLD) {
            outliers++;
          }
        }
      }
      
      final outlierRatio = totalMembers > 0 ? outliers / totalMembers : 0.0;
      
      // 计算类间中心距离（采样前20个聚类对）
      final clusterPairs = <double>[];
      final sampleSize = finalClusters.length < 20 ? finalClusters.length : 20;
      
      for (int i = 0; i < sampleSize - 1; i++) {
        for (int j = i + 1; j < sampleSize && j < i + 5; j++) {
          final embeddingI = _embeddingService.getClusterEmbedding(finalClusters[i]);
          final embeddingJ = _embeddingService.getClusterEmbedding(finalClusters[j]);
          if (embeddingI == null || embeddingI.isEmpty || embeddingJ == null || embeddingJ.isEmpty) {
            continue;
          }
          
          // 跳过旧的384维向量（已废弃的embedding模型），避免维度不匹配错误
          if (embeddingI.length == 384 || embeddingJ.length == 384) continue;
          
          final distance = 1.0 - _embeddingService.calculateCosineSimilarity(
            embeddingI,
            embeddingJ,
          );
          clusterPairs.add(distance);
        }
      }
      
      final avgInterDistance = clusterPairs.isEmpty 
          ? 0.0 
          : clusterPairs.reduce((a, b) => a + b) / clusterPairs.length;
      
      return {
        'total_clusters': finalClusters.length,
        'avg_intra_similarity': avgIntraSim,
        'avg_cluster_size': avgSize,
        'outlier_ratio': outlierRatio,
        'avg_inter_distance': avgInterDistance,
        'quality_score': _calculateQualityScore(
          avgIntraSim, 
          avgInterDistance, 
          outlierRatio,
        ),
      };
      
    } catch (e) {
      print('[SemanticClusteringService] ❌ 计算质量指标失败: $e');
      return {
        'error': e.toString(),
      };
    }
  }

  /// 计算聚类质量综合评分
  double _calculateQualityScore(
    double avgIntraSim,
    double avgInterDistance,
    double outlierRatio,
  ) {
    // 质量评分 = 类内相似度(0.4) + 类间距离(0.4) - 离群点比例(0.2)
    // 归一化到0-1范围
    final intraPart = avgIntraSim * 0.4;
    final interPart = avgInterDistance * 0.4;
    final outlierPart = (1.0 - outlierRatio) * 0.2;
    
    return (intraPart + interPart + outlierPart).clamp(0.0, 1.0);
  }

  /// 检测并重分配离群点
  Future<Map<String, dynamic>> detectAndReassignOutliers({
    Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('开始检测离群点...');
      
      final allClusters = await getAllClusters();
      final finalClusters = allClusters.where((c) => c.level == 2).toList();
      
      int totalOutliers = 0;
      int reassigned = 0;
      final newSingletons = <EventNode>[];
      
      for (final cluster in finalClusters) {
        final clusterEmbedding = _embeddingService.getClusterEmbedding(cluster);
        if (clusterEmbedding == null || clusterEmbedding.isEmpty) continue;
        
        final members = await getClusterMembers(cluster.id);
        final outlierMembers = <EventNode>[];
        
        // 检测离群点
        for (final member in members) {
          final memberEmbedding = _embeddingService.getEventEmbedding(member);
          if (memberEmbedding == null || memberEmbedding.isEmpty) continue;
          
          // 跳过旧的384维向量（已废弃的embedding模型），避免维度不匹配错误
          if (memberEmbedding.length == 384 || clusterEmbedding.length == 384) continue;
          
          final similarity = _embeddingService.calculateCosineSimilarity(
            memberEmbedding,
            clusterEmbedding,
          );
          
          if (similarity < PURITY_THRESHOLD) {
            outlierMembers.add(member);
            totalOutliers++;
          }
        }
        
        // 尝试将离群点重分配到其他聚类
        for (final outlier in outlierMembers) {
          ClusterNode? bestCluster;
          double bestSimilarity = MERGE_SIMILARITY_THRESHOLD;
          
          final outlierEmbedding = _embeddingService.getEventEmbedding(outlier);
          if (outlierEmbedding == null) continue;
          
          for (final otherCluster in finalClusters) {
            if (otherCluster.id == cluster.id) continue;
            final otherClusterEmbedding = _embeddingService.getClusterEmbedding(otherCluster);
            if (otherClusterEmbedding == null || otherClusterEmbedding.isEmpty) continue;
            
            final similarity = _embeddingService.calculateCosineSimilarity(
              outlierEmbedding,
              otherClusterEmbedding,
            );
            
            if (similarity > bestSimilarity) {
              bestSimilarity = similarity;
              bestCluster = otherCluster;
            }
          }
          
          if (bestCluster != null) {
            // 重分配到新聚类
            outlier.clusterId = bestCluster.id;
            ObjectBoxService.eventNodeBox.put(outlier);
            
            // 更新新聚类成员列表
            final newMemberIds = bestCluster.memberIds;
            if (!newMemberIds.contains(outlier.id)) {
              newMemberIds.add(outlier.id);
              bestCluster.memberIds = newMemberIds;
              ObjectBoxService.clusterNodeBox.put(bestCluster);
            }
            
            // 从旧聚类移除
            final oldMemberIds = cluster.memberIds;
            oldMemberIds.remove(outlier.id);
            cluster.memberIds = oldMemberIds;
            ObjectBoxService.clusterNodeBox.put(cluster);
            
            reassigned++;
          } else {
            // 无法重分配，标记为单例
            outlier.clusterId = null;
            ObjectBoxService.eventNodeBox.put(outlier);
            newSingletons.add(outlier);
          }
        }
      }
      
      onProgress?.call('离群点检测完成：发现 $totalOutliers 个，重分配 $reassigned 个');

      return {
        'success': true,
        'outliers_detected': totalOutliers,
        'reassigned': reassigned,
        'new_singletons': newSingletons.length,
      };
      
    } catch (e) {
      print('[SemanticClusteringService] ❌ 离群点检测失败: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 清空所有聚类数据
  /// 
  /// 这将删除所有聚类节点和聚类元数据，并清除事件节点的聚类关联
  /// 用于测试前清理旧的聚类结果
  Future<Map<String, dynamic>> clearAllClusters({
    Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('开始清空所有聚类...');
      
      // 1. 获取所有聚类节点
      final allClusters = ObjectBoxService.clusterNodeBox.getAll();
      final clusterCount = allClusters.length;
      
      onProgress?.call('找到 $clusterCount 个聚类节点');
      
      // 2. 获取所有事件节点，清除聚类关联
      final allEvents = ObjectBoxService.eventNodeBox.getAll();
      int clearedEvents = 0;
      
      for (final event in allEvents) {
        if (event.clusterId != null || event.mergedTo != null) {
          event.clusterId = null;
          event.mergedTo = null;
          ObjectBoxService.eventNodeBox.put(event);
          clearedEvents++;
        }
      }
      
      onProgress?.call('清除了 $clearedEvents 个事件的聚类关联');
      
      // 3. 删除所有聚类节点
      if (allClusters.isNotEmpty) {
        ObjectBoxService.clusterNodeBox.removeAll();
        onProgress?.call('删除了 $clusterCount 个聚类节点');
      }
      
      // 4. 删除所有聚类元数据
      final allMeta = ObjectBoxService.clusteringMetaBox.getAll();
      if (allMeta.isNotEmpty) {
        ObjectBoxService.clusteringMetaBox.removeAll();
        onProgress?.call('删除了 ${allMeta.length} 条聚类元数据');
      }
      
      onProgress?.call('✅ 所有聚类已清空');
      
      return {
        'success': true,
        'message': '聚类清空完成',
        'clusters_removed': clusterCount,
        'events_cleared': clearedEvents,
        'meta_removed': allMeta.length,
      };
      
    } catch (e, stackTrace) {
      print('[SemanticClusteringService] ❌ 清空聚类错误: $e');
      print(stackTrace);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
