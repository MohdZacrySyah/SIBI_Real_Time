import 'dart:io';

/// Mencatat satu baris CSV per frame yang diproses.
/// Sesi dimulai otomatis pada frame pertama setelah kamera menyala, dan
/// berakhir saat kamera dimatikan (tombol STOP / dispose).
class BenchmarkLogger {
  BenchmarkLogger._();
  static final BenchmarkLogger instance = BenchmarkLogger._();

  static const bool enabled = bool.fromEnvironment('BENCH', defaultValue: false);

  static const String _androidPackage = 'com.sibi.translator.sibi_realtime';

  IOSink? _sink;
  Stopwatch? _clock;
  int _lastRssSampleMs = -1000000;
  String _lastRssMb = '';
  int _rows = 0;

  Directory _preferredDir() {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Android/data/$_androidPackage/files/bench');
    }
    if (Platform.isWindows) {
      return Directory('${File(Platform.resolvedExecutable).parent.path}\\bench');
    }
    return Directory('${Directory.systemTemp.path}/sibi_bench');
  }

  void _startSession(String platform) {
    Directory dir = _preferredDir();
    try {
      dir.createSync(recursive: true);
    } catch (_) {
      dir = Directory('${Directory.systemTemp.path}/sibi_bench');
      dir.createSync(recursive: true);
    }
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final file = File('${dir.path}${Platform.pathSeparator}bench_${platform}_$stamp.csv');
    _sink = file.openWrite();
    _sink!.writeln('elapsed_ms,platform,mode,engine,hand,label,confidence,fps,'
        'landmark_ms,alpha_invoke_ms,word_invoke_ms,classify_ms,latency_ms,rss_mb');
    _clock = Stopwatch()..start();
    _rows = 0;
    _lastRssSampleMs = -1000000;
    _lastRssMb = '';
  }

  String _f(double v) => v < 0 ? '' : v.toStringAsFixed(3);

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
  }) {
    if (!enabled) return;
    try {
      if (_sink == null) _startSession(platform);
      final elapsed = _clock!.elapsedMilliseconds;

      // Memori proses (RSS) cukup dicuplik sekali per detik.
      if (elapsed - _lastRssSampleMs >= 1000) {
        _lastRssSampleMs = elapsed;
        _lastRssMb = (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1);
      }

      final safeLabel = label.replaceAll('"', "'");
      _sink!.writeln('$elapsed,$platform,$mode,"${engine.replaceAll('"', "'")}",'
          '${handDetected ? 1 : 0},"$safeLabel",${confidence.toStringAsFixed(3)},'
          '${fps.toStringAsFixed(1)},${_f(landmarkMs)},${_f(alphaInvokeMs)},'
          '${_f(wordInvokeMs)},${_f(classifyMs)},${_f(latencyMs)},$_lastRssMb');
      _rows++;
      if (_rows % 60 == 0) _sink!.flush();
    } catch (_) {
      // Pencatatan tidak boleh mengganggu aplikasi.
    }
  }

  Future<void> stopSession() async {
    final sink = _sink;
    if (sink == null) return;
    _sink = null;
    _clock?.stop();
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {}
  }
}
