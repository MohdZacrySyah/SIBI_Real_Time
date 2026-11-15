import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart' as mp;
import 'package:provider/provider.dart';
import 'platform_camera_bridge.dart';
import '../../src/ui/camera_view.dart';
import 'hand_landmark.dart';
import '../state/sibi_state.dart';
import 'sibi_vision_ffi.dart';
import 'benchmark_logger.dart';

class NativeCameraBridge extends PlatformCameraBridge {
  CameraController? _controller;
  mp.HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<mp.Hand>>? _landmarkSubscription;
  bool _isStreamProcessing = false;
  DateTime? _frameStart; // waktu frame kamera diterima (Android)
  List<CameraDescription>? _cachedCameras;
  CameraLensDirection _preferredLensDirection = CameraLensDirection.front;

  // Windows FFI Isolate variables
  Isolate? _ffiIsolate;
  ReceivePort? _ffiReceivePort;
  SendPort? _ffiIsolateSendPort;

  bool _isCameraInitializing = false;
  bool _isCameraActive = false;

  @override
  Future<void> initCamera(CameraViewState state) async {
    if (Platform.isWindows) {
      await _initWindowsFFI(state);
    } else {
      await _initCameraAndPlugin(state);
    }
  }

  @override
  Future<void> disposeCamera(CameraViewState state) async {
    await BenchmarkLogger.instance.stopSession();
    if (Platform.isWindows) {
      await _disposeWindowsFFI(state);
    } else {
      await _disposeCamera(state);
    }
  }

  @override
  Future<void> toggleCamera(CameraViewState state) async {
    if (Platform.isAndroid || Platform.isIOS) {
      _preferredLensDirection = _preferredLensDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;
      await _disposeCamera(state);
      await _initCameraAndPlugin(state);
    }
  }

  // Getter helper untuk controller agar UI di camera_view.dart bisa membaca orientasi/arah lens
  CameraController? get controller => _controller;

  // ---------------------------------------------------------------------------
  // IMPLEMENTASI WINDOWS (FFI & BACKGROUND ISOLATE)
  // ---------------------------------------------------------------------------
  Future<void> _initWindowsFFI(CameraViewState state) async {
    if (_isCameraActive) return;
    final sibiState = Provider.of<SibiState>(state.context, listen: false);
    _isCameraInitializing = true;
    state.setInitializing(true);
    sibiState.setCameraActive(false, message: 'Memulai Sistem...');

    try {
      _ffiReceivePort = ReceivePort();
        final token = RootIsolateToken.instance;
        _ffiIsolate = await Isolate.spawn(_ffiIsolateEntry, IsolateInitData(_ffiReceivePort!.sendPort, token));

      _ffiReceivePort!.listen((message) {
        if (message is SendPort) {
          _ffiIsolateSendPort = message;
          final exePath = Platform.resolvedExecutable;
          final exeDir = File(exePath).parent.path;
          final modelPath = "$exeDir\\data\\flutter_assets\\assets\\hand_landmarker.task";
          final classifierPath = "$exeDir\\data\\flutter_assets\\assets\\sibi_alphabet_quantized.tflite";

          _ffiIsolateSendPort!.send(FfiRequest(
            'init',
            modelPath: modelPath,
            classifierPath: classifierPath,
            numHands: 1,
          ));
        } else if (message is FfiResponse) {
          if (message.initResult != null) {
            if (message.initResult == true) {
              sibiState.setBridgeConnected(true);
              sibiState.setCameraActive(true, message: 'Sistem Aktif (Windows)');
              _isCameraActive = true;
            } else {
              sibiState.setCameraActive(false, message: message.errorMessage ?? 'Gagal memuat model FFI.');
            }
            _isCameraInitializing = false;
            state.setInitializing(false);
          } else {
            // Pemrosesan frame normal dari background isolate
            if (!state.mounted) return;

            // Teruskan data frame dan deteksi tangan ke CameraViewState tanpa klasifikasi ganda
            state.onPredictionResult(CameraPrediction(
              label: '',
              confidence: 0.0,
              inferenceTimeMs: message.inferenceTimeMs,
              hands: message.hands,
              imageBytes: message.imageBytes,
              timestamp: message.frameStartMicros > 0
                  ? DateTime.fromMicrosecondsSinceEpoch(message.frameStartMicros)
                  : null,
              landmarkTimeMs: message.inferenceTimeMs,
            ));
          }
        }
      });
    } catch (e) {
      debugPrint("Gagal menginisialisasi FFI Windows: $e");
      sibiState.setCameraActive(false, message: 'Gagal mendeteksi kamera Windows.');
      _isCameraInitializing = false;
      state.setInitializing(false);
    }
  }

