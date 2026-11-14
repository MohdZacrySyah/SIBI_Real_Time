import 'dart:math' as math;

/// A unified representation of a single 3D coordinate point.
class AppLandmark {
  final double x;
  final double y;
  final double z;

  AppLandmark({
    required this.x,
    required this.y,
    required this.z,
  });

  /// Factory constructor to map from MediaPipe landmark format.
  factory AppLandmark.fromMap(Map<String, dynamic> map) {
    return AppLandmark(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      z: (map['z'] as num).toDouble(),
    );
  }

  /// Converts this landmark to a list of double coordinates.
  List<double> toList() => [x, y, z];

  @override
  String toString() => 'AppLandmark(x: $x, y: $y, z: $z)';
}

/// A unified representation of a hand containing 21 landmark points.
class AppHand {
  final List<AppLandmark> landmarks;

  AppHand({required this.landmarks}) {
    assert(landmarks.length == 21, 'Sebuah tangan harus memiliki tepat 21 landmark.');
  }

  /// Helper to convert 21 landmarks into a single flat vector [63]
  List<double> toFlatVector() {
    final List<double> vector = [];
    for (var lm in landmarks) {
      vector.addAll(lm.toList());
    }
    return vector;
  }

  /// Helper to convert 21 landmarks into wrist-relative coordinate vector [63]
  /// sesuai dengan format training dataset SIBI (lm - wrist).
  List<double> toWristRelativeRawVector({bool mirror = false}) {
    if (landmarks.isEmpty) return List.filled(63, 0.0);
    final wrist = landmarks[0];
    final List<double> vector = [];
    final double mirrorFactor = mirror ? -1.0 : 1.0;

    for (var lm in landmarks) {
      vector.add((lm.x - wrist.x) * mirrorFactor);
      vector.add(lm.y - wrist.y);
      vector.add(lm.z - wrist.z);
    }
    return vector;
  }

  /// Helper to convert 21 landmarks into a wrist-relative + scale-normalized flat vector [63]
  List<double> toWristRelativeVector({bool mirror = false}) {
    if (landmarks.isEmpty) return List.filled(63, 0.0);
    final wrist = landmarks[0];
    final middleBase = landmarks[9];

    final dx = middleBase.x - wrist.x;
    final dy = middleBase.y - wrist.y;
    final dz = middleBase.z - wrist.z;
    double scale = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (scale < 1e-4) {
      scale = 1.0;
    }

    final List<double> vector = [];
    final double mirrorFactor = mirror ? -1.0 : 1.0;
    
    for (var lm in landmarks) {
      vector.add(((lm.x - wrist.x) / scale) * mirrorFactor);
      vector.add((lm.y - wrist.y) / scale);
      vector.add((lm.z - wrist.z) / scale);
    }
    return vector;
  }
}
