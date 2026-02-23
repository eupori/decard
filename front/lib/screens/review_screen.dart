import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/session_model.dart';
import '../models/card_model.dart';
import '../services/api_service.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/flash_card_item.dart';
import '../widgets/save_to_library_dialog.dart';
import 'main_screen.dart' show buildAppBottomNav;
import 'study_screen.dart';
import 'subjective_study_screen.dart';

class ReviewScreen extends StatefulWidget {
  final SessionModel session;

  const ReviewScreen({super.key, required this.session});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late List<CardModel> _cards;
  String _filter = 'all'; // all / pending / accepted / rejected
  late bool _isSaved;

  @override
  void initState() {
    super.initState();
    _cards = List.from(widget.session.cards);
    _isSaved = widget.session.folderId != null;
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
        showErrorSnackBar(context, '업데이트 실패: ${friendlyError(e)}');
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
        showSuccessSnackBar(context, '$count장 카드를 채택했습니다.');
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, '전체 채택 실패: ${friendlyError(e)}');
      }
    }
  }

  Future<void> _resetAll() async {
    try {
      int count = 0;
      for (final card in _cards) {
        if (!card.isPending) {
          await ApiService.updateCard(card.id, status: 'pending');
          card.status = 'pending';
          count++;
        }
      }
      setState(() {});
      if (mounted) {
        showSuccessSnackBar(context, '$count장 카드를 되돌렸습니다.');
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, '전체 해제 실패: ${friendlyError(e)}');
      }
    }
  }

  Future<void> _saveToLibrary() async {
    final defaultName = widget.session.displayName ??
        widget.session.filename.replaceAll('.pdf', '');
    final saved = await SaveToLibraryDialog.show(
      context,
      sessionId: widget.session.id,
      defaultName: defaultName,
    );
    if (saved == true && mounted) {
      setState(() => _isSaved = true);
      showSuccessSnackBar(context, '보관함에 저장되었습니다.');
    }
  }

  void _startStudy() {
    final studyCards = _cards.where((c) => c.isAccepted).toList();
    if (studyCards.isEmpty) {
      showErrorSnackBar(context, '학습할 카드가 없습니다.');
      return;
    }

    final title = widget.session.filename.replaceAll('.pdf', '');

    if (widget.session.templateType == 'subjective') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SubjectiveStudyScreen(
            cards: studyCards,
            title: title,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudyScreen(
            cards: studyCards,
            title: title,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filteredCards;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.session.displayName ??
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
      bottomNavigationBar: buildAppBottomNav(context, selectedIndex: 0),
      body: Column(
        children: [
          // 통계 바 (고정)
          _buildStatsBar(cs),

          // 필터칩 + 액션바 + 카드리스트 통합 스크롤
          Expanded(
            child: filtered.isEmpty
                ? ListView(
                    children: [
                      _buildFilterChips(cs),
                      _buildActionBar(cs),
                      const SizedBox(height: 80),
                      _buildEmpty(cs),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: filtered.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Column(
                          children: [
                            _buildFilterChips(cs),
                            _buildActionBar(cs),
                          ],
                        );
                      }
                      final card = filtered[index - 1];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: FlashCardItem(
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
                                showErrorSnackBar(context, '수정 실패: ${friendlyError(e)}');
                              }
                            }
                          },
                        ),
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
      child: Column(
        children: [
          // 보관함 저장 버튼
          SizedBox(
            width: double.infinity,
            child: _isSaved
                ? OutlinedButton.icon(
                    onPressed: _saveToLibrary,
                    icon: Icon(Icons.folder_rounded,
                        size: 18, color: cs.primary),
                    label: Text('보관됨',
                        style: TextStyle(color: cs.primary)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: cs.primary),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: _saveToLibrary,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('보관함에 저장'),
                  ),
          ),
          const SizedBox(height: 8),
          Row(
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
              ] else if (_acceptedCount > 0 || _rejectedCount > 0) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetAll,
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('전체 해제'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: _startStudy,
                  icon: const Icon(Icons.school_rounded, size: 18),
                  label: Text('학습하기 ($_acceptedCount장)'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    IconData icon;
    String message;

    switch (_filter) {
      case 'pending':
        icon = Icons.check_circle_outline_rounded;
        message = '모든 카드를 검수했습니다!';
        break;
      case 'accepted':
        icon = Icons.thumb_up_off_alt_rounded;
        message = '아직 채택된 카드가 없습니다.\n카드를 확인하고 채택해보세요.';
        break;
      case 'rejected':
        icon = Icons.delete_outline_rounded;
        message = '삭제된 카드가 없습니다.';
        break;
      default:
        icon = Icons.inbox_rounded;
        message = '카드가 없습니다.';
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
