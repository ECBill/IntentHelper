import 'dart:async';
import 'package:app/models/llm_config.dart';
import 'package:app/models/todo_entity.dart';
import 'package:app/services/embeddings_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/record_entity.dart';
import '../models/summary_entity.dart';
import '../models/speaker_entity.dart';
import '../models/event_entity.dart';
import '../models/event_relation_entity.dart';

import '../models/objectbox.g.dart';
import '../models/graph_models.dart';

class ObjectBoxService {
  static late final Store store;
  static late final Box<RecordEntity> recordBox;
  static late final Box<SummaryEntity> summaryBox;
  static late final Box<LlmConfigEntity> configBox;
  static late final Box<SpeakerEntity> speakerBox;
  static late final Box<TodoEntity> todoBox;
  static late final Box<EventEntity> eventBox;
  static late final Box<EventRelationEntity> eventRelationBox;
  static late final Box<Node> nodeBox;
  static late final Box<Edge> edgeBox;
  static late final Box<Attribute> attributeBox;
  static late final Box<Context> contextBox;

  // Singleton pattern to ensure only one instance of ObjectBoxService
  static final ObjectBoxService _instance = ObjectBoxService._internal();

  factory ObjectBoxService() => _instance;

  ObjectBoxService._internal();

  static Future<void> initialize() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = p.join(docsDir.path, 'person-db');

    if (Store.isOpen(dbDir)) {
      // applicable when store is from other isolate
      store = Store.attach(getObjectBoxModel(), dbDir);
    } else {
      try {
        store = await openStore(directory: dbDir);
      } catch (error) {
        // If the store cannot be opened, it might already be open.
        // Try to attach to it instead.
        store = Store.attach(getObjectBoxModel(), dbDir);
      }
    }

