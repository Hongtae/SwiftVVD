//
//  File: Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVDHelper

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

private extension ImagePixelFormat {
    static func from(foreignFormat pf: VVDImagePixelFormat) -> ImagePixelFormat {
        switch pf {
        case VVDImagePixelFormat_R8:         return .r8
        case VVDImagePixelFormat_RG8:        return .rg8
        case VVDImagePixelFormat_RGB8:       return .rgb8
        case VVDImagePixelFormat_RGBA8:      return .rgba8
        case VVDImagePixelFormat_R16:        return .r16
        case VVDImagePixelFormat_RG16:       return .rg16
        case VVDImagePixelFormat_RGB16:      return .rgb16
        case VVDImagePixelFormat_RGBA16:     return .rgba16
        case VVDImagePixelFormat_R32:        return .r32
        case VVDImagePixelFormat_RG32:       return .rg32
        case VVDImagePixelFormat_RGB32:      return .rgb32
        case VVDImagePixelFormat_RGBA32:     return .rgba32
        case VVDImagePixelFormat_R32F:       return .r32f
        case VVDImagePixelFormat_RG32F:      return .rg32f
        case VVDImagePixelFormat_RGB32F:     return .rgb32f
        case VVDImagePixelFormat_RGBA32F:    return .rgba32f
        default:
            return .invalid 
        }
    }

    func foreignFormat() -> VVDImagePixelFormat {
        switch self {
        case .r8:               return VVDImagePixelFormat_R8
        case .rg8:              return VVDImagePixelFormat_RG8
        case .rgb8:             return VVDImagePixelFormat_RGB8
        case .rgba8:            return VVDImagePixelFormat_RGBA8
        case .r16:              return VVDImagePixelFormat_R16
        case .rg16:             return VVDImagePixelFormat_RG16
        case .rgb16:            return VVDImagePixelFormat_RGB16
        case .rgba16:           return VVDImagePixelFormat_RGBA16
        case .r32:              return VVDImagePixelFormat_R32
        case .rg32:             return VVDImagePixelFormat_RG32
        case .rgb32:            return VVDImagePixelFormat_RGB32
        case .rgba32:           return VVDImagePixelFormat_RGBA32
        case .r32f:             return VVDImagePixelFormat_R32F
        case .rg32f:            return VVDImagePixelFormat_RG32F
        case .rgb32f:           return VVDImagePixelFormat_RGB32F
        case .rgba32f:          return VVDImagePixelFormat_RGBA32
        default:
            return VVDImagePixelFormat_Invalid
        }
    }
}

public extension ImagePixelFormat {
    var bytesPerPixel: Int {
        Int(VVDImagePixelFormatBytesPerPixel(foreignFormat()))
    }
}

public enum ImageFormat {
    case unknown
    case png
    case jpeg
    case bmp
}

