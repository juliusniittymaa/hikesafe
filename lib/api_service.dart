import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// =============================================================================
// WEATHER MODELS
// =============================================================================

/// One point in the near-future forecast, used both for display and for
/// the safety-assessment logic below.
class HourlyForecastPoint {
  final DateTime time;
  final double temperatureC;
  final double windSpeedKmh;
  final double precipitationProbability; // percent, 0-100
  final int weatherCode;

  HourlyForecastPoint({
    required this.time,
    required this.temperatureC,
    required this.windSpeedKmh,
    required this.precipitationProbability,
    required this.weatherCode,
  });
}

/// Immutable holder for a current-weather snapshot plus enough near-future
/// data (next few hours + today's sunset) to power the safety check.
class WeatherData {
  final double temperatureC;
  final double windSpeedKmh;
  final double precipitationProbability; // percent, 0-100
  final int weatherCode; // WMO weather code from Open-Meteo
  final DateTime? sunset;
  final List<HourlyForecastPoint> upcomingHours; // next ~5 hours, soonest first

  WeatherData({
    required this.temperatureC,
    required this.windSpeedKmh,
    required this.precipitationProbability,
    required this.weatherCode,
    required this.sunset,
    required this.upcomingHours,
  });

  double get temperatureF => (temperatureC * 9 / 5) + 32;

  String get description => describeWeatherCode(weatherCode);

  static String describeWeatherCode(int weatherCode) {
    if (weatherCode == 0) return 'Clear sky';
    if (weatherCode <= 3) return 'Partly cloudy';
    if (weatherCode == 45 || weatherCode == 48) return 'Fog';
    if (weatherCode >= 51 && weatherCode <= 57) return 'Drizzle';
    if (weatherCode >= 61 && weatherCode <= 67) return 'Rain';
    if (weatherCode >= 71 && weatherCode <= 77) return 'Snow';
    if (weatherCode >= 80 && weatherCode <= 82) return 'Rain showers';
    if (weatherCode >= 85 && weatherCode <= 86) return 'Snow showers';
    if (weatherCode >= 95) return 'Thunderstorm';
    return 'Unknown';
  }
}

/// Thrown whenever a network call fails, times out, or returns bad data.
/// The UI catches this and shows a friendly message instead of crashing.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

String _formatClockTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// =============================================================================
// SAFETY ADVISORY
// =============================================================================
// Simple rule-based check combining the forecast for the next few hours
// with how much daylight is left. This is a basic heuristic to prompt good
// judgement, NOT a substitute for checking an official forecast or trail
// conditions.

enum SafetyLevel { safe, caution, headBack }

class SafetyAssessment {
  final SafetyLevel level;
  final String headline;
  final List<String> reasons;

  SafetyAssessment({
    required this.level,
    required this.headline,
    required this.reasons,
  });

  /// Rough 0-100 indicator for the traffic-light badge, purely visual —
  /// not a precise risk score, just a way to echo the level as a number.
  int get score => switch (level) {
        SafetyLevel.safe => 92,
        SafetyLevel.caution => 58,
        SafetyLevel.headBack => 24,
      };
}

