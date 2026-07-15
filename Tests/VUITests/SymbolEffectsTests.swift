import XCTest
@testable import VUI

final class SymbolEffectsTests: XCTestCase {
    func testPortableSymbolCatalogLoadsVectorLayersAndDistinguishesVariants() throws {
        let outline = try XCTUnwrap(SymbolAssetCatalog.resolve(
            name: "star",
            variableValue: nil,
            bundle: nil
        ))
        let filled = try XCTUnwrap(SymbolAssetCatalog.resolve(
            name: "star.fill",
            variableValue: nil,
            bundle: nil
        ))

        XCTAssertEqual(outline.viewport, CGRect(x: 0, y: 0, width: 24, height: 24))
        XCTAssertEqual(filled.viewport, outline.viewport)
        XCTAssertEqual(outline.layers.count, 1)
        XCTAssertEqual(filled.layers.count, 1)
        XCTAssertFalse(outline.layers[0].path.isEmpty)
        XCTAssertFalse(filled.layers[0].path.isEmpty)
        XCTAssertNotEqual(outline.identity, filled.identity)

        let layered = try XCTUnwrap(SymbolAssetCatalog.resolve(
            name: "photo.fill",
            variableValue: nil,
            bundle: nil
        ))
        XCTAssertEqual(layered.layers.count, 2)
        XCTAssertEqual(layered.layers.map(\.semanticLevel), [1, 0])
        XCTAssertEqual(layered.layers.map(\.effectLevel), [1, 0])
        XCTAssertEqual(layered.layers.map(\.variableColorLevel), [1, 0])
        XCTAssertEqual(layered.variableColorLevelCount, 2)
        XCTAssertEqual(layered.layers.map(\.opacity), [0.3, 1])
        XCTAssertEqual(outline.layers.map(\.variableColorLevel), [nil])
        XCTAssertEqual(outline.variableColorLevelCount, 0)

        let drawable = try XCTUnwrap(SymbolAssetCatalog.resolve(
            name: "draw",
            variableValue: nil,
            bundle: nil
        ))
        XCTAssertEqual(drawable.layers.count, 2)
        XCTAssertEqual(drawable.drawMotionGroupCount, 2)
        XCTAssertEqual(
            drawable.layers.compactMap { $0.draw?.motionGroup },
            [0, 1]
        )
        XCTAssertEqual(drawable.drawMotionGroupDurations.count, 2)
        XCTAssertTrue(drawable.drawMotionGroupDurations.allSatisfy { $0 > 2.0 / 15.0 })
        let firstDraw = try XCTUnwrap(drawable.layers[0].draw)
        XCTAssertFalse(firstDraw.clipPath(progress: 0.5, reversed: false).isEmpty)
        XCTAssertNotEqual(
            firstDraw.clipPath(progress: 0.5, reversed: false),
            firstDraw.clipPath(progress: 0.5, reversed: true)
        )

        let draw = try XCTUnwrap(SymbolAssetCatalog.resolve(
            name: "draw",
            variableValue: nil,
            bundle: nil
        ))
        XCTAssertEqual(draw.layers.count, 2)
        XCTAssertEqual(draw.layers.compactMap { $0.draw?.motionGroup }, [0, 1])
        XCTAssertEqual(draw.drawMotionGroupCount, 2)
        XCTAssertEqual(draw.drawMotionGroupDurations.count, 2)
        XCTAssertTrue(draw.drawMotionGroupDurations.allSatisfy { $0 > 0 })
        XCTAssertTrue(draw.layers.allSatisfy { $0.draw?.guides.isEmpty == false })

        let sameProvider = SymbolImageProvider(
            name: "star",
            variableValue: nil,
            bundle: nil,
            label: nil
        )
        XCTAssertTrue(sameProvider.isEqual(to: SymbolImageProvider(
            name: "star",
            variableValue: nil,
            bundle: nil,
            label: nil
        )))
        XCTAssertFalse(sameProvider.isEqual(to: SymbolImageProvider(
            name: "star.fill",
            variableValue: nil,
            bundle: nil,
            label: nil
        )))
    }

    func testSVGPathParserSupportsCompactRelativeAndArcCommands() throws {
        var compact = SVGPathDataParser("M12 2 14 8l6 .5-4.5 4 1.5 6L12 15l-5 3 1.5-6L4 8.5 10 8z")
        let compactPath = try XCTUnwrap(compact.parse())
        XCTAssertFalse(compactPath.isEmpty)
        XCTAssertEqual(compactPath.initialPoint, CGPoint(x: 12, y: 2))

        var arc = SVGPathDataParser("M2 10 A8 8 0 0 1 18 10 A8 8 0 0 1 2 10 Z")
        let arcPath = try XCTUnwrap(arc.parse())
        XCTAssertFalse(arcPath.isEmpty)
        XCTAssertEqual(arcPath.currentPoint, CGPoint(x: 2, y: 10))
        XCTAssertGreaterThan(arcPath.boundingRect.width, 15.9)
        XCTAssertGreaterThan(arcPath.boundingRect.height, 15.9)
    }

