// ignore_for_file: avoid_print

import 'dart:convert';

import 'dart:io';

import 'dart:math' as math;

const String inputPath = 'assets/districts/Bezirk_19.json';

const String outputPath = 'assets/districts/Bezirk_19_route_test.json';

const int districtNumber = 19;

const int minimumTestStopCount = 220;

const String osrmBaseUrl = 'https://router.project-osrm.org';

const String userAgent = 'TourGo Route Generator';

/// Bewegungen kleiner als dieser Wert werden bei der

/// Erkennung eines Richtungswechsels ignoriert.

///

/// Damit erzeugen leicht unterschiedliche Projektionen

/// von Häusern auf beiden Straßenseiten nicht sofort

/// einen Richtungswechsel.

const double directionNoiseMeters = 18.0;

/// Ein echter Richtungswechsel muss sich mindestens

/// ungefähr so weit in Gegenrichtung fortsetzen.

const double minimumReversalMeters = 35.0;

Future<void> main() async {
  print('TourGo Route Generator');

  print('======================');

  print('');

  print('Test: Tourrichtung + reihenfolgebewusste Hausanschlüsse');

  print('');

  final inputFile = File(inputPath);

  if (!await inputFile.exists()) {
    stderr.writeln('FEHLER: $inputPath wurde nicht gefunden.');

    exitCode = 1;

    return;
  }

  final dynamic decoded = jsonDecode(await inputFile.readAsString());

  final rawStops = _extractStopList(decoded);

  final allStops = <_Stop>[];

  for (final item in rawStops) {
    if (item is! Map) {
      continue;
    }

    final map = Map<String, dynamic>.from(item);

    final lat = map['lat'];

    final lng = map['lng'];

    if (lat is! num || lng is! num) {
      continue;
    }

    final address = (map['adresse'] ?? '').toString().trim();

    allStops.add(
      _Stop(
        stopNumber: allStops.length + 1,

        latitude: lat.toDouble(),

        longitude: lng.toDouble(),

        address: address,

        streetName: _streetFromAddress(address),
      ),
    );
  }

  print('${allStops.length} gültige Stopps gefunden.');

  if (allStops.length < 2) {
    stderr.writeln('FEHLER: Zu wenige gültige Stopps.');

    exitCode = 1;

    return;
  }

  final allSegments = _buildStreetSegments(allStops);

  if (allSegments.isEmpty) {
    stderr.writeln('FEHLER: Keine Straßenabschnitte erkannt.');

    exitCode = 1;

    return;
  }

  final selectedSegments = <_StreetSegment>[];
  var selectedStopCount = 0;

  for (final segment in allSegments) {
    selectedSegments.add(segment);
    selectedStopCount += segment.stops.length;

    if (selectedStopCount >= minimumTestStopCount) {
      break;
    }
  }

  print('');

  print(
    'Verwende Straßenabschnitte bis mindestens '
    '$minimumTestStopCount Stopps erreicht sind – insgesamt '
    '${selectedSegments.length} Straßenabschnitte:',
  );

  for (var index = 0; index < selectedSegments.length; index++) {
    final segment = selectedSegments[index];

    print(
      '  ${index + 1}. ${segment.streetName} · '
      'Stopps ${segment.stops.first.stopNumber}'
      '–${segment.stops.last.stopNumber} · '
      '${segment.stops.length} Stopps',
    );
  }

  final selectedStops = selectedSegments
      .expand((segment) => segment.stops)
      .toList();

  print('');

  print('Test umfasst ${selectedStops.length} Stopps.');

  print('');

  final routeParts = <_RoutePart>[];

  final connections = <_StopConnection>[];
  final routeMovements = <Map<String, dynamic>>[];

  _RoutePoint? previousRouteEnd;

  for (
    var segmentIndex = 0;

    segmentIndex < selectedSegments.length;

    segmentIndex++
  ) {
    final segment = selectedSegments[segmentIndex];

    print('----------------------------------------');

    print(
      'Abschnitt ${segmentIndex + 1}: '
      '${segment.streetName}',
    );

    print(
      'Stopps ${segment.stops.first.stopNumber}'
      '–${segment.stops.last.stopNumber}',
    );

    print('');

    final snappedStops = <_SnappedStop>[];

    for (final stop in segment.stops) {
      stdout.write(
        '  Stopp ${stop.stopNumber}'
        '${stop.address.isEmpty ? '' : ' · ${stop.address}'} ... ',
      );

      final snapped = await _snapStop(stop);

      snappedStops.add(snapped);

      print(
        '${snapped.roadName.isEmpty ? 'unbekannt' : snapped.roadName}'
        ' · '
        '${snapped.snapDistanceMeters.toStringAsFixed(1)} m',
      );

      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    final normalizedStreet = _normalizeStreet(segment.streetName);

    final matchingSnaps = snappedStops.where((item) {
      return _normalizeStreet(item.roadName) == normalizedStreet;
    }).toList();

    print('');

    print(
      '  Sichere Straßenpunkte: '
      '${matchingSnaps.length}/${segment.stops.length}',
    );

    final axisCandidates = _buildAxisCandidates(
      snappedStops: snappedStops,

      matchingSnaps: matchingSnaps,
    );

    if (axisCandidates.length < 2) {
      stderr.writeln(
        'FEHLER: Für ${segment.streetName} '
        'konnten nicht genügend Straßenpunkte '
        'bestimmt werden.',
      );

      exitCode = 1;

      return;
    }

    final endpoints = _findFarthestPair(axisCandidates);

    print(
      '  Grundachse: '
      'Stopp ${endpoints.$1.stop.stopNumber} '
      '↔ Stopp ${endpoints.$2.stop.stopNumber}',
    );

    final axisRoute = await _routeBetweenPoints(
      _RoutePoint(
        latitude: endpoints.$1.roadLatitude,

        longitude: endpoints.$1.roadLongitude,
      ),

      _RoutePoint(
        latitude: endpoints.$2.roadLatitude,

        longitude: endpoints.$2.roadLongitude,
      ),
    );

    if (axisRoute.points.length < 2) {
      stderr.writeln(
        'FEHLER: Keine brauchbare Straßenachse '
        'für ${segment.streetName}.',
      );

      exitCode = 1;

      return;
    }

    final axis = _RouteAxis(axisRoute.points);

    final projectedStops = <_ProjectedStop>[];

    for (final stop in segment.stops) {
      final projection = axis.project(stop.latitude, stop.longitude);

      projectedStops.add(_ProjectedStop(stop: stop, projection: projection));
    }

    print('');

    print('  Positionen entlang der Straße:');

    for (final item in projectedStops) {
      print(
        '    Stopp ${item.stop.stopNumber}: '
        '${item.projection.progressMeters.toStringAsFixed(1)} m',
      );
    }

    final movement = _buildTourMovement(projectedStops, axis.lengthMeters);

    print('');

    print('  Erkannte Tourbewegung:');

    for (var index = 0; index < movement.length; index++) {
      final point = movement[index];

      final label = switch (point.type) {
        _MovementPointType.start => 'Start',

        _MovementPointType.turn => 'Richtungswechsel',

        _MovementPointType.end => 'Ende',
      };

      print(
        '    $label: '
        '${point.progressMeters.toStringAsFixed(1)} m',
      );
    }

    final tourRoutePoints = _buildRouteFromMovement(axis, movement);

    if (tourRoutePoints.length < 2) {
      stderr.writeln(
        'FEHLER: Tourroute für '
        '${segment.streetName} ist ungültig.',
      );

      exitCode = 1;

      return;
    }

    final streetStart = tourRoutePoints.first;

    final streetEnd = tourRoutePoints.last;

    // Der eingehende Übergang gehört ebenfalls zur tatsächlich gefahrenen
    // Linie dieses Straßenabschnitts. Gerade der erste Stopp einer Straße
    // kann bereits an diesem Übergang liegen, bevor die eigentliche
    // Straßenachse ihren geometrischen Startpunkt erreicht.
    var incomingTransitionPoints = <_RoutePoint>[];

    if (previousRouteEnd != null) {
      final gap = _distanceMeters(
        previousRouteEnd.latitude,

        previousRouteEnd.longitude,

        streetStart.latitude,

        streetStart.longitude,
      );

      if (gap > 2) {
        print('');

        print(
          '  Übergang zur Straße: '
          '${gap.toStringAsFixed(1)} m Luftlinie',
        );

        final transition = await _routeBetweenPoints(
          previousRouteEnd,

          streetStart,
        );

        incomingTransitionPoints = transition.points;

        routeParts.add(
          _RoutePart(
            type: 'transition',

            streetName: '',

            segmentNumber: segmentIndex + 1,

            points: transition.points,

            distanceMeters: transition.distanceMeters,
          ),
        );
      }
    }

    final streetDistance = _polylineLength(tourRoutePoints);

    routeParts.add(
      _RoutePart(
        type: 'street',

        streetName: segment.streetName,

        segmentNumber: segmentIndex + 1,

        points: tourRoutePoints,

        distanceMeters: streetDistance,
      ),
    );

    // Bewegungsabschnitte speichern. Damit weiß Flutter später auch,
    // in welcher Richtung dieser Teil der Straße befahren wird.
    for (
      var movementIndex = 0;
      movementIndex < movement.length - 1;
      movementIndex++
    ) {
      final from = movement[movementIndex].progressMeters;
      final to = movement[movementIndex + 1].progressMeters;
      final movementPoints = axis.slice(from, to);

      routeMovements.add({
        'segmentNumber': segmentIndex + 1,
        'streetName': segment.streetName,
        'movementNumber': movementIndex + 1,
        'direction': to >= from ? 'forward' : 'reverse',
        'fromProgressMeters': from,
        'toProgressMeters': to,
        'distanceMeters': (to - from).abs(),
        'points': movementPoints.map((point) {
          return {'lat': point.latitude, 'lng': point.longitude};
        }).toList(),
      });
    }

    // Hausanschlüsse werden auf die tatsächlich gefahrene Linie projiziert.
    // Dazu zählt auch der eingehende Übergang von der vorherigen Straße.
    // Das ist wichtig für Stopps wie Sondheimer-Au-Str. 6: Der Stopp liegt
    // bereits an der Anfahrt und darf deshalb nicht künstlich an den Anfang
    // der späteren Straßenachse gezogen werden.
    final travelledPoints = <_RoutePoint>[];

    void appendTravelPoints(List<_RoutePoint> points) {
      for (final point in points) {
        if (travelledPoints.isNotEmpty) {
          final gap = _distanceMeters(
            travelledPoints.last.latitude,
            travelledPoints.last.longitude,
            point.latitude,
            point.longitude,
          );

          if (gap < 0.2) {
            continue;
          }
        }

        travelledPoints.add(point);
      }
    }

    appendTravelPoints(incomingTransitionPoints);
    appendTravelPoints(tourRoutePoints);

    final travelledAxis = _RouteAxis(travelledPoints);
    var minimumTravelProgress = 0.0;

    print('');
    print('  Reihenfolgebewusste Hausanschlüsse:');

    for (var stopIndex = 0; stopIndex < segment.stops.length; stopIndex++) {
      final stop = segment.stops[stopIndex];
      final snapped = snappedStops[stopIndex];

      // Die Tourreihenfolge gehört ausschließlich zur Hauptroute. Deshalb
      // führen wir den Fortschritts-Cursor weiterhin mit der geordneten
      // Projektion fort, verwenden ihn aber nicht mehr automatisch für die
      // sichtbare dünne Hausverbindung.
      final orderedProjection = travelledAxis.projectAfter(
        stop.latitude,
        stop.longitude,
        minimumTravelProgress,
      );
      minimumTravelProgress = orderedProjection.progressMeters;

      // Für den Hausanschluss ist der von OSRM ermittelte nächstgelegene
      // Straßenpunkt die beste Information. Das ist besonders wichtig bei
      // Punkten ohne von OSRM gelieferten Straßennamen (z. B. Am Alten
      // Schwimmbad 10 oder Sondheimer-Au-Str. 6). So kann der Anschluss an
      // genau der Straßenstelle enden, die direkt beim Haus liegt, während
      // die dicke Hauptroute weiterhin die gespeicherte Tourreihenfolge zeigt.
      //
      // Meldet OSRM dagegen ausdrücklich einen ANDEREN Straßennamen, nehmen
      // wir nicht blind diesen Snap. Dann bleibt der Anschluss auf der
      // ermittelten Achse der eigentlichen Tourstraße. Dadurch wird z. B. ein
      // Punkt an einer nahen Querstraße nicht fälschlich dort angeschlossen.
      final snappedRoadMatchesStreet =
          _normalizeStreet(snapped.roadName) == normalizedStreet;
      final snappedRoadIsUnknown = snapped.roadName.trim().isEmpty;
      final useSnappedRoadPoint =
          snappedRoadMatchesStreet || snappedRoadIsUnknown;

      final axisProjection = axis.project(stop.latitude, stop.longitude);

      var connectionPoint = useSnappedRoadPoint
          ? _RoutePoint(
              latitude: snapped.roadLatitude,
              longitude: snapped.roadLongitude,
            )
          : axisProjection.point;

      var connectionDistance = useSnappedRoadPoint
          ? snapped.snapDistanceMeters
          : axisProjection.distanceMeters;

      // Mehrfachadressen bleiben eigenständige Stopps. Für Pointweg 8 sind
      // die ersten beiden Zustellpunkte bereits korrekt. Ab dem dritten
      // Zustellpunkt verwenden wir deshalb nicht mehr automatisch den
      // fremd benannten OSRM-Snap (z. B. Ölmühlweg), sondern den geometrisch
      // nächstgelegenen Punkt der tatsächlich gefahrenen Pointweg-Route.
      //
      // Das verändert weder Stoppreihenfolge noch Markerkoordinaten.
      final isLaterPointweg8Stop =
          normalizedStreet == 'pointweg' &&
          _normalizeAddress(stop.address) == 'pointweg8' &&
          _duplicateAddressPosition(segment.stops, stopIndex) >= 3;

      if (isLaterPointweg8Stop) {
        final routeProjection = travelledAxis.project(
          stop.latitude,
          stop.longitude,
        );

        connectionPoint = routeProjection.point;
        connectionDistance = routeProjection.distanceMeters;
      }

      // Bahnhofstraße 22 kommt dreimal als eigenständiger Zustellpunkt vor.
      // Der mittlere Punkt (Stopp 78 / 2 von 3) besitzt bereits den passenden
      // Zugang zur Straße. Die beiden äußeren Zustellpunkte 77 und 79 sollen
      // deshalb denselben Straßen-Zugang benutzen, statt jeweils an weit
      // entfernte Stellen der Bahnhofstraße angeschlossen zu werden.
      //
      // Die Markerkoordinaten und die Reihenfolge 77 -> 78 -> 79 bleiben
      // vollständig unverändert.
      final duplicatePosition = _duplicateAddressPosition(
        segment.stops,
        stopIndex,
      );

      final isBahnhofstrasse22 =
          normalizedStreet == 'bahnhofstr' &&
          _normalizeAddress(stop.address) == 'bahnhofstr22';

      if (isBahnhofstrasse22 &&
          (duplicatePosition == 1 || duplicatePosition == 3)) {
        final referenceIndex = segment.stops.indexWhere(
          (candidate) =>
              _normalizeAddress(candidate.address) == 'bahnhofstr22' &&
              candidate.stopNumber == 78,
        );

        if (referenceIndex >= 0) {
          final referenceSnap = snappedStops[referenceIndex];

          connectionPoint = _RoutePoint(
            latitude: referenceSnap.roadLatitude,
            longitude: referenceSnap.roadLongitude,
          );

          connectionDistance = _distanceMeters(
            stop.latitude,
            stop.longitude,
            connectionPoint.latitude,
            connectionPoint.longitude,
          );
        }
      }

      final connectionProgress = travelledAxis
          .project(connectionPoint.latitude, connectionPoint.longitude)
          .progressMeters;

      final connectionSource = useSnappedRoadPoint
          ? (snappedRoadIsUnknown
                ? ' · direkter Straßensnap (Name unbekannt)'
                : ' · direkter Straßensnap')
          : ' · Straßenachse (fremder Snap: ${snapped.roadName})';

      print(
        '    Stopp ${stop.stopNumber}: '
        '${connectionProgress.toStringAsFixed(1)} m · '
        'Anschluss '
        '${connectionDistance.toStringAsFixed(1)} m'
        '$connectionSource',
      );

      connections.add(
        _StopConnection(
          stop: stop,
          streetName: segment.streetName,
          segmentNumber: segmentIndex + 1,
          roadPoint: connectionPoint,
          distanceMeters: connectionDistance,
        ),
      );
    }

    previousRouteEnd = streetEnd;

    print('');

    print(
      '  Straßenachse: '
      '${axisRoute.points.length} Punkte · '
      '${axis.lengthMeters.toStringAsFixed(0)} m',
    );

    print(
      '  Tourroute: '
      '${tourRoutePoints.length} Punkte · '
      '${streetDistance.toStringAsFixed(0)} m',
    );

    final reversalCount = movement.where((item) {
      return item.type == _MovementPointType.turn;
    }).length;

    print(
      '  Erkannte Richtungswechsel: '
      '$reversalCount',
    );

    print('');
  }

  final combinedMainRoute = _combineRouteParts(routeParts);

  // Zweite, globale Plausibilitätsprüfung der sichtbaren Hausanschlüsse.
  // Erst jetzt ist die komplette tatsächlich gezeichnete Hauptroute bekannt
  // (einschließlich der Übergänge zu den nachfolgenden Straßen). Dadurch
  // können Stopps wie „Am Alten Schwimmbad 10/15“ an einen später
  // vorbeiführenden, geografisch deutlich besseren Routenpunkt angeschlossen
  // werden. Die Tourreihenfolge und routeMovements werden dabei NICHT
  // verändert – korrigiert wird ausschließlich die dünne Hausverbindung.
  final globalMainAxis = _RouteAxis(combinedMainRoute);
  final correctedConnections = <_StopConnection>[];

  print('========================================');
  print('Globale Anschlussprüfung');
  print('========================================');

  for (final connection in connections) {
    final geographicProjection = globalMainAxis.project(
      connection.stop.latitude,
      connection.stop.longitude,
    );

    final currentDistance = connection.distanceMeters;
    final geographicDistance = geographicProjection.distanceMeters;

    final isProtectedPointweg8 =
        _normalizeStreet(connection.streetName) == 'pointweg' &&
        _normalizeAddress(connection.stop.address) == 'pointweg8';

    final isProtectedBahnhofstrasse22 =
        _normalizeStreet(connection.streetName) == 'bahnhofstr' &&
        _normalizeAddress(connection.stop.address) == 'bahnhofstr22';

    final useGlobalFallback =
        !isProtectedPointweg8 &&
        !isProtectedBahnhofstrasse22 &&
        currentDistance > geographicDistance + 30.0 &&
        currentDistance > geographicDistance * 2.5;

    if (useGlobalFallback) {
      print(
        '  Stopp ${connection.stop.stopNumber} · '
        '${connection.stop.address}: '
        '${currentDistance.toStringAsFixed(1)} m → '
        '${geographicDistance.toStringAsFixed(1)} m '
        '· globaler geografischer Fallback',
      );

      correctedConnections.add(
        _StopConnection(
          stop: connection.stop,
          streetName: connection.streetName,
          segmentNumber: connection.segmentNumber,
          roadPoint: geographicProjection.point,
          distanceMeters: geographicDistance,
        ),
      );
    } else {
      correctedConnections.add(connection);
    }
  }

  print('');

  final totalDistance = routeParts.fold<double>(
    0,

    (sum, part) => sum + part.distanceMeters,
  );

  final output = <String, dynamic>{
    'district': districtNumber,

    'type': 'ordered_street_movement_test',

    'segmentCount': selectedSegments.length,

    'startStop': selectedStops.first.stopNumber,

    'endStop': selectedStops.last.stopNumber,

    'stopCount': selectedStops.length,

    'distanceMeters': totalDistance,

    'mainRoute': {
      'type': 'LineString',

      'points': combinedMainRoute.map((point) {
        return {'lat': point.latitude, 'lng': point.longitude};
      }).toList(),
    },

    'routeParts': routeParts.map((part) {
      return {
        'type': part.type,

        'streetName': part.streetName,

        'segmentNumber': part.segmentNumber,

        'distanceMeters': part.distanceMeters,

        'points': part.points.map((point) {
          return {'lat': point.latitude, 'lng': point.longitude};
        }).toList(),
      };
    }).toList(),

    'routeMovements': routeMovements,
    'streetSegments': selectedSegments.asMap().entries.map((entry) {
      final segment = entry.value;

      return {
        'segmentNumber': entry.key + 1,

        'streetName': segment.streetName,

        'startStop': segment.stops.first.stopNumber,

        'endStop': segment.stops.last.stopNumber,

        'stopCount': segment.stops.length,
      };
    }).toList(),

    'stopConnections': correctedConnections.map((connection) {
      return {
        'stopNumber': connection.stop.stopNumber,

        'address': connection.stop.address,

        'streetName': connection.streetName,

        'segmentNumber': connection.segmentNumber,

        'distanceMeters': connection.distanceMeters,

        'roadPoint': {
          'lat': connection.roadPoint.latitude,

          'lng': connection.roadPoint.longitude,
        },

        'stopPoint': {
          'lat': connection.stop.latitude,

          'lng': connection.stop.longitude,
        },

        'points': [
          {
            'lat': connection.roadPoint.latitude,

            'lng': connection.roadPoint.longitude,
          },

          {'lat': connection.stop.latitude, 'lng': connection.stop.longitude},
        ],
      };
    }).toList(),
  };

  final outputFile = File(outputPath);

  await outputFile.parent.create(recursive: true);

  const encoder = JsonEncoder.withIndent('  ');

  await outputFile.writeAsString(encoder.convert(output));

  print('========================================');

  print('FERTIG');

  print('========================================');

  print(
    'Straßenabschnitte: '
    '${selectedSegments.length}',
  );

  print('Stopps: ${selectedStops.length}');

  print(
    'Hauptroutenpunkte: '
    '${combinedMainRoute.length}',
  );

  print(
    'Hausanschlüsse: '
    '${connections.length}',
  );

  print(
    'Gesamtroute: '
    '${(totalDistance / 1000).toStringAsFixed(2)} km',
  );

  print('');

  print('Gespeichert unter:');

  print(outputPath);
}

List<dynamic> _extractStopList(dynamic decoded) {
  if (decoded is List) {
    return decoded;
  }

  if (decoded is Map<String, dynamic> && decoded['points'] is List) {
    return List<dynamic>.from(decoded['points'] as List);
  }

  throw const FormatException('Keine gültige Stoppliste gefunden.');
}

List<_StreetSegment> _buildStreetSegments(List<_Stop> stops) {
  final segments = <_StreetSegment>[];

  String? currentStreet;

  String? currentKey;

  final currentStops = <_Stop>[];

  void finishCurrentSegment() {
    if (currentStreet == null || currentStops.isEmpty) {
      return;
    }

    segments.add(
      _StreetSegment(
        streetName: currentStreet,

        stops: List<_Stop>.from(currentStops),
      ),
    );

    currentStops.clear();
  }

  for (final stop in stops) {
    final street = stop.streetName.trim();

    if (street.isEmpty) {
      if (currentStreet != null) {
        currentStops.add(stop);
      }

      continue;
    }

    final key = _normalizeStreet(street);

    if (currentStreet == null) {
      currentStreet = street;

      currentKey = key;

      currentStops.add(stop);

      continue;
    }

    if (key == currentKey) {
      currentStops.add(stop);

      continue;
    }

    finishCurrentSegment();

    currentStreet = street;

    currentKey = key;

    currentStops.add(stop);
  }

  finishCurrentSegment();

  return segments;
}

String _streetFromAddress(String address) {
  if (address.isEmpty) {
    return '';
  }

  final match = RegExp(r'^(.+?)\s+\d+\s*[a-zA-Z]?(?:[-/]\d+\s*[a-zA-Z]?)?$')
      .firstMatch(address);

  if (match == null) {
    return address.trim();
  }

  return (match.group(1) ?? '').trim();
}

String _normalizeAddress(String value) {
  var result = value
      .trim()
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');

  result = result.replaceAll(RegExp(r'strasse\b'), 'str');
  result = result.replaceAll(RegExp(r'str\.?\b'), 'str');
  result = result.replaceAll(RegExp(r'[^a-z0-9]'), '');

  return result;
}

int _duplicateAddressPosition(List<_Stop> stops, int stopIndex) {
  if (stopIndex < 0 || stopIndex >= stops.length) {
    return 0;
  }

  final target = _normalizeAddress(stops[stopIndex].address);

  if (target.isEmpty) {
    return 0;
  }

  var position = 0;

  for (var index = 0; index <= stopIndex; index++) {
    if (_normalizeAddress(stops[index].address) == target) {
      position++;
    }
  }

  return position;
}

String _normalizeStreet(String value) {
  var result = value
      .trim()
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');

  result = result.replaceAll(RegExp(r'strasse\b'), 'str');

  result = result.replaceAll(RegExp(r'str\\.?\b'), 'str');

  result = result.replaceAll(RegExp(r'[^a-z0-9]'), '');

  return result;
}

List<_SnappedStop> _buildAxisCandidates({
  required List<_SnappedStop> snappedStops,
  required List<_SnappedStop> matchingSnaps,
}) {
  if (matchingSnaps.length >= 2) {
    final result = <_SnappedStop>[...matchingSnaps];

    // OSRM liefert bei einzelnen Häusern manchmal keinen Straßennamen,
    // obwohl der gefundene Straßenpunkt geometrisch korrekt auf der
    // Fortsetzung derselben Straße liegt. Wenn solche namenlosen Punkte
    // am ENDE eines zusammenhängenden Tourabschnitts kommen, dürfen sie
    // die Grundachse verlängern.
    //
    // Wichtig: Wir nehmen bewusst nicht jeden unbekannten Snap auf.
    // Dadurch bleibt z. B. der bereits korrekt funktionierende erste
    // Stopp der Sondheimer-Au-Str. an seiner eingehenden Anfahrt hängen,
    // statt die Straßenachse künstlich in diese Richtung zu verschieben.
    var lastMatchingIndex = -1;

    for (var index = 0; index < snappedStops.length; index++) {
      if (matchingSnaps.contains(snappedStops[index])) {
        lastMatchingIndex = index;
      }
    }

    if (lastMatchingIndex >= 0 && lastMatchingIndex < snappedStops.length - 1) {
      var previousAccepted = snappedStops[lastMatchingIndex];

      for (
        var index = lastMatchingIndex + 1;
        index < snappedStops.length;
        index++
      ) {
        final candidate = snappedStops[index];

        // Ein Haus darf durchaus 20–30 m von der befahrbaren Straße
        // entfernt liegen. Größere Snap-Distanzen sind für eine
        // automatische Achsenerweiterung zu unsicher.
        final isPointwegTrailingContinuation =
            _normalizeStreet(previousAccepted.stop.streetName) == 'pointweg' &&
            candidate.stop.stopNumber >= 123 &&
            candidate.stop.stopNumber <= 126;

        if (candidate.snapDistanceMeters >
            (isPointwegTrailingContinuation ? 50.0 : 35.0)) {
          break;
        }

        final continuationDistance = _distanceMeters(
          previousAccepted.roadLatitude,
          previousAccepted.roadLongitude,
          candidate.roadLatitude,
          candidate.roadLongitude,
        );

        // Die Fortsetzung muss räumlich an den bisherigen Straßenverlauf
        // anschließen. So verhindern wir, dass ein weit entfernter Snap
        // auf einer Nebenstraße die Grundachse übernimmt.
        if (continuationDistance >
            (isPointwegTrailingContinuation ? 220.0 : 160.0)) {
          break;
        }

        result.add(candidate);
        previousAccepted = candidate;
      }
    }

    return result;
  }

  if (snappedStops.length <= 2) {
    return snappedStops;
  }

  if (matchingSnaps.length == 1) {
    final known = matchingSnaps.first;

    _SnappedStop? bestOther;

    var bestDistance = double.infinity;

    for (final candidate in snappedStops) {
      if (identical(candidate, known)) {
        continue;
      }

      final distance = _distanceMeters(
        known.roadLatitude,
        known.roadLongitude,
        candidate.roadLatitude,
        candidate.roadLongitude,
      );

      if (distance < bestDistance) {
        bestDistance = distance;

        bestOther = candidate;
      }
    }

    if (bestOther != null) {
      return [known, bestOther];
    }
  }

  return snappedStops;
}

Future<_SnappedStop> _snapStop(_Stop stop) async {
  final uri = Uri.parse(
    '$osrmBaseUrl/nearest/v1/driving/'
    '${stop.longitude},${stop.latitude}'
    '?number=1',
  );

  final response = await _getJson(uri);

  if (response['code'] != 'Ok') {
    throw HttpException(
      'OSRM Nearest fehlgeschlagen: '
      '${response['code']}',
    );
  }

  final waypoints = response['waypoints'];

  if (waypoints is! List || waypoints.isEmpty) {
    throw const FormatException('Kein Straßenpunkt gefunden.');
  }

  final rawWaypoint = waypoints.first;

  if (rawWaypoint is! Map) {
    throw const FormatException('Ungültiger Straßenpunkt.');
  }

  final waypoint = Map<String, dynamic>.from(rawWaypoint);

  final location = waypoint['location'];

  if (location is! List || location.length < 2) {
    throw const FormatException('Ungültiger Straßenpunkt.');
  }

  final lng = location[0];

  final lat = location[1];

  if (lng is! num || lat is! num) {
    throw const FormatException('Ungültige Koordinaten.');
  }

  final roadLat = lat.toDouble();

  final roadLng = lng.toDouble();

  final rawDistance = waypoint['distance'];

  return _SnappedStop(
    stop: stop,

    roadLatitude: roadLat,

    roadLongitude: roadLng,

    snapDistanceMeters: rawDistance is num
        ? rawDistance.toDouble()
        : _distanceMeters(stop.latitude, stop.longitude, roadLat, roadLng),

    roadName: (waypoint['name'] ?? '').toString().trim(),
  );
}

(_SnappedStop, _SnappedStop) _findFarthestPair(List<_SnappedStop> stops) {
  var first = stops.first;

  var second = stops.last;

  var greatestDistance = -1.0;

  for (var i = 0; i < stops.length; i++) {
    for (var j = i + 1; j < stops.length; j++) {
      final distance = _distanceMeters(
        stops[i].roadLatitude,

        stops[i].roadLongitude,

        stops[j].roadLatitude,

        stops[j].roadLongitude,
      );

      if (distance > greatestDistance) {
        greatestDistance = distance;

        first = stops[i];

        second = stops[j];
      }
    }
  }

  return (first, second);
}

List<_MovementPoint> _buildTourMovement(
  List<_ProjectedStop> stops,

  double axisLength,
) {
  if (stops.isEmpty) {
    return const [];
  }

  if (stops.length == 1) {
    return [
      _MovementPoint(
        progressMeters: stops.first.projection.progressMeters,

        type: _MovementPointType.start,
      ),

      _MovementPoint(
        progressMeters: stops.first.projection.progressMeters,

        type: _MovementPointType.end,
      ),
    ];
  }

  final values = stops.map((item) => item.projection.progressMeters).toList();

  //

  // Kleine Sprünge in Gegenrichtung werden ignoriert.

  //

  // Wir suchen zunächst nach einer stabilen

  // Bewegungsrichtung.

  //

  int direction = 0;

  var anchor = values.first;

  var extreme = values.first;

  final movement = <_MovementPoint>[
    _MovementPoint(
      progressMeters: values.first,

      type: _MovementPointType.start,
    ),
  ];

  for (var index = 1; index < values.length; index++) {
    final value = values[index];

    if (direction == 0) {
      final difference = value - anchor;

      if (difference.abs() >= directionNoiseMeters) {
        direction = difference > 0 ? 1 : -1;

        extreme = value;
      }

      continue;
    }

    if (direction > 0) {
      if (value > extreme) {
        extreme = value;

        continue;
      }

      final reversal = extreme - value;

      if (reversal >= minimumReversalMeters) {
        movement.add(
          _MovementPoint(
            progressMeters: extreme,

            type: _MovementPointType.turn,
          ),
        );

        direction = -1;

        anchor = extreme;

        extreme = value;
      }
    } else {
      if (value < extreme) {
        extreme = value;

        continue;
      }

      final reversal = value - extreme;

      if (reversal >= minimumReversalMeters) {
        movement.add(
          _MovementPoint(
            progressMeters: extreme,

            type: _MovementPointType.turn,
          ),
        );

        direction = 1;

        anchor = extreme;

        extreme = value;
      }
    }
  }

  var finalProgress = values.last;

  //

  // Falls der letzte Stopp nur ein kleiner Ausreißer

  // hinter dem letzten Extrem ist, verwenden wir

  // trotzdem exakt die Position des letzten Stopps.

  //

  finalProgress = finalProgress.clamp(0.0, axisLength);

  movement.add(
    _MovementPoint(progressMeters: finalProgress, type: _MovementPointType.end),
  );

  //

  // Falls Start und Ende nahezu identisch sind,

  // aber die Tour zwischendurch deutlich entlang

  // der Straße gelaufen ist, muss das Extrem als

  // Richtungswechsel erhalten bleiben.

  //

  if (movement.length == 2) {
    final start = movement.first.progressMeters;

    final end = movement.last.progressMeters;

    var minValue = values.first;

    var maxValue = values.first;

    for (final value in values) {
      minValue = math.min(minValue, value);

      maxValue = math.max(maxValue, value);
    }

    final travelledSpan = maxValue - minValue;

    if (travelledSpan >= minimumReversalMeters * 2) {
      final startToMin = (start - minValue).abs();
      final startToMax = (start - maxValue).abs();
      final endToMin = (end - minValue).abs();
      final endToMax = (end - maxValue).abs();

      final minIsRealTurn =
          startToMin >= minimumReversalMeters &&
          endToMin >= minimumReversalMeters;
      final maxIsRealTurn =
          startToMax >= minimumReversalMeters &&
          endToMax >= minimumReversalMeters;

      double? turn;
      if (minIsRealTurn && maxIsRealTurn) {
        final viaMin = startToMin + endToMin;
        final viaMax = startToMax + endToMax;
        turn = viaMax >= viaMin ? maxValue : minValue;
      } else if (minIsRealTurn) {
        turn = minValue;
      } else if (maxIsRealTurn) {
        turn = maxValue;
      }

      if (turn != null) {
        movement.insert(
          1,
          _MovementPoint(progressMeters: turn, type: _MovementPointType.turn),
        );
      }
    }
  }

  return _removeRedundantMovement(movement);
}

List<_MovementPoint> _removeRedundantMovement(List<_MovementPoint> input) {
  if (input.length <= 2) {
    return input;
  }

  final result = <_MovementPoint>[];

  for (final point in input) {
    if (result.isNotEmpty) {
      final distance = (result.last.progressMeters - point.progressMeters)
          .abs();

      if (distance < 1) {
        if (point.type == _MovementPointType.end) {
          result[result.length - 1] = point;
        }

        continue;
      }
    }

    result.add(point);
  }

  return result;
}

List<_RoutePoint> _buildRouteFromMovement(
  _RouteAxis axis,

  List<_MovementPoint> movement,
) {
  if (movement.length < 2) {
    return const [];
  }

  final result = <_RoutePoint>[];

  for (var index = 0; index < movement.length - 1; index++) {
    final from = movement[index].progressMeters;

    final to = movement[index + 1].progressMeters;

    final slice = axis.slice(from, to);

    for (final point in slice) {
      if (result.isNotEmpty) {
        final distance = _distanceMeters(
          result.last.latitude,

          result.last.longitude,

          point.latitude,

          point.longitude,
        );

        if (distance < 0.2) {
          continue;
        }
      }

      result.add(point);
    }
  }

  return result;
}

Future<_RouteResult> _routeBetweenPoints(
  _RoutePoint first,

  _RoutePoint second,
) async {
  final coordinates =
      '${first.longitude},${first.latitude};'
      '${second.longitude},${second.latitude}';

  final uri = Uri.parse(
    '$osrmBaseUrl/route/v1/driving/'
    '$coordinates'
    '?overview=full'
    '&geometries=geojson'
    '&steps=false'
    '&alternatives=false',
  );

  final response = await _getJson(uri);

  if (response['code'] != 'Ok') {
    throw HttpException(
      'OSRM Route fehlgeschlagen: '
      '${response['code']}',
    );
  }

  final routes = response['routes'];

  if (routes is! List || routes.isEmpty) {
    throw const FormatException('Keine Route erhalten.');
  }

  final rawRoute = routes.first;

  if (rawRoute is! Map) {
    throw const FormatException('Ungültige Route.');
  }

  final route = Map<String, dynamic>.from(rawRoute);

  final rawGeometry = route['geometry'];

  if (rawGeometry is! Map) {
    throw const FormatException('Keine Routengeometrie erhalten.');
  }

  final geometry = Map<String, dynamic>.from(rawGeometry);

  final coordinatesList = geometry['coordinates'];

  if (coordinatesList is! List) {
    throw const FormatException('Keine Routengeometrie erhalten.');
  }

  final points = <_RoutePoint>[];

  for (final coordinate in coordinatesList) {
    if (coordinate is! List || coordinate.length < 2) {
      continue;
    }

    final lng = coordinate[0];

    final lat = coordinate[1];

    if (lng is! num || lat is! num) {
      continue;
    }

    points.add(
      _RoutePoint(latitude: lat.toDouble(), longitude: lng.toDouble()),
    );
  }

  if (points.length < 2) {
    throw const FormatException('Route enthält zu wenige Punkte.');
  }

  return _RouteResult(
    points: points,

    distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0,
  );
}

List<_RoutePoint> _combineRouteParts(List<_RoutePart> parts) {
  final result = <_RoutePoint>[];

  for (final part in parts) {
    for (final point in part.points) {
      if (result.isNotEmpty) {
        final previous = result.last;

        final distance = _distanceMeters(
          previous.latitude,

          previous.longitude,

          point.latitude,

          point.longitude,
        );

        if (distance < 0.2) {
          continue;
        }
      }

      result.add(point);
    }
  }

  return result;
}

double _polylineLength(List<_RoutePoint> points) {
  if (points.length < 2) {
    return 0;
  }

  var result = 0.0;

  for (var index = 0; index < points.length - 1; index++) {
    result += _distanceMeters(
      points[index].latitude,

      points[index].longitude,

      points[index + 1].latitude,

      points[index + 1].longitude,
    );
  }

  return result;
}

Future<Map<String, dynamic>> _getJson(Uri uri) async {
  final client = HttpClient();

  try {
    final request = await client.getUrl(uri);

    request.headers.set(HttpHeaders.userAgentHeader, userAgent);

    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final response = await request.close();

    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $body', uri: uri);
    }

    final dynamic decoded = jsonDecode(body);

    if (decoded is! Map) {
      throw const FormatException('Ungültige Serverantwort.');
    }

    return Map<String, dynamic>.from(decoded);
  } finally {
    client.close(force: true);
  }
}

