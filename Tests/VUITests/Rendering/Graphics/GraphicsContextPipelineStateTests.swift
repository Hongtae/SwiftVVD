import Foundation
import Synchronization
import XCTest
import VVD
@testable import VUI

final class GraphicsContextPipelineStateTests: XCTestCase {
    private let modes: [_Stencil] = [
        .makeFill, .makeStroke, .testNonZero, .testEven, .testZero, .testOdd, .ignore
    ]

    private final class TestState: DepthStencilState {
        let device: GraphicsDevice
        let descriptor: DepthStencilDescriptor

        init(device: GraphicsDevice, descriptor: DepthStencilDescriptor) {
            self.device = device
            self.descriptor = descriptor
        }
    }

    private final class TestRenderState: RenderPipelineState {
        let device: GraphicsDevice
        init(device: GraphicsDevice) { self.device = device }
    }

    private final class TestFunction: VVD.ShaderFunction {
        // The test device retains descriptors containing these functions.
        unowned let owner: TestDevice
        var device: GraphicsDevice { owner }
        let stage: ShaderStage
        init(device: TestDevice, stage: ShaderStage) {
            self.owner = device
            self.stage = stage
        }
        var stageInputAttributes: [ShaderAttribute] { [] }
        var functionConstants: [String: ShaderFunctionConstant] { [:] }
        var functionName: String { "pipeline_test" }
    }

    private final class TestDevice: GraphicsDevice, @unchecked Sendable {
        let name = "Pipeline state test device"
        let features: GraphicsDeviceFeatures = []

        private var renderFailures = 0
        private var renderDescriptors: [RenderPipelineDescriptor] = []

        var renderRequests: [RenderPipelineDescriptor] {
            lock.lock()
            defer { lock.unlock() }
            return renderDescriptors
        }

        func failNextRenderStates(_ count: Int) {
            lock.lock()
            defer { lock.unlock() }
            renderFailures = count
        }

        private let lock = NSLock()
        private var failures = 0
        private var descriptors: [DepthStencilDescriptor] = []
        private var bindingFailures = 0
        private var requestedBindingLayouts: [ShaderBindingSetLayout] = []

        var bindingLayouts: [ShaderBindingSetLayout] {
            lock.lock()
            defer { lock.unlock() }
            return requestedBindingLayouts
        }

        func failNextBindingSets(_ count: Int) {
            lock.lock()
            defer { lock.unlock() }
            bindingFailures = count
        }

        var requests: [DepthStencilDescriptor] {
            lock.lock()
            defer { lock.unlock() }
            return descriptors
        }

        func failNext(_ count: Int) {
            lock.lock()
            defer { lock.unlock() }
            failures = count
        }

        func makeDepthStencilState(descriptor: DepthStencilDescriptor) -> DepthStencilState? {
            lock.lock()
            defer { lock.unlock() }
            descriptors.append(descriptor)
            if failures > 0 {
                failures -= 1
                return nil
            }
            return TestState(device: self, descriptor: descriptor)
        }

        func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue? { nil }
        func makeShaderModule(from: VVD.Shader) -> ShaderModule? { nil }
        func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet? {
            lock.lock()
            defer { lock.unlock() }
            requestedBindingLayouts.append(layout)
            if bindingFailures > 0 {
                bindingFailures -= 1
                return nil
            }
            return TestBindingSet(device: self)
        }
        func makeRenderPipelineState(descriptor: RenderPipelineDescriptor,
                                     reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState? {
            lock.lock()
            defer { lock.unlock() }
            renderDescriptors.append(descriptor)
            if renderFailures > 0 {
                renderFailures -= 1
                return nil
            }
            return TestRenderState(device: self)
        }
        func makeComputePipelineState(descriptor: ComputePipelineDescriptor,
                                      reflection: UnsafeMutablePointer<PipelineReflection>?) -> ComputePipelineState? { nil }
        func makeBuffer(length: Int, storageMode: StorageMode, cpuCacheMode: CPUCacheMode) -> GPUBuffer? { nil }
        func makeTexture(descriptor: TextureDescriptor) -> Texture? { nil }
        func makeTransientRenderTarget(type: TextureType, pixelFormat: PixelFormat,
                                       width: Int, height: Int, depth: Int, sampleCount: Int) -> Texture? { nil }
        func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState? { nil }
        func makeEvent() -> GPUEvent? { nil }
        func makeSemaphore() -> GPUSemaphore? { nil }
    }

