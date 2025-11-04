//
//  File: VulkanDeviceMemory.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

struct VulkanMemoryBlock {
    let offset: UInt64
    let size: UInt64
    unowned var chunk: VulkanMemoryChunk?

    var propertyFlags: VkMemoryPropertyFlags {
        return chunk?.propertyFlags ?? 0
    }
}

struct VulkanMemoryAllocationContext {
    let device: VkDevice
    let atomSize: VkDeviceSize
    let allocationCallbacks: ()->UnsafePointer<VkAllocationCallbacks>?
}

final class VulkanMemoryChunk {
    let chunkSize: UInt64
    let blockSize: UInt64
    let totalBlocks: UInt64
    let dedicated: Bool

    var mapped: UnsafeMutableRawPointer?

    let propertyFlags: VkMemoryPropertyFlags
    let memory: VkDeviceMemory
    unowned let pool: VulkanMemoryPool
    unowned let allocator: VulkanMemoryAllocator?

    private let context: VulkanMemoryAllocationContext
    private var freeBlocks: [VulkanMemoryBlock]

    @discardableResult
    func invalidate(offset: UInt64, size: UInt64) -> Bool {
        if self.mapped != nil &&
           (propertyFlags & UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue)) == 0 {
            if offset < chunkSize {
                let atomSize = context.atomSize
                let alignUp = { (value: UInt64) -> UInt64 in
                    return value % atomSize == 0 ? value : value + atomSize - (value % atomSize)
                }

                var range = VkMappedMemoryRange()
                range.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE
                range.memory = memory
                // VUID-VkMappedMemoryRange-offset-00687
                range.offset = alignUp(offset)
                if size == VK_WHOLE_SIZE {
                    range.size = size
                } else {
                    // VUID-VkMappedMemoryRange-size-01390
                    let begin = alignUp(offset)
                    let end = alignUp(offset + size)
                    range.size = min(end - begin, chunkSize - begin)
                }
                let result = vkInvalidateMappedMemoryRanges(context.device, 1, &range)
                if result == VK_SUCCESS {
                    return true
                } else {
                    Log.err("vkInvalidateMappedMemoryRanges failed: \(result)")
                }
            } else {
                Log.err("VulkanMemoryChunk.invalidate() failed: Out of range")
            }
        }
        return false
    }

    @discardableResult
    func flush(offset: UInt64, size: UInt64) -> Bool {
        if self.mapped != nil &&
           (propertyFlags & UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue)) == 0 {
           
            if offset < chunkSize {
                let atomSize = context.atomSize
                let alignUp = { (value: UInt64) -> UInt64 in
                    return value % atomSize == 0 ? value : value + atomSize - (value % atomSize)
                }

                var range = VkMappedMemoryRange()
                range.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE
                range.memory = memory
                // VUID-VkMappedMemoryRange-offset-00687
                range.offset = alignUp(offset)
                if size == VK_WHOLE_SIZE {
                    range.size = size
                } else {
                    // VUID-VkMappedMemoryRange-size-01389
                    let begin = alignUp(offset)
                    let end = alignUp(offset + size)
                    range.size = min(end - begin, chunkSize - begin)
                }
                let result = vkFlushMappedMemoryRanges(context.device, 1, &range)
                if result == VK_SUCCESS {
                    return true
                } else {
                    Log.err("vkFlushMappedMemoryRanges failed: \(result)")
                }
            } else {
                Log.err("VulkanMemoryChunk.flush() failed: Out of range")
            }
        }
        return false
    }

    func push(_ block: VulkanMemoryBlock) {
        assert(block.chunk === self)
        assert(block.size <= self.blockSize)
        assert(block.offset < self.chunkSize)

        let block2 = VulkanMemoryBlock(offset: block.offset, size: blockSize, chunk: self)
        freeBlocks.append(block2)
        assert(freeBlocks.count <= totalBlocks)
    }

    func pop() -> VulkanMemoryBlock? {
        freeBlocks.popLast()
    }

    var numFreeBlocks: Int { freeBlocks.count }

    init(context: VulkanMemoryAllocationContext,
         pool: VulkanMemoryPool,
         allocator: VulkanMemoryAllocator?,
         memory: VkDeviceMemory,
         propertyFlags: VkMemoryPropertyFlags,
         chunkSize: UInt64,
         blockSize: UInt64,
         totalBlocks: UInt64,
         dedicated: Bool) {
        let atomSize = context.atomSize
        assert(chunkSize % atomSize == 0)

        self.context = context
        self.pool = pool
        self.allocator = allocator
        self.memory = memory
        self.propertyFlags = propertyFlags
        self.chunkSize = chunkSize
        self.blockSize = blockSize
        self.totalBlocks = totalBlocks
        self.dedicated = dedicated

        if propertyFlags & UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue) != 0 {
            let offset: VkDeviceSize = 0
            let size: VkDeviceSize = VK_WHOLE_SIZE

            let result = vkMapMemory(context.device, memory, offset, size, 0, &mapped)
            if result != VK_SUCCESS {
                Log.err("vkMapMemory failed: \(result)")
            }
        }

        self.freeBlocks = []
        freeBlocks.reserveCapacity(Int(totalBlocks))
        var offset: UInt64 = 0
        for _ in 0..<totalBlocks {
            let block = VulkanMemoryBlock(offset: offset, size: blockSize, chunk: self)
            freeBlocks.append(block)
            offset += blockSize
        }
    }

    deinit {
        assert(freeBlocks.count == totalBlocks)        
        if self.mapped != nil {
            vkUnmapMemory(context.device, self.memory)
            self.mapped = nil
        }
        vkFreeMemory(context.device, self.memory, context.allocationCallbacks())
    }
}

