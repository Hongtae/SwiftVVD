import XCTest
@testable import VUI
@testable import VVD

final class ColorPickerSurfaceTests: XCTestCase {
    // ASSERTIONS: colorPickerPublicStructure27Observed
    // ASSERTIONS: colorPickerFieldMetadata27Observed
    // ASSERTIONS: colorPickerOwnerLowering27Observed
    func testPublicSurfaceNormalizesColorAndCGColorBindings() {
        var color = VUI.Color(
            .sRGB,
            red: 0.1,
            green: 0.2,
            blue: 0.3,
            opacity: 0.4
        )
        var cgColor = CGColor(
            red: 0.5,
            green: 0.6,
            blue: 0.7,
            alpha: 0.8
        )
        let colorPicker = ColorPicker(
            selection: Binding(
                get: { color },
                set: { color = $0 }
            ),
            supportsOpacity: false
        ) {
            Text("Color")
        }
        let cgColorPicker = ColorPicker(
            selection: Binding(
                get: { cgColor },
                set: { cgColor = $0 }
            ),
            supportsOpacity: true
        ) {
            Text("CG Color")
        }

        XCTAssertEqual(
            Mirror(reflecting: colorPicker).children.map(\.label),
            ["_color", "supportsOpacity", "label"]
        )
        XCTAssertEqual(
            Mirror(reflecting: cgColorPicker).children.map(\.label),
            ["_color", "supportsOpacity", "label"]
        )
        XCTAssertFalse(colorPicker.supportsOpacity)
        XCTAssertTrue(cgColorPicker.supportsOpacity)

        let replacement = VUI.Color(
            .sRGB,
            red: 0.8,
            green: 0.4,
            blue: 0.2,
            opacity: 0.6
        )
        colorPicker._color.wrappedValue = replacement
        cgColorPicker._color.wrappedValue = replacement

        assertComponents(
            color,
            red: 0.8,
            green: 0.4,
            blue: 0.2,
            opacity: 0.6
        )
        assertComponents(
            cgColor,
            red: 0.8,
            green: 0.4,
            blue: 0.2,
            opacity: 0.6
        )

        let bodyType = String(reflecting: type(of: colorPicker.body))
        XCTAssertTrue(bodyType.contains("ResolvedColorPickerStyle"))
        XCTAssertTrue(bodyType.contains("StaticSourceWriter"))
    }

    // ASSERTIONS: colorPickerPublicStructure27Observed
    func testTextConvenienceInitializerFamiliesTypeCheck() {
        let color = Binding.constant(VUI.Color.red)
        let cgColor = Binding.constant(
            CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        )
        let titleResource: LocalizedStringResource = "Tint"

        _ = ColorPicker("Tint", selection: color)
        _ = ColorPicker(titleResource, selection: color)
        _ = ColorPicker(Substring("Tint"), selection: color)
        _ = ColorPicker("Tint", selection: cgColor)
        _ = ColorPicker(titleResource, selection: cgColor)
        _ = ColorPicker(Substring("Tint"), selection: cgColor)
    }

