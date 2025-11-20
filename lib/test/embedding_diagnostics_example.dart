/// Example usage of embedding diagnostics
/// 
/// This demonstrates how to use the analyzeEmbeddings function to diagnose
/// embedding quality issues in Chinese text processing.

import 'package:app/services/embedding_service.dart';
import 'package:app/models/graph_models.dart';

Future<void> runEmbeddingDiagnostics() async {
  final service = EmbeddingService();
  
  // Create sample events with Chinese text
  final events = [
    EventNode(
      id: '1',
      name: '使用美团进行外卖点餐',
      type: '外卖订单',
      description: '点了热干面和关东煮',
    ),
    EventNode(
      id: '2',
      name: '讨论热干面的情况',
      type: '餐饮讨论',
      description: '和朋友讨论热干面的做法',
    ),
    EventNode(
      id: '3',
      name: '民宿住宿',
      type: '住宿',
      description: '在民宿住了一晚',
    ),
    EventNode(
      id: '4',
      name: '讨论外卖餐厅',
      type: '餐饮讨论',
      description: '讨论附近的外卖餐厅选择',
    ),
  ];
  
  // Generate embeddings for all events
  for (final event in events) {
    final embedding = await service.generateEventEmbedding(event);
    service.setEventEmbedding(event, embedding ?? []);
  }
  
  // Run diagnostics
  final analysis = await service.analyzeEmbeddings(events);
  
  print('=== Embedding Quality Analysis ===');
  print('Total events: ${analysis['total_events']}');
  print('Null embeddings: ${analysis['null_embeddings']}');
  print('Zero embeddings: ${analysis['zero_embeddings']}');
  print('Unique embeddings: ${analysis['unique_embeddings']}');
  print('');
  
  final simStats = analysis['similarity_stats'] as Map<String, dynamic>;
  print('=== Similarity Statistics ===');
  print('Sample size: ${simStats['sample_size']}');
  print('Average similarity: ${simStats['avg_similarity']}');
  print('Max similarity: ${simStats['max_similarity']}');
  print('Min similarity: ${simStats['min_similarity']}');
  print('');
  
  print('=== Top Duplicate Embeddings ===');
  final topDuplicates = analysis['top_duplicates'] as List;
  for (var i = 0; i < topDuplicates.length && i < 5; i++) {
    final dup = topDuplicates[i];
    print('Hash: ${dup['hash'].substring(0, 8)}... Count: ${dup['count']}');
  }
  print('');
  
  print('=== Potential Issues ===');
  final issues = analysis['potential_issues'] as List<String>;
  for (final issue in issues) {
    print('- $issue');
  }
  print('');
  
  // Test search with a query
  print('=== Search Test: "外卖" ===');
  final results = await service.searchSimilarEventsByText(
    '外卖',
    events,
    topK: 5,
    threshold: 0.0,
  );
  
  for (var i = 0; i < results.length; i++) {
    final result = results[i];
    final event = result['event'] as EventNode;
    final similarity = result['similarity'] as double;
    print('${i + 1}. ${event.name} (similarity: ${similarity.toStringAsFixed(3)})');
  }
  print('');
  
  // Test hybrid search (if available)
  print('=== Hybrid Search Test: "外卖" ===');
  final hybridResults = await service.searchSimilarEventsHybridByText(
    '外卖',
    events,
    topK: 5,
    cosineThreshold: 0.0,
  );
  
  for (var i = 0; i < hybridResults.length; i++) {
    final result = hybridResults[i];
    final event = result['event'] as EventNode;
    final score = result['score'] as double;
    final cos = result['similarity'] as double;
    final lex = result['lexical'] as double;
    print('${i + 1}. ${event.name}');
    print('   Score: ${score.toStringAsFixed(3)} (cos: ${cos.toStringAsFixed(3)}, lex: ${lex.toStringAsFixed(3)})');
  }
}

/// Comparison of keyword search vs vector search
Future<void> compareSearchMethods() async {
  final service = EmbeddingService();
  
  // Sample data similar to the problem description
  final events = [
    EventNode(
      id: '1',
      name: '讨论热干面的情况',
      type: '餐饮讨论',
      description: '热干面是武汉特色小吃',
    ),
    EventNode(
      id: '2',
      name: '使用美团进行外卖点餐',
      type: '外卖订单',
      description: '点了外卖',
    ),
    EventNode(
      id: '3',
      name: '点用餐外卖',
      type: '外卖订单',
      description: '点了晚餐外卖',
    ),
    EventNode(
      id: '4',
      name: '讨论外卖餐厅',
      type: '餐饮讨论',
      description: '讨论外卖餐厅的选择',
    ),
    EventNode(
      id: '5',
      name: '吃关东煮',
      type: '用餐',
      description: '在便利店买了关东煮',
    ),
    EventNode(
      id: '8',
      name: '民宿住宿',
      type: '住宿',
      description: '在民宿住宿一晚',
    ),
    EventNode(
      id: '10',
      name: '讨论对伴侣的态度',
      type: '情感讨论',
      description: '和朋友讨论伴侣相处',
    ),
  ];
  
  // Generate embeddings
  for (final event in events) {
    final embedding = await service.generateEventEmbedding(event);
    service.setEventEmbedding(event, embedding ?? []);
  }
  
  final query = '外卖';
  
  // Keyword search (manual)
  print('=== Keyword Search: "$query" ===');
  int keywordMatches = 0;
  for (final event in events) {
    final text = event.getEmbeddingText().toLowerCase();
    if (text.contains(query)) {
      keywordMatches++;
      print('- ${event.name}');
    }
  }
  print('Total keyword matches: $keywordMatches');
  print('');
  
  // Vector search
  print('=== Vector Search: "$query" ===');
  final vectorResults = await service.searchSimilarEventsByText(
    query,
    events,
    topK: 5,
    threshold: 0.0,
  );
  
  for (var i = 0; i < vectorResults.length; i++) {
    final result = vectorResults[i];
    final event = result['event'] as EventNode;
    final similarity = result['similarity'] as double;
    print('${i + 1}. ${event.name} (${similarity.toStringAsFixed(3)})');
  }
}
