import XCTest
import VVD
@testable import VUI

final class GraphicsImageTests: XCTestCase {
    private final class SampleTexture: Texture {
        let width = 4
        let height = 2
        let depth = 1
        let mipmapCount = 1
        let arrayLength = 1
        let sampleCount = 1
        let type = TextureType.type2D
        let pixelFormat = PixelFormat.rgba8Unorm
        let isTransient = false
        var device: GraphicsDevice { fatalError("No GPU operation in this fixture") }
        func makeTextureView(pixelFormat: PixelFormat) -> Texture? { nil }
    }

    // ASSERTIONS canvasGraphicsImageSizeAndTemplateObserved
    // ASSERTIONS canvasResourceOwnerFieldsObserved
    func testOrientedSizeUsesSourceScaleAndCanvasKeepsSeparateValue() {
        let texture = SampleTexture()
        for orientation in Image.Orientation.allCases {
            for scale: CGFloat in [-2, 0, 0.5, 1, 2] {
                let image = GraphicsImage(texture: texture, scale: scale, orientation: orientation)
                let swaps = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
                let expected = scale == 0 ? CGSize.zero : CGSize(
                    width: (swaps ? 2 : 4) / scale,
                    height: (swaps ? 4 : 2) / scale
                )
                let resolved = GraphicsContext.ResolvedImage(resolved: image, baseline: image.size.height)
                XCTAssertEqual(image.size, expected)
                XCTAssertEqual(resolved.size, expected)
                XCTAssertEqual(resolved.baseline, expected.height)
                XCTAssertEqual(image.unrotatedPixelSize, CGSize(width: 4, height: 2))
                XCTAssertTrue(resolved.texture === texture)
                XCTAssertEqual(Mirror(reflecting: resolved).children.compactMap(\.label),
                               ["resolved", "baseline", "shading"])
            }
        }
    }

    // ASSERTIONS canvasResourceOwnerFieldsObserved
    // ASSERTIONS canvasGraphicsImageSizeAndTemplateObserved
    func testCopiesShareOnlyContentsAndKeepResizingAndMaskValuesIndependent() {
        let source = GraphicsImage(texture: SampleTexture(), scale: 2)
        var copy = source
        copy.resizingInfo = Image.ResizingInfo(
            capInsets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4), mode: .tile)
        copy.orientation = .right
        copy.isAntialiased = false
        copy.interpolation = .none
        let template = GraphicsImage(contents: copy.contents, scale: copy.scale,
            unrotatedPixelSize: copy.unrotatedPixelSize, isTemplate: true)
        copy.maskColor = template.maskColor

        XCTAssertNil(source.resizingInfo)
        XCTAssertNil(source.maskColor)
        XCTAssertEqual(source.orientation, .up)
        XCTAssertTrue(source.isAntialiased)
        XCTAssertEqual(source.interpolation, .low)
        XCTAssertEqual(copy.maskColor?.base, Color.Resolved(
            colorSpace: .sRGBLinear, red: 1, green: 1, blue: 1, opacity: 1))
        XCTAssertNil(copy.maskColor?.headroom)
        XCTAssertEqual(copy.allowedDynamicRange, .standard)
        guard case let .texture(lhs) = source.contents,
              case let .texture(rhs) = copy.contents else {
            return XCTFail("Texture contents missing")
        }
        XCTAssertTrue(lhs === rhs)

