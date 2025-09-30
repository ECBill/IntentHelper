import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:objectbox/objectbox.dart';
import 'package:flutter/services.dart';
import '../models/todo_entity.dart';
import '../models/record_entity.dart';
import '../models/summary_entity.dart';
import '../models/event_entity.dart';
import '../models/event_relation_entity.dart';
import '../models/graph_models.dart';
import '../models/objectbox.g.dart';
import '../services/embedding_service.dart';
import '../services/objectbox_service.dart';

class ImportDataScreen extends StatefulWidget {
  const ImportDataScreen({Key? key}) : super(key: key);

  @override
  State<ImportDataScreen> createState() => _ImportDataScreenState();
}

class _ImportDataScreenState extends State<ImportDataScreen> {
  double _progress = 0.0;
  String _status = '';
  List<String> _problems = [];
  String? _jsonContent;
  bool _isImporting = false;

  // TODO: 替换为你的 ObjectBox Box 实例获取方式
  late final Box<TodoEntity> todoBox;
  late final Box<RecordEntity> recordBox;
  late final Box<SummaryEntity> summaryBox;
  late final Box<EventEntity> eventBox;
  late final Box<EventRelationEntity> eventRelationBox;
  late final Box<Node> nodeBox;

  @override
  void initState() {
    super.initState();
    todoBox = ObjectBoxService.todoBox;
    recordBox = ObjectBoxService.recordBox;
    summaryBox = ObjectBoxService.summaryBox;
    eventBox = ObjectBoxService.eventBox;
    eventRelationBox = ObjectBoxService.eventRelationEntityBox;
    nodeBox = ObjectBoxService.nodeBox;
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    String debugMsg = '';
    if (result == null) {
      setState(() {
        _status = 'FilePicker 未返回结果，可能是权限或系统问题';
        _jsonContent = null;
      });
      return;
    }
    debugMsg += 'result!=null; files.length=${result.files.length}; ';
    if (result.files.isEmpty) {
      setState(() {
        _status = '未选择任何文件（files 为空）';
        _jsonContent = null;
      });
      return;
    }
    final file = result.files.single;
    debugMsg += 'name=${file.name}; size=${file.size}; path=${file.path}; bytes=${file.bytes != null};';
    if (file.bytes != null) {
      try {
        final content = utf8.decode(file.bytes!);
        if (content.trim().isEmpty) {
          setState(() {
            _status = '文件内容为空（通过 bytes 读取）\n$debugMsg';
            _jsonContent = null;
          });
          return;
        }
        setState(() {
          _jsonContent = content;
          _status = '文件已选择（通过 bytes 读取）\n$debugMsg';
        });
        return;
      } catch (e) {
        setState(() {
          _status = '文件内容解码失败: $e\n$debugMsg';
            _jsonContent = null;
        });
        return;
      }
    } else if (file.path != null) {
      try {
        final f = File(file.path!);
        final content = await f.readAsString();
        if (content.trim().isEmpty) {
          setState(() {
            _status = '文件内容为空（通过 path 读取）\n$debugMsg';
            _jsonContent = null;
          });
          return;
        }
        setState(() {
          _jsonContent = content;
          _status = '文件已选择（通过 path 读取）\n$debugMsg';
        });
        return;
      } catch (e) {
        setState(() {
          _status = '读取文件失败: $e\n$debugMsg';
          _jsonContent = null;
        });
        return;
      }
    } else {
      setState(() {
        _status = '文件选择异常，bytes 和 path 都为 null\n$debugMsg';
        _jsonContent = null;
      });
      return;
    }
  }

  Future<void> _loadFromAssets() async {
    setState(() {
      _status = '正在读取内置 JSON 文件...';
      _jsonContent = null;
    });
    try {
      // 这里的路径要和 pubspec.yaml 里 assets 路径一致
      final content = await rootBundle.loadString('assets/objectbox_export_2025-09-28T19-32-21.439441.json');
      if (content.trim().isEmpty) {
        setState(() {
          _status = '内置 JSON 文件内容为空';
          _jsonContent = null;
        });
        return;
      }
      setState(() {
        _jsonContent = content;
        _status = '已加载内置 JSON 文件';
      });
    } catch (e) {
      setState(() {
        _status = '读取内置 JSON 文件失败: $e';
        _jsonContent = null;
      });
    }
  }

