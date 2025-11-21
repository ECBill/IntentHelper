# 对话关注点状态机 (Focus State Machine)

## 概述

对话关注点状态机是一个智能模块，用于追踪开放式长对话中用户关注点的动态演化。它取代了原有的简单LLM主题提取方式，提供了更精确、更持久的关注点建模能力。

## 核心特性

### 1. 多维度关注点建模

每个关注点（FocusPoint）包含：
- **类型**: 事件(event)、主题(topic)、实体(entity)
- **状态**: 新兴、活跃、背景、潜在、衰退
- **多维度分数**:
  - 显著性分数（综合）
  - 最近性分数（非线性衰减）
  - 重复强化分数（对数缩放）
  - 情绪权重分数
  - 因果连接度分数
  - 漂移预测分数

### 2. 智能评分算法

#### 最近性分数 (Recency Score)
使用慢速尾部衰减公式，保留较旧但仍相关的关注点：

```
f_recency(Δt) = 1 / (1 + (Δt / τ)^β)
其中: τ = 300秒 (5分钟), β = 0.7
```

#### 重复强化分数 (Repetition Score)
基于提及次数的对数缩放：

```
f_repetition = log(1 + mention_count) / log(1 + max_mentions)
```

#### 综合显著性分数 (Salience Score)
加权组合各维度分数：

```
Salience = 0.25 * recency + 0.20 * repetition + 0.15 * emotion + 
           0.20 * causal + 0.20 * drift
```

### 3. 关注点漂移追踪

FocusDriftModel 维护：
- **转移矩阵**: 记录关注点之间的转移概率
- **转移历史**: 保存最近200次转移
- **动量向量**: 跟踪最近20个关注点序列
- **预测能力**: 基于历史模式预测新兴关注点

### 4. 自动合并与去重

系统会自动检测并合并相似的关注点：
- 精确匹配（标签相同）
- 别名匹配
- 模糊匹配（基于Jaccard相似度 >= 0.7）

### 5. 动态容量管理

- **活跃关注点**: 6-12个（动态调整）
- **潜在关注点**: 最多8个
- **自动修剪**: 移除2小时以上未更新且分数低的关注点

## 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│ HumanUnderstandingSystem                                   │
│  ├─ FocusStateMachine (新增)                               │
│  │   ├─ ingestUtterance()  ← 摄入对话                      │
│  │   ├─ updateScores()     ← 更新分数                      │
│  │   ├─ reclassifyFocuses() ← 重新分类                     │
│  │   └─ getTop(N)          ← 获取Top N关注点               │
│  │                                                           │
│  ├─ FocusDriftModel                                         │
│  │   ├─ recordTransition()  ← 记录转移                     │
│  │   ├─ updateTrajectory()  ← 更新轨迹                     │
│  │   └─ predictEmerging()   ← 预测新兴                     │
│  │                                                           │
│  ├─ IntentLifecycleManager (保留作为备份)                  │
│  ├─ ConversationTopicTracker (保留作为备份)                │
│  └─ CausalChainExtractor (用于链接关注点)                  │
└─────────────────────────────────────────────────────────────┘
                    ↓
        ┌───────────────────────┐
        │ KnowledgeGraphManager │
        │ ← Top 12 focus labels │
        └───────────────────────┘
```

## 使用流程

### 1. 初始化
```dart
final focusStateMachine = FocusStateMachine();
await focusStateMachine.initialize();
```

### 2. 摄入对话
```dart
final analysis = SemanticAnalysisInput(
  entities: ['Flutter', 'AI', '机器学习'],
  intent: 'learning',
  emotion: 'curious',
  content: '我想学习关于Flutter和AI的知识...',
  timestamp: DateTime.now(),
);

await focusStateMachine.ingestUtterance(analysis);
```

### 3. 获取关注点
```dart
// 获取所有活跃关注点
final activeFocuses = focusStateMachine.getActiveFocuses();

// 获取Top N个关注点
final topFocuses = focusStateMachine.getTop(12);

