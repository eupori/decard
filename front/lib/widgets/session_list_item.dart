import 'package:flutter/material.dart';

class SessionListItem extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final String removeTooltip;
  final bool showFolderIndicator;

  const SessionListItem({
    super.key,
    required this.session,
    required this.onTap,
    required this.onRemove,
    this.removeTooltip = '삭제',
    this.showFolderIndicator = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = session['display_name'] as String?;
    final filename = (session['filename'] as String).replaceAll('.pdf', '');
    final label = displayName ?? filename;
    final cardCount = session['card_count'] as int;
    final templateType = session['template_type'] as String;
    final status = session['status'] as String? ?? 'completed';
    final createdAt = DateTime.tryParse(session['created_at'] as String);
    final timeAgo = createdAt != null ? _formatTimeAgo(createdAt) : '';
    final folderId = session['folder_id'] as String?;
    final isProcessing = status == 'processing';
    final isFailed = status == 'failed';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: isFailed
                  ? cs.error.withValues(alpha: 0.5)
                  : isProcessing
                      ? cs.primary.withValues(alpha: 0.3)
                      : cs.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // 템플릿/상태 아이콘
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isFailed
                      ? cs.errorContainer.withValues(alpha: 0.5)
                      : cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: isFailed
                    ? Icon(Icons.error_outline_rounded,
                        size: 18, color: cs.error)
                    : isProcessing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: Padding(
                              padding: const EdgeInsets.all(9),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                          )
                        : Icon(
                            _templateIcon(templateType),
                            size: 18,
                            color: cs.primary,
                          ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isFailed ? cs.onSurfaceVariant : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isProcessing
                          ? '생성 중... · $timeAgo'
                          : isFailed
                              ? '생성 실패 · $timeAgo'
                              : '${_templateLabel(templateType)} · $cardCount장 · $timeAgo',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                isFailed ? cs.error : cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              // 폴더 표시
              if (showFolderIndicator &&
                  folderId != null &&
                  !isProcessing &&
                  !isFailed)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.folder_rounded,
                      size: 16, color: cs.primary.withValues(alpha: 0.6)),
                ),
              // 카드 수 뱃지 / 상태
              if (isProcessing)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                )
              else if (!isFailed)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$cardCount',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded,
                    size: 18, color: cs.onSurfaceVariant),
                tooltip: removeTooltip,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _templateIcon(String type) {
    switch (type) {
      case 'definition':
        return Icons.menu_book_rounded;
      case 'cloze':
        return Icons.edit_note_rounded;
      case 'comparison':
        return Icons.compare_arrows_rounded;
      case 'subjective':
        return Icons.draw_rounded;
      default:
        return Icons.description_outlined;
    }
  }

  static String _templateLabel(String type) {
    switch (type) {
      case 'definition':
        return '정의형';
      case 'cloze':
        return '빈칸형';
      case 'comparison':
        return '비교형';
      case 'subjective':
        return '주관식';
      default:
        return type;
    }
  }

  static String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${dt.month}/${dt.day}';
  }
}
