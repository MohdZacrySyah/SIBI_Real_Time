// Versi kosong untuk platform tanpa dart:io (web).
class BenchmarkLogger {
  BenchmarkLogger._();
  static final BenchmarkLogger instance = BenchmarkLogger._();

  static const bool enabled = false;

  void logFrame({
    required String platform,
    required String mode,
    required String engine,
    required bool handDetected,
    required String label,
    required double confidence,
    required double fps,
    required double landmarkMs,
    required double alphaInvokeMs,
    required double wordInvokeMs,
    required double classifyMs,
    required double latencyMs,
  }) {}

  Future<void> stopSession() async {}
}
