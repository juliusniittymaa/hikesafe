import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'app_theme.dart';
import 'api_service.dart';

/// "Decide" tab: full explanation of whether the hiker should keep going,
/// be careful, or head back, plus a snapshot of the conditions behind
/// that call. Seeds from RootShell's shared snapshot but can refresh
/// independently using the last known position.
class AdviceScreen extends StatefulWidget {
  final Position? position;
  final WeatherData? weather;
  final SafetyAssessment? safety;

  const AdviceScreen({
    super.key,
    required this.position,
    required this.weather,
    required this.safety,
  });

  @override
  State<AdviceScreen> createState() => _AdviceScreenState();
}

class _AdviceScreenState extends State<AdviceScreen> {
  WeatherData? _weather;
  SafetyAssessment? _safety;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _weather = widget.weather;
    _safety = widget.safety;
  }

  @override
  void didUpdateWidget(covariant AdviceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pick up a fresher snapshot if RootShell reloaded while we were
    // showing stale/no data (e.g. first load finished after this tab
    // was already built).
    if (_weather == null && widget.weather != null) {
      _weather = widget.weather;
      _safety = widget.safety;
    }
  }

  Future<void> _refresh() async {
    final position = widget.position;
    if (position == null) {
      setState(() => _errorMessage = 'No location available to refresh with.');
      return;
    }

    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
    });

    try {
      final weather = await ApiService.fetchWeather(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _weather = weather;
        _safety = SafetyAdvisor.assess(weather, DateTime.now());
        _isRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
        _errorMessage = 'Could not refresh conditions — showing the last known data.';
      });
    }
  }

  Color _levelColor(SafetyLevel level) => switch (level) {
        SafetyLevel.safe => AppColors.green,
        SafetyLevel.caution => AppColors.amber,
        SafetyLevel.headBack => AppColors.red,
      };

  String _levelLabel(SafetyLevel level) => switch (level) {
        SafetyLevel.safe => 'On track',
        SafetyLevel.caution => 'Caution',
        SafetyLevel.headBack => 'High risk',
      };

  @override
  Widget build(BuildContext context) {
    final safety = _safety;
    final weather = _weather;
    final ink = Theme.of(context).colorScheme.onSurface;
    final muted = ink.withOpacity(0.6);

    return SafeArea(
      child: safety == null || weather == null
          ? _buildNoDataState(ink)
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('DECISION CHECK', style: AppText.kicker(AppColors.green)),
                            const SizedBox(height: 6),
                            Text('What are my options?', style: AppText.title(ink, size: 26)),
                          ],
                        ),
                      ),
                      _buildBadge(safety),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_errorMessage != null) ...[
                    _buildInlineError(_errorMessage!),
                    const SizedBox(height: 12),
                  ],
                  _buildMetricsRow(weather, safety),
                  const SizedBox(height: 14),
                  _buildExplainCard(safety),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: _isRefreshing ? null : _refresh,
                      icon: _isRefreshing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 18, color: AppColors.green),
                      label: Text('Refresh conditions',
                          style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This is an automated estimate based on forecast data and daylight remaining. '
                    'Always use your own judgement, check official trail conditions, and turn back '
                    'earlier than you think you need to.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, height: 1.5, color: muted),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildNoDataState(Color ink) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: ink.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              'No conditions data yet. Go to the Home tab and let it load, then come back.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineError(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildBadge(SafetyAssessment safety) {
    final color = _levelColor(safety.level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(_levelLabel(safety.level), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(width: 5),
          Text('${safety.score}', style: const TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildMetricsRow(WeatherData weather, SafetyAssessment safety) {
    final minutesToSunset = weather.sunset?.difference(DateTime.now()).inMinutes;
    final windAttention = weather.windSpeedKmh >= 35;
    final rainAttention = weather.precipitationProbability >= 40;
    final sunsetAttention = minutesToSunset != null && minutesToSunset <= 150;

    return Row(
      children: [
        Expanded(
          child: _metricCard('TEMP', '${weather.temperatureC.toStringAsFixed(0)}°C', false),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard('WIND', '${weather.windSpeedKmh.toStringAsFixed(0)} km/h', windAttention),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard('RAIN', '${weather.precipitationProbability.toStringAsFixed(0)}%', rainAttention),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            'SUNSET',
            weather.sunset != null
                ? '${weather.sunset!.hour.toString().padLeft(2, '0')}:${weather.sunset!.minute.toString().padLeft(2, '0')}'
                : '—',
            sunsetAttention,
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, bool attention) {
    return Builder(builder: (context) {
      final outline = Theme.of(context).colorScheme.outline;
      final ink = Theme.of(context).colorScheme.onSurface;
      return Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: attention ? AppColors.amberBg : Theme.of(context).colorScheme.surface,
          border: Border.all(color: attention ? const Color(0xFFECC890) : outline),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: ink.withOpacity(0.6))),
            const SizedBox(height: 7),
            Text(
              value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: attention ? AppColors.amber : ink),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildExplainCard(SafetyAssessment safety) {
    final title = switch (safety.level) {
      SafetyLevel.headBack => 'Your safety margin is shrinking.',
      SafetyLevel.caution => 'Reassess before the next section.',
      SafetyLevel.safe => 'Conditions look good right now.',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        border: Border.all(color: const Color(0xFFECC890)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink)),
          const SizedBox(height: 9),
          for (final reason in safety.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: const BoxDecoration(color: AppColors.amber, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(reason, style: const TextStyle(fontSize: 12, color: Color(0xFF68563F), height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