private extension ImageFormat {
    static func from(foreignFormat f: VVDImageFormat) -> ImageFormat {
        switch f {
        case VVDImageFormat_PNG:     return .png   
        case VVDImageFormat_JPEG:    return .jpeg
        case VVDImageFormat_BMP:     return .bmp
        default:
            return .unknown
        }
    }
    func foreignFormat() -> VVDImageFormat {
        switch self {
        case .png:      return VVDImageFormat_PNG
        case .jpeg:     return VVDImageFormat_JPEG
        case .bmp:      return VVDImageFormat_BMP
        default:
            return VVDImageFormat_Unknown
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

private typealias ReadFunction = (_:UnsafeRawPointer, _:Int)->RawColorValue
private typealias WriteFunction = (_: UnsafeMutableRawBufferPointer, _: Int, _: RawColorValue)->Void
@inline(__always) private func getReadFunction(_ format: ImagePixelFormat)->ReadFunction? {
    let readPixel: ReadFunction? = 
    switch format {
    case .r8:      { readPixelR($0, offset: $1, cType: UInt8.self) }
    case .rg8:     { readPixelRG($0, offset: $1, cType: UInt8.self) }
    case .rgb8:    { readPixelRGB($0, offset: $1, cType: UInt8.self) }
    case .rgba8:   { readPixelRGBA($0, offset: $1, cType: UInt8.self) }
    case .r16:     { readPixelR($0, offset: $1, cType: UInt16.self) }
    case .rg16:    { readPixelRG($0, offset: $1, cType: UInt16.self) }
    case .rgb16:   { readPixelRGB($0, offset: $1, cType: UInt16.self) }
    case .rgba16:  { readPixelRGBA($0, offset: $1, cType: UInt16.self) }
    case .r32:     { readPixelR($0, offset: $1, cType: UInt32.self) }
    case .rg32:    { readPixelRG($0, offset: $1, cType: UInt32.self) }
    case .rgb32:   { readPixelRGB($0, offset: $1, cType: UInt32.self) }
    case .rgba32:  { readPixelRGBA($0, offset: $1, cType: UInt32.self) }
    case .r32f:    { readPixelR($0, offset: $1, cType: Float.self) }
    case .rg32f:   { readPixelRG($0, offset: $1, cType: Float.self) }
    case .rgb32f:  { readPixelRGB($0, offset: $1, cType: Float.self) }
    case .rgba32f: { readPixelRGBA($0, offset: $1, cType: Float.self) }
    default:
        nil
    }
    return readPixel
}
@inline(__always) private func getWriteFunction(_ format: ImagePixelFormat)->WriteFunction? {
    let writePixel: WriteFunction? =
    switch format {
    case .r8:      { writePixelR($0, offset: $1, color: $2, cType: UInt8.self) }
    case .rg8:     { writePixelRG($0, offset: $1, color: $2, cType: UInt8.self) }
    case .rgb8:    { writePixelRGB($0, offset: $1, color: $2, cType: UInt8.self) }
    case .rgba8:   { writePixelRGBA($0, offset: $1, color: $2, cType: UInt8.self) }
    case .r16:     { writePixelR($0, offset: $1, color: $2, cType: UInt16.self) }
    case .rg16:    { writePixelRG($0, offset: $1, color: $2, cType: UInt16.self) }
    case .rgb16:   { writePixelRGB($0, offset: $1, color: $2, cType: UInt16.self) }
    case .rgba16:  { writePixelRGBA($0, offset: $1, color: $2, cType: UInt16.self) }
    case .r32:     { writePixelR($0, offset: $1, color: $2, cType: UInt32.self) }
    case .rg32:    { writePixelRG($0, offset: $1, color: $2, cType: UInt16.self) }
    case .rgb32:   { writePixelRGB($0, offset: $1, color: $2, cType: UInt16.self) }
    case .rgba32:  { writePixelRGBA($0, offset: $1, color: $2, cType: UInt16.self) }
    case .r32f:    { writePixelR($0, offset: $1, color: $2, cType: Float.self) }
    case .rg32f:   { writePixelRG($0, offset: $1, color: $2, cType: Float.self) }
    case .rgb32f:  { writePixelRGB($0, offset: $1, color: $2, cType: Float.self) }
    case .rgba32f: { writePixelRGBA($0, offset: $1, color: $2, cType: Float.self) }
    default:
        nil
    }
    return writePixel
}


public struct Image {
    public let width: Int
    public let height: Int

    public let pixelFormat: ImagePixelFormat
    public var bytesPerPixel: Int { pixelFormat.bytesPerPixel }

    internal var data: Data

    public init?(data: UnsafeRawBufferPointer) {
        var result = VVDImageDecodeFromMemory(data.baseAddress, data.count)
        defer { VVDImageReleaseDecodeContext(&result) }
        if result.error == VVDImageDecodeError_Success {
            self.width = Int(result.width)
            self.height = Int(result.height)
            self.pixelFormat = .from(foreignFormat: result.pixelFormat)
            let bytesPerPixel = self.pixelFormat.bytesPerPixel
            assert(bytesPerPixel > 0)

            let byteCount = Int(result.decodedDataLength)
            assert(byteCount == bytesPerPixel * self.width * self.height)
            self.data = Data(bytes: result.decodedData, count: byteCount)
        } else {
            Log.err("Image DecodeError: \(String(cString: result.errorDescription))")
            return nil
        }
    }

    public init<T>(width: Int, height: Int, pixelFormat: ImagePixelFormat, content: T) {
        assert(width > 0)
        assert(height > 0)
        assert(pixelFormat != .invalid)

        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        let length = pixelFormat.bytesPerPixel * width * height
        self.data = Data(count: length)
        let copyBytes = MemoryLayout<T>.size.clamp(min: 0, max: length)
        if copyBytes > 0 {
            _=self.data.withUnsafeMutableBytes { buffer in
                withUnsafeBytes(of: content) {
                    $0.copyBytes(to: buffer, count: copyBytes)
                }
            }
        }
    }

    public init(width: Int, height: Int, pixelFormat: ImagePixelFormat, data: (any DataProtocol)? = nil) {
        assert(width > 0)
        assert(height > 0)
        assert(pixelFormat != .invalid)

        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        let length = pixelFormat.bytesPerPixel * width * height
        self.data = Data(count: length)
        if let data {
            let copyBytes = data.count.clamp(min: 0, max: length)
            if copyBytes > 0 {
                _=self.data.withUnsafeMutableBytes {
                    (bufferPointer: UnsafeMutableRawBufferPointer) in
                    data.copyBytes(to: bufferPointer, count: copyBytes)
                }
            }
        }
    }

    public func canEncode(toImageFormat imageFormat: ImageFormat) -> Bool {
        let imageFormat = imageFormat.foreignFormat()
        let pixelFormat = self.pixelFormat.foreignFormat()
        let supportFormat = VVDImagePixelFormatEncodingSupported(imageFormat, pixelFormat)
        let pf: ImagePixelFormat = .from(foreignFormat: supportFormat)
        if pf == self.pixelFormat {
            return true
        }
        return false
    }

    public func encode(format: ImageFormat) -> Data? {
        let imageFormat = format.foreignFormat()
        let pixelFormat = self.pixelFormat.foreignFormat()
        let byteCount = self.bytesPerPixel * self.width * self.height
        assert(byteCount == self.data.count)

        var result = self.data.withUnsafeBytes {
            VVDImageEncodeFromMemory(imageFormat,
                                    UInt32(self.width),
                                    UInt32(self.height),
                                    pixelFormat,
                                    $0.baseAddress, $0.count)
        }
        defer { VVDImageReleaseEncodeContext(&result) }
        if result.error == VVDImageEncodeError_Success {
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

        if getWriteFunction(format) == nil {
            Log.error("Invalid output format!")
            return nil
        }
        if getReadFunction(self.pixelFormat) == nil {
            Log.error("Invalid input format!")
            return nil
        }

        let bpp = format.bytesPerPixel
        let rowStride = bpp * width
        let bufferLength = rowStride * height
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferLength, alignment: 1)

        var image = Image(width: width, height: height,
                          pixelFormat: format,
                          data: Data(bytesNoCopy: buffer.baseAddress!,
                                     count: buffer.count,
                                     deallocator: .custom({ p,_ in p.deallocate()})))

        if self.width == width && self.height == height {
            for ny in 0..<height {
                for nx in 0..<width {
                    let color = readPixel(x: nx, y: ny)
                    image.writePixel(x: nx, y: ny, value: color)
                }
            }
        } else {
            let scaleX = Float(self.width) / Float(width)
            let scaleY = Float(self.height) / Float(height)

            for ny in 0..<height {
                for nx in 0..<width {
                    // convert source location
                    let x = (Float(nx) + 0.5) * scaleX - 0.5
                    let y = (Float(ny) + 0.5) * scaleY - 0.5

                    let x1 = x - scaleX * 0.5
                    let x2 = x + scaleX * 0.5
                    let y1 = y - scaleY * 0.5
                    let y2 = y + scaleY * 0.5

                    let color = _interpolate(x1, x2, y1, y2, interpolation)
                    image.writePixel(x: nx, y: ny, value: color)
                }
            }
        }
        return image
    }

    public typealias Pixel = (r: Double, g: Double, b: Double, a: Double)

    public func readPixel(x: Int, y: Int) -> Pixel {
        if let fn = getReadFunction(self.pixelFormat) {
            let bpp = self.bytesPerPixel
            let x = clamp(x, min: 0, max: self.width - 1)
            let y = clamp(y, min: 0, max: self.height - 1)
            let offset = (y * self.width + x) * bpp
            let value = self.data.withUnsafeBytes {
                fn($0.baseAddress!, offset)
            }
            return Pixel(r: value.r, g: value.g, b: value.b, a: value.a)
        } else {
            Log.error("Invalid pixel format")
        }
        return Pixel(r: 0, g: 0, b: 0, a: 0)
    }

    public mutating func writePixel(x: Int, y: Int, value: Pixel) {
        if let fn = getWriteFunction(self.pixelFormat) {
            let bpp = self.bytesPerPixel
            let x = clamp(x, min: 0, max: self.width - 1)
            let y = clamp(y, min: 0, max: self.height - 1)
            let offset = (y * self.width + x) * bpp

            let color = RawColorValue(r: clamp(value.r, min: 0, max: 1),
                                      g: clamp(value.g, min: 0, max: 1),
                                      b: clamp(value.b, min: 0, max: 1),
                                      a: clamp(value.a, min: 0, max: 1))
            self.data.withUnsafeMutableBytes { fn($0, offset, color) }
        } else {
            Log.error("Invalid pixel format")
        }
    }

    public func interpolate(_ rect: CGRect, interpolate interp: ImageInterpolation) -> Pixel {
        if rect.isNull { return Pixel(r: 0, g: 0, b: 0, a: 0) }
        if rect.isInfinite {
            return _interpolate(0, Float(self.width), 0, Float(self.height), interp)
        }
        return _interpolate(Float(rect.minX), Float(rect.maxX), Float(rect.minY), Float(rect.maxY), interp)
    }

    private func _interpolate(_ _x1: Float, _ _x2: Float, _ _y1: Float, _ _y2: Float, _ interp: ImageInterpolation) -> Pixel {
        guard let readPixel = getReadFunction(self.pixelFormat) else {
            Log.error("Invalid pixel format")
            return Pixel(r: 0, g: 0, b: 0, a: 0)
        }

        let bpp = self.bytesPerPixel
        let getPixel = { (x: Float, y: Float) -> RawColorValue in
            let nx = clamp(Int(x), min: 0, max: self.width - 1)
            let ny = clamp(Int(y), min: 0, max: self.height - 1)
            let offset = (ny * self.width + nx) * bpp
            return self.data.withUnsafeBytes {
                readPixel($0.baseAddress!, offset)
            }
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
        switch interp {
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
                    let f: Double = 1.0 / 6.0
                    let t = Double(t)
                    if t < -2.0 { return 0.0 }
                    if t < -1.0 { return (2.0 + t) * (2.0 + t) * (2.0 + t) * f }
                    if t < 0.0  { return (4.0 + t * t * (-6.0 - 3.0 * t)) * f }
                    if t < 1.0  { return (4.0 + t * t * (-6.0 + 3.0 * t)) * f }
                    if t < 2.0  { return (2.0 - t) * (2.0 - t) * (2.0 - t) * f }
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

        let scaleX = abs(_x1 - _x2)
        let scaleY = abs(_y1 - _y2)

        let interpolateBox = { (x: Float, y: Float)->RawColorValue in
            let x1 = x - scaleX * 0.5
            let x2 = x + scaleX * 0.5
            let y1 = y - scaleY * 0.5
            let y2 = y + scaleY * 0.5

            var color: RawColorValue = (0, 0, 0, 0)
            for ny in Int(y1.rounded())...Int(y2.rounded()) {
                for nx in Int(x1.rounded())...Int(x2.rounded()) {
                    let xMin = max(Float(nx)-0.5, x1)
                    let xMax = min(Float(nx)+0.5, x2)
                    let yMin = max(Float(ny)-0.5, y1)
                    let yMax = min(Float(ny)+0.5, y2)
                    let k = Double((xMax - xMin) * (yMax - yMin))
                    let c = interpolatePoint((xMin + xMax) * 0.5, (yMin + yMax) * 0.5)
                    color = (color.r + c.r * k, color.g + c.g * k, color.b + c.b * k, color.a + c.a * k)
                }
            }
            let area = 1.0 / Double((x2 - x1) * (y2 - y1))
            return (color.r * area, color.g * area, color.b * area, color.a * area)
        }

        let sample: (_:Float, _:Float)->RawColorValue
        if scaleX < 1.0 && scaleY < 1.0 {
            sample = interpolatePoint // enlarge
        } else {
            sample = interpolateBox
        }

        let x = min(_x1, _x2)
        let y = min(_y1, _y2)
        let color = sample(x, y)
        return Pixel(r: color.r, g: color.g, b: color.b, a: color.a)        
    }
}


@inline(__always) private func fixedToDouble<T>(_ value: T) -> Double where T: FixedWidthInteger, T: SignedInteger {
    return max(Double(value) / Double(T.max - 1), -1.0)
}
@inline(__always) private func fixedToDouble<T>(_ value: T) -> Double where T: FixedWidthInteger, T: UnsignedInteger {
    return Double(value) / Double(T.max - 1)
}
@inline(__always) private func ufloatToDouble(eBits: UInt, mBits: UInt, exponent: UInt32, mantissa: UInt32) -> Double {
    let expUpper: UInt32 = (1 << eBits) - 1
    let expLower: UInt32 = expUpper >> 1
    let manUpper = Double(1 << mBits)

    let m = mantissa & ((1 << mBits) - 1)
    let e = exponent & ((1 << eBits) - 1)

    if e == 0 {
        if m == 0 { return .zero }
        return (1.0 / Double(1 << (expLower - 1))) * (Double(m) / manUpper)
    }
    if e < expUpper {
        if e > expLower {
            return Double(1 << (e - expLower)) * (1.0 + Double(m) / manUpper)
        }
        return (1.0 / Double(1 << (expLower - e))) * (1.0 + Double(m) / manUpper)
    }
    if m == 0 { return .infinity }
    return .nan
}
@inline(__always) private func ufloatToDouble(eBits: UInt, mBits: UInt, value: UInt32) -> Double {
    ufloatToDouble(eBits: eBits, mBits: mBits, exponent: value >> mBits, mantissa: value)
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
                                          usage: usage.union([.copySource, .copyDestination])))
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

    public static func fromTexture(buffer: GPUBuffer,
                                   width: Int, height: Int,
                                   pixelFormat: PixelFormat) -> Image? {
        if (width < 1 || height < 1) {
            Log.error("Invalid texture dimensions")
            return nil
        }
        var imageFormat: ImagePixelFormat = .invalid
        var getPixel: ((_:UnsafeRawPointer)->RawColorValue)?
        switch pixelFormat {
        case .r8Unorm, .r8Uint:
            imageFormat = .r8
            getPixel = { data in
                let p = data.assumingMemoryBound(to: UInt8.self).pointee
                return (fixedToDouble(p), 0, 0, 1)
            }
        case .r8Snorm, .r8Sint:
            imageFormat = .r8
            getPixel = { data in
                let p = data.assumingMemoryBound(to: Int8.self).pointee
                return (fixedToDouble(p), 0, 0, 1)
            }
        case .r16Unorm, .r16Uint:
            imageFormat = .r16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: UInt16.self).pointee
                return (fixedToDouble(p), 0, 0, 1)
            }
        case .r16Snorm, .r16Sint:
            imageFormat = .r16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: Int16.self).pointee
                return (fixedToDouble(p), 0, 0, 1)
            }
        case .r16Float:
            imageFormat = .r16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: Float16.self).pointee
                return (Double(p), 0, 0, 1)
            }
        case .rg8Unorm, .rg8Uint:
            imageFormat = .rg8
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (UInt8, UInt8).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), 0, 1)
            }
        case .rg8Snorm, .rg8Sint:
            imageFormat = .rg8
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (Int8, Int8).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), 0, 1)
            }
        case .r32Uint:
            imageFormat = .r32
            getPixel = { data in
                let p = data.assumingMemoryBound(to: UInt32.self).pointee
                return (fixedToDouble(p), 0, 0, 1)
            }
        case .r32Sint:
            imageFormat = .r32
            getPixel = { data in
                let p = data.assumingMemoryBound(to: Int32.self).pointee
                return (fixedToDouble(p), 0, 0, 1)
            }
        case .r32Float:
            imageFormat = .r32f
            getPixel = { data in
                let p = data.assumingMemoryBound(to: Float32.self).pointee
                return (Double(p), 0, 0, 1)
            }
        case .rg16Unorm, .rg16Uint:
            imageFormat = .rg16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (UInt16, UInt16).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), 0, 1)
            }
        case .rg16Snorm, .rg16Sint:
            imageFormat = .rg16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (Int16, Int16).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), 0, 1)
            }
        case .rg16Float:
            imageFormat = .rg16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (Float16, Float16).self).pointee
                return (Double(p.0), Double(p.1), 0, 1)
            }
        case .rgba8Unorm, .rgba8Unorm_srgb, .rgba8Uint:
            imageFormat = .rgba8
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (UInt8, UInt8, UInt8, UInt8).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), fixedToDouble(p.2), fixedToDouble(p.3))
            }
        case .rgba8Snorm, .rgba8Sint:
            imageFormat = .rgba8
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (Int8, Int8, Int8, Int8).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), fixedToDouble(p.2), fixedToDouble(p.3))
            }
        case .bgra8Unorm, .bgra8Unorm_srgb:
            imageFormat = .rgba8
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (UInt8, UInt8, UInt8, UInt8).self).pointee
                return (fixedToDouble(p.2), fixedToDouble(p.1), fixedToDouble(p.0), fixedToDouble(p.3))
            }
        case .rgb10a2Unorm, .rgb10a2Uint:
            imageFormat = .rgba16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: UInt32.self).pointee
                return (Double(p & 1023) / 1023.0,
                        Double((p >> 10) & 1023) / 1023.0,
                        Double((p >> 20) & 1023) / 1023.0,
                        Double((p >> 30) & 3) / 3.0)
            }
        case .rg11b10Float:
            imageFormat = .rgb16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: UInt32.self).pointee
                return (ufloatToDouble(eBits: 5, mBits: 6, value: p >> 21),
                        ufloatToDouble(eBits: 5, mBits: 6, value: p >> 10),
                        ufloatToDouble(eBits: 5, mBits: 5, value: p),
                        1.0)
            }
        case .rgb9e5Float:
            imageFormat = .rgb16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: UInt32.self).pointee
                let exp = p & 31
                return (ufloatToDouble(eBits: 5, mBits: 9, exponent: exp, mantissa: p >> 23),
                        ufloatToDouble(eBits: 5, mBits: 9, exponent: exp, mantissa: p >> 14),
                        ufloatToDouble(eBits: 5, mBits: 9, exponent: exp, mantissa: p >> 5),
                        1.0)
            }
        case .bgr10a2Unorm:
            imageFormat = .rgba16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: UInt32.self).pointee
                return (Double((p >> 20) & 1023) / 1023.0,
                        Double((p >> 10) & 1023) / 1023.0,
                        Double(p & 1023) / 1023.0,
                        Double((p >> 30) & 3) / 3.0)
            }
        case .rg32Uint:
            imageFormat = .rg32
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (UInt32, UInt32).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), 0.0, 1.0)
            }
        case .rg32Sint:
            imageFormat = .rg32
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (Int32, Int32).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), 0.0, 1.0)
            }
        case .rg32Float:
            imageFormat = .rg32f
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (Float32, Float32).self).pointee
                return (Double(p.0), Double(p.1), 0.0, 1.0)
            }
        case .rgba16Unorm, .rgba16Uint:
            imageFormat = .rgba16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (UInt16, UInt16, UInt16, UInt16).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), fixedToDouble(p.2), fixedToDouble(p.3))
            }
        case .rgba16Snorm, .rgba16Sint:
            imageFormat = .rgba16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (Int16, Int16, Int16, Int16).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), fixedToDouble(p.2), fixedToDouble(p.3))
            }
        case .rgba16Float:
            imageFormat = .rgba16
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (Float16, Float16, Float16, Float16).self).pointee
                return (Double(p.0), Double(p.1), Double(p.2), Double(p.3))
            }
        case .rgba32Uint:
            imageFormat = .rgba32
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (UInt32, UInt32, UInt32, UInt32).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), fixedToDouble(p.2), fixedToDouble(p.3))
            }
        case .rgba32Sint:
            imageFormat = .rgba32
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (Int32, Int32, Int32, Int32).self).pointee
                return (fixedToDouble(p.0), fixedToDouble(p.1), fixedToDouble(p.2), fixedToDouble(p.3))
            }
        case .rgba32Float:
            imageFormat = .rgba32f
            getPixel = { data in
                let p = data.assumingMemoryBound(to: (Float32, Float32, Float32, Float32).self).pointee
                return (Double(p.0), Double(p.1), Double(p.2), Double(p.3))
            }
        default:
            break
        }

        guard let getPixel else {
            Log.error("Unsupported texture format: \(pixelFormat)")
            return nil
        }
        assert(imageFormat != .invalid)

        let bpp = pixelFormat.bytesPerPixel
        let bufferLength = width * height * bpp

        if buffer.length >= bufferLength {
            if var ptr = buffer.contents() {
                var image = Image(width: width, height: height, pixelFormat: imageFormat)
                for y in 0..<height {
                    for x in 0..<width {
                        let c = getPixel(ptr)
                        ptr = ptr + bpp
                        image.writePixel(x: x, y: y, value: (c.r, c.g, c.b, c.a))
                    }
                }
                return image
            } else {
                Log.error("buffer is not accessible!")
            }
        }
        return nil
    }
}
