import AppKit
import Combine
import CoreAudio
import Foundation

struct AudioApp: Identifiable, Hashable {
    let processObjectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let name: String
    let isPlaying: Bool

    var id: AudioObjectID { processObjectID }
}

struct ManagedApp {
    var gain: Float = 1.0
    /// nil = follow the system default output device.
    var deviceUID: String?
    var player: ProcessTapPlayer?
    var error: String?
}

@MainActor
final class AppMixerController: ObservableObject {
    static let shared = AppMixerController()

    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var managed: [AudioObjectID: ManagedApp] = [:]

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        refreshApps()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in AppMixerController.shared.refreshApps() }
        }
        // Apps routed to "Default" must follow the default device when it moves.
        AudioDeviceManager.shared.$defaultOutputID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                for (id, state) in self.managed where state.deviceUID == nil {
                    self.rebuildPlayer(for: id)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Process discovery

    func refreshApps() {
        let processObjects = caGetArray(systemObject, caAddress(kAudioHardwarePropertyProcessObjectList), of: AudioObjectID.self)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var seen = Set<AudioObjectID>()
        var result: [AudioApp] = []
        for processObject in processObjects {
            guard let pid = caGet(processObject, caAddress(kAudioProcessPropertyPID), pid_t(0)), pid != ownPID else { continue }
            let bundleID = caGetString(processObject, caAddress(kAudioProcessPropertyBundleID))
            let playing = (caGet(processObject, caAddress(kAudioProcessPropertyIsRunningOutput), UInt32(0)) ?? 0) != 0
            let runningApp = NSRunningApplication(processIdentifier: pid)

            // Show real apps plus anything currently emitting audio or already
            // managed; hide the swarm of silent system daemons.
            let isRegularApp = runningApp?.activationPolicy == .regular
            guard isRegularApp || playing || managed[processObject] != nil else { continue }

            let name = runningApp?.localizedName
                ?? bundleID?.components(separatedBy: ".").last
                ?? "PID \(pid)"
            result.append(AudioApp(processObjectID: processObject, pid: pid,
                                   bundleID: bundleID, name: name, isPlaying: playing))
            seen.insert(processObject)
        }

        result.sort {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        apps = result

        // Managed processes that exited: tear their taps down.
        for id in managed.keys where !seen.contains(id) {
            managed[id]?.player?.invalidate()
            managed.removeValue(forKey: id)
        }
    }

    func icon(for app: AudioApp) -> NSImage? {
        NSRunningApplication(processIdentifier: app.pid)?.icon
    }

    // MARK: - Managing apps

    func setManaged(_ app: AudioApp, _ enabled: Bool) {
        if enabled {
            guard managed[app.id] == nil else { return }
            managed[app.id] = ManagedApp()
            rebuildPlayer(for: app.id)
        } else {
            managed[app.id]?.player?.invalidate()
            managed.removeValue(forKey: app.id)
        }
    }

    func setGain(_ app: AudioApp, _ gain: Float) {
        guard var state = managed[app.id] else { return }
        state.gain = gain
        state.player?.gain = gain
        managed[app.id] = state
    }

    func setDevice(_ app: AudioApp, uid: String?) {
        guard var state = managed[app.id] else { return }
        state.deviceUID = uid
        managed[app.id] = state
        rebuildPlayer(for: app.id)
    }

    private func rebuildPlayer(for processObjectID: AudioObjectID) {
        guard var state = managed[processObjectID] else { return }
        state.player?.invalidate()
        state.player = nil
        state.error = nil

        let targetUID = state.deviceUID
            ?? AudioDeviceManager.shared.defaultOutputDevice?.uid

        if let targetUID {
            do {
                state.player = try ProcessTapPlayer(processObjectID: processObjectID,
                                                    outputDeviceUID: targetUID,
                                                    initialGain: state.gain)
            } catch {
                state.error = error.localizedDescription
            }
        } else {
            state.error = "No output device available"
        }
        managed[processObjectID] = state
    }

    /// Must run before exit — otherwise tapped apps stay muted until they
    /// restart their audio.
    func shutdown() {
        for (id, state) in managed {
            state.player?.invalidate()
            managed[id]?.player = nil
        }
        managed.removeAll()
    }
}
