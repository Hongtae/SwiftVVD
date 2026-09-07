import XCTest
@testable import VUI

private struct DerivedLookupPrimaryKey: PropertyKey {
    static let defaultValue = "default"
}

private struct DerivedLookupSecondaryKey: PropertyKey {
    static let defaultValue = 0
}

private struct DerivedLookupBaseKey: PropertyKey {
    static let defaultValue = 1
}

private struct DerivedLookupComputedKey: DerivedPropertyKey {
    static func value(in plist: PropertyList) -> Int {
        plist[DerivedLookupBaseKey.self] * 3
    }
}

private struct DerivedLookupEnvironmentKey: EnvironmentKey {
    static let defaultValue = "environment-default"
}

private final class DerivedEnvironmentCounter {
    var value = 0
}

private struct DerivedEnvironmentCounterKey: EnvironmentKey {
    static var defaultValue: DerivedEnvironmentCounter? { nil }
}

private struct CountedDerivedEnvironmentKey: DerivedEnvironmentKey {
    static func value(in environment: EnvironmentValues) -> Int {
        XCTAssertNil(environment.tracker)
        environment[DerivedEnvironmentCounterKey.self]?.value += 1
        return environment[DerivedLookupEnvironmentKey.self].count
    }
}

private struct SecondaryToPrimaryLookup: PropertyKeyLookup {
    typealias Primary = DerivedLookupPrimaryKey
    typealias Secondary = DerivedLookupSecondaryKey

    static func lookup(in value: Int) -> String? {
        value > 0 ? "secondary-\(value)" : nil
    }
}

final class PropertyListDerivedLookupTests: XCTestCase {
    // ASSERTIONS canvasTextLayoutDerivedEnvironmentObserved
    func testDerivedEnvironmentAdapterCachesAggregateWithoutTrackingItsInputReads() throws {
        let counter = DerivedEnvironmentCounter()
        var original = EnvironmentValues()
        original[DerivedEnvironmentCounterKey.self] = counter
        original[DerivedLookupEnvironmentKey.self] = "first"
        var environment = original.trackingCopy()
        let tracker = try XCTUnwrap(environment.tracker)
        XCTAssertEqual(environment[CountedDerivedEnvironmentKey.self], 5)
        XCTAssertEqual(environment[CountedDerivedEnvironmentKey.self], 5)
        XCTAssertEqual(counter.value, 1)

        var equivalent = original
        equivalent[DerivedLookupEnvironmentKey.self] = "other"
        XCTAssertFalse(tracker.hasDifferentUsedValues(equivalent._plist))
        var different = original
        different[DerivedLookupEnvironmentKey.self] = "longer"
        XCTAssertTrue(tracker.hasDifferentUsedValues(different._plist))

        environment[DerivedLookupEnvironmentKey.self] = "updated"
        XCTAssertEqual(environment[CountedDerivedEnvironmentKey.self], 7)
        let beforeRepeat = counter.value
        XCTAssertEqual(environment[CountedDerivedEnvironmentKey.self], 7)
        XCTAssertEqual(counter.value, beforeRepeat)

        let untracked = original.untrackedCopy()
        let beforeUntracked = counter.value
        XCTAssertEqual(untracked[CountedDerivedEnvironmentKey.self], 5)
        XCTAssertEqual(untracked[CountedDerivedEnvironmentKey.self], 5)
        XCTAssertEqual(counter.value, beforeUntracked + 2)
    }

    func testDerivedPropertyKeySubscriptComputesFromPropertyList() {
        var plist = PropertyList()

        XCTAssertEqual(plist[DerivedLookupComputedKey.self], 3)

        plist[DerivedLookupBaseKey.self] = 4

        XCTAssertEqual(plist[DerivedLookupComputedKey.self], 12)
    }

    func testSecondaryLookupUsesSecondaryValueWhenPrimaryIsMissing() {
        var plist = PropertyList()
        plist[DerivedLookupSecondaryKey.self] = 2

        XCTAssertEqual(plist.valueWithSecondaryLookup(SecondaryToPrimaryLookup.self), "secondary-2")
    }

    func testSecondaryLookupReturnsDefaultWhenNoPrimaryOrMatchingSecondaryExists() {
        var plist = PropertyList()
        plist[DerivedLookupSecondaryKey.self] = 0

        XCTAssertEqual(plist.valueWithSecondaryLookup(SecondaryToPrimaryLookup.self), "default")
    }

    func testSecondaryLookupFallsThroughToLowerPriorityPrimaryWhenLookupReturnsNil() {
        var plist = PropertyList()
        plist[DerivedLookupPrimaryKey.self] = "primary"
        plist[DerivedLookupSecondaryKey.self] = 0

        XCTAssertEqual(plist.valueWithSecondaryLookup(SecondaryToPrimaryLookup.self), "primary")
    }

    func testSecondaryLookupUsesFirstMatchingEntryInPropertyListOrder() {
        var plist = PropertyList()
        plist[DerivedLookupPrimaryKey.self] = "primary"
        plist[DerivedLookupSecondaryKey.self] = 5

        XCTAssertEqual(plist.valueWithSecondaryLookup(SecondaryToPrimaryLookup.self), "secondary-5")
    }

