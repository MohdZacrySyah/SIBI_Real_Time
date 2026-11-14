import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../ml/hand_landmark.dart';
import '../ml/platform_classifier.dart';
import '../state/sibi_state.dart';
import '../ml/camera_bridge.dart';
import '../ml/platform_camera_bridge.dart';
import 'theme.dart';

class CameraView extends StatefulWidget {
  final PlatformClassifier classifier;
  final bool isExpanded;

  const CameraView({
    super.key, 
    required this.classifier,
    this.isExpanded = false,
  });

  @override
  State<CameraView> createState() => CameraViewState();
}

class CameraViewState extends State<CameraView> {
  late final PlatformCameraBridge _cameraBridge;
  bool _isCameraInitializing = false;

  // Debouncing State untuk Pengetikan Huruf
  String _currentBufferChar = '';
  DateTime? _bufferStartTime;
  String _lastEmittedChar = ''; // Mencegah spam gesture yang sama
  final Duration _debounceThreshold = const Duration(milliseconds: 350); // Waktu tahan gesture 350ms
  String _lastLiveLabel = 'Menunggu Gesture...';
  String _lastLiveDisplay = 'Menunggu Gesture...';

  // FPS tracking variables
  int _fpsFrameCount = 0;
  DateTime? _fpsStartTime;
  double _currentCalculatedFps = 0.0;

  bool _wasPaused = false;
  late SibiState _sibiState;

  @override
  void initState() {
    super.initState();
    _cameraBridge = createCameraBridge();
    _sibiState = Provider.of<SibiState>(context, listen: false);
    _sibiState.addListener(_onStateChanged);

    // Jangan mulai kamera otomatis di awal, tunggu aksi user
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   _cameraBridge.initCamera(this);
    // });
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (_sibiState.isPaused != _wasPaused) {
      _wasPaused = _sibiState.isPaused;
      if (_wasPaused) {
        // Mode jeda diaktifkan: Matikan kamera secara fisik
        _cameraBridge.disposeCamera(this);
      } else {
        // Mode jeda dimatikan: Hidupkan kembali kamera
        _cameraBridge.initCamera(this);
      }
    }
  }

  @override
  void dispose() {
    _sibiState.removeListener(_onStateChanged);
    _cameraBridge.disposeCamera(this);
    super.dispose();
  }

  // Method publik untuk diakses oleh Native/Web Bridge guna mengatur status loading kamera
  void setInitializing(bool val) {
    if (!mounted) return;
    setState(() => _isCameraInitializing = val);
  }

  // Callback terpadu saat prediksi gerakan berhasil diperoleh (dari FFI / Android Stream)
  void onPredictionResult(CameraPrediction prediction) {
    if (!mounted) return;
    final state = Provider.of<SibiState>(context, listen: false);

    // Update data landmark tangan yang terdeteksi
    state.updateDetectedHands(prediction.hands);

    // Hitung kecepatan bingkai (FPS)
    _calculateFps();

    // Update frame gambar Windows jika disediakan (Windows Only)
    if (prediction.imageBytes != null) {
      state.updateStreamedImage(prediction.imageBytes);
    }

    // PENTING: Jalankan AI Inference di Main Isolate satu kali per frame dengan mode yang dipilih (Auto / Alphabet / Word)
    final result = widget.classifier.classify(prediction.hands, mode: state.translationMode);

    // Hitung latency end-to-end sesungguhnya (dari frame diterima hingga prediksi teks selesai)
    final latencyMs = (DateTime.now().difference(prediction.timestamp).inMicroseconds) / 1000.0;

    // Perbarui metrik performa di SibiState dengan data pengukuran riil
    state.updatePerformanceMetrics(
      fps: _currentCalculatedFps,
      inferenceTimeMs: result.inferenceTimeMs,
      latencyMs: latencyMs,
      confidence: result.confidence,
    );

    // Update status mesin aktif di SibiState ("Huruf", "Kata", atau "Menunggu")
    if (result.inferenceSource.contains('Kata')) {
      state.updateActiveEngine('Kata');
    } else if (result.inferenceSource.contains('Huruf')) {
      state.updateActiveEngine('Huruf');
    } else {
      state.updateActiveEngine('Menunggu');
    }

    if (_lastLiveLabel != result.label) {
      setState(() {
        _lastLiveLabel = result.label;
        if (result.label != 'Menunggu Gesture...' && result.label != '?') {
          _lastLiveDisplay = '${result.label} (${(result.confidence * 100).toInt()}%)';
        } else {
          _lastLiveDisplay = result.label;
        }
      });
    }

    // Proses hasil terjemahan dengan debouncer pengetikan kata/huruf
    _processDebouncedPrediction(result.label);
  }

