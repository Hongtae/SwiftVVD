import XCTest
@testable import VVD
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

private final class CountingVectorImageProvider: AnyImageProviderBox, @unchecked Sendable {
    let symbol: ResolvedVectorSymbol
    private(set) var resolutionCount = 0

    init(symbol: ResolvedVectorSymbol) {
        self.symbol = symbol
    }

    override var requiresBackendResolution: Bool { false }

    override func makeVectorSymbol() -> ResolvedVectorSymbol? {
        resolutionCount += 1
        return symbol
    }
}

private final class NumericTransitionTestTypeface: Typeface {
    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? {
        .texture(TextureFont.GlyphData(
            texture: nil,
            offset: .zero,
            advance: CGSize(width: 10, height: 0),
            frame: .zero,
            ascender: 8,
            descender: -2
        ))
    }

    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint { .zero }
    func hasGlyph(for: UnicodeScalar) -> Bool { true }
    var lineHeight: CGFloat { 10 }
    var ascender: CGFloat { 8 }
    var descender: CGFloat { -2 }
    var identifier: String { "numeric-transition-test" }
    func isEqual(to other: any Typeface) -> Bool { self === (other as AnyObject) }
    func hashIdentity(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    func purgeResources(reason: ResourcePurgeReason) {}
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

    func modifyTransition(state: inout ContentTransition.State, to target: Self) {
        state.transition = .opacity
    }

    func defaultAnimation(to target: Self) -> Animation? {
        return .linear(duration: 0.25)
    }
}

private func installUnstyledLayer(
    in group: _ShapeStyle_InterpolatorGroup
) -> UInt32 {
    let result = group.addLayer(id: .unstyled, style: nil)
    group.resetLayerCursor()
    guard case let .direct(_, serial) = result else {
        preconditionFailure("The first shape-style layer must append directly.")
    }
    return serial
}

private struct CanvasEnvironmentProbeKey: EnvironmentKey {
    static let defaultValue = 0
}

private extension EnvironmentValues {
    var canvasEnvironmentProbe: Int {
        get { self[CanvasEnvironmentProbeKey.self] }
        set { self[CanvasEnvironmentProbeKey.self] = newValue }
    }
}

private final class InterpolatorGroupRewriteContext {
    let rendererHost: TestViewRendererHost
    let viewGraph: ViewGraph
    let time: Attribute<Time>

    init() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        var time: Attribute<Time>!
        viewGraph.data.withCurrent {
            time = viewGraph.data.graph.makeInput(value: .zero)
        }

        self.rendererHost = rendererHost
        self.viewGraph = viewGraph
        self.time = time
    }

    @discardableResult
    func rewrite(
        _ group: DisplayList.UnaryInterpolatorGroup,
        list: DisplayList,
        at currentTime: Time,
        contentOrigin: CGPoint = .zero,
        contentOffset: CGSize = .zero,
        frame: CGRect? = nil
    ) -> DisplayList {
        var output = list
        viewGraph.data.withCurrent {
            time.setValue(currentTime)
            _ = group.rewriteInterpolation(
                serial: 0,
                list: &output,
                time: time,
                frame: frame ?? list.interpolationBounds ?? .zero,
                contentOrigin: contentOrigin,
                contentOffset: contentOffset,
                version: DisplayList.Version(forUpdate: ())
            )
        }
        return output
    }

    @discardableResult
    func synchronize(
        _ group: DisplayList.UnaryInterpolatorGroup,
        seed: DisplayList.Seed,
        target: DisplayList,
        transition: ContentTransition,
        at currentTime: Time,
        supportsVFD: Bool = false,
        rasterizationOptions: RasterizationOptions = RasterizationOptions(),
        contentOrigin: CGPoint = .zero,
        contentOffset: CGSize = .zero,
        frame: CGRect? = nil
    ) -> DisplayList {
        let target = versioned(target, for: seed)
        group.update(
            contentSeed: seed,
            transition: transition,
            animation: nil,
            listener: nil,
            contentsScale: 1,
            rasterizationOptions: rasterizationOptions,
            supportsVFD: supportsVFD
        )
        return rewrite(
            group,
            list: target,
            at: currentTime,
            contentOrigin: contentOrigin,
            contentOffset: contentOffset,
            frame: frame
        )
    }

    @discardableResult
    func transition(
        _ group: DisplayList.UnaryInterpolatorGroup,
        seed: DisplayList.Seed,
        from current: DisplayList,
        to target: DisplayList,
        state: ContentTransition.State,
        at currentTime: Time,
        supportsVFD: Bool = false,
        currentOrigin: CGPoint = .zero,
        targetOrigin: CGPoint = .zero,
        contentOffset: CGSize = .zero,
        frame: CGRect? = nil
    ) -> DisplayList {
        let current = versioned(current, for: group.layer.contentSeed)
        let target = versioned(target, for: seed)
        if group.layer.contents.list != current {
            _ = synchronize(
                group,
                seed: group.layer.contentSeed,
                target: current,
                transition: state.transition,
                at: currentTime,
                supportsVFD: supportsVFD,
                rasterizationOptions: state.rasterizationOptions,
                contentOrigin: currentOrigin
            )
        }
        group.update(
            contentSeed: seed,
            transition: state.transition,
            animation: state.animation,
            listener: nil,
            contentsScale: 1,
            rasterizationOptions: state.rasterizationOptions,
            supportsVFD: supportsVFD
        )
        return rewrite(
            group,
            list: target,
            at: currentTime,
            contentOrigin: targetOrigin,
            contentOffset: contentOffset,
            frame: frame
        )
    }

    @discardableResult
    func advance(
        _ group: DisplayList.UnaryInterpolatorGroup,
        to currentTime: Time,
        contentOrigin: CGPoint = .zero,
        contentOffset: CGSize = .zero,
        frame: CGRect? = nil
    ) -> DisplayList {
        rewrite(
            group,
            list: group.layer.contents.list,
            at: currentTime,
            contentOrigin: contentOrigin,
            contentOffset: contentOffset,
            frame: frame
        )
    }

    private func versioned(
        _ list: DisplayList,
        for seed: DisplayList.Seed
    ) -> DisplayList {
        var list = list
        let version = DisplayList.Version(value: Int(seed.value))
        for index in list.items.indices {
            list.items[index].version = version
        }
        return list
    }
}

private struct InterpolatorGroupBodyVisitor: AttributeBodyVisitor {
    var group: DisplayList.InterpolatorGroup?

    mutating func visit<Body: _AttributeBody>(body: UnsafePointer<Body>) {
        group = Mirror(reflecting: body.pointee).children.first {
            $0.label == "group"
        }?.value as? DisplayList.InterpolatorGroup
    }
}

final class InterpolatableContentDisplayListTests: XCTestCase {
    // ASSERTIONS pathStorageEqualityRuntimeObserved
    private func assertPathElementsEqual(
        _ actual: Path,
        _ expected: Path,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var actualElements: [Path.Element] = []
        var expectedElements: [Path.Element] = []
        actual.forEach { actualElements.append($0) }
        expected.forEach { expectedElements.append($0) }
        XCTAssertEqual(actualElements, expectedElements, file: file, line: line)
        XCTAssertEqual(actual.boundingRect, expected.boundingRect, file: file, line: line)
    }

    private lazy var interpolationContext = InterpolatorGroupRewriteContext()

    @discardableResult
    private func beginTransition(
        _ group: DisplayList.UnaryInterpolatorGroup,
        from current: DisplayList,
        to target: DisplayList,
        state: ContentTransition.State,
        seed: DisplayList.Seed? = nil,
        at time: Time = .zero,
        supportsVFD: Bool = false
    ) -> DisplayList {
        interpolationContext.transition(
            group,
            seed: seed ?? DisplayList.Seed(
                decodedValue: group.layer.contentSeed.value &+ 1
            ),
            from: current,
            to: target,
            state: state,
            at: time,
            supportsVFD: supportsVFD
        )
    }

    @discardableResult
    private func updateInterpolators(
        _ group: DisplayList.UnaryInterpolatorGroup,
        at time: Time
    ) -> DisplayList {
        interpolationContext.advance(group, to: time)
    }

    func testInterpolatorLayerPhaseCaseOrderMatchesRuntimeSurface() {
        typealias LayerPhase = DisplayList.InterpolatorLayer.Phase

        XCTAssertEqual(MemoryLayout<LayerPhase>.size, 1)
        XCTAssertEqual(MemoryLayout<LayerPhase>.stride, 1)

        func tag(_ phase: LayerPhase) -> UInt8 {
            withUnsafeBytes(of: phase) { $0[0] }
        }

        XCTAssertEqual(tag(.pending), 0)
        XCTAssertEqual(tag(.first), 1)
        XCTAssertEqual(tag(.second), 2)
        XCTAssertEqual(tag(.running), 3)
        XCTAssertEqual(Set<LayerPhase>([.pending, .first, .second, .running]).count, 4)
    }

    func testInterpolatorLayerContentsStoresPreparedDrawingCacheFields() {
        var list = DisplayList()
        list.appendDebugItem(bounds: CGRect(x: 1, y: 2, width: 3, height: 4)) { _ in }
        var contents = DisplayList.InterpolatorLayer.Contents(
            displayList: list,
            origin: CGPoint(x: 5, y: 7),
            numericValue: 12.5
        )

        XCTAssertTrue(contents.list.hasSameInterpolationSurface(as: list))
        XCTAssertEqual(contents.origin, CGPoint(x: 5, y: 7))
        XCTAssertNil(contents.rbList)
        XCTAssertTrue(contents.nextTime.seconds.isInfinite)
        XCTAssertEqual(contents.numericValue, 12.5)

        let renderer = DisplayList.GraphicsRenderer()
        let first = contents.preparedList(using: renderer, at: .zero)
        let firstContents = contents.rbList
        let second = contents.preparedList(
            using: renderer,
            at: Time(seconds: 10)
        )
        let translated = list.translated(
            by: CGSize(width: 5, height: 7)
        )

        XCTAssertTrue(first.hasSameInterpolationSurface(as: translated))
        XCTAssertEqual(first.numericValue, 12.5)
        XCTAssertTrue(second.hasSameInterpolationSurface(as: translated))
        XCTAssertEqual(second.numericValue, 12.5)
        XCTAssertTrue((firstContents as AnyObject?) === (contents.rbList as AnyObject?))
        XCTAssertTrue(contents.nextTime.seconds.isInfinite)
    }

    func testInterpolatorLayerPreparesCurrentAndRemovedContentsWithPersistentRenderer() {
        var source = DisplayList()
        source.appendDebugItem(bounds: CGRect(x: 0, y: 0, width: 10, height: 10)) { _ in }
        var target = DisplayList()
        target.appendDebugItem(bounds: CGRect(x: 20, y: 0, width: 10, height: 10)) { _ in }

        let group = DisplayList.UnaryInterpolatorGroup(maxDuration: 1)
        beginTransition(
            group,
            from: source,
            to: target,
            state: ContentTransition.State(
                transition: .opacity,
                animation: .linear(duration: 0.25)
            )
        )
        updateInterpolators(group, at: .zero)

        XCTAssertNotNil(group.layer.renderer)
        XCTAssertNotNil(group.layer.contents.rbList)
        XCTAssertNotNil(group.layer.removed.first?.contents.rbList)
        XCTAssertTrue(group.layer.contents.nextTime.seconds.isInfinite)
        XCTAssertTrue(group.layer.removed.first?.contents.nextTime.seconds.isInfinite == true)
    }

    func testInterpolatorLayerContentsRefreshesAtRendererDeadlineThenReusesFinishedContents() {
        var body = DisplayList()
        body.appendDebugItem(bounds: CGRect(x: 0, y: 0, width: 10, height: 10)) { _ in }
        let animation = DisplayList.OpacityAnimation(
            from: _OpacityEffect(opacity: 0),
            to: _OpacityEffect(opacity: 1),
            animation: .linear(duration: 1)
        )
        let list = DisplayList.effect(.animation(animation), contents: body)
        var contents = DisplayList.InterpolatorLayer.Contents(displayList: list)
        let renderer = DisplayList.GraphicsRenderer()

        _ = contents.preparedList(using: renderer, at: .zero)
        let first = contents.rbList
        XCTAssertEqual(contents.nextTime.seconds, 0)

        _ = contents.preparedList(using: renderer, at: .zero)
        let refreshed = contents.rbList
        XCTAssertFalse((first as AnyObject?) === (refreshed as AnyObject?))

        for time in [0.1, 0.2, 0.3, 1.4] {
            _ = contents.preparedList(using: renderer, at: Time(seconds: time))
        }
        let finished = contents.rbList
        XCTAssertTrue(contents.nextTime.seconds.isInfinite)
        _ = contents.preparedList(using: renderer, at: Time(seconds: 2))
        XCTAssertTrue((finished as AnyObject?) === (contents.rbList as AnyObject?))
    }

