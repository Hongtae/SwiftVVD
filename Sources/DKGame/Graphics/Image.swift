//
//  File: Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation
import DKWrapper

public enum ImagePixelFormat {
    case invalid            
    case r8             //  1 byte  per pixel, uint8
    case rg8            //  2 bytes per pixel, uint8
    case rgb8           //  3 bytes per pixel, uint8
    case rgba8          //  4 bytes per pixel, uint8
    case r16            //  2 bytes per pixel, uint16
    case rg16           //  4 bytes per pixel, uint16
    case rgb16          //  6 bytes per pixel, uint16
    case rgba16         //  8 bytes per pixel, uint16
    case r32            //  4 bytes per pixel, uint32
    case rg32           //  8 bytes per pixel, uint32
    case rgb32          // 12 bytes per pixel, uint32
    case rgba32         // 16 bytes per pixel, uint32
    case r32f           //  4 bytes per pixel, float32
    case rg32f          //  8 bytes per pixel, float32
    case rgb32f         // 12 bytes per pixel, float32
    case rgba32f        // 16 bytes per pixel, float32
}

fileprivate extension ImagePixelFormat {
    static func from(dkImagePixelFormat pf: DKImagePixelFormat) -> ImagePixelFormat {
        switch pf {
        case DKImagePixelFormat_R8:         return .r8
        case DKImagePixelFormat_RG8:        return .rg8
        case DKImagePixelFormat_RGB8:       return .rgb8
        case DKImagePixelFormat_RGBA8:      return .rgba8
        case DKImagePixelFormat_R16:        return .r16
        case DKImagePixelFormat_RG16:       return .rg16
        case DKImagePixelFormat_RGB16:      return .rgb16
        case DKImagePixelFormat_RGBA16:     return .rgba16
        case DKImagePixelFormat_R32:        return .r32
        case DKImagePixelFormat_RG32:       return .rg32
        case DKImagePixelFormat_RGB32:      return .rgb32
        case DKImagePixelFormat_RGBA32:     return .rgba32
        case DKImagePixelFormat_R32F:       return .r32f
        case DKImagePixelFormat_RG32F:      return .rg32f
        case DKImagePixelFormat_RGB32F:     return .rgb32f
        case DKImagePixelFormat_RGBA32F:    return .rgba32f
        default:
            return .invalid 
        }
    }

    func dkImagePixelFormat() -> DKImagePixelFormat {
        switch self {
        case .r8:               return DKImagePixelFormat_R8
        case .rg8:              return DKImagePixelFormat_RG8
        case .rgb8:             return DKImagePixelFormat_RGB8
        case .rgba8:            return DKImagePixelFormat_RGBA8
        case .r16:              return DKImagePixelFormat_R16
        case .rg16:             return DKImagePixelFormat_RG16
        case .rgb16:            return DKImagePixelFormat_RGB16
        case .rgba16:           return DKImagePixelFormat_RGBA16
        case .r32:              return DKImagePixelFormat_R32
        case .rg32:             return DKImagePixelFormat_RG32
        case .rgb32:            return DKImagePixelFormat_RGB32
        case .rgba32:           return DKImagePixelFormat_RGBA32
        case .r32f:             return DKImagePixelFormat_R32F
        case .rg32f:            return DKImagePixelFormat_RG32F
        case .rgb32f:           return DKImagePixelFormat_RGB32F
        case .rgba32f:          return DKImagePixelFormat_RGBA32
        default:
            return DKImagePixelFormat_Invalid
        }
    }

    func bytesPerPixel() -> Int {
        Int(DKImagePixelFormatBytesPerPixel(dkImagePixelFormat()))
    }
}

public enum ImageFormat {
    case unknown
    case png
    case jpeg
    case bmp
}

fileprivate extension ImageFormat {
    static func from(dkImageFormat f: DKImageFormat) -> ImageFormat {
        switch f {
        case DKImageFormat_PNG:     return .png   
        case DKImageFormat_JPEG:    return .jpeg
        case DKImageFormat_BMP:     return .bmp
        default:
            return .unknown
        }
    }
    func dkImageFormat() -> DKImageFormat {
        switch self {
        case .png:      return DKImageFormat_PNG
        case .jpeg:     return DKImageFormat_JPEG
        case .bmp:      return DKImageFormat_BMP
        default:
            return DKImageFormat_Unknown
        }
    }
}

public enum ImageInterpolation {
    case nearest
    case bilinear
    case bicubic
    case spline
    case gaussian
    case quadratic
}


