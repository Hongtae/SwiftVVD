import XCTest
@testable import VUI

final class SymbolEffectsTests: XCTestCase {
    func testObservedConfigurationFactoriesAndFluentMembers() {
        XCTAssertEqual(PulseSymbolEffect.pulse.isLayered, nil)
        XCTAssertEqual(PulseSymbolEffect.pulse.byLayer.isLayered, true)
        XCTAssertEqual(PulseSymbolEffect.pulse.wholeSymbol.isLayered, false)

        XCTAssertEqual(BounceSymbolEffect.bounce.up.isUp, true)
        XCTAssertEqual(BounceSymbolEffect.bounce.down.isUp, false)
        XCTAssertEqual(BounceSymbolEffect.bounce.byLayer.isLayered, true)
        XCTAssertEqual(BounceSymbolEffect.bounce.wholeSymbol.isLayered, false)

        XCTAssertEqual(VariableColorSymbolEffect.variableColor.reversing.isReversing, true)
        XCTAssertEqual(VariableColorSymbolEffect.variableColor.nonReversing.isReversing, false)
        XCTAssertEqual(VariableColorSymbolEffect.variableColor.cumulative.isIterative, false)
        XCTAssertEqual(VariableColorSymbolEffect.variableColor.iterative.isIterative, true)
        XCTAssertEqual(VariableColorSymbolEffect.variableColor.hideInactiveLayers.hasReveal, true)
        XCTAssertEqual(VariableColorSymbolEffect.variableColor.dimInactiveLayers.hasReveal, false)

        XCTAssertEqual(ScaleSymbolEffect.scale.up.isUp, true)
        XCTAssertEqual(AppearSymbolEffect.appear.down.isUp, false)
        XCTAssertEqual(DisappearSymbolEffect.disappear.wholeSymbol.isLayered, false)
        XCTAssertEqual(ReplaceSymbolEffect.replace.offUp.style, .offUp)
        XCTAssertEqual(ReplaceSymbolEffect.downUp.style, .downUp)
        XCTAssertEqual(
            ReplaceSymbolEffect.replace.magic(fallback: .upUp)._backing.fallback.style,
            .upUp
        )

        XCTAssertEqual(WiggleSymbolEffect.wiggle.clockwise.style, .rotational(true))
        XCTAssertEqual(WiggleSymbolEffect.wiggle.counterClockwise.style, .rotational(false))
        XCTAssertEqual(WiggleSymbolEffect.wiggle.left.style, .linear(180))
        XCTAssertEqual(WiggleSymbolEffect.wiggle.right.style, .linear(0))
        XCTAssertEqual(WiggleSymbolEffect.wiggle.up.style, .linear(-90))
        XCTAssertEqual(WiggleSymbolEffect.wiggle.down.style, .linear(90))
        XCTAssertEqual(WiggleSymbolEffect.wiggle.forward.style, .localized(true))
        XCTAssertEqual(WiggleSymbolEffect.wiggle.backward.style, .localized(false))
        XCTAssertEqual(WiggleSymbolEffect.wiggle.custom(angle: .degrees(42)).style, .linear(42))

        XCTAssertEqual(RotateSymbolEffect.rotate.clockwise.isClockwise, true)
        XCTAssertEqual(RotateSymbolEffect.rotate.counterClockwise.isClockwise, false)
        XCTAssertEqual(BreatheSymbolEffect.breathe.pulse.style, .dim)
        XCTAssertEqual(BreatheSymbolEffect.breathe.plain.style, .scale)
        XCTAssertEqual(DrawOnSymbolEffect.drawOn.individually.layerBehavior, .individually)
        XCTAssertEqual(DrawOffSymbolEffect.drawOff.reversed.isReversed, true)
        XCTAssertEqual(DrawOffSymbolEffect.drawOff.nonReversed.isReversed, false)

        // ASSERTIONS symbolEffectConfigurationRuntimeObserved
    }

    func testObservedOptionsPreserveUnclampedValuesAndRepeatBehavior() {
        XCTAssertEqual(SymbolEffectOptions.default.speed, 1)
        XCTAssertNil(SymbolEffectOptions.default.repeat)
        XCTAssertFalse(SymbolEffectOptions.default.prefersContinuous)
        XCTAssertNil(SymbolEffectOptions.default.repeatDelay)

        let periodic = VUI.SymbolEffectOptions.speed(-2).repeat(
            VUI.SymbolEffectOptions.RepeatBehavior.periodic(-3, delay: -0.5)
        )
        XCTAssertEqual(periodic.speed, -2)
        XCTAssertEqual(periodic.repeat, VUI.SymbolEffectOptions.RepeatOption.count(-3))
        XCTAssertFalse(periodic.prefersContinuous)
        XCTAssertEqual(periodic.repeatDelay, -0.5)

        let continuous = VUI.SymbolEffectOptions.repeat(
            VUI.SymbolEffectOptions.RepeatBehavior.continuous
        )
        XCTAssertEqual(continuous.repeat, VUI.SymbolEffectOptions.RepeatOption.indefinite)
        XCTAssertTrue(continuous.prefersContinuous)
        XCTAssertNil(continuous.repeatDelay)
        XCTAssertEqual(
            VUI.SymbolEffectOptions.nonRepeating.repeat,
            VUI.SymbolEffectOptions.RepeatOption.count(1)
        )

        // ASSERTIONS symbolEffectPublicSurfaceObserved
    }

