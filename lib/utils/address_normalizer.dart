class AddressNormalizer {
  const AddressNormalizer._();

  /// Normalisierung für Vergleiche und Suche.
  ///
  /// Beispiele:
  /// Bahnstraße 7
  /// Bahnstr. 7
  /// Bahnstrasse 7
  /// Bahn Str. 7
  ///
  /// werden auf eine vergleichbare Form gebracht.
  static String normalize(String value) {
    var result = value.trim().toLowerCase();

    // Umlaute auch in ausgeschriebener Form vergleichbar machen.
    result = result
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');

    // Häufige Varianten von "Straße".
    result = result.replaceAll(RegExp(r'\bstrasse\b'), 'str');

    result = result.replaceAll(RegExp(r'\bstr\.\b'), 'str');

    result = result.replaceAll(RegExp(r'\bstr\.'), 'str');

    /*
     * "Bahnstraße" -> "bahnstr"
     * "Bahnstrasse" -> "bahnstr"
     *
     * Nach der ß-Normalisierung steht hier bereits "strasse".
     */
    result = result.replaceAll(RegExp(r'strasse\b'), 'str');

    // Satzzeichen entfernen.
    result = result.replaceAll(RegExp(r'[.,;:_]'), '');

    // Leerzeichen komplett entfernen.
    //
    // Dadurch werden z. B.
    // "12 A" und "12a" identisch.
    result = result.replaceAll(RegExp(r'\s+'), '');

    return result;
  }

  static bool equals(String first, String second) {
    return normalize(first) == normalize(second);
  }

  static bool contains(String value, String query) {
    final normalizedValue = normalize(value);
    final normalizedQuery = normalize(query);

    if (normalizedQuery.isEmpty) {
      return true;
    }

    return normalizedValue.contains(normalizedQuery);
  }
}
