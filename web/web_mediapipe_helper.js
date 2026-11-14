// ============================================================================
// SIBI REAL-TIME WEB CAMERA & ML HELPER
// ============================================================================

import { HandLandmarker, FilesetResolver } from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.8/+esm";

let activeStream = null;
let handLandmarker = null;
let tfliteModel = null;
let isRunning = false;
let animationFrameId = null;
let labels = [];

// Pencari path asset dinamis (mendukung debugging lokal & kompilasi rilis)
async function resolveAssetPath(filename) {
  const paths = [
    `assets/assets/${filename}`,
    `assets/${filename}`,
    filename
  ];
  for (let p of paths) {
    try {
      const res = await fetch(p);
      if (res.ok) {
        console.log(`Found asset at: ${p}`);
        return p;
      }
    } catch (e) {
      // Abaikan dan coba path berikutnya
    }
  }
  return `assets/assets/${filename}`; // Fallback default
}

// Memuat daftar label secara dinamis
let alphabetLabels = [];
let wordLabels = [];

async function loadLabels() {
  try {
    // 1. Coba muat alphabet_labels.txt
    try {
      const alphaPath = await resolveAssetPath("alphabet_labels.txt");
      const respA = await fetch(alphaPath);
      if (respA.ok) {
        const textA = await respA.text();
        alphabetLabels = textA.split("\n").map(l => l.trim()).filter(l => l.length > 0);
        labels = alphabetLabels;
      }
    } catch (_) {}

    // 2. Coba muat word_labels.txt
    try {
      const wordPath = await resolveAssetPath("word_labels.txt");
      const respW = await fetch(wordPath);
      if (respW.ok) {
        const textW = await respW.text();
        wordLabels = textW.split("\n").map(l => l.trim()).filter(l => l.length > 0);
      }
    } catch (_) {}

    // Fallback jika labels.txt masih dicari
    if (labels.length === 0) {
      try {
        const fallbackPath = await resolveAssetPath("labels.txt");
        const respF = await fetch(fallbackPath);
        if (respF.ok) {
          const textF = await respF.text();
          labels = textF.split("\n").map(l => l.trim()).filter(l => l.length > 0);
        }
      } catch (_) {}
    }

    if (labels.length === 0) {
      labels = Array.from({length: 26}, (_, i) => String.fromCharCode(65 + i));
    }
    console.log("Labels successfully loaded:", labels);
  } catch (e) {
    console.error("Failed to load labels:", e);
    labels = Array.from({length: 26}, (_, i) => String.fromCharCode(65 + i));
  }
}

// Inisialisasi MediaPipe Tasks-Vision dan TFLite Web
async function initWebAI() {
  await loadLabels();
  
  console.log("Initializing MediaPipe HandLandmarker...");
  const vision = await FilesetResolver.forVisionTasks(
    "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.8/wasm"
  );
  
  const landmarkerPath = await resolveAssetPath("hand_landmarker.task");
  
  handLandmarker = await HandLandmarker.createFromOptions(vision, {
    baseOptions: {
      modelAssetPath: landmarkerPath,
      delegate: "GPU"
    },
    runningMode: "VIDEO",
    numHands: 1
  });
  
  console.log("Initializing TensorFlow Lite Web Model...");
  // Atur path WASM untuk TFLite dari CDN guna mencegah kegagalan 404 lokal
  tflite.setWasmPath("https://cdn.jsdelivr.net/npm/@tensorflow/tfjs-tflite@0.0.1-alpha.9/dist/");
  
  let classifierPath = await resolveAssetPath("sibi_alphabet_quantized.tflite");
  try {
    tfliteModel = await tflite.loadTFLiteModel(classifierPath);
  } catch (loadErr) {
    console.warn("Primary quantized model load failed, falling back to sibi_classifier.tflite:", loadErr);
    classifierPath = await resolveAssetPath("sibi_classifier.tflite");
    tfliteModel = await tflite.loadTFLiteModel(classifierPath);
  }
  console.log("Web AI Systems initialized successfully.");
}

// Helper untuk mencari elemen di DOM utama, Shadow DOM, maupun di dalam IFrames (Flutter Platform Views)
function getElement(id) {
  // 1. Coba cari di DOM utama
  let el = document.getElementById(id);
  if (el) return el;
  
  // 2. Coba cari di dalam Shadow DOM milik Flutter Platform Views
  const views = document.querySelectorAll("flt-platform-view");
  for (let view of views) {
    if (view.shadowRoot) {
      el = view.shadowRoot.getElementById(id) || view.shadowRoot.querySelector(`#${id}`);
      if (el) return el;
    }
  }
  
  // 3. Coba cari di dalam IFrame (jika Flutter merender platform view sebagai iframe)
  const iframes = document.querySelectorAll("iframe");
  for (let iframe of iframes) {
    try {
      const doc = iframe.contentDocument || iframe.contentWindow.document;
      if (doc) {
        el = doc.getElementById(id) || doc.querySelector(`#${id}`);
        if (el) return el;
      }
    } catch (e) {
      // Abaikan jika terkena cross-origin restriction (seharusnya localhost aman)
    }
  }
  
  // 4. Carian rekursif di semua element dengan shadowRoot
  const allElements = document.querySelectorAll("*");
  for (let element of allElements) {
    if (element.shadowRoot) {
      el = element.shadowRoot.getElementById(id) || element.shadowRoot.querySelector(`#${id}`);
      if (el) return el;
    }
  }
  return null;
}

