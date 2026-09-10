import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'app_theme.dart';
import 'api_service.dart';

/// Landing tab. Pure presentation — all data (position/weather/safety) is
/// fetched once by RootShell and handed down here, so switching tabs
/// never triggers a duplicate location or weather fetch.
class HomeScreen extends StatelessWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final Position? position;
  final WeatherData? weather;
  final SafetyAssessment? safety;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRefresh;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenAdvice;

  const HomeScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.position,
    required this.weather,
    required this.safety,
    required this.isLoading,
    required this.errorMessage,
    required this.onRefresh,
    required this.onOpenMap,
    required this.onOpenAdvice,
  });

  Color _levelColor(SafetyLevel level) => switch (level) {
        SafetyLevel.safe => AppColors.green,
        SafetyLevel.caution => AppColors.amber,
        SafetyLevel.headBack => AppColors.red,
      };

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final muted = isDarkMode ? AppColors.mutedDark : AppColors.muted;

    return SafeArea(
      child: isLoading
          ? _buildLoading(ink)
          : errorMessage != null
              ? _buildError(context, ink)
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(ink, muted),
                      const SizedBox(height: 19),
                      _buildReadinessHero(),
                      const SizedBox(height: 13),
                      _buildPrimaryButton(onOpenMap, 'Open live map', Icons.arrow_forward),
                      _buildSectionHeader('Safety check', safety != null ? 'READY' : 'PENDING', muted, ink),
                      _buildInfoCard(
                        context,
                        icon: Icons.health_and_safety_outlined,
                        title: safety?.headline ?? 'No data yet',
                        body: safety != null
                            ? safety!.reasons.first
                            : 'Refresh once your location has loaded to see hiking advice.',
                        actionLabel: 'DETAILS',
                        onAction: onOpenAdvice,
                        muted: muted,
                        ink: ink,
                      ),
                      _buildSectionHeader('Conditions', 'REFRESHABLE', muted, ink),
                      _buildInfoCard(
                        context,
                        icon: Icons.refresh,
                        title: 'Refresh weather & location',
                        body: 'Pulls the latest temperature, wind, and forecast for where you are now.',
                        actionLabel: 'REFRESH',
                        onAction: onRefresh,
                        muted: muted,
                        ink: ink,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Decision support only. Always carry offline maps and follow official '
                        'weather and emergency guidance.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted.withOpacity(0.85), fontSize: 10, height: 1.5),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildLoading(Color ink) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.forest),
          const SizedBox(height: 16),
          Text(
            'Finding your location and checking conditions…',
            textAlign: TextAlign.center,
            style: TextStyle(color: ink),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, Color ink) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.red),
            const SizedBox(height: 12),
            Text(errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: ink, fontSize: 15)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRefresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.forest,
                foregroundColor: AppColors.white,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color ink, Color muted) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HIKESAFE COMPANION', style: AppText.kicker(AppColors.green)),
              const SizedBox(height: 6),
              Text('Ready to explore?', style: AppText.title(ink)),
            ],
          ),
        ),
        GestureDetector(
          onTap: onToggleTheme,
          child: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
            child: Icon(
              isDarkMode ? Icons.light_mode : Icons.dark_mode,
              color: AppColors.forest,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadinessHero() {
    final level = safety?.level;
    final windowColor = level == null
        ? AppColors.green
        : level == SafetyLevel.headBack
            ? AppColors.red
            : level == SafetyLevel.caution
                ? AppColors.amber
                : AppColors.green;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      position != null
                          ? '${position!.latitude.toStringAsFixed(3)}, ${position!.longitude.toStringAsFixed(3)}'
                          : 'Your current area',
                      style: const TextStyle(color: Color(0xFFBFD1C6), fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      weather != null ? '${weather!.temperatureC.toStringAsFixed(0)}°C' : '—',
                      style: const TextStyle(
                          color: AppColors.white, fontSize: 42, fontWeight: FontWeight.w900, height: 1),
                    ),
                  ],
                ),
              ),
              Text(
                weather?.description ?? 'Unknown',
                style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              border: Border.all(color: Colors.white.withOpacity(0.13)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: windowColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        safety?.headline ?? 'Waiting for conditions',
                        style: const TextStyle(color: AppColors.white, fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        weather?.sunset != null
                            ? 'Sunset ${weather!.sunset!.hour.toString().padLeft(2, '0')}:${weather!.sunset!.minute.toString().padLeft(2, '0')} · Rain ${weather!.precipitationProbability.toStringAsFixed(0)}%'
                            : 'Refresh to load current conditions',
                        style: const TextStyle(color: Color(0xFFC6D7CD), fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(VoidCallback onTap, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: AppColors.forest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 17),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                Icon(icon, color: AppColors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String meta, Color muted, Color ink) {
    return Padding(
      padding: const EdgeInsets.only(top: 21, bottom: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: ink)),
          Text(meta, style: AppText.sectionMeta(AppColors.green)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required String actionLabel,
    required VoidCallback onAction,
    required Color muted,
    required Color ink,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: AppColors.forest),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(fontSize: 10, height: 1.35, color: muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAction,
            child: Text(actionLabel, style: AppText.sectionMeta(AppColors.green)),
          ),
        ],
      ),
    );
  }
}
