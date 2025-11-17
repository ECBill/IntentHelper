# 语义聚类系统架构图

## 系统流程图

```
┌─────────────────────────────────────────────────────────────────┐
│                   语义聚类系统完整流程                              │
└─────────────────────────────────────────────────────────────────┘

1️⃣ 数据准备阶段
┌──────────────────────────────────────────────────────────────┐
│  用户对话记录                                                   │
│  ↓                                                             │
│  KnowledgeGraphService.processEventsFromConversation()        │
│  ↓                                                             │
│  创建 EventNode (name, type, description, embedding...)       │
│  ↓                                                             │
│  ObjectBox 数据库存储                                           │
└──────────────────────────────────────────────────────────────┘

2️⃣ 向量生成阶段
┌──────────────────────────────────────────────────────────────┐
│  [UI] 图谱维护 → "为所有事件生成向量"                            │
│  ↓                                                             │
│  KnowledgeGraphService.generateEmbeddingsForAllEvents()       │
│  ↓                                                             │
│  EmbeddingService.generateEventEmbedding()                    │
│  ↓                                                             │
│  调用 Embedding API (384维向量)                                │
│  ↓                                                             │
│  EventNode.embedding = [0.123, -0.456, ...]                  │
└──────────────────────────────────────────────────────────────┘

3️⃣ 语义聚类阶段
┌──────────────────────────────────────────────────────────────┐
│  [UI] 图谱维护 → "整理图谱（语义聚类）"                          │
│  ↓                                                             │
│  SemanticClusteringService.organizeGraph()                    │
│  ↓                                                             │
│  ┌─────────────────────────────────────────────┐              │
│  │ 1. 获取候选事件 (增量策略)                    │              │
│  │    - 未聚类的事件 (clusterId == null)        │              │
│  │    - 最近30天更新/访问的事件                   │              │
│  │    - 必须有 embedding                        │              │
│  └─────────────────────────────────────────────┘              │
│  ↓                                                             │
│  ┌─────────────────────────────────────────────┐              │
│  │ 2. 执行聚类算法                               │              │
│  │    算法: 凝聚层次聚类 (Agglomerative)          │              │
│  │    相似度: 余弦相似度 > 0.85                   │              │
│  │    时间约束: 成员跨度 ≤ 30天                   │              │
│  │    大小限制: 2 ≤ 成员数 ≤ 20                   │              │
│  └─────────────────────────────────────────────┘              │
│  ↓                                                             │
│  ┌─────────────────────────────────────────────┐              │
│  │ 3. 生成聚类摘要                               │              │
│  │    - 计算聚类中心向量 (成员均值)                │              │
│  │    - GPT-4o-mini 生成标题                     │              │
│  │    - 统计元数据 (大小、相似度、时间范围)         │              │
│  │    - 创建 ClusterNode                        │              │
│  └─────────────────────────────────────────────┘              │
│  ↓                                                             │
│  ┌─────────────────────────────────────────────┐              │
│  │ 4. 更新成员事件                               │              │
│  │    EventNode.clusterId = cluster.id          │              │
│  │    EventNode.mergedTo = cluster.id (可选)    │              │
│  └─────────────────────────────────────────────┘              │
│  ↓                                                             │
│  ┌─────────────────────────────────────────────┐              │
│  │ 5. 保存结果                                   │              │
│  │    - ClusterNode → ObjectBox                 │              │
│  │    - ClusteringMeta (元数据记录)              │              │
│  └─────────────────────────────────────────────┘              │
└──────────────────────────────────────────────────────────────┘

4️⃣ 查询优化阶段
┌──────────────────────────────────────────────────────────────┐
│  [UI] 事件向量查询 → 输入查询文本                               │
│  ↓                                                             │
│  KnowledgeGraphService.searchEventsByText()                   │
│  ↓                                                             │
│  ┌─────────────────────────────────────────────┐              │
│  │ 1. 过滤已合并事件                              │              │
│  │    candidates = events.where(                │              │
│  │      e => e.mergedTo == null                 │              │
│  │    )                                         │              │
│  └─────────────────────────────────────────────┘              │
│  ↓                                                             │
│  ┌─────────────────────────────────────────────┐              │
│  │ 2. 向量相似度召回                              │              │
│  │    cosineSim(query, event) > threshold       │              │
│  └─────────────────────────────────────────────┘              │
│  ↓                                                             │
│  ┌─────────────────────────────────────────────┐              │
│  │ 3. 优先级评分排序                              │              │
│  │    考虑: 相似度 + 时间衰减 + 激活历史            │              │
│  └─────────────────────────────────────────────┘              │
│  ↓                                                             │
│  返回结果 (聚类摘要 + 独立事件)                                  │
└──────────────────────────────────────────────────────────────┘

5️⃣ 聚类展示阶段
┌──────────────────────────────────────────────────────────────┐
│  [UI] 聚类管理 → 查看所有聚类                                   │
│  ↓                                                             │
│  ┌────────────────────────────────────┐                       │
│  │ 聚类卡片 (可折叠)                    │                       │
│  │ ┌────────────────────────────────┐ │                       │
│  │ │ 📊 聚类标题                      │ │                       │
│  │ │ 描述: 包含4个相关事件             │ │                       │
│  │ │ 时间: 01/15 - 02/03              │ │                       │
│  │ └────────────────────────────────┘ │                       │
│  │ [展开后显示成员事件列表]             │                       │
│  │ • 事件1 (类型 • 日期)               │                       │
│  │ • 事件2 (类型 • 日期)               │                       │
│  │ • 事件3 (类型 • 日期)               │                       │
│  │ • 事件4 (类型 • 日期)               │                       │
│  └────────────────────────────────────┘                       │
└──────────────────────────────────────────────────────────────┘
```

