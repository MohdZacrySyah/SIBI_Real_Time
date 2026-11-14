import numpy as np
import tensorflow as tf

model_path = r"D:\SEMESTER 6\PROPOSAL TA 2026 RPL\SIBI_REALTIME\assets\sibi_classifier.tflite"
interpreter = tf.lite.Interpreter(model_path=model_path)
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

print("Input details:")
for d in input_details:
    print(f"  Name: {d['name']}, Shape: {d['shape']}, Type: {d['dtype']}")

print("\nOutput details:")
for d in output_details:
    print(f"  Name: {d['name']}, Shape: {d['shape']}, Type: {d['dtype']}")

# Test with dummy input
dummy_input = np.zeros(input_details[0]['shape'], dtype=input_details[0]['dtype'])
interpreter.set_tensor(input_details[0]['index'], dummy_input)
interpreter.invoke()
output = interpreter.get_tensor(output_details[0]['index'])

print("\nOutput for zero input:")
print(f"  Max probability: {np.max(output):.4f}")
print(f"  Predicted class: {np.argmax(output)}")