async function startWebCamera(videoElementId, canvasElementId, onPredictionCallback) {
  if (isRunning) return;
  
  try {
    if (!handLandmarker || !tfliteModel) {
      await initWebAI();
    }
    
    // Tunggu hingga elemen video dan canvas tersedia di DOM (menghindari race condition render HTML)
    let video = null;
    let canvas = null;
    let elementRetries = 0;
    while (elementRetries < 30) {
      video = getElement(videoElementId);
      canvas = getElement(canvasElementId);
      if (video && canvas) {
        break;
      }
      await new Promise(resolve => setTimeout(resolve, 50));
      elementRetries++;
    }
    
    if (!video || !canvas) {
      throw new Error("Elemen Video atau Canvas tidak ditemukan di DOM setelah beberapa saat.");
    }
    
    const ctx = canvas.getContext("2d");
    
    activeStream = await navigator.mediaDevices.getUserMedia({
      video: { width: 640, height: 480, facingMode: "user" },
      audio: false
    });
    
    video.srcObject = activeStream;
    video.play();
    
    isRunning = true;
    
    video.onloadeddata = () => {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      
      let lastVideoTime = -1;
      let lastInferenceTime = 0;
      const inferenceInterval = 100; // Jalankan deteksi AI setiap 100ms (10 FPS) untuk efisiensi CPU
      let latestLandmarks = null;
      
      const sequenceLength = 30;
      const landmarkBuffer = [];

      function renderLoop() {
        if (!isRunning) return;
        
        const now = performance.now();
        
        // 1. Render gambar cermin (flipped horizontally) agar feed terasa alami seperti cermin - dibungkus try-catch agar aman
        try {
          ctx.save();
          ctx.translate(canvas.width, 0);
          ctx.scale(-1, 1);
          
          // Gambar frame video
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          
          // Gambar landmark tangan di atas frame cermin
          if (latestLandmarks) {
            drawLandmarks(ctx, latestLandmarks);
          }
          ctx.restore();
        } catch (drawErr) {
          console.error("Failed to render camera frame to canvas:", drawErr);
        }
        
        // 2. Lakukan inferensi AI secara terjadwal - dibungkus try-catch agar kegagalan AI tidak membekukan preview kamera
        try {
          if (video.currentTime !== lastVideoTime && (now - lastInferenceTime >= inferenceInterval)) {
            lastVideoTime = video.currentTime;
            lastInferenceTime = now;
            
            let startTime = performance.now();
            
            // MediaPipe memproses video asli (tidak cermin) agar koordinat landmark konsisten
            const results = handLandmarker.detectForVideo(video, now);
            
            let label = "Menunggu Gesture...";
            let confidence = 0.0;
            let handsData = [];
            
            if (results.landmarks && results.landmarks.length > 0) {
              const landmarks = results.landmarks[0];
              latestLandmarks = landmarks;
              handsData = landmarks;
              
              // Normalisasi relatif pergelangan tangan (wrist-relative) & Skala (scale-invariant)
              const wrist = landmarks[0];
              const middleBase = landmarks[9];
              const dx = middleBase.x - wrist.x;
              const dy = middleBase.y - wrist.y;
              const dz = middleBase.z - wrist.z;
              let scale = Math.sqrt(dx * dx + dy * dy + dz * dz);
              if (scale < 1e-4) {
                scale = 1.0;
              }

              const frameVector = [];
              for (let lm of landmarks) {
                frameVector.push((lm.x - wrist.x) / scale);
                frameVector.push((lm.y - wrist.y) / scale);
                frameVector.push((lm.z - wrist.z) / scale);
              }

              landmarkBuffer.push(frameVector);
              if (landmarkBuffer.length > sequenceLength) {
                landmarkBuffer.shift();
              }

              // Pad sequence jika kurang dari 30 frame
              const paddedSequence = [];
              if (landmarkBuffer.length < sequenceLength) {
                const padCount = sequenceLength - landmarkBuffer.length;
                const firstFrame = landmarkBuffer[0];
                for (let i = 0; i < padCount; i++) {
                  paddedSequence.push(firstFrame);
                }
                for (let f of landmarkBuffer) {
                  paddedSequence.push(f);
                }
              } else {
                for (let f of landmarkBuffer) {
                  paddedSequence.push(f);
                }
              }
              
              // Inferensi TFLite di browser (Shape [1, 30, 63])
              try {
                const inputTensor = tf.tensor3d([paddedSequence], [1, 30, 63]);
                const outputTensor = tfliteModel.predict(inputTensor);
                const outputData = outputTensor.dataSync();
                
                let maxIndex = -1;
                let maxVal = -1.0;
                for (let i = 0; i < outputData.length; i++) {
                  if (outputData[i] > maxVal) {
                    maxVal = outputData[i];
                    maxIndex = i;
                  }
                }
                
                if (maxIndex >= 0 && maxVal >= 0.5) {
                  label = labels[maxIndex] || "?";
                  confidence = maxVal;
                }
                
                inputTensor.dispose();
                outputTensor.dispose();
              } catch (e) {
                console.error("Error running TFLite prediction:", e);
              }
            } else {
              latestLandmarks = null;
            }
            
            let endTime = performance.now();
            currentInferenceTimeMs = endTime - startTime;
            currentLabel = label;
            currentConfidence = confidence;
            
            // Kirim data hasil prediksi kembali ke aplikasi Flutter/Dart
            if (onPredictionCallback) {
              onPredictionCallback(
                currentLabel,
                currentConfidence,
                currentInferenceTimeMs,
                JSON.stringify(handsData)
              );
            }
          }
        } catch (aiErr) {
          console.error("Error in AI detection pipeline:", aiErr);
        }
        
        animationFrameId = requestAnimationFrame(renderLoop);
      }
      
      renderLoop();
    };
    
  } catch (e) {
    console.error("Failed to start web camera or init AI:", e);
    throw e;
  }
}

