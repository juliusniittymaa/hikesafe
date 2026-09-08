import 'package:flutter/material.dart';
import 'map_screen.dart';

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
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: MapScreen(
        isDarkMode: _isDarkMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }

  // High-contrast light theme: readable in direct sunlight on the trail.
  ThemeData get _lightTheme => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F5F0),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 15),
        ),
      );

  // Dark theme: easier on the eyes at dawn/dusk and saves battery on OLED.
  ThemeData get _darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 15),
        ),
      );
}
