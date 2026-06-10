//
//  File: AudioDevice.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import miniaudio

public struct AudioDeviceInfo: Sendable {
    public let name: String
    public let isDefault: Bool

    let id: ma_device_id

    init(name: String, isDefault: Bool, id: ma_device_id) {
        self.name = name
        self.isDefault = isDefault
        self.id = id
    }
}

private func string<T>(fromDeviceName name: inout T) -> String {
    let capacity = MemoryLayout<T>.size
    return withUnsafePointer(to: &name) { ptr in
        ptr.withMemoryRebound(to: CChar.self,
                              capacity: capacity) {
            String(cString: $0)
        }
    }
}

public func availableAudioDevices() -> [AudioDeviceInfo] {
    let context = UnsafeMutablePointer<ma_context>.allocate(capacity: 1)
    defer { context.deallocate() }

    guard ma_context_init(nil, 0, nil, context) == MA_SUCCESS else {
        return []
    }
    defer { ma_context_uninit(context) }

    var playbackInfos: UnsafeMutablePointer<ma_device_info>?
    var playbackCount: ma_uint32 = 0

    guard ma_context_get_devices(context,
                                 &playbackInfos,
                                 &playbackCount,
                                 nil,
                                 nil) == MA_SUCCESS,
          let playbackInfos else {
        return []
    }

    var devices: [AudioDeviceInfo] = []
    devices.reserveCapacity(Int(playbackCount))

    for index in 0..<Int(playbackCount) {
        var info = playbackInfos[index]
        let device = AudioDeviceInfo(name: string(fromDeviceName: &info.name),
                                     isDefault: info.isDefault != 0,
                                     id: info.id)
        if device.isDefault {
            devices.insert(device, at: 0)
        } else {
            devices.append(device)
        }
    }
    return devices
}

public final class AudioDevice: @unchecked Sendable {
    let engine: UnsafeMutablePointer<ma_engine>
    public let deviceName: String
    public let sampleRate: Int
    public let channels: Int

    public convenience init?(device: AudioDeviceInfo? = nil) {
        self.init(device: device, noDevice: false)
    }

    convenience init?(noDevice: Bool) {
        self.init(device: nil, noDevice: noDevice)
    }

    private init?(device: AudioDeviceInfo?, noDevice: Bool) {
        let engine = UnsafeMutablePointer<ma_engine>.allocate(capacity: 1)

        var config = ma_engine_config_init()
        config.listenerCount = 1
        if noDevice {
            config.noDevice = ma_bool32(MA_TRUE)
            config.channels = 2
            config.sampleRate = 48_000
        }

        let result: ma_result
        if let device, noDevice == false {
            var id = device.id
            result = withUnsafeMutablePointer(to: &id) { idPtr in
                config.pPlaybackDeviceID = idPtr
                return ma_engine_init(&config, engine)
            }
            self.deviceName = device.name
        } else if noDevice {
            config.pPlaybackDeviceID = nil
            result = ma_engine_init(&config, engine)
            self.deviceName = "No Audio Device"
        } else {
            config.pPlaybackDeviceID = nil
            result = ma_engine_init(&config, engine)
            self.deviceName = availableAudioDevices().first(where: \.isDefault)?.name ?? "Default Audio Device"
        }

        guard result == MA_SUCCESS else {
            engine.deallocate()
            Log.err("ma_engine_init failed. result: \(result)")
            return nil
        }

        self.engine = engine
        self.sampleRate = Int(ma_engine_get_sample_rate(engine))
        self.channels = Int(ma_engine_get_channels(engine))

        Log.info("miniaudio device: \(deviceName), \(sampleRate) Hz, \(channels) channels.")
    }

    deinit {
        ma_engine_uninit(engine)
        engine.deallocate()
    }

    public func makeSource(stream: AudioStream) -> AudioSource? {
        AudioSource(device: self, stream: stream)
    }
}
