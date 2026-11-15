import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'hand_landmark.dart';
import 'platform_classifier.dart';

/// ============================================================================
/// KELAS UTAMA: SibiClassifier (Intelligent Auto-Hybrid SIBI Translator)
/// ============================================================================
/// Mengintegrasikan 2 Model TFLite On-Device:
/// • Model 1: Alphabet Fingerspelling DNN (26 Huruf A–Z, masukan 63 fitur landmark per-frame [1, 63])
/// • Model 2: Dynamic Word Gestures CNN-LSTM (7 Kata Dasar, masukan sekuens 30 frame [1, 30, 63])
/// • Intelligent Arbiter: Otomatis mendeteksi varians energi gerakan dinamis vs pose statis (dengan opsi mode manual).
class SibiClassifier extends PlatformClassifier {
  // Interpreter Mesin 1: Alphabet Fingerspelling (DNN)
  Interpreter? _alphabetInterpreter;
  List<String> _alphabetLabels = [];
  List<double> _alphabetScalerMean = [];
  List<double> _alphabetScalerScale = [];

  // Interpreter Mesin 2: Dynamic Word Gestures (CNN-LSTM)
  Interpreter? _wordInterpreter;
  List<String> _wordLabels = [];
  List<double> _wordScalerMean = [];
  List<double> _wordScalerScale = [];

  bool _isTfliteLoaded = false;
  String _lastErrorMessage = '';

  // Sliding window buffer untuk Mesin 2 (CNN-LSTM 30 Frame)
  static const int _sequenceLength = 30;
  final List<List<double>> _slidingWindowWord = [];

  // Smoothing queue untuk Mesin 1 (Majority Voting 5 Frame)
  static const int _smoothingWindowSize = 5;
  final List<String> _recentAlphabetLabels = [];
  int _missingFramesCount = 0;

  // Ambang batas kepercayaan (Thresholds)
  static const double _wordConfidenceThreshold = 0.65;
  static const double _alphabetConfidenceThreshold = 0.45;
  static const double _dynamicMotionThreshold = 0.018; // Ambang varians gerakan dinamis

  // Hysteresis Counters untuk Mencegah Mode Berkedip (Anti-Flicker State Machine)
  static const int _minFramesToEnterWordMode = 6;  // Butuh 6 frame berturut-turut di atas ambang gerakan
  static const int _minFramesToExitWordMode = 8;   // Butuh 8 frame berturut-turut stabil untuk kembali ke huruf
  int _consecutiveHighMotionFrames = 0;
  int _consecutiveLowMotionFrames = 0;
  bool _isInDynamicWordMode = false;

  PredictionResult _lastPrediction = PredictionResult(
    label: 'Menunggu Gesture...',
    confidence: 0.0,
    inferenceSource: 'SIBI Auto-Hybrid',
  );

  @override
  bool get isTfliteLoaded => _isTfliteLoaded;

  @override
  String get lastErrorMessage => _lastErrorMessage;