final class VulkanMemoryAllocator {
    var numAllocations: Int {
        mutex.withLock {
            chunks.reduce(0) { result, chunk in
                result + Int(chunk.totalBlocks) - chunk.numFreeBlocks
            }
        }
    }

    var numDeviceAllocations: Int { 
        mutex.withLock { chunks.count }
    }

    var totalMemorySize: UInt64 { 
        mutex.withLock {
            chunks.reduce(UInt64(0)) { result, chunk in
                result + UInt64(chunk.chunkSize)
            }
        }
    }

    var memorySizeInUse: UInt64 { 
        mutex.withLock { self.memoryInUse }
    }

    func alloc(_ size: UInt64) -> VulkanMemoryBlock? {
        if size > blockSize { return nil }

        mutex.lock()
        defer { mutex.unlock() }

        if let chunk = self.chunks.first(where: { $0.numFreeBlocks > 0 }) {
            let block = chunk.pop()!
            assert(block.size >= size)
            self.memoryInUse += size
            return VulkanMemoryBlock(offset: block.offset, size: size, chunk: block.chunk)
        }
        // allocate new chunk
        let context = pool.context
        let memoryTypeIndex = pool.memoryTypeIndex
        let memoryPropertyFlags = pool.memoryPropertyFlags
        
        let chunkSize = blockSize * blocksPerChunk

        var memAllocInfo = VkMemoryAllocateInfo()
        memAllocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        memAllocInfo.allocationSize = chunkSize
        memAllocInfo.memoryTypeIndex = memoryTypeIndex

        var memory: VkDeviceMemory? = nil
        let result = vkAllocateMemory(context.device, &memAllocInfo, context.allocationCallbacks(), &memory)
        if result != VK_SUCCESS {
            Log.err("vkAllocateMemory failed: \(result)")
            return nil
        }

        let chunk = VulkanMemoryChunk(context: context,
                                      pool: pool,
                                      allocator: self,
                                      memory: memory!,
                                      propertyFlags: memoryPropertyFlags,
                                      chunkSize: chunkSize,
                                      blockSize: blockSize,
                                      totalBlocks: blocksPerChunk,
                                      dedicated: false)
        self.chunks.append(chunk)
        let block = chunk.pop()!
        assert(block.size >= size)
        self.memoryInUse += size
        return VulkanMemoryBlock(offset: block.offset, size: size, chunk: block.chunk)
    }