    private final class TestSampler: SamplerState {
        let device: GraphicsDevice
        init(device: GraphicsDevice) { self.device = device }
    }

    private final class TestTexture: Texture {
        let device: GraphicsDevice
        init(device: GraphicsDevice) { self.device = device }
        var pixelFormat: PixelFormat { .r8Unorm }
        var width: Int { 2 }
        var height: Int { 2 }
        var depth: Int { 1 }
        var mipmapCount: Int { 1 }
        var arrayLength: Int { 1 }
        var sampleCount: Int { 1 }
        var type: TextureType { .type2D }
        var isTransient: Bool { false }
        func makeTextureView(pixelFormat: PixelFormat) -> Texture? { nil }
    }

    private final class TestBindingSet: ShaderBindingSet {
        private struct Bindings: Sendable {
            var textures: [Int: Texture] = [:]
            var samplers: [Int: SamplerState] = [:]
            var samplerWrites: [Int] = []
        }

        let device: GraphicsDevice
        private let bindings = Mutex(Bindings())

        var textures: [Int: Texture] { bindings.withLock { $0.textures } }
        var samplers: [Int: SamplerState] { bindings.withLock { $0.samplers } }
        var samplerWrites: [Int] { bindings.withLock { $0.samplerWrites } }

        init(device: GraphicsDevice) { self.device = device }
        func setBuffer(_ buffer: GPUBuffer, offset: Int, length: Int, binding: Int) {}
        func setBufferArray(_ buffers: [BufferBindingInfo], binding: Int) {}
        func setTexture(_ texture: Texture, binding: Int) {
            bindings.withLock { $0.textures[binding] = texture }
        }
        func setTextureArray(_ textures: [Texture], binding: Int) {
            for (offset, texture) in textures.enumerated() {
                setTexture(texture, binding: binding + offset)
            }
        }
        func setSamplerState(_ sampler: SamplerState, binding: Int) {
            bindings.withLock {
                $0.samplers[binding] = sampler
                $0.samplerWrites.append(binding)
            }
        }
        func setSamplerStateArray(_ samplers: [SamplerState], binding: Int) {
            for (offset, sampler) in samplers.enumerated() {
                setSamplerState(sampler, binding: binding + offset)
            }
        }
    }

    private func makePipeline(_ device: TestDevice) -> GraphicsPipelineStates {
        GraphicsPipelineStates(
            device: device, shaderFunctions: [:],
            bindingLayout1: .init(bindings: [
                .init(binding: 0, type: .textureSampler, arrayLength: 1)
            ]),
            bindingLayout2: .init(bindings: [
                .init(binding: 0, type: .textureSampler, arrayLength: 1),
                .init(binding: 1, type: .textureSampler, arrayLength: 1)
            ]),
            defaultSampler: TestSampler(device: device), defaultMaskTexture: TestTexture(device: device))
    }

