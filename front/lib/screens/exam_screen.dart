import 'dart:math';
import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../services/api_service.dart';
import 'exam_result_screen.dart';

class ExamQuestion {
  final CardModel card;
  final bool isObjective;
  final List<String>? choices;
  final int? correctIndex;

  ExamQuestion({
    required this.card,
    required this.isObjective,
    this.choices,
    this.correctIndex,
  });
}

class ExamScreen extends StatefulWidget {
  final List<CardModel> cards;
  final String title;
  final String sessionId;
  final String examType; // 'mixed', 'subjective', 'objective'
  final int questionCount;

  const ExamScreen({
    super.key,
    required this.cards,
    required this.title,
    required this.sessionId,
    required this.examType,
    required this.questionCount,
  });

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  late List<ExamQuestion> _questions;
  int _currentIndex = 0;

  // 답안 저장
  final Map<int, String> _subjectiveAnswers = {};
  final Map<int, int> _objectiveAnswers = {};

  // 비동기 채점 (주관식 — 다음 문제 푸는 동안 백그라운드 채점)
  final Map<int, Future<Map<String, dynamic>>> _gradingFutures = {};

  // 현재 문제 UI 상태
  final _answerController = TextEditingController();
  int? _selectedChoice;

  // 채점 로딩 상태
  bool _isFinishing = false;
  int _totalSubjective = 0;
  int _gradedCount = 0;

