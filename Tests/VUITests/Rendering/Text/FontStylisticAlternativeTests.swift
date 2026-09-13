import Foundation
import XCTest
import VVD
@testable import VUI

final class FontStylisticAlternativeTests: XCTestCase {
    // ASSERTIONS fontStylisticAlternativeValuesAndProviderObserved
    func testValuesCodingAndProviderIdentity() throws {
        let base = VUI.Font.system(size: 40)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for raw in 1...20 {
            let value = try XCTUnwrap(VUI.Font._StylisticAlternative(rawValue: raw))
            let font = base._stylisticAlternative(value)
            let box = try XCTUnwrap(font.provider as? FontBox<VUI.Font.ModifierProvider<VUI.Font.StylisticAlternativeModifier>>)
            XCTAssertTrue(box.base.base.provider === base.provider)
            XCTAssertEqual(box.base.modifier.alternative.rawValue, raw)
            XCTAssertNotEqual(font, base)
            XCTAssertNotEqual(font, font._stylisticAlternative(value))
            XCTAssertEqual(font, base._stylisticAlternative(value))
            XCTAssertEqual(font.hashValue, base._stylisticAlternative(value).hashValue)
            let data = try encoder.encode(font.codingProxy)
            let expected = "{\"tag\":{\"modifier\":{\"_0\":\"_stylisticAlternative\"}},\"value\":{\"font\":{\"tag\":{\"system\":{}},\"value\":{\"design\":{},\"size\":40,\"weight\":{}}},\"modifier\":\(raw)}}"
            XCTAssertEqual(String(decoding: data, as: UTF8.self), expected)
            XCTAssertEqual(try JSONDecoder().decode(VUI.Font.CodingProxy.self, from: data).base, font)
        }
        for raw in [Int.min, -1, 0, 21, Int.max] {
            XCTAssertNil(VUI.Font._StylisticAlternative(rawValue: raw))
            XCTAssertThrowsError(try JSONDecoder().decode(RawRepresentableProxy<VUI.Font._StylisticAlternative>.self,
                from: Data(String(raw).utf8)))
        }
    }

    // ASSERTIONS fontStylisticAlternativeFeatureCompositionObserved
    func testDescriptorFeaturesAndRedactionKeepSeparateOwners() {
        let original = FontDescriptor(source: .named("Roboto-Regular", nil), pointSize: 40)
        var context = EnvironmentValues().fontResolutionContext
        for raw in 1...20 {
            let modifier = VUI.Font.StylisticAlternativeModifier(alternative: .init(rawValue: raw)!)
            var descriptor = original
            modifier.modify(descriptor: &descriptor, in: context)
            let tag = String(format: "ss%02d", raw).utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            XCTAssertEqual(descriptor.shapingFeatures, [TypefaceShapingFeature(tag: tag)])
            XCTAssertTrue(original.shapingFeatures.isEmpty)
            XCTAssertFalse(descriptor === original)
            var traits = VUI.Font.ResolvedTraits(pointSize: 17.125, weight: 0.23)
            modifier.modify(traits: &traits)
            XCTAssertEqual(traits.pointSize, 17.125)
            XCTAssertEqual(traits.weight, 0.23)
            XCTAssertNil(traits.width)
        }
        context.shouldRedactContent = true
        var descriptor = original.adding(features: [TypefaceShapingFeature(tag: 0x746e_756d)])
        let retained = descriptor
        VUI.Font.StylisticAlternativeModifier(alternative: .one).modify(descriptor: &descriptor, in: context)
        XCTAssertTrue(descriptor === retained)
        XCTAssertEqual(descriptor.shapingFeatures, retained.shapingFeatures)
    }

    // ASSERTIONS textStylisticAlternativeCarrierObserved
    func testTextRetainsTypedModifiersAndOrderedStyleEntries() throws {
        let first = Text(verbatim: "AB")._stylisticAlternative(.one)
        XCTAssertEqual(first, Text(verbatim: "AB")._stylisticAlternative(.one))
        XCTAssertNotEqual(first, Text(verbatim: "AB")._stylisticAlternative(.two))
        let text = first._stylisticAlternative(.two)._stylisticAlternative(.one)
        var style = Text.Style()
        for modifier in text.modifiers.reversed() { modifier.modify(style: &style) }
        let modifiers = try style.fontModifiers.map {
            try XCTUnwrap($0 as? AnyDynamicFontModifier<VUI.Font.StylisticAlternativeModifier>)
        }
        XCTAssertEqual(modifiers.map(\.modifier.alternative.rawValue), [1, 2, 1])
        XCTAssertFalse(modifiers[0] === modifiers[2])
        XCTAssertEqual(modifiers[0], modifiers[2])
    }

