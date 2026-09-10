import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'app_theme.dart';
import 'api_service.dart';

/// Live map tab: hiker's current position, nearby hiking trails
/// (highlighted and color-coded by significance), a compact weather
/// readout, and the SOS emergency-info sheet. Fully self-contained — owns
/// its own live location stream independent of the Home/Advice snapshot.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;

  Position? _currentPosition;
  WeatherData? _weather;
  List<Trail> _trails = [];
  double? _trailSearchRadiusKm;
  bool _trailsFetchedOnce = false;

  bool _isLoadingLocation = true;
  bool _isLoadingTrails = false;

  String? _locationError;
  String? _trailError;

  bool _hasCenteredMap = false;

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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });

      _loadWeather(position.latitude, position.longitude);
      _loadTrails(position.latitude, position.longitude);
      _centerMapIfNeeded();

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
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
      _mapController.move(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 14);
    }
  }

  Future<void> _loadWeather(double lat, double lon) async {
    try {
      final weather = await ApiService.fetchWeather(lat, lon);
      if (!mounted) return;
      setState(() => _weather = weather);
    } catch (_) {
      // Weather is shown as a secondary pill here; Home/Advice already
      // surface a full error state, so we just skip updating silently.
    }
  }

  Future<void> _loadTrails(double lat, double lon) async {
    setState(() {
      _isLoadingTrails = true;
      _trailError = null;
    });
    try {
      final result = await ApiService.fetchNearbyTrails(lat, lon);
      if (!mounted) return;
      setState(() {
        _trails = result.trails;
        _trailSearchRadiusKm = result.radiusUsedKm;
        _isLoadingTrails = false;
        _trailsFetchedOnce = true;
      });
    } catch (e) {
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

  Color _colorForTrail(Trail trail) {
    if (!trail.isNamedRoute) return AppColors.blue.withOpacity(0.55);
    switch (trail.network) {
      case 'iwn':
        return const Color(0xFF7A5CC7);
      case 'nwn':
        return AppColors.red;
      case 'rwn':
        return AppColors.amber;
      case 'lwn':
        return const Color(0xFFCC8A2E);
      default:
        return AppColors.forest;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildMapWrap(context),
        if (_isLoadingLocation) _buildFullScreenLoader('Finding your location…'),
      ],
    );
  }

  Widget _buildMapWrap(BuildContext context) {
    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(46.8, 8.2);

    return Column(
      children: [
        SizedBox(
          height: 340,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: center, initialZoom: 14, minZoom: 3, maxZoom: 18),
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
                          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                          width: 44,
                          height: 44,
                          child: const _PulsingLocationDot(),
                        ),
                      ],
                    ),
                ],
              ),
              Positioned(
                left: 14,
                right: 14,
                top: 15,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _pill(
                            _isLoadingTrails ? '● SEARCHING' : '● LIVE CONDITIONS',
                            AppColors.green,
                            Colors.white.withOpacity(0.91),
                          ),
                          const SizedBox(height: 6),
                          _pill('Nearby trails', AppColors.ink, Colors.white.withOpacity(0.88), big: true),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _showSosSheet,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(15)),
                        child: const Center(
                          child: Text('SOS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.amberBg, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    _weather != null
                        ? '${_weather!.description} · ${_weather!.temperatureC.toStringAsFixed(0)}°'
                        : 'Loading…',
                    style: const TextStyle(fontSize: 10, color: AppColors.amberText, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                bottom: 14,
                child: Row(
                  children: [
                    _circleIconButton(Icons.my_location, () {
                      if (_currentPosition != null) {
                        _mapController.move(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 15);
                      }
                    }),
                    const SizedBox(width: 8),
                    _circleIconButton(Icons.refresh, _refreshAll),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(27)),
            ),
            transform: Matrix4.translationValues(0, -18, 0),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    margin: const EdgeInsets.only(bottom: 14),
                    alignment: Alignment.center,
                  ),
                  if (_trails.any((t) => t.isNamedRoute)) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Nearby named trails',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
                        Text('${_trails.where((t) => t.isNamedRoute).length} FOUND',
                            style: AppText.sectionMeta(AppColors.green)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildTrailChipList(context),
                    const SizedBox(height: 8),
                  ],
                  if (_locationError != null) _buildErrorBanner(context, _locationError!),
                  if (_trailError != null) _buildErrorBanner(context, _trailError!),
                  if (_trailError == null && _trailsFetchedOnce && !_isLoadingTrails && _trails.isEmpty)
                    _buildInfoBanner(
                      context,
                      'No trails found even within ${_trailSearchRadiusKm?.toStringAsFixed(0) ?? '150'} km. '
                      'You may be somewhere without mapped hiking trails nearby.',
                    ),
                  if (_trailError == null &&
                      _trails.isNotEmpty &&
                      _trailSearchRadiusKm != null &&
                      _trailSearchRadiusKm! > 5)
                    _buildInfoBanner(context,
                        'Nearest trails are about ${_trailSearchRadiusKm!.toStringAsFixed(0)} km away — none found closer.'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, Color textColor, Color bg, {bool big = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: big ? 5 : 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: big ? 18 : 9,
          color: textColor,
          fontWeight: FontWeight.w900,
          letterSpacing: big ? 0 : 1,
        ),
      ),
    );
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: AppColors.forest),
      ),
    );
  }

  Widget _buildTrailChipList(BuildContext context) {
    final namedTrails = _trails.where((t) => t.isNamedRoute).toList();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: namedTrails.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final trail = namedTrails[index];
          return GestureDetector(
            onTap: () => _mapController.fitCamera(
              CameraFit.bounds(bounds: LatLngBounds.fromPoints(trail.points), padding: const EdgeInsets.all(48)),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: _colorForTrail(trail), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(trail.name ?? trail.networkLabel,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 12))),
          TextButton(
            onPressed: _initLocationFlow,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(BuildContext context, String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
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
            Text(message, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _PulsingLocationDot extends StatefulWidget {
  const _PulsingLocationDot();

  @override
  State<_PulsingLocationDot> createState() => _PulsingLocationDotState();
}

class _PulsingLocationDotState extends State<_PulsingLocationDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
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
                decoration: BoxDecoration(color: AppColors.forest.withOpacity(0.25), shape: BoxShape.circle),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.forest,
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

class _SosSheet extends StatelessWidget {
  final Position? position;
  const _SosSheet({required this.position});

  @override
  Widget build(BuildContext context) {
    final pos = position;
    final coordsText =
        pos == null ? 'Location unavailable' : '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';

    return Container(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
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
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.sos, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text('Emergency Info',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Your coordinates (share verbally or by text):',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
          const SizedBox(height: 6),
          SelectableText(
            coordsText,
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 20),
          if (pos != null) ...[
            Text('Elevation (from GPS):',
                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
            const SizedBox(height: 4),
            Text('${pos.altitude.toStringAsFixed(0)} m',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 20),
          ],
          ElevatedButton.icon(
            onPressed: pos == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: coordsText));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coordinates copied')));
                  },
            icon: const Icon(Icons.copy),
            label: const Text('Copy coordinates'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: call local emergency services and read out the coordinates above.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }
}
