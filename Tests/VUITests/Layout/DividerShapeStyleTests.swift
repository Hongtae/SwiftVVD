import Foundation
import XCTest
@testable import VUI

private struct DividerShapeProbe: Shape {
    var value: CGFloat

    var layoutDirectionBehavior: LayoutDirectionBehavior {
        .fixed
    }

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: value, dy: value))
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: 91, height: 73)
    }

    var animatableData: CGFloat {
        get { value }
        set { value = newValue }
    }
}

private enum DividerSystemColorDefinition: SystemColorDefinition {
    static func value(
        for type: SystemColorType,
        environment: EnvironmentValues
    ) -> Color.ResolvedHDR {
        Color.ResolvedHDR(Color.Resolved(
            colorSpace: .sRGB,
            red: 0.25,
            green: 0.5,
            blue: 0.75,
            opacity: 0.8
        ))
    }

    static func opacity(
        at level: Int,
        environment: EnvironmentValues
    ) -> Float {
        level > 0 ? 0.75 : 1
    }
}

private struct DividerOffsetOperationStyle: ShapeStyle {
    func _apply(to shape: inout _ShapeStyle_Shape) {
        switch shape.operation {
        case let .resolveStyle(name, levels):
            shape.result = .pack(_ShapeStyle_Pack(styles: levels.map {
                (
                    key: _ShapeStyle_Pack.Key(name, $0),
                    style: _ShapeStyle_Pack.Style(.color(
                        Color.red.resolveHDR(in: shape.environment)
                    ))
                )
            }))
        case .copyStyle:
            shape.result = .style(AnyShapeStyle(Color.red))
        default:
            Color.red._apply(to: &shape)
        }
    }

    typealias Resolved = Never
}

