# Bud App 本地数据导出/导入说明文档

## 1. 导出说明

- 通过设置页“Export Data”功能，可以将所有本地 ObjectBox 数据库内容导出为结构化 JSON 文件。
- 导出文件名格式：`objectbox_export_2025-09-28Txx-xx-xx.json`，保存在 app 的文档目录（可通过系统分享面板发送到微信、邮箱等）。
- 导出内容包含所有主要实体，结构如下：

```json
{
  "todoEntities": [ ... ],
  "recordEntities": [ ... ],
  "summaryEntities": [ ... ],
  "eventNodeEntities": [ ... ],
  "llmConfigEntities": [ ... ],
  "speakerEntities": [ ... ],
  "eventRelationEntities": [ ... ],
  "nodeEntities": [ ... ],
  "edgeEntities": [ ... ]
}
```

- 每个 key 对应一个实体表，value 是该表所有数据的数组，每个元素为该实体的字段 map。
- 字段名与实体类完全一致，便于自动映射。

## 2. 导入建议

- 重装 app 后，可通过“导入”功能将上述 JSON 文件内容恢复到本地数据库。
- 导入流程建议：
  1. 选择导出的 JSON 文件（可用文件选择器或直接粘贴内容）。
  2. 解析 JSON，依次读取每个实体数组。
  3. 对于每个实体数组，遍历每个元素，构造对应的实体对象（如 TodoEntity.fromJson(json)），并插入到 ObjectBox 数据库。
  4. 建议先清空数据库再导入，避免主键冲突或重复。
  5. 如有新旧结构不一致，可在 fromJson 时做兼容处理。

- 示例伪代码：

```dart
final json = jsonDecode(exportedJsonString);
for (final todo in json['todoEntities']) {
  final entity = TodoEntity.fromJson(todo);
  todoBox.put(entity);
}
// 其它实体同理
```

- 注意事项：
  - 导入时建议关闭自动生成主键（如 id/obxId），以便保留原有数据关联。
  - 导入前可备份当前数据库，防止数据丢失。
  - 如有大文件，导入过程可能较慢。

## 3. Copilot 提示

- Copilot 可根据本说明文档和导出 JSON 结构，自动生成批量导入各实体的代码。
- 如需自动适配新字段或结构变更，可在 fromJson 方法中做兼容。
- 如需进一步自动化导入流程，可实现 UI 按钮触发导入、进度提示等。

---

如有问题可随时补充！本说明文档可直接交给 Copilot 作为导入功能开发的参考。