  Future<void> _disposeWindowsFFI(CameraViewState state) async {
    final sibiState = Provider.of<SibiState>(state.context, listen: false);
    if (_ffiIsolateSendPort != null) {
      _ffiIsolateSendPort!.send(FfiRequest('close'));
      _ffiIsolateSendPort = null;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _ffiReceivePort?.close();
    _ffiReceivePort = null;
    _ffiIsolate?.kill(priority: Isolate.beforeNextEvent);
    _ffiIsolate = null;

    sibiState.setBridgeConnected(false);
    sibiState.updateStreamedImage(null);
    sibiState.updateDetectedHands([]);
    sibiState.setCameraActive(false, message: 'Sistem dimatikan.');
    _isCameraActive = false;
  }

  // ---------------------------------------------------------------------------
  // IMPLEMENTASI MOBILE (ANDROID / IOS CAMERA & MEDIAPIPE)
  // ---------------------------------------------------------------------------
  Future<void> _initCameraAndPlugin(CameraViewState state) async {
    if (_isCameraActive) return;
    final sibiState = Provider.of<SibiState>(state.context, listen: false);
    _isCameraInitializing = true;
    state.setInitializing(true);
    sibiState.setCameraActive(false, message: 'Memulai Sistem...');

    try {
      if (_cachedCameras == null || _cachedCameras!.isEmpty) {
        _cachedCameras = await availableCameras();
      }
      final cameras = _cachedCameras!;
      if (cameras.isEmpty) {
        sibiState.setCameraActive(false, message: 'Perangkat tidak ditemukan.', permissionDenied: false);
        _isCameraInitializing = false;
        state.setInitializing(false);
        return;
      }

      final camera = cameras.firstWhere(
        (cam) => cam.lensDirection == _preferredLensDirection,
        orElse: () => cameras.first,
      );
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
        sibiState.setCameraActive(false, message: 'Kamera gagal diakses. Coba turunkan resolusi atau gunakan kamera lain.', permissionDenied: true);
        _isCameraInitializing = false;
        state.setInitializing(false);
        return;
      }

      final isAndroid = defaultTargetPlatform == TargetPlatform.android;
      if (isAndroid) {
        try {
          if (_landmarkerPlugin == null) {
            _landmarkerPlugin = mp.HandLandmarkerPlugin.create(
              numHands: 1,
              minHandDetectionConfidence: 0.7,
              delegate: mp.HandLandmarkerDelegate.gpu,
            );
            _landmarkSubscription = _landmarkerPlugin!.landmarkStream.listen((hands) {
              _onLandmarksDetected(hands, state);
            });
          }

          await _controller!.startImageStream((CameraImage image) {
            if (!_isStreamProcessing && _landmarkerPlugin != null && _controller != null) {
              _isStreamProcessing = true;
              _frameStart = DateTime.now();
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
          sibiState.setModelStatus(false, message: 'Gagal inisialisasi MediaPipe. Silakan gunakan Mode Simulator.');
        }
      }

      await Future.delayed(const Duration(milliseconds: 250));
      sibiState.setCameraActive(true, message: 'Sistem Aktif (Android)');
      _isCameraActive = true;
      _isCameraInitializing = false;
      state.setInitializing(false);
    } catch (e) {
      debugPrint('Error inisialisasi kamera: $e');
      sibiState.setCameraActive(false, message: 'Gagal mengakses kamera. Pastikan izin telah diberikan.', permissionDenied: true);
      _isCameraInitializing = false;
      state.setInitializing(false);
    }
  }

  Future<void> _disposeCamera(CameraViewState state) async {
    final sibiState = Provider.of<SibiState>(state.context, listen: false);
    if (_controller != null) {
      try {
        if (_controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
      } catch (e) {
        // Ignore
      }
      await _controller!.dispose();
      _controller = null;
    }

    if (_landmarkSubscription != null) {
      await _landmarkSubscription!.cancel();
      _landmarkSubscription = null;
    }
    if (_landmarkerPlugin != null) {
      _landmarkerPlugin = null;
    }

    sibiState.updateDetectedHands([]);
    sibiState.setCameraActive(false, message: 'Kamera Mati');
    _isCameraActive = false;
  }

  void _onLandmarksDetected(List<mp.Hand> hands, CameraViewState state) {
    final sibiState = Provider.of<SibiState>(state.context, listen: false);
    if (sibiState.isPaused) {
      _isStreamProcessing = false;
      return;
    }

    final frameStart = _frameStart ?? DateTime.now();
    final landmarkMs = DateTime.now().difference(frameStart).inMicroseconds / 1000.0;

    try {
      if (hands.isEmpty) {
        state.onPredictionResult(CameraPrediction(
          label: 'Menunggu Gesture...',
          confidence: 0.0,
          inferenceTimeMs: 0.0,
          hands: [],
          timestamp: frameStart,
          landmarkTimeMs: landmarkMs,
        ));
        return;
      }

      // Map model landmark dari plugin ke model terpadu kita dengan menyesuaikan rotasi/cermin ke koordinat layar
      final appHands = hands.map((mpHand) {
        final appLms = mpHand.landmarks.map((lm) {
          double xMapped = lm.x;
          double yMapped = lm.y;

          if (_controller != null) {
            final isFront = _controller!.description.lensDirection == CameraLensDirection.front;
            final orientation = _controller!.description.sensorOrientation;

            int deviceRotation = 0;
            switch (_controller!.value.deviceOrientation) {
              case DeviceOrientation.portraitUp: deviceRotation = 0; break;
              case DeviceOrientation.landscapeLeft: deviceRotation = 90; break;
              case DeviceOrientation.portraitDown: deviceRotation = 180; break;
              case DeviceOrientation.landscapeRight: deviceRotation = 270; break;
            }

            int relativeRotation = isFront
                ? (orientation + deviceRotation) % 360
                : (orientation - deviceRotation + 360) % 360;

            if (isFront) {
              if (relativeRotation == 270) {
                xMapped = 1.0 - lm.y; yMapped = 1.0 - lm.x;
              } else if (relativeRotation == 90) {
                xMapped = lm.y; yMapped = lm.x;
              } else if (relativeRotation == 0) {
                xMapped = 1.0 - lm.x; yMapped = lm.y;
              } else if (relativeRotation == 180) {
                xMapped = lm.x; yMapped = 1.0 - lm.y;
              }
            } else {
              if (relativeRotation == 270) {
                xMapped = lm.y; yMapped = 1.0 - lm.x;
              } else if (relativeRotation == 90) {
                xMapped = 1.0 - lm.y; yMapped = lm.x;
              } else if (relativeRotation == 0) {
                xMapped = lm.x; yMapped = lm.y;
              } else if (relativeRotation == 180) {
                xMapped = 1.0 - lm.x; yMapped = 1.0 - lm.y;
              }
            }
          }
          return AppLandmark(x: xMapped, y: yMapped, z: lm.z);
        }).toList();
        return AppHand(landmarks: appLms);
      }).toList();

      state.onPredictionResult(CameraPrediction(
        label: '',
        confidence: 0.0,
        inferenceTimeMs: 0.0,
        hands: appHands,
        timestamp: frameStart,
        landmarkTimeMs: landmarkMs,
      ));
    } finally {
      _isStreamProcessing = false;
    }
  }

  // Tampilan pratinjau kamera native
  @override
  Widget buildPreview(BuildContext context, CameraViewState state) {
    final sibiState = Provider.of<SibiState>(context);

    // Untuk platform Windows FFI: Render JPEG image bytes dari OpenCV C++ Isolate (BoxFit.contain agar tidak terpotong)
    if (Platform.isWindows) {
      if (sibiState.streamedImageBytes != null && sibiState.streamedImageBytes!.isNotEmpty) {
        return SizedBox.expand(
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 640,
                height: 480,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      sibiState.streamedImageBytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                    CustomPaint(
                      painter: LandmarkPainter(
                        hands: sibiState.detectedHands,
                        previewSize: const Size(640, 480),
                        lensDirection: CameraLensDirection.front,
                        sensorOrientation: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.electricIndigo),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.electricIndigo),
        ),
      );
    }

    final previewSize = _controller!.value.previewSize!;
    final previewAspectRatio = previewSize.height / previewSize.width;

    return Center(
      child: AspectRatio(
        aspectRatio: previewAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_controller!),
            CustomPaint(
              painter: LandmarkPainter(
                hands: sibiState.detectedHands,
                previewSize: previewSize,
                lensDirection: _controller!.description.lensDirection,
                sensorOrientation: _controller!.description.sensorOrientation,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DATA CLASSES & HELPER ENTRY POINTS FOR WINDOWS FFI ISOLATE
// ---------------------------------------------------------------------------
class FfiRequest {
  final String command;
  final String? modelPath;
  final String? classifierPath;
  final int? numHands;
  FfiRequest(this.command, {this.modelPath, this.classifierPath, this.numHands});
}

class FfiResponse {
  final Uint8List? imageBytes;
  final List<AppHand> hands;
  final String label;
  final double confidence;
  final double inferenceTimeMs;
  final double latencyMs;
  final int frameStartMicros;
  final bool? initResult;
  final String? errorMessage;

  FfiResponse({
    this.imageBytes,
    required this.hands,
    required this.label,
    required this.confidence,
    required this.inferenceTimeMs,
    required this.latencyMs,
    this.frameStartMicros = 0,
    this.initResult,
    this.errorMessage,
  });
}

class IsolateInitData {
  final SendPort sendPort;
  final RootIsolateToken? token;
  IsolateInitData(this.sendPort, this.token);
}

void _ffiIsolateEntry(IsolateInitData initData) {
  if (initData.token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(initData.token!);
  }
  
  final ReceivePort isolateReceivePort = ReceivePort();
  initData.sendPort.send(isolateReceivePort.sendPort);

  SibiVisionFFI? ffiClient;
  bool isPaused = false;

  ffi.Pointer<ffi.Uint8>? imageBuffer;
  ffi.Pointer<ffi.Int32>? imageSizePtr;
  ffi.Pointer<ffi.Float>? landmarksPtr;
  ffi.Pointer<ffi.Int32>? predIndexPtr;
  ffi.Pointer<ffi.Float>? predConfidencePtr;

  isolateReceivePort.listen((message) async {
    if (message is FfiRequest) {
      switch (message.command) {
        case 'init':
          try {
            imageBuffer = malloc.allocate<ffi.Uint8>(10 * 1024 * 1024);
            imageSizePtr = malloc.allocate<ffi.Int32>(4);
            landmarksPtr = malloc.allocate<ffi.Float>(63 * 4);
            predIndexPtr = malloc.allocate<ffi.Int32>(4);
            predConfidencePtr = malloc.allocate<ffi.Float>(4);

            ffiClient = SibiVisionFFI();
            final success = ffiClient!.init(
              modelPath: message.modelPath!,
              classifierPath: message.classifierPath!,
              numHands: message.numHands!,
            );
            
            // --- CLASSIFIER DIHAPUS DARI ISOLATE KARENA CRASH DLL TFLITE_FLUTTER (Error 126) ---
            // SibiClassifier kini hanya dieksekusi di Main Isolate (di dalam camera_view.dart)
            
            initData.sendPort.send(FfiResponse(
              hands: [],
              label: '',
              confidence: 0.0,
              inferenceTimeMs: 0.0,
              latencyMs: 0.0,
              initResult: success,
            ));

            if (success) {
              isPaused = false;
              _runFfiLoop(
                ffiClient!,
                imageBuffer!,
                imageSizePtr!,
                landmarksPtr!,
                predIndexPtr!,
                predConfidencePtr!,
                initData.sendPort,
                () => isPaused,
              );
            }
          } catch (e) {
            initData.sendPort.send(FfiResponse(
              hands: [],
              label: '',
              confidence: 0.0,
              inferenceTimeMs: 0.0,
              latencyMs: 0.0,
              initResult: false,
              errorMessage: e.toString(),
            ));
          }
          break;
        case 'pause':
          isPaused = true;
          break;
        case 'resume':
          isPaused = false;
          break;
        case 'close':
          isPaused = true;
          ffiClient?.close();
          ffiClient = null;
          
          if (imageBuffer != null) malloc.free(imageBuffer!);
          if (imageSizePtr != null) malloc.free(imageSizePtr!);
          if (landmarksPtr != null) malloc.free(landmarksPtr!);
          if (predIndexPtr != null) malloc.free(predIndexPtr!);
          if (predConfidencePtr != null) malloc.free(predConfidencePtr!);
          
          isolateReceivePort.close();
          break;
      }
    }
  });
}

void _runFfiLoop(
  SibiVisionFFI ffiClient,
  ffi.Pointer<ffi.Uint8> imageBuffer,
  ffi.Pointer<ffi.Int32> imageSizePtr,
  ffi.Pointer<ffi.Float> landmarksPtr,
  ffi.Pointer<ffi.Int32> predIndexPtr,
  ffi.Pointer<ffi.Float> predConfidencePtr,
  SendPort mainSendPort,
  bool Function() isPausedFn,
) {
  void processSingleFrame() {
    if (isPausedFn()) {
      Future.delayed(const Duration(milliseconds: 100), processSingleFrame);
      return;
    }

    try {
      final startTime = DateTime.now();
      final detectedCount = ffiClient.process(
        outImageDataPtr: imageBuffer,
        outImageSizePtr: imageSizePtr,
        outLandmarksPtr: landmarksPtr,
        outPredIndexPtr: predIndexPtr,
        outPredConfidencePtr: predConfidencePtr,
        maxHands: 1,
      );

      if (detectedCount >= 0) {
        Uint8List? frameBytes;
        final jpegSize = imageSizePtr.value;
        if (jpegSize > 0) {
          final jpegBytes = imageBuffer.asTypedList(jpegSize);
          frameBytes = Uint8List.fromList(jpegBytes);
        }

        final List<AppHand> detectedHands = [];
        if (detectedCount > 0) {
          final landmarksList = landmarksPtr.asTypedList(1 * 21 * 3);
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

        String label = 'Menunggu Gesture...';
        double confidence = 0.0;
        
        // PENTING: Inference TFLite kini DILAKUKAN DI MAIN ISOLATE!
        // Isolate ini hanya mengirimkan koordinat tangan (detectedHands).

        final endTime = DateTime.now();
        final inferenceTimeMs = (endTime.difference(startTime).inMicroseconds) / 1000.0;

        mainSendPort.send(FfiResponse(
          imageBytes: frameBytes,
          hands: detectedHands,
          label: label,
          confidence: confidence,
          inferenceTimeMs: inferenceTimeMs,
          latencyMs: inferenceTimeMs,
          frameStartMicros: startTime.microsecondsSinceEpoch,
        ));
      }
    } catch (e) {
      // Ignore
    }

    Future.delayed(const Duration(milliseconds: 16), processSingleFrame);
  }

  processSingleFrame();
}

PlatformCameraBridge createCameraBridge() => NativeCameraBridge();

