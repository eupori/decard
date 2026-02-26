import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'explore_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'login_screen.dart';

/// HomeScreen이 생성 오버레이를 표시 중인지 알려주는 글로벌 노티파이어
final ValueNotifier<bool> hideBottomNav = ValueNotifier(false);

/// 현재 탭 인덱스 (push된 화면에서 탭 전환용)
final ValueNotifier<int> mainTabIndex = ValueNotifier(0);

/// push된 화면(ReviewScreen, FolderDetailScreen 등)에서 쓸 바텀바
Widget buildAppBottomNav(BuildContext context, {int selectedIndex = 0}) {
  final cs = Theme.of(context).colorScheme;
  return NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: (i) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      mainTabIndex.value = i;
    },
    height: 64,
    backgroundColor: cs.surface,
    indicatorColor: cs.primaryContainer,
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: '홈',
      ),
      NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: Icon(Icons.explore_rounded),
        label: '탐색',
      ),
      NavigationDestination(
        icon: Icon(Icons.folder_outlined),
        selectedIcon: Icon(Icons.folder_rounded),
        label: '보관함',
      ),
    ],
  );
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isLoggedIn = false;
  DateTime? _lastBackPressed;

  @override
  void initState() {
    super.initState();
    mainTabIndex.addListener(_onTabChanged);
    _checkAuth();
  }

  @override
  void dispose() {
    mainTabIndex.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    _checkAuth();
    setState(() {});
  }

  Future<void> _checkAuth() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (mounted && _isLoggedIn != loggedIn) {
      setState(() => _isLoggedIn = loggedIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressed != null &&
            now.difference(_lastBackPressed!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
        } else {
          _lastBackPressed = now;
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(
                content: Text('한 번 더 누르면 앱이 종료됩니다'),
                duration: Duration(seconds: 2),
              ),
            );
        }
      },
      child: ValueListenableBuilder<bool>(
      valueListenable: hideBottomNav,
      builder: (context, hidden, _) {
        return Scaffold(
          body: IndexedStack(
            index: mainTabIndex.value,
            children: [
              const HomeScreen(),
              const ExploreScreen(),
              _isLoggedIn
                  ? const LibraryScreen()
                  : _buildLoginRequired(cs),
            ],
          ),
          bottomNavigationBar: hidden
              ? null
              : NavigationBar(
                  selectedIndex: mainTabIndex.value,
                  onDestinationSelected: (i) {
                    mainTabIndex.value = i;
                  },
                  height: 64,
                  backgroundColor: cs.surface,
                  indicatorColor: cs.primaryContainer,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: '홈',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore_rounded),
                      label: '탐색',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder_rounded),
                      label: '보관함',
                    ),
                  ],
                ),
        );
      },
    ),
    );
  }

  Widget _buildLoginRequired(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_rounded,
                size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              '보관함은 로그인 후 이용할 수 있어요',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '카드를 과목별로 정리하고 관리해보세요',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
                _checkAuth();
              },
              icon: const Icon(Icons.login_rounded),
              label: const Text('로그인하기'),
              style: FilledButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