    func testSingleTextureBindingSetInitializesDefaultSamplerOnce() throws {
        let device = TestDevice()
        let pipeline = makePipeline(device)
        let bindings = try XCTUnwrap(pipeline.makeBindingSet1() as? TestBindingSet)
        XCTAssertEqual(bindings.samplerWrites, [0])
        let sampler = try XCTUnwrap(bindings.samplers[0] as? TestSampler)
        XCTAssertTrue(sampler === pipeline.defaultSampler as? TestSampler)
        XCTAssertTrue(bindings.textures.isEmpty)
        XCTAssertEqual(device.bindingLayouts.count, 1)
        XCTAssertEqual(device.bindingLayouts[0].bindings.map(\.binding), [0])
        XCTAssertEqual(device.bindingLayouts[0].bindings.map(\.arrayLength), [1])
        XCTAssertEqual(device.bindingLayouts[0].bindings.map(\.type), [.textureSampler])

        let first = TestTexture(device: device), second = TestTexture(device: device)
        bindings.setTexture(first, binding: 0)
        bindings.setTexture(second, binding: 0)
        XCTAssertTrue(bindings.textures[0] as? TestTexture === second)
        XCTAssertTrue(bindings.samplers[0] as? TestSampler === sampler)
        XCTAssertEqual(bindings.samplerWrites, [0])
    }

    func testTwoTextureBindingSetInitializesBothDefaultSamplers() throws {
        let device = TestDevice()
        let pipeline = makePipeline(device)
        let bindings = try XCTUnwrap(pipeline.makeBindingSet2() as? TestBindingSet)
        XCTAssertEqual(bindings.samplerWrites, [0, 1])
        for index in 0...1 {
            let sampler = try XCTUnwrap(bindings.samplers[index] as? TestSampler)
            XCTAssertTrue(sampler === pipeline.defaultSampler as? TestSampler)
        }
        XCTAssertTrue(bindings.textures.isEmpty)
        XCTAssertEqual(device.bindingLayouts.count, 1)
        XCTAssertEqual(device.bindingLayouts[0].bindings.map(\.binding), [0, 1])
        XCTAssertEqual(device.bindingLayouts[0].bindings.map(\.arrayLength), [1, 1])
        XCTAssertEqual(device.bindingLayouts[0].bindings.map(\.type), [.textureSampler, .textureSampler])
    }

    func testBindingSetFactoriesKeepMutableTexturesIndependent() throws {
        let device = TestDevice()
        let pipeline = makePipeline(device)
        let otherPipeline = makePipeline(device)
        let first = try XCTUnwrap(pipeline.makeBindingSet1() as? TestBindingSet)
        let second = try XCTUnwrap(pipeline.makeBindingSet1() as? TestBindingSet)
        let dual = try XCTUnwrap(pipeline.makeBindingSet2() as? TestBindingSet)
        let other = try XCTUnwrap(otherPipeline.makeBindingSet2() as? TestBindingSet)
        XCTAssertFalse(first === second)
        XCTAssertFalse(first === dual)
        XCTAssertFalse(dual === other)
        let texture = TestTexture(device: device)
        first.setTexture(texture, binding: 0)
        dual.setTexture(texture, binding: 1)
        XCTAssertTrue(second.textures.isEmpty)
        XCTAssertNil(dual.textures[0])
        XCTAssertTrue(other.textures.isEmpty)
        let sampler = try XCTUnwrap(other.samplers[0] as? TestSampler)
        XCTAssertTrue(sampler === otherPipeline.defaultSampler as? TestSampler)
        XCTAssertFalse(sampler === pipeline.defaultSampler as? TestSampler)
    }

    func testBindingSetCreationFailuresRemainRetryable() throws {
        let device = TestDevice()
        let pipeline = makePipeline(device)
        device.failNextBindingSets(2)
        XCTAssertNil(pipeline.makeBindingSet1())
        XCTAssertNil(pipeline.makeBindingSet2())
        let single = try XCTUnwrap(pipeline.makeBindingSet1() as? TestBindingSet)
        let dual = try XCTUnwrap(pipeline.makeBindingSet2() as? TestBindingSet)
        XCTAssertEqual(single.samplerWrites, [0])
        XCTAssertEqual(dual.samplerWrites, [0, 1])
        XCTAssertEqual(device.bindingLayouts.map { $0.bindings.count }, [1, 2, 1, 2])
    }