final class DividerShapeStyleTests: XCTestCase {
    // ASSERTIONS dividerShapeStyleInternalsObserved
    func testObservedDividerAndShapeStyleStorage() {
        XCTAssertEqual(
            labels(of: DividerStyleConfiguration(orientation: .horizontal)),
            ["orientation"]
        )
        XCTAssertEqual(
            labels(of: ResolvedDivider(
                configuration: DividerStyleConfiguration(
                    orientation: .horizontal
                )
            )),
            ["configuration"]
        )
        XCTAssertEqual(labels(of: PlainDividerStyle()), ["_thickness"])
        XCTAssertEqual(labels(of: DefaultDividerStyle()), [])
        XCTAssertEqual(
            labels(of: DividerStyleModifier(style: PlainDividerStyle())),
            ["style"]
        )
        XCTAssertEqual(
            labels(of: DividerShape(DividerShapeProbe(value: 2))),
            ["base"]
        )
        XCTAssertEqual(
            labels(of: HierarchicalShapeStyle.primary),
            ["id"]
        )
        XCTAssertEqual(labels(of: SeparatorShapeStyle()), [])
        XCTAssertEqual(
            labels(of: _OpacityShapeStyle(style: Color.red, opacity: 0.5)),
            ["style", "opacity"]
        )
        XCTAssertEqual(
            labels(of: HierarchicalShapeStyleModifier(
                base: Color.red,
                level: 2
            )),
            ["base", "level"]
        )
        XCTAssertEqual(
            labels(of: OffsetShapeStyle(base: Color.red, offset: 2)),
            ["base", "offset"]
        )
        XCTAssertEqual(labels(of: SystemColorsStyle()), [])
        XCTAssertEqual(
            labels(of: SystemColorDefinitionType(
                base: DividerSystemColorDefinition.self
            )),
            ["base"]
        )

        XCTAssertEqual(MemoryLayout<SeparatorShapeStyle>.size, 0)
        XCTAssertEqual(MemoryLayout<SeparatorShapeStyle>.stride, 1)
        XCTAssertEqual(MemoryLayout<_ShapeStyle_Shape>.size, 108)
        XCTAssertEqual(MemoryLayout<_ShapeStyle_Shape>.stride, 112)
        XCTAssertEqual(MemoryLayout<_ShapeStyle_Shape.Operation>.size, 25)
        XCTAssertEqual(MemoryLayout<_ShapeStyle_Shape.Result>.size, 9)
        XCTAssertEqual(
            MemoryLayout<_ShapeStyle_Shape.PreparedTextResult>.size,
            8
        )
        XCTAssertEqual(
            MemoryLayout<_ShapeStyle_Shape.RecursiveStyles>.size,
            1
        )
        XCTAssertEqual(MemoryLayout<_ShapeStyle_ShapeType>.size, 1)
        XCTAssertEqual(MemoryLayout<_ShapeStyle_ShapeType>.stride, 1)
        XCTAssertEqual(
            MemoryLayout<_ShapeStyle_ShapeType.Operation>.size,
            0
        )
        XCTAssertEqual(MemoryLayout<_ShapeStyle_ShapeType.Result>.size, 1)
        XCTAssertEqual(MemoryLayout<_ShapeStyle_Substrate>.size, 1)
        XCTAssertEqual(MemoryLayout<SystemColorType>.size, 1)
        XCTAssertEqual(MemoryLayout<SystemColorDefinitionType>.size, 16)
        XCTAssertEqual(
            [
                _ShapeStyle_Substrate.caLayer,
                .graphicsContext,
                .archive,
            ].map {
                withUnsafeBytes(of: $0) { $0[0] }
            },
            [0, 1, 2]
        )
        let systemColorTypes: [SystemColorType] = [
            .red,
            .orange,
            .yellow,
            .green,
            .teal,
            .mint,
            .cyan,
            .blue,
            .indigo,
            .purple,
            .pink,
            .brown,
            .gray,
            .primary,
            .secondary,
            .tertiary,
            .quaternary,
            .quinary,
            .primaryFill,
            .secondaryFill,
            .tertiaryFill,
            .quaternaryFill,
        ]
        XCTAssertEqual(
            systemColorTypes.map {
                withUnsafeBytes(of: $0) { $0[0] }
            },
            Array(UInt8(0)...UInt8(21))
        )
        let systemColorType: Any.Type = SystemColorType.self
        XCTAssertTrue(systemColorType is any Encodable.Type)
        XCTAssertTrue(systemColorType is any Decodable.Type)
        XCTAssertTrue(systemColorType is any Hashable.Type)
        XCTAssertFalse(systemColorType is any RawRepresentable.Type)
        XCTAssertFalse(systemColorType is any CaseIterable.Type)
        let systemColorDefinitionType: Any.Type =
            SystemColorDefinitionType.self
        XCTAssertTrue(systemColorDefinitionType is any Equatable.Type)
        XCTAssertFalse(systemColorDefinitionType is any Hashable.Type)
        XCTAssertEqual(
            SystemColorDefinitionType(
                base: DividerSystemColorDefinition.self
            ),
            SystemColorDefinitionType(
                base: DividerSystemColorDefinition.self
            )
        )
        assertPrimitiveShapeStyle(SystemColorsStyle())
        assertPrimitiveShapeStyle(Color.Resolved(
            colorSpace: .sRGB,
            red: 1,
            green: 0,
            blue: 0
        ))
        assertPrimitiveShapeStyle(Color.ResolvedHDR(Color.Resolved(
            colorSpace: .sRGB,
            red: 1,
            green: 0,
            blue: 0
        )))

        withGraph { graph in
            let view = graph.makeInput(value: ResolvedDivider(
                configuration: DividerStyleConfiguration(
                    orientation: .horizontal
                )
            ))
            let modifier = graph.makeInput(value: DividerStyleModifier(
                style: PlainDividerStyle()
            ))
            let accessor = StyleBodyAccessor<
                ResolvedDivider,
                DividerStyleModifier<PlainDividerStyle>
            >(
                _view: view,
                _styleModifier: modifier
            )
            XCTAssertEqual(
                labels(of: accessor),
                ["_view", "_styleModifier"]
            )
        }
    }

    func testShapeTypeModifiesBackgroundTransitions() {
        assertShapeTypeResult(Color.red, is: nil)
        assertShapeTypeResult(ForegroundStyle(), is: true)
        assertShapeTypeResult(BackgroundStyle(), is: true)
        assertShapeTypeResult(SeparatorShapeStyle(), is: true)
        assertShapeTypeResult(HierarchicalShapeStyle.primary, is: true)
        assertShapeTypeResult(
            _OpacityShapeStyle(style: Color.red, opacity: 0.5),
            is: nil
        )
        assertShapeTypeResult(Color.red.secondary, is: true)
    }

