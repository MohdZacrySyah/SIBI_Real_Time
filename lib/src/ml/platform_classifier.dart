import 'hand_landmark.dart';

class PredictionResult {
  final String label;
  final double confidence;
  final String inferenceSource;

  PredictionResult({
    required this.label,
    required this.confidence,
    required this.inferenceSource,
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
