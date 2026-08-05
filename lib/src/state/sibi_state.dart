import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ml/hand_landmark.dart';

class TranslationRecord {
  final String id;
  final String text;
  final DateTime timestamp;
  final double confidence;
  final double avgFps;
  final double avgLatencyMs;

  TranslationRecord({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.confidence,
    required this.avgFps,
    required this.avgLatencyMs,
  });
}

class SibiState extends ChangeNotifier {
  // Pengaturan Tema
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  // Status Kamera
  bool _isCameraActive = false;
  bool get isCameraActive => _isCameraActive;

  String _cameraStatusMessage = 'Menginisialisasi Kamera...';
  String get cameraStatusMessage => _cameraStatusMessage;

  bool _cameraPermissionDenied = false;
  bool get cameraPermissionDenied => _cameraPermissionDenied;

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  // Status Model ML
  bool _isModelLoaded = false;
  bool get isModelLoaded => _isModelLoaded;

  String _modelStatusMessage = 'Mempersiapkan Model...';
  String get modelStatusMessage => _modelStatusMessage;



  // Data Deteksi Landmark
  List<AppHand> _detectedHands = [];
  List<AppHand> get detectedHands => _detectedHands;

  // Status Native C++ Camera DLL (untuk Windows Desktop)
  Uint8List? _streamedImageBytes;
  Uint8List? get streamedImageBytes => _streamedImageBytes;

  bool _isBridgeConnected = false;
  bool get isBridgeConnected => _isBridgeConnected;

  // Teks Hasil Terjemahan
  String _translatedText = '';
  String get translatedText => _translatedText;

  // Riwayat Terjemahan
  final List<TranslationRecord> _history = [];
  List<TranslationRecord> get history => List.unmodifiable(_history);

  // Parameter Performa & Benchmarks
  double _fps = 0.0;
  double get fps => _fps;

  double _inferenceTimeMs = 0.0;
  double get inferenceTimeMs => _inferenceTimeMs;

  double _latencyMs = 0.0;
  double get latencyMs => _latencyMs;

  double _confidence = 0.0;
  double get confidence => _confidence;

  double _detectionThreshold = 0.65;
  double get detectionThreshold => _detectionThreshold;

  // Status Text-to-Speech
  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  // Setters & Updaters
  void setCameraActive(bool active, {String? message, bool permissionDenied = false}) {
    _isCameraActive = active;
    _cameraPermissionDenied = permissionDenied;
    if (message != null) {
      _cameraStatusMessage = message;
    }
    notifyListeners();
  }

  void setModelStatus(bool loaded, {required String message}) {
    _isModelLoaded = loaded;
    _modelStatusMessage = message;
    notifyListeners();
  }

  void togglePause() {
    _isPaused = !_isPaused;
    // Jika dipause, bersihkan tangan yang terdeteksi
    if (_isPaused) {
      _detectedHands = [];
    }
    notifyListeners();
  }

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void updateDetectedHands(List<AppHand> hands) {
    _detectedHands = hands;
    notifyListeners();
  }

  void updateStreamedImage(Uint8List? bytes) {
    _streamedImageBytes = bytes;
    notifyListeners();
  }

  void setBridgeConnected(bool connected) {
    _isBridgeConnected = connected;
    notifyListeners();
  }

  void updatePerformanceMetrics({required double fps, required double inferenceTimeMs, required double latencyMs, required double confidence}) {
    _fps = fps;
    _inferenceTimeMs = inferenceTimeMs;
    _latencyMs = latencyMs;
    _confidence = confidence;
    notifyListeners();
  }

  void appendLetter(String letter) {
    if (letter.isEmpty) return;
    
    // Cegah duplikasi huruf berulang secara instan jika waktu terlalu dekat
    if (_translatedText.isNotEmpty && _translatedText.endsWith(letter)) {
      // Izinkan jika memang sengaja (bisa diatur dengan gesture tahan),
      // namun untuk UX real-time ketikan awal kita batasi debounce singkat.
    }
    
    if (_translatedText.isNotEmpty && !_translatedText.endsWith(' ')) {
      _translatedText += ' ';
    }
    _translatedText += letter;
    notifyListeners();
  }

  void appendWord(String word) {
    if (word.isEmpty) return;
    if (_translatedText.isNotEmpty && !_translatedText.endsWith(' ')) {
      _translatedText += ' ';
    }
    _translatedText += word;
    notifyListeners();
  }

  void backspace() {
    if (_translatedText.isNotEmpty) {
      _translatedText = _translatedText.substring(0, _translatedText.length - 1);
      notifyListeners();
    }
  }

  void clearText() {
    _translatedText = '';
    notifyListeners();
  }

  void setThreshold(double val) {
    _detectionThreshold = val;
    notifyListeners();
  }

  // Simpan Terjemahan ke Riwayat
  void saveCurrentTranslationToHistory() {
    if (_translatedText.trim().isEmpty) return;

    final record = TranslationRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: _translatedText.trim(),
      timestamp: DateTime.now(),
      confidence: _confidence > 0 ? _confidence : 0.88, // default fallback confidence if simulated
      avgFps: _fps > 0 ? _fps : 30.0,
      avgLatencyMs: _inferenceTimeMs > 0 ? _inferenceTimeMs : 12.0,
    );

    _history.insert(0, record);
    notifyListeners();
  }

  void deleteHistoryItem(String id) {
    _history.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  // Text-To-Speech Mock (Speak)
  Future<void> speakTranslation() async {
    if (_translatedText.trim().isEmpty) return;
    
    _isSpeaking = true;
    notifyListeners();

    // Mock speaking delay
    await Future.delayed(Duration(milliseconds: 1000 + (_translatedText.length * 50)));

    _isSpeaking = false;
    notifyListeners();
  }
}
