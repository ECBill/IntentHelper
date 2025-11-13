# 两阶段聚类优化方案

## 📋 背景与问题

### 原有聚类问题
1. **主题区分度不高**：聚类结果如"生活与策略讨论"、"生活与工作的交流"、"合作与生活安排"等标题相似度高，缺乏区分度
2. **细粒度不足**：饮食与游戏等不同主题混在同一聚类中，未能独立分类
3. **异类混聚**：公司合作、风控算法、婚礼计划、朋友圈分享等不相关事件被聚在一起
4. **时间窗口限制**：30天窗口限制妨碍了全局主题的聚合

### 问题根源分析
- **语义表示不足**：仅使用事件标题生成embedding，缺少内容语义信息
- **单阶段聚类局限**：使用单一相似度阈值，无法同时满足粗分和细分的需求
- **距离度量单一**：GTE-small模型偏向通用句向量，对"讨论"、"计划"等通用词敏感，导致主题混杂

## 🎯 优化方案

### 1. 联合嵌入（Joint Embedding）

#### 实现方式
```dart
// 生成联合嵌入：标题 + 内容的加权组合
Future<List<double>?> _generateJointEmbedding(EventNode event) async {
  // 生成标题embedding
  final titleEmbedding = await _embeddingService.generateTextEmbedding(event.name);
  
  // 生成内容embedding（描述+目的+结果）
  final contentText = event.getEmbeddingText();
  final contentEmbedding = await _embeddingService.generateTextEmbedding(contentText);
  
  // 加权组合：标题权重0.7，内容权重0.3
  final jointEmbedding = <double>[];
  for (int i = 0; i < titleEmbedding.length; i++) {
    jointEmbedding.add(
      TITLE_WEIGHT * titleEmbedding[i] + CONTENT_WEIGHT * contentEmbedding[i]
    );
  }
  
  return jointEmbedding;
}
```

#### 优势
- 标题提供核心主题信息（权重0.7）
- 内容提供细节和上下文（权重0.3）
- 增强了语义区分能力

### 2. 两阶段聚类（Two-Stage Clustering）

#### 第一阶段：主题粗分

**目标**：将事件分为高层次主题类别（生活、学业、娱乐、技术、工作等）

**参数设置**：
```dart
static const double STAGE1_SIMILARITY_THRESHOLD = 0.70;  // 较低阈值
static const int STAGE1_MIN_CLUSTER_SIZE = 3;            // 至少3个事件
static const int STAGE1_MAX_CLUSTER_SIZE = 100;          // 可容纳大量事件
```

**特点**：
- 使用较低相似度阈值（0.70），容纳更多主题变化
- 不强制时间约束，允许跨时间聚合
- 生成宽泛的主题分类标题（如"生活与日常事务"、"学业与学术研究"）

#### 第二阶段：类内细分

**目标**：在每个主题簇内进行细粒度聚类（饮食、游戏、论文、婚礼等）

**参数设置**：
```dart
static const double STAGE2_SIMILARITY_THRESHOLD = 0.85;  // 较高阈值
static const int STAGE2_MIN_CLUSTER_SIZE = 2;            // 至少2个事件
static const int STAGE2_MAX_CLUSTER_SIZE = 15;           // 不宜过大
```

**特点**：
- 使用较高相似度阈值（0.85），严格区分细节
- 纯度检查：新成员与簇中心相似度必须>0.72
- 生成具体标题（如"饮食·海底捞讨论"、"游戏·连段技巧"）

### 3. 簇合并与纯度检查

#### 簇合并
```dart
static const double MERGE_SIMILARITY_THRESHOLD = 0.86;

// 尝试合并到现有聚类
for (final cluster in existingClusters) {
  final similarity = calculateCosineSimilarity(
    event.embedding,
    cluster.embedding,
  );
  
  if (similarity >= MERGE_SIMILARITY_THRESHOLD) {
    // 合并到该聚类
    event.clusterId = cluster.id;
  }
}
```

