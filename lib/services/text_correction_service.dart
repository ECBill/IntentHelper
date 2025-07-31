/// 文本纠错服务 - 针对ASR识别结果进行拼音和语义纠错
class TextCorrectionService {
  static final TextCorrectionService _instance = TextCorrectionService._internal();
  factory TextCorrectionService() => _instance;
  TextCorrectionService._internal();

  // 拼音相近词替换映射
  static const Map<String, List<String>> _pinyinSimilarWords = {
    // 声母混淆
    '不': ['布', '步', '部'],
    '的': ['得', '地', '德'],
    '是': ['事', '试', '适', '室'],
    '在': ['再', '载', '栽'],
    '他': ['她', '它', '塔'],
    '了': ['啦', '拉', '辣'],
    '有': ['友', '右', '由', '游'],
    '这': ['着', '者', '折'],
    '个': ['各', '格', '歌'],
    '我': ['握', '沃', '卧'],
    '就': ['旧', '救', '九'],
    '会': ['汇', '慧', '回', '灰'],
    '能': ['年', '嫩', '内'],
    '说': ['水', '谁', '税'],
    '都': ['读', '毒', '独'],
    '要': ['药', '摇', '窑', '腰'],
    '可': ['课', '克', '刻'],
    '还': ['孩', '海', '害'],
    '来': ['累', '类', '泪'],
    '去': ['取', '趣', '区'],
    '看': ['刊', '砍', '堪'],
    '好': ['号', '毫', '豪'],
    '时': ['十', '失', '师', '诗'],
    '年': ['念', '粘', '捻'],
    '天': ['田', '甜', '添'],
    '家': ['加', '夹', '嘉'],
    '手': ['首', '守', '受'],
    '心': ['新', '信', '星'],
    '水': ['谁', '税', '睡'],
    '火': ['或', '货', '获'],
    '电': ['店', '点', '典'],
    '车': ['茶', '查', '叉'],
    '开': ['该', '改', '盖'],
    '学': ['雪', '血', '靴'],
    '工': ['公', '功', '攻'],
    '作': ['坐', '做', '昨'],
    '生': ['声', '升', '胜'],
    '现': ['先', '线', '限'],
    '想': ['像', '向', '象'],
    '知': ['只', '指', '制', '治'],
    '道': ['到', '倒', '刀'],
    '问': ['闻', '文', '温'],
    '题': ['提', '体', '替'],
    '听': ['停', '庭', '亭'],
    '话': ['化', '华', '画'],
    '语': ['雨', '鱼', '于', '与'],
    '言': ['眼', '研', '严'],
    '字': ['自', '子', '紫'],
    '意': ['异', '易', '艺', '议'],
    '思': ['丝', '死', '四', '寺'],
    '理': ['里', '立', '历', '力'],
    '解': ['街', '界', '借'],
    '明': ['名', '命', '鸣'],
    '白': ['百', '柏', '拜'],
    '法': ['发', '罚', '乏'],
    '方': ['房', '防', '访'],
    '式': ['市', '事', '试'],
    '种': ['重', '中', '钟', '终'],
    '类': ['累', '雷'],
    '系': ['洗', '喜', '细', '西'],
    '统': ['通', '同', '痛', '童'],
    '关': ['观', '官', '管', '惯'],
    '键': ['见', '建', '健', '件'],
    '重': ['中', '钟', '终'],
    '点': ['店', '电', '典'],
    '容': ['融', '荣', '绒'],
    '信': ['新', '心', '星', '兴'],
    '息': ['吸', '席', '惜'],
    '数': ['树', '书', '舒', '述'],
    '据': ['具', '聚', '句', '巨'],
    '分': ['份', '粉', '奋', '愤'],
    '析': ['西', '惜', '席', '吸'],
  };

