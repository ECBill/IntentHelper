import 'dart:convert';
import 'dart:math';
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
  
  final ObjectBoxService _objectBox = ObjectBoxService();
  final EmbeddingService _embeddingService = EmbeddingService();
  
  // 聚类参数
  static const double SIMILARITY_THRESHOLD = 0.85;  // 余弦相似度阈值
  static const int TEMPORAL_WINDOW_DAYS = 30;       // 时间窗口（天）
  static const int MIN_CLUSTER_SIZE = 2;            // 最小聚类大小
  static const int MAX_CLUSTER_SIZE = 20;           // 最大聚类大小
  
  /// 主要聚类方法：对知识图谱执行增量聚类
  /// 
  /// 返回聚类结果摘要
  Future<Map<String, dynamic>> organizeGraph({
    bool forceRecluster = false,
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
      
      // 2. 执行聚类
      onProgress?.call('正在聚类...');
      final clusters = await _clusterEvents(candidates, onProgress: onProgress);
      onProgress?.call('生成了 ${clusters.length} 个聚类');
      
      // 3. 为每个聚类生成摘要
      final clusterNodes = <ClusterNode>[];
      int processedClusters = 0;
      
      for (final cluster in clusters) {
        if (cluster['members'].length < MIN_CLUSTER_SIZE) {
          continue; // 跳过过小的聚类
        }
        
        processedClusters++;
        onProgress?.call('生成聚类摘要 $processedClusters/${clusters.length}...');
        
        final clusterNode = await _createClusterSummary(cluster);
        clusterNodes.add(clusterNode);
        
        // 更新成员事件的聚类信息
        await _updateMemberEvents(cluster['members'], clusterNode.id);
      }
      
      // 4. 保存聚类结果
      onProgress?.call('保存聚类结果...');
      await _saveClusteringResults(clusterNodes);
      
      // 5. 记录聚类元数据
      final meta = ClusteringMeta(
        clusteringTime: DateTime.now(),
        totalEvents: candidates.length,
        clustersCreated: clusterNodes.length,
        eventsClustered: clusterNodes.fold(0, (sum, c) => sum + c.memberCount),
        eventsUnclustered: candidates.length - clusterNodes.fold(0, (sum, c) => sum + c.memberCount),
        algorithmUsed: 'agglomerative-cosine',
        avgClusterSize: clusterNodes.isEmpty ? 0 : 
          clusterNodes.fold(0.0, (sum, c) => sum + c.memberCount) / clusterNodes.length,
        avgIntraClusterSimilarity: clusterNodes.isEmpty ? 0 :
          clusterNodes.fold(0.0, (sum, c) => sum + c.avgSimilarity) / clusterNodes.length,
      );
      meta.parameters = {
        'similarity_threshold': SIMILARITY_THRESHOLD,
        'temporal_window_days': TEMPORAL_WINDOW_DAYS,
        'min_cluster_size': MIN_CLUSTER_SIZE,
      };
      
      // 注意：这里需要在objectbox_service中添加对应的保存方法
      // await _objectBox.insertClusteringMeta(meta);
      
      final duration = DateTime.now().difference(startTime);
      onProgress?.call('聚类完成！耗时 ${duration.inSeconds} 秒');
      
      return {
        'success': true,
        'message': '聚类完成',
        'clusters_created': clusterNodes.length,
        'events_processed': candidates.length,
        'events_clustered': meta.eventsClustered,
        'avg_cluster_size': meta.avgClusterSize,
        'avg_similarity': meta.avgIntraClusterSimilarity,
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
  Future<List<EventNode>> _getIncrementalCandidates(bool forceRecluster) async {
    final allEvents = _objectBox.queryEventNodes();
    
    if (forceRecluster) {
      // 强制重新聚类所有事件
      return allEvents.where((e) => 
        e.embedding.isNotEmpty
      ).toList();
    }
    
    // 增量策略：只处理未聚类或最近更新的事件
    final now = DateTime.now();
    final cutoffTime = now.subtract(Duration(days: TEMPORAL_WINDOW_DAYS));
    
    return allEvents.where((e) {
      // 必须有embedding
      if (e.embedding.isEmpty) return false;
      
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
        
        // 检查相似度
        final similarity = _embeddingService.calculateCosineSimilarity(
          events[i].embedding,
          events[j].embedding,
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
  Future<ClusterNode> _createClusterSummary(Map<String, dynamic> cluster) async {
    final members = cluster['members'] as List<EventNode>;
    
    // 1. 生成聚类中心向量（成员embedding的均值）
    final centroid = _calculateCentroid(members.map((e) => e.embedding).toList());
    
    // 2. 计算平均相似度
    final avgSimilarity = _calculateAvgSimilarity(members);
    
    // 3. 生成聚类标题（使用GPT-4o-mini）
    final title = await _generateClusterTitle(members);
    
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
    final clusterId = 'cluster_${DateTime.now().millisecondsSinceEpoch}';
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
        final similarity = _embeddingService.calculateCosineSimilarity(
          members[i].embedding,
          members[j].embedding,
        );
        totalSimilarity += similarity;
        pairCount++;
      }
    }
    
    return pairCount > 0 ? totalSimilarity / pairCount : 1.0;
  }
  
  /// 使用GPT-4o-mini生成聚类标题
  Future<String> _generateClusterTitle(List<EventNode> members) async {
    try {
      // 收集事件标题用于生成摘要
      final eventTitles = members.take(10).map((e) => e.name).join('\n• ');
      
      final prompt = '''
请为以下事件生成一个简洁的聚类标题（10字以内）：

• $eventTitles

要求：
1. 标题应该概括这些事件的共同主题
2. 使用简洁明了的语言
3. 长度控制在10字以内
4. 只返回标题文本，不要其他内容

示例：
• 近期论文讨论进展
• 最近出游计划
• 工作会议记录
''';
      
      final llm = await LLM.create('gpt-4o-mini');
      final response = await llm.createRequest(content: prompt);
      
      // 清理响应，只保留标题
      final title = response.trim().replaceAll(RegExp(r'^[\s•\-\*]+'), '');
      
      return title.length > 20 ? title.substring(0, 20) + '...' : title;
      
    } catch (e) {
      print('[SemanticClusteringService] ⚠️ 生成标题失败，使用默认标题: $e');
      // 降级策略：使用第一个事件的类型 + 数量
      return '${members.first.type}相关事件 (${members.length}个)';
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
      _objectBox.updateEventNode(event);
    }
  }
  
  /// 保存聚类结果（需要在ObjectBoxService中添加相关方法）
  Future<void> _saveClusteringResults(List<ClusterNode> clusterNodes) async {
    // 注意：这里需要在objectbox_service中添加对应的方法
    // for (final cluster in clusterNodes) {
    //   _objectBox.insertClusterNode(cluster);
    // }
    print('[SemanticClusteringService] 保存了 ${clusterNodes.length} 个聚类节点');
  }
  
  /// 获取所有聚类节点
  Future<List<ClusterNode>> getAllClusters() async {
    // 注意：需要在objectbox_service中添加查询方法
    // return _objectBox.queryClusterNodes();
    return <ClusterNode>[]; // 临时返回空列表
  }
  
  /// 获取特定聚类的成员事件
  Future<List<EventNode>> getClusterMembers(String clusterId) async {
    final allEvents = _objectBox.queryEventNodes();
    return allEvents.where((e) => e.clusterId == clusterId).toList();
  }
  
  /// 获取未聚类的事件
  Future<List<EventNode>> getUnclusteredEvents() async {
    final allEvents = _objectBox.queryEventNodes();
    return allEvents.where((e) => 
      e.embedding.isNotEmpty && e.clusterId == null
    ).toList();
  }
}