    func testGraphInputModifiersPublishObservedEffectKindsAndTriggers() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var indefiniteInputs = makeGraphInputs(graph: graph)
            let indefinite = graph.makeInput(
                value: _IndefiniteSymbolEffectModifier(
                    effect: PulseSymbolEffect.pulse.byLayer,
                    options: .speed(2),
                    isActive: true
                )
            )
            _IndefiniteSymbolEffectModifier._makeInputs(
                modifier: _GraphValue(_attribute: indefinite),
                inputs: &indefiniteInputs
            )
            let indefiniteEffects = indefiniteInputs.cachedEnvironment.value.environment.value.symbolEffects
            XCTAssertEqual(indefiniteEffects.count, 1)
            XCTAssertEqual(indefiniteEffects[0].effect.options.speed, 2)
            if case let .pulse(configuration) = indefiniteEffects[0].effect.configuration.effect {
                XCTAssertEqual(configuration.isLayered, true)
            } else {
                XCTFail("expected pulse configuration")
            }
            if case .indefinite = indefiniteEffects[0].effect.trigger {
            } else {
                XCTFail("expected indefinite trigger")
            }

            var inactiveInputs = makeGraphInputs(graph: graph)
            let inactive = graph.makeInput(
                value: _IndefiniteSymbolEffectModifier(
                    effect: PulseSymbolEffect.pulse,
                    options: .default,
                    isActive: false
                )
            )
            _IndefiniteSymbolEffectModifier._makeInputs(
                modifier: _GraphValue(_attribute: inactive),
                inputs: &inactiveInputs
            )
            XCTAssertTrue(inactiveInputs.cachedEnvironment.value.environment.value.symbolEffects.isEmpty)

            var discreteInputs = makeGraphInputs(graph: graph)
            let discrete = graph.makeInput(
                value: _DiscreteSymbolEffectModifier(
                    effect: BounceSymbolEffect.bounce.up,
                    options: VUI.SymbolEffectOptions.repeat(
                        VUI.SymbolEffectOptions.RepeatBehavior.periodic(2)
                    ),
                    value: 7
                )
            )
            _DiscreteSymbolEffectModifier<Int>._makeInputs(
                modifier: _GraphValue(_attribute: discrete),
                inputs: &discreteInputs
            )
            let discreteEffects = discreteInputs.cachedEnvironment.value.environment.value.symbolEffects
            XCTAssertEqual(discreteEffects.count, 1)
            if case let .value(trigger) = discreteEffects[0].effect.trigger {
                XCTAssertTrue(trigger.isEqual(to: AnySymbolEffectTrigger(7)))
                XCTAssertFalse(trigger.isEqual(to: AnySymbolEffectTrigger(8)))
            } else {
                XCTFail("expected value trigger")
            }

            // ASSERTIONS symbolEffectGraphDisassemblyObserved
        }
    }

    func testRemovedModifierClearsExistingEffectEnvironmentWhenEnabled() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var values = EnvironmentValues()
            values.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: PulseSymbolEffect.pulse.configuration,
                    options: .default,
                    trigger: .indefinite
                ),
                for: 1
            )
            var inputs = makeGraphInputs(graph: graph, environment: values)
            let modifier = graph.makeInput(value: _SymbolEffectsRemovedModifier(isEnabled: true))
            _SymbolEffectsRemovedModifier._makeInputs(
                modifier: _GraphValue(_attribute: modifier),
                inputs: &inputs
            )
            XCTAssertTrue(inputs.cachedEnvironment.value.environment.value.symbolEffects.isEmpty)
        }
    }

    func testSymbolContentAndViewTransitionsRetainConfiguration() {
        let content = ContentTransition.symbolEffect(
            ReplaceSymbolEffect.replace.offUp,
            options: .speed(1.5)
        )
        XCTAssertEqual(
            content,
            .symbolEffect(ReplaceSymbolEffect.replace.offUp, options: .speed(1.5))
        )
        XCTAssertNotEqual(content, .symbolEffect)

        let transition = SymbolEffectTransition(
            effect: AppearSymbolEffect.appear.down,
            options: .speed(2)
        )
        if case let .appear(configuration) = transition.config.effect {
            XCTAssertEqual(configuration.isUp, false)
        } else {
            XCTFail("expected appear configuration")
        }
        XCTAssertEqual(transition.options.speed, 2)
    }

    private func makeGraphInputs(
        graph: _AGGraph,
        environment values: EnvironmentValues = EnvironmentValues()
    ) -> _GraphInputs {
        _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time(seconds: 0)),
            cachedEnvironment: MutableBox(
                CachedEnvironment(environment: graph.makeInput(value: values))
            ),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
    }
}
