import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/sgc_api_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final EarthquakeApiService _apiService = EarthquakeApiService();
  
  LatLng? _currentPosition;
  List<Earthquake> _recentEarthquakes = [];
  bool _isLoading = true;
  bool _mapReady = false;
  Timer? _refreshTimer;

  bool get _isUserInColombia {
    if (_currentPosition == null) return true; // Default to Colombia
    // Reuse the polygon check from Earthquake class
    final testEq = Earthquake(
      id: 'test', date: DateTime.now(), magnitude: 0,
      latitude: _currentPosition!.latitude, longitude: _currentPosition!.longitude,
      depth: 0, reference: '', source: '',
    );
    return testEq.isInColombia;
  }

  @override
  void initState() {
    super.initState();
    _loadEarthquakes().then((_) => _tryDeterminePosition());
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) => _loadEarthquakes());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _tryDeterminePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted) {
        setState(() => _currentPosition = LatLng(position.latitude, position.longitude));
        if (_mapReady) _mapController.move(_currentPosition!, 6.0);
      }
    } catch (e) {
      debugPrint('Geolocation unavailable: $e');
    }
  }

  Future<void> _loadEarthquakes() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final earthquakes = await _apiService.fetchRecentEarthquakes(limit: 2000);
      if (mounted) {
        setState(() {
          _recentEarthquakes = earthquakes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _magnitudeColor(double mag) {
    if (mag >= 6.0) return const Color(0xFFFF0000);
    if (mag >= 5.0) return const Color(0xFFFF4444);
    if (mag >= 4.0) return const Color(0xFFFF8800);
    if (mag >= 3.0) return const Color(0xFFFFBB33);
    if (mag >= 2.0) return const Color(0xFF99CC00);
    return const Color(0xFF66BB6A);
  }

  double _magnitudeSize(double mag) {
    if (mag >= 6.0) return 40;
    if (mag >= 5.0) return 34;
    if (mag >= 4.0) return 28;
    if (mag >= 3.0) return 22;
    if (mag >= 2.0) return 18;
    return 14;
  }

  // Find the nearest earthquake to a tap point
  Earthquake? _findNearestQuake(LatLng tapPoint) {
    Earthquake? nearest;
    double minDist = double.infinity;
    for (final eq in _recentEarthquakes) {
      final dLat = eq.latitude - tapPoint.latitude;
      final dLon = eq.longitude - tapPoint.longitude;
      final dist = dLat * dLat + dLon * dLon;
      if (dist < minDist) {
        minDist = dist;
        nearest = eq;
      }
    }
    // Only trigger if tap is close enough (roughly ~50km at equator zoom)
    if (nearest != null && minDist < 0.5) return nearest;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _currentPosition ?? const LatLng(4.5709, -74.2973);
    final colombianQuakes = _recentEarthquakes.where((eq) => eq.isInColombia).toList();

    // Build lightweight CircleMarker list (canvas-rendered, no widget overhead)
    final circles = _recentEarthquakes.map((eq) {
      final color = _magnitudeColor(eq.magnitude);
      final radius = _magnitudeSize(eq.magnitude) / 2;
      return CircleMarker(
        point: LatLng(eq.latitude, eq.longitude),
        radius: radius,
        color: color.withValues(alpha: 0.35),
        borderColor: color,
        borderStrokeWidth: 1.5,
      );
    }).toList();

    // Only create widget-based Markers for significant quakes (M4+) to show text labels
    final significantQuakes = _recentEarthquakes.where((eq) => eq.magnitude >= 4.0).take(100).toList();

    return Column(
      children: [
        Expanded(
          flex: _isUserInColombia ? 3 : 5,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: _isUserInColombia 
                    ? const BorderRadius.vertical(top: Radius.circular(12)) 
                    : BorderRadius.circular(12),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom: 3.0,
                    onMapReady: () => _mapReady = true,
                    onTap: (tapPosition, point) {
                      final eq = _findNearestQuake(point);
                      if (eq != null) _showEarthquakeDetails(eq);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.quakenet.quakenet',
                    ),
                    // Canvas-drawn circles — extremely fast, no widget tree
                    CircleLayer(circles: circles),
                    // Minimal widget layer: user position + M4+ text labels only
                    MarkerLayer(
                      markers: [
                        if (_currentPosition != null)
                          Marker(
                            point: _currentPosition!,
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF58A6FF),
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF58A6FF).withValues(alpha: 0.5),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ...significantQuakes.map((eq) {
                          final size = _magnitudeSize(eq.magnitude);
                          return Marker(
                            point: LatLng(eq.latitude, eq.longitude),
                            width: size,
                            height: size,
                            child: Center(
                              child: Text(
                                eq.magnitude.toStringAsFixed(1),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: size * 0.35,
                                  fontWeight: FontWeight.bold,
                                  shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
              if (_isLoading)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Cargando sismos...', style: TextStyle(fontSize: 12, color: Color(0xFF8B949E))),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: const Color(0xFF161B22).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _loadEarthquakes,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh, size: 16, color: Color(0xFF8B949E)),
                          if (_recentEarthquakes.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${_recentEarthquakes.length} sismos',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFC9D1D9)),
                            ),
                            if (colombianQuakes.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3FB950).withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${colombianQuakes.length} 🇨🇴',
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF3FB950), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Colombia reports panel
        if (_isUserInColombia)
          Expanded(
            flex: 2,
            child: _buildColombiaReportsList(colombianQuakes),
          ),
      ],
    );
  }

  Widget _buildColombiaReportsList(List<Earthquake> colombianQuakes) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              color: const Color(0xFF0D1117).withValues(alpha: 0.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.article_outlined, size: 16, color: Color(0xFF3FB950)),
                const SizedBox(width: 8),
                const Text(
                  'Sismos en Colombia',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Spacer(),
                Text(
                  '${colombianQuakes.length} eventos',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
                ),
              ],
            ),
          ),
          Expanded(
            child: colombianQuakes.isEmpty 
              ? const Center(
                  child: Text(
                    'No hay sismos recientes en Colombia',
                    style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: colombianQuakes.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (context, index) {
                    final eq = colombianQuakes[index];
                    final color = _magnitudeColor(eq.magnitude);
                    
                    String distanceStr = '';
                    if (_currentPosition != null) {
                      final dist = Geolocator.distanceBetween(
                        _currentPosition!.latitude, _currentPosition!.longitude,
                        eq.latitude, eq.longitude,
                      );
                      distanceStr = '${(dist / 1000).toStringAsFixed(0)}km';
                    }

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          eq.magnitude.toStringAsFixed(1),
                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      title: FutureBuilder<String>(
                        future: ReverseGeocoder.getAddress(eq.latitude, eq.longitude, eq.reference),
                        builder: (context, snapshot) {
                          return Text(
                            snapshot.data ?? 'Cargando...',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                      subtitle: Text(
                        'Prof: ${eq.depth.toStringAsFixed(1)}km • ${_formatDate(eq.date)} • ${eq.source}',
                        style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                      ),
                      trailing: distanceStr.isNotEmpty ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.near_me, size: 12, color: Color(0xFF8B949E)),
                          const SizedBox(height: 2),
                          Text(distanceStr, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10)),
                        ],
                      ) : null,
                      onTap: () {
                        _mapController.move(LatLng(eq.latitude, eq.longitude), 7.0);
                        _showEarthquakeDetails(eq);
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays}d';
    return '${local.day}/${local.month}/${local.year}';
  }

  void _showEarthquakeDetails(Earthquake eq) {
    String distanceText = '';
    if (_currentPosition != null) {
      final distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        eq.latitude, eq.longitude,
      );
      distanceText = '${(distanceInMeters / 1000).toStringAsFixed(1)} km de ti';
    }

    final color = _magnitudeColor(eq.magnitude);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color),
                  ),
                  child: Text(
                    'M ${eq.magnitude.toStringAsFixed(1)}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 8),
                if (eq.isInColombia)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3FB950).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('🇨🇴 Colombia', style: TextStyle(fontSize: 11, color: Color(0xFF3FB950))),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Location from reverse geocoding
            FutureBuilder<String>(
              future: ReverseGeocoder.getAddress(eq.latitude, eq.longitude, eq.reference),
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? 'Cargando ubicación...',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                );
              },
            ),
            if (eq.reference.isNotEmpty && eq.source == 'USGS')
              Text(eq.reference, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            const SizedBox(height: 12),
            _detailRow(Icons.arrow_downward, 'Profundidad', '${eq.depth.toStringAsFixed(1)} km'),
            _detailRow(Icons.access_time, 'Fecha', eq.date.toLocal().toString().split('.')[0]),
            _detailRow(Icons.source, 'Fuente', eq.source),
            _detailRow(Icons.location_on, 'Coordenadas', '${eq.latitude.toStringAsFixed(3)}, ${eq.longitude.toStringAsFixed(3)}'),
            if (distanceText.isNotEmpty)
              _detailRow(Icons.near_me, 'Distancia', distanceText),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF8B949E)),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 13))),
        ],
      ),
    );
  }
}
