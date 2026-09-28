import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/district.dart';
import '../models/tour_stop.dart';

class LocalDistrictStorage {
  const LocalDistrictStorage();

  static const String _customDistrictsKey = 'custom_districts_v1';

  String _stopsKey(int districtNumber) => 'district_${districtNumber}_stops_v1';

  Future<List<District>> loadCustomDistricts() async {
    final preferences = await SharedPreferences.getInstance();
    final rawJson = preferences.getString(_customDistrictsKey);

    if (rawJson == null || rawJson.isEmpty) {
      return const <District>[];
    }

    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      throw const FormatException(
        'Gespeicherte Bezirke haben ein ungültiges Format.',
      );
    }

    final districts = decoded.map<District>((item) {
      if (item is! Map) {
        throw const FormatException('Ein gespeicherter Bezirk ist ungültig.');
      }

      final map = Map<String, dynamic>.from(item);
      final number = map['number'];
      if (number is! num) {
        throw const FormatException(
          'Ein gespeicherter Bezirk hat keine gültige Nummer.',
        );
      }

      return District(
        number: number.toInt(),
        assetPath: '',
      );
    }).toList();

    districts.sort((a, b) => a.number.compareTo(b.number));
    return districts;
  }

  Future<void> saveCustomDistrict(District district) async {
    final districts = await loadCustomDistricts();

    if (districts.any((item) => item.number == district.number)) {
      throw StateError('Bezirk ${district.number} existiert bereits.');
    }

    final updated = <District>[...districts, district]
      ..sort((a, b) => a.number.compareTo(b.number));

    await _saveCustomDistricts(updated);
  }

  Future<void> _saveCustomDistricts(List<District> districts) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      districts
          .map(
            (district) => <String, dynamic>{
              'number': district.number,
            },
          )
          .toList(),
    );

    final success = await preferences.setString(_customDistrictsKey, encoded);
    if (!success) {
      throw StateError(
        'Die lokalen Bezirksdaten konnten nicht gespeichert werden.',
      );
    }
  }

  Future<void> renameCustomDistrict(
    int oldNumber,
    int newNumber,
  ) async {
    if (oldNumber == newNumber) return;

    final districts = await loadCustomDistricts();
    if (!districts.any((item) => item.number == oldNumber)) {
      throw StateError('Bezirk $oldNumber wurde nicht gefunden.');
    }
    if (districts.any((item) => item.number == newNumber)) {
      throw StateError('Bezirk $newNumber existiert bereits.');
    }

    final preferences = await SharedPreferences.getInstance();
    final oldStops = await loadStops(oldNumber);

    final updated = districts
        .map(
          (district) => district.number == oldNumber
              ? District(number: newNumber, assetPath: '')
              : district,
        )
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));

    await _saveCustomDistricts(updated);

    if (oldStops != null) {
      await saveStops(newNumber, oldStops);
    }

    await preferences.remove(_stopsKey(oldNumber));
  }

  Future<void> deleteCustomDistrict(int districtNumber) async {
    final districts = await loadCustomDistricts();
    final updated = districts
        .where((district) => district.number != districtNumber)
        .toList();

    if (updated.length == districts.length) {
      throw StateError('Bezirk $districtNumber wurde nicht gefunden.');
    }

    await _saveCustomDistricts(updated);

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_stopsKey(districtNumber));
  }

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