  // Method public untuk memulai & mematikan kamera dari luar
  void startCamera() => _cameraBridge.initCamera(this);
  void stopCamera() => _cameraBridge.disposeCamera(this);
  void toggleCamera() => _cameraBridge.toggleCamera(this);
  bool get canToggleCamera => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Menghitung FPS (Frames Per Second) dari pemrosesan gambar kamera
  void _calculateFps() {
    _fpsFrameCount++;
    final now = DateTime.now();
    _fpsStartTime ??= now;
    
    final diff = now.difference(_fpsStartTime!).inMilliseconds;
    if (diff >= 1000) {
      setState(() {
        _currentCalculatedFps = (_fpsFrameCount * 1000.0) / diff;
        _fpsFrameCount = 0;
        _fpsStartTime = now;
      });
    }
  }

  /// Algoritma Debouncing Pengetikan Kata/Huruf Real-time
  void _processDebouncedPrediction(String label) {
    // Saring semua status idle/menunggu agar TIDAK masuk ke kotak hasil pengetikan
    if (label.isEmpty || 
        label.startsWith('Menunggu') || 
        label == '?' || 
        label == 'Menunggu Gesture...') {
      _bufferStartTime = null;
      _currentBufferChar = '';
      _lastEmittedChar = ''; // Reset state emit ketika tidak ada gesture
      return;
    }

    // Hindari spam: Jangan proses jika kata/huruf yang sama baru saja diketik, 
    // kecuali pengguna menurunkan tangan atau merubah gesture terlebih dahulu.
    if (label == _lastEmittedChar) {
      return;
    }

    final state = Provider.of<SibiState>(context, listen: false);

    if (_currentBufferChar == label) {
      // Label sama sedang ditahan
      final elapsed = DateTime.now().difference(_bufferStartTime!);
      if (elapsed >= _debounceThreshold) {
        final isWord = label.length > 1;
        
        if (isWord) {
          state.appendWord(label);
          _triggerHapticFeedback();
        } else {
          state.appendLetter(label);
          _triggerHapticFeedback();
        }
        
        // Simpan sebagai huruf/kata terakhir yang diketik untuk mencegah spam
        _lastEmittedChar = label;
        // Reset buffer
        _currentBufferChar = '';
        _bufferStartTime = null;
      }
    } else {
      // Label baru terdeteksi, mulai hitung waktu buffer baru
      _currentBufferChar = label;
      _bufferStartTime = DateTime.now();
    }
  }