#### 纯度检查
```dart
static const double PURITY_THRESHOLD = 0.72;

bool _checkPurity(List<EventNode> cluster, EventNode newMember) {
  final centroid = _calculateCentroid(cluster);
  final similarity = calculateCosineSimilarity(
    newMember.embedding,
    centroid,
  );
  
  return similarity >= PURITY_THRESHOLD;
}
```

### 4. 标题生成优化

#### 第一层标题（主题层）
- 要求：宽泛的主题分类（8-12字）
- 示例：
  - "生活与日常事务"
  - "学业与学术研究"
  - "娱乐与休闲活动"
  - "技术与工作事项"

#### 第二层标题（细分层）
- 要求：具体而有区分度（8-15字）
- 格式：主类·子类
- 示例：
  - "饮食·火锅餐厅体验"
  - "游戏·装备与技巧"
  - "论文·深度学习研究"
  - "旅行·酒店预订计划"

**避免泛化词**：不使用"讨论"、"交流"、"事务"等作为主要内容

## 🔧 新增接口

### 1. 全量初始化聚类
```dart
// 对所有历史事件执行两阶段聚类
Future<Map<String, dynamic>> clusterInitAll({
  Function(String)? onProgress,
}) async {
  // 1. 获取所有有embedding的事件
  // 2. 更新联合嵌入
  // 3. 执行两阶段聚类
  // 4. 保存结果
}
```

**使用场景**：
- 首次启用两阶段聚类
- 重新组织全部历史数据
- 算法参数调整后的全量重聚

### 2. 按日期范围聚类
```dart
// 对指定时间段内的事件聚类并合并入既有结构
Future<Map<String, dynamic>> clusterByDateRange({
  required DateTime startDate,
  required DateTime endDate,
  Function(String)? onProgress,
}) async {
  // 1. 获取日期范围内的事件
  // 2. 更新联合嵌入
  // 3. 尝试合并到现有聚类
  // 4. 对未合并事件执行新聚类
}
```

**使用场景**：
- 增量聚类特定时间段的事件
- 导入历史数据后的局部聚类
- 按月/周定期聚类

### 3. 增强的organizeGraph方法
```dart
// 主要聚类方法，支持单阶段或两阶段模式
Future<Map<String, dynamic>> organizeGraph({
  bool forceRecluster = false,
  bool useTwoStage = true,  // 默认使用两阶段
  Function(String)? onProgress,
}) async
```

**参数说明**：
- `forceRecluster`: 是否强制重新聚类所有事件
- `useTwoStage`: 是否使用两阶段聚类（默认true，可回退到单阶段）
- `onProgress`: 进度回调函数

## 📊 质量监控

### 聚类质量指标
```dart
Future<Map<String, dynamic>> getClusteringQualityMetrics() async {
  return {
    'total_clusters': 聚类总数,
    'avg_intra_similarity': 平均类内相似度,
    'avg_cluster_size': 平均聚类大小,
    'outlier_ratio': 离群点比例,
    'avg_inter_distance': 平均类间距离,
    'quality_score': 综合质量评分,
  };
}
```

### 离群点检测与重分配
```dart
Future<Map<String, dynamic>> detectAndReassignOutliers({
  Function(String)? onProgress,
}) async {
  // 1. 检测每个聚类中的离群点（与中心相似度<0.72）
  // 2. 尝试将离群点重分配到其他更合适的聚类
  // 3. 无法重分配的标记为单例
}
```

## 🗂️ 数据模型更新

### ClusterNode 新增字段
```dart
@Entity()
class ClusterNode {
  // ... 原有字段 ...
  
  // 两阶段聚类支持字段
  int level;                  // 聚类层级：1=主题层，2=细分层
  String? parentClusterId;    // 父聚类ID（仅level=2时有效）
  
  ClusterNode({
    // ... 原有参数 ...
    this.level = 2,           // 默认为细分层
    this.parentClusterId,
  });
}
```

## 📈 预期效果

### 1. 主题区分度提升
- **原有**：
  - "生活与策略讨论"
  - "生活与工作的交流"
  - "合作与生活安排"
  
