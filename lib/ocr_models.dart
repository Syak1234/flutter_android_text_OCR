class OcrHistoryItem {
  final String id;
  final int timestampMs;
  final String preview;
  final String fullText;
  final String imagePath;

  OcrHistoryItem({
    required this.id,
    required this.timestampMs,
    required this.preview,
    required this.fullText,
    required this.imagePath,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestampMs': timestampMs,
    'preview': preview,
    'fullText': fullText,
    'imagePath': imagePath,
  };

  static OcrHistoryItem fromJson(Map<String, dynamic> j) => OcrHistoryItem(
    id: j['id'] as String,
    timestampMs: (j['timestampMs'] as num).toInt(),
    preview: (j['preview'] as String?) ?? '',
    fullText: (j['fullText'] as String?) ?? '',
    imagePath: (j['imagePath'] as String?) ?? '',
  );
}

class OcrStats {
  final int totalScans;
  final int totalCharacters;
  final int? lastScanAtMs;

  OcrStats({
    required this.totalScans,
    required this.totalCharacters,
    required this.lastScanAtMs,
  });

  Map<String, dynamic> toJson() => {
    'totalScans': totalScans,
    'totalCharacters': totalCharacters,
    'lastScanAtMs': lastScanAtMs,
  };

  static OcrStats fromJson(Map<String, dynamic> j) => OcrStats(
    totalScans: (j['totalScans'] as num?)?.toInt() ?? 0,
    totalCharacters: (j['totalCharacters'] as num?)?.toInt() ?? 0,
    lastScanAtMs: (j['lastScanAtMs'] as num?)?.toInt(),
  );

  static OcrStats empty() =>
      OcrStats(totalScans: 0, totalCharacters: 0, lastScanAtMs: null);

  OcrStats copyWith({
    int? totalScans,
    int? totalCharacters,
    int? lastScanAtMs,
  }) => OcrStats(
    totalScans: totalScans ?? this.totalScans,
    totalCharacters: totalCharacters ?? this.totalCharacters,
    lastScanAtMs: lastScanAtMs ?? this.lastScanAtMs,
  );
}
