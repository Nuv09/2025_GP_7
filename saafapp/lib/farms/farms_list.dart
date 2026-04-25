class FarmsList {
  final String farmOwner;
  final String farmName;
  final String infectionAreas;
  final int numberOfPalm;
  final String? imageURL;

  const FarmsList({
    required this.farmOwner,
    required this.farmName,
    required this.infectionAreas,
    required this.numberOfPalm,
    this.imageURL,
  });

  factory FarmsList.fromMap(Map<String, dynamic> data) {
    return FarmsList(
      farmOwner: (data['ownerName'] ?? '').toString(),
      farmName: (data['farmName'] ?? '').toString(),
      infectionAreas: (data['infectionAreas'] ?? 'غير محدد').toString(),
      numberOfPalm: _asInt(data['numberOfPalm']),
      imageURL: (() {
        final v = (data['imageURL'] ?? data['imageUrl'] ?? '')
            .toString()
            .trim();
        return v.isEmpty ? null : v;
      })(),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
