import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../utils/snackbar_helper.dart';
import 'review_screen.dart';

class ManualCreateScreen extends StatefulWidget {
  const ManualCreateScreen({super.key});

  @override
  State<ManualCreateScreen> createState() => _ManualCreateScreenState();
}

class _ManualCreateScreenState extends State<ManualCreateScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 직접 입력 탭
  final _sessionNameController = TextEditingController();
  final _frontController = TextEditingController();
  final _backController = TextEditingController();
  final List<Map<String, String>> _cards = [];
  bool _isSaving = false;

  // 파일 가져오기 탭
  final _importSessionNameController = TextEditingController();
  String? _importFilePath;
  String? _importFileName;
  Uint8List? _importFileBytes;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _sessionNameController.dispose();
    _frontController.dispose();
    _backController.dispose();
    _importSessionNameController.dispose();
    super.dispose();
  }

  void _addCard() {
    final front = _frontController.text.trim();
    final back = _backController.text.trim();
    if (front.isEmpty || back.isEmpty) {
      showErrorSnackBar(context, '앞면과 뒷면을 모두 입력해주세요.');
      return;
    }
    setState(() {
      _cards.add({'front': front, 'back': back});
      _frontController.clear();
      _backController.clear();
    });
  }

  void _removeCard(int index) {
    setState(() => _cards.removeAt(index));
  }

  Future<void> _saveManualCards() async {
    if (_cards.isEmpty) {
      showErrorSnackBar(context, '최소 1장의 카드를 추가해주세요.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final session = await ApiService.createManualSession(
        displayName: _sessionNameController.text.trim().isNotEmpty
            ? _sessionNameController.text.trim()
            : null,
        cards: _cards,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ReviewScreen(session: session)),
      );
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickImportFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
      withData: kIsWeb,
    );
    if (result != null) {
      setState(() {
        _importFilePath = kIsWeb ? null : result.files.single.path;
        _importFileName = result.files.single.name;
        _importFileBytes = result.files.single.bytes;
      });
    }
  }

  Future<void> _importFile() async {
    if (_importFileName == null) {
      showErrorSnackBar(context, '파일을 선택해주세요.');
      return;
    }
    setState(() => _isImporting = true);
    try {
      final session = await ApiService.importFile(
        bytes: _importFileBytes,
        filePath: _importFilePath,
        fileName: _importFileName!,
        displayName: _importSessionNameController.text.trim().isNotEmpty
            ? _importSessionNameController.text.trim()
            : null,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ReviewScreen(session: session)),
      );
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('직접 카드 만들기'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '직접 입력'),
            Tab(text: '파일 가져오기'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildManualTab(cs),
          _buildImportTab(cs),
        ],
      ),
    );
  }

  Widget _buildManualTab(ColorScheme cs) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _sessionNameController,
                    decoration: const InputDecoration(
                      hintText: '세션 이름 (선택)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('카드 추가',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _frontController,
                    decoration: const InputDecoration(
                      hintText: '앞면 (질문)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _backController,
                    decoration: const InputDecoration(
                      hintText: '뒷면 (답)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _addCard,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('카드 추가'),
                      style: FilledButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  if (_cards.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('추가된 카드 (${_cards.length}장)',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _cards.length; i++)
                      _buildCardItem(cs, i),
                  ],
                ],
              ),
            ),
          ),
          // 저장 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: FilledButton.icon(
              onPressed: _cards.isEmpty || _isSaving ? null : _saveManualCards,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text('저장 (${_cards.length}장)',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardItem(ColorScheme cs, int index) {
    final card = _cards[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${index + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card['front']!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(card['back']!,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _removeCard(index),
              icon: Icon(Icons.close_rounded,
                  size: 18, color: cs.onSurfaceVariant),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportTab(ColorScheme cs) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text(
                'CSV 또는 XLSX 파일을 선택하세요.\n1열: 앞면(질문), 2열: 뒷면(답), 3열: 근거(선택)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: _pickImportFile,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _importFileName != null
                        ? cs.primary
                        : cs.outlineVariant,
                    width: _importFileName != null ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  color: _importFileName != null
                      ? cs.primaryContainer.withValues(alpha: 0.3)
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      _importFileName != null
                          ? Icons.check_circle_rounded
                          : Icons.upload_file_rounded,
                      size: 40,
                      color: _importFileName != null
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _importFileName ?? '탭하여 CSV/XLSX 파일을 선택하세요',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: _importFileName != null
                                ? cs.primary
                                : cs.onSurfaceVariant,
                            fontWeight: _importFileName != null
                                ? FontWeight.w600
                                : null,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _importSessionNameController,
              decoration: const InputDecoration(
                hintText: '세션 이름 (선택)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed:
                  _importFileName == null || _isImporting ? null : _importFile,
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.file_download_rounded),
              label: const Text('가져오기',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
