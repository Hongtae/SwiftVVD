import XCTest
@testable import VUI

final class AGValueComparisonTests: XCTestCase {
    func testNodeCreationReadsTheDeclaredBodyComparisonMode() {
        ComparisonModeReads.rule = 0
        ComparisonModeReads.statefulRule = 0
        ComparisonModeReads.lowLevelBody = 0

        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            _ = graph.makeRule(ComparisonModeRule())
            _ = graph.makeStatefulRule(ComparisonModeStatefulRule())
            let _: Attribute<Int> = graph.makeLowLevelAttribute(
                body: ComparisonModeLowLevelBody(),
                value: 0,
                flags: []
            ) { _, _ in }
        }

        XCTAssertEqual(ComparisonModeReads.rule, 1)
        XCTAssertEqual(ComparisonModeReads.statefulRule, 1)
        XCTAssertEqual(ComparisonModeReads.lowLevelBody, 1)
        XCTAssertEqual(DefaultComparisonModeRule.comparisonMode.rawValue, 2)
        XCTAssertEqual(_External.comparisonMode.rawValue, 3)
    }

    func testLayoutComparisonUsesStoredRepresentationAndReferenceIdentity() {
        for rawValue: UInt32 in [2, 3, 0x102, 0x103] {
            let options = AGComparisonOptions(rawValue: rawValue)

            XCTAssertTrue(
                _AGGraph.compareValues(
                    ComparisonPayload.payload(7),
                    ComparisonPayload.payload(7),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ComparisonPayload.payload(7),
                    ComparisonPayload.payload(8),
                    options: options
                )
            )

            let reference = ComparisonReference(1)
            let alias = reference
            let other = ComparisonReference(1)
            XCTAssertTrue(
                _AGGraph.compareValues(
                    WeakComparisonPayload(object: reference),
                    WeakComparisonPayload(object: alias),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    WeakComparisonPayload(object: reference),
                    WeakComparisonPayload(object: other),
                    options: options
                )
            )

            let closure: () -> Int = { 1 }
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ClosureComparisonPayload(body: closure),
                    ClosureComparisonPayload(body: closure),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ClosureComparisonPayload(body: { 1 }),
                    ClosureComparisonPayload(body: { 1 }),
                    options: options
                )
            )

        }
    }

    func testModeTwoLayoutComparisonIgnoresPaddingBytes() {
        let lhs = makePaddedComparisonPointer(fill: 0x11, byte: 7, word: 42)
        let differentPadding = makePaddedComparisonPointer(
            fill: 0xee,
            byte: 7,
            word: 42
        )
        let changedField = makePaddedComparisonPointer(fill: 0x11, byte: 8, word: 42)
        defer {
            lhs.deinitialize(count: 1)
            lhs.deallocate()
            differentPadding.deinitialize(count: 1)
            differentPadding.deallocate()
            changedField.deinitialize(count: 1)
            changedField.deallocate()
        }

        for rawValue: UInt32 in [2, 0x102] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareStoredValues(
                    lhs,
                    differentPadding,
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareStoredValues(lhs, changedField, options: options)
            )
        }
        for rawValue: UInt32 in [3, 0x103] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareStoredValues(lhs, lhs, options: options)
            )
            XCTAssertFalse(
                _AGGraph.compareStoredValues(
                    lhs,
                    differentPadding,
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareStoredValues(lhs, changedField, options: options)
            )
        }
    }

    func testExistentialUnusedStorageFollowsTheComparisonMode() {
        let lhs = makeExistentialComparisonPointer(fill: 0x11, value: 7)
        let sameStorage = makeExistentialComparisonPointer(fill: 0x11, value: 7)
        let differentUnusedStorage = makeExistentialComparisonPointer(
            fill: 0xee,
            value: 7
        )
        let differentValue = makeExistentialComparisonPointer(fill: 0x11, value: 8)
        defer {
            lhs.deinitialize(count: 1)
            lhs.deallocate()
            sameStorage.deinitialize(count: 1)
            sameStorage.deallocate()
            differentUnusedStorage.deinitialize(count: 1)
            differentUnusedStorage.deallocate()
            differentValue.deinitialize(count: 1)
            differentValue.deallocate()
        }

        for rawValue: UInt32 in [2, 0x102] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareStoredValues(lhs, sameStorage, options: options)
            )
            XCTAssertTrue(
                _AGGraph.compareStoredValues(
                    lhs,
                    differentUnusedStorage,
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareStoredValues(lhs, differentValue, options: options)
            )
        }
        for rawValue: UInt32 in [3, 0x103] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareStoredValues(lhs, sameStorage, options: options)
            )
            XCTAssertFalse(
                _AGGraph.compareStoredValues(
                    lhs,
                    differentUnusedStorage,
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareStoredValues(lhs, differentValue, options: options)
            )
        }
    }

    func testLayoutComparisonProjectsActiveEnumPayloads() {
        let firstLongString = String(repeating: "a", count: 64)
        let secondLongString = Array(repeating: "a", count: 64).joined()

        for rawValue: UInt32 in [2, 0x102] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareValues(
                    IndirectComparisonPayload.node(1, .end),
                    IndirectComparisonPayload.node(1, .end),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    IndirectComparisonPayload.node(1, .end),
                    IndirectComparisonPayload.node(2, .end),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    StringComparisonPayload.value(firstLongString),
                    StringComparisonPayload.value(secondLongString),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    Optional(firstLongString),
                    Optional(secondLongString),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    LargeComparisonPayload.value(1, 2, 3, 4),
                    LargeComparisonPayload.value(1, 2, 3, 4),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    LargeComparisonPayload.value(1, 2, 3, 4),
                    LargeComparisonPayload.value(1, 2, 3, 5),
                    options: options
                )
            )
        }

        for rawValue: UInt32 in [3, 0x103] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertFalse(
                _AGGraph.compareValues(
                    IndirectComparisonPayload.node(1, .end),
                    IndirectComparisonPayload.node(1, .end),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    StringComparisonPayload.value(firstLongString),
                    StringComparisonPayload.value(secondLongString),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    Optional(firstLongString),
                    Optional(secondLongString),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    LargeComparisonPayload.value(1, 2, 3, 4),
                    LargeComparisonPayload.value(1, 2, 3, 4),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    LargeComparisonPayload.value(1, 2, 3, 4),
                    LargeComparisonPayload.value(1, 2, 3, 5),
                    options: options
                )
            )
        }
    }

    func testTypedNodeStorageOwnsAndReleasesReferenceValues() {
        var first: ComparisonReference? = ComparisonReference(1)
        weak let weakFirst = first
        var second: ComparisonReference? = ComparisonReference(2)
        weak let weakSecond = second
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let attribute = graph.makeInput(
                value: StrongComparisonPayload(object: first!)
            )
            first = nil
            XCTAssertNotNil(weakFirst)

            XCTAssertTrue(
                attribute.setValue(StrongComparisonPayload(object: second!))
            )
            XCTAssertNil(weakFirst)
            second = nil
            XCTAssertNotNil(weakSecond)

            graph.removeNode(attribute.identifier)
            XCTAssertNil(weakSecond)
        }
    }

    func testTypedNodeStorageKeepsReferenceAndClosureComparisonBoundaries() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let reference = ComparisonReference(1)
            let other = ComparisonReference(1)
            let weakAttribute: Attribute<WeakComparisonPayload> =
                graph.makeLowLevelAttribute(
                    body: DefaultComparisonModeBody(),
                    value: WeakComparisonPayload(object: reference),
                    flags: []
                ) { _, _ in }
            XCTAssertFalse(
                weakAttribute.setValue(WeakComparisonPayload(object: reference))
            )
            XCTAssertTrue(
                weakAttribute.setValue(WeakComparisonPayload(object: other))
            )

            let closure: () -> Int = { 1 }
            let closureAttribute: Attribute<ClosureComparisonPayload> =
                graph.makeLowLevelAttribute(
                    body: DefaultComparisonModeBody(),
                    value: ClosureComparisonPayload(body: closure),
                    flags: []
                ) { _, _ in }
            XCTAssertFalse(
                closureAttribute.setValue(ClosureComparisonPayload(body: closure))
            )
            XCTAssertTrue(
                closureAttribute.setValue(ClosureComparisonPayload(body: { 1 }))
            )
        }
    }

}

