import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../services/api_service.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/drawing_canvas.dart';

class SubjectiveStudyScreen extends StatefulWidget {
  final List<CardModel> cards;
  final String title;

  const SubjectiveStudyScreen({
    super.key,
    required this.cards,
    required this.title,
  });

  @override
  State<SubjectiveStudyScreen> createState() => _SubjectiveStudyScreenState();
}

class _SubjectiveStudyScreenState extends State<SubjectiveStudyScreen> {
  late List<CardModel> _cards;
  int _currentIndex = 0;
  bool _useDrawing = false;
  bool _isGrading = false;
  Map<String, dynamic>? _gradeResult;

  final _answerController = TextEditingController();
  final _canvasKey = GlobalKey();
  final _drawingCanvasKey = GlobalKey<DrawingCanvasState>();

  @override
  void initState() {
    super.initState();
    _cards = List.from(widget.cards)..shuffle(Random());
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  CardModel get _currentCard => _cards[_currentIndex];

  void _next() {
    if (_currentIndex < _cards.length - 1) {
      setState(() {
        _currentIndex++;
        _resetState();
      });
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _resetState();
      });
    }
  }

  void _resetState() {
    _answerController.clear();
    _useDrawing = false;
    _isGrading = false;
    _gradeResult = null;
    _drawingCanvasKey.currentState?.clear();
  }

  Future<void> _grade() async {
    final userAnswer = _answerController.text.trim();
    Uint8List? drawingImage;

    if (_useDrawing) {
      drawingImage = await _drawingCanvasKey.currentState?.captureImage();
    }

    if (userAnswer.isEmpty && drawingImage == null) {
      showErrorSnackBar(context, '답안을 입력해주세요.');
      return;
    }

    setState(() => _isGrading = true);

    try {
      final result = await ApiService.gradeCard(
        cardId: _currentCard.id,
        userAnswer: userAnswer,
        drawingImage: drawingImage,
      );
      if (mounted) {
        setState(() {
          _gradeResult = result;
          _isGrading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isGrading = false);
        showErrorSnackBar(context, e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGrading = false);
        showErrorSnackBar(context, '채점 오류: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = _currentIndex + 1;
    final total = _cards.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
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

            // 스크롤 가능한 본문
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 질문 카드
                    _buildQuestionCard(cs),
                    const SizedBox(height: 16),

                    // 채점 결과가 없으면 답안 입력 영역
                    if (_gradeResult == null) ...[
                      _buildAnswerInput(cs),
                    ],

                    // 채점 결과
                    if (_gradeResult != null) ...[
                      _buildGradeResult(cs),
                      const SizedBox(height: 16),
                      _buildModelAnswer(cs),
                    ],

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),

            // 하단 버튼
            _buildBottomBar(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary, width: 2),
        color: cs.primaryContainer.withValues(alpha: 0.15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '질문',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _currentCard.front,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'p.${_currentCard.evidencePage}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerInput(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 입력 모드 토글
        Row(
          children: [
            Text(
              '답안 작성',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _useDrawing = !_useDrawing),
              icon: Icon(
                _useDrawing ? Icons.keyboard : Icons.draw_rounded,
                size: 18,
              ),
              label: Text(_useDrawing ? '텍스트로 전환' : '손글씨 추가'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 텍스트 입력
        TextField(
          controller: _answerController,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: '답안을 입력하세요...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),

        // 손글씨 캔버스
        if (_useDrawing) ...[
          const SizedBox(height: 16),
          DrawingCanvas(
            key: _drawingCanvasKey,
            repaintKey: _canvasKey,
          ),
        ],
      ],
    );
  }

  Widget _buildGradeResult(ColorScheme cs) {
    final score = _gradeResult!['score'] as String;
    final feedback = _gradeResult!['feedback'] as String;
    final userAnswer = _gradeResult!['user_answer'] as String;

    Color scoreColor;
    String scoreLabel;
    IconData scoreIcon;

    switch (score) {
      case 'correct':
        scoreColor = const Color(0xFF22C55E);
        scoreLabel = '정답';
        scoreIcon = Icons.check_circle_rounded;
        break;
      case 'partial':
        scoreColor = const Color(0xFFF59E0B);
        scoreLabel = '부분 정답';
        scoreIcon = Icons.info_rounded;
        break;
      default:
        scoreColor = const Color(0xFFEF4444);
        scoreLabel = '오답';
        scoreIcon = Icons.cancel_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
        color: scoreColor.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 점수 헤더
          Row(
            children: [
              Icon(scoreIcon, color: scoreColor, size: 28),
              const SizedBox(width: 10),
              Text(
                scoreLabel,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 피드백
          Text(
            feedback,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                ),
          ),

          // 내 답안
          if (userAnswer.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '내 답안',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userAnswer,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.5,
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModelAnswer(ColorScheme cs) {
    final modelAnswer = _gradeResult!['model_answer'] as String;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.3)),
        color: cs.tertiaryContainer.withValues(alpha: 0.15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '모범답안',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            modelAnswer,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 이전
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _currentIndex > 0 ? _prev : null,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('이전'),
            ),
          ),
          const SizedBox(width: 12),

          // 채점하기 or 다음
          Expanded(
            flex: 2,
            child: _gradeResult != null
                ? (_currentIndex < _cards.length - 1
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
                      ))
                : FilledButton.icon(
                    onPressed: _isGrading ? null : _grade,
                    icon: _isGrading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.grading_rounded, size: 18),
                    label: Text(_isGrading ? '채점 중...' : '채점하기'),
                  ),
          ),
        ],
      ),
    );
  }
}