  // 常见错误词组替换
  static const Map<String, String> _commonErrorCorrections = {
    // 常见语法错误
    '地话': '的话',
    '得话': '的话',
    '在拿里': '在哪里',
    '在娜里': '在哪里',
    '什末': '什么',
    '神马': '什么',
    '甚么': '什么',
    '怎末': '怎么',
    '咋么': '怎么',
    '咋末': '怎么',
    '为什末': '为什么',
    '为神马': '为什么',
    '那个时后': '那个时候',
    '那个时侯': '那个时候',
    '这个时后': '这个时候',
    '这个时侯': '这个时候',
    '一顶要': '一定要',
    '因为所以': '因为',
    '应为': '因为',
    '英为': '因为',
    '锁以': '所以',
    '索以': '所以',
    '单是': '但是',
    '弹是': '但是',
    '燃后': '然后',
    '染后': '然后',
    '茹果': '如果',
    '入果': '如果',
    '拿么': '那么',
    '娜么': '那么',
    '着么': '这么',
    '折么': '这么',
    '先在': '现在',
    '线在': '现在',
    '只道': '知道',
    '指道': '知道',
    '人为': '认为',
    '仍为': '认为',
    '角得': '觉得',
    '脚得': '觉得',
    '干觉': '感觉',
    '赶觉': '感觉',
    '希欢': '喜欢',
    '西欢': '喜欢',
    '像要': '想要',
    '象要': '想要',
    '须要': '需要',
    '虚要': '需要',
    '克能': '可能',
    '课能': '可能',
    '英该': '应该',
    '因该': '应该',
    '必需': '必须',
    '毕须': '必须',
    '一只': '一直',
    '医直': '一直',
    '以经': '已经',
    '一经': '已经',
    '孩是': '还是',
    '海是': '还是',
    '火者': '或者',
    '获者': '或者',
    '比角': '比较',
    '笔较': '比较',
    '党然': '当然',
    '挡然': '当然',
    '恳定': '肯定',
    '垦定': '肯定',
    '以定': '一定',
    '医定': '一定',
    '没友': '没有',
    '没右': '没有',
    '布会': '不会',
    '部会': '不会',
    '布能': '不能',
    '部能': '不能',
    '布要': '不要',
    '部要': '不要',
    '布好': '不好',
    '部好': '不好',
    '布对': '不对',
    '部对': '不对',
    '布是': '不是',
    '部是': '不是',
    '布错': '不错',
    '部错': '不错',
    '没措': '没错',
    '没做': '没错',
  };

  // 数字和量词纠错
  static const Map<String, String> _numberUnitCorrections = {
    '1个': '一个',
    '壹个': '一个',
    '2个': '两个',
    '俩个': '两个',
    '3个': '三个',
    '仨个': '三个',
    '4个': '四个',
    '死个': '四个',
    '5个': '五个',
    '无个': '五个',
    '6个': '六个',
    '溜个': '六个',
    '7个': '七个',
    '齐个': '七个',
    '8个': '八个',
    '巴个': '八个',
    '9个': '九个',
    '久个': '九个',
    '10个': '十个',
    '事个': '十个',
    '1点': '一点',
    '医点': '一点',
    '2点': '两点',
    '亮点': '两点',
    '1些': '一些',
    '医些': '一些',
    '1下': '一下',
    '医下': '一下',
    '1次': '一次',
    '医次': '一次',
    '第1': '第一',
    '弟一': '第一',
    '第2': '第二',
    '弟二': '第二',
    '第3': '第三',
    '弟三': '第三',
  };

  // 语义上下文纠错
  static const Map<String, Map<String, String>> _contextCorrections = {
    // 时间相关
    '时间': {
      '实间': '时间',
      '事间': '时间',
      '始间': '时间',
    },
    '现在': {
      '先在': '现在',
      '线在': '现在',
      '限在': '现在',
    },
    '以后': {
      '一后': '以后',
      '医后': '以后',
      '已后': '以后',
    },
    '之前': {
      '只前': '之前',
      '指前': '之前',
      '制前': '之前',
    },
    // 地点相关
    '这里': {
      '着里': '这里',
      '折里': '这里',
      '者里': '这里',
    },
    '那里': {
      '拿里': '那里',
      '娜里': '那里',
    },
    '哪里': {
      '那里': '哪里',
      '拿里': '哪里',
      '娜里': '哪里',
    },
    // 动作相关
    '开始': {
      '开事': '开始',
      '该始': '开始',
      '改始': '开始',
    },
    '结束': {
      '解束': '结束',
      '街束': '结束',
      '界束': '结束',
    },
    '继续': {
      '及续': '继续',
      '计续': '继续',
      '记续': '继续',
    },
  };

