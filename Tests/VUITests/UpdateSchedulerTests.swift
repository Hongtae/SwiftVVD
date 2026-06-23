import XCTest
@testable import VUI

final class UpdateSchedulerTests: XCTestCase {
    func testEnqueueActionRunsUnderNestedUpdateDrainAndReturnsMonotonicIDs() {
        var events: [String] = []

        let firstID = Update.enqueueAction {
            events.append(Update.isActive ? "active" : "inactive")
            events.append(Update.threadIsUpdating ? "updating" : "dispatching")
        }
        let secondID = Update.enqueueAction {
            events.append("second")
        }

        XCTAssertEqual(secondID, firstID + 1)
        XCTAssertEqual(events, ["active", "dispatching", "second"])
        XCTAssertFalse(Update.isActive)
        XCTAssertFalse(Update.threadIsUpdating)
    }

    func testEnsureDefersQueuedActionsUntilOutermostEnd() {
        var events: [String] = []

        Update.ensure {
            events.append(Update.threadIsUpdating ? "outer-updating" : "outer-not-updating")

            Update.enqueueAction {
                events.append(Update.threadIsUpdating ? "action-updating" : "action-dispatching")
            }

            XCTAssertTrue(Update.canDispatch)
            XCTAssertEqual(events, ["outer-updating"])
            events.append("outer-end")
        }

        XCTAssertEqual(events, ["outer-updating", "outer-end", "action-dispatching"])
        XCTAssertFalse(Update.isActive)
        XCTAssertFalse(Update.threadIsUpdating)
    }

    func testDispatchActionsSnapshotsAndLoopsForReentrantEnqueues() {
        var events: [String] = []

        Update.ensure {
            Update.enqueueAction {
                events.append("first")
                Update.enqueueAction {
                    events.append("second")
                }
                events.append("first-end")
            }

            XCTAssertEqual(events, [])
        }

        XCTAssertEqual(events, ["first", "first-end", "second"])
        XCTAssertFalse(Update.isActive)
    }

    func testDispatchImmediatelyRunsBodyNowAndDefersQueuedActionsToEnd() {
        var events: [String] = []

        let result = Update.dispatchImmediately {
            events.append(Update.threadIsUpdating ? "body-updating" : "body-dispatching")
            Update.enqueueAction {
                events.append("queued")
            }
            events.append("body-end")
            return 17
        }

        XCTAssertEqual(result, 17)
        XCTAssertEqual(events, ["body-dispatching", "body-end", "queued"])
        XCTAssertFalse(Update.isActive)
        XCTAssertFalse(Update.threadIsUpdating)
    }
}
