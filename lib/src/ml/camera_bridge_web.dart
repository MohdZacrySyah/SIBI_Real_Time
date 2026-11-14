import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/sibi_state.dart';
import '../ui/camera_view.dart';
import 'platform_camera_bridge.dart';

@JS('startWebCamera')
external JSPromise startWebCamera(
  JSString videoId,
  JSString canvasId,
  JSFunction callback,
);

@JS('stopWebCamera')
external void stopWebCamera();

@JS('sibiWebAiReady')
external JSBoolean? get sibiWebAiReady;

class WebCameraBridge extends PlatformCameraBridge {
  bool _isCameraActive = false;
  final String viewTypeId = 'sibi-webcam-view';

  WebCameraBridge() {
    // Daftarkan view factory HTML untuk kamera web
    ui_web.platformViewRegistry.registerViewFactory(
      viewTypeId,
      (int viewId) {
        final div = web.document.createElement('div') as web.HTMLDivElement
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.position = 'relative'
          ..style.backgroundColor = 'black'
          ..style.borderRadius = '14px'
          ..style.overflow = 'hidden';

        // Video tag (tersembunyi karena kita melukis di canvas)
        final video = web.document.createElement('video') as web.HTMLVideoElement
          ..id = 'webcam-video'
          ..setAttribute('autoplay', 'true')
          ..setAttribute('playsinline', 'true')
          ..style.display = 'none';

        // Canvas tag untuk menampilkan feed kamera dan landmark MediaPipe
        final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
          ..id = 'webcam-canvas'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'contain';

        div.appendChild(video);
        div.appendChild(canvas);
        return div;
      },
    );
  }

  @override
  Future<void> initCamera(CameraViewState state) async {
    if (_isCameraActive) return;
    
    final sibiState = Provider.of<SibiState>(state.context, listen: false);
    sibiState.setCameraActive(false, message: 'Menghubungkan Kamera...');
    
    try {
      // Tunggu hingga JS helper siap (menghindari race condition)
      int retries = 0;
      while (retries < 50) {
        try {
          if (sibiWebAiReady?.toDart ?? false) {
            break;
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 100));
        retries++;
      }
      
      if (retries >= 50) {
        throw Exception('JavaScript Web AI Helper tidak berhasil dimuat dalam waktu 5 detik.');
      }
      // Wrapper callback Javascript ke Dart
      final JSFunction predictionCallback = ((
        JSString label,
        JSNumber confidence,
        JSNumber inferenceTimeMs,
        JSString handsJson,
      ) {
        if (!state.mounted) return;
        
        final dartLabel = label.toDart;
        final dartConfidence = confidence.toDartDouble;
        final dartInferenceTime = inferenceTimeMs.toDartDouble;
        
        // Teruskan data prediksi ke CameraViewState untuk diproses terpadu
        state.onPredictionResult(CameraPrediction(
          label: dartLabel,
          confidence: dartConfidence,
          inferenceTimeMs: dartInferenceTime,
          hands: [], // Visualisasi digambar langsung oleh JS di kanvas
        ));
        
      }).toJS;
      
      // Panggil fungsi global Javascript helper kita dan tunggu hingga selesai
      final promise = startWebCamera('webcam-video'.toJS, 'webcam-canvas'.toJS, predictionCallback);
      await promise.toDart;
      
      _isCameraActive = true;
      sibiState.setCameraActive(true, message: 'Sistem Aktif (Web)');
    } catch (e) {
      debugPrint('Error starting Web Camera: $e');
      sibiState.setCameraActive(false, message: 'Gagal membuka kamera web.\nDetail: $e');
    }
  }

  @override
  Future<void> disposeCamera(CameraViewState state) async {
    if (!_isCameraActive) return;
    try {
      stopWebCamera();
    } catch (e) {
      debugPrint('Error stopping Web Camera: $e');
    }
    _isCameraActive = false;
    final sibiState = Provider.of<SibiState>(state.context, listen: false);
    sibiState.setCameraActive(false, message: 'Kamera Mati');
  }

  @override
  Widget buildPreview(BuildContext context, CameraViewState state) {
    return HtmlElementView(viewType: viewTypeId);
  }
}

PlatformCameraBridge createCameraBridge() => WebCameraBridge();
