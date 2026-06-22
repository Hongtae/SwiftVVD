import XCTest
@testable import VVD

final class CollisionFilterTests: XCTestCase {
    func testDefaultFiltersCollide() {
        let a = CollisionFilter()
        let b = CollisionFilter()

        XCTAssertTrue(a.allowsCollision(with: b))
        XCTAssertTrue(b.allowsCollision(with: a))
    }

    func testFiltersRequireMutualGroupMaskMatch() {
        let player = CollisionGroup.bit(1)
        let enemy = CollisionGroup.bit(2)

        let playerFilter = CollisionFilter(group: player, mask: CollisionMask(enemy))
        let enemyFilter = CollisionFilter(group: enemy, mask: CollisionMask(player))
        let silentEnemyFilter = CollisionFilter(group: enemy, mask: .none)

        XCTAssertTrue(playerFilter.allowsCollision(with: enemyFilter))
        XCTAssertFalse(playerFilter.allowsCollision(with: silentEnemyFilter))
    }

    func testMaskCanMatchAnyGroupBit() {
        let player = CollisionGroup.bit(1)
        let trigger = CollisionGroup.bit(3)
        let environment = CollisionGroup.bit(4)

        let mask = CollisionMask(player.union(trigger))

        XCTAssertTrue(mask.intersects(player))
        XCTAssertTrue(mask.intersects(trigger))
        XCTAssertFalse(mask.intersects(environment))
    }
}
