
public class AudioSource {
    public enum State {
        case unknown
        case stopped
        case playing
        case paused
    }

    public var pitch: Float = 1.0
    public var gain: Float = 1.0
    public var maxGain: Float = 1.0
    public var maxDistance: Float = 0.0
    public var rollOffFactor: Float = 0.0
    public var coneOuterGain: Float = 0.0
    public var coneInnerAngle: Float = 0.0
    public var coneOuterAngle: Float = 0.0
    public var referenceDistance: Float = 0.0
    public var position: Vector3 = .zero
    public var velocity: Vector3 = .zero
    public var direction: Vector3 = .zero

    public var state: State = .unknown
}