double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0;

  final phi1 = _toRadians(lat1);

  final phi2 = _toRadians(lat2);

  final deltaPhi = _toRadians(lat2 - lat1);

  final deltaLambda = _toRadians(lon2 - lon1);

  final a =
      math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
      math.cos(phi1) *
          math.cos(phi2) *
          math.sin(deltaLambda / 2) *
          math.sin(deltaLambda / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return earthRadius * c;
}

double _toRadians(double degrees) {
  return degrees * math.pi / 180;
}

class _RouteAxis {
  final List<_RoutePoint> points;

  late final List<double> _progress;

  late final double lengthMeters;

  _RouteAxis(this.points) {
    if (points.length < 2) {
      throw ArgumentError(
        'Eine Straßenachse benötigt '
        'mindestens zwei Punkte.',
      );
    }

    _progress = List<double>.filled(points.length, 0);

    var total = 0.0;

    for (var index = 1; index < points.length; index++) {
      total += _distanceMeters(
        points[index - 1].latitude,

        points[index - 1].longitude,

        points[index].latitude,

        points[index].longitude,
      );

      _progress[index] = total;
    }

    lengthMeters = total;
  }

  _AxisProjection project(double latitude, double longitude) {
    _RoutePoint? bestPoint;

    var bestDistance = double.infinity;

    var bestProgress = 0.0;

    for (var index = 0; index < points.length - 1; index++) {
      final projection = _projectOnSegment(
        latitude,

        longitude,

        points[index],

        points[index + 1],
      );

      final distance = _distanceMeters(
        latitude,

        longitude,

        projection.point.latitude,

        projection.point.longitude,
      );

      if (distance < bestDistance) {
        bestDistance = distance;

        bestPoint = projection.point;

        final segmentLength = _progress[index + 1] - _progress[index];

        bestProgress = _progress[index] + segmentLength * projection.factor;
      }
    }

    if (bestPoint == null) {
      throw const FormatException(
        'Keine Projektion auf '
        'Straßenachse möglich.',
      );
    }

    return _AxisProjection(
      point: bestPoint,

      progressMeters: bestProgress,

      distanceMeters: bestDistance,
    );
  }

