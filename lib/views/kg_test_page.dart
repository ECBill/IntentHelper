import 'package:flutter/material.dart';
import 'package:app/services/chat_manager.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/models/graph_models.dart';

class KGTestPage extends StatefulWidget {
  const KGTestPage({Key? key}) : super(key: key);

  @override
  State<KGTestPage> createState() => _KGTestPageState();
}

class _KGTestPageState extends State<KGTestPage> {
  final TextEditingController _inputController = TextEditingController();
  final ChatManager _chatManager = ChatManager();
  String _result = '';
  List<Node> _allNodes = [];
  List<Edge> _allEdges = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadKGData();
    _initChatManager();
  }

  Future<void> _initChatManager() async {
    try {
      await _chatManager.init(selectedModel: 'gpt-4o-mini', systemPrompt: '你是一个智能助手');
    } catch (e) {
      print('初始化ChatManager失败: $e');
    }
  }

  Future<void> _loadKGData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final objectBox = ObjectBoxService();
      _allNodes = objectBox.queryNodes();
      _allEdges = objectBox.queryEdges();
    } catch (e) {
      print('加载知识图谱数据失败: $e');
      _allNodes = [];
      _allEdges = [];
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _testBuildInputWithKG() async {
    if (_inputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入测试文本')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '';
    });

    try {
      // 调试信息：显示详细的处理步骤
      final userInput = _inputController.text;

      // 1. 提取关键词
      final keywordReg = RegExp(r'[\u4e00-\u9fa5A-Za-z0-9_]+');
      final keywords = keywordReg.allMatches(userInput).map((m) => m.group(0)!).toSet().toList();

      // 2. 查询相关节点
      final objectBox = ObjectBoxService();
      final allNodes = objectBox.queryNodes();
      final relatedNodes = <Node>[];

      for (final keyword in keywords) {
        for (final node in allNodes) {
          if (node.name.contains(keyword)) {
            relatedNodes.add(node);
          }
        }
      }

      // 3. 构建调试信息
      String debugInfo = '=== 调试信息 ===\n';
      debugInfo += '输入文本: $userInput\n';
      debugInfo += '提取的关键词: $keywords\n';
      debugInfo += '数据库中的节点数: ${allNodes.length}\n';
      debugInfo += '匹配到的相关节点数: ${relatedNodes.length}\n';

      if (relatedNodes.isNotEmpty) {
        debugInfo += '相关节点:\n';
        for (var node in relatedNodes) {
          debugInfo += '  - ${node.name} (${node.type})\n';
        }
      }

      debugInfo += '\n=== buildInputWithKG 结果 ===\n';

      // 4. 调用原函数
      final result = await _chatManager.buildInputWithKG(userInput);

      setState(() {
        _result = debugInfo + result;
      });
    } catch (e) {
      setState(() {
        _result = '错误: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addTestData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final objectBox = ObjectBoxService();

      // 添加一些测试节点
      final testNodes = [
        Node(
          id: 'phone_iphone15',
          name: 'iPhone 15',
          type: '手机',
          attributes: {'品牌': 'Apple', '价格': '5999', '存储': '128GB'},
        ),
        Node(
          id: 'phone_xiaomi14',
          name: '小米14',
          type: '手机',
          attributes: {'品牌': '小米', '价格': '3999', '存储': '256GB'},
        ),
        Node(
          id: 'person_张三',
          name: '张三',
          type: '人',
          attributes: {'年龄': '25', '职业': '程序员'},
        ),
        Node(
          id: 'event_购买',
          name: '购买',
          type: '事件',
          attributes: {'时间': '2024-01-15'},
        ),
      ];

      // 添加测试边
      final testEdges = [
        Edge(
          source: 'person_张三',
          relation: '购买',
          target: 'phone_iphone15',
          context: 'test_context',
          timestamp: DateTime.now(),
        ),
        Edge(
          source: 'person_张三',
          relation: '考虑',
          target: 'phone_xiaomi14',
          context: 'test_context',
          timestamp: DateTime.now(),
        ),
      ];

      // 插入数据
      for (final node in testNodes) {
        final existing = objectBox.findNodeByNameType(node.name, node.type);
        if (existing == null) {
          objectBox.insertNode(node);
        }
      }

      for (final edge in testEdges) {
        objectBox.insertEdge(edge);
      }

      await _loadKGData();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('测试数据添加成功')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加测试数据失败: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _clearAllData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 清空所有知识图谱数据
      ObjectBoxService.nodeBox.removeAll();
      ObjectBoxService.edgeBox.removeAll();
      ObjectBoxService.attributeBox.removeAll();

      await _loadKGData();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所有数据已清空')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清空数据失败: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识图谱测试'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 数据统计
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '知识图谱数据统计',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text('节点数量: ${_allNodes.length}'),
                          Text('边数量: ${_allEdges.length}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _addTestData,
                        child: const Text('添加测试数据'),
                      ),
                      ElevatedButton(
                        onPressed: _clearAllData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('清空所有数据'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 测试输入
                  TextField(
                    controller: _inputController,
                    decoration: const InputDecoration(
                      labelText: '输入测试文本',
                      hintText: '例如: 我想买一个iPhone 15',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),

                  ElevatedButton(
                    onPressed: _testBuildInputWithKG,
                    child: const Text('测试 buildInputWithKG'),
                  ),
                  const SizedBox(height: 16),

                  // 结果显示
                  if (_result.isNotEmpty) ...[
                    Text(
                      '测试结果:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            _result,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // 显示现有数据
                  if (_allNodes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '现有节点:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _allNodes.length,
                        itemBuilder: (context, index) {
                          final node = _allNodes[index];
                          return Card(
                            child: ListTile(
                              title: Text('${node.name} (${node.type})'),
                              subtitle: Text('属性: ${node.attributes}'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }
}
