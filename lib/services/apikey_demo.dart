import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

void main() async {
  final url = Uri.parse('https://one-api.bud.inc/v1/chat/completions');
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer M20lUdvsllJ1Yuub3dBeF709Bf024064AcAaF0A37fDf4c57' // 替换为你的API KEY
  };
  final now = DateTime.now();
  final timeContext = "${now.year}年${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日";
  // final prompt = '''你是一个信息抽取智能体，任务是从真实日常对话中提取两类信息：\n第一类：状态类信息（Status Information） 这类信息具有结构化、唯一性强、可更新的特点，通常是关于人物、时间、地点、身份、关系、属性等的“静态事实”，�������为、动作、计划等“事件描述”不需要提取。\n请将状态类信息提取为三元组格式： （主体，属性，属性值） 注意：主体默认为“我”或对话中提到的其他人物；如果信息来自推断（如根据语气、上下文判断关系），也可以提取；一条对话中可能包含多个三元组。\n第二类：事件类信息（Event Information） 这类信息具有非结构化、多样性强�����不可替代的特点，通常是关于人物在某时某地做了什么、发生了什么、说了什么、有哪些附属信息。\n请将事件类信息概括为自然语言句子，完整、具体、准确，便于后续存入向量数据库，该总结归类就归类，该详细记录就记录，信息的核心围绕“我”服务。\n输出格式要求：第一部分是状态类信息，格式为 JSON 数组，每个元素是一个三元组；第二部分是事件类信息，��式为 JSON 数组，每个元素是一个完整的自然语言句子。\n注意：只输出纯 JSON，不要包含 ```json 或 ``` 等 markdown 语法。\n现在请从以下对话���提取信息：\n对话历史如下（请开始分析）：我昨天和小明去看了电影，电影很精彩。''';
  final prompt = """
你是一个知识图谱构建助手。请从我提供的对话中提取出结构化的知识图谱信息，输出格式为 JSON，包含以下部分：

1. nodes：实体节点数组，每个节点结构如下：
{
  "id": "唯一标识（可用name type组合）",
  "name": "实体名称",
  "type": "实体类型（如 手机、人、事件、政策）",
  "attributes": {
    "属性名1": "属性值1",
    "属性名2": "属性值2"
  }
}

2. edges：关系边数组，每个边结构如下：
{
  "source": "源实体ID",
  "relation": "关系类型（如 使用、购买、建议）",
  "target": "目标实体ID或值",
  "context": "可选：上下文描述，如对话原文",
  "timestamp": "可选：时间戳或日期"
}

请保持字段标准化，确保结果可以被 JSON 解析器直接解析。

对话内容如下：
别人：其实以后可以玩点像海龟汤这种文字类的桌游也不错。
我：对，推理类的、储存文字的那种也挺有意思。
别人：那种游戏重点更多是在交流上，不是游戏机制。
我：对，更能体现一个人的表达和思考能力，不光是对游戏的理解。
别人：你看我下一次就肯定比今天打得好，熟悉了游戏机制之后肯定更顺。
别人：我记得你以前不是挺喜欢那个狮子的吗？
我：你说狮子林佳琪？
别人：对对对，他不是现在不做了嘛？
我：对啊，早就凉了，不带货了。
别人：哎，打桌游还是挺开心的。
别人：CV为什么不跟我们玩？四个人一起玩多舒服啊。
我：CV看不上我们这种局。
别人：快把刚刚那个不认识的哥们也叫上。
别人：他说他03年上大学来着。
我：哎对了，我跟你们说，我回家那会儿去网吧，刚进去，有俩人问我：“你们是刚毕业的？”我说，“还没毕业。”
别人：他们以为你是高中生？
我：不是，是初中生！完全看不出我都快研究生毕业了。
别人：哈哈哈哈，真的假的。
我：我当时听完真的有点开心。
别人：年轻真好。
我：以前没觉得，现在是真感觉跟年轻人比确实有差距了。
别人：那你也比我们俩小吧。
我：我们三个刚好是99、00、01的。

""";
  final body = jsonEncode({
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "user", "content": prompt}
    ]
  });
  try {
    final response = await http.post(url, headers: headers, body: body);
    print('状态码: ${response.statusCode}');
    print('返回内容:\n${response.body}');
    // 用 UTF-8 解码 response.bodyBytes，确保中文不乱码
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final content = data['choices']?[0]?['message']?['content'];
    print('模型输出内容:');
    print(content);
    // 也可以尝试如下方式：
    // print(String.fromCharCodes(contentStr.runes));
  } catch (e) {
    print('请求异常: $e');
  }
}