- **优化后**：
  - 第一层：
    - "生活与日常事务"
    - "工作与职业发展"
  - 第二层：
    - "饮食·餐厅体验" → "饮食·海底捞讨论"、"饮食·魏家凉皮"
    - "游戏·娱乐体验" → "游戏·连段技巧"、"游戏·装备问题"
    - "工作·项目合作" → "工作·公司合作"、"工作·技术讨论"

### 2. 聚类纯度提升
- 饮食类事件独立成簇，不与游戏混杂
- 游戏相关事件细分为装备、技巧、抽卡等子类
- 技术工作类事件不与个人生活混合

### 3. 标题可读性提升
- 避免"讨论"、"交流"等泛化词
- 使用"主类·子类"格式增强层次感
- 标题直接反映核心内容

## 🔄 迁移指南

### 从单阶段迁移到两阶段

1. **数据准备**：
   ```dart
   // 确保所有EventNode都有embedding
   await knowledgeGraphService.generateEmbeddingsForAllEvents();
   ```

2. **执行全量初始化聚类**：
   ```dart
   final result = await clusteringService.clusterInitAll(
     onProgress: (msg) => print(msg),
   );
   ```

3. **验证结果**：
   ```dart
   final metrics = await clusteringService.getClusteringQualityMetrics();
   print('质量评分: ${metrics['quality_score']}');
   print('离群点比例: ${metrics['outlier_ratio']}');
   ```

4. **处理离群点**（可选）：
   ```dart
   final outlierResult = await clusteringService.detectAndReassignOutliers(
     onProgress: (msg) => print(msg),
   );
   ```

### 向后兼容性

代码完全向后兼容，可通过参数控制：

```dart
// 使用两阶段聚类（推荐）
await clusteringService.organizeGraph(useTwoStage: true);

// 使用单阶段聚类（向后兼容）
await clusteringService.organizeGraph(useTwoStage: false);
```

## 🎓 使用建议

### 初次使用
1. 使用 `clusterInitAll()` 对全量数据初始化聚类
2. 检查质量指标，调整阈值参数（如需要）
3. 运行离群点检测和重分配

### 日常使用
1. 定期执行 `clusterByDateRange()` 处理新增数据
2. 或使用 `organizeGraph(useTwoStage: true)` 进行增量聚类
3. 定期检查质量指标

### 参数调优
如果聚类效果不理想，可以调整以下参数：

```dart
// 第一阶段：主题不够宽泛 → 降低阈值
static const double STAGE1_SIMILARITY_THRESHOLD = 0.65; // 从0.70降到0.65

// 第二阶段：细分不够 → 提高阈值
static const double STAGE2_SIMILARITY_THRESHOLD = 0.88; // 从0.85提高到0.88

// 纯度检查：聚类内离群点多 → 提高阈值
static const double PURITY_THRESHOLD = 0.75; // 从0.72提高到0.75
```

## 📝 注意事项

1. **首次运行耗时较长**：全量聚类需要对所有事件更新联合嵌入，建议在后台执行
2. **LLM调用成本**：每个聚类都会调用GPT-4o-mini生成标题，大量聚类会产生API费用
3. **存储空间增加**：level=1和level=2的聚类节点都会保存，存储空间会略有增加
4. **旧聚类清理**：如果需要，可以手动清理旧的单阶段聚类节点

## 🔮 未来优化方向

1. **自动参数调优**：根据质量指标自动调整阈值参数
2. **增量标题更新**：当聚类成员变化时，自动更新标题
3. **聚类可视化**：在UI中展示两层聚类的树形结构
4. **主题标签提取**：自动为每个聚类提取关键词标签
5. **模型升级**：如果两阶段聚类效果仍不理想，考虑更换更专业的嵌入模型

## 📖 相关文档

- [CLUSTERING_ARCHITECTURE.md](CLUSTERING_ARCHITECTURE.md) - 原有架构文档
- [CLUSTERING_USAGE_GUIDE.md](CLUSTERING_USAGE_GUIDE.md) - 使用指南
- [CLUSTERING_README.md](CLUSTERING_README.md) - 功能总结
