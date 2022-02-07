import OpenAL
import Foundation

public class AudioDevice {
    public init () {
        let device = alcOpenDevice(nil)
        let context = alcCreateContext(device, nil)

        alcMakeContextCurrent(context);
        let deviceName = String(validatingUTF8: alcGetString(device, ALC_DEVICE_SPECIFIER)) ?? "Null"
        var majorVersion : Int32 = 0;
        var minorVersion : Int32 = 0;
        alcGetIntegerv(device, ALC_MAJOR_VERSION, Int32(MemoryLayout<Int32>.size), &majorVersion);
        alcGetIntegerv(device, ALC_MINOR_VERSION, Int32(MemoryLayout<Int32>.size), &minorVersion);

        print("OpenAL device: \(deviceName) Version: \(majorVersion).\(minorVersion).")
    }
}