  /// Inisialisasi & pemuatan kedua mesin inferensi secara bersamaan
  @override
  Future<bool> initialize({String? modelPath, String? labelsPath}) async {
    try {
      if (kIsWeb) {
        _lastErrorMessage = 'TFLite tidak didukung di Web secara default dalam setup ini.';
        return false;
      }

      // 1. Inisialisasi Mesin 1: Alphabet Fingerspelling (DNN 26 Huruf)
      try {
        if (modelPath != null && modelPath.isNotEmpty && File(modelPath).existsSync()) {
          _alphabetInterpreter = Interpreter.fromFile(File(modelPath));
        } else {
          _alphabetInterpreter = await Interpreter.fromAsset('assets/sibi_alphabet_quantized.tflite');
        }

        final alphaLabelsData = await rootBundle.loadString('assets/alphabet_labels.txt');
        _alphabetLabels = alphaLabelsData.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

        final alphaScalerData = await rootBundle.loadString('assets/alphabet_scaler.json');
        final Map<String, dynamic> sc1 = json.decode(alphaScalerData);
        _alphabetScalerMean = (sc1['mean'] as List).map((e) => (e as num).toDouble()).toList();
        _alphabetScalerScale = (sc1['scale'] as List).map((e) => (e as num).toDouble()).toList();
        debugPrint('SIBI [Auto-Hybrid]: Model Huruf A-Z berhasil dimuat (${_alphabetLabels.length} kelas).');
      } catch (e) {
        debugPrint('SIBI [Auto-Hybrid]: Gagal memuat Model Huruf: $e');
      }

      // 2. Inisialisasi Mesin 2: Dynamic Word Gestures (CNN-LSTM 7 Kata)
      try {
        _wordInterpreter = await Interpreter.fromAsset('assets/sibi_word_lstm_quantized.tflite');
        final wordLabelsData = await rootBundle.loadString('assets/word_labels.txt');
        _wordLabels = wordLabelsData.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

        final wordScalerData = await rootBundle.loadString('assets/word_scaler.json');
        final Map<String, dynamic> sc2 = json.decode(wordScalerData);
        _wordScalerMean = (sc2['mean'] as List).map((e) => (e as num).toDouble()).toList();
        _wordScalerScale = (sc2['scale'] as List).map((e) => (e as num).toDouble()).toList();
        debugPrint('SIBI [Auto-Hybrid]: Model Kata CNN-LSTM berhasil dimuat (${_wordLabels.length} kata).');
      } catch (e) {
        debugPrint('SIBI [Auto-Hybrid]: Gagal memuat Model Kata CNN-LSTM: $e');
      }

      _isTfliteLoaded = (_alphabetInterpreter != null || _wordInterpreter != null);
      debugPrint('SIBI Auto-Hybrid: Sistem satu mode cerdas siap digunakan!');
      return _isTfliteLoaded;
    } catch (e) {
      _isTfliteLoaded = false;
      _lastErrorMessage = e.toString();
      debugPrint('SIBI Gagal Inisialisasi: $e');
      return false;
    }
  }

  /// Reset buffer smoothing dan window
  void resetBuffer() {
    _slidingWindowWord.clear();
    _recentAlphabetLabels.clear();
    _missingFramesCount = 0;
    _consecutiveHighMotionFrames = 0;
    _consecutiveLowMotionFrames = 0;
    _isInDynamicWordMode = false;
    _lastPrediction = PredictionResult(
      label: 'Menunggu Gesture...',
      confidence: 0.0,
      inferenceSource: 'SIBI Auto-Hybrid',
    );
  }

  // Pengukuran waktu satu pemanggilan interpreter.run() (untuk benchmark)
  double _alphaInvokeSumMs = 0.0;
  int _alphaInvokeCount = 0;
  double _lastWordInvokeMs = -1.0;

  @override
  double get lastAlphaInvokeMs => _alphaInvokeCount == 0 ? -1.0 : _alphaInvokeSumMs / _alphaInvokeCount;

  @override
  double get lastWordInvokeMs => _lastWordInvokeMs;

