# FocusStateMachine 修复和增强

## 问题概述

之前在使用 FocusStateMachine 时遇到了以下问题：

1. **LLM 返回空数组问题**：当用户发送非常短的消息（如"就直接糊了..."）时，LLM 会按照 prompt 指示返回空数组 `[]`
2. **UI 显示为空**：虽然之前成功提取了关注点（如"牛"、"报告情况"），但 UI 界面显示为空
3. **缺少对话上下文**：每条消息独立处理，没有利用对话历史提供上下文

## 修复方案

### 1. 对话上下文缓冲

**变更**：添加了 `_conversationHistory` 列表来保存最近的对话记录

```dart
// 对话历史缓冲（用于提供上下文）
final List<SemanticAnalysisInput> _conversationHistory = [];
static const int _maxHistorySize = 10;
```

**效果**：
- 保存最近 10 条对话
- LLM 提取关注点时会使用最近 5 条消息作为上下文
- 即使当前消息很短，也能从上下文推断关注点

### 2. 改进的 LLM Prompt

**变更**：更新了 LLM prompt，增加了以下指导：

```
【最近对话上下文】：
...（最近5条消息）

【严格要求】：
- 如果当前对话很简短但能从上下文推断关注点，仍应提取
- 如果实在无法提取有意义的关注点，返回空数组 []
```

**效果**：
- LLM 能够结合上下文理解短消息
- 减少空结果的出现
- 提高关注点提取的连续性

### 3. 详细的调试日志

**变更**：在关键位置添加了详细的日志输出

```dart
// 输出活跃关注点列表
print('[FocusStateMachine] 📋 活跃关注点列表: ${_activeFocuses.map(...).join(", ")}');

// 输出重新分类过程
print('[FocusStateMachine] 📊 排序后前5个关注点: ...');
print('[FocusStateMachine] 📊 活跃阈值: ${activeThreshold.toStringAsFixed(3)}');
```

**效果**：
- 可以清楚地看到每次处理后的活跃关注点
- 方便调试和问题定位
- 了解分数计算和分类逻辑

### 4. 回退提取机制

**变更**：当关注点列表为空但有对话历史时，自动触发回退提取

```dart
void _performFallbackExtraction() {
  print('[FocusStateMachine] 🔄 执行回退提取...');
  final recentAnalysis = _conversationHistory.last;
  final fallbackFocuses = _extractFocusesFromAnalysis(recentAnalysis);
  ...
}
```

**效果**：
- 防止关注点列表完全为空
- 使用基础提取方法作为降级方案
- 确保总是有一些关注点可供展示

### 5. 降低最小活跃数量并增强保留策略

**变更**：
- 将最小活跃关注点数从 6 降低到 3
- 添加了强制提升机制，确保即使分数较低也会保留最小数量

```dart
static const int _minActiveFocuses = 3;

// 如果还是不够，从所有关注点中提升
while (_activeFocuses.length < _minActiveFocuses && ...) {
  // 强制提升逻辑
}
```

**效果**：
- 避免因过度严格的分数要求导致空状态
- 即使新对话提取为空，也能保持已有关注点
- UI 始终有内容可以展示

### 6. 空结果处理改进

**变更**：在 `ingestUtterance` 中添加了空结果的明确处理

```dart
if (extractedFocuses.isNotEmpty) {
  for (final newFocus in extractedFocuses) {
    _processNewFocus(newFocus, analysis);
  }
} else {
  print('[FocusStateMachine] ℹ️ 本次提取为空，保持现有关注点状态');
}
```

**效果**：
- 清楚地记录空提取情况
- 不会因为空提取而清空现有状态
- 继续更新现有关注点的分数

## 测试验证

添加了新的测试用例：

1. **空提取状态保持测试**：验证收到空提取后活跃关注点仍然存在
2. **对话历史上下文测试**：验证多条相关消息能够建立上下文并提取关注点

```dart
test('FocusStateMachine should maintain state when receiving empty extractions', () async {
  // 先添加有意义的内容
  // 然后发送很短的消息
  // 验证活跃关注点仍然保留
})

test('FocusStateMachine should use conversation history for context', () async {
  // 发送一系列相关消息
  // 验证能够提取到关注点
})
```

## 使用建议

1. **监控日志**：关注以下关键日志输出
   - `📋 活跃关注点列表` - 查看当前活跃关注点及其分数
   - `⚠️ 警告：活跃关注点列表为空` - 出现时需要调查原因
   - `🔄 执行回退提取` - 表示触发了降级机制

2. **调试模式**：如果遇到问题，可以在日志中查看
   - LLM 响应内容（截断到200字符）
   - 重新分类过程中的详细信息
   - 修剪操作的数量

3. **性能考虑**：
   - 对话历史限制为 10 条，避免内存占用过大
   - 每次只使用最近 5 条作为 LLM 上下文
   - 定期修剪 2 小时前的过旧关注点

## 后续优化建议

1. **更智能的空结果处理**：可以基于对话间隔时间决定是否需要提取
2. **分数衰减调优**：根据实际使用情况调整时间衰减参数
3. **类型分层展示**：在 UI 中区分显示 event/topic/entity 类型
4. **历史回溯提取**：当用户明确提到之前的话题时，重新激活相关关注点

## 相关文件

- `lib/services/focus_state_machine.dart` - 主要修改文件
- `lib/models/focus_models.dart` - 数据模型定义
- `lib/services/human_understanding_system.dart` - 调用 FocusStateMachine 的系统
- `lib/views/human_understanding_dashboard.dart` - UI 展示
- `test/focus_state_machine_test.dart` - 测试用例
