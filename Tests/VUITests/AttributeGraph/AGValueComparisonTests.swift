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
        XCTAssertEqual(DefaultComparisonModeRule.comparisonMode, .layout)
        XCTAssertEqual(_External.comparisonMode, .storedRepresentation)
        XCTAssertEqual(AGComparisonMode.layout.rawValue, 2)
        XCTAssertEqual(AGComparisonMode.storedRepresentation.rawValue, 3)
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

    func testLayoutComparisonDetectsChangedHeapBackedArrayElement() {
        let lhs = [
            ScrollGeometryState(
                geometry: ScrollGeometry(
                    contentOffset: .zero,
                    contentSize: CGSize(width: 100, height: 1_000),
                    contentInsets: EdgeInsets(),
                    containerSize: CGSize(width: 100, height: 100)
                ),
                scrollableAxes: .vertical,
                transform: WeakAttribute()
            )
        ]
        let rhs = [
            ScrollGeometryState(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 40),
                    contentSize: CGSize(width: 100, height: 1_000),
                    contentInsets: EdgeInsets(),
                    containerSize: CGSize(width: 100, height: 100)
                ),
                scrollableAxes: .vertical,
                transform: WeakAttribute()
            )
        ]

        for rawValue: UInt32 in [2, 0x102] {
            XCTAssertFalse(
                _AGGraph.compareValues(
                    lhs,
                    rhs,
                    options: AGComparisonOptions(rawValue: rawValue)
                )
            )
        }
    }

    func testModeTwoLayoutComparisonIgnoresPaddingBytes() {
        // ASSERTIONS attributeGraphPreparedComparisonProgramObserved
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

    func testKeyPathProjectionUsesLayoutComparison() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let source = graph.makeInput(
                value: KeyPathPaddedComparisonRoot(
                    projected: PaddedComparisonPayload(byte: 7, word: 42)
                )
            )
            let projection = graph.subscriptNode(
                parent: source,
                keyPath: \.projected
            )
            let projectionNode = try! XCTUnwrap(
                graph.slots[Int(projection.identifier.rawValue)].node
            )
            let lhs = makePaddedComparisonStorage(
                fill: 0x11,
                byte: 7,
                word: 42
            )
            let differentPadding = makePaddedComparisonStorage(
                fill: 0xee,
                byte: 7,
                word: 42
            )
            let changedField = makePaddedComparisonStorage(
                fill: 0x11,
                byte: 8,
                word: 42
            )

            XCTAssertTrue(projectionNode.valuesEqual(lhs, differentPadding))
            XCTAssertFalse(projectionNode.valuesEqual(lhs, changedField))
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
        // ASSERTIONS attributeGraphPreparedComparisonProgramObserved
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
            XCTAssertTrue(
                _AGGraph.compareValues(
                    SameTypeCaseComparisonPayload.first(7),
                    SameTypeCaseComparisonPayload.first(7),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    SameTypeCaseComparisonPayload.first(7),
                    SameTypeCaseComparisonPayload.second(7),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    SameTypeCaseComparisonPayload.firstEmpty,
                    SameTypeCaseComparisonPayload.secondEmpty,
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

    func testRecursiveEnumComparisonUsesPublishedLayoutResult() {
        for rawValue: UInt32 in [2, 0x102, 0x202, 0x302] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareValues(
                    IndirectComparisonPayload.node(1, .node(2, .end)),
                    IndirectComparisonPayload.node(1, .node(2, .end)),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    IndirectComparisonPayload.node(
                        1,
                        .node(2, .node(3, .end))
                    ),
                    IndirectComparisonPayload.node(
                        1,
                        .node(2, .node(3, .end))
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    IndirectComparisonPayload.node(1, .node(2, .end)),
                    IndirectComparisonPayload.node(1, .node(3, .end)),
                    options: options
                )
            )
        }
    }

    func testLayoutComparisonProjectsOutOfLineExistentialPayloads() {
        let reference = ComparisonReference(1)
        let alias = reference
        let other = ComparisonReference(1)

        for rawValue: UInt32 in [2, 0x102] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ExistentialComparisonPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    ExistentialComparisonPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ExistentialComparisonPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    ExistentialComparisonPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 5)
                    ),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ExistentialComparisonPayload(
                        value: AlignedExistentialValue(value: SIMD4(1, 2, 3, 4))
                    ),
                    ExistentialComparisonPayload(
                        value: AlignedExistentialValue(value: SIMD4(1, 2, 3, 4))
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ExistentialComparisonPayload(
                        value: AlignedExistentialValue(value: SIMD4(1, 2, 3, 4))
                    ),
                    ExistentialComparisonPayload(
                        value: AlignedExistentialValue(value: SIMD4(1, 2, 3, 5))
                    ),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ExistentialComparisonPayload(
                        value: WeakExistentialValue(object: reference)
                    ),
                    ExistentialComparisonPayload(
                        value: WeakExistentialValue(object: alias)
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ExistentialComparisonPayload(
                        value: WeakExistentialValue(object: reference)
                    ),
                    ExistentialComparisonPayload(
                        value: WeakExistentialValue(object: other)
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ExistentialComparisonPayload(value: Int(7)),
                    ExistentialComparisonPayload(value: UInt(7)),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    AnyExistentialComparisonPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    AnyExistentialComparisonPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    AnyExistentialComparisonPayload(
                        value: AlignedExistentialValue(value: SIMD4(1, 2, 3, 4))
                    ),
                    AnyExistentialComparisonPayload(
                        value: AlignedExistentialValue(value: SIMD4(1, 2, 3, 4))
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    AnyExistentialComparisonPayload(value: Int(7)),
                    AnyExistentialComparisonPayload(value: UInt(7)),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    AnyObjectComparisonPayload(value: reference),
                    AnyObjectComparisonPayload(value: alias),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    AnyObjectComparisonPayload(value: reference),
                    AnyObjectComparisonPayload(value: other),
                    options: options
                )
            )
        }

        for rawValue: UInt32 in [3, 0x103] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ExistentialComparisonPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    ExistentialComparisonPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ExistentialComparisonPayload(
                        value: AlignedExistentialValue(value: SIMD4(1, 2, 3, 4))
                    ),
                    ExistentialComparisonPayload(
                        value: AlignedExistentialValue(value: SIMD4(1, 2, 3, 4))
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ExistentialComparisonPayload(
                        value: WeakExistentialValue(object: reference)
                    ),
                    ExistentialComparisonPayload(
                        value: WeakExistentialValue(object: alias)
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    AnyExistentialComparisonPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    AnyExistentialComparisonPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    AnyExistentialComparisonPayload(
                        value: AlignedExistentialValue(value: SIMD4(1, 2, 3, 4))
                    ),
                    AnyExistentialComparisonPayload(
                        value: AlignedExistentialValue(value: SIMD4(1, 2, 3, 4))
                    ),
                    options: options
                )
            )
        }
    }

    func testProtocolCompositionUsesItsDeclaredContainerRepresentation() {
        let reference = ComparisonReference(1)
        let alias = reference
        let other = ComparisonReference(1)

        for rawValue: UInt32 in [2, 0x102] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ProtocolCompositionPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    ProtocolCompositionPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    EquatableProtocolCompositionPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    EquatableProtocolCompositionPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ProtocolCompositionPayload(value: reference),
                    ProtocolCompositionPayload(value: alias),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ProtocolCompositionPayload(value: reference),
                    ProtocolCompositionPayload(value: other),
                    options: options
                )
            )
        }

        for rawValue: UInt32 in [3, 0x103] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ProtocolCompositionPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    ProtocolCompositionPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    EquatableProtocolCompositionPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    EquatableProtocolCompositionPayload(
                        value: LargeExistentialValue(a: 1, b: 2, c: 3, d: 4)
                    ),
                    options: options
                )
            )
        }

        for rawValue: UInt32 in [2, 3, 0x102, 0x103] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ThreeWitnessClassCompositionPayload(value: reference),
                    ThreeWitnessClassCompositionPayload(value: alias),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ThreeWitnessClassCompositionPayload(value: reference),
                    ThreeWitnessClassCompositionPayload(value: other),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    FourWitnessClassCompositionPayload(value: reference),
                    FourWitnessClassCompositionPayload(value: alias),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    FourWitnessClassCompositionPayload(value: reference),
                    FourWitnessClassCompositionPayload(value: other),
                    options: options
                )
            )
        }
    }

    func testExtendedExistentialUsesStoredRepresentation() {
        XCTAssertEqual(
            _MetadataKind((any ParameterizedComparisonProtocol<Int>).self),
            .extendedExistential
        )
        XCTAssertEqual(
            _MetadataKind(
                (any ClassParameterizedComparisonProtocol<Int>).self
            ),
            .extendedExistential
        )
        XCTAssertEqual(
            _MetadataKind((any ParameterizedComparisonProtocol<Int>.Type).self),
            .extendedExistential
        )

        let lhs = makeParameterizedExistentialComparisonPointer(
            fill: 0x11,
            value: 7
        )
        let sameStorage = makeParameterizedExistentialComparisonPointer(
            fill: 0x11,
            value: 7
        )
        let differentUnusedStorage = makeParameterizedExistentialComparisonPointer(
            fill: 0xee,
            value: 7
        )
        defer {
            lhs.deinitialize(count: 1)
            lhs.deallocate()
            sameStorage.deinitialize(count: 1)
            sameStorage.deallocate()
            differentUnusedStorage.deinitialize(count: 1)
            differentUnusedStorage.deallocate()
        }

        let reference = ParameterizedComparisonReference(1)
        let alias = reference
        let other = ParameterizedComparisonReference(1)
        for rawValue: UInt32 in [2, 3, 0x102, 0x103, 0x202, 0x302] {
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
                _AGGraph.compareValues(
                    ParameterizedExistentialComparisonPayload(
                        value: ParameterizedLargeComparisonValue(
                            a: 1,
                            b: 2,
                            c: 3,
                            d: 4
                        )
                    ),
                    ParameterizedExistentialComparisonPayload(
                        value: ParameterizedLargeComparisonValue(
                            a: 1,
                            b: 2,
                            c: 3,
                            d: 4
                        )
                    ),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ClassParameterizedComparisonPayload(value: reference),
                    ClassParameterizedComparisonPayload(value: alias),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ClassParameterizedComparisonPayload(value: reference),
                    ClassParameterizedComparisonPayload(value: other),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    MetatypeParameterizedComparisonPayload(
                        value: ParameterizedInlineComparisonValue.self
                    ),
                    MetatypeParameterizedComparisonPayload(
                        value: ParameterizedInlineComparisonValue.self
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    MetatypeParameterizedComparisonPayload(
                        value: ParameterizedInlineComparisonValue.self
                    ),
                    MetatypeParameterizedComparisonPayload(
                        value: AlternateParameterizedInlineComparisonValue.self
                    ),
                    options: options
                )
            )
        }
    }

    func testSpecialExistentialsUseTheirDeclaredRepresentation() {
        let sharedError: any Error = ComparisonError(code: 7)
        let sharedMarkedError: any Error & ComparisonErrorMarker =
            MarkedComparisonError(code: 7)
        let sharedReference = DerivedComparisonReference(7)
        let distinctReference = DerivedComparisonReference(7)

        for rawValue: UInt32 in [2, 0x102, 0x202, 0x302] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ErrorComparisonPayload(value: sharedError),
                    ErrorComparisonPayload(value: sharedError),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ErrorComparisonPayload(value: ComparisonError(code: 7)),
                    ErrorComparisonPayload(value: ComparisonError(code: 7)),
                    options: options
                )
            )
        }

        for rawValue: UInt32 in [3, 0x103] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ErrorComparisonPayload(value: sharedError),
                    ErrorComparisonPayload(value: sharedError),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ErrorComparisonPayload(value: ComparisonError(code: 7)),
                    ErrorComparisonPayload(value: ComparisonError(code: 7)),
                    options: options
                )
            )
        }

        for rawValue: UInt32 in [2, 0x102, 0x202, 0x302] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ErrorCompositionComparisonPayload(
                        value: sharedMarkedError
                    ),
                    ErrorCompositionComparisonPayload(
                        value: sharedMarkedError
                    ),
                    options: options
                )
            )
            XCTAssertTrue(
                _AGGraph.compareValues(
                    ErrorCompositionComparisonPayload(
                        value: MarkedComparisonError(code: 7)
                    ),
                    ErrorCompositionComparisonPayload(
                        value: MarkedComparisonError(code: 7)
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    ErrorCompositionComparisonPayload(
                        value: MarkedComparisonError(code: 7)
                    ),
                    ErrorCompositionComparisonPayload(
                        value: MarkedComparisonError(code: 8)
                    ),
                    options: options
                )
            )
        }

        for rawValue: UInt32 in [2, 3, 0x102, 0x103, 0x202, 0x302] {
            let options = AGComparisonOptions(rawValue: rawValue)
            XCTAssertTrue(
                _AGGraph.compareValues(
                    SuperclassExistentialComparisonPayload(
                        value: sharedReference
                    ),
                    SuperclassExistentialComparisonPayload(
                        value: sharedReference
                    ),
                    options: options
                )
            )
            XCTAssertFalse(
                _AGGraph.compareValues(
                    SuperclassExistentialComparisonPayload(
                        value: sharedReference
                    ),
                    SuperclassExistentialComparisonPayload(
                        value: distinctReference
                    ),
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

private enum SameTypeCaseComparisonPayload {
    case first(Int)
    case second(Int)
    case firstEmpty
    case secondEmpty
}

private protocol ComparisonMarkerA {}
private protocol ComparisonMarkerB {}
private protocol ComparisonMarkerC {}
private protocol ComparisonClassMarker: AnyObject {}
private protocol ParameterizedComparisonProtocol<Element> {
    associatedtype Element
}
private protocol ClassParameterizedComparisonProtocol<Element>: AnyObject {
    associatedtype Element
}

private final class ComparisonReference:
    ComparisonMarkerA,
    ComparisonMarkerB,
    ComparisonMarkerC,
    ComparisonClassMarker
{
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

private struct ProtocolCompositionPayload {
    var value: any ComparisonMarkerA & ComparisonMarkerB
}

private struct EquatableProtocolCompositionPayload {
    var value: any Equatable & ComparisonMarkerA & ComparisonMarkerB
}

private struct ThreeWitnessClassCompositionPayload {
    var value: any ComparisonClassMarker & ComparisonMarkerA & ComparisonMarkerB
}

private struct FourWitnessClassCompositionPayload {
    var value: any ComparisonClassMarker & ComparisonMarkerA & ComparisonMarkerB
        & ComparisonMarkerC
}

private struct AnyExistentialComparisonPayload {
    var value: Any
}

private struct AnyObjectComparisonPayload {
    var value: AnyObject
}

private struct ParameterizedExistentialComparisonPayload {
    var value: any ParameterizedComparisonProtocol<Int>
}

private struct ClassParameterizedComparisonPayload {
    var value: any ClassParameterizedComparisonProtocol<Int>
}

private struct MetatypeParameterizedComparisonPayload {
    var value: any ParameterizedComparisonProtocol<Int>.Type
}

private struct ComparisonError: Error {
    var code: Int
}

private struct ErrorComparisonPayload {
    var value: any Error
}

private protocol ComparisonErrorMarker {}

private struct MarkedComparisonError: Error, ComparisonErrorMarker {
    var code: Int
}

private struct ErrorCompositionComparisonPayload {
    var value: any Error & ComparisonErrorMarker
}

private class ComparisonBaseReference {
    var value: Int

    init(_ value: Int) {
        self.value = value
    }
}

private protocol DerivedComparisonMarker: AnyObject {}

private final class DerivedComparisonReference:
    ComparisonBaseReference,
    DerivedComparisonMarker
{}

private struct SuperclassExistentialComparisonPayload {
    var value: any ComparisonBaseReference & DerivedComparisonMarker
}

private struct ParameterizedInlineComparisonValue:
    ParameterizedComparisonProtocol
{
    typealias Element = Int
    var value: Int
}

private struct AlternateParameterizedInlineComparisonValue:
    ParameterizedComparisonProtocol
{
    typealias Element = Int
    var value: Int
}

private struct ParameterizedLargeComparisonValue:
    ParameterizedComparisonProtocol
{
    typealias Element = Int
    var a: UInt64
    var b: UInt64
    var c: UInt64
    var d: UInt64
}

private final class ParameterizedComparisonReference:
    ClassParameterizedComparisonProtocol
{
    typealias Element = Int
    var value: Int

    init(_ value: Int) {
        self.value = value
    }
}

private struct LargeExistentialValue:
    ComparisonMarkerA,
    ComparisonMarkerB,
    Equatable
{
    var a: UInt64
    var b: UInt64
    var c: UInt64
    var d: UInt64
}

private struct AlignedExistentialValue: Equatable {
    var value: SIMD4<Float>
}

private struct WeakExistentialValue: Equatable {
    weak var object: ComparisonReference?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.object === rhs.object
    }
}

private struct PaddedComparisonPayload {
    var byte: UInt8
    var word: UInt64
}

private struct KeyPathPaddedComparisonRoot {
    var projected: PaddedComparisonPayload
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

private func makePaddedComparisonStorage(
    fill: UInt8,
    byte: UInt8,
    word: UInt64
) -> _AGValueStorage<PaddedComparisonPayload> {
    let storage = _AGValueStorage(
        PaddedComparisonPayload(byte: byte, word: word)
    )
    guard let wordOffset = MemoryLayout<PaddedComparisonPayload>.offset(
        of: \.word
    ) else {
        fatalError("PaddedComparisonPayload.word has no stable offset")
    }
    let raw = UnsafeMutableRawPointer(mutating: storage.pointer)
    for offset in MemoryLayout<UInt8>.size..<wordOffset {
        raw.advanced(by: offset).storeBytes(of: fill, as: UInt8.self)
    }
    return storage
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

private func makeParameterizedExistentialComparisonPointer(
    fill: UInt8,
    value: Int
) -> UnsafeMutablePointer<ParameterizedExistentialComparisonPayload> {
    let pointer = UnsafeMutablePointer<
        ParameterizedExistentialComparisonPayload
    >.allocate(capacity: 1)
    pointer.initialize(
        to: ParameterizedExistentialComparisonPayload(
            value: ParameterizedInlineComparisonValue(value: value)
        )
    )
    let raw = UnsafeMutableRawPointer(pointer)
    for offset in MemoryLayout<Int>.size..<(3 * MemoryLayout<UInt>.size) {
        raw.advanced(by: offset).storeBytes(of: fill, as: UInt8.self)
    }
    return pointer
}