## 数据模型关系图

```
EventNode (事件节点)
├─ id: String                    // 唯一标识
├─ name: String                  // 事件名称
├─ type: String                  // 事件类型
├─ description: String?          // 描述
├─ embedding: List<double>       // 384维向量
├─ clusterId: String?            // ⭐ 所属聚类ID
├─ mergedTo: String?             // ⭐ 合并到的聚类ID
├─ startTime: DateTime?          // 开始时间
└─ lastUpdated: DateTime         // 更新时间

         ↓ 聚类关系
         
ClusterNode (聚类节点)          ⭐ 新增
├─ id: String                    // 聚类唯一标识
├─ name: String                  // GPT生成的标题
├─ type: String = "cluster"      // 固定为cluster
├─ description: String           // 聚类描述
├─ embedding: List<double>       // 聚类中心向量
├─ memberIdsJson: String         // 成员ID列表(JSON)
├─ memberCount: int              // 成员数量
├─ avgSimilarity: double         // 平均相似度
├─ earliestEventTime: DateTime?  // 最早事件时间
├─ latestEventTime: DateTime?    // 最晚事件时间
├─ createdAt: DateTime           // 创建时间
└─ lastUpdated: DateTime         // 更新时间

         ↓ 元数据记录
         
ClusteringMeta (聚类元数据)     ⭐ 新增
├─ clusteringTime: DateTime      // 聚类执行时间
├─ totalEvents: int              // 参与事件数
├─ clustersCreated: int          // 创建的聚类数
├─ eventsClustered: int          // 已聚类事件数
├─ eventsUnclustered: int        // 未聚类事件数
├─ algorithmUsed: String         // 算法名称
├─ parametersJson: String        // 参数(JSON)
├─ avgClusterSize: double        // 平均聚类大小
└─ avgIntraClusterSimilarity: double  // 平均类内相似度
```

## 聚类算法伪代码

