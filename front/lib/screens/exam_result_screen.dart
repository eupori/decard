import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../services/exam_history_service.dart';
import 'exam_screen.dart';

class ExamResult {
  final CardModel card;
  final bool isObjective;
  final String score; // 'correct' / 'partial' / 'incorrect'
  final String? feedback; // AI 피드백 (주관식만)
  final String? userAnswer;

  const ExamResult({
    required this.card,
    required this.isObjective,
    required this.score,
    this.feedback,
    this.userAnswer,
  });
}

class ExamResultScreen extends StatefulWidget {
  final List<ExamResult> results;
  final String title;
  final String sessionId;
  final List<CardModel> allCards;
  final String examType;

  const ExamResultScreen({
    super.key,
    required this.results,
    required this.title,
    required this.sessionId,
    required this.allCards,
    required this.examType,
  });

  @override
  State<ExamResultScreen> createState() => _ExamResultScreenState();
}

class _ExamResultScreenState extends State<ExamResultScreen> {
  List<ExamRecord> _history = [];

  int get _correctCount =>
      widget.results.where((r) => r.score == 'correct').length;
  int get _partialCount =>
      widget.results.where((r) => r.score == 'partial').length;
  int get _incorrectCount =>
      widget.results.where((r) => r.score == 'incorrect').length;

  double get _totalScore => widget.results.isEmpty
      ? 0
      : (_correctCount * 1.0 + _partialCount * 0.5) /
          widget.results.length *
          100;

  int get _scoreInt => _totalScore.round();

  List<ExamResult> get _wrongResults => widget.results
      .where((r) => r.score == 'incorrect' || r.score == 'partial')
      .toList();

  @override
  void initState() {
    super.initState();
    _saveAndLoadHistory();
  }

  Future<void> _saveAndLoadHistory() async {
    if (widget.results.isEmpty) return;

    await ExamHistoryService.save(ExamRecord(
      sessionId: widget.sessionId,
      title: widget.title,
      date: DateTime.now(),
      questionCount: widget.results.length,
      correctCount: _correctCount,
      partialCount: _partialCount,
      incorrectCount: _incorrectCount,
      score: _totalScore,
    ));

    final history =
        await ExamHistoryService.getBySession(widget.sessionId);
    if (mounted) {
      setState(() => _history = history);
    }
  }

  Color _getScoreColor(int score) {
    if (score >= 90) return const Color(0xFF22C55E);
    if (score >= 70) return const Color(0xFF6290C3);
    if (score >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.results.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: Text('결과가 없습니다.')),
      );
    }

    final scoreColor = _getScoreColor(_scoreInt);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 1. 상단 원형 점수
            const SizedBox(height: 12),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scoreColor.withValues(alpha: 0.1),
                border: Border.all(color: scoreColor, width: 4),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$_scoreInt',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                  Text(
                    '점',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scoreColor),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // 2. 통계 Row
            Row(
              children: [
                _StatItem(
                    count: _correctCount,
                    label: '정답',
                    color: const Color(0xFF22C55E)),
                _StatItem(
                    count: _partialCount,
                    label: '부분정답',
                    color: const Color(0xFFF59E0B)),
                _StatItem(
                    count: _incorrectCount,
                    label: '오답',
                    color: const Color(0xFFEF4444)),
              ],
            ),

            const SizedBox(height: 28),

            // 3. 틀린 카드 목록 또는 축하 메시지
            if (_wrongResults.isEmpty) ...[
              const SizedBox(height: 20),
              const Icon(Icons.celebration_rounded,
                  size: 48, color: Color(0xFF22C55E)),
              const SizedBox(height: 12),
              Text(
                '모두 정답!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(height: 20),
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '틀린 문제 (${_wrongResults.length}개)',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              ..._wrongResults.map((r) => _WrongCardTile(result: r)),
            ],

            const SizedBox(height: 20),

            // 4. 하단 버튼
            if (_wrongResults.isNotEmpty)
              FilledButton(
                onPressed: () {
                  final wrongCards =
                      _wrongResults.map((r) => r.card).toList();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExamScreen(
                        cards: wrongCards,
                        title: '${widget.title} (재시험)',
                        sessionId: widget.sessionId,
                        examType: widget.examType,
                        questionCount: wrongCards.length,
                      ),
                    ),
                  );
                },
                child: const Text('틀린 문제 재시험'),
              ),
            if (_wrongResults.isNotEmpty) const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('목록으로'),
              ),
            ),

            // 5. 시험 기록
            if (_history.length > 1) ...[
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '이전 시험 기록',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              // 최신순, 현재 시험(첫번째) 제외하고 최근 5개
              ..._history.skip(1).take(5).map(
                    (r) => _HistoryTile(record: r),
                  ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _StatItem({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _WrongCardTile extends StatelessWidget {
  final ExamResult result;

  const _WrongCardTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPartial = result.score == 'partial';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        title: Text(
          result.card.front,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              _Badge(
                label: result.isObjective ? '객관식' : '주관식',
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              _Badge(
                label: isPartial ? '부분정답' : '오답',
                color: isPartial
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFEF4444),
              ),
            ],
          ),
        ),
        children: [
          if (result.userAnswer != null) ...[
            _AnswerBlock(
              label: '내 답안',
              content: result.userAnswer!,
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.05),
            ),
            const SizedBox(height: 8),
          ],
          _AnswerBlock(
            label: '정답',
            content: result.card.back,
            backgroundColor: theme.colorScheme.tertiaryContainer,
          ),
          if (!result.isObjective && result.feedback != null) ...[
            const SizedBox(height: 8),
            _AnswerBlock(
              label: 'AI 피드백',
              content: result.feedback!,
              backgroundColor: theme.colorScheme.primaryContainer
                  .withValues(alpha: 0.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  final String label;
  final String content;
  final Color backgroundColor;

  const _AnswerBlock({
    required this.label,
    required this.content,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            content,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final ExamRecord record;

  const _HistoryTile({required this.record});

  Color _getColor(double score) {
    if (score >= 90) return const Color(0xFF22C55E);
    if (score >= 70) return const Color(0xFF6290C3);
    if (score >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor(record.score);
    final date = record.date;
    final dateStr =
        '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Text(
              dateStr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: 12),
            Text(
              '${record.score.round()}점',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const Spacer(),
            Text(
              '${record.correctCount}/${record.questionCount}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
