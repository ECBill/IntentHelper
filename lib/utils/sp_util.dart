import 'package:shared_preferences/shared_preferences.dart';

class SPUtil {
  static const String sp_key_member_remain_quota = 'sp_key_member_remain_quota';
  static const String sp_key_member_expiredTime = 'sp_key_member_expiredTime';

  static Future<int?> getInt(String key) async {
    SharedPreferences instance = await SharedPreferences.getInstance();
    int? result = instance.getInt(key);
    return result;
  }

  static Future<bool> setInt(String key, int value) async {
    SharedPreferences instance = await SharedPreferences.getInstance();
    bool result = await instance.setInt(key, value);
    return result;
  }
}
