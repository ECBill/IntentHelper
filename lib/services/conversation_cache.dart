import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:app/services/llm.dart';
import 'package:app/services/enhanced_kg_service.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:intl/intl.dart';

/// 缓存项优先级
enum CacheItemPriority {
  low(1),
  medium(2),
  high(3),
  critical(4),
  userProfile(5);

  const CacheItemPriority(this.value);
  final int value;
}

/// 缓存项类
class CacheItem {
  final String key;
  final String content;
  final double weight;
  final CacheItemPriority priority;
  final Set<String> relatedTopics;
  final DateTime createdAt;
  DateTime lastAccessedAt;
  int accessCount;
  double relevanceScore;
  final String category;
  final dynamic data;

  CacheItem({
    required this.key,
    required this.content,
    required this.priority,
    required this.relatedTopics,
    required this.createdAt,
    required this.relevanceScore,
    this.category = 'general',
    this.data,
  }) : lastAccessedAt = createdAt,
        accessCount = 1,
        weight = 1.0;

  void updateAccess() {
    lastAccessedAt = DateTime.now();
    accessCount++;
  }

  double calculateWeight() {
    final timeFactor = DateTime.now().difference(lastAccessedAt).inMinutes / 60.0;
    final accessFactor = accessCount.toDouble();
    final priorityFactor = priority.value.toDouble();
    final relevanceFactor = relevanceScore;

    return (priorityFactor * 2.0 + relevanceFactor + accessFactor * 0.5) / (timeFactor + 1.0);
  }
}

/// 对话摘要类
class ConversationSummary {
  final String summary;
  final DateTime createdAt;
  final List<String> keywords;

  ConversationSummary({
    required this.summary,
    required this.createdAt,
    required this.keywords,
  });
}

/// 对话上下文类
class ConversationContext {
  final String currentTopic;
  final List<String> activeKeywords;
  final DateTime lastUpdated;

  ConversationContext({
    required this.currentTopic,
    required this.activeKeywords,
    required this.lastUpdated,
  });
}

/// 用户个人上下文类
class UserPersonalContext {
  final Map<String, dynamic> personalInfo;
  final List<String> preferences;
  final DateTime lastUpdated;

  UserPersonalContext({
    required this.personalInfo,
    required this.preferences,
    required this.lastUpdated,
  });
}

class ConversationCache {
  static final ConversationCache _instance = ConversationCache._internal();
  factory ConversationCache() => _instance;
  ConversationCache._internal();

  final Map<String, CacheItem> _cache = {};
  final Queue<String> _recentQueries = Queue();
  bool _initialized = false;

  /// 初始化缓存系统
  Future<void> initialize() async {
    if (_initialized) return;

    print('[ConversationCache] 🚀 初始化对话缓存系统...');
    _initialized = true;
    print('[ConversationCache] ✅ 对话缓存系统初始化完成');
  }

  /// 处理背景对话
  Future<void> processBackgroundConversation(String text) async {
    if (!_initialized) await initialize();

    print('[ConversationCache] 📝 处理背景对话: "${text.substring(0, text.length > 30 ? 30 : text.length)}..."');

    // 简化实现：将对话添加到缓存
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    final cacheItem = CacheItem(
      key: key,
      content: text,
      priority: CacheItemPriority.medium,
      relatedTopics: _extractTopics(text),
      createdAt: DateTime.now(),
      relevanceScore: 0.5,
      category: 'conversation',
    );

    _cache[key] = cacheItem;
    _recentQueries.add(text);

    // 保持队列长度
    if (_recentQueries.length > 100) {
      _recentQueries.removeFirst();
    }
  }

  /// 获取快速响应
  Map<String, dynamic>? getQuickResponse(String query) {
    if (!_initialized) return null;

    // 简化实现：检查是否有相关缓存
    final relevantItems = _cache.values
        .where((item) => item.content.toLowerCase().contains(query.toLowerCase()))
        .toList();

    if (relevantItems.isEmpty) return null;

    return {
      'hasCache': true,
      'content': relevantItems.map((item) => item.content).toList(),
      'relevanceScores': relevantItems.map((item) => item.relevanceScore).toList(),
      'cacheHitCount': relevantItems.length,
      'personal_info': {},
      'focus_summary': [],
    };
  }

  /// 获取当前个人关注点摘要
  List<String> getCurrentPersonalFocusSummary() {
    return ['学习', '项目', '技术'];
  }

  /// 获取相关个人信息
  Map<String, dynamic> getRelevantPersonalInfoForGeneration() {
    return {
      'topics': getCurrentPersonalFocusSummary(),
      'recent_conversations': _recentQueries.take(5).toList(),
    };
  }

  /// 获取缓存统计
  Map<String, dynamic> getCacheStats() {
    return {
      'total_items': _cache.length,
      'recent_queries': _recentQueries.length,
      'initialized': _initialized,
    };
  }

  /// 获取所有缓存项
  List<CacheItem> getAllCacheItems() {
    return _cache.values.toList();
  }

  /// 按分类获取缓存项
  List<CacheItem> getCacheItemsByCategory(String category) {
    return _cache.values
        .where((item) => item.category == category)
        .toList();
  }

  /// 获取最近的对话摘要
  List<ConversationSummary> getRecentSummaries({int limit = 10}) {
    return _recentQueries
        .take(limit)
        .map((query) => ConversationSummary(
              summary: query,
              createdAt: DateTime.now(),
              keywords: _extractTopics(query).toList(),
            ))
        .toList();
  }

  /// 获取当前对话上下文
  ConversationContext? getCurrentConversationContext() {
    if (_recentQueries.isEmpty) return null;

    return ConversationContext(
      currentTopic: _recentQueries.last,
      activeKeywords: _extractTopics(_recentQueries.last).toList(),
      lastUpdated: DateTime.now(),
    );
  }

  /// 获取用户个人上下文
  UserPersonalContext? getUserPersonalContext() {
    return UserPersonalContext(
      personalInfo: getRelevantPersonalInfoForGeneration(),
      preferences: getCurrentPersonalFocusSummary(),
      lastUpdated: DateTime.now(),
    );
  }

  /// 获取主动交互建议
  Map<String, dynamic> getProactiveInteractionSuggestions() {
    return {
      'suggestions': ['继续之前的话题', '探索新的领域'],
      'confidence': 0.7,
    };
  }

  /// 获取缓存项详细信息
  Map<String, dynamic> getCacheItemDetails(String key) {
    final item = _cache[key];
    if (item == null) return {};

    return {
      'key': item.key,
      'content': item.content,
      'category': item.category,
      'created_at': item.createdAt.toIso8601String(),
      'access_count': item.accessCount,
      'relevance_score': item.relevanceScore,
    };
  }

  /// 清空缓存
  void clearCache() {
    _cache.clear();
    _recentQueries.clear();
    print('[ConversationCache] 🗑️ 缓存已清空');
  }

  /// 提取话题关键词
  Set<String> _extractTopics(String text) {
    final topics = <String>{};
    final content = text.toLowerCase();

    if (content.contains('学习')) topics.add('学习');
    if (content.contains('项目')) topics.add('项目');
    if (content.contains('技术')) topics.add('技术');
    if (content.contains('工作')) topics.add('工作');
    if (content.contains('flutter')) topics.add('flutter');

    return topics;
  }
}
