import XCTest
@testable import VUI

final class ValueActionModifierTests: XCTestCase {
    // ASSERTIONS: modernOnChangeValueActionObserved
    func testModernOnChangeStorageComposesValueAndAppearanceModifiers() throws {
        let initialFalse = EmptyView().onChange(of: 7, initial: false) { _, _ in }
        let initialTrue = EmptyView().onChange(of: 7, initial: true) { _, _ in }

        let falseMirror = Mirror(reflecting: initialFalse)
        let trueMirror = Mirror(reflecting: initialTrue)
        let falseChildren = Array(falseMirror.children)
        let trueChildren = Array(trueMirror.children)
        XCTAssertEqual(falseChildren.map(\.label), ["content", "modifier"])
        XCTAssertEqual(trueChildren.map(\.label), ["content", "modifier"])

        let falseAppearance = try XCTUnwrap(falseChildren.last?.value)
        let trueAppearance = try XCTUnwrap(trueChildren.last?.value)
        XCTAssertEqual(Mirror(reflecting: falseAppearance).children.map(\.label), [
            "appear",
            "disappear",
        ])
        XCTAssertEqual(Mirror(reflecting: trueAppearance).children.map(\.label), [
            "appear",
            "disappear",
        ])

        let falseAppear = try XCTUnwrap(
            Mirror(reflecting: falseAppearance).children.first?.value
        )
        let trueAppear = try XCTUnwrap(
            Mirror(reflecting: trueAppearance).children.first?.value
        )
        XCTAssertTrue(Mirror(reflecting: falseAppear).children.isEmpty)
        XCTAssertEqual(Mirror(reflecting: trueAppear).children.count, 1)

        let falseContent = try XCTUnwrap(falseChildren.first?.value)
        let falseContentChildren = Array(Mirror(reflecting: falseContent).children)
        let valueModifier = try XCTUnwrap(
            falseContentChildren.last?.value
        )
        XCTAssertEqual(Mirror(reflecting: valueModifier).children.map(\.label), [
            "value",
            "action",
        ])
    }

    func testDispatcherQueuesChangedOldAndNewValuesAfterEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var events: [(Int, Int)] = []
            let modifier = graph.makeInput(
                value: _ValueActionModifier2(value: 1) {
                    events.append(($0, $1))
                }
            )
            let phase = graph.makeInput(value: _GraphInputs.Phase())
            let dispatcher = graph.makeStatefulRule(
                ValueActionDispatcher(modifier: modifier, phase: phase)
            )
            dispatcher.flags = [.transactional]

            _ = dispatcher.value
            XCTAssertEqual(events.count, 0)

            modifier.setValue(_ValueActionModifier2(value: 2) {
                events.append(($0, $1))
            })
            Update.begin()
            _ = dispatcher.value
            XCTAssertEqual(Update.queuedActionReasons, [.onChange])
            XCTAssertEqual(events.count, 0)
            Update.end()
            XCTAssertEqual(events.map { [$0.0, $0.1] }, [[1, 2]])

            modifier.setValue(_ValueActionModifier2(value: 2) {
                events.append(($0, $1))
            })
            _ = dispatcher.value
            XCTAssertEqual(events.map { [$0.0, $0.1] }, [[1, 2]])
        }
    }

    func testDispatcherRebasesWithoutActionWhenPhaseResetSeedChanges() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var events: [(Int, Int)] = []
            let modifier = graph.makeInput(
                value: _ValueActionModifier2(value: 1) {
                    events.append(($0, $1))
                }
            )
            let phase = graph.makeInput(value: _GraphInputs.Phase())
            let dispatcher = graph.makeStatefulRule(
                ValueActionDispatcher(modifier: modifier, phase: phase)
            )

            _ = dispatcher.value
            modifier.setValue(_ValueActionModifier2(value: 3) {
                events.append(($0, $1))
            })
            var nextPhase = phase.value
            nextPhase.resetSeed = 1
            phase.setValue(nextPhase)
            _ = dispatcher.value
            XCTAssertEqual(events.count, 0)

            modifier.setValue(_ValueActionModifier2(value: 4) {
                events.append(($0, $1))
            })
            _ = dispatcher.value
            XCTAssertEqual(events.map { [$0.0, $0.1] }, [[3, 4]])
        }
    }
}