    func dealloc(_ block: inout VulkanMemoryBlock) {
        if let chunk = block.chunk {
            mutex.lock()
            defer { mutex.unlock() }

            assert(chunk.allocator === self)
            assert(chunk.blockSize == self.blockSize)
            assert(self.memoryInUse >= block.size)
            self.memoryInUse -= block.size
            chunk.push(block)
            block.chunk = nil

            if chunk.numFreeBlocks == chunk.totalBlocks {
                let freeBlocks = self.chunks.reduce(0) { result, chunk in
                    result + chunk.numFreeBlocks
                }
                if freeBlocks > blocksPerChunk + (blocksPerChunk >> 2) {
                    if let index = self.chunks.firstIndex(where: { $0 === chunk }) {
                        self.chunks.remove(at: index)
                    }
                }
            }
            // sort by most used to reduce fragmentation
            chunks.sort { $0.numFreeBlocks < $1.numFreeBlocks }
        }
    }

    func purge() -> UInt64 {
        var purged: UInt64 = 0
        mutex.lock()
        defer { mutex.unlock() }
        while true {
            let index = chunks.firstIndex(where: {
                $0.numFreeBlocks == $0.totalBlocks
            })
            guard let index else { break }
            let chunk = chunks[index]
            purged += chunk.chunkSize
            chunks.remove(at: index)
        }
        return purged
    }

    let blockSize: UInt64
    let blocksPerChunk: UInt64

    unowned let pool: VulkanMemoryPool

    private let mutex = NSLock()
    private var memoryInUse: UInt64 = 0
    private var chunks: [VulkanMemoryChunk] = []

    init(pool: VulkanMemoryPool, size: UInt64, blocks: UInt64) {
        self.pool = pool
        self.blockSize = size
        self.blocksPerChunk = blocks
    }
}

private let memoryChunkSizeBlocks: [(blockSize: UInt64, numBlocks: UInt64)] = [
    ( 1024, 512 ),
    ( 2048, 512 ),
    ( 4096, 512 ),
    ( 8192, 512 ),
    ( 16384, 256 ),
    ( 32768, 256 ),
    ( 65536, 256 ),
    ( 131072, 256 ),
    ( 262144, 256 ),
    ( 524288, 256 ),
    ( 1048576, 128 ),
    ( 2097152, 64 ),
    ( 4194304, 32 ),
    ( 8388608, 16 ),
    ( 16777216, 8 ),
    ( 33554432, 4 ), // 32M
]

final class VulkanMemoryPool {
    let memoryTypeIndex: UInt32
    let memoryPropertyFlags: VkMemoryPropertyFlags
    let memoryHeap: VkMemoryHeap

    func alloc(size: UInt64) -> VulkanMemoryBlock? {
        assert(size > 0)

        let lowerBound = { (size: UInt)-> VulkanMemoryAllocator? in
            var first = 0
            var count = self.allocators.count
            while count > 0 {
                let step = count / 2
                let pos = first + step
                if self.allocators[pos].blockSize < size {
                    first = pos + 1
                    count -= step + 1
                } else {
                    count = step
                }
            }
            if first < self.allocators.count {
                return self.allocators[first]
            }
            return nil
        }
        if let allocator = lowerBound(UInt(size)) {
            assert(allocator.blockSize >= size)
            return allocator.alloc(size)
        }

        var memAllocInfo = VkMemoryAllocateInfo()
        memAllocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        memAllocInfo.allocationSize = size
        memAllocInfo.memoryTypeIndex = self.memoryTypeIndex
        var memory: VkDeviceMemory? = nil
        let result = vkAllocateMemory(context.device, &memAllocInfo, context.allocationCallbacks(), &memory)
        if result != VK_SUCCESS {
            Log.error("vkAllocateMemory failed: \(result)")
            return nil
        }
        let chunk = VulkanMemoryChunk(context: context,
                                      pool: self,
                                      allocator: nil,
                                      memory: memory!,
                                      propertyFlags: memoryPropertyFlags,
                                      chunkSize: size,
                                      blockSize: size,
                                      totalBlocks: 1,
                                      dedicated: false)
        mutex.lock()
        defer { mutex.unlock() }
        self.dedicatedAllocations.updateValue(chunk, forKey: ObjectIdentifier(chunk))
        return chunk.pop()
    }

