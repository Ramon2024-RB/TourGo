import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

import 'package:latlong2/latlong.dart';

import 'data/district_repository.dart';

import 'data/street_segment_service.dart';
import 'data/local_district_storage.dart';

import 'models/district.dart';

import 'models/street_segment.dart';

import 'models/tour_stop.dart';

import 'utils/address_normalizer.dart';

void main() {
  runApp(const TourGoApp());
}

class TourGoApp extends StatelessWidget {
  const TourGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TourGo',

      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),

          brightness: Brightness.light,
        ),

        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),

      home: const DistrictSelectionPage(),
    );
  }
}

class DistrictSelectionPage extends StatefulWidget {
  const DistrictSelectionPage({super.key});

  @override
  State<DistrictSelectionPage> createState() => _DistrictSelectionPageState();
}

class _DistrictSelectionPageState extends State<DistrictSelectionPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final districts = DistrictRepository.districts.where((district) {
      return district.name.toLowerCase().contains(_query.trim().toLowerCase());
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              const Text(
                'TourGo',

                style: TextStyle(
                  fontSize: 34,

                  fontWeight: FontWeight.w800,

                  letterSpacing: -1,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Welchen Bezirk möchtest du öffnen?',

                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 24),

              TextField(
                onChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                },

                decoration: InputDecoration(
                  hintText: 'Bezirk suchen',

                  prefixIcon: const Icon(Icons.search_rounded),

                  filled: true,

                  fillColor: Colors.white,

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),

                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Bezirke',

                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 12),

              Expanded(
                child: ListView.separated(
                  itemCount: districts.length,

                  separatorBuilder: (_, _) => const SizedBox(height: 10),

                  itemBuilder: (context, index) {
                    final district = districts[index];

                    return _DistrictCard(
                      district: district,

                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DistrictMapPage(district: district),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DistrictCard extends StatelessWidget {
  final District district;

  final VoidCallback onTap;

  const _DistrictCard({required this.district, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,

      borderRadius: BorderRadius.circular(16),

      child: InkWell(
        borderRadius: BorderRadius.circular(16),

        onTap: onTap,

        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),

          child: Row(
            children: [
              Container(
                width: 46,

                height: 46,

                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,

                  borderRadius: BorderRadius.circular(13),
                ),

                child: Icon(
                  Icons.route_rounded,

                  color: Theme.of(context).colorScheme.primary,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Text(
                  district.name,

                  style: const TextStyle(
                    fontSize: 17,

                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class DistrictMapPage extends StatefulWidget {
  final District district;

  const DistrictMapPage({super.key, required this.district});

  @override
  State<DistrictMapPage> createState() => _DistrictMapPageState();
}

class _DistrictMapPageState extends State<DistrictMapPage> {
  final DistrictRepository _repository = const DistrictRepository();

  final LocalDistrictStorage _localStorage = const LocalDistrictStorage();

  final MapController _mapController = MapController();

  late Future<List<TourStop>> _stopsFuture;

  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  bool _locationLoading = false;
  String? _locationError;

  bool _initialFitDone = false;

  int _markerZoomLevel = 0;

  List<TourStop> _loadedStops = const [];

  List<StreetSegment> _segments = const [];

  StreetSegment? _selectedSegment;

  /// Globaler Index innerhalb des gesamten Bezirks.

  int? _selectedStopIndex;

  @override
  void initState() {
    super.initState();

    _stopsFuture = _loadStops();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    if (_locationLoading) return;

    setState(() {
      _locationLoading = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _locationLoading = false;
          _locationError = 'Ortungsdienste sind deaktiviert.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locationLoading = false;
          _locationError = permission == LocationPermission.deniedForever
              ? 'Standortzugriff ist in den Einstellungen deaktiviert.'
              : 'Standortzugriff wurde nicht erlaubt.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );

      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        _locationLoading = false;
        _locationError = null;
      });

      await _positionSubscription?.cancel();

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              distanceFilter: 15,
            ),
          ).listen(
            (position) {
              if (!mounted) return;
              setState(() {
                _currentPosition = position;
                _locationLoading = false;
                _locationError = null;
              });
            },
            onError: (_) {
              if (!mounted) return;
              setState(() {
                _locationLoading = false;
                _locationError = 'Standort konnte nicht aktualisiert werden.';
              });
            },
          );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationLoading = false;
        _locationError = 'Standort konnte nicht ermittelt werden.';
      });
    }
  }

  Future<void> _centerOnCurrentLocation() async {
    if (_currentPosition == null) {
      await _startLocationTracking();
    }

    if (!mounted) return;

    final position = _currentPosition;

    if (position == null) {
      if (_locationError != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_locationError!)));
      }
      return;
    }

    _mapController.move(LatLng(position.latitude, position.longitude), 17);
  }

  Future<List<TourStop>> _loadStops() async {
    final assetStops = await _repository.loadDistrict(widget.district);
    final savedStops = await _localStorage.loadStops(widget.district.number);

    if (savedStops == null) {
      return assetStops;
    }

    return savedStops;
  }

  Future<void> _reloadStopsFromStorage() async {
    setState(() {
      _loadedStops = const [];
      _segments = const [];
      _selectedSegment = null;
      _selectedStopIndex = null;
      _initialFitDone = false;
      _stopsFuture = _loadStops();
    });
  }

  void _fitDistrict(List<TourStop> stops) {
    if (stops.isEmpty) {
      return;
    }

    final points = stops
        .map((stop) => LatLng(stop.latitude, stop.longitude))
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,

          padding: const EdgeInsets.fromLTRB(30, 110, 30, 110),
        ),
      );
    });
  }

  void _selectSegment(StreetSegment segment, {bool fitCamera = true}) {
    setState(() {
      _selectedSegment = segment;

      _selectedStopIndex = null;
    });

    if (!fitCamera) {
      return;
    }

    _fitSegment(segment);
  }

  void _fitSegment(StreetSegment segment) {
    final points = segment.stops
        .map((stop) => LatLng(stop.latitude, stop.longitude))
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || points.isEmpty) {
        return;
      }

      if (points.length == 1) {
        _mapController.move(points.first, 18);

        return;
      }

      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,

          padding: const EdgeInsets.fromLTRB(60, 120, 60, 250),
        ),
      );
    });
  }

  StreetSegment? _segmentForStopIndex(int stopIndex) {
    for (final segment in _segments) {
      if (stopIndex >= segment.startStopIndex &&
          stopIndex <= segment.endStopIndex) {
        return segment;
      }
    }

    return null;
  }

  void _selectStop(int stopIndex) {
    if (stopIndex < 0 || stopIndex >= _loadedStops.length) {
      return;
    }

    final stop = _loadedStops[stopIndex];

    final segment = _segmentForStopIndex(stopIndex);

    setState(() {
      _selectedStopIndex = stopIndex;

      _selectedSegment = segment;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _mapController.move(LatLng(stop.latitude, stop.longitude), 18);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedSegment = null;

      _selectedStopIndex = null;
    });
  }

  bool _isStopInSelectedSegment(int stopIndex) {
    final segment = _selectedSegment;

    if (segment == null) {
      return false;
    }

    return stopIndex >= segment.startStopIndex &&
        stopIndex <= segment.endStopIndex;
  }

  StreetSegment? _previousSegment(StreetSegment segment) {
    final index = _segments.indexOf(segment);

    if (index <= 0) {
      return null;
    }

    return _segments[index - 1];
  }

  StreetSegment? _nextSegment(StreetSegment segment) {
    final index = _segments.indexOf(segment);

    if (index < 0 || index >= _segments.length - 1) {
      return null;
    }

    return _segments[index + 1];
  }

  DuplicateStopPosition? _duplicateInfoForStop(
    StreetSegment segment,

    int globalStopIndex,
  ) {
    final localIndex = globalStopIndex - segment.startStopIndex;

    return segment.duplicatePositionForStop(localIndex);
  }

  DuplicateStopPosition? _duplicateInfoForGlobalStop(int stopIndex) {
    if (stopIndex < 0 || stopIndex >= _loadedStops.length) {
      return null;
    }

    final selectedStop = _loadedStops[stopIndex];

    if (selectedStop.address.isEmpty) {
      return null;
    }

    final normalizedAddress = AddressNormalizer.normalize(selectedStop.address);

    final matchingIndexes = <int>[];

    for (var index = 0; index < _loadedStops.length; index++) {
      final candidate = _loadedStops[index];

      if (candidate.address.isEmpty) {
        continue;
      }

      if (AddressNormalizer.normalize(candidate.address) == normalizedAddress) {
        matchingIndexes.add(index);
      }
    }

    if (matchingIndexes.length <= 1) {
      return null;
    }

    final position = matchingIndexes.indexOf(stopIndex) + 1;

    if (position <= 0) {
      return null;
    }

    return DuplicateStopPosition(
      position: position,

      total: matchingIndexes.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<TourStop>>(
        future: _stopsFuture,

        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorView(
              districtName: widget.district.name,

              message: snapshot.error.toString(),
            );
          }

          final stops = snapshot.data ?? const <TourStop>[];

          if (stops.isEmpty) {
            return _ErrorView(
              districtName: widget.district.name,

              message: 'Dieser Bezirk enthält keine Stopps.',
            );
          }

          if (_loadedStops.isEmpty) {
            _loadedStops = stops;

            _segments = const StreetSegmentService().buildSegments(stops);
          }

          if (!_initialFitDone) {
            _initialFitDone = true;

            _fitDistrict(stops);
          }

          final selectedSegment = _selectedSegment;

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,

                options: MapOptions(
                  initialCenter: LatLng(
                    stops.first.latitude,

                    stops.first.longitude,
                  ),

                  initialZoom: 14,

                  minZoom: 4,

                  maxZoom: 19,

                  onPositionChanged: (position, hasGesture) {
                    final newZoom = position.zoom;
                    final newMarkerZoomLevel = newZoom < 14.2
                        ? 0
                        : newZoom < 15.5
                        ? 1
                        : 2;


                    if (newMarkerZoomLevel == _markerZoomLevel) {
                      return;
                    }

                    setState(() {
                      _markerZoomLevel = newMarkerZoomLevel;
                    });
                  },
                ),

                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',

                    userAgentPackageName: 'de.ramonvidal.tourgo',
                  ),

                  if (_currentPosition != null &&
                      _currentPosition!.accuracy > 0)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ),
                          radius: _currentPosition!.accuracy,
                          useRadiusInMeter: true,
                          color: const Color(0xFF00B8B8)
                              .withValues(alpha: 0.12),
                          borderColor: const Color(0xFF00A6A6)
                              .withValues(alpha: 0.32),
                          borderStrokeWidth: 1.5,
                        ),
                      ],
                    ),

                  if (_markerZoomLevel == 0)
                    CircleLayer(
                      circles: List.generate(stops.length, (index) {
                        final stop = stops[index];
                        final inSelectedSegment =
                            _isStopInSelectedSegment(index);
                        final isSelectedStop = _selectedStopIndex == index;
                        final dimmed =
                            selectedSegment != null && !inSelectedSegment;

                        Color fillColor;
                        Color borderColor;

                        if (stop.isMailbox) {
                          fillColor = Colors.amber.shade200;
                          borderColor = Colors.amber.shade900;
                        } else if (stop.isCompany) {
                          fillColor = Colors.orange.shade200;
                          borderColor = Colors.orange.shade800;
                        } else {
                          fillColor = const Color(0xFFE3F2FD);
                          borderColor = const Color(0xFF1565C0);
                        }

                        if (isSelectedStop) {
                          fillColor = const Color(0xFF1565C0);
                          borderColor = Colors.white;
                        }

                        final opacity = dimmed ? 0.15 : 1.0;

                        return CircleMarker(
                          point: LatLng(stop.latitude, stop.longitude),
                          radius: isSelectedStop ? 8 : 4.5,
                          color: fillColor.withValues(alpha: opacity),
                          borderColor:
                              borderColor.withValues(alpha: opacity),
                          borderStrokeWidth: isSelectedStop
                              ? 2.5
                              : inSelectedSegment
                              ? 2
                              : 1.2,
                        );
                      }),
                    )
                  else
                    MarkerLayer(
                      markers: List.generate(stops.length, (index) {
                        final stop = stops[index];

                        final inSelectedSegment =
                            _isStopInSelectedSegment(index);

                        final isSelectedStop = _selectedStopIndex == index;

                        final dimmed =
                            selectedSegment != null && !inSelectedSegment;

                        final duplicateInfo =
                            _duplicateInfoForGlobalStop(index);

                        final compact = _markerZoomLevel == 1;

                        final markerWidth = isSelectedStop
                            ? 46.0
                            : compact
                            ? 28.0
                            : inSelectedSegment
                            ? 42.0
                            : 38.0;

                        final markerHeight = isSelectedStop
                            ? 42.0
                            : compact
                            ? 24.0
                            : inSelectedSegment
                            ? 38.0
                            : 34.0;

                        return Marker(
                          point: LatLng(stop.latitude, stop.longitude),

                          width: markerWidth,

                          height: markerHeight,

                          child: Opacity(
                            opacity: dimmed ? 0.15 : 1,

                            child: GestureDetector(
                              onTap: () {
                                _selectStop(index);
                              },

                              child: _StopMarker(
                                stop: stop,

                                stopNumber: index + 1,

                                duplicateInfo: duplicateInfo,

                                selected: inSelectedSegment,

                                target: isSelectedStop,

                                zoomLevel: _markerZoomLevel,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                  if (_markerZoomLevel == 0 && _selectedStopIndex != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(
                            stops[_selectedStopIndex!].latitude,
                            stops[_selectedStopIndex!].longitude,
                          ),
                          width: 46,
                          height: 42,
                          child: GestureDetector(
                            onTap: () {
                              _selectStop(_selectedStopIndex!);
                            },
                            child: _StopMarker(
                              stop: stops[_selectedStopIndex!],
                              stopNumber: _selectedStopIndex! + 1,
                              duplicateInfo: _duplicateInfoForGlobalStop(
                                _selectedStopIndex!,
                              ),
                              selected: _isStopInSelectedSegment(
                                _selectedStopIndex!,
                              ),
                              target: true,
                              zoomLevel: _markerZoomLevel,
                            ),
                          ),
                        ),
                      ],
                    ),

                  if (_currentPosition != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ),
                          width: 30,
                          height: 30,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00B8B8),
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 7,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 7,
                                height: 7,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(14),

                  child: Row(
                    children: [
                      Material(
                        color: Colors.white,

                        borderRadius: BorderRadius.circular(14),

                        elevation: 3,

                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),

                          onTap: () {
                            Navigator.of(context).pop();
                          },

                          child: const SizedBox(
                            width: 48,

                            height: 48,

                            child: Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Container(
                          height: 48,

                          padding: const EdgeInsets.symmetric(horizontal: 16),

                          decoration: BoxDecoration(
                            color: Colors.white,

                            borderRadius: BorderRadius.circular(14),

                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,

                                blurRadius: 8,

                                offset: Offset(0, 2),
                              ),
                            ],
                          ),

                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.district.name,

                                  style: const TextStyle(
                                    fontSize: 17,

                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),

                              Text(
                                '${stops.length} Stopps',

                                style: TextStyle(
                                  fontSize: 13,

                                  color: Colors.grey.shade600,
                                ),
                              ),

                              const SizedBox(width: 4),

                              PopupMenuButton<String>(
                                tooltip: 'Bezirk-Menü',
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.more_vert_rounded),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    Navigator.of(context)
                                        .push(
                                          MaterialPageRoute(
                                            builder: (_) => DistrictEditorPage(
                                              district: widget.district,
                                              stops: stops,
                                            ),
                                          ),
                                        )
                                        .then((_) async {
                                          if (!mounted) {
                                            return;
                                          }
                                          await _reloadStopsFromStorage();
                                        });
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem<String>(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_road_rounded),
                                        SizedBox(width: 10),
                                        Text('Bezirk bearbeiten'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Positioned(
                right: 14,

                bottom: selectedSegment == null ? 92 : 260,

                child: SafeArea(
                  top: false,

                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: IconButton(
                          tooltip: 'Zu meinem Standort',
                          onPressed: _locationLoading
                              ? null
                              : _centerOnCurrentLocation,
                          icon: _locationLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Color(0xFF00A6A6),
                                  ),
                                )
                              : Icon(
                                  _currentPosition == null
                                      ? Icons.my_location_outlined
                                      : Icons.my_location_rounded,
                                  color: const Color(0xFF00A6A6),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Material(
                        color: Colors.white,

                        shape: const CircleBorder(),

                        elevation: 4,

                        child: IconButton(
                          tooltip: 'Gesamten Bezirk anzeigen',

                          onPressed: () {
                            _clearSelection();

                            _fitDistrict(stops);
                          },

                          icon: const Icon(Icons.zoom_out_map_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (selectedSegment == null)
                Positioned(
                  left: 14,

                  right: 14,

                  bottom: 20,

                  child: SafeArea(
                    top: false,

                    child: Material(
                      color: Colors.white,

                      borderRadius: BorderRadius.circular(18),

                      elevation: 5,

                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),

                        onTap: () {
                          _openSearch();
                        },

                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 18,

                            vertical: 16,
                          ),

                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,

                                color: Color(0xFF1565C0),
                              ),

                              SizedBox(width: 12),

                              Expanded(
                                child: Text(
                                  'Straße oder Hausnummer suchen',

                                  style: TextStyle(
                                    fontSize: 16,

                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (selectedSegment != null)
                Positioned(
                  left: 12,

                  right: 12,

                  bottom: 12,

                  child: SafeArea(
                    top: false,

                    child: _SelectedSegmentCard(
                      segment: selectedSegment,

                      previous: _previousSegment(selectedSegment),

                      next: _nextSegment(selectedSegment),

                      selectedStopIndex: _selectedStopIndex,

                      duplicateInfo: _selectedStopIndex == null
                          ? null
                          : _duplicateInfoForStop(
                              selectedSegment,

                              _selectedStopIndex!,
                            ),

                      selectedStop: _selectedStopIndex == null
                          ? null
                          : stops[_selectedStopIndex!],

                      onClose: _clearSelection,

                      onSearch: _openSearch,

                      onPreviousStop:
                          _selectedStopIndex != null && _selectedStopIndex! > 0
                          ? () => _selectStop(_selectedStopIndex! - 1)
                          : null,

                      onNextStop:
                          _selectedStopIndex != null &&
                              _selectedStopIndex! < stops.length - 1
                          ? () => _selectStop(_selectedStopIndex! + 1)
                          : null,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openSearch() {
    showSearch<void>(
      context: context,

      delegate: TourSearchDelegate(
        stops: _loadedStops,

        segments: _segments,

        onStopSelected: (stopIndex) {
          _selectStop(stopIndex);
        },

        onSegmentSelected: (segment) {
          _selectSegment(segment);
        },
      ),
    );
  }
}

class _SelectedSegmentCard extends StatelessWidget {
  final StreetSegment segment;
  final StreetSegment? previous;
  final StreetSegment? next;
  final int? selectedStopIndex;
  final TourStop? selectedStop;
  final DuplicateStopPosition? duplicateInfo;
  final VoidCallback onClose;
  final VoidCallback onSearch;
  final VoidCallback? onPreviousStop;
  final VoidCallback? onNextStop;

  const _SelectedSegmentCard({
    required this.segment,
    required this.previous,
    required this.next,
    required this.selectedStopIndex,
    required this.selectedStop,
    required this.duplicateInfo,
    required this.onClose,
    required this.onSearch,
    required this.onPreviousStop,
    required this.onNextStop,
  });

  @override
  Widget build(BuildContext context) {
    final stop = selectedStop;
    final stopIndex = selectedStopIndex;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: stop != null && stopIndex != null
            ? _buildStopView(context, stop, stopIndex)
            : _buildSegmentView(context),
      ),
    );
  }

  Widget _buildStopView(BuildContext context, TourStop stop, int stopIndex) {
    final primary = Theme.of(context).colorScheme.primary;
    final address = stop.address.isNotEmpty ? stop.address : stop.name;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.location_on_rounded, color: primary, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 7,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _InfoPill(label: 'Stopp ${stopIndex + 1}'),
                      if (duplicateInfo != null)
                        _InfoPill(
                          label:
                              '${duplicateInfo!.position} von ${duplicateInfo!.total}',
                          emphasized: true,
                        ),
                      if (stop.hasSection)
                        _InfoPill(label: 'Teil ${stop.section}'),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Schließen',
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        if (stop.isMailbox ||
            stop.company.isNotEmpty ||
            stop.note.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FB),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stop.isMailbox)
                  const _StopDetailRow(
                    icon: Icons.markunread_mailbox_rounded,
                    text: 'Briefkasten',
                  ),
                if (stop.company.isNotEmpty)
                  _StopDetailRow(
                    icon: Icons.business_rounded,
                    text: stop.company,
                  ),
                if (stop.note.isNotEmpty)
                  _StopDetailRow(
                    icon: Icons.info_outline_rounded,
                    text: stop.note,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StopNavigationButton(
                icon: Icons.arrow_back_rounded,
                label: 'Vorheriger',
                onPressed: onPreviousStop,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StopNavigationButton(
                icon: Icons.arrow_forward_rounded,
                label: 'Nächster',
                onPressed: onNextStop,
                iconAfter: true,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Suche',
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSegmentView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    segment.streetName,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${segment.stopRange} · ${segment.stopCount} ${segment.stopCount == 1 ? 'Stopp' : 'Stopps'}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Suche',
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              tooltip: 'Schließen',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        if (segment.houseNumbers.isNotEmpty) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              segment.houseNumbers,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                previous == null ? '← Start' : '← ${previous!.streetName}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                next == null ? 'Ende →' : '${next!.streetName} →',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final bool emphasized;

  const _InfoPill({required this.label, this.emphasized = false});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: emphasized
            ? Theme.of(context).colorScheme.primaryContainer
            : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: emphasized ? primary : Colors.grey.shade700,
        ),
      ),
    );
  }
}

class _StopDetailRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _StopDetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopNavigationButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool iconAfter;

  const _StopNavigationButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconAfter = false,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Icon(icon, size: 17),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ];

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: iconAfter ? children.reversed.toList() : children,
      ),
    );
  }
}

class _StopMarker extends StatelessWidget {
  final TourStop stop;

  final int stopNumber;

  final DuplicateStopPosition? duplicateInfo;

  final bool selected;

  final bool target;

  final int zoomLevel;

  const _StopMarker({
    required this.stop,

    required this.stopNumber,

    required this.duplicateInfo,

    this.selected = false,

    this.target = false,

    required this.zoomLevel,
  });

  @override
  Widget build(BuildContext context) {
    final houseNumber = stop.houseNumber.isNotEmpty ? stop.houseNumber : '•';

    final compact = !target && zoomLevel < 2;
    final veryCompact = !target && zoomLevel == 0;

    final secondaryParts = <String>[];

    if (stop.hasSection) {
      secondaryParts.add(stop.section);
    }

    secondaryParts.add('$stopNumber');

    final secondaryText = secondaryParts.join(' · ');

    String duplicateSuperscript = '';
    if (duplicateInfo != null) {
      const superscriptDigits = <String>[
        '⁰',
        '¹',
        '²',
        '³',
        '⁴',
        '⁵',
        '⁶',
        '⁷',
        '⁸',
        '⁹',
      ];

      final positionText = duplicateInfo!.position.toString();
      duplicateSuperscript = positionText
          .split('')
          .map((digit) => superscriptDigits[int.parse(digit)])
          .join();
    }

    Color backgroundColor;

    Color borderColor;

    Color foregroundColor;

    if (target) {
      backgroundColor = const Color(0xFF1565C0);

      borderColor = Colors.white;

      foregroundColor = Colors.white;
    } else if (stop.isMailbox) {
      backgroundColor = selected
          ? Colors.amber.shade200
          : Colors.amber.shade100;

      borderColor = Colors.amber.shade900;

      foregroundColor = Colors.amber.shade900;
    } else if (stop.isCompany) {
      backgroundColor = selected
          ? Colors.orange.shade100
          : Colors.orange.shade50;

      borderColor = Colors.orange.shade800;

      foregroundColor = Colors.orange.shade900;
    } else {
      backgroundColor = selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.white;

      borderColor = const Color(0xFF1565C0);

      foregroundColor = const Color(0xFF1565C0);
    }

    final statusIcon = stop.isMailbox
        ? Icons.markunread_mailbox_rounded
        : stop.isCompany
        ? Icons.business_rounded
        : null;

    if (veryCompact) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor,
          border: Border.all(
            color: borderColor,
            width: selected ? 2.2 : 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.24 : 0.14),
              blurRadius: selected ? 4 : 2,
            ),
          ],
        ),
        child: statusIcon == null
            ? null
            : Center(
                child: Icon(
                  statusIcon,
                  size: 10,
                  color: foregroundColor,
                ),
              ),
      );
    }

    if (compact) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: borderColor,
            width: selected ? 2.4 : 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.25 : 0.14),
              blurRadius: selected ? 4 : 2,
            ),
          ],
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: houseNumber),
              if (duplicateSuperscript.isNotEmpty)
                TextSpan(
                  text: duplicateSuperscript,
                  style: const TextStyle(
                    fontSize: 6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            fontSize: 10,
            height: 1,
            fontWeight: FontWeight.w900,
            color: foregroundColor,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),

      decoration: BoxDecoration(
        color: backgroundColor,

        borderRadius: BorderRadius.circular(9),

        border: Border.all(
          color: borderColor,

          width: target
              ? 2.5
              : selected
              ? 3
              : 1.5,
        ),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: target
                  ? 0.38
                  : selected
                  ? 0.28
                  : 0.16,
            ),

            blurRadius: target
                ? 9
                : selected
                ? 6
                : 3,

            spreadRadius: target ? 1 : 0,
          ),
        ],
      ),

      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,

              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: houseNumber),
                      if (duplicateSuperscript.isNotEmpty)
                        TextSpan(
                          text: duplicateSuperscript,
                          style: TextStyle(
                            fontSize: target
                                ? 9
                                : selected
                                ? 8
                                : 7.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                    ],
                  ),

                  maxLines: 1,

                  overflow: TextOverflow.fade,

                  softWrap: false,

                  style: TextStyle(
                    fontSize: target
                        ? 15
                        : selected
                        ? 14
                        : 13,

                    height: 1,

                    fontWeight: FontWeight.w900,

                    color: foregroundColor,
                  ),
                ),

                const SizedBox(height: 1),

                Text(
                  secondaryText,

                  maxLines: 1,

                  overflow: TextOverflow.fade,

                  softWrap: false,

                  style: TextStyle(
                    fontSize: target ? 7 : 6,

                    height: 1,

                    fontWeight: FontWeight.w700,

                    color: foregroundColor.withValues(
                      alpha: target ? 0.9 : 0.78,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (statusIcon != null)
            Positioned(
              top: 0,

              right: 0,

              child: Icon(
                statusIcon,

                size: target ? 8 : 7,

                color: foregroundColor,
              ),
            ),
        ],
      ),
    );
  }
}

