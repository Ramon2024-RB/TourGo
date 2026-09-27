import '../utils/address_normalizer.dart';
import 'tour_stop.dart';

class StreetSegment {
  final String streetName;
  final int segmentNumber;
  final int startStopIndex;
  final int endStopIndex;
  final List<TourStop> stops;

  const StreetSegment({
    required this.streetName,
    required this.segmentNumber,
    required this.startStopIndex,
    required this.endStopIndex,
    required this.stops,
  });

  int get startStopNumber => startStopIndex + 1;

  int get endStopNumber => endStopIndex + 1;

  int get stopCount => stops.length;

  String get stopRange {
    if (startStopNumber == endStopNumber) {
      return 'Stopp $startStopNumber';
    }

    return 'Stopps $startStopNumber–$endStopNumber';
  }

  String get houseNumbers {
    return stops
        .asMap()
        .entries
        .map((entry) {
          final stop = entry.value;

          if (stop.houseNumber.isEmpty) {
            return '';
          }

          final duplicateInfo = duplicatePositionForStop(entry.key);

          if (duplicateInfo == null) {
            return stop.houseNumber;
          }

          return '${stop.houseNumber} '
              '(${duplicateInfo.position}/${duplicateInfo.total})';
        })
        .where((value) => value.isNotEmpty)
        .join(' → ');
  }

  DuplicateStopPosition? duplicatePositionForStop(int localStopIndex) {
    if (localStopIndex < 0 || localStopIndex >= stops.length) {
      return null;
    }

    final selectedStop = stops[localStopIndex];

    if (selectedStop.address.isEmpty) {
      return null;
    }

    final normalizedAddress = AddressNormalizer.normalize(selectedStop.address);

    final matchingIndexes = <int>[];

    for (var index = 0; index < stops.length; index++) {
      final candidate = stops[index];

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

    final position = matchingIndexes.indexOf(localStopIndex) + 1;

    if (position <= 0) {
      return null;
    }

    return DuplicateStopPosition(
      position: position,
      total: matchingIndexes.length,
    );
  }
}

class DuplicateStopPosition {
  final int position;
  final int total;

  const DuplicateStopPosition({required this.position, required this.total});
}