    private func assertDescriptor(_ descriptor: DepthStencilDescriptor, mode: Int,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let expected: [(StencilOperation, StencilOperation, CompareFunction, UInt32)] = [
            (.incrementWrap, .decrementWrap, .always, .max),
            (.incrementClamp, .incrementClamp, .always, .max),
            (.keep, .keep, .notEqual, .max),
            (.keep, .keep, .notEqual, 1),
            (.keep, .keep, .equal, .max),
            (.keep, .keep, .equal, 1),
            (.keep, .keep, .always, .max)
        ]
        let value = expected[mode]
        XCTAssertEqual(descriptor.depthCompareFunction, .always, file: file, line: line)
        XCTAssertFalse(descriptor.isDepthWriteEnabled, file: file, line: line)
        for (face, operation) in [(descriptor.frontFaceStencil, value.0),
                                   (descriptor.backFaceStencil, value.1)] {
            XCTAssertEqual(face.depthStencilPassOperation, operation, file: file, line: line)
            XCTAssertEqual(face.stencilCompareFunction, value.2, file: file, line: line)
            XCTAssertEqual(face.readMask, value.3, file: file, line: line)
            XCTAssertEqual(face.writeMask, .max, file: file, line: line)
            XCTAssertEqual(face.stencilFailureOperation, .keep, file: file, line: line)
            XCTAssertEqual(face.depthFailOperation, .keep, file: file, line: line)
        }
    }

    func testStencilIndicesCoverEveryCacheSlot() {
        XCTAssertEqual(_Stencil.allCases, modes)
        XCTAssertEqual(_Stencil.allCases.map(\.rawValue), Array(modes.indices))
    }

    func testStencilDescriptorsRemainDistinctAndCachedAcrossLookupOrders() throws {
        let device = TestDevice()
        let pipeline = makePipeline(device)
        XCTAssertTrue(device.requests.isEmpty)
        var retained: [Int: TestState] = [:]
        for round in 0..<12 {
            for offset in 0..<modes.count {
                let index = (round * 3 + offset * 5) % modes.count
                let state = try XCTUnwrap(pipeline.depthStencilState(modes[index]) as? TestState)
                assertDescriptor(state.descriptor, mode: index)
                XCTAssertTrue(state.device as AnyObject === device)
                if let previous = retained[index] { XCTAssertTrue(previous === state) }
                retained[index] = state
            }
        }
        XCTAssertEqual(device.requests.count, 7)
        XCTAssertEqual(Set(retained.values.map(ObjectIdentifier.init)).count, 7)
    }

    func testFailedStencilCreationRetriesWithoutChangingOtherCachedModes() throws {
        for index in modes.indices {
            let device = TestDevice()
            let pipeline = makePipeline(device)
            let other = modes[(index + 1) % modes.count]
            let cached = try XCTUnwrap(pipeline.depthStencilState(other) as? TestState)
            device.failNext(2)
            for _ in 0..<2 {
                XCTAssertNil(pipeline.depthStencilState(modes[index]))
                XCTAssertTrue(pipeline.depthStencilState(other) as? TestState === cached)
            }
            let recovered = try XCTUnwrap(pipeline.depthStencilState(modes[index]) as? TestState)
            XCTAssertTrue(pipeline.depthStencilState(modes[index]) as? TestState === recovered)
            XCTAssertTrue(pipeline.depthStencilState(other) as? TestState === cached)
            XCTAssertFalse(recovered === cached)
            XCTAssertEqual(device.requests.count, 4)
            for descriptor in device.requests.dropFirst() { assertDescriptor(descriptor, mode: index) }
        }
    }