  /// 纠正ASR识别结果
  String correctText(String originalText) {
    if (originalText.isEmpty) return originalText;

    String correctedText = originalText;

    // 1. 基本清理
    correctedText = _basicCleanup(correctedText);

    // 2. 常见错误词组替换
    correctedText = _applyCommonCorrections(correctedText);

    // 3. 数字和量词纠错
    correctedText = _correctNumbersAndUnits(correctedText);

    // 4. 拼音相近词替换（基于上下文）
    correctedText = _correctPinyinSimilar(correctedText);

    // 5. 语义上下文纠错
    correctedText = _correctContextual(correctedText);

    // 6. 最终清理
    correctedText = _finalCleanup(correctedText);

    if (correctedText != originalText) {
      print('[TextCorrection] 🔧 纠错: "$originalText" → "$correctedText"');
    }

    return correctedText;
  }

  /// 基本清理
  String _basicCleanup(String text) {
    // 移除多余的空格
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    // 移除首尾空格
    text = text.trim();
    // 移除重复的标点
    text = text.replaceAll(RegExp(r'[。，！？；：]{2,}'), '。');
    text = text.replaceAll(RegExp(r'[,，]{2,}'), '，');
    text = text.replaceAll(RegExp(r'[!！]{2,}'), '！');
    text = text.replaceAll(RegExp(r'[?？]{2,}'), '？');

    return text;
  }

  /// 应用常见错误纠正
  String _applyCommonCorrections(String text) {
    String result = text;

    _commonErrorCorrections.forEach((error, correction) {
      result = result.replaceAll(error, correction);
    });

    return result;
  }

  /// 纠正数字和量词
  String _correctNumbersAndUnits(String text) {
    String result = text;

    _numberUnitCorrections.forEach((error, correction) {
      result = result.replaceAll(error, correction);
    });

    return result;
  }

  /// 拼音相近词纠错（基于简单上下文）
  String _correctPinyinSimilar(String text) {
    List<String> words = text.split('');

    for (int i = 0; i < words.length; i++) {
      String word = words[i];

      // 检查是否需要替换
      _pinyinSimilarWords.forEach((correct, similars) {
        if (similars.contains(word)) {
          // 简单的上下文检查
          String context = '';
          if (i > 0) context += words[i-1];
          if (i < words.length - 1) context += words[i+1];

          // 基于上下文决定是否替换
          if (_shouldReplace(word, correct, context)) {
            words[i] = correct;
          }
        }
      });
    }

    return words.join('');
  }

  /// 语义上下文纠错
  String _correctContextual(String text) {
    String result = text;

    _contextCorrections.forEach((category, corrections) {
      corrections.forEach((error, correction) {
        result = result.replaceAll(error, correction);
      });
    });

    return result;
  }

  /// 判断是否应该替换（简单的上下文逻辑）
  bool _shouldReplace(String current, String target, String context) {
    // 如果上下文包含某些关键词，则倾向于替换
    if (context.contains('的') && (target == '的' || target == '得' || target == '地')) {
      return target == '的';
    }

    if (context.contains('在') && (target == '在' || target == '再')) {
      return target == '在';
    }

    if (context.contains('时') && target == '时') {
      return true;
    }

    // 默认不替换，除非有强烈的上下文指示
    return false;
  }

  /// 最终清理
  String _finalCleanup(String text) {
    // 移除多余的空格
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    text = text.trim();

    // 确保标点符号前没有空格
    text = text.replaceAll(RegExp(r'\s+([。，！？；：])'), r'$1');

    return text;
  }

  /// 获取纠错统计信息
  Map<String, int> getCorrectionStats() {
    return {
      'pinyinWords': _pinyinSimilarWords.length,
      'commonErrors': _commonErrorCorrections.length,
      'numberUnits': _numberUnitCorrections.length,
      'contextRules': _contextCorrections.length,
    };
  }
}
