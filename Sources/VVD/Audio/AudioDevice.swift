//
//  File: AudioDevice.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import OpenAL

public struct ALDevice {
    public let name: String
    public let majorVersion: Int
    public let minorVersion: Int
}

public func availableALDevices() -> [ALDevice] {
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

                    let name = String(cString: alcGetString(device, ALC_DEVICE_SPECIFIER))
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


public final class AudioDevice: @unchecked Sendable {
    public let device: ALCdevice
    public let context: ALCcontext

    public let deviceName: String
    public let majorVersion: Int
    public let minorVersion: Int

    struct BitsChannels: Hashable {
        let bits: Int
        let channels: Int
    }
    var formatTable: [BitsChannels: Int32] = [:]

    public init?(deviceName: String) {
        guard let device = alcOpenDevice(deviceName) else { return nil }

        if let context = alcCreateContext(device, nil) {
            alcMakeContextCurrent(context)

            self.device = device
            self.context = context

            self.deviceName = String(utf8String: alcGetString(device, ALC_DEVICE_SPECIFIER)) ?? ""
            var majorVersion : Int32 = 0
            var minorVersion : Int32 = 0
            alcGetIntegerv(device, ALC_MAJOR_VERSION, Int32(MemoryLayout<Int32>.size), &majorVersion)
            alcGetIntegerv(device, ALC_MINOR_VERSION, Int32(MemoryLayout<Int32>.size), &minorVersion)

            self.majorVersion = Int(majorVersion)
            self.minorVersion = Int(minorVersion)

            Log.info("OpenAL device: \(deviceName) Version: \(majorVersion).\(minorVersion).")

            // update format table
            formatTable[BitsChannels(bits: 4, channels: 1)] = alGetEnumValue("AL_FORMAT_MONO_IMA4")
            formatTable[BitsChannels(bits: 4, channels: 2)] = alGetEnumValue("AL_FORMAT_STEREO_IMA4")

            formatTable[BitsChannels(bits: 8, channels: 1)] = AL_FORMAT_MONO8
            formatTable[BitsChannels(bits: 8, channels: 2)] = AL_FORMAT_STEREO8
            formatTable[BitsChannels(bits: 8, channels: 4)] = alGetEnumValue("AL_FORMAT_QUAD8")
            formatTable[BitsChannels(bits: 8, channels: 6)] = alGetEnumValue("AL_FORMAT_51CHN8")
            formatTable[BitsChannels(bits: 8, channels: 8)] = alGetEnumValue("AL_FORMAT_71CHN8")

            formatTable[BitsChannels(bits:16, channels: 1)] = AL_FORMAT_MONO16
            formatTable[BitsChannels(bits:16, channels: 2)] = AL_FORMAT_STEREO16
            formatTable[BitsChannels(bits:16, channels: 4)] = alGetEnumValue("AL_FORMAT_QUAD16")
            formatTable[BitsChannels(bits:16, channels: 6)] = alGetEnumValue("AL_FORMAT_51CHN16")
            formatTable[BitsChannels(bits:16, channels: 8)] = alGetEnumValue("AL_FORMAT_71CHN16")

            formatTable[BitsChannels(bits:32, channels: 1)] = alGetEnumValue("AL_FORMAT_MONO_FLOAT32")
            formatTable[BitsChannels(bits:32, channels: 2)] = alGetEnumValue("AL_FORMAT_STEREO_FLOAT32")
            formatTable[BitsChannels(bits:32, channels: 4)] = alGetEnumValue("AL_FORMAT_QUAD32")
            formatTable[BitsChannels(bits:32, channels: 6)] = alGetEnumValue("AL_FORMAT_51CHN32")
            formatTable[BitsChannels(bits:32, channels: 8)] = alGetEnumValue("AL_FORMAT_71CHN32")

        } else {
            Log.err("alcCreateContext failed.")
            return nil
        }
    }

    deinit {
        if alcGetCurrentContext() == context {
            alcMakeContextCurrent(nil)
        }
        alcDestroyContext(context)
        alcCloseDevice(device)
    }

    public func makeSource() -> AudioSource? {
        var sourceID: ALuint = 0
        alGenSources(1, &sourceID)
        alSourcei(sourceID, AL_LOOPING, 0)
        alSourcei(sourceID, AL_BUFFER, 0)
        alSourceStop(sourceID)

        return AudioSource(device: self, sourceID: sourceID)
    }

    public func format(bits: Int, channels: Int) -> Int32 {
        return formatTable[BitsChannels(bits: bits, channels: channels)] ?? 0
    }
}