  @override
  void initState() {
    super.initState();
    _questions = _generateQuestions();
    _totalSubjective =
        _questions.where((q) => !q.isObjective).length;
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  // ── 문제 생성 ──

  List<ExamQuestion> _generateQuestions() {
    final rng = Random();
    final allCards = List<CardModel>.from(widget.cards)..shuffle(rng);
    final count = min(widget.questionCount, allCards.length);
    final selected = allCards.sublist(0, count);

    List<bool> objectiveFlags;
    switch (widget.examType) {
      case 'subjective':
        objectiveFlags = List.filled(count, false);
        break;
      case 'objective':
        objectiveFlags = List.filled(count, true);
        break;
      default: // mixed
        if (widget.cards.length < 4) {
          objectiveFlags = List.filled(count, false);
        } else {
          final objCount = count ~/ 2;
          objectiveFlags = [
            ...List.filled(objCount, true),
            ...List.filled(count - objCount, false),
          ]..shuffle(rng);
        }
    }

    final questions = <ExamQuestion>[];
    for (int i = 0; i < count; i++) {
      final card = selected[i];
      var isObj = objectiveFlags[i];

      if (card.templateType == 'cloze') isObj = false;

      if (isObj) {
        final result = _generateChoices(card, widget.cards, rng);
        if (result != null) {
          questions.add(ExamQuestion(
            card: card,
            isObjective: true,
            choices: result.$1,
            correctIndex: result.$2,
          ));
        } else {
          questions.add(ExamQuestion(card: card, isObjective: false));
        }
      } else {
        questions.add(ExamQuestion(card: card, isObjective: false));
      }
    }

    return questions;
  }

  (List<String>, int)? _generateChoices(
      CardModel card, List<CardModel> pool, Random rng) {
    final candidates = pool
        .where((c) => c.id != card.id && c.back.trim() != card.back.trim())
        .toList();
    if (candidates.length < 3) return null;

    candidates.shuffle(rng);
    final wrongs = candidates.take(3).map((c) => _truncate(c.back)).toList();
    final correctAnswer = _truncate(card.back);
    final choices = [...wrongs, correctAnswer]..shuffle(rng);
    final correctIndex = choices.indexOf(correctAnswer);
    return (choices, correctIndex);
  }

  String _truncate(String text) {
    if (text.length > 200) return '${text.substring(0, 100)}...';
    return text;
  }

  // ── 답안 저장/복원 ──

  bool get _hasCurrentAnswer {
    final q = _questions[_currentIndex];
    if (q.isObjective) return _selectedChoice != null;
    return _answerController.text.trim().isNotEmpty;
  }

  void _saveCurrentAnswer() {
    final q = _questions[_currentIndex];
    if (q.isObjective) {
      if (_selectedChoice != null) {
        _objectiveAnswers[_currentIndex] = _selectedChoice!;
      }
    } else {
      final answer = _answerController.text.trim();
      if (answer.isNotEmpty) {
        final prevAnswer = _subjectiveAnswers[_currentIndex];
        _subjectiveAnswers[_currentIndex] = answer;
        // 답이 바뀌었거나 처음이면 비동기 채점 시작
        if (prevAnswer != answer) {
          _gradingFutures[_currentIndex] = ApiService.gradeCard(
            cardId: q.card.id,
            userAnswer: answer,
          );
        }
      }
    }
  }

  void _restoreCurrentAnswer() {
    final q = _questions[_currentIndex];
    if (q.isObjective) {
      _selectedChoice = _objectiveAnswers[_currentIndex];
    } else {
      _answerController.text = _subjectiveAnswers[_currentIndex] ?? '';
    }
  }

  // ── 네비게이션 ──

  void _goNext() {
    _saveCurrentAnswer();
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _answerController.clear();
        _selectedChoice = null;
        _restoreCurrentAnswer();
      });
    } else {
      _finishExam();
    }
  }

  void _goPrev() {
    _saveCurrentAnswer();
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _answerController.clear();
        _selectedChoice = null;
        _restoreCurrentAnswer();
      });
    }
  }

  void _skipAndNext() {
    // 답 없이 다음으로 (오답 처리)
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _answerController.clear();
        _selectedChoice = null;
        _restoreCurrentAnswer();
      });
    } else {
      _finishExam();
    }
  }

  // ── 채점 + 결과 ──

  Future<void> _finishExam() async {
    setState(() => _isFinishing = true);

    final results = <ExamResult>[];

    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];

      if (q.isObjective) {
        final selected = _objectiveAnswers[i];
        if (selected != null) {
          final isCorrect = selected == q.correctIndex;
          results.add(ExamResult(
            card: q.card,
            isObjective: true,
            score: isCorrect ? 'correct' : 'incorrect',
            userAnswer: q.choices![selected],
          ));
        } else {
          results.add(ExamResult(
            card: q.card,
            isObjective: true,
            score: 'incorrect',
          ));
        }
      } else {
        final answer = _subjectiveAnswers[i];
        if (answer != null &&
            answer.isNotEmpty &&
            _gradingFutures.containsKey(i)) {
          try {
            final gradeResult = await _gradingFutures[i]!;
            final score = gradeResult['score'] as String;
            results.add(ExamResult(
              card: q.card,
              isObjective: false,
              score: score,
              feedback: gradeResult['feedback'] as String?,
              userAnswer: answer,
            ));
          } catch (_) {
            results.add(ExamResult(
              card: q.card,
              isObjective: false,
              score: 'incorrect',
              feedback: '채점 실패',
              userAnswer: answer,
            ));
          }
          if (mounted) setState(() => _gradedCount++);
        } else {
          results.add(ExamResult(
            card: q.card,
            isObjective: false,
            score: 'incorrect',
            userAnswer: answer,
          ));
        }
      }
    }

    // SRS 기록 (실패해도 무시)
    for (final r in results) {
      try {
        int rating;
        if (r.score == 'correct') {
          rating = r.isObjective ? 3 : 4;
        } else if (r.score == 'partial') {
          rating = 2;
        } else {
          rating = 1;
        }
        ApiService.reviewCard(cardId: r.card.id, rating: rating);
      } catch (_) {}
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ExamResultScreen(
          results: results,
          title: widget.title,
          sessionId: widget.sessionId,
          allCards: widget.cards,
          examType: widget.examType,
        ),
      ),
    );
  }

  // ── 뒤로가기 확인 ──

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('시험 종료'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('시험을 종료하시겠습니까?\n진행 상황이 저장되지 않습니다.'),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style:
                          FilledButton.styleFrom(backgroundColor: cs.error),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('종료'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return result ?? false;
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    if (_isFinishing) return _buildGradingScreen();

    final cs = Theme.of(context).colorScheme;
    final q = _questions[_currentIndex];
    final progress = _currentIndex + 1;
    final total = _questions.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontSize: 16)),
          actions: [
            TextButton(
              onPressed: _skipAndNext,
              child: Text('건너뛰기',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // 프로그레스 바 + 유형 뱃지
              _buildProgressBar(cs, q, progress, total),

              // 본문
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildQuestionCard(q.card, cs),
                      const SizedBox(height: 16),
                      if (q.isObjective)
                        _buildObjectiveUI(q, cs)
                      else
                        _buildSubjectiveUI(cs),
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
      ),
    );
  }

  Widget _buildGradingScreen() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    strokeWidth: 6,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  '채점 중...',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (_totalSubjective > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '주관식 $_gradedCount / $_totalSubjective',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(
      ColorScheme cs, ExamQuestion q, int progress, int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainerLow,
                  color: cs.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: q.isObjective
                  ? cs.secondaryContainer
                  : cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              q.isObjective ? '객관식' : '주관식',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: q.isObjective
                    ? cs.onSecondaryContainer
                    : cs.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(CardModel card, ColorScheme cs) {
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
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            card.front,
            style: (MediaQuery.of(context).size.width > 600
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.titleMedium)
                ?.copyWith(
              height: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (card.evidencePage > 0) ...[
            const SizedBox(height: 8),
            Text(
              'p.${card.evidencePage}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  // ── 주관식 ──

  Widget _buildSubjectiveUI(ColorScheme cs) {
    return TextField(
      controller: _answerController,
      maxLines: 4,
      decoration: InputDecoration(
        hintText: '답안을 입력하세요...',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }

  // ── 객관식 ──

  Widget _buildObjectiveUI(ExamQuestion q, ColorScheme cs) {
    return Column(
      children: [
        for (int i = 0; i < q.choices!.length; i++) ...[
          _buildChoiceCard(i, q, cs),
          if (i < q.choices!.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildChoiceCard(int index, ExamQuestion q, ColorScheme cs) {
    final isSelected = _selectedChoice == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedChoice = index),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? cs.primaryContainer.withValues(alpha: 0.15)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? cs.primary : cs.surfaceContainerLow,
              ),
              child: Center(
                child: Text(
                  String.fromCharCode(0x2460 + index), // ①②③④
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                q.choices![index],
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 하단 버튼 ──

  Widget _buildBottomBar(ColorScheme cs) {
    final isLast = _currentIndex >= _questions.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border:
            Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          if (_currentIndex > 0) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _goPrev,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('이전'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: _currentIndex > 0 ? 2 : 1,
            child: FilledButton.icon(
              onPressed: _hasCurrentAnswer ? _goNext : null,
              icon: Icon(
                isLast
                    ? Icons.check_rounded
                    : Icons.arrow_forward_rounded,
                size: 18,
              ),
              label: Text(isLast ? '제출' : '다음'),
            ),
          ),
        ],
      ),
    );
  }
}