  /// Eksekusi klasifikasi cerdas dalam satu mode otomatis (Auto-Routing) dengan cadangan manual
  @override
  PredictionResult classify(List<AppHand> hands, {String mode = 'auto'}) {
    final inferenceStopwatch = Stopwatch()..start();
    _alphaInvokeSumMs = 0.0;
    _alphaInvokeCount = 0;
    _lastWordInvokeMs = -1.0;
    if (hands.isEmpty) {
      _missingFramesCount++;
      if (_missingFramesCount > 10) {
        _slidingWindowWord.clear();
        _recentAlphabetLabels.clear();
        _consecutiveHighMotionFrames = 0;
        _consecutiveLowMotionFrames = 0;
        _isInDynamicWordMode = false;
      }
      inferenceStopwatch.stop();
      return PredictionResult(
        label: 'Menunggu Gesture...',
        confidence: 0.0,
        inferenceSource: 'SIBI Auto-Hybrid',
        inferenceTimeMs: 0.0,
      );
    }

    _missingFramesCount = 0;
    final hand = hands[0];

    // ==========================================================
    // 1. UPDATE SLIDING WINDOW KATA (30 FRAME) & HITUNG GERAKAN
    // ==========================================================
    final rawWord = hand.toWristRelativeRawVector(mirror: false);
    final normWord = _normalize(rawWord, _wordScalerMean, _wordScalerScale);

    _slidingWindowWord.add(normWord);
    if (_slidingWindowWord.length > _sequenceLength) {
      _slidingWindowWord.removeAt(0);
    }

    // Hitung varians gerakan temporal tangan (Delta E)
    final double motionEnergy = _calculateTemporalMotionEnergy(_slidingWindowWord);

    // ==========================================================
    // 2. HYSTERESIS STATE MACHINE (MENCEGAH MODE BERKEDIP)
    // ==========================================================
    if (motionEnergy >= _dynamicMotionThreshold) {
      _consecutiveHighMotionFrames++;
      _consecutiveLowMotionFrames = 0;
      if (_consecutiveHighMotionFrames >= _minFramesToEnterWordMode) {
        _isInDynamicWordMode = true;
      }
    } else {
      _consecutiveLowMotionFrames++;
      _consecutiveHighMotionFrames = 0;
      if (_consecutiveLowMotionFrames >= _minFramesToExitWordMode) {
        _isInDynamicWordMode = false;
      }
    }

    // Tentukan apakah kita harus menjalankan inferensi kata dan huruf
    final bool allowWordInference = (mode == 'word') || (mode == 'auto');
    final bool allowAlphaInference = (mode == 'alphabet') || (mode == 'auto');

    // ==========================================================
    // 3. JALANKAN INFERENSI KATA (CNN-LSTM) JIKA DIIZINKAN & BUFFER CUKUP
    // ==========================================================
    _InferenceOutput? wordResult;
    if (allowWordInference && _wordInterpreter != null && _slidingWindowWord.length == _sequenceLength) {
      wordResult = _runWordLSTMInference(_slidingWindowWord);
    }

    // ==========================================================
    // 4. JALANKAN INFERENSI HURUF (DNN SINGLE-FRAME)
    // ==========================================================
    _InferenceOutput? alphaResult;
    if (allowAlphaInference && _alphabetInterpreter != null) {
      final rawAlphaNormal = hand.toWristRelativeRawVector(mirror: false);
      final rawAlphaMirrored = hand.toWristRelativeRawVector(mirror: true);
      final normAlphaNormal = _normalize(rawAlphaNormal, _alphabetScalerMean, _alphabetScalerScale);
      final normAlphaMirrored = _normalize(rawAlphaMirrored, _alphabetScalerMean, _alphabetScalerScale);

      final resNormal = _runSingleInference(_alphabetInterpreter!, normAlphaNormal, _alphabetLabels.length);
      final resMirrored = _runSingleInference(_alphabetInterpreter!, normAlphaMirrored, _alphabetLabels.length);
      alphaResult = (resNormal.maxProb >= resMirrored.maxProb) ? resNormal : resMirrored;
    }

    // ==========================================================
    // 5. ARBITRASE HASIL BERDASARKAN MODE & HYSTERESIS
    // ==========================================================
    
    // A. MODE CADANGAN: KHUSUS KATA
    if (mode == 'word') {
      inferenceStopwatch.stop();
      final elapsedMs = inferenceStopwatch.elapsedMicroseconds / 1000.0;
      if (wordResult != null &&
          wordResult.maxProb >= _wordConfidenceThreshold &&
          wordResult.maxIndex != -1) {
        final wordLabel = (wordResult.maxIndex < _wordLabels.length)
            ? _wordLabels[wordResult.maxIndex]
            : '?';
        _lastPrediction = PredictionResult(
          label: wordLabel,
          confidence: wordResult.maxProb,
          inferenceSource: 'Model 2: Kata Dinamis (CNN-LSTM)',
          inferenceTimeMs: elapsedMs,
        );
        return _lastPrediction;
      }
      return PredictionResult(
        label: 'Menunggu Gerakan Kata...',
        confidence: wordResult?.maxProb ?? 0.0,
        inferenceSource: 'Model 2: Kata Dinamis (CNN-LSTM)',
        inferenceTimeMs: elapsedMs,
      );
    }

    // B. MODE CADANGAN: KHUSUS HURUF
    if (mode == 'alphabet') {
      inferenceStopwatch.stop();
      final elapsedMs = inferenceStopwatch.elapsedMicroseconds / 1000.0;
      if (alphaResult != null &&
          alphaResult.maxProb >= _alphabetConfidenceThreshold &&
          alphaResult.maxIndex != -1) {
        final alphaLabel = (alphaResult.maxIndex < _alphabetLabels.length)
            ? _alphabetLabels[alphaResult.maxIndex]
            : '?';
        _recentAlphabetLabels.add(alphaLabel);
        if (_recentAlphabetLabels.length > _smoothingWindowSize) {
          _recentAlphabetLabels.removeAt(0);
        }
        final smoothedLabel = _getMajorityLabel(_recentAlphabetLabels);
        _lastPrediction = PredictionResult(
          label: smoothedLabel,
          confidence: alphaResult.maxProb,
          inferenceSource: 'Model 1: Ejaan Huruf (DNN)',
          inferenceTimeMs: elapsedMs,
        );
        return _lastPrediction;
      }
      return PredictionResult(
        label: 'Menunggu Pose Huruf...',
        confidence: alphaResult?.maxProb ?? 0.0,
        inferenceSource: 'Model 1: Ejaan Huruf (DNN)',
        inferenceTimeMs: elapsedMs,
      );
    }

    // C. MODE UTAMA: AUTO-HYBRID DENGAN HYSTERESIS (ALUR NORMAL SKRIPSI)
    // Syarat menampilkan kata:
    // 1. Status hysteresis berada di mode kata (_isInDynamicWordMode == true)
    // 2. Model Kata memiliki confidence >= 0.65
    // Jika tidak memenuhi, sistem otomatis jatuh kembali (fallback) ke mode huruf.
    inferenceStopwatch.stop();
    final elapsedMs = inferenceStopwatch.elapsedMicroseconds / 1000.0;

    if (_isInDynamicWordMode &&
        wordResult != null &&
        wordResult.maxProb >= _wordConfidenceThreshold &&
        wordResult.maxIndex != -1) {
      final wordLabel = (wordResult.maxIndex < _wordLabels.length)
          ? _wordLabels[wordResult.maxIndex]
          : '?';

      // Reset antrean smoothing huruf agar tidak bercampur dengan kata
      _recentAlphabetLabels.clear();

      _lastPrediction = PredictionResult(
        label: wordLabel,
        confidence: wordResult.maxProb,
        inferenceSource: 'Model 2: Kata Dinamis (CNN-LSTM)',
        inferenceTimeMs: elapsedMs,
      );
      return _lastPrediction;
    }

    // Fallback Ejaan Huruf (Jika tangan diam/stabil ATAU confidence kata < 0.65)
    if (alphaResult != null &&
        alphaResult.maxProb >= _alphabetConfidenceThreshold &&
        alphaResult.maxIndex != -1) {
      final alphaLabel = (alphaResult.maxIndex < _alphabetLabels.length)
          ? _alphabetLabels[alphaResult.maxIndex]
          : '?';

      _recentAlphabetLabels.add(alphaLabel);
      if (_recentAlphabetLabels.length > _smoothingWindowSize) {
        _recentAlphabetLabels.removeAt(0);
      }
      final smoothedLabel = _getMajorityLabel(_recentAlphabetLabels);

      _lastPrediction = PredictionResult(
        label: smoothedLabel,
        confidence: alphaResult.maxProb,
        inferenceSource: 'Model 1: Ejaan Huruf (DNN)',
        inferenceTimeMs: elapsedMs,
      );
      return _lastPrediction;
    }

    // Default: Menunggu Gesture Jelas
    return PredictionResult(
      label: 'Menunggu Gesture...',
      confidence: 0.0,
      inferenceSource: 'SIBI Auto-Hybrid',
      inferenceTimeMs: elapsedMs,
    );
  }

