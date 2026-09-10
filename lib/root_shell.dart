import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'app_theme.dart';
import 'api_service.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'advice_screen.dart';

/// App shell: fetches the shared location/weather/safety snapshot once
/// (used by Home and Advice), and hosts the three tabs behind a single
/// persistent bottom tab bar — mirroring the reference design's app
/// shell rather than pushing/popping full-screen routes.
class RootShell extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const RootShell({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tabIndex = 0;

  Position? _position;
  WeatherData? _weather;
  SafetyAssessment? _safety;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  Future<void> _loadEverything() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are turned off. Please enable GPS.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission was denied.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
            'Location permission is permanently denied. Enable it in system Settings.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final weather = await ApiService.fetchWeather(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _position = position;
        _weather = weather;
        _safety = SafetyAdvisor.assess(weather, DateTime.now());
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _goToTab(int index) => setState(() => _tabIndex = index);

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: [
          HomeScreen(
            isDarkMode: widget.isDarkMode,
            onToggleTheme: widget.onToggleTheme,
            position: _position,
            weather: _weather,
            safety: _safety,
            isLoading: _isLoading,
            errorMessage: _errorMessage,
            onRefresh: _loadEverything,
            onOpenMap: () => _goToTab(1),
            onOpenAdvice: () => _goToTab(2),
          ),
          const MapScreen(),
          AdviceScreen(
            position: _position,
            weather: _weather,
            safety: _safety,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _TabButton(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                  isActive: _tabIndex == 0,
                  ink: ink,
                  onTap: () => _goToTab(0),
                ),
                _TabButton(
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore,
                  label: 'Live',
                  isActive: _tabIndex == 1,
                  ink: ink,
                  onTap: () => _goToTab(1),
                ),
                _TabButton(
                  icon: Icons.health_and_safety_outlined,
                  activeIcon: Icons.health_and_safety,
                  label: 'Decide',
                  isActive: _tabIndex == 2,
                  ink: ink,
                  onTap: () => _goToTab(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final Color ink;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.ink,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.green : ink.withOpacity(0.45);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isActive ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