private typealias RawColorValue = (r: Double, g: Double, b: Double, a: Double)
// write fixed width integer
@inline(__always) private func writePixelR<T: FixedWidthInteger>(_ buffer: UnsafeMutableRawBufferPointer, offset: Int, color: RawColorValue, cType: T.Type)
{
    let q = Double(T.max)
    let value = T(color.r * q)
    buffer.storeBytes(of: value, toByteOffset: offset, as: type(of: value))
}
@inline(__always) private func writePixelRG<T: FixedWidthInteger>(_ buffer: UnsafeMutableRawBufferPointer, offset: Int, color: RawColorValue, cType: T.Type)
{
    let q = Double(T.max)
    let value = (T(color.r * q), T(color.g * q))
    buffer.storeBytes(of: value, toByteOffset: offset, as: type(of: value))
}
@inline(__always) private func writePixelRGB<T: FixedWidthInteger>(_ buffer: UnsafeMutableRawBufferPointer, offset: Int, color: RawColorValue, cType: T.Type)
{
    let q = Double(T.max)
    let value = (T(color.r * q), T(color.g * q), T(color.b * q))
    buffer.storeBytes(of: value, toByteOffset: offset, as: type(of: value))
}
@inline(__always) private func writePixelRGBA<T: FixedWidthInteger>(_ buffer: UnsafeMutableRawBufferPointer, offset: Int, color: RawColorValue, cType: T.Type)
{
    let q = Double(T.max)
    let value = (T(color.r * q), T(color.g * q), T(color.b * q), T(color.a * q))
    buffer.storeBytes(of: value, toByteOffset: offset, as: type(of: value))
}

// write floating point
@inline(__always) private func writePixelR<T: BinaryFloatingPoint>(_ buffer: UnsafeMutableRawBufferPointer, offset: Int, color: RawColorValue, cType: T.Type)
{
    let value = T(color.r)
    buffer.storeBytes(of: value, toByteOffset: offset, as: type(of: value))
}
@inline(__always) private func writePixelRG<T: BinaryFloatingPoint>(_ buffer: UnsafeMutableRawBufferPointer, offset: Int, color: RawColorValue, cType: T.Type)
{
    let value = (T(color.r), T(color.g))
    buffer.storeBytes(of: value, toByteOffset: offset, as: type(of: value))
}
@inline(__always) private func writePixelRGB<T: BinaryFloatingPoint>(_ buffer: UnsafeMutableRawBufferPointer, offset: Int, color: RawColorValue, cType: T.Type)
{
    let value = (T(color.r), T(color.g), T(color.b))
    buffer.storeBytes(of: value, toByteOffset: offset, as: type(of: value))
}
@inline(__always) private func writePixelRGBA<T: BinaryFloatingPoint>(_ buffer: UnsafeMutableRawBufferPointer, offset: Int, color: RawColorValue, cType: T.Type)
{
    let value = (T(color.r), T(color.g), T(color.b), T(color.a))
    buffer.storeBytes(of: value, toByteOffset: offset, as: type(of: value))
}

// read fixed width integer
@inline(__always) private func readPixelR<T: FixedWidthInteger>(_ data: UnsafeRawPointer, offset: Int, cType: T.Type) -> RawColorValue
{
    let norm = 1.0 / Double(T.max)
    let value = data.load(fromByteOffset: offset, as: T.self)
    return (Double(value) * norm, 0, 0, 1)
}
@inline(__always) private func readPixelRG<T: FixedWidthInteger>(_ data: UnsafeRawPointer, offset: Int, cType: T.Type) -> RawColorValue
{
    let norm = 1.0 / Double(T.max)
    let value = data.load(fromByteOffset: offset, as: (T, T).self)
    return (Double(value.0) * norm, Double(value.1) * norm, 0, 1)
}
@inline(__always) private func readPixelRGB<T: FixedWidthInteger>(_ data: UnsafeRawPointer, offset: Int, cType: T.Type) -> RawColorValue
{
    let norm = 1.0 / Double(T.max)
    let value = data.load(fromByteOffset: offset, as: (T, T, T).self)
    return (Double(value.0) * norm, Double(value.1) * norm, Double(value.2) * norm, 1)
}
@inline(__always) private func readPixelRGBA<T: FixedWidthInteger>(_ data: UnsafeRawPointer, offset: Int, cType: T.Type) -> RawColorValue
{
    let norm = 1.0 / Double(T.max)
    let value = data.load(fromByteOffset: offset, as: (T, T, T, T).self)
    return (Double(value.0) * norm, Double(value.1) * norm, Double(value.2) * norm, Double(value.3) * norm)
}

