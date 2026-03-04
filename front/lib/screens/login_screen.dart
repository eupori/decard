import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_helper.dart';
import '../utils/web_auth_stub.dart'
    if (dart.library.html) '../utils/web_auth.dart' as web_nav;

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('로그인'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // 로고
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(Icons.style_rounded, size: 36, color: cs.primary),
              ),
              const SizedBox(height: 20),
              Text(
                '데카드에 오신 것을 환영합니다',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '로그인하면 기기 간 데이터가 동기화됩니다.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),

              const SizedBox(height: 40),

              // 카카오 로그인
              _SocialLoginButton(
                onPressed: () => _handleKakaoLogin(context),
                backgroundColor: const Color(0xFFFEE500),
                foregroundColor: const Color(0xFF191919),
                icon: _kakaoIcon(),
                label: '카카오로 시작하기',
              ),

              const SizedBox(height: 12),

              // Google 로그인
              _SocialLoginButton(
                onPressed: () => _handleGoogleLogin(context),
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1F1F1F),
                icon: _googleIcon(),
                label: 'Google로 시작하기',
                borderColor: const Color(0xFFDADCE0),
              ),

              // Apple 로그인 (iOS/macOS만)
              if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) ...[
                const SizedBox(height: 12),
                _SocialLoginButton(
                  onPressed: () => _handleAppleLogin(context),
                  backgroundColor: cs.brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  foregroundColor: cs.brightness == Brightness.dark
                      ? Colors.black
                      : Colors.white,
                  icon: Icon(
                    Icons.apple_rounded,
                    size: 22,
                    color: cs.brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white,
                  ),
                  label: 'Apple로 시작하기',
                ),
              ],

              const SizedBox(height: 32),

              // 안내 문구
              Text(
                '로그인 없이도 사용 가능합니다.\n로그인하면 여러 기기에서 카드를 관리할 수 있어요.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.6,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleKakaoLogin(BuildContext context) async {
    if (kIsWeb) {
      final url = AuthService.getKakaoLoginUrl();
      web_nav.navigateTo(url);
    } else {
      try {
        final url = '${AuthService.getKakaoLoginUrl()}?platform=mobile';
        final result = await FlutterWebAuth2.authenticate(
          url: url,
          callbackUrlScheme: 'decard',
        );
        final uri = Uri.parse(result);
        final token = uri.queryParameters['token'];
        final error = uri.queryParameters['error'];
        if (token != null && context.mounted) {
          await AuthService.setToken(token);
          await AuthService.linkDevice();
          if (context.mounted) {
            showSuccessSnackBar(context, '로그인되었습니다!');
            Navigator.pop(context, true);
          }
        } else if (error != null && context.mounted) {
          showErrorSnackBar(context, '로그인에 실패했습니다. 다시 시도해주세요.');
        }
      } catch (e) {
        if (context.mounted) {
          showErrorSnackBar(context, '로그인이 취소되었습니다.');
        }
      }
    }
  }

  Future<void> _handleGoogleLogin(BuildContext context) async {
    final error = await AuthService.loginWithGoogle();
    if (!context.mounted) return;
    if (error == null) {
      showSuccessSnackBar(context, '로그인되었습니다!');
      Navigator.pop(context, true);
    } else {
      showErrorSnackBar(context, error);
    }
  }

  Future<void> _handleAppleLogin(BuildContext context) async {
    final error = await AuthService.loginWithApple();
    if (!context.mounted) return;
    if (error == null) {
      showSuccessSnackBar(context, '로그인되었습니다!');
      Navigator.pop(context, true);
    } else {
      showErrorSnackBar(context, error);
    }
  }

  Widget _googleIcon() {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }

  Widget _kakaoIcon() {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _KakaoLogoPainter()),
    );
  }

}

// ──────────────────────────────────────
// 소셜 로그인 버튼 위젯
// ──────────────────────────────────────

class _SocialLoginButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Widget icon;
  final String label;
  final Color? borderColor;

  const _SocialLoginButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: borderColor != null
                ? BorderSide(color: borderColor!, width: 1)
                : BorderSide.none,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────
// 카카오 로고 (말풍선)
// ──────────────────────────────────────

class _KakaoLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF191919)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h * 0.42;
    final rx = w * 0.44;
    final ry = h * 0.34;

    // 말풍선 몸체 (타원)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      paint,
    );

    // 꼬리
    final path = Path()
      ..moveTo(cx - w * 0.1, cy + ry * 0.75)
      ..lineTo(cx - w * 0.18, h * 0.92)
      ..lineTo(cx + w * 0.05, cy + ry * 0.85)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ──────────────────────────────────────
// Google 로고 (4색 G)
// ──────────────────────────────────────

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Google "G" 로고 (간소화 4색)
    final rect = Rect.fromLTWH(0, 0, w, h);

    // 파랑 (오른쪽)
    final blue = Paint()..color = const Color(0xFF4285F4)..style = PaintingStyle.fill;
    canvas.drawArc(rect, -0.5, 1.8, true, blue);

    // 초록 (아래 오른쪽)
    final green = Paint()..color = const Color(0xFF34A853)..style = PaintingStyle.fill;
    canvas.drawArc(rect, 1.3, 1.0, true, green);

    // 노랑 (아래 왼쪽)
    final yellow = Paint()..color = const Color(0xFFFBBC05)..style = PaintingStyle.fill;
    canvas.drawArc(rect, 2.3, 0.7, true, yellow);

    // 빨강 (위 왼쪽)
    final red = Paint()..color = const Color(0xFFEA4335)..style = PaintingStyle.fill;
    canvas.drawArc(rect, 3.0, 1.05, true, red);

    // 중앙 흰 원 (도넛 모양)
    final white = Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.fill;
    final innerRect = Rect.fromCenter(center: Offset(w/2, h/2), width: w*0.55, height: h*0.55);
    canvas.drawOval(innerRect, white);

    // 오른쪽 가로 바
    canvas.drawRect(
      Rect.fromLTWH(w * 0.5, h * 0.38, w * 0.48, h * 0.24),
      blue,
    );
    // 흰색 내부
    canvas.drawRect(
      Rect.fromLTWH(w * 0.5, h * 0.44, w * 0.38, h * 0.12),
      white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