    func testStencilCachesRemainInstanceAndDeviceLocal() throws {
        let firstDevice = TestDevice(), secondDevice = TestDevice()
        let first = makePipeline(firstDevice), sameDevice = makePipeline(firstDevice)
        let otherDevice = makePipeline(secondDevice)
        for mode in modes {
            let a = try XCTUnwrap(first.depthStencilState(mode) as? TestState)
            let b = try XCTUnwrap(sameDevice.depthStencilState(mode) as? TestState)
            let c = try XCTUnwrap(otherDevice.depthStencilState(mode) as? TestState)
            XCTAssertFalse(a === b)
            XCTAssertFalse(a === c)
            XCTAssertFalse(b === c)
            XCTAssertTrue(a.device as AnyObject === firstDevice)
            XCTAssertTrue(b.device as AnyObject === firstDevice)
            XCTAssertTrue(c.device as AnyObject === secondDevice)
        }
        XCTAssertEqual(firstDevice.requests.count, 14)
        XCTAssertEqual(secondDevice.requests.count, 7)
    }

    func testStencilCacheRetainsStatesUntilOwnerIsReleased() throws {
        let device = TestDevice()
        for mode in modes {
            var pipeline: GraphicsPipelineStates? = makePipeline(device)
            weak var observed: TestState?
            do {
                let state = try XCTUnwrap(pipeline?.depthStencilState(mode) as? TestState)
                observed = state
            }
            XCTAssertNotNil(observed)
            pipeline = nil
            XCTAssertNil(observed)
        }
        XCTAssertEqual(device.requests.count, 7)
    }

    func testConcurrentStencilLookupsCreateOneStatePerMode() {
        let device = TestDevice()
        let lookups = ConcurrentLookups(makePipeline(device))
        let modes = self.modes
        DispatchQueue.concurrentPerform(iterations: 16) { worker in
            for iteration in 0..<256 {
                let index = (worker + iteration) % modes.count
                lookups.lookup(modes[index], index: index)
            }
        }
        XCTAssertEqual(device.requests.count, 7)
        XCTAssertEqual(lookups.nilCount, 0)
        XCTAssertEqual(lookups.identityMismatches, 0)
        XCTAssertEqual(Set(lookups.states.values.map(ObjectIdentifier.init)).count, 7)
        for (index, state) in lookups.states { assertDescriptor(state.descriptor, mode: index) }
    }

    func testConcurrentStencilCreationFailuresRemainRetryable() {
        let device = TestDevice()
        device.failNext(16)
        let lookups = ConcurrentLookups(makePipeline(device))
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            for _ in 0..<64 { lookups.lookup(.makeFill, index: 0) }
        }
        XCTAssertEqual(device.requests.count, 17)
        XCTAssertEqual(lookups.nilCount, 16)
        XCTAssertEqual(lookups.identityMismatches, 0)
        XCTAssertEqual(lookups.states.count, 1)
        for descriptor in device.requests { assertDescriptor(descriptor, mode: 0) }
    }

    private func renderDescriptors() -> [GraphicsPipelineStates.RenderStateDescriptor] {
        [
            .init(shader: .vertexColor, colorFormat: .rgba8Unorm, depthFormat: .invalid,
                  blendState: .opaque, sampleCount: 1),
            .init(shader: .vertexColor, colorFormat: .rgba8Unorm, depthFormat: .invalid,
                  blendState: .premultipliedAlphaBlend, sampleCount: 1),
            .init(shader: .vertexColor, colorFormat: .bgra8Unorm, depthFormat: .invalid,
                  blendState: .opaque, sampleCount: 1),
            .init(shader: .vertexColor, colorFormat: .rgba8Unorm, depthFormat: .depth32Float_stencil8,
                  blendState: .opaque, sampleCount: 1),
            .init(shader: .vertexColor, colorFormat: .rgba8Unorm, depthFormat: .invalid,
                  blendState: .opaque, sampleCount: 4),
            .init(shader: .stencil, colorFormat: .rgba8Unorm, depthFormat: .invalid,
                  blendState: .opaque, sampleCount: 1),
            .init(shader: .projectiveImage, colorFormat: .rgba8Unorm, depthFormat: .invalid,
                  blendState: .opaque, sampleCount: 1)
        ]
    }

