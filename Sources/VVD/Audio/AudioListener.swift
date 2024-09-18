//
//  File: AudioListener.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation
import OpenAL

public class AudioListener {
    public var gain: Float {
        get {
            var v: Float = 1.0
            alGetListenerf(AL_GAIN, &v)
            return v
        }
        set(v) {
            alListenerf(AL_GAIN, max(v, 0.0))
        }
    }

    public var position: Vector3 {
        get {
            var v: Float3 = (0, 0, 0)
            alGetListener3f(AL_POSITION, &v.0, &v.1, &v.2)
            return Vector3(v)
        }
        set(v) {
            let v = v.float3
            alListener3f(AL_POSITION, v.0, v.1, v.2)
        }
    }

    public var velocity: Vector3 {
        get {
            var v: Float3 = (0, 0, 0)
            alGetListener3f(AL_VELOCITY, &v.0, &v.1, &v.2)
            return Vector3(v)
        }
        set(v) {
            let v = v.float3
            alListener3f(AL_VELOCITY, v.0, v.1, v.2)
        }
    }
    
    public var forward: Vector3 {
        get {
            var v: [ALfloat] = [
                0.0, 0.0, -1.0, // forward
                0.0, 1.0, 0.0,  // up
            ]
            alGetListenerfv(AL_ORIENTATION, &v)
            return Vector3(Scalar(v[0]), Scalar(v[1]), Scalar(v[2]))
        }
        set(vec) {
            var v: [ALfloat] = [
                0.0, 0.0, -1.0, // forward
                0.0, 1.0, 0.0,  // up
            ]
            alGetListenerfv(AL_ORIENTATION, &v)
            let v2 = vec.normalized()
            v[0] = ALfloat(v2.x)
            v[1] = ALfloat(v2.y)
            v[2] = ALfloat(v2.z)
            alListenerfv(AL_ORIENTATION, v)
        }
    }

    public var up: Vector3 {
        get {
            var v: [ALfloat] = [
                0.0, 0.0, -1.0, // forward
                0.0, 1.0, 0.0,  // up
            ]
            alGetListenerfv(AL_ORIENTATION, &v)
            return Vector3(Scalar(v[3]), Scalar(v[4]), Scalar(v[5]))
        }
        set(vec) {
            var v: [ALfloat] = [
                0.0, 0.0, -1.0, // forward
                0.0, 1.0, 0.0,  // up
            ]
            alGetListenerfv(AL_ORIENTATION, &v)
            let v2 = vec.normalized()
            v[3] = ALfloat(v2.x)
            v[4] = ALfloat(v2.y)
            v[5] = ALfloat(v2.z)
            alListenerfv(AL_ORIENTATION, v)
        }
    }

    public let device: AudioDevice

    public func setOrientation(forward: Vector3, up: Vector3) {
        let f = forward.normalized()
        let u = up.normalized()
        let v = [ALfloat(f.x), ALfloat(f.y), ALfloat(f.z),
                 ALfloat(u.x), ALfloat(u.y), ALfloat(u.z)]
        alListenerfv(AL_ORIENTATION, v)
    }

    public func setOrientation(matrix: Matrix3) {
        self.setOrientation(forward: matrix.row3, up: matrix.row2)
    }

    init(device: AudioDevice) {
        self.device = device
    }
}
