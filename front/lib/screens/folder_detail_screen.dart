import 'package:flutter/material.dart';
import '../models/folder_model.dart';
import '../services/api_service.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/folder_edit_dialog.dart';
import '../widgets/session_list_item.dart';
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
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final status = session['status'] as String? ?? 'completed';
        return SessionListItem(
          session: session,
          removeTooltip: '보관함에서 제거',
          onTap: () {
            if (status == 'processing') {
              showInfoSnackBar(context, '아직 카드를 생성하고 있습니다.');
            } else if (status == 'failed') {
              showErrorSnackBar(context, '카드 생성에 실패한 세션입니다.');
            } else {
              _openSession(session['id'] as String);
            }
          },
          onRemove: () => _removeSession(session['id'] as String),
        );
      },
    );
  }

  Future<void> _editFolder() async {
    final result = await showFolderEditDialog(
      context,
      initialName: _folderName,
      initialColor: widget.folder.color,
      title: '과목 수정',
      confirmLabel: '저장',
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
