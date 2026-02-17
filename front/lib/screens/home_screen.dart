import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart' show themeNotifier;
import '../models/session_model.dart';
import '../services/api_service.dart';
import 'review_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedFilePath;
  String? _selectedFileName;
  Uint8List? _selectedFileBytes;
  String _templateType = 'definition';
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> _sessions = [];
  bool _sessionsLoading = true;

  final _templateOptions = [
    ('definition', '정의형', 'OO란? 형태의 Q&A', Icons.menu_book_rounded),
    ('cloze', '빈칸형', '핵심 키워드 빈칸 채우기', Icons.edit_note_rounded),
    ('comparison', '비교형', 'A vs B 차이점 비교', Icons.compare_arrows_rounded),
  ];

  bool get _hasFile =>
      _selectedFileName != null &&
      (_selectedFilePath != null || _selectedFileBytes != null);

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await ApiService.listSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {
      // 실패해도 무시
    } finally {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _openSession(String sessionId) async {
    setState(() => _isLoading = true);
    try {
      final session = await ApiService.getSession(sessionId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewScreen(session: session)),
      ).then((_) => _loadSessions());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '오류가 발생했습니다: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    try {
      await ApiService.deleteSession(sessionId);
      setState(() => _sessions.removeWhere((s) => s['id'] == sessionId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: kIsWeb,
    );

    if (result != null) {
      setState(() {
        _selectedFilePath = kIsWeb ? null : result.files.single.path;
        _selectedFileName = result.files.single.name;
        _selectedFileBytes = result.files.single.bytes;
        _error = null;
      });
    }
  }

  Future<void> _generate() async {
    if (!_hasFile) {
      setState(() => _error = 'PDF 파일을 선택해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      late final SessionModel session;
      if (kIsWeb && _selectedFileBytes != null) {
        session = await ApiService.generateFromBytes(
          bytes: _selectedFileBytes!,
          fileName: _selectedFileName!,
          templateType: _templateType,
        );
      } else {
        session = await ApiService.generate(
          filePath: _selectedFilePath!,
          fileName: _selectedFileName!,
          templateType: _templateType,
        );
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewScreen(session: session)),
      ).then((_) => _loadSessions());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '오류가 발생했습니다: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: _isLoading ? _buildLoading(cs) : _buildMain(cs),
      ),
    );
  }

  Widget _buildLoading(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '카드를 만들고 있어요',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'PDF를 분석하고 근거 포함 카드를 생성 중...\n약 15~30초 소요됩니다.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMain(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 다크모드 토글
          Align(
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, mode, _) {
                final isDark = mode == ThemeMode.dark;
                return IconButton(
                  onPressed: () {
                    themeNotifier.value =
                        isDark ? ThemeMode.light : ThemeMode.dark;
                  },
                  icon: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  tooltip: isDark ? '라이트 모드' : '다크 모드',
                );
              },
            ),
          ),

          // 로고 + 타이틀
          Center(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child:
                      Icon(Icons.style_rounded, size: 32, color: cs.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  '데카드',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'PDF 올리면 시험 대비 끝.\n근거 포함 암기카드를 자동으로 만들어드려요.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // 1. PDF 업로드
          Text(
            '1. PDF 파일 선택',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          InkWell(
            onTap: _pickFile,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _hasFile ? cs.primary : cs.outlineVariant,
                  width: _hasFile ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(16),
                color: _hasFile
                    ? cs.primaryContainer.withValues(alpha: 0.3)
                    : null,
              ),
              child: Column(
                children: [
                  Icon(
                    _hasFile
                        ? Icons.check_circle_rounded
                        : Icons.upload_file_rounded,
                    size: 40,
                    color: _hasFile ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedFileName ?? '탭하여 PDF를 선택하세요',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _hasFile ? cs.primary : cs.onSurfaceVariant,
                          fontWeight: _hasFile ? FontWeight.w600 : null,
                        ),
                  ),
                  if (!_hasFile) ...[
                    const SizedBox(height: 4),
                    Text(
                      '강의자료, 교재, 필기노트 등',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // 2. 템플릿 선택
          Text(
            '2. 카드 유형 선택',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          for (final t in _templateOptions)
            _buildTemplateOption(cs,
                value: t.$1, label: t.$2, desc: t.$3, icon: t.$4),

          const SizedBox(height: 32),

          // 에러
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: cs.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: TextStyle(color: cs.onErrorContainer))),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 생성 버튼
          FilledButton.icon(
            onPressed: _hasFile ? _generate : null,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('카드 만들기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),

          const SizedBox(height: 40),

          // 이전 기록 (최대 10개)
          if (_sessions.isNotEmpty) ...[
            Text(
              '이전 기록',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            for (final s in _sessions.take(10)) _buildSessionItem(cs, s),

            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionItem(ColorScheme cs, Map<String, dynamic> session) {
    final filename = (session['filename'] as String).replaceAll('.pdf', '');
    final cardCount = session['card_count'] as int;
    final templateType = session['template_type'] as String;
    final createdAt = DateTime.tryParse(session['created_at'] as String);
    final timeAgo = createdAt != null ? _formatTimeAgo(createdAt) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openSession(session['id'] as String),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.description_outlined,
                  size: 24, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filename,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_templateLabel(templateType)} · ${cardCount}장 · $timeAgo',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _deleteSession(session['id'] as String),
                icon: Icon(Icons.close_rounded,
                    size: 18, color: cs.onSurfaceVariant),
                tooltip: '삭제',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildTemplateOption(
    ColorScheme cs, {
    required String value,
    required String label,
    required String desc,
    required IconData icon,
  }) {
    final selected = _templateType == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _templateType = value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? cs.primaryContainer.withValues(alpha: 0.3)
                : null,
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: selected ? cs.primary : null)),
                    Text(desc,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: cs.primary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
