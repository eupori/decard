import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  static const _key = 'decard_device_id';
  static String? _cached;

  static Future<String> getDeviceId() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_key, id);
    }
    _cached = id;
    return id;
  }
}
