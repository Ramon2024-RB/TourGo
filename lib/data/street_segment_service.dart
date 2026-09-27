import '../models/street_segment.dart';
import '../models/tour_stop.dart';
import '../utils/address_normalizer.dart';

class StreetSegmentService {
  const StreetSegmentService();

  List<StreetSegment> buildSegments(List<TourStop> stops) {
    if (stops.isEmpty) {
      return const [];
    }

    final segments = <StreetSegment>[];

    String? currentStreet;
    int? currentStartIndex;
    final currentStops = <TourStop>[];

    for (var index = 0; index < stops.length; index++) {
      final stop = stops[index];
      final street = stop.streetName.trim();

      /*
       * Stopps ohne erkennbaren Straßennamen werden nicht als
       * eigene Straße behandelt.
       *
       * Sie unterbrechen den aktuell laufenden Straßenabschnitt
       * ebenfalls nicht automatisch.
       */
      if (street.isEmpty) {
        if (currentStreet != null) {
          currentStops.add(stop);
        }

        continue;
      }

      if (currentStreet == null) {
        currentStreet = street;
        currentStartIndex = index;
        currentStops.add(stop);
        continue;
      }

      if (AddressNormalizer.equals(currentStreet, street)) {
        currentStops.add(stop);
        continue;
      }

      _addSegment(
        segments: segments,
        streetName: currentStreet,
        startIndex: currentStartIndex!,
        endIndex: index - 1,
        stops: currentStops,
      );

      currentStreet = street;
      currentStartIndex = index;

      currentStops
        ..clear()
        ..add(stop);
    }

    if (currentStreet != null &&
        currentStartIndex != null &&
        currentStops.isNotEmpty) {
      _addSegment(
        segments: segments,
        streetName: currentStreet,
        startIndex: currentStartIndex,
        endIndex: stops.length - 1,
        stops: currentStops,
      );
    }

    return _numberSegments(segments);
  }

  void _addSegment({
    required List<StreetSegment> segments,
    required String streetName,
    required int startIndex,
    required int endIndex,
    required List<TourStop> stops,
  }) {
    segments.add(
      StreetSegment(
        streetName: streetName,
        segmentNumber: 1,
        startStopIndex: startIndex,
        endStopIndex: endIndex,
        stops: List<TourStop>.from(stops),
      ),
    );
  }

  List<StreetSegment> _numberSegments(List<StreetSegment> segments) {
    final counters = <String, int>{};

    return segments.map((segment) {
      final key = AddressNormalizer.normalize(segment.streetName);

      final nextNumber = (counters[key] ?? 0) + 1;

      counters[key] = nextNumber;

      return StreetSegment(
        streetName: segment.streetName,
        segmentNumber: nextNumber,
        startStopIndex: segment.startStopIndex,
        endStopIndex: segment.endStopIndex,
        stops: segment.stops,
      );
    }).toList();
  }
}
