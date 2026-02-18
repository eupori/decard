import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart' show themeNotifier;
import '../models/session_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_helper.dart';
import '../utils/web_auth_stub.dart'
    if (dart.library.html) '../utils/web_auth.dart' as web_auth;
import 'login_screen.dart';
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
  bool _sessionsError = false;

  // Auth state
  bool _isLoggedIn = false;
  Map<String, dynamic>? _user;

  // Loading animation
  int _loadingMessageIndex = 0;
  Timer? _loadingTimer;
  final _loadingMessages = [
    'PDF 분석 중...',
    '텍스트 추출 중...',
    '카드 생성 중...',
    '근거 매칭 중...',
    '거의 완료...',
  ];

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
    _handleOAuthCallback();
    _checkAuthState();
    _loadSessions();
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleOAuthCallback() async {
    if (!kIsWeb) return;

    // URL fragment에서 토큰 추출
    final token = web_auth.extractTokenFromUrl();
    if (token != null) {
      await AuthService.setToken(token);
      await AuthService.linkDevice();
      await _checkAuthState();
      _loadSessions();
      if (mounted) showSuccessSnackBar(context, '로그인되었습니다!');
      return;
    }

    // 에러 확인
    final error = web_auth.extractAuthErrorFromUrl();
    if (error != null && mounted) {
      showErrorSnackBar(context, '로그인에 실패했습니다. 다시 시도해주세요.');
    }
  }

  Future<void> _checkAuthState() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (loggedIn) {
      final user = await AuthService.getUser();
      if (mounted) {
        setState(() {
          _isLoggedIn = user != null;
          _user = user;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoggedIn = false;
          _user = null;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    // 로그인 화면에서 돌아온 후 상태 확인
    if (result == true || result == null) {
      await _checkAuthState();
      _loadSessions();
    }
  }

  Future<void> _handleLogout() async {
    await AuthService.logout();
    setState(() {
      _isLoggedIn = false;
      _user = null;
    });
    _loadSessions();
    if (mounted) showSuccessSnackBar(context, '로그아웃되었습니다.');
  }

  void _startLoadingAnimation() {
    _loadingMessageIndex = 0;
    _loadingTimer?.cancel();
    _loadingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && _isLoading) {
        setState(() {
          _loadingMessageIndex =
              (_loadingMessageIndex + 1) % _loadingMessages.length;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _loadSessions() async {
    setState(() {
      _sessionsLoading = true;
      _sessionsError = false;
    });
    try {
      final sessions = await ApiService.listSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {
      if (mounted) setState(() => _sessionsError = true);
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
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDeleteSession(String sessionId, String filename) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('세션 삭제'),
        content: Text('"$filename" 세션을 삭제하시겠습니까?\n생성된 카드도 모두 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
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
      _deleteSession(sessionId);
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    try {
      await ApiService.deleteSession(sessionId);
      setState(() => _sessions.removeWhere((s) => s['id'] == sessionId));
      if (mounted) showSuccessSnackBar(context, '세션이 삭제되었습니다.');
    } catch (e) {
      if (mounted) showErrorSnackBar(context, '삭제 실패: ${friendlyError(e)}');
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
    _startLoadingAnimation();

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
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      _loadingTimer?.cancel();
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _loadingMessages[_loadingMessageIndex],
                key: ValueKey<int>(_loadingMessageIndex),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '약 15~30초 소요됩니다.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMain(ColorScheme cs) {
    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 바: 다크모드 토글 + 로그인/프로필
            Row(
              children: [
                const Spacer(),
                // 다크모드 토글
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (context, mode, _) {
                    final isDark = mode == ThemeMode.dark;
                    return IconButton(
                      onPressed: () {
                        themeNotifier.value =
                            isDark ? ThemeMode.light : ThemeMode.dark;
                      },
                      icon: Icon(
                        isDark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      tooltip: isDark ? '라이트 모드' : '다크 모드',
                    );
                  },
                ),
                const SizedBox(width: 4),
                // 로그인 버튼 또는 프로필
                if (_isLoggedIn && _user != null)
                  _buildProfileChip(cs)
                else
                  _buildLoginButton(cs),
              ],
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
                    child: Icon(Icons.style_rounded,
                        size: 32, color: cs.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '데카드',
                    style:
                        Theme.of(context).textTheme.headlineMedium?.copyWith(
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
                      style:
                          Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: _hasFile
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                                fontWeight:
                                    _hasFile ? FontWeight.w600 : null,
                              ),
                    ),
                    if (!_hasFile) ...[
                      const SizedBox(height: 4),
                      Text(
                        '강의자료, 교재, 필기노트 등',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
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
                            style:
                                TextStyle(color: cs.onErrorContainer))),
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
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),

            const SizedBox(height: 40),

            // 이전 기록
            _buildSessionsSection(cs),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsSection(ColorScheme cs) {
    // Loading state - skeleton
    if (_sessionsLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이전 기록',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < 3; i++) _buildSkeletonItem(cs),
        ],
      );
    }

    // Error state
    if (_sessionsError) {
      return Center(
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('기록을 불러올 수 없습니다.',
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

    // Empty state - onboarding tip
    if (_sessions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(Icons.lightbulb_outline_rounded,
                size: 36, color: cs.primary),
            const SizedBox(height: 12),
            Text(
              '이렇게 사용하세요',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '1. 시험 범위 PDF를 업로드하세요\n'
              '2. AI가 근거 포함 암기카드를 만들어요\n'
              '3. 카드를 검수하고 학습하세요',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.6,
                  ),
            ),
          ],
        ),
      );
    }

    // Sessions list
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '이전 기록',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        for (final s in _sessions.take(10)) _buildSessionItem(cs, s),
      ],
    );
  }

  Widget _buildSkeletonItem(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 120,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 10,
                    width: 80,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
              // Template type icon
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
                      filename,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_templateLabel(templateType)} · $cardCount장 · $timeAgo',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                    ),
                  ],
                ),
              ),
              // Card count badge
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
                onPressed: () => _confirmDeleteSession(
                    session['id'] as String, filename),
                icon: Icon(Icons.close_rounded,
                    size: 18, color: cs.onSurfaceVariant),
                tooltip: '삭제',
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

  IconData _templateIcon(String type) {
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
      case 'subjective':
        return '주관식';
      default:
        return type;
    }
  }

  Widget _buildLoginButton(ColorScheme cs) {
    return TextButton(
      onPressed: _handleLogin,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(
        '로그인',
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildProfileChip(ColorScheme cs) {
    final nickname = _user?['nickname'] ?? '';
    final profileImage = _user?['profile_image'] ?? '';

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: profileImage.isNotEmpty
                        ? NetworkImage(profileImage)
                        : null,
                    child: profileImage.isEmpty
                        ? const Icon(Icons.person_rounded)
                        : null,
                  ),
                  title: Text(nickname.isNotEmpty ? nickname : '사용자'),
                  subtitle: const Text('카카오 계정'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('로그아웃'),
                  onTap: () {
                    Navigator.pop(context);
                    _handleLogout();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: profileImage.isNotEmpty
                  ? NetworkImage(profileImage)
                  : null,
              backgroundColor: cs.primaryContainer,
              child: profileImage.isEmpty
                  ? Icon(Icons.person_rounded, size: 18, color: cs.primary)
                  : null,
            ),
            const SizedBox(width: 6),
            Text(
              nickname.isNotEmpty ? nickname : '사용자',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
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
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    color: cs.primary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
