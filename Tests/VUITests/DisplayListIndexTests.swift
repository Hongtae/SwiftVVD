import XCTest
@testable import VUI

final class DisplayListIndexTests: XCTestCase {
    func testDisplayListIdentitySurface() throws {
        let first = _DisplayList_Identity()
        let second = _DisplayList_Identity()

        XCTAssertNotEqual(first, .none)
        XCTAssertNotEqual(second, .none)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(_DisplayList_Identity.none.value, 0)
        XCTAssertEqual(_DisplayList_Identity(decodedValue: 42).value, 42)
        XCTAssertEqual(_DisplayList_Identity(decodedValue: 42).description, "#42")

        let encoded = try JSONEncoder().encode(_DisplayList_Identity(decodedValue: 42))
        XCTAssertEqual(
            try JSONDecoder().decode(_DisplayList_Identity.self, from: encoded),
            _DisplayList_Identity(decodedValue: 42)
        )
    }

    func testDisplayListStableIdentityAndMapSurface() throws {
        let identity = _DisplayList_Identity(decodedValue: 9)
        let hash = StrongHash(words: (1, 2, 3, 4, 5))
        let stable = _DisplayList_StableIdentity(hash: hash, serial: 7)
        var map = _DisplayList_StableIdentityMap()

        XCTAssertEqual(MemoryLayout<_DisplayList_StableIdentity>.size, 24)
        XCTAssertEqual(stable.hash, hash)
        XCTAssertEqual(stable.serial, 7)
        XCTAssertTrue(map.isEmpty)

        map[identity] = stable
        XCTAssertEqual(map[identity], stable)
        XCTAssertFalse(map.isEmpty)

        map[identity] = nil
        XCTAssertNil(map[identity])
        XCTAssertTrue(map.isEmpty)

        let retained = _DisplayList_StableIdentity(hash: hash, serial: 8)
        let insertedIdentity = _DisplayList_Identity(decodedValue: 10)
        let inserted = _DisplayList_StableIdentity(hash: StrongHash(of: "inserted"), serial: 9)
        var existing = _DisplayList_StableIdentityMap()
        existing[identity] = stable
        var incoming = _DisplayList_StableIdentityMap()
        incoming[identity] = retained
        incoming[insertedIdentity] = inserted

        existing.formUnion(incoming)
        XCTAssertEqual(existing[identity], stable)
        XCTAssertEqual(existing[insertedIdentity], inserted)

        let encoded = try JSONEncoder().encode(stable)
        XCTAssertEqual(
            try JSONDecoder().decode(_DisplayList_StableIdentity.self, from: encoded),
            stable
        )
    }

    func testDisplayListStableIdentityProtobufSurface() throws {
        let stable = _DisplayList_StableIdentity(
            hash: StrongHash(words: (1, 2, 3, 4, 5)),
            serial: 7
        )
        let data = try ProtobufEncoder.encoding(stable)

        XCTAssertEqual(
            data,
            Data([
                0x0a, 0x16,
                0x0a, 0x14,
                0x01, 0x00, 0x00, 0x00,
                0x02, 0x00, 0x00, 0x00,
                0x03, 0x00, 0x00, 0x00,
                0x04, 0x00, 0x00, 0x00,
                0x05, 0x00, 0x00, 0x00,
                0x10, 0x07,
            ])
        )

        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try _DisplayList_StableIdentity(from: &decoder), stable)

        var packedSerialDecoder = ProtobufDecoder(Data([0x12, 0x02, 0x01, 0x07]))
        let packedSerial = try _DisplayList_StableIdentity(from: &packedSerialDecoder)
        XCTAssertEqual(packedSerial.hash, StrongHash(words: (0, 0, 0, 0, 0)))
        XCTAssertEqual(packedSerial.serial, 7)

