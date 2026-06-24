import XCTest
@testable import VUI

final class AppearanceActionModifierTests: XCTestCase {
    func testAppearanceEffectQueuesAppearOnceUntilPhaseChanges() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var events: [String] = []
            let modifier = graph.makeInput(
                value: _AppearanceActionModifier(
                    appear: { events.append("appear") },
                    disappear: { events.append("disappear") }
                )
            )
            let phase = graph.makeInput(value: Phase())
            let effect = graph.makeStatefulRule(
                AppearanceEffect(modifier: modifier, phase: phase)
            )

            graph.makeSideEffectRule {
                _ = effect.value
                return ()
            }

            XCTAssertEqual(events, ["appear"])

            _ = effect.value
            XCTAssertEqual(events, ["appear"])

            var nextPhase = phase.value
            nextPhase.resetSeed = 1
            phase.setValue(nextPhase)

            XCTAssertEqual(events, ["appear", "disappear", "appear"])
        }
    }

    func testAppearanceEffectUsesLatestCallbacksAfterModifierChange() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var events: [String] = []
            let modifier = graph.makeInput(
                value: _AppearanceActionModifier(
                    appear: { events.append("first-appear") },
                    disappear: { events.append("first-disappear") }
                )
            )
            let phase = graph.makeInput(value: Phase())
            let effect = graph.makeStatefulRule(
                AppearanceEffect(modifier: modifier, phase: phase)
            )

            graph.makeSideEffectRule {
                _ = effect.value
                return ()
            }

            XCTAssertEqual(events, ["first-appear"])

            modifier.setValue(
                _AppearanceActionModifier(
                    appear: { events.append("second-appear") },
                    disappear: { events.append("second-disappear") }
                )
            )

            XCTAssertEqual(events, ["first-appear"])

            var nextPhase = phase.value
            nextPhase.resetSeed = 1
            phase.setValue(nextPhase)

            XCTAssertEqual(events, ["first-appear", "second-disappear", "second-appear"])
        }
    }

    func testOnDisappearOnlyModifierQueuesDisappearAfterPhaseChange() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var events: [String] = []
            let modifier = graph.makeInput(
                value: _AppearanceActionModifier(
                    appear: nil,
                    disappear: { events.append("disappear") }
                )
            )
            let phase = graph.makeInput(value: Phase())
            let effect = graph.makeStatefulRule(
                AppearanceEffect(modifier: modifier, phase: phase)
            )

            graph.makeSideEffectRule {
                _ = effect.value
                return ()
            }

            XCTAssertEqual(events, [])

            var nextPhase = phase.value
            nextPhase.resetSeed = 1
            phase.setValue(nextPhase)

            XCTAssertEqual(events, ["disappear"])
        }
    }
}
