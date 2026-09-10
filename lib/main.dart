import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'root_shell.dart';

void main() {
  runApp(const HikeSafeApp());
}

class HikeSafeApp extends StatefulWidget {
  const HikeSafeApp({super.key});

  @override
  State<HikeSafeApp> createState() => _HikeSafeAppState();
}

class _HikeSafeAppState extends State<HikeSafeApp> {
  bool _isDarkMode = false;

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HikeSafe',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(isDark: false),
      darkTheme: buildAppTheme(isDark: true),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: RootShell(
        isDarkMode: _isDarkMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
