import XCTest
@testable import VUI

private struct TrackerDependencyNameKey: EnvironmentKey {
    static let defaultValue = "default-name"
}

private struct TrackerDependencyStatusKey: EnvironmentKey {
    static let defaultValue = "default-status"
}

final class PropertyListTrackerDependencyTests: XCTestCase {
    func testTrackedEnvironmentSetterInvalidatesOnlyWrittenKey() {
        var list = PropertyList()
        list[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "source"
        list[EnvironmentPropertyKey<TrackerDependencyStatusKey>.self] = "destination"
        let tracker = _PropertyListTracker()
        var values = EnvironmentValues(list, tracker: tracker)

        XCTAssertEqual(values[TrackerDependencyNameKey.self], "source")

        values[TrackerDependencyStatusKey.self] = "changed-status"

        XCTAssertFalse(tracker.hasDifferentUsedValues(values._plist))

        values[TrackerDependencyNameKey.self] = "changed-name"

        XCTAssertTrue(tracker.hasDifferentUsedValues(values._plist))
    }

    func testTrackingCopyStartsFreshTrackerWithoutSharingParentReads() {
        var parentList = PropertyList()
        parentList[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "parent"
        let parentTracker = _PropertyListTracker()
        let parentValues = EnvironmentValues(parentList, tracker: parentTracker)
        XCTAssertEqual(parentValues[TrackerDependencyNameKey.self], "parent")

        var childValues = parentValues.trackingCopy()
        childValues[TrackerDependencyStatusKey.self] = "child"

        XCTAssertFalse(parentTracker.hasDifferentUsedValues(parentList))
        XCTAssertFalse(childValues.tracker!.hasDifferentUsedValues(childValues._plist))

        var changedUnreadChildList = childValues._plist
        changedUnreadChildList[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "changed"

        XCTAssertFalse(childValues.tracker!.hasDifferentUsedValues(changedUnreadChildList))
        XCTAssertEqual(childValues[TrackerDependencyNameKey.self], "parent")

        XCTAssertTrue(childValues.tracker!.hasDifferentUsedValues(changedUnreadChildList))
    }

    func testMergedEnvironmentReturnsFreshTrackedMergedValues() {
        let graph = _AGGraph()
        var mergedValues: EnvironmentValues!

        _AGGraph.withCurrent(graph) {
            var primaryList = PropertyList()
            primaryList[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "primary"
            let primaryValues = EnvironmentValues.tracking(primaryList)

            var fallbackList = PropertyList()
            fallbackList[EnvironmentPropertyKey<TrackerDependencyStatusKey>.self] = "fallback"
            let fallbackValues = EnvironmentValues.tracking(fallbackList)

            let primaryAttr = graph.makeInput(value: primaryValues)
            let fallbackAttr = graph.makeInput(value: fallbackValues)
            let mergedAttr: Attribute<EnvironmentValues> = graph.makeRule(
                MergedEnvironment(
                    selfWeak: primaryAttr.asWeak().base,
                    otherRaw: fallbackAttr.identifier.rawValue
                )
            )

            mergedValues = mergedAttr.value
        }

        XCTAssertNotNil(mergedValues.tracker)
        XCTAssertFalse(mergedValues.tracker!.hasDifferentUsedValues(mergedValues._plist))
        XCTAssertEqual(mergedValues[TrackerDependencyNameKey.self], "primary")
        XCTAssertEqual(mergedValues[TrackerDependencyStatusKey.self], "fallback")

        var changedList = mergedValues._plist
        changedList[EnvironmentPropertyKey<TrackerDependencyStatusKey>.self] = "changed"

        XCTAssertTrue(mergedValues.tracker!.hasDifferentUsedValues(changedList))
    }

    func testTrackerUnionNoopsWhenTrackedIDsMatch() {
        var list = PropertyList()
        list[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "source"
        let source = _PropertyListTracker()
        source.initializeValues(from: list)
        XCTAssertEqual(source.value(list, for: EnvironmentPropertyKey<TrackerDependencyNameKey>.self), "source")

        let destination = _PropertyListTracker()
        destination.initializeValues(from: list)
        destination.formUnion(source)

        var changed = list
        changed[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "changed"

        XCTAssertFalse(destination.hasDifferentUsedValues(changed))
    }

    func testEnvironmentAddDependenciesCopiesSourceTrackerReads() {
        var sourceList = PropertyList()
        sourceList[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "source"
        let sourceTracker = _PropertyListTracker()
        let sourceValues = EnvironmentValues(sourceList, tracker: sourceTracker)
        XCTAssertEqual(sourceValues[TrackerDependencyNameKey.self], "source")

        var destinationList = PropertyList()
        destinationList[EnvironmentPropertyKey<TrackerDependencyStatusKey>.self] = "destination"
        let destinationTracker = _PropertyListTracker()
        let destinationValues = EnvironmentValues(destinationList, tracker: destinationTracker)

        destinationValues.addDependencies(from: sourceTracker)

        XCTAssertFalse(destinationTracker.hasDifferentUsedValues(sourceList))

        var changedSourceList = sourceList
        changedSourceList[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "changed"

        XCTAssertTrue(destinationTracker.hasDifferentUsedValues(changedSourceList))
    }

    func testEnvironmentAddDependenciesPreservesDestinationReadForDuplicateKey() {
        var sourceList = PropertyList()
        sourceList[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "source"
        let sourceTracker = _PropertyListTracker()
        let sourceValues = EnvironmentValues(sourceList, tracker: sourceTracker)
        XCTAssertEqual(sourceValues[TrackerDependencyNameKey.self], "source")

        var destinationList = PropertyList()
        destinationList[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "destination"
        let destinationTracker = _PropertyListTracker()
        let destinationValues = EnvironmentValues(destinationList, tracker: destinationTracker)
        XCTAssertEqual(destinationValues[TrackerDependencyNameKey.self], "destination")

        destinationValues.addDependencies(from: sourceTracker)

        var changedSourceList = sourceList
        changedSourceList[EnvironmentPropertyKey<TrackerDependencyStatusKey>.self] = "unrelated"

        XCTAssertTrue(destinationTracker.hasDifferentUsedValues(changedSourceList))
        XCTAssertFalse(destinationTracker.hasDifferentUsedValues(destinationList))
    }

    func testEnvironmentAddDependenciesWithoutDestinationTrackerIsNoop() {
        var sourceList = PropertyList()
        sourceList[EnvironmentPropertyKey<TrackerDependencyNameKey>.self] = "source"
        let sourceTracker = _PropertyListTracker()
        let sourceValues = EnvironmentValues(sourceList, tracker: sourceTracker)
        XCTAssertEqual(sourceValues[TrackerDependencyNameKey.self], "source")

        let destinationValues = EnvironmentValues()
        destinationValues.addDependencies(from: sourceTracker)

        XCTAssertEqual(destinationValues[TrackerDependencyNameKey.self], "default-name")
    }
}