function stopWebCamera() {
  isRunning = false;
  if (animationFrameId) {
    cancelAnimationFrame(animationFrameId);
    animationFrameId = null;
  }
  
  if (activeStream) {
    activeStream.getTracks().forEach(track => track.stop());
    activeStream = null;
  }
  
  // Hapus referensi srcObject pada elemen video agar browser melepaskan hardware kamera sepenuhnya
  const video = getElement("webcam-video");
  if (video) {
    video.srcObject = null;
  }
  
  console.log("Web Camera stopped.");
}

// Helper untuk melukis 21 landmark jari di kanvas web
function drawLandmarks(ctx, landmarks) {
  const connections = [
    [0, 1], [1, 2], [2, 3], [3, 4],
    [0, 5], [5, 6], [6, 7], [7, 8],
    [5, 9], [9, 10], [10, 11], [11, 12],
    [9, 13], [13, 14], [14, 15], [15, 16],
    [13, 17], [0, 17], [17, 18], [18, 19], [19, 20]
  ];
  
  const w = ctx.canvas.width;
  const h = ctx.canvas.height;
  
  // Gambar Garis penghubung
  ctx.strokeStyle = "#4F46E5"; // Electric Indigo
  ctx.lineWidth = 3;
  for (let conn of connections) {
    const start = landmarks[conn[0]];
    const end = landmarks[conn[1]];
    ctx.beginPath();
    ctx.moveTo(start.x * w, start.y * h);
    ctx.lineTo(end.x * w, end.y * h);
    ctx.stroke();
  }
  
  // Gambar Titik sendi
  for (let i = 0; i < landmarks.length; i++) {
    const lm = landmarks[i];
    ctx.beginPath();
    ctx.arc(lm.x * w, lm.y * h, 5, 0, 2 * Math.PI);
    if (i === 4 || i === 8 || i === 12 || i === 16 || i === 20) {
      ctx.fillStyle = "#A855F7"; // Neon Purple (Ujung Jari)
    } else if (i === 0) {
      ctx.fillStyle = "#10B981"; // Success Emerald (Pergelangan)
    } else {
      ctx.fillStyle = "#06B6D4"; // Electric Cyan
    }
    ctx.fill();
  }
}

// Buka fungsi ini agar bisa dipanggil secara global oleh dart via JS binding
window.startWebCamera = startWebCamera;
window.stopWebCamera = stopWebCamera;
window.initWebAI = initWebAI;

// Mulai inisialisasi AI secara mandiri di latar belakang agar ketika user klik START, model sudah siap di memori
initWebAI()
  .then(() => {
    window.sibiWebAiReady = true;
    console.log("SIBI Web AI Helper is fully loaded and ready.");
  })
  .catch(e => {
    console.error("Background AI initialization failed:", e);
    // Masih set ready agar tombol START tidak terkunci permanen, error akan dilempar saat startWebCamera dijalankan
    window.sibiWebAiReady = true;
  });
