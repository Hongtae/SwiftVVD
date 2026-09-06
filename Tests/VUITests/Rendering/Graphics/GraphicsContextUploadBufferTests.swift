import XCTest
import VVD
@testable import VUI

final class GraphicsContextUploadBufferTests: XCTestCase {
    private final class BufferMetrics {
        var lengthReads = 0
        var contentsReads = 0
        var flushes = 0
        var released = false
    }

    private final class TestBuffer: GPUBuffer {
        let device: GraphicsDevice
        let metrics: BufferMetrics
        private let capacity: Int
        private let storage: UnsafeMutableRawPointer?

        init(device: GraphicsDevice, length: Int, mapped: Bool, metrics: BufferMetrics) {
            self.device = device
            self.capacity = length
            self.metrics = metrics
            self.storage = mapped
                ? UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 4096)
                : nil
        }

        deinit {
            storage?.deallocate()
            metrics.released = true
        }

        var length: Int {
            metrics.lengthReads += 1
            return capacity
        }

        func contents() -> UnsafeMutableRawPointer? {
            metrics.contentsReads += 1
            return storage
        }

        func flush() { metrics.flushes += 1 }
    }

    private final class TestDevice: GraphicsDevice, @unchecked Sendable {
        enum Allocation {
            case mapped(extraCapacity: Int = 0)
            case unmapped
            case failure
        }

        let name = "Upload buffer test device"
        var allocations: [Allocation] = []
        var requests: [(length: Int, storageMode: StorageMode, cpuCacheMode: CPUCacheMode)] = []
        var metrics: [BufferMetrics] = []

        func makeBuffer(length: Int, storageMode: StorageMode,
                        cpuCacheMode: CPUCacheMode) -> GPUBuffer? {
            let index = requests.count
            requests.append((length, storageMode, cpuCacheMode))
            let allocation = index < allocations.count ? allocations[index] : .mapped()
            let mapped: Bool
            let extraCapacity: Int
            switch allocation {
            case .failure: return nil
            case .unmapped:
                mapped = false
                extraCapacity = 0
            case .mapped(let extra):
                mapped = true
                extraCapacity = extra
            }
            let metric = BufferMetrics()
            metrics.append(metric)
            return TestBuffer(device: self, length: length + extraCapacity,
                              mapped: mapped, metrics: metric)
        }

        func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue? { nil }
        func makeShaderModule(from: VVD.Shader) -> ShaderModule? { nil }
        func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet? { nil }
        func makeRenderPipelineState(descriptor: RenderPipelineDescriptor,
                                     reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState? { nil }
        func makeComputePipelineState(descriptor: ComputePipelineDescriptor,
                                      reflection: UnsafeMutablePointer<PipelineReflection>?) -> ComputePipelineState? { nil }
        func makeDepthStencilState(descriptor: DepthStencilDescriptor) -> DepthStencilState? { nil }
        func makeTexture(descriptor: TextureDescriptor) -> Texture? { nil }
        func makeTransientRenderTarget(type: TextureType, pixelFormat: PixelFormat,
                                       width: Int, height: Int, depth: Int,
                                       sampleCount: Int) -> Texture? { nil }
        func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState? { nil }
        func makeEvent() -> GPUEvent? { nil }
        func makeSemaphore() -> GPUSemaphore? { nil }
    }

    private func assertUploaded(_ slice: GraphicsContext.BufferSlice, equals bytes: [UInt8],
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let copied = try withExtendedLifetime(slice.buffer) {
            let contents = try XCTUnwrap(slice.buffer.contents(), file: file, line: line)
            return Array(UnsafeRawBufferPointer(
                start: contents.advanced(by: slice.offset), count: bytes.count
            ))
        }
        XCTAssertEqual(copied, bytes, file: file, line: line)
    }

    func testArenaReusesMappingAndLengthWhileFlushingEveryCopy() throws {
        let device = TestDevice()
        let arena = GraphicsContext.UploadBufferArena(device: device)
        let empty: [UInt8] = []
        XCTAssertNil(empty.withUnsafeBytes { arena.copy($0, alignment: 1) })
        XCTAssertTrue(device.requests.isEmpty)

        var uploads: [(GraphicsContext.BufferSlice, [UInt8])] = []
        var previousEnd = 0
        for index in 0..<32 {
            let bytes = (0..<(19 + index)).map { UInt8($0 + index) }
            let alignment = 1 << (index % 7)
            let expectedAlignment = max(16, alignment)
            let expectedOffset = (previousEnd + expectedAlignment - 1) & ~(expectedAlignment - 1)
            let slice = try XCTUnwrap(bytes.withUnsafeBytes {
                arena.copy($0, alignment: alignment)
            })
            XCTAssertEqual(slice.offset, expectedOffset)
            previousEnd = slice.offset + bytes.count
            uploads.append((slice, bytes))
        }

        XCTAssertEqual(device.requests.map(\.length), [256 * 1024])
        XCTAssertTrue(device.requests.allSatisfy {
            $0.storageMode == .shared && $0.cpuCacheMode == .writeCombined
        })
        XCTAssertEqual(device.metrics[0].lengthReads, 1)
        XCTAssertEqual(device.metrics[0].contentsReads, 1)
        XCTAssertEqual(device.metrics[0].flushes, uploads.count)
        // Explicit readback below is separate from the arena's mapping queries.
        for (slice, bytes) in uploads {
            XCTAssertTrue(slice.buffer === uploads[0].0.buffer)
            try assertUploaded(slice, equals: bytes)
        }
    }

    func testArenaRolloverUsesActualCapacityAndPreservesOversizedSlices() throws {
        let device = TestDevice()
        device.allocations = [.mapped(extraCapacity: 64)]
        let arena = GraphicsContext.UploadBufferArena(device: device)
        let counts = [262144, 64, 1, 262145, 64]
        let offsets = [0, 262144, 0, 0, 262160]
        var uploads: [(GraphicsContext.BufferSlice, [UInt8])] = []
        for (index, count) in counts.enumerated() {
            let bytes = [UInt8](repeating: UInt8(index + 1), count: count)
            let slice = try XCTUnwrap(bytes.withUnsafeBytes { arena.copy($0, alignment: 16) })
            XCTAssertEqual(slice.offset, offsets[index])
            uploads.append((slice, bytes))
        }
        XCTAssertEqual(device.requests.map(\.length), [262144, 262144, 266240])
        XCTAssertEqual(device.metrics.map(\.lengthReads), [1, 1, 1])
        XCTAssertEqual(device.metrics.map(\.contentsReads), [1, 1, 1])
        XCTAssertEqual(device.metrics.map(\.flushes), [2, 1, 2])
        XCTAssertTrue(uploads[0].0.buffer === uploads[1].0.buffer)
        XCTAssertFalse(uploads[1].0.buffer === uploads[2].0.buffer)
        XCTAssertFalse(uploads[2].0.buffer === uploads[3].0.buffer)
        XCTAssertTrue(uploads[3].0.buffer === uploads[4].0.buffer)
        for (slice, bytes) in uploads { try assertUploaded(slice, equals: bytes) }
    }

    func testArenaAllocationAndMappingFailuresKeepExistingStorageUsable() throws {
        let device = TestDevice()
        device.allocations = [.mapped(), .failure, .unmapped, .mapped()]
        let arena = GraphicsContext.UploadBufferArena(device: device)
        let firstBytes = [UInt8](repeating: 7, count: 16)
        let first = try XCTUnwrap(firstBytes.withUnsafeBytes { arena.copy($0, alignment: 16) })
        let largeBytes = [UInt8](repeating: 9, count: 262145)
        XCTAssertNil(largeBytes.withUnsafeBytes { arena.copy($0, alignment: 16) })
        XCTAssertNil(largeBytes.withUnsafeBytes { arena.copy($0, alignment: 16) })
        XCTAssertTrue(device.metrics[1].released)
        XCTAssertEqual(device.metrics[1].contentsReads, 1)
        XCTAssertEqual(device.metrics[1].lengthReads, 0)
        XCTAssertEqual(device.metrics[1].flushes, 0)

        let smallBytes = [UInt8](repeating: 8, count: 32)
        let small = try XCTUnwrap(smallBytes.withUnsafeBytes { arena.copy($0, alignment: 16) })
        XCTAssertTrue(first.buffer === small.buffer)
        XCTAssertEqual(small.offset, 16)
        let large = try XCTUnwrap(largeBytes.withUnsafeBytes { arena.copy($0, alignment: 16) })
        XCTAssertFalse(first.buffer === large.buffer)
        XCTAssertEqual(large.offset, 0)
        XCTAssertEqual(device.requests.count, 4)
        XCTAssertEqual(device.metrics.map(\.flushes), [2, 0, 1])
        try assertUploaded(first, equals: firstBytes)
        try assertUploaded(small, equals: smallBytes)
        try assertUploaded(large, equals: largeBytes)
    }

    func testArenaAndRetainedSliceKeepMappedBufferAlive() throws {
        let device = TestDevice()
        var arena: GraphicsContext.UploadBufferArena? = .init(device: device)
        let bytes: [UInt8] = [2, 3, 5, 7]
        var first: GraphicsContext.BufferSlice? = try XCTUnwrap(
            bytes.withUnsafeBytes { arena!.copy($0, alignment: 16) }
        )
        weak var buffer: GPUBuffer?
        buffer = first!.buffer
        first = nil
        XCTAssertNotNil(buffer)
        XCTAssertFalse(device.metrics[0].released)

        var survivor: GraphicsContext.BufferSlice? = try XCTUnwrap(
            bytes.withUnsafeBytes { arena!.copy($0, alignment: 16) }
        )
        XCTAssertTrue(survivor!.buffer === buffer)
        arena = nil
        XCTAssertNotNil(buffer)
        XCTAssertFalse(device.metrics[0].released)
        try assertUploaded(survivor!, equals: bytes)
        survivor = nil
        XCTAssertNil(buffer)
        XCTAssertTrue(device.metrics[0].released)
    }

    private func makeContext(commandBuffer: CommandBuffer) throws -> GraphicsContext {
        let bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        return try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(), environment: EnvironmentValues(),
            viewport: bounds, contentOffset: .zero, contentScaleFactor: 1,
            resolution: bounds.size, commandBuffer: commandBuffer
        ))
    }

    func testArenaCopiesAlignedSlicesIntoOneBuffer() throws {
        guard let deviceContext = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }

        let arena = GraphicsContext.UploadBufferArena(
            device: deviceContext.device
        )
        let firstBytes: [UInt8] = [1, 2, 3]
        let secondValues: [UInt64] = [0x0807_0605_0403_0201]

        let firstSlice = try XCTUnwrap(firstBytes.withUnsafeBytes {
            arena.copy($0, alignment: MemoryLayout<UInt8>.alignment)
        })
        let secondSlice = try XCTUnwrap(secondValues.withUnsafeBytes {
            arena.copy($0, alignment: MemoryLayout<UInt64>.alignment)
        })

        XCTAssertTrue(firstSlice.buffer === secondSlice.buffer)
        XCTAssertEqual(firstSlice.offset, 0)
        XCTAssertEqual(
            secondSlice.offset % GraphicsContext.UploadBufferArena.allocationAlignment,
            0
        )
        XCTAssertGreaterThanOrEqual(
            secondSlice.offset,
            firstSlice.offset + firstBytes.count
        )

        let contents = try XCTUnwrap(firstSlice.buffer.contents())
        let copiedFirstBytes = Array(
            UnsafeRawBufferPointer(
                start: contents.advanced(by: firstSlice.offset),
                count: firstBytes.count
            )
        )
        let copiedSecondBytes = Array(
            UnsafeRawBufferPointer(
                start: contents.advanced(by: secondSlice.offset),
                count: MemoryLayout<UInt64>.stride * secondValues.count
            )
        )

        XCTAssertEqual(copiedFirstBytes, firstBytes)
        XCTAssertEqual(
            copiedSecondBytes,
            secondValues.withUnsafeBytes { Array($0) }
        )
    }

    func testContextCopiesAndLayersShareScratchWithoutSharingIndependentRoots() throws {
        guard let device = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }
        let queue = try XCTUnwrap(device.renderQueue())
        let context = try makeContext(commandBuffer: XCTUnwrap(queue.makeCommandBuffer()))
        let copy = context
        let layer = try XCTUnwrap(context.makeLayerContext())
        let sizedLayer = try XCTUnwrap(context.makeLayerContext(CGSize(width: 8, height: 8)))
        let independent = try makeContext(commandBuffer: XCTUnwrap(queue.makeCommandBuffer()))
        XCTAssertTrue(context.pathGeometryScratch === copy.pathGeometryScratch)
        XCTAssertTrue(context.pathGeometryScratch === layer.pathGeometryScratch)
        XCTAssertTrue(context.pathGeometryScratch === sizedLayer.pathGeometryScratch)
        XCTAssertFalse(context.pathGeometryScratch === independent.pathGeometryScratch)
    }

    func testScratchReuseDoesNotOverwriteEarlierUploads() throws {
        guard let device = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }
        let queue = try XCTUnwrap(device.renderQueue())
        let context = try makeContext(commandBuffer: XCTUnwrap(queue.makeCommandBuffer()))
        func upload(_ path: Path) throws -> (
            vertices: GraphicsContext.BufferSlice, indices: GraphicsContext.BufferSlice,
            vertexBytes: [UInt8], indexBytes: [UInt8]
        ) {
            let geometry = context.pathGeometryScratch.makeGeometry(path: path, transform: .identity)
            return (
                try XCTUnwrap(context.makeBuffer(geometry.vertices)),
                try XCTUnwrap(context.makeBuffer(geometry.triangleIndices)),
                geometry.vertices.withUnsafeBytes { Array($0) },
                geometry.triangleIndices.withUnsafeBytes { Array($0) }
            )
        }
        let first = try upload(Path(ellipseIn: CGRect(x: 1, y: 2, width: 31, height: 17)))
        let second = try upload(Path(CGRect(x: -10, y: -20, width: 3, height: 4)))
        XCTAssertTrue(first.vertices.buffer === second.vertices.buffer)
        for uploaded in [first, second] {
            for (slice, bytes) in [(uploaded.vertices, uploaded.vertexBytes),
                                   (uploaded.indices, uploaded.indexBytes)] {
                let contents = try XCTUnwrap(slice.buffer.contents())
                let copied = Array(UnsafeRawBufferPointer(
                    start: contents.advanced(by: slice.offset), count: bytes.count
                ))
                XCTAssertEqual(copied, bytes)
            }
        }
    }
}
