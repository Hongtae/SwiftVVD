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
            var v: Vector3 = .zero
            alGetListener3f(AL_POSITION, &v.x, &v.y, &v.z)
            return v
        }
        set(v) {
            alListener3f(AL_POSITION, v.x, v.y, v.z)
        }
    }

    public var velocity: Vector3 {
        get {
            var v: Vector3 = .zero
            alGetListener3f(AL_VELOCITY, &v.x, &v.y, &v.z)
            return v
        }
        set(v) {
            alListener3f(AL_VELOCITY, v.x, v.y, v.z)
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
        let v = [f.x, f.y, f.z, u.x, u.y, u.z]
        alListenerfv(AL_ORIENTATION, v)
    }

    public func setOrientation(matrix: Matrix3) {
        self.setOrientation(forward: matrix.row3, up: matrix.row2)
    }

    init(device: AudioDevice) {
        self.device = device
    }
}
