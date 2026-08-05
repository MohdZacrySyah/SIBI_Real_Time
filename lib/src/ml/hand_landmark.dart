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
}
