import 'dart:convert';
import 'package:http/http.dart' as http;

/// Represents a single earthquake event.
class Earthquake {
  final String id;
  final DateTime date;
  final double magnitude;
  final double latitude;
  final double longitude;
  final double depth;
  final String reference;
  final String source;

  Earthquake({
    required this.id,
    required this.date,
    required this.magnitude,
    required this.latitude,
    required this.longitude,
    required this.depth,
    required this.reference,
    required this.source,
  });

  /// Accurate Colombian territory bounds using a simplified polygon
  bool get isInColombia {
    // San Andres and Providencia are part of Colombia but lie outside the
    // mainland polygon below.
    if (latitude >= 12.2 && latitude <= 13.8 && longitude >= -82.1 && longitude <= -81.0) {
      return true;
    }
    final List<List<double>> polygon = [
      [12.5, -71.5], [11.0, -71.0], [9.0, -73.0],  [7.0, -71.0],
      [4.0, -67.5],  [-1.0, -69.0], [-4.2, -70.0], [-0.5, -75.0],
      [1.5, -79.0],  [6.0, -77.5],  [8.0, -77.5],  [9.5, -75.0],
    ];
    int intersectCount = 0;
    for (int j = 0; j < polygon.length - 1; j++) {
      if (_rayCastIntersect(latitude, longitude, polygon[j], polygon[j + 1])) intersectCount++;
    }
    if (_rayCastIntersect(latitude, longitude, polygon.last, polygon.first)) intersectCount++;
    return (intersectCount % 2) == 1;
  }

  bool _rayCastIntersect(double lat, double lon, List<double> p1, List<double> p2) {
    double lat1 = p1[0], lon1 = p1[1];
    double lat2 = p2[0], lon2 = p2[1];
    if ((lon1 > lon) != (lon2 > lon)) {
      double intersectLat = lat1 + (lon - lon1) * (lat2 - lat1) / (lon2 - lon1);
      if (lat < intersectLat) return true;
    }
    return false;
  }

  // -- USGS GeoJSON parser --
  factory Earthquake.fromUsgsJson(Map<String, dynamic> json) {
    final props = json['properties'] as Map<String, dynamic>? ?? {};
    final geo = json['geometry'] as Map<String, dynamic>? ?? {};
    final coords = geo['coordinates'] as List<dynamic>? ?? [0.0, 0.0, 0.0];

    return Earthquake(
      id: 'usgs_${json['id'] ?? ''}',
      date: DateTime.fromMillisecondsSinceEpoch((props['time'] as int?) ?? 0),
      magnitude: (props['mag'] as num?)?.toDouble() ?? 0.0,
      latitude: (coords[1] as num?)?.toDouble() ?? 0.0,
      longitude: (coords[0] as num?)?.toDouble() ?? 0.0,
      depth: (coords.length > 2 ? coords[2] as num? : 0)?.toDouble() ?? 0.0,
      reference: (props['place'] as String?) ?? 'Desconocido',
      source: 'USGS',
    );
  }

  // -- Official SGC GeoJSON parser --
  factory Earthquake.fromSgcJson(Map<String, dynamic> json) {
    final props = json['properties'] as Map<String, dynamic>? ?? {};
    final geo = json['geometry'] as Map<String, dynamic>? ?? {};
    final coords = geo['coordinates'] as List<dynamic>? ?? [0.0, 0.0, 0.0];
    // Convert '2026-09-23 05:09:02' to '2026-09-23T05:09:02' for reliable Dart parsing
    final utcTime = props['utcTime']?.toString().replaceAll(' ', 'T');
    final localTime = props['localTime']?.toString().replaceAll(' ', 'T');

    return Earthquake(
      id: 'sgc_${json['id'] ?? ''}',
      // Prefer the UTC timestamp so filtering works correctly in any device timezone.
      date: utcTime == null
          ? DateTime.tryParse(localTime ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.tryParse('${utcTime}Z')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      magnitude: (props['mag'] as num?)?.toDouble() ?? 0.0,
      latitude: (coords[1] as num?)?.toDouble() ?? 0.0,
      longitude: (coords[0] as num?)?.toDouble() ?? 0.0,
      depth: (props['depth'] as num?)?.toDouble() ??
          (coords.length > 2 ? coords[2] as num? : 0)?.toDouble() ?? 0.0,
      reference: (props['place'] as String?) ?? 'SGC',
      source: 'SGC',
    );
  }
}

class EarthquakeApiService {
  // ALL earthquakes in the last 7 days — many more epicenters
  static const String _usgsWeekly =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_week.geojson';

