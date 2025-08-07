import 'dart:convert';
import 'package:http/http.dart' as http;

/// 智能语言模型纠错服务
/// 结合轻量级语言模型和规则进行ASR结果纠错
class SmartTextCorrectionService {
  static final SmartTextCorrectionService _instance = SmartTextCorrectionService._internal();
  factory SmartTextCorrectionService() => _instance;
  SmartTextCorrectionService._internal();

  // 配置选项
  bool _useOnlineModel = false; // 默认关闭在线模型
  bool _useFallbackRules = true;
  String _apiEndpoint = 'https://api.openai.com/v1/chat/completions';
  String? _apiKey;
  
  // 智能调用策略
  bool _enableSmartCalling = true;
  int _maxDailyCalls = 100;        // 每日最大API调用次数
  int _dailyCallCount = 0;         // 今日已调用次数
  DateTime _lastResetDate = DateTime.now();
  
  // 置信度阈值 - 只有低置信度的结果才调用API
  double _confidenceThreshold = 0.8;  // 置信度低于80%才调用API
  
  // 缓存机制
  final Map<String, String> _correctionCache = {};
  final int _maxCacheSize = 5000;  // 增加缓存大小
  
  // 离线模式增强规则
  bool _useEnhancedOfflineRules = true;
  
  // 统计信息
  int _onlineCorrections = 0;
  int _ruleCorrections = 0;
  int _cacheHits = 0;
  int _totalRequests = 0;

  /// 设置API配置
  void configure({
    String? apiKey,
    String? apiEndpoint,
    bool? useOnlineModel,
    bool? useFallbackRules,
  }) {
    _apiKey = apiKey ?? _apiKey;
    _apiEndpoint = apiEndpoint ?? _apiEndpoint;
    _useOnlineModel = useOnlineModel ?? _useOnlineModel;
    _useFallbackRules = useFallbackRules ?? _useFallbackRules;
    
    print('[SmartCorrection] 🔧 配置更新: 在线模型=${_useOnlineModel}, 规则备用=${_useFallbackRules}');
  }

  /// 智能纠错主入口
  Future<String> correctText(String originalText) async {
    if (originalText.isEmpty) return originalText;
    
    _totalRequests++;
    _checkDailyReset();
    
    // 1. 检查缓存（优先级最高）
    if (_correctionCache.containsKey(originalText)) {
      _cacheHits++;
      return _correctionCache[originalText]!;
    }
    
    // 2. 首先使用增强离线规则（免费且快速）
    String correctedText = _useEnhancedOfflineRules ? 
        _correctWithEnhancedRules(originalText) : 
        _correctWithRules(originalText);
    
    // 3. 智能判断是否需要API调用
    bool shouldCallAPI = _shouldCallOnlineAPI(originalText, correctedText);
    
    if (shouldCallAPI) {
      try {
        String apiResult = await _correctWithLanguageModel(originalText);
        if (apiResult != originalText && apiResult.isNotEmpty) {
          _onlineCorrections++;
          _dailyCallCount++;
          _cacheResult(originalText, apiResult);
          print('[SmartCorrection] 🤖 API纠错: "$originalText" → "$apiResult" (今日第${_dailyCallCount}次调用)');
          return apiResult;
        }
      } catch (e) {
        print('[SmartCorrection] ⚠️ API调用失败，使用离线结果: $e');
      }
    }
    
    // 4. 返回离线纠错结果
    if (correctedText != originalText) {
      _ruleCorrections++;
      _cacheResult(originalText, correctedText);
    }
    
    return correctedText;
  }

  /// 检查每日调用次数重置
  void _checkDailyReset() {
    final now = DateTime.now();
    if (now.day != _lastResetDate.day || 
        now.month != _lastResetDate.month || 
        now.year != _lastResetDate.year) {
      _dailyCallCount = 0;
      _lastResetDate = now;
      print('[SmartCorrection] 🔄 每日API调用次数已重置');
    }
  }

  /// 智能判断是否需要调用在线API
  bool _shouldCallOnlineAPI(String original, String offlineResult) {
    // 1. 基础检查
    if (!_useOnlineModel || _apiKey == null || !_enableSmartCalling) {
      return false;
    }
    
    // 2. 每日额度检查
    if (_dailyCallCount >= _maxDailyCalls) {
      return false;
    }
    
    // 3. 离线纠错已经有效果，不需要API
    if (offlineResult != original) {
      return false;
    }
    
    // 4. 短文本或常见文本，不需要API
    if (original.length < 5) {
      return false;
    }
    
    // 5. 包含明显错误模式才调用API
    bool hasComplexErrors = _hasComplexErrors(original);
    
    // 6. 重要对话内容才使用API（检测关键词）
    bool isImportantContent = _isImportantContent(original);
    
    return hasComplexErrors || isImportantContent;
  }

