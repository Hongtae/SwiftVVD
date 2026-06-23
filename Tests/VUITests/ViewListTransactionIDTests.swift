import XCTest
@testable import VUI

final class ViewListTransactionIDTests: XCTestCase {
    func testZeroInitializerStoresZeroWord() {
        XCTAssertEqual(TransactionID().value, 0)
    }

    func testComparisonUsesSignedStoredWordOrder() {
        var highBit = TransactionID()
        highBit.value = UInt.max

        let zero = TransactionID()

        var one = TransactionID()
        one.value = 1

        XCTAssertLessThan(highBit, zero)
        XCTAssertLessThan(highBit, one)
        XCTAssertFalse(one < highBit)
    }

    func testEqualityAndHashingUseStoredWord() {
        var lhs = TransactionID()
        lhs.value = UInt.max

        var rhs = TransactionID()
        rhs.value = UInt.max

        var different = TransactionID()
        different.value = UInt.max - 1

        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, different)
        XCTAssertTrue(Set([lhs]).contains(rhs))
    }

    func testContextInitializersReadCurrentGraphCounterLane() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let derived = graph.makeRule {
                source.value + 1
            }

            XCTAssertEqual(derived.value, 2)

            let context = RuleContext(attribute: derived)
            XCTAssertEqual(TransactionID(context: context).value, 1)
            XCTAssertEqual(TransactionID(context: AnyRuleContext(context)).value, 1)

            source.setValue(2)
            XCTAssertEqual(derived.value, 3)
            XCTAssertEqual(TransactionID(context: context).value, 2)
        }
    }
}
