# 动态优先级评分系统 (Dynamic Priority Scoring System)

## 概述

本系统实现了基于时间衰减、再激活信号、语义相似度和图结构注意力扩散的事件节点动态优先级评分机制，用于改进知识图谱中事件节点的检索排序质量。

## 理论基础

### 核心公式

每个事件节点的动态优先级分数 `P(node, t)` 由四个组件线性组合而成：

```
P̃ = θ₁·f_time + θ₂·f_react + θ₃·f_sem + θ₄·f_diff
```

最终检索排序分数：

```
score(node) = cos(v_q, v_node) × (1 + P̃)
```

或使用 Softmax 归一化：

```
attention(i) = exp(P̃ᵢ) / Σⱼ exp(P̃ⱼ)
score(node) = cos(v_q, v_node) × attention(i)
```

## 四大组件详解

### 1. 时间衰减 (Temporal Attentional Decay)

**公式**: `f_time = exp(-λ · Δt)`

**参数**:
- `λ` (lambda): 时间衰减系数，范围 [0.005, 0.02]，默认 0.01
- `Δt`: 当前时间与节点最后访问时间的差值（单位：天）

**特性**:
- 最近的事件获得更高的权重
- 当查询中包含相对时间表达式（如"昨天"、"上周"）时，λ 临时放大 2-5 倍
- 支持的时间表达式：昨天、今天、明天、刚才、刚刚、上周、本周、下周、上月、本月、下月、最近、近期等

**实现**:
```dart
double calculateTemporalDecay(EventNode node, {DateTime? now}) {
  now ??= DateTime.now();
  final nodeTime = node.lastSeenTime ?? node.startTime ?? node.lastUpdated;
  final deltaTime = now.difference(nodeTime);
  final deltaDays = deltaTime.inHours / 24.0;
  final decay = exp(-lambda * deltaDays);
  return decay * temporalBoost;
}
```

### 2. 再激活信号 (Contextual Reinstatement)

**公式**: `f_react = Σᵢ α · exp(-β · Δt_react,i)`

**参数**:
- `α` (alpha): 激活强度系数，默认 1.0，可与召回相似度成比例
- `β` (beta): 遗忘速度系数，默认 0.01
- `Δt_react,i`: 第 i 次激活到当前时间的差值

**特性**:
- 追踪节点的历史激活事件（每次被召回并判定相关时记录）
- 使用指数衰减累计激活强度
- 自动限制激活历史为最近 100 条记录
- 支持反向传播：当节点被激活时，通过 revisit/progress_of 边影响邻居节点

**激活记录结构**:
```json
{
  "timestamp": 1699702800000,
  "similarity": 0.95
}
```

### 3. 语义相似度 (Semantic Alignment)

**公式**: `f_sem = (cos(v_q, v_node) + 1) / 2`

**特性**:
- 使用余弦相似度计算查询向量与节点嵌入向量的语义匹配度
- 线性缩放从 [-1, 1] 到 [0, 1]
- 直接利用现有的 embedding 向量（384维）

### 4. 注意力扩散 (Attention Diffusion via Graph)

**公式**: `f_diff(u) = Σ_{v∈N(u)} w_uv · P(v)`

**参数**:
- `γ` (gamma): 扩散衰减因子，默认 0.5
- `K`: 最大跳数限制，默认 1-hop
- `w_uv`: 边权重，基于边类型

**边类型权重**:
- `revisit` / `progress_of`: 1.0（最高）
- `causal`（因果关系）: 0.8
- `contains`（包含关系）: 0.7
- `temporal_sequence`（时间顺序）: 0.6
- 其他: 0.5

**特性**:
- 利用知识图谱的结构信息传播注意力
- 使用 K-hop 限制避免过度扩散
- 对邻居数量做平均，避免高度节点得分过高

## 权重参数配置

### 默认权重 (θ)

基于实验建议的初始值：

```dart
θ₁ = 0.3  // f_time 权重（时间衰减）
θ₂ = 0.4  // f_react 权重（再激活信号）
θ₃ = 0.2  // f_sem 权重（语义相似度）
θ₄ = 0.1  // f_diff 权重（图扩散）
```

### 调参建议

针对不同应用场景可以调整权重：

