import 'package:flutter/material.dart';
import 'package:app/views/cache_debug_page.dart';
import 'package:app/services/chat_manager.dart';

// 在现有页面中添加调试入口的示例
class DebugMenuPage extends StatelessWidget {
  final ChatManager chatManager;

  const DebugMenuPage({Key? key, required this.chatManager}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('调试工具'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.storage, color: Colors.blue),
              title: const Text('缓存调试工具'),
              subtitle: const Text('查看和管理智能对话缓存'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CacheDebugPage(),
                  ),
                );
              },
            ),
          ),
          // 可以添加更多调试工具
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info, color: Colors.green),
              title: const Text('系统信息'),
              subtitle: const Text('查看应用版本和系统状态'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                // 其他调试功能
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 或者作为浮动按钮添加到主页面
class MainPageWithDebugButton extends StatelessWidget {
  final ChatManager chatManager;
  final Widget child;

  const MainPageWithDebugButton({
    Key? key,
    required this.chatManager,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CacheDebugPage(),
            ),
          );
        },
        backgroundColor: Colors.orange,
        child: const Icon(Icons.bug_report),
      ),
    );
  }
}
