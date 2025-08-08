import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

void main() async {
  // 首先加载 .env 文件
  await dotenv.load(fileName: ".env");

  final url = Uri.parse('https://xiaomi.dns.navy/v1/chat/completions'); // 使用你的代理服务器
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${dotenv.env['OPENAI_API_KEY'] ?? ''}' // 注意这里要加Bearer前缀
  };
  final now = DateTime.now();
  final timeContext = "${now.year}年${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日";
  // final prompt = '''你是一个信息抽取智能体，任务是从真实日常对���中提取两类信息���\n第一类：状态类信息（Status Information） 这类信息具有结构化、唯一性强、可更新的特点，通常是关于人物、时间、地点、身份、关系、属性等的“静态事实”，�������为、动作、计划等“事件描述”不需要提取。\n请将状态类信息提取为三元组格式： （主体，属性，属性值） 注意：主体默认为“我”或对话中提到的其他人物；如果信息来自推断（如根据语气、上下文判断关系），也可以提取；一条对话中可能包含多个三元组。\n第二类：事件类信息（Event Information） 这类信息具有非结构化、多样性强�����不可替代的特点，通常是关于人物在某时某地做了什么、发生了什么、说了什么、有哪些附属信息。\n请将事件类信息概括为自然语言句子，完整、��体、准确，便于后续存入向量数据库，该总结归类就归类，该详细记录就记录，信息的核心围绕“我”服务。\n输出格式要求：第一部分是状态类信息，格式为 JSON 数组，每个元素是一个三元组；第二部分是事件类信息，��式为 JSON 数组，每个元素是一个完整的自然语言句子。\n注意：只输出纯 JSON，不要包含 ```json 或 ``` 等 markdown 语法。\n现在请从以下��话���提取信息：\n对话历史如下（请开始分析）：我昨天和小明去看了电影，电影很精彩。''';
  final prompt = """
你是一个知识图谱构建助手。请从我提供的对话中提取出结构化的知识图谱信息，输出格式为 JSON，包含以下部分：

1. nodes：实体节点数组，每个节点请尽量补全所有可推断的属性，节点结构如下：
{
  "id": "唯一标识（可用name type组合）",
  "name": "实体名称",
  "type": "实体类型（如 人、事件、地点、物品、组织、时间等）",
  "attributes": {
    "属性名1": "属性值1",
    "属性名2": "属性值2"
  }（属性字典，尽量补全如时间、地点、参与人、方式、原因、结果、别名、相关事件、常见活动等）
}

2. edges：关系边数组，请尽量发现并补全所有显式和隐含的关系，每个边结构如下：
{
  "source": "源实体ID",
  "relation": "关系类型（如 参与、发生在、属于、使用、拥有、同地点、同时间、同参与人等）",
  "target": "目标实体ID或值",
  "context": "可选：上下文描述，如对话原文",
  "timestamp": "可选：时间戳或日期"
}

特别要求：
对于事件类节点，务必补全发生时间、地点、相关人物等属性。
对于地点、人物等实体，补全别名、相关事件、常见活动等属性。
对于对话中未直接表达但可推断的联系，也请补全。
输出内容要尽量详细、全面，避免遗漏有用信息。
请保持字段标准化，确保结果可以被 JSON 解析器直接解析。

对话内容如下：
别人：真的很清楚坚果过得怎么样
我：还行啊就今天才刚开始
别人：也是哦那你今天有什么计划吗
我：天天的话在家写代码中午的话那个开会我准备翘掉了因为内容没错完
别人：重额的信息呢要不你先跟负责人说一下进度看看能不能晚点参
我：不是的我们组会都是你跟老板讨论你的进度那你没有进度你就不需要跟他讨论什么了吗
别人：是这样啊
别人：觉得还是跟老板说一声比较好不然他可能会觉得你不重视这个会
我：嗯我是打算跟他说一下的要不说的话还是有点问题的
别人：说一声比较好这样也显得你比���负责嘛那你除了开会和携代码今天还有别的事儿吗
别人：今年案晚上要出去约会
别人：这谁呀新交的女朋友吗也不算性交吧都已经相处半年了
别人：久了呢看来你们感情不错呀今晚准备去哪儿玩
我：新晚去五角场场吃粒粒
别人：焦成好吃的可多啦颗粒饼超美味呢吃完还能在附近逛逛看看有没有好玩的
我：是有这个打
���人：希望你们今晚玩的开心多拍点照片哦
我：啊数据已经数集句差不多了你可以下了
别人：要是还有什么想聊的随时都能找我哦

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
