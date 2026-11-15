import 'hand_landmark.dart';

class PredictionResult {
  final String label;
  final double confidence;
  final String inferenceSource;
  final double inferenceTimeMs;

  PredictionResult({
    required this.label,
    required this.confidence,
    required this.inferenceSource,
    this.inferenceTimeMs = 0.0,
  });
}

abstract class PlatformClassifier {
  bool get isTfliteLoaded;
  String get lastErrorMessage;
  Future<bool> initialize();
  PredictionResult classify(List<AppHand> hands, {String mode = 'auto'});

  /// Waktu rata-rata satu pemanggilan interpreter.run() Model 1 / Model 2 pada
  /// frame terakhir (ms). Bernilai -1 jika model tidak dijalankan. (Benchmark)
  double get lastAlphaInvokeMs => -1.0;
  double get lastWordInvokeMs => -1.0;
  String getLabelFromIndex(int index);
  void dispose();
}