    // ASSERTIONS fontStylisticAlternativeFeatureCompositionObserved
    func testResolvedCopiesRetainFeaturesWithoutChangingTheOriginalResource() {
        let environment = EnvironmentValues()
        let base = VUI.Font.custom("Roboto-Regular", fixedSize: 40)
        let original = base.platformFont(in: environment.fontResolutionContext)
        let font = base._stylisticAlternative(.one)
        let first = font.platformFont(in: environment.fontResolutionContext)
        XCTAssertTrue(first === font.platformFont(in: environment.fontResolutionContext))
        XCTAssertTrue(original.shapingFeatures.isEmpty)
        for copy in [font, font.resolved(in: environment), font.resolved(in: environment).resolved(in: environment)] {
            XCTAssertEqual(copy.resolveDescriptor(in: environment.fontResolutionContext).shapingFeatures,
                [TypefaceShapingFeature(tag: 0x7373_3031)])
        }
        XCTAssertNotEqual(first, original)
        XCTAssertEqual(first.pointSize, original.pointSize)
        XCTAssertEqual(first.selectedWeight, original.selectedWeight)
    }

    // ASSERTIONS fontStylisticAlternativeGlyphConsumerObserved
    // ASSERTIONS fontStylisticAlternativeFeatureCompositionObserved
    // ASSERTIONS textStylisticAlternativeCarrierObserved
    func testAllSetsAndCombinationsReachFileAndDataTextInBothRenderingModes() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let previous = appContext
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
        defer { appContext = previous }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sample = "AB"
        let sequences = (1...20).map { [$0] } + [[1, 1], [1, 2], [2, 1], [1, 20], [20, 1], [1, 2, 1]]
        for enabled in [true, false] {
            let data = try StylisticFontFixture.make(enabled: enabled)
            let url = folder.appendingPathComponent("\(enabled).ttf")
            try data.write(to: url)
            for mode: VUI.Font.DefaultRenderingMode in [.bitmap(), .vector()] {
                var environment = EnvironmentValues()
                environment.defaultFontRenderingMode = mode
                let context = GraphTextResolutionContext(environment: environment, sceneResources: SceneResources())
                for base: VUI.Font in [.file(url, size: 40), .data(data, size: 40)] {
                    for sequence in sequences {
                        let font = sequence.reduce(base) { $0._stylisticAlternative(.init(rawValue: $1)!) }
                        let text = sequence.reduce(Text(verbatim: sample).font(base)) { $0._stylisticAlternative(.init(rawValue: $1)!) }
                        let first = sequence.min()!
                        let letter = Character(UnicodeScalar(65 + (first == 1 && sequence.contains(2) ? 2 : first))!)
                        let expected = enabled ? String(letter) + (sequence.contains(2) ? "C" : "B") : sample
                        let reference = try XCTUnwrap(Text(verbatim: expected).font(base)._resolve(context: context,
                            referenceDate: Date(timeIntervalSince1970: 0)))
                        let glyphs = reference.makeGlyphs().flatMap(\.glyphs)
                        for input in [Text(verbatim: sample).font(font), text] {
                            let resolved = try XCTUnwrap(input._resolve(context: context, referenceDate: Date(timeIntervalSince1970: 0)))
                            let actual = resolved.makeGlyphs().flatMap(\.glyphs)
                            XCTAssertEqual(actual.map(\.glyphIndex), glyphs.map(\.glyphIndex), "\(enabled) \(sequence)")
                            XCTAssertEqual(actual.map(\.advance), glyphs.map(\.advance))
                            XCTAssertEqual(actual.map(\.sourceRange), [0..<1, 1..<2])
                            XCTAssertEqual(resolved.measure(), reference.measure())
                        }
                    }
                }
            }
        }
    }

    // ASSERTIONS fontStylisticAlternativeGlyphConsumerObserved
    func testBundledFontSuppliesItsOwnSubstitutions() throws {
        let previous = appContext
        appContext = StyleTestAppContext()
        defer { appContext = previous }
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let context = GraphTextResolutionContext(environment: environment, sceneResources: SceneResources())
        for (raw, expected): (Int, UInt32) in [(1, 580), (2, 75), (6, 645), (7, 650), (20, 75)] {
            let font = VUI.Font.custom("Roboto-Regular", fixedSize: 40)._stylisticAlternative(.init(rawValue: raw)!)
            let resolved = try XCTUnwrap(Text(verbatim: "g").font(font)._resolve(context: context,
                referenceDate: Date(timeIntervalSince1970: 0)))
            XCTAssertEqual(resolved.makeGlyphs().flatMap(\.glyphs).map(\.glyphIndex), [expected])
        }
    }
}