  _AxisProjection projectAfter(
    double latitude,
    double longitude,
    double minimumProgressMeters,
  ) {
    final minimum = minimumProgressMeters.clamp(0.0, lengthMeters);
    _RoutePoint? bestPoint;
    var bestDistance = double.infinity;
    var bestProgress = minimum;

    for (var index = 0; index < points.length - 1; index++) {
      final segmentStart = _progress[index];
      final segmentEnd = _progress[index + 1];
      if (segmentEnd < minimum) continue;

      final projection = _projectOnSegment(
        latitude,
        longitude,
        points[index],
        points[index + 1],
      );
      final segmentLength = segmentEnd - segmentStart;
      var factor = projection.factor;

      if (segmentLength > 0 && segmentStart < minimum) {
        final minimumFactor = (minimum - segmentStart) / segmentLength;
        if (factor < minimumFactor) {
          factor = minimumFactor.clamp(0.0, 1.0);
        }
      }

      final candidatePoint = _interpolatePoint(
        points[index],
        points[index + 1],
        factor,
      );
      final candidateProgress = segmentStart + segmentLength * factor;
      final distance = _distanceMeters(
        latitude,
        longitude,
        candidatePoint.latitude,
        candidatePoint.longitude,
      );

      final isBetterDistance = distance < bestDistance - 0.25;
      final isSameDistanceButEarlier =
          (distance - bestDistance).abs() <= 0.25 &&
          candidateProgress < bestProgress;

      if (isBetterDistance || isSameDistanceButEarlier) {
        bestDistance = distance;
        bestPoint = candidatePoint;
        bestProgress = candidateProgress;
      }
    }

    if (bestPoint == null) {
      final fallbackPoint = pointAt(minimum);
      return _AxisProjection(
        point: fallbackPoint,
        progressMeters: minimum,
        distanceMeters: _distanceMeters(
          latitude,
          longitude,
          fallbackPoint.latitude,
          fallbackPoint.longitude,
        ),
      );
    }

    return _AxisProjection(
      point: bestPoint,
      progressMeters: bestProgress,
      distanceMeters: bestDistance,
    );
  }