// read floating point
@inline(__always) private func readPixelR<T: BinaryFloatingPoint>(_ data: UnsafeRawPointer, offset: Int, cType: T.Type) -> RawColorValue
{
    let value = data.load(fromByteOffset: offset, as: T.self)
    return (Double(value), 0, 0, 1)
}
@inline(__always) private func readPixelRG<T: BinaryFloatingPoint>(_ data: UnsafeRawPointer, offset: Int, cType: T.Type) -> RawColorValue
{
    let value = data.load(fromByteOffset: offset, as: (T, T).self)
    return (Double(value.0), Double(value.1), 0, 1)
}
@inline(__always) private func readPixelRGB<T: BinaryFloatingPoint>(_ data: UnsafeRawPointer, offset: Int, cType: T.Type) -> RawColorValue
{
    let value = data.load(fromByteOffset: offset, as: (T, T, T).self)
    return (Double(value.0), Double(value.1), Double(value.2), 1)
}
@inline(__always) private func readPixelRGBA<T: BinaryFloatingPoint>(_ data: UnsafeRawPointer, offset: Int, cType: T.Type) -> RawColorValue
{
    let value = data.load(fromByteOffset: offset, as: (T, T, T, T).self)
    return (Double(value.0), Double(value.1), Double(value.2), Double(value.3))
}

public class Image {
    public let width: Int
    public let height: Int

    public let pixelFormat: ImagePixelFormat
    public var bytesPerPixel: Int { pixelFormat.bytesPerPixel() }

    public let data: Data

    public init?(data: UnsafeRawBufferPointer) {
        var result = DKImageDecodeFromMemory(data.baseAddress, data.count)
        defer { DKImageReleaseDecodeContext(&result) }
        if result.error == DKImageDecodeError_Success {
            self.width = Int(result.width)
            self.height = Int(result.height)
            self.pixelFormat = .from(dkImagePixelFormat: result.pixelFormat)
            let bytesPerPixel = self.pixelFormat.bytesPerPixel()
            assert(bytesPerPixel > 0)

            let byteCount = Int(result.decodedDataLength)
            assert(byteCount == bytesPerPixel * self.width * self.height)
            self.data = Data(bytes: result.decodedData, count: byteCount)
        } else {
            Log.err("Image DecodeError: \(String(cString: result.errorDescription))")
            return nil
        }
    }

