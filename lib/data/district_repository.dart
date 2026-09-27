import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/district.dart';
import '../models/tour_stop.dart';

class DistrictRepository {
  const DistrictRepository();

  static const List<District> districts = [
    District(number: 17, assetPath: 'assets/districts/Bezirk_17.json'),
    District(number: 19, assetPath: 'assets/districts/Bezirk_19.json'),
    District(number: 21, assetPath: 'assets/districts/Bezirk_21.json'),
    District(number: 23, assetPath: 'assets/districts/Bezirk_23.json'),
  ];

  Future<List<TourStop>> loadDistrict(District district) async {
    final jsonString = await rootBundle.loadString(district.assetPath);

    final dynamic decoded = jsonDecode(jsonString);

    final List<dynamic> stopList;

    // Format 1:
    // [
    //   { "lat": ..., "lng": ..., ... },
    //   ...
    // ]
    if (decoded is List) {
      stopList = decoded;
    }
    // Format 2:
    // {
    //   "points": [
    //     { "lat": ..., "lng": ..., ... },
    //     ...
    //   ],
    //   "notes": []
    // }
    else if (decoded is Map<String, dynamic> && decoded['points'] is List) {
      stopList = List<dynamic>.from(decoded['points'] as List);
    } else {
      throw FormatException(
        '${district.name} enthält keine gültige Stoppliste.',
      );
    }

    final stops = <TourStop>[];

    for (final item in stopList) {
      if (item is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(item);

      final lat = map['lat'];
      final lng = map['lng'];

      // Ungültige Einträge ohne Koordinaten werden übersprungen,
      // statt den kompletten Bezirk unbrauchbar zu machen.
      if (lat is! num || lng is! num) {
        continue;
      }

      stops.add(TourStop.fromJson(map));
    }

    if (stops.isEmpty) {
      throw FormatException('${district.name} enthält keine gültigen Stopps.');
    }

    return stops;
  }
}
