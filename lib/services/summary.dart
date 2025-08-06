import 'dart:convert';
import 'package:app/constants/prompt_constants.dart';
import 'package:app/models/record_entity.dart';
import 'package:app/models/summary_entity.dart';
import 'package:app/services/llm.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:intl/intl.dart';
import 'package:app/services/knowledge_graph_service.dart';

class DialogueSummary {
  // 添加回调函数类型定义
  static Function(List<SummaryEntity>)? onSummaryGenerated;

  // MainProcess, start the summarization process
  static Future<void> start({int? startTime, Function(List<SummaryEntity>)? onSummaryCallback}) async {
    try {
      // 设置回调函数
      if (onSummaryCallback != null) {
        onSummaryGenerated = onSummaryCallback;
      }

      int? startSummaryTime = startTime;
      int? endTime = ObjectBoxService().getLastRecord()?.createdAt;
      print('[DialogueSummary] start called, startSummaryTime=$startSummaryTime, endTime=$endTime');

      if (endTime == null || (endTime - startSummaryTime! < 1 * 60 * 1000)) {
        print('[DialogueSummary] return: 没有新对话�����对话过短');
        return;
      }

      if (startSummaryTime == null) {
        print('[DialogueSummary] startSummaryTime为null，尝试从summaryBox获取');
        if (!ObjectBoxService.summaryBox.isEmpty()) {
          startSummaryTime = ObjectBoxService().getLastSummary()?.endTime;
          print('[DialogueSummary] 从summaryBox获取到startSummaryTime: $startSummaryTime');
        } else {
          startSummaryTime = 0;
          print('[DialogueSummary] summaryBox为空，startSummaryTime设为0');
        }
      }

      print('[DialogueSummary] 调用_summarize, startSummaryTime=$startSummaryTime');

      // Generate summary
      var summary = await _summarize(startSummaryTime!);
      print('[DialogueSummary] _summarize返回: ${summary != null ? '有内容' : 'null'}');

      if (summary != null) {
        print('[DialogueSummary] 进入summary!=null分支');
        print('[DialogueSummary] 开始解析summary json');
        List<dynamic> summaryArray = jsonDecode(summary)["output"];
        print('[DialogueSummary] summaryArray 解析完成，长度: ${summaryArray.length}');
        print("[DialogueSummary] summaryArray 内容为: $summaryArray");

        List<SummaryEntity> summaryEntities = [];

        // Process each item in the summary array
        for (var item in summaryArray) {
          print('[DialogueSummary] 处理summary item: $item');
          String subject = item['subject'];
          String abstract = item['abstract'].toString();
          int startTime;
          int endTime;

          try {
            startTime = DateFormat("yyyy-MM-dd HH:mm:ss").parse(item['start_time']).millisecondsSinceEpoch;
            endTime = DateFormat("yyyy-MM-dd HH:mm:ss").parse(item['end_time']).millisecondsSinceEpoch;
          } catch (e) {
            // 如果没有秒，尝试用不带秒的格式解析
            startTime = DateFormat("yyyy-MM-dd HH:mm").parse(item['start_time']).millisecondsSinceEpoch;
            endTime = DateFormat("yyyy-MM-dd HH:mm").parse(item['end_time']).millisecondsSinceEpoch;
          }

          SummaryEntity summaryEntity = SummaryEntity(
            subject: subject,
            content: abstract,
            startTime: startTime,
            endTime: endTime,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            isMeeting: false,
            audioPath: null,
          );
          summaryEntities.add(summaryEntity);
        }
        print('[DialogueSummary] summaryEntities 构建完成，数量: ${summaryEntities.length}');

        // Insert the summary entities into the ObjectBox database
        await ObjectBoxService().insertSummaries(summaryEntities);
        print('[DialogueSummary] 摘要已写入数据库，数量: ${summaryEntities.length}');

        // 🔥 新增：触发摘要生成完成的回调，在聊天框中显示摘要
        print('[DialogueSummary] 🔍 检查回调函数状态: onSummaryGenerated=${onSummaryGenerated != null ? "已设置" : "未设置"}');
        print('[DialogueSummary] 🔍 检查摘要实体数量: ${summaryEntities.length}');

        if (onSummaryGenerated != null && summaryEntities.isNotEmpty) {
          print('[DialogueSummary] 🎯 触发摘要显示回调，摘要数量: ${summaryEntities.length}');
          try {
            onSummaryGenerated!(summaryEntities);
            print('[DialogueSummary] ✅ 摘要回调执行成功');
          } catch (e) {
            print('[DialogueSummary] ❌ 摘要回调执行失败: $e');
          }
        } else {
          print('[DialogueSummary] ⚠️ 摘要回调未执行 - onSummaryGenerated: ${onSummaryGenerated != null}, summaryEntities.isNotEmpty: ${summaryEntities.isNotEmpty}');
        }
      } else {
        print('[DialogueSummary] summary为null，未生成摘要');
      }
    } catch (e) {
      print("An error occurred while processing the summary: $e");
      throw Exception("An error occurred while processing the summary");
    }
  }

  // Method to generate a summary using the LLM
  static Future<String?> _summarize(int startTime) async {
    List<RecordEntity>? listRecords = ObjectBoxService().getRecordsByTimeRange(startTime, DateTime.now().millisecondsSinceEpoch);

    if (listRecords == null) {
      return null;
    }

    int contentLength = 0;
    StringBuffer chatHistoryBuffer = StringBuffer();
    for (RecordEntity record in listRecords) {
      contentLength += record.content!.length;
      String formattedTime = DateFormat("yyyy-MM-dd HH:mm")
          .format(DateTime.fromMillisecondsSinceEpoch(record.createdAt!));
      chatHistoryBuffer.write("($formattedTime) ${record.role}: ${record.content}\n");
    }

    if (contentLength < 150) {
      return null;
    }

    final chatHistory = chatHistoryBuffer.toString();

    try {
      LLM summaryLlm = await LLM.create('gpt-4o-mini', systemPrompt: systemPromptOfSummary);
      String summary = await summaryLlm.createRequest(content: getUserPromptOfSummaryGeneration(chatHistory));
      print("Initial summary: $summary");

      summaryLlm.setSystemPrompt(systemPrompt: systemPromptOfSummaryReflection);
      String comments = await summaryLlm.createRequest(content: getUserPromptOfSummaryReflectionGeneration(chatHistory, summary));
      print("Feedback: $comments");

      summaryLlm.setSystemPrompt(systemPrompt: systemPromptOfNewSummary);
      summary = await summaryLlm.createRequest(content: getUserPromptOfNewSummaryGeneration(chatHistory, summary, comments));
      print("Revised summary: $summary");

      // ========== 知识图谱处理 ==========
      // 在生成摘要后，利用已有的对话历史数据进行知识图谱事件提取
      print("[DialogueSummary] 🔗 开始执行自动知识图��事件提取...");
      try {
        print('[DialogueSummary] 调用 KnowledgeGraphService.processEventsFromConversation, chatHistory 长度: ${chatHistory.length}, contextId: ${DateTime.now().millisecondsSinceEpoch.toString()}');
        await KnowledgeGraphService.processEventsFromConversation(chatHistory, contextId: DateTime.now().millisecondsSinceEpoch.toString());
        print("[DialogueSummary] ✅ 知识图谱事件提取完成");
      } catch (e) {
        print("[DialogueSummary] ❌ 知识图谱处理失败: $e");
      }

      return summary;
    } catch (e) {
      print("An error occurred while generating the summary: $e");
      throw Exception("An error occurred while generating the summary");
    }
  }
}