```python
function organizeGraph(forceRecluster=false):
    # 1. 获取候选事件
    candidates = []
    for event in all_events:
        if event.embedding.isEmpty:
            continue
        if forceRecluster:
            candidates.add(event)
        elif event.clusterId is null:
            candidates.add(event)
        elif event.lastUpdated > (now - 30 days):
            candidates.add(event)
    
    # 2. 执行聚类
    clusters = []
    assigned = set()
    
    for i, event_i in enumerate(candidates):
        if i in assigned:
            continue
            
        cluster = [event_i]
        assigned.add(i)
        
        for j, event_j in enumerate(candidates[i+1:], i+1):
            if j in assigned:
                continue
            
            # 计算相似度
            similarity = cosine_similarity(
                event_i.embedding, 
                event_j.embedding
            )
            
            if similarity >= 0.85:
                # 检查时间约束
                if check_temporal_constraint(cluster + [event_j]):
                    cluster.add(event_j)
                    assigned.add(j)
                    
                    if len(cluster) >= 20:  # 最大聚类大小
                        break
        
        if len(cluster) >= 2:  # 最小聚类大小
            clusters.add(cluster)
    
    # 3. 生成聚类摘要
    for cluster in clusters:
        # 计算中心向量
        centroid = mean([e.embedding for e in cluster])
        
        # 生成标题
        titles = [e.name for e in cluster[:10]]
        cluster_title = generate_title_by_gpt(titles)
        
        # 创建聚类节点
        cluster_node = ClusterNode(
            id = f"cluster_{timestamp}",
            name = cluster_title,
            embedding = centroid,
            memberIds = [e.id for e in cluster],
            memberCount = len(cluster),
            avgSimilarity = calculate_avg_similarity(cluster),
            ...
        )
        
        # 更新成员事件
        for event in cluster:
            event.clusterId = cluster_node.id
            event.save()
        
        cluster_node.save()
    
    # 4. 保存元数据
    meta = ClusteringMeta(
        clusteringTime = now,
        totalEvents = len(candidates),
        clustersCreated = len(clusters),
        ...
    )
    meta.save()
    
    return clusters
```

## 向量检索流程图

```
用户查询: "机器学习"
    ↓
生成查询向量 embedding_query
    ↓
┌────────────────────────────────────────┐
│ 获取所有事件 (过滤已合并)                  │
│ activeEvents = events.where(            │
│   e => e.mergedTo == null               │
│ )                                       │
└────────────────────────────────────────┘
    ↓
┌────────────────────────────────────────┐
│ 计算相似度并召回                          │
│ for event in activeEvents:              │
│   sim = cosine(embedding_query,         │
│                event.embedding)         │
│   if sim > 0.2:                         │
│     candidates.add(event, sim)          │
└────────────────────────────────────────┘
    ↓
┌────────────────────────────────────────┐
│ 优先级评分排序                            │
│ 考虑因素:                                │
│ • 余弦相似度 (权重: 0.5)                  │
│ • 时间衰减 (权重: 0.3)                    │
│ • 激活历史 (权重: 0.2)                    │
└────────────────────────────────────────┘
    ↓
┌────────────────────────────────────────┐
│ 返回Top-K结果                            │
│ 结果中可能包含:                           │
│ • ClusterNode (type = "cluster")        │
│   - 代表一组相似事件                      │
│   - 可展开查看成员                        │
│ • EventNode (独立事件)                   │
│   - 未被聚类的事件                        │
│   - 或聚类外的高相关事件                   │
└────────────────────────────────────────┘
    ↓
用户在UI中查看结果
    ↓
点击聚类卡片展开
    ↓
调用 expandClusterMembers(clusterId)
    ↓
显示聚类中的所有成员事件
```

## 性能分析

### 时间复杂度

- **聚类算法**: O(n²) - 凝聚层次聚类
- **向量搜索**: O(n) - 线性扫描
- **优先级评分**: O(n log n) - 排序

### 优化策略

1. **增量聚类**: 只处理候选事件，不是全量
2. **过滤合并节点**: 减少搜索空间
3. **向量索引**: 未来可使用HNSW索引加速
4. **批处理**: 分批处理大量事件

### 预期性能

```
事件数量 | 聚类耗时 | 查询耗时
--------|---------|--------
< 100   | < 5s    | < 100ms
100-500 | 10-30s  | < 200ms
500-1000| 30-120s | < 500ms
> 1000  | 需优化   | 需索引
```

## 总结

这个语义聚类系统通过以下核心技术实现了高效的知识组织：

1. **向量表示**: 使用384维embedding捕捉语义信息
2. **增量聚类**: 只处理增量数据，提高效率
3. **智能摘要**: GPT-4o-mini生成人类可读的聚类标题
4. **查询优化**: 过滤已合并节点，减少重复结果
5. **用户友好**: 可视化界面，支持交互式浏览

系统设计遵循了最小修改原则，在现有架构基础上优雅地扩展了聚类功能。
