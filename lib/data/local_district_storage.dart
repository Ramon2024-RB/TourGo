import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tour_stop.dart';

class LocalDistrictStorage {
  const LocalDistrictStorage();

  String _stopsKey(int districtNumber) => 'district_${districtNumber}_stops_v1';

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

  Future<void> resetStops(int districtNumber) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_stopsKey(districtNumber));
  }
}
