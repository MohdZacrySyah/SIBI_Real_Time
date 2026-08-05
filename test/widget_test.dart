import 'package:flutter_test/flutter_test.dart';
import 'package:sibi_realtime/src/ml/hand_landmark.dart';
import 'package:sibi_realtime/src/ml/sibi_classifier.dart';
import 'package:sibi_realtime/src/state/sibi_state.dart';

void main() {
  group('Pengujian SIBI State Management', () {
    test('State awal harus memiliki parameter default yang sesuai', () {
      final state = SibiState();
      
      expect(state.isCameraActive, isFalse);
      expect(state.isModelLoaded, isFalse);
      expect(state.translatedText, isEmpty);
      expect(state.history, isEmpty);
      expect(state.fps, 0.0);
    });

    test('Menambah kata dan huruf harus memperbarui teks terjemahan', () {
      final state = SibiState();
      
      state.appendLetter('A');
      expect(state.translatedText, 'A');
      
      state.appendWord('Halo');
      expect(state.translatedText, 'A Halo');
      
      state.backspace();
      expect(state.translatedText, 'A Hal');
      
      state.clearText();
      expect(state.translatedText, isEmpty);
    });
  });

  group('Pengujian Klasifikasi SIBI (Geometric Rule-Based)', () {
    test('Klasifikasi default harus mengembalikan hasil menunggu gesture jika koordinat kosong/acak', () {
      final classifier = SibiClassifier();
      
      // Buat data tangan tiruan dengan 21 landmark tersebar agar tidak memicu deteksi 'O' secara tidak sengaja
      final dummyLms = List.generate(21, (i) => AppLandmark(x: i * 0.05, y: i * 0.05, z: i * 0.05));
      final dummyHand = AppHand(landmarks: dummyLms);
      
      final result = classifier.classify(dummyHand);

      expect(result.inferenceSource, 'Rule-Based Fallback');
      expect(result.label, isNotEmpty);
    });
  });
}
