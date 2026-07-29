// audiotap — prints N spectrum band levels (0..MAX) per line, ~15 Hz.
//
// Uses ScreenCaptureKit's system-audio capture (macOS 13+): no loopback
// driver, no Audio MIDI Setup, and it would follow whatever output device is
// active, because it taps the OS mix before the device.
//
// STATUS: not wired into sonar. On macOS 15 the stream starts and *video*
// frames are delivered (so Screen Recording is granted), but audio sample
// buffers never arrive — the same silent failure reported elsewhere for
// SCK audio on 15.x. Verified identical whether launched from a terminal,
// via `open`, or spawned by sketchybar itself, so it is not a TCC-parent
// issue. Kept here for when the OS side is fixed; sonar uses cava today.
//
// Usage: audiotap [--bars N] [--max M] [--probe]
//   --probe : exit 0 if capture is authorized and delivering audio, else 1

import Foundation
import ScreenCaptureKit
import AVFoundation
import Accelerate

func arg(_ name: String, _ fallback: Int) -> Int {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count,
          let v = Int(CommandLine.arguments[i + 1]) else { return fallback }
    return v
}

let bars = max(1, arg("--bars", 12))
let maxLevel = max(1, arg("--max", 16))
let probe = CommandLine.arguments.contains("--probe")

let fftSize = 1024
let log2n = vDSP_Length(10)

final class Spectrum: @unchecked Sendable {
    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: 1024)
    private var filled = false
    private var smoothed: [Float]
    private let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    private let window: [Float]

    init() {
        smoothed = [Float](repeating: 0, count: bars)
        var w = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&w, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        window = w
    }

    func push(_ samples: UnsafePointer<Float>, _ n: Int) {
        guard n > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        if n >= fftSize {
            for i in 0..<fftSize { ring[i] = samples[n - fftSize + i] }
        } else {
            let keep = fftSize - n
            for i in 0..<keep { ring[i] = ring[i + n] }
            for i in 0..<n { ring[keep + i] = samples[i] }
        }
        filled = true
    }

    // Log-spaced bands with a fast-attack / slow-release envelope.
    func bands() -> [Int] {
        lock.lock()
        let input = ring
        let have = filled
        lock.unlock()
        guard have else { return [Int](repeating: 0, count: bars) }

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        let binCount = fftSize / 2
        let minBin = 2.0, maxBin = Double(binCount - 1)
        var out = [Int](repeating: 0, count: bars)
        for b in 0..<bars {
            let lo = minBin * pow(maxBin / minBin, Double(b) / Double(bars))
            let hi = minBin * pow(maxBin / minBin, Double(b + 1) / Double(bars))
            let l = Int(lo), h = max(Int(hi), Int(lo) + 1)
            var peak: Float = 0
            for i in l..<min(h, binCount) { peak = max(peak, magnitudes[i]) }
            let scaled = log10(1 + peak * 0.02) * 1.9
            let prev = smoothed[b]
            let next = scaled > prev ? scaled : prev * 0.72 + scaled * 0.28
            smoothed[b] = next
            out[b] = min(maxLevel, Int((next * Float(maxLevel)).rounded()))
        }
        return out
    }
}

let spectrum = Spectrum()
let runLock = NSLock()
var isRunning = false

final class Output: NSObject, SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(buffer) else { return }
        runLock.lock(); isRunning = true; runLock.unlock()
        try? buffer.withAudioBufferList { list, _ in
            guard let first = list.first, let data = first.mData else { return }
            let n = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            spectrum.push(data.assumingMemoryBound(to: Float.self), n)
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { exit(1) }
}

let output = Output()

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { exit(1) }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        // A real (if small) video size at a normal frame rate: SCStream stops
        // delivering audio if the video side is starved.
        config.width = 640
        config.height = 360
        config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        config.queueDepth = 5
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        let q = DispatchQueue(label: "audiotap.capture")
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: q)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: q)
        try await stream.startCapture()
    } catch {
        FileHandle.standardError.write("capture failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if probe {
    for _ in 0..<30 {
        Thread.sleep(forTimeInterval: 0.1)
        runLock.lock(); let ok = isRunning; runLock.unlock()
        if ok { exit(0) }
    }
    exit(1)
}

var out: FileHandle = .standardOutput
if let i = CommandLine.arguments.firstIndex(of: "--out"), i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    FileManager.default.createFile(atPath: path, contents: nil)
    if let fh = FileHandle(forWritingAtPath: path) { out = fh }
}
setvbuf(stdout, nil, _IOLBF, 0)
while true {
    Thread.sleep(forTimeInterval: 0.066)
    let line = spectrum.bands().map(String.init).joined(separator: ";") + "\n"
    out.write(line.data(using: .utf8)!)
}