**强调时效性**（如新闻、事件追踪）:
```dart
θ₁ = 0.5, θ₂ = 0.3, θ₃ = 0.15, θ₄ = 0.05
```

**强调历史关联**（如知识积累、学习记录）:
```dart
θ₁ = 0.2, θ₂ = 0.5, θ₃ = 0.2, θ₄ = 0.1
```

**强调语义匹配**（如精确查询）:
```dart
θ₁ = 0.2, θ₂ = 0.2, θ₃ = 0.5, θ₄ = 0.1
```

**强调图结构**（如关系发现）:
```dart
θ₁ = 0.2, θ₂ = 0.3, θ₃ = 0.2, θ₄ = 0.3
```

## 使用方法

### 基本使用

```dart
// 使用优先级评分检索（默认启用）
final results = await KnowledgeGraphService.searchEventsByText(
  '昨天吃了什么',
  topK: 10,
  usePriorityScoring: true,
);

// 结果包含详细的评分信息
for (final result in results) {
  final event = result['event'] as EventNode;
  final priorityScore = result['priority_score'];
  final finalScore = result['final_score'];
  final components = result['components'];
  
  print('事件: ${event.name}');
  print('优先级分数: $priorityScore');
  print('  - 时间衰减: ${components['f_time']}');
  print('  - 再激活: ${components['f_react']}');
  print('  - 语义: ${components['f_sem']}');
  print('最终排序分数: $finalScore');
}
```

### 参数配置

```dart
final priorityService = EventPriorityScoringService();

// 更新参数
priorityService.updateParameters(
  lambda: 0.015,      // 调整时间衰减速度
  alpha: 1.2,         // 调整激活强度
  beta: 0.012,        // 调整遗忘速度
  gamma: 0.6,         // 调整图扩散衰减
  theta1: 0.35,       // 调整时间权重
  theta2: 0.35,       // 调整再激活权重
  theta3: 0.2,        // 调整语义权重
  theta4: 0.1,        // 调整图扩散权重
  strategy: ScoringStrategy.multiplicative,  // 或 softmax
);

// 查看当前配置
final config = priorityService.getConfiguration();
print(config);
```

### 手动记录激活

```dart
final priorityService = EventPriorityScoringService();

// 当节点被召回并判定为相关时
await priorityService.recordActivation(
  node: eventNode,
  similarity: 0.95,
  relatedOldNode: previousNode,  // 可选：建立 revisit 关系
);
```

### 诊断分析

```dart
final priorityService = EventPriorityScoringService();

// 分析优先级分数分布
final analysis = await priorityService.analyzePriorityDistribution(
  nodes: candidateNodes,
  queryVector: queryVector,
);

print('总节点数: ${analysis['total_nodes']}');
print('最小分数: ${analysis['min_score']}');
print('最大分数: ${analysis['max_score']}');
print('平均分数: ${analysis['avg_score']}');
print('分数分布: ${analysis['score_distribution']}');
```

## 数据模型扩展

### EventNode 新增字段

```dart
@Entity()
class EventNode {
  // ... 原有字段 ...
  
  // 优先级评分相关字段
  DateTime? lastSeenTime;        // 最后被检索/访问的时间
  String activationHistoryJson;  // 激活历史记录（JSON格式）
  double cachedPriorityScore;    // 缓存的优先级分数
}
```

### EventRelation 新增边类型

```dart
static const String RELATION_REVISIT = 'revisit';         // 重访关系
static const String RELATION_PROGRESS_OF = 'progress_of'; // 进展关系
```

## 排序策略

### 策略 A: Softmax 归一化

适用于需要明确注意力分布的场景。

```dart
strategy: ScoringStrategy.softmax
```

计算步骤：
1. 计算所有候选节点的 P̃
2. 应用 Softmax: `attention(i) = exp(P̃ᵢ) / Σⱼ exp(P̃ⱼ)`
3. 最终分数: `score = cos(v_q, v_node) × attention(i)`

### 策略 B: 乘法增强（默认）

适用于大多数检索场景，计算简单高效。

```dart
strategy: ScoringStrategy.multiplicative
```

计算公式：
```
score = cos(v_q, v_node) × (1 + P̃)
```

## 性能优化

### 批量计算

