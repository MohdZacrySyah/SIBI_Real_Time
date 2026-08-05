import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'hand_landmark.dart';

/// ============================================================================
/// STRUKTUR DATA HASH/PREDIKSI MODEL
/// ============================================================================
class PredictionResult {
  final String label;            // Label teks hasil penerjemahan (misal: 'A', 'Halo')
  final double confidence;       // Tingkat kepercayaan hasil prediksi (nilai 0.0 s.d 1.0)
  final String inferenceSource;  // Sumber inferensi (contoh: 'TFLite Model')

  PredictionResult({
    required this.label,
    required this.confidence,
    required this.inferenceSource,
  });
}

/// ============================================================================
/// KELAS UTAMA: SibiClassifier (Pengklasifikasi Isyarat SIBI)
/// ============================================================================
class SibiClassifier {
  Interpreter? _interpreter;       // Runner interpreter TFLite dari paket tflite_flutter
  bool _isTfliteLoaded = false;    // Status penanda apakah model berhasil dimuat
  String _lastErrorMessage = '';   // Menyimpan pesan kesalahan jika model gagal dimuat
  List<String> _dynamicLabels = []; // Daftar label kelas yang dimuat dari berkas labels.txt

  bool get isTfliteLoaded => _isTfliteLoaded;
  String get lastErrorMessage => _lastErrorMessage;

  /// Memuat model TensorFlow Lite (.tflite) dan daftar label secara asinkron
  Future<bool> initialize() async {
    try {
      if (kIsWeb) {
        _lastErrorMessage = 'TFLite tidak didukung di Web secara default dalam setup ini.';
        return false;
      }
      
      // 1. Memuat file biner model TensorFlow Lite dari folder Assets aplikasi
      // Pada Windows: library eksternal memanggil interpreter native DLL
      // Pada Android: library memanggil interpreter native shared object (.so)
      _interpreter = await Interpreter.fromAsset('assets/sibi_classifier.tflite');
      _isTfliteLoaded = true;

      // 2. Memuat daftar label secara dinamis dari file assets/labels.txt
      try {
        final labelsData = await rootBundle.loadString('assets/labels.txt');
        _dynamicLabels = labelsData.split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        debugPrint('Berhasil memuat ${_dynamicLabels.length} label dari assets/labels.txt');
      } catch (_) {
        debugPrint('File labels.txt tidak ditemukan, menggunakan label bawaan aplikasi.');
      }

      debugPrint('TFLite SIBI Classifier berhasil dimuat.');
      return true;
    } catch (e) {
      _isTfliteLoaded = false;
      _lastErrorMessage = e.toString();
      debugPrint('Gagal memuat TFLite SIBI Classifier: $e');
      return false;
    }
  }

  /// Melakukan inferensi/klasifikasi gerakan berdasarkan koordinat landmark tangan
  PredictionResult classify(List<AppHand> hands) {
    if (_isTfliteLoaded && _interpreter != null) {
      try {
        // ---------------------------------------------------------------------
        // 1. PENYIAPAN BUFFER INPUT MODEL (Format Shape: [1, 126])
        // Input model adalah vektor baris tunggal berisi 126 nilai float:
        // - 21 landmark * 3 sumbu (x, y, z) = 63 nilai per tangan
        // - 2 tangan * 63 nilai = 126 nilai total
        // ---------------------------------------------------------------------
        final List<double> flatLandmarks = [];
        for (int i = 0; i < 2; i++) {
          if (i < hands.length) {
            // Jika tangan terdeteksi, tambahkan 63 koordinatnya
            flatLandmarks.addAll(hands[i].toFlatVector());
          } else {
            // Jika tangan tidak terdeteksi, isi dengan nilai 0.0 (zero-padding)
            flatLandmarks.addAll(List.filled(63, 0.0));
          }
        }
        // Bungkus dalam array 2 dimensi [1, 126] sesuai requirement tensor input
        final inputBuffer = [flatLandmarks];
        
        // ---------------------------------------------------------------------
        // 2. PENYIAPAN BUFFER OUTPUT MODEL (Format Shape: [1, jumlah_kelas])
        // Menyimpan nilai probabilitas kecocokan untuk setiap kelas (softmax output)
        // ---------------------------------------------------------------------
        final numClasses = _dynamicLabels.isNotEmpty ? _dynamicLabels.length : 30;
        final outputBuffer = List.filled(1 * numClasses, 0.0).reshape([1, numClasses]);
        
        // ---------------------------------------------------------------------
        // 3. JALANKAN OPERASI INFERENSI TFLITE NATIVE
        // ---------------------------------------------------------------------
        _interpreter!.run(inputBuffer, outputBuffer);
        
        // ---------------------------------------------------------------------
        // 4. PENENTUAN PREDIKSI TERBAIK (ArgMax)
        // Cari kelas dengan probabilitas (skor kecocokan) tertinggi.
        // ---------------------------------------------------------------------
        final List<double> probabilities = List<double>.from(outputBuffer[0]);
        double maxProb = -1.0;
        int maxIndex = -1;
        
        for (int i = 0; i < probabilities.length; i++) {
          if (probabilities[i] > maxProb) {
            maxProb = probabilities[i];
            maxIndex = i;
          }
        }
        
        // Hanya terima prediksi jika tingkat akurasi (confidence) >= 50% (0.5)
        if (maxIndex != -1 && maxProb >= 0.5) {
          final label = getLabelFromIndex(maxIndex);
          return PredictionResult(
            label: label,
            confidence: maxProb,
            inferenceSource: 'TFLite Model',
          );
        }
      } catch (e) {
        debugPrint('Gagal menjalankan inferensi TFLite: $e');
      }
    }

    // Jika TFLite gagal atau tidak mendeteksi apa pun, kembalikan tanda Tanya
    return PredictionResult(
      label: '?',
      confidence: 0.0,
      inferenceSource: 'Tidak Ada TFLite',
    );
  }

  /// Memetakan indeks keluaran model TFLite ke Label teks karakter/huruf SIBI
  String getLabelFromIndex(int index) {
    // Gunakan daftar label dinamis jika file labels.txt berhasil dimuat
    if (_dynamicLabels.isNotEmpty) {
      if (index >= 0 && index < _dynamicLabels.length) {
        return _dynamicLabels[index];
      }
      return '?';
    }

    // Fallback daftar label statis bawaan aplikasi
    const labels = [
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N',
      'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
      'Halo', 'Saya', 'Terima Kasih', 'Sama-sama'
    ];
    if (index >= 0 && index < labels.length) {
      return labels[index];
    }
    return '?';
  }

  /// Tutup interpreter untuk membebaskan alokasi memori
  void dispose() {
    _interpreter?.close();
  }
}
