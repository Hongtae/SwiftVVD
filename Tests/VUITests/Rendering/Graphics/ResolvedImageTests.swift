import XCTest
import VVD
@testable import VUI

final class ResolvedImageTests: XCTestCase {
    private func graphics() -> GraphicsImage {
        GraphicsImage(contents: nil, scale: 2, unrotatedPixelSize: CGSize(width: 8, height: 4))
    }

    private func metrics() -> VUI.Image.LayoutMetrics {
        VUI.Image.LayoutMetrics(baselineOffset: 3, capHeight: 11,
            contentSize: CGSize(width: 21, height: 15), alignmentOrigin: CGPoint(x: -2, y: 4))
    }

    func testLayoutMetricsKeepContentSizeSeparateFromImageFrame() {
        var image = VUI.Image.Resolved(image: graphics(), decorative: true)
        XCTAssertEqual(image.contentSize, CGSize(width: 4, height: 2))
        XCTAssertEqual(image.baselineOffset, 0)
        XCTAssertEqual(image.capHeight, 2)
        XCTAssertEqual(image.alignmentOrigin, .zero)
        image.layoutMetrics = metrics()
        XCTAssertEqual(image.layoutMetrics?.backgroundSize, .zero)
        XCTAssertEqual(image.size, CGSize(width: 4, height: 2))
        XCTAssertEqual(image.sizeThatFits(in: .zero), CGSize(width: 21, height: 15))
        XCTAssertEqual(image.frame(in: CGSize(width: 31, height: 19)),
                       CGRect(x: -2, y: 4, width: 4, height: 2))
        XCTAssertEqual(image.baselineOffset, 3)
        XCTAssertEqual(image.capHeight, 11)
        XCTAssertEqual(Mirror(reflecting: image).children.compactMap(\.label),
            ["image", "label", "_basePlatformItemImage", "_layoutMetrics", "decorative",
             "backgroundShape", "backgroundCornerRadius", "styleResolverMode"])
        // ASSERTIONS imageResolvedLayoutMetricsObserved
        // ASSERTIONS imageResolvedStorageOwnershipObserved
    }