  List<_RoutePoint> slice(double fromMeters, double toMeters) {
    final from = fromMeters.clamp(0.0, lengthMeters);

    final to = toMeters.clamp(0.0, lengthMeters);

    if ((from - to).abs() < 0.1) {
      return [pointAt(from), pointAt(to)];
    }

    if (from < to) {
      return _sliceForward(from, to);
    }

    return _sliceForward(to, from).reversed.toList();
  }

  List<_RoutePoint> _sliceForward(double from, double to) {
    final result = <_RoutePoint>[pointAt(from)];

    for (var index = 1; index < points.length - 1; index++) {
      final progress = _progress[index];

      if (progress > from && progress < to) {
        result.add(points[index]);
      }
    }

    result.add(pointAt(to));

    return result;
  }

  _RoutePoint pointAt(double meters) {
    final target = meters.clamp(0.0, lengthMeters);

    if (target <= 0) {
      return points.first;
    }

    if (target >= lengthMeters) {
      return points.last;
    }

    for (var index = 0; index < points.length - 1; index++) {
      final startProgress = _progress[index];

      final endProgress = _progress[index + 1];

      if (target < startProgress || target > endProgress) {
        continue;
      }

      final length = endProgress - startProgress;

      if (length <= 0) {
        return points[index];
      }

      final factor = (target - startProgress) / length;

      return _interpolatePoint(points[index], points[index + 1], factor);
    }

    return points.last;
  }
}

