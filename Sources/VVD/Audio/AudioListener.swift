//
//  File: AudioListener.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
private import miniaudio

public final class AudioListener: @unchecked Sendable {
    private let listenerIndex: ma_uint32 = 0
    private var engine: UnsafeMutablePointer<ma_engine> {
        device.engineRawPointer.assumingMemoryBound(to: ma_engine.self)
    }

    public var gain: Float {
        get {
            ma_engine_get_volume(engine)
        }
        set {
            _ = ma_engine_set_volume(engine, max(newValue, 0.0))
        }
    }

    public var position: Vector3 {
        get {
            let v = ma_engine_listener_get_position(engine, listenerIndex)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.float3
            ma_engine_listener_set_position(engine, listenerIndex, v.0, v.1, v.2)
        }
    }

    public var velocity: Vector3 {
        get {
            let v = ma_engine_listener_get_velocity(engine, listenerIndex)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.float3
            ma_engine_listener_set_velocity(engine, listenerIndex, v.0, v.1, v.2)
        }
    }

    public var forward: Vector3 {
        get {
            let v = ma_engine_listener_get_direction(engine, listenerIndex)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.normalized().float3
            ma_engine_listener_set_direction(engine, listenerIndex, v.0, v.1, v.2)
        }
    }

    public var up: Vector3 {
        get {
            let v = ma_engine_listener_get_world_up(engine, listenerIndex)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.normalized().float3
            ma_engine_listener_set_world_up(engine, listenerIndex, v.0, v.1, v.2)
        }
    }

    public let device: AudioDevice

    public func setOrientation(forward: Vector3, up: Vector3) {
        let f = forward.normalized().float3
        let u = up.normalized().float3
        ma_engine_listener_set_direction(engine, listenerIndex, f.0, f.1, f.2)
        ma_engine_listener_set_world_up(engine, listenerIndex, u.0, u.1, u.2)
    }

    public func setOrientation(matrix: Matrix3) {
        self.setOrientation(forward: matrix.row3, up: matrix.row2)
    }

    init(device: AudioDevice) {
        self.device = device
        ma_engine_listener_set_enabled(engine, listenerIndex, 1)
        self.setOrientation(forward: Vector3(0, 0, -1), up: Vector3(0, 1, 0))
    }
}