        var drawing = ImageDrawing(GraphicsContext.ResolvedImage(resolved: source, baseline: 1))
        let saved = drawing
        drawing.applyResizingProvider(ResizableProvider(
            base: Image(decorative: SampleTexture(), scale: 1),
            capInsets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4), resizingMode: .tile))
        XCTAssertNil(saved.resizingMode)
        XCTAssertEqual(drawing.image.resizingInfo, copy.resizingInfo)
        XCTAssertTrue(saved.texture === drawing.texture)
    }

    // ASSERTIONS canvasGraphicsImageValueEqualityObserved
    func testTextureIdentityAndAllMetadataParticipateInValueEquality() {
        let texture = SampleTexture()
        let source = GraphicsImage(texture: texture, scale: 1)
        XCTAssertEqual(source, GraphicsImage(texture: texture, scale: 1))
        XCTAssertNotEqual(source, GraphicsImage(texture: SampleTexture(), scale: 1))
        let changes: [(inout GraphicsImage) -> Void] = [
            { $0.contents = nil },
            { $0.scale = 2 },
            { $0.unrotatedPixelSize.width = 8 },
            { $0.orientation = .down },
            { $0.maskColor = Color.ResolvedHDR(Color.Resolved(red: 1, green: 1, blue: 1)) },
            { $0.resizingInfo = Image.ResizingInfo(capInsets: EdgeInsets(), mode: .stretch) },
            { $0.isAntialiased = false },
            { $0.interpolation = .none },
            { $0.allowedDynamicRange = .high }
        ]
        for change in changes {
            var copy = source
            change(&copy)
            XCTAssertNotEqual(source, copy)
        }
        let a = GraphicsImage(contents: source.contents, scale: 1,
            unrotatedPixelSize: source.unrotatedPixelSize, isTemplate: true)
        let b = GraphicsImage(contents: source.contents, scale: 1,
            unrotatedPixelSize: source.unrotatedPixelSize, isTemplate: true)
        XCTAssertEqual(a, b)
    }

    func testTextureLifetimePurgeLeavesRetainedImageMetadataIntact() throws {
        weak var weakTexture: SampleTexture?
        var image: GraphicsImage?
        do {
            let texture = SampleTexture()
            weakTexture = texture
            image = GraphicsImage(texture: texture, scale: 2, orientation: .right)
        }
        let retained = try XCTUnwrap(image)
        image = nil
        XCTAssertNotNil(weakTexture)
        guard case let .texture(resource) = retained.contents else {
            return XCTFail("Texture contents missing")
        }
        resource.purgeResources(reason: .lowMemory)
        XCTAssertNotNil(weakTexture)
        resource.purgeResources(reason: .appTermination)
        XCTAssertNil(weakTexture)
        XCTAssertNil(retained.texture)
        XCTAssertEqual(retained.size, CGSize(width: 1, height: 2))
        XCTAssertEqual(retained.unrotatedPixelSize, CGSize(width: 4, height: 2))
    }

    private func makeContext(
        queue: CommandQueue, size: CGSize, scale: CGFloat = 1
    ) throws -> GraphicsContext {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        var environment = EnvironmentValues()
        environment.displayScale = scale
        let scene = SceneResources()
        scene.contentScaleFactor = scale
        let context = try XCTUnwrap(GraphicsContext(sceneResources: scene,
            environment: environment, viewport: CGRect(origin: .zero, size: size),
            contentOffset: .zero, contentScaleFactor: scale, resolution: size,
            commandBuffer: commands))
        context.clear(with: .clear)
        return context
    }

    // ASSERTIONS canvasGraphicsImageSizeAndTemplateObserved
    func testTextureProviderCarriesScaleOrientationAndValueResizingThroughCanvas() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let queue = try XCTUnwrap(device.renderQueue())
        let texture = try XCTUnwrap(device.device.makeTexture(descriptor: TextureDescriptor(
            textureType: .type2D, pixelFormat: .rgba8Unorm, width: 4, height: 2, usage: .sampled)))
        let context = try makeContext(queue: queue, size: CGSize(width: 8, height: 8), scale: 3)
        for orientation in Image.Orientation.allCases {
            for scale: CGFloat in [-2, 0, 0.5, 1, 2] {
                let source = Image(decorative: texture, scale: scale, orientation: orientation)
                let image = context.resolve(source)
                let expected = GraphicsImage(texture: texture, scale: scale, orientation: orientation)
                XCTAssertEqual(image.resolved, expected)
                XCTAssertEqual(image.baseline, expected.size.height)
                let resized = context.resolve(source.resizable(
                    capInsets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4), resizingMode: .tile))
                XCTAssertNil(image.resolved.resizingInfo)
                XCTAssertEqual(resized.resolved.resizingInfo?.mode, .tile)
                XCTAssertEqual(resized.resolved.resizingInfo?.capInsets.leading, 2)
                guard case let .texture(a) = image.resolved.contents,
                      case let .texture(b) = resized.resolved.contents else {
                    return XCTFail("Texture contents missing")
                }
                XCTAssertTrue(a === b)
            }
        }
    }

    // ASSERTIONS canvasGraphicsImageOrientationPixelsObserved
    func testAllEightOrientationsRenderTheObservedPixelOrderOnMetal() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let queue = try XCTUnwrap(device.renderQueue())
        let values: [UInt8] = [32, 64, 96, 128, 160, 192, 224, 255]
        let bitmap = VVD.Image(width: 4, height: 2, pixelFormat: .rgba8,
            data: Data(values.flatMap { [$0, UInt8(0), UInt8(0), UInt8(255)] }))
        let texture = try XCTUnwrap(bitmap.makeTexture(commandQueue: queue))
        let expected: [[UInt8]] = [
            [32, 64, 96, 128, 160, 192, 224, 255],
            [128, 96, 64, 32, 255, 224, 192, 160],
            [255, 224, 192, 160, 128, 96, 64, 32],
            [160, 192, 224, 255, 32, 64, 96, 128],
            [128, 255, 96, 224, 64, 192, 32, 160],
            [32, 160, 64, 192, 96, 224, 128, 255],
            [160, 32, 192, 64, 224, 96, 255, 128],
            [255, 128, 224, 96, 192, 64, 160, 32]
        ]
        for (index, orientation) in Image.Orientation.allCases.enumerated() {
            let source = Image(decorative: texture, scale: 1, orientation: orientation)
            let size = index < 4 ? CGSize(width: 4, height: 2) : CGSize(width: 2, height: 4)
            let context = try makeContext(queue: queue, size: size)
            context.draw(context.resolve(source), in: CGRect(origin: .zero, size: size))
            let done = expectation(description: "Image orientation completion")
            context.commandBuffer.addCompletedHandler { _ in done.fulfill() }
            XCTAssertTrue(context.commandBuffer.commit())
            wait(for: [done], timeout: 5)
            let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
            let bytes = try XCTUnwrap(staging.contents()).assumingMemoryBound(to: UInt8.self)
            XCTAssertEqual((0..<8).map { bytes[$0 * 4] }, expected[index], "\(orientation)")
            XCTAssertEqual((0..<8).map { bytes[$0 * 4 + 3] }, Array(repeating: 255, count: 8))
        }
    }
}