  void _triggerHapticFeedback() {
    if (!kIsWeb) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<SibiState>(context);

    // 1. Tampilan ketika kamera dinonaktifkan atau dijeda
    if (state.isPaused) {
      return Container(
        color: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off_rounded, size: 64, color: AppTheme.textSecondary),
              const SizedBox(height: 16),
              Text(
                'Kamera Mati',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tekan tombol START untuk menghidupkan kamera',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Tampilkan Loading Spinner saat kamera sedang diinisialisasi (hanya untuk Native)
    if (_isCameraInitializing && !kIsWeb) {
      return Container(
        color: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppTheme.successEmerald),
              const SizedBox(height: 16),
              Text(
                state.cameraStatusMessage.isNotEmpty ? state.cameraStatusMessage : 'Memulai Sistem...',
                style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Tampilkan Pesan Kesalahan jika kamera gagal diakses (hanya untuk Native)
    if (!state.isCameraActive && !kIsWeb) {
      return Container(
        padding: const EdgeInsets.all(24),
        color: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off_rounded, size: 64, color: Colors.white54),
              const SizedBox(height: 16),
              Text(
                'Kamera Mati',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              const Text(
                'Klik tombol START di bawah untuk mulai dan menyalakan kamera.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    // 4. Kamera berhasil aktif: Tampilkan pratinjau kamera sesuai platform
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Render penampang kamera statis dari bridge (Windows, Android, Web)
          _cameraBridge.buildPreview(context, this),
          
          // Khusus Web: Tampilkan loading atau error overlay di atas HtmlElementView jika kamera belum aktif/sedang loading
          if (kIsWeb && (!state.isCameraActive || _isCameraInitializing))
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isCameraInitializing) ...[
                          const CircularProgressIndicator(color: AppTheme.successEmerald),
                          const SizedBox(height: 16),
                          Text(
                            state.cameraStatusMessage.isNotEmpty ? state.cameraStatusMessage : 'Memulai Sistem...',
                            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                          ),
                        ] else ...[
                          const Icon(Icons.videocam_off_rounded, size: 64, color: Colors.white54),
                          const SizedBox(height: 16),
                          Text(
                            'Kamera Mati',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Klik tombol START di bawah untuk mulai dan menyalakan kamera.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          
          // Siku Pembatas (Corner Brackets) overlay
          Positioned.fill(
            child: CustomPaint(
              painter: CornerBracketsPainter(
                color: Colors.white.withOpacity(0.5),
                bracketLength: 30,
                strokeWidth: 2,
              ),
            ),
          ),

          // Status Badge overlay
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppTheme.glassBorder, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.successEmerald,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'KAMERA AKTIF',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Live Prediction Overlay Badge & Label Kecil Mode Mesin ("Huruf" / "Kata")
          Positioned(
            bottom: 16,
            left: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Label Kecil "Huruf" / "Kata"
                Consumer<SibiState>(
                  builder: (context, state, _) {
                    final String engine = state.currentActiveEngine;
                    final bool isWord = engine == 'Kata';
                    final bool isLetter = engine == 'Huruf';
                    final Color badgeColor = isWord 
                        ? const Color(0xFFF59E0B) // Amber untuk Kata
                        : (isLetter ? const Color(0xFF10B981) : Colors.grey); // Emerald untuk Huruf

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: badgeColor.withOpacity(0.6), width: 1.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isWord ? Icons.waves_rounded : (isLetter ? Icons.text_fields_rounded : Icons.hourglass_empty_rounded),
                            color: badgeColor,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            engine.toUpperCase(),
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: badgeColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // Hasil Deteksi Real-Time AI
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.electricCyan.withOpacity(0.4), width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.psychology_rounded, color: AppTheme.electricCyan, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        _lastLiveLabel.isNotEmpty ? 'AI: $_lastLiveLabel' : 'AI: Menunggu...',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.electricCyan,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter untuk melukis 21 landmark tangan dan garis penghubungnya (Hanya untuk Mobile/Desktop Native)
class LandmarkPainter extends CustomPainter {
  final List<AppHand> hands;
  final Size previewSize;
  final CameraLensDirection lensDirection;
  final int sensorOrientation;

  LandmarkPainter({
    required this.hands,
    required this.previewSize,
    required this.lensDirection,
    required this.sensorOrientation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty) return;

    final nodePaint = Paint()
      ..color = AppTheme.electricCyan
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = AppTheme.electricIndigo.withOpacity(0.8)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    const connections = [
      [0, 1], [1, 2], [2, 3], [3, 4],
      [0, 5], [5, 6], [6, 7], [7, 8],
      [5, 9], [9, 10], [10, 11], [11, 12],
      [9, 13], [13, 14], [14, 15], [15, 16],
      [13, 17], [0, 17], [17, 18], [18, 19], [19, 20],
    ];

    for (final hand in hands) {
      for (final connection in connections) {
        final start = hand.landmarks[connection[0]];
        final end = hand.landmarks[connection[1]];
        
        final startDx = start.x * size.width;
        final startDy = start.y * size.height;
        final endDx = end.x * size.width;
        final endDy = end.y * size.height;

        canvas.drawLine(
          Offset(startDx, startDy),
          Offset(endDx, endDy),
          linePaint,
        );
      }

      for (int i = 0; i < hand.landmarks.length; i++) {
        final landmark = hand.landmarks[i];
        final dx = landmark.x * size.width;
        final dy = landmark.y * size.height;

        if (i == 4 || i == 8 || i == 12 || i == 16 || i == 20) {
          nodePaint.color = AppTheme.neonPurple;
        } else if (i == 0) {
          nodePaint.color = AppTheme.successEmerald;
        } else {
          nodePaint.color = AppTheme.electricCyan;
        }

        canvas.drawCircle(Offset(dx, dy), 5, nodePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LandmarkPainter oldDelegate) => true;
}

/// CustomPainter untuk melukis siku pembatas kurung sudut
class CornerBracketsPainter extends CustomPainter {
  final Color color;
  final double bracketLength;
  final double strokeWidth;

  CornerBracketsPainter({
    required this.color,
    this.bracketLength = 30.0,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square;

    final w = size.width;
    final h = size.height;

    canvas.drawPath(
      Path()
        ..moveTo(0, bracketLength)
        ..lineTo(0, 0)
        ..lineTo(bracketLength, 0),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(w - bracketLength, 0)
        ..lineTo(w, 0)
        ..lineTo(w, bracketLength),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(0, h - bracketLength)
        ..lineTo(0, h)
        ..lineTo(bracketLength, h),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(w - bracketLength, h)
        ..lineTo(w, h)
        ..lineTo(w, h - bracketLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
