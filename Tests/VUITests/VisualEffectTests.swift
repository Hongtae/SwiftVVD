import XCTest
@testable import VUI

private final class VisualEffectGeometryRecorder: @unchecked Sendable {
    var size = CGSize.zero
    var local = CGRect.zero
    var global = CGRect.zero
    var named = CGRect.zero
    var namedBounds: CGRect?
    var safeAreaInsets = EdgeInsets()
}

private struct VisualEffectDisplaySource: View, TestPrimitiveView {
    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("VisualEffectDisplaySource._makeView called outside an active _AGGraph context.")
        }
        let displayList = graph.makeRule {
            var list = DisplayList()
            list.appendCustomItem(
                bounds: CGRect(x: 0, y: 0, width: 20, height: 10),
                isOpaque: false,
                colorMode: .nonLinear,
                rendersAsynchronously: false
            ) { _ in }
            return list
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 20, height: 10))
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)
        return outputs
    }
}

final class VisualEffectTests: XCTestCase {
    // ASSERTIONS visualEffectPublicSurfaceObserved
    func testPublicEffectFactoriesUseObservedCarrierShapes() {
        let empty = EmptyVisualEffect()
        XCTAssertEqual(Mirror(reflecting: empty).children.count, 0)

        let offset = empty.offset(x: 3, y: 5)
        XCTAssertEqual(String(reflecting: type(of: offset)).contains("CombinedVisualEffect"), true)
        XCTAssertEqual(Mirror(reflecting: offset).children.map(\.label), ["first", "second"])

        let chained = offset.opacity(0.4).blur(radius: 2, opaque: true)
        XCTAssertEqual(Mirror(reflecting: chained).children.map(\.label), ["first", "second"])
        XCTAssertEqual(
            String(reflecting: type(of: chained.animatableData)).contains("AnimatablePair"),
            true
        )

        var nonAffine = ProjectionTransform()
        nonAffine.m13 = 0.25
        let transformed = empty.transformEffect(nonAffine)
        let geometry = try! XCTUnwrap(
            Mirror(reflecting: transformed).children.first { $0.label == "second" }
        ).value
        let base = try! XCTUnwrap(
            Mirror(reflecting: geometry).children.first { $0.label == "base" }
        ).value
        let affine = try! XCTUnwrap(
            Mirror(reflecting: base).children.first { $0.label == "transform" }
        ).value as! CGAffineTransform
        XCTAssertTrue(affine.isIdentity)
    }

    // ASSERTIONS visualEffectGeometryRuntimeObserved
    func testViewModifierSuppliesPreEffectGeometryAndAppliesEffectsInOrder() throws {
        let graph = _AGGraph()
        let recorder = VisualEffectGeometryRecorder()

        try _AGGraph.withCurrent(graph) {
            let view = VisualEffectDisplaySource().visualEffect { effect, proxy in
                recorder.size = proxy.size
                recorder.local = proxy.frame(in: .local)
                recorder.global = proxy.frame(in: .global)
                recorder.named = proxy.frame(in: .named("outer"))
                recorder.namedBounds = proxy.bounds(of: .named("outer"))
                recorder.safeAreaInsets = proxy.safeAreaInsets
                return effect
                    .offset(x: 6, y: 8)
                    .opacity(0.4)
                    .blur(radius: 2, opaque: true)
            }
            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let list = Attribute<DisplayList>(outputID).value

            XCTAssertEqual(recorder.size, CGSize(width: 80, height: 40))
            XCTAssertEqual(recorder.local, CGRect(x: 0, y: 0, width: 80, height: 40))
            XCTAssertEqual(recorder.global, CGRect(x: 80, y: 60, width: 80, height: 40))
            XCTAssertEqual(recorder.named, CGRect(x: 30, y: 20, width: 80, height: 40))
            XCTAssertEqual(
                recorder.namedBounds,
                CGRect(x: -30, y: -20, width: 200, height: 120)
            )
            XCTAssertEqual(recorder.safeAreaInsets, EdgeInsets())

            let blur = try XCTUnwrap(style(in: try XCTUnwrap(list.items.first)))
            guard case let .blur(radius, isOpaque) = blur.style else {
                return XCTFail("Expected blur as the outer visual effect")
            }
            XCTAssertEqual(radius, 2)
            XCTAssertTrue(isOpaque)

            let opacity = try XCTUnwrap(style(in: try XCTUnwrap(blur.contents.items.first)))
            guard case let .opacity(amount) = opacity.style else {
                return XCTFail("Expected opacity inside blur")
            }
            XCTAssertEqual(amount, 0.4, accuracy: 0.000_001)
            XCTAssertEqual(
                opacity.contents.interpolationBounds,
                CGRect(x: 6, y: 8, width: 20, height: 10)
            )
        }
    }

    private func style(
        in item: DisplayList.Item
    ) -> (style: DisplayList.Content.StyleValue.Style, contents: DisplayList)? {
        guard case let .content(content) = item.value,
              case let .style(value) = content.value else {
            return nil
        }
        return (value.style, value.contents)
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        var transform = ViewTransform()
        transform.appendPosition(CGPoint(x: 50, y: 40))
        transform.appendSizedSpace(name: AnyHashable("outer"), size: CGSize(width: 200, height: 120))

        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: Phase()),
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
            transform: graph.makeInput(value: transform),
            position: graph.makeInput(value: CGPoint(x: 80, y: 60)),
            containerPosition: graph.makeInput(value: CGPoint(x: 50, y: 40)),
            size: graph.makeInput(value: ViewSize(width: 80, height: 40)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
