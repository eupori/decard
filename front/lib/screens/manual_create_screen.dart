import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../utils/snackbar_helper.dart';
import 'review_screen.dart';

/// 카드 유형 enum
enum CardType { definition, multipleChoice, cloze }

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
  final List<Map<String, String>> _cards = [];
  bool _isSaving = false;

  // 카드 유형
  CardType _selectedType = CardType.definition;

  // ── 주관식 ──
  final _frontController = TextEditingController();
  final _backController = TextEditingController();

  // ── 객관식 ──
  final _mcQuestionController = TextEditingController();
  List<TextEditingController> _mcChoiceControllers = [];
  int _mcCorrectIndex = 0; // 정답 인덱스 (0-based)

  // ── 빈칸형 ──
  final _clozeTextController = TextEditingController();
  bool _clozeSelectMode = false; // false: 텍스트 입력, true: 단어 선택
  List<String> _clozeWords = [];
  final Set<int> _clozeSelectedIndices = {};

  // 파일 가져오기 탭
  final _importSessionNameController = TextEditingController();
  String? _importFilePath;
  String? _importFileName;
  Uint8List? _importFileBytes;
  bool _isImporting = false;

  static const _circledNumbers = ['①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initMcChoices(5);
  }

  void _initMcChoices(int count) {
    _mcChoiceControllers = List.generate(count, (_) => TextEditingController());
    _mcCorrectIndex = 0;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _sessionNameController.dispose();
    _frontController.dispose();
    _backController.dispose();
    _mcQuestionController.dispose();
    for (final c in _mcChoiceControllers) {
      c.dispose();
    }
    _clozeTextController.dispose();
    _importSessionNameController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────
  // 카드 추가 로직
  // ──────────────────────────────────────

  void _addCard() {
    switch (_selectedType) {
      case CardType.definition:
        _addDefinitionCard();
      case CardType.multipleChoice:
        _addMultipleChoiceCard();
      case CardType.cloze:
        _addClozeCard();
    }
  }

  void _addDefinitionCard() {
    final front = _frontController.text.trim();
    final back = _backController.text.trim();
    if (front.isEmpty || back.isEmpty) {
      showErrorSnackBar(context, '앞면과 뒷면을 모두 입력해주세요.');
      return;
    }
    setState(() {
      _cards.add({
        'front': front,
        'back': back,
        'template_type': 'definition',
      });
      _frontController.clear();
      _backController.clear();
    });
  }

  void _addMultipleChoiceCard() {
    final question = _mcQuestionController.text.trim();
    if (question.isEmpty) {
      showErrorSnackBar(context, '질문을 입력해주세요.');
      return;
    }
    // 빈 보기 체크
    final choices = <String>[];
    for (int i = 0; i < _mcChoiceControllers.length; i++) {
      final text = _mcChoiceControllers[i].text.trim();
      if (text.isEmpty) {
        showErrorSnackBar(context, '${_circledNumbers[i]} 보기를 입력해주세요.');
        return;
      }
      choices.add(text);
    }
    // front: 질문 + 보기 리스트
    final choiceLines =
        choices.asMap().entries.map((e) => '${_circledNumbers[e.key]} ${e.value}').join('\n');
    final front = '$question\n\n$choiceLines';
    final back = '${_circledNumbers[_mcCorrectIndex]} ${choices[_mcCorrectIndex]}';

    setState(() {
      _cards.add({
        'front': front,
        'back': back,
        'template_type': 'multiple_choice',
      });
      _mcQuestionController.clear();
      for (final c in _mcChoiceControllers) {
        c.clear();
      }
      _mcCorrectIndex = 0;
    });
  }

  void _addClozeCard() {
    if (_clozeSelectedIndices.isEmpty) {
      showErrorSnackBar(context, '빈칸으로 만들 단어를 선택해주세요.');
      return;
    }
    // front: 선택된 단어를 ___로 치환
    final frontWords = <String>[];
    final answers = <String>[];
    for (int i = 0; i < _clozeWords.length; i++) {
      if (_clozeSelectedIndices.contains(i)) {
        frontWords.add('___');
        answers.add(_clozeWords[i]);
      } else {
        frontWords.add(_clozeWords[i]);
      }
    }
    final front = frontWords.join(' ');
    final back = answers.join(', ');

    setState(() {
      _cards.add({
        'front': front,
        'back': back,
        'template_type': 'cloze',
      });
      _clozeTextController.clear();
      _clozeWords.clear();
      _clozeSelectedIndices.clear();
      _clozeSelectMode = false;
    });
  }

  void _removeCard(int index) {
    setState(() => _cards.removeAt(index));
  }

  // ──────────────────────────────────────
  // 객관식 보기 추가/삭제
  // ──────────────────────────────────────

  void _addMcChoice() {
    if (_mcChoiceControllers.length >= 8) return;
    setState(() {
      _mcChoiceControllers.add(TextEditingController());
    });
  }

  void _removeMcChoice() {
    if (_mcChoiceControllers.length <= 2) return;
    setState(() {
      _mcChoiceControllers.last.dispose();
      _mcChoiceControllers.removeLast();
      if (_mcCorrectIndex >= _mcChoiceControllers.length) {
        _mcCorrectIndex = _mcChoiceControllers.length - 1;
      }
    });
  }

  // ──────────────────────────────────────
  // 빈칸형: 단어 분리 + 선택 모드 전환
  // ──────────────────────────────────────

  void _enterClozeSelectMode() {
    final text = _clozeTextController.text.trim();
    if (text.isEmpty) {
      showErrorSnackBar(context, '문장을 입력해주세요.');
      return;
    }
    setState(() {
      _clozeWords = text.split(RegExp(r'\s+'));
      _clozeSelectedIndices.clear();
      _clozeSelectMode = true;
    });
  }

  void _exitClozeSelectMode() {
    setState(() {
      _clozeSelectMode = false;
    });
  }

  // ──────────────────────────────────────
  // 저장
  // ──────────────────────────────────────

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

  // ──────────────────────────────────────
  // 파일 가져오기
  // ──────────────────────────────────────

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

  // ──────────────────────────────────────
  // Build
  // ──────────────────────────────────────

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

  // ──────────────────────────────────────
  // 직접 입력 탭
  // ──────────────────────────────────────

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
                  // 카드 유형 선택
                  Text('카드 유형',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _buildTypeSelector(cs),
                  const SizedBox(height: 20),
                  Text('카드 추가',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  // 유형별 폼
                  _buildCardForm(cs),
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

  // ──────────────────────────────────────
  // 카드 유형 선택 (SegmentedButton)
  // ──────────────────────────────────────

  Widget _buildTypeSelector(ColorScheme cs) {
    return SegmentedButton<CardType>(
      segments: const [
        ButtonSegment(
          value: CardType.definition,
          label: Text('주관식'),
          icon: Icon(Icons.quiz_outlined, size: 18),
        ),
        ButtonSegment(
          value: CardType.multipleChoice,
          label: Text('객관식'),
          icon: Icon(Icons.checklist_rounded, size: 18),
        ),
        ButtonSegment(
          value: CardType.cloze,
          label: Text('빈칸형'),
          icon: Icon(Icons.space_bar_rounded, size: 18),
        ),
      ],
      selected: {_selectedType},
      onSelectionChanged: (selected) {
        setState(() => _selectedType = selected.first);
      },
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: cs.primaryContainer,
        selectedForegroundColor: cs.onPrimaryContainer,
      ),
    );
  }

  // ──────────────────────────────────────
  // 유형별 입력 폼
  // ──────────────────────────────────────

  Widget _buildCardForm(ColorScheme cs) {
    switch (_selectedType) {
      case CardType.definition:
        return _buildDefinitionForm();
      case CardType.multipleChoice:
        return _buildMultipleChoiceForm(cs);
      case CardType.cloze:
        return _buildClozeForm(cs);
    }
  }

  /// 주관식: 앞면 + 뒷면
  Widget _buildDefinitionForm() {
    return Column(
      children: [
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
      ],
    );
  }

  /// 객관식: 질문 + 보기 리스트 + 정답 선택
  Widget _buildMultipleChoiceForm(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _mcQuestionController,
          decoration: const InputDecoration(
            hintText: '질문',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        RadioGroup<int>(
          groupValue: _mcCorrectIndex,
          onChanged: (v) => setState(() => _mcCorrectIndex = v!),
          child: Column(
            children: [
              for (int i = 0; i < _mcChoiceControllers.length; i++) ...[
                Row(
                  children: [
                    Radio<int>(
                      value: i,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    Text(_circledNumbers[i],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _mcCorrectIndex == i ? cs.primary : cs.onSurfaceVariant,
                        )),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _mcChoiceControllers[i],
                        decoration: InputDecoration(
                          hintText: '보기 ${i + 1}',
                          border: const OutlineInputBorder(),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _mcChoiceControllers.length <= 2 ? null : _removeMcChoice,
              icon: const Icon(Icons.remove_rounded, size: 16),
              label: const Text('보기 삭제'),
              style: OutlinedButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _mcChoiceControllers.length >= 8 ? null : _addMcChoice,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('보기 추가'),
              style: OutlinedButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 빈칸형: 텍스트 입력 → 단어 선택 → 미리보기
  Widget _buildClozeForm(ColorScheme cs) {
    if (!_clozeSelectMode) {
      // 상태 1: 텍스트 입력
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _clozeTextController,
            decoration: const InputDecoration(
              hintText: '전체 문장을 입력하세요',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _enterClozeSelectMode,
              icon: const Icon(Icons.touch_app_rounded, size: 16),
              label: const Text('빈칸 선택하기'),
              style: OutlinedButton.styleFrom(
                minimumSize: Size.zero,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ],
      );
    }

    // 상태 2: 단어 선택 모드
    // 미리보기 생성
    final previewWords = <String>[];
    for (int i = 0; i < _clozeWords.length; i++) {
      previewWords
          .add(_clozeSelectedIndices.contains(i) ? '___' : _clozeWords[i]);
    }
    final previewText = previewWords.join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 뒤로가기 버튼
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _exitClozeSelectMode,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('문장 수정'),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('탭하여 빈칸으로 만들 단어를 선택하세요',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        // 단어 Wrap
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(_clozeWords.length, (i) {
              final isSelected = _clozeSelectedIndices.contains(i);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _clozeSelectedIndices.remove(i);
                    } else {
                      _clozeSelectedIndices.add(i);
                    }
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primary
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _clozeWords[i],
                    style: TextStyle(
                      color: isSelected
                          ? cs.onPrimary
                          : cs.onSurface,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        // 미리보기
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('미리보기',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(previewText,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────
  // 추가된 카드 아이템
  // ──────────────────────────────────────

  Widget _buildCardItem(ColorScheme cs, int index) {
    final card = _cards[index];
    final type = card['template_type'] ?? 'definition';

    // 유형 태그
    final (String label, Color color) = switch (type) {
      'multiple_choice' => ('객관식', cs.tertiary),
      'cloze' => ('빈칸형', cs.secondary),
      _ => ('주관식', cs.primary),
    };

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
            // 유형 태그
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color)),
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

  // ──────────────────────────────────────
  // 파일 가져오기 탭
  // ──────────────────────────────────────

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
