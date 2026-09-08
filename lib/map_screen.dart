import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'api_service.dart';

class MapScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const MapScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;

  Position? _currentPosition;
  WeatherData? _weather;
  SafetyAssessment? _safety;
  List<Trail> _trails = [];
  bool _trailsFetchedOnce = false;

  bool _isLoadingLocation = true;
  bool _isLoadingWeather = false;
  bool _isLoadingTrails = false;

  String? _locationError;
  String? _weatherError;
  String? _trailError;

  bool _hasCenteredMap = false;
  bool _showSafetyDetails = false;

  @override
  void initState() {
    super.initState();
    _initLocationFlow();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _initLocationFlow() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });

      _loadWeather(position.latitude, position.longitude);
      _loadTrails(position.latitude, position.longitude);
      _centerMapIfNeeded();

      // Keep listening so the marker (and weather) stay current as the
      // hiker moves along the trail.
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15, // meters — ignore tiny GPS jitter
        ),
      ).listen((position) {
        if (!mounted) return;
        setState(() => _currentPosition = position);
        _loadWeather(position.latitude, position.longitude);
      }, onError: (e) {
        if (!mounted) return;
        setState(() => _locationError = 'Lost GPS signal: $e');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingLocation = false;
        _locationError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _centerMapIfNeeded() {
    if (!_hasCenteredMap && _currentPosition != null) {
      _hasCenteredMap = true;
      _mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        14,
      );
    }
  }

  Future<void> _loadWeather(double lat, double lon) async {
    setState(() {
      _isLoadingWeather = true;
      _weatherError = null;
    });
    try {
      final weather = await ApiService.fetchWeather(lat, lon);
      if (!mounted) return;
      setState(() {
        _weather = weather;
        _safety = SafetyAdvisor.assess(weather, DateTime.now());
        _isLoadingWeather = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingWeather = false;
        _weatherError = 'Weather unavailable';
      });
    }
  }

  Future<void> _loadTrails(double lat, double lon) async {
    setState(() {
      _isLoadingTrails = true;
      _trailError = null;
    });
    try {
      final trails = await ApiService.fetchNearbyTrails(lat, lon);
      if (!mounted) return;
      setState(() {
        _trails = trails;
        _isLoadingTrails = false;
        _trailsFetchedOnce = true;
      });
    } catch (e) {
      // Printed to the debug console so the exact cause (timeout, DNS,
      // bad response, etc.) is visible while testing.
      debugPrint('Trail fetch failed: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingTrails = false;
        _trailError = 'Trail data unavailable — tap Retry';
      });
    }
  }

  Future<void> _refreshAll() async {
    if (_currentPosition != null) {
      _loadWeather(_currentPosition!.latitude, _currentPosition!.longitude);
      _loadTrails(_currentPosition!.latitude, _currentPosition!.longitude);
    } else {
      _initLocationFlow();
    }
  }

  void _showSosSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SosSheet(position: _currentPosition),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                if (_safety != null) _buildSafetyCard(),
                if (_weather != null || _isLoadingWeather || _weatherError != null)
                  _buildWeatherCard(),
                if (_trails.any((t) => t.isNamedRoute)) _buildTrailChipList(),
                if (_locationError != null) _buildErrorBanner(_locationError!),
                if (_trailError != null) _buildErrorBanner(_trailError!),
                if (_trailError == null &&
                    _trailsFetchedOnce &&
                    !_isLoadingTrails &&
                    _trails.isEmpty)
                  _buildInfoBanner(
                      'No trails found within 5 km of here. Try refreshing once you\'re closer to a trailhead.'),
              ],
            ),
          ),
          if (_isLoadingLocation) _buildFullScreenLoader('Finding your location…'),
        ],
      ),
      floatingActionButton: _buildFabColumn(),
    );
  }

  /// Color-codes a trail by how significant its OSM "network" tag says it
  /// is (international > national > regional > local), with named-but-
  /// untagged routes in a solid accent color and raw fallback fragments in
  /// a muted, thin gray so they read as "minor path" rather than "trail".
  Color _colorForTrail(Trail trail) {
    if (!trail.isNamedRoute) {
      return Colors.blueGrey.withOpacity(0.55);
    }
    switch (trail.network) {
      case 'iwn':
        return Colors.purple.shade400;
      case 'nwn':
        return Colors.red.shade600;
      case 'rwn':
        return Colors.orange.shade700;
      case 'lwn':
        return Colors.amber.shade700;
      default:
        return Colors.deepOrange.shade400;
    }
  }

  /// A horizontally scrollable row of chips for every named trail found
  /// nearby. Tapping one zooms/pans the map to fit that trail's full
  /// extent, so "highlighted well" also means "easy to actually find".
  Widget _buildTrailChipList() {
    final namedTrails = _trails.where((t) => t.isNamedRoute).toList();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: namedTrails.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final trail = namedTrails[index];
          final color = _colorForTrail(trail);
          return ActionChip(
            avatar: CircleAvatar(backgroundColor: color, radius: 6),
            label: Text(
              trail.name ?? trail.networkLabel,
              style: const TextStyle(fontSize: 13),
            ),
            backgroundColor: Theme.of(context).colorScheme.surface,
            onPressed: () {
              _mapController.fitCamera(
                CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(trail.points),
                  padding: const EdgeInsets.all(48),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMap() {
    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(46.8, 8.2); // fallback center until GPS resolves

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 14,
        minZoom: 3,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.hikesafe',
          maxNativeZoom: 19,
        ),
        PolylineLayer(
          polylines: [
            for (final trail in _trails)
              Polyline(
                points: trail.points,
                strokeWidth: trail.isNamedRoute ? 5 : 3,
                color: _colorForTrail(trail),
                borderStrokeWidth: trail.isNamedRoute ? 1.5 : 0.5,
                borderColor: Colors.white,
              ),
          ],
        ),
        if (_currentPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                    _currentPosition!.latitude, _currentPosition!.longitude),
                width: 44,
                height: 44,
                child: const _PulsingLocationDot(),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RoundIconButton(
            icon: Icons.refresh,
            onTap: _refreshAll,
            tooltip: 'Refresh weather & trails',
          ),
          Row(
            children: [
              if (_isLoadingTrails)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              _RoundIconButton(
                icon: widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                onTap: widget.onToggleTheme,
                tooltip: 'Toggle theme',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyCard() {
    final safety = _safety!;
    final Color accentColor = switch (safety.level) {
      SafetyLevel.safe => Colors.green.shade600,
      SafetyLevel.caution => Colors.orange.shade700,
      SafetyLevel.headBack => Colors.red.shade700,
    };
    final IconData icon = switch (safety.level) {
      SafetyLevel.safe => Icons.check_circle,
      SafetyLevel.caution => Icons.warning_amber_rounded,
      SafetyLevel.headBack => Icons.directions_walk,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: GestureDetector(
        onTap: () => setState(() => _showSafetyDetails = !_showSafetyDetails),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accentColor, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: accentColor, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      safety.headline,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ),
                  Icon(
                    _showSafetyDetails
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: accentColor,
                  ),
                ],
              ),
              if (_showSafetyDetails) ...[
                const SizedBox(height: 8),
                for (final reason in safety.reasons)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '•  $reason',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Estimate only — always use your own judgement and check local conditions.',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBanner(String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _isLoadingWeather && _weather == null
            ? const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading weather…', style: TextStyle(fontSize: 16)),
                ],
              )
            : _weatherError != null && _weather == null
                ? Row(
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.redAccent),
                      const SizedBox(width: 10),
                      Text(_weatherError!, style: const TextStyle(fontSize: 16)),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_weather!.temperatureC.toStringAsFixed(0)}°C / '
                            '${_weather!.temperatureF.toStringAsFixed(0)}°F',
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _weather!.description,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _WeatherStat(
                            icon: Icons.air,
                            label:
                                '${_weather!.windSpeedKmh.toStringAsFixed(0)} km/h',
                          ),
                          const SizedBox(height: 6),
                          _WeatherStat(
                            icon: Icons.water_drop,
                            label:
                                '${_weather!.precipitationProbability.toStringAsFixed(0)}% rain',
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          TextButton(
            onPressed: _initLocationFlow,
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildFullScreenLoader(String message) {
    return Container(
      color: Colors.black.withOpacity(0.55),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFabColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'center',
          onPressed: () {
            if (_currentPosition != null) {
              _mapController.move(
                LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                15,
              );
            }
          },
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: const Icon(Icons.my_location),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'sos',
          onPressed: _showSosSheet,
          backgroundColor: Colors.red.shade700,
          icon: const Icon(Icons.sos, color: Colors.white),
          label: const Text(
            'SOS',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// Small stat row used inside the weather card (wind / rain chance).
class _WeatherStat extends StatelessWidget {
  final IconData icon;
  final String label;
  const _WeatherStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// A round icon button used in the top bar.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 4,
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

/// A simple animated dot marking the hiker's live GPS position.
class _PulsingLocationDot extends StatefulWidget {
  const _PulsingLocationDot();

  @override
  State<_PulsingLocationDot> createState() => _PulsingLocationDotState();
}

class _PulsingLocationDotState extends State<_PulsingLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (0.5 * (1 - (_controller.value - 0.5).abs() * 2));
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: scale,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Bottom sheet shown when the SOS button is tapped: large, copyable
/// coordinates plus GPS elevation, for reading out loud or texting to
/// rescuers/family and for route planning.
class _SosSheet extends StatelessWidget {
  final Position? position;
  const _SosSheet({required this.position});

  @override
  Widget build(BuildContext context) {
    final pos = position;
    final coordsText = pos == null
        ? 'Location unavailable'
        : '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sos, color: Colors.red, size: 28),
              const SizedBox(width: 8),
              const Text(
                'Emergency Info',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Your coordinates (share verbally or by text):',
              style: TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          SelectableText(
            coordsText,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 20),
          if (pos != null) ...[
            const Text('Elevation (from GPS):', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              '${pos.altitude.toStringAsFixed(0)} m',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
          ],
          ElevatedButton.icon(
            onPressed: pos == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: coordsText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Coordinates copied')),
                    );
                  },
            icon: const Icon(Icons.copy),
            label: const Text('Copy coordinates'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: call local emergency services and read out the coordinates above.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}
