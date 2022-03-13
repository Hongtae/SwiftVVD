import DKGameUtils
import Foundation

public class AtomicNumber32 {
    private var atomic: DKAtomicNumber32 = DKAtomicNumber32()
    public init() {
        atomic.value = 0
    }
    public func increment() -> Int32 { DKAtomicNumber32_Increment(&atomic) }
    public func decrement() -> Int32 { DKAtomicNumber32_Decrement(&atomic) }

    public func add(_ addend: Int32) -> Int32 {
        DKAtomicNumber32_Add(&atomic, addend)
    }
    public func exchange(_ value: Int32) -> Int32 {
        DKAtomicNumber32_Exchange(&atomic, value)
    }
    public func compareAndSet(comparand: Int32, newValue: Int32) -> Bool {
        DKAtomicNumber32_CompareAndSet(&atomic, comparand, newValue)
    }
    public func load() -> Int32 {
        var value = DKAtomicNumber32_Value(&atomic)
        while DKAtomicNumber32_CompareAndSet(&atomic, value, value) == false {
            value = DKAtomicNumber32_Value(&atomic)
        }
        return value
    }
    public func store(_ value: Int32) {
        DKAtomicNumber32_Exchange(&atomic, value)
    }
    public var value: Int32 { DKAtomicNumber32_Value(&atomic) }
}

public class AtomicNumber64 {
    private var atomic: DKAtomicNumber64 = DKAtomicNumber64()
    public init() {
        atomic.value = 0
    }
    public func increment() -> Int64 { DKAtomicNumber64_Increment(&atomic) }
    public func decrement() -> Int64 { DKAtomicNumber64_Decrement(&atomic) }

    public func add(_ addend: Int64) -> Int64 {
        DKAtomicNumber64_Add(&atomic, addend)
    }
    public func exchange(_ value: Int64) -> Int64 {
        DKAtomicNumber64_Exchange(&atomic, value)
    }
    public func compareAndSet(comparand: Int64, newValue: Int64) -> Bool {
        DKAtomicNumber64_CompareAndSet(&atomic, comparand, newValue)
    }
    public func load() -> Int64 {
        var value = DKAtomicNumber64_Value(&atomic)
        while DKAtomicNumber64_CompareAndSet(&atomic, value, value) == false {
            value = DKAtomicNumber64_Value(&atomic)
        }
        return value
    }
    public func store(_ value: Int64) {
        DKAtomicNumber64_Exchange(&atomic, value)
    }
    public var value: Int64 { DKAtomicNumber64_Value(&atomic) }
}

public class SpinLock: NSLocking {
    private let free = Int32(0)
    private let locked = Int32(1)
    private var atomic = AtomicNumber32()

    public init() {
        atomic.store(free)
    }
    public func tryLock() -> Bool {
        atomic.compareAndSet(comparand: free, newValue: locked)
    }
    public func lock() {
        while tryLock() == false {
            DKThreadYield()
        }
    }
    public func unlock() {
        guard atomic.compareAndSet(comparand: locked, newValue: free) else {
            fatalError("Error! object was not locked.")
        }
    }
}

private var lockedContextTable: [ObjectIdentifier: (threadId: UInt, count: UInt64)] = .init()
private let condition: NSCondition = NSCondition()

public func synchronized<Result>(_ context: AnyObject, _ body: () throws -> Result) rethrows -> Result {
    let threadId: UInt = DKThreadCurrentId()
    let key = ObjectIdentifier(context)
    condition.lock()
    while true {
        if var ctxt = lockedContextTable[key] {
            if ctxt.threadId == threadId {
                ctxt.count += 1
                lockedContextTable.updateValue(ctxt, forKey: key)
                break
            }
        } else {
            lockedContextTable.updateValue((threadId: threadId, count: 1), forKey: key)
            break
        }
        condition.wait()
    }
    condition.unlock()
    defer {
        condition.lock()
        var ctxt = lockedContextTable[key]!
        ctxt.count -= 1
        if ctxt.count == 0 {
            lockedContextTable.removeValue(forKey: key)
            condition.broadcast()
        } else {
            lockedContextTable.updateValue(ctxt, forKey: key)
        }
        condition.unlock()
    }
    return try body()
}

public func synchronizedBy<Result>(locking lock: NSLocking, _ body: () throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body()
}

public func threadYield() {
    DKThreadYield()
}

public func threadId() -> UInt {
    return DKThreadCurrentId()
}
