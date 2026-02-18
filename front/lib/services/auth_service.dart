import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'device_service.dart';

class AuthService {
  static const _tokenKey = 'decard_jwt_token';
  static String? _cachedToken;
  static Map<String, dynamic>? _cachedUser;

  // ── Token ──

  static Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
    return _cachedToken;
  }

  static Future<void> setToken(String token) async {
    _cachedToken = token;
    _cachedUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> clearToken() async {
    _cachedToken = null;
    _cachedUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ── Kakao Login URL ──

  static String getKakaoLoginUrl() => ApiConfig.kakaoLoginUrl;

  // ── User ──

  static Future<Map<String, dynamic>?> getUser() async {
    if (_cachedUser != null) return _cachedUser;

    final token = await getToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse(ApiConfig.authMeUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        _cachedUser = jsonDecode(response.body) as Map<String, dynamic>;
        return _cachedUser;
      } else {
        // 토큰 만료 등
        await clearToken();
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  // ── Link Device ──

  static Future<void> linkDevice() async {
    final token = await getToken();
    if (token == null) return;

    final deviceId = await DeviceService.getDeviceId();
    try {
      await http.post(
        Uri.parse(ApiConfig.linkDeviceUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'X-Device-ID': deviceId,
        },
      );
    } catch (_) {
      // 실패해도 무시 (세션 연동은 best-effort)
    }
  }

  // ── Logout ──

  static Future<void> logout() async {
    await clearToken();
  }
}
