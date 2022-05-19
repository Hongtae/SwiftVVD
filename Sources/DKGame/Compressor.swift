import DKGameUtils
import Foundation

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
    static public func compress(in input: InputStream, out output: OutputStream, method: Method) -> Bool {
        var inStream = DKStream()
        inStream.userContext = unsafeBitCast(input as AnyObject, to: DKStreamContext.self)
        inStream.read = { ctxt, data, size in
            let input = unsafeBitCast(ctxt, to: AnyObject.self) as! InputStream
            return UInt64(input.read(data!.assumingMemoryBound(to: UInt8.self), maxLength: size))
        }
        var outStream = DKStream()
        outStream.userContext = unsafeBitCast(output as AnyObject, to: DKStreamContext.self)
        inStream.write = { ctxt, data, size in
            let output = unsafeBitCast(ctxt, to: AnyObject.self) as! OutputStream
            return UInt64(output.write(data!.assumingMemoryBound(to: UInt8.self), maxLength: size))
        }

        var level = method.level
        var algo: DKCompressionAlgorithm
        switch method.algorithm {
            case .zlib: algo = DKCompressionAlgorithm_Zlib
            case .zstd: algo = DKCompressionAlgorithm_Zstd
            case .lz4:  algo = DKCompressionAlgorithm_Lz4
            case .lzma: algo = DKCompressionAlgorithm_Lzma
            case .automatic:
                algo = DKCompressionAlgorithm_Zstd
                level = 3
        }
        let inputStreamOpen = input.streamStatus == .notOpen
        let outputStreamOpen = output.streamStatus == .notOpen
        if inputStreamOpen { input.open() }
        if outputStreamOpen { output.open() }

        let result = DKCompressionEncode(algo, &inStream, &outStream, Int32(level))

        if inputStreamOpen { input.close() }
        if outputStreamOpen { output.close() }

        return result == DKCompressionResult_Success
    }
    static public func decompress(in: InputStream, out: OutputStream) -> Bool {

        false
    }
}
