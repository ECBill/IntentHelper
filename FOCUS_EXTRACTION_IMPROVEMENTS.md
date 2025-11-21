# 关注点提取改进文档

## 问题背景

之前的FocusStateMachine实现存在以下问题：

1. **关注点过于笼统**：只能提取"工作"、"对话"、"casual_chat"等抽象类别，无法识别具体内容
2. **缺乏上下文细节**：无法捕捉"朋友的恋情"、"Flutter项目的性能问题"等具体信息
3. **静态关键词匹配**：使用硬编码的模式匹配，无法理解对话的深层语义

## 解决方案

### 1. LLM深度语义提取

新增 `_extractFocusesWithLLM()` 方法，使用LLM进行深度语义分析：

```dart
Future<List<FocusPoint>> _extractFocusesWithLLM(SemanticAnalysisInput analysis)
```

**特点：**
- 提取**具体的**人名、事件、项目、问题（而非抽象类别）
- 捕捉**关系和上下文**（人物关系、事件细节、时间背景）
- 支持**动态演进**（关注点随对话实时更新）
- 区分**三种类型**：事件(event)、实体(entity)、主题(topic)

### 2. 提取示例对比

#### 之前的提取结果 ❌
对话："我昨天跟朋友聊了他最近的恋情，他说遇到了一些沟通问题"

提取结果：
- casual_chat (主题)
- 对话 (主题)
- 工作 (主题)
- information_seeking (事件)

#### 改进后的提取结果 ✅
对话："我昨天跟朋友聊了他最近的恋情，他说遇到了一些沟通问题"

提取结果：
```json
[
  {
    "type": "event",
    "canonicalLabel": "朋友的恋情进展",
    "aliases": ["朋友恋爱", "感情问题"],
    "emotionalScore": 0.6,
    "metadata": {
      "source": "llm_extraction",
      "specific_context": "朋友最近遇到恋情中的沟通问题",
      "content_snippet": "我昨天跟朋友聊了他最近的恋情，他说遇到了一些沟通问题",
      "entities": ["朋友"],
      "temporal_info": "昨天",
      "relational_info": "朋友关系"
    }
  },
  {
    "type": "topic",
    "canonicalLabel": "恋爱中的沟通技巧",
    "aliases": ["情侣沟通", "感情交流"],
    "emotionalScore": 0.5,
    "metadata": {
      "source": "llm_extraction",
      "specific_context": "讨论如何改善恋爱关系中的沟通",
      "entities": ["沟通问题"],
      "relational_info": "情侣关系"
    }
  }
]
```

### 3. 提取原则

LLM提取遵循以下原则：

1. **具体性优先**：
   - ❌ 错误："工作"、"对话"、"casual_chat"
   - ✅ 正确："朋友的恋情进展"、"Flutter项目的性能优化"、"下周的产品发布会"

2. **关系和上下文**：
   - 捕捉人物关系：朋友、同事、家人
   - 记录时间信息：昨天、下周、最近
   - 保留具体场景：会议、讨论、计划

3. **动态性**：
   - 每次对话都重新分析
   - 关注点随对话演进
   - 自动合并相似关注点

4. **多样性**：
   - 同时捕捉事件、实体、主题
   - 最多返回5个高置信度关注点
   - 避免过度提取

## 技术实现

### 工作流程

```
用户消息
  ↓
HumanUnderstandingSystem.processSemanticInput()
  ↓
FocusStateMachine.ingestUtterance(analysis)
  ↓
_extractFocusesWithLLM() [使用LLM深度分析]
  ↓ (失败时)
_extractFocusesFromAnalysis() [降级到基础提取]
  ↓
_processNewFocus() [处理新关注点，合并相似项]
  ↓
updateScores() [更新多维度评分]
  ↓
_reclassifyFocuses() [重新分类为活跃/潜在]
  ↓
getTop(12) → focusLabels
  ↓
KnowledgeGraphManager.updateActiveTopics(focusLabels)
  ↓
知识图谱使用具体关注点进行查询
```

### 持续更新机制

系统通过以下机制确保关注点持续更新：

1. **对话监听**：每5秒检查新对话（`_monitorNewConversations`）
2. **批量处理**：发现新对话时触发 `_processBatchConversations`
3. **语义分析**：调用 `processSemanticInput` 处理每条新消息
4. **关注点更新**：自动调用 `FocusStateMachine.ingestUtterance`
5. **知识图谱同步**：更新后的关注点自动传递给知识图谱

