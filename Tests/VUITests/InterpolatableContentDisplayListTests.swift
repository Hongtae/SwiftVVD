import XCTest
import VVD
@testable import VUI

private final class ProbeTexture: Texture {
    var width: Int { 1 }
    var height: Int { 1 }
    var depth: Int { 1 }
    var mipmapCount: Int { 1 }
    var arrayLength: Int { 1 }
    var sampleCount: Int { 1 }
    var type: TextureType { .type2D }
    var pixelFormat: PixelFormat { .rgba8Unorm }
    var isTransient: Bool { false }
    var device: GraphicsDevice { fatalError("ProbeTexture.device is unused.") }

    func makeTextureView(pixelFormat: PixelFormat) -> Texture? {
        nil
    }
}

private enum InterpolatableContentProbeLog {
    nonisolated(unsafe) static var modifyTransitionCalls = 0
    nonisolated(unsafe) static var defaultAnimationCalls = 0

    static func reset() {
        modifyTransitionCalls = 0
        defaultAnimationCalls = 0
    }
}

private struct ProbeInterpolatableContent: Equatable, InterpolatableContent {
    var value: Int

    func modifyTransition(state: inout ContentTransition.State, to target: Self) {
        InterpolatableContentProbeLog.modifyTransitionCalls += 1
    }

    func defaultAnimation(to target: Self) -> Animation? {
        InterpolatableContentProbeLog.defaultAnimationCalls += 1
        return .linear(duration: 0.25)
    }
}

private struct VersionedTransitionContent: Equatable, InterpolatableContent {
    static var defaultTransition: ContentTransition { .opacity }

    var value: Int
}

final class InterpolatableContentDisplayListTests: XCTestCase {
    func testPrivateColorMatrixSurface() throws {
        XCTAssertEqual(_ColorMatrix(), _ColorMatrix(_ColorMatrix().colorMatrix))

        var color = _ColorMatrix(color: Color(red: 0.25, green: 0.5, blue: 0.75, opacity: 0.6), in: EnvironmentValues())
        XCTAssertEqual(color.m11, 0.25)
        XCTAssertEqual(color.m22, 0.5)
        XCTAssertEqual(color.m33, 0.75)
        XCTAssertEqual(color.m44, 0.6)
        XCTAssertEqual(color.m15, 0)
        XCTAssertEqual(color.m25, 0)
        XCTAssertEqual(color.m35, 0)
        XCTAssertEqual(color.m45, 0)

        var a = _ColorMatrix()
        a.m11 = 2
        a.m12 = 3
        a.m13 = 5
        a.m14 = 7
        a.m15 = 11
        a.m21 = 13
        a.m22 = 17
        a.m23 = 19
        a.m24 = 23
        a.m25 = 29
        a.m31 = 31
        a.m32 = 37
        a.m33 = 41
        a.m34 = 43
        a.m35 = 47
        a.m41 = 53
        a.m42 = 59
        a.m43 = 61
        a.m44 = 67
        a.m45 = 71

        var b = _ColorMatrix()
        b.m11 = 73
        b.m12 = 79
        b.m13 = 83
        b.m14 = 89
        b.m15 = 97
        b.m21 = 101
        b.m22 = 103
        b.m23 = 107
        b.m24 = 109
        b.m25 = 113
        b.m31 = 127
        b.m32 = 131
        b.m33 = 137
        b.m34 = 139
        b.m35 = 149
        b.m41 = 151
        b.m42 = 157
        b.m43 = 163
        b.m44 = 167
        b.m45 = 173

        let product = a * b
        XCTAssertEqual(product.m11, 2141)
        XCTAssertEqual(product.m12, 2221)
        XCTAssertEqual(product.m13, 2313)
        XCTAssertEqual(product.m14, 2369)
        XCTAssertEqual(product.m15, 2500)
        XCTAssertEqual(product.m21, 8552)
        XCTAssertEqual(product.m25, 10021)
        XCTAssertEqual(product.m31, 17700)
        XCTAssertEqual(product.m35, 20783)
        XCTAssertEqual(product.m41, 27692)
        XCTAssertEqual(product.m45, 32559)

        let data = try JSONEncoder().encode(a)
        XCTAssertEqual(String(data: data, encoding: .utf8), "[2,3,5,7,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71]")
        XCTAssertEqual(try JSONDecoder().decode(_ColorMatrix.self, from: data), a)

        color.m11 = 1
        XCTAssertNotEqual(color, _ColorMatrix(color: Color(red: 0.25, green: 0.5, blue: 0.75, opacity: 0.6), in: EnvironmentValues()))
    }

    func testDisplayListSeedSurface() {
        XCTAssertEqual(DisplayList.Seed().value, 0)
        XCTAssertEqual(DisplayList.Seed(decodedValue: 42).value, 42)
        XCTAssertEqual(DisplayList.Seed.undefined.value, 2)
        XCTAssertEqual(DisplayList.Seed(DisplayList.Version(value: 0)).value, 0)
        XCTAssertEqual(DisplayList.Seed(DisplayList.Version(value: 1)).value, 3)
        XCTAssertEqual(DisplayList.Seed(DisplayList.Version(value: 0x0001_0000)).value, 0x0043)

        var zero = DisplayList.Seed()
        zero.invalidate()
        XCTAssertEqual(zero.value, 0)

        var undefined = DisplayList.Seed.undefined
        undefined.invalidate()
        XCTAssertEqual(undefined.value, 0xfffd)
        undefined.invalidate()
        XCTAssertEqual(undefined.value, 3)
    }

    func testDisplayListRenderTraversalIncludesContentTransitionEffects() {
        var list = makeDisplayList(debugItemCount: 1, itemCount: 2)
        let retained = makeDisplayList(debugItemCount: 2, itemCount: 1)
        let ignored = makeDisplayList(debugItemCount: 3, itemCount: 3)

        list.appendEffect(
            .contentTransition(ContentTransition.State(transition: .opacity)),
            contents: retained
        )
        list.appendEffect(
            .state(StrongHash(words: (1, 2, 3, 4, 5))),
            contents: ignored
        )

        var renderItemCount = 0
        list.forEachRenderItem { _ in
            renderItemCount += 1
        }

        XCTAssertEqual(renderItemCount, 6)
    }

