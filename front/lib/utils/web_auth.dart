import 'package:web/web.dart' as web;

/// 웹 URL fragment에서 토큰 추출: /#token=xxx
String? extractTokenFromUrl() {
  final fragment = web.window.location.hash; // e.g. "#token=abc123"
  if (fragment.startsWith('#token=')) {
    final token = fragment.substring(7); // remove "#token="
    // fragment만 제거 (Flutter 히스토리와 충돌 방지)
    web.window.location.hash = '';
    return token;
  }
  return null;
}

/// 웹 URL fragment에서 에러 추출: /#auth_error=xxx
String? extractAuthErrorFromUrl() {
  final fragment = web.window.location.hash;
  if (fragment.startsWith('#auth_error=')) {
    final error = fragment.substring(12);
    web.window.location.hash = '';
    return error;
  }
  return null;
}

/// 같은 탭에서 URL로 이동 (웹 전용)
void navigateTo(String url) {
  web.window.location.href = url;
}
