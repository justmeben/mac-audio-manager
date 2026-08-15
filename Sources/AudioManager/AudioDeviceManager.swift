import AudioToolbox
import Combine
import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transportType: UInt32
    let hasInput: Bool
    let hasOutput: Bool
    let sampleRate: Double

    var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    var isBuiltIn: Bool { transportType == kAudioDeviceTransportTypeBuiltIn }

    /// Bluetooth headsets surface as two HAL devices ("XX:input" / "XX:output")
    /// sharing a MAC-derived UID prefix. Stripping the suffix lets us pair them.
    var baseUID: String {
        uid.replacingOccurrences(of: ":input", with: "")
            .replacingOccurrences(of: ":output", with: "")
    }

    /// A telephony-grade sample rate on a Bluetooth link means the headset is
    /// in the low-quality hands-free profile (HFP/SCO) instead of A2DP.
    var looksLikeCallMode: Bool { isBluetooth && sampleRate > 0 && sampleRate <= 24_000 }

    var transportName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return "Virtual"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        default: return "Other"
        }
    }
}

enum BluetoothMode: String, CaseIterable, Identifiable {
    case highQuality
    case headsetMic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .highQuality: return "High quality (music)"
        case .headsetMic: return "Headset mic (calls)"
        }
    }
}

@MainActor
final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var defaultOutputID: AudioObjectID = 0
    @Published private(set) var defaultInputID: AudioObjectID = 0
    @Published private(set) var outputVolume: Float = 0
    @Published private(set) var outputVolumeSettable = false

    var outputDevices: [AudioDevice] {
        devices.filter { $0.hasOutput && $0.transportType != kAudioDeviceTransportTypeAggregate }
    }

    var inputDevices: [AudioDevice] {
        devices.filter { $0.hasInput && $0.transportType != kAudioDeviceTransportTypeAggregate }
    }

    var defaultOutputDevice: AudioDevice? { devices.first { $0.id == defaultOutputID } }
    var defaultInputDevice: AudioDevice? { devices.first { $0.id == defaultInputID } }

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private var refreshTimer: Timer?

    private init() {
        refresh()
        installListeners()
        // Bluetooth profile flips (sample-rate changes) and external volume
        // changes don't all emit listener callbacks we track, so poll lightly.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in AudioDeviceManager.shared.refresh() }
        }
    }

    // MARK: - Refresh

    func refresh() {
        let ids = caGetArray(systemObject, caAddress(kAudioHardwarePropertyDevices), of: AudioObjectID.self)
        devices = ids.compactMap { deviceInfo($0) }

        defaultOutputID = caGet(systemObject, caAddress(kAudioHardwarePropertyDefaultOutputDevice), AudioObjectID(0)) ?? 0
        defaultInputID = caGet(systemObject, caAddress(kAudioHardwarePropertyDefaultInputDevice), AudioObjectID(0)) ?? 0

        let volumeAddr = volumeAddress()
        if defaultOutputID != 0, caHasProperty(defaultOutputID, volumeAddr) {
            outputVolumeSettable = caIsSettable(defaultOutputID, volumeAddr)
            if let vol = caGet(defaultOutputID, volumeAddr, Float32(0)), abs(vol - outputVolume) > 0.005 {
                outputVolume = vol
            }
        } else {
            outputVolumeSettable = false
        }
    }

    private func deviceInfo(_ id: AudioObjectID) -> AudioDevice? {
        guard let uid = caGetString(id, caAddress(kAudioDevicePropertyDeviceUID)) else { return nil }
        let name = caGetString(id, caAddress(kAudioDevicePropertyDeviceNameCFString)) ?? uid
        let transport = caGet(id, caAddress(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0
        let inputs = caStreamCount(id, scope: kAudioObjectPropertyScopeInput)
        let outputs = caStreamCount(id, scope: kAudioObjectPropertyScopeOutput)
        guard inputs > 0 || outputs > 0 else { return nil }
        let rate = caGet(id, caAddress(kAudioDevicePropertyNominalSampleRate), Float64(0)) ?? 0
        return AudioDevice(id: id, uid: uid, name: name, transportType: transport,
                           hasInput: inputs > 0, hasOutput: outputs > 0, sampleRate: rate)
    }

    private func installListeners() {
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
        ]
        for selector in selectors {
            var addr = caAddress(selector)
            AudioObjectAddPropertyListenerBlock(systemObject, &addr, DispatchQueue.main) { _, _ in
                Task { @MainActor in AudioDeviceManager.shared.refresh() }
            }
        }
    }

    // MARK: - Defaults & volume

    func setDefaultOutput(_ id: AudioObjectID) {
        caSet(systemObject, caAddress(kAudioHardwarePropertyDefaultOutputDevice), id)
        caSet(systemObject, caAddress(kAudioHardwarePropertyDefaultSystemOutputDevice), id)
        refresh()
    }

    func setDefaultInput(_ id: AudioObjectID) {
        caSet(systemObject, caAddress(kAudioHardwarePropertyDefaultInputDevice), id)
        refresh()
    }

    func setOutputVolume(_ volume: Float) {
        guard defaultOutputID != 0 else { return }
        caSet(defaultOutputID, volumeAddress(), Float32(volume))
        outputVolume = volume
    }

    private func volumeAddress() -> AudioObjectPropertyAddress {
        caAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
    }

    // MARK: - Bluetooth profile ("mode") switching
    //
    // macOS offers no direct A2DP/HFP switch. The lever that actually works:
    // the link drops to HFP whenever the headset's own microphone is the
    // system input. Moving input to the built-in mic lets the link
    // renegotiate back to A2DP within a second or two.

    func inputCounterpart(of device: AudioDevice) -> AudioDevice? {
        devices.first { $0.hasInput && $0.baseUID == device.baseUID }
    }

    func currentMode(for device: AudioDevice) -> BluetoothMode {
        if let input = defaultInputDevice, input.baseUID == device.baseUID {
            return .headsetMic
        }
        return .highQuality
    }

    func set(mode: BluetoothMode, for device: AudioDevice) {
        switch mode {
        case .headsetMic:
            if let mic = inputCounterpart(of: device) {
                setDefaultInput(mic.id)
            }
        case .highQuality:
            if let builtIn = devices.first(where: { $0.hasInput && $0.isBuiltIn }) {
                setDefaultInput(builtIn.id)
            } else if let anyOther = devices.first(where: { $0.hasInput && $0.baseUID != device.baseUID }) {
                setDefaultInput(anyOther.id)
            }
        }
    }
}
