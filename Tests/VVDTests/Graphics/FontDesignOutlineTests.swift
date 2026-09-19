import Foundation
import XCTest
import VVD

final class FontDesignOutlineTests: XCTestCase {
    private struct Element: Decodable {
        var kind: Int
        var points: [CGFloat]
    }
    private struct Sample: Decodable {
        var size: CGFloat
        var character: UInt32
        var glyph: UInt32
        var unitsPerEM: Int
        var bounds: [CGFloat]
        var elements: [Element]
    }
    private func resource(_ name: String = "Roboto/Roboto-VariableFont_wdth,wght.ttf") -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Sources/VUI/Resources/Fonts").appendingPathComponent(name)
    }
    private func outline(_ font: Font, glyph: UInt32) -> [[CGFloat]]? {
        var result: [[CGFloat]] = []
        let supported = font.decomposeDesignGlyphOutline(at: glyph) { command in
            // Reentering a font read proves that callbacks run outside its lock.
            XCTAssertNotNil(font.designMetrics)
            switch command {
            case let .move(p): result.append([0, p.x, p.y])
            case let .line(p): result.append([1, p.x, p.y])
            case let .quadCurve(p, control): result.append([2, control.x, control.y, p.x, p.y])
            case let .curve(p, a, b): result.append([3, a.x, a.y, b.x, b.y, p.x, p.y])
            }
        }
        return supported ? result : nil
    }
    private func canonical(_ rows: [[CGFloat]]) -> [[CGFloat]] {
        var result: [[CGFloat]] = []
        var first: [CGFloat]?
        func close() {
            guard let start = first else { return }
            if result.last == [1] + start { result.removeLast() }
            result.append([4]); first = nil
        }
        for row in rows {
            if row[0] == 0 { close(); first = Array(row.dropFirst()) }
            if row[0] == 4 { close() } else { result.append(row) }
        }
        close()
        return result
    }

    func testFractionalBoundsAndAllOutlineCommandsAreIndependentOfRasterSize() throws {
        let samples = try JSONDecoder().decode([Sample].self, from: Data(Self.samples.utf8))
        let font = try XCTUnwrap(Font(path: resource().path))
        for sample in samples {
            let scalar = try XCTUnwrap(UnicodeScalar(sample.character))
            for dpi: Font.DPI in [(72, 72), (144, 96)] {
                font.setPointSize(sample.size, dpi: dpi)
                let before = try XCTUnwrap(font.glyphMetrics(for: scalar))
                XCTAssertEqual(before.index, sample.glyph)
                let bounds = try XCTUnwrap(font.designGlyphBounds(at: sample.glyph))
                let commands = try XCTUnwrap(outline(font, glyph: sample.glyph))
                let scale = sample.size / CGFloat(sample.unitsPerEM)
                for (a, b) in zip([bounds.minX, bounds.minY, bounds.width, bounds.height], sample.bounds) {
                    XCTAssertEqual(a * scale, b, accuracy: 1e-10)
                }
                let actual = canonical(commands.map { [$0[0]] + $0.dropFirst().map { $0 * scale } })
                let expected = canonical(sample.elements.map { [CGFloat($0.kind)] + $0.points })
                XCTAssertEqual(actual.count, expected.count)
                for (a, b) in zip(actual, expected) {
                    XCTAssertEqual(a.count, b.count)
                    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 1e-10) }
                }
                let after = try XCTUnwrap(font.glyphMetrics(for: scalar))
                XCTAssertEqual(after.advance, before.advance)
                XCTAssertEqual(after.bearing, before.bearing)
                XCTAssertEqual(after.size, before.size)
                XCTAssertEqual(font.pointSize, sample.size)
                XCTAssertEqual(font.dpi.x, dpi.x); XCTAssertEqual(font.dpi.y, dpi.y)
            }
        }
    }

    func testSelectedVariationsAndNamedInstancesRetainTheirOutlineOwner() throws {
        let file = resource()
        let font = try XCTUnwrap(Font(path: file.path))
        let original = try XCTUnwrap(outline(font, glyph: 37))
        for weight: CGFloat in [650, 900, 400, 100, 650] {
            let coordinates: [UInt32: CGFloat] = [0x7767_6874: weight]
            let fresh = try XCTUnwrap(Font(data: Data(contentsOf: file)))
            XCTAssertTrue(font.setVariationCoordinates(coordinates))
            XCTAssertTrue(fresh.setVariationCoordinates(coordinates))
            XCTAssertEqual(outline(font, glyph: 37), outline(fresh, glyph: 37))
            XCTAssertEqual(font.designGlyphBounds(at: 37), fresh.designGlyphBounds(at: 37))
            if weight == 400 { XCTAssertEqual(outline(font, glyph: 37), original) }
            else { XCTAssertNotEqual(outline(font, glyph: 37), original) }
        }
        XCTAssertTrue(font.setVariationCoordinates([:]))
        XCTAssertEqual(outline(font, glyph: 37), original)
        let metadata = try XCTUnwrap(Font.metadata(path: file.path))
        let weightAxis = try XCTUnwrap(metadata.variationAxes.firstIndex { $0.tag == 0x7767_6874 })
        let instance = try XCTUnwrap(metadata.variationInstances.first { $0.coordinates[weightAxis] == 700 })
        let named = try XCTUnwrap(Font(path: file.path, faceIndex: instance.index << 16))
        let coordinates = Dictionary(uniqueKeysWithValues: zip(metadata.variationAxes.map(\.tag), instance.coordinates))
        XCTAssertTrue(font.setVariationCoordinates(coordinates))
        XCTAssertEqual(outline(named, glyph: 38), outline(font, glyph: 38))
        XCTAssertEqual(named.designGlyphBounds(at: 38), font.designGlyphBounds(at: 38))
    }

    func testEmptyUnsupportedAndReleasedInputStorageRemainDistinct() throws {
        var data = try Data(contentsOf: resource())
        let font = try XCTUnwrap(Font(data: data))
        data.resetBytes(in: data.startIndex..<data.endIndex)
        XCTAssertEqual(outline(font, glyph: 4), [])
        XCTAssertEqual(font.designGlyphBounds(at: 4), .zero)
        XCTAssertNotNil(outline(font, glyph: 37))
        XCTAssertNil(outline(font, glyph: .max))
        XCTAssertNil(font.designGlyphBounds(at: .max))
        let bitmap = try XCTUnwrap(Font(path: resource("NotoColorEmoji/NotoColorEmoji.ttf").path))
        XCTAssertNil(outline(bitmap, glyph: 0))
        XCTAssertNil(bitmap.designGlyphBounds(at: 0))
    }

    private static let samples = #"""
    [
    {"bounds":[0.191162109375,0,8.444091796875,9.59765625],"character":65,"elements":[{"kind":0,"points":[4.6669921875,8.747314453125]},{"kind":1,"points":[1.48974609375,0]},{"kind":1,"points":[0.191162109375,0]},{"kind":1,"points":[3.849609375,9.59765625]},{"kind":1,"points":[4.686767578125,9.59765625]},{"kind":4,"points":[]},{"kind":0,"points":[7.330078125,0]},{"kind":1,"points":[4.146240234375,8.747314453125]},{"kind":1,"points":[4.12646484375,9.59765625]},{"kind":1,"points":[4.963623046875,9.59765625]},{"kind":1,"points":[8.63525390625,0]},{"kind":4,"points":[]},{"kind":0,"points":[7.165283203125,3.552978515625]},{"kind":1,"points":[7.165283203125,2.511474609375]},{"kind":1,"points":[1.773193359375,2.511474609375]},{"kind":1,"points":[1.773193359375,3.552978515625]},{"kind":4,"points":[]}],"glyph":37,"hasPath":true,"size":13.5,"unitsPerEM":2048},
    {"bounds":[1.114013671875,0,6.532470703125,9.59765625],"character":66,"elements":[{"kind":0,"points":[4.53515625,4.489013671875]},{"kind":1,"points":[2.102783203125,4.489013671875]},{"kind":1,"points":[2.089599609375,5.5107421875]},{"kind":1,"points":[4.2978515625,5.5107421875]},{"kind":2,"points":[4.844970703125,5.5107421875,5.253662109375,5.6953125]},{"kind":2,"points":[5.662353515625,5.8798828125,5.8897705078125,6.2259521484375]},{"kind":2,"points":[6.1171875,6.572021484375,6.1171875,7.05322265625]},{"kind":2,"points":[6.1171875,7.58056640625,5.9161376953125,7.9134521484375]},{"kind":2,"points":[5.715087890625,8.246337890625,5.3031005859375,8.4012451171875]},{"kind":2,"points":[4.89111328125,8.55615234375,4.25830078125,8.55615234375]},{"kind":1,"points":[2.38623046875,8.55615234375]},{"kind":1,"points":[2.38623046875,0]},{"kind":1,"points":[1.114013671875,0]},{"kind":1,"points":[1.114013671875,9.59765625]},{"kind":1,"points":[4.25830078125,9.59765625]},{"kind":2,"points":[4.99658203125,9.59765625,5.57666015625,9.4493408203125]},{"kind":2,"points":[6.15673828125,9.301025390625,6.5621337890625,8.9879150390625]},{"kind":2,"points":[6.967529296875,8.6748046875,7.178466796875,8.193603515625]},{"kind":2,"points":[7.389404296875,7.71240234375,7.389404296875,7.0400390625]},{"kind":2,"points":[7.389404296875,6.44677734375,7.086181640625,5.9688720703125]},{"kind":2,"points":[6.782958984375,5.490966796875,6.2457275390625,5.187744140625]},{"kind":2,"points":[5.70849609375,4.884521484375,4.989990234375,4.798828125]},{"kind":4,"points":[]},{"kind":0,"points":[4.475830078125,0]},{"kind":1,"points":[1.601806640625,0]},{"kind":1,"points":[2.3203125,1.034912109375]},{"kind":1,"points":[4.475830078125,1.034912109375]},{"kind":2,"points":[5.082275390625,1.034912109375,5.5074462890625,1.245849609375]},{"kind":2,"points":[5.9326171875,1.456787109375,6.15673828125,1.8424072265625]},{"kind":2,"points":[6.380859375,2.22802734375,6.380859375,2.75537109375]},{"kind":2,"points":[6.380859375,3.289306640625,6.189697265625,3.67822265625]},{"kind":2,"points":[5.99853515625,4.067138671875,5.58984375,4.278076171875]},{"kind":2,"points":[5.18115234375,4.489013671875,4.53515625,4.489013671875]},{"kind":1,"points":[2.722412109375,4.489013671875]},{"kind":1,"points":[2.735595703125,5.5107421875]},{"kind":1,"points":[5.214111328125,5.5107421875]},{"kind":1,"points":[5.484375,5.1416015625]},{"kind":2,"points":[6.176513671875,5.082275390625,6.65771484375,4.7493896484375]},{"kind":2,"points":[7.138916015625,4.41650390625,7.3927001953125,3.90234375]},{"kind":2,"points":[7.646484375,3.38818359375,7.646484375,2.7685546875]},{"kind":2,"points":[7.646484375,1.8720703125,7.2542724609375,1.2557373046875]},{"kind":2,"points":[6.862060546875,0.639404296875,6.150146484375,0.3197021484375]},{"kind":2,"points":[5.438232421875,0,4.475830078125,0]},{"kind":4,"points":[]}],"glyph":38,"hasPath":true,"size":13.5,"unitsPerEM":2048},
    {"bounds":[0,0,0,0],"character":32,"elements":[],"glyph":4,"hasPath":false,"size":13.5,"unitsPerEM":2048},
    {"bounds":[0.32568359375,0,14.38623046875,16.3515625],"character":65,"elements":[{"kind":0,"points":[7.951171875,14.90283203125]},{"kind":1,"points":[2.5380859375,0]},{"kind":1,"points":[0.32568359375,0]},{"kind":1,"points":[6.55859375,16.3515625]},{"kind":1,"points":[7.98486328125,16.3515625]},{"kind":4,"points":[]},{"kind":0,"points":[12.48828125,0]},{"kind":1,"points":[7.06396484375,14.90283203125]},{"kind":1,"points":[7.0302734375,16.3515625]},{"kind":1,"points":[8.45654296875,16.3515625]},{"kind":1,"points":[14.7119140625,0]},{"kind":4,"points":[]},{"kind":0,"points":[12.20751953125,6.05322265625]},{"kind":1,"points":[12.20751953125,4.27880859375]},{"kind":1,"points":[3.02099609375,4.27880859375]},{"kind":1,"points":[3.02099609375,6.05322265625]},{"kind":4,"points":[]}],"glyph":37,"hasPath":true,"size":23,"unitsPerEM":2048},
    {"bounds":[1.89794921875,0,11.12939453125,16.3515625],"character":66,"elements":[{"kind":0,"points":[7.7265625,7.64794921875]},{"kind":1,"points":[3.58251953125,7.64794921875]},{"kind":1,"points":[3.56005859375,9.388671875]},{"kind":1,"points":[7.322265625,9.388671875]},{"kind":2,"points":[8.25439453125,9.388671875,8.95068359375,9.703125]},{"kind":2,"points":[9.64697265625,10.017578125,10.034423828125,10.607177734375]},{"kind":2,"points":[10.421875,11.19677734375,10.421875,12.0166015625]},{"kind":2,"points":[10.421875,12.9150390625,10.079345703125,13.482177734375]},{"kind":2,"points":[9.73681640625,14.04931640625,9.034912109375,14.313232421875]},{"kind":2,"points":[8.3330078125,14.5771484375,7.2548828125,14.5771484375]},{"kind":1,"points":[4.0654296875,14.5771484375]},{"kind":1,"points":[4.0654296875,0]},{"kind":1,"points":[1.89794921875,0]},{"kind":1,"points":[1.89794921875,16.3515625]},{"kind":1,"points":[7.2548828125,16.3515625]},{"kind":2,"points":[8.5126953125,16.3515625,9.5009765625,16.098876953125]},{"kind":2,"points":[10.4892578125,15.84619140625,11.179931640625,15.312744140625]},{"kind":2,"points":[11.87060546875,14.779296875,12.22998046875,13.95947265625]},{"kind":2,"points":[12.58935546875,13.1396484375,12.58935546875,11.994140625]},{"kind":2,"points":[12.58935546875,10.9833984375,12.07275390625,10.169189453125]},{"kind":2,"points":[11.55615234375,9.35498046875,10.640869140625,8.83837890625]},{"kind":2,"points":[9.7255859375,8.32177734375,8.50146484375,8.17578125]},{"kind":4,"points":[]},{"kind":0,"points":[7.62548828125,0]},{"kind":1,"points":[2.72900390625,0]},{"kind":1,"points":[3.953125,1.76318359375]},{"kind":1,"points":[7.62548828125,1.76318359375]},{"kind":2,"points":[8.65869140625,1.76318359375,9.383056640625,2.12255859375]},{"kind":2,"points":[10.107421875,2.48193359375,10.4892578125,3.138916015625]},{"kind":2,"points":[10.87109375,3.7958984375,10.87109375,4.6943359375]},{"kind":2,"points":[10.87109375,5.60400390625,10.54541015625,6.2666015625]},{"kind":2,"points":[10.2197265625,6.92919921875,9.5234375,7.28857421875]},{"kind":2,"points":[8.8271484375,7.64794921875,7.7265625,7.64794921875]},{"kind":1,"points":[4.63818359375,7.64794921875]},{"kind":1,"points":[4.66064453125,9.388671875]},{"kind":1,"points":[8.88330078125,9.388671875]},{"kind":1,"points":[9.34375,8.759765625]},{"kind":2,"points":[10.52294921875,8.65869140625,11.3427734375,8.091552734375]},{"kind":2,"points":[12.16259765625,7.5244140625,12.594970703125,6.6484375]},{"kind":2,"points":[13.02734375,5.7724609375,13.02734375,4.716796875]},{"kind":2,"points":[13.02734375,3.189453125,12.359130859375,2.139404296875]},{"kind":2,"points":[11.69091796875,1.08935546875,10.47802734375,0.544677734375]},{"kind":2,"points":[9.26513671875,0,7.62548828125,0]},{"kind":4,"points":[]}],"glyph":38,"hasPath":true,"size":23,"unitsPerEM":2048},
    {"bounds":[0,0,0,0],"character":32,"elements":[],"glyph":4,"hasPath":false,"size":23,"unitsPerEM":2048},
    {"bounds":[0.43896484375,0,19.39013671875,22.0390625],"character":65,"elements":[{"kind":0,"points":[10.716796875,20.08642578125]},{"kind":1,"points":[3.4208984375,0]},{"kind":1,"points":[0.43896484375,0]},{"kind":1,"points":[8.83984375,22.0390625]},{"kind":1,"points":[10.76220703125,22.0390625]},{"kind":4,"points":[]},{"kind":0,"points":[16.83203125,0]},{"kind":1,"points":[9.52099609375,20.08642578125]},{"kind":1,"points":[9.4755859375,22.0390625]},{"kind":1,"points":[11.39794921875,22.0390625]},{"kind":1,"points":[19.8291015625,0]},{"kind":4,"points":[]},{"kind":0,"points":[16.45361328125,8.15869140625]},{"kind":1,"points":[16.45361328125,5.76708984375]},{"kind":1,"points":[4.07177734375,5.76708984375]},{"kind":1,"points":[4.07177734375,8.15869140625]},{"kind":4,"points":[]}],"glyph":37,"hasPath":true,"size":31,"unitsPerEM":2048},
    {"bounds":[2.55810546875,0,15.00048828125,22.0390625],"character":66,"elements":[{"kind":0,"points":[10.4140625,10.30810546875]},{"kind":1,"points":[4.82861328125,10.30810546875]},{"kind":1,"points":[4.79833984375,12.654296875]},{"kind":1,"points":[9.869140625,12.654296875]},{"kind":2,"points":[11.12548828125,12.654296875,12.06396484375,13.078125]},{"kind":2,"points":[13.00244140625,13.501953125,13.524658203125,14.296630859375]},{"kind":2,"points":[14.046875,15.09130859375,14.046875,16.1962890625]},{"kind":2,"points":[14.046875,17.4072265625,13.585205078125,18.171630859375]},{"kind":2,"points":[13.12353515625,18.93603515625,12.177490234375,19.291748046875]},{"kind":2,"points":[11.2314453125,19.6474609375,9.7783203125,19.6474609375]},{"kind":1,"points":[5.4794921875,19.6474609375]},{"kind":1,"points":[5.4794921875,0]},{"kind":1,"points":[2.55810546875,0]},{"kind":1,"points":[2.55810546875,22.0390625]},{"kind":1,"points":[9.7783203125,22.0390625]},{"kind":2,"points":[11.4736328125,22.0390625,12.8056640625,21.698486328125]},{"kind":2,"points":[14.1376953125,21.35791015625,15.068603515625,20.638916015625]},{"kind":2,"points":[15.99951171875,19.919921875,16.48388671875,18.81494140625]},{"kind":2,"points":[16.96826171875,17.7099609375,16.96826171875,16.166015625]},{"kind":2,"points":[16.96826171875,14.8037109375,16.27197265625,13.706298828125]},{"kind":2,"points":[15.57568359375,12.60888671875,14.342041015625,11.91259765625]},{"kind":2,"points":[13.1083984375,11.21630859375,11.45849609375,11.01953125]},{"kind":4,"points":[]},{"kind":0,"points":[10.27783203125,0]},{"kind":1,"points":[3.67822265625,0]},{"kind":1,"points":[5.328125,2.37646484375]},{"kind":1,"points":[10.27783203125,2.37646484375]},{"kind":2,"points":[11.67041015625,2.37646484375,12.646728515625,2.86083984375]},{"kind":2,"points":[13.623046875,3.34521484375,14.1376953125,4.230712890625]},{"kind":2,"points":[14.65234375,5.1162109375,14.65234375,6.3271484375]},{"kind":2,"points":[14.65234375,7.55322265625,14.21337890625,8.4462890625]},{"kind":2,"points":[13.7744140625,9.33935546875,12.8359375,9.82373046875]},{"kind":2,"points":[11.8974609375,10.30810546875,10.4140625,10.30810546875]},{"kind":1,"points":[6.25146484375,10.30810546875]},{"kind":1,"points":[6.28173828125,12.654296875]},{"kind":1,"points":[11.97314453125,12.654296875]},{"kind":1,"points":[12.59375,11.806640625]},{"kind":2,"points":[14.18310546875,11.67041015625,15.2880859375,10.906005859375]},{"kind":2,"points":[16.39306640625,10.1416015625,16.975830078125,8.9609375]},{"kind":2,"points":[17.55859375,7.7802734375,17.55859375,6.357421875]},{"kind":2,"points":[17.55859375,4.298828125,16.657958984375,2.883544921875]},{"kind":2,"points":[15.75732421875,1.46826171875,14.12255859375,0.734130859375]},{"kind":2,"points":[12.48779296875,0,10.27783203125,0]},{"kind":4,"points":[]}],"glyph":38,"hasPath":true,"size":31,"unitsPerEM":2048},
    {"bounds":[0,0,0,0],"character":32,"elements":[],"glyph":4,"hasPath":false,"size":31,"unitsPerEM":2048}
    ]
    """#
}
