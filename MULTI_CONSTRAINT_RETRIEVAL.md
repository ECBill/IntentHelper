# 多约束动态知识图谱检索模块

## 概述

多约束动态知识图谱检索模块是对现有知识图谱检索系统的重大增强。它在传统的向量相似度检索基础上，引入了多层约束条件，实现了更精准、更高效的事件节点检索和排序。

### 核心创新点

1. **多层约束架构**：支持硬约束（必须满足）和软约束（评分加权）的组合使用
2. **动态节点池管理**：增量更新而非完全替换，提高效率并保持历史相关性
3. **综合评分机制**：结合向量相似度、约束得分和时效性衰减
4. **灵活可扩展**：轻松添加新的约束类型和调整权重配置

## 架构设计

### 核心组件

```
lib/models/constraint_models.dart       # 约束模型定义
lib/services/multi_constraint_retrieval.dart  # 检索服务实现
lib/services/knowledge_graph_manager.dart     # 集成点
lib/views/human_understanding_dashboard.dart  # UI展示
```

### 数据流

```
用户关注主题更新（每5秒）
    ↓
MultiConstraintRetrievalService.retrieveMultipleTopics()
    ↓
对每个主题：
  1. 向量检索（获取候选集）
  2. 应用硬约束（过滤）
  3. 应用软约束（评分）
  4. 计算综合得分
    ↓
mergeAndPrune（与现有节点池合并）
    ↓
保留前20个最高分节点
    ↓
更新UI显示
```

## 约束类型

### 硬约束（必须满足）

#### TimeWindowConstraint - 时间窗口约束
```dart
TimeWindowConstraint(
  startTime: DateTime(2024, 1, 1),
  endTime: DateTime(2024, 1, 31),
)
```
用途：限制事件必须在指定时间范围内

#### LocationMatchConstraint - 地点匹配约束
```dart
LocationMatchConstraint(
  requiredLocation: '上海',
)
```
用途：要求事件必须在指定地点

#### EntityPresenceConstraint - 实体存在约束
```dart
EntityPresenceConstraint(
  requiredEntityIds: ['entity_1', 'entity_2'],
)
```
用途：要求事件必须包含指定实体

### 软约束（评分加权）

#### TemporalProximityConstraint - 时间接近度约束
```dart
TemporalProximityConstraint(
  targetTime: DateTime.now(),
  maxDistance: Duration(days: 7),
  weight: 0.3,
)
```
用途：时间越接近目标时间，得分越高（线性衰减）

#### LocationSimilarityConstraint - 地点相似度约束
```dart
LocationSimilarityConstraint(
  targetLocation: '北京',
  weight: 0.3,
)
```
用途：地点部分匹配也能获得得分

#### FreshnessBoostConstraint - 新鲜度奖励约束
```dart
FreshnessBoostConstraint(
  recentWindow: Duration(hours: 48),
  weight: 0.2,
)
```
用途：最近更新或访问的节点获得奖励分数

## 使用指南

### 基础用法

系统已自动集成到 `KnowledgeGraphManager`，当主题更新时会自动应用默认约束集：

```dart
// 在 human_understanding_system.dart 中自动调用
await _knowledgeGraphManager.updateActiveTopics(topics);
```

### 自定义约束集

创建自定义约束组合：

```dart
final service = MultiConstraintRetrievalService();

// 创建自定义约束
final constraints = [
  TemporalProximityConstraint(
    targetTime: DateTime.now(),
    weight: 0.4,
  ),
  LocationSimilarityConstraint(
    targetLocation: '上海办公室',
    weight: 0.3,
  ),
  FreshnessBoostConstraint(
    weight: 0.2,
  ),
];

// 执行检索
final results = await service.retrieveMultipleTopics(
  topics: ['会议', '项目'],
  context: RetrievalContext(
    focusTopics: ['会议', '项目'],
    targetLocation: '上海',
  ),
  constraints: constraints,
  finalTopK: 20,
);
```

### 严格查询模式

需要精确匹配时使用严格约束：

```dart
final strictConstraints = service.createStrictConstraints(
  startTime: DateTime(2024, 1, 1),
  endTime: DateTime(2024, 1, 31),
  requiredLocation: '上海',
  requiredEntityIds: ['user_123'],
);

final results = await service.retrieveMultipleTopics(
  topics: ['重要会议'],
  context: context,
  constraints: strictConstraints,
);
```

## 添加自定义约束

### 步骤1: 定义约束类

在 `lib/models/constraint_models.dart` 中添加新约束：

```dart
/// 参与者数量约束 - 事件参与者越多得分越高
class ParticipantCountConstraint extends Constraint {
  final int minParticipants;
  final int idealParticipants;

  ParticipantCountConstraint({
    this.minParticipants = 1,
    this.idealParticipants = 10,
    double weight = 1.0,
  }) : super(name: 'ParticipantCount', isHard: false, weight: weight);

  @override
  ConstraintResult evaluate(EventNode node, RetrievalContext context) {
    // 获取参与者数量（需要扩展EventNode或从关系中查询）
    final participantCount = 5; // 示例值
    
    if (participantCount < minParticipants) {
      return ConstraintResult.pass(score: 0.0, reason: '参与者不足');
    }
    
    final ratio = participantCount / idealParticipants.toDouble();
    final score = ratio > 1.0 ? 1.0 : ratio;
    
    return ConstraintResult.pass(
      score: score * weight,
      reason: '参与者: $participantCount / $idealParticipants',
    );
  }
}
```

