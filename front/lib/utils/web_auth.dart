import 'package:web/web.dart' as web;

/// 웹 URL fragment에서 토큰 추출: /#token=xxx
/// hash 클리어는 별도로 clearUrlFragment()를 호출해야 함
String? extractTokenFromUrl() {
  final fragment = web.window.location.hash; // e.g. "#token=abc123"
  if (fragment.startsWith('#token=')) {
    return fragment.substring(7); // remove "#token="
  }
  return null;
}

/// 웹 URL fragment에서 에러 추출: /#auth_error=xxx
String? extractAuthErrorFromUrl() {
  final fragment = web.window.location.hash;
  if (fragment.startsWith('#auth_error=')) {
    return fragment.substring(12);
  }
  return null;
}

/// URL fragment 제거 (토큰 저장 완료 후 호출)
void clearUrlFragment() {
  web.window.location.hash = '';
}

/// 같은 탭에서 URL로 이동 (웹 전용)
void navigateTo(String url) {
  web.window.location.href = url;
}
