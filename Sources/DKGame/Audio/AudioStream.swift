import DKGameUtils

public class AudioStream {
    var stream: DKAudioStream?

    deinit {
        if var s = stream {
            withUnsafeMutablePointer(to: &s) {
                ptr in DKAudioStreamDestroy(ptr)
            }
        }
    }
}
