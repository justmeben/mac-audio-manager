import SwiftUI

struct MixerView: View {
    @EnvironmentObject private var mixer: AppMixerController
    @EnvironmentObject private var deviceManager: AudioDeviceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mixer.apps.isEmpty {
                ContentUnavailableView(
                    "No audio apps found",
                    systemImage: "waveform.slash",
                    description: Text("Apps appear here once they have played audio.")
                )
            } else {
                List {
                    ForEach(mixer.apps) { app in
                        AppMixerRow(app: app)
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            Text("Turning Control on taps the app's audio (macOS will ask once for System Audio Recording permission). While controlled, the app plays through AudioManager at the volume and device you set here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
        }
    }
}

private struct AppMixerRow: View {
    @EnvironmentObject private var mixer: AppMixerController
    @EnvironmentObject private var deviceManager: AudioDeviceManager
    let app: AudioApp

    private var state: ManagedApp? { mixer.managed[app.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Group {
                    if let icon = mixer.icon(for: app) {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "app.dashed").resizable()
                    }
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    Text(app.isPlaying ? "Playing" : "Silent")
                        .font(.caption)
                        .foregroundStyle(app.isPlaying ? Color.green : Color.secondary)
                }
                .frame(minWidth: 140, alignment: .leading)

                Spacer()

                if let state {
                    Image(systemName: volumeIcon(state.gain))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Slider(
                        value: Binding(
                            get: { Double(state.gain) },
                            set: { mixer.setGain(app, Float($0)) }
                        ), in: 0...1.5
                    )
                    .frame(width: 170)
                    Text("\(Int((state.gain * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)

                    Picker(
                        "",
                        selection: Binding(
                            get: { state.deviceUID },
                            set: { mixer.setDevice(app, uid: $0) }
                        )
                    ) {
                        Text("Default device").tag(String?.none)
                        ForEach(deviceManager.outputDevices) { device in
                            Text(device.name).tag(String?.some(device.uid))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                Toggle(
                    "Control",
                    isOn: Binding(
                        get: { state != nil },
                        set: { mixer.setManaged(app, $0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Take over this app's volume and output device")
            }

            if let error = state?.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 38)
            }
        }
        .padding(.vertical, 3)
    }

    private func volumeIcon(_ gain: Float) -> String {
        switch gain {
        case 0: return "speaker.slash.fill"
        case ..<0.5: return "speaker.wave.1.fill"
        case ..<1.0: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
