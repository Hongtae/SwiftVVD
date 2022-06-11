
public class AudioPlayer {

    public typealias State = AudioSource.State

    public var channels = 2
    public var bits = 16
    public var sampleRate = 441000
    public var duration = 0.0

    public var position = 0.0

    public var source: AudioSource
    public var stream: AudioStream

    public weak var playbackContext: AudioDeviceContext? {
        didSet {
            if oldValue !== playbackContext {
                if let device = oldValue {
                    device.unbindPlayer(self)
                }
                if let device = playbackContext {
                    device.bindPlayer(self)
                }
            }
        }
    }

    public init(source: AudioSource, stream: AudioStream) {
        self.source = source
        self.stream = stream
    }
}
