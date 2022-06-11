import Foundation
import OpenAL

public struct ALDevice {
    public let name: String
    public let majorVersion: Int
    public let minorVersion: Int
}

public func AvailableALDevices() -> [ALDevice] {
    var devices: [ALDevice] = []
    if alcIsExtensionPresent(nil, "ALC_ENUMERATION_EXT") == AL_TRUE {

        // defaultDeviceName contains the name of the default device 
        let defaultDeviceName = String(utf8String: alcGetString(nil, ALC_DEFAULT_DEVICE_SPECIFIER))

        // Pass in NULL device handle to get list of devices 
        if var devicesRawCStrArray = alcGetString(nil, ALC_DEVICE_SPECIFIER) {
            // devices contains the device names, separated by NULL
            // and terminated by two consecutive NULLs. 

            while devicesRawCStrArray.pointee != 0 {
                if let device = alcOpenDevice(devicesRawCStrArray) {

                    if let name = String(utf8String: alcGetString(device, ALC_DEVICE_SPECIFIER)) {
                        var majorVersion: Int32 = 0
                        var minorVersion: Int32 = 0
                        alcGetIntegerv(device, ALC_MAJOR_VERSION, Int32(MemoryLayout<Int32>.size), &majorVersion)
                        alcGetIntegerv(device, ALC_MINOR_VERSION, Int32(MemoryLayout<Int32>.size), &minorVersion)

                        let dev = ALDevice(name: name,
                                           majorVersion: Int(majorVersion),
                                           minorVersion: Int(minorVersion))
                        if name == defaultDeviceName {
                            devices.insert(dev, at: 0)
                        } else {
                            devices.append(dev)
                        }
                    }
                    alcCloseDevice(device)
                }
                let len = strlen(devicesRawCStrArray) + 1
                devicesRawCStrArray = devicesRawCStrArray.advanced(by: len)
            }
        }
    }
    return devices
}

public typealias ALCdevice = OpaquePointer
public typealias ALCcontext = OpaquePointer


public class AudioDevice {
    public let device: ALCdevice
    public let deviceName: String
    public let majorVersion: Int
    public let minorVersion: Int

    public init?(deviceName: String) {
        guard let device = alcOpenDevice(deviceName) else { return nil }
        self.device = device
        self.deviceName = String(utf8String: alcGetString(device, ALC_DEVICE_SPECIFIER)) ?? ""
        var majorVersion : Int32 = 0
        var minorVersion : Int32 = 0
        alcGetIntegerv(device, ALC_MAJOR_VERSION, Int32(MemoryLayout<Int32>.size), &majorVersion)
        alcGetIntegerv(device, ALC_MINOR_VERSION, Int32(MemoryLayout<Int32>.size), &minorVersion)

        self.majorVersion = Int(majorVersion)
        self.minorVersion = Int(minorVersion)

        print("OpenAL device: \(deviceName) Version: \(majorVersion).\(minorVersion).")
    }

    deinit {
		alcCloseDevice(device)
    }
}