class TourSearchDelegate extends SearchDelegate<void> {
  final List<TourStop> stops;

  final List<StreetSegment> segments;

  final ValueChanged<int> onStopSelected;

  final ValueChanged<StreetSegment> onSegmentSelected;

  TourSearchDelegate({
    required this.stops,

    required this.segments,

    required this.onStopSelected,

    required this.onSegmentSelected,
  });

  @override
  String get searchFieldLabel => 'Straße oder Hausnummer';

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) {
      return null;
    }

    return [
      IconButton(
        onPressed: () {
          query = '';
        },

        icon: const Icon(Icons.clear_rounded),
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () {
        close(context, null);
      },

      icon: const Icon(Icons.arrow_back_rounded),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearch(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearch(context);
  }

  Widget _buildSearch(BuildContext context) {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),

          child: Text(
            'Straßenname, Adresse oder Hausnummer eingeben.',

            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final queryIsOnlyHouseNumber = RegExp(r'^\d+\s*[a-zA-Z]?$')
        .hasMatch(trimmedQuery);

    if (queryIsOnlyHouseNumber) {
      return _buildHouseNumberResults(context, trimmedQuery);
    }

    final addressMatches = stops.asMap().entries.where((entry) {
      return AddressNormalizer.contains(entry.value.address, trimmedQuery);
    }).toList();

    final exactAddressMatches = addressMatches.where((entry) {
      return AddressNormalizer.equals(entry.value.address, trimmedQuery);
    }).toList();

    if (exactAddressMatches.isNotEmpty) {
      return _buildStopResults(context, exactAddressMatches, title: 'Adresse');
    }

    final matchingSegments = segments.where((segment) {
      return AddressNormalizer.contains(segment.streetName, trimmedQuery);
    }).toList();

    final containsNumber = RegExp(r'\d').hasMatch(trimmedQuery);

    if (containsNumber && addressMatches.isNotEmpty) {
      return _buildStopResults(context, addressMatches, title: 'Adressen');
    }

    if (matchingSegments.isNotEmpty) {
      return _buildStreetResults(context, matchingSegments);
    }

    if (addressMatches.isNotEmpty) {
      return _buildStopResults(context, addressMatches, title: 'Adressen');
    }

    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),

        child: Text(
          'Keine passende Straße oder Hausnummer gefunden.',

          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildHouseNumberResults(BuildContext context, String searchNumber) {
    final normalizedNumber = AddressNormalizer.normalize(searchNumber);

    final matches = stops.asMap().entries.where((entry) {
      return AddressNormalizer.normalize(entry.value.houseNumber) ==
          normalizedNumber;
    }).toList();

    if (matches.isEmpty) {
      return const Center(child: Text('Keine passende Hausnummer gefunden.'));
    }

    return _buildStopResults(
      context,

      matches,

      title: 'Hausnummer $searchNumber',
    );
  }

  Widget _buildStreetResults(
    BuildContext context,

    List<StreetSegment> matchingSegments,
  ) {
    final groups = <String, List<StreetSegment>>{};

    for (final segment in matchingSegments) {
      final key = AddressNormalizer.normalize(segment.streetName);

      groups.putIfAbsent(key, () => <StreetSegment>[]);

      groups[key]!.add(segment);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),

      children: groups.values.map((streetSegments) {
        final firstSegment = streetSegments.first;

        final totalStops = streetSegments.fold<int>(
          0,

          (sum, segment) => sum + segment.stopCount,
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 12),

          clipBehavior: Clip.antiAlias,

          child: ExpansionTile(
            initiallyExpanded: groups.length == 1,

            leading: const CircleAvatar(child: Icon(Icons.signpost_rounded)),

            title: Text(
              firstSegment.streetName,

              style: const TextStyle(fontWeight: FontWeight.w800),
            ),

            subtitle: Text(
              '${streetSegments.length} '
              '${streetSegments.length == 1 ? 'Abschnitt' : 'Abschnitte'}'
              ' • $totalStops Stopps',
            ),

            children: streetSegments.map((segment) {
              return _StreetSegmentTile(
                segment: segment,

                allSegments: segments,

                onSegmentSelected: () {
                  close(context, null);

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onSegmentSelected(segment);
                  });
                },

                onStopSelected: (globalStopIndex) {
                  close(context, null);

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onStopSelected(globalStopIndex);
                  });
                },
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStopResults(
    BuildContext context,

    List<MapEntry<int, TourStop>> matches, {

    required String title,
  }) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),

          child: Text(
            '$title · ${matches.length} Treffer',

            style: TextStyle(
              color: Colors.grey.shade600,

              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        ...matches.map((entry) {
          final stop = entry.value;

          final stopNumber = entry.key + 1;

          final duplicateInfo = _globalDuplicateInfo(entry.key);

          IconData icon = Icons.home_rounded;

          if (stop.isMailbox) {
            icon = Icons.markunread_mailbox_rounded;
          } else if (stop.isCompany) {
            icon = Icons.business_rounded;
          }

          var titleText = stop.address.isNotEmpty ? stop.address : stop.name;

          if (duplicateInfo != null) {
            titleText += ' · ${duplicateInfo.position}/${duplicateInfo.total}';
          }

          return ListTile(
            leading: CircleAvatar(child: Icon(icon, size: 19)),

            title: Text(
              titleText,

              style: const TextStyle(fontWeight: FontWeight.w700),
            ),

            subtitle: Text(_buildStopSubtitle(stop, stopNumber)),

            trailing: const Icon(Icons.location_on_outlined),

            onTap: () {
              close(context, null);

              WidgetsBinding.instance.addPostFrameCallback((_) {
                onStopSelected(entry.key);
              });
            },
          );
        }),
      ],
    );
  }

  DuplicateStopPosition? _globalDuplicateInfo(int stopIndex) {
    if (stopIndex < 0 || stopIndex >= stops.length) {
      return null;
    }

    final selected = stops[stopIndex];

    if (selected.address.isEmpty) {
      return null;
    }

    final normalized = AddressNormalizer.normalize(selected.address);

    final indexes = <int>[];

    for (var index = 0; index < stops.length; index++) {
      final candidate = stops[index];

      if (candidate.address.isEmpty) {
        continue;
      }

      if (AddressNormalizer.normalize(candidate.address) == normalized) {
        indexes.add(index);
      }
    }

    if (indexes.length <= 1) {
      return null;
    }

    final position = indexes.indexOf(stopIndex) + 1;

    if (position <= 0) {
      return null;
    }

    return DuplicateStopPosition(position: position, total: indexes.length);
  }

  String _buildStopSubtitle(TourStop stop, int stopNumber) {
    final parts = <String>['Stopp $stopNumber'];

    if (stop.hasSection) {
      parts.add('Teil ${stop.section}');
    }

    if (stop.company.isNotEmpty) {
      parts.add(stop.company);
    }

    if (stop.isMailbox) {
      parts.add('Briefkasten');
    }

    return parts.join(' • ');
  }
}

class _StreetSegmentTile extends StatelessWidget {
  final StreetSegment segment;

  final List<StreetSegment> allSegments;

  final VoidCallback onSegmentSelected;

  final ValueChanged<int> onStopSelected;

  const _StreetSegmentTile({
    required this.segment,

    required this.allSegments,

    required this.onSegmentSelected,

    required this.onStopSelected,
  });

  @override
  Widget build(BuildContext context) {
    final segmentIndex = allSegments.indexOf(segment);

    final previous = segmentIndex > 0 ? allSegments[segmentIndex - 1] : null;

    final next = segmentIndex < allSegments.length - 1
        ? allSegments[segmentIndex + 1]
        : null;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),

      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),

        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),

        title: Text(
          'Abschnitt ${segment.segmentNumber}',

          style: const TextStyle(fontWeight: FontWeight.w700),
        ),

        subtitle: Text(
          '${segment.stopRange} • '
          '${segment.stopCount} '
          '${segment.stopCount == 1 ? 'Stopp' : 'Stopps'}',
        ),

        trailing: IconButton(
          tooltip: 'Auf Karte anzeigen',

          onPressed: onSegmentSelected,

          icon: const Icon(Icons.map_outlined),
        ),

        children: [
          if (segment.houseNumbers.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,

              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),

                child: Text(
                  segment.houseNumbers,

                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),

          if (previous != null || next != null)
            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(12),

              margin: const EdgeInsets.only(bottom: 10),

              decoration: BoxDecoration(
                color: Colors.grey.shade100,

                borderRadius: BorderRadius.circular(12),
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  if (previous != null)
                    Text(
                      'Davor: '
                      '${previous.streetName}',
                    ),

                  if (previous != null && next != null)
                    const SizedBox(height: 4),

                  if (next != null) Text('Danach: ${next.streetName}'),
                ],
              ),
            ),

          ...segment.stops.asMap().entries.map((entry) {
            final stop = entry.value;

            final globalStopIndex = segment.startStopIndex + entry.key;

            final actualStopNumber = globalStopIndex + 1;

            final duplicateInfo = segment.duplicatePositionForStop(entry.key);

            var addressText = stop.address.isNotEmpty
                ? stop.address
                : stop.name;

            if (duplicateInfo != null) {
              addressText +=
                  ' · ${duplicateInfo.position}/${duplicateInfo.total}';
            }

            return ListTile(
              contentPadding: EdgeInsets.zero,

              dense: true,

              leading: SizedBox(
                width: 50,

                child: Text(
                  duplicateInfo == null
                      ? (stop.houseNumber.isNotEmpty ? stop.houseNumber : '•')
                      : '${stop.houseNumber}\n'
                            '${duplicateInfo.position}/${duplicateInfo.total}',

                  textAlign: TextAlign.center,

                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),

              title: Text(addressText),

              subtitle: Text('Stopp $actualStopNumber'),

              trailing: const Icon(Icons.chevron_right_rounded),

              onTap: () {
                onStopSelected(globalStopIndex);
              },
            );
          }),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String districtName;

  final String message;

  const _ErrorView({required this.districtName, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(districtName)),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Text(
            'Bezirk konnte nicht geladen werden:\n\n$message',

            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class DistrictEditorPage extends StatelessWidget {
  final District district;
  final List<TourStop> stops;

  const DistrictEditorPage({
    super.key,
    required this.district,
    required this.stops,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${district.name} bearbeiten')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.edit_location_alt_rounded,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        district.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text('${stops.length} Stopps'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Bearbeiten',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _EditorActionCard(
            icon: Icons.location_on_rounded,
            title: 'Zustellpunkte bearbeiten',
            subtitle: 'Vorhandene Stopps ansehen und auswählen',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DistrictStopsEditorPage(district: district, stops: stops),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Die Reihenfolge der Zustellpunkte bestimmt die Tour. '
                    'Du kannst Stopps hinzufügen, verschieben, bearbeiten oder neu anordnen.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EditorActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class DistrictStopsEditorPage extends StatefulWidget {
  final District district;
  final List<TourStop> stops;

  const DistrictStopsEditorPage({
    super.key,
    required this.district,
    required this.stops,
  });

  @override
  State<DistrictStopsEditorPage> createState() =>
      _DistrictStopsEditorPageState();
}

class _DistrictStopsEditorPageState extends State<DistrictStopsEditorPage> {
  final LocalDistrictStorage _localStorage = const LocalDistrictStorage();
  final MapController _editorMapController = MapController();

  late final List<TourStop> _editableStops;
  late LatLng _editorCenter;
  double _editorZoom = 16;
  bool _mapView = true;
  bool _addMode = false;
  int? _moveStopIndex;

  @override
  void initState() {
    super.initState();
    _editableStops = List<TourStop>.from(widget.stops);
    _editorCenter = _editableStops.isNotEmpty
        ? LatLng(_editableStops.first.latitude, _editableStops.first.longitude)
        : const LatLng(50.05, 10.23);
  }

  Future<bool> _saveStops({required String successMessage}) async {
    try {
      await _localStorage.saveStops(widget.district.number, _editableStops);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          duration: const Duration(seconds: 2),
        ),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Speichern fehlgeschlagen: $error'),
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }
  }

  Future<TourStop?> _showStopForm({
    required LatLng position,
    TourStop? existingStop,
    int? stopIndex,
  }) async {
    final addressController = TextEditingController(
      text: existingStop?.address ?? '',
    );
    final companyController = TextEditingController(
      text: existingStop?.company ?? '',
    );
    final noteController = TextEditingController(
      text: existingStop?.note ?? '',
    );
    final sectionController = TextEditingController(
      text: existingStop?.section ?? '',
    );
    var isMailbox = existingStop?.isMailbox ?? false;

    return showModalBottomSheet<TourStop>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        existingStop == null
                            ? 'Neuen Zustellpunkt anlegen'
                            : 'Stopp ${(stopIndex ?? 0) + 1} bearbeiten',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        existingStop == null
                            ? 'Nach dem Speichern bleibst du auf der Karte und kannst direkt den nächsten Punkt setzen.'
                            : 'Änderungen werden direkt lokal gespeichert.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Position: ${position.latitude.toStringAsFixed(6)}, '
                        '${position.longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: addressController,
                        autofocus: existingStop == null,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Adresse',
                          hintText: 'z. B. Bahnhofstraße 22',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.home_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: companyController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Firma',
                          hintText: 'Optional',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteController,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Hinweis',
                          hintText: 'Optional',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.info_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: sectionController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Teil',
                          hintText: 'z. B. A oder B',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.label_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Briefkasten',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Diesen Zustellpunkt als Briefkasten kennzeichnen',
                        ),
                        value: isMailbox,
                        onChanged: (value) {
                          setSheetState(() => isMailbox = value);
                        },
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            final address = addressController.text.trim();
                            if (address.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Bitte eine Adresse eingeben.'),
                                ),
                              );
                              return;
                            }
                            final parsed = _editorSplitAddress(address);
                            Navigator.of(context).pop(
                              TourStop(
                                latitude: position.latitude,
                                longitude: position.longitude,
                                name: address,
                                address: address,
                                streetName: parsed.street,
                                houseNumber: parsed.houseNumber,
                                company: companyController.text.trim(),
                                note: noteController.text.trim(),
                                recipients: existingStop == null
                                    ? const <dynamic>[]
                                    : List<dynamic>.from(
                                        existingStop.recipients,
                                      ),
                                isMailbox: isMailbox,
                                section: sectionController.text.trim(),
                              ),
                            );
                          },
                          icon: Icon(
                            existingStop == null
                                ? Icons.add_location_alt_rounded
                                : Icons.check_rounded,
                          ),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              existingStop == null
                                  ? 'Zustellpunkt hinzufügen'
                                  : 'Änderungen speichern',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addStopAt(LatLng position) async {
    final newStop = await _showStopForm(position: position);
    if (newStop == null || !mounted) return;

    setState(() => _editableStops.add(newStop));
    final saved = await _saveStops(
      successMessage:
          'Stopp ${_editableStops.length} wurde hinzugefügt. Du kannst direkt den nächsten Punkt setzen.',
    );
    if (!saved && mounted) {
      setState(() => _editableStops.removeLast());
    }
  }

  Future<void> _editStop(int index) async {
    final stop = _editableStops[index];
    final updated = await _showStopForm(
      position: LatLng(stop.latitude, stop.longitude),
      existingStop: stop,
      stopIndex: index,
    );
    if (updated == null || !mounted) return;

    final previous = _editableStops[index];
    setState(() => _editableStops[index] = updated);
    final saved = await _saveStops(
      successMessage: 'Stopp ${index + 1} wurde gespeichert.',
    );
    if (!saved && mounted) {
      setState(() => _editableStops[index] = previous);
    }
  }

  Future<void> _deleteStop(int index) async {
    final stop = _editableStops[index];
    final label = stop.address.isNotEmpty ? stop.address : stop.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stopp ${index + 1} löschen?'),
        content: Text(
          '$label\n\nDer Zustellpunkt wird dauerhaft aus diesem Bezirk entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final removed = _editableStops[index];
    setState(() => _editableStops.removeAt(index));
    final saved = await _saveStops(successMessage: '$label wurde gelöscht.');
    if (!saved && mounted) {
      setState(() => _editableStops.insert(index, removed));
    }
  }

  void _startMoveStop(int index) {
    setState(() {
      _addMode = false;
      _moveStopIndex = index;
    });
  }

  Future<void> _moveStopToMapPosition(LatLng position) async {
    final index = _moveStopIndex;
    if (index == null || index < 0 || index >= _editableStops.length) return;

    final previous = _editableStops[index];
    final moved = TourStop(
      latitude: position.latitude,
      longitude: position.longitude,
      name: previous.name,
      address: previous.address,
      streetName: previous.streetName,
      houseNumber: previous.houseNumber,
      company: previous.company,
      note: previous.note,
      recipients: List<dynamic>.from(previous.recipients),
      isMailbox: previous.isMailbox,
      section: previous.section,
    );

    setState(() {
      _editableStops[index] = moved;
      _moveStopIndex = null;
    });

    final saved = await _saveStops(
      successMessage: 'Position von Stopp ${index + 1} wurde gespeichert.',
    );
    if (!saved && mounted) {
      setState(() => _editableStops[index] = previous);
    }
  }

  Future<void> _reorderStops(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    final previousOrder = List<TourStop>.from(_editableStops);
    setState(() {
      final stop = _editableStops.removeAt(oldIndex);
      _editableStops.insert(newIndex, stop);
    });

    final saved = await _saveStops(
      successMessage: 'Zustellreihenfolge wurde gespeichert.',
    );
    if (!saved && mounted) {
      setState(() {
        _editableStops
          ..clear()
          ..addAll(previousOrder);
      });
    }
  }

  Future<void> _moveStopToPosition(int index) async {
    final controller = TextEditingController(text: '${index + 1}');
    final target = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('An Position verschieben'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aktuell: Stopp ${index + 1}\n'
              'Neue Position zwischen 1 und ${_editableStops.length}:',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Neue Stoppnummer',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                final value = int.tryParse(controller.text.trim());
                if (value != null &&
                    value >= 1 &&
                    value <= _editableStops.length) {
                  Navigator.of(context).pop(value);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 1 || value > _editableStops.length) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Bitte eine Zahl zwischen 1 und ${_editableStops.length} eingeben.',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(context).pop(value);
            },
            child: const Text('Verschieben'),
          ),
        ],
      ),
    );

    if (target == null || !mounted || target == index + 1) return;

    final previousOrder = List<TourStop>.from(_editableStops);
    setState(() {
      final stop = _editableStops.removeAt(index);
      var insertIndex = target - 1;
      if (insertIndex > _editableStops.length) {
        insertIndex = _editableStops.length;
      }
      _editableStops.insert(insertIndex, stop);
    });

    final saved = await _saveStops(
      successMessage: 'Stopp wurde an Position $target verschoben.',
    );
    if (!saved && mounted) {
      setState(() {
        _editableStops
          ..clear()
          ..addAll(previousOrder);
      });
    }
  }

  Future<void> _showMapStopActions(int index) async {
    final stop = _editableStops[index];
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  stop.address.isNotEmpty ? stop.address : stop.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text('Stopp ${index + 1}'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Bearbeiten'),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.open_with_rounded),
                title: const Text('Position verschieben'),
                subtitle: const Text(
                  'Danach neue Position auf der Karte antippen',
                ),
                onTap: () => Navigator.of(context).pop('move'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Löschen',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'edit') {
      await _editStop(index);
    } else if (action == 'move') {
      _startMoveStop(index);
    } else if (action == 'delete') {
      await _deleteStop(index);
    }
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _editorMapController,
          options: MapOptions(
            initialCenter: _editorCenter,
            initialZoom: _editorZoom,
            minZoom: 4,
            maxZoom: 19,
            onPositionChanged: (position, hasGesture) {
              _editorCenter = position.center;
              _editorZoom = position.zoom;
            },
            onTap: (_, point) {
              if (_moveStopIndex != null) {
                _moveStopToMapPosition(point);
              } else if (_addMode) {
                _addStopAt(point);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'de.ramonvidal.tourgo',
            ),
            MarkerLayer(
              markers: List.generate(_editableStops.length, (index) {
                final stop = _editableStops[index];
                return Marker(
                  point: LatLng(stop.latitude, stop.longitude),
                  width: 40,
                  height: 36,
                  child: GestureDetector(
                    onTap: () {
                      if (!_addMode && _moveStopIndex == null) {
                        _showMapStopActions(index);
                      }
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: stop.company.isNotEmpty
                            ? Colors.orange
                            : Colors.white,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: _moveStopIndex == index
                              ? Colors.red
                              : const Color(0xFF1565C0),
                          width: _moveStopIndex == index ? 3 : 1.8,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 3,
                            offset: Offset(0, 1),
                            color: Color(0x33000000),
                          ),
                        ],
                      ),
                      child: Text(
                        stop.houseNumber.isNotEmpty
                            ? stop.houseNumber
                            : '${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: stop.company.isNotEmpty
                              ? Colors.white
                              : const Color(0xFF1565C0),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Material(
              color: (_addMode || _moveStopIndex != null)
                  ? const Color(0xFF1565C0)
                  : Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              elevation: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Icon(
                      _moveStopIndex != null
                          ? Icons.open_with_rounded
                          : _addMode
                          ? Icons.add_location_alt_rounded
                          : Icons.touch_app_rounded,
                      color: (_addMode || _moveStopIndex != null)
                          ? Colors.white
                          : const Color(0xFF1565C0),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _moveStopIndex != null
                            ? 'Stopp ${_moveStopIndex! + 1} verschieben: Tippe auf die neue Position.'
                            : _addMode
                            ? 'Hinzufügen aktiv: Tippe auf die Position des nächsten Zustellpunkts.'
                            : 'Tippe einen Zustellpunkt an, um ihn zu bearbeiten, zu verschieben oder zu löschen.',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: (_addMode || _moveStopIndex != null)
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                    if (_addMode || _moveStopIndex != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _addMode = false;
                          _moveStopIndex = null;
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          _moveStopIndex != null ? 'Abbrechen' : 'Fertig',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_editableStops.isEmpty) {
      return const Center(child: Text('Noch keine Zustellpunkte'));
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      itemCount: _editableStops.length,
      onReorderItem: (oldIndex, newIndex) {
        _reorderStops(oldIndex, newIndex);
      },
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) {
        return Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final stop = _editableStops[index];
        final subtitleParts = <String>['Stopp ${index + 1}'];
        if (stop.company.isNotEmpty) subtitleParts.add(stop.company);
        if (stop.hasSection) subtitleParts.add('Teil ${stop.section}');
        if (stop.isMailbox) subtitleParts.add('Briefkasten');

        return Padding(
          key: ObjectKey(stop),
          padding: const EdgeInsets.only(bottom: 4),
          child: Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: ReorderableDragStartListener(
                index: index,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.drag_handle_rounded),
                ),
              ),
              title: Text(
                stop.address.isNotEmpty ? stop.address : stop.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(subtitleParts.join(' • ')),
              onTap: () => _editStop(index),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _editStop(index);
                  } else if (value == 'position') {
                    _moveStopToPosition(index);
                  } else if (value == 'delete') {
                    _deleteStop(index);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                  PopupMenuItem(
                    value: 'position',
                    child: Text('An Position verschieben'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Löschen')),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zustellpunkte bearbeiten'),
        actions: [
          IconButton(
            tooltip: _mapView ? 'Listenansicht' : 'Kartenansicht',
            onPressed: () {
              setState(() {
                _mapView = !_mapView;
                if (!_mapView) {
                  _addMode = false;
                  _moveStopIndex = null;
                }
              });
            },
            icon: Icon(_mapView ? Icons.view_list_rounded : Icons.map_outlined),
          ),
        ],
      ),
      body: _mapView ? _buildMap() : _buildList(),
      floatingActionButton: _mapView && _moveStopIndex == null
          ? FloatingActionButton.extended(
              onPressed: () {
                setState(() => _addMode = !_addMode);
              },
              icon: Icon(
                _addMode ? Icons.close_rounded : Icons.add_location_alt_rounded,
              ),
              label: Text(_addMode ? 'Abbrechen' : 'Hinzufügen'),
            )
          : null,
    );
  }
}

_EditorAddressParts _editorSplitAddress(String address) {
  if (address.isEmpty) {
    return const _EditorAddressParts(street: '', houseNumber: '');
  }

  final match = RegExp(r'^(.+?)\s+(\d+\s*[a-zA-Z]?(?:[-/]\d+\s*[a-zA-Z]?)?)$')
      .firstMatch(address);

  if (match == null) {
    return _EditorAddressParts(street: address, houseNumber: '');
  }

  return _EditorAddressParts(
    street: (match.group(1) ?? '').trim(),
    houseNumber: (match.group(2) ?? '').replaceAll(RegExp(r'\s+'), '').trim(),
  );
}

class _EditorAddressParts {
  final String street;
  final String houseNumber;

  const _EditorAddressParts({required this.street, required this.houseNumber});
}