        var zeroSerialDecoder = ProtobufDecoder(
            try ProtobufEncoder.encoding(
                _DisplayList_StableIdentity(hash: stable.hash, serial: 0)
            )
        )
        XCTAssertEqual(
            try _DisplayList_StableIdentity(from: &zeroSerialDecoder).serial,
            0
        )
    }

    func testDisplayListStableIdentityMapProtobufSurface() throws {
        let identity = _DisplayList_Identity(decodedValue: 9)
        let stable = _DisplayList_StableIdentity(
            hash: StrongHash(words: (1, 2, 3, 4, 5)),
            serial: 7
        )
        var map = _DisplayList_StableIdentityMap()
        map[identity] = stable

        let data = try ProtobufEncoder.encoding(map)
        XCTAssertEqual(
            data,
            Data([
                0x0a, 0x1e,
                0x08, 0x09,
                0x12, 0x1a,
                0x0a, 0x16,
                0x0a, 0x14,
                0x01, 0x00, 0x00, 0x00,
                0x02, 0x00, 0x00, 0x00,
                0x03, 0x00, 0x00, 0x00,
                0x04, 0x00, 0x00, 0x00,
                0x05, 0x00, 0x00, 0x00,
                0x10, 0x07,
            ])
        )

        var decoder = ProtobufDecoder(data)
        let decoded = try _DisplayList_StableIdentityMap(from: &decoder)
        XCTAssertEqual(decoded[identity], stable)
    }

    func testDisplayListStableIdentityMapProtobufRequiresBothEntryFieldsAndUsesLastDuplicate() throws {
        var missingValueDecoder = ProtobufDecoder(Data([0x0a, 0x02, 0x08, 0x09]))
        XCTAssertThrowsError(
            try _DisplayList_StableIdentityMap(from: &missingValueDecoder)
        )

        var missingIdentityDecoder = ProtobufDecoder(Data([0x0a, 0x02, 0x12, 0x00]))
        XCTAssertThrowsError(
            try _DisplayList_StableIdentityMap(from: &missingIdentityDecoder)
        )

        var packedIdentityDecoder = ProtobufDecoder(
            Data([0x0a, 0x06, 0x0a, 0x02, 0x01, 0x09, 0x12, 0x00])
        )
        let packedIdentityMap = try _DisplayList_StableIdentityMap(
            from: &packedIdentityDecoder
        )
        XCTAssertEqual(
            packedIdentityMap[_DisplayList_Identity(decodedValue: 9)],
            _DisplayList_StableIdentity(
                hash: StrongHash(words: (0, 0, 0, 0, 0)),
                serial: 0
            )
        )

        var noneMap = _DisplayList_StableIdentityMap()
        noneMap[.none] = _DisplayList_StableIdentity(
            hash: StrongHash(words: (0, 0, 0, 0, 0)),
            serial: 0
        )
        var omittedIdentityDecoder = ProtobufDecoder(
            try ProtobufEncoder.encoding(noneMap)
        )
        XCTAssertThrowsError(
            try _DisplayList_StableIdentityMap(from: &omittedIdentityDecoder)
        )

        let identity = _DisplayList_Identity(decodedValue: 9)
        let first = _DisplayList_StableIdentity(
            hash: StrongHash(words: (1, 2, 3, 4, 5)),
            serial: 7
        )
        let last = _DisplayList_StableIdentity(
            hash: StrongHash(words: (6, 7, 8, 9, 10)),
            serial: 11
        )
        var firstMap = _DisplayList_StableIdentityMap()
        firstMap[identity] = first
        var lastMap = _DisplayList_StableIdentityMap()
        lastMap[identity] = last
        var duplicateData = try ProtobufEncoder.encoding(firstMap)
        duplicateData.append(try ProtobufEncoder.encoding(lastMap))

        var duplicateDecoder = ProtobufDecoder(duplicateData)
        let decoded = try _DisplayList_StableIdentityMap(from: &duplicateDecoder)
        XCTAssertEqual(decoded[identity], last)
    }

    func testDisplayListIndexFieldShapeAndIDProjection() {
        let index = DisplayList.Index()

        XCTAssertEqual(MemoryLayout<DisplayList.Index>.size, 17)
        XCTAssertEqual(MemoryLayout<DisplayList.Index.ID>.size, 16)
        XCTAssertEqual(index.identity, .none)
        XCTAssertEqual(index.serial, 0)
        XCTAssertEqual(index.archiveIdentity, .none)
        XCTAssertEqual(index.archiveSerial, 0)
        XCTAssertEqual(index.id, DisplayList.Index().id)
        XCTAssertEqual(index.id.hashValue, DisplayList.Index().id.hashValue)
    }

    func testDisplayListIndexEnterLeaveAndArchiveStateMachine() {
        var index = DisplayList.Index()
        let identity = _DisplayList_Identity(decodedValue: 11)

        let root = index.enter(identity: identity)
        XCTAssertEqual(root.identity, .none)
        XCTAssertEqual(index.identity, identity)
        XCTAssertEqual(index.serial, 0)

        index.updateArchive(entering: true)
        XCTAssertEqual(index.identity, .none)
        XCTAssertEqual(index.serial, 0)
        XCTAssertEqual(index.archiveIdentity, identity)
        XCTAssertEqual(index.archiveSerial, 0)

        index.updateArchive(entering: false)
        XCTAssertEqual(index.identity, identity)
        XCTAssertEqual(index.archiveIdentity, .none)

        index.leave(index: root)
        XCTAssertEqual(index.identity, .none)
        XCTAssertEqual(index.serial, 0)
        XCTAssertEqual(index.archiveIdentity, .none)
        XCTAssertEqual(index.archiveSerial, 0)
    }

    func testDisplayListIndexNoneEntryAdvancesSerialWithoutReplacingIdentity() {
        var index = DisplayList.Index()
        let identity = _DisplayList_Identity(decodedValue: 17)
        let root = index.enter(identity: identity)

        let entered = index.enter(identity: .none)
        XCTAssertEqual(index.identity, identity)
        XCTAssertEqual(index.serial, 1)
        XCTAssertEqual(entered.id, index.id)

        index.leave(index: entered)
        XCTAssertEqual(index.identity, identity)
        XCTAssertEqual(index.serial, 1)

        index.leave(index: root)
        XCTAssertEqual(index.identity, .none)
        XCTAssertEqual(index.serial, 0)
    }
}
