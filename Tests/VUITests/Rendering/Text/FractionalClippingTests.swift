import Foundation
import XCTest
import VVD
@testable import VUI

final class FractionalClippingTests: XCTestCase {
    // ASSERTIONS fontClippingFractionalTextConsumerObserved
    // ASSERTIONS fontClippingFractionalInterpolationObserved
    // ASSERTIONS fontClippingCoordinateNormalizationObserved
    // ASSERTIONS textFontVerticalOutsets27Observed
    func testFileAndDataTextPreserveFractionalCeilingsInBothRenderingModes() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cases: [(FractionalClippingFixture.Kind, CGFloat, CGFloat, Double, Double)] = [
            (.single, 650, 1024 / 350.5, 2150.5, 674.5),
            (.multiple, 650, 2.6654860046407274, 2184.1700915564597, 657.4982706002035),
            (.mapped, 525, 2.8199855150878617, 2163.1172939979656, 668.1288911495423)
        ]
        for (kind, weightClass, boundary, ascent, descent) in cases {
            let data = try FractionalClippingFixture.make(kind)
            let url = folder.appendingPathComponent("\(kind).ttf")
            try data.write(to: url)
            let weight = VUI.Font.Weight(value: FontWeightScale.logicalWeight(forClass: weightClass))
            XCTAssertEqual(weight.weightClass, weightClass)
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                for size in [boundary - 0.00001, boundary, boundary + 0.00001] {
                    for font: VUI.Font in [.file(url, size: size, weight: weight), .data(data, size: size, weight: weight)] {
                        for scale: CGFloat in [1, 2, 3] {
                            var environment = EnvironmentValues()
                            environment.defaultFontRenderingMode = mode
                            environment.displayScale = scale
                            for string in ["Hg", "Hg\nHg"] {
                                let source = try XCTUnwrap(Text(verbatim: string).font(font)._resolve(context:
                                    GraphTextResolutionContext(environment: environment, sceneResources: SceneResources()),
                                    referenceDate: Date(timeIntervalSince1970: 0)))
                                let resolved = ResolvedTextSource(runs: source.runs, scaleFactor: 1,
                                    displayScale: scale, preferredLanguages: ["en"])
                                let metrics = try XCTUnwrap(resolved.maximumFontMetrics)
                                let styled = ResolvedStyledText.TextLayoutManager(resolvedText: resolved)
                                let top = CGFloat(ascent) * size / 2048 - metrics.ascender
                                let bottom = CGFloat(descent) * size / 2048 + metrics.descender
                                guard case let .styledText(faces, _, _, attributes) = resolved.runs[0] else {
                                    XCTFail("Missing resolved font run"); continue
                                }
                                let raw = try XCTUnwrap(attributes.fontResource?.resolvedMetrics(
                                    for: faces[0], scaleFactor: resolved.scaleFactor))
                                XCTAssertEqual(raw.outsets.top, top)
                                XCTAssertEqual(raw.outsets.bottom, bottom, accuracy: 1e-14)
                                let verticalBottom = max(bottom, (kind == .mapped ? 0.282064 : 0.286064) * size)
                                XCTAssertEqual(metrics.outsets.top, top)
                                XCTAssertEqual(metrics.outsets.bottom, verticalBottom, accuracy: 1e-14)
                                XCTAssertEqual(styled.drawingMargins.top, ceil(top * scale) / scale)
                                XCTAssertEqual(styled.drawingMargins.bottom, ceil(verticalBottom * scale) / scale)
                                XCTAssertEqual(styled.drawingMargins.leading, 0)
                                XCTAssertEqual(styled.drawingMargins.trailing, 0)
                                if size == boundary, scale == 2 {
                                    XCTAssertEqual(styled.drawingMargins.top, kind == .multiple ? 1 : 0.5)
                                }
                                let size = resolved.measure()
                                let item = DisplayList.Content.TextValue(
                                    view: StyledTextContentView(text: styled, renderer: nil), size: size,
                                    frame: styled.frame(in: size, renderer: nil), shading: .color(.black),
                                    transform: .identity, command: .closure(bounds: nil))
                                XCTAssertEqual(item.frame.minY, -styled.drawingMargins.top)
                                let drawing = try XCTUnwrap(item.makeDrawing())
                                // Preparation must retain the expanded frame's positive compensation.
                                XCTAssertEqual(drawing.origin.y, styled.drawingMargins.top)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A real variable font with independent clipping changes and unchanged natural metrics.
enum FractionalClippingFixture {
    enum Kind { case single, multiple, mapped }

    static func make(_ kind: Kind) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let source = try Data(contentsOf: url)
        var tables: [String: Data] = [:]
        for index in 0..<Int(read16(source, 4)) {
            let record = 12 + index * 16
            let tag = String(decoding: source[record..<record + 4], as: UTF8.self)
            let start = Int(read32(source, record + 8)), count = Int(read32(source, record + 12))
            tables[tag] = source.subdata(in: start..<start + count)
        }
        for (index, value): (Int, Int16) in [(0, 1800), (1, -400), (2, -100)] {
            write16(UInt16(bitPattern: value), &tables["hhea"]!, 4 + index * 2)
        }
        write16(read16(tables["OS/2"]!, 62) & ~UInt16(128), &tables["OS/2"]!, 62)
        write16(2100, &tables["OS/2"]!, 74)
        write16(700, &tables["OS/2"]!, 76)
        var mvar = words([1, 0, 0, 8, 2, 28])
        for (index, tag) in ["hcla", "hcld"].enumerated() {
            mvar.append(contentsOf: tag.utf8); mvar.append(words([0, UInt16(index)]))
        }
        if kind == .single {
            mvar.append(words([1, 0, 12, 1, 0, 28, 2, 1, 0, 16384, 16384, 0, 0, 0,
                               2, 1, 1, 0, 101, UInt16(bitPattern: -51)]))
        } else {
            mvar.append(words([1, 0, 12, 1, 0, 52, 2, 3]))
            mvar.append(signedWords([0, 9830, 16384, 0, 0, 0,
                                    0, 16384, 16384, -16384, -11469, 0,
                                    -16384, -8192, 0, 0, 0, 0]))
            mvar.append(words([2, 3, 3, 0, 1, 2]))
            mvar.append(signedWords([101, -67, 41, -51, 89, -21]))
        }
        tables["MVAR"] = mvar
        tables.removeValue(forKey: "avar")
        if kind == .mapped {
            tables["avar"] = words([1, 0, 0, 2, 4]) + signedWords([-16384, -16384, 0, 0, 6554, 9830, 16384, 16384]) +
                words([4]) + signedWords([-16384, -16384, -8192, -12288, 0, 0, 16384, 16384])
        }
        write32(0, &tables["head"]!, 8)
        let count = tables.count
        var power = 1, selector = 0
        while power * 2 <= count { power *= 2; selector += 1 }
        var output = words([1, 0, UInt16(count), UInt16(power * 16), UInt16(selector), UInt16((count - power) * 16)])
        output.append(Data(repeating: 0, count: count * 16))
        var head = 0
        for (index, tag) in tables.keys.sorted().enumerated() {
            let data = tables[tag]!, record = 12 + index * 16
            output.replaceSubrange(record..<record + 4, with: tag.utf8)
            write32(checksum(data), &output, record + 4)
            write32(UInt32(output.count), &output, record + 8)
            write32(UInt32(data.count), &output, record + 12)
            if tag == "head" { head = output.count }
            output.append(data)
            while !output.count.isMultiple(of: 4) { output.append(0) }
        }
        write32(0xb1b0afba &- checksum(output), &output, head + 8)
        return output
    }

    private static func words(_ values: [UInt16]) -> Data { Data(values.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] }) }
    private static func signedWords(_ values: [Int16]) -> Data { words(values.map(UInt16.init(bitPattern:))) }
    private static func read16(_ data: Data, _ offset: Int) -> UInt16 { UInt16(data[offset]) << 8 | UInt16(data[offset + 1]) }
    private static func read32(_ data: Data, _ offset: Int) -> UInt32 { UInt32(read16(data, offset)) << 16 | UInt32(read16(data, offset + 2)) }
    private static func write16(_ value: UInt16, _ data: inout Data, _ offset: Int) { data.replaceSubrange(offset..<offset + 2, with: words([value])) }
    private static func write32(_ value: UInt32, _ data: inout Data, _ offset: Int) {
        data.replaceSubrange(offset..<offset + 4, with: words([UInt16(value >> 16), UInt16(value & 65535)]))
    }
    private static func checksum(_ data: Data) -> UInt32 {
        var padded = data
        while !padded.count.isMultiple(of: 4) { padded.append(0) }
        return stride(from: 0, to: padded.count, by: 4).reduce(0) { $0 &+ read32(padded, $1) }
    }
}
