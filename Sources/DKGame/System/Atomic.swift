import DKGameUtils

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

public class SpinLock {
    private let free = Int32(0)
    private let locked = Int32(1)
    private var atomic = AtomicNumber32()

    enum SpinLockError: Error {
        case deadlockDetected
        case objectWasNotLockedByCallingThread
        case objectWasNotLocked
    }

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
    public func unlock() throws {
        guard atomic.compareAndSet(comparand: locked, newValue: free) else {
            throw SpinLockError.objectWasNotLocked
        }
    }
}
