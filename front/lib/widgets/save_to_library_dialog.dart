import 'package:flutter/material.dart';
import '../models/folder_model.dart';
import '../services/api_service.dart';
import '../services/library_prefs.dart';

class SaveToLibraryDialog extends StatefulWidget {
  final String sessionId;
  final String defaultName;

  const SaveToLibraryDialog({
    super.key,
    required this.sessionId,
    required this.defaultName,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String sessionId,
    required String defaultName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => SaveToLibraryDialog(
        sessionId: sessionId,
        defaultName: defaultName,
      ),
    );
  }

  @override
  State<SaveToLibraryDialog> createState() => _SaveToLibraryDialogState();
}

class _SaveToLibraryDialogState extends State<SaveToLibraryDialog> {
  late TextEditingController _nameController;
  List<FolderModel> _folders = [];
  bool _loading = true;

  // 폴더 선택: null이면 "새 과목 만들기" 모드
  String? _selectedFolderId;
  bool get _isNewFolder => _selectedFolderId == null;

  final _newFolderController = TextEditingController();
  String _newFolderColor = '#C2E7DA';
  bool _autoSave = false;
  bool _saving = false;
  String? _errorText;

  static const _presetColors = [
    '#C2E7DA', '#6290C3', '#9B72CF', '#F59E0B', '#EF4444', '#94A3B8',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.defaultName);
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _newFolderController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final folders = await ApiService.listFolders();
      final autoSave = await LibraryPrefs.getAutoSave();
      final lastFolderId = await LibraryPrefs.getLastFolderId();
      if (mounted) {
        setState(() {
          _folders = folders;
          _autoSave = autoSave;
          // 기존 폴더가 있으면 마지막 사용 폴더 or 첫 번째 선택
          if (folders.isNotEmpty) {
            if (lastFolderId != null &&
                folders.any((f) => f.id == lastFolderId)) {
              _selectedFolderId = lastFolderId;
            } else {
              _selectedFolderId = folders.first.id;
            }
          }
          // 폴더 없으면 _selectedFolderId = null → 새 과목 모드
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _parseColor(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  Future<void> _save() async {
    if (_saving) return;

    // 새 과목인데 이름이 비어있으면 에러
    if (_isNewFolder && _newFolderController.text.trim().isEmpty) {
      setState(() => _errorText = '과목 이름을 입력해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      final displayName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : null;

      final result = await ApiService.saveToLibrary(
        sessionId: widget.sessionId,
        folderId: _isNewFolder ? null : _selectedFolderId,
        newFolderName: _isNewFolder ? _newFolderController.text.trim() : null,
        newFolderColor: _isNewFolder ? _newFolderColor : null,
        displayName: displayName,
      );

      await LibraryPrefs.setAutoSave(_autoSave);
      final savedFolderId = result['folder_id'] as String?;
      if (savedFolderId != null) {
        await LibraryPrefs.setLastFolderId(savedFolderId);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorText = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('보관함에 저장'),
      content: _loading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 세션 이름
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '이름',
                        hintText: '세션 이름',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 과목 선택
                    Text('과목',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        )),
                    const SizedBox(height: 8),

                    // 과목 목록 (칩 형태)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // 기존 폴더들
                        ..._folders.map((f) => ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: _parseColor(f.color),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(f.name),
                                ],
                              ),
                              selected: _selectedFolderId == f.id,
                              onSelected: (_) => setState(() {
                                _selectedFolderId = f.id;
                                _errorText = null;
                              }),
                            )),
                        // "새 과목" 칩
                        ChoiceChip(
                          label: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 16),
                              SizedBox(width: 4),
                              Text('새 과목'),
                            ],
                          ),
                          selected: _isNewFolder,
                          onSelected: (_) => setState(() {
                            _selectedFolderId = null;
                            _errorText = null;
                          }),
                        ),
                      ],
                    ),

                    // 새 과목 입력 필드
                    if (_isNewFolder) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _newFolderController,
                        autofocus: _folders.isNotEmpty,
                        decoration: InputDecoration(
                          labelText: '과목 이름',
                          hintText: '예: 경영학원론',
                          border: const OutlineInputBorder(),
                          errorText: _errorText,
                        ),
                        onChanged: (_) {
                          if (_errorText != null) {
                            setState(() => _errorText = null);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: _presetColors.map((c) {
                          final isSelected = c == _newFolderColor;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _newFolderColor = c),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: _parseColor(c),
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: cs.onSurface, width: 2.5)
                                      : null,
                                ),
                                child: isSelected
                                    ? Icon(Icons.check,
                                        size: 14, color: cs.onSurface)
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    // 에러 (기존 폴더 선택 시)
                    if (_errorText != null && !_isNewFolder) ...[
                      const SizedBox(height: 8),
                      Text(_errorText!,
                          style: TextStyle(color: cs.error, fontSize: 12)),
                    ],

                    const SizedBox(height: 16),

                    // 자동 저장
                    GestureDetector(
                      onTap: () =>
                          setState(() => _autoSave = !_autoSave),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: _autoSave,
                              onChanged: (v) =>
                                  setState(() => _autoSave = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '다음부터 자동으로 저장',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      actions: _loading
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('저장'),
              ),
            ],
    );
  }
}
