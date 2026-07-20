import XCTest
@testable import VUI

private final class TextVariantInputRecorder {
    var isEnabled: Bool?
}

private struct TextVariantInputRecorderContent: View, TestPrimitiveView {
    var recorder: TextVariantInputRecorder

    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        view._attribute.value.recorder.isEnabled = inputs.base[VariantThatFitsFlag.self]
        return _ViewOutputs()
    }
}

private struct TextVariantTestLayoutEngine: LayoutEngine {
    var marker: Int

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        CGSize(width: marker, height: marker)
    }
}

private struct TextVariantTestResolver: SizeFittingTextResolver {
    struct Input {
        var markers: [Int]
        var texts: [ResolvedStyledText]
    }

    typealias Engine = TextVariantTestLayoutEngine

    var sizeVariant: TextSizeVariant

    var narrowerVariant: TextVariantTestResolver {
        TextVariantTestResolver(sizeVariant: sizeVariant.nextDown)
    }

    func value(for input: Input) -> SizeFittingTextCacheValue<TextVariantTestLayoutEngine> {
        let index = min(sizeVariant.rawValue, input.markers.count - 1)
        return SizeFittingTextCacheValue(
            text: input.texts[index],
            engine: TextVariantTestLayoutEngine(marker: input.markers[index]),
            renderer: nil
        )
    }
}

private struct TestDateDiscreteStringStyle: DiscreteFormatStyle {
    func format(_ value: Date) -> String {
        "date:\(Int(value.timeIntervalSinceReferenceDate))"
    }

    func discreteInput(before input: Date) -> Date? {
        input.addingTimeInterval(-2)
    }

    func discreteInput(after input: Date) -> Date? {
        input.addingTimeInterval(2)
    }

    func locale(_ locale: Locale) -> TestDateDiscreteStringStyle { self }
}

private struct TestDateDiscreteAttributedStyle: DiscreteFormatStyle {
    func format(_ value: Date) -> AttributedString {
        var first = AttributedString("red")
        first._setCoreAttributes(_ResolvedTextRunAttributes(
            font: .system(size: 18, weight: .bold),
            foregroundColor: .red,
            underlineStyle: Text.LineStyle(pattern: .dash, color: .green),
            kern: 2,
            baselineOffset: 3
        ))

        var second = AttributedString("blue")
        second._setCoreAttributes(_ResolvedTextRunAttributes(
            foregroundColor: .blue,
            strikethroughStyle: Text.LineStyle(pattern: .dot, color: .orange),
            tracking: 1
        ))
        return first + AttributedString(" ") + second
    }

    func discreteInput(before input: Date) -> Date? {
        input.addingTimeInterval(-2)
    }

    func discreteInput(after input: Date) -> Date? {
        input.addingTimeInterval(2)
    }

    func locale(_ locale: Locale) -> TestDateDiscreteAttributedStyle { self }
}

private struct TestLocaleDiscreteStringStyle: DiscreteFormatStyle {
    var localeIdentifier = "unset"

    func format(_ value: Date) -> String {
        localeIdentifier
    }

    func discreteInput(before input: Date) -> Date? { nil }
    func discreteInput(after input: Date) -> Date? { nil }

    func locale(_ locale: Locale) -> TestLocaleDiscreteStringStyle {
        var copy = self
        copy.localeIdentifier = locale.identifier
        return copy
    }
}

private struct TestDurationDiscreteStringStyle: DiscreteFormatStyle {
    func format(_ value: Duration) -> String {
        "duration:\(value.components.seconds)"
    }

    func discreteInput(before input: Duration) -> Duration? {
        input - .seconds(1)
    }

    func discreteInput(after input: Duration) -> Duration? {
        input + .seconds(1)
    }

    func locale(_ locale: Locale) -> TestDurationDiscreteStringStyle { self }
}

private struct TestDateRangeDiscreteStringStyle: DiscreteFormatStyle {
    func format(_ value: Range<Date>) -> String {
        "range:\(Int(value.lowerBound.timeIntervalSinceReferenceDate))..." +
            "\(Int(value.upperBound.timeIntervalSinceReferenceDate))"
    }

