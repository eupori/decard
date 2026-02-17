import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/card_model.dart';

class FlashCardItem extends StatefulWidget {
  final CardModel card;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onRestore;
  final Future<void> Function(String front, String back) onEdit;

  const FlashCardItem({
    super.key,
    required this.card,
    required this.onAccept,
    required this.onReject,
    required this.onRestore,
    required this.onEdit,
  });

  @override
  State<FlashCardItem> createState() => _FlashCardItemState();
}

class _FlashCardItemState extends State<FlashCardItem> {
  bool _showBack = false;
  bool _showEvidence = false;
  bool _isEditing = false;
  late TextEditingController _frontCtrl;
  late TextEditingController _backCtrl;

  @override
  void initState() {
    super.initState();
    _frontCtrl = TextEditingController(text: widget.card.front);
    _backCtrl = TextEditingController(text: widget.card.back);
  }

  @override
  void dispose() {
    _frontCtrl.dispose();
    _backCtrl.dispose();
    super.dispose();
  }

  Color _statusColor() {
    if (widget.card.isAccepted) return AppTheme.acceptedColor;
    if (widget.card.isRejected) return AppTheme.rejectedColor;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = widget.card;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: card.isRejected
              ? AppTheme.rejectedColor.withValues(alpha: 0.3)
              : card.isAccepted
                  ? AppTheme.acceptedColor.withValues(alpha: 0.3)
                  : cs.outlineVariant,
        ),
        color: card.isRejected
            ? AppTheme.rejectedColor.withValues(alpha: 0.05)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상태 + 페이지 헤더
          _buildHeader(cs, card),

          // 카드 내용 (탭으로 뒤집기)
          _isEditing ? _buildEditMode(cs) : _buildCardContent(cs, card),

          // 근거
          if (_showEvidence && card.evidence.isNotEmpty)
            _buildEvidence(cs, card),

          // 액션 버튼
          _buildActions(cs, card),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, CardModel card) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          // 상태 뱃지
          if (!card.isPending)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor().withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                card.isAccepted ? '채택' : '삭제',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _statusColor(),
                ),
              ),
            ),
          if (!card.isPending) const SizedBox(width: 8),

          // 페이지 번호
          Icon(Icons.description_outlined,
              size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            'p.${card.evidencePage}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),

          const Spacer(),

          // 템플릿 타입
          Text(
            _templateLabel(card.templateType),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildCardContent(ColorScheme cs, CardModel card) {
    return GestureDetector(
      onTap: () => setState(() => _showBack = !_showBack),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 앞면/뒷면 라벨
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _showBack
                        ? cs.tertiaryContainer
                        : cs.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _showBack ? '뒷면 (정답)' : '앞면 (질문)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          _showBack ? cs.onTertiaryContainer : cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.touch_app_rounded,
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('탭하여 뒤집기',
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),

            // 카드 텍스트
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _showBack ? card.back : card.front,
                key: ValueKey(_showBack),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      fontWeight:
                          _showBack ? FontWeight.normal : FontWeight.w500,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditMode(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('앞면 (질문)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.primary)),
          const SizedBox(height: 6),
          TextField(
            controller: _frontCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          Text('뒷면 (정답)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.tertiary)),
          const SizedBox(height: 6),
          TextField(
            controller: _backCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _isEditing = false),
                child: const Text('취소'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  await widget.onEdit(
                      _frontCtrl.text.trim(), _backCtrl.text.trim());
                  setState(() => _isEditing = false);
                },
                child: const Text('저장'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEvidence(ColorScheme cs, CardModel card) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.evidenceColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppTheme.evidenceColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded,
              size: 18, color: AppTheme.evidenceColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '근거 (p.${card.evidencePage})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.evidenceColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  card.evidence,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ColorScheme cs, CardModel card) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          // 근거 토글
          IconButton(
            onPressed: () => setState(() => _showEvidence = !_showEvidence),
            icon: Icon(
              _showEvidence
                  ? Icons.visibility_off_outlined
                  : Icons.format_quote_rounded,
              size: 20,
            ),
            tooltip: '근거 보기',
            visualDensity: VisualDensity.compact,
          ),

          // 수정
          IconButton(
            onPressed: () {
              _frontCtrl.text = card.front;
              _backCtrl.text = card.back;
              setState(() => _isEditing = true);
            },
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: '수정',
            visualDensity: VisualDensity.compact,
          ),

          const Spacer(),

          // 삭제 or 되돌리기
          if (card.isRejected)
            TextButton.icon(
              onPressed: widget.onRestore,
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('되돌리기'),
            )
          else ...[
            // 삭제
            IconButton(
              onPressed: widget.onReject,
              icon: Icon(Icons.close_rounded,
                  color: AppTheme.rejectedColor, size: 22),
              tooltip: '삭제',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            // 채택
            FilledButton.icon(
              onPressed: card.isAccepted ? null : widget.onAccept,
              icon: Icon(
                card.isAccepted
                    ? Icons.check_circle_rounded
                    : Icons.check_rounded,
                size: 18,
              ),
              label: Text(card.isAccepted ? '채택됨' : '채택'),
              style: FilledButton.styleFrom(
                minimumSize: Size.zero,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                backgroundColor:
                    card.isAccepted ? AppTheme.acceptedColor : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _templateLabel(String type) {
    switch (type) {
      case 'definition':
        return '정의형';
      case 'cloze':
        return '빈칸형';
      case 'comparison':
        return '비교형';
      default:
        return type;
    }
  }
}
