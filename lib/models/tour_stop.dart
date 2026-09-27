class TourStop {
  final double latitude;
  final double longitude;

  final String name;
  final String address;
  final String streetName;
  final String houseNumber;

  final String company;
  final String note;

  final List<dynamic> recipients;

  final bool isMailbox;
  final String section;

  const TourStop({
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.address,
    required this.streetName,
    required this.houseNumber,
    required this.company,
    required this.note,
    required this.recipients,
    required this.isMailbox,
    required this.section,
  });

  factory TourStop.fromJson(Map<String, dynamic> json) {
    final address = (json['adresse'] ?? '').toString().trim();
    final name = (json['name'] ?? '').toString().trim();

    final lat = json['lat'];
    final lng = json['lng'];

    if (lat is! num || lng is! num) {
      throw const FormatException(
        'Ein Stopp besitzt keine gültigen Koordinaten.',
      );
    }

    final addressParts = _splitAddress(address);

    return TourStop(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      name: name.isNotEmpty ? name : address,
      address: address,
      streetName: addressParts.street,
      houseNumber: addressParts.houseNumber,
      company: (json['firma'] ?? '').toString().trim(),
      note: (json['hinweis'] ?? '').toString().trim(),
      recipients: json['empfaenger'] is List
          ? List<dynamic>.from(json['empfaenger'])
          : const [],
      isMailbox: _readBool(json['briefkasten']),
      section: (json['teil'] ?? '').toString().trim(),
    );
  }

  static _AddressParts _splitAddress(String address) {
    if (address.isEmpty) {
      return const _AddressParts(street: '', houseNumber: '');
    }

    /*
     * Erkennt z. B.:
     *
     * Hauptstraße 17
     * Hauptstraße 17a
     * Hauptstraße 17 A
     * An der Ziegelei 12
     * Todenbüttler Straße 3
     *
     * Der letzte Teil der Adresse wird nur dann als Hausnummer
     * behandelt, wenn er mit einer Zahl beginnt.
     */
    final match = RegExp(r'^(.+?)\s+(\d+\s*[a-zA-Z]?(?:[-/]\d+\s*[a-zA-Z]?)?)$')
        .firstMatch(address);

    if (match == null) {
      return _AddressParts(street: address, houseNumber: '');
    }

    return _AddressParts(
      street: (match.group(1) ?? '').trim(),
      houseNumber: (match.group(2) ?? '').replaceAll(RegExp(r'\s+'), '').trim(),
    );
  }

  static bool _readBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      return normalized == 'true' ||
          normalized == '1' ||
          normalized == 'ja' ||
          normalized == 'yes';
    }

    return false;
  }

  bool get isCompany => company.isNotEmpty;

  bool get hasNote => note.isNotEmpty;

  bool get hasSection => section.isNotEmpty;
}

class _AddressParts {
  final String street;
  final String houseNumber;

  const _AddressParts({required this.street, required this.houseNumber});
}
