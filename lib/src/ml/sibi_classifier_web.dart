import 'platform_classifier.dart';
import 'hand_landmark.dart';

class SibiClassifierWeb extends PlatformClassifier {
  @override
  bool get isTfliteLoaded => true;

  @override
  String get lastErrorMessage => '';

  @override
  Future<bool> initialize() async {
    return true; // Prediksi di web ditangani sepenuhnya di sisi JS WebAssembly
  }

  @override
  PredictionResult classify(List<AppHand> hands, {String mode = 'auto'}) {
    return PredictionResult(
      label: 'Menunggu Gesture...',
      confidence: 0.0,
      inferenceSource: 'JS WASM Web Model',
    );
  }

  @override
  String getLabelFromIndex(int index) {
    return '?';
  }

  @override
  void dispose() {}
}

PlatformClassifier createClassifier() => SibiClassifierWeb();
