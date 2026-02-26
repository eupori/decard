import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show themeNotifier, oauthHandledInMain;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/library_prefs.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/session_list_item.dart';
import '../utils/web_auth_stub.dart'
    if (dart.library.html) '../utils/web_auth.dart' as web_auth;
import '../models/card_model.dart';
import 'login_screen.dart';
import 'main_screen.dart' show hideBottomNav, mainTabIndex;
import 'manual_create_screen.dart';
import 'review_screen.dart';
import 'study_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedFilePath;
  String? _selectedFileName;
  Uint8List? _selectedFileBytes;
  int? _selectedFileSize;
  String _templateType = 'definition';
  String? _error;

  // Generate overlay state
  bool _showGeneratingValue = false;
  bool get _showGenerating => _showGeneratingValue;
  set _showGenerating(bool v) {
    _showGeneratingValue = v;
    hideBottomNav.value = v;
  }
  bool _uploadDone = false;
  double _uploadProgress = 0.0;
  bool _serverProcessing = false;
  bool _waitingHere = false;
  String? _generatedSessionId;
  int _generatedPageCount = 0;
  int _tipIndex = 0;
  Timer? _tipTimer;
  Timer? _progressTimer;
  double _progress = 0.0;
  int _elapsedSeconds = 0;

  final _tips = [
    'PDF 꼼꼼히 읽는 중...',
    '중요한 내용 밑줄 긋는 중...',
    '문제 카드에 적는 중...',
    '카드 모양 자르는 중...',
    '흩어진 카드 모으는 중...',
    '근거 페이지 찾아 붙이는 중...',
    '머릿속에 지식 넣는 중...',
    '시험에 나올 것만 골라내는 중...',
    '거의 다 됐어요, 조금만요...',
  ];

  List<Map<String, dynamic>> _sessions = [];
  bool _sessionsLoading = true;
  bool _sessionsError = false;

  // Auth state
  bool _isLoggedIn = false;
  Map<String, dynamic>? _user;

  // Polling for processing sessions
  Timer? _pollingTimer;

  // SRS state
  int _dueCards = 0;
  int _streakDays = 0;
  int _reviewsToday = 0;
  bool _statsLoaded = false;

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
    _loadStudyStats();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _tipTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleOAuthCallback() async {
    if (!kIsWeb) return;

    // main()에서 이미 처리한 경우 스낵바만 표시
    if (oauthHandledInMain) {
      oauthHandledInMain = false;
      await _checkAuthState();
      _loadSessions();
      if (mounted) showSuccessSnackBar(context, '로그인되었습니다!');
      return;
    }

    // 폴백: main()에서 못 잡은 경우
    final token = web_auth.extractTokenFromUrl();
    if (token != null) {
      await AuthService.setToken(token);
      await AuthService.linkDevice();
      web_auth.clearUrlFragment();
      await _checkAuthState();
      _loadSessions();
      if (mounted) showSuccessSnackBar(context, '로그인되었습니다!');
      return;
    }

    // 에러 확인
    final error = web_auth.extractAuthErrorFromUrl();
    if (error != null && mounted) {
      web_auth.clearUrlFragment();
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

  int get _estimatedSeconds => (_generatedPageCount * 35).clamp(90, 900);

  String get _estimatedTimeLabel {
    final minutes = (_estimatedSeconds / 60).ceil();
    return '약 $minutes분 소요';
  }

  void _startWaitingHere() {
    _elapsedSeconds = 0;
    _progress = 0.0;

    setState(() => _waitingHere = true);

    // 문구 로테이션
    _tipIndex = 0;
    _tipTimer?.cancel();
    _tipTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _waitingHere) {
        setState(() => _tipIndex = (_tipIndex + 1) % _tips.length);
      }
    });

    // 프로그레스 바 (1초마다 업데이트, 점근적으로 99%까지)
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _waitingHere) {
        _elapsedSeconds++;
        setState(() {
          // 예상 시간까지 선형으로 80%까지, 이후 점근적으로 99%까지
          final linear = (_elapsedSeconds / _estimatedSeconds).clamp(0.0, 0.8);
          if (linear < 0.8) {
            _progress = linear;
          } else {
            // 80% 이후: 느리게 99%까지 접근 (절대 멈추지 않음)
            final overtime = _elapsedSeconds - (_estimatedSeconds * 0.8).toInt();
            _progress = 0.8 + 0.19 * (1 - 1 / (1 + overtime / 60.0));
          }
        });
      }
    });

    // 완료 폴링 (5초 간격)
    _pollUntilDone();
  }

  Future<void> _pollUntilDone() async {
    while (mounted && _waitingHere && _generatedSessionId != null) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted || !_waitingHere) return;

      try {
        final sessions = await ApiService.listSessions();
        final target = sessions.firstWhere(
          (s) => s['id'] == _generatedSessionId,
          orElse: () => <String, dynamic>{},
        );

        if (target.isEmpty) continue;

        final status = target['status'] as String?;
        if (status == 'completed') {
          _tipTimer?.cancel();
          _progressTimer?.cancel();
          if (!mounted) return;

          // 자동 저장
          await _tryAutoSave(_generatedSessionId!);

          final session = await ApiService.getSession(_generatedSessionId!);
          if (!mounted) return;

          setState(() {
            _showGenerating = false;
            _waitingHere = false;
          });

          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ReviewScreen(session: session)),
          ).then((_) => _loadSessions());
          return;
        } else if (status == 'failed') {
          _tipTimer?.cancel();
          _progressTimer?.cancel();
          if (!mounted) return;
          setState(() {
            _showGenerating = false;
            _waitingHere = false;
          });
          showErrorSnackBar(context, '카드 생성에 실패했습니다. 다른 PDF로 시도해주세요.');
          _loadSessions();
          return;
        }
      } catch (_) {
        // 폴링 실패는 무시, 다음 주기에 재시도
      }
    }
  }

  void _startPollingIfNeeded() {
    final hasProcessing = _sessions.any((s) => s['status'] == 'processing');
    if (hasProcessing && _pollingTimer == null) {
      _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _pollSessions();
      });
    } else if (!hasProcessing && _pollingTimer != null) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  Future<void> _pollSessions() async {
    // 이전 processing 세션 ID들 기억
    final previousProcessing = _sessions
        .where((s) => s['status'] == 'processing')
        .map((s) => s['id'] as String)
        .toSet();

    try {
      final sessions = await ApiService.listSessions();
      if (!mounted) return;
      setState(() => _sessions = sessions);

      // processing → completed로 바뀐 세션 감지
      for (final id in previousProcessing) {
        final updated = sessions.firstWhere(
          (s) => s['id'] == id,
          orElse: () => <String, dynamic>{},
        );
        if (updated.isNotEmpty && updated['status'] == 'completed') {
          final cardCount = updated['card_count'] as int;
          // 자동 저장
          await _tryAutoSave(id);
          if (mounted) {
            showSuccessSnackBar(context, '카드 $cardCount장이 생성되었습니다!');
          }
        }
      }

      _startPollingIfNeeded();
    } catch (_) {
      // 폴링 실패는 무시 (다음 주기에 재시도)
    }
  }

  Future<void> _tryAutoSave(String sessionId) async {
    try {
      final autoSave = await LibraryPrefs.getAutoSave();
      if (!autoSave) return;
      final folderId = await LibraryPrefs.getLastFolderId();
      if (folderId == null) return;
      await ApiService.saveToLibrary(
        sessionId: sessionId,
        folderId: folderId,
      );
    } catch (_) {
      // 자동 저장 실패 시 무시 (폴더 삭제됐을 수 있음)
      await LibraryPrefs.setLastFolderId(null);
    }
  }

  Future<void> _loadSessions() async {
    setState(() {
      _sessionsLoading = true;
      _sessionsError = false;
    });
    try {
      final sessions = await ApiService.listSessions();
      if (mounted) {
        setState(() => _sessions = sessions);
        _startPollingIfNeeded();
      }
    } catch (_) {
      if (mounted) setState(() => _sessionsError = true);
    } finally {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _loadStudyStats() async {
    try {
      final stats = await ApiService.getStudyStats();
      if (mounted) {
        setState(() {
          _dueCards = stats['due_cards'] as int? ?? 0;
          _streakDays = stats['streak_days'] as int? ?? 0;
          _reviewsToday = stats['reviews_today'] as int? ?? 0;
          _statsLoaded = true;
        });
      }
    } catch (_) {
      // 통계 로드 실패 시 무시 (SRS 기능 없이도 앱 정상 작동)
    }
  }

  Future<void> _startSrsStudy() async {
    try {
      final dueCardsData = await ApiService.getDueCards();
      if (!mounted) return;

      if (dueCardsData.isEmpty) {
        showInfoSnackBar(context, '복습할 카드가 없습니다.');
        return;
      }

      final cards = dueCardsData.map((data) => CardModel.fromJson(data)).toList();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudyScreen(
            cards: cards,
            title: '오늘의 복습',
            srsMode: true,
          ),
        ),
      ).then((_) {
        _loadStudyStats();
        _loadSessions();
      });
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
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
        _selectedFileSize = result.files.single.size;
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
      _error = null;
      _showGenerating = true;
      _uploadDone = false;
      _uploadProgress = 0.0;
      _serverProcessing = false;
    });

    try {
      final result = await ApiService.generateWithProgress(
        bytes: (kIsWeb && _selectedFileBytes != null) ? _selectedFileBytes : null,
        filePath: (!kIsWeb && _selectedFilePath != null) ? _selectedFilePath : null,
        fileName: _selectedFileName!,
        templateType: _templateType,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
              if (progress >= 0.99) _serverProcessing = true;
            });
          }
        },
      );

      if (!mounted) return;

      // 업로드 성공 → 안내 화면으로 전환
      setState(() {
        _uploadDone = true;
        _generatedSessionId = result.id;
        _generatedPageCount = result.pageCount;
        _selectedFilePath = null;
        _selectedFileName = null;
        _selectedFileBytes = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _showGenerating = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: _showGenerating ? _buildGenerating(cs) : _buildMain(cs),
      ),
    );
  }

  Widget _buildGenerating(ColorScheme cs) {
    // 단계 3: 포그라운드 대기 (프로그레스 + 감성 문구)
    if (_waitingHere) {
      final percent = (_progress * 100).toInt();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 프로그레스 원형
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 4,
                        color: cs.primary,
                        backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                '카드를 만들고 있어요',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_estimatedTimeLabel · $_generatedPageCount페이지',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),
              // 감성 문구
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  _tips[_tipIndex],
                  key: ValueKey<int>(_tipIndex),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () {
                  _tipTimer?.cancel();
                  _progressTimer?.cancel();
                  setState(() {
                    _waitingHere = false;
                    _showGenerating = false;
                  });
                  _loadSessions();
                  showInfoSnackBar(context, '완료되면 알려드릴게요!');
                },
                icon: const Icon(Icons.home_rounded, size: 18),
                label: const Text('홈에서 기다릴게요'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 단계 1~2: 업로드 중 → 선택지
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _uploadDone
                  ? Icon(Icons.check_circle_rounded,
                      key: const ValueKey('done'),
                      size: 64,
                      color: cs.primary)
                  : _serverProcessing
                      ? SizedBox(
                          key: const ValueKey('server'),
                          width: 64,
                          height: 64,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: cs.primary,
                          ),
                        )
                      : SizedBox(
                          key: const ValueKey('loading'),
                          width: 64,
                          height: 64,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: _uploadProgress > 0 ? _uploadProgress : null,
                                strokeWidth: 3,
                                color: cs.primary,
                                backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                              ),
                              if (_uploadProgress > 0)
                                Text(
                                  '${(_uploadProgress * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: cs.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),
            const SizedBox(height: 32),
            Text(
              _uploadDone ? '카드 생성이 시작되었어요!'
                : _serverProcessing ? '서버에서 처리 중...'
                : '업로드 중...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              _uploadDone
                  ? 'AI가 카드를 만들고 있어요.\n어떻게 하시겠어요?'
                  : _serverProcessing
                      ? '업로드 완료 \u2713 잠시만 기다려주세요.'
                      : 'PDF를 서버로 전송하고 있어요...',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
            if (_uploadDone) ...[
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: _startWaitingHere,
                icon: const Icon(Icons.hourglass_top_rounded),
                label: Text('완료까지 기다리기 ($_estimatedTimeLabel)'),
                style: FilledButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _showGenerating = false);
                  _loadSessions();
                  showInfoSnackBar(context, '완료되면 알려드릴게요!');
                },
                icon: const Icon(Icons.home_rounded),
                label: const Text('홈으로 돌아가기'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                ),
              ),
            ],
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
            // 상단 바: 가이드 + 다크모드 토글 + 로그인/프로필
            Row(
              children: [
                IconButton(
                  onPressed: () => _showGuide(cs),
                  icon: Icon(Icons.help_outline_rounded,
                      color: cs.onSurfaceVariant),
                  tooltip: '이용 가이드',
                ),
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

            // 오늘의 복습 배너
            if (_statsLoaded && _dueCards > 0) ...[
              const SizedBox(height: 28),
              _buildDueCardsBanner(cs),
            ],

            const SizedBox(height: 28),

            // ── PDF 카드 (메인) ──
            Card(
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _hasFile ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
                  width: _hasFile ? 1.5 : 1,
                ),
              ),
              color: cs.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.picture_as_pdf_rounded, size: 22, color: cs.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('PDF로 카드 만들기',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                )),
                              Text('강의자료, 교재를 올려보세요',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                )),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 파일 선택 영역
                    InkWell(
                      onTap: _pickFile,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: _hasFile
                              ? cs.primaryContainer.withValues(alpha: 0.3)
                              : cs.outlineVariant.withValues(alpha: 0.15),
                          border: Border.all(
                            color: _hasFile ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _hasFile ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                              size: 28,
                              color: _hasFile ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedFileName ?? '탭하여 PDF를 선택하세요',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: _hasFile ? cs.primary : cs.onSurfaceVariant,
                                      fontWeight: _hasFile ? FontWeight.w600 : null,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_hasFile && _selectedFileSize != null)
                                    Text(
                                      _formatFileSize(_selectedFileSize!),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (_hasFile)
                              Icon(Icons.swap_horiz_rounded, size: 20, color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 카드 유형 선택 (3개 가로 칩)
                    Wrap(
                      spacing: 8,
                      children: _templateOptions.map((t) {
                        final selected = _templateType == t.$1;
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(t.$4, size: 15,
                                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(t.$2, style: TextStyle(fontSize: 13)),
                            ],
                          ),
                          selected: selected,
                          onSelected: (_) => setState(() => _templateType = t.$1),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      }).toList(),
                    ),

                    // 에러
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: cs.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: TextStyle(color: cs.onErrorContainer, fontSize: 13))),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // 생성 버튼
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _hasFile ? _generate : null,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                        label: const Text('카드 만들기',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── 하단 2열 카드 (카드셋 둘러보기 / 직접 만들기) ──
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    cs,
                    icon: Icons.explore_rounded,
                    iconColor: cs.tertiary,
                    iconBgColor: cs.tertiaryContainer,
                    title: '카드셋 둘러보기',
                    subtitle: '인기 자격증\n카드셋 탐색',
                    onTap: () => mainTabIndex.value = 1,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionCard(
                    cs,
                    icon: Icons.edit_note_rounded,
                    iconColor: cs.secondary,
                    iconBgColor: cs.secondaryContainer,
                    title: '직접 만들기',
                    subtitle: '나만의\n카드 입력',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ManualCreateScreen()),
                      ).then((_) => _loadSessions());
                    },
                  ),
                ),
              ],
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
        for (final s in _sessions.take(5))
          SessionListItem(
            session: s,
            showFolderIndicator: true,
            onTap: () {
              final status = s['status'] as String? ?? 'completed';
              if (status == 'processing') {
                showInfoSnackBar(context, '아직 카드를 생성하고 있습니다. 잠시만 기다려주세요.');
              } else if (status == 'failed') {
                showErrorSnackBar(context, '카드 생성에 실패한 세션입니다.');
              } else {
                _openSession(s['id'] as String);
              }
            },
            onRemove: () => _confirmDeleteSession(
              s['id'] as String,
              (s['filename'] as String).replaceAll('.pdf', ''),
            ),
          ),
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildDueCardsBanner(ColorScheme cs) {
    return InkWell(
      onTap: _startSrsStudy,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary.withValues(alpha: 0.1),
              cs.tertiary.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.replay_rounded, color: cs.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘 복습할 카드 $_dueCards장',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _streakDays > 0
                        ? '$_streakDays일 연속 학습 중'
                        : _reviewsToday > 0
                            ? '오늘 $_reviewsToday장 복습 완료'
                            : '탭하여 복습 시작',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
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

  void _showGuide(ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('이용 가이드',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 20),
              _guideStep(cs, Icons.upload_file_rounded, '1. PDF 업로드',
                  '시험 범위 강의자료, 교재, 필기노트 등의\nPDF 파일을 업로드하세요.'),
              _guideStep(cs, Icons.auto_awesome_rounded, '2. 카드 유형 선택',
                  '정의형, 빈칸형, 비교형 중 원하는\n카드 유형을 선택하세요.'),
              _guideStep(cs, Icons.style_rounded, '3. AI 카드 생성',
                  'AI가 PDF를 분석하여 근거 포함\n암기카드를 자동으로 만들어줍니다.'),
              _guideStep(cs, Icons.checklist_rounded, '4. 카드 검수',
                  '생성된 카드를 확인하고 채택하거나\n삭제·수정할 수 있습니다.'),
              _guideStep(cs, Icons.school_rounded, '5. 학습하기',
                  '플래시카드로 시험 대비 학습을\n시작하세요!'),
              _guideStep(cs, Icons.folder_rounded, '6. 보관함',
                  '카드를 과목별로 정리하고 관리할 수\n있습니다. (로그인 필요)'),
              const Divider(height: 32),
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.chat_bubble_outline_rounded,
                      size: 18, color: cs.primary),
                ),
                title: const Text('피드백 보내기',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text('버그 제보, 개선 의견을 보내주세요',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                trailing: Icon(Icons.open_in_new_rounded,
                    size: 18, color: cs.onSurfaceVariant),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(
                      Uri.parse('https://open.kakao.com/o/TODO_PLACEHOLDER'),
                      mode: LaunchMode.externalApplication);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideStep(
      ColorScheme cs, IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    ColorScheme cs, {
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      color: cs.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(height: 12),
              Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
              const SizedBox(height: 4),
              Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.3,
                )),
            ],
          ),
        ),
      ),
    );
  }
}