    init(width: Int, height: Int, pixelFormat: ImagePixelFormat, data: Data) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.data = data
    }

    public func canEncode(toImageFormat imageFormat: ImageFormat) -> Bool {
        let dkImageFormat = imageFormat.dkImageFormat()
        let dkPixelFormat = self.pixelFormat.dkImagePixelFormat()
        let supportFormat = DKImagePixelFormatEncodingSupported(dkImageFormat, dkPixelFormat)
        let pf: ImagePixelFormat = .from(dkImagePixelFormat: supportFormat)
        if pf == self.pixelFormat {
            return true
        }
        return false
    }

    public func encode(format: ImageFormat) -> Data? {
        let imageFormat = format.dkImageFormat()
        let pixelFormat = self.pixelFormat.dkImagePixelFormat()
        let byteCount = self.bytesPerPixel * self.width * self.height
        assert(byteCount == self.data.count)

        var result = self.data.withUnsafeBytes {
            DKImageEncodeFromMemory(imageFormat,
                                    UInt32(self.width),
                                    UInt32(self.height),
                                    pixelFormat,
                                    $0.baseAddress, $0.count)
        }
        defer { DKImageReleaseEncodeContext(&result) }
        if result.error == DKImageEncodeError_Success {
            return .init(bytes: result.encodedData, count: result.encodedDataLength)
        } else {
            Log.err("Image EncodeError: \(String(cString: result.errorDescription))")
        }
        return nil
    }

    public func resample(format: ImagePixelFormat) -> Image? {
        self.resample(width: self.width, height: self.height, format: format, interpolation: .nearest)
    }

    public func resample(width: Int, height: Int, format: ImagePixelFormat, interpolation: ImageInterpolation) -> Image? {
        guard width > 0 && height > 0 && format != .invalid else { return nil }
        if width == self.width && height == self.height && format == self.pixelFormat {
            return self
        }

        let bpp = format.bytesPerPixel()
        let rowStride = bpp * width
        let bufferLength = rowStride * height
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferLength, alignment: 1)

        let writePixel: (_: UnsafeMutableRawBufferPointer, _: Int, _: RawColorValue)->Void
        switch format {
        case .r8:      writePixel = { writePixelR($0, offset: $1, color: $2, cType: UInt8.self) }
        case .rg8:     writePixel = { writePixelRG($0, offset: $1, color: $2, cType: UInt8.self) }
        case .rgb8:    writePixel = { writePixelRGB($0, offset: $1, color: $2, cType: UInt8.self) }
        case .rgba8:   writePixel = { writePixelRGBA($0, offset: $1, color: $2, cType: UInt8.self) }
        case .r16:     writePixel = { writePixelR($0, offset: $1, color: $2, cType: UInt16.self) }
        case .rg16:    writePixel = { writePixelRG($0, offset: $1, color: $2, cType: UInt16.self) }
        case .rgb16:   writePixel = { writePixelRGB($0, offset: $1, color: $2, cType: UInt16.self) }
        case .rgba16:  writePixel = { writePixelRGBA($0, offset: $1, color: $2, cType: UInt16.self) }
        case .r32:     writePixel = { writePixelR($0, offset: $1, color: $2, cType: UInt32.self) }
        case .rg32:    writePixel = { writePixelRG($0, offset: $1, color: $2, cType: UInt16.self) }
        case .rgb32:   writePixel = { writePixelRGB($0, offset: $1, color: $2, cType: UInt16.self) }
        case .rgba32:  writePixel = { writePixelRGBA($0, offset: $1, color: $2, cType: UInt16.self) }
        case .r32f:    writePixel = { writePixelR($0, offset: $1, color: $2, cType: Float.self) }
        case .rg32f:   writePixel = { writePixelRG($0, offset: $1, color: $2, cType: Float.self) }
        case .rgb32f:  writePixel = { writePixelRGB($0, offset: $1, color: $2, cType: Float.self) }
        case .rgba32f: writePixel = { writePixelRGBA($0, offset: $1, color: $2, cType: Float.self) }
        default:
            fatalError("Invalid format")
        }

        let readPixel: (_:UnsafeRawPointer, _:Int)->RawColorValue
        switch self.pixelFormat {
        case .r8:      readPixel = { readPixelR($0, offset: $1, cType: UInt8.self) }
        case .rg8:     readPixel = { readPixelRG($0, offset: $1, cType: UInt8.self) }
        case .rgb8:    readPixel = { readPixelRGB($0, offset: $1, cType: UInt8.self) }
        case .rgba8:   readPixel = { readPixelRGBA($0, offset: $1, cType: UInt8.self) }
        case .r16:     readPixel = { readPixelR($0, offset: $1, cType: UInt16.self) }
        case .rg16:    readPixel = { readPixelRG($0, offset: $1, cType: UInt16.self) }
        case .rgb16:   readPixel = { readPixelRGB($0, offset: $1, cType: UInt16.self) }
        case .rgba16:  readPixel = { readPixelRGBA($0, offset: $1, cType: UInt16.self) }
        case .r32:     readPixel = { readPixelR($0, offset: $1, cType: UInt32.self) }
        case .rg32:    readPixel = { readPixelRG($0, offset: $1, cType: UInt32.self) }
        case .rgb32:   readPixel = { readPixelRGB($0, offset: $1, cType: UInt32.self) }
        case .rgba32:  readPixel = { readPixelRGBA($0, offset: $1, cType: UInt32.self) }
        case .r32f:    readPixel = { readPixelR($0, offset: $1, cType: Float.self) }
        case .rg32f:   readPixel = { readPixelRG($0, offset: $1, cType: Float.self) }
        case .rgb32f:  readPixel = { readPixelRGB($0, offset: $1, cType: Float.self) }
        case .rgba32f: readPixel = { readPixelRGBA($0, offset: $1, cType: Float.self) }
        default:
            fatalError("Invalid format")
        }

        self.data.withUnsafeBytes { ptr in
            let scaleX = Float(self.width) / Float(width)
            let scaleY = Float(self.height) / Float(height)

            let sourceBpp = self.pixelFormat.bytesPerPixel()
            let sourceData = UnsafeRawPointer(ptr.baseAddress)!
            let getPixel = { (x: Float, y: Float) -> RawColorValue in
                let x = clamp(Int(x), min: 0, max: self.width - 1)
                let y = clamp(Int(y), min: 0, max: self.height - 1)
                let offset = (y * self.width + x) * sourceBpp
                return readPixel(sourceData, offset)
            }
            let interpKernel = { (kernel: (Float)->Double, x: Float, y: Float) -> RawColorValue in
                let fx = floor(x)
                let fy = floor(y)
                let px = (-1...2).map { fx + .init($0) }
                let py = (-1...2).map { fy + .init($0) }
                let kx = px.map { kernel($0 - x) }
                let ky = py.map { kernel($0 - y) }

                var color: RawColorValue = (0, 0, 0, 0)
                py.indices.forEach { yIndex in
                    px.indices.forEach { xIndex in
                        let k = kx[xIndex] * ky[yIndex]
                        let c = getPixel(px[xIndex], py[yIndex])
                        color = (color.r + c.r * k, color.g + c.g * k, color.b + c.b * k, color.a + c.a * k)
                    }
                }
                return color
            }
            let interpolatePoint: (_: Float, _: Float)->RawColorValue
            switch interpolation {
            case .nearest:
                interpolatePoint = { x, y in
                    getPixel(x.rounded(), y.rounded())
                }
            case .bilinear:
                interpolatePoint = { x, y in
                    let x1 = floor(x)
                    let x2 = floor(x + 1)
                    let y1 = floor(y)
                    let y2 = floor(y + 1)
                    let t1 = Double(x - x1)
                    let t2 = Double(y - y1)
                    let d = t1 * t2
                    let b = t1 - d
                    let c = t2 - d
                    let a = 1.0 - t1 - c
                    let p1 = getPixel(x1, y1)
                    let p2 = getPixel(x2, y1)
                    let p3 = getPixel(x1, y2)
                    let p4 = getPixel(x2, y2)
                    return (p1.r * a + p2.r * b + p3.r * c + p4.r * d,
                            p1.g * a + p2.g * b + p3.g * c + p4.g * d,
                            p1.b * a + p2.b * b + p3.b * c + p4.b * d,
                            p1.a * a + p2.a * b + p3.a * c + p4.a * d)
                }
            case .bicubic:
                interpolatePoint = { x, y in
                    let kernelCubic = { (t: Float) -> Double in
                        let t1 = abs(t)
                        let t2 = t1 * t1
                        if t1 < 1 { return .init(1 - 2 * t2 + t2 * t1) }
                        if t1 < 2 { return .init(4 - 8 * t1 + 5 * t2 - t2 * t1) }
                        return 0.0
                    }
                    return interpKernel(kernelCubic, x, y)
                }
            case .spline:
                interpolatePoint = { x, y in
                    let kernelSpline = { (t: Float) -> Double in
                        let t = Double(t)
                        if t < -2.0 { return 0.0 }
                        if t < -1.0 { return (2.0 + t) * (2.0 + t) * (2.0 + t) * 0.16666666666666666667 }
                        if t < 0.0  { return (4.0 + t * t * (-6.0 - 3.0 * t)) * 0.16666666666666666667 }
                        if t < 1.0  { return (4.0 + t * t * (-6.0 + 3.0 * t)) * 0.16666666666666666667 }
                        if t < 2.0  { return (2.0 - t) * (2.0 - t) * (2.0 - t) * 0.16666666666666666667 }
                        return 0.0
                    }
                    return interpKernel(kernelSpline, x, y)
                }
            case .gaussian:
                interpolatePoint = { x, y in
                    let kernelGaussian = { (t: Float) -> Double in
                        return exp(-2.0 * Double(t * t)) * 0.79788456080287
                    }
                    return interpKernel(kernelGaussian, x, y)
                }
            case .quadratic:
                interpolatePoint = { x, y in
                    let kernelQuadratic = { (t: Float) -> Double in
                        if t < -1.5 { return 0 }
                        if t < -0.5 { return .init(0.5 * (t + 1.5) * (t + 1.5)) }
                        if t < 0.5 { return .init(0.75 - t * t) }
                        if t < 1.5 { return .init(0.5 * (t - 1.5) * (t - 1.5)) }
                        return 0.0
                    }
                    return interpKernel(kernelQuadratic, x, y)
                }
            }

            let interpolateBox = { (x: Float, y: Float)->RawColorValue in
                let x1 = x - scaleX * 0.5
                let x2 = x + scaleX * 0.5
                let y1 = y - scaleY * 0.5
                let y2 = y + scaleY * 0.5

                var color: RawColorValue = (0, 0, 0, 0)
                for y in Int(y1.rounded())...Int(y2.rounded()) {
                    for x in Int(x1.rounded())...Int(x2.rounded()) {
                        let xMin = max(Float(x)-0.5, x1)
                        let xMax = min(Float(x)+0.5, x2)
                        let yMin = max(Float(y)-0.5, y1)
                        let yMax = min(Float(y)+0.5, y2)
                        let k = Double((xMax - xMin) * (yMax - yMin))
                        let c = interpolatePoint((xMin + xMax) * 0.5, (yMin + yMax) * 0.5)
                        color = (color.r + c.r * k, color.g + c.g * k, color.b + c.b * k, color.a + c.a * k)
                    }
                }
                let area = 1.0 / Double((x2 - x1) * (y2 - y1))
                return (color.r * area, color.g * area, color.b * area, color.a * area)
            }
            var sample: (_:Float, _:Float)->RawColorValue = { getPixel($0, $1) }
            if self.width != width || self.height != height {
                if scaleX <= 1 && scaleY <= 1 { // enlarge
                    sample = interpolatePoint
                } else {
                    sample = interpolateBox
                }
            }

            for ny in 0..<height {
                for nx in 0..<width {
                    // convert source location
                    let x = (Float(nx) + 0.5) * scaleX - 0.5
                    let y = (Float(ny) + 0.5) * scaleY - 0.5

                    var color = sample(x, y)
                    color.r = color.r.clamp(min: 0, max: 1)
                    color.g = color.g.clamp(min: 0, max: 1)
                    color.b = color.b.clamp(min: 0, max: 1)
                    color.a = color.a.clamp(min: 0, max: 1)
                    let offset = ny * rowStride + nx * bpp
                    writePixel(buffer, offset, color)
                }
            }
        }
        return .init(width: width, height: height,
                     pixelFormat: format,
                     data: Data(bytesNoCopy: buffer.baseAddress!,
                                count: buffer.count,
                                deallocator: .custom({ p,_ in p.deallocate()})
                                ))
    }
}

