import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tour_stop.dart';

class StoredRouteViaPoint {
  final double latitude;

  final double longitude;

  final int afterStopIndex;

  const StoredRouteViaPoint({
    required this.latitude,

    required this.longitude,

    required this.afterStopIndex,
  });

  LatLng get position => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'latitude': latitude,

    'longitude': longitude,

    'afterStopIndex': afterStopIndex,
  };

  factory StoredRouteViaPoint.fromJson(Map<String, dynamic> json) {
    return StoredRouteViaPoint(
      latitude: (json['latitude'] as num).toDouble(),

      longitude: (json['longitude'] as num).toDouble(),

      afterStopIndex: (json['afterStopIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

class StoredRouteSectionGeometry {
  final int afterStopIndex;

  final List<LatLng> points;

  const StoredRouteSectionGeometry({
    required this.afterStopIndex,

    required this.points,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'afterStopIndex': afterStopIndex,

    'points': points
        .map(
          (point) => <String, dynamic>{
            'latitude': point.latitude,

            'longitude': point.longitude,
          },
        )
        .toList(),
  };

  factory StoredRouteSectionGeometry.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];

    if (rawPoints is! List) {
      throw const FormatException(
        'Gespeicherte Routengeometrie enthält keine gültigen Punkte.',
      );
    }

    final points = rawPoints.map<LatLng>((item) {
      if (item is! Map) {
        throw const FormatException(
          'Ein gespeicherter Geometriepunkt ist ungültig.',
        );
      }

      final map = Map<String, dynamic>.from(item);

      return LatLng(
        (map['latitude'] as num).toDouble(),

        (map['longitude'] as num).toDouble(),
      );
    }).toList();

    return StoredRouteSectionGeometry(
      afterStopIndex: (json['afterStopIndex'] as num).toInt(),

      points: points,
    );
  }
}

class LocalDistrictStorage {
  const LocalDistrictStorage();

  String _stopsKey(int districtNumber) => 'district_${districtNumber}_stops_v1';

  String _routeViaPointsKey(int districtNumber) =>
      'district_${districtNumber}_route_via_points_v1';

  String _routeSectionGeometriesKey(int districtNumber) =>
      'district_${districtNumber}_route_section_geometries_v1';

  Future<List<TourStop>?> loadStops(int districtNumber) async {
    final preferences = await SharedPreferences.getInstance();

    final rawJson = preferences.getString(_stopsKey(districtNumber));

    if (rawJson == null || rawJson.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(rawJson);

    if (decoded is! List) {
      throw const FormatException(
        'Gespeicherte Zustellpunkte haben ein ungültiges Format.',
      );
    }

    return decoded.map<TourStop>((item) {
      if (item is! Map) {
        throw const FormatException(
          'Ein gespeicherter Zustellpunkt ist ungültig.',
        );
      }

      final map = Map<String, dynamic>.from(item);

      return TourStop(
        latitude: (map['latitude'] as num).toDouble(),

        longitude: (map['longitude'] as num).toDouble(),

        name: (map['name'] ?? '').toString(),

        address: (map['address'] ?? '').toString(),

        streetName: (map['streetName'] ?? '').toString(),

        houseNumber: (map['houseNumber'] ?? '').toString(),

        company: (map['company'] ?? '').toString(),

        note: (map['note'] ?? '').toString(),

        recipients: map['recipients'] is List
            ? List<dynamic>.from(map['recipients'] as List)
            : const <dynamic>[],

        isMailbox: map['isMailbox'] == true,

        section: (map['section'] ?? '').toString(),
      );
    }).toList();
  }

  Future<void> saveStops(int districtNumber, List<TourStop> stops) async {
    final preferences = await SharedPreferences.getInstance();

    final encoded = jsonEncode(
      stops.map((stop) {
        return <String, dynamic>{
          'latitude': stop.latitude,

          'longitude': stop.longitude,

          'name': stop.name,

          'address': stop.address,

          'streetName': stop.streetName,

          'houseNumber': stop.houseNumber,

          'company': stop.company,

          'note': stop.note,

          'recipients': stop.recipients,

          'isMailbox': stop.isMailbox,

          'section': stop.section,
        };
      }).toList(),
    );

    final success = await preferences.setString(
      _stopsKey(districtNumber),

      encoded,
    );

    if (!success) {
      throw StateError(
        'Die lokalen Bezirksdaten konnten nicht gespeichert werden.',
      );
    }
  }

  Future<List<StoredRouteViaPoint>> loadRouteViaPoints(
    int districtNumber,
  ) async {
    final preferences = await SharedPreferences.getInstance();

    final rawJson = preferences.getString(_routeViaPointsKey(districtNumber));

    if (rawJson == null || rawJson.isEmpty) {
      return <StoredRouteViaPoint>[];
    }

    final decoded = jsonDecode(rawJson);

    if (decoded is! List) {
      throw const FormatException(
        'Gespeicherte Routenpunkte haben ein ungültiges Format.',
      );
    }

    return decoded.map<StoredRouteViaPoint>((item) {
      if (item is! Map) {
        throw const FormatException(
          'Ein gespeicherter Routenpunkt ist ungültig.',
        );
      }

      final map = Map<String, dynamic>.from(item);

      return StoredRouteViaPoint.fromJson(map);
    }).toList();
  }

  Future<void> saveRouteViaPoints(
    int districtNumber,

    List<StoredRouteViaPoint> points,
  ) async {
    final preferences = await SharedPreferences.getInstance();

    final encoded = jsonEncode(points.map((point) => point.toJson()).toList());

    final success = await preferences.setString(
      _routeViaPointsKey(districtNumber),

      encoded,
    );

    if (!success) {
      throw StateError(
        'Die manuellen Routenpunkte konnten nicht gespeichert werden.',
      );
    }
  }

  Future<void> resetRouteViaPoints(int districtNumber) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_routeViaPointsKey(districtNumber));
  }

  Future<Map<int, List<LatLng>>> loadRouteSectionGeometries(
    int districtNumber,
  ) async {
    final preferences = await SharedPreferences.getInstance();

    final rawJson = preferences.getString(
      _routeSectionGeometriesKey(districtNumber),
    );

    if (rawJson == null || rawJson.isEmpty) {
      return <int, List<LatLng>>{};
    }

    final decoded = jsonDecode(rawJson);

    if (decoded is! List) {
      throw const FormatException(
        'Gespeicherte Routenabschnitte haben ein ungültiges Format.',
      );
    }

    final result = <int, List<LatLng>>{};

    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }

      final geometry = StoredRouteSectionGeometry.fromJson(
        Map<String, dynamic>.from(item),
      );

      if (geometry.points.length >= 2) {
        result[geometry.afterStopIndex] = geometry.points;
      }
    }

    return result;
  }

  Future<void> saveRouteSectionGeometry(
    int districtNumber,

    int afterStopIndex,

    List<LatLng> points,
  ) async {
    if (points.length < 2) {
      throw ArgumentError('Eine Routengeometrie benötigt mindestens 2 Punkte.');
    }

    final geometries = await loadRouteSectionGeometries(districtNumber);

    geometries[afterStopIndex] = List<LatLng>.from(points);

    final encoded = jsonEncode(
      geometries.entries
          .map(
            (entry) => StoredRouteSectionGeometry(
              afterStopIndex: entry.key,

              points: entry.value,
            ).toJson(),
          )
          .toList(),
    );

    final preferences = await SharedPreferences.getInstance();

    final success = await preferences.setString(
      _routeSectionGeometriesKey(districtNumber),

      encoded,
    );

    if (!success) {
      throw StateError(
        'Die korrigierte Routengeometrie konnte nicht gespeichert werden.',
      );
    }
  }

  Future<void> removeRouteSectionGeometry(
    int districtNumber,
    int afterStopIndex,
  ) async {
    final geometries = await loadRouteSectionGeometries(districtNumber);

    if (!geometries.containsKey(afterStopIndex)) {
      return;
    }

    geometries.remove(afterStopIndex);

    final preferences = await SharedPreferences.getInstance();

    if (geometries.isEmpty) {
      final success = await preferences.remove(
        _routeSectionGeometriesKey(districtNumber),
      );

      if (!success) {
        throw StateError(
          'Die korrigierte Routengeometrie konnte nicht gelöscht werden.',
        );
      }
      return;
    }

    final encoded = jsonEncode(
      geometries.entries
          .map(
            (entry) => StoredRouteSectionGeometry(
              afterStopIndex: entry.key,
              points: entry.value,
            ).toJson(),
          )
          .toList(),
    );

    final success = await preferences.setString(
      _routeSectionGeometriesKey(districtNumber),
      encoded,
    );

    if (!success) {
      throw StateError(
        'Die korrigierte Routengeometrie konnte nicht gelöscht werden.',
      );
    }
  }

  Future<void> resetRouteSectionGeometries(int districtNumber) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_routeSectionGeometriesKey(districtNumber));
  }

  Future<void> resetStops(int districtNumber) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_stopsKey(districtNumber));
  }
}