    func testDividerShapeForwardsOnlyWrappedShapeContracts() {
        var shape = DividerShape(DividerShapeProbe(value: 2))
        let rect = CGRect(x: 0, y: 0, width: 40, height: 30)
        let proposal = ProposedViewSize(width: 17, height: nil)

        XCTAssertEqual(
            DividerShape<DividerShapeProbe>.role,
            .separator
        )
        XCTAssertEqual(shape.layoutDirectionBehavior, .fixed)
        XCTAssertEqual(
            shape.path(in: rect),
            DividerShapeProbe(value: 2).path(in: rect)
        )
        XCTAssertEqual(
            shape.sizeThatFits(proposal),
            proposal.replacingUnspecifiedDimensions()
        )
        XCTAssertNotEqual(
            shape.sizeThatFits(proposal),
            shape.base.sizeThatFits(proposal)
        )
        XCTAssertEqual(shape.animatableData, 2)
        shape.animatableData = 4
        XCTAssertEqual(shape.base.value, 4)
    }

    func testLayoutDirectionBehaviorDefaultsAndRectangleOverride() {
        XCTAssertEqual(
            LayoutDirectionBehavior.mirrors,
            .mirrors(in: .rightToLeft)
        )
        XCTAssertNotEqual(
            LayoutDirectionBehavior.mirrors(in: .leftToRight),
            .mirrors
        )
        XCTAssertEqual(
            DividerShapeProbe(value: 0).layoutDirectionBehavior,
            .fixed
        )
        XCTAssertEqual(Rectangle().layoutDirectionBehavior, .fixed)
        XCTAssertEqual(MemoryLayout<LayoutDirectionBehavior>.size, 1)
    }

    func testDefaultDividerBodyReentersWithPlainStyle() {
        let body = DefaultDividerStyle().makeBody(
            configuration: DividerStyleConfiguration(
                orientation: .horizontal
            )
        )
        XCTAssertEqual(
            String(reflecting: type(of: body)),
            "VUI.ModifiedContent<VUI.Divider, " +
                "VUI.DividerStyleModifier<VUI.PlainDividerStyle>>"
        )
        XCTAssertEqual(
            ObjectIdentifier(type(of: ResolvedDivider.defaultStyleModifier)),
            ObjectIdentifier(
                DividerStyleModifier<DefaultDividerStyle>.self
            )
        )
    }

    func testDividerChildTracksDynamicStackOrientation() {
        withGraph { graph in
            let orientation = graph.makeInput(
                value: Optional<Axis>(.horizontal)
            )
            let child = graph.makeRule(Divider.Child(
                stackOrientation: nil,
                dynamicStackOrientation: OptionalAttribute(orientation)
            ))

            XCTAssertEqual(child.value.configuration.orientation, .vertical)
            orientation.setValue(Optional<Axis>(.vertical))
            XCTAssertEqual(child.value.configuration.orientation, .horizontal)
            orientation.setValue(nil)
            XCTAssertEqual(child.value.configuration.orientation, .horizontal)
        }
    }

    func testPlainDividerUsesEnvironmentThicknessOnCrossAxis() {
        withGraph { graph in
            let proposal = _ProposedSize(width: 80, height: 40)
            let direct = PlainDividerStyle().makeBody(
                configuration: DividerStyleConfiguration(
                    orientation: .vertical
                )
            )
            XCTAssertNotNil(makeLayout(
                direct,
                graph: graph,
                stackOrientation: .horizontal,
                thickness: 3
            ))
            XCTAssertNotNil(makeLayout(
                ResolvedDivider(
                    configuration: DividerStyleConfiguration(
                        orientation: .vertical
                    )
                ),
                graph: graph,
                stackOrientation: .horizontal,
                thickness: 3
            ))
            guard let horizontal = makeDividerLayout(
                graph: graph,
                stackOrientation: .horizontal,
                thickness: 3
            ) else {
                return XCTFail("missing horizontal Divider layout")
            }
            XCTAssertEqual(
                horizontal.sizeThatFits(proposal),
                CGSize(width: 3, height: 40)
            )

            guard let vertical = makeDividerLayout(
                graph: graph,
                stackOrientation: .vertical,
                thickness: 3
            ) else {
                return XCTFail("missing vertical Divider layout")
            }
            XCTAssertEqual(
                vertical.sizeThatFits(proposal),
                CGSize(width: 80, height: 3)
            )

            guard let neutral = makeDividerLayout(
                graph: graph,
                stackOrientation: nil,
                thickness: 3
            ) else {
                return XCTFail("missing neutral Divider layout")
            }
            XCTAssertEqual(
                neutral.sizeThatFits(proposal),
                CGSize(width: 80, height: 3)
            )
        }
    }