    recordBox = Box<RecordEntity>(store);
    summaryBox = Box<SummaryEntity>(store);
    configBox = Box<LlmConfigEntity>(store);
    speakerBox = Box<SpeakerEntity>(store);
    todoBox = Box<TodoEntity>(store);
    eventBox = Box<EventEntity>(store);
    eventRelationBox = Box<EventRelationEntity>(store);
    nodeBox = Box<Node>(store);
    edgeBox = Box<Edge>(store);
    attributeBox = Box<Attribute>(store);
    contextBox = Box<Context>(store);
  }

  void insertRecord(RecordEntity record, String category) {
    record.category = category;
    recordBox.put(record);
  }

  void insertDefaultRecord(RecordEntity record) {
    insertRecord(record, RecordEntity.categoryDefault);
  }

  void insertDialogueRecord(RecordEntity record) {
    insertRecord(record, RecordEntity.categoryDialogue);
  }

  void insertMeetingRecord(RecordEntity record) {
    insertRecord(record, RecordEntity.categoryMeeting);
  }

  List<RecordEntity>? getMeetingRecordsByTimeRange(startTime, endTime) {
    final queryBuilder = recordBox
        .query(RecordEntity_.createdAt
        .between(startTime, endTime)
        .and(RecordEntity_.category.equals(RecordEntity.categoryMeeting)))
        .order(RecordEntity_.createdAt);
    final query = queryBuilder.build();
    query.limit = 1000;
    return query.find();
  }

  Future<void> insertRecords(List<RecordEntity> vectors) async {
    recordBox.putMany(vectors);
  }

  RecordEntity? getLastRecord() {
    return recordBox.isEmpty() ? null : recordBox.getAll().last;
  }

  List<RecordEntity>? getRecords() {
    return recordBox.getAll();
  }

  List<RecordEntity>? getChatRecords({int offset = 0, int limit = 50}) {
    final queryBuilder = recordBox.query().order(RecordEntity_.createdAt, flags: Order.descending);

    final query = queryBuilder.build();
    query.offset = offset;
    query.limit = limit;
    return query.find();
  }

  // 获取最近的记录，用于声纹识别动态阈值计算
  List<RecordEntity>? getRecentRecords({int limit = 50}) {
    final queryBuilder = recordBox.query().order(RecordEntity_.createdAt, flags: Order.descending);
    final query = queryBuilder.build();
    query.limit = limit;
    return query.find();
  }

  List<RecordEntity>? getTermRecords() {
    final queryBuilder = recordBox.query().order(RecordEntity_.createdAt, flags: Order.descending);
    final query = queryBuilder.build();
    query.limit = 8;
    return query.find().reversed.toList();
  }

  List<RecordEntity>? getChatRecordsByTimeRange(startTime, endTime) {
    final queryBuilder = recordBox
        .query(RecordEntity_.createdAt.between(startTime, endTime))
        .order(RecordEntity_.createdAt, flags: Order.descending);
    final query = queryBuilder.build();
    query.limit = 1000;
    return query.find();
  }

  List<RecordEntity> getRecordsBySubject(String subject) {
    final summaryQuery = summaryBox.query(SummaryEntity_.subject.equals(subject, caseSensitive: false)).build();
    final summaryResults = summaryQuery.find();

    // If no summaries are found, return an empty list
    if (summaryResults.isEmpty) return [];

    final List<RecordEntity> finalRecords = [];

    for (final summary in summaryResults) {
      final recordQuery = recordBox.query(RecordEntity_.createdAt.between(summary.startTime, summary.endTime)).build();

      final recordResults = recordQuery.find();

      finalRecords.addAll(recordResults);
    }

    return finalRecords;
  }

  List<RecordEntity> getRecordsByTimeRange(int startTime, int endTime) {
    return recordBox.query(RecordEntity_.createdAt.between(startTime, endTime)).build().find();
  }

  List<Map<RecordEntity, double>> getSimilarRecordsByContents(List<double> queryVector, int topK) {
    try {
      // 暂时禁用向量搜索，因为ObjectBox版本不支持
      print('[ObjectBoxService] Vector search not supported for RecordEntity');
      return [];
    } catch (e) {
      print('[ObjectBoxService] Vector search error: $e');
      return [];
    }
  }

  List<Map<RecordEntity, double>> getSimilarRecordsBySummaries(List<double> queryVector, int topK) {
    try {
      // 暂时禁用向量搜索，因为ObjectBox版本不支持
      print('[ObjectBoxService] Vector search not supported for SummaryEntity');
      return [];
    } catch (e) {
      print('[ObjectBoxService] Vector search error: $e');
      return [];
    }
  }

  Future<void> deleteAllRecords() async {
    recordBox.removeAll();
  }

  Future<void> deleteAllSummaries() async {
    summaryBox.removeAll();
  }

  Future<void> deleteSummary(int id) async {
    summaryBox.remove(id);
  }

  Future<void> deleteSummaries(List<int> ids) async {
    summaryBox.removeMany(ids);
  }

  Future<void> insertConfig(LlmConfigEntity llmConfig) async {
    configBox.put(llmConfig);
  }

  Future<void> insertConfigs(List<LlmConfigEntity> vectors) async {
    configBox.putMany(vectors);
  }

  LlmConfigEntity? getLastConfig() {
    return configBox.isEmpty() ? null : configBox.getAll().last;
  }

  List<LlmConfigEntity>? getConfigs() {
    return configBox.getAll();
  }

  LlmConfigEntity? getConfigsByModel(String model) {
    final configQuery = configBox.query(LlmConfigEntity_.model.equals(model)).build();

    return configQuery.findFirst();
  }

  LlmConfigEntity? getConfigsByProvider(String provider) {
    final configQuery = configBox.query(LlmConfigEntity_.provider.equals(provider)).build();

    return configQuery.findFirst();
  }

  Future<void> deleteAllConfigs() async {
    configBox.removeAll();
  }

  Future<void> insertSummary(SummaryEntity record) async {
    summaryBox.put(record);
  }

  Future<void> insertSummaries(List<SummaryEntity> vectors) async {
    summaryBox.putMany(vectors);
  }

  List<SummaryEntity>? getSummaries() {
    return summaryBox.getAll();
  }

  List<SummaryEntity>? getMeetingSummaries() {
    List<SummaryEntity>? list =
    summaryBox.isEmpty() ? null : summaryBox.query(SummaryEntity_.isMeeting.equals(true)).build().find();
    return list;
  }

  List<SummaryEntity>? getDailySummaries() {
    return summaryBox.isEmpty() ? null : summaryBox.query(SummaryEntity_.isMeeting.equals(false)).build().find();
  }

  SummaryEntity? getLastSummary({bool isMeeting = false}) {
    if (isMeeting) {
      final results = summaryBox
          .query(SummaryEntity_.isMeeting.equals(true))
          .order(SummaryEntity_.createdAt, flags: Order.descending)
          .build()
          .find();
      return results.isEmpty ? null : results.last;
    }
    return summaryBox.isEmpty() ? null : summaryBox.getAll().last;
  }

  List<SummaryEntity>? getSummariesBySubject(String subject) {
    return summaryBox.isEmpty() ? null : summaryBox.query(SummaryEntity_.subject.equals(subject)).build().find();
  }

  List<SummaryEntity>? getSummariesByKeyword(String keyword) {
    return summaryBox.isEmpty()
        ? null
        : summaryBox
        .query(SummaryEntity_.content.contains(keyword).or(SummaryEntity_.subject.contains(keyword)))
        .build()
        .find();
  }

  List<Map<SummaryEntity, double>> getSimilarSummariesByContents(List<double> queryVector, int topK) {
    try {
      // 暂时禁用向量搜索，因为ObjectBox版本不支持
      print('[ObjectBoxService] Vector search not supported for SummaryEntity');
      return [];
    } catch (e) {
      print('[ObjectBoxService] Vector search error: $e');
      return [];
    }
  }

  // Future<List<SummaryEntity>?> getSimilarSummariesWithConstraints(List<String> keywords, double threshold,
  //     {int? time, String? level}) async {
  //   if ((time == null) != (level == null)) {
  //     throw ArgumentError("Both 'time' and 'level' must be provided together, or neither should be provided.");
  //   }
  //
  //   Embeddings embeddings = await Embeddings.create();
  //   final keywordsVec = await embeddings.getMultipleEmbeddings(keywords);
  //   if (keywordsVec == null) return null;
  //
  //   Condition<SummaryEntity>? conditions;
  //
  //   if (time != null) {
  //     final timeRange = (level == 'mm')
  //         ? SummaryEntity_.startTime.lessOrEqual(time).and(SummaryEntity_.endTime.greaterOrEqual(time))
  //         : SummaryEntity_.startTime.between(time, time + 24 * 60 * 60 * 1000);
  //
  //     conditions = timeRange;
  //   }
  //
  //   Condition<SummaryEntity> similarityConditions = SummaryEntity_.vector.nearestNeighborsF32(keywordsVec[0], 5);
  //
  //   for (int i = 1; i < keywordsVec.length; i++) {
  //     similarityConditions = similarityConditions.or(SummaryEntity_.vector.nearestNeighborsF32(keywordsVec[i], 5));
  //   }
  //
  //   final results = summaryBox
  //       .query(conditions == null ? similarityConditions : conditions.and(similarityConditions))
  //       .build()
  //       .findWithScores();
  //
  //   return results.where((result) => result.score > threshold).map((result) => result.object).toList();
  // }

  List<SpeakerEntity>? getUserSpeaker() {
    return speakerBox.getAll();
  }

  Future<void> insertSpeaker(SpeakerEntity speaker) async {
    speakerBox.put(speaker);
  }

  Future<void> deleteAllSpeakers() async {
    speakerBox.removeAll();
  }

  Future<void> createTodo(TodoEntity todo) async {
    todoBox.put(todo);
  }

  Future<void> createTodos(List<TodoEntity> todos) async {
    todoBox.putMany(todos);
  }

  List<TodoEntity>? getAllTodos() {
    return todoBox.getAll();
  }

  List<TodoEntity>? getTodosByStatus(Status status) {
    return todoBox
        .query(TodoEntity_.statusIndex.equals(status.index))
        .order(TodoEntity_.createdAt, flags: Order.descending)
        .build()
        .find();
  }

  List<TodoEntity>? getTodosByKeyword(String keyword) {
    return todoBox.query(TodoEntity_.task.equals(keyword).or(TodoEntity_.detail.equals(keyword))).build().find();
  }

  TodoEntity? getLastTodo() {
    return todoBox.isEmpty() ? null : todoBox.getAll().last;
  }

  void sortTodosByDeadline(List<TodoEntity> todos, {bool ascending = true}) {
    todos.sort((a, b) {
      int comparisonResult = a.deadline!.compareTo(b.deadline!);
      return ascending ? comparisonResult : -comparisonResult;
    });
  }

  void sortTodosByCreatedAt(List<TodoEntity> todos, {bool ascending = true}) {
    todos.sort((a, b) {
      int comparisonResult = a.createdAt!.compareTo(b.createdAt!);
      return ascending ? comparisonResult : -comparisonResult;
    });
  }

  Future<void> updateTodo(int id, String content, String? detail, int? deadline) async {
    TodoEntity? todo = todoBox.get(id);
    if (todo != null) {
      todo.task = content;
      todo.detail = detail;
      todo.deadline = deadline;
      todoBox.put(todo);
    }
  }

  Future<void> updateTodoStatus(int id, Status status) async {
    TodoEntity? todo = todoBox.get(id);
    if (todo != null) {
      todo.status = status;
      todoBox.put(todo);
    }
  }

  Future<void> updateSummaryTitle(int id, String title) async {
    SummaryEntity? summary = summaryBox.get(id);
    if (summary != null) {
      summary.title = title;
      summaryBox.put(summary);
    }
  }

  Future<void> toggleStared(int id) async {
    TodoEntity? todo = todoBox.get(id);
    if (todo != null) {
      todo.clock = !todo.clock;
      todoBox.put(todo);
    }
  }

  Future<void> updateTodoDeadline(int id, int deadline) async {
    TodoEntity? todo = todoBox.get(id);
    if (todo != null) {
      todo.deadline = deadline;
    }
  }

  Future<void> deleteAllTodos() async {
    todoBox.removeAll();
  }

  Future<void> deleteTodos(List<TodoEntity> todos) async {
    for (TodoEntity todo in todos) {
      todoBox.remove(todo.id);
    }
  }

  // ========== 知识图谱相关操作 ==========

  // Node
  Node? findNodeByNameType(String name, String type) {
    final query = nodeBox.query(Node_.name.equals(name).and(Node_.type.equals(type))).build();
    return query.findFirst();
  }
  void insertNode(Node node) {
    nodeBox.put(node);
  }
  List<Node> queryNodes() {
    return nodeBox.getAll();
  }

  // Edge
  void insertEdge(Edge edge) {
    edgeBox.put(edge);
  }
  List<Edge> queryEdges({String? source, String? target}) {
    var qb = edgeBox.query();
    if (source != null) {
      qb = edgeBox.query(Edge_.source.equals(source));
    }
    if (target != null) {
      qb = edgeBox.query(Edge_.target.equals(target));
    }
    return qb.build().find();
  }

  // Attribute
  void insertAttribute(Attribute attr) {
    attributeBox.put(attr);
  }
  List<Attribute> queryAttributes({String? nodeId}) {
    var qb = attributeBox.query();
    if (nodeId != null) {
      qb = attributeBox.query(Attribute_.nodeId.equals(nodeId));
    }
    return qb.build().find();
  }

  // 清空所有节点
  Future<void> clearEvents() async {
    nodeBox.removeAll();
  }
  // 清空所有边
  Future<void> clearEventRelations() async {
    edgeBox.removeAll();
  }
}
