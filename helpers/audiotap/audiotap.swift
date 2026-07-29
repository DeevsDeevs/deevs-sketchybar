// audiotap — prints system-audio output level (0..1) per line at ~12 Hz.
// Uses CoreAudio process taps (macOS 14.4+): no loopback driver, no routing
// changes; follows whatever output device is active. Needs the
// "System Audio Recording" privacy permission on first run.
// Usage: audiotap [--probe]   (--probe: exit 0 if capture works, else 1)

import Foundation
import CoreAudio
import AudioToolbox

let probe = CommandLine.arguments.contains("--probe")

guard #available(macOS 14.4, *) else { exit(1) }

// Tap the system mixdown (all processes).
let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
tapDesc.muteBehavior = .unmuted
tapDesc.isPrivate = true

var tapID = AudioObjectID(kAudioObjectUnknown)
var status = AudioHardwareCreateProcessTap(tapDesc, &tapID)
guard status == noErr, tapID != kAudioObjectUnknown else { exit(1) }

let aggDesc: [String: Any] = [
    kAudioAggregateDeviceNameKey: "deevs-sonar-tap",
    kAudioAggregateDeviceUIDKey: "com.deevs.sketchybar.sonar-tap",
    kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceIsStackedKey: false,
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
    kAudioAggregateDeviceTapListKey: [
        [
            kAudioSubTapUIDKey: tapDesc.uuid.uuidString,
            kAudioSubTapDriftCompensationKey: true,
        ]
    ],
]

var aggID = AudioObjectID(kAudioObjectUnknown)
status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
guard status == noErr, aggID != kAudioObjectUnknown else {
    AudioHardwareDestroyProcessTap(tapID)
    exit(1)
}

final class Level: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    private var seen = false
    func update(_ v: Float) { lock.lock(); value = max(value, v); seen = true; lock.unlock() }
    func take() -> Float { lock.lock(); let v = value; value = 0; lock.unlock(); return v }
    var everSeen: Bool { lock.lock(); defer { lock.unlock() }; return seen }
}
let level = Level()

var procID: AudioDeviceIOProcID?
status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { _, inData, _, _, _ in
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    var sum: Float = 0
    var count = 0
    for buf in buffers {
        guard let ptr = buf.mData else { continue }
        let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
        let samples = ptr.bindMemory(to: Float.self, capacity: n)
        var i = 0
        while i < n {
            sum += samples[i] * samples[i]
            i += 8 // sparse sampling is plenty for a level meter
            count += 1
        }
    }
    if count > 0 {
        level.update(min(1.0, sqrtf(sum / Float(count)) * 3.0))
    }
}
guard status == noErr, let procID else {
    AudioHardwareDestroyAggregateDevice(aggID)
    AudioHardwareDestroyProcessTap(tapID)
    exit(1)
}

status = AudioDeviceStart(aggID, procID)
guard status == noErr else {
    AudioHardwareDestroyAggregateDevice(aggID)
    AudioHardwareDestroyProcessTap(tapID)
    exit(1)
}

func cleanup() {
    AudioDeviceStop(aggID, procID)
    AudioDeviceDestroyIOProcID(aggID, procID)
    AudioHardwareDestroyAggregateDevice(aggID)
    AudioHardwareDestroyProcessTap(tapID)
}
// No signal handlers needed: private taps/aggregates are torn down by the
// HAL when the owning process dies.

if probe {
    Thread.sleep(forTimeInterval: 0.8)
    let ok = level.everSeen
    cleanup()
    exit(ok ? 0 : 1)
}

setvbuf(stdout, nil, _IOLBF, 0)
while true {
    Thread.sleep(forTimeInterval: 0.085)
    print(String(format: "%.2f", level.take()))
}
