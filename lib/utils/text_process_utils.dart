class TextProcessUtils {
  static String removeBracketsContent(String text) {
    return text.replaceAll(RegExp(r'\[.*?\]|\{.*?\}'), '');
  }

  static String clearIfRepeatedMoreThanFiveTimes(String text) {
    return text.replaceAllMapped(
      RegExp(r'\b([^,\s]+)(?:[\s,]+\1\b){5,}', caseSensitive: false),
          (match) => match.group(1)!,
    );
  }
}