  // SGC: Catálogo oficial del Servicio Geológico Colombiano (MapServer)
  // Official SGC feed used by its current seismicity viewer. It is queried
  // by date, unlike the historical ArcGIS catalogue.
  static const String _sgcRecentEvents =
      'https://api.sgc.gov.co/biweekly/biweekly_earthquakes';

  /// Fetch from SGC for Colombia and USGS for the rest of the world.
  Future<List<Earthquake>> fetchRecentEarthquakes({int limit = 2000, int perRegion = 20}) async {
    final results = await Future.wait([
      _fetchUsgs(limit: limit),
      _fetchSgc(),
    ]);

    final usgsQuakes = results[0];
    final sgcQuakes = results[1];

    // Colombia is represented exclusively by its official source (SGC).
    final all = [...sgcQuakes, ...usgsQuakes.where((eq) => !eq.isInColombia)];
    all.sort((a, b) => b.date.compareTo(a.date));

    // Group by ~5° grid cell (rough country/region) and keep only the most recent per region
    // EXCEPTION: Keep all earthquakes inside Colombia
    final Map<String, List<Earthquake>> byRegion = {};
    final List<Earthquake> colombiaQuakes = [];
    
    for (final eq in all) {
      if (eq.isInColombia) {
        colombiaQuakes.add(eq);
      } else {
        final key = '${(eq.latitude / 5).floor()}_${(eq.longitude / 5).floor()}';
        byRegion.putIfAbsent(key, () => []);
        byRegion[key]!.add(eq);
      }
    }

    final List<Earthquake> filtered = [...colombiaQuakes];
    for (final regionQuakes in byRegion.values) {
      filtered.addAll(regionQuakes.take(perRegion));
    }
    
    // Filter to strictly the last 24 hours
    final oneDayAgo = DateTime.now().subtract(const Duration(hours: 24));
    final recentOnly = filtered.where((eq) => eq.date.isAfter(oneDayAgo)).toList();

    recentOnly.sort((a, b) => b.date.compareTo(a.date));
    return recentOnly;
  }

  Future<List<Earthquake>> _fetchUsgs({int limit = 2000}) async {
    try {
      final response = await http.get(Uri.parse(_usgsWeekly)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>? ?? [];
        return features
            .take(limit)
            .map((f) => Earthquake.fromUsgsJson(f as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Earthquake>> _fetchSgc() async {
    try {
      // Add a day to cover Colombia's UTC-5 local time around midnight.
      // The common 24-hour filter below keeps the final list fresh.
      final now = DateTime.now();
      final uri = Uri.parse(_sgcRecentEvents).replace(queryParameters: {
        'startdate': _formatSgcDate(now.subtract(const Duration(days: 2))),
        'enddate': _formatSgcDate(now.add(const Duration(hours: 1))),
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>? ?? [];
        return features
            .map((feature) => Earthquake.fromSgcJson(feature as Map<String, dynamic>))
            .where((eq) => eq.isInColombia && eq.magnitude > 0)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  String _formatSgcDate(DateTime date) {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)}T'
        '${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
  }
}

/// Reverse-geocoding via OpenStreetMap Nominatim (HTTP, works on any device)
class ReverseGeocoder {
  static final Map<String, String> _cache = {};

  static Future<String> getAddress(double lat, double lon, String fallback) async {
    // Round to 1 decimal place (~11.1 km accuracy) to drastically increase cache hits 
    // and prevent Nominatim rate-limiting (HTTP 429) when rendering 50+ list items.
    final key = '${lat.toStringAsFixed(1)}_${lon.toStringAsFixed(1)}';
    if (_cache.containsKey(key)) return _cache[key]!;

    try {
      final url = 'https://nominatim.openstreetmap.org/reverse'
          '?format=json&lat=$lat&lon=$lon&zoom=12&accept-language=es';
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'QuakeNet/1.0'},
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>? ?? {};

        final city = address['city'] ?? address['town'] ?? address['village'] ?? address['municipality'] ?? address['county'] ?? address['state_district'] ?? '';
        final state = address['state'] ?? '';
        final country = address['country'] ?? '';

        String result;
        if (city.toString().isNotEmpty && state.toString().isNotEmpty) {
          result = '${city}, ${state}';
        } else if (city.toString().isNotEmpty) {
          result = '$city, $country';
        } else if (state.toString().isNotEmpty) {
          result = '$state, $country';
        } else {
          result = data['display_name']?.toString().split(',').take(2).join(',') ?? fallback;
        }

        _cache[key] = result;
        return result;
      }
    } catch (_) {}
    
    // In case of rate-limiting or network error, return the fallback string, but DON'T cache it 
    // so it can retry later if the user scrolls.
    return fallback;
  }
}
