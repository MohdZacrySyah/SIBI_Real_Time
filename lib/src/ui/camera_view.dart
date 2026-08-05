import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hand_landmarker/hand_landmarker.dart' as mp;
import 'package:provider/provider.dart';
import '../ml/hand_landmark.dart';
import '../ml/sibi_classifier.dart';
import '../state/sibi_state.dart';
import '../ml/sibi_vision_ffi.dart';
import 'theme.dart';

class CameraView extends StatefulWidget {
  final SibiClassifier classifier;

  const CameraView({super.key, required this.classifier});

  @override
  State<CameraView> createState() => CameraViewState();
}

class CameraViewState extends State<CameraView> {
  CameraController? _controller;
  mp.HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<mp.Hand>>? _landmarkSubscription;
  bool _isCameraInitializing = false;
  bool _isStreamProcessing = false;
  CameraLensDirection _preferredLensDirection = CameraLensDirection.front;
  static List<CameraDescription>? _cachedCameras;
  
  // Debouncing State untuk Pengetikan Huruf
  String _lastConfirmedChar = '';
  String _currentBufferChar = '';
  DateTime? _bufferStartTime;
  final Duration _debounceThreshold = const Duration(milliseconds: 1000);

  // FPS tracking variables
  int _fpsFrameCount = 0;
  DateTime? _fpsStartTime;
  double _currentCalculatedFps = 0.0;

  // Windows FFI variables
  SibiVisionFFI? _ffi;
  bool _isFfiProcessing = false;
  ffi.Pointer<ffi.Uint8>? _ffiImageBuffer;
  ffi.Pointer<ffi.Int32>? _ffiImageSizePtr;
  ffi.Pointer<ffi.Float>? _ffiLandmarksPtr;
  ffi.Pointer<ffi.Int32>? _ffiPredIndexPtr;
  ffi.Pointer<ffi.Float>? _ffiPredConfidencePtr;
  Timer? _ffiTimer;

  bool _wasPaused = false;
  late SibiState _sibiState;

