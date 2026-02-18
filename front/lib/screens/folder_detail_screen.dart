import 'package:flutter/material.dart';
import '../models/folder_model.dart';
import '../services/api_service.dart';
import '../utils/snackbar_helper.dart';
import 'main_screen.dart' show buildAppBottomNav;
import 'review_screen.dart';

class FolderDetailScreen extends StatefulWidget {
  final FolderModel folder;

  const FolderDetailScreen({super.key, required this.folder});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  bool _error = false;

  late String _folderName;

  @override
  void initState() {
    super.initState();
    _folderName = widget.folder.name;
    _loadSessions();
  }

  Color _parseColor(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final sessions =
          await ApiService.listFolderSessions(widget.folder.id);
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSession(String sessionId) async {
    try {
      final session = await ApiService.getSession(sessionId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewScreen(session: session)),
      ).then((_) => _loadSessions());
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    }
  }

  Future<void> _removeSession(String sessionId) async {
    try {
      await ApiService.removeFromLibrary(sessionId);
      _loadSessions();
      if (mounted) showSuccessSnackBar(context, '보관함에서 제거되었습니다.');
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${dt.month}/${dt.day}';
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

  IconData _templateIcon(String type) {
    switch (type) {
      case 'definition':
        return Icons.menu_book_rounded;
      case 'cloze':
        return Icons.edit_note_rounded;
      case 'comparison':
        return Icons.compare_arrows_rounded;
      default:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _parseColor(widget.folder.color);

    return Scaffold(
      bottomNavigationBar: buildAppBottomNav(context, selectedIndex: 1),
      appBar: AppBar(
        title: Text(_folderName, style: const TextStyle(fontSize: 16)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _editFolder();
              if (value == 'delete') _deleteFolder();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('수정')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('삭제', style: TextStyle(color: Color(0xFFEF4444))),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Container(height: 4, color: color),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSessions,
        child: _buildBody(cs),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('세션 목록을 불러올 수 없습니다.',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadSessions,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_sessions.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_rounded,
                      size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    '이 과목에 저장된 세션이 없습니다',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _sessions.length,
      itemBuilder: (context, index) =>
          _buildSessionItem(cs, _sessions[index]),
    );
  }

  Widget _buildSessionItem(ColorScheme cs, Map<String, dynamic> session) {
    final displayName = session['display_name'] as String?;
    final filename = (session['filename'] as String).replaceAll('.pdf', '');
    final label = displayName ?? filename;
    final cardCount = session['card_count'] as int;
    final templateType = session['template_type'] as String;
    final status = session['status'] as String? ?? 'completed';
    final createdAt = DateTime.tryParse(session['created_at'] as String);
    final timeAgo = createdAt != null ? _formatTimeAgo(createdAt) : '';
    final isProcessing = status == 'processing';
    final isFailed = status == 'failed';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          if (isProcessing) {
            showInfoSnackBar(context, '아직 카드를 생성하고 있습니다.');
          } else if (isFailed) {
            showErrorSnackBar(context, '카드 생성에 실패한 세션입니다.');
          } else {
            _openSession(session['id'] as String);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isProcessing
                          ? '생성 중...'
                          : '${_templateLabel(templateType)} · $cardCount장 · $timeAgo',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (!isProcessing && !isFailed)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                onPressed: () => _removeSession(session['id'] as String),
                icon: Icon(Icons.close_rounded,
                    size: 18, color: cs.onSurfaceVariant),
                tooltip: '보관함에서 제거',
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

  Future<void> _editFolder() async {
    final nameController = TextEditingController(text: _folderName);
    final presetColors = [
      '#C2E7DA', '#6290C3', '#9B72CF', '#F59E0B', '#EF4444', '#94A3B8',
    ];
    String selectedColor = widget.folder.color;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: const Text('과목 수정'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '과목명',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('색상', style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  )),
                  const SizedBox(height: 8),
                  Row(
                    children: presetColors.map((c) {
                      final isSelected = c == selectedColor;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedColor = c),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _parseColor(c),
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(
                                      color: cs.onSurface, width: 2.5)
                                  : null,
                            ),
                            child: isSelected
                                ? Icon(Icons.check, size: 16,
                                    color: cs.onSurface)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.pop(ctx, {
                      'name': nameController.text.trim(),
                      'color': selectedColor,
                    });
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      try {
        await ApiService.updateFolder(
          widget.folder.id,
          name: result['name'],
          color: result['color'],
        );
        setState(() => _folderName = result['name']!);
        if (mounted) showSuccessSnackBar(context, '과목이 수정되었습니다.');
      } catch (e) {
        if (mounted) showErrorSnackBar(context, friendlyError(e));
      }
    }
  }

  Future<void> _deleteFolder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('과목 삭제'),
        content: Text(
          '"$_folderName" 과목을 삭제하시겠습니까?\n'
          '세션은 보존되며 보관함에서만 제거됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              minimumSize: Size.zero,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.deleteFolder(widget.folder.id);
        if (mounted) {
          showSuccessSnackBar(context, '과목이 삭제되었습니다.');
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) showErrorSnackBar(context, friendlyError(e));
      }
    }
  }
}