  Future<void> _importData() async {
    if (_jsonContent == null) {
      setState(() {
        _status = '请先选择 JSON 文件';
      });
      return;
    }
    setState(() {
      _isImporting = true;
      _progress = 0.0;
      _problems.clear();
      _status = '正在解析 JSON...';
    });
    try {
      final Map<String, dynamic> data = jsonDecode(_jsonContent!);
      final importTasks = [
        // {'key': 'todoEntities', 'box': todoBox, 'fromJson': TodoEntity.fromJson},
        // {'key': 'recordEntities', 'box': recordBox, 'fromJson': RecordEntity.fromJson},
        // {'key': 'summaryEntities', 'box': summaryBox, 'fromJson': SummaryEntity.fromJson},
        {'key': 'eventNodeEntities', 'box': nodeBox, 'fromJson': EventEntity.fromJson},
        // {'key': 'eventRelationEntities', 'box': eventRelationBox, 'fromJson': EventRelationEntity.fromJson},
        // {'key': 'nodeEntities', 'box': nodeBox, 'fromJson': NodeEntity.fromJson},
      ];
      int total = 0;
      int imported = 0;
      // 1. 预扫描所有导入对象，找到每类实体的最大 id
      final Map<String, int> maxIdMap = {};
      for (final task in importTasks) {
        List? list;
        try {
          list = data[task['key']] as List?;
        } catch (err) {
          _problems.add('解析 ${task['key']} 阶段出错: ${err.runtimeType}: $err');
          continue;
        }
        if (list == null) continue;
        int maxId = 0;
        for (final e in list) {
          if (task['key'] == 'nodeEntities') {
            final nodeEntity = NodeEntity.fromJson(e as Map<String, dynamic>);
            if (nodeEntity.id is int && nodeEntity.id > maxId) {
              maxId = nodeEntity.id;
            } else if (nodeEntity.id is String) {
              final parsedId = int.tryParse(nodeEntity.id as String);
              if (parsedId != null && parsedId > maxId) {
                maxId = parsedId;
              }
            }
          } else {
            final entity = (task['fromJson'] as Function)(e as Map<String, dynamic>);
            var id = (entity as dynamic).id;
            if (id is String) {
              id = int.tryParse(id) ?? 0;
              (entity as dynamic).id = id;
            }
            if (id != null && id is int && id > maxId) {
              maxId = id;
            }
          }
        }
        maxIdMap[task['key'] as String] = maxId;
      }
      // 2. 设置每个 box 的自增序列（如果需要）
      for (final task in importTasks) {
        final maxId = maxIdMap[task['key']] ?? 0;
        if (maxId > 0) {
          final box = task['box'];
          try {
            // 只有 int 类型主键的 box 才能设置 sequence
            if (task['key'] != 'nodeEntities') {
              (box as dynamic).idProperty.setSequence(maxId + 1);
              // 强制推进自增序列：插入一条临时数据再删掉
              final fromJson = task['fromJson'] as Function;
              final dummy = fromJson({
                'id': maxId,
                // 其它字段用默认或空值
              });
              box.put(dummy);
              box.remove(maxId);
              print('[ImportData] 设置 ${task['key']} 的自增序列为 ${maxId + 1} 并推进到 maxId');
            }
          } catch (e) {
            print('[ImportData] 设置 ${task['key']} 自增序列失败: $e');
          }
        }
      }
      // 统计所有导入任务的总条数
      total = 0;
      for (final task in importTasks) {
        final list = data[task['key']] as List?;
        if (list != null) total += list.length;
      }
      int processed = 0;
      for (final task in importTasks) {
        final list = data[task['key']] as List?;
        print('[ImportData] 任务 ${task['key']} 数据条数: \\${list?.length}');
        if (list == null) continue;
        print('[ImportData] 开始导入 \u001b[1m${task['key']}\u001b[0m，共 ${list.length} 条');
        for (int i = 0; i < list.length; i++) {
          if (task['key'] == 'eventNodeEntities' && i >= 20) {
            print('[ImportData] eventNodeEntities 调试终止：只处理前20条');
            break;
          }
          final e = list[i];
          if (task['key'] == 'eventNodeEntities') {
            print('[ImportData] eventNodeEntities 正在处理: \\${e.toString()}');
          }
          try {
            if (task['key'] == 'eventNodeEntities') {
              // EventEntity -> EventNode 字段映射
              final entity = (task['fromJson'] as Function)(e as Map<String, dynamic>);
              String nodeId = entity.id?.toString() ?? '';
              if (nodeId.isEmpty || nodeId == '0') {
                nodeId = 'eventnode_' + DateTime.now().millisecondsSinceEpoch.toString() + '_' + (1000 + (10000 * (DateTime.now().microsecond % 1000))).toString();
                _problems.add('eventNodeEntities 原始 id 非法，已分配新 id=$nodeId');
              }
              // 检查唯一约束冲突
              final box = task['box'] as Box<EventNode>;
              final existingNode = box.query(EventNode_.id.equals(nodeId)).build().findFirst();
              if (existingNode != null) {
                _problems.add('eventNodeEntities 唯一约束冲突，已跳过 id=$nodeId');
                print('[ImportData] eventNodeEntities 唯一约束冲突，已跳过 id=$nodeId');
                continue;
              }
              // 构造 EventNode
              final eventNode = EventNode(
                id: nodeId,
                name: entity.title ?? '',
                type: entity.category ?? '',
                startTime: entity.timestamp != null ? DateTime.fromMillisecondsSinceEpoch(entity.timestamp!) : null,
                description: entity.description,
                location: entity.location,
                // 其它字段可根据需要补充
              );
              // 生成 embedding
              try {
                final embedding = await EmbeddingService().generateEventEmbedding(eventNode);
                if (embedding != null && embedding.isNotEmpty) {
                  eventNode.embedding = embedding;
                  print('[ImportData] EventNode id=$nodeId embedding 生成成功');
                } else {
                  _problems.add('eventNodeEntities id=$nodeId 未能生成 embedding');
                  print('[ImportData] EventNode id=$nodeId embedding 生成失败');
                }
              } catch (err) {
                _problems.add('eventNodeEntities id=$nodeId 生成 embedding 异常: ${err.runtimeType}: $err');
                print('[ImportData] EventNode id=$nodeId embedding 生成异常: $err');
              }
              // 写入 nodeBox
              try {
                print('[ImportData] EventNode id=$nodeId 尝试写入 nodeBox...');
                await box.putAsync(eventNode);
                print('[ImportData] EventNode id=$nodeId 写入 nodeBox 成功');
                imported++;
                print('[ImportData] EventNode id=$nodeId imported++ 完成');
              } catch (err) {
                print('[ImportData] EventNode id=$nodeId 写入 nodeBox 失败: $err');
                _problems.add('eventNodeEntities 导入失败，id=$nodeId，错误: '
                  '${err.runtimeType}: $err\n数据: ${e.toString()}');
              }
            } else if (task['key'] == 'nodeEntities') {
              final nodeEntity = NodeEntity.fromJson(e as Map<String, dynamic>);
              String? nodeId = nodeEntity.id?.toString();
              // 如果 id 为空或为 "0"，分配新 id
              if (nodeId == null || nodeId == '' || nodeId == '0') {
                final newId = DateTime.now().millisecondsSinceEpoch.toString() + '_' + (1000 + (10000 * (new DateTime.now().microsecond % 1000))).toString();
                _problems.add('nodeEntities 原始 id=$nodeId 非法，已分配新 id=$newId');
                nodeId = newId;
              }
              final box = task['box'] as Box<Node>;
              // 检查唯一约束冲突（Node.id）
              final existingNode = box.query(Node_.id.equals(nodeId)).build().findFirst();
              if (existingNode != null) {
                _problems.add('nodeEntities 唯一约束冲突，已跳过 id=$nodeId');
                continue;
              }
              final node = Node(
                id: nodeId,
                name: nodeEntity.label ?? '',
                type: nodeEntity.properties != null && nodeEntity.properties!['type'] != null
                    ? nodeEntity.properties!['type'].toString()
                    : '',
              );
              box.put(node);
              imported++;
            } else if (task['key'] == 'eventRelationEntities') {
              final entity = (task['fromJson'] as Function)(e as Map<String, dynamic>);
              var id = (entity as dynamic).id;
              if (id is String) {
                final parsed = int.tryParse(id);
                if (parsed == null) {
                  _problems.add('${task['key']} id 字段无法转换为 int，原始 id=$id，数据: ${e.toString()}');
                  continue;
                }
                id = parsed;
                try {
                  (entity as dynamic).id = id;
                } catch (err) {
                  _problems.add('${task['key']} id 字段为 final，无法赋值，原始 id=$id，数据: ${e.toString()}');
                  continue;
                }
              }
              if (id is! int) {
                _problems.add('${task['key']} id 字段类型错误，期望 int，实际 ${id.runtimeType}，数据: ${e.toString()}');
                continue;
              }
              final box = task['box'] as Box;
              // 检查主键冲突
              if (id != null && id != 0 && box.get(id) != null) {
                _problems.add('${task['key']} 主键冲突，已跳过 id=$id');
                continue;
              }
              try {
                box.put(entity);
                imported++;
              } catch (err) {
                if (err.toString().contains('Unique constraint')) {
                  _problems.add('${task['key']} 唯一约束冲突，已跳过 id=$id');
                  continue;
                } else {
                  _problems.add('${task['key']} 导入失败，id=$id，错误: '
                    '${err.runtimeType}: $err\n数据: ${e.toString()}');
                }
              }
            } else {
              final entity = (task['fromJson'] as Function)(e as Map<String, dynamic>);
              var id = (entity as dynamic).id;
              // 类型检查与转换
              if (id is String) {
                final parsed = int.tryParse(id);
                if (parsed == null) {
                  _problems.add('${task['key']} id 字段无法转换为 int，原始 id=$id，数据: ${e.toString()}');
                  continue;
                }
                id = parsed;
                // 尝试赋值，如果失败则报错
                try {
                  (entity as dynamic).id = id;
                } catch (err) {
                  _problems.add('${task['key']} id 字段为 final，无法赋值，原始 id=$id，数据: ${e.toString()}');
                  continue;
                }
              }
              if (id is! int) {
                _problems.add('${task['key']} id 字段类型错误，期望 int，实际 ${id.runtimeType}，数据: ${e.toString()}');
                continue;
              }
              final box = task['box'] as Box;
              // 检查主键冲突
              if (id != null && id != 0 && box.get(id) != null) {
                _problems.add('${task['key']} 主键冲突，已跳过 id=$id');
                continue;
              }
              // 不能再检查 idProperty/sequence，直接尝试 put
              try {
                box.put(entity);
                imported++;
              } catch (err) {
                // 检查是否为自增序列冲突
                if (err is ArgumentError && err.toString().contains('ID is higher or equal to internal ID sequence')) {
                  try {
                    (entity as dynamic).id = 0;
                    box.put(entity);
                    imported++;
                    _problems.add('${task['key']} id=$id 因自增序列冲突已自动分配新id，原始数据: ${e.toString()}');
                  } catch (err2) {
                    _problems.add('${task['key']} 导入失败，id=$id，错误: '
                      '${err2.runtimeType}: $err2\n数据: ${e.toString()}');
                  }
                } else {
                  _problems.add('${task['key']} 导入失败，id=$id，错误: '
                    '${err.runtimeType}: $err\n数据: ${e.toString()}');
                }
              }
            }
          } catch (err) {
            _problems.add('${task['key']} 解析或导入异常: ${err.runtimeType}: $err\n数据: ${e.toString()}');
          }
          processed++;
          if (processed % 10 == 0 || processed == total) {
            print('[ImportData] 已处理 $processed/$total 条');
            setState(() {
              _progress = processed / total;
              _status = '已导入 $imported/$total 条';
            });
          }
        }
        print('[ImportData] 完成导入 ${task['key']}');
      }
      print('[ImportData] 全部导入完成，成功导入 $imported/$total 条');
      setState(() {
        _progress = 1.0;
        _status = '导入完成，共导入 $imported/$total 条';
      });
    } catch (e, stack) {
      setState(() {
        _status = '解析或导入失败: $e';
        _isImporting = false;
        _problems.add('全局异常: [31m${e.runtimeType}: $e\n$stack[0m');
      });
    }
    setState(() {
      _isImporting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入本地数据')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isImporting ? null : _pickFile,
                    child: const Text('选择 JSON 文件'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isImporting ? null : _loadFromAssets,
                    child: const Text('从内置文件导入'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_status),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_jsonContent != null && !_isImporting) ? _importData : null,
              child: const Text('开始导入'),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 16),
            const Text('导入中遇到的问题：'),
            Expanded(
              child: ListView.builder(
                itemCount: _problems.length,
                itemBuilder: (context, index) => Text(_problems[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