private enum ComparisonPayload {
    case empty
    case payload(UInt64)
}

private indirect enum IndirectComparisonPayload {
    case node(Int, IndirectComparisonPayload)
    case end
}

private enum StringComparisonPayload {
    case value(String)
}

private enum LargeComparisonPayload {
    case value(UInt64, UInt64, UInt64, UInt64)
}

private final class ComparisonReference {
    var value: Int

    init(_ value: Int) {
        self.value = value
    }
}

private struct WeakComparisonPayload {
    weak var object: ComparisonReference?
}

private struct StrongComparisonPayload {
    var object: ComparisonReference
}

private struct ClosureComparisonPayload {
    var body: () -> Int
}

private struct ExistentialComparisonPayload {
    var value: any Equatable
}

private struct PaddedComparisonPayload {
    var byte: UInt8
    var word: UInt64
}

private enum ComparisonModeReads {
    nonisolated(unsafe) static var rule = 0
    nonisolated(unsafe) static var statefulRule = 0
    nonisolated(unsafe) static var lowLevelBody = 0
}

private struct DefaultComparisonModeRule: Rule {
    var value: Int { 0 }
}

private struct ComparisonModeRule: Rule {
    static var comparisonMode: AGComparisonMode {
        ComparisonModeReads.rule += 1
        return AGComparisonMode(rawValue: 0x12)
    }

