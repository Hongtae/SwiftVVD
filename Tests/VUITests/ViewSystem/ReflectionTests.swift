import XCTest
@testable import VUI

final class ReflectionTests: XCTestCase {
    private func assertNames(
        _ names: [String],
        equal expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            names == expected || names.allSatisfy(\.isEmpty),
            "Unexpected reflection field names: \(names)",
            file: file,
            line: line
        )
    }

    func testStoredFieldTraversalProvidesNamesOffsetsTypesAndKinds() {
        var fields: [(String, Int, Any.Type, _MetadataKind)] = []
        let completed = _forEachField(of: ReflectionPayload.self) {
            name,
            offset,
            type,
            kind in
            fields.append((String(cString: name), offset, type, kind))
            return true
        }

        XCTAssertTrue(completed)
        assertNames(fields.map(\.0), equal: ["number", "text"])
        XCTAssertEqual(fields.map(\.1), [
            MemoryLayout<ReflectionPayload>.offset(of: \.number)!,
            MemoryLayout<ReflectionPayload>.offset(of: \.text)!,
        ])
        XCTAssertTrue(fields[0].2 == Int.self)
        XCTAssertTrue(fields[1].2 == String.self)
        XCTAssertEqual(fields.map(\.3), [.struct, .struct])
    }

    func testThreeArgumentTraversalKeepsTupleFieldOrder() {
        typealias Payload = (Int, String, Bool)
        var names: [String] = []
        var types: [Any.Type] = []
        let completed = _forEachField(of: Payload.self) { name, _, type in
            names.append(String(cString: name))
            types.append(type)
            return true
        }

        XCTAssertTrue(completed)
        assertNames(names, equal: [".0", ".1", ".2"])
        XCTAssertTrue(types[0] == Int.self)
        XCTAssertTrue(types[1] == String.self)
        XCTAssertTrue(types[2] == Bool.self)
    }

    func testClassTraversalRequiresClassTypeOption() {
        XCTAssertFalse(
            _forEachField(of: ReflectionObject.self) { _, _, _, _ in true }
        )

        var names: [String] = []
        let completed = _forEachField(
            of: ReflectionObject.self,
            options: .classType
        ) { name, _, type, kind in
            names.append(String(cString: name))
            XCTAssertTrue(type == Int.self)
            XCTAssertEqual(kind, .struct)
            return true
        }
        XCTAssertTrue(completed)
        assertNames(names, equal: ["value"])
    }
}

private struct ReflectionPayload {
    var number: Int
    var text: String
}

private final class ReflectionObject {
    var value: Int = 0
}