_SegmentProjection _projectOnSegment(
  double latitude,

  double longitude,

  _RoutePoint start,

  _RoutePoint end,
) {
  final referenceLatitude = latitude * math.pi / 180;

  const metersPerDegreeLat = 111320.0;

  final metersPerDegreeLng = 111320.0 * math.cos(referenceLatitude);

  final px = longitude * metersPerDegreeLng;

  final py = latitude * metersPerDegreeLat;

  final ax = start.longitude * metersPerDegreeLng;

  final ay = start.latitude * metersPerDegreeLat;

  final bx = end.longitude * metersPerDegreeLng;

  final by = end.latitude * metersPerDegreeLat;

  final abX = bx - ax;

  final abY = by - ay;

  final abSquared = abX * abX + abY * abY;

  if (abSquared == 0) {
    return _SegmentProjection(point: start, factor: 0);
  }

  var factor = ((px - ax) * abX + (py - ay) * abY) / abSquared;

  factor = factor.clamp(0.0, 1.0);

  final nearestX = ax + factor * abX;

  final nearestY = ay + factor * abY;

  return _SegmentProjection(
    point: _RoutePoint(
      latitude: nearestY / metersPerDegreeLat,

      longitude: nearestX / metersPerDegreeLng,
    ),

    factor: factor,
  );
}

