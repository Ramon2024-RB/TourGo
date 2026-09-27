class District {
  final int number;
  final String assetPath;

  const District({required this.number, required this.assetPath});

  String get name => 'Bezirk $number';
}
