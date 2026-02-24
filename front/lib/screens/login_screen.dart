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

              // 구글 로그인 (목업)
              _SocialLoginButton(
                onPressed: () => _showComingSoon(context, 'Google'),
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF444444),
                icon: _googleIcon(),
                label: 'Google로 시작하기',
                border: true,
              ),

              const SizedBox(height: 12),

              // 애플 로그인 (목업)
              _SocialLoginButton(
                onPressed: () => _showComingSoon(context, 'Apple'),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.apple_rounded, size: 22, color: Colors.white),
                label: 'Apple로 시작하기',
              ),

              const SizedBox(height: 28),

              // 구분선
              Row(
                children: [
                  Expanded(child: Divider(color: cs.outlineVariant)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '또는',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ),
                  Expanded(child: Divider(color: cs.outlineVariant)),
                ],
              ),

              const SizedBox(height: 28),

              // 이메일 회원가입 (목업)
              OutlinedButton.icon(
                onPressed: () => _showComingSoon(context, '이메일 회원가입'),
                icon: const Icon(Icons.email_outlined, size: 20),
                label: const Text('이메일로 시작하기'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),

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

  void _showComingSoon(BuildContext context, String provider) {
    showSuccessSnackBar(context, '$provider 로그인은 준비 중입니다.');
  }

  Widget _kakaoIcon() {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _KakaoLogoPainter()),
    );
  }

  Widget _googleIcon() {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
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
  final bool border;

  const _SocialLoginButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
    this.border = false,
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
            side: border
                ? const BorderSide(color: Color(0xFFDADADA))
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
// 구글 로고 (G)
// ──────────────────────────────────────

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = w * 0.42;

    // 간단한 G 로고 — 4색 원호
    final strokeW = w * 0.18;

    void drawArc(double start, double sweep, Color color) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.butt,
      );
    }

    const pi = 3.14159265;
    drawArc(-pi * 0.15, -pi * 0.55, const Color(0xFF4285F4)); // 파랑 (상단 우)
    drawArc(-pi * 0.7, -pi * 0.35, const Color(0xFF34A853)); // 초록 (하단 좌)
    drawArc(-pi * 1.05, -pi * 0.35, const Color(0xFFFBBC05)); // 노랑 (하단 좌)
    drawArc(-pi * 1.4, -pi * 0.35, const Color(0xFFEA4335)); // 빨강 (상단 좌)

    // 가운데 가로선
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + r + strokeW * 0.3, cy),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