extension Image {
    public func makeTexture(commandQueue: CommandQueue, usage: TextureUsage = .sampled) -> Texture? {
        var textureFormat: PixelFormat = .invalid
        var imageFormat: ImagePixelFormat = self.pixelFormat

        switch self.pixelFormat {
        case .r8:               textureFormat = .r8Unorm
        case .rg8:              textureFormat = .rg8Unorm
        case .rgb8, .rgba8:     textureFormat = .rgba8Unorm
                                imageFormat = .rgba8
        case .r16:              textureFormat = .r16Unorm
        case .rg16:             textureFormat = .rg16Unorm
        case .rgb16, .rgba16:   textureFormat = .rgba16Unorm
                                imageFormat = .rgba16
        case .r32:              textureFormat = .r32Uint
        case .rg32:             textureFormat = .rg32Uint
        case .rgb32, .rgba32:   textureFormat = .rgba32Uint
                                imageFormat = .rgba32
        case .r32f:             textureFormat = .r32Float
        case .rg32f:            textureFormat = .rg32Float
        case .rgb32f, .rgba32f: textureFormat = .rgba32Float
                                imageFormat = .rgba32f
        default:
            textureFormat = .invalid
        }
        if textureFormat == .invalid {
            Log.error("Invalid pixel format")
            return nil
        }
        if imageFormat != self.pixelFormat {
            return self.resample(format: imageFormat)?.makeTexture(commandQueue: commandQueue)
        }

        let device = commandQueue.device

        // create texture.
        guard let texture = device.makeTexture(
            descriptor: TextureDescriptor(textureType: .type2D,
                                          pixelFormat: textureFormat,
                                          width: width,
                                          height: height,
                                          usage: usage.union(.copyDestination)))
        else { return nil }

        // create buffer for staging
        guard let stgBuffer = self.data.withUnsafeBytes({ src in
            if let buffer = device.makeBuffer(length: src.count,
                                              storageMode: .shared,
                                              cpuCacheMode: .writeCombined) {
                if let dest = buffer.contents() {
                    dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                    buffer.flush()
                    return buffer
                }
            }
            return nil
        }) else { return nil }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }
        guard let encoder = commandBuffer.makeCopyCommandEncoder() else {
            return nil
        }
        encoder.copy(from: stgBuffer,
                     sourceOffset: BufferImageOrigin(offset: 0,
                                                     imageWidth: width,
                                                     imageHeight: height),
                     to: texture,
                     destinationOffset: TextureOrigin(layer: 0, level: 0,
                                                      x: 0, y: 0, z: 0),
                     size: TextureSize(width: width, height: height, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        return texture
    }
}