    private func makeRenderPipeline(_ device: TestDevice) -> GraphicsPipelineStates {
        let functions = GraphicsPipelineStates.ShaderFunctions(
            vertexFunction: TestFunction(device: device, stage: .vertex),
            fragmentFunction: TestFunction(device: device, stage: .fragment))
        return GraphicsPipelineStates(
            device: device,
            shaderFunctions: [.vertexColor: functions, .stencil: functions, .projectiveImage: functions],
            bindingLayout1: .init(bindings: []), bindingLayout2: .init(bindings: []),
            defaultSampler: TestSampler(device: device), defaultMaskTexture: TestTexture(device: device))
    }

    func testRenderStateCacheKeepsEveryDescriptorKeyDistinct() throws {
        let device = TestDevice()
        let pipeline = makeRenderPipeline(device)
        let descriptors = renderDescriptors()
        var states: [TestRenderState] = []
        for (index, key) in descriptors.enumerated() {
            let state = try XCTUnwrap(pipeline.renderState(key) as? TestRenderState)
            let request = device.renderRequests[index]
            XCTAssertTrue(state.device as AnyObject === device)
            XCTAssertEqual(request.colorAttachments.count, 1)
            XCTAssertEqual(request.colorAttachments[0].index, 0)
            XCTAssertEqual(request.colorAttachments[0].pixelFormat, key.colorFormat)
            XCTAssertEqual(request.colorAttachments[0].blendState, key.blendState)
            XCTAssertEqual(request.depthStencilAttachmentPixelFormat, key.depthFormat)
            XCTAssertEqual(request.rasterSampleCount, key.sampleCount)
            XCTAssertEqual(request.primitiveTopology, .triangle)
            XCTAssertEqual(request.triangleFillMode, .fill)
            let stride = key.shader == .stencil ? MemoryLayout<Float2>.stride
                : key.shader == .projectiveImage ? MemoryLayout<_ProjectiveVertex>.stride
                : MemoryLayout<_Vertex>.stride
            XCTAssertEqual(request.vertexDescriptor.layouts[0].stride, stride)
            states.append(state)
        }
        for index in descriptors.indices.reversed() {
            XCTAssertTrue(pipeline.renderState(descriptors[index]) as? TestRenderState === states[index])
        }
        XCTAssertEqual(device.renderRequests.count, descriptors.count)
        XCTAssertEqual(Set(states.map(ObjectIdentifier.init)).count, descriptors.count)
    }

    func testRenderStateFailuresAndMissingShadersDoNotBlockEitherCache() throws {
        let device = TestDevice()
        let pipeline = makeRenderPipeline(device)
        let keys = renderDescriptors()
        let cached = try XCTUnwrap(pipeline.renderState(keys[0]) as? TestRenderState)
        device.failNextRenderStates(2)
        for _ in 0..<2 {
            XCTAssertNil(pipeline.renderState(keys[1]))
            XCTAssertTrue(pipeline.renderState(keys[0]) as? TestRenderState === cached)
        }
        let recovered = try XCTUnwrap(pipeline.renderState(keys[1]) as? TestRenderState)
        XCTAssertTrue(pipeline.renderState(keys[1]) as? TestRenderState === recovered)
        let missing = GraphicsPipelineStates.RenderStateDescriptor(
            shader: .blendNormal, colorFormat: .rgba8Unorm, depthFormat: .invalid,
            blendState: .opaque, sampleCount: 1)
        XCTAssertNil(pipeline.renderState(missing))
        XCTAssertNil(pipeline.renderState(missing))
        XCTAssertEqual(device.renderRequests.count, 4)
        XCTAssertNotNil(pipeline.depthStencilState(.makeFill))
        XCTAssertTrue(pipeline.renderState(keys[0]) as? TestRenderState === cached)
    }

