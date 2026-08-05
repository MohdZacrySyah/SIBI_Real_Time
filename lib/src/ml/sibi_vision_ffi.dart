import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

/// ============================================================================
/// DART FFI (FOREIGN FUNCTION INTERFACE) BINDINGS UNTUK SIBI VISION NATIVE C++
/// ============================================================================
/// Berkas ini mendefinisikan tipe data, pointer, dan fungsi penghubung antara
/// aplikasi Flutter (Dart) dengan library biner C++ (`sibi_vision.dll`) secara langsung.

// -----------------------------------------------------------------------------
// 1. DEFINISI PENANDA TIPE FUNGSI: init_system (C++ & Dart)
// Fungsi ini memuat model MediaPipe, model klasifikasi TFLite, dan mengaktifkan kamera.
// -----------------------------------------------------------------------------
typedef InitSystemC = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<Utf8> modelPath,      // Path berkas model (.task) bertipe Utf8 pointer
  ffi.Pointer<Utf8> classifierPath, // Path berkas model klasifikasi (.tflite) bertipe Utf8 pointer
  ffi.Int32 numHands,               // Batas jumlah tangan yang dideteksi (32-bit Integer C++)
);
typedef InitSystemDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<Utf8> modelPath,
  ffi.Pointer<Utf8> classifierPath,
  int numHands,                     // Representasi int pada Dart
);

// -----------------------------------------------------------------------------
// 2. DEFINISI PENANDA TIPE FUNGSI: process_next_frame (C++ & Dart)
// Fungsi ini dipanggil periodik untuk membaca kamera, ekstraksi landmark, dan klasifikasi model.
// -----------------------------------------------------------------------------
typedef ProcessNextFrameC = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> handle,         // Pointer handle instansi sistem visi C++
  ffi.Pointer<ffi.Uint8> outImageData,     // Pointer penyimpan data citra JPEG hasil kompresi frame
  ffi.Pointer<ffi.Int32> outImageSize,     // Pointer penyimpan ukuran byte JPEG hasil kompresi
  ffi.Pointer<ffi.Float> outLandmarks,     // Pointer koordinat 21 landmark tangan (x, y, z)
  ffi.Pointer<ffi.Int32> outPredIndex,     // Pointer penyimpan indeks prediksi gerakan SIBI
  ffi.Pointer<ffi.Float> outPredConfidence, // Pointer penyimpan skor akurasi (confidence score)
  ffi.Int32 maxHands,                     // Maksimal tangan yang diproses
);
typedef ProcessNextFrameDart = int Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<ffi.Uint8> outImageData,
  ffi.Pointer<ffi.Int32> outImageSize,
  ffi.Pointer<ffi.Float> outLandmarks,
  ffi.Pointer<ffi.Int32> outPredIndex,
  ffi.Pointer<ffi.Float> outPredConfidence,
  int maxHands,
);

// -----------------------------------------------------------------------------
// 3. DEFINISI PENANDA TIPE FUNGSI: close_system (C++ & Dart)
// Fungsi ini mematikan sesi kamera OpenCV dan membebaskan alokasi memori di C++.
// -----------------------------------------------------------------------------
typedef CloseSystemC = ffi.Void Function(ffi.Pointer<ffi.Void> handle);
typedef CloseSystemDart = void Function(ffi.Pointer<ffi.Void> handle);

/// ============================================================================
/// KELAS UTAMA: SibiVisionFFI
/// ============================================================================
class SibiVisionFFI {
  late final ffi.DynamicLibrary _lib;         // Pustaka tautan dinamis (.dll)
  late final InitSystemDart _initSystem;       // Reference fungsi inisialisasi Dart
  late final ProcessNextFrameDart _processNextFrame; // Reference fungsi proses frame Dart
  late final CloseSystemDart _closeSystem;     // Reference fungsi penutup sistem Dart

  ffi.Pointer<ffi.Void>? _handle;             // Menyimpan alamat memori (handle) sistem native C++

  SibiVisionFFI() {
    // 1. Memuat berkas library DLL ke memori RAM
    _lib = _loadLibrary();
    
    // 2. Menghubungkan variabel fungsi Dart dengan simbol fungsi native di dalam DLL
    _initSystem = _lib
        .lookup<ffi.NativeFunction<InitSystemC>>('init_system')
        .asFunction<InitSystemDart>();
        
    _processNextFrame = _lib
        .lookup<ffi.NativeFunction<ProcessNextFrameC>>('process_next_frame')
        .asFunction<ProcessNextFrameDart>();
        
    _closeSystem = _lib
        .lookup<ffi.NativeFunction<CloseSystemC>>('close_system')
        .asFunction<CloseSystemDart>();
  }

  /// Memuat file Dynamic Link Library (.dll) pada sistem operasi Windows
  ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isWindows) {
      // Pastikan file sibi_vision.dll diletakkan satu folder dengan executable (.exe)
      return ffi.DynamicLibrary.open('sibi_vision.dll');
    }
    throw UnsupportedError('Platform ini tidak didukung oleh SibiVisionFFI.');
  }

  /// Inisialisasi model MediaPipe, TFLite Classifier, dan kamera OpenCV di memori native
  bool init({
    required String modelPath,
    required String classifierPath,
    required int numHands,
  }) {
    if (_handle != null) return true; // Sudah diinisialisasi sebelumnya

    // Mengonversi tipe String Dart ke Pointer karakter C-style UTF-8
    final modelPathPtr = modelPath.toNativeUtf8();
    final classifierPathPtr = classifierPath.toNativeUtf8();
    
    try {
      // Panggil fungsi init_system C++ di DLL
      _handle = _initSystem(modelPathPtr, classifierPathPtr, numHands);
      // Validasi alamat memori handle sistem (harus tidak nol)
      return _handle != null && _handle!.address != 0;
    } catch (e) {
      print("Error inisialisasi SIBI Vision FFI Windows: $e");
      return false;
    } finally {
      // Bebaskan memori pointer string setelah fungsi C++ selesai berjalan
      malloc.free(modelPathPtr);
      malloc.free(classifierPathPtr);
    }
  }

  /// Menjalankan pemrosesan per bingkai video secara native di C++
  int process({
    required ffi.Pointer<ffi.Uint8> outImageDataPtr,
    required ffi.Pointer<ffi.Int32> outImageSizePtr,
    required ffi.Pointer<ffi.Float> outLandmarksPtr,
    required ffi.Pointer<ffi.Int32> outPredIndexPtr,
    required ffi.Pointer<ffi.Float> outPredConfidencePtr,
    required int maxHands,
  }) {
    // Validasi apakah sistem C++ sudah siap di memori
    if (_handle == null || _handle!.address == 0) return -99;
    
    // Kirim pointer-pointer alokasi memori ke fungsi process_next_frame C++
    return _processNextFrame(
      _handle!,
      outImageDataPtr,
      outImageSizePtr,
      outLandmarksPtr,
      outPredIndexPtr,
      outPredConfidencePtr,
      maxHands,
    );
  }

  /// Menghentikan kamera OpenCV dan membebaskan instance memori native C++
  void close() {
    if (_handle != null && _handle!.address != 0) {
      _closeSystem(_handle!);
      _handle = null; // Kosongkan handle
    }
  }
}
