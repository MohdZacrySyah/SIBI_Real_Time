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
  String getLabelFromIndex(int index);
  void dispose();
}
