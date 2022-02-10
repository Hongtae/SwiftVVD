import DKGameUtils

public class Compressor {
    public enum Algorithm {
        case zlib
        case zstd
        case lz4
        case lzma
        case automatic // Default method for compression, Auto-detected method for decompression.
    }
    public struct Method {
        public var algorithm: Algorithm
        public var level: Int

        public static let fastest = Method(algorithm:.lz4, level:0)
        public static let fast = Method(algorithm:.lz4, level:9)
        public static let best = Method(algorithm:.lzma, level:9)
        public static let balance = Method(algorithm: .zstd, level:3)
        public static let automatic = Method(algorithm: .automatic, level:0)
    }

    public init() {
    }
    static public func Compress(method: Method) -> Bool {
       var stream: DKStream = DKStream()

        let compressionResult: DKCompressionResult = withUnsafeMutablePointer(to: &stream) {
            pstream in
            DKCompressionEncode(DKCompressionAlgorithm_Zstd, pstream, nil, 0)
        }
        return compressionResult == DKCompressionResult_Success
    }
    static public func Decompress() {

    }
}