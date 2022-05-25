import DKGameUtils
import Foundation

public class AtomicNumber32 {
    private var atomic: DKAtomicNumber32 = DKAtomicNumber32()
    public init(_ value: Int32 = 0) {
        atomic.value = value
    }
    @discardableResult
    public func increment() -> Int32 { DKAtomicNumber32_Increment(&atomic) }
    @discardableResult
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
    public init(_ value: Int64 = 0) {
        atomic.value = value
    }
    @discardableResult
    public func increment() -> Int64 { DKAtomicNumber64_Increment(&atomic) }
    @discardableResult
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

#if DEBUG
private var threadWaitings: [UInt: Set<UInt>] = [:]
private func setThreadWaiting(target: UInt) {
    let threadId: UInt = DKThreadCurrentId()

    if let waitings = threadWaitings[target], waitings.contains(threadId) {
        // deadlock
        fatalError("deadlock detected, threadId:\(threadId), \(target). Waiting for each other to finish.")
    }
    if threadWaitings[threadId] == nil {
        threadWaitings[threadId] = []
    }
    threadWaitings[threadId]!.update(with: target)
}
private func clearThreadWaiting() {
    let threadId: UInt = DKThreadCurrentId()
    threadWaitings[threadId] = nil
}
#else
private func setThreadWaiting(target: UInt) {}
private func clearThreadWaiting() {}
#endif

public func synchronized<Result>(_ context: AnyObject, _ body: () throws -> Result) rethrows -> Result {
    let threadId: UInt = DKThreadCurrentId()
    let key = ObjectIdentifier(context)

    condition.lock()
    while true {
        clearThreadWaiting()
        if var ctxt = lockedContextTable[key] {
            if ctxt.threadId == threadId {
                ctxt.count += 1
                lockedContextTable.updateValue(ctxt, forKey: key)
                break
            } else {
                setThreadWaiting(target: ctxt.threadId)
            }
        } else {
            lockedContextTable.updateValue((threadId: threadId, count: 1), forKey: key)
            break
        }
        condition.wait()
    }
    clearThreadWaiting()
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

public func synchronized(_ context: AnyObject, timeout: Double, _ body: () throws -> Void) rethrows -> Bool {
    let threadId: UInt = DKThreadCurrentId()
    let timer: TickCounter = TickCounter.now
    let key = ObjectIdentifier(context)
    
    var locked = false
    condition.lock()
    while true {
        if var ctxt = lockedContextTable[key] {
            if ctxt.threadId == threadId {
                ctxt.count += 1
                lockedContextTable.updateValue(ctxt, forKey: key)
                locked = true
                break
            }
        } else {
            lockedContextTable.updateValue((threadId: threadId, count: 1), forKey: key)
            locked = true
            break
        }

        let remain = timeout - timer.elapsed
        if remain > 0.0 && condition.wait(until: Date(timeIntervalSinceNow: remain)) {
        } else { // time-out!
            break
        }
    }
    condition.unlock()

    if locked {
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
        try body()
    }
    return locked
}

public func synchronized<Result>(_ objects: [AnyObject], _ body: () throws -> Result) rethrows -> Result {
    let threadId: UInt = DKThreadCurrentId()

    condition.lock()
    while true {
        clearThreadWaiting()
        if objects.allSatisfy({
            let key = ObjectIdentifier($0)
            if let ctxt = lockedContextTable[key] {
                if ctxt.threadId == threadId {
                    return true
                }
                setThreadWaiting(target: ctxt.threadId)
                return false
            }
            return true
        }) {
            objects.forEach { 
                let key = ObjectIdentifier($0)
                if var ctxt = lockedContextTable[key] {
                    ctxt.count += 1
                    lockedContextTable.updateValue(ctxt, forKey: key)
                } else {
                    lockedContextTable.updateValue((threadId: threadId, count: 1), forKey: key)
                }
            }
            break
        }
        condition.wait()
    }
    clearThreadWaiting()
    condition.unlock()
    defer {
        condition.lock()
        var broadcast = false
        objects.forEach { 
            let key = ObjectIdentifier($0)
            var ctxt = lockedContextTable[key]!
            ctxt.count -= 1
            if ctxt.count == 0 {
                lockedContextTable.removeValue(forKey: key)
                broadcast = true
            } else {
                lockedContextTable.updateValue(ctxt, forKey: key)
            }
        }
        if broadcast {
            condition.broadcast()
        }
        condition.unlock()
    }
    return try body()
}

public func synchronized(_ objects: [AnyObject], timeout: Double, _ body: () throws -> Void) rethrows -> Bool {
    let threadId: UInt = DKThreadCurrentId()
    let timer: TickCounter = TickCounter.now

    var locked = false
    condition.lock()
    while true {
        if objects.allSatisfy({
            let key = ObjectIdentifier($0)
            if let ctxt = lockedContextTable[key] {
                return ctxt.threadId == threadId
            }
            return true
        }) {
            objects.forEach { 
                let key = ObjectIdentifier($0)
                if var ctxt = lockedContextTable[key] {
                    ctxt.count += 1
                    lockedContextTable.updateValue(ctxt, forKey: key)
                } else {
                    lockedContextTable.updateValue((threadId: threadId, count: 1), forKey: key)
                }
            }
            locked = true
            break
        } else {
            let remain = timeout - timer.elapsed
            if remain > 0.0 && condition.wait(until: Date(timeIntervalSinceNow: remain)) {
            } else { // time-out!
                break
            }
        }
    }
    condition.unlock()

    if locked {
        defer {
            condition.lock()
            var broadcast = false
            objects.forEach { 
                let key = ObjectIdentifier($0)

                var ctxt = lockedContextTable[key]!
                ctxt.count -= 1
                if ctxt.count == 0 {
                    lockedContextTable.removeValue(forKey: key)
                    broadcast = true
                } else {
                    lockedContextTable.updateValue(ctxt, forKey: key)
                }
            }
            if broadcast {
                condition.broadcast()
            }
            condition.unlock()
        }
        try body()
    }
    return locked
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
