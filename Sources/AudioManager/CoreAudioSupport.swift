import CoreAudio
import Foundation

// Thin helpers over the C property API. All return nil / [] / OSStatus on
// failure instead of throwing so call sites stay compact.

func caAddress(_ selector: AudioObjectPropertySelector,
               _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
               _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

func caGet<T>(_ objectID: AudioObjectID, _ address: AudioObjectPropertyAddress, _ initial: T) -> T? {
    var addr = address
    var size = UInt32(MemoryLayout<T>.size)
    var value = initial
    let status = AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &value)
    return status == noErr ? value : nil
}

func caGetString(_ objectID: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
    var addr = address
    var value: CFString?
    var size = UInt32(MemoryLayout<CFString?>.size)
    let status = withUnsafeMutablePointer(to: &value) { ptr in
        AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, ptr)
    }
    guard status == noErr, let value else { return nil }
    return value as String
}

func caGetArray<T>(_ objectID: AudioObjectID, _ address: AudioObjectPropertyAddress, of type: T.Type) -> [T] {
    var addr = address
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(objectID, &addr, 0, nil, &dataSize) == noErr, dataSize > 0 else {
        return []
    }
    let count = Int(dataSize) / MemoryLayout<T>.stride
    guard count > 0 else { return [] }
    let buffer = UnsafeMutableBufferPointer<T>.allocate(capacity: count)
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(objectID, &addr, 0, nil, &dataSize, buffer.baseAddress!) == noErr else {
        return []
    }
    return Array(buffer.prefix(Int(dataSize) / MemoryLayout<T>.stride))
}

@discardableResult
func caSet<T>(_ objectID: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> OSStatus {
    var addr = address
    var v = value
    return AudioObjectSetPropertyData(objectID, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &v)
}

func caHasProperty(_ objectID: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
    var addr = address
    return AudioObjectHasProperty(objectID, &addr)
}

func caIsSettable(_ objectID: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
    var addr = address
    var settable: DarwinBoolean = false
    return AudioObjectIsPropertySettable(objectID, &addr, &settable) == noErr && settable.boolValue
}

/// Number of streams in a scope — nonzero means the device does input/output.
func caStreamCount(_ objectID: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
    var addr = caAddress(kAudioDevicePropertyStreams, scope)
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(objectID, &addr, 0, nil, &dataSize) == noErr else { return 0 }
    return Int(dataSize) / MemoryLayout<AudioObjectID>.stride
}

func fourCC(_ status: OSStatus) -> String {
    let n = UInt32(bitPattern: status)
    let chars = [24, 16, 8, 0].map { Character(UnicodeScalar((n >> $0) & 0xFF) ?? " ") }
    if chars.allSatisfy({ $0.isASCII && !$0.isWhitespace }) {
        return "'\(String(chars))' (\(status))"
    }
    return "\(status)"
}

enum CoreAudioError: LocalizedError {
    case osStatus(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .osStatus(operation, status):
            return "\(operation) failed: \(fourCC(status))"
        }
    }
}