    var value: Int { 0 }
}

private struct ComparisonModeStatefulRule: StatefulRule {
    typealias Value = Int

    static var comparisonMode: AGComparisonMode {
        ComparisonModeReads.statefulRule += 1
        return AGComparisonMode(rawValue: 0x13)
    }

    mutating func updateValue() {
        value = 0
    }
}

private struct ComparisonModeLowLevelBody: _AttributeBody {
    static var comparisonMode: AGComparisonMode {
        ComparisonModeReads.lowLevelBody += 1
        return AGComparisonMode(rawValue: 0x14)
    }
}

private struct DefaultComparisonModeBody: _AttributeBody {}

private func makePaddedComparisonPointer(
    fill: UInt8,
    byte: UInt8,
    word: UInt64
) -> UnsafeMutablePointer<PaddedComparisonPayload> {
    let pointer = UnsafeMutablePointer<PaddedComparisonPayload>.allocate(capacity: 1)
    pointer.initialize(to: PaddedComparisonPayload(byte: byte, word: word))
    guard let wordOffset = MemoryLayout<PaddedComparisonPayload>.offset(of: \.word) else {
        fatalError("PaddedComparisonPayload.word has no stable offset")
    }
    let raw = UnsafeMutableRawPointer(pointer)
    for offset in MemoryLayout<UInt8>.size..<wordOffset {
        raw.advanced(by: offset).storeBytes(of: fill, as: UInt8.self)
    }
    return pointer
}

private func makeExistentialComparisonPointer(
    fill: UInt8,
    value: Int
) -> UnsafeMutablePointer<ExistentialComparisonPayload> {
    let pointer = UnsafeMutablePointer<ExistentialComparisonPayload>.allocate(
        capacity: 1
    )
    pointer.initialize(to: ExistentialComparisonPayload(value: value))
    let raw = UnsafeMutableRawPointer(pointer)
    for offset in MemoryLayout<Int>.size..<(3 * MemoryLayout<UInt>.size) {
        raw.advanced(by: offset).storeBytes(of: fill, as: UInt8.self)
    }
    return pointer
}
