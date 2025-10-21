/// KG历史记录模型
class KGHistoryEntry {
  final DateTime windowStart;
  final String summary;

  KGHistoryEntry({required this.windowStart, required this.summary});

  factory KGHistoryEntry.fromJson(Map<String, dynamic> json) {
    return KGHistoryEntry(
      windowStart: DateTime.parse(json['windowStart'] as String),
      summary: json['summary'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'windowStart': windowStart.toIso8601String(),
      'summary': summary,
    };
  }
}