class SafetyAdvisor {
  /// Looks at current conditions, the next few forecast hours, and how
  /// close sunset is, then returns a traffic-light style assessment. Each
  /// hazard contributes at most ONE line (using its peak/worst value
  /// across the look-ahead window) so the list never repeats near-duplicate
  /// entries hour by hour.
  static SafetyAssessment assess(WeatherData weather, DateTime now) {
    final reasons = <String>[];
    SafetyLevel level = SafetyLevel.safe;

    void escalate(SafetyLevel newLevel) {
      if (newLevel.index > level.index) level = newLevel;
    }

    // --- Daylight remaining (always shown, with the actual clock time) ---
    if (weather.sunset != null) {
      final sunsetLabel = _formatClockTime(weather.sunset!);
      final minutesLeft = weather.sunset!.difference(now).inMinutes;

      if (minutesLeft <= 0) {
        escalate(SafetyLevel.headBack);
        reasons.add('Sunset was at $sunsetLabel — light is fading fast');
      } else if (minutesLeft <= 60) {
        escalate(SafetyLevel.headBack);
        reasons.add('Sunset at $sunsetLabel — only $minutesLeft min of daylight left');
      } else {
        final h = minutesLeft ~/ 60;
        final m = minutesLeft % 60;
        final leftLabel = h > 0 ? '${h}h ${m}m' : '${m}m';
        if (minutesLeft <= 150) escalate(SafetyLevel.caution);
        reasons.add('Sunset at $sunsetLabel — $leftLabel of daylight left');
      }
    }

    // --- Current wind (always shown) --------------------------------------
    final currentWindLabel = '${weather.windSpeedKmh.toStringAsFixed(0)} km/h';
    if (weather.windSpeedKmh >= 50) {
      escalate(SafetyLevel.headBack);
      reasons.add('Current wind is $currentWindLabel — strong enough to be hazardous');
    } else if (weather.windSpeedKmh >= 35) {
      escalate(SafetyLevel.caution);
      reasons.add('Current wind is $currentWindLabel');
    } else {
      reasons.add('Current wind: $currentWindLabel');
    }

    if (weather.weatherCode >= 95) {
      escalate(SafetyLevel.headBack);
      reasons.add('Thunderstorm conditions right now');
    }

    // --- Next few forecast hours, consolidated to one line per hazard -----
    final horizon = weather.upcomingHours.take(3).toList();
    if (horizon.isNotEmpty) {
      final peakRain = horizon.reduce(
          (a, b) => a.precipitationProbability >= b.precipitationProbability ? a : b);
      if (peakRain.precipitationProbability >= 70) {
        escalate(SafetyLevel.headBack);
        reasons.add(
            '${peakRain.precipitationProbability.toStringAsFixed(0)}% chance of rain around ${_formatClockTime(peakRain.time)}');
      } else if (peakRain.precipitationProbability >= 40) {
        escalate(SafetyLevel.caution);
        reasons.add(
            '${peakRain.precipitationProbability.toStringAsFixed(0)}% chance of rain around ${_formatClockTime(peakRain.time)}');
      }

      final peakWind = horizon.reduce((a, b) => a.windSpeedKmh >= b.windSpeedKmh ? a : b);
      if (peakWind.windSpeedKmh >= 50) {
        escalate(SafetyLevel.headBack);
        reasons.add(
            'Wind could reach ${peakWind.windSpeedKmh.toStringAsFixed(0)} km/h around ${_formatClockTime(peakWind.time)}');
      } else if (peakWind.windSpeedKmh >= 35) {
        escalate(SafetyLevel.caution);
        reasons.add(
            'Wind could reach ${peakWind.windSpeedKmh.toStringAsFixed(0)} km/h around ${_formatClockTime(peakWind.time)}');
      }

      HourlyForecastPoint? stormPoint;
      for (final p in horizon) {
        if (p.weatherCode >= 95) {
          stormPoint = p;
          break;
        }
      }
      if (stormPoint != null) {
        escalate(SafetyLevel.headBack);
        reasons.add('Thunderstorms possible around ${_formatClockTime(stormPoint.time)}');
      }
    }

    final headline = switch (level) {
      SafetyLevel.safe => 'Safe to continue',
      SafetyLevel.caution => 'Keep an eye on conditions',
      SafetyLevel.headBack => 'Consider heading back',
    };

    return SafetyAssessment(level: level, headline: headline, reasons: reasons);
  }
}

// =============================================================================
// TRAIL MODELS
// =============================================================================

/// A single trail to draw on the map. `isNamedRoute` distinguishes an
/// official, named hiking route (built from an OSM "route=hiking" relation
/// — usually the trails hikers actually look for) from a raw, unnamed
/// path/track segment used only as a fallback when no named routes exist
/// nearby.
class Trail {
  final String? name;
  final String? network; // iwn / nwn / rwn / lwn, or null if untagged
  final List<LatLng> points;
  final bool isNamedRoute;

  Trail({
    required this.points,
    required this.isNamedRoute,
    this.name,
    this.network,
  });

  String get networkLabel {
    switch (network) {
      case 'iwn':
        return 'International trail';
      case 'nwn':
        return 'National trail';
      case 'rwn':
        return 'Regional trail';
      case 'lwn':
        return 'Local trail';
      default:
        return isNamedRoute ? 'Hiking trail' : 'Unnamed path';
    }
  }
}

