import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/theme.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'utils/web_auth_stub.dart'
    if (dart.library.html) 'utils/web_auth.dart' as web_auth;

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

/// OAuth 토큰이 URL에서 추출되었는지 여부 (HomeScreen에서 중복 처리 방지)
bool oauthHandledInMain = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Flutter 라우터가 hash를 소비하기 전에 OAuth 토큰 먼저 추출·저장
  if (kIsWeb) {
    final token = web_auth.extractTokenFromUrl();
    if (token != null) {
      await AuthService.setToken(token);
      await AuthService.linkDevice();
      web_auth.clearUrlFragment();
      oauthHandledInMain = true;
    }
  }

  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('theme_mode');
  if (savedTheme == 'light') {
    themeNotifier.value = ThemeMode.light;
  } else {
    themeNotifier.value = ThemeMode.dark;
  }
  themeNotifier.addListener(() {
    prefs.setString(
      'theme_mode',
      themeNotifier.value == ThemeMode.dark ? 'dark' : 'light',
    );
  });
  runApp(const DecardApp());
}

class DecardApp extends StatelessWidget {
  const DecardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: '데카드',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