  /// 检测复杂错误模式
  bool _hasComplexErrors(String text) {
    // 检测可能需要语言模型处理的复杂错误
    final complexPatterns = [
      RegExp(r'[一二三四五六七八九十]\w*[个只条件项]'), // 数字+量词组合
      RegExp(r'[\u4e00-\u9fff]{2,}[是的了在][\u4e00-\u9fff]{2,}'), // 可能的语序错误
      RegExp(r'[布部步不][是会能要对错]'), // 布系列错误
      RegExp(r'[医一移][下点些次声]'), // 医系列错误
      RegExp(r'[什甚神][末么模]'), // 什么变形
    ];
    
    return complexPatterns.any((pattern) => pattern.hasMatch(text));
  }

  /// 检测重要内容
  bool _isImportantContent(String text) {
    // 包含重要关键词的对话才使用API
    final importantKeywords = [
      '会议', '重要', '项目', '任务', '工作', '计划', '决定', '问题',
      '需要', '必须', '应该', '时间', '地点', '联系', '电话', '地址',
      '价格', '费用', '金额', '合同', '协议', '签约', '会面', '约定'
    ];
    
    return importantKeywords.any((keyword) => text.contains(keyword));
  }

  /// 增强版离线规则纠错
  String _correctWithEnhancedRules(String text) {
    String result = text;
    
    // 扩展的高频错误纠正词典
    final enhancedFixes = {
      // 布系列（最高频错误）
      '布是': '不是', '布会': '不会', '布能': '不能', '布要': '不要', 
      '布对': '不对', '布错': '不错', '布行': '不行', '布好': '不好',
      '布用': '不用', '布过': '不过', '布管': '不管', '布如': '不如',
      '步是': '不是', '步会': '不会', '部是': '不是', '部会': '不会',
      
      // 医系列
      '医下': '一下', '医点': '一点', '医些': '一些', '医次': '一次',
      '医声': '一声', '医个': '一个', '医天': '一天', '医年': '一年',
      '医起': '一起', '医样': '一样', '医直': '一直', '医定': '一定',
      
      // 时间相关
      '先在': '现在', '以后': '以后', '事间': '时间', '实间': '时间',
      '时后': '时候', '时侯': '时候', '那时后': '那时候', '这时后': '这时候',
      
      // 疑问词
      '什末': '什么', '甚么': '什么', '神马': '什么',
      '怎末': '怎么', '咋么': '怎么', '咋末': '怎么',
      '拿里': '哪里', '娜里': '哪里', '那里': '哪里',
      '拿么': '那么', '娜么': '那么', '着么': '这么',
      '为什末': '为什么', '为神马': '为什么',
      
      // 动作词
      '只道': '知道', '指道': '知道', '制道': '知道',
      '角得': '觉得', '脚得': '觉得', '干觉': '感觉', '赶觉': '感觉',
      '希欢': '喜欢', '西欢': '喜欢', '像要': '想要', '象要': '想要',
      '须要': '需要', '虚要': '需要', '克能': '可能', '课能': '可能',
      
      // 连词语法
      '应为': '因为', '英为': '因为', '因该': '应该', '英该': '应该',
      '单是': '但是', '弹是': '但是', '燃后': '然后', '染后': '然后',
      '茹果': '如果', '入果': '如果', '孩是': '还是', '海是': '还是',
      '火者': '或者', '获者': '或者', '党然': '当然', '挡然': '当然',
      
      // 状态词
      '恳定': '肯定', '垦定': '肯定', '必需': '必须', '毕须': '必须',
      '比角': '比较', '笔较': '比较', '没友': '没有', '没右': '没有',
      
      // 数字转换
      '1个': '一个', '2个': '两个', '3个': '三个', '4个': '四个', '5个': '五个',
      '6个': '六个', '7个': '七个', '8个': '八个', '9个': '九个', '10个': '十个',
      '第1': '第一', '第2': '第二', '第3': '第三', '第4': '第四', '第5': '第五',
      '1点': '一点', '2点': '两点', '1些': '一些', '1下': '一下', '1次': '一次',
      
      // 动作完善
      '开事': '开始', '该始': '开始', '改始': '开始',
      '解束': '结束', '街束': '结束', '界束': '结束',
      '及续': '继续', '计续': '继续', '记续': '继续',
    };
    
    // 应用增强规则
    for (final entry in enhancedFixes.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    
    // 正则表达式模式纠错
    result = _applyRegexCorrections(result);
    
    // 基本清理
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    return result;
  }

  /// 应用正则表达式纠错
  String _applyRegexCorrections(String text) {
    String result = text;
    
    // 模式纠错
    final patterns = [
      // 数字后面跟个 -> 一个、两个等
      [RegExp(r'(\d+)个'), (Match m) => _numberToChineseWithUnit(m.group(1)!, '个')],
      
      // 第+数字 -> 第一、第二等
      [RegExp(r'第(\d+)'), (Match m) => '第${_numberToChinese(m.group(1)!)}'],
      
      // 医+数字 -> 一+数字
      [RegExp(r'医(\d+)'), (Match m) => '一${m.group(1)}'],
      
      // 布+动词 -> 不+动词
      [RegExp(r'布([是会能要对错行好用过管如])'), (Match m) => '不${m.group(1)}'],
    ];
    
    for (final pattern in patterns) {
      final regex = pattern[0] as RegExp;
      final replacer = pattern[1] as String Function(Match);
      result = result.replaceAllMapped(regex, replacer);
    }
    
    return result;
  }

  /// 数字转中文
  String _numberToChinese(String number) {
    final map = {'1': '一', '2': '二', '3': '三', '4': '四', '5': '五',
                 '6': '六', '7': '七', '8': '八', '9': '九', '10': '十'};
    return map[number] ?? number;
  }

  /// 数字转中文带量词
  String _numberToChineseWithUnit(String number, String unit) {
    final chineseNum = _numberToChinese(number);
    if (number == '2' && unit == '个') return '两个';
    return '$chineseNum$unit';
  }

  /// 配置成本控制
  void configureCostControl({
    int? maxDailyCalls,
    double? confidenceThreshold,
    bool? enableSmartCalling,
    bool? useEnhancedOfflineRules,
  }) {
    _maxDailyCalls = maxDailyCalls ?? _maxDailyCalls;
    _confidenceThreshold = confidenceThreshold ?? _confidenceThreshold;
    _enableSmartCalling = enableSmartCalling ?? _enableSmartCalling;
    _useEnhancedOfflineRules = useEnhancedOfflineRules ?? _useEnhancedOfflineRules;
    
    print('[SmartCorrection] 💰 成本控制更新: 每日限额=$_maxDailyCalls, 智能调用=$_enableSmartCalling');
  }

  /// 获取成本统计
  Map<String, dynamic> getCostStats() {
    return {
      'dailyCallCount': _dailyCallCount,
      'maxDailyCalls': _maxDailyCalls,
      'remainingCalls': _maxDailyCalls - _dailyCallCount,
      'costControlEnabled': _enableSmartCalling,
      'enhancedOfflineEnabled': _useEnhancedOfflineRules,
      'estimatedDailyCost': _dailyCallCount * 0.002, // 假设每次调用0.002美元
      'cacheHitRate': _totalRequests > 0 ? _cacheHits / _totalRequests : 0.0,
    };
  }

  /// 智能纠错主入口 - 经济版本
  Future<String> correctTextEconomical(String originalText) async {
    if (originalText.isEmpty) return originalText;
    
    _totalRequests++;
    _checkDailyReset();
    
    // 1. 检查缓存（优先级最高）
    if (_correctionCache.containsKey(originalText)) {
      _cacheHits++;
      return _correctionCache[originalText]!;
    }
    
    // 2. 首先使用增强离线规则（免费且快速）
    String correctedText = _useEnhancedOfflineRules ? 
        _correctWithEnhancedRules(originalText) : 
        _correctWithRules(originalText);
    
    // 3. 智能判断是否需要API调用
    bool shouldCallAPI = _shouldCallOnlineAPI(originalText, correctedText);
    
    if (shouldCallAPI) {
      try {
        String apiResult = await _correctWithLanguageModel(originalText);
        if (apiResult != originalText && apiResult.isNotEmpty) {
          _onlineCorrections++;
          _dailyCallCount++;
          _cacheResult(originalText, apiResult);
          print('[SmartCorrection] 🤖 API纠错: "$originalText" → "$apiResult" (今日第${_dailyCallCount}次调用)');
          return apiResult;
        }
      } catch (e) {
        print('[SmartCorrection] ⚠️ API调用失败，使用离线结果: $e');
      }
    }
    
    // 4. 返回离线纠错结果
    if (correctedText != originalText) {
      _ruleCorrections++;
      _cacheResult(originalText, correctedText);
    }
    
    return correctedText;
  }

  /// 使用轻量级语言模型进行纠错
  Future<String> _correctWithLanguageModel(String text) async {
    try {
      final prompt = _buildCorrectionPrompt(text);
      
      final response = await http.post(
        Uri.parse(_apiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: json.encode({
          'model': 'gpt-4o-mini', // 轻量级模型
          'messages': [
            {
              'role': 'system',
              'content': '你是一个专业的中文语音识别结果纠错助手。只返回纠错后的文本，不要解释。'
            },
            {
              'role': 'user',
              'content': prompt
            }
          ],
          'max_tokens': 100, // 减少token使用
          'temperature': 0.1,
          'top_p': 0.9,
        }),
      ).timeout(const Duration(seconds: 2)); // 缩短超时时间

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final correctedText = data['choices'][0]['message']['content'].toString().trim();
        return correctedText;
      } else {
        throw Exception('API请求失败: ${response.statusCode}');
      }
    } catch (e) {
      print('[SmartCorrection] ❌ 语言模型纠错失败: $e');
      rethrow;
    }
  }

  /// 构建纠错提示词
  String _buildCorrectionPrompt(String text) {
    return '纠正中文ASR错误: $text';
  }

  /// 使用规则进行纠错（基础版本）
  String _correctWithRules(String text) {
    String result = text;
    
    // 基础错误纠正
    final basicFixes = {
      '布是': '不是', '布会': '不会', '先在': '现在', '什末': '什么',
      '医下': '一下', '医点': '一点', '只道': '知道', '应为': '因为',
    };
    
    for (final entry in basicFixes.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 缓存纠错结果
  void _cacheResult(String original, String corrected) {
    if (_correctionCache.length >= _maxCacheSize) {
      final keys = _correctionCache.keys.take(500).toList();
      for (final key in keys) {
        _correctionCache.remove(key);
      }
    }
    _correctionCache[original] = corrected;
  }

  /// 预热缓存
  void warmupCache() {
    final commonPairs = {
      '你好': '你好', '谢谢': '谢谢', '布是': '不是', '布会': '不会',
      '先在': '现在', '什末': '什么', '医下': '一下', '只道': '知道',
    };
    
    _correctionCache.addAll(commonPairs);
    print('[SmartCorrection] 🔥 缓存预热完成，加载${commonPairs.length}个常见纠错对');
  }

  /// 获取统计信息
  Map<String, dynamic> getStats() {
    return {
      'totalRequests': _totalRequests,
      'onlineCorrections': _onlineCorrections,
      'ruleCorrections': _ruleCorrections,
      'cacheHits': _cacheHits,
      'cacheSize': _correctionCache.length,
      'onlineSuccessRate': _totalRequests > 0 ? _onlineCorrections / _totalRequests : 0.0,
      'cacheHitRate': _totalRequests > 0 ? _cacheHits / _totalRequests : 0.0,
      'isOnlineEnabled': _useOnlineModel,
      'hasApiKey': _apiKey != null,
      'enhancedOfflineEnabled': _useEnhancedOfflineRules,
      ..._getCostStats(),
    };
  }

  /// 内部成本统计
  Map<String, dynamic> _getCostStats() {
    return {
      'dailyCallCount': _dailyCallCount,
      'maxDailyCalls': _maxDailyCalls,
      'remainingCalls': _maxDailyCalls - _dailyCallCount,
      'estimatedDailyCost': _dailyCallCount * 0.001, // 更保守的成本估算
    };
  }

  /// 清空缓存
  void clearCache() {
    _correctionCache.clear();
    print('[SmartCorrection] 🧹 缓存已清空');
  }

  /// 重置统计
  void resetStats() {
    _totalRequests = 0;
    _onlineCorrections = 0;
    _ruleCorrections = 0;
    _cacheHits = 0;
    print('[SmartCorrection] 📊 统计已重置');
  }

  /// 获取纠错统计信息（兼容方法）
  Map<String, dynamic> getCorrectionStats() {
    return getStats();
  }
}