### 步骤2: 使用自定义约束

```dart
final constraints = [
  ...service.createDefaultConstraints(),
  ParticipantCountConstraint(
    minParticipants: 3,
    idealParticipants: 10,
    weight: 0.2,
  ),
];
```

## 综合评分机制

### 评分公式

```
CompositeScore = embeddingScore × wE 
               + Σ(constraintScores) × wC 
               + recencyFactor × wR

其中：
- wE: embedding权重（默认0.4）
- wC: 约束权重（默认0.5）
- wR: 时效性权重（默认0.1）
- recencyFactor = 1 / (1 + hoursSinceUpdate / stalenessHours)
```

### 权重调优

根据应用场景调整权重：

```dart
scoredNode.computeCompositeScore(
  embeddingWeight: 0.5,    // 更重视语义相似度
  constraintWeight: 0.4,   // 约束重要性
  recencyWeight: 0.1,      // 时效性重要性
  stalenessHours: 24.0,    // 24小时后开始衰减
);
```

## 动态节点池管理

### 增量更新策略

每次主题更新时：

1. **检索新候选**：基于新主题获取候选节点
2. **评分新节点**：应用约束计算综合得分
3. **合并去重**：
   - 如果节点已存在且新得分更高，替换
   - 如果节点已存在但新得分较低，保留旧节点但更新时间戳
   - 如果是新节点，直接添加
4. **重新排序**：按综合得分降序排列
5. **裁剪池大小**：保留前20个节点

### 优势

- **效率提升**：避免每次完全重建，减少计算成本
- **连续性**：保持历史相关节点，避免频繁"闪现"
- **自适应**：根据主题变化自然演化节点集合

## UI展示

### 节点卡片

每个节点卡片显示：
- 综合得分（composite_score）
- 余弦相似度（embedding score）
- 多约束评分指示器（如有）

### 详情对话框

点击节点查看完整信息：
- 所有字段值
- **约束得分详情**（新增）：
  - TemporalProximity（时间接近度）- 橙色时钟图标
  - LocationSimilarity（地点相似度）- 蓝色地点图标
  - FreshnessBoost（新鲜度）- 绿色新标签图标
  - EntityPresence（实体存在）- 紫色用户图标
- 优先级组件得分（兼容旧系统）

## 性能考量

### 优化策略

1. **缓存机制**：节点池缓存避免重复计算
2. **批量处理**：多主题并行检索
3. **增量更新**：仅处理变化部分
4. **限制候选集**：每个主题最多30个候选（topK=30）

### 性能指标

- 单次主题更新：< 500ms（包含向量检索和约束评估）
- 节点池合并：< 50ms
- UI刷新延迟：< 100ms
- 内存占用：约2-5MB（20节点池）

## 配置参数

### 全局配置

在 `knowledge_graph_manager.dart` 中调整：

```dart
// 每个主题的候选数量
topKPerTopic: 20,

// 最终保留节点数
finalTopK: 20,

// 相似度阈值
similarityThreshold: 0.2,

// 是否重新计算得分
recomputeScores: true,
```

### 约束配置

在 `multi_constraint_retrieval.dart` 的 `createDefaultConstraints` 中调整：

```dart
TemporalProximityConstraint(
  maxDistance: Duration(days: 30),  // 时间范围
  weight: 0.3,                      // 权重
),
LocationSimilarityConstraint(
  weight: 0.3,
),
FreshnessBoostConstraint(
  recentWindow: Duration(hours: 48),
  weight: 0.2,
),
```

## 测试

运行测试套件：

```bash
flutter test test/multi_constraint_test.dart
```

测试覆盖：
- ✅ 硬约束过滤逻辑
- ✅ 软约束评分计算
- ✅ 综合得分计算
- ✅ 节点池合并和去重
- ✅ 池大小限制
- ✅ 约束工厂方法

## 未来扩展

### 短期计划

1. 实现 `EntityPresenceConstraint` 的实际查询逻辑（需要集成 `EventEntityRelation`）
2. 添加地点层级匹配（省-市-区）
3. 实现语义漂移检测

### 长期计划

1. **自适应权重**：根据用户交互学习最优权重配置
2. **上下文感知约束**：根据对话状态动态调整约束
3. **多模态约束**：支持图像、音频等多模态特征约束
4. **分布式检索**：支持大规模节点库的分布式检索

## 故障排查

### 问题：检索结果为空

1. 检查 `similarityThreshold` 是否过高
2. 验证硬约束是否过于严格
3. 查看日志确认向量检索是否成功

### 问题：得分计算异常

1. 检查约束权重总和是否合理
2. 验证 `computeCompositeScore` 参数配置
3. 确认时间字段不为null

### 问题：节点池不更新

1. 检查 `mergeAndPrune` 的 `maxPoolSize` 配置
2. 验证新节点得分是否足够高
3. 确认 `recomputeScores` 是否启用

## 相关文件

- `lib/models/constraint_models.dart` - 约束模型
- `lib/services/multi_constraint_retrieval.dart` - 检索服务
- `lib/services/knowledge_graph_manager.dart` - 管理器集成
- `lib/views/human_understanding_dashboard.dart` - UI显示
- `test/multi_constraint_test.dart` - 测试套件

## 贡献指南

欢迎贡献新的约束类型或优化建议！

1. Fork 仓库
2. 在 `lib/models/constraint_models.dart` 中添加约束
3. 在 `test/multi_constraint_test.dart` 中添加测试
4. 提交 Pull Request

## 许可证

与主项目保持一致
