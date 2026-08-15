import Accelerate
import CoreAudio
import Foundation
import os

/// Taps one process's audio (muting its direct output) and re-renders it to a
/// chosen output device at an adjustable gain, via a private aggregate device.
final class ProcessTapPlayer {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue: DispatchQueue
    private let gainState: OSAllocatedUnfairLock<Float>
    private var invalidated = false

    var gain: Float {
        get { gainState.withLock { $0 } }
        set { gainState.withLock { $0 = newValue } }
    }

    init(processObjectID: AudioObjectID, outputDeviceUID: String, initialGain: Float) throws {
        gainState = OSAllocatedUnfairLock(initialState: initialGain)
        ioQueue = DispatchQueue(label: "AudioManager.tap.\(processObjectID)", qos: .userInteractive)

        // 1. Tap the process. mutedWhenTapped removes the app's audio from its
        //    normal device — from here on, we are the one rendering it.
        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.name = "AudioManager tap \(processObjectID)"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else {
            throw CoreAudioError.osStatus("Creating process tap", status)
        }
        tapID = newTapID

        // 2. Private aggregate: the target output device + the tap as input.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioManager \(processObjectID)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard status == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw CoreAudioError.osStatus("Creating aggregate device", status)
        }
        aggregateID = newAggregateID

        // 3. IO proc: input buffers are the tap, output buffers the device.
        let gainState = self.gainState
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) { _, inInputData, _, outOutputData, _ in
            let inputList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let outputList = UnsafeMutableAudioBufferListPointer(outOutputData)
            var gain = gainState.withLock { $0 }

            for outIndex in 0..<outputList.count {
                let outBuffer = outputList[outIndex]
                guard let dstRaw = outBuffer.mData else { continue }
                memset(dstRaw, 0, Int(outBuffer.mDataByteSize))

                let dst = dstRaw.assumingMemoryBound(to: Float32.self)
                let dstSamples = Int(outBuffer.mDataByteSize) / MemoryLayout<Float32>.size

                if outIndex < inputList.count, let srcRaw = inputList[outIndex].mData {
                    // Matching stream layout: scale straight across.
                    let src = srcRaw.assumingMemoryBound(to: Float32.self)
                    let n = min(dstSamples, Int(inputList[outIndex].mDataByteSize) / MemoryLayout<Float32>.size)
                    vDSP_vsmul(src, 1, &gain, dst, 1, vDSP_Length(n))
                } else if inputList.count == 1, let srcRaw = inputList[0].mData {
                    // Tap delivered one interleaved buffer but the device has
                    // several streams: pull this output's channel out of it.
                    let src = srcRaw.assumingMemoryBound(to: Float32.self)
                    let channels = max(1, Int(inputList[0].mNumberChannels))
                    guard outIndex < channels else { continue }
                    let srcFrames = Int(inputList[0].mDataByteSize) / MemoryLayout<Float32>.size / channels
                    let n = min(dstSamples, srcFrames)
                    vDSP_vsmul(src + outIndex, vDSP_Stride(channels), &gain, dst, 1, vDSP_Length(n))
                }
            }
        }
        guard status == noErr, ioProcID != nil else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            throw CoreAudioError.osStatus("Creating IO proc", status)
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            invalidate()
            throw CoreAudioError.osStatus("Starting aggregate device", status)
        }
    }

    /// Tears everything down and un-mutes the tapped process. Safe to call twice.
    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit {
        invalidate()
    }
}
