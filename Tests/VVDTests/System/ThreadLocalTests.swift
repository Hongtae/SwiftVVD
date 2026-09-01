import XCTest
@testable import VVD

final class ThreadLocalStorageTests: XCTestCase {
    private final class Key: @unchecked Sendable {}
    private final class Value {}

    private static let firstKey = Key()
    private static let secondKey = Key()

    private static var firstKeyPointer: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(firstKey).toOpaque())
    }

    private static var secondKeyPointer: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(secondKey).toOpaque())
    }

    func testSetGetAndClearRawPointer() {
        let value = Value()
        let valuePointer = Unmanaged.passUnretained(value).toOpaque()

        ThreadLocalStorage.set(Self.firstKeyPointer, valuePointer)
        defer { ThreadLocalStorage.set(Self.firstKeyPointer, nil) }

        XCTAssertEqual(ThreadLocalStorage.get(Self.firstKeyPointer), valuePointer)
        ThreadLocalStorage.set(Self.firstKeyPointer, nil)
        XCTAssertNil(ThreadLocalStorage.get(Self.firstKeyPointer))
    }

    func testKeysAreIndependent() {
        let firstValue = Value()
        let secondValue = Value()
        let firstValuePointer = Unmanaged.passUnretained(firstValue).toOpaque()
        let secondValuePointer = Unmanaged.passUnretained(secondValue).toOpaque()

        ThreadLocalStorage.set(Self.firstKeyPointer, firstValuePointer)
        ThreadLocalStorage.set(Self.secondKeyPointer, secondValuePointer)
        defer {
            ThreadLocalStorage.set(Self.firstKeyPointer, nil)
            ThreadLocalStorage.set(Self.secondKeyPointer, nil)
        }

        XCTAssertEqual(ThreadLocalStorage.get(Self.firstKeyPointer), firstValuePointer)
        XCTAssertEqual(ThreadLocalStorage.get(Self.secondKeyPointer), secondValuePointer)
    }
}
