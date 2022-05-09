import OpenAL
import Foundation

public struct AudioListener {
    public var gain: Float = 0.0
    public var position: Vector3 = .zero
    public var orientation: Matrix3 = .identity

    public var forward: Vector3 = Vector3(x: 0, y: 0, z: -1)
    public var up: Vector3 = Vector3(x: 0, y: 1, z: 0)
}

public class AudioDeviceContext {
    public let device: AudioDevice
    public let listener: AudioListener

    public init(device: AudioDevice) {
        self.device = device
        self.listener = AudioListener()
    }
}