_RoutePoint _interpolatePoint(
  _RoutePoint first,

  _RoutePoint second,

  double factor,
) {
  return _RoutePoint(
    latitude: first.latitude + (second.latitude - first.latitude) * factor,

    longitude: first.longitude + (second.longitude - first.longitude) * factor,
  );
}

class _Stop {
  final int stopNumber;

  final double latitude;

  final double longitude;

  final String address;

  final String streetName;

  const _Stop({
    required this.stopNumber,

    required this.latitude,

    required this.longitude,

    required this.address,

    required this.streetName,
  });
}

class _StreetSegment {
  final String streetName;

  final List<_Stop> stops;

  const _StreetSegment({required this.streetName, required this.stops});
}

class _SnappedStop {
  final _Stop stop;

  final double roadLatitude;

  final double roadLongitude;

  final double snapDistanceMeters;

  final String roadName;

  const _SnappedStop({
    required this.stop,

    required this.roadLatitude,

    required this.roadLongitude,

    required this.snapDistanceMeters,

    required this.roadName,
  });
}

class _RoutePoint {
  final double latitude;

  final double longitude;

  const _RoutePoint({required this.latitude, required this.longitude});
}

class _RouteResult {
  final List<_RoutePoint> points;

  final double distanceMeters;

  const _RouteResult({required this.points, required this.distanceMeters});
}