  @override
  void initState() {
    super.initState();
    _sibiState = Provider.of<SibiState>(context, listen: false);
    _sibiState.addListener(_onStateChanged);

    // Jalankan kamera secara otomatis jika di Android/Mobile
    if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initCameraAndPlugin();
      });
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      // Langsung jalankan FFI Windows secara otomatis
      WidgetsBinding.instance.addPostFrameCallback((_) {
        initWindowsFFI();
      });
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (_sibiState.isPaused != _wasPaused) {
      _wasPaused = _sibiState.isPaused;
      if (_wasPaused) {
        // Mode jeda diaktifkan: Matikan kamera secara fisik
        if (defaultTargetPlatform == TargetPlatform.android) {
          _disposeCamera();
        } else {
          _disposeWindowsFFI();
        }
      } else {
        // Mode jeda dimatikan: Hidupkan kembali kamera
        if (defaultTargetPlatform == TargetPlatform.android) {
          _initCameraAndPlugin();
        } else {
          initWindowsFFI();
        }
      }
    }
  }

  Future<void> initWindowsFFI() async {
    final state = Provider.of<SibiState>(context, listen: false);
    setState(() => _isCameraInitializing = true);
    state.setCameraActive(false, message: 'Memulai Sistem...');

    try {
      // Alokasikan memori pointer C++ (10MB cukup untuk gambar JPEG Full HD)
      _ffiImageBuffer = malloc.allocate<ffi.Uint8>(10 * 1024 * 1024);
      _ffiImageSizePtr = malloc.allocate<ffi.Int32>(4);
      _ffiLandmarksPtr = malloc.allocate<ffi.Float>(126 * 4);
      _ffiPredIndexPtr = malloc.allocate<ffi.Int32>(4);
      _ffiPredConfidencePtr = malloc.allocate<ffi.Float>(4);

      _ffi = SibiVisionFFI();

      // Cari model di folder flutter_assets
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      final modelPath = "$exeDir\\data\\flutter_assets\\assets\\hand_landmarker.task";
      final classifierPath = "$exeDir\\data\\flutter_assets\\assets\\sibi_classifier.tflite";

      debugPrint("Memuat model MediaPipe FFI Windows: $modelPath");
      debugPrint("Memuat model TFLite Classifier Windows: $classifierPath");

      final success = _ffi!.init(
        modelPath: modelPath,
        classifierPath: classifierPath,
        numHands: 2,
      );
      if (!success) {
        state.setCameraActive(false, message: 'Gagal memuat model MediaPipe FFI.');
        setState(() => _isCameraInitializing = false);
        return;
      }

      state.setBridgeConnected(true);
      state.setCameraActive(true, message: 'Sistem Aktif');

      // Mulai timer untuk memproses frame
      _ffiTimer = Timer.periodic(const Duration(milliseconds: 30), (_) => _processFfiFrame());
    } catch (e) {
      debugPrint("Gagal menginisialisasi FFI Windows: $e");
      state.setCameraActive(false, message: 'Gagal mendeteksi kamera Windows.');
    } finally {
      setState(() => _isCameraInitializing = false);
    }
  }

  void _processFfiFrame() {
    if (_ffi == null || _isFfiProcessing || !mounted) return;
    final state = Provider.of<SibiState>(context, listen: false);
    if (state.isPaused) return;

    _isFfiProcessing = true;

    try {
      final detectedCount = _ffi!.process(
        outImageDataPtr: _ffiImageBuffer!,
        outImageSizePtr: _ffiImageSizePtr!,
        outLandmarksPtr: _ffiLandmarksPtr!,
        outPredIndexPtr: _ffiPredIndexPtr!,
        outPredConfidencePtr: _ffiPredConfidencePtr!,
        maxHands: 2,
      );

      if (detectedCount < 0) {
        // Frame kosong atau error kamera
        _isFfiProcessing = false;
        return;
      }

      _calculateFps();

      // Ambil ukuran JPEG dan salin bytes
      final jpegSize = _ffiImageSizePtr!.value;
      if (jpegSize > 0) {
        final jpegBytes = _ffiImageBuffer!.asTypedList(jpegSize);
        final Uint8List frameBytes = Uint8List.fromList(jpegBytes);
        state.updateStreamedImage(frameBytes);
      }

      // Ambil koordinat landmark
      final List<AppHand> detectedHands = [];
      if (detectedCount > 0) {
        final landmarksList = _ffiLandmarksPtr!.asTypedList(2 * 21 * 3);
        
        for (int i = 0; i < detectedCount; ++i) {
          final List<AppLandmark> lms = [];
          for (int j = 0; j < 21; ++j) {
            int baseIdx = (i * 21 + j) * 3;
            lms.add(AppLandmark(
              x: landmarksList[baseIdx].toDouble(),
              y: landmarksList[baseIdx + 1].toDouble(),
              z: landmarksList[baseIdx + 2].toDouble(),
            ));
          }
          detectedHands.add(AppHand(landmarks: lms));
        }
      }

      state.updateDetectedHands(detectedHands);

      // Jalankan klasifikasi model secara native
      final startTime = DateTime.now();
      
      String label = 'Menunggu Gesture...';
      double confidence = 0.0;
      final predIndex = _ffiPredIndexPtr!.value;
      final predConfidence = _ffiPredConfidencePtr!.value;
      
      if (detectedCount > 0 && predIndex >= 0) {
        label = widget.classifier.getLabelFromIndex(predIndex);
        confidence = predConfidence;
      }

      final endTime = DateTime.now();
      final inferenceTimeMs = (endTime.difference(startTime).inMicroseconds) / 1000.0;

      state.updatePerformanceMetrics(
        fps: _currentCalculatedFps > 0 ? _currentCalculatedFps : 30.0,
        inferenceTimeMs: inferenceTimeMs,
        latencyMs: inferenceTimeMs + 5.0,
        confidence: confidence,
      );

      _processDebouncedPrediction(label);
    } catch (e) {
      debugPrint("Error memproses frame FFI Windows: $e");
    } finally {
      _isFfiProcessing = false;
    }
  }

  void _disposeWindowsFFI() {
    _ffiTimer?.cancel();
    _ffiTimer = null;
    
    _ffi?.close();
    _ffi = null;

    if (_ffiImageBuffer != null) {
      malloc.free(_ffiImageBuffer!);
      _ffiImageBuffer = null;
    }
    if (_ffiImageSizePtr != null) {
      malloc.free(_ffiImageSizePtr!);
      _ffiImageSizePtr = null;
    }
    if (_ffiLandmarksPtr != null) {
      malloc.free(_ffiLandmarksPtr!);
      _ffiLandmarksPtr = null;
    }
    if (_ffiPredIndexPtr != null) {
      malloc.free(_ffiPredIndexPtr!);
      _ffiPredIndexPtr = null;
    }
    if (_ffiPredConfidencePtr != null) {
      malloc.free(_ffiPredConfidencePtr!);
      _ffiPredConfidencePtr = null;
    }

    final state = Provider.of<SibiState>(context, listen: false);
    state.setBridgeConnected(false);
    state.updateStreamedImage(null);
    state.updateDetectedHands([]);
    state.setCameraActive(false, message: 'Sistem dimatikan.');
  }

  Future<void> _initCameraAndPlugin() async {
    final state = Provider.of<SibiState>(context, listen: false);

    setState(() => _isCameraInitializing = true);
    state.setCameraActive(false, message: 'Memulai Sistem...');

    try {
      if (_cachedCameras == null || _cachedCameras!.isEmpty) {
        _cachedCameras = await availableCameras();
      }
      final cameras = _cachedCameras!;
      if (cameras.isEmpty) {
        state.setCameraActive(false, message: 'Perangkat tidak ditemukan.', permissionDenied: false);
        setState(() => _isCameraInitializing = false);
        return;
      }

      // Cari kamera sesuai arah preferensi (depan/belakang), jika tidak ada pakai yang tersedia
      final camera = cameras.firstWhere(
        (cam) => cam.lensDirection == _preferredLensDirection,
        orElse: () => cameras.first,
      );
      
      // Update preferensi dengan yang sebenarnya didapat
      _preferredLensDirection = camera.lensDirection;

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.yuv420
            : null,
      );

      try {
        await _controller!.initialize();
      } catch (e) {
        debugPrint('Camera initialization failed: $e');
        if (mounted) {
          state.setCameraActive(false, message: 'Kamera gagal diakses. Coba turunkan resolusi atau gunakan kamera lain.', permissionDenied: true);
          setState(() => _isCameraInitializing = false);
        }
        return;
      }

      // Hanya inisialisasi MediaPipe jika berjalan di platform Android
      final isAndroid = defaultTargetPlatform == TargetPlatform.android;
      
      if (isAndroid) {
        try {
          if (_landmarkerPlugin == null) {
            _landmarkerPlugin = mp.HandLandmarkerPlugin.create(
              numHands: 2,
              minHandDetectionConfidence: 0.7,
              delegate: mp.HandLandmarkerDelegate.gpu,
            );

            // Listen ke hasil stream koordinat hand landmarks dari MediaPipe native
            _landmarkSubscription = _landmarkerPlugin!.landmarkStream.listen(_onLandmarksDetected);
          }
          
          // Mulai aliran frame kamera secara asinkron dengan pembatasan frame rate
          await _controller!.startImageStream((CameraImage image) {
            if (!_isStreamProcessing && _landmarkerPlugin != null && _controller != null) {
              _isStreamProcessing = true;
              try {
                _landmarkerPlugin!.processFrame(
                  image,
                  _controller!.description.sensorOrientation,
                );
              } catch (e) {
                debugPrint('Error memproses frame kamera: $e');
                _isStreamProcessing = false;
              }
            }
          });
        } catch (mlErr) {
          debugPrint('Gagal menginisialisasi MediaPipe native: $mlErr');
          if (mounted) {
            state.setModelStatus(false, message: 'Gagal inisialisasi MediaPipe. Silakan gunakan Mode Simulator.');
          }
        }
      }

      // Beri jeda sejenak agar UI sempat me-render frame pertama kamera
      // sebelum memblokir thread untuk memuat model MediaPipe yang berat
      await Future.delayed(const Duration(milliseconds: 250));

      if (mounted) {
        state.setCameraActive(true, message: 'Sistem Aktif');
        setState(() => _isCameraInitializing = false);
      }
    } catch (e) {
      debugPrint('Error inisialisasi kamera: $e');
      if (mounted) {
        state.setCameraActive(false, message: 'Gagal mengakses kamera. Pastikan izin telah diberikan.', permissionDenied: true);
        setState(() => _isCameraInitializing = false);
      }
    }
  }

  /// Callback saat landmark tangan terdeteksi dari MediaPipe stream (Android Only)
  void _onLandmarksDetected(List<mp.Hand> hands) {
    if (!mounted) return;
    final state = Provider.of<SibiState>(context, listen: false);
    
    if (state.isPaused) {
      _isStreamProcessing = false;
      return;
    }

    try {
      // Hitung FPS Kamera/Inference
      _calculateFps();

      if (hands.isEmpty) {
        state.updateDetectedHands([]);
        // Reset buffer pengetikan jika tangan hilang dari layar
        _currentBufferChar = '';
        _bufferStartTime = null;
        return;
      }

      // Map model landmark dari plugin ke model terpadu kita dengan menyesuaikan rotasi/cermin ke koordinat layar
      final appHands = hands.map((mpHand) {
        final appLms = mpHand.landmarks.map((lm) {
          double xMapped = lm.x;
          double yMapped = lm.y;

          if (defaultTargetPlatform == TargetPlatform.android && _controller != null) {
            final isFront = _controller!.description.lensDirection == CameraLensDirection.front;
            final orientation = _controller!.description.sensorOrientation;

            if (isFront) {
              // Kamera Depan (Mirrored)
              if (orientation == 270) {
                xMapped = 1.0 - lm.y;
                yMapped = 1.0 - lm.x;
              } else if (orientation == 90) {
                xMapped = lm.y;
                yMapped = lm.x;
              } else if (orientation == 0) {
                xMapped = 1.0 - lm.x;
                yMapped = lm.y;
              } else if (orientation == 180) {
                xMapped = lm.x;
                yMapped = 1.0 - lm.y;
              }
            } else {
              // Kamera Belakang (Not Mirrored)
              if (orientation == 270) {
                xMapped = lm.y;
                yMapped = 1.0 - lm.x;
              } else if (orientation == 90) {
                xMapped = 1.0 - lm.y;
                yMapped = lm.x;
              } else if (orientation == 0) {
                xMapped = 1.0 - lm.x;
                yMapped = lm.y;
              } else if (orientation == 180) {
                xMapped = lm.x;
                yMapped = 1.0 - lm.y;
              }
            }
          }
          return AppLandmark(x: xMapped, y: yMapped, z: lm.z);
        }).toList();
        return AppHand(landmarks: appLms);
      }).toList();

      state.updateDetectedHands(appHands);

      // Jalankan klasifikasi model
      final startTime = DateTime.now();
      final classificationResult = widget.classifier.classify(appHands);
      final endTime = DateTime.now();

      final inferenceTimeMs = (endTime.difference(startTime).inMicroseconds) / 1000.0;

      // Update metrik ke state manager
      state.updatePerformanceMetrics(
        fps: _currentCalculatedFps > 0 ? _currentCalculatedFps : 25.0,
        inferenceTimeMs: inferenceTimeMs,
        latencyMs: inferenceTimeMs + 8.0, // Estimasi overhead buffer
        confidence: classificationResult.confidence,
      );

      // Proses hasil prediksi dengan debouncer
      _processDebouncedPrediction(classificationResult.label);
    } finally {
      _isStreamProcessing = false;
    }
  }

  /// Algoritma Debouncing Pengetikan Kata/Huruf Real-time
  void _processDebouncedPrediction(String label) {
    if (label == 'Menunggu Gesture...' || label == '?') {
      _bufferStartTime = null;
      _currentBufferChar = '';
      return;
    }

    final state = Provider.of<SibiState>(context, listen: false);

    if (_currentBufferChar == label) {
      // Label sama sedang ditahan
      final elapsed = DateTime.now().difference(_bufferStartTime!);
      if (elapsed >= _debounceThreshold) {
        // Cek jika huruf/kata ini berbeda dengan huruf terakhir yang diketik
        // atau jika berupa kata penuh (sehingga boleh diketik berurutan)
        final isWord = label.length > 1;
        
        if (isWord) {
          state.appendWord(label);
          // Mainkan feedback getar ringan jika didukung
          _triggerHapticFeedback();
          // Reset buffer
          _currentBufferChar = '';
          _bufferStartTime = null;
        } else {
          // Hanya ketik jika berbeda dengan huruf terakhir di ujung teks
          final currentText = state.translatedText;
          if (currentText.isEmpty || !currentText.endsWith(label)) {
            state.appendLetter(label);
            _triggerHapticFeedback();
          }
          // Reset buffer agar tidak mengetik huruf yang sama berulang-ulang tanpa jeda
          _currentBufferChar = '';
          _bufferStartTime = null;
        }
      }
    } else {
      // Label baru terdeteksi, mulai hitung waktu buffer baru
      _currentBufferChar = label;
      _bufferStartTime = DateTime.now();
    }
  }

  void _triggerHapticFeedback() {
    // Memberikan sentuhan getar lembut (mock/platform feedback)
    kIsWeb ? null : SystemSound.play(SystemSoundType.click);
  }

  void _calculateFps() {
    _fpsFrameCount++;
    final now = DateTime.now();
    _fpsStartTime ??= now;

    final diff = now.difference(_fpsStartTime!);
    if (diff.inSeconds >= 1) {
      _currentCalculatedFps = _fpsFrameCount / (diff.inMilliseconds / 1000.0);
      _fpsFrameCount = 0;
      _fpsStartTime = now;
    }
  }

  Future<void> _disposeCamera({bool disposePlugin = false}) async {
    _isStreamProcessing = false;
    
    if (disposePlugin) {
      _landmarkSubscription?.cancel();
      _landmarkSubscription = null;
      _landmarkerPlugin?.dispose();
      _landmarkerPlugin = null;
    }
    
    if (_controller != null) {
      try {
        if (_controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
          await Future.delayed(const Duration(milliseconds: 150)); // Jeda 150ms agar native stream bersih
        }
      } catch (_) {}
      try {
        await _controller!.dispose();
      } catch (_) {}
      _controller = null;
    }
  }

  Future<void> _toggleCameraLens() async {
    if (_isCameraInitializing) return;
    
    setState(() {
      _preferredLensDirection = _preferredLensDirection == CameraLensDirection.front 
          ? CameraLensDirection.back 
          : CameraLensDirection.front;
    });
    
    await _disposeCamera(disposePlugin: false);
    _initCameraAndPlugin();
  }

  @override
  void dispose() {
    _sibiState.removeListener(_onStateChanged);
    _disposeCamera(disposePlugin: true);
    _disposeWindowsFFI();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<SibiState>(context);

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

    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    
    if (isWindows) {
      if (state.isBridgeConnected && state.streamedImageBytes != null) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Image.memory(
                  state.streamedImageBytes!,
                  gaplessPlayback: true,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: LandmarkPainter(
                    hands: state.detectedHands,
                    previewSize: const Size(640, 480),
                    lensDirection: CameraLensDirection.front,
                    sensorOrientation: 0,
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
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
            ],
          ),
        );
      } else {
        if (_isCameraInitializing || (state.isBridgeConnected && state.streamedImageBytes == null)) {
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

        return Container(
          padding: const EdgeInsets.all(24),
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
                  'Tekan tombol START hijau di bawah untuk menghidupkan kamera',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (_isCameraInitializing) {
      return Container(
        color: Colors.transparent,
        height: double.infinity,
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.electricIndigo),
        ),
      );
    }

    if (!state.isCameraActive || _controller == null || !_controller!.value.isInitialized) {
      return Container(
        padding: const EdgeInsets.all(24),
        color: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off_rounded, size: 64, color: AppTheme.dangerRose),
              const SizedBox(height: 16),
              Text(
                'Sensor Kamera Tidak Tersedia',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppTheme.dangerRose),
              ),
              const SizedBox(height: 12),
              Text(
                state.cameraStatusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _initCameraAndPlugin,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba Lagi'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceDark),
              ),
            ],
          ),
        ),
      );
    }

    // Kamera berhasil aktif
    final controller = _controller!;
    final previewSize = controller.value.previewSize!;
    final previewAspectRatio = previewSize.height / previewSize.width;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview & 3. Custom Painter Overlay
          Center(
            child: AspectRatio(
              aspectRatio: previewAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(controller),
                  CustomPaint(
                    painter: LandmarkPainter(
                      hands: state.detectedHands,
                      previewSize: previewSize,
                      lensDirection: controller.description.lensDirection,
                      sensorOrientation: controller.description.sensorOrientation,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 2. Corner Brackets (Siku Pembatas)
          Positioned.fill(
            child: CustomPaint(
              painter: CornerBracketsPainter(
                color: Colors.white.withOpacity(0.5),
                bracketLength: 30,
                strokeWidth: 2,
              ),
            ),
          ),

          // 4. Status Badge Overlay
          Positioned(
            top: 16,
            left: 16,
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


          // 6. Tombol Balik Kamera (Hanya untuk Mobile)
          if (!isWindows)
            Positioned(
              top: 16,
              right: 72,
              child: Material(
                color: Colors.black.withOpacity(0.5),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.flip_camera_android_rounded, color: Colors.white),
                  tooltip: 'Balik Kamera',
                  onPressed: _toggleCameraLens,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// CustomPainter untuk melukis 21 landmark tangan dan garis penghubungnya
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

    // Paint untuk titik Landmark
    final nodePaint = Paint()
      ..color = AppTheme.electricCyan
      ..style = PaintingStyle.fill;

    // Paint untuk garis sendi
    final linePaint = Paint()
      ..color = AppTheme.electricIndigo.withOpacity(0.8)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // Struktur koneksi antar landmark tangan MediaPipe (21 titik)
    const connections = [
      [0, 1], [1, 2], [2, 3], [3, 4], // Jempol
      [0, 5], [5, 6], [6, 7], [7, 8], // Telunjuk
      [5, 9], [9, 10], [10, 11], [11, 12], // Tengah
      [9, 13], [13, 14], [14, 15], [15, 16], // Manis
      [13, 17], [0, 17], [17, 18], [18, 19], [19, 20], // Kelingking
    ];

    for (final hand in hands) {
      // 1. Gambar Garis Penghubung Sendi
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

      // 2. Gambar Titik Landmark
      for (int i = 0; i < hand.landmarks.length; i++) {
        final landmark = hand.landmarks[i];
        final dx = landmark.x * size.width;
        final dy = landmark.y * size.height;

        // Beri warna khusus pada ujung jari untuk estetika
        if (i == 4 || i == 8 || i == 12 || i == 16 || i == 20) {
          nodePaint.color = AppTheme.neonPurple;
        } else if (i == 0) {
          nodePaint.color = AppTheme.successEmerald; // Pergelangan tangan
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

/// CustomPainter untuk melukis kurung sudut pembatas (Corner brackets) seperti pada desain mockup
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
      ..strokeCap = StrokeCap.square; // Sudut lancip rata

    final w = size.width;
    final h = size.height;

    // Kiri Atas
    canvas.drawPath(
      Path()
        ..moveTo(0, bracketLength)
        ..lineTo(0, 0)
        ..lineTo(bracketLength, 0),
      paint,
    );

    // Kanan Atas
    canvas.drawPath(
      Path()
        ..moveTo(w - bracketLength, 0)
        ..lineTo(w, 0)
        ..lineTo(w, bracketLength),
      paint,
    );

    // Kiri Bawah
    canvas.drawPath(
      Path()
        ..moveTo(0, h - bracketLength)
        ..lineTo(0, h)
        ..lineTo(bracketLength, h),
      paint,
    );

    // Kanan Bawah
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