    func discreteInput(before input: Range<Date>) -> Range<Date>? { nil }
    func discreteInput(after input: Range<Date>) -> Range<Date>? { nil }
    func input(before input: Range<Date>) -> Range<Date>? { nil }
    func input(after input: Range<Date>) -> Range<Date>? { nil }
    func locale(_ locale: Locale) -> TestDateRangeDiscreteStringStyle { self }
}

private func makeVariantText(unique: Bool = true) -> ResolvedStyledText {
    ResolvedStyledText(features: unique ? [.isUniqueSizeVariant] : [])
}

final class TextVariantPreferenceTests: XCTestCase {
    func testDateStyleMatchesObservedLayoutAndCodableValues() throws {
        XCTAssertEqual(MemoryLayout<Text.DateStyle>.size, 17)
        XCTAssertEqual(MemoryLayout<Text.DateStyle>.stride, 24)
        XCTAssertEqual(MemoryLayout<Text.DateStyle>.alignment, 8)

        let styles: [(Text.DateStyle, UInt8)] = [
            (.time, 0),
            (.date, 1),
            (.relative, 2),
            (.offset, 3),
            (.timer, 4),
        ]
        for (style, rawValue) in styles {
            let data = try JSONEncoder().encode(style)
            XCTAssertEqual(
                String(decoding: data, as: UTF8.self),
                "{\"storage\":\(rawValue)}"
            )
            XCTAssertEqual(try JSONDecoder().decode(Text.DateStyle.self, from: data), style)
        }
    }

    func testRelativeDateStorageOffersARegularCandidateAndOptionalNarrowerCandidate() {
        let text = Text(Date.now.addingTimeInterval(93_784), style: .relative)
        let variants = text._sizeVariantTexts(in: EnvironmentValues())

        guard case let .anyTextStorage(storage) = text.storage else {
            return XCTFail("relative date text should use AnyTextStorage")
        }
        XCTAssertTrue(String(reflecting: type(of: storage)).contains("TimeDataFormattingStorage"))
        XCTAssertEqual(
            Mirror(reflecting: storage).children.compactMap(\.label),
            ["source", "format", "reducedLuminanceBudget"]
        )

        XCTAssertEqual(variants?.first?.0, .regular)
        XCTAssertFalse(variants?.first?.1.isEmpty ?? true)
        if let variants, variants.count > 1 {
            XCTAssertEqual(variants[1].0, .compact)
            XCTAssertLessThanOrEqual(variants[1].1.count, variants[0].1.count)
        }
    }

    func testOffsetDateUsesObservedLocalizedSignAndWideUnitOutput() {
        let reference = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var environment = EnvironmentValues()

        environment.locale = Locale(identifier: "en_US")
        XCTAssertEqual(
            Text(reference.addingTimeInterval(-3_600), style: .offset)
                ._resolveText(in: environment, referenceDate: reference),
            "+1 hour"
        )
        XCTAssertEqual(
            Text(reference.addingTimeInterval(3_600), style: .offset)
                ._resolveText(in: environment, referenceDate: reference),
            "−1 hour"
        )

        environment.locale = Locale(identifier: "ko_KR")
        XCTAssertEqual(
            Text(reference.addingTimeInterval(-172_800), style: .offset)
                ._resolveText(in: environment, referenceDate: reference),
            "+2일"
        )
        XCTAssertEqual(
            Text(reference.addingTimeInterval(172_800), style: .offset)
                ._resolveText(in: environment, referenceDate: reference),
            "−2일"
        )
    }

    func testGenericTimeDataFormatterReceivesEnvironmentLocale() {
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "fr_FR")
        let text = Text(
            TimeDataSource<Date>.currentDate,
            format: TestLocaleDiscreteStringStyle()
        )