    func testPlainDividerThicknessEnvironmentInvalidatesStyleBody() {
        withGraph { graph in
            var environment = EnvironmentValues()
            environment.dividerThickness = 2
            let environmentAttribute = graph.makeInput(value: environment)
            guard let layout = makeLayoutAttribute(
                Divider(),
                graph: graph,
                stackOrientation: .horizontal,
                environment: environmentAttribute
            ) else {
                return XCTFail("missing Divider layout attribute")
            }
            let proposal = _ProposedSize(width: 80, height: 40)
            XCTAssertEqual(
                layout.value.sizeThatFits(proposal),
                CGSize(width: 2, height: 40)
            )

            environment.dividerThickness = 5
            environmentAttribute.setValue(environment)
            XCTAssertEqual(
                layout.value.sizeThatFits(proposal),
                CGSize(width: 5, height: 40)
            )
        }
    }

    // ASSERTIONS dividerSeparatorRenderingObserved
    func testSeparatorUsesObservedSystemHierarchyPalettes() {
        let expected: [
            (
                ColorScheme,
                ColorSchemeContrast,
                [Int]
            )
        ] = [
            (.light, .standard, [216, 127, 66, 25, 12]),
            (.dark, .standard, [216, 140, 63, 25, 12]),
            (.light, .increased, [255, 193, 142, 89, 38]),
            (.dark, .increased, [255, 178, 127, 76, 38]),
        ]
        let styles = [
            HierarchicalShapeStyle.primary,
            .secondary,
            .tertiary,
            .quaternary,
            .quinary,
        ]

        for (scheme, contrast, alphas) in expected {
            let environment = environment(
                scheme: scheme,
                contrast: contrast
            )
            for (index, style) in styles.enumerated() {
                let resolved = resolvedColor(
                    style,
                    environment: environment
                )
                let component: Float = scheme == .light ? 0 : 1
                XCTAssertEqual(resolved.red, component, accuracy: 0.000_001)
                XCTAssertEqual(resolved.green, component, accuracy: 0.000_001)
                XCTAssertEqual(resolved.blue, component, accuracy: 0.000_001)
                XCTAssertEqual(
                    resolved.opacity,
                    Float(alphas[index]) / 255,
                    accuracy: 0.000_001
                )
            }

            let separator = resolvedColor(
                SeparatorShapeStyle(),
                environment: environment
            )
            let quaternary = resolvedColor(
                HierarchicalShapeStyle.quaternary,
                environment: environment
            )
            assertEqual(separator, quaternary)
        }
    }

    func testExplicitForegroundHierarchyUsesObservedFallbackAndClamping() {
        var primaryOnly = environment(scheme: .light)
        primaryOnly.foregroundStyleLevels = _ForegroundStyleLevels(
            primary: AnyShapeStyle(Color.red)
        )
        let hierarchy = [
            HierarchicalShapeStyle.primary,
            .secondary,
            .tertiary,
            .quaternary,
            .quinary,
        ]
        let expectedOpacity: [Float] = [1, 0.5, 0.25, 0.18, 0.18]
        let red = Color.red.resolve(in: primaryOnly)
        for (index, style) in hierarchy.enumerated() {
            var expected = red
            expected.opacity *= expectedOpacity[index]
            assertEqual(
                resolvedColor(style, environment: primaryOnly),
                expected
            )
        }

        var twoLevels = environment(scheme: .light)
        twoLevels.foregroundStyleLevels = _ForegroundStyleLevels(
            primary: AnyShapeStyle(Color.red),
            secondary: AnyShapeStyle(Color.green)
        )
        assertEqual(
            resolvedColor(.primary, environment: twoLevels),
            Color.red.resolve(in: twoLevels)
        )
        for style in hierarchy.dropFirst() {
            assertEqual(
                resolvedColor(style, environment: twoLevels),
                Color.green.resolve(in: twoLevels)
            )
        }

        var threeLevels = twoLevels
        threeLevels.foregroundStyleLevels = _ForegroundStyleLevels(
            primary: AnyShapeStyle(Color.red),
            secondary: AnyShapeStyle(Color.green),
            tertiary: AnyShapeStyle(Color.blue)
        )
        assertEqual(
            resolvedColor(.secondary, environment: threeLevels),
            Color.green.resolve(in: threeLevels)
        )
        for style in hierarchy.dropFirst(2) {
            assertEqual(
                resolvedColor(style, environment: threeLevels),
                Color.blue.resolve(in: threeLevels)
            )
        }
    }

