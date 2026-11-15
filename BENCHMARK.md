# Panduan Pengukuran Performa (Benchmark)

Logger CSV hanya aktif jika aplikasi dijalankan dengan `--dart-define=BENCH=true`.
Selalu gunakan build **release**.

## 1. Menjalankan
- Android (kabel USB): `flutter run --release --dart-define=BENCH=true -d <id_perangkat>`
  atau `flutter build apk --release --dart-define=BENCH=true` lalu instal APK.
- Windows: `flutter build windows --release --dart-define=BENCH=true`
  lalu jalankan `build\windows\x64\runner\Release\sibi_realtime.exe`.

## 2. Prosedur satu sesi
1. Pilih mode (Huruf / Kata / Otomatis), tekan **START**.
2. Lakukan skenario (lihat tabel di bawah), tekan **STOP**. Satu START–STOP = satu berkas CSV.
3. Catat nama berkas dan skenarionya.

| Skenario (Tabel 3.10) | Cara | Mode |
|---|---|---|
| Latency & inference time huruf | Peragakan huruf bergantian sampai ≥ 100 frame berisi tangan | Huruf |
| Latency & inference time kata | Peragakan ke-7 kata bergantian, ≥ 100 prediksi kata | Kata |
| Mode Otomatis | Campur huruf dan kata | Otomatis |
| FPS pipeline | 60 detik terus bergerak/tangan terlihat | masing-masing |
| Penggunaan jangka panjang | 10–15 menit tanpa berhenti | Otomatis |

## 3. Mengambil berkas
- Android: `adb pull /sdcard/Android/data/com.sibi.translator.sibi_realtime/files/bench ./bench_android`
- Windows: folder `bench` di samping `sibi_realtime.exe`.

## 4. Meringkas
`python tools/bench_summary.py ./bench_android ./bench_windows`
menghasilkan rerata, SD, dan p95 (juga `summary.csv`).

## 5. Kolom CSV
`elapsed_ms, platform, mode, engine, hand, label, confidence, fps, landmark_ms,
alpha_invoke_ms, word_invoke_ms, classify_ms, latency_ms, rss_mb`

- `landmark_ms`: Android = frame diterima hingga landmark siap (MediaPipe).
  Windows = durasi `process_next_frame` (kamera + landmark + JPEG), termasuk menunggu frame.
- `alpha_invoke_ms` / `word_invoke_ms`: waktu satu `interpreter.run()` Model 1 (rerata dua
  pemanggilan: asli dan cermin) / Model 2.
- `latency_ms`: frame diterima hingga hasil prediksi siap (sebelum penundaan debounce 350 ms
  dan buffer 30 frame untuk kata, yang dilaporkan terpisah).
- `rss_mb`: memori proses, dicuplik sekali per detik.
