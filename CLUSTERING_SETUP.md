# 语义聚类功能设置指南

## ⚠️ 重要：Schema生成步骤

由于新增了 `ClusterNode` 和 `ClusteringMeta` 实体，需要重新生成ObjectBox schema。

### 必要步骤：

1. **重新生成ObjectBox schema**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

2. **取消注释ObjectBoxService中的聚类方法**
   
   在 `lib/services/objectbox_service.dart` 文件末尾，找到被注释的聚类相关方法区块，并：
   
   a. 添加Box声明（在类的开头，第34行附近）：
   ```dart
   static late final Box<ClusterNode> clusterNodeBox;
   static late final Box<ClusteringMeta> clusteringMetaBox;
   ```
   
   b. 在 `initialize()` 方法中添加（第74行附近）：
   ```dart
   clusterNodeBox = Box<ClusterNode>(store);
   clusteringMetaBox = Box<ClusteringMeta>(store);
   ```
   
   c. 取消注释所有聚类相关方法（第783行开始）

3. **更新SemanticClusteringService**
   
   在 `lib/services/semantic_clustering_service.dart` 中，取消以下方法的注释：
   - `_saveClusteringResults` 方法中的实际保存逻辑
   - `getAllClusters` 方法中的实际查询逻辑
   
   查找 `// 注意：` 注释并按提示更新代码。

## 功能说明

### 1. 核心特性

- **增量聚类**：只处理新增或最近30天内更新的事件，避免重复计算
- **向量聚类**：基于embedding的余弦相似度（阈值0.85）
- **时间约束**：聚类成员必须在30天时间窗口内
- **智能摘要**：使用GPT-4o-mini自动生成聚类标题和描述

### 2. 使用方式

#### 在kg_test_page.dart中：

1. **触发聚类**：点击"图谱维护"标签页中的"整理图谱"按钮
2. **查看聚类**：切换到新增的"聚类管理"标签页
3. **浏览聚类详情**：点击聚类卡片查看包含的事件节点

#### 聚类参数（可在semantic_clustering_service.dart中调整）：

```dart
static const double SIMILARITY_THRESHOLD = 0.85;  // 余弦相似度阈值
static const int TEMPORAL_WINDOW_DAYS = 30;       // 时间窗口（天）
static const int MIN_CLUSTER_SIZE = 2;            // 最小聚类大小
static const int MAX_CLUSTER_SIZE = 20;           // 最大聚类大小
```

### 3. 数据模型

#### EventNode 新增字段：
- `clusterId`: 所属聚类ID
- `mergedTo`: 被合并到某个聚类摘要节点

#### ClusterNode（新实体）：
- 聚类摘要节点，包含聚类标题、描述、成员列表
- 有自己的embedding（成员向量的中心点）
- 记录成员数量、平均相似度、时间范围等统计信息

#### ClusteringMeta（新实体）：
- 记录每次聚类操作的元数据
- 包括聚类时间、参数、结果统计等

### 4. 向量查询优化

聚类完成后，向量查询会自动：
- 优先返回聚类摘要节点（代表一组相关事件）
- 过滤掉已被合并的原始事件节点
- 支持通过聚类展开查看所有成员

## 故障排查

### 问题1：编译错误 - "Undefined class 'ClusterNode'"

**解决方案**：
1. 确认已运行 `flutter pub run build_runner build`
2. 检查 `lib/models/objectbox.g.dart` 是否包含ClusterNode和ClusteringMeta的定义

### 问题2：聚类按钮点击无响应

**解决方案**：
1. 检查是否有事件节点包含embedding（可在"数据验证"标签中检查）
2. 运行"为所有事件生成向量"按钮确保所有事件都有embedding

### 问题3：聚类结果不理想

**解决方案**：
1. 调整 `SIMILARITY_THRESHOLD`（降低会生成更多聚类）
2. 调整 `TEMPORAL_WINDOW_DAYS`（增大会允许更远时间跨度的事件聚类）
3. 检查事件的embedding质量

## 后续优化建议

1. **自动触发聚类**：在系统空闲时自动执行聚类
2. **聚类质量评估**：添加聚类质量指标和可视化
3. **手动调整**：允许用户手动合并/拆分聚类
4. **聚类重命名**：支持用户自定义聚类标题
5. **向量索引优化**：使用专门的向量数据库加速检索

## 性能优化

- 当事件数量 < 100时，聚类速度很快（< 5秒）
- 事件数量 100-500时，预计10-30秒
- 事件数量 > 500时，建议使用更高效的聚类算法（如HDBSCAN）
