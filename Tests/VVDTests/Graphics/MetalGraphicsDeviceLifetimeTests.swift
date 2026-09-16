#if os(macOS) && DEBUG
import Metal
import XCTest
@testable import VVD

@MainActor
private var retainedMetalBuffer: GPUBuffer?

final class MetalGraphicsDeviceLifetimeTests: XCTestCase {
    @MainActor
    func testSuccessfulInitializersRegisterUntilDeviceDestruction() async throws {
        guard let nativeDevice = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }
        let factories: [() -> MetalGraphicsDevice?] = [
            { MetalGraphicsDevice(device: nativeDevice) },
            { MetalGraphicsDevice() },
            { MetalGraphicsDevice { $0 == nativeDevice.name } },
            { MetalGraphicsDevice(name: nativeDevice.name) },
        ]

        for factory in factories {
            let existingTasks = Set(detachedServiceTasks.keys)
            var device: MetalGraphicsDevice? = try XCTUnwrap(factory())
            weak var weakDevice = device
            try await waitUntil {
                Set(detachedServiceTasks.keys).subtracting(existingTasks).count == 1
            }
            let taskIDs = Set(detachedServiceTasks.keys).subtracting(existingTasks)

            device = nil
            XCTAssertNil(weakDevice, "The monitor must not retain its device")
            try await waitUntil {
                Set(detachedServiceTasks.keys).isDisjoint(with: taskIDs)
            }
        }
    }

    @MainActor
    func testGlobalBufferKeepsLifetimeTaskPendingUntilReleased() async throws {
        guard let nativeDevice = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }
        let existingTasks = Set(detachedServiceTasks.keys)
        var device: MetalGraphicsDevice? = MetalGraphicsDevice(device: nativeDevice)
        weak var weakDevice = device
        retainedMetalBuffer = try XCTUnwrap(device?.makeBuffer(
            length: 256, storageMode: .shared, cpuCacheMode: .defaultCache))
        defer { retainedMetalBuffer = nil }

        try await waitUntil {
            Set(detachedServiceTasks.keys).subtracting(existingTasks).count == 1
        }
        let taskID = try XCTUnwrap(
            Set(detachedServiceTasks.keys).subtracting(existingTasks).first)
#if compiler(>=6.4)
        let task = try XCTUnwrap(detachedServiceTasks[taskID])
#else
        let task = try XCTUnwrap(detachedServiceTasks[taskID]?.task)
#endif

        device = nil
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(weakDevice)
        XCTAssertNotNil(detachedServiceTasks[taskID])
        XCTAssertFalse(task.isCancelled)

        retainedMetalBuffer = nil
        XCTAssertNil(weakDevice)
        XCTAssertTrue(task.isCancelled)
        try await waitUntil { detachedServiceTasks[taskID] == nil }
    }

    @MainActor
    func testFailedInitializationAndImmediateDestructionLeaveNoTask() async throws {
        guard let nativeDevice = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }
        let existingTasks = Set(detachedServiceTasks.keys)
        XCTAssertNil(MetalGraphicsDevice { _ in false })

        weak var weakDevice: MetalGraphicsDevice?
        do {
            let device = MetalGraphicsDevice(device: nativeDevice)
            weakDevice = device
        }
        XCTAssertNil(weakDevice)
        // Registration is queued on this actor, so destruction happened first.
        try await Task.sleep(for: .milliseconds(50))
        try await waitUntil {
            Set(detachedServiceTasks.keys).subtracting(existingTasks).isEmpty
        }
    }

    @MainActor
    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for lifetime task cleanup",
                      file: file, line: line)
    }
}
#endif
