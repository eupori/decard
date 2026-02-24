import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/card_model.dart';
import '../utils/cloze_text.dart';

class StudyScreen extends StatefulWidget {
  final List<CardModel> cards;
  final String title;

  const StudyScreen({super.key, required this.cards, required this.title});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen>
    with TickerProviderStateMixin {
  late List<CardModel> _cards;
  int _currentIndex = 0;
  bool _showBack = false;
  bool _isCompleted = false;
  double _dragOffset = 0;

  late AnimationController _slideController;
  Offset _slideAnimOffset = Offset.zero;
  double _animRotation = 0;
  double _animOpacity = 1.0;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _cards = List.from(widget.cards)..shuffle(Random());
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _animateSlideOut(int direction) async {
    if (_isAnimating) return;
    _isAnimating = true;

    final screenWidth = MediaQuery.of(context).size.width;
    final endX = direction == 1 ? -screenWidth : screenWidth;

    // 드래그 상태에서 이어받기
    final startX = _dragOffset * 0.7;
    final startRotation = _dragOffset * 0.0003;
    final startOpacity = (1 - (_dragOffset.abs() / 200)).clamp(0.3, 1.0);

    _slideAnimOffset = Offset(startX, 0);
    _animRotation = startRotation;
    _animOpacity = startOpacity;
    _dragOffset = 0;

    // 슬라이드 아웃: 현재 위치 → 화면 밖
    _slideController.reset();
    _slideController.duration = const Duration(milliseconds: 250);
    late VoidCallback slideOutListener;
    slideOutListener = () {
      final t = Curves.easeInCubic.transform(_slideController.value);
      setState(() {
        _slideAnimOffset = Offset(startX + (endX - startX) * t, 0);
        _animRotation = startRotation + (endX * 0.0003 - startRotation) * t;
        _animOpacity = (startOpacity * (1 - t)).clamp(0.0, 1.0);
      });
    };
    _slideController.addListener(slideOutListener);
    await _slideController.forward();
    _slideController.removeListener(slideOutListener);

    // 인덱스 변경
    setState(() {
      if (direction == 1 && _currentIndex < _cards.length - 1) {
        _currentIndex++;
      } else if (direction == -1 && _currentIndex > 0) {
        _currentIndex--;
      }
      _showBack = false;
      _slideAnimOffset = Offset(-endX * 0.3, 0);
      _animRotation = 0;
      _animOpacity = 1.0;
    });

    HapticFeedback.mediumImpact();

    // 슬라이드 인: 반대쪽에서 → 중앙
    _slideController.reset();
    _slideController.duration = const Duration(milliseconds: 200);
    final slideInStart = -endX * 0.3;
    late VoidCallback slideInListener;
    slideInListener = () {
      final t = Curves.easeOutCubic.transform(_slideController.value);
      setState(() {
        _slideAnimOffset = Offset(slideInStart * (1 - t), 0);
      });
    };
    _slideController.addListener(slideInListener);
    await _slideController.forward();
    _slideController.removeListener(slideInListener);

    _slideController.duration = const Duration(milliseconds: 300);
    _isAnimating = false;
    _slideAnimOffset = Offset.zero;
    setState(() {});
  }

  void _next() {
    if (_currentIndex < _cards.length - 1 && !_isAnimating) {
      _animateSlideOut(1);
    }
  }

  void _prev() {
    if (_currentIndex > 0 && !_isAnimating) {
      _animateSlideOut(-1);
    }
  }

  void _reshuffle() {
    if (_currentIndex > 0 && !_isCompleted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('카드 섞기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('현재 ${_currentIndex + 1}/${_cards.length}장째입니다.\n섞으면 처음부터 다시 시작됩니다.'),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _doReshuffle();
                      },
                      child: const Text('섞기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      _doReshuffle();
    }
  }

  void _doReshuffle() {
    setState(() {
      _cards.shuffle(Random());
      _currentIndex = 0;
      _showBack = false;
      _isCompleted = false;
      _dragOffset = 0;
      _slideAnimOffset = Offset.zero;
      _animRotation = 0;
      _animOpacity = 1.0;
      _isAnimating = false;
    });
  }

  void _springBack() {
    final startOffset = _dragOffset;
    _slideController.reset();
    _slideController.duration = const Duration(milliseconds: 200);
    late VoidCallback listener;
    listener = () {
      setState(() {
        _dragOffset = startOffset *
            (1 - Curves.easeOutCubic.transform(_slideController.value));
      });
    };
    _slideController.addListener(listener);
    _slideController.forward().then((_) {
      _slideController.removeListener(listener);
      _slideController.duration = const Duration(milliseconds: 300);
      setState(() => _dragOffset = 0);
    });
  }

  void _complete() {
    setState(() => _isCompleted = true);
  }

  TextStyle _responsiveTextStyle(int length) {
    final base = Theme.of(context).textTheme;
    if (length <= 20) {
      return base.headlineSmall!.copyWith(
        height: 1.6,
        fontWeight: FontWeight.w600,
      );
    } else if (length <= 80) {
      return base.titleLarge!.copyWith(
        height: 1.6,
        fontWeight: FontWeight.w600,
      );
    } else {
      return base.titleMedium!.copyWith(
        height: 1.6,
        fontWeight: FontWeight.w600,
      );
    }
  }

  String _formatAnswer(String text) {
    var result = text;
    // 온점 뒤 줄바꿈 (문장 끝, 이미 줄바꿈이 아닌 경우)
    result = result.replaceAllMapped(
      RegExp(r'([.다])[\s]+(?!\n)'),
      (m) => '${m[1]}\n',
    );
    // "1." "2)" 등 번호 매기기
    result = result.replaceAllMapped(
      RegExp(r'(?<!\n)\s+(\d+[.)]\s)'),
      (m) => '\n${m[1]}',
    );
    // "1단계" "2단계" 등 단계 구분
    result = result.replaceAllMapped(
      RegExp(r'(?<!\n)\s+(\d+단계)'),
      (m) => '\n${m[1]}',
    );
    // "①②③" 등 원문자
    result = result.replaceAllMapped(
      RegExp(r'(?<!\n)\s*([①②③④⑤⑥⑦⑧⑨⑩])'),
      (m) => '\n${m[1]}',
    );
    // "·" "-" 항목 구분
    result = result.replaceAllMapped(
      RegExp(r'(?<!\n)\s+([-·•]\s)'),
      (m) => '\n${m[1]}',
    );
    // 연속 줄바꿈 정리
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // 단어 기준 줄바꿈 (글자 사이에 Word Joiner 삽입 → 공백에서만 줄바꿈)
    result = result.split('\n').map((line) {
      return line.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word.split('').join('\u2060');
      }).join(' ');
    }).join('\n');
    return result.trimLeft();
  }

