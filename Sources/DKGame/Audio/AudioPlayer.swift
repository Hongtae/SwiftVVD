@AudioActor
public class AudioPlayer {

    public typealias State = AudioSource.State

    public nonisolated var sampleRate: Int  { stream.sampleRate }
    public nonisolated var channels: Int    { stream.channels }
    public nonisolated var bits: Int        { stream.bits }
    public nonisolated var duration: Double { stream.timeTotal }

    public var position: Double { stream.timePosition }

    public let source: AudioSource
    public let stream: AudioStream

    var playing = false
    var buffering = false
    var bufferedPosition: Double = 0.0
    var playbackPosition: Double = 0.0
    var playLoopCount = 0
    var bufferSize = 0
    var maxBufferingTime = 1.0

    public init(source: AudioSource, stream: AudioStream) {
        self.source = source
        self.stream = stream
    }

    deinit {
        source.state = .stopped
        source.dequeueBuffers()
    }

    func bufferingStateChanged(_: Bool, timeStamp: Double) {
    }

    func playbackStateChanged(_: Bool, position: Double) {
    }

    func processStream(data: UnsafeRawPointer, byteCount: Int, timeStamp: Double) {        
    }
}
