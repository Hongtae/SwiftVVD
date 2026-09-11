import Dispatch
import Synchronization
import XCTest
@testable import VUI

private struct CollisionKey: Hashable, Sendable {
    let value: Int
    func hash(into hasher: inout Hasher) { hasher.combine(0) }
}

private final class CachedObject: Sendable {
    let key: Int
    let generation: Int
    init(key: Int, generation: Int) {
        self.key = key
        self.generation = generation
    }
}

final class ObjectCacheTests: XCTestCase {
    private typealias Cache = ObjectCache<CollisionKey, CachedObject>

    // ASSERTIONS canvasResourceOwnerFieldsObserved
    func testAtomicBoxCopiesShareTheirMutableBuffer() {
        let first = AtomicBox(wrappedValue: 0)
        let copy = first
        copy.access { $0 = 7 }
        XCTAssertEqual(first.access { $0 }, 7)
    }

    private func entries(_ cache: Cache) -> [Int] {
        cache._data.access { $0.table.compactMap { $0.data?.key.value } }
    }

    // ASSERTIONS objectCacheBucketReplacementObserved
    func testCollisionsUseAllFourSlotsAndRefreshRecencyOnHits() {
        let constructed = Mutex<[Int]>([])
        let cache = Cache { key in
            let generation = constructed.withLock { values in
                values.append(key.value)
                return values.count
            }
            return CachedObject(key: key.value, generation: generation)
        }
        let first = cache[CollisionKey(value: 0)]
        for key in [1,2,3,0,4,2,5,0] { _ = cache[CollisionKey(value: key)] }
        XCTAssertEqual(entries(cache), [0,4,2,5])
        XCTAssertEqual(constructed.withLock { $0 }, [0,1,2,3,4,5])
        XCTAssertTrue(first === cache[CollisionKey(value: 0)])
        XCTAssertEqual(cache._data.access { $0.clock }, 10)
        XCTAssertEqual(cache[CollisionKey(value: 1)].generation, 7)
    }

    // ASSERTIONS objectCacheBucketReplacementObserved
    func testOptionalNilIsACachedValue() {
        let count = Mutex(0)
        let cache = ObjectCache<Int, Int?> { _ in
            count.withLock { $0 += 1 }
            return nil
        }
        XCTAssertNil(cache[3])
        XCTAssertNil(cache[3])
        XCTAssertEqual(count.withLock { $0 }, 1)
    }

    // ASSERTIONS objectCacheWrappingRecencyObserved
    func testRecencySurvivesUInt32Wrap() {
        let cache = Cache { CachedObject(key: $0.value, generation: 0) }
        cache._data.access { $0.clock = UInt32.max - 4 }
        for key in 0..<4 { _ = cache[CollisionKey(value: key)] }
        _ = cache[CollisionKey(value: 0)]
        XCTAssertEqual(cache._data.access { $0.clock }, 0)
        _ = cache[CollisionKey(value: 4)]
        XCTAssertEqual(entries(cache), [0,4,2,3])
        XCTAssertEqual(cache._data.access { $0.clock }, 1)
    }

    // ASSERTIONS objectCacheWrappingRecencyObserved
    func testSignedRecencyAndTiesUseTheFirstGreatestAge() {
        for signed in [false, true] {
            let cache = Cache { CachedObject(key: $0.value, generation: 0) }
            for key in 0..<4 { _ = cache[CollisionKey(value: key)] }
            cache._data.access { data in
                data.clock = signed ? 0 : 100
                let stamps: [UInt32] = signed ? [0x80000000,0x80000001,0xffffffff,0] : [100,100,100,100]
                let indices = data.table.indices.filter { data.table[$0].data != nil }
                for (index, stamp) in zip(indices, stamps) { data.table[index].used = stamp }
            }
            _ = cache[CollisionKey(value: 4)]
            XCTAssertEqual(entries(cache), signed ? [0,4,2,3] : [4,1,2,3])
        }
    }

    // ASSERTIONS objectCacheUnlockedPublicationObserved
    func testConcurrentSameKeyMissesReturnTheirOwnCandidates() {
        checkConcurrentPublication(secondKey: 0)
    }

    // ASSERTIONS objectCacheUnlockedPublicationObserved
    func testConcurrentCollidingMissesPublishIntoTheirPreviouslySelectedSlot() {
        checkConcurrentPublication(secondKey: 1)
    }

    private func checkConcurrentPublication(secondKey: Int) {
        let started = DispatchSemaphore(value: 0)
        let finishFirst = DispatchSemaphore(value: 0)
        let done = DispatchGroup()
        let count = Mutex(0)
        let firstResult = Mutex<CachedObject?>(nil)
        let cache = Cache { key in
            let generation = count.withLock { $0 += 1; return $0 }
            if generation == 1 {
                started.signal()
                XCTAssertEqual(finishFirst.wait(timeout: .now() + 5), .success)
            }
            return CachedObject(key: key.value, generation: generation)
        }
        done.enter()
        DispatchQueue.global().async {
            let value = cache[CollisionKey(value: 0)]
            firstResult.withLock { $0 = value }
            done.leave()
        }
        defer { finishFirst.signal() }
        guard started.wait(timeout: .now() + 5) == .success else {
            return XCTFail("The first constructor did not start.")
        }
        let second = cache[CollisionKey(value: secondKey)]
        XCTAssertEqual(second.generation, 2)
        finishFirst.signal()
        XCTAssertEqual(done.wait(timeout: .now() + 5), .success)
        let first = firstResult.withLock { $0 }
        XCTAssertEqual(first?.generation, 1)
        XCTAssertFalse(first === second)
        XCTAssertEqual(entries(cache), [0])
        XCTAssertTrue(first === cache[CollisionKey(value: 0)])
        XCTAssertEqual(count.withLock { $0 }, 2)
    }

    // ASSERTIONS objectCacheUnlockedPublicationObserved
    func testConstructorCanResolveAnotherKeyWithoutHoldingTheCacheLock() {
        let owner = Mutex<Cache?>(nil)
        let cache = Cache { key in
            if key.value == 0 {
                let nested = owner.withLock { $0! }
                XCTAssertEqual(nested[CollisionKey(value: 1)].key, 1)
            }
            return CachedObject(key: key.value, generation: 0)
        }
        owner.withLock { $0 = cache }
        defer { owner.withLock { $0 = nil } }
        XCTAssertEqual(cache[CollisionKey(value: 0)].key, 0)
        XCTAssertEqual(entries(cache), [0])
    }

    // ASSERTIONS objectCacheBucketReplacementObserved
    func testEvictionReleasesTheCachedValue() {
        let cache = Cache { CachedObject(key: $0.value, generation: 0) }
        weak var first = cache[CollisionKey(value: 0)]
        XCTAssertNotNil(first)
        for key in 1...4 { _ = cache[CollisionKey(value: key)] }
        XCTAssertNil(first)
        XCTAssertEqual(entries(cache), [4,1,2,3])
    }
}
