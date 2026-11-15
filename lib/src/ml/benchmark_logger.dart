// Pencatat data pengukuran performa (benchmark) ke berkas CSV.
// Aktif hanya jika aplikasi dijalankan dengan: --dart-define=BENCH=true
export 'benchmark_logger_stub.dart'
    if (dart.library.io) 'benchmark_logger_io.dart';