    func testResizableProposalsClampOnlySpecifiedAxesToCapInsetSums() {
        for mode: VUI.Image.ResizingMode in [.stretch, .tile] {
            var image = VUI.Image.Resolved(image: graphics(), decorative: true)
            image.layoutMetrics = metrics()
            image.image.resizingInfo = VUI.Image.ResizingInfo(
                capInsets: EdgeInsets(top: 7, leading: 10, bottom: 9, trailing: 20), mode: mode)
            let cases: [(_ProposedSize, CGSize)] = [
                (.unspecified, CGSize(width: 4, height: 2)),
                (.zero, CGSize(width: 30, height: 16)),
                (_ProposedSize(width: 1, height: 2), CGSize(width: 30, height: 16)),
                (_ProposedSize(width: nil, height: 2), CGSize(width: 4, height: 16)),
                (_ProposedSize(width: 1, height: nil), CGSize(width: 30, height: 2)),
                (_ProposedSize(width: -3, height: -4), CGSize(width: 30, height: 16)),
                (_ProposedSize(width: .infinity, height: .infinity), CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
            ]
            for (proposal, expected) in cases {
                XCTAssertEqual(image.sizeThatFits(in: proposal), expected)
                XCTAssertEqual(ImageDrawing(image).sizeThatFits(proposal), expected)
            }
            let nanSize = image.sizeThatFits(in: _ProposedSize(width: .nan, height: .nan))
            XCTAssertTrue(nanSize.width.isNaN && nanSize.height.isNaN)
            XCTAssertEqual(image.frame(in: CGSize(width: 31, height: 19)),
                           CGRect(x: 0, y: 0, width: 31, height: 19))
            image.image.resizingInfo?.capInsets = EdgeInsets(top: -7, leading: -10, bottom: -9, trailing: -20)
            XCTAssertEqual(image.sizeThatFits(in: _ProposedSize(width: -3, height: -4)),
                           CGSize(width: -3, height: -4))
        }
        // ASSERTIONS imageResolvedLayoutMetricsObserved
    }

    func testIndirectOptionalSharesCopiesAndReplacesBoxOnWriteback() {
        func address<T>(_ value: IndirectOptional<T>) -> UInt {
            XCTAssertEqual(MemoryLayout<IndirectOptional<T>>.size, MemoryLayout<UInt>.size)
            return withUnsafeBytes(of: value) { $0.load(as: UInt.self) }
        }
        let original = IndirectOptional(metrics())
        var copy = original
        XCTAssertEqual(address(original), address(copy))
        copy.wrappedValue = original.wrappedValue
        XCTAssertNotEqual(address(original), address(copy))
        XCTAssertEqual(original, copy)
        let saved = copy
        copy.wrappedValue?.capHeight = 99
        XCTAssertNotEqual(address(saved), address(copy))
        XCTAssertEqual(saved.wrappedValue?.capHeight, 11)
        XCTAssertEqual(copy.wrappedValue?.capHeight, 99)
        copy.wrappedValue = nil
        XCTAssertEqual(address(copy), 0)
        var nan = original
        nan.wrappedValue?.capHeight = .nan
        XCTAssertNotEqual(nan, nan)
        withExtendedLifetime((original, saved)) {}
        // ASSERTIONS imageResolvedStorageOwnershipObserved
    }

    func testIndirectOptionalHashUsesPresenceThenPayload() {
        for value: Int? in [nil, 7] {
            var expected = Hasher()
            var actual = expected
            if let value {
                expected.combine(UInt(1))
                value.hash(into: &expected)
            } else {
                expected.combine(UInt(0))
            }
            IndirectOptional(wrappedValue: value).hash(into: &actual)
            XCTAssertEqual(actual.finalize(), expected.finalize())
        }
        // ASSERTIONS imageResolvedStorageOwnershipObserved
    }

    func testResolvedEqualityUsesAllFieldsAndObjectIdentity() {
        let a: AnyObject = NSMutableString(string: "same")
        let b: AnyObject = NSMutableString(string: "same")
        let source = VUI.Image.Resolved(image: graphics(), decorative: false,
            label: .text(Text(verbatim: "label")), basePlatformItemImage: a)
        var copy = source
        XCTAssertEqual(source, copy)
        copy.basePlatformItemImage = b
        XCTAssertNotEqual(source, copy)
        let mutations: [(inout VUI.Image.Resolved) -> Void] = [
            { $0.image.scale = 4 },
            { $0.label = .systemSymbol("label") },
            { $0.basePlatformItemImage = nil },
            { $0.layoutMetrics = self.metrics() },
            { $0.decorative = true },
            { $0.backgroundShape = .circle },
            { $0.backgroundCornerRadius = 2 },
            { $0.styleResolverMode.foregroundLevels = 7 }
        ]
        for mutate in mutations {
            var changed = source
            mutate(&changed)
            XCTAssertNotEqual(source, changed)
        }
        XCTAssertEqual(EquatableOptionalObject<AnyObject>(wrappedValue: nil),
                       EquatableOptionalObject<AnyObject>(wrappedValue: nil))
        // ASSERTIONS imageResolvedStorageOwnershipObserved
    }

    func testImageReplacementRecomputesModeWhilePreservingBackgroundOption() throws {
        let svg = try SVG(source: "<svg viewBox=\"0 0 8 4\"><path d=\"M0 0H8V4H0Z\"/></svg>")
        let plain = GraphicsImage(svg: svg)
        var template = plain
        template.maskColor = Color.ResolvedHDR(Color.Resolved(red: 1, green: 1, blue: 1))
        var image = VUI.Image.Resolved(image: plain, decorative: true,
            backgroundShape: .square, backgroundCornerRadius: 1.234567890123)
        XCTAssertEqual(image.styleResolverMode.foregroundLevels, 0)
        XCTAssertEqual(image.styleResolverMode.options, .background)
        XCTAssertEqual(image.backgroundCornerRadius, Float(1.234567890123))
        image.backgroundShape = nil
        XCTAssertEqual(image.styleResolverMode.options, .background)
        image.styleResolverMode.options.insert(.multicolor)
        image.image = template
        XCTAssertEqual(image.styleResolverMode.foregroundLevels, 1)
        XCTAssertEqual(image.styleResolverMode.options, .background)
        image.image.contents = nil
        XCTAssertEqual(image.styleResolverMode.foregroundLevels, 0)
        XCTAssertEqual(image.styleResolverMode.options, .background)
        // ASSERTIONS imageResolvedStyleResolverModeObserved
    }

    private final class Provider: AnyImageProviderBox, @unchecked Sendable {
        let value: VUI.Image.Resolved
        init(_ value: VUI.Image.Resolved) { self.value = value }
        override func resolveImage(in context: GraphicsContext) -> VUI.Image.Resolved { value }
    }

    func testCanvasProjectsBaselineWhileViewDrawingKeepsMetricsAndLabel() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else { throw XCTSkip("Metal unavailable") }
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(sceneResources: SceneResources(),
            environment: EnvironmentValues(), viewport: CGRect(x: 0, y: 0, width: 8, height: 8),
            contentOffset: .zero, contentScaleFactor: 1, resolution: CGSize(width: 8, height: 8),
            commandBuffer: commands))
        var value = VUI.Image.Resolved(image: graphics(), decorative: false, label: .text(Text(verbatim: "label")))
        value.layoutMetrics = metrics()
        let source = VUI.Image(provider: Provider(value))
        let canvas = context.resolve(source)
        XCTAssertEqual(canvas.size, CGSize(width: 4, height: 2))
        XCTAssertEqual(canvas.baseline, -1)
        let drawing = context.resolveImageDrawing(source)
        XCTAssertEqual(drawing.resolved, value)
        XCTAssertEqual(drawing.baseline, canvas.baseline)
        XCTAssertEqual(drawing.sizeThatFits(.zero), CGSize(width: 21, height: 15))
        let resized = context.resolveImageDrawing(source.resizable(
            capInsets: EdgeInsets(top: 7, leading: 10, bottom: 9, trailing: 20), resizingMode: .tile))
        XCTAssertEqual(resized.resolved.label, value.label)
        XCTAssertEqual(resized.resolved.layoutMetrics, value.layoutMetrics)
        XCTAssertFalse(resized.resolved.decorative)
        XCTAssertEqual(resized.sizeThatFits(.zero), CGSize(width: 30, height: 16))
        XCTAssertNil(value.image.resizingInfo)
        let texture = try XCTUnwrap(device.device.makeTexture(descriptor: TextureDescriptor(
            textureType: .type2D, pixelFormat: .rgba8Unorm, width: 8, height: 4, usage: .sampled)))
        let label = Text(verbatim: "texture")
        let labelled = context.resolveImageDrawing(VUI.Image(texture, scale: 2, label: label))
        XCTAssertEqual(labelled.resolved.label, .text(label))
        XCTAssertFalse(labelled.resolved.decorative)
        let decorative = context.resolveImageDrawing(VUI.Image(decorative: texture, scale: 2))
        XCTAssertNil(decorative.resolved.label)
        XCTAssertTrue(decorative.resolved.decorative)
        XCTAssertTrue(labelled.texture === decorative.texture)
        // ASSERTIONS imageResolvedLayoutMetricsObserved
        // ASSERTIONS imageResolvedStorageOwnershipObserved
    }
}