  Widget _buildBackContent(CardModel card, ColorScheme cs) {
    final formatted = _formatAnswer(card.back);
    final isLong = formatted.length > 40 || formatted.contains('\n');
    return Text(
      formatted,
      key: const ValueKey('back'),
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            height: 1.8,
            fontWeight: FontWeight.w500,
            wordSpacing: 1.2,
          ),
      textAlign: isLong ? TextAlign.left : TextAlign.center,
      softWrap: true,
      overflow: TextOverflow.visible,
    );
  }

  Widget _buildEvidence(CardModel card, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.evidenceColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'p.${card.evidencePage}: ${card.evidence}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              height: 1.5,
              fontStyle: FontStyle.italic,
              color: cs.onSurfaceVariant,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCompleted) return _buildCompletionScreen();

    final cs = Theme.of(context).colorScheme;
    final card = _cards[_currentIndex];
    final progress = _currentIndex + 1;
    final total = _cards.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            onPressed: _reshuffle,
            icon: const Icon(Icons.shuffle_rounded),
            tooltip: '섞기',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 진행률
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Text(
                    '$progress / $total (${(progress / total * 100).round()}%)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: progress / total),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        builder: (context, value, _) =>
                            LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor: cs.surfaceContainerLow,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 카드
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showBack = !_showBack),
                onHorizontalDragUpdate: (details) {
                  if (_isAnimating) return;
                  setState(() => _dragOffset += details.delta.dx);
                },
                onHorizontalDragEnd: (details) {
                  if (_isAnimating) return;
                  if (_dragOffset < -40 &&
                      _currentIndex < _cards.length - 1) {
                    HapticFeedback.lightImpact();
                    _animateSlideOut(1);
                  } else if (_dragOffset > 40 && _currentIndex > 0) {
                    HapticFeedback.lightImpact();
                    _animateSlideOut(-1);
                  } else {
                    _springBack();
                  }
                },
                child: Transform.translate(
                  offset: Offset(
                    _isAnimating
                        ? _slideAnimOffset.dx
                        : _dragOffset * 0.7,
                    0,
                  ),
                  child: Transform.rotate(
                    angle: _isAnimating
                        ? _animRotation
                        : _dragOffset * 0.0003,
                    child: Opacity(
                      opacity: _isAnimating
                          ? _animOpacity
                          : (1 - (_dragOffset.abs() / 200))
                              .clamp(0.3, 1.0),
                      child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _showBack ? cs.tertiary : cs.primary,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_showBack ? cs.tertiary : cs.primary)
                                    .withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // 앞면/뒷면 라벨
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _showBack
                                      ? cs.tertiaryContainer
                                      : cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _showBack ? '정답' : '질문',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _showBack
                                        ? cs.onTertiaryContainer
                                        : cs.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'p.${card.evidencePage}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),

                          // 카드 텍스트 - AnimatedSwitcher
                          Expanded(
                            child: Center(
                              child: SingleChildScrollView(
                                child: AnimatedSwitcher(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                  child: _showBack
                                      ? _buildBackContent(card, cs)
                                      : ClozeText(
                                          text: card.front,
                                          key: const ValueKey('front'),
                                          style: _responsiveTextStyle(card.front.length),
                                          textAlign: TextAlign.center,
                                        ),
                                ),
                              ),
                            ),
                          ),

                          // 근거 (뒷면일 때) 또는 힌트 (처음 2장)
                          if (_showBack && card.evidence.isNotEmpty)
                            _buildEvidence(card, cs)
                          else if (_currentIndex < 2)
                            Text(
                              '탭하여 뒤집기 · 스와이프로 넘기기',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ),
                ),
              ),
            ),

            // 이전/다음 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _currentIndex > 0 ? _prev : null,
                      icon:
                          const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('이전'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _currentIndex < _cards.length - 1
                        ? FilledButton.icon(
                            onPressed: _next,
                            icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18),
                            label: const Text('다음'),
                          )
                        : FilledButton.icon(
                            onPressed: _complete,
                            icon: const Icon(Icons.check_rounded,
                                size: 18),
                            label: const Text('완료'),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionScreen() {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.acceptedColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.celebration_rounded,
                    size: 40,
                    color: AppTheme.acceptedColor,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '학습 완료!',
                  style:
                      Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_cards.length}장의 카드를 모두 학습했습니다.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _reshuffle,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('다시 학습하기'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('목록으로'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
