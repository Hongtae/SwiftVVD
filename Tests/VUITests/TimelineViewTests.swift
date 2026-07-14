import XCTest
@testable import VUI

private struct TimelineProbeSchedule: TimelineSchedule {
    var interval: TimeInterval

    func entries(
        from startDate: Date,
        mode: TimelineScheduleMode
    ) -> [Date] {
        [
            startDate,
            startDate.addingTimeInterval(interval),
            startDate.addingTimeInterval(interval * 2),
        ]
    }
}

private struct TimelineProbeView: View, TestPrimitiveView {
    var date: Date
    var cadence: TimelineViewDefaultContext.Cadence

    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        let layout = graph.makeRule {
            let value = view._attribute.value
            let height: CGFloat
            switch value.cadence {
            case .live: height = 0
            case .seconds: height = 1
            case .minutes: height = 2
            }
            return LayoutComputer.fixed(
                CGSize(
                    width: value.date.timeIntervalSinceReferenceDate,
                    height: height
                )
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

final class TimelineViewTests: XCTestCase {
    // ASSERTIONS timelineFieldMetadataObserved
    // ASSERTIONS timelineViewPublicSurfaceObserved
    func testObservedStorageShapesAndCadenceOrdering() throws {
        XCTAssertTrue(
            PeriodicTimelineSchedule.Entries.Element.self == Date.self
        )
        XCTAssertTrue(
            PeriodicTimelineSchedule.Entries.Iterator.self ==
                PeriodicTimelineSchedule.Entries.self
        )
        XCTAssertTrue(
            EveryMinuteTimelineSchedule.Entries.Element.self == Date.self
        )
        XCTAssertTrue(
            EveryMinuteTimelineSchedule.Entries.Iterator.self ==
                EveryMinuteTimelineSchedule.Entries.self
        )
        XCTAssertTrue(
            AnimationTimelineSchedule.Entries.Element.self == Date.self
        )
        XCTAssertTrue(
            AnimationTimelineSchedule.Entries.Iterator.self ==
                AnimationTimelineSchedule.Entries.self
        )

        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let periodic = PeriodicTimelineSchedule(from: origin, by: 10)
        XCTAssertEqual(Mirror(reflecting: periodic).children.map(\.label), [
            "date",
            "interval",
        ])
        XCTAssertEqual(MemoryLayout<PeriodicTimelineSchedule>.size, 16)

        var periodicEntries = periodic.entries(from: origin, mode: .normal)
        XCTAssertEqual(Mirror(reflecting: periodicEntries).children.map(\.label), [
            "date",
            "interval",
        ])
        XCTAssertNotNil(periodicEntries.next())

        let everyMinute = EveryMinuteTimelineSchedule()
        XCTAssertTrue(Mirror(reflecting: everyMinute).children.isEmpty)
        var minuteEntries = everyMinute.entries(from: origin, mode: .normal)
        XCTAssertEqual(Mirror(reflecting: minuteEntries).children.map(\.label), [
            "nextDate",
        ])
        XCTAssertNotNil(minuteEntries.next())

        let explicit = ExplicitTimelineSchedule([origin])
        XCTAssertEqual(Mirror(reflecting: explicit).children.map(\.label), ["entries"])

        let animation = AnimationTimelineSchedule()
        XCTAssertEqual(Mirror(reflecting: animation).children.map(\.label), [
            "minimumInterval",
            "paused",
        ])
        XCTAssertEqual(animation.minimumInterval, 1.0 / 120.0, accuracy: 0.000_000_001)
        XCTAssertFalse(animation.paused)
        let animationEntries = animation.entries(from: origin, mode: .normal)
        XCTAssertEqual(Mirror(reflecting: animationEntries).children.map(\.label), [
            "date",
            "interval",
        ])
        let timeline = TimelineView(.periodic(from: origin, by: 1)) { context in
            TimelineProbeView(date: context.date, cadence: context.cadence)
        }
        XCTAssertEqual(Mirror(reflecting: timeline).children.map(\.label), [
            "schedule",
            "content",
        ])
        XCTAssertLessThan(
            TimelineViewDefaultContext.Cadence.live,
            .seconds
        )
        XCTAssertLessThan(
            TimelineViewDefaultContext.Cadence.seconds,
            .minutes
        )
        XCTAssertEqual(MemoryLayout<TimelineViewDefaultContext>.size, 9)
        XCTAssertEqual(MemoryLayout<TimelineViewDefaultContext>.stride, 16)
    }

    // ASSERTIONS timelineScheduleRuntimeObserved
    func testScheduleEntrySemanticsMatchObservedRuntime() throws {
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let periodic = PeriodicTimelineSchedule(from: origin, by: 10)

        XCTAssertEqual(
            offsets(periodic.entries(from: origin.addingTimeInterval(-5), mode: .normal), origin: origin),
            [0, 10, 20, 30]
        )
        XCTAssertEqual(
            offsets(periodic.entries(from: origin.addingTimeInterval(10.25), mode: .normal), origin: origin),
            [10, 20, 30, 40]
        )
        XCTAssertEqual(
            offsets(periodic.entries(from: origin.addingTimeInterval(19.99), mode: .lowFrequency), origin: origin),
            [10, 20, 30, 40]
        )

        let minute = EveryMinuteTimelineSchedule()
        XCTAssertEqual(
            offsets(minute.entries(from: origin, mode: .normal), origin: origin),
            [-40, 20, 80, 140]
        )
        XCTAssertEqual(
            offsets(minute.entries(from: origin.addingTimeInterval(79.75), mode: .lowFrequency), origin: origin),
            [20, 80, 140, 200]
        )

        let explicitDates = [
            origin.addingTimeInterval(-1),
            origin.addingTimeInterval(4),
        ]
        let explicit = ExplicitTimelineSchedule(explicitDates)
        XCTAssertEqual(
            Array(explicit.entries(from: origin.addingTimeInterval(100), mode: .lowFrequency)),
            explicitDates
        )

        var animation = AnimationTimelineSchedule()
            .entries(from: origin, mode: .normal)
        XCTAssertEqual(try XCTUnwrap(animation.next()), origin)
        XCTAssertEqual(
            try XCTUnwrap(animation.next()).timeIntervalSince(origin),
            1.0 / 120.0,
            accuracy: 0.000_000_001
        )

        var zero = AnimationTimelineSchedule(minimumInterval: 0)
            .entries(from: origin, mode: .normal)
        XCTAssertEqual(zero.next(), origin)
        XCTAssertEqual(zero.next(), origin)

        var paused = AnimationTimelineSchedule(paused: true)
            .entries(from: origin, mode: .normal)
        XCTAssertNil(paused.next())

        var lowFrequency = AnimationTimelineSchedule()
            .entries(from: origin, mode: .lowFrequency)
        XCTAssertNil(lowFrequency.next())
    }

    // ASSERTIONS timelineViewRuntimeObserved
    // ASSERTIONS timelineViewGraphSchedulingDisassemblyObserved
    func testGraphRulePublishesDatesAndSchedulesTheNextEntry() throws {
        try withTimelineHost { viewGraph, graph in
            let referenceDate = graph.makeInput(
                value: Optional(Date(timeIntervalSinceReferenceDate: 2_000))
            )
            let timeline = TimelineView(TimelineProbeSchedule(interval: 5)) { context in
                TimelineProbeView(date: context.date, cadence: context.cadence)
            }
            let source = graph.makeInput(value: timeline)
            let (inputs, time, phase) = makeViewInputs(
                graph: graph,
                referenceDate: referenceDate.asWeak()
            )
            let outputs = type(of: timeline)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: inputs
            )

            func sample() throws -> CGSize {
                let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
                return layout.sizeThatFits(.unspecified)
            }

            viewGraph.nextUpdate.views = ViewGraph.NextUpdate()
            XCTAssertEqual(try sample(), CGSize(width: 2_000, height: 0))
            XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 5, accuracy: 0.000_001)

            referenceDate.setValue(Date(timeIntervalSinceReferenceDate: 2_005))
            time.setValue(Time(seconds: 5))
            viewGraph.nextUpdate.views = ViewGraph.NextUpdate()
            XCTAssertEqual(try sample(), CGSize(width: 2_005, height: 0))
            XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 10, accuracy: 0.000_001)

            source.setValue(
                TimelineView(TimelineProbeSchedule(interval: 2)) { context in
                    TimelineProbeView(date: context.date, cadence: context.cadence)
                }
            )
            viewGraph.nextUpdate.views = ViewGraph.NextUpdate()
            XCTAssertEqual(try sample(), CGSize(width: 2_005, height: 0))
            XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 7, accuracy: 0.000_001)

            referenceDate.setValue(Date(timeIntervalSinceReferenceDate: 2_010))
            var reset = Phase()
            reset.resetSeed = 1
            phase.setValue(reset)
            time.setValue(Time(seconds: 10))
            viewGraph.nextUpdate.views = ViewGraph.NextUpdate()
            XCTAssertEqual(try sample(), CGSize(width: 2_010, height: 0))
            XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 12, accuracy: 0.000_001)
        }
    }

    private func offsets<S: Sequence>(
        _ entries: S,
        origin: Date
    ) -> [TimeInterval] where S.Element == Date {
        Array(entries.prefix(4)).map { $0.timeIntervalSince(origin) }
    }

    private func makeViewInputs(
        graph: _AGGraph,
        referenceDate: WeakAttribute<Date?>
    ) -> (
        inputs: _ViewInputs,
        time: Attribute<Time>,
        phase: Attribute<Phase>
    ) {
        let environment = graph.makeInput(value: EnvironmentValues())
        let time = graph.makeInput(value: Time(seconds: 0))
        let phase = graph.makeInput(value: Phase())
        let base = _GraphInputs(
            customInputs: PropertyList(),
            time: time,
            cachedEnvironment: MutableBox(
                CachedEnvironment(environment: environment)
            ),
            phase: phase,
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
        var inputs = _ViewInputs(
            base: base,
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
            stackOrientation: nil
        )
        inputs[ReferenceDateInput.self] = referenceDate
        return (inputs, time, phase)
    }

    private func withTimelineHost(
        _ body: (ViewGraph, _AGGraph) throws -> Void
    ) rethrows {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        try viewGraph.data.withCurrent {
            try body(viewGraph, viewGraph.data.graph)
        }
    }
}
