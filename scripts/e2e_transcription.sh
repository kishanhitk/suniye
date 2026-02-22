#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /absolute/path/to/audio.wav" >&2
  exit 1
fi

WAV_PATH="$1"
if [[ ! -f "${WAV_PATH}" ]]; then
  echo "Audio file not found: ${WAV_PATH}" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${HOME}/Library/Application Support/VibeStoke/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
RUN_DIR="${ROOT_DIR}/.e2e"
BIN_PATH="${RUN_DIR}/decode_e2e"
SRC_PATH="${RUN_DIR}/main.swift"

mkdir -p "${RUN_DIR}"

for file in encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt; do
  if [[ ! -f "${MODEL_DIR}/${file}" ]]; then
    echo "Missing model file: ${MODEL_DIR}/${file}" >&2
    exit 1
  fi
done

cat > "${SRC_PATH}" <<'SWIFT'
import Foundation

func fail(_ message: String) -> Never {
  fputs("\(message)\n", stderr)
  exit(1)
}

guard CommandLine.arguments.count == 3 else {
  fail("Expected args: <wav-path> <model-dir>")
}

let wavPath = CommandLine.arguments[1]
let modelDir = CommandLine.arguments[2]

func readMono16kWav(_ path: String) throws -> [Float] {
  let data = try Data(contentsOf: URL(fileURLWithPath: path))
  if data.count < 44 { throw NSError(domain: "wav", code: 1) }

  func u16(_ offset: Int) -> UInt16 {
    data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }.littleEndian
  }
  func u32(_ offset: Int) -> UInt32 {
    data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }.littleEndian
  }

  guard String(data: data.subdata(in: 0..<4), encoding: .ascii) == "RIFF" else {
    throw NSError(domain: "wav", code: 2)
  }
  guard String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WAVE" else {
    throw NSError(domain: "wav", code: 3)
  }

  let channels = Int(u16(22))
  let sampleRate = Int(u32(24))
  let bitsPerSample = Int(u16(34))
  guard channels == 1, sampleRate == 16_000, bitsPerSample == 16 else {
    throw NSError(domain: "wav", code: 4)
  }

  var offset = 12
  var pcmStart = -1
  var pcmSize = 0

  while offset + 8 <= data.count {
    guard let chunk = String(data: data.subdata(in: offset..<(offset + 4)), encoding: .ascii) else {
      break
    }
    let chunkSize = Int(u32(offset + 4))
    let payload = offset + 8
    if chunk == "data" {
      pcmStart = payload
      pcmSize = chunkSize
      break
    }
    offset = payload + chunkSize + (chunkSize % 2)
  }

  guard pcmStart >= 0, pcmStart + pcmSize <= data.count else {
    throw NSError(domain: "wav", code: 5)
  }

  let sampleCount = pcmSize / 2
  var samples = [Float]()
  samples.reserveCapacity(sampleCount)

  for i in 0..<sampleCount {
    let byteOffset = pcmStart + i * 2
    let s = Int16(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: byteOffset, as: Int16.self) })
    samples.append(Float(s) / Float(Int16.max))
  }

  return samples
}

let encoder = modelDir + "/encoder.int8.onnx"
let decoder = modelDir + "/decoder.int8.onnx"
let joiner = modelDir + "/joiner.int8.onnx"
let tokens = modelDir + "/tokens.txt"

let transducer = sherpaOnnxOfflineTransducerModelConfig(encoder: encoder, decoder: decoder, joiner: joiner)
let modelConfig = sherpaOnnxOfflineModelConfig(tokens: tokens, transducer: transducer, numThreads: 4, provider: "cpu", debug: 0, modelType: "nemo_transducer")
let recognizerConfig = sherpaOnnxOfflineRecognizerConfig(featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80), modelConfig: modelConfig, decodingMethod: "greedy_search", maxActivePaths: 4)

var cfg = recognizerConfig
guard let recognizer = SherpaOnnxCreateOfflineRecognizer(&cfg) else {
  fail("Failed to create recognizer")
}
defer { SherpaOnnxDestroyOfflineRecognizer(recognizer) }

guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
  fail("Failed to create stream")
}
defer { SherpaOnnxDestroyOfflineStream(stream) }

let samples: [Float]
do {
  samples = try readMono16kWav(wavPath)
} catch {
  fail("Failed to read WAV: \(error)")
}

samples.withUnsafeBufferPointer { buffer in
  if let ptr = buffer.baseAddress, !buffer.isEmpty {
    SherpaOnnxAcceptWaveformOffline(stream, 16_000, ptr, Int32(buffer.count))
  }
}

SherpaOnnxDecodeOfflineStream(recognizer, stream)
guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
  fail("No recognition result")
}
defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }

let text = result.pointee.text.map(String.init(cString:)) ?? ""
print(text)
SWIFT

swiftc \
  -emit-executable \
  -import-objc-header "${ROOT_DIR}/VibeStoke/VibeStoke-Bridging-Header.h" \
  "${ROOT_DIR}/VibeStoke/SherpaOnnx.swift" \
  "${SRC_PATH}" \
  -L "${ROOT_DIR}/VibeStoke/Frameworks" \
  -lsherpa-onnx-c-api \
  -o "${BIN_PATH}"

DYLD_LIBRARY_PATH="${ROOT_DIR}/VibeStoke/Frameworks:${DYLD_LIBRARY_PATH:-}" "${BIN_PATH}" "${WAV_PATH}" "${MODEL_DIR}"
