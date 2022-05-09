
public class AudioPlayer {

    public typealias State = AudioSource.State

    public var channels = 2
    public var bits = 16
    public var sampleRate = 441000
    public var duration = 0.0

    public var position = 0.0

    public var source: AudioSource? = nil
    public var stream: AudioStream? = nil
}