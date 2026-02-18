import 'package:flutter/material.dart';
import '../models/folder_model.dart';
import '../services/api_service.dart';
import '../utils/snackbar_helper.dart';
import 'folder_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<FolderModel> _folders = [];
  bool _loading = true;
  bool _error = false;

  static const _presetColors = [
    '#C2E7DA',
    '#6290C3',
    '#9B72CF',
    '#F59E0B',
    '#EF4444',
    '#94A3B8',
  ];

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final folders = await ApiService.listFolders();
      if (mounted) setState(() => _folders = folders);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _parseColor(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  Future<void> _showCreateFolderDialog() async {
    final nameController = TextEditingController();
    String selectedColor = _presetColors[0];

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: const Text('새 과목 만들기'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '과목명',
                      hintText: '예: 경영학원론',
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
                    children: _presetColors.map((c) {
                      final isSelected = c == selectedColor;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedColor = c),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _parseColor(c),
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: cs.onSurface, width: 2.5)
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
                  child: const Text('만들기'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      try {
        await ApiService.createFolder(
          name: result['name']!,
          color: result['color'],
        );
        _loadFolders();
        if (mounted) showSuccessSnackBar(context, '과목이 생성되었습니다.');
      } catch (e) {
        if (mounted) showErrorSnackBar(context, friendlyError(e));
      }
    }
  }

  Future<void> _showEditFolderDialog(FolderModel folder) async {
    final nameController = TextEditingController(text: folder.name);
    String selectedColor = folder.color;

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
                    children: _presetColors.map((c) {
                      final isSelected = c == selectedColor;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedColor = c),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _parseColor(c),
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: cs.onSurface, width: 2.5)
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
          folder.id,
          name: result['name'],
          color: result['color'],
        );
        _loadFolders();
        if (mounted) showSuccessSnackBar(context, '과목이 수정되었습니다.');
      } catch (e) {
        if (mounted) showErrorSnackBar(context, friendlyError(e));
      }
    }
  }

  Future<void> _confirmDeleteFolder(FolderModel folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('과목 삭제'),
        content: Text(
          '"${folder.name}" 과목을 삭제하시겠습니까?\n'
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.deleteFolder(folder.id);
        _loadFolders();
        if (mounted) showSuccessSnackBar(context, '과목이 삭제되었습니다.');
      } catch (e) {
        if (mounted) showErrorSnackBar(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('보관함'),
        actions: [
          IconButton(
            onPressed: _showCreateFolderDialog,
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '새 과목 만들기',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadFolders,
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
            Text('보관함을 불러올 수 없습니다.',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadFolders,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_folders.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open_rounded,
                      size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    '아직 보관한 과목이 없습니다',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '카드를 만든 후 보관함에 저장해보세요',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _showCreateFolderDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('과목 만들기'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: _folders.length,
      itemBuilder: (context, index) => _buildFolderCard(cs, _folders[index]),
    );
  }

  Widget _buildFolderCard(ColorScheme cs, FolderModel folder) {
    final color = _parseColor(folder.color);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FolderDetailScreen(folder: folder),
          ),
        ).then((_) => _loadFolders());
      },
      onLongPress: () => _showFolderMenu(folder),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 컬러바
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  topRight: Radius.circular(15),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.folder_rounded, color: color, size: 28),
                    const SizedBox(height: 10),
                    Text(
                      folder.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      '${folder.sessionCount}개 세션 · ${folder.cardCount}장',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderMenu(FolderModel folder) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('수정'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditFolderDialog(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: Color(0xFFEF4444)),
              title: const Text('삭제',
                  style: TextStyle(color: Color(0xFFEF4444))),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteFolder(folder);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