    func testCGColorCompatibilitySurfacePreservesReferenceAndCodingSemantics() throws {
        let white = CGColor.white
        let sameWhite = white
        let rgbWhite = CGColor(
            red: 1,
            green: 1,
            blue: 1,
            alpha: 1
        )

        XCTAssertTrue(white === sameWhite)
        XCTAssertTrue(white === CGColor.white)
        XCTAssertTrue(CGColor.black === CGColor.black)
        XCTAssertTrue(CGColor.clear === CGColor.clear)
        XCTAssertEqual(white.components, [1, 1])
        XCTAssertEqual(CGColor.black.components, [0, 1])
        XCTAssertEqual(CGColor.clear.components, [0, 0])
        XCTAssertEqual(white.numberOfComponents, 2)
        XCTAssertEqual(rgbWhite.numberOfComponents, 4)
        XCTAssertNotEqual(white, rgbWhite)

        if #available(macOS 27, iOS 27, tvOS 27, watchOS 27, *) {
            let encoded = try JSONEncoder().encode(rgbWhite)
            let decoded = try JSONDecoder().decode(
                CGColor.self,
                from: encoded
            )
            XCTAssertEqual(decoded, rgbWhite)
        }
    }

    // ASSERTIONS: colorPickerWriteback27Observed
    // ASSERTIONS: colorPickerOpacityPolicy27Observed
    func testComponentProjectionWritesOneColorPerEdit() {
        var color = VUI.Color(
            .sRGB,
            red: 0.1,
            green: 0.2,
            blue: 0.3,
            opacity: 0.4
        )
        var writes = 0
        let projection = ColorPickerComponentProjection(
            color: Binding(
                get: { color },
                set: {
                    color = $0
                    writes += 1
                }
            ),
            supportsOpacity: true,
            environment: EnvironmentValues()
        )

        projection.binding(for: .red).wrappedValue = 0.8

        XCTAssertEqual(writes, 1)
        assertComponents(
            color,
            red: 0.8,
            green: 0.2,
            blue: 0.3,
            opacity: 0.4
        )
    }

    // ASSERTIONS: colorPickerOpacityPolicy27Observed
    func testOpacityDisabledEditClampsOutputToOpaque() {
        var color = VUI.Color(
            .sRGB,
            red: 0.1,
            green: 0.2,
            blue: 0.3,
            opacity: 0.4
        )
        var writes = 0
        let projection = ColorPickerComponentProjection(
            color: Binding(
                get: { color },
                set: {
                    color = $0
                    writes += 1
                }
            ),
            supportsOpacity: false,
            environment: EnvironmentValues()
        )

        projection.binding(for: .blue).wrappedValue = 0.9

        XCTAssertEqual(writes, 1)
        assertComponents(
            color,
            red: 0.1,
            green: 0.2,
            blue: 0.9,
            opacity: 1
        )
    }

    // ASSERTIONS: colorPickerOwnerLowering27Observed
    func testPortableControlAndEditorRenderWithoutAPlatformHost() {
        var color = VUI.Color(
            .sRGB,
            red: 0.2,
            green: 0.4,
            blue: 0.6,
            opacity: 0.8
        )
        let binding = Binding(
            get: { color },
            set: { color = $0 }
        )

        render(ColorPicker("Tint", selection: binding))
        render(ColorPickerEditor(
            color: binding,
            supportsOpacity: true
        ))
    }

    // ASSERTIONS: colorPickerWriteback27Observed
    // ASSERTIONS: colorPickerOpacityPolicy27Observed
    @MainActor
    func testMountedEditorDragWritesOneOpaqueColor() throws {
        let store = ColorPickerPointerStore(
            color: VUI.Color(
                .sRGB,
                red: 0.2,
                green: 0.4,
                blue: 0.6,
                opacity: 0.5
            )
        )
        let controller = WindowController(
            content: ColorPickerEditor(
                color: store.binding,
                supportsOpacity: false
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorPickerPointerStore.self)
            )
        )
        let size = CGSize(width: 320, height: 240)
        update(controller, size: size, tick: 0)

        let point = try XCTUnwrap(
            gesturePoints(
                in: controller,
                size: size,
                typeName: "DragGesture"
            ).max { lhs, rhs in
                lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
            }
        )
        click(controller, at: point)

        XCTAssertEqual(store.writes.count, 1)
        let resolved = store.color.resolve(in: EnvironmentValues())
        XCTAssertEqual(resolved.opacity, 1, accuracy: 0.000_001)
        XCTAssertTrue(
            max(resolved.red, resolved.green, resolved.blue) > 0.9
        )
    }

    @MainActor
    func testMountedSwatchOpensRendererOwnedEditor() throws {
        let store = ColorPickerPointerStore(color: .red)
        let controller = WindowController(
            content: ColorPicker("Tint", selection: store.binding)
                .frame(width: 240, height: 80),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorPickerSurfaceTests.self)
            )
        )
        let size = CGSize(width: 240, height: 80)
        update(controller, size: size, tick: 0)
        let window = try XCTUnwrap(
            ColorPickerTestWindow(
                name: "test",
                style: [],
                delegate: nil,
                data: [:]
            )
        )
        XCTAssertTrue(controller.shouldClose(window: window))

        let point = try XCTUnwrap(
            gesturePoints(
                in: controller,
                size: size,
                typeName: "ButtonGesture"
            ).first
        )
        click(controller, at: point)
        update(controller, size: size, tick: 1)

        XCTAssertFalse(controller.shouldClose(window: window))
    }

    private func render<Content: View>(_ root: Content) {
        let renderer = TestViewRendererHost()
        let graph = ViewGraph(
            rootViewType: Content.self,
            content: root,
            rendererHost: renderer,
            requestedOutputs: []
        )
        renderer.storage = graph
        graph.setSize(CGSize(width: 320, height: 240))
        graph.updateOutputs(at: .zero)
    }

    @MainActor
    private func update(
        _ controller: WindowController,
        size: CGSize,
        tick: UInt64
    ) {
        var redraw = false
        controller.updateView(
            tick: tick,
            delta: tick == 0 ? 0 : 1.0 / 60.0,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }
    }

    @MainActor
    private func gesturePoints(
        in controller: WindowController,
        size: CGSize,
        typeName: String
    ) -> [CGPoint] {
        var points: [CGPoint] = []
        for y in stride(from: 0.0, through: size.height, by: 2.0) {
            for x in stride(from: 0.0, through: size.width, by: 2.0) {
                let point = CGPoint(x: x, y: y)
                guard let responder = controller.gestureEnvironment
                    .eventBinding(
                        at: point,
                        accepting: VUI.MouseEvent.self
                    )?.responder as? any AnyGestureResponder,
                    String(reflecting: responder.gestureType)
                        .contains(typeName) else {
                    continue
                }
                points.append(point)
            }
        }
        return points
    }

    @MainActor
    private func click(
        _ controller: WindowController,
        at point: CGPoint
    ) {
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            location: point,
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            location: point,
            timestamp: 0.01
        )))
        Update.dispatchActions()
    }

    private func assertComponents(
        _ color: VUI.Color,
        red: Double,
        green: Double,
        blue: Double,
        opacity: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let resolved = color.resolve(in: EnvironmentValues())
        XCTAssertEqual(Double(resolved.red), red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(Double(resolved.green), green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(Double(resolved.blue), blue, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(Double(resolved.opacity), opacity, accuracy: 0.000_001, file: file, line: line)
    }

    private func assertComponents(
        _ color: CGColor,
        red: Double,
        green: Double,
        blue: Double,
        opacity: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = colorPickerComponents(of: color)
        XCTAssertEqual(components.red, red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(components.green, green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(components.blue, blue, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(components.alpha, opacity, accuracy: 0.000_001, file: file, line: line)
    }
}

private final class ColorPickerPointerStore: @unchecked Sendable {
    var color: VUI.Color
    var writes: [VUI.Color] = []

    init(color: VUI.Color) {
        self.color = color
    }

    var binding: Binding<VUI.Color> {
        Binding(
            get: { self.color },
            set: {
                self.color = $0
                self.writes.append($0)
            }
        )
    }
}

@MainActor
private final class ColorPickerTestWindow: VVD.Window {
    var activated = false
    var visible = false
    var contentBounds = CGRect.zero
    var windowFrame = CGRect.zero
    var contentScaleFactor: CGFloat = 1
    var resolution = CGSize.zero
    var origin = CGPoint.zero
    var contentSize = CGSize.zero
    var title: String
    weak var delegate: WindowDelegate?
    var screen: (any VVD.Screen)? { nil }
    var isValid: Bool { true }
    var platformHandle: OpaquePointer? { nil }
    var eventObservers = WindowEventObserverContainer()

    required init?(
        name: String,
        style: WindowStyle,
        delegate: WindowDelegate?,
        data: [String: Any]
    ) {
        title = name
        self.delegate = delegate
    }

    func show() {}
    func hide() {}
    func activate() {}
    func minimize() {}
    func requestToClose() -> Bool { true }
    func close() {}
    func convertPointToScreen(_ point: CGPoint) -> CGPoint { point }
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint { point }
}