  /// Menghitung tingkat varians pergerakan tangan dalam sekuens frame (energi gerak delta E)
  double _calculateTemporalMotionEnergy(List<List<double>> window) {
    if (window.length < 10) return 0.0;
    double totalDisplacement = 0.0;
    // Hitung pergeseran koordinat 21 titik landmark tangan (63 koordinat x, y, z)
    for (int i = 1; i < window.length; i++) {
      final prev = window[i - 1];
      final curr = window[i];
      for (int k = 0; k < 63; k += 3) {
        final dx = curr[k] - prev[k];
        final dy = curr[k + 1] - prev[k + 1];
        final dz = curr[k + 2] - prev[k + 2];
        totalDisplacement += math.sqrt(dx * dx + dy * dy + dz * dz);
      }
    }
    return totalDisplacement / (window.length * 21);
  }

  /// Eksekusi inferensi Model 2 (CNN-LSTM)
  _InferenceOutput _runWordLSTMInference(List<List<double>> sequence) {
    var inputSeq = [sequence]; // shape [1, 30, 63]
    var outputBuf = List<List<double>>.generate(1, (_) => List<double>.filled(_wordLabels.length, 0.0));
    final invokeSw = Stopwatch()..start();
    _wordInterpreter!.run(inputSeq, outputBuf);
    invokeSw.stop();
    _lastWordInvokeMs = invokeSw.elapsedMicroseconds / 1000.0;

    final probs = outputBuf[0];
    double maxProb = -1.0;
    int maxIndex = -1;
    for (int i = 0; i < probs.length; i++) {
      if (probs[i] > maxProb) {
        maxProb = probs[i];
        maxIndex = i;
      }
    }
    return _InferenceOutput(maxIndex, maxProb);
  }