class _RoutePart {
  final String type;

  final String streetName;

  final int segmentNumber;

  final List<_RoutePoint> points;

  final double distanceMeters;

  const _RoutePart({
    required this.type,

    required this.streetName,

    required this.segmentNumber,

    required this.points,

    required this.distanceMeters,
  });
}

class _StopConnection {
  final _Stop stop;

  final String streetName;

  final int segmentNumber;

  final _RoutePoint roadPoint;

  final double distanceMeters;

  const _StopConnection({
    required this.stop,

    required this.streetName,

    required this.segmentNumber,

    required this.roadPoint,

    required this.distanceMeters,
  });
}

class _ProjectedStop {
  final _Stop stop;

  final _AxisProjection projection;

  const _ProjectedStop({required this.stop, required this.projection});
}

class _AxisProjection {
  final _RoutePoint point;

  final double progressMeters;

  final double distanceMeters;

  const _AxisProjection({
    required this.point,

    required this.progressMeters,

    required this.distanceMeters,
  });
}

class _SegmentProjection {
  final _RoutePoint point;

  final double factor;

  const _SegmentProjection({required this.point, required this.factor});
}

enum _MovementPointType { start, turn, end }

class _MovementPoint {
  final double progressMeters;

  final _MovementPointType type;

  const _MovementPoint({required this.progressMeters, required this.type});
}
