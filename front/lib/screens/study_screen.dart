import 'dart:math';

import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/card_model.dart';

class StudyScreen extends StatefulWidget {
  final List<CardModel> cards;
  final String title;

  const StudyScreen({super.key, required this.cards, required this.title});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late List<CardModel> _cards;
  int _currentIndex = 0;
  bool _showBack = false;
  bool _showEvidence = false;

  @override
  void initState() {
    super.initState();
    _cards = List.from(widget.cards)..shuffle(Random());
  }

  void _next() {
    if (_currentIndex < _cards.length - 1) {
      setState(() {
        _currentIndex++;
        _showBack = false;
        _showEvidence = false;
      });
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _showBack = false;
        _showEvidence = false;
      });
    }
  }

  void _reshuffle() {
    setState(() {
      _cards.shuffle(Random());
      _currentIndex = 0;
      _showBack = false;
      _showEvidence = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Text(
                    '$progress / $total',
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
                      child: LinearProgressIndicator(
                        value: progress / total,
                        minHeight: 6,
                        backgroundColor: cs.surfaceContainerLow,
                        color: cs.primary,
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
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity != null) {
                    if (details.primaryVelocity! < -100) _next();
                    if (details.primaryVelocity! > 100) _prev();
                  }
                },
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
                        color: (_showBack ? cs.tertiary : cs.primary)
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
                                fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),

                      // 카드 텍스트
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: AnimatedCrossFade(
                              duration: const Duration(milliseconds: 200),
                              crossFadeState: _showBack
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              firstChild: Text(
                                card.front,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      height: 1.6,
                                      fontWeight: FontWeight.w600,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              secondChild: Text(
                                card.back,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(height: 1.6),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 탭 힌트
                      Text(
                        '탭하여 뒤집기',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 근거 토글
            if (_showBack && card.evidence.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showEvidence = !_showEvidence),
                      icon: Icon(
                        _showEvidence
                            ? Icons.visibility_off_outlined
                            : Icons.format_quote_rounded,
                        size: 18,
                      ),
                      label: Text(_showEvidence ? '근거 숨기기' : '근거 보기'),
                    ),
                    if (_showEvidence)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              AppTheme.evidenceColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppTheme.evidenceColor
                                  .withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          '📖 p.${card.evidencePage}: ${card.evidence}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    height: 1.5,
                                    fontStyle: FontStyle.italic,
                                    color: cs.onSurfaceVariant,
                                  ),
                        ),
                      ),
                  ],
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
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('이전'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _currentIndex < _cards.length - 1
                        ? FilledButton.icon(
                            onPressed: _next,
                            icon: const Icon(Icons.arrow_forward_rounded,
                                size: 18),
                            label: const Text('다음'),
                          )
                        : FilledButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.check_rounded, size: 18),
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
}
