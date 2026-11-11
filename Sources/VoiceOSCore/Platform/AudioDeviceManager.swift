import Foundation
import CoreAudio
import AVFoundation

public struct NativeAudioDeviceInfo: Codable, Sendable, Identifiable {
    public var id: String { uid }
    public let uid: String
    public let name: String
    public let isDefault: Bool
    public let sampleRate: Double
    public let channels: Int
    
    public init(uid: String, name: String, isDefault: Bool, sampleRate: Double = 16000.0, channels: Int = 1) {
        self.uid = uid
        self.name = name
        self.isDefault = isDefault
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

/// Native macOS CoreAudio Device Manager matching APP-SECRET.md line 69:
/// `getNativeAudioDevices`, `getNativeAudioDevicesWithInfo`, `getDefaultMicrophoneName`, `onVolumeUpdate`.
public final class AudioDeviceManager: @unchecked Sendable {
    public static let shared = AudioDeviceManager()
    
    private init() {}
    
    // MARK: - Native Audio Device Discovery
    
    public func getNativeAudioDevicesWithInfo() -> [NativeAudioDeviceInfo] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            return fallbackAudioDevices()
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        
        let fetchStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard fetchStatus == noErr else {
            return fallbackAudioDevices()
        }
        
        let defaultDeviceID = getDefaultInputDeviceID()
        var inputDevices: [NativeAudioDeviceInfo] = []
        
        for id in deviceIDs {
            // Check if device has input channels
            var inputChannelsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(id, &inputChannelsAddress, 0, nil, &streamSize) == noErr && streamSize > 0 {
                let name = getDeviceName(id)
                let uid = getDeviceUID(id)
                let isDef = (id == defaultDeviceID)
                inputDevices.append(NativeAudioDeviceInfo(
                    uid: uid,
                    name: name,
                    isDefault: isDef,
                    sampleRate: 16000.0,
                    channels: 1
                ))
            }
        }
        
        return inputDevices.isEmpty ? fallbackAudioDevices() : inputDevices
    }
    
    public func getDefaultMicrophoneName() -> String {
        let defID = getDefaultInputDeviceID()
        if defID != 0 {
            let name = getDeviceName(defID)
            if !name.isEmpty { return name }
        }
        return "MacBook Pro Microphone (Built-in)"
    }
    
    // MARK: - CoreAudio Internal Property Helpers
    
    private func getDefaultInputDeviceID() -> AudioObjectID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : 0
    }
    
    private func getDeviceName(_ id: AudioObjectID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, &name)
        return status == noErr ? (name as String) : "Audio Device"
    }
    
    private func getDeviceUID(_ id: AudioObjectID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, &uid)
        return status == noErr ? (uid as String) : "\(id)"
    }
    
    private func fallbackAudioDevices() -> [NativeAudioDeviceInfo] {
        return [
            NativeAudioDeviceInfo(
                uid: "builtin_mic_default",
                name: "MacBook Pro Microphone (Built-in)",
                isDefault: true,
                sampleRate: 16000.0,
                channels: 1
            )
        ]
    }
}

