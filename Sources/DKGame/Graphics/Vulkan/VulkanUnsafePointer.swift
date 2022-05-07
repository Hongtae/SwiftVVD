#if ENABLE_VULKAN
import Vulkan
import Foundation

class TemporaryBufferHolder {
    var buffers: [UnsafeRawPointer] = []
    let label: String
    init (label: String) {
        self.label = label
    }
    deinit {
        //Log.verbose("<< TemporaryBufferHolder(label:\"\(self.label)\") deallocate \(buffers.count) buffers. >>")
        for ptr in buffers {
            ptr.deallocate()
        }
    }
}

func unsafePointerCopy<T>(from object: T, holder: TemporaryBufferHolder) -> UnsafePointer<T> {
    let buffer: UnsafeMutablePointer<T> = .allocate(capacity: 1)
    withUnsafePointer(to: object) {
        buffer.initialize(from: $0, count: 1)
    }
    holder.buffers.append(buffer)
    return UnsafePointer<T>(buffer)
}

func unsafePointerCopy(string str: String, holder: TemporaryBufferHolder) -> UnsafePointer<CChar> {
    let buffer = str.withCString { ptr -> UnsafePointer<CChar> in
        let length = str.utf8.count + 1
        let buffer: UnsafeMutablePointer<CChar> = .allocate(capacity: length)
        strcpy_s(buffer, length, ptr)
        return UnsafePointer(buffer)
    }
    holder.buffers.append(buffer)
    return buffer
}

func unsafePointerCopy<C>(collection source: C, holder: TemporaryBufferHolder) -> UnsafePointer<C.Element>? where C: Collection {
    if source.isEmpty { return nil }

    let buffer: UnsafeMutableBufferPointer<C.Element> = .allocate(capacity: source.count)
    _ = buffer.initialize(from: source)
    let ptr = UnsafePointer<C.Element>(buffer.baseAddress!)
    holder.buffers.append(ptr)
    return ptr
}

#endif //if ENABLE_VULKAN