    func testRenderStateRetentionRemainsOwnerLocal() throws {
        let device = TestDevice()
        let other = makeRenderPipeline(device)
        let key = renderDescriptors()[0]
        let otherState = try XCTUnwrap(other.renderState(key) as? TestRenderState)
        weak var observed: TestRenderState?
        var pipeline: GraphicsPipelineStates? = makeRenderPipeline(device)
        do {
            let state = try XCTUnwrap(pipeline?.renderState(key) as? TestRenderState)
            XCTAssertFalse(state === otherState)
            observed = state
        }
        XCTAssertNotNil(observed)
        pipeline = nil
        XCTAssertNil(observed)
        XCTAssertTrue(other.renderState(key) as? TestRenderState === otherState)
    }

    func testConcurrentRenderAndStencilLookupsPreserveCreationAndRetry() {
        for failures in [0, 16] {
            let device = TestDevice()
            device.failNextRenderStates(failures)
            device.failNext(failures)
            let lookups = ConcurrentMixedLookups(
                makeRenderPipeline(device), keys: renderDescriptors(), modes: modes)
            DispatchQueue.concurrentPerform(iterations: 16) { worker in
                for index in 0..<256 { lookups.lookup(worker + index) }
            }
            XCTAssertEqual(device.renderRequests.count, 7 + failures)
            XCTAssertEqual(device.requests.count, 7 + failures)
            XCTAssertEqual(lookups.renderNilCount, failures)
            XCTAssertEqual(lookups.stencilNilCount, failures)
            XCTAssertEqual(lookups.identityMismatches, 0)
            XCTAssertEqual(Set(lookups.renderStates.values.map(ObjectIdentifier.init)).count, 7)
            XCTAssertEqual(Set(lookups.stencilStates.values.map(ObjectIdentifier.init)).count, 7)
        }
    }

    // Only the two protected getters cross threads; result recording happens afterward.
    private final class ConcurrentMixedLookups: @unchecked Sendable {
        let pipeline: GraphicsPipelineStates
        let keys: [GraphicsPipelineStates.RenderStateDescriptor]
        let modes: [_Stencil]
        private let lock = NSLock()
        private(set) var renderStates: [Int: TestRenderState] = [:]
        private(set) var stencilStates: [Int: TestState] = [:]
        private(set) var renderNilCount = 0
        private(set) var stencilNilCount = 0
        private(set) var identityMismatches = 0

        init(_ pipeline: GraphicsPipelineStates,
             keys: [GraphicsPipelineStates.RenderStateDescriptor], modes: [_Stencil]) {
            self.pipeline = pipeline
            self.keys = keys
            self.modes = modes
        }

        func lookup(_ ordinal: Int) {
            let index = ordinal % keys.count
            let mode = ordinal % modes.count
            let render = pipeline.renderState(keys[index]) as? TestRenderState
            let stencil = pipeline.depthStencilState(modes[mode]) as? TestState
            lock.lock()
            defer { lock.unlock() }
            if let render {
                if let previous = renderStates[index], previous !== render { identityMismatches += 1 }
                renderStates[index] = render
            } else { renderNilCount += 1 }
            if let stencil {
                if let previous = stencilStates[mode], previous !== stencil { identityMismatches += 1 }
                stencilStates[mode] = stencil
            } else { stencilNilCount += 1 }
        }
    }

    // Only the stencil getter crosses threads. Record results separately so the
    // test does not serialize cache calls or assert general pipeline Sendability.
    private final class ConcurrentLookups: @unchecked Sendable {
        let pipeline: GraphicsPipelineStates
        private let lock = NSLock()
        private(set) var states: [Int: TestState] = [:]
        private(set) var nilCount = 0
        private(set) var identityMismatches = 0

        init(_ pipeline: GraphicsPipelineStates) { self.pipeline = pipeline }

        func lookup(_ mode: _Stencil, index: Int) {
            let state = pipeline.depthStencilState(mode) as? TestState
            lock.lock()
            defer { lock.unlock() }
            guard let state else {
                nilCount += 1
                return
            }
            if let previous = states[index], previous !== state {
                identityMismatches += 1
            }
            states[index] = state
        }
    }
}