/// Controlled substitutions exercise every stylistic-set tag without new font assets.
enum StylisticFontFixture {
    static func make(enabled: Bool) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let source = try Data(contentsOf: url)
        var tables: [String: Data] = [:]
        for index in 0..<Int(u16(source, 4)) {
            let record = 12 + 16 * index
            let tag = String(decoding: source[record..<record + 4], as: UTF8.self)
            let start = Int(u32(source, record + 8)), size = Int(u32(source, record + 12))
            tables[tag] = source.subdata(in: start..<start + size)
        }
        if enabled {
            let face = try XCTUnwrap(VVD.Font(data: source))
            let glyphs = try (65...85).map { UInt16(try XCTUnwrap(face.glyphMetrics(for: UnicodeScalar($0)!)).index) }
            XCTAssertEqual(Set(glyphs).count, 21)
            var lookups: [Data] = []
            for index in 0..<20 {
                let inputs: [UInt16] = index == 1 ? [glyphs[0], glyphs[1]] : [glyphs[0]]
                let outputs = [UInt16](repeating: glyphs[index + 1], count: inputs.count)
                let subtable = words([2, UInt16(6 + inputs.count * 2), UInt16(inputs.count)] + outputs + [1, UInt16(inputs.count)] + inputs)
                lookups.append(words([1, 0, 1, 8]) + subtable)
            }
            var offsets: [UInt16] = [], offset = 42
            for lookup in lookups { offsets.append(UInt16(offset)); offset += lookup.count }
            let lookupList = words([20] + offsets) + lookups.reduce(Data(), +)
            var features = words([20])
            for index in 0..<20 {
                features.append(contentsOf: String(format: "ss%02d", index + 1).utf8)
                features.append(words([UInt16(122 + index * 6)]))
            }
            for index in 0..<20 { features.append(words([0, 1, UInt16(index)])) }
            let script = words([4, 0, 0, 65535, 20] + (0..<20).map(UInt16.init))
            var scripts = words([2])
            scripts.append(contentsOf: "DFLT".utf8); scripts.append(words([14]))
            scripts.append(contentsOf: "latn".utf8); scripts.append(words([UInt16(14 + script.count)]))
            scripts.append(script); scripts.append(script)
            tables["GSUB"] = words([1, 0, 10, UInt16(10 + scripts.count), UInt16(10 + scripts.count + features.count)]) + scripts + features + lookupList
        } else {
            tables.removeValue(forKey: "GSUB")
        }
        write32(0, &tables["head"]!, 8)
        let count = tables.count
        var power = 1, selector = 0
        while power * 2 <= count { power *= 2; selector += 1 }
        var output = words([1, 0, UInt16(count), UInt16(power * 16), UInt16(selector), UInt16((count - power) * 16)])
        output.append(Data(repeating: 0, count: 16 * count))
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
    private static func u16(_ data: Data, _ offset: Int) -> UInt16 { UInt16(data[offset]) << 8 | UInt16(data[offset + 1]) }
    private static func u32(_ data: Data, _ offset: Int) -> UInt32 { UInt32(u16(data, offset)) << 16 | UInt32(u16(data, offset + 2)) }
    private static func write32(_ value: UInt32, _ data: inout Data, _ offset: Int) {
        data.replaceSubrange(offset..<offset + 4, with: words([UInt16(value >> 16), UInt16(value & 65535)]))
    }
    private static func checksum(_ source: Data) -> UInt32 {
        var data = source
        while !data.count.isMultiple(of: 4) { data.append(0) }
        return stride(from: 0, to: data.count, by: 4).reduce(0) { $0 &+ u32(data, $1) }
    }
}
