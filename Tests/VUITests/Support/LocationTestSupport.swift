@testable import VUI

final class TestStoredLocation<Value>: StoredLocationBase<Value>, @unchecked Sendable {
    var updating = false

    override var isUpdating: Bool {
        updating
    }

    override func commit(
        transaction: Transaction,
        id: Transaction.ID,
        mutation: BeginUpdate
    ) {
        mutation.apply()
    }

    override func notifyObservers() {
    }
}
