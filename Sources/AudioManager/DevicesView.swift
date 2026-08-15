import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var deviceManager: AudioDeviceManager

    var body: some View {
        Form {
            Section("Output") {
                ForEach(deviceManager.outputDevices) { device in
                    OutputDeviceRow(device: device)
                }
                if deviceManager.outputVolumeSettable {
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(
                            value: Binding(
                                get: { deviceManager.outputVolume },
                                set: { deviceManager.setOutputVolume($0) }
                            ), in: 0...1
                        )
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Input") {
                ForEach(deviceManager.inputDevices) { device in
                    InputDeviceRow(device: device)
                }
                Text("Selecting a Bluetooth headset as input forces the whole link into low-quality call mode (HFP). Keep the built-in mic selected for full-quality music.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct OutputDeviceRow: View {
    @EnvironmentObject private var deviceManager: AudioDeviceManager
    let device: AudioDevice

    private var isDefault: Bool { device.id == deviceManager.defaultOutputID }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    deviceManager.setDefaultOutput(device.id)
                } label: {
                    Image(systemName: isDefault ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isDefault ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Set as default output")

                Image(systemName: device.isBluetooth ? "wave.3.right.circle" : "speaker.wave.2.circle")
                    .foregroundStyle(.secondary)
                Text(device.name).fontWeight(isDefault ? .semibold : .regular)

                if device.isBluetooth {
                    QualityBadge(device: device)
                }

                Spacer()
                Text("\(device.transportName) · \(formattedRate(device.sampleRate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if device.isBluetooth, deviceManager.inputCounterpart(of: device) != nil {
                BluetoothModePicker(device: device)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct QualityBadge: View {
    let device: AudioDevice

    var body: some View {
        if device.looksLikeCallMode {
            Label("Call mode — degraded", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .help("The headset is in the hands-free profile (HFP/SCO): telephone-quality audio. Switch mode to High quality below.")
        } else {
            Label("High quality", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
    }
}

private struct BluetoothModePicker: View {
    @EnvironmentObject private var deviceManager: AudioDeviceManager
    let device: AudioDevice

    var body: some View {
        Picker(
            "Mode",
            selection: Binding(
                get: { deviceManager.currentMode(for: device) },
                set: { deviceManager.set(mode: $0, for: device) }
            )
        ) {
            ForEach(BluetoothMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 380)
        .help("High quality frees the headset mic so the link can use A2DP. Headset mic enables the mic but drops the whole link to call quality.")
    }
}

private struct InputDeviceRow: View {
    @EnvironmentObject private var deviceManager: AudioDeviceManager
    let device: AudioDevice

    private var isDefault: Bool { device.id == deviceManager.defaultInputID }

    var body: some View {
        HStack {
            Button {
                deviceManager.setDefaultInput(device.id)
            } label: {
                Image(systemName: isDefault ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isDefault ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Set as default input")

            Image(systemName: "mic")
                .foregroundStyle(.secondary)
            Text(device.name).fontWeight(isDefault ? .semibold : .regular)

            Spacer()
            Text(device.transportName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

func formattedRate(_ rate: Double) -> String {
    guard rate > 0 else { return "—" }
    return String(format: "%.1f kHz", rate / 1000)
}