// 获取潜在关注点
final latentFocuses = focusStateMachine.getLatentFocuses();
```

### 4. 查看统计
```dart
final stats = focusStateMachine.getStatistics();
print('活跃: ${stats['active_focuses_count']}');
print('潜在: ${stats['latent_focuses_count']}');
print('类型分布: ${stats['focus_type_distribution']}');

final driftStats = focusStateMachine.getDriftStats();
print('转移次数: ${driftStats['total_transitions']}');
```

## 与知识图谱集成

Focus State Machine 自动为知识图谱提供查询约束：

```dart
// 在 processSemanticInput 中自动执行
await focusStateMachine.ingestUtterance(analysis);

final topFocuses = focusStateMachine.getTop(12);
final focusLabels = topFocuses.map((f) => f.canonicalLabel).toList();

// 用关注点标签更新知识图谱查询
await knowledgeGraphManager.updateActiveTopics(focusLabels);
```

这样知识图谱始终基于当前最相关的关注点进行检索，避免了之前的问题：
- ❌ 每5秒完全刷新主题列表
- ❌ 主题判断重复且单一
- ❌ 权重随时间流逝下降太快
- ✅ 增量更新，保持历史相关性
- ✅ 多样化关注点（事件+主题+实体）
- ✅ 慢速衰减，兼顾多重关注

## UI可视化

Dashboard新增"关注点"标签页，展示：

1. **统计卡片**
   - 活跃/潜在/总数
   - 转移次数
   - 类型分布

2. **活跃关注点列表**
   - 显著性进度条
   - 五维分数明细（最近、重复、情绪、因果、漂移）
   - 提及次数和关联数量

3. **潜在关注点列表**
   - 即将成为焦点的关注点
   - 预测分数

## 配置参数

可在 `FocusStateMachine` 类中调整：

```dart
static const int _maxActiveFocuses = 12;  // 活跃关注点上限
static const int _minActiveFocuses = 6;   // 活跃关注点下限
static const int _maxLatentFocuses = 8;   // 潜在关注点上限

static const double _weightRecency = 0.25;    // 最近性权重
static const double _weightRepetition = 0.20; // 重复权重
static const double _weightEmotion = 0.15;    // 情绪权重
static const double _weightCausal = 0.20;     // 因果权重
static const double _weightDrift = 0.20;      // 漂移权重

static const double _recencyTau = 300.0;   // 衰减时间常数（秒）
static const double _recencyBeta = 0.7;    // 衰减指数
```

## 性能优化

1. **增量处理**: 只更新变化的关注点
2. **自动修剪**: 定期清理过旧的低分关注点
3. **限制历史**: 转移历史最多200条，序列最多20个
4. **延迟计算**: 分数按需计算，避免过度计算

## 未来扩展

可能的增强方向：

1. **Embedding集成**: 使用向量相似度进行更精确的匹配
2. **用户画像**: 根据用户习惯调整评分权重
3. **情感分析**: 集成语音韵律和情感强度
4. **预测分支**: 多分支预测未来可能的关注点

## 调试和监控

```dart
// 查看当前状态
final activeFocuses = focusStateMachine.getActiveFocuses();
for (final focus in activeFocuses) {
  print('${focus.canonicalLabel}: ${focus.salienceScore}');
  print('  最近性: ${focus.recencyScore}');
  print('  重复性: ${focus.repetitionScore}');
  print('  情绪: ${focus.emotionalScore}');
  print('  因果: ${focus.causalConnectivityScore}');
  print('  漂移: ${focus.driftPredictiveScore}');
}

// 查看转移轨迹
final transitions = focusStateMachine._driftModel.getTransitionHistory(limit: 10);
for (final t in transitions) {
  print('${t.fromFocusId} → ${t.toFocusId} (${t.transitionStrength})');
}
```

## 论文相关

此模块是论文中多约束知识事件匹配的关键创新点：
- 提供了持久的、多维度的用户关注建模
- 支持增量式知识图谱检索池更新
- 避免了全量刷新导致的性能问题
- 能够兼顾多重关注主题，实现理想的「有些最近提及的权重高，有些之前提及的但现在转话题的权重低」的效果
