import XCTest
@testable import VUI

extension EnvironmentValues {
    @Entry var macroSampleCount: Int = 7
    @Entry var macroSampleName: String = "default"
}

extension Transaction {
    @Entry var macroTransactionFlag: Bool = false
}

extension ContainerValues {
    @Entry var macroContainerRank: Int = 3
}

final class EntryMacroTests: XCTestCase {
    func testEntryMacroSynthesizesEnvironmentKeyAccessors() {
        var values = EnvironmentValues()

        XCTAssertEqual(values.macroSampleCount, 7)
        XCTAssertEqual(values.macroSampleName, "default")

        values.macroSampleCount = 11
        values.macroSampleName = "changed"

        XCTAssertEqual(values.macroSampleCount, 11)
        XCTAssertEqual(values.macroSampleName, "changed")
    }

    func testEntryMacroSynthesizesTransactionKeyAccessors() {
        var transaction = Transaction()

        XCTAssertFalse(transaction.macroTransactionFlag)

        transaction.macroTransactionFlag = true

        XCTAssertTrue(transaction.macroTransactionFlag)
    }

    func testEntryMacroSynthesizesContainerValueKeyAccessors() {
        var values = ContainerValues()

        XCTAssertEqual(values.macroContainerRank, 3)

        values.macroContainerRank = 8

        XCTAssertEqual(values.macroContainerRank, 8)
    }
}