系统支持批量计算优先级分数，并在需要时进行两轮迭代以包含图扩散：

```dart
final priorityScores = await priorityService.calculateBatchPriorityScores(
  nodes: candidates,
  queryVector: queryVector,
  enableDiffusion: true,
);
```

### 缓存机制

- 激活历史自动限制为最近 100 条
- 支持在节点对象中缓存优先级分数（`cachedPriorityScore`）
- EmbeddingService 已有嵌入向量缓存机制

## 评估与调优

### 评估指标

建议使用以下指标评估优先级评分效果：

1. **MAP (Mean Average Precision)**: 平均精度均值
2. **Recall@K**: 前K个结果的召回率
3. **NDCG (Normalized Discounted Cumulative Gain)**: 归一化折损累计增益
4. **MRR (Mean Reciprocal Rank)**: 平均倒数排名

### 调优流程

1. **收集标注数据**: 人工标注查询-事件的相关性
2. **Grid Search**: 遍历参数空间寻找最优组合
3. **交叉验证**: 使用 k-fold 验证参数稳定性
4. **A/B 测试**: 在真实场景中对比新旧方法

### 参数搜索空间建议

```dart
// 时间衰减
lambda: [0.005, 0.01, 0.015, 0.02]

// 再激活
alpha: [0.8, 1.0, 1.2]
beta: [0.008, 0.01, 0.012, 0.015]

// 图扩散
gamma: [0.3, 0.5, 0.7]

// 权重组合（需满足 Σθᵢ = 1.0）
theta1: [0.2, 0.3, 0.4, 0.5]
theta2: [0.2, 0.3, 0.4, 0.5]
theta3: [0.1, 0.2, 0.3]
theta4: [0.0, 0.1, 0.2]
```

## 常见问题

### Q: 为什么需要运行 ObjectBox 生成器？

A: 新增的优先级字段需要在数据库 schema 中注册。运行：
```bash
dart run build_runner build --delete-conflicting-outputs
```

### Q: 如何禁用优先级评分？

A: 在检索时设置参数：
```dart
await KnowledgeGraphService.searchEventsByText(
  query,
  usePriorityScoring: false,
);
```

### Q: 图扩散计算是否会很慢？

A: 默认限制为 1-hop 且批量计算，性能影响很小。如需禁用：
```dart
await priorityService.rankEventsByPriority(
  candidates: candidates,
  queryVector: queryVector,
  enableDiffusion: false,
);
```

### Q: 如何处理冷启动节点（无激活历史）？

A: 冷启动节点的 `f_react = 0`，主要依赖 `f_time` 和 `f_sem`。随着使用增多会自动积累激活历史。

### Q: 相对时间表达式检测支持哪些语言？

A: 当前仅支持中文常见表达式。可扩展 `detectAndBoostTemporalExpression` 方法支持更多语言。

## 论文撰写建议

### 创新点描述

本系统的核心创新在于：

1. **多维度融合**: 综合时间、激活历史、语义和图结构四个维度
2. **自适应机制**: 基于查询内容动态调整时间敏感度
3. **图结构利用**: 通过注意力扩散传播相关性
4. **上下文记忆**: 激活历史机制模拟人类记忆的再激活效应

### 实验设计

1. **基线方法**: 纯余弦相似度、TF-IDF、BM25
2. **对比方法**: 仅时间衰减、仅语义相似度、混合方法（无图扩散）
3. **完整方法**: 本系统的全部四个组件

### 预期结果

在具有时间敏感性和关联性的事件检索任务中，预期本系统相比基线方法在 MAP、NDCG 等指标上有 10-25% 的提升。

## 未来扩展

- [ ] 支持多语言时间表达式
- [ ] 学习最优参数权重（而非手工调整）
- [ ] 支持用户个性化参数配置
- [ ] 引入强化学习优化排序策略
- [ ] 扩展到多跳图扩散（K > 1）
- [ ] 支持异构图（事件-实体混合）

## 参考文献

相关理论基础参考：

1. Temporal Information Retrieval
2. Contextual Reinstatement in Memory Psychology
3. Graph Attention Networks (GAT)
4. Learning to Rank for Information Retrieval

---

**版本**: 1.0.0  
**最后更新**: 2024-11-11  
**维护者**: ECBill
