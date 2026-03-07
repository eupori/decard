import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
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

  // ── Google Login ──

  static Future<String?> loginWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: kIsWeb
            ? null
            : '374766262600-jqjj2tptpjvk3hktnsrj5mroj2moj0ds.apps.googleusercontent.com',
      );
      final account = await googleSignIn.signIn();
      if (account == null) return null; // 사용자 취소

      final auth = await account.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;

      if (idToken == null && accessToken == null) {
        return '토큰을 가져올 수 없습니다.';
      }

      final response = await http.post(
        Uri.parse(ApiConfig.googleVerifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (idToken != null) 'id_token': idToken,
          if (accessToken != null) 'access_token': accessToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String;
        await setToken(token);
        await linkDevice();
        return null; // 성공
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['detail'] as String? ?? '로그인에 실패했습니다.';
      }
    } catch (e) {
      return 'Google 로그인 오류: $e';
    }
  }

  // ── Apple Login ──

  static Future<String?> loginWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) return '토큰을 가져올 수 없습니다.';

      final response = await http.post(
        Uri.parse(ApiConfig.appleVerifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_token': idToken,
          'nonce': rawNonce,
          'full_name': credential.givenName != null
              ? '${credential.familyName ?? ''} ${credential.givenName}'.trim()
              : null,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String;
        await setToken(token);
        await linkDevice();
        return null; // 성공
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['detail'] as String? ?? '로그인에 실패했습니다.';
      }
    } catch (e) {
      if (e.toString().contains('AuthorizationErrorCode.canceled')) {
        return null; // 사용자 취소 — 에러 아님
      }
      return '로그인 중 오류가 발생했습니다.';
    }
  }

  static String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  // ── Delete Account ──

  static Future<bool> deleteAccount() async {
    final token = await getToken();
    if (token == null) return false;

    try {
      final response = await http.delete(
        Uri.parse(ApiConfig.deleteAccountUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        await clearToken();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