    func allocDedicated(size: UInt64, image: VkImage?, buffer: VkBuffer?) -> VulkanMemoryBlock? {
        if image != nil && buffer != nil {
            Log.error("At least one of image and buffer must be nil.");
            return nil
        }
        assert(size > 0)

        var memAllocInfo = VkMemoryAllocateInfo()
        memAllocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        memAllocInfo.allocationSize = size
        memAllocInfo.memoryTypeIndex = self.memoryTypeIndex

        var memoryDedicatedAllocateInfo = VkMemoryDedicatedAllocateInfo()
        memoryDedicatedAllocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO
        memoryDedicatedAllocateInfo.image = image
        memoryDedicatedAllocateInfo.buffer = buffer

        var memory: VkDeviceMemory? = nil
        let result = withUnsafePointer(to: memoryDedicatedAllocateInfo) {
            memAllocInfo.pNext = UnsafeRawPointer($0)
            return vkAllocateMemory(context.device, &memAllocInfo, context.allocationCallbacks(), &memory)
        }
        if result != VK_SUCCESS {
            Log.error("vkAllocateMemory failed: \(result)")
            return nil
        }
        let chunk = VulkanMemoryChunk(context: context,
                                      pool: self,
                                      allocator: nil,
                                      memory: memory!,
                                      propertyFlags: memoryPropertyFlags,
                                      chunkSize: size,
                                      blockSize: size,
                                      totalBlocks: 1,
                                      dedicated: false)
        mutex.lock()
        defer { mutex.unlock() }
        self.dedicatedAllocations.updateValue(chunk, forKey: ObjectIdentifier(chunk))
        return chunk.pop()
    }

    func dealloc(_ block: inout VulkanMemoryBlock) {
        if let chunk = block.chunk {
            assert(chunk.pool === self)
            if let allocator = chunk.allocator {
                assert(allocator.pool === self)
                allocator.dealloc(&block)
            } else {
                mutex.lock()
                assert(dedicatedAllocations[ObjectIdentifier(chunk)] === chunk)
                dedicatedAllocations[ObjectIdentifier(chunk)] = nil
                mutex.unlock()

                chunk.push(block)
                block.chunk = nil
            }
        }
    }

    func purge() -> UInt64 {
        allocators.reduce(UInt64(0)) { result, alloc in
            result + alloc.purge()
        }
    }

    var numAllocations: Int {
        let count = allocators.reduce(0) { result, alloc in
            result + alloc.numAllocations
        }
        return mutex.withLock { count + dedicatedAllocations.count }
    }

    var numDeviceAllocations: Int { 
        let count = allocators.reduce(0) { result, alloc in
            result + alloc.numDeviceAllocations
        }
        return mutex.withLock { count + dedicatedAllocations.count }
    }

    var totalMemorySize: UInt64 { 
        let size = allocators.reduce(UInt64(0)) { result, alloc in
            result + alloc.totalMemorySize
        }
        return mutex.withLock {
            dedicatedAllocations.reduce(size) { result, element in
                return result + element.1.chunkSize
            }
        }
    }

    var memorySizeInUse: UInt64 { 
        let size = allocators.reduce(UInt64(0)) { result, alloc in
            result + alloc.memorySizeInUse
        }
        return mutex.withLock {
            dedicatedAllocations.reduce(size) { result, element in
                return result + element.1.chunkSize
            }
        }
    }

    let context: VulkanMemoryAllocationContext

    private var allocators: [VulkanMemoryAllocator]
    private let mutex = NSLock()
    var dedicatedAllocations: [ObjectIdentifier: VulkanMemoryChunk] = [:]

    init(context: VulkanMemoryAllocationContext, typeIndex: UInt32, flags: VkMemoryPropertyFlags, heap: VkMemoryHeap) {
        self.context = context
        self.memoryTypeIndex = typeIndex
        self.memoryPropertyFlags = flags
        self.memoryHeap = heap

        self.allocators = []
        self.allocators = memoryChunkSizeBlocks.map {
            VulkanMemoryAllocator(pool: self, size: $0.blockSize, blocks: $0.numBlocks)
        }
    }

    deinit {
        assert(dedicatedAllocations.isEmpty)
    }
}
#endif //if ENABLE_VULKAN