    func testStatefulImageConsumerRetainsAndDiffsSymbolEffectPhase() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let symbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
                name: "star",
                variableValue: nil,
                bundle: nil
            ))
            let resolved = graph.makeInput(
                value: Optional(GraphicsContext.ResolvedImage(symbol: symbol))
            )
            var values = EnvironmentValues()
            values.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: BounceSymbolEffect.bounce.configuration,
                    options: .default,
                    trigger: .value(AnySymbolEffectTrigger(1))
                ),
                for: 7
            )
            let environment = graph.makeInput(value: values)
            let transaction = graph.makeInput(value: Transaction())
            let time = graph.makeInput(value: Time(seconds: 0))
            let child: Attribute<ImageViewChild.Value> = graph.makeStatefulRule(
                ImageViewChild(
                    resolvedImage: resolved,
                    environment: environment,
                    transaction: transaction,
                    time: time
                )
            )

            let first = child.value
            XCTAssertEqual(first.symbolEffects.count, 1)
            XCTAssertEqual(first.symbolEffectVersion, 1)

            var changedValues = EnvironmentValues()
            changedValues.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: BounceSymbolEffect.bounce.configuration,
                    options: .default,
                    trigger: .value(AnySymbolEffectTrigger(2))
                ),
                for: 7
            )
            environment.setValue(changedValues)
            let changed = child.value
            XCTAssertEqual(changed.symbolEffects.count, 1)
            XCTAssertEqual(changed.symbolEffectVersion, 2)

            resolved.setValue(nil)
            let cleared = child.value
            XCTAssertTrue(cleared.symbolEffects.isEmpty)
            XCTAssertEqual(cleared.symbolEffectVersion, 3)

            // ASSERTIONS symbolEffectImageConsumerDisassemblyObserved
        }
    }

    func testWholeSymbolPulseUsesObservedTwoSecondOpacityCycle() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let symbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
                name: "star.fill",
                variableValue: nil,
                bundle: nil
            ))
            let resolved = graph.makeInput(
                value: Optional(GraphicsContext.ResolvedImage(symbol: symbol))
            )
            var values = EnvironmentValues()
            values.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: PulseSymbolEffect.pulse.wholeSymbol.configuration,
                    options: .nonRepeating,
                    trigger: .value(AnySymbolEffectTrigger(1))
                ),
                for: 11
            )
            let environment = graph.makeInput(value: values)
            let time = graph.makeInput(value: Time(seconds: 0))
            let child: Attribute<ImageViewChild.Value> = graph.makeStatefulRule(
                ImageViewChild(
                    resolvedImage: resolved,
                    environment: environment,
                    transaction: graph.makeInput(value: Transaction()),
                    time: time
                )
            )

            XCTAssertFalse(child.value.isSymbolEffectActive)
            XCTAssertEqual(child.value.symbolOpacity, 1)

            var triggered = values
            triggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(2))
            environment.setValue(triggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            XCTAssertEqual(child.value.symbolOpacity, 1, accuracy: 0.000_001)

            time.setValue(Time(seconds: 1))
            XCTAssertTrue(child.value.isSymbolEffectActive)
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)

            time.setValue(Time(seconds: 2))
            XCTAssertFalse(child.value.isSymbolEffectActive)
            XCTAssertEqual(child.value.symbolOpacity, 1, accuracy: 0.000_001)

            triggered.symbolEffects[0].effect.options = .default
            triggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(3))
            environment.setValue(triggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 3))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 4))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            triggered.symbolEffects[0].effect.options = .speed(2).nonRepeating
            triggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(4))
            environment.setValue(triggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 4.5))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 5))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            triggered.symbolEffects[0].effect.options = .repeat(.periodic(2))
            triggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(5))
            environment.setValue(triggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 6))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 7))
            XCTAssertEqual(child.value.symbolOpacity, 1, accuracy: 0.000_001)
            time.setValue(Time(seconds: 8))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 9))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            environment.setValue(EnvironmentValues())
            _ = child.value
            var indefinite = EnvironmentValues()
            indefinite.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: PulseSymbolEffect.pulse.wholeSymbol.configuration,
                    options: .default,
                    trigger: .indefinite
                ),
                for: 11
            )
            environment.setValue(indefinite)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 10))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 11))
            XCTAssertTrue(child.value.isSymbolEffectActive)
            XCTAssertEqual(child.value.symbolOpacity, 1, accuracy: 0.000_001)
            time.setValue(Time(seconds: 12))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)

            // ASSERTIONS symbolEffectWholeSymbolPulseRuntimeObserved
            // ASSERTIONS symbolEffectPulseOptionsRuntimeObserved
        }
    }

    func testWholeSymbolPulseMatchesObservedRepeatAndControlBehavior() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let symbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
                name: "star.fill",
                variableValue: nil,
                bundle: nil
            ))
            let resolved = graph.makeInput(
                value: Optional(GraphicsContext.ResolvedImage(symbol: symbol))
            )
            var delayed = EnvironmentValues()
            delayed.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: PulseSymbolEffect.pulse.wholeSymbol.configuration,
                    options: .repeat(.periodic(2, delay: 0.5)),
                    trigger: .value(AnySymbolEffectTrigger(1))
                ),
                for: 11
            )
            let environment = graph.makeInput(value: delayed)
            let time = graph.makeInput(value: Time(seconds: 0))
            let child: Attribute<ImageViewChild.Value> = graph.makeStatefulRule(
                ImageViewChild(
                    resolvedImage: resolved,
                    environment: environment,
                    transaction: graph.makeInput(value: Transaction()),
                    time: time
                )
            )

            XCTAssertFalse(child.value.isSymbolEffectActive)
            delayed.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(2))
            environment.setValue(delayed)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 1))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 2.25))
            XCTAssertTrue(child.value.isSymbolEffectActive)
            XCTAssertEqual(child.value.symbolOpacity, 1, accuracy: 0.000_001)
            time.setValue(Time(seconds: 3.5))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 4.5))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            time.setValue(Time(seconds: 5))
            var continuous = EnvironmentValues()
            continuous.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: PulseSymbolEffect.pulse.wholeSymbol.configuration,
                    options: .repeat(.continuous),
                    trigger: .indefinite
                ),
                for: 12
            )
            environment.setValue(continuous)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 6))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 7))
            XCTAssertTrue(child.value.isSymbolEffectActive)
            XCTAssertEqual(child.value.symbolOpacity, 1, accuracy: 0.000_001)
            time.setValue(Time(seconds: 8))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)

            environment.setValue(EnvironmentValues())
            _ = child.value
            time.setValue(Time(seconds: 9))
            var cancellable = EnvironmentValues()
            cancellable.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: PulseSymbolEffect.pulse.wholeSymbol.configuration,
                    options: .default,
                    trigger: .indefinite
                ),
                for: 13
            )
            environment.setValue(cancellable)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 9.75))
            environment.setValue(EnvironmentValues())
            XCTAssertTrue(child.value.isSymbolEffectActive)
            XCTAssertEqual(
                child.value.symbolOpacity,
                0.65 + 0.35 * cos(0.75 * .pi),
                accuracy: 0.000_001
            )
            time.setValue(Time(seconds: 10))
            XCTAssertTrue(child.value.isSymbolEffectActive)
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 11))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            time.setValue(Time(seconds: 12))
            var retriggered = EnvironmentValues()
            retriggered.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: PulseSymbolEffect.pulse.wholeSymbol.configuration,
                    options: .nonRepeating,
                    trigger: .value(AnySymbolEffectTrigger(1))
                ),
                for: 14
            )
            environment.setValue(retriggered)
            XCTAssertFalse(child.value.isSymbolEffectActive)
            retriggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(2))
            environment.setValue(retriggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 12.75))
            let opacityBeforeRetrigger = child.value.symbolOpacity
            retriggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(3))
            environment.setValue(retriggered)
            XCTAssertEqual(child.value.symbolOpacity, opacityBeforeRetrigger, accuracy: 0.000_001)
            time.setValue(Time(seconds: 13))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 14))
            XCTAssertTrue(child.value.isSymbolEffectActive)
            XCTAssertEqual(child.value.symbolOpacity, 1, accuracy: 0.000_001)
            time.setValue(Time(seconds: 15))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 16))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            time.setValue(Time(seconds: 17))
            retriggered.symbolEffects[0].effect.options = .speed(0).nonRepeating
            retriggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(4))
            environment.setValue(retriggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 19))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 21))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            time.setValue(Time(seconds: 22))
            retriggered.symbolEffects[0].effect.options = .speed(-1).nonRepeating
            retriggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(5))
            environment.setValue(retriggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 24))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 26))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            time.setValue(Time(seconds: 27))
            retriggered.symbolEffects[0].effect.options = .speed(0.25).nonRepeating
            retriggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(6))
            environment.setValue(retriggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 29))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 31))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            time.setValue(Time(seconds: 32))
            retriggered.symbolEffects[0].effect.options = .speed(-10).nonRepeating
            retriggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(7))
            environment.setValue(retriggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 34))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            time.setValue(Time(seconds: 36))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            time.setValue(Time(seconds: 37))
            retriggered.symbolEffects[0].effect.configuration =
                PulseSymbolEffect.pulse.byLayer.configuration
            retriggered.symbolEffects[0].effect.options = .nonRepeating
            retriggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(8))
            environment.setValue(retriggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            XCTAssertEqual(child.value.symbolOpacity, 1, accuracy: 0.000_001)
            XCTAssertEqual(child.value.symbolLayerOpacities, [1])
            time.setValue(Time(seconds: 38))
            XCTAssertEqual(child.value.symbolOpacity, 1, accuracy: 0.000_001)
            XCTAssertEqual(
                try XCTUnwrap(child.value.symbolLayerOpacities?.first),
                0.3,
                accuracy: 0.000_001
            )
            time.setValue(Time(seconds: 39))
            XCTAssertFalse(child.value.isSymbolEffectActive)
            XCTAssertNil(child.value.symbolLayerOpacities)

            time.setValue(Time(seconds: 40))
            retriggered.symbolEffects[0].effect.configuration =
                PulseSymbolEffect.pulse.wholeSymbol.configuration
            retriggered.symbolEffects[0].effect.trigger = .value(AnySymbolEffectTrigger(9))
            environment.setValue(retriggered)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: 41))
            XCTAssertEqual(child.value.symbolOpacity, 0.3, accuracy: 0.000_001)
            XCTAssertNil(child.value.symbolLayerOpacities)
            time.setValue(Time(seconds: 42))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            // ASSERTIONS symbolEffectPulseRepeatControlRuntimeObserved
            // ASSERTIONS symbolEffectPulseLayeredRuntimeObserved
        }
    }

    func testVariableColorMatchesObservedLayerStateAndControlBehavior() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let symbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
                name: "photo.fill",
                variableValue: nil,
                bundle: nil
            ))
            let resolved = graph.makeInput(
                value: Optional(GraphicsContext.ResolvedImage(symbol: symbol))
            )
            var effects = EnvironmentValues()
            effects.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: VariableColorSymbolEffect.variableColor.configuration,
                    options: .nonRepeating,
                    trigger: .value(AnySymbolEffectTrigger(1))
                ),
                for: 21
            )
            let environment = graph.makeInput(value: effects)
            let time = graph.makeInput(value: Time(seconds: 0))
            let child: Attribute<ImageViewChild.Value> = graph.makeStatefulRule(
                ImageViewChild(
                    resolvedImage: resolved,
                    environment: environment,
                    transaction: graph.makeInput(value: Transaction()),
                    time: time
                )
            )

            let intro = ImageViewChild.ActiveVariableColor.introDuration
            let outro = ImageViewChild.ActiveVariableColor.outroDuration
            let step = ImageViewChild.ActiveVariableColor.stepDuration
            var nextTrigger = 1

            func assertOpacities(
                _ expected: [Double],
                accuracy: Double = 0.000_001,
                file: StaticString = #filePath,
                line: UInt = #line
            ) throws {
                let actual = try XCTUnwrap(
                    child.value.symbolVariableColorOpacities,
                    file: file,
                    line: line
                )
                XCTAssertEqual(actual.count, expected.count, file: file, line: line)
                for (actual, expected) in zip(actual, expected) {
                    XCTAssertEqual(
                        actual,
                        expected,
                        accuracy: accuracy,
                        file: file,
                        line: line
                    )
                }
            }

            func activate(
                _ configuration: VUI.SymbolEffectConfiguration,
                options: VUI.SymbolEffectOptions = .nonRepeating,
                at start: Double
            ) {
                time.setValue(Time(seconds: start))
                nextTrigger += 1
                effects.symbolEffects[0].effect.configuration = configuration
                effects.symbolEffects[0].effect.options = options
                effects.symbolEffects[0].effect.trigger =
                    .value(AnySymbolEffectTrigger(nextTrigger))
                environment.setValue(effects)
                XCTAssertTrue(child.value.isSymbolEffectActive)
            }

            XCTAssertFalse(child.value.isSymbolEffectActive)
            activate(VariableColorSymbolEffect.variableColor.configuration, at: 0)
            try assertOpacities([1, 1])
            time.setValue(Time(seconds: intro))
            try assertOpacities([0.3, 0.3])
            time.setValue(Time(seconds: intro + step * 0.5))
            try assertOpacities([0.65, 0.3])
            time.setValue(Time(seconds: intro + step * 1.5))
            try assertOpacities([1, 0.65])
            time.setValue(Time(seconds: intro + step * 2))
            try assertOpacities([1, 1])
            time.setValue(Time(seconds: intro + step * 3.5))
            try assertOpacities([0.65, 0.65])
            time.setValue(Time(seconds: intro + step * 4 + outro * 0.5))
            try assertOpacities([0.65, 0.65])
            time.setValue(Time(seconds: intro + step * 4 + outro + 0.001))
            XCTAssertFalse(child.value.isSymbolEffectActive)
            XCTAssertNil(child.value.symbolVariableColorOpacities)

            let iterativeStart = 3.0
            activate(
                VariableColorSymbolEffect.variableColor.iterative.configuration,
                at: iterativeStart
            )
            time.setValue(Time(seconds: iterativeStart + intro + step))
            try assertOpacities([1, 0.3])
            time.setValue(Time(seconds: iterativeStart + intro + step * 2))
            try assertOpacities([0.3, 1])
            time.setValue(Time(
                seconds: iterativeStart + intro + step * 3 + outro * 0.5
            ))
            try assertOpacities([0.65, 0.65])

            let hideStart = 6.0
            activate(
                VariableColorSymbolEffect.variableColor
                    .hideInactiveLayers.configuration,
                at: hideStart
            )
            time.setValue(Time(seconds: hideStart + intro))
            try assertOpacities([0, 0])

            let reversingStart = 9.0
            activate(
                VariableColorSymbolEffect.variableColor.reversing.configuration,
                at: reversingStart
            )
            time.setValue(Time(seconds: reversingStart + intro + step * 3.5))
            try assertOpacities([1, 0.65])
            time.setValue(Time(seconds: reversingStart + intro + step * 4.5))
            try assertOpacities([0.65, 0.3])
            time.setValue(Time(
                seconds: reversingStart + intro + step * 5 + outro + 0.001
            ))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            let bounceStart = 13.0
            activate(
                VariableColorSymbolEffect.variableColor
                    .iterative.reversing.configuration,
                at: bounceStart
            )
            time.setValue(Time(seconds: bounceStart + intro))
            try assertOpacities([1, 0.3])
            time.setValue(Time(seconds: bounceStart + intro + step))
            try assertOpacities([0.3, 1])
            time.setValue(Time(seconds: bounceStart + intro + step * 2))
            try assertOpacities([1, 0.3])
            time.setValue(Time(
                seconds: bounceStart + intro + step * 2 + outro * 0.5
            ))
            try assertOpacities([1, 0.65])

            let fastStart = 16.0
            activate(
                VariableColorSymbolEffect.variableColor.configuration,
                options: .speed(10).nonRepeating,
                at: fastStart
            )
            time.setValue(Time(
                seconds: fastStart + (intro + step * 4 + outro) / 2 + 0.001
            ))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            let slowStart = 18.0
            activate(
                VariableColorSymbolEffect.variableColor.configuration,
                options: .speed(0).nonRepeating,
                at: slowStart
            )
            time.setValue(Time(seconds: slowStart + 2))
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(
                seconds: slowStart + (intro + step * 4 + outro) / 0.5 + 0.001
            ))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            let repeatedStart = 23.0
            activate(
                VariableColorSymbolEffect.variableColor.configuration,
                options: .repeat(.periodic(2)),
                at: repeatedStart
            )
            time.setValue(Time(
                seconds: repeatedStart + intro + step * 4 + step
            ))
            XCTAssertTrue(child.value.isSymbolEffectActive)
            try assertOpacities([1, 0.3])
            time.setValue(Time(
                seconds: repeatedStart + intro + step * 8 + outro + 0.001
            ))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            let cancellationStart = 28.0
            time.setValue(Time(seconds: cancellationStart))
            environment.setValue(EnvironmentValues())
            _ = child.value
            var cancellable = EnvironmentValues()
            cancellable.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: VariableColorSymbolEffect.variableColor.configuration,
                    options: .default,
                    trigger: .indefinite
                ),
                for: 22
            )
            environment.setValue(cancellable)
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: cancellationStart + 0.8))
            environment.setValue(EnvironmentValues())
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(
                seconds: cancellationStart + intro + step * 4 + outro + 0.001
            ))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            let retriggerStart = 32.0
            time.setValue(Time(seconds: retriggerStart))
            var retriggered = EnvironmentValues()
            retriggered.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: VariableColorSymbolEffect.variableColor.configuration,
                    options: .nonRepeating,
                    trigger: .value(AnySymbolEffectTrigger(1))
                ),
                for: 23
            )
            environment.setValue(retriggered)
            XCTAssertFalse(child.value.isSymbolEffectActive)
            retriggered.symbolEffects[0].effect.trigger =
                .value(AnySymbolEffectTrigger(2))
            environment.setValue(retriggered)
            time.setValue(Time(seconds: retriggerStart + 0.9))
            let beforeRetrigger = try XCTUnwrap(
                child.value.symbolVariableColorOpacities
            )
            retriggered.symbolEffects[0].effect.trigger =
                .value(AnySymbolEffectTrigger(3))
            environment.setValue(retriggered)
            let afterRetrigger = try XCTUnwrap(
                child.value.symbolVariableColorOpacities
            )
            XCTAssertEqual(afterRetrigger.count, beforeRetrigger.count)
            for (before, after) in zip(beforeRetrigger, afterRetrigger) {
                XCTAssertEqual(before, after, accuracy: 0.000_001)
            }
            time.setValue(Time(seconds: retriggerStart + 2.2))
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(
                seconds: retriggerStart + 0.9 + intro + step * 4 + outro + 0.001
            ))
            XCTAssertFalse(child.value.isSymbolEffectActive)

            // ASSERTIONS symbolEffectVariableColorRuntimeObserved
            // ASSERTIONS symbolEffectVariableColorOptionsRuntimeObserved
            // ASSERTIONS symbolEffectVariableColorDisassemblyObserved
        }
    }

    func testDrawEffectMatchesObservedHiddenStateAndMotionGroupBehavior() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let symbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
                name: "draw",
                variableValue: nil,
                bundle: nil
            ))
            let durations = symbol.drawMotionGroupDurations
            let longest = try XCTUnwrap(durations.max())
            let resolved = graph.makeInput(
                value: Optional(GraphicsContext.ResolvedImage(symbol: symbol))
            )
            let environment = graph.makeInput(value: EnvironmentValues())
            let time = graph.makeInput(value: Time(seconds: 0))
            let child: Attribute<ImageViewChild.Value> = graph.makeStatefulRule(
                ImageViewChild(
                    resolvedImage: resolved,
                    environment: environment,
                    transaction: graph.makeInput(value: Transaction()),
                    time: time
                )
            )

            func drawEnvironment(
                _ configuration: VUI.SymbolEffectConfiguration,
                options: VUI.SymbolEffectOptions = .default,
                trigger: ResolvedSymbolEffect.Trigger = .indefinite,
                id: Int
            ) -> EnvironmentValues {
                var values = EnvironmentValues()
                values.appendSymbolEffect(
                    ResolvedSymbolEffect(
                        configuration: configuration,
                        options: options,
                        trigger: trigger
                    ),
                    for: id
                )
                return values
            }

            func progresses(
                file: StaticString = #filePath,
                line: UInt = #line
            ) throws -> [Double] {
                try XCTUnwrap(
                    child.value.symbolDrawProgresses,
                    file: file,
                    line: line
                )
            }

            XCTAssertFalse(child.value.isSymbolEffectActive)
            environment.setValue(drawEnvironment(
                DrawOffSymbolEffect.drawOff.configuration,
                id: 31
            ))
            XCTAssertEqual(try progresses(), [1, 1])
            XCTAssertTrue(child.value.isSymbolEffectActive)

            time.setValue(Time(seconds: longest + 0.001))
            XCTAssertEqual(try progresses(), [0, 0])
            XCTAssertFalse(child.value.isSymbolEffectActive)

            environment.setValue(EnvironmentValues())
            XCTAssertEqual(try progresses(), [0, 0])
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: longest * 2 + 0.002))
            XCTAssertNil(child.value.symbolDrawProgresses)
            XCTAssertFalse(child.value.isSymbolEffectActive)

            let wholeStart = longest * 3
            time.setValue(Time(seconds: wholeStart))
            environment.setValue(drawEnvironment(
                DrawOffSymbolEffect.drawOff.wholeSymbol.configuration,
                id: 32
            ))
            _ = child.value
            time.setValue(Time(seconds: wholeStart + longest * 0.5))
            let whole = try progresses()
            XCTAssertEqual(whole[0], whole[1], accuracy: 0.000_001)
            XCTAssertEqual(whole[0], 0.5, accuracy: 0.000_001)

            time.setValue(Time(seconds: wholeStart + longest + 0.001))
            _ = child.value
            environment.setValue(EnvironmentValues())
            _ = child.value
            time.setValue(Time(seconds: wholeStart + longest * 2 + 0.002))
            XCTAssertNil(child.value.symbolDrawProgresses)

            let individualStart = wholeStart + longest * 3
            time.setValue(Time(seconds: individualStart))
            environment.setValue(drawEnvironment(
                DrawOffSymbolEffect.drawOff.individually.configuration,
                id: 33
            ))
            _ = child.value
            time.setValue(Time(
                seconds: individualStart + durations[0] + 0.000_1
            ))
            let individual = try progresses()
            XCTAssertEqual(individual[0], 0, accuracy: 0.000_001)
            XCTAssertGreaterThan(individual[1], 0.99)

            time.setValue(Time(
                seconds: individualStart + durations.reduce(0, +) + 0.001
            ))
            _ = child.value
            environment.setValue(EnvironmentValues())
            _ = child.value
            time.setValue(Time(
                seconds: individualStart + durations.reduce(0, +) * 2 + 0.002
            ))
            XCTAssertNil(child.value.symbolDrawProgresses)

            let reversedStart = individualStart + durations.reduce(0, +) * 3
            time.setValue(Time(seconds: reversedStart))
            environment.setValue(drawEnvironment(
                DrawOffSymbolEffect.drawOff.individually.reversed.configuration,
                id: 34
            ))
            XCTAssertTrue(child.value.symbolDrawsReversed)
            time.setValue(Time(
                seconds: reversedStart + durations[1] + 0.000_1
            ))
            let reversed = try progresses()
            XCTAssertGreaterThan(reversed[0], 0.99)
            XCTAssertEqual(reversed[1], 0, accuracy: 0.000_001)

            let reversedEnd = reversedStart + durations.reduce(0, +) + 0.001
            time.setValue(Time(seconds: reversedEnd))
            _ = child.value
            environment.setValue(EnvironmentValues())
            _ = child.value
            let restoredAfterReverse = reversedEnd + durations.reduce(0, +) + 0.001
            time.setValue(Time(seconds: restoredAfterReverse))
            XCTAssertNil(child.value.symbolDrawProgresses)

            let fastStart = restoredAfterReverse + 1
            time.setValue(Time(seconds: fastStart))
            environment.setValue(drawEnvironment(
                DrawOffSymbolEffect.drawOff.configuration,
                options: .speed(10),
                id: 35
            ))
            _ = child.value
            time.setValue(Time(seconds: fastStart + longest / 2 + 0.001))
            XCTAssertEqual(try progresses(), [0, 0])

            environment.setValue(EnvironmentValues())
            _ = child.value
            let fastRestoreEnd = fastStart + longest + 0.002
            time.setValue(Time(seconds: fastRestoreEnd))
            XCTAssertNil(child.value.symbolDrawProgresses)

            let repeatingStart = fastRestoreEnd + 1
            time.setValue(Time(seconds: repeatingStart))
            environment.setValue(drawEnvironment(
                DrawOffSymbolEffect.drawOff.configuration,
                options: .repeat(.periodic(2)),
                id: 36
            ))
            _ = child.value
            time.setValue(Time(seconds: repeatingStart + longest * 2 + 0.001))
            XCTAssertEqual(try progresses(), [0, 0])
            XCTAssertFalse(child.value.isSymbolEffectActive)

            environment.setValue(EnvironmentValues())
            _ = child.value
            let repeatingRestoreEnd = repeatingStart + longest * 3 + 0.002
            time.setValue(Time(seconds: repeatingRestoreEnd))
            XCTAssertNil(child.value.symbolDrawProgresses)

            let transitionStart = repeatingRestoreEnd + 1
            time.setValue(Time(seconds: transitionStart))
            environment.setValue(drawEnvironment(
                DrawOnSymbolEffect.drawOn.configuration,
                trigger: .transition(.identity),
                id: 37
            ))
            XCTAssertNil(child.value.symbolDrawProgresses)
            environment.setValue(drawEnvironment(
                DrawOnSymbolEffect.drawOn.configuration,
                trigger: .transition(.didDisappear),
                id: 37
            ))
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: transitionStart + longest + 0.001))
            XCTAssertEqual(try progresses(), [0, 0])
            environment.setValue(drawEnvironment(
                DrawOnSymbolEffect.drawOn.configuration,
                trigger: .transition(.identity),
                id: 37
            ))
            _ = child.value
            time.setValue(Time(seconds: transitionStart + longest * 2 + 0.002))
            XCTAssertNil(child.value.symbolDrawProgresses)

            // ASSERTIONS symbolEffectDrawRuntimeObserved
            // ASSERTIONS symbolEffectDrawTransitionRuntimeObserved
            // ASSERTIONS symbolEffectDrawOptionsRuntimeObserved
            // ASSERTIONS symbolEffectDrawBackendOptionsObserved
            // ASSERTIONS symbolEffectDrawDisassemblyObserved
        }
    }

    func testDrawEffectsUseIndependentPathProgressAndObservedControlRules() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let symbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
                name: "draw",
                variableValue: nil,
                bundle: nil
            ))
            let resolved = graph.makeInput(
                value: Optional(GraphicsContext.ResolvedImage(symbol: symbol))
            )
            let environment = graph.makeInput(value: EnvironmentValues())
            let transaction = graph.makeInput(value: Transaction())
            let time = graph.makeInput(value: Time(seconds: 0))
            let child: Attribute<ImageViewChild.Value> = graph.makeStatefulRule(
                ImageViewChild(
                    resolvedImage: resolved,
                    environment: environment,
                    transaction: transaction,
                    time: time
                )
            )

            XCTAssertNil(child.value.symbolDrawProgresses)
            let durations = symbol.drawMotionGroupDurations
            let end = durations.max() ?? 0

            var active = EnvironmentValues()
            active.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: DrawOnSymbolEffect.drawOn.configuration,
                    options: .repeat(.periodic(2)),
                    trigger: .indefinite
                ),
                for: 31
            )
            environment.setValue(active)
            XCTAssertEqual(child.value.symbolDrawProgresses, [1, 1])
            XCTAssertFalse(child.value.symbolDrawsReversed)

            time.setValue(Time(seconds: end * 0.5))
            let midpoint = try XCTUnwrap(child.value.symbolDrawProgresses)
            XCTAssertTrue(midpoint.allSatisfy { $0 >= 0 && $0 <= 1 })
            XCTAssertTrue(midpoint.contains { $0 > 0 && $0 < 1 })

            time.setValue(Time(seconds: end + 0.001))
            XCTAssertEqual(child.value.symbolDrawProgresses, [0, 0])
            XCTAssertFalse(child.value.isSymbolEffectActive)

            environment.setValue(EnvironmentValues())
            XCTAssertEqual(child.value.symbolDrawProgresses, [0, 0])
            XCTAssertTrue(child.value.isSymbolEffectActive)
            time.setValue(Time(seconds: end * 2 + 0.002))
            XCTAssertNil(child.value.symbolDrawProgresses)

            time.setValue(Time(seconds: 3))
            var reversed = EnvironmentValues()
            reversed.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: DrawOffSymbolEffect.drawOff
                        .reversed.configuration,
                    options: .speed(10),
                    trigger: .indefinite
                ),
                for: 32
            )
            environment.setValue(reversed)
            XCTAssertTrue(child.value.symbolDrawsReversed)
            time.setValue(Time(seconds: 3 + end / 2 + 0.001))
            XCTAssertEqual(child.value.symbolDrawProgresses, [0, 0])

            var entering = EnvironmentValues()
            entering.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: DrawOffSymbolEffect.drawOff.configuration,
                    options: .default,
                    trigger: .transition(.willAppear)
                ),
                for: 33
            )
            let transitionEnvironment = graph.makeInput(value: entering)
            let transitionTime = graph.makeInput(value: Time(seconds: 5))
            let transitionChild: Attribute<ImageViewChild.Value> =
                graph.makeStatefulRule(
                    ImageViewChild(
                        resolvedImage: resolved,
                        environment: transitionEnvironment,
                        transaction: transaction,
                        time: transitionTime
                    )
                )
            XCTAssertEqual(transitionChild.value.symbolDrawProgresses, [0, 0])
            XCTAssertFalse(transitionChild.value.isSymbolEffectActive)
            entering.symbolEffects[0].effect.trigger = .transition(.identity)
            transitionEnvironment.setValue(entering)
            XCTAssertEqual(transitionChild.value.symbolDrawProgresses, [0, 0])
            XCTAssertTrue(transitionChild.value.isSymbolEffectActive)
            transitionTime.setValue(Time(seconds: 5 + end + 0.001))
            XCTAssertNil(transitionChild.value.symbolDrawProgresses)

            let fallbackSymbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
                name: "star",
                variableValue: nil,
                bundle: nil
            ))
            resolved.setValue(GraphicsContext.ResolvedImage(symbol: fallbackSymbol))
            time.setValue(Time(seconds: 7))
            environment.setValue(EnvironmentValues())
            _ = child.value
            var fallback = EnvironmentValues()
            fallback.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: DrawOffSymbolEffect.drawOff.configuration,
                    options: .default,
                    trigger: .indefinite
                ),
                for: 34
            )
            environment.setValue(fallback)
            XCTAssertNil(child.value.symbolDrawProgresses)
            XCTAssertEqual(child.value.symbolDrawFallbackOpacity, 1)
            time.setValue(Time(seconds: 7.8))
            XCTAssertEqual(
                try XCTUnwrap(child.value.symbolDrawFallbackOpacity),
                0,
                accuracy: 0.000_001
            )

            // ASSERTIONS symbolEffectDrawRuntimeObserved
            // ASSERTIONS symbolEffectDrawTransitionRuntimeObserved
            // ASSERTIONS symbolEffectDrawSpatialRuntimeObserved
            // ASSERTIONS symbolEffectDrawOptionsRuntimeObserved
            // ASSERTIONS symbolEffectDrawBackendOptionsObserved
            // ASSERTIONS symbolEffectDrawDisassemblyObserved
        }
    }

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