    func testTrackerCachesPrimaryValuesAndDetectsInvalidatedChanges() {
        var old = PropertyList()
        old[DerivedLookupPrimaryKey.self] = "old"
        let tracker = _PropertyListTracker()
        tracker.initializeValues(from: old)

        XCTAssertEqual(tracker.value(old, for: DerivedLookupPrimaryKey.self), "old")
        XCTAssertFalse(tracker.hasDifferentUsedValues(old))

        var new = old
        new[DerivedLookupPrimaryKey.self] = "new"
        tracker.invalidateValue(for: DerivedLookupPrimaryKey.self, from: old, to: new)

        XCTAssertTrue(tracker.hasDifferentUsedValues(new))
    }

    func testTrackerMovesDerivedValuesToPendingWhenPrimaryKeyInvalidates() {
        var old = PropertyList()
        old[DerivedLookupBaseKey.self] = 2
        let tracker = _PropertyListTracker()
        tracker.initializeValues(from: old)

        XCTAssertEqual(tracker.derivedValue(old, for: DerivedLookupComputedKey.self), 6)

        var new = old
        new[DerivedLookupBaseKey.self] = 3
        tracker.invalidateValue(for: DerivedLookupBaseKey.self, from: old, to: new)

        XCTAssertTrue(tracker.hasDifferentUsedValues(new))
    }

    func testTrackerStoresSecondaryLookupValuesInPrimaryDictionaryLane() {
        var old = PropertyList()
        old[DerivedLookupSecondaryKey.self] = 2
        let tracker = _PropertyListTracker()
        tracker.initializeValues(from: old)

        XCTAssertEqual(
            tracker.valueWithSecondaryLookup(old, secondaryLookupHandler: SecondaryToPrimaryLookup.self),
            "secondary-2"
        )

        XCTAssertEqual(tracker.value(old, for: DerivedLookupPrimaryKey.self), "secondary-2")

        var new = old
        new[DerivedLookupPrimaryKey.self] = "primary"
        tracker.invalidateValue(for: DerivedLookupPrimaryKey.self, from: old, to: new)

        XCTAssertTrue(tracker.hasDifferentUsedValues(new))
    }

    func testTrackerPrimaryCacheFeedsSecondaryLookupLane() {
        var plist = PropertyList()
        plist[DerivedLookupSecondaryKey.self] = 2
        let tracker = _PropertyListTracker()
        tracker.initializeValues(from: plist)

        XCTAssertEqual(tracker.value(plist, for: DerivedLookupPrimaryKey.self), "default")
        XCTAssertEqual(
            tracker.valueWithSecondaryLookup(plist, secondaryLookupHandler: SecondaryToPrimaryLookup.self),
            "default"
        )
    }

    func testTrackerUnionCopiesSourceIntoEmptyDestinationWithoutDirtying() {
        var sourceList = PropertyList()
        sourceList[DerivedLookupPrimaryKey.self] = "source"
        let source = _PropertyListTracker()
        source.initializeValues(from: sourceList)
        XCTAssertEqual(source.value(sourceList, for: DerivedLookupPrimaryKey.self), "source")

        let destination = _PropertyListTracker()
        destination.formUnion(source)

        XCTAssertFalse(destination.hasDifferentUsedValues(sourceList))
        XCTAssertEqual(destination.value(sourceList, for: DerivedLookupPrimaryKey.self), "source")
    }

    func testTrackerUnionAdoptsSourceIDWhenDestinationAlreadyHasDifferentID() {
        var sourceList = PropertyList()
        sourceList[DerivedLookupPrimaryKey.self] = "source"
        let source = _PropertyListTracker()
        source.initializeValues(from: sourceList)
        XCTAssertEqual(source.value(sourceList, for: DerivedLookupPrimaryKey.self), "source")

        var destinationList = PropertyList()
        destinationList[DerivedLookupBaseKey.self] = 9
        let destination = _PropertyListTracker()
        destination.initializeValues(from: destinationList)
        destination.formUnion(source)

        XCTAssertFalse(destination.hasDifferentUsedValues(sourceList))
        XCTAssertEqual(destination.value(sourceList, for: DerivedLookupPrimaryKey.self), "source")
    }

    func testEnvironmentValuesReadsThroughTrackerWhenPresent() {
        var plist = PropertyList()
        plist[EnvironmentPropertyKey<DerivedLookupEnvironmentKey>.self] = "tracked"
        let tracker = _PropertyListTracker()
        let values = EnvironmentValues(plist, tracker: tracker)

        XCTAssertEqual(values[DerivedLookupEnvironmentKey.self], "tracked")
        XCTAssertFalse(tracker.hasDifferentUsedValues(plist))

        var changed = plist
        changed[EnvironmentPropertyKey<DerivedLookupEnvironmentKey>.self] = "changed"
        tracker.invalidateValue(
            for: EnvironmentPropertyKey<DerivedLookupEnvironmentKey>.self,
            from: plist,
            to: changed
        )

        XCTAssertTrue(tracker.hasDifferentUsedValues(changed))
    }
}
