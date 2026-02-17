import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const DecardApp());
}

class DecardApp extends StatelessWidget {
  const DecardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '데카드',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
