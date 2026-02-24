import 'dart:math';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _cardsController;
  late final AnimationController _textController;
  late final AnimationController _fadeOutController;

  // 로고: 바운스 스케일
  late final Animation<double> _logoScale;

  // 카드 3장: 팬 아웃
  late final Animation<double> _cardsFan;

  // 텍스트: 슬라이드 + 페이드
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;

  // 페이드 아웃
  late final Animation<double> _fadeOut;

  @override
  void initState() {
    super.initState();

    // 1) 로고 바운스 (0 → 600ms)
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoScale = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    );

    // 2) 카드 팬 아웃 (200ms → 800ms)
    _cardsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _cardsFan = CurvedAnimation(
      parent: _cardsController,
      curve: Curves.easeOutBack,
    );

    // 3) 텍스트 슬라이드 인 (500ms → 1000ms)
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _textOpacity = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeIn,
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: Curves.easeOutCubic,
    ));

    // 4) 전체 페이드 아웃 (1600ms → 1900ms)
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeOutController, curve: Curves.easeIn),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    // 로고 등장
    _logoController.forward();

    // 200ms 후 카드 팬 아웃
    await Future.delayed(const Duration(milliseconds: 200));
    _cardsController.forward();

    // 500ms 후 텍스트
    await Future.delayed(const Duration(milliseconds: 300));
    _textController.forward();

    // 잠시 머문 후 페이드 아웃
    await Future.delayed(const Duration(milliseconds: 900));
    await _fadeOutController.forward();

    // 메인 화면으로 이동
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const MainScreen(),
          transitionDuration: Duration.zero,
        ),
      );
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _cardsController.dispose();
    _textController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : AppTheme.navy;

    return AnimatedBuilder(
      animation: _fadeOut,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeOut.value,
          child: Scaffold(
            backgroundColor: bgColor,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 카드 + 로고 영역
                  SizedBox(
                    width: 200,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 뒤쪽 카드 3장 (팬 아웃)
                        ..._buildFanCards(),
                        // 중앙 로고
                        ScaleTransition(
                          scale: _logoScale,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppTheme.mint,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.mint.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.style_rounded,
                              size: 40,
                              color: AppTheme.navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 앱 이름
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textOpacity,
                      child: const Text(
                        '데카드',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 부제
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textOpacity,
                      child: Text(
                        'PDF를 넣으면, 암기카드가 나온다',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.6),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildFanCards() {
    // 3장의 미니 카드가 부채꼴로 펼쳐짐
    const cardColors = [
      Color(0xFF6290C3), // blue
      Color(0xFF4A7FB5), // slightly darker blue
      Color(0xFFC2E7DA), // mint
    ];
    const angles = [-25.0, 0.0, 25.0]; // 회전 각도
    const offsets = [
      Offset(-30, -8),
      Offset(0, -15),
      Offset(30, -8),
    ];

    return List.generate(3, (i) {
      return AnimatedBuilder(
        animation: _cardsFan,
        builder: (context, child) {
          final progress = _cardsFan.value;
          final angle = angles[i] * progress * (pi / 180);
          final dx = offsets[i].dx * progress;
          final dy = offsets[i].dy * progress;

          return Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.translationValues(dx, dy, 0)
              ..rotateZ(angle),
            child: Opacity(
              opacity: progress.clamp(0.0, 1.0),
              child: Container(
                width: 52,
                height: 72,
                decoration: BoxDecoration(
                  color: cardColors[i].withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    i == 2
                        ? Icons.auto_awesome_rounded
                        : Icons.description_rounded,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