    func testPrivateColorMatrixSurface() throws {
        XCTAssertEqual(_ColorMatrix(), _ColorMatrix(_ColorMatrix().colorMatrix))

        let sourceColor = Color(red: 0.25, green: 0.5, blue: 0.75, opacity: 0.6)
        let resolvedColor = sourceColor.resolve(in: EnvironmentValues())
        var color = _ColorMatrix(color: sourceColor, in: EnvironmentValues())
        XCTAssertEqual(color.m11, resolvedColor.linearRed)
        XCTAssertEqual(color.m22, resolvedColor.linearGreen)
        XCTAssertEqual(color.m33, resolvedColor.linearBlue)
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

    func testInterpolatorLayerUsesItemIdentityAndVersionEquality() {
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

        layer.setDisplayList(first, origin: .zero)
        layer.setDisplayList(sameSurface, origin: .zero)
        XCTAssertEqual(layer.contents.displayList.itemRecords.first?.kind, .shapeFill)

        layer.setDisplayList(changedKind, origin: .zero)
        XCTAssertEqual(
            layer.contents.displayList.itemRecords.first?.kind,
            .shapeFill
        )
        XCTAssertEqual(layer.removedCount, 0)
    }

    func testDisplayListAnimationStyleParticipatesInSurfaceMatching() throws {
        let id = try XCTUnwrap(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"))
        func styledList(
            _ animation: RBAnimation,
            id: UUID?,
            flags: UInt32 = DisplayList.StyleCommand.AnimationStyle.defaultFlags
        ) -> DisplayList {
            var list = DisplayList()
            list.appendAnimationStyle(animation, id: id, flags: flags)
            list.appendItem(
                kind: .shapeFill,
                bounds: CGRect(x: 0, y: 0, width: 10, height: 10)
            ) { _ in }
            return list
        }
        let animation = RBAnimation()
        animation.addBezierDuration(
            2,
            controlPoint1: CGPoint(x: 0.25, y: 0),
            controlPoint2: CGPoint(x: 0.75, y: 1)
        )

        let source = styledList(animation, id: id)

        let matchingAnimation = RBAnimation()
        matchingAnimation.addBezierDuration(
            2,
            controlPoint1: CGPoint(x: 0.25, y: 0),
            controlPoint2: CGPoint(x: 0.75, y: 1)
        )
        let same = styledList(matchingAnimation, id: id)

        guard case let .animation(style)? = source.renderItems.first?.styleChain.commands.first else {
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

        let delayedAnimation = RBAnimation()
        delayedAnimation.addDelay(1)
        delayedAnimation.addBezierDuration(
            2,
            controlPoint1: CGPoint(x: 0.25, y: 0),
            controlPoint2: CGPoint(x: 0.75, y: 1)
        )
        let changedAnimation = styledList(delayedAnimation, id: id)

        let changedID = styledList(
            matchingAnimation,
            id: try XCTUnwrap(UUID(uuidString: "FFEEDDCC-BBAA-9988-7766-554433221100"))
        )

        let changedFlags = styledList(matchingAnimation, id: id, flags: 0x211)

        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedAnimation))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedID))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedFlags))

        var appended = DisplayList()
        appended.append(contentsOf: source)
        XCTAssertEqual(
            appended.renderItems.first?.styleChain,
            source.renderItems.first?.styleChain
        )

        let outerAnimation = RBAnimation()
        outerAnimation.addBezierDuration(
            4,
            controlPoint1: CGPoint(x: 0.25, y: 0),
            controlPoint2: CGPoint(x: 0.75, y: 1)
        )
        appended.appendAnimationStyle(outerAnimation, id: nil, flags: 0x200)
        appended.append(contentsOf: source)
        XCTAssertEqual(appended.renderItems[1].styleChain.commands.count, 2)
        guard case let .animation(outerStyle) = appended.renderItems[1].styleChain.commands[1] else {
            XCTFail("missing outer animation style")
            return
        }
        XCTAssertTrue(outerStyle.animation.isEqual(outerAnimation))
    }

    func testRBDisplayListInterpolatorResolvesPerItemAnimationStyleChain() throws {
        let styleA = DisplayList.StyleCommand.MetadataIdentity(
            count: 1,
            namespace: try XCTUnwrap(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"))
        )
        let styleB = DisplayList.StyleCommand.MetadataIdentity(
            count: 1,
            namespace: try XCTUnwrap(UUID(uuidString: "FFEEDDCC-BBAA-9988-7766-554433221100"))
        )
        let animation2 = Animation.linear(duration: 2).rbAnimation
        let animation4 = Animation.linear(duration: 4).rbAnimation
        let idA = try XCTUnwrap(UUID(uuidString: "10213243-5465-7687-98A9-BACBDCEDFE0F"))
        let idB = try XCTUnwrap(UUID(uuidString: "0FFEDDCB-BAA9-8976-6554-433221100001"))

        func makeStyledList(
            bounds: CGRect,
            styles: [(RBAnimation, UUID?, UInt32, DisplayList.StyleCommand.MetadataIdentity)]
        ) -> DisplayList {
            var list = DisplayList()
            for (animation, id, flags, metadataIdentity) in styles {
                list.appendAnimationStyle(
                    animation,
                    id: id,
                    flags: flags,
                    metadataIdentity: metadataIdentity
                )
            }
            list.appendItem(kind: .shapeFill, bounds: bounds) { _ in }
            return list
        }

        let transition = RBTransition()
        transition.method = ContentTransition.Method.diff.method
        let effect = RBTransitionEffect()
        effect.type = ContentTransition.EffectType.opacity.type
        effect.events = 3
        effect.animationIndex = 1
        transition.addEffect(effect)

        let fromBounds = CGRect(x: 0, y: 0, width: 10, height: 20)
        let toBounds = CGRect(x: 20, y: 5, width: 30, height: 40)
        func interpolator(
            _ styles: [(RBAnimation, UUID?, UInt32, DisplayList.StyleCommand.MetadataIdentity)]
        ) -> RBDisplayListInterpolator {
            RBDisplayListInterpolator(
                from: makeStyledList(bounds: fromBounds, styles: styles),
                to: makeStyledList(bounds: toBounds, styles: styles),
                options: [.transition: transition]
            )
        }

        let outerWins = interpolator([
            (animation2, idA, 0x200, styleA),
            (animation4, idB, 0x200, styleB),
        ])
        XCTAssertEqual(outerWins.activeDuration, 4)
        XCTAssertEqual(
            outerWins.boundingRect(withProgress: 0.5),
            CGRect(x: 2.5, y: 0.625, width: 12.5, height: 22.5)
        )

        let skippedOuterDefault = interpolator([
            (animation2, idA, 0x200, styleA),
            (animation4, idB, 0x111, styleB),
        ])
        XCTAssertEqual(skippedOuterDefault.activeDuration, 2)
        XCTAssertEqual(
            skippedOuterDefault.boundingRect(withProgress: 0.5),
            CGRect(x: 5, y: 1.25, width: 15, height: 25)
        )

        let nilIDSelectsTarget = interpolator([
            (animation2, nil, 0x111, styleA),
        ])
        XCTAssertEqual(nilIDSelectsTarget.activeDuration, 2)
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

        for (list, expected) in [(gradient, redBlue), (changedGradient, blueGreen)] {
            guard case let .paint(box)? = list.itemRecords.first?.shapeStyle,
                  let paint = box as? _AnyResolvedPaint<LinearGradient._Paint> else {
                return XCTFail("Gradient records must retain their resolved paint.")
            }
            XCTAssertEqual(paint.paint.gradient.stops.map(\.color),
                           expected.stops.map { $0.color.resolve(in: EnvironmentValues()) })
            XCTAssertEqual(paint.paint.startPoint, .top)
            XCTAssertEqual(paint.paint.endPoint, .bottom)
        }
        XCTAssertTrue(gradient.hasSameInterpolationSurface(as: sameGradient))
        XCTAssertTrue(gradient.hasSameInterpolationSurface(as: erasedGradient))
        XCTAssertFalse(gradient.hasSameInterpolationSurface(as: changedGradient))
        XCTAssertFalse(gradient.hasSameInterpolationSurface(as: color))
        XCTAssertEqual(
            foreground.itemRecords.first?.shapeStyle,
            .color(Color(Color.primary.resolveHDR(in: EnvironmentValues())))
        )
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

    func testTypedShapeContentPreservesPayloadTransformAndSurfaceIdentity() throws {
        let bounds = CGRect(x: 2, y: 3, width: 10, height: 12)
        let path = Path(bounds)

        var source = DisplayList()
        source.appendShapeItem(
            path: path,
            role: .fill,
            style: Color.red,
            bounds: bounds,
            fillStyle: FillStyle(eoFill: true)
        )

        let item = try XCTUnwrap(source.items.first)
        guard case let .content(content) = item.value,
              case let .shape(shape) = content.value else {
            return XCTFail("shape should use typed display-list content")
        }
        XCTAssertEqual(shape.path, path)
        XCTAssertEqual(shape.fillStyle, FillStyle(eoFill: true))
        XCTAssertEqual(shape.transform, .identity)
        XCTAssertEqual(shape.command.record.kind, .shapeFill)

        var same = DisplayList()
        same.appendShapeItem(
            path: path,
            role: .fill,
            style: Color.red,
            bounds: bounds,
            fillStyle: FillStyle(eoFill: true)
        )
        var changedPath = DisplayList()
        changedPath.appendShapeItem(
            path: Path(ellipseIn: bounds),
            role: .fill,
            style: Color.red,
            bounds: bounds,
            fillStyle: FillStyle(eoFill: true)
        )
        XCTAssertTrue(source.hasSameInterpolationSurface(as: same))
        XCTAssertFalse(source.hasSameInterpolationSurface(as: changedPath))

        let transform = CGAffineTransform(translationX: 11, y: 13)
        var transformed = DisplayList()
        transformed.appendTransformedItem(item, affineTransform: transform)
        let transformedItem = try XCTUnwrap(transformed.items.first)
        guard case let .content(transformedContent) = transformedItem.value,
              case let .shape(transformedShape) = transformedContent.value else {
            return XCTFail("transformed shape should remain typed content")
        }
        XCTAssertEqual(transformedShape.path, path)
        XCTAssertEqual(transformedShape.transform, transform)
        XCTAssertEqual(
            transformedShape.command.bounds,
            bounds.offsetBy(dx: 11, dy: 13)
        )
    }

    func testRBDisplayListInterpolatorMixesCompatibleTypedColorShapeGeometry() throws {
        let sourceBounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let targetBounds = CGRect(x: 20, y: 10, width: 40, height: 30)
        let midpointBounds = CGRect(x: 10, y: 5, width: 30, height: 25)

        var source = DisplayList()
        source.appendShapeItem(
            path: Path(sourceBounds),
            role: .fill,
            style: Color.red,
            bounds: sourceBounds
        )
        var target = DisplayList()
        target.appendShapeItem(
            path: Path(targetBounds),
            role: .fill,
            style: Color.red,
            bounds: targetBounds
        )

        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [:]
        )
        let midpoint = interpolator.copyContents(withProgress: 0.5)

        XCTAssertEqual(midpoint.items.count, 1)
        XCTAssertEqual(midpoint.interpolationBounds, midpointBounds)
        XCTAssertEqual(midpoint.itemRecords.first?.kind, .shapeFill)
        XCTAssertNil(midpoint.itemRecords.first?.effectKind)
        XCTAssertEqual(midpoint.itemRecords.first?.bounds, midpointBounds)
        XCTAssertEqual(midpoint.itemRecords.first?.shapeStyle, .color(.red))

        let item = try XCTUnwrap(midpoint.items.first)
        guard case let .content(content) = item.value,
              case let .shape(shape) = content.value else {
            return XCTFail("compatible shape geometry should use one typed mixed item")
        }
        assertPathElementsEqual(shape.path, Path(midpointBounds))
        XCTAssertEqual(shape.command.bounds, midpointBounds)
        XCTAssertTrue(shape.transform.isIdentity)

        XCTAssertEqual(
            interpolator.copyContents(withProgress: 0).items.first?.command,
            source.items.first?.command
        )
        XCTAssertEqual(
            interpolator.copyContents(withProgress: 1).items.first?.command,
            target.items.first?.command
        )

        var changedColor = DisplayList()
        changedColor.appendShapeItem(
            path: Path(targetBounds),
            role: .fill,
            style: Color.blue,
            bounds: targetBounds
        )
        XCTAssertNil(
            RBDisplayListInterpolator(
                from: source,
                to: changedColor,
                options: [:]
            ).copyContents(withProgress: 0.5).itemRecords.first?.effectKind
        )

        var incompatiblePath = DisplayList()
        incompatiblePath.appendShapeItem(
            path: Path(ellipseIn: targetBounds),
            role: .fill,
            style: Color.red,
            bounds: targetBounds
        )
        XCTAssertEqual(
            RBDisplayListInterpolator(
                from: source,
                to: incompatiblePath,
                options: [:]
            ).copyContents(withProgress: 0.5).itemRecords.first?.effectKind,
            .crossFade
        )
    }

    func testRBDisplayListInterpolatorUsesObservedAffineTransformMixRules() throws {
        let localBounds = CGRect(x: 0, y: 0, width: 10, height: 10)

        func shapeList(_ transform: CGAffineTransform) throws -> DisplayList {
            var base = DisplayList()
            base.appendShapeItem(
                path: Path(localBounds),
                role: .fill,
                style: Color.red,
                bounds: localBounds
            )
            var transformed = DisplayList()
            transformed.appendTransformedItem(
                try XCTUnwrap(base.items.first),
                affineTransform: transform
            )
            return transformed
        }

        func midpointTransform(
            from source: CGAffineTransform,
            to target: CGAffineTransform
        ) throws -> CGAffineTransform {
            let midpoint = RBDisplayListInterpolator(
                from: try shapeList(source),
                to: try shapeList(target)
            ).copyContents(withProgress: 0.5)
            let item = try XCTUnwrap(midpoint.items.first)
            guard case let .content(content) = item.value,
                  case let .shape(shape) = content.value else {
                XCTFail("compatible transforms should use one typed shape item")
                return .identity
            }
            return shape.transform
        }

        func assertTransform(
            _ actual: CGAffineTransform,
            _ expected: CGAffineTransform,
            accuracy: CGFloat = 0.000_001,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(actual.a, expected.a, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actual.b, expected.b, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actual.c, expected.c, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actual.d, expected.d, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actual.tx, expected.tx, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actual.ty, expected.ty, accuracy: accuracy, file: file, line: line)
        }

        assertTransform(
            try midpointTransform(
                from: .identity,
                to: CGAffineTransform(rotationAngle: .pi / 2)
            ),
            CGAffineTransform(rotationAngle: .pi / 4)
        )
        assertTransform(
            try midpointTransform(
                from: CGAffineTransform(rotationAngle: 170 * .pi / 180),
                to: CGAffineTransform(rotationAngle: -170 * .pi / 180)
            ),
            CGAffineTransform(rotationAngle: .pi)
        )
        assertTransform(
            try midpointTransform(
                from: .identity,
                to: CGAffineTransform(a: 1, b: 0.5, c: 0.25, d: 1, tx: 8, ty: 4)
            ),
            CGAffineTransform(
                a: 1.030687220,
                b: 0.243312247,
                c: 0.166990661,
                d: 0.955231907,
                tx: 4,
                ty: 2
            )
        )
        assertTransform(
            try midpointTransform(
                from: CGAffineTransform(scaleX: -1, y: 1),
                to: CGAffineTransform(scaleX: 1, y: -1)
            ),
            CGAffineTransform(a: 0, b: 0, c: 0, d: 0, tx: 0, ty: 0)
        )

        let incompatible = RBDisplayListInterpolator(
            from: try shapeList(.identity),
            to: try shapeList(CGAffineTransform(scaleX: 1, y: 0))
        ).copyContents(withProgress: 0.5)
        XCTAssertEqual(incompatible.itemRecords.first?.effectKind, .crossFade)
    }

    func testRBDisplayListInterpolatorMixesTypedShapeColorInOklabAcrossColorSpacesAndAlpha() throws {
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)

        func midpointColor(
            from sourceColor: VUI.Color,
            to targetColor: VUI.Color
        ) throws -> VUI.Color {
            var source = DisplayList()
            source.appendShapeItem(
                path: Path(bounds),
                role: .fill,
                style: sourceColor,
                bounds: bounds
            )
            var target = DisplayList()
            target.appendShapeItem(
                path: Path(bounds),
                role: .fill,
                style: targetColor,
                bounds: bounds
            )
            let contents = RBDisplayListInterpolator(
                from: source,
                to: target,
                options: [:]
            ).copyContents(withProgress: 0.5)
            XCTAssertEqual(contents.items.count, 1)
            XCTAssertNil(contents.itemRecords.first?.effectKind)
            let color = contents.items.first.flatMap { item -> VUI.Color? in
                guard case let .shape(_, .some(.color(color)), _, _, _) = item.command else {
                    return nil
                }
                return color
            }
            return try XCTUnwrap(color)
        }

        let red = VUI.Color(.sRGB, red: 1, green: 0, blue: 0)
        let blue = VUI.Color(.sRGB, red: 0, green: 0, blue: 1)
        let sRGBMidpoint = try midpointColor(from: red, to: blue)
        XCTAssertEqual(sRGBMidpoint.renderingComponents().colorSpace, .sRGB)
        XCTAssertEqual(sRGBMidpoint.renderingComponents().red, 0.5504410671, accuracy: 0.000_001)
        XCTAssertEqual(sRGBMidpoint.renderingComponents().green, 0.3256206847, accuracy: 0.000_001)
        XCTAssertEqual(sRGBMidpoint.renderingComponents().blue, 0.6365006535, accuracy: 0.000_001)
        XCTAssertEqual(sRGBMidpoint.renderingComponents().alpha, 1, accuracy: 0.000_001)

        let linearRed = VUI.Color(.sRGBLinear, red: 1, green: 0, blue: 0)
        let linearBlue = VUI.Color(.sRGBLinear, red: 0, green: 0, blue: 1)
        let linearMidpoint = try midpointColor(from: linearRed, to: linearBlue)
        XCTAssertEqual(linearMidpoint.renderingComponents().colorSpace, .sRGB)
        XCTAssertEqual(linearMidpoint.resolve(in: EnvironmentValues()).linearRed, 0.2637342898, accuracy: 0.000_001)
        XCTAssertEqual(linearMidpoint.resolve(in: EnvironmentValues()).linearGreen, 0.0865716757, accuracy: 0.000_001)
        XCTAssertEqual(linearMidpoint.resolve(in: EnvironmentValues()).linearBlue, 0.3628242654, accuracy: 0.000_001)
        XCTAssertEqual(linearMidpoint.renderingComponents().alpha, 1, accuracy: 0.000_001)

        let p3Red = VUI.Color(.displayP3, red: 1, green: 0, blue: 0)
        let p3Blue = VUI.Color(.displayP3, red: 0, green: 0, blue: 1)
        let p3Midpoint = try midpointColor(from: p3Red, to: p3Blue)
        XCTAssertEqual(p3Midpoint.renderingComponents().colorSpace, .displayP3)
        XCTAssertEqual(p3Midpoint.renderingComponents().red, 0.5674134830, accuracy: 0.000_001)
        XCTAssertEqual(p3Midpoint.renderingComponents().green, 0.3382744906, accuracy: 0.000_001)
        XCTAssertEqual(p3Midpoint.renderingComponents().blue, 0.6287854995, accuracy: 0.000_001)
        XCTAssertEqual(p3Midpoint.renderingComponents().alpha, 1, accuracy: 0.000_001)

        let sRGBToP3Midpoint = try midpointColor(from: red, to: p3Blue)
        XCTAssertEqual(sRGBToP3Midpoint.renderingComponents().colorSpace, .sRGB)
        XCTAssertEqual(sRGBToP3Midpoint.renderingComponents().red, 0.5552106371, accuracy: 0.000_001)
        XCTAssertEqual(sRGBToP3Midpoint.renderingComponents().green, 0.3330116465, accuracy: 0.000_001)
        XCTAssertEqual(sRGBToP3Midpoint.renderingComponents().blue, 0.6563702302, accuracy: 0.000_001)
        XCTAssertEqual(sRGBToP3Midpoint.renderingComponents().alpha, 1, accuracy: 0.000_001)

        let p3ToSRGBMidpoint = try midpointColor(from: p3Red, to: blue)
        XCTAssertEqual(p3ToSRGBMidpoint.renderingComponents().colorSpace, .displayP3)
        XCTAssertEqual(p3ToSRGBMidpoint.renderingComponents().red, 0.5621900129, accuracy: 0.000_001)
        XCTAssertEqual(p3ToSRGBMidpoint.renderingComponents().green, 0.3308116657, accuracy: 0.000_001)
        XCTAssertEqual(p3ToSRGBMidpoint.renderingComponents().blue, 0.6096897172, accuracy: 0.000_001)
        XCTAssertEqual(p3ToSRGBMidpoint.renderingComponents().alpha, 1, accuracy: 0.000_001)

        let transparentBlue = VUI.Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 0)
        let opaqueToTransparent = try midpointColor(from: red, to: transparentBlue)
        XCTAssertEqual(opaqueToTransparent.renderingComponents().red, 1, accuracy: 0.000_001)
        XCTAssertEqual(opaqueToTransparent.renderingComponents().green, 0, accuracy: 0.000_001)
        XCTAssertEqual(opaqueToTransparent.renderingComponents().blue, 0, accuracy: 0.000_001)
        XCTAssertEqual(opaqueToTransparent.renderingComponents().alpha, 0.5, accuracy: 0.000_001)

        let transparentRed = VUI.Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0)
        let transparentToOpaque = try midpointColor(from: transparentRed, to: blue)
        XCTAssertEqual(transparentToOpaque.renderingComponents().red, 0, accuracy: 0.000_001)
        XCTAssertEqual(transparentToOpaque.renderingComponents().green, 0, accuracy: 0.000_001)
        XCTAssertEqual(transparentToOpaque.renderingComponents().blue, 1, accuracy: 0.000_001)
        XCTAssertEqual(transparentToOpaque.renderingComponents().alpha, 0.5, accuracy: 0.000_001)

        let quarterRed = VUI.Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.25)
        let threeQuarterBlue = VUI.Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 0.75)
        let alphaMidpoint = try midpointColor(from: quarterRed, to: threeQuarterBlue)
        XCTAssertEqual(alphaMidpoint.renderingComponents().red, 0.3164174757, accuracy: 0.000_001)
        XCTAssertEqual(alphaMidpoint.renderingComponents().green, 0.2788379121, accuracy: 0.000_001)
        XCTAssertEqual(alphaMidpoint.renderingComponents().blue, 0.8218085756, accuracy: 0.000_001)
        XCTAssertEqual(alphaMidpoint.renderingComponents().alpha, 0.5, accuracy: 0.000_001)
    }

    func testRBDisplayListInterpolatorMixesTypedLinearGradientStopsGeometryAndFallback() throws {
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let red = Color(.sRGB, red: 1, green: 0, blue: 0)
        let green = Color(.sRGB, red: 0, green: 1, blue: 0)
        let blue = Color(.sRGB, red: 0, green: 0, blue: 1)
        let yellow = Color(.sRGB, red: 1, green: 1, blue: 0)
        let magenta = Color(.sRGB, red: 1, green: 0, blue: 1)

        func makeList(
            gradient: Gradient,
            startPoint: CGPoint,
            endPoint: CGPoint,
            options: GraphicsContext.GradientOptions = []
        ) -> DisplayList {
            let command = DisplayList.ItemCommand.shape(
                role: .fill,
                style: .gradient(gradient),
                fillStyle: FillStyle(),
                strokeStyle: nil,
                bounds: bounds
            )
            let content = DisplayList.Content(
                path: Path(bounds),
                shading: .linearGradient(
                    gradient,
                    startPoint: startPoint,
                    endPoint: endPoint,
                    options: options
                ),
                fillStyle: FillStyle(),
                strokeStyle: nil,
                command: command
            )
            var list = DisplayList()
            list.items.append(DisplayList.Item(
                content: content,
                frame: bounds,
                identity: .none,
                version: DisplayList.Version(value: 0)
            ))
            list.recordInterpolationBounds(bounds)
            return list
        }

        func mixedShape(in list: DisplayList) throws -> DisplayList.Content.ShapeValue {
            let item = try XCTUnwrap(list.items.first)
            guard case let .content(content) = item.value,
                  case let .shape(shape) = content.value else {
                throw NSError(domain: "VUITests", code: 1)
            }
            return shape
        }

        func assertColor(
            _ color: VUI.Color,
            red: Double,
            green: Double,
            blue: Double,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(color.renderingComponents().colorSpace, .sRGB, file: file, line: line)
            XCTAssertEqual(color.renderingComponents().red, red, accuracy: 0.000_001, file: file, line: line)
            XCTAssertEqual(color.renderingComponents().green, green, accuracy: 0.000_001, file: file, line: line)
            XCTAssertEqual(color.renderingComponents().blue, blue, accuracy: 0.000_001, file: file, line: line)
            XCTAssertEqual(color.renderingComponents().alpha, 1, accuracy: 0.000_001, file: file, line: line)
        }

        let sourceGradient = Gradient(stops: [
            .init(color: red, location: 0),
            .init(color: blue, location: 0.6),
        ])
        let targetGradient = Gradient(stops: [
            .init(color: green, location: 0.2),
            .init(color: yellow, location: 1),
        ])
        let source = makeList(
            gradient: sourceGradient,
            startPoint: CGPoint(x: 0, y: 10),
            endPoint: CGPoint(x: 20, y: 10)
        )
        let target = makeList(
            gradient: targetGradient,
            startPoint: CGPoint(x: 10, y: 0),
            endPoint: CGPoint(x: 10, y: 20)
        )
        let midpoint = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [:]
        ).copyContents(withProgress: 0.5)

        XCTAssertEqual(midpoint.items.count, 1)
        XCTAssertNil(midpoint.itemRecords.first?.effectKind)
        let midpointShape = try mixedShape(in: midpoint)
        guard case let .linearGradient(
            midpointGradient,
            midpointStart,
            midpointEnd,
            midpointOptions
        ) = try XCTUnwrap(midpointShape.shading.properties.first) else {
            return XCTFail("midpoint should retain typed linear-gradient shading")
        }
        XCTAssertEqual(midpointStart, CGPoint(x: 5, y: 5))
        XCTAssertEqual(midpointEnd, CGPoint(x: 15, y: 15))
        XCTAssertEqual(midpointOptions, [])
        XCTAssertEqual(midpointGradient.stops.map(\.location), [0.1, 0.8])
        assertColor(midpointGradient.stops[0].color, red: 0.5, green: 0.5, blue: 0)
        assertColor(midpointGradient.stops[1].color, red: 0.5, green: 0.5, blue: 0.5)
        guard case let .shape(_, .some(.gradient(commandGradient)), _, _, _) = midpointShape.command else {
            return XCTFail("midpoint command should retain its typed gradient")
        }
        XCTAssertEqual(commandGradient, midpointGradient)

        let threeStopTarget = Gradient(stops: [
            .init(color: green, location: 0),
            .init(color: magenta, location: 0.5),
            .init(color: yellow, location: 1),
        ])
        let countMismatchMidpoint = RBDisplayListInterpolator(
            from: makeList(
                gradient: Gradient(colors: [red, blue]),
                startPoint: .zero,
                endPoint: CGPoint(x: 20, y: 0)
            ),
            to: makeList(
                gradient: threeStopTarget,
                startPoint: .zero,
                endPoint: CGPoint(x: 20, y: 0)
            ),
            options: [:]
        ).copyContents(withProgress: 0.5)
        let countMismatchShape = try mixedShape(in: countMismatchMidpoint)
        guard case let .linearGradient(countMismatchGradient, _, _, _) = try XCTUnwrap(
            countMismatchShape.shading.properties.first
        ) else {
            return XCTFail("different stop counts should produce a typed union gradient")
        }
        XCTAssertEqual(countMismatchGradient.stops.map(\.location), [0, 0.5, 1])
        assertColor(countMismatchGradient.stops[0].color, red: 0.5, green: 0.5, blue: 0)
        assertColor(countMismatchGradient.stops[1].color, red: 0.75, green: 0, blue: 0.75)
        assertColor(countMismatchGradient.stops[2].color, red: 0.5, green: 0.5, blue: 0.5)

        let optionsMismatch = RBDisplayListInterpolator(
            from: source,
            to: makeList(
                gradient: targetGradient,
                startPoint: CGPoint(x: 10, y: 0),
                endPoint: CGPoint(x: 10, y: 20),
                options: [.repeat]
            ),
            options: [:]
        ).copyContents(withProgress: 0.5)
        XCTAssertEqual(optionsMismatch.itemRecords.first?.effectKind, .crossFade)
    }

    func testRBDisplayListInterpolatorMixesTypedRadialAndConicGradientGeometryAndRejectsKindMismatch() throws {
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let gradient = Gradient(colors: [
            Color(.sRGB, red: 1, green: 0, blue: 0),
            Color(.sRGB, red: 0, green: 0, blue: 1),
        ])

        func makeList(
            shading: GraphicsContext.Shading,
            commandGradient: Gradient = gradient
        ) -> DisplayList {
            let command = DisplayList.ItemCommand.shape(
                role: .fill,
                style: .gradient(commandGradient),
                fillStyle: FillStyle(),
                strokeStyle: nil,
                bounds: bounds
            )
            let content = DisplayList.Content(
                path: Path(bounds),
                shading: shading,
                fillStyle: FillStyle(),
                strokeStyle: nil,
                command: command
            )
            var list = DisplayList()
            list.items.append(DisplayList.Item(
                content: content,
                frame: bounds,
                identity: .none,
                version: DisplayList.Version(value: 0)
            ))
            list.recordInterpolationBounds(bounds)
            return list
        }

        func mixedShading(from source: DisplayList, to target: DisplayList) throws -> GraphicsContext.Shading {
            let midpoint = RBDisplayListInterpolator(
                from: source,
                to: target,
                options: [:]
            ).copyContents(withProgress: 0.5)
            XCTAssertEqual(midpoint.items.count, 1)
            XCTAssertNil(midpoint.itemRecords.first?.effectKind)
            let item = try XCTUnwrap(midpoint.items.first)
            guard case let .content(content) = item.value,
                  case let .shape(shape) = content.value else {
                throw NSError(domain: "VUITests", code: 2)
            }
            return shape.shading
        }

        let radialSource = makeList(shading: .radialGradient(
            gradient,
            center: CGPoint(x: 5, y: 10),
            startRadius: 0,
            endRadius: 15
        ))
        let radialTarget = makeList(shading: .radialGradient(
            gradient,
            center: CGPoint(x: 15, y: 10),
            startRadius: 2,
            endRadius: 10
        ))
        let radialMidpoint = try mixedShading(from: radialSource, to: radialTarget)
        guard case let .radialGradient(
            radialGradient,
            radialCenter,
            radialStartRadius,
            radialEndRadius,
            radialOptions
        ) = try XCTUnwrap(radialMidpoint.properties.first) else {
            return XCTFail("radial gradients should retain their typed shading kind")
        }
        XCTAssertEqual(radialGradient, gradient)
        XCTAssertEqual(radialCenter, CGPoint(x: 10, y: 10))
        XCTAssertEqual(radialStartRadius, 1)
        XCTAssertEqual(radialEndRadius, 12.5)
        XCTAssertEqual(radialOptions, [])

        let conicSource = makeList(shading: .conicGradient(
            gradient,
            center: CGPoint(x: 6, y: 10),
            angle: .radians(0)
        ))
        let conicTarget = makeList(shading: .conicGradient(
            gradient,
            center: CGPoint(x: 14, y: 10),
            angle: .radians(.pi / 2)
        ))
        let conicMidpoint = try mixedShading(from: conicSource, to: conicTarget)
        guard case let .conicGradient(
            conicGradient,
            conicCenter,
            conicAngle,
            conicOptions
        ) = try XCTUnwrap(conicMidpoint.properties.first) else {
            return XCTFail("conic gradients should retain their typed shading kind")
        }
        XCTAssertEqual(conicGradient, gradient)
        XCTAssertEqual(conicCenter, CGPoint(x: 10, y: 10))
        XCTAssertEqual(conicAngle.radians, .pi / 4, accuracy: 0.000_001)
        XCTAssertEqual(conicOptions, [])

        let linearTarget = makeList(shading: .linearGradient(
            gradient,
            startPoint: CGPoint(x: 0, y: 10),
            endPoint: CGPoint(x: 20, y: 10)
        ))
        let kindMismatch = RBDisplayListInterpolator(
            from: linearTarget,
            to: radialTarget,
            options: [:]
        ).copyContents(withProgress: 0.5)
        XCTAssertEqual(kindMismatch.itemRecords.first?.effectKind, .crossFade)

        let radialOptionsMismatch = makeList(shading: .radialGradient(
            gradient,
            center: CGPoint(x: 15, y: 10),
            startRadius: 2,
            endRadius: 10,
            options: [.repeat]
        ))
        XCTAssertEqual(
            RBDisplayListInterpolator(
                from: radialSource,
                to: radialOptionsMismatch,
                options: [:]
            ).copyContents(withProgress: 0.5).itemRecords.first?.effectKind,
            .crossFade
        )
    }

    func testRBDisplayListInterpolatorMixesCompatibleTypedStrokeGeometry() throws {
        let sourceBounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let targetBounds = CGRect(x: 20, y: 10, width: 40, height: 30)
        let midpointBounds = CGRect(x: 10, y: 5, width: 30, height: 25)
        let sourcePathBounds = CGRect(x: 1, y: 1, width: 18, height: 18)
        let targetPathBounds = CGRect(x: 21, y: 11, width: 38, height: 28)
        let midpointPathBounds = CGRect(x: 11, y: 6, width: 28, height: 23)
        let strokeStyle = StrokeStyle(lineWidth: 2)

        var source = DisplayList()
        source.appendShapeItem(
            path: Path(sourcePathBounds),
            role: .stroke,
            style: Color.red,
            bounds: sourceBounds,
            strokeStyle: strokeStyle
        )
        var target = DisplayList()
        target.appendShapeItem(
            path: Path(targetPathBounds),
            role: .stroke,
            style: Color.red,
            bounds: targetBounds,
            strokeStyle: strokeStyle
        )

        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [:]
        )
        let midpoint = interpolator.copyContents(withProgress: 0.5)

        XCTAssertEqual(midpoint.items.count, 1)
        XCTAssertEqual(midpoint.interpolationBounds, midpointBounds)
        XCTAssertEqual(midpoint.itemRecords.first?.kind, .shapeStroke)
        XCTAssertNil(midpoint.itemRecords.first?.effectKind)
        XCTAssertEqual(midpoint.itemRecords.first?.bounds, midpointBounds)
        XCTAssertEqual(midpoint.itemRecords.first?.strokeStyle, strokeStyle)

        let item = try XCTUnwrap(midpoint.items.first)
        guard case let .content(content) = item.value,
              case let .shape(shape) = content.value else {
            return XCTFail("compatible stroke geometry should use one typed mixed item")
        }
        assertPathElementsEqual(shape.path, Path(midpointPathBounds))
        XCTAssertEqual(shape.strokeStyle, strokeStyle)
        XCTAssertEqual(shape.command.bounds, midpointBounds)

        var changedLineWidth = DisplayList()
        changedLineWidth.appendShapeItem(
            path: Path(targetPathBounds),
            role: .stroke,
            style: Color.red,
            bounds: targetBounds,
            strokeStyle: StrokeStyle(lineWidth: 4)
        )
        XCTAssertEqual(
            RBDisplayListInterpolator(
                from: source,
                to: changedLineWidth,
                options: [:]
            ).copyContents(withProgress: 0.5).itemRecords.first?.effectKind,
            .crossFade
        )
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

    func testTypedImageContentPreservesPayloadAcrossTransformation() throws {
        let bounds = CGRect(x: 2, y: 3, width: 10, height: 12)
        let image = makeResolvedImage(baseline: 4, shading: .color(.red))
        var source = DisplayList()
        source.appendImageItem(image, bounds: bounds, opacity: 0.25)

        let item = try XCTUnwrap(source.items.first)
        guard case let .content(content) = item.value,
              case let .image(imageValue) = content.value else {
            return XCTFail("image should use typed display-list content")
        }
        XCTAssertEqual(imageValue.image.baseline, 4)
        XCTAssertEqual(imageValue.frame, bounds)
        XCTAssertEqual(imageValue.transform, .identity)
        XCTAssertEqual(imageValue.command.record.kind, .image)

        let transform = CGAffineTransform(a: 1, b: 0.25, c: 0, d: 1, tx: 7, ty: 9)
        var transformed = DisplayList()
        transformed.appendTransformedItem(item, affineTransform: transform)
        let transformedItem = try XCTUnwrap(transformed.items.first)
        guard case let .content(transformedContent) = transformedItem.value,
              case let .image(transformedImage) = transformedContent.value else {
            return XCTFail("transformed image should remain typed content")
        }
        XCTAssertEqual(transformedImage.image.baseline, 4)
        XCTAssertEqual(transformedImage.frame, bounds)
        XCTAssertEqual(transformedImage.transform, transform)
        XCTAssertEqual(transformedItem.opacity, 0.25)
        XCTAssertEqual(
            transformedImage.command.bounds,
            bounds.applying(transform).standardized
        )
    }

    func testRBDisplayListInterpolatorMixesCompatibleImageGeometryAsOneItem() throws {
        let sourceBounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let targetBounds = CGRect(x: 20, y: 5, width: 30, height: 40)
        let midpointBounds = CGRect(x: 10, y: 2.5, width: 25, height: 30)
        let texture = ProbeTexture()
        let image = makeResolvedImage(texture: texture)

        var source = DisplayList()
        source.appendImageItem(image, bounds: sourceBounds, opacity: 0.25)
        var target = DisplayList()
        target.appendImageItem(image, bounds: targetBounds, opacity: 0.75)

        var sameGeometryDifferentAlpha = DisplayList()
        sameGeometryDifferentAlpha.appendImageItem(
            image,
            bounds: sourceBounds,
            opacity: 0.75
        )
        XCTAssertFalse(source.hasSameInterpolationSurface(as: sameGeometryDifferentAlpha))

        XCTAssertEqual(
            RBDisplayListInterpolator(from: source, to: target, options: [:])
                .copyContents(withProgress: 0).items.first?.opacity,
            0.25
        )
        XCTAssertEqual(
            RBDisplayListInterpolator(from: source, to: target, options: [:])
                .copyContents(withProgress: 1).items.first?.opacity,
            0.75
        )

        let midpoint = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [:]
        ).copyContents(withProgress: 0.5)

        XCTAssertEqual(midpoint.items.count, 1)
        XCTAssertEqual(midpoint.interpolationBounds, midpointBounds)
        XCTAssertEqual(midpoint.itemRecords.first?.kind, .image)
        XCTAssertNil(midpoint.itemRecords.first?.effectKind)
        XCTAssertEqual(midpoint.itemRecords.first?.bounds, midpointBounds)

        let item = try XCTUnwrap(midpoint.items.first)
        guard case let .content(content) = item.value,
              case let .image(imageValue) = content.value else {
            return XCTFail("compatible image geometry should use one typed mixed item")
        }
        XCTAssertEqual(imageValue.frame, midpointBounds)
        XCTAssertEqual(imageValue.transform, .identity)
        XCTAssertEqual(imageValue.command.bounds, midpointBounds)
        XCTAssertEqual(item.opacity, 0.5)

        var differentTexture = DisplayList()
        differentTexture.appendImageItem(
            makeResolvedImage(texture: ProbeTexture()),
            bounds: targetBounds
        )
        XCTAssertEqual(
            RBDisplayListInterpolator(
                from: source,
                to: differentTexture,
                options: [:]
            ).copyContents(withProgress: 0.5).itemRecords.first?.effectKind,
            .crossFade
        )
    }

    func testSymbolAnimatorUsesStyleSpecificLayeredImageComposition() throws {
        let sourceSymbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
            name: "photo.fill",
            variableValue: nil,
            bundle: nil
        ))
        let targetSymbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
            name: "draw",
            variableValue: nil,
            bundle: nil
        ))
        let sourceImage = ImageDrawing(symbol: sourceSymbol)
        let targetImage = ImageDrawing(symbol: targetSymbol)

        func makeAnimator(
            transition: ContentTransition,
            source: ImageDrawing = sourceImage,
            target: ImageDrawing = targetImage
        ) -> SymbolAnimator {
            var transaction = Transaction()
            transaction.animation = .linear(duration: 3)
            let animator = SymbolAnimator(image: source)
            animator.update(
                image: target,
                state: ContentTransition.State(transition: transition),
                transaction: transaction
            )
            XCTAssertTrue(animator.isAnimating)
            _ = animator.presentation(at: .zero)
            return animator
        }

        let layered = makeAnimator(
            transition: .symbolEffect(.replace)
        )
        let layeredPresentation = try XCTUnwrap(
            layered.presentation(at: Time(seconds: 0.3))
        )
        XCTAssertEqual(layeredPresentation.symbols.count, 2)
        let layeredTarget = layeredPresentation.symbols[0]
        let layeredSource = layeredPresentation.symbols[1]
        XCTAssertEqual(layeredSource.levels.count, 1)
        XCTAssertEqual(layeredTarget.levels.count, 2)
        let drawProgresses = try XCTUnwrap(
            layeredTarget.drawProgresses
        )
        XCTAssertEqual(drawProgresses.count, 2)
        XCTAssertTrue(drawProgresses.allSatisfy { $0 > 0 && $0 < 1 })
        XCTAssertNotEqual(drawProgresses[0], drawProgresses[1])

        let downUp = makeAnimator(
            transition: .symbolEffect(ReplaceSymbolEffect.replace.downUp)
        )
        let downUpPresentation = try XCTUnwrap(
            downUp.presentation(at: Time(seconds: 0.3))
        )
        let downUpTarget = downUpPresentation.symbols[0]
        XCTAssertEqual(downUpTarget.levels.count, 2)
        XCTAssertGreaterThan(
            downUpTarget.levels[0].scale,
            downUpTarget.levels[1].scale
        )
        XCTAssertNil(downUpTarget.drawProgresses)
        let downUpSource = try XCTUnwrap(
            downUp.presentation(at: Time(seconds: 0.125))
        ).symbols[1]
        XCTAssertEqual(downUpSource.levels[0].opacity, 1)
        XCTAssertLessThan(downUpSource.levels[0].scale, 1)

        let upUp = makeAnimator(
            transition: .symbolEffect(ReplaceSymbolEffect.replace.upUp)
        )
        let upUpSource = try XCTUnwrap(
            upUp.presentation(at: Time(seconds: 0.125))
        ).symbols[1]
        XCTAssertGreaterThan(upUpSource.levels[0].opacity, 0)
        XCTAssertLessThan(upUpSource.levels[0].opacity, 1)
        XCTAssertGreaterThan(upUpSource.levels[0].scale, 1)

        let whole = makeAnimator(
            transition: .symbolEffect(
                ReplaceSymbolEffect.replace.wholeSymbol
            )
        )
        let wholePresentation = try XCTUnwrap(
            whole.presentation(at: Time(seconds: 0.3))
        )
        XCTAssertEqual(wholePresentation.symbols.count, 2)
        XCTAssertEqual(wholePresentation.symbols[0].levels.count, 1)
        XCTAssertEqual(wholePresentation.symbols[1].levels.count, 1)

        let offUp = makeAnimator(
            transition: .symbolEffect(ReplaceSymbolEffect.replace.offUp)
        )
        let offUpStart = try XCTUnwrap(offUp.presentation(at: .zero))
        XCTAssertEqual(offUpStart.symbols[1].levels[0].opacity, 1)
        let offUpPresentation = try XCTUnwrap(
            offUp.presentation(at: Time(seconds: 0.01))
        )
        XCTAssertEqual(offUpPresentation.symbols[0].levels.count, 2)
        XCTAssertEqual(offUpPresentation.symbols[1].levels.count, 1)
        XCTAssertTrue(offUpPresentation.symbols[0].levels.allSatisfy {
            $0.opacity > 0
        })
        XCTAssertTrue(offUpPresentation.symbols[1].levels.allSatisfy {
            $0.opacity == 0
        })
        XCTAssertNil(offUp.presentation(at: Time(seconds: 0.25)))
        XCTAssertFalse(offUp.isAnimating)

        let reverseAutomatic = makeAnimator(
            transition: .symbolEffect(.replace),
            source: targetImage,
            target: sourceImage
        )
        let blank = try XCTUnwrap(
            reverseAutomatic.presentation(at: Time(seconds: 0.4))
        )
        XCTAssertTrue(blank.symbols.flatMap(\.levels).allSatisfy {
            $0.opacity == 0
        })
        let incoming = try XCTUnwrap(
            reverseAutomatic.presentation(at: Time(seconds: 0.6))
        )
        XCTAssertTrue(incoming.symbols[0].levels.contains { $0.opacity > 0 })

        // ASSERTIONS symbolEffectReplacementConsumerOwnershipObserved
        // ASSERTIONS symbolEffectReplaceSpatialRuntimeObserved
        // ASSERTIONS symbolEffectReplaceTimelineRuntimeObserved
    }

    func testSymbolAnimatorRetargetRetainsPresentationGenerations() throws {
        func image(_ name: String) throws -> ImageDrawing {
            ImageDrawing(
                symbol: try XCTUnwrap(SymbolAssetCatalog.resolve(
                    name: name,
                    variableValue: nil,
                    bundle: nil
                ))
            )
        }

        let source = try image("photo.fill")
        let firstTarget = try image("draw")
        let secondTarget = try image("trash.fill")
        var transaction = Transaction()
        transaction.animation = .linear(duration: 3)
        let state = ContentTransition.State(
            transition: .symbolEffect(ReplaceSymbolEffect.replace.downUp)
        )
        let animator = SymbolAnimator(image: source)
        animator.update(
            image: firstTarget,
            state: state,
            transaction: transaction
        )
        _ = animator.presentation(at: .zero)
        let beforeRetarget = try XCTUnwrap(
            animator.presentation(at: Time(seconds: 0.2))
        )
        XCTAssertEqual(
            beforeRetarget.symbols.map { $0.image.symbol?.identity.name },
            ["draw", "photo.fill"]
        )
        let sourceScale = beforeRetarget.symbols[1].levels[0].scale

        animator.update(
            image: secondTarget,
            state: state,
            transaction: transaction
        )
        let firstAfterRetarget = try XCTUnwrap(
            animator.presentation(at: Time(seconds: 0.2))
        )
        XCTAssertEqual(
            firstAfterRetarget.symbols.map { $0.image.symbol?.identity.name },
            ["trash.fill", "draw", "photo.fill"]
        )
        XCTAssertEqual(
            firstAfterRetarget.symbols[2].levels[0].scale,
            sourceScale,
            accuracy: 0.000_001
        )
        XCTAssertEqual(firstAfterRetarget.symbols[1].levels[0].scale, 1)
        XCTAssertEqual(firstAfterRetarget.symbols[0].levels[0].scale, 0.5)
        XCTAssertEqual(firstAfterRetarget.symbols[0].levels[0].opacity, 0)

        let afterFirstCompletion = try XCTUnwrap(
            animator.presentation(at: Time(seconds: 0.51))
        )
        XCTAssertEqual(
            afterFirstCompletion.symbols.map {
                $0.image.symbol?.identity.name
            },
            ["trash.fill", "draw"]
        )
        XCTAssertNil(animator.presentation(at: Time(seconds: 0.71)))
        XCTAssertFalse(animator.isAnimating)

        // ASSERTIONS symbolEffectReplaceRetargetPresentationGenerationsObserved
    }

    func testRBDisplayListInterpolatorMixesCompatibleImageTintAsOneItem() throws {
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let texture = ProbeTexture()
        let sourceImage = makeResolvedImage(
            shading: .color(VUI.Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.25)),
            texture: texture
        )
        let targetImage = makeResolvedImage(
            shading: .color(VUI.Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 0.75)),
            texture: texture
        )
        var source = DisplayList()
        source.appendImageItem(sourceImage, bounds: bounds)
        var target = DisplayList()
        target.appendImageItem(targetImage, bounds: bounds)

        let midpoint = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [:]
        ).copyContents(withProgress: 0.5)
        XCTAssertEqual(midpoint.items.count, 1)
        guard case let .color(recordedTint)? = midpoint.itemRecords.first?.image?.shading,
              case let .content(content) = midpoint.items[0].value,
              case let .image(imageValue) = content.value,
              let shading = imageValue.image.shading,
              case let .color(renderedTint) = shading.properties.first else {
            return XCTFail("compatible image tint should remain one typed image item")
        }
        XCTAssertEqual(recordedTint.renderingComponents().red, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(recordedTint.renderingComponents().green, 0, accuracy: 0.000_001)
        XCTAssertEqual(recordedTint.renderingComponents().blue, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(recordedTint.renderingComponents().alpha, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(renderedTint, recordedTint)

        var untinted = DisplayList()
        untinted.appendImageItem(
            makeResolvedImage(texture: texture),
            bounds: bounds
        )
        var opaqueBlue = DisplayList()
        opaqueBlue.appendImageItem(
            makeResolvedImage(
                shading: .color(VUI.Color(.sRGB, red: 0, green: 0, blue: 1)),
                texture: texture
            ),
            bounds: bounds
        )
        let whiteToBlue = RBDisplayListInterpolator(
            from: untinted,
            to: opaqueBlue,
            options: [:]
        ).copyContents(withProgress: 0.5)
        guard case let .color(whiteToBlueTint)? =
            whiteToBlue.itemRecords.first?.image?.shading else {
            return XCTFail("missing identity-white to blue tint mix")
        }
        XCTAssertEqual(whiteToBlueTint.renderingComponents().red, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(whiteToBlueTint.renderingComponents().green, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(whiteToBlueTint.renderingComponents().blue, 1, accuracy: 0.000_001)
        XCTAssertEqual(whiteToBlueTint.renderingComponents().alpha, 1, accuracy: 0.000_001)

        var differentColorSpace = DisplayList()
        differentColorSpace.appendImageItem(
            makeResolvedImage(
                shading: .color(VUI.Color(.displayP3, red: 0, green: 0, blue: 1)),
                texture: texture
            ),
            bounds: bounds
        )
        XCTAssertEqual(
            RBDisplayListInterpolator(
                from: source,
                to: differentColorSpace,
                options: [:]
            ).copyContents(withProgress: 0.5).itemRecords.first?.effectKind,
            .crossFade
        )
    }

    func testRBDisplayListInterpolatorMixesImagePlacementInsideFixedCoverage() throws {
        let coverage = CGRect(x: 0, y: 0, width: 20, height: 20)
        let sourcePlacement = coverage
        let targetPlacement = CGRect(x: 10, y: 0, width: 20, height: 20)
        let midpointPlacement = CGRect(x: 5, y: 0, width: 20, height: 20)
        let image = makeResolvedImage(texture: ProbeTexture())

        var source = DisplayList()
        source.appendImageItem(
            image,
            bounds: coverage,
            placementRect: sourcePlacement
        )
        var target = DisplayList()
        target.appendImageItem(
            image,
            bounds: coverage,
            placementRect: targetPlacement
        )

        XCTAssertFalse(source.hasSameInterpolationSurface(as: target))
        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [:]
        )
        XCTAssertEqual(
            interpolator.copyContents(withProgress: 0)
                .itemRecords.first?.image?.placementRect,
            sourcePlacement
        )
        XCTAssertEqual(
            interpolator.copyContents(withProgress: 1)
                .itemRecords.first?.image?.placementRect,
            targetPlacement
        )

        let midpoint = interpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(midpoint.items.count, 1)
        XCTAssertEqual(midpoint.itemRecords.first?.bounds, coverage)
        XCTAssertEqual(
            midpoint.itemRecords.first?.image?.placementRect,
            midpointPlacement
        )
        XCTAssertNil(midpoint.itemRecords.first?.effectKind)

        let item = try XCTUnwrap(midpoint.items.first)
        guard case let .content(content) = item.value,
              case let .image(imageValue) = content.value else {
            return XCTFail("compatible placement should remain one typed image item")
        }
        XCTAssertEqual(imageValue.frame, midpointPlacement)
        XCTAssertEqual(imageValue.command.bounds, coverage)
        XCTAssertEqual(imageValue.image.textureTransform, .identity)
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
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
            var environment = EnvironmentValues.tracking()
            environment.canvasEnvironmentProbe = 41
            let canvas = Canvas(
                opaque: true,
                colorMode: .extendedLinear,
                rendersAsynchronously: true
            ) { _, _ in
            }
            let canvasAttr = graph.makeInput(value: canvas)
            let outputs = Canvas<EmptyView>._makeView(
                view: _GraphValue(_attribute: canvasAttr),
                inputs: makeViewInputs(graph: graph, environment: environment)
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
            guard case let .content(content) = list.items[0].value else {
                return XCTFail("Canvas should emit display-list content")
            }
            XCTAssertEqual(content.environment?.canvasEnvironmentProbe, 41)
            XCTAssertNil(content.environment?.tracker)
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

    func testInterpolatorLayerIgnoresBackendEffectRecordWhenItemVersionMatches() {
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

        layer.setDisplayList(opacity, origin: .zero)
        layer.setDisplayList(sameOpacity, origin: .zero)
        XCTAssertEqual(layer.contents.displayList.itemRecords.first?.effectKind, .opacity)

        layer.setDisplayList(blur, origin: .zero)
        XCTAssertEqual(layer.contents.displayList.itemRecords.first?.kind, .effect)
        XCTAssertEqual(
            layer.contents.displayList.itemRecords.first?.effectKind,
            .opacity
        )
        XCTAssertEqual(layer.removedCount, 0)
    }

    func testInterpolatorLayerIgnoresEffectPayloadWhenItemVersionMatches() {
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

        layer.setDisplayList(opacityEffect, origin: .zero)
        layer.setDisplayList(sameOpacityEffect, origin: .zero)
        XCTAssertEqual(layer.contents.displayList.effects.count, 1)

        layer.setDisplayList(identityEffect, origin: .zero)
        XCTAssertEqual(layer.contents.displayList.effects.count, 1)
        XCTAssertEqual(layer.removedCount, 0)
        switch layer.contents.displayList.effects.first?.effect {
        case let .contentTransition(state):
            XCTAssertEqual(state.transition, .opacity)
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
        XCTAssertEqual(midpoint.renderItems.count, 0)
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

        let item = try XCTUnwrap(effectItem.contents.items.first)
        guard case let .content(content) = item.value,
              case let .crossFade(crossFade) = content.value else {
            return XCTFail("interpolator should preserve typed cross-fade branches")
        }
        XCTAssertEqual(crossFade.source?.sourceBounds, CGRect(x: 0, y: 0, width: 10, height: 20))
        XCTAssertEqual(crossFade.source?.outputBounds, CGRect(x: 10, y: 2.5, width: 20, height: 30))
        XCTAssertEqual(crossFade.source?.contents.itemRecords.first?.kind, .shapeFill)
        XCTAssertEqual(crossFade.target?.sourceBounds, CGRect(x: 20, y: 5, width: 30, height: 40))
        XCTAssertEqual(crossFade.target?.outputBounds, CGRect(x: 10, y: 2.5, width: 20, height: 30))
        XCTAssertEqual(crossFade.target?.contents.itemRecords.first?.kind, .shapeFill)
        XCTAssertTrue(crossFade.transform.isIdentity)

        let transform = CGAffineTransform(translationX: 7, y: 9)
        var transformed = DisplayList()
        transformed.appendTransformedItem(item, affineTransform: transform)
        let transformedItem = try XCTUnwrap(transformed.items.first)
        guard case let .content(transformedContent) = transformedItem.value,
              case let .crossFade(transformedCrossFade) = transformedContent.value else {
            return XCTFail("affine transformation should preserve typed cross-fade content")
        }
        XCTAssertEqual(transformedCrossFade.transform, transform)
        XCTAssertEqual(
            transformedCrossFade.command.bounds,
            CGRect(x: 17, y: 11.5, width: 20, height: 30)
        )
        XCTAssertEqual(transformedCrossFade.source?.sourceBounds, crossFade.source?.sourceBounds)
        XCTAssertEqual(transformedCrossFade.target?.sourceBounds, crossFade.target?.sourceBounds)
    }

    func testRBDisplayListInterpolatorMixesCompatibleMaskGeometryAndAlpha() throws {
        let sourceMaskBounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let targetMaskBounds = CGRect(x: 20, y: 10, width: 40, height: 30)
        let midpointMaskBounds = CGRect(x: 10, y: 5, width: 30, height: 25)
        let contentBounds = CGRect(x: 0, y: 0, width: 80, height: 80)

        func shapeList(bounds: CGRect, color: VUI.Color) -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: Path(bounds),
                role: .fill,
                style: color,
                bounds: bounds
            )
            return list
        }

        let sourceMask = shapeList(
            bounds: sourceMaskBounds,
            color: VUI.Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.25)
        )
        let targetMask = shapeList(
            bounds: targetMaskBounds,
            color: VUI.Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.75)
        )
        let source = DisplayList.effect(
            .mask(sourceMask, []),
            contents: shapeList(
                bounds: contentBounds,
                color: VUI.Color(.sRGB, red: 1, green: 0, blue: 0)
            )
        )
        let target = DisplayList.effect(
            .mask(targetMask, []),
            contents: shapeList(
                bounds: contentBounds,
                color: VUI.Color(.sRGB, red: 1, green: 0, blue: 0)
            )
        )
        let interpolator = RBDisplayListInterpolator(from: source, to: target)

        XCTAssertEqual(interpolator.boundingRect(withProgress: 0), sourceMaskBounds)
        XCTAssertEqual(interpolator.boundingRect(withProgress: 0.5), midpointMaskBounds)
        XCTAssertEqual(interpolator.boundingRect(withProgress: 1), targetMaskBounds)

        let midpoint = interpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(midpoint.interpolationBounds, midpointMaskBounds)
        let effect = try XCTUnwrap(midpoint.effects.first)
        guard case let .mask(mask, options) = effect.effect else {
            return XCTFail("compatible layer clip should retain one mask effect")
        }
        XCTAssertEqual(options.rawValue, 0)
        XCTAssertEqual(mask.items.count, 1)
        XCTAssertEqual(mask.interpolationBounds, midpointMaskBounds)
        guard case let .content(maskContent) = try XCTUnwrap(mask.items.first).value,
              case let .shape(maskShape) = maskContent.value,
              case let .color(maskColor)? = maskShape.command.record.shapeStyle else {
            return XCTFail("mixed mask should retain typed color shape content")
        }
        assertPathElementsEqual(maskShape.path, Path(midpointMaskBounds))
        XCTAssertEqual(maskColor.renderingComponents().alpha, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(effect.contents.interpolationBounds, contentBounds)
    }

    func testRBDisplayListInterpolatorKeepsSourceMaskForIncompatibleCoverageFamily() throws {
        let maskBounds = CGRect(x: 10, y: 15, width: 30, height: 20)
        let contentBounds = CGRect(x: 0, y: 0, width: 80, height: 80)

        func shapeList(path: Path, bounds: CGRect, color: VUI.Color) -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: path,
                role: .fill,
                style: color,
                bounds: bounds
            )
            return list
        }

        let sourceMask = shapeList(
            path: Path(maskBounds),
            bounds: maskBounds,
            color: .white
        )
        let targetMask = shapeList(
            path: Path(ellipseIn: maskBounds),
            bounds: maskBounds,
            color: .white
        )
        let contents = shapeList(
            path: Path(contentBounds),
            bounds: contentBounds,
            color: .red
        )
        let interpolator = RBDisplayListInterpolator(
            from: .effect(.mask(sourceMask, []), contents: contents),
            to: .effect(.mask(targetMask, []), contents: contents)
        )

        for progress: Float in [0, 0.25, 0.5, 0.75, 1] {
            XCTAssertEqual(interpolator.boundingRect(withProgress: progress), maskBounds)
            let sampled = interpolator.copyContents(withProgress: progress)
            let effect = try XCTUnwrap(sampled.effects.first)
            guard case let .mask(mask, options) = effect.effect else {
                return XCTFail("incompatible child coverage should remain a mask effect")
            }
            XCTAssertEqual(options.rawValue, 0)
            XCTAssertEqual(mask.items.count, 1)
            guard case let .content(maskContent) = try XCTUnwrap(mask.items.first).value,
                  case let .shape(maskShape) = maskContent.value else {
                return XCTFail("incompatible child coverage should retain the source shape")
            }
            XCTAssertEqual(maskShape.path, Path(maskBounds))
        }
    }

    func testRBDisplayListInterpolatorKeepsMultiItemSupersetMaskForEntireLifetime() throws {
        let firstMaskBounds = CGRect(x: 10, y: 15, width: 20, height: 20)
        let secondMaskBounds = CGRect(x: 40, y: 15, width: 20, height: 20)
        let targetMaskBounds = firstMaskBounds.union(secondMaskBounds)
        let contentBounds = CGRect(x: 0, y: 0, width: 80, height: 80)

        func maskList(_ bounds: [CGRect]) -> DisplayList {
            var list = DisplayList()
            for bounds in bounds {
                list.appendShapeItem(
                    path: Path(bounds),
                    role: .fill,
                    style: Color.white,
                    bounds: bounds
                )
            }
            return list
        }

        func contentList() -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: Path(contentBounds),
                role: .fill,
                style: Color.red,
                bounds: contentBounds
            )
            return list
        }

        let transition = RBTransition()
        transition.method = ContentTransition.Method.diff.method
        let effect = RBTransitionEffect()
        effect.type = ContentTransition.EffectType(type: 3).type
        effect.events = 3
        transition.addEffect(effect)

        let singleItemMask = maskList([firstMaskBounds])
        let multiItemMask = maskList([firstMaskBounds, secondMaskBounds])
        for (sourceMask, targetMask) in [
            (singleItemMask, multiItemMask),
            (multiItemMask, singleItemMask),
        ] {
            let interpolator = RBDisplayListInterpolator(
                from: .effect(.mask(sourceMask, []), contents: contentList()),
                to: .effect(.mask(targetMask, []), contents: contentList()),
                options: [.transition: transition]
            )

            XCTAssertEqual(interpolator.activeDuration, 1)
            XCTAssertFalse(interpolator.onlyFades)
            for progress: Float in [0, 0.25, 0.5, 0.75, 1] {
                XCTAssertEqual(
                    interpolator.boundingRect(withProgress: progress),
                    targetMaskBounds
                )
                let sampled = interpolator.copyContents(withProgress: progress)
                let sampledEffect = try XCTUnwrap(sampled.effects.first)
                guard case let .mask(mask, options) = sampledEffect.effect else {
                    return XCTFail("multi-item child coverage should remain a mask effect")
                }
                XCTAssertEqual(options.rawValue, 0)
                XCTAssertEqual(mask.items.count, 2)
                XCTAssertEqual(mask.interpolationBounds, targetMaskBounds)
            }
        }
    }

    func testRBDisplayListInterpolatorRecursivelyMixesNestedMaskGeometry() throws {
        let sourceInnerBounds = CGRect(x: 10, y: 15, width: 20, height: 20)
        let targetInnerBounds = CGRect(x: 40, y: 15, width: 20, height: 20)
        let outerBounds = CGRect(x: 0, y: 0, width: 80, height: 80)

        func shapeList(bounds: CGRect, color: VUI.Color) -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: Path(bounds),
                role: .fill,
                style: color,
                bounds: bounds
            )
            return list
        }

        func nestedList(innerBounds: CGRect) -> DisplayList {
            let innerMask = shapeList(bounds: innerBounds, color: .white)
            let nestedMask = DisplayList.effect(
                .mask(innerMask, []),
                contents: shapeList(bounds: outerBounds, color: .white)
            )
            return .effect(
                .mask(nestedMask, []),
                contents: shapeList(bounds: outerBounds, color: .red)
            )
        }

        let interpolator = RBDisplayListInterpolator(
            from: nestedList(innerBounds: sourceInnerBounds),
            to: nestedList(innerBounds: targetInnerBounds)
        )

        XCTAssertEqual(interpolator.activeDuration, 1)
        XCTAssertFalse(interpolator.onlyFades)
        for progress: Float in [0, 0.25, 0.5, 0.75, 1] {
            let expectedBounds = CGRect(
                x: 10 + 30 * CGFloat(progress),
                y: 15,
                width: 20,
                height: 20
            )
            XCTAssertEqual(
                interpolator.boundingRect(withProgress: progress),
                expectedBounds
            )

            let sampled = interpolator.copyContents(withProgress: progress)
            XCTAssertEqual(sampled.interpolationBounds, expectedBounds)
            let outerEffect = try XCTUnwrap(sampled.effects.first)
            guard case let .mask(nestedMask, outerOptions) = outerEffect.effect else {
                return XCTFail("outer nested coverage should remain a mask effect")
            }
            XCTAssertEqual(outerOptions.rawValue, 0)
            XCTAssertEqual(nestedMask.interpolationBounds, expectedBounds)

            let innerEffect = try XCTUnwrap(nestedMask.effects.first)
            guard case let .mask(innerMask, innerOptions) = innerEffect.effect else {
                return XCTFail("inner nested coverage should remain a mask effect")
            }
            XCTAssertEqual(innerOptions.rawValue, 0)
            XCTAssertEqual(innerMask.interpolationBounds, expectedBounds)
            guard case let .content(maskContent) = try XCTUnwrap(innerMask.items.first).value,
                  case let .shape(maskShape) = maskContent.value else {
                return XCTFail("inner nested coverage should retain typed shape content")
            }
            assertPathElementsEqual(maskShape.path, Path(expectedBounds))
        }
    }

    func testRBDisplayListInterpolatorPreservesDirectAndNestedMaskTopologyBranches() throws {
        let sourceMaskBounds = CGRect(x: 10, y: 15, width: 20, height: 20)
        let targetMaskBounds = CGRect(x: 40, y: 15, width: 20, height: 20)
        let unionBounds = sourceMaskBounds.union(targetMaskBounds)
        let outerBounds = CGRect(x: 0, y: 0, width: 80, height: 80)

        func shapeList(bounds: CGRect, color: VUI.Color) -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: Path(bounds),
                role: .fill,
                style: color,
                bounds: bounds
            )
            return list
        }

        let directMask = shapeList(bounds: sourceMaskBounds, color: .white)
        let nestedMask = DisplayList.effect(
            .mask(shapeList(bounds: targetMaskBounds, color: .white), []),
            contents: shapeList(bounds: outerBounds, color: .white)
        )
        let contents = shapeList(bounds: outerBounds, color: .red)

        let transition = RBTransition()
        transition.method = ContentTransition.Method.diff.method
        let effect = RBTransitionEffect()
        effect.type = ContentTransition.EffectType(type: 3).type
        effect.events = 3
        transition.addEffect(effect)

        for (sourceMask, targetMask) in [
            (directMask, nestedMask),
            (nestedMask, directMask),
        ] {
            let interpolator = RBDisplayListInterpolator(
                from: .effect(.mask(sourceMask, []), contents: contents),
                to: .effect(.mask(targetMask, []), contents: contents),
                options: [.transition: transition]
            )

            XCTAssertEqual(interpolator.activeDuration, 1)
            XCTAssertFalse(interpolator.onlyFades)
            for progress: Float in [0, 0.25, 0.5, 0.75, 1] {
                XCTAssertEqual(
                    interpolator.boundingRect(withProgress: progress),
                    unionBounds
                )
                let sampled = interpolator.copyContents(withProgress: progress)
                XCTAssertEqual(sampled.interpolationBounds, unionBounds)
                let outerEffect = try XCTUnwrap(sampled.effects.first)
                guard case let .mask(mask, options) = outerEffect.effect else {
                    return XCTFail("topology fallback should remain an outer mask effect")
                }
                XCTAssertEqual(options.rawValue, 0)
                XCTAssertEqual(mask.interpolationBounds, unionBounds)
                XCTAssertEqual(mask.items.count, 2)
                XCTAssertEqual(mask.effects.count, 1)
            }
        }

        for (sourceMask, targetMask) in [
            (directMask, nestedMask),
            (nestedMask, directMask),
        ] {
            let interpolator = RBDisplayListInterpolator(
                from: .effect(.mask(sourceMask, []), contents: contents),
                to: .effect(.mask(targetMask, []), contents: contents)
            )

            for progress: Float in [0, 0.25, 0.5, 0.75, 1] {
                XCTAssertEqual(
                    interpolator.boundingRect(withProgress: progress),
                    unionBounds
                )
                let sampled = interpolator.copyContents(withProgress: progress)
                let outerEffect = try XCTUnwrap(sampled.effects.first)
                guard case let .mask(mask, options) = outerEffect.effect else {
                    return XCTFail("default topology fallback should remain a mask effect")
                }
                XCTAssertEqual(options.rawValue, 0)
                XCTAssertEqual(mask.interpolationBounds, unionBounds)
                XCTAssertEqual(mask.items.count, 2)
                XCTAssertTrue(mask.effects.isEmpty)
                let sourceOpacity = try XCTUnwrap(
                    typedOpacityStyle(in: mask.items[0])?.opacity
                )
                let targetOpacity = try XCTUnwrap(
                    typedOpacityStyle(in: mask.items[1])?.opacity
                )
                XCTAssertEqual(sourceOpacity, 1 - Double(progress), accuracy: 0.000_001)
                XCTAssertEqual(targetOpacity, Double(progress), accuracy: 0.000_001)
            }
        }
    }

    func testRBDisplayListInterpolatorMergesSameMaskAcrossDifferentModes() throws {
        let maskBounds = CGRect(x: 10, y: 15, width: 30, height: 20)
        let contentBounds = CGRect(x: 0, y: 0, width: 80, height: 80)

        func shapeList(bounds: CGRect, color: VUI.Color) -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: Path(bounds),
                role: .fill,
                style: color,
                bounds: bounds
            )
            return list
        }

        let mask = shapeList(bounds: maskBounds, color: .white)
        let source = DisplayList.effect(
            .mask(mask, []),
            contents: shapeList(
                bounds: contentBounds,
                color: VUI.Color(.sRGB, red: 1, green: 0, blue: 0)
            )
        )
        let target = DisplayList.effect(
            .mask(mask, .inverse),
            contents: shapeList(
                bounds: contentBounds,
                color: VUI.Color(.sRGB, red: 0, green: 0, blue: 1)
            )
        )
        let interpolator = RBDisplayListInterpolator(from: source, to: target)

        for progress: Float in [0, 0.25, 0.5, 0.75, 1] {
            XCTAssertEqual(interpolator.boundingRect(withProgress: progress), contentBounds)
            let sampled = interpolator.copyContents(withProgress: progress)
            XCTAssertEqual(sampled.interpolationBounds, contentBounds)
            XCTAssertEqual(sampled.effects.count, 2)
            guard sampled.effects.count == 2 else { continue }
            guard case let .mask(_, sourceOptions) = sampled.effects[0].effect,
                  case let .mask(_, targetOptions) = sampled.effects[1].effect else {
                return XCTFail("different clip modes should retain both ordered mask effects")
            }
            XCTAssertEqual(sourceOptions.rawValue, 0)
            XCTAssertEqual(targetOptions, .inverse)
        }
    }

    func testRBDisplayListInterpolatorPreservesDifferentModeMaskGeometryAndAlpha() throws {
        let sourceMaskBounds = CGRect(x: 10, y: 15, width: 30, height: 20)
        let targetMaskBounds = CGRect(x: 20, y: 10, width: 40, height: 30)
        let contentBounds = CGRect(x: 0, y: 0, width: 80, height: 80)

        func shapeList(bounds: CGRect, color: VUI.Color) -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: Path(bounds),
                role: .fill,
                style: color,
                bounds: bounds
            )
            return list
        }

        let source = DisplayList.effect(
            .mask(
                shapeList(
                    bounds: sourceMaskBounds,
                    color: VUI.Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.25)
                ),
                []
            ),
            contents: shapeList(bounds: contentBounds, color: .red)
        )
        let target = DisplayList.effect(
            .mask(
                shapeList(
                    bounds: targetMaskBounds,
                    color: VUI.Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.75)
                ),
                .inverse
            ),
            contents: shapeList(
                bounds: contentBounds,
                color: VUI.Color(.sRGB, red: 0, green: 0, blue: 1)
            )
        )
        let interpolator = RBDisplayListInterpolator(from: source, to: target)

        for progress: Float in [0, 0.25, 0.5, 0.75, 1] {
            XCTAssertEqual(interpolator.boundingRect(withProgress: progress), contentBounds)
            let sampled = interpolator.copyContents(withProgress: progress)
            XCTAssertEqual(sampled.interpolationBounds, contentBounds)
            XCTAssertEqual(sampled.effects.count, 2)
        }

        let midpoint = interpolator.copyContents(withProgress: 0.5)
        let sourceEffect = try XCTUnwrap(midpoint.effects.first)
        let targetEffect = try XCTUnwrap(midpoint.effects.last)
        guard case let .mask(sourceMask, sourceOptions) = sourceEffect.effect,
              case let .mask(targetMask, targetOptions) = targetEffect.effect else {
            return XCTFail("different clip modes should preserve both mask branches")
        }
        XCTAssertEqual(sourceOptions.rawValue, 0)
        XCTAssertEqual(targetOptions, .inverse)
        XCTAssertEqual(sourceMask.interpolationBounds, sourceMaskBounds)
        XCTAssertEqual(targetMask.interpolationBounds, targetMaskBounds)

        guard case let .content(sourceMaskContent) = try XCTUnwrap(sourceMask.items.first).value,
              case let .shape(sourceMaskShape) = sourceMaskContent.value,
              case let .color(sourceMaskColor)? = sourceMaskShape.command.record.shapeStyle,
              case let .content(targetMaskContent) = try XCTUnwrap(targetMask.items.first).value,
              case let .shape(targetMaskShape) = targetMaskContent.value,
              case let .color(targetMaskColor)? = targetMaskShape.command.record.shapeStyle else {
            return XCTFail("different-mode branches should retain typed mask geometry and alpha")
        }
        XCTAssertEqual(sourceMaskShape.path, Path(sourceMaskBounds))
        XCTAssertEqual(targetMaskShape.path, Path(targetMaskBounds))
        XCTAssertEqual(sourceMaskColor.renderingComponents().alpha, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(targetMaskColor.renderingComponents().alpha, 0.75, accuracy: 0.000_001)
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
            CGRect(x: 20, y: 10, width: 20, height: 20)
        )

        let sourceExtraStart = sourceExtraInterpolator.copyContents(withProgress: 0)
        XCTAssertEqual(
            sourceExtraStart.itemRecords.map(\.bounds),
            [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: -40, y: 30, width: 5, height: 5),
            ]
        )
        XCTAssertEqual(sourceExtraStart.itemRecords.map(\.sourceFraction), [0, nil])
        XCTAssertEqual(sourceExtraStart.itemRecords.map(\.targetFraction), [0, nil])
        XCTAssertEqual(sourceExtraStart.interpolationBounds, CGRect(x: -40, y: 0, width: 50, height: 35))

        let sourceExtraMidpoint = sourceExtraInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(
            sourceExtraMidpoint.itemRecords.map(\.bounds),
            [
                CGRect(x: 10, y: 5, width: 15, height: 15),
                CGRect(x: -40, y: 30, width: 5, height: 5),
            ]
        )
        XCTAssertEqual(sourceExtraMidpoint.itemRecords.map(\.sourceFraction), [0.5, nil])
        XCTAssertEqual(sourceExtraMidpoint.itemRecords.map(\.targetFraction), [0.5, nil])
        XCTAssertEqual(sourceExtraMidpoint.interpolationBounds, CGRect(x: -40, y: 5, width: 65, height: 30))
        guard let sourceExtraPair = typedCrossFade(in: sourceExtraMidpoint.items[0]),
              let sourceExtraRemoval = typedOpacityStyle(in: sourceExtraMidpoint.items[1]) else {
            return XCTFail("source-extra interpolation should keep a mixed pair and removal effect")
        }
        XCTAssertNotNil(sourceExtraPair.source)
        XCTAssertNotNil(sourceExtraPair.target)
        XCTAssertEqual(sourceExtraRemoval.opacity, 0.5, accuracy: 0.000001)
        XCTAssertEqual(sourceExtraRemoval.contents.itemRecords.map(\.kind), [.shapeFill])

        let sourceExtraEnd = sourceExtraInterpolator.copyContents(withProgress: 1)
        XCTAssertEqual(
            sourceExtraEnd.itemRecords.map(\.bounds),
            [CGRect(x: 20, y: 10, width: 20, height: 20)]
        )
        XCTAssertEqual(sourceExtraEnd.itemRecords.map(\.sourceFraction), [1])
        XCTAssertEqual(sourceExtraEnd.itemRecords.map(\.targetFraction), [1])
        XCTAssertEqual(sourceExtraEnd.interpolationBounds, CGRect(x: 20, y: 10, width: 20, height: 20))

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
            CGRect(x: 0, y: 0, width: 10, height: 10)
        )
        XCTAssertEqual(
            targetExtraInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 5, y: 10, width: 35, height: 25)
        )

        let targetExtraStart = targetExtraInterpolator.copyContents(withProgress: 0)
        XCTAssertEqual(
            targetExtraStart.itemRecords.map(\.bounds),
            [CGRect(x: 0, y: 0, width: 10, height: 10)]
        )
        XCTAssertEqual(targetExtraStart.itemRecords.map(\.sourceFraction), [0])
        XCTAssertEqual(targetExtraStart.itemRecords.map(\.targetFraction), [0])
        XCTAssertEqual(targetExtraStart.interpolationBounds, CGRect(x: 0, y: 0, width: 10, height: 10))

        let targetExtraMidpoint = targetExtraInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(
            targetExtraMidpoint.itemRecords.map(\.bounds),
            [
                CGRect(x: 10, y: 5, width: 15, height: 15),
                CGRect(x: 5, y: 25, width: 15, height: 10),
            ]
        )
        XCTAssertEqual(targetExtraMidpoint.itemRecords.map(\.sourceFraction), [0.5, nil])
        XCTAssertEqual(targetExtraMidpoint.itemRecords.map(\.targetFraction), [0.5, nil])
        XCTAssertEqual(targetExtraMidpoint.interpolationBounds, CGRect(x: 5, y: 5, width: 20, height: 30))
        guard let targetExtraPair = typedCrossFade(in: targetExtraMidpoint.items[0]),
              let targetExtraInsertion = typedOpacityStyle(in: targetExtraMidpoint.items[1]) else {
            return XCTFail("target-extra interpolation should keep a mixed pair and insertion effect")
        }
        XCTAssertNotNil(targetExtraPair.source)
        XCTAssertNotNil(targetExtraPair.target)
        XCTAssertEqual(targetExtraInsertion.opacity, 0.5, accuracy: 0.000001)
        XCTAssertEqual(targetExtraInsertion.contents.itemRecords.map(\.kind), [.shapeFill])

        let targetExtraEnd = targetExtraInterpolator.copyContents(withProgress: 1)
        XCTAssertEqual(
            targetExtraEnd.itemRecords.map(\.bounds),
            [
                CGRect(x: 20, y: 10, width: 20, height: 20),
                CGRect(x: 5, y: 25, width: 15, height: 10),
            ]
        )
        XCTAssertEqual(targetExtraEnd.itemRecords.map(\.sourceFraction), [1, nil])
        XCTAssertEqual(targetExtraEnd.itemRecords.map(\.targetFraction), [1, nil])
        XCTAssertEqual(targetExtraEnd.interpolationBounds, CGRect(x: 5, y: 10, width: 35, height: 25))
    }

    func testRBDisplayListInterpolatorUsesTypedFallbackForOneSidedContents() {
        var source = DisplayList()
        source.interpolationBounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let target = makeDisplayList(
            itemBounds: [CGRect(x: 20, y: 10, width: 20, height: 20)],
            itemKind: .shapeFill
        )
        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: ContentTransition.opacity.rbTransition]
        )

        let midpoint = interpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(
            midpoint.interpolationBounds,
            CGRect(x: 10, y: 5, width: 15, height: 15)
        )
        guard let operations = typedCrossFades(in: midpoint) else {
            return XCTFail("one-sided interpolation should use a typed fallback operation")
        }
        XCTAssertEqual(operations.count, 1)
        XCTAssertNil(operations[0].source)
        XCTAssertEqual(
            operations[0].target?.sourceBounds,
            CGRect(x: 20, y: 10, width: 20, height: 20)
        )
        XCTAssertEqual(
            operations[0].target?.outputBounds,
            CGRect(x: 10, y: 5, width: 15, height: 15)
        )
    }

    func testRBDisplayListInterpolatorMiddleKindMismatchKeepsSampledPrefixPairing() {
        var removalSource = DisplayList()
        removalSource.appendItem(kind: .shapeFill, bounds: CGRect(x: 0, y: 0, width: 10, height: 10)) { _ in }
        removalSource.appendItem(kind: .shapeStroke, bounds: CGRect(x: 25, y: 0, width: 10, height: 10)) { _ in }
        removalSource.appendItem(kind: .shapeFill, bounds: CGRect(x: 60, y: 0, width: 10, height: 10)) { _ in }
        var removalTarget = DisplayList()
        removalTarget.appendItem(kind: .shapeFill, bounds: CGRect(x: 0, y: 20, width: 10, height: 10)) { _ in }
        removalTarget.appendItem(kind: .shapeFill, bounds: CGRect(x: 40, y: 20, width: 10, height: 10)) { _ in }

        let removal = RBDisplayListInterpolator(
            from: removalSource,
            to: removalTarget,
            options: [.transition: ContentTransition.opacity.rbTransition]
        ).copyContents(withProgress: 0.5)
        XCTAssertEqual(removal.interpolationBounds, CGRect(x: 0, y: 0, width: 70, height: 20))
        XCTAssertEqual(removal.items.count, 3)
        guard let removalPair = typedCrossFade(in: removal.items[1]),
              let removalEffect = typedOpacityStyle(in: removal.items[2]) else {
            return XCTFail("middle removal should keep prefix pairing and a removal effect")
        }
        XCTAssertEqual(removalPair.source?.contents.itemRecords.first?.kind, .shapeStroke)
        XCTAssertEqual(removalPair.target?.contents.itemRecords.first?.kind, .shapeFill)
        XCTAssertEqual(removalEffect.opacity, 0.5, accuracy: 0.000001)
        XCTAssertEqual(removalEffect.contents.itemRecords.first?.kind, .shapeFill)

        var insertionSource = DisplayList()
        insertionSource.appendItem(kind: .shapeFill, bounds: CGRect(x: 0, y: 0, width: 10, height: 10)) { _ in }
        insertionSource.appendItem(kind: .shapeFill, bounds: CGRect(x: 60, y: 0, width: 10, height: 10)) { _ in }
        var insertionTarget = DisplayList()
        insertionTarget.appendItem(kind: .shapeFill, bounds: CGRect(x: 0, y: 20, width: 10, height: 10)) { _ in }
        insertionTarget.appendItem(kind: .shapeStroke, bounds: CGRect(x: 25, y: 20, width: 10, height: 10)) { _ in }
        insertionTarget.appendItem(kind: .shapeFill, bounds: CGRect(x: 40, y: 20, width: 10, height: 10)) { _ in }

        let insertion = RBDisplayListInterpolator(
            from: insertionSource,
            to: insertionTarget,
            options: [.transition: ContentTransition.opacity.rbTransition]
        ).copyContents(withProgress: 0.5)
        XCTAssertEqual(insertion.interpolationBounds, CGRect(x: 0, y: 10, width: 52.5, height: 20))
        XCTAssertEqual(insertion.items.count, 3)
        guard let insertionPair = typedCrossFade(in: insertion.items[1]),
              let insertionEffect = typedOpacityStyle(in: insertion.items[2]) else {
            return XCTFail("middle insertion should keep prefix pairing and an insertion effect")
        }
        XCTAssertEqual(insertionPair.source?.contents.itemRecords.first?.kind, .shapeFill)
        XCTAssertEqual(insertionPair.target?.contents.itemRecords.first?.kind, .shapeStroke)
        XCTAssertEqual(insertionEffect.opacity, 0.5, accuracy: 0.000001)
        XCTAssertEqual(insertionEffect.contents.itemRecords.first?.kind, .shapeFill)
    }

    func testRBDisplayListInterpolatorRoutesTransitionEffectsByOperationEvent() {
        let source = makeDisplayList(
            itemBounds: [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: 60, y: 0, width: 10, height: 10),
            ],
            itemKind: .shapeFill
        )
        let removalTarget = makeDisplayList(
            itemBounds: [CGRect(x: 0, y: 20, width: 10, height: 10)],
            itemKind: .shapeFill
        )

        let insertOnlyRemovalInterpolator = RBDisplayListInterpolator(
            from: source,
            to: removalTarget,
            options: [.transition: opacityTransition(events: 1)]
        )
        XCTAssertEqual(
            insertOnlyRemovalInterpolator.boundingRect(withProgress: 0),
            CGRect(x: 0, y: 0, width: 10, height: 10)
        )
        XCTAssertEqual(
            insertOnlyRemovalInterpolator.boundingRect(withProgress: 0.5),
            CGRect(x: 0, y: 10, width: 10, height: 10)
        )
        let insertOnlyRemoval = insertOnlyRemovalInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(insertOnlyRemoval.items.count, 1)
        XCTAssertNotNil(typedCrossFade(in: insertOnlyRemoval.items[0]))

        let removalOnlyRemovalInterpolator = RBDisplayListInterpolator(
            from: source,
            to: removalTarget,
            options: [.transition: opacityTransition(events: 2)]
        )
        XCTAssertEqual(
            removalOnlyRemovalInterpolator.boundingRect(withProgress: 0),
            CGRect(x: 0, y: 0, width: 70, height: 10)
        )
        XCTAssertEqual(
            removalOnlyRemovalInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 0, y: 20, width: 10, height: 10)
        )
        let removalOnlyRemoval = removalOnlyRemovalInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(removalOnlyRemoval.items.count, 2)
        XCTAssertNotNil(typedCrossFade(in: removalOnlyRemoval.items[0]))
        guard let removalEffect = typedOpacityStyle(in: removalOnlyRemoval.items[1]) else {
            return XCTFail("matching removal event should lower an opacity style")
        }
        XCTAssertEqual(removalEffect.opacity, 0.5, accuracy: 0.000001)

        let insertionTarget = makeDisplayList(
            itemBounds: [
                CGRect(x: 0, y: 20, width: 10, height: 10),
                CGRect(x: 40, y: 20, width: 10, height: 10),
            ],
            itemKind: .shapeFill
        )
        let insertionSource = makeDisplayList(
            itemBounds: [CGRect(x: 0, y: 0, width: 10, height: 10)],
            itemKind: .shapeFill
        )

        let removalOnlyInsertionInterpolator = RBDisplayListInterpolator(
            from: insertionSource,
            to: insertionTarget,
            options: [.transition: opacityTransition(events: 2)]
        )
        XCTAssertEqual(
            removalOnlyInsertionInterpolator.boundingRect(withProgress: 0),
            CGRect(x: 0, y: 0, width: 50, height: 30)
        )
        let removalOnlyInsertion = removalOnlyInsertionInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(removalOnlyInsertion.items.count, 2)
        XCTAssertNotNil(typedCrossFade(in: removalOnlyInsertion.items[0]))
        XCTAssertEqual(removalOnlyInsertion.itemRecords[1].kind, .shapeFill)

        let insertOnlyInsertionInterpolator = RBDisplayListInterpolator(
            from: insertionSource,
            to: insertionTarget,
            options: [.transition: opacityTransition(events: 1)]
        )
        XCTAssertEqual(
            insertOnlyInsertionInterpolator.boundingRect(withProgress: 0),
            CGRect(x: 0, y: 0, width: 10, height: 10)
        )
        XCTAssertEqual(
            insertOnlyInsertionInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 0, y: 20, width: 50, height: 10)
        )
        let insertOnlyInsertion = insertOnlyInsertionInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(insertOnlyInsertion.items.count, 2)
        XCTAssertNotNil(typedCrossFade(in: insertOnlyInsertion.items[0]))
        guard let insertionEffect = typedOpacityStyle(in: insertOnlyInsertion.items[1]) else {
            return XCTFail("matching insertion event should lower an opacity style")
        }
        XCTAssertEqual(insertionEffect.opacity, 0.5, accuracy: 0.000001)
    }

    func testRBDisplayListInterpolatorRoutesWholeListOperationEvents() {
        let bounds = CGRect(x: 20, y: 15, width: 20, height: 10)
        let empty = DisplayList()
        let content = makeDisplayList(
            itemBounds: [bounds],
            itemKind: .shapeFill
        )
        let samples: [Float] = [0, 0.5, 1]

        func assertStableBounds(
            _ interpolator: RBDisplayListInterpolator,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            for progress in samples {
                XCTAssertEqual(
                    interpolator.boundingRect(withProgress: progress),
                    bounds,
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    interpolator.copyContents(withProgress: progress).interpolationBounds,
                    bounds,
                    file: file,
                    line: line
                )
            }
        }

        let defaultInsertion = RBDisplayListInterpolator(from: empty, to: content)
        XCTAssertEqual(defaultInsertion.activeDuration, 1)
        assertStableBounds(defaultInsertion)
        for (progress, expectedFraction) in zip(samples, [Float(0), 0.5, 1]) {
            let list = defaultInsertion.copyContents(withProgress: progress)
            let crossFade = typedCrossFade(in: list.items.first!)
            XCTAssertNil(crossFade?.source)
            XCTAssertNotNil(crossFade?.target)
            XCTAssertEqual(list.itemRecords.first?.targetFraction, expectedFraction)
        }

        let defaultRemoval = RBDisplayListInterpolator(from: content, to: empty)
        XCTAssertEqual(defaultRemoval.activeDuration, 1)
        assertStableBounds(defaultRemoval)
        for (progress, expectedFraction) in zip(samples, [Float(0), 0.5, 1]) {
            let list = defaultRemoval.copyContents(withProgress: progress)
            let crossFade = typedCrossFade(in: list.items.first!)
            XCTAssertNotNil(crossFade?.source)
            XCTAssertNil(crossFade?.target)
            XCTAssertEqual(list.itemRecords.first?.sourceFraction, expectedFraction)
        }

        for events in UInt32(0)...UInt32(3) {
            let insertion = RBDisplayListInterpolator(
                from: empty,
                to: content,
                options: [.transition: opacityTransition(events: events)]
            )
            let matchesInsertion = events & 1 != 0
            XCTAssertEqual(insertion.activeDuration, matchesInsertion ? 1 : 0)
            assertStableBounds(insertion)
            let insertionLists = samples.map(insertion.copyContents(withProgress:))
            if matchesInsertion {
                XCTAssertTrue(insertionLists[0].items.isEmpty)
                XCTAssertEqual(typedOpacityStyle(in: insertionLists[1].items.first!)?.opacity, 0.5)
                XCTAssertEqual(insertionLists[2].itemRecords.map(\.kind), [.shapeFill])
            } else {
                for list in insertionLists {
                    XCTAssertEqual(list.itemRecords.map(\.kind), [.shapeFill])
                }
            }

            let removal = RBDisplayListInterpolator(
                from: content,
                to: empty,
                options: [.transition: opacityTransition(events: events)]
            )
            let matchesRemoval = events & 2 != 0
            XCTAssertEqual(removal.activeDuration, 1)
            assertStableBounds(removal)
            let removalLists = samples.map(removal.copyContents(withProgress:))
            if matchesRemoval {
                XCTAssertEqual(removalLists[0].itemRecords.map(\.kind), [.shapeFill])
                XCTAssertEqual(typedOpacityStyle(in: removalLists[1].items.first!)?.opacity, 0.5)
                XCTAssertTrue(removalLists[2].items.isEmpty)
            } else {
                for list in removalLists {
                    XCTAssertTrue(list.items.isEmpty)
                }
            }
        }
    }

    func testRBDisplayListInterpolatorLowersTransitionGeometryAndBlurIntoTypedContents() throws {
        let source = makeDisplayList(
            itemBounds: [CGRect(x: 0, y: 0, width: 10, height: 10)],
            itemKind: .shapeFill
        )
        let target = makeDisplayList(
            itemBounds: [
                CGRect(x: 0, y: 20, width: 10, height: 10),
                CGRect(x: 40, y: 20, width: 10, height: 10),
            ],
            itemKind: .shapeFill
        )
        let transition = RBTransition()
        transition.addEffect(opacityEffect(events: 1))

        let translation = RBTransitionEffect()
        translation.type = ContentTransition.EffectType.translation(.zero).type
        translation.setArgumentValue(10, atIndex: 0)
        translation.setArgumentValue(-4, atIndex: 1)
        translation.duration = 1
        translation.events = 1
        transition.addEffect(translation)

        let blur = RBTransitionEffect()
        blur.type = ContentTransition.EffectType.blur(radius: 12).type
        blur.setArgumentValue(12, atIndex: 0)
        blur.duration = 1
        blur.events = 1
        transition.addEffect(blur)

        let midpoint = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: transition]
        ).copyContents(withProgress: 0.5)
        let expected = try XCTUnwrap(
            transition.effectResults(
                at: 0.5,
                event: 1,
                bounds: CGRect(x: 40, y: 20, width: 10, height: 10)
            )
        )
        XCTAssertEqual(midpoint.items.count, 2)
        guard let blurStyle = typedBlurStyle(in: midpoint.items[1]),
              let opacityStyle = typedOpacityStyle(in: blurStyle.contents.items[0]) else {
            return XCTFail("transition output should retain blur and opacity wrappers")
        }
        XCTAssertEqual(blurStyle.radius, expected.blurRadius, accuracy: 0.000001)
        XCTAssertEqual(midpoint.itemRecords[1].bounds, expected.bounds)
        XCTAssertEqual(opacityStyle.opacity, Double(expected.alpha), accuracy: 0.000001)
        XCTAssertEqual(
            opacityStyle.contents.itemRecords.first?.bounds,
            CGRect(x: 40, y: 20, width: 10, height: 10)
                .applying(expected.transform)
                .standardized
        )
    }

    func testRBDisplayListInterpolatorKeepsTextCrossFadeAtBothEndpointBounds() throws {
        var source = DisplayList()
        source.appendTextItem(
            foreground: .color(.red),
            bounds: CGRect(x: 0, y: 0, width: 30, height: 10)
        ) { _ in }
        var target = DisplayList()
        target.appendTextItem(
            foreground: .color(.red),
            bounds: CGRect(x: 100, y: 50, width: 50, height: 10)
        ) { _ in }
        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: ContentTransition.text.rbTransition]
        )

        let midpoint = interpolator.copyContents(withProgress: 0.5)
        let item = try XCTUnwrap(midpoint.items.first)
        let record = try XCTUnwrap(midpoint.itemRecords.first)

        XCTAssertEqual(record.effectKind, .crossFade)
        XCTAssertEqual(record.bounds, CGRect(x: 0, y: 0, width: 150, height: 60))
        XCTAssertEqual(
            interpolator.boundingRect(withProgress: 0),
            CGRect(x: 0, y: 0, width: 150, height: 60)
        )
        XCTAssertEqual(
            interpolator.boundingRect(withProgress: 0.5),
            CGRect(x: 0, y: 0, width: 150, height: 60)
        )
        XCTAssertEqual(
            interpolator.boundingRect(withProgress: 1),
            CGRect(x: 0, y: 0, width: 150, height: 60)
        )
        guard case let .content(content) = item.value,
              case let .crossFade(crossFade) = content.value else {
            return XCTFail("text transition should preserve both endpoint branches")
        }
        XCTAssertEqual(crossFade.source?.sourceBounds, CGRect(x: 0, y: 0, width: 30, height: 10))
        XCTAssertEqual(crossFade.source?.outputBounds, CGRect(x: 0, y: 0, width: 30, height: 10))
        XCTAssertEqual(crossFade.target?.sourceBounds, CGRect(x: 100, y: 50, width: 50, height: 10))
        XCTAssertEqual(crossFade.target?.outputBounds, CGRect(x: 100, y: 50, width: 50, height: 10))
    }

    func testMaterializedInterpolationContentsPreserveCrossFadePresentation() throws {
        var source = DisplayList()
        source.appendTextItem(
            foreground: .color(.red),
            bounds: CGRect(x: 0, y: 0, width: 30, height: 10)
        ) { _ in }
        var target = DisplayList()
        target.appendTextItem(
            foreground: .color(.blue),
            bounds: CGRect(x: 100, y: 50, width: 50, height: 10)
        ) { _ in }
        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: ContentTransition.text.rbTransition]
        )

        let translatedMidpoint = interpolator
            .copyContents(withProgress: 0.5)
            .translated(by: CGSize(width: 7, height: 9))
        let materialized = translatedMidpoint.materializingInterpolationContents()

        XCTAssertEqual(materialized.items.count, 2)
        XCTAssertEqual(materialized.items.map(\.opacity), [0.5, 0.5])
        XCTAssertEqual(
            materialized.items.map(\.frame),
            [
                CGRect(x: 7, y: 9, width: 30, height: 10),
                CGRect(x: 107, y: 59, width: 50, height: 10),
            ]
        )
        XCTAssertFalse(
            materialized.itemRecords.contains {
                $0.effectKind == .crossFade
            }
        )
    }

    func testMaterializedCrossFadeAppliesBranchTransformBeforeReplayTransform() throws {
        var source = DisplayList()
        source.appendTextItem(
            foreground: .color(.red),
            bounds: CGRect(x: 0, y: 0, width: 10, height: 10)
        ) { _ in }

        var crossFade = DisplayList()
        crossFade.appendCrossFadeItem(
            sourceItems: source.items,
            sourceBounds: CGRect(x: 0, y: 0, width: 10, height: 10),
            sourceOutputBounds: CGRect(x: 20, y: 30, width: 20, height: 30),
            targetItems: [],
            targetBounds: nil,
            targetOutputBounds: nil,
            bounds: CGRect(x: 20, y: 30, width: 20, height: 30),
            sourceFraction: 0,
            targetFraction: 0
        )

        let materialized = crossFade
            .translated(by: CGSize(width: 7, height: 9))
            .materializingInterpolationContents()

        XCTAssertEqual(materialized.items.count, 1)
        XCTAssertEqual(
            materialized.items.first?.frame,
            CGRect(x: 27, y: 39, width: 20, height: 30)
        )
    }

    func testWholeListOpacityRetargetKeepsPriorPresentationAsUnscaledFadeBranch() throws {
        var compact = DisplayList()
        compact.appendTextItem(
            foreground: .color(.blue),
            bounds: CGRect(x: 65, y: 10, width: 84, height: 24)
        ) { _ in }
        var expanded = DisplayList()
        expanded.appendTextItem(
            foreground: .color(.purple),
            bounds: CGRect(x: 0, y: 4.5, width: 214, height: 35)
        ) { _ in }

        let forward = RBDisplayListInterpolator(
            from: compact,
            to: expanded,
            options: [.transition: ContentTransition.text.rbTransition]
        )
        let forwardPresentation = forward.copyContents(withProgress: 0.25)
        let retarget = RBDisplayListInterpolator(
            from: forwardPresentation,
            to: compact,
            options: [.transition: ContentTransition.text.rbTransition]
        )
        let retargetPresentation = retarget.copyContents(withProgress: 0.5)

        let outerItem = try XCTUnwrap(retargetPresentation.items.first)
        guard case let .content(outerContent) = outerItem.value,
              case let .crossFade(outerFade) = outerContent.value,
              let sourceBranch = outerFade.source,
              let targetBranch = outerFade.target else {
            return XCTFail("retarget should preserve the prior presentation as one fade branch")
        }
        XCTAssertEqual(sourceBranch.sourceBounds, forwardPresentation.interpolationBounds)
        XCTAssertEqual(sourceBranch.outputBounds, forwardPresentation.interpolationBounds)
        XCTAssertEqual(targetBranch.sourceBounds, compact.interpolationBounds)
        XCTAssertEqual(targetBranch.outputBounds, compact.interpolationBounds)

        let innerItem = try XCTUnwrap(sourceBranch.contents.items.first)
        guard case let .content(innerContent) = innerItem.value,
              case .crossFade = innerContent.value else {
            return XCTFail("the prior endpoint cross-fade should remain nested without scaling")
        }
    }

    func testNumericTextTransitionKeepsCommonPrefixAndSuffixAsPairedGlyphAtoms() throws {
        let source = try makeNumericTextDisplayList("1234", numericValue: 1234)
        let target = try makeNumericTextDisplayList("1254", numericValue: 1254)
        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: ContentTransition.numericText().rbTransition]
        )

        let contents = interpolator.copyContents(withProgress: 0.2)

        XCTAssertEqual(contents.items.count, 5)
        XCTAssertEqual(contents.itemRecords.map(\.kind), Array(repeating: .effect, count: 5))
    }

    func testNumericTextTransitionSequencesInsertedGlyphsFromLeadingEdge() throws {
        let source = try makeNumericTextDisplayList("0", numericValue: 0)
        let target = try makeNumericTextDisplayList("11", numericValue: 11)
        let interpolator = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: ContentTransition.numericText().rbTransition]
        )

        XCTAssertEqual(
            interpolator.activeDuration,
            0.8 + Double(38.0 / 255.0 * 204.0 / 255.0),
            accuracy: 0.000_001
        )

        let contents = interpolator.copyContents(withProgress: 0.2)
        XCTAssertEqual(contents.items.count, 3)
        XCTAssertEqual(contents.itemRecords.map(\.kind), Array(repeating: .effect, count: 3))
    }

    // ASSERTIONS rbDisplayListNumericCopiedRetargetGlyphTopologyObserved
    func testNumericTextCopiedRetargetPreservesGlyphTopology() throws {
        let source = try makeNumericTextDisplayList("1234", numericValue: 1234)
        let firstTarget = try makeNumericTextDisplayList("1254", numericValue: 1254)
        let secondTarget = try makeNumericTextDisplayList("1264", numericValue: 1264)
        let animation = Animation.linear(duration: 1.2).rbAnimation
        let first = RBDisplayListInterpolator(
            from: source,
            to: firstTarget,
            options: [
                .transition: ContentTransition.numericText(value: 1254).rbTransition,
                .animation: animation,
            ]
        )
        let firstPresentation = first
            .copyContents(withProgress: 0.2)
            .materializingInterpolationContents()
        let base = RBDisplayListInterpolator(
            from: firstTarget,
            to: secondTarget,
            options: [
                .transition: ContentTransition.numericText(value: 1264).rbTransition,
                .animation: animation,
            ]
        )
        let retargeted = base.copy() as! RBDisplayListInterpolator
        retargeted.setFrom(firstPresentation)

        let retargetedPresentation = retargeted.copyContents(withProgress: 0.4)
        let operationBounds = retargetedPresentation.itemCommands.compactMap(\.bounds)

        XCTAssertEqual(retargetedPresentation.items.count, 5)
        XCTAssertEqual(operationBounds.count, 5)
        XCTAssertLessThan(
            try XCTUnwrap(operationBounds.map(\.width).max()),
            100,
            "retargeting must keep glyph operations instead of pairing the whole text item"
        )
    }

    // ASSERTIONS rbDisplayListNumericPresentationRetargetTopologyObserved
    func testNumericTextLayerRetargetPreservesUnchangedGlyphTopology() throws {
        let unary = DisplayList.UnaryInterpolatorGroup()
        let source = try makeNumericTextDisplayList("1234", numericValue: 1234)
        let firstTarget = try makeNumericTextDisplayList("1254", numericValue: 1254)
        let secondTarget = try makeNumericTextDisplayList("1264", numericValue: 1264)
        var state = ContentTransition.State(
            transition: .numericText(value: 1254)
        )
        state.animation = .linear(duration: 1.2)

        _ = interpolationContext.transition(
            unary,
            seed: DisplayList.Seed(decodedValue: 1),
            from: source,
            to: firstTarget,
            state: state,
            at: .zero
        )
        interpolationContext.advance(unary, to: Time(seconds: 0.01))
        interpolationContext.advance(unary, to: Time(seconds: 0.02))
        interpolationContext.advance(unary, to: Time(seconds: 0.22))

        state.transition = .numericText(value: 1264)
        _ = interpolationContext.transition(
            unary,
            seed: DisplayList.Seed(decodedValue: 2),
            from: firstTarget,
            to: secondTarget,
            state: state,
            at: Time(seconds: 0.22)
        )

        let retargeted = try XCTUnwrap(
            unary.layer.removed.last?.interpolator
        )
        XCTAssertNil(retargeted.from.numericValue)
        let presentation = retargeted.copyContents(withProgress: 0.4)
        let operationBounds = presentation.itemCommands.compactMap(\.bounds)
        XCTAssertEqual(presentation.items.count, 5)
        XCTAssertEqual(operationBounds.count, 5)
        XCTAssertLessThan(
            try XCTUnwrap(operationBounds.map(\.width).max()),
            100,
            "the layer retarget must keep unchanged glyphs out of the transition operation"
        )
    }

    func testNumericTextLayerSameTimeRetargetKeepsGlyphOperations() throws {
        let unary = DisplayList.UnaryInterpolatorGroup()
        var currentValue = 0
        var current = try makeNumericTextDisplayList("0", numericValue: 0)

        for step in 1...12 {
            let targetValue = step * 17
            let target = try makeNumericTextDisplayList(
                "\(targetValue)",
                numericValue: Float(targetValue)
            )
            var state = ContentTransition.State(
                transition: .numericText(value: Double(targetValue))
            )
            state.animation = .linear(duration: 1.2)
            _ = interpolationContext.transition(
                unary,
                seed: DisplayList.Seed(decodedValue: UInt16(step)),
                from: current,
                to: target,
                state: state,
                at: .zero
            )

            let presentation = try XCTUnwrap(
                unary.layer.removed.last?.interpolator
            ).copyContents(withProgress: 0.05)
            XCTAssertFalse(
                presentation.itemCommands.compactMap(\.bounds).contains {
                    $0.width >= 100
                },
                "\(currentValue) -> \(targetValue) restored a whole-text operation"
            )
            currentValue = targetValue
            current = target
        }

        XCTAssertEqual(unary.layer.removedCount, 8)
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
            to: source,
            needsGeometry: true
        )
        let geometryWrapper = try XCTUnwrap(geometryOutput.effects.first)
        guard case .identity = geometryWrapper.effect else {
            return XCTFail("Expected the offset placement to remain an outer identity effect.")
        }
        XCTAssertEqual(
            geometryWrapper.frame,
            CGRect(x: 3, y: 4, width: 10, height: 10)
        )
        let geometryContents = try contentTransitionContents(
            in: geometryWrapper.contents
        )
        XCTAssertEqual(geometryContents.itemRecords.first?.kind, .text)
        XCTAssertEqual(
            geometryContents.itemRecords.first?.bounds,
            CGRect(x: 0, y: 0, width: 10, height: 10)
        )
        XCTAssertEqual(
            geometryContents.interpolationBounds,
            CGRect(x: 0, y: 0, width: 10, height: 10)
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

    func testDisplayListModifiersStoreTypedStyleContents() throws {
        let bounds = CGRect(x: 2, y: 3, width: 10, height: 12)
        var source = DisplayList()
        source.appendShapeItem(
            path: Path(bounds),
            role: .fill,
            style: Color.red,
            bounds: bounds
        )

        let opacity = try displayList(
            applying: _OpacityEffect(opacity: 0.5),
            to: source
        )
        let opacityItem = try XCTUnwrap(opacity.items.first)
        guard case let .content(opacityContent) = opacityItem.value,
              case let .style(opacityStyle) = opacityContent.value,
              case let .opacity(value) = opacityStyle.style else {
            return XCTFail("opacity should use typed style content")
        }
        XCTAssertEqual(value, 0.5)
        XCTAssertEqual(opacityStyle.contents.items.count, 1)
        XCTAssertEqual(opacityStyle.contents.itemRecords.first?.kind, .shapeFill)

        var changedSource = DisplayList()
        changedSource.appendShapeItem(
            path: Path(ellipseIn: bounds),
            role: .fill,
            style: Color.red,
            bounds: bounds
        )
        let changedOpacity = try displayList(
            applying: _OpacityEffect(opacity: 0.5),
            to: changedSource
        )
        XCTAssertFalse(opacity.hasSameInterpolationSurface(as: changedOpacity))

        let blur = try displayList(
            applying: _BlurEffect(radius: 4, opaque: true),
            to: source
        )
        let blurItem = try XCTUnwrap(blur.items.first)
        guard case let .content(blurContent) = blurItem.value,
              case let .style(blurStyle) = blurContent.value,
              case let .blur(radius, isOpaque) = blurStyle.style else {
            return XCTFail("blur should use typed style content")
        }
        XCTAssertEqual(radius, 4)
        XCTAssertTrue(isOpaque)

        let blend = try displayList(
            applying: _BlendModeEffect(blendMode: .multiply),
            to: source
        )
        let blendItem = try XCTUnwrap(blend.items.first)
        guard case let .content(blendContent) = blendItem.value,
              case let .style(blendStyle) = blendContent.value,
              case let .blendMode(mode) = blendStyle.style else {
            return XCTFail("blend mode should use typed style content")
        }
        XCTAssertEqual(mode, .multiply)

        let transform = CGAffineTransform(translationX: 7, y: 9)
        var transformed = DisplayList()
        transformed.appendTransformedItem(opacityItem, affineTransform: transform)
        let transformedItem = try XCTUnwrap(transformed.items.first)
        guard case let .content(transformedContent) = transformedItem.value,
              case let .style(transformedStyle) = transformedContent.value else {
            return XCTFail("transformed style should remain typed content")
        }
        XCTAssertEqual(transformedStyle.transform, transform)
        XCTAssertEqual(transformedStyle.contents.items.count, 1)
        XCTAssertEqual(
            transformedStyle.command.bounds,
            bounds.offsetBy(dx: 7, dy: 9)
        )
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

        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 0)

        unary.maxDuration = 0.5
        unary.reset()
        XCTAssertEqual(unary.maxDuration, 0.5)
        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertFalse(unary.layer.supportsVFD)

        let shapeStyle = _ShapeStyle_InterpolatorGroup()
        let shapeStyleBase: DisplayList.InterpolatorGroup = shapeStyle
        XCTAssertTrue(shapeStyleBase === shapeStyle)
        XCTAssertEqual(
            Mirror(reflecting: shapeStyle).children.compactMap(\.label),
            ["layers", "contentsScale", "rasterizationOptions", "serial", "cursor"]
        )
        let shapeStyleLayer = _ShapeStyle_InterpolatorGroup.Layer(
            id: .unstyled,
            serial: 0,
            style: nil,
            state: DisplayList.InterpolatorLayer(),
            isRemoved: false
        )
        XCTAssertEqual(
            Mirror(reflecting: shapeStyleLayer).children.compactMap(\.label),
            ["id", "serial", "style", "state", "isRemoved"]
        )
        _ = _ShapeStyle_LayerID.styled(.foreground, 0)
        _ = _ShapeStyle_LayerID.customStyle(0)
        _ = _ShapeStyle_LayerID.named(nil)
        _ = _ShapeStyle_LayerID.unstyled
    }

    // ASSERTIONS shapeStyleRenderedLayerReplacementReplayObserved
    // ASSERTIONS shapeStyledTrailingLayerRetirementObserved
    // ASSERTIONS shapeStyleRemovedLayerCleanupObserved
    func testShapeStyleRenderedLayersReplaceRetireAndCleanUp() throws {
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
            let environment = EnvironmentValues()
            let environmentAttribute = graph.makeInput(value: environment)
            let group = _ShapeStyle_InterpolatorGroup()
            let frame = CGRect(x: 0, y: 0, width: 20, height: 10)
            let foreground = _ShapeStyle_Pack.fill(
                .color(Color.red.resolveHDR(in: environment)),
                name: .foreground
            )
            let background = _ShapeStyle_Pack.fill(
                .color(Color.blue.resolveHDR(in: environment)),
                name: .background
            )

            var firstShape = _ShapeStyle_RenderedShape(
                shape: .path(Path(frame), FillStyle()),
                contentSeed: DisplayList.Seed(decodedValue: 1),
                frame: frame,
                options: DisplayList.Options(),
                environment: environmentAttribute
            )
            var firstLayers = _ShapeStyle_RenderedLayers(group: group)
            firstShape.renderItem(
                name: .foreground,
                styles: foreground,
                layers: &firstLayers
            )
            let first = firstLayers.commit(shape: &firstShape)
            XCTAssertEqual(first.items.count, 1)
            XCTAssertEqual(group.layers.map(\.id), [.styled(.foreground, 0)])

            var replacementShape = _ShapeStyle_RenderedShape(
                shape: .path(Path(frame), FillStyle()),
                contentSeed: DisplayList.Seed(decodedValue: 3),
                frame: frame,
                options: DisplayList.Options(),
                environment: environmentAttribute
            )
            var replacementLayers = _ShapeStyle_RenderedLayers(group: group)
            replacementShape.renderItem(
                name: .background,
                styles: background,
                layers: &replacementLayers
            )
            let replacement = replacementLayers.commit(
                shape: &replacementShape
            )
            XCTAssertEqual(replacement.items.count, 2)
            XCTAssertEqual(
                group.layers.map(\.id),
                [.styled(.foreground, 0), .styled(.background, 0)]
            )
            XCTAssertTrue(group.layers[0].isRemoved)
            XCTAssertFalse(group.layers[1].isRemoved)

            group.update(
                contentSeed: DisplayList.Seed(decodedValue: 3),
                transition: .identity,
                animation: nil,
                listener: nil,
                contentsScale: 1,
                rasterizationOptions: RasterizationOptions(),
                supportsVFD: false
            )
            XCTAssertEqual(group.layers.map(\.id), [.styled(.background, 0)])

            var emptyShape = _ShapeStyle_RenderedShape(
                shape: .empty,
                contentSeed: DisplayList.Seed(decodedValue: 5),
                frame: frame,
                options: DisplayList.Options(),
                environment: environmentAttribute
            )
            var retiredLayers = _ShapeStyle_RenderedLayers(group: group)
            let retired = retiredLayers.commit(shape: &emptyShape)
            XCTAssertEqual(retired.items.count, 1)
            XCTAssertTrue(group.layers[0].isRemoved)
            if case let .effect(.interpolatorLayer(owner, serial), contents) =
                retired.items[0].value {
                XCTAssertTrue(owner === group)
                XCTAssertEqual(serial, group.layers[0].serial)
                XCTAssertTrue(contents.items.isEmpty)
            } else {
                XCTFail("missing retired shape-style interpolator layer")
            }
        }
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

        var renderOptions: [RBDisplayListInterpolatorOptionKey: Any] = [
            .transition: opacity,
            .fadeInOutFraction: Float(0.33),
            .rasterizationScale: Float(3),
        ]
        #if canImport(CoreGraphics)
        renderOptions[.colorSpace] = CGColorSpace(name: CGColorSpace.sRGB)!
        #endif
        let renderOptionInterpolator = RBDisplayListInterpolator(from: from, to: to, options: renderOptions)
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
            transition.animation = animation?.rbAnimation
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
        XCTAssertEqual(animationTable.entries[0].animations.count, 1)
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

        let secondaryTableAnimation = RBAnimation()
        secondaryTableAnimation.addBezierDuration(
            4,
            controlPoint1: .zero,
            controlPoint2: CGPoint(x: 1, y: 1)
        )
        let pairedIndex = animationTable.internAnimation(
            matchingTableAnimation,
            secondary: secondaryTableAnimation
        )
        XCTAssertEqual(pairedIndex, 3)
        XCTAssertEqual(
            animationTable.internAnimation(
                matchingTableAnimation,
                secondary: secondaryTableAnimation
            ),
            pairedIndex
        )
        XCTAssertEqual(animationTable.entries[2].animations.count, 2)
        XCTAssertEqual(animationTable.maximumDuration(animationIndex: pairedIndex), 4)
        XCTAssertEqual(
            animationTable.evaluate(
                animationIndex: pairedIndex,
                sequence: 0,
                time: 1
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            animationTable.evaluate(
                animationIndex: pairedIndex,
                sequence: 1,
                time: 1
            ),
            0.25,
            accuracy: 0.001
        )
        XCTAssertEqual(
            animationTable.evaluate(
                animationIndex: pairedIndex,
                sequence: 7,
                time: 1
            ),
            0.25,
            accuracy: 0.001
        )
        secondaryTableAnimation.addDelay(10)
        XCTAssertEqual(
            animationTable.animation(at: pairedIndex, sequence: 1)?.activeDuration,
            4
        )

        let secondaryOnlyIndex = animationTable.internAnimation(
            nil,
            secondary: secondaryTableAnimation
        )
        XCTAssertNotEqual(secondaryOnlyIndex, animationTable.defaultAnimationIndex)
        XCTAssertEqual(
            animationTable.animation(at: secondaryOnlyIndex, sequence: 0)?.activeDuration,
            4
        )
        XCTAssertEqual(
            animationTable.animation(at: secondaryOnlyIndex, sequence: 1)?.activeDuration,
            4
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
        #if canImport(ObjectiveC)
        XCTAssertFalse(effects.responds(to: NSSelectorFromString("copyWithZone:")))
        #endif

        let matchingSequencer = RBAnimationSequencer()
        matchingSequencer.distanceMode = 1
        matchingSequencer.sequencesGlyphs = true
        matchingSequencer.startPoint = CGPoint(x: 1, y: 2)
        matchingSequencer.endPoint = CGPoint(x: 3, y: 4)
        matchingSequencer.added = matchingEffects
        XCTAssertTrue(sequencer.isEqual(sequencer))
        XCTAssertFalse(sequencer.isEqual(matchingSequencer))
        #if canImport(ObjectiveC)
        XCTAssertFalse(sequencer.responds(to: NSSelectorFromString("copyWithZone:")))
        #endif

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

    func testInterpolatorLayerStagesRemovalAndPreservesShortPreparationBegin() {
        let group = DisplayList.UnaryInterpolatorGroup()
        let current = makeDisplayList(debugItemCount: 1, itemCount: 1)
        let target = makeDisplayList(debugItemCount: 2, itemCount: 2)
        var state = ContentTransition.State(transition: .opacity)
        state.animation = .linear(duration: 0.2)

        beginTransition(
            group,
            from: current,
            to: target,
            state: state,
            at: Time(seconds: 1)
        )

        XCTAssertEqual(group.layer.removed.first?.phase, .first)
        XCTAssertEqual(group.layer.removed.first?.begin.seconds, 1)
        XCTAssertNotNil(group.layer.removed.first?.interpolator)

        updateInterpolators(group, at: Time(seconds: 1))
        XCTAssertEqual(group.layer.removed.first?.phase, .first)

        updateInterpolators(group, at: Time(seconds: 1.01))
        XCTAssertEqual(group.layer.removed.first?.phase, .second)
        XCTAssertEqual(
            group.layer.removed.first?.begin.seconds ?? .nan,
            1.01,
            accuracy: 0.000_001
        )

        updateInterpolators(group, at: Time(seconds: 1.02))
        XCTAssertEqual(group.layer.removed.first?.phase, .running)
        XCTAssertEqual(
            group.layer.removed.first?.begin.seconds ?? .nan,
            1.01,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            group.layer.nextUpdateTime.seconds,
            1.21,
            accuracy: 0.000_001
        )
    }

    func testUnaryInterpolatorGroupTracksLayerState() {
        let unary = DisplayList.UnaryInterpolatorGroup()
        let current = makeDisplayList(debugItemCount: 1)
        let target = makeDisplayList(debugItemCount: 2, itemCount: 2)
        var state = ContentTransition.State(
            transition: .opacity,
            options: .addsDrawingGroup
        )
        state.animation = .linear(duration: 0.2)

        _ = interpolationContext.transition(
            unary,
            seed: DisplayList.Seed(decodedValue: 5),
            from: current,
            to: target,
            state: state,
            at: Time(seconds: 2),
            supportsVFD: true
        )

        XCTAssertEqual(unary.contentSeed, DisplayList.Seed(decodedValue: 5))
        XCTAssertTrue(unary.layer.supportsVFD)
        XCTAssertTrue(unary.rasterizationOptions.isAccelerated)
        XCTAssertEqual(unary.layer.contents.displayList.debugItems.count, 2)
        XCTAssertEqual(unary.layer.removedCount, 1)
        XCTAssertEqual(unary.layer.removed.first?.transition?.method, ContentTransition.Method.none.method)
        XCTAssertEqual(unary.layer.removed.first?.transition?.effects.first?.type, ContentTransition.EffectType.opacity.type)
        XCTAssertEqual(unary.layer.time.seconds, 2)
        XCTAssertEqual(unary.layer.removed.first?.begin.seconds, 2)
        XCTAssertNotNil(unary.layer.removed.first?.interpolator)
        XCTAssertTrue(unary.layer.removed.first?.interpolator?.onlyFades ?? false)
        XCTAssertNotNil(unary.layer.removed.first?.interpolator?.options[.transition])
        XCTAssertNotNil(unary.layer.removed.first?.interpolator?.animation)
        XCTAssertNil(unary.layer.removed.first?.interpolator?.options[.rasterizationScale])
        XCTAssertEqual(unary.layer.removed.first?.interpolator?.animation?.activeDuration, 0.2)
        XCTAssertEqual(unary.layer.removed.first?.duration, 0.2)
        XCTAssertEqual(unary.layer.removed.first?.phase, .first)
        XCTAssertEqual(unary.layer.nextUpdateTime.seconds, 2.2, accuracy: 0.000_001)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 2.2, accuracy: 0.000_001)
        XCTAssertFalse(unary.layer.needsUpdate)

        interpolationContext.advance(unary, to: Time(seconds: 2.1))
        XCTAssertEqual(unary.layer.removed.first?.phase, .second)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 2.3, accuracy: 0.000_001)

        interpolationContext.advance(unary, to: Time(seconds: 2.3))
        XCTAssertEqual(unary.layer.removed.first?.phase, .running)
        XCTAssertEqual(unary.layer.removed.first?.begin.seconds ?? .nan, 2.3, accuracy: 0.000_001)

        let completedOutput = interpolationContext.advance(
            unary,
            to: Time(seconds: 2.5)
        )
        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertTrue(unary.layer.nextUpdateTime.seconds.isInfinite)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 2.5, accuracy: 0.000_001)
        XCTAssertTrue(completedOutput.effects.isEmpty)

        unary.reset()
        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertTrue(unary.layer.supportsVFD)
    }

    // ASSERTIONS unaryInterpolatorGroupCurrentAndRemovedMetadataObserved
    func testUnaryInterpolatorGroupFeaturesFollowCurrentAndRemovedContents() {
        let unary = DisplayList.UnaryInterpolatorGroup()
        let body = makeDisplayList(debugItemCount: 1)
        let source = DisplayList.effect(
            .state(StrongHash(words: (1, 2, 3, 4, 5))),
            contents: body
        )
        let target = makeDisplayList(debugItemCount: 2)
        let transition = ContentTransition.State(
            transition: .opacity,
            animation: .linear(duration: 0.2)
        )

        _ = interpolationContext.synchronize(
            unary,
            seed: DisplayList.Seed(),
            target: source,
            transition: transition.transition,
            at: .zero
        )
        XCTAssertTrue(unary.features.contains(.stateEffects))

        _ = interpolationContext.transition(
            unary,
            seed: DisplayList.Seed(decodedValue: 1),
            from: source,
            to: target,
            state: transition,
            at: .zero
        )
        XCTAssertTrue(unary.features.contains(.stateEffects))

        interpolationContext.advance(unary, to: Time(seconds: 0.01))
        interpolationContext.advance(unary, to: Time(seconds: 0.02))
        interpolationContext.advance(unary, to: Time(seconds: 0.22))

        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertFalse(unary.features.contains(.stateEffects))
    }

    // ASSERTIONS displayListIdentityTraversalObserved
    // ASSERTIONS interpolatorLayerDisjointIdentityObserved
    // ASSERTIONS interpolatorLayerFastFadeOutputObserved
    func testInterpolatorLayerUsesTwoOpacityItemsOnlyForDisjointFadeContents() throws {
        let sourceBounds = CGRect(x: 2, y: 4, width: 10, height: 20)
        let targetBounds = CGRect(x: 20, y: 30, width: 40, height: 50)
        let sourceOrigin = CGPoint(x: 3, y: 5)
        let targetOrigin = CGPoint(x: 11, y: 13)
        let contentOffset = CGSize(width: 40, height: 50)
        let frame = CGRect(x: 90, y: 80, width: 60, height: 70)
        let state = ContentTransition.State(
            transition: .opacity,
            animation: .linear(duration: 0.2)
        )

        let disjoint = DisplayList.UnaryInterpolatorGroup()
        let source = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: sourceBounds
        )
        let target = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: targetBounds
        )
        let output = interpolationContext.transition(
            disjoint,
            seed: DisplayList.Seed(decodedValue: 7),
            from: source,
            to: target,
            state: state,
            at: Time(seconds: 1),
            currentOrigin: sourceOrigin,
            targetOrigin: targetOrigin,
            contentOffset: contentOffset,
            frame: frame
        )

        XCTAssertEqual(output.items.count, 2)
        let effects = output.effects
        XCTAssertEqual(effects.count, 2)
        guard case let .opacity(outgoingOpacity) = effects[0].effect,
              case let .opacity(incomingOpacity) = effects[1].effect else {
            return XCTFail("Expected the disjoint fade fast path.")
        }
        XCTAssertEqual(outgoingOpacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(incomingOpacity, 0, accuracy: 0.000_001)
        XCTAssertEqual(
            effects[0].frame,
            CGRect(
                x: contentOffset.width + sourceOrigin.x - targetOrigin.x,
                y: contentOffset.height + sourceOrigin.y - targetOrigin.y,
                width: frame.width,
                height: frame.height
            )
        )
        XCTAssertEqual(
            effects[1].frame,
            CGRect(
                x: contentOffset.width,
                y: contentOffset.height,
                width: frame.width,
                height: frame.height
            )
        )
        XCTAssertEqual(effects[0].version, effects[1].version)

        let sharedIdentity = _DisplayList_Identity()
        var overlappingSource = source
        var overlappingTarget = target
        overlappingSource.items[0].identity = sharedIdentity
        overlappingTarget.items[0].identity = sharedIdentity
        let overlapping = DisplayList.UnaryInterpolatorGroup()
        let overlappingOutput = interpolationContext.transition(
            overlapping,
            seed: DisplayList.Seed(decodedValue: 8),
            from: overlappingSource,
            to: overlappingTarget,
            state: state,
            at: Time(seconds: 2)
        )

        XCTAssertEqual(overlappingOutput.items.count, 1)
        let overlappingItem = try XCTUnwrap(overlappingOutput.items.first)
        guard case let .content(content) = overlappingItem.value,
              case .drawing = content.value else {
            return XCTFail("An overlapping identity must use interpolated drawing output.")
        }
    }

    // ASSERTIONS interpolatorLayerDrawingOutputObserved
    func testInterpolatorLayerGeneralOutputUsesOneVersionSeededRGBAContentsItem() throws {
        let sourceBounds = CGRect(x: 2, y: 4, width: 10, height: 20)
        let targetBounds = CGRect(x: 20, y: 30, width: 40, height: 50)
        let sourceOrigin = CGPoint(x: 3, y: 5)
        let targetOrigin = CGPoint(x: 11, y: 13)
        let contentOffset = CGSize(width: 40, height: 50)
        let frame = CGRect(x: 90, y: 80, width: 60, height: 70)
        let transition = ContentTransition(
            method: .diff,
            effects: [
                ContentTransition.Effect(
                    type: ContentTransition.EffectType(type: 3),
                    begin: 0,
                    duration: 0,
                    events: 3
                ),
            ]
        )
        let state = ContentTransition.State(
            transition: transition,
            animation: .linear(duration: 0.2),
            options: .addsDrawingGroup
        )
        let group = DisplayList.UnaryInterpolatorGroup()
        let source = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: sourceBounds
        )
        let target = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: targetBounds
        )

        let output = interpolationContext.transition(
            group,
            seed: DisplayList.Seed(decodedValue: 9),
            from: source,
            to: target,
            state: state,
            at: Time(seconds: 3),
            currentOrigin: sourceOrigin,
            targetOrigin: targetOrigin,
            contentOffset: contentOffset,
            frame: frame
        )

        XCTAssertEqual(output.items.count, 1)
        let item = try XCTUnwrap(output.items.first)
        guard case let .content(content) = item.value,
              case let .drawing(contents, origin, options) = content.value,
              let local = contents as? DisplayList.LocalContents else {
            return XCTFail("Expected one backend drawing contents item.")
        }

        let sampledBounds = sourceBounds.offsetBy(
            dx: sourceOrigin.x,
            dy: sourceOrigin.y
        )
        let drawingBounds = sampledBounds.integral
        XCTAssertEqual(origin, drawingBounds.origin)
        XCTAssertEqual(
            item.frame,
            drawingBounds.offsetBy(
                dx: contentOffset.width - targetOrigin.x,
                dy: contentOffset.height - targetOrigin.y
            )
        )
        XCTAssertEqual(
            local.list.interpolationBounds,
            sampledBounds
        )
        XCTAssertTrue(options.flags.contains(.rgbaContext))
        XCTAssertTrue(options.flags.contains(.isAccelerated))
        XCTAssertFalse(options.flags.contains(.requiresLayer))
        XCTAssertEqual(content.seed, DisplayList.Seed(item.version))
        XCTAssertEqual(output.interpolationBounds, item.frame)
    }

    // ASSERTIONS displayListFrameOnlyTranslationObserved
    func testDisplayListTranslateMovesFramesAndVersionWithoutTransformingPayload() throws {
        let bounds = CGRect(x: 2, y: 4, width: 10, height: 20)
        var list = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: bounds,
            itemKind: .shapeFill
        )
        list.items[0].version = DisplayList.Version(value: 5)
        let command = list.items[0].command

        list.translate(
            by: CGSize(width: 30, height: -7),
            version: DisplayList.Version(value: 9)
        )

        let translated = try XCTUnwrap(list.items.first)
        XCTAssertEqual(
            translated.frame,
            bounds.offsetBy(dx: 30, dy: -7)
        )
        XCTAssertEqual(translated.version, DisplayList.Version(value: 9))
        XCTAssertEqual(translated.command, command)
        XCTAssertEqual(
            list.interpolationBounds,
            bounds.offsetBy(dx: 30, dy: -7)
        )

        list.translate(
            by: CGSize(width: -5, height: 2),
            version: DisplayList.Version(value: 3)
        )
        XCTAssertEqual(
            list.items.first?.frame,
            bounds.offsetBy(dx: 25, dy: -5)
        )
        XCTAssertEqual(
            list.items.first?.version,
            DisplayList.Version(value: 9)
        )
        XCTAssertEqual(list.items.first?.command, command)
    }

    func testInterpolatorLayerReplacesPendingRemovalAndBoundsPreparedQueue() {
        var state = ContentTransition.State(transition: .opacity)
        state.animation = .linear(duration: 20)

        let pendingGroup = DisplayList.UnaryInterpolatorGroup()
        let initial = makeDisplayList(debugItemCount: 0, itemCount: 1)
        _ = interpolationContext.synchronize(
            pendingGroup,
            seed: DisplayList.Seed(),
            target: initial,
            transition: state.transition,
            at: .zero
        )
        pendingGroup.update(
            contentSeed: DisplayList.Seed(decodedValue: 1),
            transition: state.transition,
            animation: state.animation,
            listener: nil,
            contentsScale: 1,
            rasterizationOptions: state.rasterizationOptions,
            supportsVFD: false
        )
        XCTAssertEqual(pendingGroup.layer.removedCount, 1)
        XCTAssertEqual(pendingGroup.layer.removed.first?.phase, .pending)

        pendingGroup.update(
            contentSeed: DisplayList.Seed(decodedValue: 2),
            transition: state.transition,
            animation: state.animation,
            listener: nil,
            contentsScale: 1,
            rasterizationOptions: state.rasterizationOptions,
            supportsVFD: false
        )
        XCTAssertEqual(pendingGroup.layer.removedCount, 1)
        XCTAssertEqual(
            pendingGroup.layer.removed.first?.contents.displayList.items.count,
            1
        )

        let preparedGroup = DisplayList.UnaryInterpolatorGroup()
        var current = initial
        var target = initial
        for step in 1...9 {
            current = target
            target = makeDisplayList(
                debugItemCount: 0,
                itemCount: step + 1
            )
            beginTransition(
                preparedGroup,
                from: current,
                to: target,
                state: state,
                at: Time(seconds: Double(step) * 0.01)
            )
        }
        XCTAssertEqual(preparedGroup.layer.removedCount, 8)
        XCTAssertEqual(
            preparedGroup.layer.removed.first?.contents.displayList.items.count,
            2
        )

        current = target
        target = makeDisplayList(debugItemCount: 0, itemCount: 11)
        beginTransition(
            preparedGroup,
            from: current,
            to: target,
            state: state,
            at: Time(seconds: 0.1)
        )
        XCTAssertEqual(preparedGroup.layer.removedCount, 8)
        XCTAssertEqual(
            preparedGroup.layer.removed.first?.contents.displayList.items.count,
            3
        )
        XCTAssertNotNil(preparedGroup.layer.removed.last?.interpolator)
    }

    func testInterpolatorLayerExpiryRemovesThroughCurrentEntryAndRebuildsTail() {
        let group = DisplayList.UnaryInterpolatorGroup()
        var state = ContentTransition.State(transition: .opacity)
        state.animation = .linear(duration: 0.1)

        let first = makeDisplayList(debugItemCount: 0, itemCount: 1)
        let second = makeDisplayList(debugItemCount: 0, itemCount: 2)
        let third = makeDisplayList(debugItemCount: 0, itemCount: 3)
        beginTransition(
            group,
            from: first,
            to: second,
            state: state
        )
        updateInterpolators(group, at: Time(seconds: 0.01))
        updateInterpolators(group, at: Time(seconds: 0.02))

        beginTransition(
            group,
            from: second,
            to: third,
            state: state,
            at: Time(seconds: 0.02)
        )
        let staleTailInterpolator = group.layer.removed.last?.interpolator
        XCTAssertEqual(group.layer.removedCount, 2)

        updateInterpolators(group, at: Time(seconds: 0.12))

        XCTAssertEqual(group.layer.removedCount, 1)
        XCTAssertEqual(
            group.layer.removed.first?.contents.displayList.items.count,
            2
        )
        XCTAssertNotNil(group.layer.removed.first?.interpolator)
        XCTAssertFalse(
            staleTailInterpolator === group.layer.removed.first?.interpolator
        )
        XCTAssertTrue(group.layer.needsUpdate)
    }

    func testUnaryInterpolatorGroupComposesActivePresentationIntoAnimatedRetarget() throws {
        let unary = DisplayList.UnaryInterpolatorGroup()
        let source = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 20, height: 20)
        )
        let firstTarget = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 100, y: 0, width: 20, height: 20)
        )
        let secondTarget = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 200, y: 0, width: 20, height: 20)
        )
        var state = ContentTransition.State(transition: .interpolate)
        state.animation = .linear(duration: 2)

        _ = interpolationContext.transition(
            unary,
            seed: DisplayList.Seed(decodedValue: 1),
            from: source,
            to: firstTarget,
            state: state,
            at: .zero
        )
        interpolationContext.advance(unary, to: Time(seconds: 0.01))
        interpolationContext.advance(unary, to: Time(seconds: 0.02))
        interpolationContext.advance(unary, to: Time(seconds: 1.01))

        let firstPresentation = try XCTUnwrap(
            unary.layer.removed.last?.interpolator?.copyContents(withProgress: 1)
        )
        let firstPresentationBounds = try XCTUnwrap(firstPresentation.interpolationBounds)
        XCTAssertEqual(firstPresentationBounds.minX, 50, accuracy: 0.001)

        let output = interpolationContext.transition(
            unary,
            seed: DisplayList.Seed(decodedValue: 2),
            from: firstTarget,
            to: secondTarget,
            state: state,
            at: Time(seconds: 1.01)
        )

        XCTAssertEqual(unary.layer.removedCount, 2)
        XCTAssertEqual(output.effects.count, 0)
        let firstRemoval = try XCTUnwrap(unary.layer.removed.first?.interpolator)
        XCTAssertEqual(
            try XCTUnwrap(firstRemoval.to.interpolationBounds).minX,
            100,
            accuracy: 0.001
        )
        let retargeted = try XCTUnwrap(unary.layer.removed.last?.interpolator)
        XCTAssertEqual(
            try XCTUnwrap(retargeted.from.interpolationBounds).minX,
            firstPresentationBounds.minX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(retargeted.to.interpolationBounds).minX,
            200,
            accuracy: 0.001
        )
        XCTAssertFalse(
            retargeted.from.itemRecords.contains {
                $0.effectKind == .crossFade
            }
        )
    }

    func testUnaryInterpolatorGroupMaterializesRepeatedAnimatedRetargetSources() throws {
        func textList(at x: CGFloat) -> DisplayList {
            var list = DisplayList()
            list.appendTextItem(
                foreground: .color(.red),
                bounds: CGRect(x: x, y: 0, width: 20, height: 10)
            ) { _ in }
            return list
        }

        let unary = DisplayList.UnaryInterpolatorGroup()
        var current = textList(at: 0)
        var state = ContentTransition.State(transition: .text)
        state.animation = .linear(duration: 20)
        var currentTime = 0.0

        for step in 1...12 {
            let target = textList(at: CGFloat(step * 20))
            _ = interpolationContext.transition(
                unary,
                seed: DisplayList.Seed(decodedValue: UInt16(step)),
                from: current,
                to: target,
                state: state,
                at: Time(seconds: currentTime)
            )

            let retainedCount = min(step, 8)
            XCTAssertEqual(unary.layer.removedCount, retainedCount)
            let source = try XCTUnwrap(
                unary.layer.removed.last?.interpolator?.from
            )
            XCTAssertEqual(source.items.count, retainedCount)
            XCTAssertFalse(
                source.itemRecords.contains {
                    $0.effectKind == .crossFade
                }
            )
            interpolationContext.advance(
                unary,
                to: Time(seconds: currentTime + 0.01)
            )
            interpolationContext.advance(
                unary,
                to: Time(seconds: currentTime + 0.02)
            )
            interpolationContext.advance(
                unary,
                to: Time(seconds: currentTime + 0.25)
            )
            currentTime += 0.25
            current = target
        }

        let finalSource = try XCTUnwrap(
            unary.layer.removed.last?.interpolator?.from
        )
        let sampled = DisplayList.GraphicsRenderer().sample(
            list: finalSource,
            at: Time(seconds: 2)
        )
        XCTAssertEqual(sampled.items.count, 8)
    }

    func testUnaryInterpolatorGroupRapidRetargetSettlesAtLatestEndpoint() throws {
        func textList(width: CGFloat) -> DisplayList {
            var list = DisplayList()
            list.appendTextItem(
                foreground: .color(width < 100 ? .blue : .purple),
                bounds: CGRect(x: 0, y: 0, width: width, height: 24)
            ) { _ in }
            return list
        }

        let compact = textList(width: 84)
        let expanded = textList(width: 215)
        let unary = DisplayList.UnaryInterpolatorGroup()
        var current = compact
        var state = ContentTransition.State(transition: .text)
        state.animation = .easeInOut(duration: 1.4)

        _ = interpolationContext.synchronize(
            unary,
            seed: DisplayList.Seed(decodedValue: 0),
            target: compact,
            transition: .text,
            at: .zero,
            supportsVFD: false,
            rasterizationOptions: RasterizationOptions()
        )

        for action in 0..<16 {
            let time = 2.0 + Double(action) * 0.12
            interpolationContext.advance(unary, to: Time(seconds: time))
            let target = action.isMultiple(of: 2) ? expanded : compact
            _ = interpolationContext.transition(
                unary,
                seed: DisplayList.Seed(decodedValue: UInt16(action + 1)),
                from: current,
                to: target,
                state: state,
                at: Time(seconds: time)
            )
            interpolationContext.advance(
                unary,
                to: Time(seconds: time + 0.001)
            )
            current = target
        }

        interpolationContext.advance(unary, to: Time(seconds: 3.92))
        interpolationContext.advance(unary, to: Time(seconds: 4.04))
        let output = interpolationContext.advance(
            unary,
            to: Time(seconds: 5.55)
        )
        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertEqual(output.interpolationBounds, compact.interpolationBounds)
        XCTAssertNotEqual(output.interpolationBounds, expanded.interpolationBounds)
    }

    func testUnaryInterpolatorGroupRebasesExistingInterpolatorFromComposedPresentation() throws {
        let unary = DisplayList.UnaryInterpolatorGroup()
        let source = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 20, height: 20)
        )
        let firstTarget = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 100, y: 0, width: 20, height: 20)
        )
        let secondTarget = makeDisplayList(
            debugItemCount: 0,
            itemCount: 1,
            bounds: CGRect(x: 200, y: 0, width: 20, height: 20)
        )
        var state = ContentTransition.State(transition: .interpolate)
        state.animation = .linear(duration: 2)

        _ = interpolationContext.transition(
            unary,
            seed: DisplayList.Seed(decodedValue: 1),
            from: source,
            to: firstTarget,
            state: state,
            at: .zero
        )
        interpolationContext.advance(unary, to: Time(seconds: 0.01))
        interpolationContext.advance(unary, to: Time(seconds: 0.02))
        interpolationContext.advance(unary, to: Time(seconds: 0.5))
        _ = interpolationContext.transition(
            unary,
            seed: DisplayList.Seed(decodedValue: 2),
            from: firstTarget,
            to: secondTarget,
            state: state,
            at: Time(seconds: 0.5)
        )

        let initialSecond = try XCTUnwrap(
            unary.layer.removed.last?.interpolator
        )
        let initialSourceBounds = try XCTUnwrap(
            initialSecond.from.interpolationBounds
        )

        interpolationContext.advance(unary, to: Time(seconds: 0.75))

        let updatedSecond = try XCTUnwrap(
            unary.layer.removed.last?.interpolator
        )
        let updatedSourceBounds = try XCTUnwrap(
            updatedSecond.from.interpolationBounds
        )
        XCTAssertFalse(initialSecond === updatedSecond)
        XCTAssertGreaterThan(updatedSourceBounds.minX, initialSourceBounds.minX)
        XCTAssertTrue(
            updatedSecond.to.hasSameInterpolationSurface(as: initialSecond.to)
        )
        XCTAssertEqual(updatedSecond.activeDuration, initialSecond.activeDuration)

        let firstRemoval = try XCTUnwrap(unary.layer.removed.first)
        let firstInterpolator = try XCTUnwrap(firstRemoval.interpolator)
        let elapsed = Float(
            unary.layer.time.seconds - firstRemoval.begin.seconds
        )
        let expectedSource = firstInterpolator
            .copyContents(withProgress: elapsed)
            .materializingInterpolationContents()
        XCTAssertTrue(
            updatedSecond.from.hasSameInterpolationSurface(as: expectedSource)
        )
    }

    func testUnaryInterpolatorGroupFlattensRepeatedNumericOpacityPresentations() throws {
        let unary = DisplayList.UnaryInterpolatorGroup()
        var current = try makeNumericTextDisplayList("0", numericValue: 0)
        var state = ContentTransition.State(transition: .numericText())
        state.animation = .linear(duration: 20)
        var currentTime = 0.0

        for step in 1...128 {
            let target = try makeNumericTextDisplayList(
                "\(step)",
                numericValue: Float(step)
            )
            _ = interpolationContext.transition(
                unary,
                seed: DisplayList.Seed(decodedValue: UInt16(step)),
                from: current,
                to: target,
                state: state,
                at: Time(seconds: currentTime)
            )

            interpolationContext.advance(
                unary,
                to: Time(seconds: currentTime + 0.01)
            )
            interpolationContext.advance(
                unary,
                to: Time(seconds: currentTime + 0.02)
            )
            interpolationContext.advance(
                unary,
                to: Time(seconds: currentTime + 0.05)
            )
            currentTime += 0.05
            current = target

            let latestSource = try XCTUnwrap(
                unary.layer.removed.last?.interpolator?.from
            )
            let latestPresentation = try XCTUnwrap(
                unary.layer.removed.last?.interpolator
            ).copyContents(withProgress: 0.05)
            if step > 1 {
                XCTAssertNil(latestSource.numericValue)
            }
            XCTAssertFalse(
                latestSource.itemRecords.contains {
                    $0.effectKind == .crossFade || $0.effectKind == .opacity
                }
            )
            XCTAssertFalse(
                latestPresentation.itemCommands.compactMap(\.bounds).contains {
                    $0.width >= 100
                },
                "rapid numeric retargets must not restore whole-text operations"
            )
        }

        let finalSource = try XCTUnwrap(
            unary.layer.removed.last?.interpolator?.from
        )
        _ = DisplayList.GraphicsRenderer().sample(
            list: finalSource,
            at: Time(seconds: currentTime)
        )
    }

    func testUnaryInterpolatorGroupUpdateThenRewriteSynchronizesLayerState() {
        let unary = DisplayList.UnaryInterpolatorGroup()
        let target = makeDisplayList(debugItemCount: 2, itemCount: 2)
        var rasterizationOptions = RasterizationOptions()
        rasterizationOptions.isAccelerated = true
        rasterizationOptions.alphaOnly = true

        _ = interpolationContext.synchronize(
            unary,
            seed: DisplayList.Seed(decodedValue: 11),
            target: target,
            transition: .numericText(value: 12.5),
            at: Time(seconds: 3.5),
            supportsVFD: true,
            rasterizationOptions: rasterizationOptions
        )

        XCTAssertEqual(unary.contentSeed, DisplayList.Seed(decodedValue: 11))
        XCTAssertTrue(unary.layer.supportsVFD)
        XCTAssertEqual(unary.rasterizationOptions, rasterizationOptions)
        XCTAssertEqual(unary.layer.contentSeed.value, 11)
        XCTAssertEqual(unary.layer.contents.numericValue, 12.5)
        XCTAssertEqual(unary.layer.contents.displayList.debugItems.count, 2)
        XCTAssertEqual(unary.layer.time.seconds, 0)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 0)
    }

    func testUnaryInterpolatorGroupRetainsNumericValuesForBothTransitionEndpoints() throws {
        let unary = DisplayList.UnaryInterpolatorGroup()
        let source = makeDisplayList(debugItemCount: 1)
        let target = makeDisplayList(debugItemCount: 2)

        _ = interpolationContext.synchronize(
            unary,
            seed: DisplayList.Seed(decodedValue: 1),
            target: source,
            transition: .numericText(value: 17),
            at: .zero,
            supportsVFD: false,
            rasterizationOptions: RasterizationOptions()
        )

        _ = interpolationContext.transition(
            unary,
            seed: DisplayList.Seed(decodedValue: 2),
            from: source,
            to: target,
            state: ContentTransition.State(
                transition: .numericText(value: 0),
                animation: .linear(duration: 1)
            ),
            at: .zero
        )

        XCTAssertEqual(try XCTUnwrap(unary.layer.removed.first).contents.numericValue, 17)
        XCTAssertEqual(unary.layer.contents.numericValue, 0)
        XCTAssertEqual(
            try XCTUnwrap(unary.layer.removed.first?.interpolator).from.numericValue,
            17
        )
        XCTAssertEqual(
            try XCTUnwrap(unary.layer.removed.first?.interpolator).to.numericValue,
            0
        )
    }

    func testInterpolatorLayerOnlyRetainsWhenTransitionIsBegun() {
        let group = DisplayList.UnaryInterpolatorGroup()
        let first = makeDisplayList(debugItemCount: 1, itemCount: 1)
        let second = makeDisplayList(debugItemCount: 1, itemCount: 1)

        _ = interpolationContext.synchronize(
            group,
            seed: DisplayList.Seed(decodedValue: 1),
            target: first,
            transition: .identity,
            at: .zero
        )
        _ = interpolationContext.synchronize(
            group,
            seed: DisplayList.Seed(decodedValue: 2),
            target: second,
            transition: .identity,
            at: .zero
        )

        XCTAssertEqual(group.layer.removedCount, 0)
        XCTAssertEqual(group.layer.contentSeed.value, 2)

        _ = interpolationContext.transition(
            group,
            seed: DisplayList.Seed(decodedValue: 3),
            from: second,
            to: first,
            state: ContentTransition.State(
                transition: .opacity,
                animation: .linear(duration: 1)
            ),
            at: .zero
        )

        XCTAssertEqual(group.layer.removedCount, 1)
        XCTAssertEqual(
            group.layer.removed.first?.contents.displayList.items.first?
                .version.value,
            2
        )
        XCTAssertEqual(group.layer.contentSeed.value, 3)
    }

    func testInterpolatedDisplayListRetainsPreviousListOnFirstSameSurfaceChange() throws {
        let (viewGraph, rendererHost) = makeInterpolationViewGraph()
        _ = rendererHost

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let group = DisplayList.UnaryInterpolatorGroup()
            let firstList = makeInterpolatorLayerDisplayList(
                group: group,
                debugItemCount: 1,
                itemCount: 1,
                version: 1
            )
            let secondList = makeInterpolatorLayerDisplayList(
                group: group,
                debugItemCount: 1,
                itemCount: 1,
                version: 2
            )
            let displayList = graph.makeInput(value: firstList)
            let content = graph.makeInput(value: VersionedTransitionContent(value: 0))
            let inputs = makeViewInputs(graph: graph)
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: inputs,
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 1)
            let initialSeed = group.layer.contentSeed

            displayList.setValue(secondList)
            content.setValue(VersionedTransitionContent(value: 1))
            let updated = output.value

            XCTAssertEqual(updated.effects.count, 1)
            XCTAssertNotEqual(group.contentSeed, initialSeed)
            XCTAssertEqual(group.layer.removedCount, 1)
            XCTAssertEqual(
                group.layer.removed.first?.contents.displayList.items.first?
                    .version.value,
                1
            )
            XCTAssertEqual(
                group.layer.removed.first?.interpolator?.from.items.first?
                    .version.value,
                1
            )
            XCTAssertEqual(
                group.layer.removed.first?.interpolator?.to.items.first?
                    .version.value,
                2
            )
        }
    }

    func testInterpolatedDisplayListIdleTimeDoesNotInvalidateOutput() throws {
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
            let displayList = graph.makeInput(value: makeDisplayList(debugItemCount: 1))
            let content = graph.makeInput(value: VersionedTransitionContent(value: 0))
            let inputs = makeViewInputs(graph: graph)
            let group = DisplayList.UnaryInterpolatorGroup()
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: inputs,
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            _ = output.value
            XCTAssertFalse(output.valueState.contains(.needsEvaluation))

            inputs.base.time.setValue(Time(seconds: 1))

            XCTAssertFalse(output.valueState.contains(.needsEvaluation))
            XCTAssertEqual(group.layer.removedCount, 0)
        }
    }

    func testInterpolatedDisplayListReadsTimeWhileActiveThenReleasesDependency() throws {
        let (viewGraph, rendererHost) = makeInterpolationViewGraph()
        _ = rendererHost

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let group = DisplayList.UnaryInterpolatorGroup()
            let firstList = makeInterpolatorLayerDisplayList(
                group: group,
                debugItemCount: 1,
                itemCount: 1,
                version: 1
            )
            let secondList = makeInterpolatorLayerDisplayList(
                group: group,
                debugItemCount: 1,
                itemCount: 1,
                version: 2
            )
            let displayList = graph.makeInput(value: firstList)
            let content = graph.makeInput(value: VersionedTransitionContent(value: 0))
            let inputs = makeViewInputs(graph: graph)
            var transaction = Transaction()
            transaction.animation = .linear(duration: 0.2)
            inputs.base.transaction.setValue(transaction)
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: inputs,
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            _ = output.value

            displayList.setValue(secondList, transaction: transaction)
            content.setValue(
                VersionedTransitionContent(value: 1),
                transaction: transaction
            )
            _ = output.value
            XCTAssertGreaterThan(group.layer.removedCount, 0)

            inputs.base.time.setValue(Time(seconds: 0.01))
            XCTAssertTrue(output.valueState.contains(.needsEvaluation))
            _ = output.value
            inputs.base.time.setValue(Time(seconds: 0.02))
            XCTAssertTrue(output.valueState.contains(.needsEvaluation))
            _ = output.value
            inputs.base.time.setValue(Time(seconds: 0.22))
            XCTAssertTrue(output.valueState.contains(.needsEvaluation))
            _ = output.value
            XCTAssertEqual(group.layer.removedCount, 0)

            inputs.base.time.setValue(Time(seconds: 0.23))
            XCTAssertTrue(output.valueState.contains(.needsEvaluation))
            _ = output.value
            inputs.base.time.setValue(Time(seconds: 0.24))
            XCTAssertFalse(output.valueState.contains(.needsEvaluation))
        }
    }

    func testResolvedStyledTextTransitionRetargetComposesMultipleRemovedLayers() throws {
        let (viewGraph, rendererHost) = makeInterpolationViewGraph()
        _ = rendererHost

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let group = _ShapeStyle_InterpolatorGroup()
            let serial = installUnstyledLayer(in: group)
            let initialContents = versionedDisplayList(
                makeDisplayList(
                    debugItemCount: 1,
                    itemCount: 1,
                    bounds: CGRect(x: 10, y: 10, width: 86, height: 17)
                ),
                version: 1
            )
            let firstTargetContents = versionedDisplayList(
                makeDisplayList(
                    debugItemCount: 1,
                    itemCount: 1,
                    bounds: CGRect(x: 10, y: 10, width: 70, height: 17)
                ),
                version: 2
            )
            let retargetedContents = versionedDisplayList(
                makeDisplayList(
                    debugItemCount: 1,
                    itemCount: 1,
                    bounds: CGRect(x: 9, y: 10, width: 69, height: 17)
                ),
                version: 3
            )
            let initialList = DisplayList.effect(
                .interpolatorLayer(group, serial),
                contents: initialContents
            )
            let firstTarget = DisplayList.effect(
                .interpolatorLayer(group, serial),
                contents: firstTargetContents
            )
            let retargeted = DisplayList.effect(
                .interpolatorLayer(group, serial),
                contents: retargetedContents
            )
            let displayList = graph.makeInput(value: initialList)
            let content = graph.makeInput(
                value: ResolvedStyledText(version: 1, transitionText: "Remove Child")
            )
            let inputs = makeViewInputs(graph: graph)
            var transaction = Transaction()
            transaction.animation = .easeInOut(duration: 5)
            inputs.base.transaction.setValue(transaction)
            inputs.size.setValue(ViewSize(width: 86, height: 17))
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: inputs,
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 1)

            displayList.setValue(firstTarget, transaction: transaction)
            inputs.size.setValue(ViewSize(width: 70, height: 17), transaction: transaction)
            content.setValue(
                ResolvedStyledText(version: 2, transitionText: "Insert Child"),
                transaction: transaction
            )
            XCTAssertEqual(output.value.effects.count, 1)
            XCTAssertEqual(group.layers[0].state.removedCount, 1)
            XCTAssertEqual(
                group.layers[0].state.removed.first?.interpolator?
                    .to.interpolationBounds,
                firstTargetContents.interpolationBounds
            )

            inputs.base.time.setValue(Time(seconds: 0.01))
            _ = output.value
            inputs.base.time.setValue(Time(seconds: 0.02))
            _ = output.value

            displayList.setValue(retargeted, transaction: transaction)
            inputs.size.setValue(ViewSize(width: 69, height: 17), transaction: transaction)
            XCTAssertEqual(output.value.effects.count, 1)
            XCTAssertEqual(group.layers[0].state.removedCount, 2)
            XCTAssertEqual(
                group.layers[0].state.removed.last?.interpolator?
                    .to.interpolationBounds,
                retargetedContents.interpolationBounds
            )
        }
    }

    func testResolvedStyledTextContentChangeComposesActiveSizeOnlyTransition() throws {
        let (viewGraph, rendererHost) = makeInterpolationViewGraph()
        _ = rendererHost

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let group = _ShapeStyle_InterpolatorGroup()
            let serial = installUnstyledLayer(in: group)
            let compactContents = versionedDisplayList(
                makeDisplayList(
                    debugItemCount: 1,
                    itemCount: 1,
                    bounds: CGRect(x: 319, y: 249, width: 31, height: 10)
                ),
                version: 1
            )
            let changedCompactContents = versionedDisplayList(
                compactContents,
                version: 2
            )
            let expandedContents = versionedDisplayList(
                makeDisplayList(
                    debugItemCount: 1,
                    itemCount: 1,
                    bounds: CGRect(x: 372, y: 249, width: 35, height: 10)
                ),
                version: 3
            )
            let residualContents = versionedDisplayList(
                makeDisplayList(
                    debugItemCount: 1,
                    itemCount: 1,
                    bounds: CGRect(x: 372, y: 249, width: 35.1, height: 10)
                ),
                version: 4
            )
            let compactList = DisplayList.effect(
                .interpolatorLayer(group, serial),
                contents: compactContents
            )
            let changedCompactList = DisplayList.effect(
                .interpolatorLayer(group, serial),
                contents: changedCompactContents
            )
            let expandedList = DisplayList.effect(
                .interpolatorLayer(group, serial),
                contents: expandedContents
            )
            let residualList = DisplayList.effect(
                .interpolatorLayer(group, serial),
                contents: residualContents
            )
            let displayList = graph.makeInput(value: compactList)
            let content = graph.makeInput(
                value: ResolvedStyledText(version: 1, transitionText: "compact")
            )
            let inputs = makeViewInputs(graph: graph)
            var transaction = Transaction()
            transaction.animation = .linear(duration: 0.2)
            inputs.base.transaction.setValue(transaction)
            inputs.size.setValue(ViewSize(width: 31, height: 10))
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: inputs,
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 1)

            displayList.setValue(changedCompactList, transaction: transaction)
            content.setValue(
                ResolvedStyledText(version: 2, transitionText: "expanded"),
                transaction: transaction
            )
            XCTAssertEqual(output.value.effects.count, 1)
            XCTAssertEqual(group.layers[0].state.removedCount, 1)

            inputs.base.time.setValue(Time(seconds: 0.01))
            _ = output.value
            inputs.base.time.setValue(Time(seconds: 0.02))
            _ = output.value

            inputs.base.time.setValue(Time(seconds: 0.22))
            displayList.setValue(expandedList, transaction: transaction)
            inputs.size.setValue(ViewSize(width: 35, height: 10), transaction: transaction)
            XCTAssertEqual(output.value.effects.count, 1)
            XCTAssertEqual(group.layers[0].state.removedCount, 1)

            inputs.base.time.setValue(Time(seconds: 0.23))
            displayList.setValue(residualList, transaction: transaction)
            inputs.size.setValue(ViewSize(width: 35.1, height: 10), transaction: transaction)
            XCTAssertEqual(output.value.effects.count, 1)
            XCTAssertEqual(group.layers[0].state.removedCount, 2)

            content.setValue(
                ResolvedStyledText(version: 3, transitionText: "compact"),
                transaction: transaction
            )
            XCTAssertEqual(output.value.effects.count, 1)
            XCTAssertEqual(group.layers[0].state.removedCount, 3)
            XCTAssertEqual(
                try XCTUnwrap(
                    group.layers[0].state.removed.last?
                        .interpolator?.from.interpolationBounds
                ).width,
                try XCTUnwrap(compactContents.interpolationBounds).width,
                accuracy: 0.001
            )
        }
    }

    func testInterpolatedDisplayListIdentityTransitionSyncsCurrentWithoutRemoval() throws {
        let graph = _AGGraph()
        InterpolatableContentProbeLog.reset()

        try _AGGraph.withCurrent(graph) {
            let group = DisplayList.UnaryInterpolatorGroup()
            let firstList = makeInterpolatorLayerDisplayList(
                group: group,
                debugItemCount: 1,
                itemCount: 1,
                version: 1
            )
            let secondList = makeInterpolatorLayerDisplayList(
                group: group,
                debugItemCount: 1,
                itemCount: 1,
                version: 2
            )
            let displayList = graph.makeInput(value: firstList)
            let content = graph.makeInput(value: ProbeInterpolatableContent(value: 0))
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
            XCTAssertEqual(output.value.effects.count, 1)
            let initialSeed = group.layer.contentSeed

            displayList.setValue(secondList)
            content.setValue(ProbeInterpolatableContent(value: 1))
            let updated = output.value

            XCTAssertEqual(InterpolatableContentProbeLog.modifyTransitionCalls, 1)
            XCTAssertEqual(InterpolatableContentProbeLog.defaultAnimationCalls, 1)
            XCTAssertEqual(updated.effects.count, 1)
            XCTAssertEqual(group.layer.removedCount, 0)
            XCTAssertNotEqual(group.layer.contentSeed, initialSeed)
            XCTAssertEqual(group.layer.contents.displayList.items.count, 1)
            XCTAssertEqual(group.layer.contents.displayList.debugItems.count, 1)
        }
    }

    func testUnaryInterpolatorGroupRewriteSchedulesCurrentViewTime() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph

        let unary = DisplayList.UnaryInterpolatorGroup()
        let current = makeDisplayList(debugItemCount: 1)
        let target = makeDisplayList(debugItemCount: 2)
        var state = ContentTransition.State(transition: .opacity)
        state.animation = .linear(duration: 0.2)
        var time: Attribute<Time>!

        viewGraph.data.withCurrent {
            time = viewGraph.data.graph.makeInput(value: Time(seconds: 2))
            unary.update(
                contentSeed: DisplayList.Seed(),
                transition: state.transition,
                animation: nil,
                listener: nil,
                contentsScale: 1,
                rasterizationOptions: state.rasterizationOptions,
                supportsVFD: false
            )
            var initial = current
            _ = unary.rewriteInterpolation(
                serial: 0,
                list: &initial,
                time: time,
                frame: current.interpolationBounds ?? .zero,
                contentOrigin: .zero,
                contentOffset: .zero,
                version: DisplayList.Version(forUpdate: ())
            )
            unary.update(
                contentSeed: DisplayList.Seed(decodedValue: 7),
                transition: state.transition,
                animation: state.animation,
                listener: nil,
                contentsScale: 1,
                rasterizationOptions: state.rasterizationOptions,
                supportsVFD: false
            )
            var output = target
            _ = unary.rewriteInterpolation(
                serial: 0,
                list: &output,
                time: time,
                frame: target.interpolationBounds ?? .zero,
                contentOrigin: .zero,
                contentOffset: .zero,
                version: DisplayList.Version(forUpdate: ())
            )
        }

        XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 2, accuracy: 0.000_001)
        XCTAssertEqual(unary.nextUpdate(after: .zero).seconds, 2.2, accuracy: 0.000_001)

        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
        viewGraph.data.withCurrent {
            time.setValue(Time(seconds: 2.01))
            var output = target
            _ = unary.rewriteInterpolation(
                serial: 0,
                list: &output,
                time: time,
                frame: target.interpolationBounds ?? .zero,
                contentOrigin: .zero,
                contentOffset: .zero,
                version: DisplayList.Version(forUpdate: ())
            )
        }
        XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 2.01, accuracy: 0.000_001)
        XCTAssertEqual(unary.nextUpdate(after: .zero).seconds, 2.21, accuracy: 0.000_001)

        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
        viewGraph.data.withCurrent {
            time.setValue(Time(seconds: 2.02))
            var output = target
            _ = unary.rewriteInterpolation(
                serial: 0,
                list: &output,
                time: time,
                frame: target.interpolationBounds ?? .zero,
                contentOrigin: .zero,
                contentOffset: .zero,
                version: DisplayList.Version(forUpdate: ())
            )
        }
        XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 2.02, accuracy: 0.000_001)

        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
        viewGraph.data.withCurrent {
            time.setValue(Time(seconds: 2.21))
            var output = target
            _ = unary.rewriteInterpolation(
                serial: 0,
                list: &output,
                time: time,
                frame: target.interpolationBounds ?? .zero,
                contentOrigin: .zero,
                contentOffset: .zero,
                version: DisplayList.Version(forUpdate: ())
            )
        }
        XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 2.21, accuracy: 0.000_001)
        XCTAssertEqual(unary.layer.removedCount, 0)
    }

    func testResolvedImageInterpolatableContentSurface() throws {
        XCTAssertEqual(ImageDrawing.defaultTransition, .interpolate)

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

        let sourceSymbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
            name: "photo.fill",
            variableValue: nil,
            bundle: nil
        ))
        let targetSymbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
            name: "draw",
            variableValue: nil,
            bundle: nil
        ))
        let sourceImage = ImageDrawing(symbol: sourceSymbol)
        let targetImage = ImageDrawing(symbol: targetSymbol)
        var replacementState = ContentTransition.State(
            transition: .symbolEffect(.replace.upUp),
            style: .animatedWidget,
            animation: .linear(duration: 3),
            options: [.formsGroup]
        )

        sourceImage.modifyTransition(
            state: &replacementState,
            to: targetImage
        )

        XCTAssertEqual(replacementState.transition, .identity)
        XCTAssertEqual(replacementState.style, .animatedWidget)
        XCTAssertEqual(
            replacementState.animation,
            .linear(duration: 3)
        )
        XCTAssertEqual(replacementState.options, [.formsGroup])

        var contentTransitionTargetSymbol = targetSymbol
        contentTransitionTargetSymbol.allowsContentTransitions = true
        let contentTransitionTargetImage = ImageDrawing(
            symbol: contentTransitionTargetSymbol
        )
        var contentTransitionState = ContentTransition.State(
            transition: .interpolate
        )
        sourceImage.modifyTransition(
            state: &contentTransitionState,
            to: contentTransitionTargetImage
        )
        XCTAssertEqual(contentTransitionState.transition, .opacity)

        // ASSERTIONS symbolEffectReplaceTransitionStateObserved
    }

    func testResolvedStyledTextInterpolatableContentSurface() {
        XCTAssertEqual(ResolvedStyledText.defaultTransition, .interpolate)

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

        var fixedNumericState = ContentTransition.State(transition: .numericText())
        text.modifyTransition(state: &fixedNumericState, to: ResolvedStyledText(version: 2))
        XCTAssertEqual(fixedNumericState.transition, .numericText())

        var automaticNumericState = ContentTransition.State(transition: .numericText(value: 17))
        text.modifyTransition(state: &automaticNumericState, to: ResolvedStyledText(version: 2))
        XCTAssertEqual(automaticNumericState.transition, .numericText(value: 17))

        let environment = EnvironmentValues()
        XCTAssertEqual(Text(verbatim: "A")._resolveTransitionText(in: environment), "A")
        XCTAssertEqual((Text(verbatim: "A") + Text(verbatim: "B"))._resolveTransitionText(in: environment), "AB")
        XCTAssertNil(Text(Image(systemName: "star"))._resolveTransitionText(in: environment))
    }

    // ASSERTIONS interpolatedDisplayListInputTransactionObserved
    // ASSERTIONS interpolatedDisplayListTransactionalFlagObserved
    func testApplyInterpolatorGroupReplacesDisplayListOutput() throws {
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
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
            XCTAssertTrue(
                graph.flags(for: outputID).contains(.transactional)
            )
            let output = Attribute<DisplayList>(outputID).value
            XCTAssertEqual(output.debugItems.count, sourceList.debugItems.count)
        }
    }

    // ASSERTIONS shapeStyleUnstyledTextLayerObserved
    func testTextMakeViewAppliesResolvedStyledTextInterpolator() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let text = graph.makeInput(value: Text("Hello"))
            var inputs = makeViewInputs(graph: graph)
            inputs.preferences.keys.add(DisplayList.Key.self)
            let outputs = Text._makeView(
                view: _GraphValue(_attribute: text),
                inputs: inputs
            )

            XCTAssertEqual(outputs.preferences.values(for: ResourceList.Key.self).count, 1)
            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            XCTAssertTrue(graph.debugDescription(for: outputID).contains("(stateful)"))
            var groupVisitor = InterpolatorGroupBodyVisitor()
            outputID.visitBody(&groupVisitor)
            let group = try XCTUnwrap(
                groupVisitor.group as? _ShapeStyle_InterpolatorGroup
            )
            let output = Attribute<DisplayList>(outputID).value
            XCTAssertEqual(group.layers.count, 1)
            XCTAssertEqual(group.layers[0].id, .unstyled)
            XCTAssertEqual(output.items.count, 1)
            if case let .effect(.identity, contents) = output.items[0].value {
                XCTAssertLessThanOrEqual(contents.items.count, 1)
            } else {
                XCTFail("missing rewritten text interpolation layer")
            }
        }
    }

    // ASSERTIONS shapeStyleUnstyledImageLayerObserved
    func testImageMakeViewAppliesResolvedImageInterpolator() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let image = graph.makeInput(value: Image(systemName: "draw"))
            var inputs = makeViewInputs(graph: graph)
            inputs.preferences.keys.add(DisplayList.Key.self)
            let outputs = Image._makeView(
                view: _GraphValue(_attribute: image),
                inputs: inputs
            )

            let resourceID = try XCTUnwrap(
                outputs.preferences.value(for: ResourceList.Key.self)
            )
            XCTAssertTrue(Attribute<ResourceList>(resourceID).value.items.isEmpty)
            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            XCTAssertTrue(graph.debugDescription(for: outputID).contains("(stateful)"))
            var groupVisitor = InterpolatorGroupBodyVisitor()
            outputID.visitBody(&groupVisitor)
            let group = try XCTUnwrap(
                groupVisitor.group as? _ShapeStyle_InterpolatorGroup
            )
            let output = Attribute<DisplayList>(outputID).value
            XCTAssertEqual(group.layers.count, 1)
            XCTAssertEqual(group.layers[0].id, .unstyled)
            XCTAssertEqual(output.items.count, 1)
            if case let .effect(.identity, contents) = output.items[0].value {
                XCTAssertLessThanOrEqual(contents.items.count, 1)
            } else {
                XCTFail("missing rewritten image interpolation layer")
            }
        }
    }

    func testSystemSymbolImageResolvesBeforeTheResourcePass() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let image = graph.makeInput(value: Image(systemName: "draw"))
            var inputs = makeViewInputs(graph: graph)
            inputs.requestsLayoutComputer = true
            inputs.preferences.keys.add(DisplayList.Key.self)
            let outputs = Image._makeView(
                view: _GraphValue(_attribute: image),
                inputs: inputs
            )

            let resourceID = try XCTUnwrap(
                outputs.preferences.value(for: ResourceList.Key.self)
            )
            XCTAssertTrue(Attribute<ResourceList>(resourceID).value.items.isEmpty)

            let layoutComputer = try XCTUnwrap(
                outputs._layoutComputer.attribute?.value
            )
            let resolvedSize = layoutComputer.sizeThatFits(.unspecified)
            XCTAssertGreaterThan(resolvedSize.width, 0)
            XCTAssertGreaterThan(resolvedSize.height, 0)

            let outputID = try XCTUnwrap(
                outputs.preferences.value(for: DisplayList.Key.self)
            )
            XCTAssertFalse(Attribute<DisplayList>(outputID).value.items.isEmpty)

            // ASSERTIONS imageViewChildSynchronousResolutionObserved
        }
    }

    func testPortableVectorResolutionIsCachedAcrossPresentationTicks() throws {
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
            let symbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
                name: "draw",
                variableValue: nil,
                bundle: nil
            ))
            let provider = CountingVectorImageProvider(symbol: symbol)
            let image = graph.makeInput(value: Image(provider: provider))
            let backendSource = graph.makeInput(value: Optional<VUI.Image>.none)
            let backendImage = graph.makeInput(
                value: ImageDrawing?.none
            )
            let environment = graph.makeInput(value: EnvironmentValues())
            let transaction = graph.makeInput(value: Transaction())
            let time = graph.makeInput(value: Time(seconds: 0))
            let child: Attribute<ImageViewChild.Value> = graph.makeStatefulRule(
                ImageViewChild(
                    view: image,
                    backendSource: backendSource,
                    backendImage: backendImage,
                    environment: environment,
                    transaction: transaction,
                    time: time
                )
            )

            XCTAssertNotNil(child.value.image?.symbol)
            XCTAssertEqual(provider.resolutionCount, 1)

            time.setValue(Time(seconds: 0.25))
            XCTAssertNotNil(child.value.image?.symbol)
            time.setValue(Time(seconds: 0.5))
            XCTAssertNotNil(child.value.image?.symbol)
            XCTAssertEqual(provider.resolutionCount, 1)

            // ASSERTIONS imageViewChildSynchronousResolutionObserved
        }
    }

    func testImageResourceResolutionKeepsFirstTransactionForPendingImage() throws {
        let state = _ImageResourceResolutionState()
        let imageA = Image(systemName: "photo.fill")
        let imageB = Image(systemName: "pencil")
        let immediate = Transaction()
        var animated = Transaction()
        animated.animation = .linear(duration: 5)

        XCTAssertNil(state.transaction(for: imageA, candidate: immediate).animation)
        XCTAssertNil(state.transaction(for: imageA, candidate: animated).animation)

        state.didResolve(image: imageA)
        XCTAssertEqual(
            try XCTUnwrap(state.transaction(for: imageB, candidate: animated).animation).box.duration,
            5,
            accuracy: 0.000_001
        )
    }

    func testResolvedStyledTextInterpolatorUpdatesShapeStyleLayer() throws {
        let (viewGraph, rendererHost) = makeInterpolationViewGraph()
        _ = rendererHost

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let group = _ShapeStyle_InterpolatorGroup()
            let serial = installUnstyledLayer(in: group)
            let sourceList = makeInterpolatorLayerDisplayList(
                group: group,
                serial: serial,
                debugItemCount: 1,
                itemCount: 1,
                version: 1
            )
            let targetList = makeInterpolatorLayerDisplayList(
                group: group,
                serial: serial,
                debugItemCount: 1,
                itemCount: 1,
                version: 2
            )
            let displayList = graph.makeInput(value: sourceList)
            let content = graph.makeInput(value: ResolvedStyledText(version: 0))
            let inputs = makeViewInputs(graph: graph)
            var transaction = Transaction()
            transaction.animation = .linear(duration: 0.25)
            inputs.base.transaction.setValue(transaction)
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: inputs,
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 1)

            displayList.setValue(targetList, transaction: transaction)
            content.setValue(
                ResolvedStyledText(version: 1),
                transaction: transaction
            )
            let updated = output.value
            XCTAssertEqual(updated.effects.count, 1)
            XCTAssertEqual(group.layers[0].state.removedCount, 1)
            XCTAssertEqual(
                group.layers[0].state.removed.first?.transition?.method,
                ContentTransition.Method.none.method
            )
            XCTAssertEqual(
                group.layers[0].state.removed.first?.interpolator?
                    .to.items.first?.version.value,
                2
            )
        }
    }

    func testResolvedStyledTextInterpolatorUsesItsDedicatedTransactionAttribute() throws {
        let (viewGraph, rendererHost) = makeInterpolationViewGraph()
        _ = rendererHost

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let group = _ShapeStyle_InterpolatorGroup()
            let serial = installUnstyledLayer(in: group)
            let sourceList = makeInterpolatorLayerDisplayList(
                group: group,
                serial: serial,
                debugItemCount: 1,
                itemCount: 1,
                version: 1
            )
            let animatedList = makeInterpolatorLayerDisplayList(
                group: group,
                serial: serial,
                debugItemCount: 1,
                itemCount: 1,
                version: 2
            )
            let immediateList = makeInterpolatorLayerDisplayList(
                group: group,
                serial: serial,
                debugItemCount: 1,
                itemCount: 1,
                version: 3
            )
            let displayList = graph.makeInput(value: sourceList)
            let content = graph.makeInput(value: ResolvedStyledText(version: 0))
            let transaction = graph.makeInput(value: Transaction())
            var inputs = makeViewInputs(graph: graph)
            inputs.base.transaction = transaction
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: inputs,
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 1)

            var animatedTransaction = Transaction()
            animatedTransaction.animation = .linear(duration: 5)
            transaction.setValue(animatedTransaction)
            displayList.setValue(animatedList, transaction: animatedTransaction)
            content.setValue(ResolvedStyledText(version: 1), transaction: animatedTransaction)

            _ = output.value
            XCTAssertEqual(group.layers[0].state.removedCount, 1)
            XCTAssertEqual(
                try XCTUnwrap(
                    group.layers[0].state.removed.first
                ).animation.activeDuration,
                5,
                accuracy: 0.000_001
            )

            transaction.setValue(Transaction())
            displayList.setValue(immediateList)
            content.setValue(ResolvedStyledText(version: 2))

            let immediate = output.value
            XCTAssertEqual(immediate.effects.count, 1)
            XCTAssertEqual(group.layers[0].state.removedCount, 1)
            XCTAssertEqual(
                group.layers[0].state.contents.displayList.items.first?
                    .version.value,
                3
            )
        }
    }

    func testTextResourceResolutionKeepsFirstTransactionForPendingVersion() throws {
        let state = _TextResourceResolutionState()
        let immediate = Transaction()
        var animated = Transaction()
        animated.animation = .linear(duration: 5)

        XCTAssertNil(state.transaction(for: 1, candidate: immediate).animation)
        XCTAssertNil(state.transaction(for: 1, candidate: animated).animation)

        state.didResolve(version: 1)
        XCTAssertEqual(
            try XCTUnwrap(state.transaction(for: 2, candidate: animated).animation).box.duration,
            5,
            accuracy: 0.000_001
        )
    }

    func testInterpolatedDisplayListReadsContentTransitionFallbackPath() throws {
        let graph = _AGGraph()
        InterpolatableContentProbeLog.reset()

        try _AGGraph.withCurrent(graph) {
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
            XCTAssertEqual(updated.effects.count, 1)
            if case .some(.interpolatorRoot) = updated.effects.first?.effect {
            } else {
                XCTFail("missing deferred interpolation root")
            }
        }
    }

    private func makeInterpolatorLayerDisplayList(
        group: DisplayList.InterpolatorGroup,
        serial: UInt32 = 0,
        debugItemCount: Int,
        itemCount: Int,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 10, height: 10),
        version: Int
    ) -> DisplayList {
        DisplayList.effect(
            .interpolatorLayer(group, serial),
            contents: versionedDisplayList(
                makeDisplayList(
                    debugItemCount: debugItemCount,
                    itemCount: itemCount,
                    bounds: bounds
                ),
                version: version
            )
        )
    }

    private func makeInterpolationViewGraph() -> (
        viewGraph: ViewGraph,
        rendererHost: TestViewRendererHost
    ) {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        return (viewGraph, rendererHost)
    }

    private func versionedDisplayList(
        _ list: DisplayList,
        version: Int
    ) -> DisplayList {
        var list = list
        let version = DisplayList.Version(value: version)
        for index in list.items.indices {
            list.items[index].version = version
        }
        return list
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

    private func typedCrossFades(
        in list: DisplayList
    ) -> [DisplayList.Content.CrossFadeValue]? {
        var values: [DisplayList.Content.CrossFadeValue] = []
        values.reserveCapacity(list.items.count)
        for item in list.items {
            guard case let .content(content) = item.value,
                  case let .crossFade(value) = content.value else {
                return nil
            }
            values.append(value)
        }
        return values
    }

    private func typedCrossFade(
        in item: DisplayList.Item
    ) -> DisplayList.Content.CrossFadeValue? {
        guard case let .content(content) = item.value,
              case let .crossFade(value) = content.value else {
            return nil
        }
        return value
    }

    private func symbolLayerMask(
        in branch: DisplayList.Content.CrossFadeValue.Branch?
    ) -> [Double]? {
        guard let item = branch?.contents.items.first,
              case let .content(content) = item.value,
              case let .image(image) = content.value else {
            return nil
        }
        return image.image.symbolLayerOpacities
    }

    private func symbolDrawProgresses(
        in branch: DisplayList.Content.CrossFadeValue.Branch?
    ) -> [Double]? {
        guard let item = branch?.contents.items.first,
              case let .content(content) = item.value,
              case let .image(image) = content.value else {
            return nil
        }
        return image.image.symbolDrawProgresses
    }

    private func crossFadeFractions(
        in value: DisplayList.Content.CrossFadeValue
    ) -> (source: Float, target: Float)? {
        guard case let .effect(
            .crossFade(sourceFraction, targetFraction),
            _
        ) = value.command else {
            return nil
        }
        return (sourceFraction, targetFraction)
    }

    private func symbolIdentity(
        in list: DisplayList
    ) -> ResolvedVectorSymbol.Identity? {
        guard let item = list.items.first,
              case let .content(content) = item.value,
              case let .image(image) = content.value else {
            return nil
        }
        return image.image.symbol?.identity
    }

    private func typedOpacityStyle(
        in item: DisplayList.Item
    ) -> (opacity: Double, contents: DisplayList)? {
        guard case let .content(content) = item.value,
              case let .style(value) = content.value,
              case let .opacity(opacity) = value.style else {
            return nil
        }
        return (opacity, value.contents)
    }

    private func typedBlurStyle(
        in item: DisplayList.Item
    ) -> (radius: CGFloat, isOpaque: Bool, contents: DisplayList)? {
        guard case let .content(content) = item.value,
              case let .style(value) = content.value,
              case let .blur(radius, isOpaque) = value.style else {
            return nil
        }
        return (radius, isOpaque, value.contents)
    }

    private func opacityTransition(events: UInt32) -> RBTransition {
        let transition = RBTransition()
        transition.addEffect(opacityEffect(events: events))
        return transition
    }

    private func opacityEffect(events: UInt32) -> RBTransitionEffect {
        let effect = RBTransitionEffect()
        effect.type = ContentTransition.EffectType.opacity.type
        effect.duration = 1
        effect.events = events
        return effect
    }

    private func displayList<Modifier: ViewModifier>(
        applying modifier: Modifier,
        to source: DisplayList,
        needsGeometry: Bool = false
    ) throws -> DisplayList {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        return try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let modifierAttr = graph.makeInput(value: modifier)
            let sourceAttr = graph.makeInput(value: source)
            var inputs = makeViewInputs(graph: graph)
            inputs.needsGeometry = needsGeometry
            let outputs = Modifier._makeView(
                modifier: _GraphValue(_attribute: modifierAttr),
                inputs: inputs
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
    ) -> ImageDrawing {
        ImageDrawing(
            baseline: baseline,
            shading: shading,
            texture: texture,
            textureTransform: textureTransform,
            scaleFactor: scaleFactor
        )
    }

    private func makeNumericTextDisplayList(
        _ text: String,
        numericValue: Float
    ) throws -> DisplayList {
        let face = NumericTransitionTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], text)],
            scaleFactor: 1
        )
        let styledText = ResolvedStyledText(resolvedText: resolved, version: 1)
        let view = StyledTextContentView(text: styledText, renderer: nil)
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 20)
        var list = DisplayList()
        list.appendTextItem(
            view,
            size: bounds.size,
            foreground: .color(.white),
            bounds: bounds,
            seed: DisplayList.Seed(DisplayList.Version(forUpdate: ()))
        )
        list.numericValue = numericValue
        return list
    }

    private func makeViewInputs(
        graph: _AGGraph,
        environment values: EnvironmentValues = EnvironmentValues()
    ) -> _ViewInputs {
        let environment = graph.makeInput(value: values)
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: environment,
            transaction: graph.makeInput(value: Transaction())
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