    func testSystemColorDefinitionDrivesColorAndFallbackOpacity() {
        var environment = environment(scheme: .light)
        environment.systemColorDefinition = SystemColorDefinitionType(
            base: DividerSystemColorDefinition.self
        )

        let primary = Color.primary.resolve(in: environment)
        XCTAssertEqual(primary.red, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(primary.green, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(primary.blue, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(primary.opacity, 0.8, accuracy: 0.000_001)

        var shape = _ShapeStyle_Shape(
            operation: .fallbackColor(level: 1),
            environment: environment
        )
        Color.red._apply(to: &shape)
        guard case let .color(color) = shape.result else {
            return XCTFail("expected color result")
        }
        XCTAssertEqual(
            color.resolve(in: environment).opacity,
            0.8 * 0.75,
            accuracy: 0.000_001
        )
    }

    func testObservedSystemFillColorsAndResolvedColorNames() {
        let expectations: [
            (
                SystemColorType,
                ColorScheme,
                ColorSchemeContrast,
                Float,
                Float
            )
        ] = [
            (.primaryFill, .light, .standard, 120 / 255, 0.20),
            (.primaryFill, .dark, .increased, 120 / 255, 0.44),
            (.secondaryFill, .light, .standard, 120 / 255, 0.16),
            (.secondaryFill, .dark, .increased, 120 / 255, 0.40),
            (.tertiaryFill, .light, .standard, 120 / 255, 0.12),
            (.tertiaryFill, .dark, .increased, 118 / 255, 0.32),
            (.quaternaryFill, .light, .standard, 116 / 255, 0.08),
            (.quaternaryFill, .dark, .increased, 116 / 255, 0.26),
        ]
        for (type, scheme, contrast, component, opacity) in expectations {
            let resolved = type.resolve(in: environment(
                scheme: scheme,
                contrast: contrast
            ))
            XCTAssertEqual(resolved.red, component, accuracy: 0.000_001)
            XCTAssertEqual(resolved.green, component, accuracy: 0.000_001)
            XCTAssertEqual(resolved.blue, 128 / 255, accuracy: 0.000_001)
            XCTAssertEqual(resolved.opacity, opacity, accuracy: 0.000_001)
        }

        XCTAssertEqual(Color.white.description, "white")
        XCTAssertEqual(Color.black.description, "black")
        XCTAssertEqual(Color.clear.description, "clear")
    }

    func testSeparatorRoleAndHierarchyModifiersUseOperationLevel() {
        var environment = environment(scheme: .light)
        environment.foregroundStyleLevels = _ForegroundStyleLevels(
            primary: AnyShapeStyle(Color.red)
        )
        let separator = resolvedColor(
            SeparatorShapeStyle(),
            environment: environment
        )
        var expectedSeparator = Color.red.resolve(in: environment)
        expectedSeparator.opacity *= 0.18
        assertEqual(separator, expectedSeparator)

        assertEqual(
            resolvedColor(
                HierarchicalShapeStyle.primary,
                environment: environment,
                role: .separator
            ),
            expectedSeparator
        )

        var expectedSecondary = Color.red.resolve(in: environment)
        expectedSecondary.opacity *= 0.5
        assertEqual(
            resolvedColor(Color.red.secondary, environment: environment),
            expectedSecondary
        )
        var expectedQuinary = Color.red.resolve(in: environment)
        expectedQuinary.opacity *= 0.18
        assertEqual(
            resolvedColor(Color.red.quinary, environment: environment),
            expectedQuinary
        )
    }

    func testOffsetStyleTranslatesOperationAndPackNamespaces() {
        let environment = environment(scheme: .light)
        var fallback = _ShapeStyle_Shape(
            operation: .fallbackColor(level: 1),
            environment: environment
        )
        OffsetShapeStyle(base: Color.red, offset: 2)._apply(to: &fallback)
        guard case let .fallbackColor(level) = fallback.operation else {
            return XCTFail("expected shifted fallback operation")
        }
        XCTAssertEqual(level, 3)
        guard case let .color(fallbackColor) = fallback.result else {
            return XCTFail("expected fallback color")
        }
        XCTAssertEqual(
            fallbackColor.resolve(in: environment).opacity,
            0.18,
            accuracy: 0.000_001
        )

        var resolve = _ShapeStyle_Shape(
            operation: .resolveStyle(
                name: .foreground,
                levels: 0..<2
            ),
            environment: environment
        )
        OffsetShapeStyle(
            base: DividerOffsetOperationStyle(),
            offset: 2
        )._apply(to: &resolve)
        guard case let .resolveStyle(_, shiftedLevels) = resolve.operation else {
            return XCTFail("expected shifted resolve operation")
        }
        XCTAssertEqual(shiftedLevels, 2..<4)
        guard case let .pack(pack) = resolve.result else {
            return XCTFail("expected adjusted style pack")
        }
        XCTAssertEqual(pack.styles.map(\.key._level), [0, 1])

        var copy = _ShapeStyle_Shape(
            operation: .copyStyle(name: .foreground),
            environment: environment
        )
        OffsetShapeStyle(
            base: DividerOffsetOperationStyle(),
            offset: 2
        )._apply(to: &copy)
        guard case let .style(copied) = copy.result else {
            return XCTFail("expected copied style")
        }
        var copiedResolution = _ShapeStyle_Shape(
            operation: .fallbackColor(level: 0),
            environment: environment
        )
        copied._apply(to: &copiedResolution)
        guard case let .color(copiedColor) = copiedResolution.result else {
            return XCTFail("expected copied style color")
        }
        XCTAssertEqual(
            copiedColor.resolve(in: environment).opacity,
            0.25,
            accuracy: 0.000_001
        )
    }

    private func labels<T>(of value: T) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label)
    }

    private func assertPrimitiveShapeStyle<S: PrimitiveShapeStyle>(
        _ style: S
    ) {
    }

    private func assertShapeTypeResult<S: ShapeStyle>(
        _ style: S,
        is expected: Bool?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var type = _ShapeStyle_ShapeType()
        S._apply(to: &type)
        switch (type.result, expected) {
        case let (.bool(value), expected?):
            XCTAssertEqual(value, expected, file: file, line: line)
        case (.none, nil):
            break
        default:
            XCTFail(
                "unexpected shape-type result \(type.result)",
                file: file,
                line: line
            )
        }
    }

    private func resolvedColor<S: ShapeStyle>(
        _ style: S,
        environment: EnvironmentValues,
        role: ShapeRole = .fill,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Color.Resolved {
        var shape = _ShapeStyle_Shape(
            operation: .fallbackColor(level: 0),
            environment: environment,
            role: role
        )
        style._apply(to: &shape)
        guard case let .color(color) = shape.result else {
            XCTFail(
                "expected color result, got \(shape.result)",
                file: file,
                line: line
            )
            return Color.clear.resolve(in: environment)
        }
        return color.resolve(in: environment)
    }

    private func assertEqual(
        _ lhs: Color.Resolved,
        _ rhs: Color.Resolved,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.red, rhs.red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(lhs.green, rhs.green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(lhs.blue, rhs.blue, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(
            lhs.opacity,
            rhs.opacity,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
    }

    private func environment(
        scheme: ColorScheme,
        contrast: ColorSchemeContrast = .standard
    ) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        environment._colorSchemeContrast = contrast
        return environment
    }

    private func withGraph(_ body: (_AGGraph) -> Void) {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        context.withCurrent {
            body(graph)
        }
    }

    private func makeDividerLayout(
        graph: _AGGraph,
        stackOrientation: Axis?,
        thickness: CGFloat
    ) -> LayoutComputer? {
        makeLayout(
            Divider(),
            graph: graph,
            stackOrientation: stackOrientation,
            thickness: thickness
        )
    }

    private func makeLayout<V: View>(
        _ view: V,
        graph: _AGGraph,
        stackOrientation: Axis?,
        thickness: CGFloat
    ) -> LayoutComputer? {
        var environment = EnvironmentValues()
        environment.dividerThickness = thickness
        return makeLayoutAttribute(
            view,
            graph: graph,
            stackOrientation: stackOrientation,
            environment: graph.makeInput(value: environment)
        )?.value
    }

    private func makeLayoutAttribute<V: View>(
        _ view: V,
        graph: _AGGraph,
        stackOrientation: Axis?,
        environment: Attribute<EnvironmentValues>
    ) -> Attribute<LayoutComputer>? {
        var inputs = _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: Phase()),
                environment: environment,
                transaction: graph.makeInput(value: Transaction())
            ),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: stackOrientation
        )
        inputs.requestsLayoutComputer = true
        let view = graph.makeInput(value: view)
        let outputs = V._makeView(
            view: _GraphValue(_attribute: view),
            inputs: inputs
        )
        return outputs._layoutComputer.attribute
    }
}
