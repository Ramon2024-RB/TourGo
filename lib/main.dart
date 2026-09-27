import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:latlong2/latlong.dart';

import 'data/district_repository.dart';

import 'data/street_segment_service.dart';

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

  final MapController _mapController = MapController();

  late final Future<List<TourStop>> _stopsFuture;

  List<LatLng> _testRoutePoints = const [];

  List<List<LatLng>> _testStopConnections = const [];

  bool _initialFitDone = false;

  List<TourStop> _loadedStops = const [];

  List<StreetSegment> _segments = const [];

  StreetSegment? _selectedSegment;

  /// Globaler Index innerhalb des gesamten Bezirks.

  int? _selectedStopIndex;

  @override
  void initState() {
    super.initState();

    _stopsFuture = _repository.loadDistrict(widget.district);
    _loadTestRoute();
  }

  Future<void> _loadTestRoute() async {
    if (widget.district.number != 19) {
      return;
    }

    try {
      final jsonString = await rootBundle.loadString(
        'assets/districts/Bezirk_19_route_test.json',
      );

      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is! Map) {
        throw const FormatException('Routendatei ist kein JSON-Objekt.');
      }

      final routeData = Map<String, dynamic>.from(decoded);
      final mainRoute = routeData['mainRoute'];

      if (mainRoute is! Map) {
        throw const FormatException('mainRoute fehlt in der Routendatei.');
      }

      final mainRouteMap = Map<String, dynamic>.from(mainRoute);
      final rawRoutePoints = mainRouteMap['points'];

      if (rawRoutePoints is! List) {
        throw const FormatException('mainRoute.points fehlt.');
      }

      final routePoints = <LatLng>[];

      for (final item in rawRoutePoints) {
        if (item is! Map) {
          continue;
        }

        final point = Map<String, dynamic>.from(item);
        final lat = point['lat'];
        final lng = point['lng'];

        if (lat is num && lng is num) {
          routePoints.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }

      final connections = <List<LatLng>>[];
      final rawConnections = routeData['stopConnections'];

      if (rawConnections is List) {
        for (final rawConnection in rawConnections) {
          if (rawConnection is! Map) {
            continue;
          }

          final connection = Map<String, dynamic>.from(rawConnection);
          final rawPoints = connection['points'];

          if (rawPoints is! List) {
            continue;
          }

          final connectionPoints = <LatLng>[];

          for (final rawPoint in rawPoints) {
            if (rawPoint is! Map) {
              continue;
            }

            final point = Map<String, dynamic>.from(rawPoint);
            final lat = point['lat'];
            final lng = point['lng'];

            if (lat is num && lng is num) {
              connectionPoints.add(LatLng(lat.toDouble(), lng.toDouble()));
            }
          }

          if (connectionPoints.length >= 2) {
            connections.add(connectionPoints);
          }
        }
      }

      if (routePoints.length < 2) {
        throw const FormatException('Hauptroute enthält zu wenige Punkte.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _testRoutePoints = routePoints;
        _testStopConnections = connections;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _testRoutePoints = const [];
        _testStopConnections = const [];
      });
    }
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
                ),

                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',

                    userAgentPackageName: 'de.ramonvidal.tourgo',
                  ),

                  if (_testStopConnections.isNotEmpty) ...[
                    PolylineLayer(
                      polylines: _testStopConnections
                          .map(
                            (points) => Polyline(
                              points: points,
                              strokeWidth: 5.5,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          )
                          .toList(),
                    ),
                    PolylineLayer(
                      polylines: _testStopConnections
                          .map(
                            (points) => Polyline(
                              points: points,
                              strokeWidth: 3.5,
                              color: const Color(0xFF1976D2),
                            ),
                          )
                          .toList(),
                    ),
                  ],

                  if (_testRoutePoints.length > 1) ...[
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _testRoutePoints,
                          strokeWidth: 9,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ],
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _testRoutePoints,
                          strokeWidth: 5.5,
                          color: const Color(0xFF1565C0),
                        ),
                      ],
                    ),
                  ],

                  MarkerLayer(
                    markers: List.generate(stops.length, (index) {
                      final stop = stops[index];

                      final inSelectedSegment = _isStopInSelectedSegment(index);

                      final isSelectedStop = _selectedStopIndex == index;

                      final dimmed =
                          selectedSegment != null && !inSelectedSegment;

                      final duplicateInfo = _duplicateInfoForGlobalStop(index);

                      return Marker(
                        point: LatLng(stop.latitude, stop.longitude),

                        width: isSelectedStop
                            ? 46
                            : inSelectedSegment
                            ? 42
                            : 38,

                        height: isSelectedStop
                            ? 42
                            : inSelectedSegment
                            ? 38
                            : 34,

                        child: Opacity(
                          opacity: dimmed ? 0.15 : 1,

                          child: GestureDetector(
                            onTap: () {
                              _selectStop(index);

                              _showStop(stop, index + 1);
                            },

                            child: _StopMarker(
                              stop: stop,

                              stopNumber: index + 1,

                              duplicateInfo: duplicateInfo,

                              selected: inSelectedSegment,

                              target: isSelectedStop,
                            ),
                          ),
                        ),
                      );
                    }),
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

                  child: Material(
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
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showStop(TourStop stop, int stopNumber) {
    showModalBottomSheet<void>(
      context: context,

      showDragHandle: true,

      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),

            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Stopp $stopNumber',

                        style: TextStyle(
                          fontSize: 14,

                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),

                    if (stop.hasSection)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,

                          vertical: 5,
                        ),

                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,

                          borderRadius: BorderRadius.circular(20),
                        ),

                        child: Text(
                          'Teil ${stop.section}',

                          style: const TextStyle(
                            fontSize: 12,

                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 5),

                Text(
                  stop.name,

                  style: const TextStyle(
                    fontSize: 23,

                    fontWeight: FontWeight.w800,
                  ),
                ),

                if (stop.isMailbox) ...[
                  const SizedBox(height: 14),

                  const Row(
                    children: [
                      Icon(Icons.markunread_mailbox_rounded, size: 20),

                      SizedBox(width: 8),

                      Text(
                        'Briefkasten',

                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],

                if (stop.company.isNotEmpty) ...[
                  const SizedBox(height: 14),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const Icon(Icons.business_rounded, size: 20),

                      const SizedBox(width: 8),

                      Expanded(child: Text(stop.company)),
                    ],
                  ),
                ],

                if (stop.note.isNotEmpty) ...[
                  const SizedBox(height: 14),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const Icon(Icons.info_outline_rounded, size: 20),

                      const SizedBox(width: 8),

                      Expanded(child: Text(stop.note)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
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

  const _SelectedSegmentCard({
    required this.segment,

    required this.previous,

    required this.next,

    required this.selectedStopIndex,

    required this.selectedStop,

    required this.duplicateInfo,

    required this.onClose,

    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,

      borderRadius: BorderRadius.circular(20),

      elevation: 8,

      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),

        child: Column(
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
                        'Abschnitt '
                        '${segment.segmentNumber} • '
                        '${segment.stopRange}',

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

            if (selectedStop != null && selectedStopIndex != null) ...[
              const SizedBox(height: 10),

              Container(
                width: double.infinity,

                padding: const EdgeInsets.symmetric(
                  horizontal: 12,

                  vertical: 10,
                ),

                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,

                      color: Theme.of(context).colorScheme.primary,
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: Text(
                        _selectedStopText(),

                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (segment.houseNumbers.isNotEmpty) ...[
              const SizedBox(height: 10),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,

                child: Text(
                  segment.houseNumbers,

                  style: const TextStyle(
                    fontSize: 15,

                    fontWeight: FontWeight.w700,
                  ),
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
        ),
      ),
    );
  }

  String _selectedStopText() {
    final stop = selectedStop!;

    var result = stop.address.isNotEmpty ? stop.address : stop.name;

    if (duplicateInfo != null) {
      result += ' · ${duplicateInfo!.position}/${duplicateInfo!.total}';
    }

    result += ' · Stopp ${selectedStopIndex! + 1}';

    return result;
  }
}

class _StopMarker extends StatelessWidget {
  final TourStop stop;

  final int stopNumber;

  final DuplicateStopPosition? duplicateInfo;

  final bool selected;

  final bool target;

  const _StopMarker({
    required this.stop,

    required this.stopNumber,

    required this.duplicateInfo,

    this.selected = false,

    this.target = false,
  });

  @override
  Widget build(BuildContext context) {
    final houseNumber = stop.houseNumber.isNotEmpty ? stop.houseNumber : '•';

    final secondaryParts = <String>[];

    if (duplicateInfo != null) {
      secondaryParts.add('${duplicateInfo!.position}/${duplicateInfo!.total}');
    }

    if (stop.hasSection) {
      secondaryParts.add(stop.section);
    }

    secondaryParts.add('$stopNumber');

    final secondaryText = secondaryParts.join(' · ');

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
                Text(
                  houseNumber,

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
