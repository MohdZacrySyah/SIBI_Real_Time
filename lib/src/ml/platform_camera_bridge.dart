import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../ui/camera_view.dart';
import 'hand_landmark.dart';

abstract class PlatformCameraBridge {
  Future<void> initCamera(CameraViewState state);
  Future<void> disposeCamera(CameraViewState state);
  Widget buildPreview(BuildContext context, CameraViewState state);
  Future<void> toggleCamera(CameraViewState state) async {}
}

class CameraPrediction {
  final String label;
  final double confidence;
  final double inferenceTimeMs;
  final List<AppHand> hands;
  final Uint8List? imageBytes;
  final DateTime timestamp;

  CameraPrediction({
    required this.label,
    required this.confidence,
    required this.inferenceTimeMs,
    required this.hands,
    this.imageBytes,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
