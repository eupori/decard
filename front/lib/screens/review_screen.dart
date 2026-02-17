import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/session_model.dart';
import '../models/card_model.dart';
import '../services/api_service.dart';
import '../widgets/flash_card_item.dart';
import 'study_screen.dart';

class ReviewScreen extends StatefulWidget {
  final SessionModel session;

  const ReviewScreen({super.key, required this.session});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late List<CardModel> _cards;
  String _filter = 'all'; // all / pending / accepted / rejected

  @override
  void initState() {
    super.initState();
    _cards = List.from(widget.session.cards);
  }

  List<CardModel> get _filteredCards {
    if (_filter == 'all') return _cards;
    return _cards.where((c) => c.status == _filter).toList();
  }

  int get _acceptedCount => _cards.where((c) => c.isAccepted).length;
  int get _rejectedCount => _cards.where((c) => c.isRejected).length;
  int get _pendingCount => _cards.where((c) => c.isPending).length;

  Future<void> _updateCardStatus(CardModel card, String status) async {
    try {
      await ApiService.updateCard(card.id, status: status);
      setState(() => card.status = status);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업데이트 실패: $e')),
        );
      }
    }
  }

  Future<void> _acceptAll() async {
    try {
      final count = await ApiService.acceptAll(widget.session.id);
      setState(() {
        for (final card in _cards) {
          if (card.isPending) card.status = 'accepted';
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count장 카드를 채택했습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('전체 채택 실패: $e')),
        );
      }
    }
  }

  void _startStudy() {
    final studyCards = _cards.where((c) => !c.isRejected).toList();
    if (studyCards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('학습할 카드가 없습니다.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyScreen(
          cards: studyCards,
          title: widget.session.filename.replaceAll('.pdf', ''),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filteredCards;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.session.filename.replaceAll('.pdf', ''),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            onPressed: _startStudy,
            icon: const Icon(Icons.school_rounded),
            tooltip: '학습하기',
          ),
        ],
      ),
      body: Column(
        children: [
          // 통계 바
          _buildStatsBar(cs),

          // 필터 칩
          _buildFilterChips(cs),

          // 액션 바
          _buildActionBar(cs),

          // 카드 리스트
          Expanded(
            child: filtered.isEmpty
                ? _buildEmpty(cs)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final card = filtered[index];
                      return FlashCardItem(
                        card: card,
                        onAccept: () => _updateCardStatus(card, 'accepted'),
                        onReject: () => _updateCardStatus(card, 'rejected'),
                        onRestore: () => _updateCardStatus(card, 'pending'),
                        onEdit: (front, back) async {
                          try {
                            await ApiService.updateCard(card.id,
                                front: front, back: back);
                            setState(() {
                              card.front = front;
                              card.back = back;
                            });
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('수정 실패: $e')),
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('전체', _cards.length, cs.onSurface),
          _statItem('대기', _pendingCount, AppTheme.pendingColor),
          _statItem('채택', _acceptedCount, AppTheme.acceptedColor),
          _statItem('삭제', _rejectedCount, AppTheme.rejectedColor),
        ],
      ),
    );
  }

  Widget _statItem(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        Text(label,
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8))),
      ],
    );
  }

  Widget _buildFilterChips(ColorScheme cs) {
    final filters = [
      ('all', '전체'),
      ('pending', '대기'),
      ('accepted', '채택'),
      ('rejected', '삭제'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: filters.map((f) {
          final selected = _filter == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(f.$2),
              selected: selected,
              onSelected: (_) => setState(() => _filter = f.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          if (_pendingCount > 0) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _acceptAll,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('전체 채택 ($_pendingCount장)'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: _startStudy,
              icon: const Icon(Icons.school_rounded, size: 18),
              label: const Text('학습하기'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            '해당 상태의 카드가 없습니다.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