/// Result of a trail search: the trails found, plus how wide the search
/// had to expand to find them — useful for telling the user "we had to
/// look 60 km out" instead of silently returning distant results.
class TrailSearchResult {
  final List<Trail> trails;
  final double radiusUsedKm;
  TrailSearchResult({required this.trails, required this.radiusUsedKm});
}

class _BoundingBox {
  final double south, north, west, east;
  _BoundingBox({
    required this.south,
    required this.north,
    required this.west,
    required this.east,
  });
}

class _OverpassResult {
  final List<Trail> trails;
  final bool hadRealError; // true only if every mirror failed outright
  final List<String> errors;
  _OverpassResult({
    required this.trails,
    required this.hadRealError,
    required this.errors,
  });
}

// =============================================================================
// API SERVICE
// =============================================================================

class ApiService {
  static const _weatherTimeout = Duration(seconds: 12);
  static const _overpassTimeout = Duration(seconds: 15);

  static const _overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];

  // ---------------------------------------------------------------------
  // WEATHER — Open-Meteo (free, no API key, no account required)
  // ---------------------------------------------------------------------
  static Future<WeatherData> fetchWeather(double lat, double lon) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&current=temperature_2m,wind_speed_10m,weather_code'
      '&hourly=temperature_2m,wind_speed_10m,precipitation_probability,weather_code'
      '&daily=sunset'
      '&forecast_days=1'
      '&timezone=auto',
    );

    try {
      final response = await http.get(uri).timeout(_weatherTimeout);

      if (response.statusCode != 200) {
        throw ApiException('Weather service returned status ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;
      if (current == null) {
        throw ApiException('Weather response was missing current conditions');
      }

      final double temp = (current['temperature_2m'] as num).toDouble();
      final double wind = (current['wind_speed_10m'] as num).toDouble();
      final int code = (current['weather_code'] as num).toInt();
      final currentTime = DateTime.tryParse(current['time'] as String? ?? '');

      double precipProb = 0;
      final upcomingHours = <HourlyForecastPoint>[];
      final hourly = data['hourly'] as Map<String, dynamic>?;

      if (hourly != null && currentTime != null) {
        final times = (hourly['time'] as List).cast<String>();
        final temps = hourly['temperature_2m'] as List;
        final winds = hourly['wind_speed_10m'] as List;
        final probs = hourly['precipitation_probability'] as List;
        final codes = hourly['weather_code'] as List;

        int bestIndex = 0;
        Duration bestDiff = const Duration(days: 999);
        for (int i = 0; i < times.length; i++) {
          final t = DateTime.tryParse(times[i]);
          if (t == null) continue;
          final diff = t.difference(currentTime).abs();
          if (diff < bestDiff) {
            bestDiff = diff;
            bestIndex = i;
          }
        }

        if (bestIndex < probs.length) {
          precipProb = (probs[bestIndex] as num).toDouble();
        }

        for (int i = bestIndex; i < times.length && upcomingHours.length < 5; i++) {
          final t = DateTime.tryParse(times[i]);
          if (t == null) continue;
          upcomingHours.add(HourlyForecastPoint(
            time: t,
            temperatureC: (temps[i] as num).toDouble(),
            windSpeedKmh: (winds[i] as num).toDouble(),
            precipitationProbability: (probs[i] as num).toDouble(),
            weatherCode: (codes[i] as num).toInt(),
          ));
        }
      }

      DateTime? sunset;
      final daily = data['daily'] as Map<String, dynamic>?;
      if (daily != null) {
        final sunsetList = daily['sunset'] as List?;
        if (sunsetList != null && sunsetList.isNotEmpty) {
          sunset = DateTime.tryParse(sunsetList.first as String);
        }
      }

      return WeatherData(
        temperatureC: temp,
        windSpeedKmh: wind,
        precipitationProbability: precipProb,
        weatherCode: code,
        sunset: sunset,
        upcomingHours: upcomingHours,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Could not reach the weather service: $e');
    }
  }

  // ---------------------------------------------------------------------
  // TRAILS — Overpass API (queries raw OpenStreetMap data, no key needed)
  // ---------------------------------------------------------------------
  //
  // Real, popular hiking trails are modeled in OSM as "route=hiking"
  // RELATIONS — a named trail stitched together from many small way
  // segments, often tagged with a "network" level (international / national
  // / regional / local). Raw ways alone (highway=path/track) only return
  // disconnected, unnamed fragments, so we fetch named route relations
  // FIRST and only fall back to raw fragments if none exist nearby.
  //
  // Cities can be genuinely far from any real trailhead, so the search
  // radius escalates in stages instead of forcing everyone onto one fixed
  // distance.
  //
  // A bounding-box filter is used instead of Overpass's "around" filter,
  // since "around" is expensive to compute server-side and a common cause
  // of timeouts on the free public instances.
  static Future<TrailSearchResult> fetchNearbyTrails(
    double lat,
    double lon, {
    int maxUnnamedFallbackTrails = 10,
  }) async {
    const radiiMeters = [5000.0, 15000.0, 40000.0, 80000.0, 150000.0];

    for (final radiusMeters in radiiMeters) {
      final result = await _fetchTrailsAtRadius(
        lat,
        lon,
        radiusMeters,
        maxUnnamedFallbackTrails: maxUnnamedFallbackTrails,
      );

      if (result.trails.isNotEmpty) {
        return TrailSearchResult(
          trails: result.trails,
          radiusUsedKm: radiusMeters / 1000,
        );
      }

      if (result.hadRealError) {
        // A genuine network failure won't be fixed by searching wider —
        // surface it immediately instead of retrying at every radius.
        throw ApiException('All trail mirrors failed: ${result.errors.join(' | ')}');
      }
      // Otherwise this radius was a real, empty result — widen and retry.
    }

    return TrailSearchResult(trails: [], radiusUsedKm: radiiMeters.last / 1000);
  }

  static Future<_OverpassResult> _fetchTrailsAtRadius(
    double lat,
    double lon,
    double radiusMeters, {
    required int maxUnnamedFallbackTrails,
  }) async {
    final bbox = _boundingBox(lat, lon, radiusMeters);

    final namedRoutesQuery = '''
      [out:json][timeout:20];
      rel["route"="hiking"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
      out body;
      way(r);
      out geom;
    ''';

    final namedResult = await _runOverpassQuery(namedRoutesQuery, _parseNamedRoutes);
    if (namedResult.trails.isNotEmpty) {
      namedResult.trails.sort((a, b) => _distanceToClosestPoint(lat, lon, a.points)
          .compareTo(_distanceToClosestPoint(lat, lon, b.points)));
      return namedResult;
    }

    final fallbackQuery = '''
      [out:json][timeout:12];
      (
        way["highway"~"^(path|track)\$"]["surface"!~"^(paved|asphalt|concrete|paving_stones|sett)\$"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
      );
      out body;
      >;
      out skel qt;
    ''';

    final fallbackResult = await _runOverpassQuery(fallbackQuery, _parseRawWays);

    if (fallbackResult.trails.isNotEmpty) {
      fallbackResult.trails.sort((a, b) => _distanceToClosestPoint(lat, lon, a.points)
          .compareTo(_distanceToClosestPoint(lat, lon, b.points)));
      return _OverpassResult(
        trails: fallbackResult.trails.take(maxUnnamedFallbackTrails).toList(),
        hadRealError: false,
        errors: [],
      );
    }

    if (!namedResult.hadRealError && !fallbackResult.hadRealError) {
      return _OverpassResult(trails: [], hadRealError: false, errors: []);
    }

    return _OverpassResult(
      trails: [],
      hadRealError: true,
      errors: [...namedResult.errors, ...fallbackResult.errors],
    );
  }

  static _BoundingBox _boundingBox(double lat, double lon, double radiusMeters) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLon = 111320.0 * cos(lat * pi / 180).abs();
    final latDelta = radiusMeters / metersPerDegreeLat;
    final lonDelta = radiusMeters / (metersPerDegreeLon < 1 ? 1 : metersPerDegreeLon);

    return _BoundingBox(
      south: lat - latDelta,
      north: lat + latDelta,
      west: lon - lonDelta,
      east: lon + lonDelta,
    );
  }

  /// Runs an Overpass query across all mirrors, stopping at the first
  /// mirror that responds successfully (even with zero results, since an
  /// empty-but-successful response is meaningful and shouldn't trigger
  /// pointless retries against every mirror).
  static Future<_OverpassResult> _runOverpassQuery(
    String query,
    List<Trail> Function(Map<String, dynamic> data) parser,
  ) async {
    final errors = <String>[];

    for (final endpoint in _overpassEndpoints) {
      try {
        final response = await http
            .post(
              Uri.parse(endpoint),
              headers: {
                // Public Overpass mirrors throttle or reject requests from
                // generic/anonymous HTTP clients. An identifying
                // User-Agent is expected practice and avoids 406/429s.
                'User-Agent': 'HikeSafeApp/1.0 (Flutter hiking safety app)',
              },
              body: {'data': query},
            )
            .timeout(_overpassTimeout);

        if (response.statusCode != 200) {
          errors.add('$endpoint -> HTTP ${response.statusCode}');
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final trails = parser(data);
        return _OverpassResult(trails: trails, hadRealError: false, errors: errors);
      } catch (e) {
        errors.add('$endpoint -> $e');
        continue;
      }
    }

    return _OverpassResult(trails: [], hadRealError: true, errors: errors);
  }

  /// Parses the named-route-relations query response: relations (with tags
  /// + member way ids, from "out body") plus way geometries (from "out
  /// geom"), stitched together into full named Trails.
  static List<Trail> _parseNamedRoutes(Map<String, dynamic> data) {
    final elements = data['elements'] as List;

    final relationTags = <int, Map<String, dynamic>>{};
    final relationWayIds = <int, List<int>>{};
    final wayGeometry = <int, List<LatLng>>{};

    for (final el in elements) {
      if (el['type'] == 'relation') {
        final id = el['id'] as int;
        relationTags[id] = (el['tags'] as Map?)?.cast<String, dynamic>() ?? {};
        final members = (el['members'] as List?) ?? [];
        relationWayIds[id] = [
          for (final m in members)
            if (m['type'] == 'way') m['ref'] as int
        ];
      } else if (el['type'] == 'way') {
        final id = el['id'] as int;
        final geom = (el['geometry'] as List?) ?? [];
        wayGeometry[id] = [
          for (final pt in geom)
            if (pt != null)
              LatLng((pt['lat'] as num).toDouble(), (pt['lon'] as num).toDouble())
        ];
      }
    }

    final trails = <Trail>[];
    relationTags.forEach((relId, tags) {
      final wayIds = relationWayIds[relId] ?? [];
      final points = <LatLng>[];
      for (final wayId in wayIds) {
        final segment = wayGeometry[wayId];
        if (segment != null) points.addAll(segment);
      }
      if (points.length >= 2) {
        trails.add(Trail(
          name: tags['name'] as String?,
          network: tags['network'] as String?,
          points: points,
          isNamedRoute: true,
        ));
      }
    });

    return trails;
  }

  /// Parses the raw path/track fallback query response: plain OSM ways with
  /// a node lookup.
  static List<Trail> _parseRawWays(Map<String, dynamic> data) {
    final elements = data['elements'] as List;

    final nodeMap = <int, LatLng>{};
    for (final el in elements) {
      if (el['type'] == 'node') {
        nodeMap[el['id'] as int] = LatLng(
          (el['lat'] as num).toDouble(),
          (el['lon'] as num).toDouble(),
        );
      }
    }

    final trails = <Trail>[];
    for (final el in elements) {
      if (el['type'] == 'way') {
        final nodeIds = (el['nodes'] as List).cast<int>();
        final points = <LatLng>[];
        for (final id in nodeIds) {
          final point = nodeMap[id];
          if (point != null) points.add(point);
        }
        if (points.length >= 2) {
          trails.add(Trail(points: points, isNamedRoute: false));
        }
      }
    }

    return trails;
  }

  static double _distanceToClosestPoint(double lat, double lon, List<LatLng> points) {
    const distanceCalc = Distance();
    double best = double.infinity;
    final origin = LatLng(lat, lon);
    for (final p in points) {
      final d = distanceCalc(origin, p);
      if (d < best) best = d;
    }
    return best;
  }
}