        XCTAssertEqual(
            text._resolveText(
                in: environment,
                referenceDate: Date(timeIntervalSinceReferenceDate: 1_000)
            ),
            "fr_FR"
        )
    }

    func testTimeAndDateStylesUseNonVariantFormatStyleStorage() {
        for style in [Text.DateStyle.time, .date] {
            let text = Text(Date(timeIntervalSinceReferenceDate: 0), style: style)
            guard case let .anyTextStorage(storage) = text.storage else {
                return XCTFail("time/date text should use AnyTextStorage")
            }

            XCTAssertTrue(String(reflecting: type(of: storage)).contains("FormatStyleStorage"))
            XCTAssertFalse(
                String(reflecting: type(of: storage)).contains("TimeDataFormattingStorage")
            )
            XCTAssertEqual(
                Mirror(reflecting: storage).children.compactMap(\.label),
                ["storage"]
            )
            guard let box = Mirror(reflecting: storage).children.first?.value else {
                return XCTFail("FormatStyleStorage should retain its box")
            }
            XCTAssertTrue(String(reflecting: type(of: box)).contains("FormatStyleBox"))
            XCTAssertEqual(
                Mirror(reflecting: box).children.compactMap(\.label),
                ["input", "format"]
            )
            XCTAssertNil(text._sizeVariantTexts(in: EnvironmentValues()))
            XCTAssertFalse(text._resolveText(in: EnvironmentValues()).isEmpty)
        }
    }

    func testTimerIntervalFormattingMatchesObservedDirectionPauseAndHourRules() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let end = start.addingTimeInterval(3_661)
        let interval = start...end
        let environment = EnvironmentValues()

        let downWithHours = Text(
            timerInterval: interval,
            countsDown: true,
            showsHours: true
        )
        XCTAssertEqual(
            downWithHours._resolveText(in: environment, referenceDate: start),
            "1:01:01"
        )
        XCTAssertEqual(
            downWithHours._resolveText(
                in: environment,
                referenceDate: start.addingTimeInterval(0.99)
            ),
            "1:01:01"
        )
        XCTAssertEqual(
            downWithHours._resolveText(
                in: environment,
                referenceDate: start.addingTimeInterval(1)
            ),
            "1:01:00"
        )
        XCTAssertEqual(
            downWithHours._resolveText(
                in: environment,
                referenceDate: end.addingTimeInterval(1)
            ),
            "0:00"
        )

        let upWithoutHours = Text(
            timerInterval: interval,
            countsDown: false,
            showsHours: false
        )
        XCTAssertEqual(
            upWithoutHours._resolveText(
                in: environment,
                referenceDate: start.addingTimeInterval(3_600)
            ),
            "60:00"
        )
        XCTAssertEqual(
            upWithoutHours._resolveText(
                in: environment,
                referenceDate: end.addingTimeInterval(1)
            ),
            "61:01"
        )
        XCTAssertNil(upWithoutHours._sizeVariantTexts(in: environment))

        let pause = start.addingTimeInterval(61)
        let pausedDown = Text(
            timerInterval: interval,
            pauseTime: pause,
            countsDown: true,
            showsHours: false
        )
        let pausedUp = Text(
            timerInterval: interval,
            pauseTime: pause,
            countsDown: false,
            showsHours: true
        )
        XCTAssertEqual(
            pausedDown._resolveText(in: environment, referenceDate: start),
            "1:01"
        )
        XCTAssertEqual(
            pausedUp._resolveText(in: environment, referenceDate: end),
            "1:01"
        )
        XCTAssertNil(pausedDown._nextUpdateDelay(in: environment, referenceDate: start))
        XCTAssertNil(pausedUp._nextUpdateDelay(in: environment, referenceDate: start))

        XCTAssertEqual(
            downWithHours._nextUpdateDelay(
                in: environment,
                referenceDate: start.addingTimeInterval(0.25)
            )!,
            0.75,
            accuracy: 1e-9
        )
        XCTAssertNil(
            downWithHours._nextUpdateDelay(in: environment, referenceDate: end)
        )
    }

    func testTimeDataSourceGenericStringFormattingAndDeadlinesMatchObservedSources() {
        XCTAssertEqual(MemoryLayout<TimeDataSource<Date>>.size, 8)
        XCTAssertEqual(MemoryLayout<TimeDataSource<Date>>.stride, 8)
        XCTAssertEqual(MemoryLayout<TimeDataSource<Date>>.alignment, 8)

        let environment = EnvironmentValues()
        let reference = Date(timeIntervalSinceReferenceDate: 1_000)
        let currentDateText = Text(
            TimeDataSource<Date>.currentDate,
            format: TestDateDiscreteStringStyle()
        )
        XCTAssertEqual(
            currentDateText._resolveText(in: environment, referenceDate: reference),
            "date:1000"
        )
        XCTAssertEqual(
            currentDateText._nextUpdateDelay(in: environment, referenceDate: reference)!,
            2,
            accuracy: 1e-9
        )
        XCTAssertNil(currentDateText._sizeVariantTexts(in: environment))

        let anchor = Date(timeIntervalSinceReferenceDate: 1_120)
        let durationText = Text(
            TimeDataSource<Duration>.durationOffset(to: anchor),
            format: TestDurationDiscreteStringStyle()
        )
        XCTAssertEqual(
            durationText._resolveText(in: environment, referenceDate: reference),
            "duration:-120"
        )
        XCTAssertEqual(
            durationText._nextUpdateDelay(in: environment, referenceDate: reference)!,
            1,
            accuracy: 1e-9
        )

        let start = Date(timeIntervalSinceReferenceDate: 900)
        let startingRangeText = Text(
            TimeDataSource<Range<Date>>.dateRange(startingAt: start),
            format: TestDateRangeDiscreteStringStyle()
        )
        XCTAssertEqual(
            startingRangeText._resolveText(in: environment, referenceDate: reference),
            "range:900...1000"
        )
        XCTAssertEqual(
            startingRangeText._resolveText(
                in: environment,
                referenceDate: Date(timeIntervalSinceReferenceDate: 800)
            ),
            "range:900...900"
        )
        XCTAssertNil(
            startingRangeText._nextUpdateDelay(in: environment, referenceDate: reference)
        )

        let end = Date(timeIntervalSinceReferenceDate: 1_100)
        let endingRangeText = Text(
            TimeDataSource<Range<Date>>.dateRange(endingAt: end),
            format: TestDateRangeDiscreteStringStyle()
        )
        XCTAssertEqual(
            endingRangeText._resolveText(in: environment, referenceDate: reference),
            "range:1000...1100"
        )
        XCTAssertEqual(
            endingRangeText._resolveText(
                in: environment,
                referenceDate: Date(timeIntervalSinceReferenceDate: 1_200)
            ),
            "range:1100...1100"
        )

        guard case let .anyTextStorage(storage) = currentDateText.storage else {
            return XCTFail("generic time-data text should use AnyTextStorage")
        }
        XCTAssertTrue(
            String(reflecting: type(of: storage)).contains("TimeDataFormattingStorage")
        )
    }

    func testAttributedScopeAndGenericTimeDataFormattingPreserveObservedRuns() throws {
        XCTAssertEqual(MemoryLayout<Text.LineStyle>.size, 16)
        XCTAssertEqual(MemoryLayout<Text.LineStyle>.stride, 16)
        XCTAssertEqual(MemoryLayout<Text.LineStyle>.alignment, 8)
        XCTAssertEqual(MemoryLayout<Text.LineStyle.Pattern>.size, 8)
        let dash = Text.LineStyle(pattern: .dash, color: .green)
        XCTAssertEqual(dash.nsUnderlineStyleValue, 0x201)
        XCTAssertEqual(dash.color, .green)
        XCTAssertEqual(Text.LineStyle.single.nsUnderlineStyleValue, 1)
        XCTAssertNil(Text.LineStyle.single.color)

        let output = TestDateDiscreteAttributedStyle().format(
            Date(timeIntervalSinceReferenceDate: 1_000)
        )
        let direct = Text(output)
        XCTAssertEqual(direct._resolveText(in: EnvironmentValues()), "red blue")
        XCTAssertFalse(direct._needsDynamicRenderingInArchive(in: EnvironmentValues()))
        guard case let .anyTextStorage(directStorage) = direct.storage,
              let attributedStorage = directStorage as? AttributedStringTextStorage else {
            return XCTFail("direct attributed text should retain attributed storage")
        }
        XCTAssertEqual(attributedStorage.str, output)

        let reference = Date(timeIntervalSinceReferenceDate: 1_000)
        let dynamic = Text(
            TimeDataSource<Date>.currentDate,
            format: TestDateDiscreteAttributedStyle()
        )
        XCTAssertEqual(
            dynamic._resolveText(in: EnvironmentValues(), referenceDate: reference),
            "red blue"
        )
        XCTAssertEqual(
            dynamic._nextUpdateDelay(in: EnvironmentValues(), referenceDate: reference),
            2
        )
        XCTAssertTrue(dynamic._needsDynamicRenderingInArchive(in: EnvironmentValues()))
        XCTAssertNil(dynamic._sizeVariantTexts(in: EnvironmentValues()))
        guard case let .anyTextStorage(dynamicStorage) = dynamic.storage else {
            return XCTFail("dynamic attributed text should use AnyTextStorage")
        }
        XCTAssertTrue(
            String(reflecting: type(of: dynamicStorage)).contains("TimeDataFormattingStorage")
        )
        XCTAssertFalse(
            String(reflecting: type(of: dynamicStorage)).contains(
                "AttributedTimeDataFormattingStorage"
            )
        )

        var recolored = output
        recolored._setCoreAttributes(_ResolvedTextRunAttributes(foregroundColor: .purple))
        XCTAssertNotEqual(Text(output), Text(recolored))
    }

    func testRelativeDateSchedulesTheNextVisibleUnitBoundary() {
        let reference = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let environment = EnvironmentValues()

        func delay(_ interval: TimeInterval, style: Text.DateStyle) -> TimeInterval? {
            Text(reference.addingTimeInterval(interval), style: style)
                ._nextUpdateDelay(in: environment, referenceDate: reference)
        }

        XCTAssertEqual(delay(4.25, style: .relative)!, 0.25, accuracy: 1e-9)
        XCTAssertEqual(delay(3_662.25, style: .relative)!, 2.25, accuracy: 1e-9)
        XCTAssertEqual(delay(93_602.25, style: .relative)!, 2.25, accuracy: 1e-9)
        XCTAssertEqual(delay(-4.25, style: .relative)!, 0.75, accuracy: 1e-9)
        XCTAssertEqual(delay(4.25, style: .timer)!, 0.25, accuracy: 1e-9)
        XCTAssertEqual(delay(93_602.25, style: .offset)!, 7_202.25, accuracy: 1e-9)
        XCTAssertNil(delay(4.25, style: .time))
        XCTAssertNil(delay(4.25, style: .date))
    }

    func testRelativeDateResourceRuleSchedulesViewGraphAtTheNextBoundary() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let text = graph.makeInput(value: Text(
                Date().addingTimeInterval(4.25),
                style: .relative
            ))
            let inputs = makeViewInputs(graph: graph)
            inputs.base.time.setValue(Time(seconds: 100))
            let outputs = Text._makeView(
                view: _GraphValue(_attribute: text),
                inputs: inputs
            )
            let resourceID = try XCTUnwrap(
                outputs.preferences.value(for: ResourceList.Key.self)
            )

            _ = Attribute<ResourceList>(resourceID).value

            XCTAssertGreaterThan(viewGraph.nextUpdate.views.time.seconds, 100)
            XCTAssertLessThan(viewGraph.nextUpdate.views.time.seconds, 101)
        }
    }

    func testPreferenceCarriersMatchObservedEmptyLayout() {
        XCTAssertEqual(MemoryLayout<FixedTextVariant>.size, 0)
        XCTAssertEqual(MemoryLayout<FixedTextVariant>.stride, 1)
        XCTAssertEqual(MemoryLayout<SizeDependentTextVariant>.size, 0)
        XCTAssertEqual(MemoryLayout<SizeDependentTextVariant>.stride, 1)
        XCTAssertEqual(MemoryLayout<_TextVariantPreference<FixedTextVariant>>.size, 0)
        XCTAssertEqual(MemoryLayout<_TextVariantPreference<FixedTextVariant>>.stride, 1)
        XCTAssertEqual(MemoryLayout<_TextVariantPreference<SizeDependentTextVariant>>.size, 0)
        XCTAssertEqual(MemoryLayout<_TextVariantPreference<SizeDependentTextVariant>>.stride, 1)

        _ = Text("fixed").textVariant(.fixed)
        _ = Text("size dependent").textVariant(.sizeDependent)
    }

    func testFixedPreferenceLeavesVariantFlagDisabled() {
        let recorder = TextVariantInputRecorder()
        let content = FixedTextVariant()._preference.body(
            TextVariantInputRecorderContent(recorder: recorder)
        )

        makeView(content)

        XCTAssertEqual(recorder.isEnabled, false)
    }

    func testSizeDependentPreferenceEnablesVariantFlag() {
        let recorder = TextVariantInputRecorder()
        let content = SizeDependentTextVariant()._preference.body(
            TextVariantInputRecorderContent(recorder: recorder)
        )

        makeView(content)

        XCTAssertEqual(recorder.isEnabled, true)
    }

    func testTextSizeVariantRawValuesAndTraversalMatchObservedOrder() {
        XCTAssertEqual(TextSizeVariant.regular.rawValue, 0)
        XCTAssertEqual(TextSizeVariant.compact.rawValue, 1)
        XCTAssertEqual(TextSizeVariant.small.rawValue, 2)
        XCTAssertEqual(TextSizeVariant.tiny.rawValue, 3)
        XCTAssertNil(TextSizeVariant.regular.nextUp)
        XCTAssertEqual(TextSizeVariant.compact.nextUp, .regular)
        XCTAssertEqual(TextSizeVariant.regular.nextDown, .compact)
        XCTAssertEqual(TextSizeVariant.compact.nextDown, .small)
    }

    func testClosestFitCacheUsesContainedProposalAndBubblesEqualSuggestion() {
        var cache = ClosestFitCache<Int>(capacity: 3)
        let wide = ProposedViewSize(width: 80, height: 100)
        let tall = ProposedViewSize(width: 100, height: 80)
        let small = ProposedViewSize(width: 60, height: 60)

        XCTAssertEqual(cache(for: wide) { value in
            XCTAssertNil(value)
            return 1
        }, 1)
        XCTAssertEqual(cache(for: tall) { value in
            XCTAssertNil(value)
            return 2
        }, 2)
        XCTAssertEqual(cache(for: small) { value in
            XCTAssertNil(value)
            return 3
        }, 3)

        XCTAssertEqual(
            cache(for: ProposedViewSize(width: 105, height: 90)) { value in
                XCTAssertEqual(value, 2)
                return value!
            },
            2
        )
        XCTAssertEqual(cache.entries.map(\.proposal), [tall, wide, small])
        XCTAssertEqual(cache.entries.map(\.value), [2, 1, 3])
    }

    func testClosestFitCacheReplacesLastEntryWhenSuggestionChangesAtCapacity() {
        var cache = ClosestFitCache<Int>(capacity: 2)
        let first = ProposedViewSize(width: 80, height: 80)
        let second = ProposedViewSize(width: 100, height: 100)
        let replacement = ProposedViewSize(width: 120, height: 120)

        XCTAssertEqual(cache(for: first) { _ in 1 }, 1)
        XCTAssertEqual(cache(for: second) { value in
            XCTAssertEqual(value, 1)
            return 2
        }, 2)
        XCTAssertEqual(cache(for: replacement) { value in
            XCTAssertEqual(value, 2)
            return 3
        }, 3)

        XCTAssertEqual(cache.entries.map(\.proposal), [first, replacement])
        XCTAssertEqual(cache.entries.map(\.value), [1, 3])
    }

    func testStickyLogicDefaultsKeepVerticalGrowthAndReleaseHorizontalGrowth() {
        var logic = StickyTextSizeFittingLogic()
        XCTAssertFalse(logic.stickOnHorizontalGrowth)
        XCTAssertTrue(logic.stickOnVerticalGrowth)
        XCTAssertNil(logic.suggestedVariant(for: .unspecified))

        logic.commit(.regular, for: ProposedViewSize(width: 100, height: 40))
        XCTAssertEqual(
            logic.suggestedVariant(for: ProposedViewSize(width: 90, height: 60)),
            .regular
        )
        XCTAssertNil(
            logic.suggestedVariant(for: ProposedViewSize(width: 110, height: 40))
        )

        logic.onInvalidation(of: .compact)
        XCTAssertNotNil(logic.committedValue)
        logic.onInvalidation(of: .regular)
        XCTAssertNil(logic.committedValue)
    }

    func testOneEntryCacheKeepsRegularVariantAndInvalidatesResolvedValueOnInputChange() {
        let text = ResolvedStyledText()
        let cache = SizeFittingTextCache(
            resolver: TextVariantTestResolver(sizeVariant: .regular),
            logic: StickyTextSizeFittingLogic(),
            input: .init(markers: [10], texts: [text])
        )

        XCTAssertEqual(cache.sizeVariantCache.capacity, 10)
        XCTAssertFalse(cache.exhaustedWidthVariants)
        XCTAssertEqual(cache.resultCache.count, 1)
        XCTAssertEqual(
            cache.sizeVariant(for: ProposedViewSize(width: 50, height: 50)),
            .regular
        )
        XCTAssertEqual(
            cache.withValue(for: ProposedViewSize(width: 50, height: 50)) {
                $0.engine.marker
            },
            10
        )

        cache.setInput(.init(markers: [20], texts: [text]), changed: false)
        XCTAssertEqual(cache.withValue(for: .unspecified) { $0.engine.marker }, 10)
        cache.setInput(.init(markers: [20], texts: [text]), changed: true)
        XCTAssertEqual(cache.withValue(for: .unspecified) { $0.engine.marker }, 20)
    }

    func testCacheLazilyAppendsNarrowerVariantsUntilOneFits() {
        let regular = makeVariantText()
        let compact = makeVariantText()
        let small = makeVariantText()

        let cache = SizeFittingTextCache(
            resolver: TextVariantTestResolver(sizeVariant: .regular),
            logic: StickyTextSizeFittingLogic(),
            input: .init(
                markers: [180, 120, 72],
                texts: [regular, compact, small]
            )
        )

        XCTAssertEqual(cache.resultCache.count, 1)
        XCTAssertEqual(
            cache.sizeVariant(for: ProposedViewSize(width: 130, height: nil)),
            .compact
        )
        XCTAssertEqual(cache.resultCache.count, 2)
        XCTAssertEqual(
            cache.sizeVariant(for: ProposedViewSize(width: 80, height: nil)),
            .small
        )
        XCTAssertEqual(cache.resultCache.count, 3)
        XCTAssertFalse(cache.exhaustedWidthVariants)
    }

    func testCacheRecordsExhaustedWidthWhenNarrowerResultIsNotUnique() {
        let regular = makeVariantText()
        let compact = makeVariantText(unique: false)

        let cache = SizeFittingTextCache(
            resolver: TextVariantTestResolver(sizeVariant: .regular),
            logic: StickyTextSizeFittingLogic(),
            input: .init(markers: [180, 120], texts: [regular, compact])
        )

        XCTAssertEqual(
            cache.sizeVariant(for: ProposedViewSize(width: 60, height: nil)),
            .compact
        )
        XCTAssertTrue(cache.exhaustedWidthVariants)
        XCTAssertNil(regular.smallerSizeVariant)
        XCTAssertNil(compact.largerSizeVariant)
    }

    func testNonUniqueRootDoesNotCreateANarrowerResolver() {
        let regular = makeVariantText(unique: false)
        let cache = SizeFittingTextCache(
            resolver: TextVariantTestResolver(sizeVariant: .regular),
            logic: StickyTextSizeFittingLogic(),
            input: .init(markers: [180], texts: [regular])
        )

        XCTAssertEqual(
            cache.sizeVariant(for: ProposedViewSize(width: 60, height: nil)),
            .regular
        )
        XCTAssertEqual(cache.resultCache.count, 1)
        XCTAssertTrue(cache.exhaustedWidthVariants)
    }

    func testResolvedTextHelperTraversesResolverCandidatesWithoutPublishingLinks() {
        let regular = makeVariantText()
        let compact = makeVariantText()
        let terminal = makeVariantText(unique: false)
        regular.setSizeVariantCandidates([regular, compact, terminal])
        let input = ResolvedTextHelper.Input(text: regular, renderer: nil)

        XCTAssertNil(regular.smallerSizeVariant)
        XCTAssertNil(compact.largerSizeVariant)
        XCTAssertTrue(ResolvedTextHelper(sizeVariant: .regular).value(for: input).text === regular)
        XCTAssertTrue(ResolvedTextHelper(sizeVariant: .compact).value(for: input).text === compact)
        XCTAssertTrue(ResolvedTextHelper(sizeVariant: .small).value(for: input).text === terminal)
    }

    func testSizeFittingFilterLeavesNonStandaloneCandidatesUnlinked() {
        let regular = makeVariantText()
        let compact = makeVariantText()
        let terminal = makeVariantText(unique: false)
        regular.setSizeVariantCandidates([regular, compact, terminal])

        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let text = graph.makeInput(value: regular)
            let size = graph.makeInput(value: ViewSize(width: 200, height: 40))
            let cache = SizeFittingTextCache(
                resolver: ResolvedTextHelper(),
                logic: StickyTextSizeFittingLogic(),
                input: ResolvedTextHelper.Input(text: regular, renderer: nil)
            )
            let output = graph.makeStatefulRule(
                SizeFittingTextFilter(
                    size: size,
                    text: text,
                    environment: graph.makeInput(value: EnvironmentValues()),
                    isArchived: false,
                    cache: cache
                )
            )

            XCTAssertTrue(output.value === regular)
            XCTAssertNil(regular.smallerSizeVariant)
            XCTAssertNil(compact.largerSizeVariant)
            XCTAssertNil(compact.smallerSizeVariant)
            XCTAssertNil(terminal.largerSizeVariant)
        }
    }

    func testSizeFittingFilterLinksOnlyStandaloneCandidatesAfterSelection() {
        let regular = makeVariantText()
        let compact = makeVariantText()
        compact.features.insert(.isStandaloneSizeVariant)
        let terminal = makeVariantText(unique: false)
        terminal.features.insert(.isStandaloneSizeVariant)
        regular.setSizeVariantCandidates([regular, compact, terminal])

        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let text = graph.makeInput(value: regular)
            let size = graph.makeInput(value: ViewSize(width: 200, height: 40))
            let cache = SizeFittingTextCache(
                resolver: ResolvedTextHelper(),
                logic: StickyTextSizeFittingLogic(),
                input: ResolvedTextHelper.Input(text: regular, renderer: nil)
            )
            let output = graph.makeStatefulRule(
                SizeFittingTextFilter(
                    size: size,
                    text: text,
                    environment: graph.makeInput(value: EnvironmentValues()),
                    isArchived: false,
                    cache: cache
                )
            )

            XCTAssertTrue(output.value === regular)
            XCTAssertTrue(regular.smallerSizeVariant === compact)
            XCTAssertTrue(compact.largerSizeVariant === regular)
            XCTAssertTrue(compact.smallerSizeVariant === terminal)
            XCTAssertTrue(terminal.largerSizeVariant === compact)
        }
    }

    func testHorizontalGrowthReconsidersTheRegularVariant() {
        let regular = makeVariantText()
        let compact = makeVariantText()

        let cache = SizeFittingTextCache(
            resolver: TextVariantTestResolver(sizeVariant: .regular),
            logic: StickyTextSizeFittingLogic(),
            input: .init(markers: [180, 100], texts: [regular, compact])
        )

        XCTAssertEqual(
            cache.sizeVariant(for: ProposedViewSize(width: 120, height: nil)),
            .compact
        )
        XCTAssertEqual(
            cache.sizeVariant(for: ProposedViewSize(width: 220, height: nil)),
            .regular
        )
    }

    func testTextMakeViewUsesDedicatedSizeFittingLayoutEngineOnlyWhenFlagIsEnabled() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let view = graph.makeInput(value: Text("variant"))

            var ordinaryInputs = makeViewInputs(graph: graph)
            ordinaryInputs.base[VariantThatFitsFlag.self] = false
            let ordinary = Text._makeView(
                view: _GraphValue(_attribute: view),
                inputs: ordinaryInputs
            )
            let ordinaryComputer = ordinary._layoutComputer.attribute!.value
            XCTAssertTrue(ordinaryComputer.box is LayoutEngineBox<ClosureLayoutEngine>)

            var sizeDependentInputs = makeViewInputs(graph: graph)
            sizeDependentInputs.base[VariantThatFitsFlag.self] = true
            let sizeDependent = Text._makeView(
                view: _GraphValue(_attribute: view),
                inputs: sizeDependentInputs
            )
            let sizeDependentComputer = sizeDependent._layoutComputer.attribute!.value
            XCTAssertTrue(
                sizeDependentComputer.box is LayoutEngineBox<SizeFittingTextLayoutComputer.Engine>
            )
            XCTAssertEqual(sizeDependentComputer.sizeThatFits(.unspecified), .zero)
        }
    }

    private func makeView<Content>(_ content: Content) where Content: View {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let view = graph.makeInput(value: content)
            _ = Content._makeView(
                view: _GraphValue(_attribute: view),
                inputs: makeViewInputs(graph: graph)
            )
        }
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        return _ViewInputs(
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
            position: graph.makeInput(value: .zero),
            containerPosition: graph.makeInput(value: .zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