### 降级策略

为保证系统稳定性，实现了双层降级机制：

```dart
if (_useLLMExtraction) {
  try {
    extractedFocuses = await _extractFocusesWithLLM(analysis);
  } catch (e) {
    // 降级到基础提取
    extractedFocuses = _extractFocusesFromAnalysis(analysis);
  }
} else {
  // 测试模式：直接使用基础提取
  extractedFocuses = _extractFocusesFromAnalysis(analysis);
}
```

### 测试支持

为支持单元测试，新增 `useLLMExtraction` 参数：

```dart
// 生产环境：启用LLM提取
await focusStateMachine.initialize(); // 默认 useLLMExtraction: true

// 测试环境：禁用LLM提取（快速、确定性）
await focusStateMachine.initialize(useLLMExtraction: false);
```

## 知识图谱集成

### 自动同步

在 `human_understanding_system.dart` 中，每次处理完语义输入后自动更新知识图谱：

```dart
// 使用关注点状态机的结果更新知识图谱
final topFocuses = _focusStateMachine.getTop(12);
final focusLabels = topFocuses.map((f) => f.canonicalLabel).toList();

if (focusLabels.isNotEmpty) {
  await _knowledgeGraphManager.updateActiveTopics(focusLabels);
}
```

### 查询效果

**之前**：
- 查询："工作"、"对话" → 返回大量不相关结果
- 无法找到具体相关的知识节点

**现在**：
- 查询："朋友的恋情进展"、"Flutter性能优化" → 返回精准匹配结果
- 知识图谱能准确定位相关事件和实体

## 使用示例

### 示例1：讨论朋友恋情

**输入对话：**
```
用户："我昨天跟小李聊天，他说和女朋友最近总是因为小事吵架，
      主要是沟通方式不对，我建议他们可以尝试非暴力沟通的方法。"
```

**提取的关注点：**
1. **事件**: "小李的恋情沟通问题"
   - 元数据：涉及人物(小李)、关系(朋友)、时间(昨天)、具体问题(沟通方式)
   
2. **主题**: "非暴力沟通方法"
   - 元数据：解决方案、沟通技巧
   
3. **实体**: "小李"
   - 元数据：朋友关系

### 示例2：Flutter项目讨论

**输入对话：**
```
用户："我们Flutter项目的列表页面滚动性能不太好，
      打算下周会议上讨论是用虚拟列表还是分页加载。"
```

**提取的关注点：**
1. **事件**: "Flutter项目列表性能优化"
   - 元数据：技术问题、具体页面(列表页)、性能问题(滚动)
   
2. **事件**: "下周的技术方案讨论会议"
   - 元数据：时间(下周)、讨论主题(虚拟列表 vs 分页加载)
   
3. **主题**: "Flutter列表性能优化方案"
   - 元数据：技术选型(虚拟列表、分页加载)

## 性能考虑

### LLM调用优化

1. **异步处理**：LLM调用不阻塞UI线程
2. **降级机制**：LLM失败时立即降级到基础提取
3. **缓存策略**：相似对话片段可能被合并，减少重复调用
4. **限制数量**：每次最多提取5个关注点，避免过度调用

### 监控指标

建议监控以下指标：

- LLM调用成功率
- 平均响应时间
- 降级到基础提取的频率
- 关注点合并率

## 未来改进方向

1. **Embedding相似度**：使用向量相似度进行更精确的关注点合并
2. **用户画像**：根据用户习惯调整提取策略和评分权重
3. **多轮对话理解**：跨多轮对话追踪同一关注点的演进
4. **主动预测**：基于历史模式预测用户下一步可能关注的内容

## 总结

通过引入LLM深度语义分析，FocusStateMachine现在能够：

- ✅ 提取**具体、细粒度**的关注点
- ✅ 捕捉**关系、上下文**等丰富信息
- ✅ **持续更新**（每条新消息都会触发分析）
- ✅ **自动同步**知识图谱（使用精准的关注点标签）
- ✅ **降级保护**（LLM失败时不影响系统运行）
- ✅ **测试友好**（可禁用LLM进行快速单元测试）

这些改进从根本上解决了之前"关注点太笼统"、"无法随对话更新"、"知识图谱查询失败"的问题。
