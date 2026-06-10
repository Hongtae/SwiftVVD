//
//  File: AudioListener.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import miniaudio

public final class AudioListener: @unchecked Sendable {
    private let listenerIndex: ma_uint32 = 0

    public var gain: Float {
        get {
            ma_engine_get_volume(device.engine)
        }
        set {
            _ = ma_engine_set_volume(device.engine, max(newValue, 0.0))
        }
    }

    public var position: Vector3 {
        get {
            let v = ma_engine_listener_get_position(device.engine, listenerIndex)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.float3
            ma_engine_listener_set_position(device.engine, listenerIndex, v.0, v.1, v.2)
        }
    }

    public var velocity: Vector3 {
        get {
            let v = ma_engine_listener_get_velocity(device.engine, listenerIndex)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.float3
            ma_engine_listener_set_velocity(device.engine, listenerIndex, v.0, v.1, v.2)
        }
    }

    public var forward: Vector3 {
        get {
            let v = ma_engine_listener_get_direction(device.engine, listenerIndex)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.normalized().float3
            ma_engine_listener_set_direction(device.engine, listenerIndex, v.0, v.1, v.2)
        }
    }

    public var up: Vector3 {
        get {
            let v = ma_engine_listener_get_world_up(device.engine, listenerIndex)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.normalized().float3
            ma_engine_listener_set_world_up(device.engine, listenerIndex, v.0, v.1, v.2)
        }
    }

    public let device: AudioDevice

    public func setOrientation(forward: Vector3, up: Vector3) {
        let f = forward.normalized().float3
        let u = up.normalized().float3
        ma_engine_listener_set_direction(device.engine, listenerIndex, f.0, f.1, f.2)
        ma_engine_listener_set_world_up(device.engine, listenerIndex, u.0, u.1, u.2)
    }

    public func setOrientation(matrix: Matrix3) {
        self.setOrientation(forward: matrix.row3, up: matrix.row2)
    }

    init(device: AudioDevice) {
        self.device = device
        ma_engine_listener_set_enabled(device.engine, listenerIndex, 1)
        self.setOrientation(forward: Vector3(0, 0, -1), up: Vector3(0, 1, 0))
    }
}