  /// Eksekusi inferensi Model 1 (DNN)
  _InferenceOutput _runSingleInference(Interpreter interp, List<double> features, int numClasses) {
    var input = [features];
    var output = List<List<double>>.generate(1, (_) => List<double>.filled(numClasses, 0.0));
    final invokeSw = Stopwatch()..start();
    interp.run(input, output);
    invokeSw.stop();
    _alphaInvokeSumMs += invokeSw.elapsedMicroseconds / 1000.0;
    _alphaInvokeCount++;

    final probs = output[0];
    double maxProb = -1.0;
    int maxIndex = -1;
    for (int i = 0; i < probs.length; i++) {
      if (probs[i] > maxProb) {
        maxProb = probs[i];
        maxIndex = i;
      }
    }
    return _InferenceOutput(maxIndex, maxProb);
  }

  /// Normalisasi koordinat
  List<double> _normalize(List<double> raw, List<double> mean, List<double> scale) {
    if (mean.isEmpty || scale.isEmpty) return raw;
    final List<double> result = List.filled(63, 0.0);
    for (int i = 0; i < 63; i++) {
      final s = scale[i] != 0 ? scale[i] : 1.0;
      result[i] = (raw[i] - mean[i]) / s;
    }
    return result;
  }

  /// Majority voting smoothing
  String _getMajorityLabel(List<String> labels) {
    if (labels.isEmpty) return 'Menunggu Gesture...';
    final counts = <String, int>{};
    for (var l in labels) {
      counts[l] = (counts[l] ?? 0) + 1;
    }
    String best = labels.last;
    int maxCount = 0;
    counts.forEach((k, v) {
      if (v > maxCount) {
        maxCount = v;
        best = k;
      }
    });
    return best;
  }

  @override
  String getLabelFromIndex(int index) {
    if (index >= 0 && index < _alphabetLabels.length) {
      return _alphabetLabels[index];
    }
    return '?';
  }

  @override
  void dispose() {
    _alphabetInterpreter?.close();
    _wordInterpreter?.close();
  }
}

PlatformClassifier createClassifier() => SibiClassifier();

class _InferenceOutput {
  final int maxIndex;
  final double maxProb;
  _InferenceOutput(this.maxIndex, this.maxProb);
}