    func testDisplayListItemsDeriveRecordsFromTypedCommands() throws {
        var source = DisplayList()
        source.appendItem(
            kind: .image,
            bounds: CGRect(x: 1, y: 2, width: 3, height: 4)
        ) { _ in }
        source.appendDebugItem(
            bounds: CGRect(x: 5, y: 6, width: 7, height: 8)
        ) { _ in }

        var copied = DisplayList()
        copied.items.append(try XCTUnwrap(source.items.first))
        copied.debugItems.append(try XCTUnwrap(source.debugItems.first))

        XCTAssertEqual(copied.itemRecords.first?.kind, .image)
        XCTAssertEqual(copied.itemRecords.first?.bounds, CGRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertEqual(copied.debugItemRecords.first?.kind, .debug)
        XCTAssertEqual(copied.debugItemRecords.first?.bounds, CGRect(x: 5, y: 6, width: 7, height: 8))

        guard case let .image(image, imageBounds)? = copied.items.first?.command else {
            XCTFail("missing image command")
            return
        }
        XCTAssertEqual(imageBounds, CGRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertEqual(image.scaleFactor, 1)
        XCTAssertFalse(image.hasShading)

        guard case let .debug(debugBounds)? = copied.debugItems.first?.command else {
            XCTFail("missing debug command")
            return
        }
        XCTAssertEqual(debugBounds, CGRect(x: 5, y: 6, width: 7, height: 8))

        var shape = DisplayList()
        shape.appendShapeItem(
            role: .stroke,
            style: Color.red,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 10),
            strokeStyle: StrokeStyle(lineWidth: 2)
        ) { _ in }
        guard case let .shape(role, style, _, strokeStyle, bounds)? = shape.items.first?.command else {
            XCTFail("missing shape command")
            return
        }
        XCTAssertEqual(role, .stroke)
        XCTAssertEqual(style, .color(.red))
        XCTAssertEqual(strokeStyle, StrokeStyle(lineWidth: 2))
        XCTAssertEqual(bounds, CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(shape.itemRecords.first?.kind, .shapeStroke)
        XCTAssertEqual(shape.itemRecords.first?.shapeStyle, .color(.red))

        var opacity = DisplayList()
        opacity.appendOpacityItem(
            bounds: CGRect(x: 0, y: 0, width: 10, height: 10),
            opacity: 0.25
        ) { _ in }
        guard case let .effect(.opacity(opacityValue), opacityBounds)? = opacity.items.first?.command else {
            XCTFail("missing opacity command")
            return
        }
        XCTAssertEqual(opacityValue, 0.25)
        XCTAssertEqual(opacityBounds, CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(opacity.itemRecords.first?.effectKind, .opacity)
        XCTAssertEqual(opacity.itemRecords.first?.opacity, 0.25)
    }

    func testDisplayListItemCommandsParticipateInLayerSurfaceMatching() {
        var layer = DisplayList.InterpolatorLayer()
        let first = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            itemKind: .shapeFill
        )
        let sameSurface = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            itemKind: .shapeFill
        )
        let changedKind = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            itemKind: .image
        )

        layer.setDisplayList(
            first,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        layer.setDisplayList(
            sameSurface,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        XCTAssertEqual(layer.contents.displayList.itemRecords.first?.kind, .shapeFill)

        layer.setDisplayList(
            changedKind,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        XCTAssertEqual(layer.contents.displayList.itemRecords.first?.kind, .image)
        XCTAssertEqual(layer.removedCount, 0)
    }

    func testDisplayListAnimationStyleParticipatesInSurfaceMatching() throws {
        let id = try XCTUnwrap(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"))
        let animation = RBAnimation()
        animation.addBezierDuration(
            2,
            controlPoint1: CGPoint(x: 0.25, y: 0),
            controlPoint2: CGPoint(x: 0.75, y: 1)
        )

        var source = makeDisplayList(debugItemCount: 0, itemCount: 1, itemKind: .shapeFill)
        source.appendAnimationStyle(animation, id: id)

        let matchingAnimation = RBAnimation()
        matchingAnimation.addBezierDuration(
            2,
            controlPoint1: CGPoint(x: 0.25, y: 0),
            controlPoint2: CGPoint(x: 0.75, y: 1)
        )
        var same = makeDisplayList(debugItemCount: 0, itemCount: 1, itemKind: .shapeFill)
        same.appendAnimationStyle(matchingAnimation, id: id)

        guard case let .animation(style)? = source.styles.first else {
            XCTFail("missing animation style")
            return
        }
        XCTAssertEqual(style.id, id)
        XCTAssertEqual(style.flags, DisplayList.StyleCommand.AnimationStyle.defaultFlags)
        XCTAssertTrue(style.animation.isEqual(matchingAnimation))
        XCTAssertFalse(style.animation === animation)
        XCTAssertTrue(source.hasSameInterpolationSurface(as: same))

        animation.addDelay(1)
        XCTAssertTrue(source.hasSameInterpolationSurface(as: same))

        var changedAnimation = makeDisplayList(debugItemCount: 0, itemCount: 1, itemKind: .shapeFill)
        let delayedAnimation = RBAnimation()
        delayedAnimation.addDelay(1)
        delayedAnimation.addBezierDuration(
            2,
            controlPoint1: CGPoint(x: 0.25, y: 0),
            controlPoint2: CGPoint(x: 0.75, y: 1)
        )
        changedAnimation.appendAnimationStyle(delayedAnimation, id: id)

        var changedID = makeDisplayList(debugItemCount: 0, itemCount: 1, itemKind: .shapeFill)
        changedID.appendAnimationStyle(
            matchingAnimation,
            id: try XCTUnwrap(UUID(uuidString: "FFEEDDCC-BBAA-9988-7766-554433221100"))
        )

        var changedFlags = makeDisplayList(debugItemCount: 0, itemCount: 1, itemKind: .shapeFill)
        changedFlags.appendAnimationStyle(matchingAnimation, id: id, flags: 0x211)

        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedAnimation))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedID))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedFlags))

        var appended = DisplayList()
        appended.append(contentsOf: source)
        XCTAssertEqual(appended.styles, source.styles)
    }

    func testDisplayListShapeRoleParticipatesInSurfaceMatching() {
        var fill = DisplayList()
        fill.appendShapeItem(
            role: .fill,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 10)
        ) { _ in }

        var sameFill = DisplayList()
        sameFill.appendShapeItem(
            role: .fill,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 10)
        ) { _ in }

        var stroke = DisplayList()
        stroke.appendShapeItem(
            role: .stroke,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 10)
        ) { _ in }

        var separator = DisplayList()
        separator.appendShapeItem(
            role: .separator,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 10)
        ) { _ in }

        XCTAssertEqual(fill.itemRecords.first?.kind, .shapeFill)
        XCTAssertEqual(stroke.itemRecords.first?.kind, .shapeStroke)
        XCTAssertEqual(separator.itemRecords.first?.kind, .shapeSeparator)
        XCTAssertTrue(fill.hasSameInterpolationSurface(as: sameFill))
        XCTAssertFalse(fill.hasSameInterpolationSurface(as: stroke))
        XCTAssertFalse(fill.hasSameInterpolationSurface(as: separator))
        XCTAssertFalse(stroke.hasSameInterpolationSurface(as: separator))
    }

    func testDisplayListShapeColorPayloadParticipatesInSurfaceMatching() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        var red = DisplayList()
        red.appendShapeItem(role: .fill, style: Color.red, bounds: bounds) { _ in }

        var sameRed = DisplayList()
        sameRed.appendShapeItem(role: .fill, style: Color.red, bounds: bounds) { _ in }

        var blue = DisplayList()
        blue.appendShapeItem(role: .fill, style: Color.blue, bounds: bounds) { _ in }

        XCTAssertEqual(red.itemRecords.first?.shapeStyle, .color(.red))
        XCTAssertEqual(blue.itemRecords.first?.shapeStyle, .color(.blue))
        XCTAssertTrue(red.hasSameInterpolationSurface(as: sameRed))
        XCTAssertFalse(red.hasSameInterpolationSurface(as: blue))
    }

    func testDisplayListShapeStyleFamilyParticipatesInSurfaceMatching() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let redBlue = Gradient(colors: [.red, .blue])
        let blueGreen = Gradient(colors: [.blue, .green])

        var gradient = DisplayList()
        gradient.appendShapeItem(role: .fill, style: redBlue, bounds: bounds) { _ in }

        var sameGradient = DisplayList()
        sameGradient.appendShapeItem(role: .fill, style: redBlue, bounds: bounds) { _ in }

        var changedGradient = DisplayList()
        changedGradient.appendShapeItem(role: .fill, style: blueGreen, bounds: bounds) { _ in }

        var erasedGradient = DisplayList()
        erasedGradient.appendShapeItem(
            role: .fill,
            style: AnyShapeStyle(redBlue),
            bounds: bounds
        ) { _ in }

        var color = DisplayList()
        color.appendShapeItem(role: .fill, style: Color.red, bounds: bounds) { _ in }

        var foreground = DisplayList()
        foreground.appendShapeItem(role: .fill, style: ForegroundStyle(), bounds: bounds) { _ in }

        var background = DisplayList()
        background.appendShapeItem(role: .fill, style: BackgroundStyle(), bounds: bounds) { _ in }

        XCTAssertEqual(gradient.itemRecords.first?.shapeStyle, .gradient(redBlue))
        XCTAssertEqual(changedGradient.itemRecords.first?.shapeStyle, .gradient(blueGreen))
        XCTAssertTrue(gradient.hasSameInterpolationSurface(as: sameGradient))
        XCTAssertTrue(gradient.hasSameInterpolationSurface(as: erasedGradient))
        XCTAssertFalse(gradient.hasSameInterpolationSurface(as: changedGradient))
        XCTAssertFalse(gradient.hasSameInterpolationSurface(as: color))
        XCTAssertEqual(foreground.itemRecords.first?.shapeStyle, .color(Color(.sRGB, white: 0.145)))
        XCTAssertEqual(background.itemRecords.first?.shapeStyle, .color(Color(.sRGB, white: 1)))
        XCTAssertFalse(foreground.hasSameInterpolationSurface(as: background))
    }

    func testDisplayListShapeFillStyleParticipatesInSurfaceMatching() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let nonZero = FillStyle(eoFill: false, antialiased: true)
        let evenOdd = FillStyle(eoFill: true, antialiased: true)

        var source = DisplayList()
        source.appendShapeItem(
            role: .fill,
            style: Color.red,
            bounds: bounds,
            fillStyle: nonZero
        ) { _ in }

        var same = DisplayList()
        same.appendShapeItem(
            role: .fill,
            style: Color.red,
            bounds: bounds,
            fillStyle: nonZero
        ) { _ in }

        var changed = DisplayList()
        changed.appendShapeItem(
            role: .fill,
            style: Color.red,
            bounds: bounds,
            fillStyle: evenOdd
        ) { _ in }

        XCTAssertEqual(source.itemRecords.first?.fillStyle, nonZero)
        XCTAssertEqual(changed.itemRecords.first?.fillStyle, evenOdd)
        XCTAssertTrue(source.hasSameInterpolationSurface(as: same))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changed))
    }

    func testDisplayListShapeStrokeStyleParticipatesInSurfaceMatching() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let thinStyle = StrokeStyle(lineWidth: 1)
        let thickStyle = StrokeStyle(lineWidth: 4)

        var thin = DisplayList()
        thin.appendShapeItem(
            role: .stroke,
            style: Color.red,
            bounds: bounds,
            strokeStyle: thinStyle
        ) { _ in }

        var sameThin = DisplayList()
        sameThin.appendShapeItem(
            role: .stroke,
            style: Color.red,
            bounds: bounds,
            strokeStyle: thinStyle
        ) { _ in }

        var thick = DisplayList()
        thick.appendShapeItem(
            role: .stroke,
            style: Color.red,
            bounds: bounds,
            strokeStyle: thickStyle
        ) { _ in }

        XCTAssertEqual(thin.itemRecords.first?.strokeStyle, thinStyle)
        XCTAssertEqual(thick.itemRecords.first?.strokeStyle, thickStyle)
        XCTAssertTrue(thin.hasSameInterpolationSurface(as: sameThin))
        XCTAssertFalse(thin.hasSameInterpolationSurface(as: thick))
    }

    func testDisplayListImagePayloadParticipatesInSurfaceMatching() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)

        var source = DisplayList()
        source.appendImageItem(makeResolvedImage(), bounds: bounds) { _ in }

        var same = DisplayList()
        same.appendImageItem(makeResolvedImage(), bounds: bounds) { _ in }

        var changedBaseline = DisplayList()
        changedBaseline.appendImageItem(makeResolvedImage(baseline: 2), bounds: bounds) { _ in }

        var changedTransform = DisplayList()
        changedTransform.appendImageItem(
            makeResolvedImage(textureTransform: CGAffineTransform(translationX: 1, y: 0)),
            bounds: bounds
        ) { _ in }

        var changedScale = DisplayList()
        changedScale.appendImageItem(makeResolvedImage(scaleFactor: 2), bounds: bounds) { _ in }

        var changedShadingPresence = DisplayList()
        changedShadingPresence.appendImageItem(
            makeResolvedImage(shading: .color(.red)),
            bounds: bounds
        ) { _ in }

        var sameRedShading = DisplayList()
        sameRedShading.appendImageItem(
            makeResolvedImage(shading: .color(.red)),
            bounds: bounds
        ) { _ in }

        var changedShadingColor = DisplayList()
        changedShadingColor.appendImageItem(
            makeResolvedImage(shading: .color(.blue)),
            bounds: bounds
        ) { _ in }

        let texture = ProbeTexture()
        var sameTexture = DisplayList()
        sameTexture.appendImageItem(makeResolvedImage(texture: texture), bounds: bounds) { _ in }

        var sameTextureAgain = DisplayList()
        sameTextureAgain.appendImageItem(makeResolvedImage(texture: texture), bounds: bounds) { _ in }

        var differentTexture = DisplayList()
        differentTexture.appendImageItem(makeResolvedImage(texture: ProbeTexture()), bounds: bounds) { _ in }

        XCTAssertEqual(source.itemRecords.first?.image?.baseline, 1)
        XCTAssertEqual(changedScale.itemRecords.first?.image?.scaleFactor, 2)
        XCTAssertFalse(source.itemRecords.first?.image?.hasShading ?? true)
        XCTAssertTrue(changedShadingPresence.itemRecords.first?.image?.hasShading ?? false)
        XCTAssertEqual(changedShadingPresence.itemRecords.first?.image?.shading, .color(.red))
        XCTAssertEqual(changedShadingColor.itemRecords.first?.image?.shading, .color(.blue))
        XCTAssertTrue(source.hasSameInterpolationSurface(as: same))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedBaseline))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedTransform))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedScale))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedShadingPresence))
        XCTAssertTrue(changedShadingPresence.hasSameInterpolationSurface(as: sameRedShading))
        XCTAssertFalse(changedShadingPresence.hasSameInterpolationSurface(as: changedShadingColor))
        XCTAssertTrue(sameTexture.hasSameInterpolationSurface(as: sameTextureAgain))
        XCTAssertFalse(sameTexture.hasSameInterpolationSurface(as: differentTexture))
    }

    func testDisplayListTextForegroundPayloadParticipatesInSurfaceMatching() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)

        var red = DisplayList()
        red.appendTextItem(foreground: .color(.red), bounds: bounds) { _ in }

        var sameRed = DisplayList()
        sameRed.appendTextItem(foreground: .color(.red), bounds: bounds) { _ in }

        var blue = DisplayList()
        blue.appendTextItem(foreground: .color(.blue), bounds: bounds) { _ in }

        XCTAssertEqual(red.itemRecords.first?.text?.foreground, .color(.red))
        XCTAssertEqual(blue.itemRecords.first?.text?.foreground, .color(.blue))
        XCTAssertTrue(red.hasSameInterpolationSurface(as: sameRed))
        XCTAssertFalse(red.hasSameInterpolationSurface(as: blue))
    }

    func testDisplayListCustomPayloadParticipatesInSurfaceMatching() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)

        var source = DisplayList()
        source.appendCustomItem(
            bounds: bounds,
            isOpaque: false,
            colorMode: .nonLinear,
            rendersAsynchronously: false
        ) { _ in }

        var same = DisplayList()
        same.appendCustomItem(
            bounds: bounds,
            isOpaque: false,
            colorMode: .nonLinear,
            rendersAsynchronously: false
        ) { _ in }

        var changedOpacity = DisplayList()
        changedOpacity.appendCustomItem(
            bounds: bounds,
            isOpaque: true,
            colorMode: .nonLinear,
            rendersAsynchronously: false
        ) { _ in }

        var changedColorMode = DisplayList()
        changedColorMode.appendCustomItem(
            bounds: bounds,
            isOpaque: false,
            colorMode: .linear,
            rendersAsynchronously: false
        ) { _ in }

        var changedAsync = DisplayList()
        changedAsync.appendCustomItem(
            bounds: bounds,
            isOpaque: false,
            colorMode: .nonLinear,
            rendersAsynchronously: true
        ) { _ in }

        XCTAssertEqual(source.itemRecords.first?.kind, .custom)
        XCTAssertEqual(source.itemRecords.first?.custom?.isOpaque, false)
        XCTAssertEqual(source.itemRecords.first?.custom?.colorMode, .nonLinear)
        XCTAssertEqual(source.itemRecords.first?.custom?.rendersAsynchronously, false)
        XCTAssertTrue(source.hasSameInterpolationSurface(as: same))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedOpacity))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedColorMode))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedAsync))
    }

    func testCanvasMakeViewEmitsCustomDisplayListItem() throws {
        let graph = AttributeGraph()

        try AttributeGraph.withCurrent(graph) {
            let canvas = Canvas(
                opaque: true,
                colorMode: .extendedLinear,
                rendersAsynchronously: true
            ) { _, _ in
            }
            let canvasAttr = graph.makeInput(value: canvas)
            let outputs = Canvas<EmptyView>._makeView(
                view: _GraphValue(_attribute: canvasAttr),
                inputs: makeViewInputs(graph: graph)
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let list = Attribute<DisplayList>(outputID).value

            XCTAssertEqual(list.items.count, 1)
            XCTAssertEqual(list.itemRecords.first?.kind, .custom)
            XCTAssertEqual(list.itemRecords.first?.bounds, CGRect(x: 0, y: 0, width: 10, height: 10))
            XCTAssertEqual(list.itemRecords.first?.custom?.isOpaque, true)
            XCTAssertEqual(list.itemRecords.first?.custom?.colorMode, .extendedLinear)
            XCTAssertEqual(list.itemRecords.first?.custom?.rendersAsynchronously, true)
            XCTAssertEqual(list.interpolationBounds, CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }

    func testBlendModeMapsToGraphicsContextBlendMode() {
        let expected: [(BlendMode, GraphicsContext.BlendMode)] = [
            (.normal, .normal),
            (.multiply, .multiply),
            (.screen, .screen),
            (.overlay, .overlay),
            (.darken, .darken),
            (.lighten, .lighten),
            (.colorDodge, .colorDodge),
            (.colorBurn, .colorBurn),
            (.softLight, .softLight),
            (.hardLight, .hardLight),
            (.difference, .difference),
            (.exclusion, .exclusion),
            (.hue, .hue),
            (.saturation, .saturation),
            (.color, .color),
            (.luminosity, .luminosity),
            (.sourceAtop, .sourceAtop),
            (.destinationOver, .destinationOver),
            (.destinationOut, .destinationOut),
            (.plusDarker, .plusDarker),
            (.plusLighter, .plusLighter),
        ]

        for (blendMode, graphicsBlendMode) in expected {
            XCTAssertEqual(
                blendMode.graphicsContextBlendMode,
                graphicsBlendMode
            )
        }
    }

    func testGraphicsContextColorInvertFilterUsesColorDiagonal() throws {
        let filter = GraphicsContext.Filter.colorInvert(0.25)
        guard case let .colorMatrix(matrix) = filter.style else {
            return XCTFail("Expected color matrix filter.")
        }

        XCTAssertEqual(matrix.r1, 0.5, accuracy: 0.000001)
        XCTAssertEqual(matrix.g2, 0.5, accuracy: 0.000001)
        XCTAssertEqual(matrix.b3, 0.5, accuracy: 0.000001)
        XCTAssertEqual(matrix.b2, 0, accuracy: 0.000001)
        XCTAssertEqual(matrix.r5, 0.25, accuracy: 0.000001)
        XCTAssertEqual(matrix.g5, 0.25, accuracy: 0.000001)
        XCTAssertEqual(matrix.b5, 0.25, accuracy: 0.000001)
    }

    func testDisplayListBlendModePayloadParticipatesInSurfaceMatching() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)

        var multiply = DisplayList()
        multiply.appendBlendModeItem(bounds: bounds, blendMode: .multiply) { _ in }

        var sameMultiply = DisplayList()
        sameMultiply.appendBlendModeItem(bounds: bounds, blendMode: .multiply) { _ in }

        var screen = DisplayList()
        screen.appendBlendModeItem(bounds: bounds, blendMode: .screen) { _ in }

        XCTAssertEqual(multiply.itemRecords.first?.kind, .effect)
        XCTAssertEqual(multiply.itemRecords.first?.effectKind, .blendMode)
        XCTAssertEqual(multiply.itemRecords.first?.blendMode, .multiply)
        XCTAssertEqual(screen.itemRecords.first?.blendMode, .screen)
        XCTAssertTrue(multiply.hasSameInterpolationSurface(as: sameMultiply))
        XCTAssertFalse(multiply.hasSameInterpolationSurface(as: screen))
    }

    func testDisplayListShadowPayloadParticipatesInSurfaceMatching() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let red = Color.red.resolve(in: EnvironmentValues())
        let blue = Color.blue.resolve(in: EnvironmentValues())

        var source = DisplayList()
        source.appendShadowItem(
            bounds: bounds,
            color: red,
            radius: 2,
            offset: CGSize(width: 3, height: 4)
        ) { _ in }

        var same = DisplayList()
        same.appendShadowItem(
            bounds: bounds,
            color: red,
            radius: 2,
            offset: CGSize(width: 3, height: 4)
        ) { _ in }

        var changedRadius = DisplayList()
        changedRadius.appendShadowItem(
            bounds: bounds,
            color: red,
            radius: 4,
            offset: CGSize(width: 3, height: 4)
        ) { _ in }

        var changedOffset = DisplayList()
        changedOffset.appendShadowItem(
            bounds: bounds,
            color: red,
            radius: 2,
            offset: CGSize(width: 4, height: 3)
        ) { _ in }

        var changedColor = DisplayList()
        changedColor.appendShadowItem(
            bounds: bounds,
            color: blue,
            radius: 2,
            offset: CGSize(width: 3, height: 4)
        ) { _ in }

        XCTAssertEqual(source.itemRecords.first?.kind, .effect)
        XCTAssertEqual(source.itemRecords.first?.effectKind, .shadow)
        XCTAssertEqual(source.itemRecords.first?.shadow?.color, red)
        XCTAssertEqual(source.itemRecords.first?.shadow?.radius, 2)
        XCTAssertEqual(source.itemRecords.first?.shadow?.offset, CGSize(width: 3, height: 4))
        XCTAssertEqual(source.itemRecords.first?.shadow?.blendModeRawValue, GraphicsContext.BlendMode.normal.rawValue)
        XCTAssertEqual(source.itemRecords.first?.shadow?.optionsRawValue, 0)
        XCTAssertTrue(source.hasSameInterpolationSurface(as: same))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedRadius))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedOffset))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedColor))
    }

    func testDisplayListColorFilterPayloadParticipatesInSurfaceMatching() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let red = Color.red.resolve(in: EnvironmentValues())
        let blue = Color.blue.resolve(in: EnvironmentValues())

        var brightness = DisplayList()
        brightness.appendColorFilterItem(
            bounds: bounds,
            filter: DisplayList.ItemRecord.ColorFilterRecord(
                kind: .brightness,
                amount: 0.2
            )
        ) { _ in }

        var sameBrightness = DisplayList()
        sameBrightness.appendColorFilterItem(
            bounds: bounds,
            filter: DisplayList.ItemRecord.ColorFilterRecord(
                kind: .brightness,
                amount: 0.2
            )
        ) { _ in }

        var changedBrightness = DisplayList()
        changedBrightness.appendColorFilterItem(
            bounds: bounds,
            filter: DisplayList.ItemRecord.ColorFilterRecord(
                kind: .brightness,
                amount: 0.4
            )
        ) { _ in }

        var contrastWithSameAmount = DisplayList()
        contrastWithSameAmount.appendColorFilterItem(
            bounds: bounds,
            filter: DisplayList.ItemRecord.ColorFilterRecord(
                kind: .contrast,
                amount: 0.2
            )
        ) { _ in }

        var multiplyRed = DisplayList()
        multiplyRed.appendColorFilterItem(
            bounds: bounds,
            filter: DisplayList.ItemRecord.ColorFilterRecord(
                kind: .colorMultiply,
                amount: 1,
                color: red
            )
        ) { _ in }

        var sameMultiplyRed = DisplayList()
        sameMultiplyRed.appendColorFilterItem(
            bounds: bounds,
            filter: DisplayList.ItemRecord.ColorFilterRecord(
                kind: .colorMultiply,
                amount: 1,
                color: red
            )
        ) { _ in }

        var multiplyBlue = DisplayList()
        multiplyBlue.appendColorFilterItem(
            bounds: bounds,
            filter: DisplayList.ItemRecord.ColorFilterRecord(
                kind: .colorMultiply,
                amount: 1,
                color: blue
            )
        ) { _ in }

        var matrix = ColorMatrix()
        matrix.r1 = 0.5
        matrix.g2 = 0.75
        var colorMatrix = DisplayList()
        colorMatrix.appendColorFilterItem(
            bounds: bounds,
            filter: DisplayList.ItemRecord.ColorFilterRecord(
                kind: .colorMatrix,
                amount: 1,
                matrix: matrix
            )
        ) { _ in }

        var sameColorMatrix = DisplayList()
        sameColorMatrix.appendColorFilterItem(
            bounds: bounds,
            filter: DisplayList.ItemRecord.ColorFilterRecord(
                kind: .colorMatrix,
                amount: 1,
                matrix: matrix
            )
        ) { _ in }

        var changedMatrix = matrix
        changedMatrix.b3 = 0.25
        var changedColorMatrix = DisplayList()
        changedColorMatrix.appendColorFilterItem(
            bounds: bounds,
            filter: DisplayList.ItemRecord.ColorFilterRecord(
                kind: .colorMatrix,
                amount: 1,
                matrix: changedMatrix
            )
        ) { _ in }

        XCTAssertEqual(brightness.itemRecords.first?.kind, .effect)
        XCTAssertEqual(brightness.itemRecords.first?.effectKind, .colorFilter)
        XCTAssertEqual(brightness.itemRecords.first?.colorFilter?.kind, .brightness)
        XCTAssertEqual(brightness.itemRecords.first?.colorFilter?.amount, 0.2)
        XCTAssertNil(brightness.itemRecords.first?.colorFilter?.color)
        XCTAssertEqual(multiplyRed.itemRecords.first?.colorFilter?.kind, .colorMultiply)
        XCTAssertEqual(multiplyRed.itemRecords.first?.colorFilter?.color, red)
        XCTAssertEqual(colorMatrix.itemRecords.first?.colorFilter?.kind, .colorMatrix)
        XCTAssertEqual(colorMatrix.itemRecords.first?.colorFilter?.matrix, matrix)
        XCTAssertTrue(brightness.hasSameInterpolationSurface(as: sameBrightness))
        XCTAssertFalse(brightness.hasSameInterpolationSurface(as: changedBrightness))
        XCTAssertFalse(brightness.hasSameInterpolationSurface(as: contrastWithSameAmount))
        XCTAssertTrue(multiplyRed.hasSameInterpolationSurface(as: sameMultiplyRed))
        XCTAssertFalse(multiplyRed.hasSameInterpolationSurface(as: multiplyBlue))
        XCTAssertTrue(colorMatrix.hasSameInterpolationSurface(as: sameColorMatrix))
        XCTAssertFalse(colorMatrix.hasSameInterpolationSurface(as: changedColorMatrix))
    }

    func testBlendModeEffectWrapsDisplayListWithGraphicsContextBlendMode() throws {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let source = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: bounds,
            itemKind: .shapeFill
        )

        let multiplied = try displayList(
            applying: _BlendModeEffect(blendMode: .multiply),
            to: source
        )
        XCTAssertEqual(multiplied.items.count, 1)
        XCTAssertEqual(multiplied.itemRecords.first?.kind, .effect)
        XCTAssertEqual(multiplied.itemRecords.first?.effectKind, .blendMode)
        XCTAssertEqual(multiplied.itemRecords.first?.blendMode, .multiply)
        XCTAssertEqual(multiplied.itemRecords.first?.bounds, bounds)

        let normal = try displayList(
            applying: _BlendModeEffect(blendMode: .normal),
            to: source
        )
        XCTAssertEqual(normal.itemRecords.first?.kind, .shapeFill)
        XCTAssertNil(normal.itemRecords.first?.effectKind)
        XCTAssertNil(normal.itemRecords.first?.blendMode)
    }

    func testShadowEffectWrapsDisplayListWithGraphicsContextShadow() throws {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let source = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: bounds,
            itemKind: .shapeFill
        )
        let red = Color.red.resolve(in: EnvironmentValues())

        let shadowed = try displayList(
            applying: _ShadowEffect(
                color: .red,
                radius: 2,
                offset: CGSize(width: 3, height: 4)
            ),
            to: source
        )

        XCTAssertEqual(shadowed.items.count, 1)
        XCTAssertEqual(shadowed.itemRecords.first?.kind, .effect)
        XCTAssertEqual(shadowed.itemRecords.first?.effectKind, .shadow)
        XCTAssertEqual(shadowed.itemRecords.first?.shadow?.color, red)
        XCTAssertEqual(shadowed.itemRecords.first?.shadow?.radius, 2)
        XCTAssertEqual(shadowed.itemRecords.first?.shadow?.offset, CGSize(width: 3, height: 4))
        XCTAssertEqual(shadowed.itemRecords.first?.bounds, bounds)

        let transparent = try displayList(
            applying: _ShadowEffect(
                color: .clear,
                radius: 2,
                offset: CGSize(width: 3, height: 4)
            ),
            to: source
        )
        XCTAssertEqual(transparent.itemRecords.first?.kind, .shapeFill)
        XCTAssertNil(transparent.itemRecords.first?.effectKind)
        XCTAssertNil(transparent.itemRecords.first?.shadow)
    }

    func testColorFilterEffectsWrapDisplayListWithGraphicsContextFilters() throws {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let source = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: bounds,
            itemKind: .shapeFill
        )

        let brightened = try displayList(
            applying: _BrightnessEffect(amount: 0.2),
            to: source
        )
        XCTAssertEqual(brightened.items.count, 1)
        XCTAssertEqual(brightened.itemRecords.first?.kind, .effect)
        XCTAssertEqual(brightened.itemRecords.first?.effectKind, .colorFilter)
        XCTAssertEqual(brightened.itemRecords.first?.colorFilter?.kind, .brightness)
        XCTAssertEqual(brightened.itemRecords.first?.colorFilter?.amount, 0.2)
        XCTAssertEqual(brightened.itemRecords.first?.bounds, bounds)

        let identityBrightness = try displayList(
            applying: _BrightnessEffect(amount: 0),
            to: source
        )
        XCTAssertEqual(identityBrightness.itemRecords.first?.kind, .shapeFill)
        XCTAssertNil(identityBrightness.itemRecords.first?.effectKind)
        XCTAssertNil(identityBrightness.itemRecords.first?.colorFilter)

        let hueRotated = try displayList(
            applying: _HueRotationEffect(angle: .radians(.pi / 2)),
            to: source
        )
        let hueRecord = try XCTUnwrap(hueRotated.itemRecords.first?.colorFilter)
        XCTAssertEqual(hueRecord.kind, .hueRotation)
        XCTAssertEqual(hueRecord.amount, .pi / 2, accuracy: 0.000001)

        let inverted = try displayList(
            applying: _ColorInvertEffect(),
            to: source
        )
        XCTAssertEqual(inverted.itemRecords.first?.colorFilter?.kind, .colorInvert)

        let luminanceToAlpha = try displayList(
            applying: _LuminanceToAlphaEffect(),
            to: source
        )
        XCTAssertEqual(luminanceToAlpha.itemRecords.first?.colorFilter?.kind, .luminanceToAlpha)

        var matrix = _ColorMatrix()
        matrix.m11 = 0.5
        matrix.m22 = 0.75
        let matrixFiltered = try displayList(
            applying: _ColorMatrixEffect(matrix: matrix),
            to: source
        )
        XCTAssertEqual(matrixFiltered.itemRecords.first?.kind, .effect)
        XCTAssertEqual(matrixFiltered.itemRecords.first?.effectKind, .colorFilter)
        XCTAssertEqual(matrixFiltered.itemRecords.first?.colorFilter?.kind, .colorMatrix)
        XCTAssertEqual(matrixFiltered.itemRecords.first?.colorFilter?.matrix, matrix.colorMatrix)

        let identityMatrix = try displayList(
            applying: _ColorMatrixEffect(matrix: _ColorMatrix()),
            to: source
        )
        XCTAssertEqual(identityMatrix.itemRecords.first?.kind, .shapeFill)
        XCTAssertNil(identityMatrix.itemRecords.first?.effectKind)
        XCTAssertNil(identityMatrix.itemRecords.first?.colorFilter)

        let red = Color.red.resolve(in: EnvironmentValues())
        let multiplied = try displayList(
            applying: _ColorMultiplyEffect._Resolved(color: red),
            to: source
        )
        XCTAssertEqual(multiplied.itemRecords.first?.kind, .effect)
        XCTAssertEqual(multiplied.itemRecords.first?.effectKind, .colorFilter)
        XCTAssertEqual(multiplied.itemRecords.first?.colorFilter?.kind, .colorMultiply)
        XCTAssertEqual(multiplied.itemRecords.first?.colorFilter?.color, red)

        let white = Color.white.resolve(in: EnvironmentValues())
        let identityMultiply = try displayList(
            applying: _ColorMultiplyEffect._Resolved(color: white),
            to: source
        )
        XCTAssertEqual(identityMultiply.itemRecords.first?.kind, .shapeFill)
        XCTAssertNil(identityMultiply.itemRecords.first?.effectKind)
        XCTAssertNil(identityMultiply.itemRecords.first?.colorFilter)
    }

    func testDisplayListEffectItemRecordKindParticipatesInSurfaceMatching() {
        var layer = DisplayList.InterpolatorLayer()
        let opacity = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            itemKind: .effect,
            itemEffectKind: .opacity
        )
        let sameOpacity = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            itemKind: .effect,
            itemEffectKind: .opacity
        )
        let blur = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            itemKind: .effect,
            itemEffectKind: .blur
        )

        layer.setDisplayList(
            opacity,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        layer.setDisplayList(
            sameOpacity,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        XCTAssertEqual(layer.contents.displayList.itemRecords.first?.effectKind, .opacity)

        layer.setDisplayList(
            blur,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        XCTAssertEqual(layer.contents.displayList.itemRecords.first?.kind, .effect)
        XCTAssertEqual(layer.contents.displayList.itemRecords.first?.effectKind, .blur)
        XCTAssertEqual(layer.removedCount, 0)
    }

    func testDisplayListEffectRecordsParticipateInSurfaceMatching() {
        var layer = DisplayList.InterpolatorLayer()
        let contents = makeDisplayList(debugItemCount: 0, itemCount: 1, itemKind: .shapeFill)
        let opacityEffect = DisplayList.effect(
            .contentTransition(ContentTransition.State(transition: .opacity)),
            contents: contents
        )
        let sameOpacityEffect = DisplayList.effect(
            .contentTransition(ContentTransition.State(transition: .opacity)),
            contents: contents
        )
        let identityEffect = DisplayList.effect(
            .contentTransition(ContentTransition.State(transition: .identity)),
            contents: contents
        )

        layer.setDisplayList(
            opacityEffect,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        layer.setDisplayList(
            sameOpacityEffect,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        XCTAssertEqual(layer.contents.displayList.effects.count, 1)

        layer.setDisplayList(
            identityEffect,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        XCTAssertEqual(layer.contents.displayList.effects.count, 1)
        XCTAssertEqual(layer.removedCount, 0)
        switch layer.contents.displayList.effects.first?.effect {
        case let .contentTransition(state):
            XCTAssertEqual(state.transition, .identity)
        default:
            XCTFail("Expected content-transition effect record.")
        }
    }

    func testRBDisplayListInterpolatorRecursivelyInterpolatesMatchingEffectContents() throws {
        let state = ContentTransition.State(transition: .opacity)
        let sourceContents = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20),
            itemKind: .shapeFill
        )
        let targetContents = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40),
            itemKind: .shapeFill
        )
        let source = DisplayList.effect(.contentTransition(state), contents: sourceContents)
        let target = DisplayList.effect(.contentTransition(state), contents: targetContents)
        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: state.transition.rbTransition]
        )

        XCTAssertEqual(interpolator.activeDuration, 1)
        XCTAssertEqual(
            interpolator.boundingRect(withProgress: 0.5),
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )

        let midpoint = interpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(midpoint.items.count, 0)
        XCTAssertEqual(midpoint.effects.count, 1)

        let effectItem = try XCTUnwrap(midpoint.effects.first)
        switch effectItem.effect {
        case let .contentTransition(outputState):
            XCTAssertEqual(outputState, state)
        default:
            XCTFail("Expected content-transition effect record.")
        }

        XCTAssertEqual(effectItem.contents.items.count, 1)
        XCTAssertEqual(effectItem.contents.itemRecords.first?.kind, .effect)
        XCTAssertEqual(effectItem.contents.itemRecords.first?.effectKind, .crossFade)
        XCTAssertEqual(effectItem.contents.itemRecords.first?.sourceFraction, 0.5)
        XCTAssertEqual(effectItem.contents.itemRecords.first?.targetFraction, 0.5)
        XCTAssertEqual(
            effectItem.contents.interpolationBounds,
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
    }

    func testRBDisplayListInterpolatorEndpointPreservesTargetEffectFallback() throws {
        let sourceState = ContentTransition.State(transition: .opacity)
        let targetState = ContentTransition.State(transition: .identity)
        var source = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20),
            itemKind: .shapeFill
        )
        source.appendEffect(
            .contentTransition(sourceState),
            contents: makeDisplayList(
                debugItemCount: 0,
                itemCount: 1,
                bounds: CGRect(x: 5, y: 5, width: 10, height: 10),
                itemKind: .shapeFill
            )
        )
        var target = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40),
            itemKind: .shapeFill
        )
        target.appendEffect(
            .contentTransition(targetState),
            contents: makeDisplayList(
                debugItemCount: 0,
                itemCount: 1,
                bounds: CGRect(x: 30, y: 15, width: 20, height: 25),
                itemKind: .shapeFill
            )
        )

        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: sourceState.transition.rbTransition]
        )
        let sourceEndpoint = interpolator.copyContents(withProgress: 0)
        let targetEndpoint = interpolator.copyContents(withProgress: 1)

        switch sourceEndpoint.effects.first?.effect {
        case let .contentTransition(state):
            XCTAssertEqual(state, sourceState)
        default:
            XCTFail("Expected source content-transition effect.")
        }
        switch targetEndpoint.effects.first?.effect {
        case let .contentTransition(state):
            XCTAssertEqual(state, targetState)
        default:
            XCTFail("Expected target content-transition effect.")
        }
        XCTAssertEqual(targetEndpoint.effects.first?.contents.interpolationBounds, CGRect(x: 30, y: 15, width: 20, height: 25))
    }

    func testRBDisplayListInterpolatorKeepsNestedEffectCarrierForAnimationIndexTransition() throws {
        let state = ContentTransition.State(transition: .opacity)
        let sourceContents = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20),
            itemKind: .shapeFill
        )
        let targetContents = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40),
            itemKind: .shapeFill
        )
        let source = DisplayList.effect(.contentTransition(state), contents: sourceContents)
        let target = DisplayList.effect(.contentTransition(state), contents: targetContents)

        let baseline = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: state.transition.rbTransition]
        )

        let animationIndexTransition = RBTransition()
        animationIndexTransition.method = ContentTransition.Method.diff.method
        let animationIndexEffect = RBTransitionEffect()
        animationIndexEffect.type = ContentTransition.EffectType.opacity.type
        animationIndexEffect.events = 3
        animationIndexEffect.animationIndex = 1
        animationIndexTransition.addEffect(animationIndexEffect)

        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: animationIndexTransition]
        )

        XCTAssertEqual(interpolator.activeDuration, baseline.activeDuration)
        XCTAssertEqual(interpolator.maxAbsoluteVelocity(withProgress: 0.5), 0)
        XCTAssertEqual(interpolator.boundingRect(withProgress: 0), baseline.boundingRect(withProgress: 0))
        XCTAssertEqual(interpolator.boundingRect(withProgress: 0.5), baseline.boundingRect(withProgress: 0.5))
        XCTAssertEqual(interpolator.boundingRect(withProgress: 1), baseline.boundingRect(withProgress: 1))

        let baselineMidpoint = try XCTUnwrap(baseline.copyContents(withProgress: 0.5).effects.first)
        let midpoint = try XCTUnwrap(interpolator.copyContents(withProgress: 0.5).effects.first)
        XCTAssertEqual(midpoint.contents.interpolationBounds, baselineMidpoint.contents.interpolationBounds)
        XCTAssertEqual(midpoint.contents.itemRecords, baselineMidpoint.contents.itemRecords)
    }

    func testRBDisplayListInterpolatorUsesItemCommandBoundsForMultiItemInterpolation() {
        let source = makeDisplayList(
            itemBounds: [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: 15, y: 5, width: 10, height: 15),
            ],
            itemKind: .shapeFill
        )
        let target = makeDisplayList(
            itemBounds: [
                CGRect(x: 20, y: 10, width: 20, height: 20),
                CGRect(x: 5, y: 25, width: 15, height: 10),
            ],
            itemKind: .shapeFill
        )
        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: ContentTransition.opacity.rbTransition]
        )

        XCTAssertEqual(interpolator.boundingRect(withProgress: 0), CGRect(x: 0, y: 0, width: 25, height: 20))
        XCTAssertEqual(interpolator.boundingRect(withProgress: 0.5), CGRect(x: 10, y: 5, width: 15, height: 22.5))
        XCTAssertEqual(interpolator.boundingRect(withProgress: 1), CGRect(x: 5, y: 10, width: 35, height: 25))

        let sourceEndpoint = interpolator.copyContents(withProgress: 0)
        XCTAssertEqual(sourceEndpoint.items.count, 2)
        XCTAssertEqual(sourceEndpoint.itemRecords.map(\.kind), [.effect, .effect])
        XCTAssertEqual(sourceEndpoint.itemRecords.map(\.effectKind), [.crossFade, .crossFade])
        XCTAssertEqual(sourceEndpoint.itemRecords.map(\.sourceFraction), [0, 0])
        XCTAssertEqual(sourceEndpoint.itemRecords.map(\.targetFraction), [0, 0])
        XCTAssertEqual(
            sourceEndpoint.itemRecords.map(\.bounds),
            [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: 15, y: 5, width: 10, height: 15),
            ]
        )
        XCTAssertEqual(sourceEndpoint.itemCommands.map(\.bounds), sourceEndpoint.itemRecords.map(\.bounds))
        XCTAssertEqual(sourceEndpoint.interpolationBounds, CGRect(x: 0, y: 0, width: 25, height: 20))

        let midpoint = interpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(midpoint.items.count, 2)
        XCTAssertEqual(midpoint.itemRecords.map(\.kind), [.effect, .effect])
        XCTAssertEqual(midpoint.itemRecords.map(\.effectKind), [.crossFade, .crossFade])
        XCTAssertEqual(midpoint.itemRecords.map(\.sourceFraction), [0.5, 0.5])
        XCTAssertEqual(midpoint.itemRecords.map(\.targetFraction), [0.5, 0.5])
        XCTAssertEqual(
            midpoint.itemRecords.map(\.bounds),
            [
                CGRect(x: 10, y: 5, width: 15, height: 15),
                CGRect(x: 10, y: 15, width: 12.5, height: 12.5),
            ]
        )
        XCTAssertEqual(midpoint.itemCommands.map(\.bounds), midpoint.itemRecords.map(\.bounds))
        XCTAssertEqual(midpoint.interpolationBounds, CGRect(x: 10, y: 5, width: 15, height: 22.5))

        let targetEndpoint = interpolator.copyContents(withProgress: 1)
        XCTAssertEqual(targetEndpoint.items.count, 2)
        XCTAssertEqual(targetEndpoint.itemRecords.map(\.kind), [.effect, .effect])
        XCTAssertEqual(targetEndpoint.itemRecords.map(\.effectKind), [.crossFade, .crossFade])
        XCTAssertEqual(targetEndpoint.itemRecords.map(\.sourceFraction), [1, 1])
        XCTAssertEqual(targetEndpoint.itemRecords.map(\.targetFraction), [1, 1])
        XCTAssertEqual(
            targetEndpoint.itemRecords.map(\.bounds),
            [
                CGRect(x: 20, y: 10, width: 20, height: 20),
                CGRect(x: 5, y: 25, width: 15, height: 10),
            ]
        )
        XCTAssertEqual(targetEndpoint.itemCommands.map(\.bounds), targetEndpoint.itemRecords.map(\.bounds))
        XCTAssertEqual(targetEndpoint.interpolationBounds, CGRect(x: 5, y: 10, width: 35, height: 25))

        let reversedTarget = makeDisplayList(
            itemBounds: [
                CGRect(x: 5, y: 25, width: 15, height: 10),
                CGRect(x: 20, y: 10, width: 20, height: 20),
            ],
            itemKind: .shapeFill
        )
        let reversedTargetInterpolator = RBDisplayListInterpolator(
            from: source,
            to: reversedTarget,
            options: [.transition: ContentTransition.opacity.rbTransition]
        )
        XCTAssertEqual(
            reversedTargetInterpolator.boundingRect(withProgress: 0.5),
            CGRect(x: 2.5, y: 7.5, width: 30, height: 17.5)
        )

        let reversedTargetMidpoint = reversedTargetInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(
            reversedTargetMidpoint.itemRecords.map(\.bounds),
            [
                CGRect(x: 2.5, y: 12.5, width: 12.5, height: 10),
                CGRect(x: 17.5, y: 7.5, width: 15, height: 17.5),
            ]
        )
        XCTAssertEqual(reversedTargetMidpoint.interpolationBounds, CGRect(x: 2.5, y: 7.5, width: 30, height: 17.5))

        let sourceExtra = makeDisplayList(
            itemBounds: [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: -40, y: 30, width: 5, height: 5),
            ],
            itemKind: .shapeFill
        )
        let singleTarget = makeDisplayList(
            itemBounds: [
                CGRect(x: 20, y: 10, width: 20, height: 20),
            ],
            itemKind: .shapeFill
        )
        let sourceExtraInterpolator = RBDisplayListInterpolator(
            from: sourceExtra,
            to: singleTarget,
            options: [.transition: ContentTransition.opacity.rbTransition]
        )
        XCTAssertEqual(
            sourceExtraInterpolator.boundingRect(withProgress: 0.5),
            CGRect(x: -40, y: 5, width: 65, height: 30)
        )
        XCTAssertEqual(
            sourceExtraInterpolator.boundingRect(withProgress: 0),
            CGRect(x: -40, y: 0, width: 50, height: 35)
        )
        XCTAssertEqual(
            sourceExtraInterpolator.boundingRect(withProgress: 1),
            CGRect(x: -40, y: 10, width: 80, height: 25)
        )

        let sourceExtraStart = sourceExtraInterpolator.copyContents(withProgress: 0)
        XCTAssertEqual(
            sourceExtraStart.itemRecords.map(\.bounds),
            [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: -40, y: 30, width: 5, height: 5),
            ]
        )
        XCTAssertEqual(sourceExtraStart.itemRecords.map(\.sourceFraction), [0, 0])
        XCTAssertEqual(sourceExtraStart.itemRecords.map(\.targetFraction), [0, 0])
        XCTAssertEqual(sourceExtraStart.interpolationBounds, CGRect(x: -40, y: 0, width: 50, height: 35))

        let sourceExtraMidpoint = sourceExtraInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(
            sourceExtraMidpoint.itemRecords.map(\.bounds),
            [
                CGRect(x: 10, y: 5, width: 15, height: 15),
                CGRect(x: -40, y: 30, width: 5, height: 5),
            ]
        )
        XCTAssertEqual(sourceExtraMidpoint.itemRecords.map(\.sourceFraction), [0.5, 0.5])
        XCTAssertEqual(sourceExtraMidpoint.itemRecords.map(\.targetFraction), [0.5, 0])
        XCTAssertEqual(sourceExtraMidpoint.interpolationBounds, CGRect(x: -40, y: 5, width: 65, height: 30))

        let sourceExtraEnd = sourceExtraInterpolator.copyContents(withProgress: 1)
        XCTAssertEqual(
            sourceExtraEnd.itemRecords.map(\.bounds),
            [
                CGRect(x: 20, y: 10, width: 20, height: 20),
                CGRect(x: -40, y: 30, width: 5, height: 5),
            ]
        )
        XCTAssertEqual(sourceExtraEnd.itemRecords.map(\.sourceFraction), [1, 1])
        XCTAssertEqual(sourceExtraEnd.itemRecords.map(\.targetFraction), [1, 0])
        XCTAssertEqual(sourceExtraEnd.interpolationBounds, CGRect(x: -40, y: 10, width: 80, height: 25))

        let targetExtraInterpolator = RBDisplayListInterpolator(
            from: makeDisplayList(
                itemBounds: [CGRect(x: 0, y: 0, width: 10, height: 10)],
                itemKind: .shapeFill
            ),
            to: target,
            options: [.transition: ContentTransition.opacity.rbTransition]
        )
        XCTAssertEqual(
            targetExtraInterpolator.boundingRect(withProgress: 0.5),
            CGRect(x: 5, y: 5, width: 20, height: 30)
        )
        XCTAssertEqual(
            targetExtraInterpolator.boundingRect(withProgress: 0),
            CGRect(x: 0, y: 0, width: 20, height: 35)
        )
        XCTAssertEqual(
            targetExtraInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 5, y: 10, width: 35, height: 25)
        )

        let targetExtraStart = targetExtraInterpolator.copyContents(withProgress: 0)
        XCTAssertEqual(
            targetExtraStart.itemRecords.map(\.bounds),
            [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: 5, y: 25, width: 15, height: 10),
            ]
        )
        XCTAssertEqual(targetExtraStart.itemRecords.map(\.sourceFraction), [0, 0])
        XCTAssertEqual(targetExtraStart.itemRecords.map(\.targetFraction), [0, 0])
        XCTAssertEqual(targetExtraStart.interpolationBounds, CGRect(x: 0, y: 0, width: 20, height: 35))

        let targetExtraMidpoint = targetExtraInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(
            targetExtraMidpoint.itemRecords.map(\.bounds),
            [
                CGRect(x: 10, y: 5, width: 15, height: 15),
                CGRect(x: 5, y: 25, width: 15, height: 10),
            ]
        )
        XCTAssertEqual(targetExtraMidpoint.itemRecords.map(\.sourceFraction), [0.5, 0])
        XCTAssertEqual(targetExtraMidpoint.itemRecords.map(\.targetFraction), [0.5, 0.5])
        XCTAssertEqual(targetExtraMidpoint.interpolationBounds, CGRect(x: 5, y: 5, width: 20, height: 30))

        let targetExtraEnd = targetExtraInterpolator.copyContents(withProgress: 1)
        XCTAssertEqual(
            targetExtraEnd.itemRecords.map(\.bounds),
            [
                CGRect(x: 20, y: 10, width: 20, height: 20),
                CGRect(x: 5, y: 25, width: 15, height: 10),
            ]
        )
        XCTAssertEqual(targetExtraEnd.itemRecords.map(\.sourceFraction), [1, 0])
        XCTAssertEqual(targetExtraEnd.itemRecords.map(\.targetFraction), [1, 1])
        XCTAssertEqual(targetExtraEnd.interpolationBounds, CGRect(x: 5, y: 10, width: 35, height: 25))
    }

    func testRBDisplayListInterpolatorKeepsDebugCountMismatchOnFallbackBounds() {
        var source = DisplayList()
        source.appendDebugItem(bounds: CGRect(x: 0, y: 0, width: 10, height: 10)) { _ in }
        source.appendDebugItem(bounds: CGRect(x: -40, y: 30, width: 5, height: 5)) { _ in }

        var target = DisplayList()
        target.appendDebugItem(bounds: CGRect(x: 20, y: 10, width: 20, height: 20)) { _ in }

        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: ContentTransition.opacity.rbTransition]
        )
        let expectedMidpointBounds = CGRect(x: -10, y: 5, width: 35, height: 27.5)

        XCTAssertEqual(interpolator.boundingRect(withProgress: 0.5), expectedMidpointBounds)
        XCTAssertEqual(interpolator.copyContents(withProgress: 0).debugItems.count, 2)
        XCTAssertEqual(interpolator.copyContents(withProgress: 1).debugItems.count, 1)

        let midpoint = interpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(midpoint.items.count, 0)
        XCTAssertEqual(midpoint.debugItems.count, 1)
        XCTAssertEqual(midpoint.debugItemRecords.map(\.bounds), [expectedMidpointBounds])
        XCTAssertEqual(midpoint.interpolationBounds, expectedMidpointBounds)
    }

    func testRBDisplayListInterpolatorUsesNestedEffectItemCommandBounds() throws {
        let state = ContentTransition.State(transition: .opacity)
        let source = DisplayList.effect(
            .contentTransition(state),
            contents: makeDisplayList(
                itemBounds: [
                    CGRect(x: 0, y: 0, width: 10, height: 10),
                    CGRect(x: 15, y: 5, width: 10, height: 15),
                ],
                itemKind: .shapeFill
            )
        )
        let target = DisplayList.effect(
            .contentTransition(state),
            contents: makeDisplayList(
                itemBounds: [
                    CGRect(x: 20, y: 10, width: 20, height: 20),
                    CGRect(x: 5, y: 25, width: 15, height: 10),
                ],
                itemKind: .shapeFill
            )
        )
        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: state.transition.rbTransition]
        )

        XCTAssertEqual(interpolator.boundingRect(withProgress: 0.5), CGRect(x: 10, y: 5, width: 15, height: 22.5))

        let midpoint = interpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(midpoint.interpolationBounds, CGRect(x: 10, y: 5, width: 15, height: 22.5))

        let effect = try XCTUnwrap(midpoint.effects.first)
        XCTAssertEqual(effect.contents.items.count, 2)
        XCTAssertEqual(effect.contents.interpolationBounds, CGRect(x: 10, y: 5, width: 15, height: 22.5))
        XCTAssertEqual(
            effect.contents.itemRecords.map(\.bounds),
            [
                CGRect(x: 10, y: 5, width: 15, height: 15),
                CGRect(x: 10, y: 15, width: 12.5, height: 12.5),
            ]
        )
    }

    func testDisplayListModifierWrappersPreserveNestedContentTransitionEffects() throws {
        let source = makeEffectCarrierDisplayList()

        let opacityOutput = try displayList(
            applying: _OpacityEffect(opacity: 0.5),
            to: source
        )
        let opacityContents = try contentTransitionContents(in: opacityOutput)
        XCTAssertEqual(opacityContents.itemRecords.first?.kind, .effect)
        XCTAssertEqual(opacityContents.itemRecords.first?.effectKind, .opacity)
        XCTAssertEqual(opacityContents.itemRecords.first?.opacity, 0.5)

        let blurOutput = try displayList(
            applying: _BlurEffect(radius: 2, opaque: false),
            to: source
        )
        let blurContents = try contentTransitionContents(in: blurOutput)
        XCTAssertEqual(blurContents.itemRecords.first?.kind, .effect)
        XCTAssertEqual(blurContents.itemRecords.first?.effectKind, .blur)
        XCTAssertEqual(blurContents.itemRecords.first?.blurRadius, 2)
        XCTAssertEqual(blurContents.itemRecords.first?.blurIsOpaque, false)

        let geometryOutput = try displayList(
            applying: _OffsetEffect(offset: CGSize(width: 3, height: 4)),
            to: source
        )
        let geometryContents = try contentTransitionContents(in: geometryOutput)
        XCTAssertEqual(geometryContents.itemRecords.first?.kind, .effect)
        XCTAssertEqual(geometryContents.itemRecords.first?.effectKind, .geometry)
        let transform = try XCTUnwrap(geometryContents.itemRecords.first?.affineTransform)
        XCTAssertEqual(transform.tx, 3, accuracy: 0.000001)
        XCTAssertEqual(transform.ty, 4, accuracy: 0.000001)
        XCTAssertEqual(
            geometryContents.interpolationBounds,
            CGRect(x: 3, y: 4, width: 10, height: 10)
        )

        let blendModeOutput = try displayList(
            applying: _BlendModeEffect(blendMode: .multiply),
            to: source
        )
        let blendModeContents = try contentTransitionContents(in: blendModeOutput)
        XCTAssertEqual(blendModeContents.itemRecords.first?.kind, .effect)
        XCTAssertEqual(blendModeContents.itemRecords.first?.effectKind, .blendMode)
        XCTAssertEqual(blendModeContents.itemRecords.first?.blendMode, .multiply)

        let shadowOutput = try displayList(
            applying: _ShadowEffect(
                color: .red,
                radius: 2,
                offset: CGSize(width: 3, height: 4)
            ),
            to: source
        )
        let shadowContents = try contentTransitionContents(in: shadowOutput)
        XCTAssertEqual(shadowContents.itemRecords.first?.kind, .effect)
        XCTAssertEqual(shadowContents.itemRecords.first?.effectKind, .shadow)
        XCTAssertEqual(shadowContents.itemRecords.first?.shadow?.radius, 2)
        XCTAssertEqual(shadowContents.itemRecords.first?.shadow?.offset, CGSize(width: 3, height: 4))

        let brightnessOutput = try displayList(
            applying: _BrightnessEffect(amount: 0.2),
            to: source
        )
        let brightnessContents = try contentTransitionContents(in: brightnessOutput)
        XCTAssertEqual(brightnessContents.itemRecords.first?.kind, .effect)
        XCTAssertEqual(brightnessContents.itemRecords.first?.effectKind, .colorFilter)
        XCTAssertEqual(brightnessContents.itemRecords.first?.colorFilter?.kind, .brightness)
        XCTAssertEqual(brightnessContents.itemRecords.first?.colorFilter?.amount, 0.2)
    }

    func testDisplayListModifierPayloadsParticipateInSurfaceMatching() throws {
        let source = makeEffectCarrierDisplayList()

        let opacityA = try contentTransitionContents(in: displayList(
            applying: _OpacityEffect(opacity: 0.4),
            to: source
        ))
        let opacityB = try contentTransitionContents(in: displayList(
            applying: _OpacityEffect(opacity: 0.6),
            to: source
        ))
        XCTAssertFalse(opacityA.hasSameInterpolationSurface(as: opacityB))

        let blurA = try contentTransitionContents(in: displayList(
            applying: _BlurEffect(radius: 2, opaque: false),
            to: source
        ))
        let blurB = try contentTransitionContents(in: displayList(
            applying: _BlurEffect(radius: 4, opaque: false),
            to: source
        ))
        XCTAssertFalse(blurA.hasSameInterpolationSurface(as: blurB))

        let opaqueBlur = try contentTransitionContents(in: displayList(
            applying: _BlurEffect(radius: 2, opaque: true),
            to: source
        ))
        XCTAssertFalse(blurA.hasSameInterpolationSurface(as: opaqueBlur))

        let multiplyBlend = try contentTransitionContents(in: displayList(
            applying: _BlendModeEffect(blendMode: .multiply),
            to: source
        ))
        let screenBlend = try contentTransitionContents(in: displayList(
            applying: _BlendModeEffect(blendMode: .screen),
            to: source
        ))
        XCTAssertFalse(multiplyBlend.hasSameInterpolationSurface(as: screenBlend))

        let shadowA = try contentTransitionContents(in: displayList(
            applying: _ShadowEffect(
                color: .red,
                radius: 2,
                offset: CGSize(width: 3, height: 4)
            ),
            to: source
        ))
        let shadowB = try contentTransitionContents(in: displayList(
            applying: _ShadowEffect(
                color: .red,
                radius: 4,
                offset: CGSize(width: 3, height: 4)
            ),
            to: source
        ))
        XCTAssertFalse(shadowA.hasSameInterpolationSurface(as: shadowB))

        let brightnessA = try contentTransitionContents(in: displayList(
            applying: _BrightnessEffect(amount: 0.2),
            to: source
        ))
        let brightnessB = try contentTransitionContents(in: displayList(
            applying: _BrightnessEffect(amount: 0.4),
            to: source
        ))
        XCTAssertFalse(brightnessA.hasSameInterpolationSurface(as: brightnessB))

        let redMultiply = try contentTransitionContents(in: displayList(
            applying: _ColorMultiplyEffect._Resolved(
                color: Color.red.resolve(in: EnvironmentValues())
            ),
            to: source
        ))
        let blueMultiply = try contentTransitionContents(in: displayList(
            applying: _ColorMultiplyEffect._Resolved(
                color: Color.blue.resolve(in: EnvironmentValues())
            ),
            to: source
        ))
        XCTAssertFalse(redMultiply.hasSameInterpolationSurface(as: blueMultiply))
    }

    func testRBDisplayListInterpolatorUsesSurfaceRecordsForChangeDetection() {
        let shape = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            itemKind: .shapeFill
        )
        let image = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            itemKind: .image
        )
        let transition = ContentTransition.opacity.rbTransition
        let itemInterpolator = RBDisplayListInterpolator(
            from: shape,
            to: image,
            options: [.transition: transition]
        )
        XCTAssertEqual(itemInterpolator.activeDuration, 1)

        let effectContents = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            itemKind: .shapeFill
        )
        let opacityEffect = DisplayList.effect(
            .contentTransition(ContentTransition.State(transition: .opacity)),
            contents: effectContents
        )
        let identityEffect = DisplayList.effect(
            .contentTransition(ContentTransition.State(transition: .identity)),
            contents: effectContents
        )
        let effectInterpolator = RBDisplayListInterpolator(
            from: opacityEffect,
            to: identityEffect,
            options: [.transition: transition]
        )
        XCTAssertEqual(effectInterpolator.activeDuration, 1)
    }

    func testDisplayListItemRecordsIgnoreEmptyBoundsForInterpolationBounds() {
        var list = DisplayList()
        list.appendItem(
            kind: .text,
            bounds: CGRect(x: 4, y: 5, width: 0, height: 10)
        ) { _ in }
        list.appendDebugItem(
            bounds: CGRect(x: 4, y: 5, width: 10, height: 0)
        ) { _ in }

        XCTAssertEqual(list.itemRecords.first?.kind, .text)
        XCTAssertNil(list.itemRecords.first?.bounds)
        XCTAssertNil(list.debugItemRecords.first?.bounds)
        XCTAssertNil(list.interpolationBounds)

        list.recordInterpolationBounds(.null)
        list.recordInterpolationBounds(CGRect(x: 4, y: 5, width: 0, height: 10))
        XCTAssertNil(list.interpolationBounds)

        list.recordInterpolationBounds(CGRect(x: 14, y: 15, width: -10, height: -5))
        XCTAssertEqual(list.interpolationBounds, CGRect(x: 4, y: 10, width: 10, height: 5))
    }

    func testInterpolatorAnimationAndEffectCarrierSurface() {
        let hash = StrongHash(words: (1, 2, 3, 4, 5))
        let animation = DisplayList.InterpolatorAnimation(value: hash, animation: .linear(duration: 0.25))
        XCTAssertEqual(animation.value, hash)
        XCTAssertNotNil(animation.animation)

        let group = DisplayList.InterpolatorGroup()
        switch DisplayList.Effect.interpolatorRoot(group, CGPoint(x: 1, y: 2), CGSize(width: 3, height: 4)) {
        case let .interpolatorRoot(storedGroup, origin, offset):
            XCTAssertTrue(storedGroup === group)
            XCTAssertEqual(origin, CGPoint(x: 1, y: 2))
            XCTAssertEqual(offset, CGSize(width: 3, height: 4))
        default:
            XCTFail("missing interpolator root carrier")
        }

        switch DisplayList.Effect.interpolatorLayer(group, 7) {
        case let .interpolatorLayer(storedGroup, serial):
            XCTAssertTrue(storedGroup === group)
            XCTAssertEqual(serial, 7)
        default:
            XCTFail("missing interpolator layer carrier")
        }

        switch DisplayList.Effect.interpolatorAnimation(animation) {
        case let .interpolatorAnimation(stored):
            XCTAssertEqual(stored.value, hash)
            XCTAssertNotNil(stored.animation)
        default:
            XCTFail("missing interpolator animation carrier")
        }
    }

    func testInterpolatorGroupClassSurface() {
        let group = DisplayList.InterpolatorGroup()
        XCTAssertTrue(group.maxDuration.isInfinite)
        XCTAssertTrue(group.nextUpdate(after: .zero).seconds.isInfinite)

        group.maxDuration = 0.25
        XCTAssertEqual(group.maxDuration, 0.25)

        let unary = DisplayList.UnaryInterpolatorGroup()
        let base: DisplayList.InterpolatorGroup = unary
        XCTAssertTrue(base === unary)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 0)

        unary.updateTime(Time(seconds: 1.25))
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 1.25)

        unary.maxDuration = 0.5
        unary.reset()
        XCTAssertTrue(unary.maxDuration.isInfinite)
        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertFalse(unary.supportsVariableFrameDuration)
    }

    func testDisplayListInterpolationBoundsSurface() {
        var first = makeDisplayList(
            debugItemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        let second = makeDisplayList(
            debugItemCount: 1,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40)
        )

        first.append(contentsOf: second)
        XCTAssertEqual(first.debugItems.count, 2)
        XCTAssertEqual(first.interpolationBounds, CGRect(x: 0, y: 0, width: 50, height: 45))
    }

    func testRBDisplayListInterpolatorCarrierSurface() {
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.transition.rawValue, "transition")
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.animation.rawValue, "animation")
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.animationSequencer.rawValue, "animationSequencer")
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.fadeInOutFraction.rawValue, "fadeInOutFraction")
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.colorSpace.rawValue, "colorSpace")
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.rasterizationScale.rawValue, "rasterizationscale")

        let from = makeDisplayList(
            debugItemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        let to = makeDisplayList(
            debugItemCount: 2,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40)
        )
        let opacity = ContentTransition.opacity.rbTransition
        let interpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [
                .transition: opacity,
                .rasterizationScale: Float(2),
            ]
        )

        XCTAssertEqual(interpolator.from.debugItems.count, 1)
        XCTAssertEqual(interpolator.to.debugItems.count, 2)
        XCTAssertTrue((interpolator.options[.transition] as? RBTransition) === opacity)
        XCTAssertEqual(interpolator.options[.rasterizationScale] as? Float, 2)
        XCTAssertEqual(interpolator.activeDuration, 1)
        XCTAssertFalse(interpolator.isIdentity)
        XCTAssertTrue(interpolator.onlyFades)
        XCTAssertEqual(interpolator.maxAbsoluteVelocity(withProgress: 0.5), 0)
        XCTAssertEqual(interpolator.boundingRect(withProgress: 0), CGRect(x: 0, y: 0, width: 10, height: 20))
        XCTAssertEqual(interpolator.boundingRect(withProgress: 0.5), CGRect(x: 10, y: 2.5, width: 20, height: 30))
        XCTAssertEqual(interpolator.boundingRect(withProgress: 1), CGRect(x: 20, y: 5, width: 30, height: 40))
        XCTAssertEqual(interpolator.copyContents(withProgress: 0).debugItems.count, 1)
        XCTAssertEqual(
            interpolator.copyContents(withProgress: 0.5).interpolationBounds,
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
        XCTAssertEqual(interpolator.copyContents(withProgress: 0.5).debugItems.count, 1)
        XCTAssertEqual(interpolator.contents(withProgress: 1).debugItems.count, 2)

        let drawableFrom = makeDisplayList(
            debugItemCount: 1,
            itemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        let drawableTo = makeDisplayList(
            debugItemCount: 2,
            itemCount: 1,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40)
        )
        let drawableInterpolator = RBDisplayListInterpolator(
            from: drawableFrom,
            to: drawableTo,
            options: [.transition: opacity]
        )
        let drawableMidpoint = drawableInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(drawableMidpoint.items.count, 1)
        XCTAssertEqual(drawableMidpoint.debugItems.count, 1)
        XCTAssertEqual(
            drawableMidpoint.interpolationBounds,
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
        XCTAssertEqual(drawableInterpolator.copyContents(withProgress: 0).items.count, 1)
        XCTAssertEqual(drawableInterpolator.copyContents(withProgress: 1).items.count, 1)

        let noTransitionInterpolator = RBDisplayListInterpolator(
            from: drawableFrom,
            to: drawableTo
        )
        XCTAssertEqual(noTransitionInterpolator.activeDuration, 1)
        XCTAssertFalse(noTransitionInterpolator.onlyFades)
        XCTAssertEqual(
            noTransitionInterpolator.boundingRect(withProgress: 0.5),
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
        XCTAssertEqual(
            noTransitionInterpolator.copyContents(withProgress: 0).itemRecords.first?.effectKind,
            .crossFade
        )
        XCTAssertEqual(
            noTransitionInterpolator.copyContents(withProgress: 0.5).interpolationBounds,
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
        XCTAssertEqual(
            noTransitionInterpolator.copyContents(withProgress: 1).itemRecords.first?.effectKind,
            .crossFade
        )

        let noTransitionSameObjectInterpolator = RBDisplayListInterpolator(
            from: drawableFrom,
            to: drawableFrom
        )
        XCTAssertEqual(noTransitionSameObjectInterpolator.activeDuration, 0)
        XCTAssertFalse(noTransitionSameObjectInterpolator.onlyFades)

        let renderOptionInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [
                .transition: opacity,
                .fadeInOutFraction: Float(0.33),
                .rasterizationScale: Float(3),
                .colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            ]
        )
        XCTAssertEqual(renderOptionInterpolator.options[.fadeInOutFraction] as? Float, 0.33)
        XCTAssertEqual(renderOptionInterpolator.options[.rasterizationScale] as? Float, 3)
        XCTAssertEqual(renderOptionInterpolator.activeDuration, 1)
        XCTAssertEqual(
            renderOptionInterpolator.boundingRect(withProgress: 0.5),
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
        XCTAssertEqual(renderOptionInterpolator.maxAbsoluteVelocity(withProgress: 0.5), 0)

        let retargetedFrom = makeDisplayList(
            debugItemCount: 1,
            bounds: CGRect(x: 10, y: 10, width: 10, height: 10)
        )
        interpolator.setFrom(retargetedFrom)
        XCTAssertEqual(interpolator.from.interpolationBounds, retargetedFrom.interpolationBounds)
        XCTAssertEqual(interpolator.boundingRect(withProgress: 0), CGRect(x: 10, y: 10, width: 10, height: 10))

        let animationOnly = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [.animation: Animation.linear(duration: 0.5).rbAnimation]
        )
        XCTAssertEqual(animationOnly.activeDuration, 0.5)

        let noTransitionAnimatedInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [.animation: Animation.linear(duration: 2).rbAnimation]
        )
        XCTAssertEqual(noTransitionAnimatedInterpolator.activeDuration, 2)
        XCTAssertEqual(
            noTransitionAnimatedInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
        let noTransitionAnimatedVelocitySamples: [(Float, Double)] = [
            (0, 0),
            (0.5, 32.97887742519379),
            (1, 37.5),
            (1.5, 32.97887742519379),
            (2, 0),
        ]
        for (progress, expectedVelocity) in noTransitionAnimatedVelocitySamples {
            XCTAssertEqual(
                noTransitionAnimatedInterpolator.maxAbsoluteVelocity(withProgress: progress),
                expectedVelocity,
                accuracy: 0.0005
            )
        }

        let copied = interpolator.copy() as? RBDisplayListInterpolator
        XCTAssertFalse(copied === interpolator)
        XCTAssertEqual(copied?.from.debugItems.count, 1)
        XCTAssertEqual(copied?.to.debugItems.count, 2)
        XCTAssertTrue(copied?.onlyFades ?? false)

        let sameCountMoved = RBDisplayListInterpolator(
            from: makeDisplayList(
                debugItemCount: 1,
                bounds: CGRect(x: 0, y: 0, width: 10, height: 20)
            ),
            to: makeDisplayList(
                debugItemCount: 1,
                bounds: CGRect(x: 20, y: 5, width: 30, height: 40)
            ),
            options: [.transition: opacity]
        )
        XCTAssertEqual(sameCountMoved.activeDuration, 1)

        let animatedInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [
                .transition: opacity,
                .animation: Animation.linear(duration: 2).rbAnimation,
            ]
        )
        XCTAssertEqual(animatedInterpolator.activeDuration, 2)
        XCTAssertEqual(
            animatedInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
        let animatedVelocitySamples: [(Float, Double)] = [
            (0, 0),
            (0.25, 25.829273462295532),
            (0.5, 32.97887742519379),
            (0.75, 36.43839657306671),
            (1, 37.5),
            (1.5, 32.97887742519379),
            (2, 0),
        ]
        for (progress, expectedVelocity) in animatedVelocitySamples {
            XCTAssertEqual(
                animatedInterpolator.maxAbsoluteVelocity(withProgress: progress),
                expectedVelocity,
                accuracy: 0.0005
            )
        }

        func transitionWithAnimationIndex(_ index: UInt, animation: Animation?) -> RBTransition {
            let transition = RBTransition()
            transition.method = ContentTransition.Method.diff.method
            transition.animation = animation
            let effect = RBTransitionEffect()
            effect.type = ContentTransition.EffectType.opacity.type
            effect.events = 3
            effect.animationIndex = index
            transition.addEffect(effect)
            return transition
        }

        for transition in [
            transitionWithAnimationIndex(0, animation: .linear(duration: 2)),
            transitionWithAnimationIndex(1, animation: nil),
            transitionWithAnimationIndex(1, animation: .linear(duration: 2)),
        ] {
            let transitionAnimationInterpolator = RBDisplayListInterpolator(
                from: from,
                to: to,
                options: [.transition: transition]
            )
            XCTAssertEqual(transitionAnimationInterpolator.activeDuration, 1)
            XCTAssertEqual(
                transitionAnimationInterpolator.boundingRect(withProgress: 1),
                CGRect(x: 20, y: 5, width: 30, height: 40)
            )
            for progress in [Float(0), Float(0.5), Float(1), Float(2)] {
                XCTAssertEqual(
                    transitionAnimationInterpolator.maxAbsoluteVelocity(withProgress: progress),
                    0
                )
            }
        }

        let customEffect = ContentTransition.Effect(
            type: ContentTransition.EffectType(type: 3),
            begin: 0,
            duration: 0,
            events: 3
        )
        let customTransition = ContentTransition(method: .diff, effects: [customEffect]).rbTransition
        let customInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [.transition: customTransition]
        )
        XCTAssertFalse(customInterpolator.onlyFades)

        let highBitOpacityTransition = RBTransition()
        let highBitOpacityEffect = RBTransitionEffect()
        highBitOpacityEffect.type = 0x100 | ContentTransition.EffectType.opacity.type
        highBitOpacityEffect.events = 3
        highBitOpacityTransition.addEffect(highBitOpacityEffect)
        let highBitOpacityInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [.transition: highBitOpacityTransition]
        )
        XCTAssertTrue(highBitOpacityInterpolator.onlyFades)

        let highBitTranslationTransition = RBTransition()
        let highBitTranslationEffect = RBTransitionEffect()
        highBitTranslationEffect.type = 0x100 | ContentTransition.EffectType.translation(.zero).type
        highBitTranslationEffect.events = 3
        highBitTranslationTransition.addEffect(highBitTranslationEffect)
        let highBitTranslationInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [.transition: highBitTranslationTransition]
        )
        XCTAssertFalse(highBitTranslationInterpolator.onlyFades)

        let effectSamples: [(ContentTransition.EffectType, Bool)] = [
            (.opacity, true),
            (.scale(0.5), false),
            (.translation(CGSize(width: 40, height: -10)), false),
            (.blur(radius: 12), false),
            (.translation(scale: CGSize(width: 0.5, height: 0.25)), false),
            (.relativeBlur(scale: CGSize(width: 0.5, height: 0.25)), false),
        ]
        for (effectType, expectedOnlyFades) in effectSamples {
            let transition = ContentTransition(
                method: .diff,
                effects: [
                    ContentTransition.Effect(
                        type: effectType,
                        begin: 0,
                        duration: 0,
                        events: 3
                    ),
                ]
            ).rbTransition
            let effectInterpolator = RBDisplayListInterpolator(
                from: drawableFrom,
                to: drawableTo,
                options: [.transition: transition]
            )
            let midpoint = effectInterpolator.copyContents(withProgress: 0.5)

            XCTAssertEqual(effectInterpolator.activeDuration, 1)
            XCTAssertEqual(effectInterpolator.onlyFades, expectedOnlyFades)
            XCTAssertEqual(effectInterpolator.maxAbsoluteVelocity(withProgress: 0.5), 0)
            XCTAssertEqual(
                effectInterpolator.boundingRect(withProgress: 0),
                CGRect(x: 0, y: 0, width: 10, height: 20)
            )
            XCTAssertEqual(
                effectInterpolator.boundingRect(withProgress: 0.5),
                CGRect(x: 10, y: 2.5, width: 20, height: 30)
            )
            XCTAssertEqual(
                effectInterpolator.boundingRect(withProgress: 1),
                CGRect(x: 20, y: 5, width: 30, height: 40)
            )
            XCTAssertEqual(
                effectInterpolator.copyContents(withProgress: 0).interpolationBounds,
                CGRect(x: 0, y: 0, width: 10, height: 20)
            )
            XCTAssertEqual(
                effectInterpolator.copyContents(withProgress: 1).interpolationBounds,
                CGRect(x: 20, y: 5, width: 30, height: 40)
            )
            XCTAssertEqual(midpoint.items.count, drawableMidpoint.items.count)
            XCTAssertEqual(midpoint.debugItems.count, drawableMidpoint.debugItems.count)
            XCTAssertEqual(midpoint.interpolationBounds, drawableMidpoint.interpolationBounds)
        }
    }

    func testRBAnimationAndSequencerCarrierSurface() {
        let empty = RBAnimation()
        XCTAssertEqual(empty.activeDuration, 0)
        XCTAssertEqual(empty.evaluateAtTime(-0.25), 0)
        XCTAssertEqual(empty.evaluateAtTime(0), 0)
        XCTAssertEqual(empty.evaluateAtTime(0.25), 1)

        let linear = Animation.linear(duration: 0.25).rbAnimation
        XCTAssertEqual(linear.activeDuration, 0.25)
        XCTAssertEqual(linear.evaluateAtTime(0), 0)
        XCTAssertEqual(linear.evaluateAtTime(0.25), 1)
        XCTAssertEqual(linear.evaluateAtTime(0.125), 0.5, accuracy: 0.001)

        let delayed = Animation.linear(duration: 0.25).delay(0.5).rbAnimation
        XCTAssertEqual(delayed.activeDuration, 0.75)
        XCTAssertEqual(delayed.evaluateAtTime(0.5), 0)
        XCTAssertEqual(delayed.evaluateAtTime(0.625), 0.5, accuracy: 0.001)

        let sped = Animation.linear(duration: 0.25).speed(2).rbAnimation
        XCTAssertEqual(sped.activeDuration, 0.125)
        XCTAssertEqual(sped.evaluateAtTime(0.0625), 0.5, accuracy: 0.001)

        let repeated = Animation.linear(duration: 0.25).repeatCount(2).rbAnimation
        XCTAssertEqual(repeated.activeDuration, 0.5)
        XCTAssertEqual(repeated.evaluateAtTime(0.375), 0.5, accuracy: 0.001)
        XCTAssertEqual(repeated.evaluateAtTime(0.5), 0)

        let sampled = RBAnimation()
        let sampledPairs: [Float] = [0, 0, 0.5, 0.25, 1, 1]
        sampledPairs.withUnsafeBufferPointer { buffer in
            sampled.addSampledFunction(
                withDuration: 2,
                count: 3,
                values: buffer.baseAddress!
            )
        }
        XCTAssertEqual(sampled.activeDuration, 2)
        XCTAssertEqual(sampled.evaluateAtTime(0), 0)
        XCTAssertEqual(sampled.evaluateAtTime(0.5), 0.125, accuracy: 0.001)
        XCTAssertEqual(sampled.evaluateAtTime(1), 0.25, accuracy: 0.001)
        XCTAssertEqual(sampled.evaluateAtTime(1.5), 0.625, accuracy: 0.001)
        XCTAssertEqual(sampled.evaluateAtTime(2), 1)

        let singleSample = RBAnimation()
        let singlePair: [Float] = [0.3, 0.7]
        singlePair.withUnsafeBufferPointer { buffer in
            singleSample.addSampledFunction(
                withDuration: 2,
                count: 1,
                values: buffer.baseAddress!
            )
        }
        XCTAssertEqual(singleSample.activeDuration, 2)
        XCTAssertEqual(singleSample.evaluateAtTime(0), 0)
        XCTAssertEqual(singleSample.evaluateAtTime(1), 0.5, accuracy: 0.001)
        XCTAssertEqual(singleSample.evaluateAtTime(2), 1)

        let offsetSample = RBAnimation()
        let offsetPairs: [Float] = [0.25, 0.5, 0.75, 1]
        offsetPairs.withUnsafeBufferPointer { buffer in
            offsetSample.addSampledFunction(
                withDuration: 2,
                count: 2,
                values: buffer.baseAddress!
            )
        }
        XCTAssertEqual(offsetSample.evaluateAtTime(0), 0.5, accuracy: 0.001)
        XCTAssertEqual(offsetSample.evaluateAtTime(0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(offsetSample.evaluateAtTime(1), 0.75, accuracy: 0.001)
        XCTAssertEqual(offsetSample.evaluateAtTime(2), 1, accuracy: 0.001)

        let preset0 = RBAnimation()
        preset0.addPreset(0, duration: 1)
        XCTAssertEqual(preset0.activeDuration, 1)
        XCTAssertEqual(preset0.evaluateAtTime(0.5), 0.5, accuracy: 0.001)

        let preset1 = RBAnimation()
        preset1.addPreset(1, duration: 1)
        XCTAssertEqual(preset1.evaluateAtTime(0.25), 0.15625, accuracy: 0.001)
        XCTAssertEqual(preset1.evaluateAtTime(0.75), 0.84375, accuracy: 0.001)

        let preset2 = RBAnimation()
        preset2.addPreset(2, duration: 1)
        XCTAssertEqual(preset2.evaluateAtTime(0.5), 0.315338, accuracy: 0.001)

        let preset3 = RBAnimation()
        preset3.addPreset(3, duration: 1)
        XCTAssertEqual(preset3.evaluateAtTime(0.5), 0.684662, accuracy: 0.001)

        let preset4 = RBAnimation()
        preset4.addPreset(4, duration: 1)
        XCTAssertEqual(preset4.evaluateAtTime(0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(preset4.evaluateAtTime(0.75), 0.871109, accuracy: 0.001)

        let preset5 = RBAnimation()
        preset5.addPreset(5, duration: 1)
        XCTAssertEqual(preset5.activeDuration, 1.5)
        XCTAssertEqual(preset5.evaluateAtTime(0.25), 0.465584, accuracy: 0.001)
        XCTAssertEqual(preset5.evaluateAtTime(1), 0.986399, accuracy: 0.001)

        let preset6 = RBAnimation()
        preset6.addPreset(6, duration: 1)
        XCTAssertEqual(preset6.activeDuration, 1.65, accuracy: 0.0001)
        XCTAssertEqual(preset6.evaluateAtTime(0.5), 0.952131, accuracy: 0.001)
        XCTAssertEqual(preset6.evaluateAtTime(0.75), 1.028375, accuracy: 0.001)

        let preset7 = RBAnimation()
        preset7.addPreset(7, duration: 1)
        XCTAssertEqual(preset7.activeDuration, 2.075, accuracy: 0.0001)
        XCTAssertEqual(preset7.evaluateAtTime(0.5), 1.096688, accuracy: 0.001)
        XCTAssertEqual(preset7.evaluateAtTime(1.25), 0.984773, accuracy: 0.001)

        let preset8 = RBAnimation()
        preset8.addPreset(8, duration: 1)
        XCTAssertEqual(preset8.evaluateAtTime(0.5), 0.133975, accuracy: 0.001)

        let preset9 = RBAnimation()
        preset9.addPreset(9, duration: 1)
        XCTAssertEqual(preset9.evaluateAtTime(0.5), 0.866025, accuracy: 0.001)

        let preset10 = RBAnimation()
        preset10.addPreset(10, duration: 1)
        XCTAssertEqual(preset10.evaluateAtTime(0.25), 0.066987, accuracy: 0.001)
        XCTAssertEqual(preset10.evaluateAtTime(0.75), 0.933013, accuracy: 0.001)

        let circularUnitCurve = Animation.timingCurve(.circularEaseInOut, duration: 1).rbAnimation
        let expectedCircularUnitCurve = RBAnimation()
        expectedCircularUnitCurve.addPreset(10, duration: 1)
        XCTAssertEqual(circularUnitCurve.activeDuration, expectedCircularUnitCurve.activeDuration)
        XCTAssertEqual(
            circularUnitCurve.evaluateAtTime(0.25),
            expectedCircularUnitCurve.evaluateAtTime(0.25),
            accuracy: 0.000001
        )
        XCTAssertEqual(
            circularUnitCurve.evaluateAtTime(0.75),
            expectedCircularUnitCurve.evaluateAtTime(0.75),
            accuracy: 0.000001
        )

        let invalidPreset = RBAnimation()
        invalidPreset.addPreset(11, duration: 1)
        XCTAssertEqual(invalidPreset.activeDuration, 0)
        XCTAssertEqual(invalidPreset.evaluateAtTime(0), 0)
        XCTAssertEqual(invalidPreset.evaluateAtTime(0.25), 1)

        let spring = RBAnimation()
        spring.addSpringDuration(1, mass: 1, stiffness: 100, damping: 10, initialVelocity: 0)
        XCTAssertEqual(spring.activeDuration, 1)
        XCTAssertEqual(spring.evaluateAtTime(0.25), 1.023360, accuracy: 0.001)
        XCTAssertEqual(spring.evaluateAtTime(0.5), 1.074591, accuracy: 0.001)

        let criticalSpring = RBAnimation()
        criticalSpring.addSpringDuration(1, mass: 1, stiffness: 100, damping: 30, initialVelocity: 0)
        XCTAssertEqual(criticalSpring.evaluateAtTime(0.25), 0.712703, accuracy: 0.001)
        XCTAssertEqual(criticalSpring.evaluateAtTime(0.5), 0.959572, accuracy: 0.001)

        let velocitySpring = RBAnimation()
        velocitySpring.addSpringDuration(1, mass: 1, stiffness: 100, damping: 10, initialVelocity: 2)
        XCTAssertEqual(velocitySpring.evaluateAtTime(0.25), 1.078182, accuracy: 0.001)

        let durationSpring = RBAnimation()
        durationSpring.addSpringDuration(2, mass: 1, stiffness: 100, damping: 10, initialVelocity: 0)
        XCTAssertEqual(durationSpring.activeDuration, 2)
        XCTAssertEqual(durationSpring.evaluateAtTime(0.25), spring.evaluateAtTime(0.25), accuracy: 0.001)

        let interpolatingSpring = Animation.interpolatingSpring(
            mass: 1,
            stiffness: 100,
            damping: 10,
            initialVelocity: 2
        ).rbAnimation
        let expectedInterpolatingSpring = RBAnimation()
        expectedInterpolatingSpring.addSpringDuration(
            2 * .pi / 10,
            mass: 1,
            stiffness: 100,
            damping: 10,
            initialVelocity: 2
        )
        XCTAssertEqual(
            interpolatingSpring.activeDuration,
            expectedInterpolatingSpring.activeDuration,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            interpolatingSpring.evaluateAtTime(0.25),
            expectedInterpolatingSpring.evaluateAtTime(0.25),
            accuracy: 0.000001
        )

        let fluidSpring = Animation.spring(response: 0.5, dampingFraction: 1.0).rbAnimation
        let expectedFluidSpring = RBAnimation()
        let fluidStiffness = fluidSpringStiffness(response: 0.5)
        expectedFluidSpring.addSpringDuration(
            0.5,
            mass: 1,
            stiffness: fluidStiffness,
            damping: 2 * sqrt(fluidStiffness),
            initialVelocity: 0
        )
        XCTAssertEqual(fluidSpring.activeDuration, 0.5)
        XCTAssertEqual(
            fluidSpring.evaluateAtTime(0.2),
            expectedFluidSpring.evaluateAtTime(0.2),
            accuracy: 0.000001
        )

        let postCurveDelay = RBAnimation()
        postCurveDelay.addBezierDuration(
            1,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        postCurveDelay.addDelay(0.5)
        XCTAssertEqual(postCurveDelay.activeDuration, 1)
        XCTAssertEqual(postCurveDelay.evaluateAtTime(0.5), 0.5, accuracy: 0.001)

        let postCurveSpeed = RBAnimation()
        postCurveSpeed.addBezierDuration(
            1,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        postCurveSpeed.addSpeed(2)
        XCTAssertEqual(postCurveSpeed.activeDuration, 1)
        XCTAssertEqual(postCurveSpeed.evaluateAtTime(0.5), 0.5, accuracy: 0.001)

        let postCurveRepeat = RBAnimation()
        postCurveRepeat.addBezierDuration(
            1,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        postCurveRepeat.addRepeatCount(2, autoreverses: true)
        XCTAssertEqual(postCurveRepeat.activeDuration, 1)
        XCTAssertEqual(postCurveRepeat.evaluateAtTime(0.5), 0.5, accuracy: 0.001)

        let secondCurve = RBAnimation()
        secondCurve.addBezierDuration(
            1,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        secondCurve.addBezierDuration(
            2,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        XCTAssertEqual(secondCurve.activeDuration, 1)
        XCTAssertEqual(secondCurve.evaluateAtTime(1), 1)

        let equalityLinear = RBAnimation()
        equalityLinear.addBezierDuration(
            1,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        let matchingLinear = RBAnimation()
        matchingLinear.addBezierDuration(
            1,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        let differentCurve = RBAnimation()
        differentCurve.addBezierDuration(
            1,
            controlPoint1: CGPoint(x: 0.42, y: 0),
            controlPoint2: CGPoint(x: 0.58, y: 1)
        )
        let matchingPostCurveDelay = RBAnimation()
        matchingPostCurveDelay.addBezierDuration(
            1,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        matchingPostCurveDelay.addDelay(0.5)
        let matchingSecondCurve = RBAnimation()
        matchingSecondCurve.addBezierDuration(
            1,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        matchingSecondCurve.addBezierDuration(
            2,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )

        XCTAssertEqual(equalityLinear, matchingLinear)
        XCTAssertEqual(equalityLinear.hash, matchingLinear.hash)
        XCTAssertNotEqual(equalityLinear, differentCurve)
        XCTAssertNotEqual(equalityLinear, postCurveDelay)
        XCTAssertEqual(postCurveDelay, matchingPostCurveDelay)
        XCTAssertNotEqual(equalityLinear, secondCurve)
        XCTAssertNotEqual(secondCurve, matchingSecondCurve)

        let copySource = RBAnimation()
        copySource.addDelay(0.25)
        copySource.addBezierDuration(
            1,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        guard let copiedAnimation = copySource.copy() as? RBAnimation else {
            XCTFail("Expected RBAnimation copy.")
            return
        }
        XCTAssertFalse(copiedAnimation === copySource)
        XCTAssertEqual(copiedAnimation, copySource)
        XCTAssertEqual(copiedAnimation.activeDuration, copySource.activeDuration)
        XCTAssertEqual(
            copiedAnimation.evaluateAtTime(0.75),
            copySource.evaluateAtTime(0.75),
            accuracy: 0.001
        )
        copySource.addDelay(0.5)
        XCTAssertNotEqual(copiedAnimation, copySource)
        XCTAssertEqual(copiedAnimation.activeDuration, 1.25)

        secondCurve.removeAll()
        XCTAssertEqual(secondCurve.activeDuration, 0)
        XCTAssertEqual(secondCurve.evaluateAtTime(0.5), 1)
        secondCurve.addBezierDuration(
            2,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        XCTAssertEqual(secondCurve.activeDuration, 2)
        XCTAssertEqual(secondCurve.evaluateAtTime(1), 0.5, accuracy: 0.001)

        var animationTable = RBAnimationTable(defaultAnimationIndex: 3)
        let emptyTableAnimation = RBAnimation()
        let tableAnimation = RBAnimation()
        tableAnimation.addBezierDuration(
            2,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        let matchingTableAnimation = RBAnimation()
        matchingTableAnimation.addBezierDuration(
            2,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        let delayedTableAnimation = RBAnimation()
        delayedTableAnimation.addDelay(0.5)
        delayedTableAnimation.addBezierDuration(
            2,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )

        XCTAssertEqual(animationTable.internAnimation(nil), 3)
        XCTAssertEqual(animationTable.internAnimation(emptyTableAnimation), -1)
        XCTAssertEqual(animationTable.internAnimation(tableAnimation), 1)
        XCTAssertEqual(animationTable.internAnimation(matchingTableAnimation), 1)
        XCTAssertEqual(animationTable.internAnimation(delayedTableAnimation), 2)
        XCTAssertEqual(animationTable.entries.count, 2)
        XCTAssertEqual(animationTable.entries[0].index, 1)
        XCTAssertEqual(animationTable.entries[0].activeDuration, 2)
        XCTAssertEqual(animationTable.animation(at: 1)?.activeDuration, 2)
        XCTAssertNil(animationTable.animation(at: 0))
        tableAnimation.addDelay(10)
        XCTAssertEqual(animationTable.animation(at: 1)?.activeDuration, 2)
        XCTAssertEqual(
            animationTable.evaluate(animationIndex: 1, time: 1),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            animationTable.evaluate(animationIndex: 1, sequence: 7, time: 1),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(animationTable.evaluate(animationIndex: 0, time: 0.25), 0.25)
        XCTAssertEqual(animationTable.evaluate(animationIndex: -2, time: 0.25), 0.25)
        XCTAssertEqual(animationTable.evaluate(animationIndex: -1, time: 0), 0)
        XCTAssertEqual(animationTable.evaluate(animationIndex: -1, time: 0.25), 1)
        XCTAssertEqual(animationTable.activeDuration(animationIndex: 2), 2.5)
        XCTAssertEqual(animationTable.maximumDuration(animationIndex: 0), 1)
        XCTAssertEqual(animationTable.maximumDuration(animationIndex: 2), 2.5)
        XCTAssertEqual(
            animationTable.maxSpeed(animationIndex: 1, time: 1),
            0.75,
            accuracy: 0.001
        )
        XCTAssertEqual(
            animationTable.maxSpeed(atTime: 1),
            0.75,
            accuracy: 0.001
        )

        let effects = RBAnimationSequencerEffects()
        XCTAssertEqual(effects.delayOffset, 0)
        XCTAssertEqual(effects.delayScale, 0)
        effects.delayOffset = 0.25
        effects.delayScale = 2

        let sequencer = RBAnimationSequencer()
        sequencer.distanceMode = 1
        sequencer.sequencesGlyphs = true
        sequencer.startPoint = CGPoint(x: 1, y: 2)
        sequencer.endPoint = CGPoint(x: 3, y: 4)
        sequencer.added = effects

        XCTAssertEqual(sequencer.distanceMode, 1)
        XCTAssertTrue(sequencer.sequencesGlyphs)
        XCTAssertEqual(sequencer.startPoint, CGPoint(x: 1, y: 2))
        XCTAssertEqual(sequencer.endPoint, CGPoint(x: 3, y: 4))
        XCTAssertEqual(sequencer.added?.delayOffset, 0.25)
        XCTAssertEqual(sequencer.added?.delayScale, 2)
        XCTAssertEqual(
            sequencer.evalDelay(at: CGPoint(x: 3, y: 4), phase: .added) ?? -1,
            2.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            sequencer.evalDelay(at: CGPoint(x: 3, y: 4), phase: .mixed) ?? -1,
            0,
            accuracy: 0.0005
        )

        sequencer.distanceMode = 0
        sequencer.startPoint = CGPoint(x: 0, y: 100)
        sequencer.endPoint = CGPoint(x: 100, y: 100)
        sequencer.mixed = effects
        XCTAssertEqual(
            sequencer.evalDelay(at: CGPoint(x: 35, y: 25), phase: .mixed) ?? -1,
            0.95,
            accuracy: 0.0005
        )

        sequencer.distanceMode = 1
        sequencer.startPoint = CGPoint(x: 35, y: 25)
        sequencer.endPoint = CGPoint(x: 35, y: 25)
        XCTAssertNil(sequencer.evalDelay(at: CGPoint(x: 35, y: 25), phase: .mixed))

        let matchingEffects = RBAnimationSequencerEffects()
        matchingEffects.delayOffset = 0.25
        matchingEffects.delayScale = 2
        XCTAssertTrue(effects.isEqual(effects))
        XCTAssertFalse(effects.isEqual(matchingEffects))
        XCTAssertFalse(effects.responds(to: NSSelectorFromString("copyWithZone:")))

        let matchingSequencer = RBAnimationSequencer()
        matchingSequencer.distanceMode = 1
        matchingSequencer.sequencesGlyphs = true
        matchingSequencer.startPoint = CGPoint(x: 1, y: 2)
        matchingSequencer.endPoint = CGPoint(x: 3, y: 4)
        matchingSequencer.added = matchingEffects
        XCTAssertTrue(sequencer.isEqual(sequencer))
        XCTAssertFalse(sequencer.isEqual(matchingSequencer))
        XCTAssertFalse(sequencer.responds(to: NSSelectorFromString("copyWithZone:")))

        let phaseSequencer = RBAnimationSequencer()
        phaseSequencer.startPoint = .zero
        phaseSequencer.endPoint = CGPoint(x: 10, y: 0)
        let addedEffects = RBAnimationSequencerEffects()
        addedEffects.delayOffset = 10
        addedEffects.delayScale = 2
        let mixedEffects = RBAnimationSequencerEffects()
        mixedEffects.delayOffset = 20
        mixedEffects.delayScale = 2
        let removedEffects = RBAnimationSequencerEffects()
        removedEffects.delayOffset = 30
        removedEffects.delayScale = 2
        phaseSequencer.added = addedEffects
        phaseSequencer.mixed = mixedEffects
        phaseSequencer.removed = removedEffects
        XCTAssertTrue(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 0))
        XCTAssertTrue(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 1))
        XCTAssertTrue(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 2))
        XCTAssertTrue(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 3))
        XCTAssertFalse(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 4))
        XCTAssertFalse(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 5))
        XCTAssertTrue(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 6))
        XCTAssertTrue(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 7))
        XCTAssertFalse(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 8))
        XCTAssertTrue(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 9))
        XCTAssertTrue(RBAnimationSequencer.canCarryAnimationIndex(operationLowNibble: 15))
        XCTAssertEqual(
            RBAnimationSequencer.operationAnimationIndex(
                operationLowNibble: 4,
                resolvedAnimationIndex: 7,
                defaultAnimationIndex: 3
            ),
            -1
        )
        XCTAssertEqual(
            RBAnimationSequencer.operationAnimationIndex(
                operationLowNibble: 8,
                resolvedAnimationIndex: nil,
                defaultAnimationIndex: 3
            ),
            -1
        )
        XCTAssertEqual(
            RBAnimationSequencer.operationAnimationIndex(
                operationLowNibble: 2,
                resolvedAnimationIndex: 7,
                defaultAnimationIndex: 3
            ),
            7
        )
        XCTAssertEqual(
            RBAnimationSequencer.operationAnimationIndex(
                operationLowNibble: 2,
                resolvedAnimationIndex: nil,
                defaultAnimationIndex: 3
            ),
            3
        )
        XCTAssertEqual(
            phaseSequencer.evalDelay(at: CGPoint(x: 5, y: 0), animatedOperationType: 0) ?? -1,
            31,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            phaseSequencer.evalDelay(at: CGPoint(x: 5, y: 0), animatedOperationType: 1) ?? -1,
            11,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            phaseSequencer.evalDelay(at: CGPoint(x: 5, y: 0), animatedOperationType: 2) ?? -1,
            21,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            phaseSequencer.evalDelay(at: CGPoint(x: 5, y: 0), animatedOperationType: 7) ?? -1,
            21,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            RBAnimationSequencer.operationDelay(byAddingSequencerDelay: 0.75, to: 1.25),
            2,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            RBAnimationSequencer.operationDelay(byAddingSequencerDelay: 0, to: 1.25),
            1.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            RBAnimationSequencer.operationDelay(byAddingSequencerDelay: -0.75, to: 1.25),
            1.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            RBAnimationSequencer.operationDelay(byAddingSequencerDelay: nil, to: 1.25),
            1.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            RBAnimationSequencer.operationDelay(byAddingSequencerDelay: .infinity, to: 1.25),
            1.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            RBAnimationSequencer.operationAnimationRecord(
                operationLowNibble: 2,
                resolvedAnimationIndex: 7,
                defaultAnimationIndex: 3,
                operationDelay: 1.25,
                sequencerDelay: 0.75
            ),
            RBAnimationSequencer.OperationAnimationRecord(animationIndex: 7, delay: 2)
        )
        XCTAssertEqual(
            RBAnimationSequencer.operationAnimationRecord(
                operationLowNibble: 5,
                resolvedAnimationIndex: 7,
                defaultAnimationIndex: 3,
                operationDelay: 1.25,
                sequencerDelay: 0.75
            ),
            RBAnimationSequencer.OperationAnimationRecord(animationIndex: -1, delay: 2)
        )
    }

    func testRBDisplayListInterpolatorSequencerDurationSurface() {
        let from = makeDisplayList(
            debugItemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        let to = makeDisplayList(
            debugItemCount: 2,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40)
        )
        let transition = ContentTransition(
            method: .diff,
            effects: [
                ContentTransition.Effect(
                    type: .translation(CGSize(width: 40, height: -10)),
                    begin: 0,
                    duration: 0,
                    events: 3
                ),
            ]
        ).rbTransition

        func makeEffects(offset: Float, scale: Float) -> RBAnimationSequencerEffects {
            let effects = RBAnimationSequencerEffects()
            effects.delayOffset = offset
            effects.delayScale = scale
            return effects
        }

        func makeSequencer(
            distanceMode: Int32 = 1,
            startPoint: CGPoint = .zero,
            endPoint: CGPoint = CGPoint(x: 100, y: 50),
            added: RBAnimationSequencerEffects? = nil,
            mixed: RBAnimationSequencerEffects? = nil,
            removed: RBAnimationSequencerEffects? = nil
        ) -> RBAnimationSequencer {
            let sequencer = RBAnimationSequencer()
            sequencer.distanceMode = distanceMode
            sequencer.sequencesGlyphs = true
            sequencer.startPoint = startPoint
            sequencer.endPoint = endPoint
            sequencer.added = added
            sequencer.mixed = mixed
            sequencer.removed = removed
            return sequencer
        }

        func makeInterpolator(_ sequencer: RBAnimationSequencer) -> RBDisplayListInterpolator {
            RBDisplayListInterpolator(
                from: from,
                to: to,
                options: [
                    .transition: transition,
                    .animationSequencer: sequencer,
                ]
            )
        }

        func makeNoTransitionInterpolator(_ sequencer: RBAnimationSequencer) -> RBDisplayListInterpolator {
            RBDisplayListInterpolator(
                from: from,
                to: to,
                options: [
                    .animationSequencer: sequencer,
                ]
            )
        }

        func assertRectApproximatelyEqual(
            _ actual: CGRect,
            _ expected: CGRect,
            accuracy: CGFloat = 0.002,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actual.size.width, expected.size.width, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actual.size.height, expected.size.height, accuracy: accuracy, file: file, line: line)
        }

        let emptyAnimationKeySequencer = RBDisplayListInterpolator(
            from: DisplayList(),
            to: DisplayList(),
            options: [
                .transition: transition,
                .animation: makeSequencer(mixed: makeEffects(offset: 0.25, scale: 2)),
            ]
        )
        XCTAssertEqual(emptyAnimationKeySequencer.activeDuration, 0)

        XCTAssertEqual(makeInterpolator(makeSequencer()).activeDuration, 1)
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(added: makeEffects(offset: 0.25, scale: 2))
            ).activeDuration,
            1
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(removed: makeEffects(offset: 0.25, scale: 2))
            ).activeDuration,
            1
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(mixed: makeEffects(offset: 0.25, scale: 0))
            ).activeDuration,
            1.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(mixed: makeEffects(offset: 0.5, scale: 0))
            ).activeDuration,
            1.5,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(mixed: makeEffects(offset: 0.25, scale: 2))
            ).activeDuration,
            2.0194153785705566,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    distanceMode: 0,
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            2.009999990463257,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    distanceMode: 0,
                    startPoint: CGPoint(x: 0, y: 100),
                    endPoint: CGPoint(x: 100, y: 100),
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            1.95,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    distanceMode: -1,
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            1.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    distanceMode: 2,
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            1.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    distanceMode: 3,
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            1.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    startPoint: CGPoint(x: 20, y: 10),
                    endPoint: CGPoint(x: 120, y: 60),
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            1.629473328590393,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    startPoint: CGPoint(x: 0, y: 100),
                    endPoint: CGPoint(x: 100, y: 100),
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            2.905294418334961,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    startPoint: CGPoint(x: 35, y: 25),
                    endPoint: CGPoint(x: 35, y: 25),
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            1,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    startPoint: CGPoint(x: 35, y: 25),
                    endPoint: CGPoint(x: 35, y: 25),
                    mixed: makeEffects(offset: 0.25, scale: 0)
                )
            ).activeDuration,
            1,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    startPoint: CGPoint(x: 35, y: 25),
                    endPoint: CGPoint(x: 35, y: 25),
                    mixed: makeEffects(offset: 0, scale: 2)
                )
            ).activeDuration,
            1,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    endPoint: CGPoint(x: 10, y: 0),
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            3.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(mixed: makeEffects(offset: 0.25, scale: 2))
            ).maxAbsoluteVelocity(withProgress: 0.5),
            0
        )

        let sequencerOnlyInterpolator = makeInterpolator(
            makeSequencer(mixed: makeEffects(offset: 0.25, scale: 2))
        )
        assertRectApproximatelyEqual(
            sequencerOnlyInterpolator.boundingRect(withProgress: 0.5),
            CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        assertRectApproximatelyEqual(
            sequencerOnlyInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        assertRectApproximatelyEqual(
            sequencerOnlyInterpolator.boundingRect(withProgress: 1.5),
            CGRect(
                x: 9.611692428588867,
                y: 2.402923107147217,
                width: 19.611692428588867,
                height: 29.611690521240234
            )
        )
        assertRectApproximatelyEqual(
            sequencerOnlyInterpolator.boundingRect(withProgress: 2.0194154),
            CGRect(x: 20, y: 5, width: 30, height: 40)
        )
        assertRectApproximatelyEqual(
            sequencerOnlyInterpolator.copyContents(withProgress: 1.5).interpolationBounds ?? .null,
            CGRect(
                x: 9.611692428588867,
                y: 2.402923107147217,
                width: 19.611692428588867,
                height: 29.611690521240234
            )
        )

        let noTransitionSequencerInterpolator = makeNoTransitionInterpolator(
            makeSequencer(mixed: makeEffects(offset: 0.25, scale: 2))
        )
        XCTAssertEqual(noTransitionSequencerInterpolator.activeDuration, 2.0194153785705566, accuracy: 0.0005)
        XCTAssertFalse(noTransitionSequencerInterpolator.onlyFades)
        assertRectApproximatelyEqual(
            noTransitionSequencerInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        assertRectApproximatelyEqual(
            noTransitionSequencerInterpolator.boundingRect(withProgress: 1.5),
            CGRect(
                x: 9.611692428588867,
                y: 2.402923107147217,
                width: 19.611692428588867,
                height: 29.611690521240234
            )
        )
        assertRectApproximatelyEqual(
            noTransitionSequencerInterpolator.copyContents(withProgress: 1.5).interpolationBounds ?? .null,
            CGRect(
                x: 9.611692428588867,
                y: 2.402923107147217,
                width: 19.611692428588867,
                height: 29.611690521240234
            )
        )
        XCTAssertEqual(noTransitionSequencerInterpolator.maxAbsoluteVelocity(withProgress: 1.5), 0)

        let noTransitionCombinedInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [
                .animation: Animation.linear(duration: 2).rbAnimation,
                .animationSequencer: makeSequencer(mixed: makeEffects(offset: 0.25, scale: 2)),
            ]
        )
        XCTAssertEqual(noTransitionCombinedInterpolator.activeDuration, 3.0194153785705566, accuracy: 0.0005)
        assertRectApproximatelyEqual(
            noTransitionCombinedInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        assertRectApproximatelyEqual(
            noTransitionCombinedInterpolator.boundingRect(withProgress: 1.5),
            CGRect(
                x: 4.807149887084961,
                y: 1.2017874717712402,
                width: 14.807149887084961,
                height: 24.80714988708496
            )
        )
        assertRectApproximatelyEqual(
            noTransitionCombinedInterpolator.boundingRect(withProgress: 2),
            CGRect(
                x: 9.80585765838623,
                y: 2.4514644145965576,
                width: 19.805858612060547,
                height: 29.805856704711914
            )
        )
        let noTransitionCombinedVelocitySamples: [(Float, Double)] = [
            (0, 0),
            (0.5, 32.97887742519379),
            (1, 37.5),
            (1.0194154, 37.493717670440674),
            (1.5, 32.97887742519379),
            (2, 0),
            (3.0194154, 0),
        ]
        for (progress, expectedVelocity) in noTransitionCombinedVelocitySamples {
            XCTAssertEqual(
                noTransitionCombinedInterpolator.maxAbsoluteVelocity(withProgress: progress),
                expectedVelocity,
                accuracy: 0.0005
            )
        }

        let combinedInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [
                .transition: transition,
                .animation: Animation.linear(duration: 2).rbAnimation,
                .animationSequencer: makeSequencer(mixed: makeEffects(offset: 0.25, scale: 2)),
            ]
        )
        XCTAssertEqual(combinedInterpolator.activeDuration, 3.0194153785705566, accuracy: 0.0005)
        assertRectApproximatelyEqual(
            combinedInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        assertRectApproximatelyEqual(
            combinedInterpolator.boundingRect(withProgress: 1.5),
            CGRect(
                x: 4.807149887084961,
                y: 1.2017874717712402,
                width: 14.807149887084961,
                height: 24.80714988708496
            )
        )
        assertRectApproximatelyEqual(
            combinedInterpolator.boundingRect(withProgress: 2),
            CGRect(
                x: 9.80585765838623,
                y: 2.4514644145965576,
                width: 19.805858612060547,
                height: 29.805856704711914
            )
        )
        assertRectApproximatelyEqual(
            combinedInterpolator.boundingRect(withProgress: 3.0194154),
            CGRect(x: 20, y: 5, width: 30, height: 40)
        )

        let combinedVelocitySamples: [(Float, Double)] = [
            (0, 0),
            (0.5, 32.97887742519379),
            (1, 37.5),
            (1.0194154, 37.493717670440674),
            (1.5, 32.97887742519379),
            (2, 0),
            (3.0194154, 0),
        ]
        for (progress, expectedVelocity) in combinedVelocitySamples {
            XCTAssertEqual(
                combinedInterpolator.maxAbsoluteVelocity(withProgress: progress),
                expectedVelocity,
                accuracy: 0.0005
            )
        }
    }

    func testUnaryInterpolatorGroupTracksLayerState() {
        let unary = DisplayList.UnaryInterpolatorGroup()
        let current = makeDisplayList(debugItemCount: 1)
        let target = makeDisplayList(debugItemCount: 2)
        var state = ContentTransition.State(
            transition: .opacity,
            options: .addsDrawingGroup
        )
        state.animation = .linear(duration: 0.2)

        let output = unary.update(
            contentSeed: DisplayList.Seed(decodedValue: 5),
            current: current,
            target: target,
            state: state,
            time: Time(seconds: 2),
            animatesSize: false,
            defersRender: false,
            supportsVFD: true
        )

        XCTAssertEqual(unary.lastContentSeed, DisplayList.Seed(decodedValue: 5))
        XCTAssertTrue(unary.supportsVariableFrameDuration)
        XCTAssertTrue(unary.rasterizationOptions.isAccelerated)
        XCTAssertEqual(unary.layer.contents.displayList.debugItems.count, 2)
        XCTAssertEqual(unary.layer.removedCount, 1)
        XCTAssertEqual(unary.layer.removed.first?.rbTransition.method, ContentTransition.Method.diff.method)
        XCTAssertEqual(unary.layer.removed.first?.rbTransition.effects.first?.type, ContentTransition.EffectType.opacity.type)
        XCTAssertEqual(unary.layer.currentTime.seconds, 2)
        XCTAssertEqual(unary.layer.removed.first?.startTime.seconds, 2)
        XCTAssertNotNil(unary.layer.removed.first?.interpolator)
        XCTAssertTrue(unary.layer.removed.first?.interpolator?.onlyFades ?? false)
        XCTAssertNotNil(unary.layer.removed.first?.interpolator?.options[.transition])
        XCTAssertNotNil(unary.layer.removed.first?.interpolator?.animation)
        XCTAssertNil(unary.layer.removed.first?.interpolator?.options[.rasterizationScale])
        XCTAssertEqual(unary.layer.removed.first?.interpolator?.animation?.activeDuration, 0.2)
        XCTAssertEqual(unary.layer.removed.first?.activeDuration, 0.2)
        XCTAssertEqual(unary.layer.nextUpdateTime.seconds, 2.2, accuracy: 0.000_001)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 2.2, accuracy: 0.000_001)
        XCTAssertEqual(unary.layer.removed.first?.interpolator?.copyContents(withProgress: 0).debugItems.count, 1)
        XCTAssertEqual(unary.layer.removed.first?.interpolator?.copyContents(withProgress: 0.1).debugItems.count, 1)
        XCTAssertEqual(unary.layer.removed.first?.interpolator?.contents(withProgress: 0.2).debugItems.count, 2)
        XCTAssertFalse(unary.layer.needsUpdate)
        XCTAssertEqual(output.effects.count, 1)

        unary.updateTime(Time(seconds: 2.1))
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 2.2, accuracy: 0.000_001)

        unary.updateTime(Time(seconds: 2.2))
        let completedOutput = unary.apply(to: target)
        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertTrue(unary.layer.nextUpdateTime.seconds.isInfinite)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 2.2, accuracy: 0.000_001)
        XCTAssertTrue(completedOutput.effects.isEmpty)

        unary.reset()
        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertFalse(unary.supportsVariableFrameDuration)
    }

    func testUnaryInterpolatorGroupSetCurrentContentsSynchronizesLayerState() {
        let unary = DisplayList.UnaryInterpolatorGroup()
        let target = makeDisplayList(debugItemCount: 2)
        var rasterizationOptions = RasterizationOptions()
        rasterizationOptions.isAccelerated = true
        rasterizationOptions.alphaOnly = true

        unary.setCurrentContents(
            contentSeed: DisplayList.Seed(decodedValue: 11),
            target: target,
            time: Time(seconds: 3.5),
            supportsVFD: true,
            rasterizationOptions: rasterizationOptions
        )

        XCTAssertEqual(unary.lastContentSeed, DisplayList.Seed(decodedValue: 11))
        XCTAssertTrue(unary.supportsVariableFrameDuration)
        XCTAssertEqual(unary.rasterizationOptions, rasterizationOptions)
        XCTAssertEqual(unary.layer.contents.version?.value, 11)
        XCTAssertEqual(unary.layer.contents.displayList.debugItems.count, 2)
        XCTAssertEqual(unary.layer.currentTime.seconds, 3.5)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 3.5)
    }

    func testInterpolatorLayerOnlyRetainsWhenTransitionStateIsSupplied() {
        var layer = DisplayList.InterpolatorLayer()
        let first = makeDisplayList(debugItemCount: 1)
        let second = makeDisplayList(debugItemCount: 1)

        layer.setDisplayList(
            first,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        layer.setDisplayList(
            second,
            origin: .zero,
            version: DisplayList.Version(value: 2)
        )

        XCTAssertEqual(layer.removedCount, 0)
        XCTAssertEqual(layer.contents.version?.value, 2)

        layer.setDisplayList(
            first,
            origin: .zero,
            version: DisplayList.Version(value: 3),
            state: ContentTransition.State(transition: .opacity)
        )

        XCTAssertEqual(layer.removedCount, 1)
        XCTAssertEqual(layer.removed.first?.contents.version?.value, 2)
        XCTAssertEqual(layer.contents.version?.value, 3)
    }

    func testInterpolatedDisplayListRetainsPreviousListOnFirstSameSurfaceChange() throws {
        let graph = AttributeGraph()

        try AttributeGraph.withCurrent(graph) {
            let firstList = makeDisplayList(debugItemCount: 1)
            let secondList = makeDisplayList(debugItemCount: 1)
            let displayList = graph.makeInput(value: firstList)
            let content = graph.makeInput(value: VersionedTransitionContent(value: 0))
            let group = DisplayList.UnaryInterpolatorGroup()
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: makeViewInputs(graph: graph),
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 0)
            XCTAssertEqual(group.layer.contents.version?.value, 1)

            displayList.setValue(secondList)
            content.setValue(VersionedTransitionContent(value: 1))
            let updated = output.value

            XCTAssertEqual(updated.effects.count, 1)
            XCTAssertEqual(updated.effects.first?.contents.debugItems.count, 1)
            XCTAssertEqual(group.lastContentSeed.value, 2)
            XCTAssertEqual(group.layer.removedCount, 1)
            XCTAssertEqual(group.layer.removed.first?.contents.version?.value, 1)
            XCTAssertEqual(group.layer.contents.version?.value, 2)
            XCTAssertEqual(group.layer.removed.first?.interpolator?.from.debugItems.count, 1)
            XCTAssertEqual(group.layer.removed.first?.interpolator?.to.debugItems.count, 1)
        }
    }

    func testInterpolatedDisplayListIdentityTransitionSyncsCurrentWithoutRemoval() throws {
        let graph = AttributeGraph()
        InterpolatableContentProbeLog.reset()

        try AttributeGraph.withCurrent(graph) {
            let firstList = makeDisplayList(debugItemCount: 1)
            let secondList = makeDisplayList(debugItemCount: 1)
            let displayList = graph.makeInput(value: firstList)
            let content = graph.makeInput(value: ProbeInterpolatableContent(value: 0))
            let group = DisplayList.UnaryInterpolatorGroup()
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: makeViewInputs(graph: graph),
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 0)

            displayList.setValue(secondList)
            content.setValue(ProbeInterpolatableContent(value: 1))
            let updated = output.value

            XCTAssertEqual(InterpolatableContentProbeLog.modifyTransitionCalls, 1)
            XCTAssertEqual(InterpolatableContentProbeLog.defaultAnimationCalls, 1)
            XCTAssertEqual(updated.effects.count, 0)
            XCTAssertEqual(group.layer.removedCount, 0)
            XCTAssertEqual(group.layer.contents.version?.value, 2)
            XCTAssertEqual(group.layer.contents.displayList.debugItems.count, 1)
        }
    }

    func testUnaryInterpolatorGroupSchedulesViewGraphLayerDeadline() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph

        let unary = DisplayList.UnaryInterpolatorGroup()
        let current = makeDisplayList(debugItemCount: 1)
        let target = makeDisplayList(debugItemCount: 2)
        var state = ContentTransition.State(transition: .opacity)
        state.animation = .linear(duration: 0.2)

        viewGraph.data.withCurrent {
            _ = unary.update(
                contentSeed: DisplayList.Seed(decodedValue: 7),
                current: current,
                target: target,
                state: state,
                time: Time(seconds: 2),
                animatesSize: false,
                defersRender: false,
                supportsVFD: false
            )
        }

        XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 2.2, accuracy: 0.000_001)

        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
        viewGraph.data.withCurrent {
            unary.updateTime(Time(seconds: 2.1))
        }
        XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 2.2, accuracy: 0.000_001)

        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
        viewGraph.data.withCurrent {
            unary.updateTime(Time(seconds: 2.2))
            _ = unary.apply(to: target)
        }
        XCTAssertTrue(viewGraph.nextUpdate.views.time.seconds.isInfinite)
    }

    func testResolvedImageInterpolatableContentSurface() {
        let previousSemantics = Semantics.overrides
        defer { Semantics.overrides = previousSemantics }

        Semantics.overrides = Semantics.Overrides()
        XCTAssertEqual(GraphicsContext.ResolvedImage.defaultTransition, .interpolate)

        Semantics.overrides = Semantics.Overrides(
            build: _SemanticFeature<Semantics_v4>.prior,
            runtime: previousSemantics.runtime
        )
        XCTAssertEqual(GraphicsContext.ResolvedImage.defaultTransition, .identity)

        let image = makeResolvedImage()
        XCTAssertFalse(image.requiresTransition(to: makeResolvedImage()))
        XCTAssertTrue(image.requiresTransition(to: makeResolvedImage(baseline: 2)))
        XCTAssertTrue(
            image.requiresTransition(
                to: makeResolvedImage(textureTransform: CGAffineTransform(translationX: 1, y: 0))
            )
        )
        XCTAssertTrue(image.requiresTransition(to: makeResolvedImage(scaleFactor: 2)))

        var unchangedState = ContentTransition.State(transition: .interpolate)
        image.modifyTransition(state: &unchangedState, to: makeResolvedImage())
        XCTAssertEqual(unchangedState.transition, .interpolate)

        var changedState = ContentTransition.State(transition: .interpolate)
        image.modifyTransition(state: &changedState, to: makeResolvedImage(baseline: 2))
        XCTAssertEqual(changedState.transition, .opacity)

        var protectedState = ContentTransition.State(
            transition: .interpolate,
            options: .animatesDifferentContent
        )
        image.modifyTransition(state: &protectedState, to: makeResolvedImage(baseline: 2))
        XCTAssertEqual(protectedState.transition, .interpolate)
    }

    func testResolvedStyledTextInterpolatableContentSurface() {
        let previousSemantics = Semantics.overrides
        defer { Semantics.overrides = previousSemantics }

        Semantics.overrides = Semantics.Overrides()
        XCTAssertEqual(ResolvedStyledText.defaultTransition, .interpolate)

        Semantics.overrides = Semantics.Overrides(
            build: _SemanticFeature<Semantics_v4>.prior,
            runtime: previousSemantics.runtime
        )
        XCTAssertEqual(ResolvedStyledText.defaultTransition, .identity)

        let text = ResolvedStyledText(version: 1)
        XCTAssertFalse(text.requiresTransition(to: ResolvedStyledText(version: 1)))
        XCTAssertTrue(text.requiresTransition(to: ResolvedStyledText(version: 2)))
        XCTAssertFalse(
            ResolvedStyledText(version: 1, transitionText: "Hello")
                .requiresTransition(to: ResolvedStyledText(version: 2, transitionText: "Hello"))
        )
        XCTAssertTrue(
            ResolvedStyledText(version: 1, transitionText: "Hello")
                .requiresTransition(to: ResolvedStyledText(version: 2, transitionText: "World"))
        )
        XCTAssertTrue(text.appliesTransitionsForSizeChanges)
        XCTAssertFalse(text.addsDrawingGroup)
        XCTAssertTrue(ResolvedStyledText(version: 1, needsDrawingGroup: true).addsDrawingGroup)

        var unchangedState = ContentTransition.State(transition: .interpolate)
        text.modifyTransition(state: &unchangedState, to: ResolvedStyledText(version: 1))
        XCTAssertEqual(unchangedState.transition, .interpolate)

        var changedState = ContentTransition.State(transition: .interpolate)
        text.modifyTransition(state: &changedState, to: ResolvedStyledText(version: 2))
        XCTAssertEqual(changedState.transition, .text)

        var sameTextState = ContentTransition.State(transition: .interpolate)
        ResolvedStyledText(version: 1, transitionText: "Hello")
            .modifyTransition(
                state: &sameTextState,
                to: ResolvedStyledText(version: 2, transitionText: "Hello")
            )
        XCTAssertEqual(sameTextState.transition, .interpolate)

        var protectedState = ContentTransition.State(
            transition: .interpolate,
            options: .animatesDifferentContent
        )
        text.modifyTransition(state: &protectedState, to: ResolvedStyledText(version: 2))
        XCTAssertEqual(protectedState.transition, .interpolate)

        let environment = EnvironmentValues()
        XCTAssertEqual(Text(verbatim: "A")._resolveTransitionText(in: environment), "A")
        XCTAssertEqual((Text(verbatim: "A") + Text(verbatim: "B"))._resolveTransitionText(in: environment), "AB")
        XCTAssertNil(Text(Image(systemName: "star"))._resolveTransitionText(in: environment))
    }

    func testApplyInterpolatorGroupReplacesDisplayListOutput() throws {
        let graph = AttributeGraph()

        try AttributeGraph.withCurrent(graph) {
            let sourceList = makeDisplayList(debugItemCount: 1)
            let displayList = graph.makeInput(value: sourceList)
            let content = graph.makeInput(value: ProbeInterpolatableContent(value: 0))
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                DisplayList.InterpolatorGroup(),
                content: content,
                inputs: makeViewInputs(graph: graph),
                animatesSize: true,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            XCTAssertNotEqual(outputID.rawValue, displayList.identifier.rawValue)
            let output = Attribute<DisplayList>(outputID).value
            XCTAssertEqual(output.debugItems.count, sourceList.debugItems.count)
        }
    }

    func testTextMakeViewAppliesResolvedStyledTextInterpolator() throws {
        let graph = AttributeGraph()

        try AttributeGraph.withCurrent(graph) {
            let text = graph.makeInput(value: Text("Hello"))
            let outputs = Text._makeView(
                view: _GraphValue(_attribute: text),
                inputs: makeViewInputs(graph: graph)
            )

            XCTAssertEqual(outputs.preferences.values(for: ResourceList.Key.self).count, 1)
            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            XCTAssertTrue(graph.debugDescription(for: outputID).contains("(stateful)"))
            XCTAssertEqual(Attribute<DisplayList>(outputID).value.items.count, 0)
        }
    }

    func testResolvedStyledTextInterpolatorEmitsContentTransitionEffect() throws {
        let graph = AttributeGraph()

        try AttributeGraph.withCurrent(graph) {
            let sourceList = makeDisplayList(debugItemCount: 1)
            let displayList = graph.makeInput(value: sourceList)
            let content = graph.makeInput(value: ResolvedStyledText(version: 0))
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                DisplayList.InterpolatorGroup(),
                content: content,
                inputs: makeViewInputs(graph: graph),
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 0)

            content.setValue(ResolvedStyledText(version: 1))
            let updated = output.value
            XCTAssertEqual(updated.debugItems.count, 0)
            XCTAssertEqual(updated.effects.count, 1)
            XCTAssertEqual(updated.effects.first?.contents.debugItems.count, sourceList.debugItems.count)
            var renderItemCount = 0
            updated.forEachRenderItem { _ in
                renderItemCount += 1
            }
            XCTAssertEqual(renderItemCount, sourceList.debugItems.count)
            switch updated.effects.first?.effect {
            case let .some(.contentTransition(state)):
                XCTAssertEqual(state.transition, .text)
            case .none:
                XCTFail("missing content-transition effect")
            default:
                XCTFail("unexpected content-transition effect")
            }
        }
    }

    func testInterpolatedDisplayListReadsContentTransitionFallbackPath() throws {
        let graph = AttributeGraph()
        InterpolatableContentProbeLog.reset()

        try AttributeGraph.withCurrent(graph) {
            let displayList = graph.makeInput(value: makeDisplayList(debugItemCount: 1))
            let content = graph.makeInput(value: ProbeInterpolatableContent(value: 0))
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                DisplayList.InterpolatorGroup(),
                content: content,
                inputs: makeViewInputs(graph: graph),
                animatesSize: false,
                defersRender: true
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)

            _ = output.value
            XCTAssertEqual(InterpolatableContentProbeLog.modifyTransitionCalls, 0)
            XCTAssertEqual(InterpolatableContentProbeLog.defaultAnimationCalls, 0)

            content.setValue(ProbeInterpolatableContent(value: 1))
            let updated = output.value

            XCTAssertEqual(InterpolatableContentProbeLog.modifyTransitionCalls, 1)
            XCTAssertEqual(InterpolatableContentProbeLog.defaultAnimationCalls, 1)
            XCTAssertEqual(updated.effects.count, 0)
        }
    }

    private func makeDisplayList(
        debugItemCount: Int,
        itemCount: Int = 0,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 10, height: 10),
        itemKind: DisplayList.ItemRecord.Kind = .closure,
        itemEffectKind: DisplayList.ItemRecord.EffectKind? = nil
    ) -> DisplayList {
        var list = DisplayList()
        for _ in 0..<debugItemCount {
            list.appendDebugItem(bounds: bounds) { _ in }
        }
        for _ in 0..<itemCount {
            list.appendItem(
                kind: itemKind,
                bounds: bounds,
                effectKind: itemEffectKind
            ) { _ in }
        }
        return list
    }

    private func makeDisplayList(
        itemBounds: [CGRect],
        itemKind: DisplayList.ItemRecord.Kind = .closure,
        itemEffectKind: DisplayList.ItemRecord.EffectKind? = nil
    ) -> DisplayList {
        var list = DisplayList()
        for bounds in itemBounds {
            list.appendItem(
                kind: itemKind,
                bounds: bounds,
                effectKind: itemEffectKind
            ) { _ in }
        }
        return list
    }

    private func makeEffectCarrierDisplayList() -> DisplayList {
        var source = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            itemKind: .shapeFill
        )
        source.appendEffect(
            .contentTransition(ContentTransition.State(transition: .opacity)),
            contents: makeDisplayList(
                debugItemCount: 0,
                itemCount: 1,
                itemKind: .text
            )
        )
        return source
    }

    private func displayList<Modifier: ViewModifier>(
        applying modifier: Modifier,
        to source: DisplayList
    ) throws -> DisplayList {
        let graph = AttributeGraph()
        return try AttributeGraph.withCurrent(graph) {
            let modifierAttr = graph.makeInput(value: modifier)
            let sourceAttr = graph.makeInput(value: source)
            let outputs = Modifier._makeView(
                modifier: _GraphValue(_attribute: modifierAttr),
                inputs: makeViewInputs(graph: graph)
            ) { _, _ in
                var outputs = _ViewOutputs()
                outputs.preferences.append(DisplayList.Key.self, node: sourceAttr.identifier)
                return outputs
            }
            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            return Attribute<DisplayList>(outputID).value
        }
    }

    private func contentTransitionContents(in list: DisplayList) throws -> DisplayList {
        XCTAssertEqual(list.effects.count, 1)
        let effect = try XCTUnwrap(list.effects.first)
        switch effect.effect {
        case let .contentTransition(state):
            XCTAssertEqual(state.transition, .opacity)
        default:
            XCTFail("Expected content-transition effect record.")
        }
        return effect.contents
    }

    private func makeResolvedImage(
        baseline: CGFloat = 1,
        shading: GraphicsContext.Shading? = nil,
        texture: Texture? = nil,
        textureTransform: CGAffineTransform = .identity,
        scaleFactor: CGFloat = 1
    ) -> GraphicsContext.ResolvedImage {
        GraphicsContext.ResolvedImage(
            baseline: baseline,
            shading: shading,
            texture: texture,
            textureTransform: textureTransform,
            scaleFactor: scaleFactor
        )
    }

    private func makeViewInputs(graph: AttributeGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time(seconds: 0)),
            cachedEnvironment: MutableBox(CachedEnvironment(environment: environment)),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
        return _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 10, height: 10)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
