//
//  File: Shader.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

@dynamicMemberLookup
public struct ShaderLibrary: Equatable, @unchecked Sendable {
    final class Storage: AppLifetimeResource, @unchecked Sendable {
        enum Source {
            case `default`
            case bundle(Bundle)
            case data(Data)
            case url(URL)
        }

        struct CacheKey: Hashable {
            var device: ObjectIdentifier
            var functionName: String
            var usage: UInt32
        }

        let source: Source
        private let lock = NSLock()
        private var functions: [CacheKey: BackendFunction] = [:]

        init(source: Source) {
            self.source = source
            super.init()
        }

        override func purgeResources(reason: ResourcePurgeReason) {
            lock.lock()
            functions.removeAll()
            lock.unlock()
        }

        func backendFunction(
            named functionName: String,
            usage: Shader.UsageType,
            device: GraphicsDevice
        ) throws -> BackendFunction {
            let key = CacheKey(
                device: ObjectIdentifier(device as AnyObject),
                functionName: functionName,
                usage: usage.rawValue
            )
            lock.lock()
            if let function = functions[key] {
                lock.unlock()
                return function
            }
            lock.unlock()

            let shader = try parsedShader(named: functionName, usage: usage)
            guard let module = device.makeShaderModule(from: shader) else {
                throw BackendError.moduleCreationFailed(functionName)
            }
            let entryPoint = try Self.entryPoint(named: functionName, in: shader)
            guard let function = module.makeFunction(name: entryPoint) else {
                throw BackendError.functionCreationFailed(entryPoint)
            }
            let resolved = BackendFunction(
                shader: shader,
                module: module,
                function: function
            )

            lock.lock()
            if let cached = functions[key] {
                lock.unlock()
                return cached
            }
            functions[key] = resolved
            lock.unlock()
            return resolved
        }

        func validateFunction(
            named functionName: String,
            usage: Shader.UsageType
        ) throws {
            let shader = try parsedShader(named: functionName, usage: usage)
            _ = try Self.entryPoint(named: functionName, in: shader)
        }

        private func parsedShader(
            named functionName: String,
            usage: Shader.UsageType
        ) throws -> VVD.Shader {
            let data = try shaderData(named: functionName, usage: usage)
            guard let shader = VVD.Shader(data: data, name: functionName),
                  shader.validate() else {
                throw BackendError.invalidSPIRV(functionName)
            }
            guard shader.stage == .fragment else {
                throw BackendError.invalidStage(functionName, String(describing: shader.stage))
            }
            return shader
        }

        private func shaderData(
            named functionName: String,
            usage: Shader.UsageType
        ) throws -> Data {
            switch source {
            case .data(let data):
                return data
            case .url(let url):
                do {
                    return try Data(contentsOf: url)
                } catch {
                    throw BackendError.unreadableURL(url, error)
                }
            case .default:
                return try Self.shaderData(
                    in: .main,
                    functionName: functionName,
                    usage: usage
                )
            case .bundle(let bundle):
                return try Self.shaderData(
                    in: bundle,
                    functionName: functionName,
                    usage: usage
                )
            }
        }

        private static func shaderData(
            in bundle: Bundle,
            functionName: String,
            usage: Shader.UsageType
        ) throws -> Data {
            let resourceNames = [
                "\(functionName).\(usage.resourceTag).frag",
                "\(functionName).frag",
                functionName,
                "default.\(usage.resourceTag).frag",
                "default.frag",
                "default",
            ]
            let subdirectories: [String?] = [nil, "Shaders", "Shaders/SPIRV", "SPIRV"]
            for subdirectory in subdirectories {
                for resourceName in resourceNames {
                    if let url = bundle.url(
                        forResource: resourceName,
                        withExtension: "spv",
                        subdirectory: subdirectory
                    ), let data = try? Data(contentsOf: url) {
                        return data
                    }
                }
            }
            throw BackendError.resourceNotFound(functionName, bundle.bundleURL)
        }

        private static func entryPoint(
            named functionName: String,
            in shader: VVD.Shader
        ) throws -> String {
            if shader.functionNames.contains(functionName) {
                return functionName
            }
            if shader.functionNames.count == 1, let only = shader.functionNames.first {
                return only
            }
            throw BackendError.functionNotFound(functionName, shader.functionNames)
        }
    }

    final class BackendFunction: @unchecked Sendable {
        let shader: VVD.Shader
        let module: any ShaderModule
        let function: any VVD.ShaderFunction

        private let lock = NSLock()
        private var renderStates: [RenderStateKey: RenderPipelineState] = [:]

        init(
            shader: VVD.Shader,
            module: any ShaderModule,
            function: any VVD.ShaderFunction
        ) {
            self.shader = shader
            self.module = module
            self.function = function
        }

        func renderState(
            pipeline: GraphicsPipelineStates,
            colorFormat: PixelFormat,
            depthFormat: PixelFormat,
            blendState: BlendState,
            sampleCount: Int
        ) -> RenderPipelineState? {
            let key = RenderStateKey(
                colorFormat: colorFormat,
                depthFormat: depthFormat,
                blendState: blendState,
                sampleCount: sampleCount
            )
            lock.lock()
            if let state = renderStates[key] {
                lock.unlock()
                return state
            }
            lock.unlock()

            guard let state = pipeline.makeCustomRenderState(
                fragmentFunction: function,
                colorFormat: colorFormat,
                depthFormat: depthFormat,
                blendState: blendState,
                sampleCount: sampleCount
            ) else {
                return nil
            }
            lock.lock()
            if let cached = renderStates[key] {
                lock.unlock()
                return cached
            }
            renderStates[key] = state
            lock.unlock()
            return state
        }

        private struct RenderStateKey: Hashable {
            var colorFormat: PixelFormat
            var depthFormat: PixelFormat
            var blendState: BlendState
            var sampleCount: Int
        }

        func makeBindingSets(
            sourceTexture: Texture?,
            imageTextures: [Texture],
            usage: Shader.UsageType,
            device: GraphicsDevice,
            sampler: SamplerState
        ) throws -> [(set: Int, bindingSet: ShaderBindingSet)] {
            let descriptorsBySet = Dictionary(grouping: shader.descriptors, by: \.set)
            return try descriptorsBySet.keys.sorted().map { set in
                guard set == 0 else {
                    throw BackendError.unsupportedDescriptorSet(set)
                }
                let descriptors = descriptorsBySet[set]!.sorted { $0.binding < $1.binding }
                let layout = ShaderBindingSetLayout(bindings: descriptors.map {
                    ShaderBinding(
                        binding: $0.binding,
                        type: $0.type,
                        arrayLength: $0.count
                    )
                })
                guard let bindingSet = device.makeShaderBindingSet(layout: layout) else {
                    throw BackendError.bindingSetCreationFailed(set)
                }
                for descriptor in descriptors {
                    switch descriptor.type {
                    case .texture, .textureSampler:
                        let textures = try (0..<descriptor.count).map { arrayIndex in
                            try texture(
                                binding: descriptor.binding + arrayIndex,
                                sourceTexture: sourceTexture,
                                imageTextures: imageTextures,
                                usage: usage
                            )
                        }
                        bindingSet.setTextureArray(textures, binding: descriptor.binding)
                        if case .textureSampler = descriptor.type {
                            bindingSet.setSamplerStateArray(
                                Array(repeating: sampler, count: descriptor.count),
                                binding: descriptor.binding
                            )
                        }
                    case .sampler:
                        bindingSet.setSamplerStateArray(
                            Array(repeating: sampler, count: descriptor.count),
                            binding: descriptor.binding
                        )
                    case .uniformBuffer,
                         .storageBuffer,
                         .storageTexture,
                         .uniformTexelBuffer,
                         .storageTexelBuffer:
                        throw BackendError.unsupportedDescriptor(
                            descriptor.set,
                            descriptor.binding,
                            String(describing: descriptor.type)
                        )
                    }
                }
                return (set, bindingSet)
            }
        }

        private func texture(
            binding: Int,
            sourceTexture: Texture?,
            imageTextures: [Texture],
            usage: Shader.UsageType
        ) throws -> Texture {
            let imageIndex: Int
            if usage == .shapeStyle {
                imageIndex = binding
            } else if binding == 0 {
                guard let sourceTexture else {
                    throw BackendError.missingSourceTexture
                }
                return sourceTexture
            } else {
                imageIndex = binding - 1
            }
            guard imageTextures.indices.contains(imageIndex) else {
                throw BackendError.missingImageTexture(binding)
            }
            return imageTextures[imageIndex]
        }
    }

    enum BackendError: LocalizedError {
        case resourceNotFound(String, URL)
        case unreadableURL(URL, any Error)
        case invalidSPIRV(String)
        case invalidStage(String, String)
        case functionNotFound(String, [String])
        case moduleCreationFailed(String)
        case functionCreationFailed(String)
        case pipelineCreationFailed(String)
        case unsupportedDescriptorSet(Int)
        case bindingSetCreationFailed(Int)
        case unsupportedDescriptor(Int, Int, String)
        case missingSourceTexture
        case missingImageTexture(Int)
        case imageResolutionFailed(Int)
        case pushConstantBlockCount(Int)
        case argumentCountMismatch(expected: Int, actual: Int)
        case argumentTypeMismatch(index: Int, expected: String, actual: String)
        case argumentDataTooLarge(index: Int, size: Int, capacity: Int)

        var errorDescription: String? {
            switch self {
            case let .resourceNotFound(name, bundleURL):
                return "SPIR-V resource for shader function '\(name)' was not found in \(bundleURL.path)."
            case let .unreadableURL(url, error):
                return "Unable to read SPIR-V shader at \(url.path): \(error.localizedDescription)"
            case let .invalidSPIRV(name):
                return "Shader function '\(name)' does not contain valid SPIR-V."
            case let .invalidStage(name, stage):
                return "Shader function '\(name)' must be a fragment shader, not \(stage)."
            case let .functionNotFound(name, available):
                return "Shader entry point '\(name)' was not found. Available entry points: \(available)."
            case let .moduleCreationFailed(name):
                return "The graphics device could not create a shader module for '\(name)'."
            case let .functionCreationFailed(name):
                return "The graphics device could not create shader function '\(name)'."
            case let .pipelineCreationFailed(name):
                return "The graphics device could not create a render pipeline for shader function '\(name)'."
            case let .unsupportedDescriptorSet(set):
                return "Custom shaders currently support descriptor set 0, not set \(set)."
            case let .bindingSetCreationFailed(set):
                return "The graphics device could not create shader binding set \(set)."
            case let .unsupportedDescriptor(set, binding, type):
                return "Custom shader descriptor set \(set), binding \(binding) uses unsupported type \(type)."
            case .missingSourceTexture:
                return "The custom shader requires a source texture that is unavailable."
            case let .missingImageTexture(binding):
                return "The custom shader has no image argument for texture binding \(binding)."
            case let .imageResolutionFailed(index):
                return "Custom shader image argument \(index) could not be resolved to a texture."
            case let .pushConstantBlockCount(count):
                return "Custom shaders support at most one push-constant block, not \(count)."
            case let .argumentCountMismatch(expected, actual):
                return "The custom shader declares \(expected) argument fields, but received \(actual) non-image arguments."
            case let .argumentTypeMismatch(index, expected, actual):
                return "Custom shader argument \(index) requires \(expected), not \(actual)."
            case let .argumentDataTooLarge(index, size, capacity):
                return "Custom shader argument \(index) contains \(size) bytes, exceeding its \(capacity)-byte field."
            }
        }
    }

    private static let defaultStorage = Storage(source: .default)
    private static let bundleLock = NSLock()
    nonisolated(unsafe) private static var bundleStorage: [ObjectIdentifier: Storage] = [:]

    let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    public static let `default` = ShaderLibrary(storage: defaultStorage)

    public static func bundle(_ bundle: Bundle) -> ShaderLibrary {
        if bundle === Bundle.main {
            return .default
        }
        let key = ObjectIdentifier(bundle)
        bundleLock.lock()
        defer { bundleLock.unlock() }
        if let storage = bundleStorage[key] {
            return ShaderLibrary(storage: storage)
        }
        let storage = Storage(source: .bundle(bundle))
        bundleStorage[key] = storage
        return ShaderLibrary(storage: storage)
    }

    public init(data: Data) {
        storage = Storage(source: .data(data))
    }

    public init(url: URL) {
        storage = Storage(source: .url(url))
    }

    public static subscript(dynamicMember name: String) -> ShaderFunction {
        ShaderFunction(library: .default, name: name)
    }

    public subscript(dynamicMember name: String) -> ShaderFunction {
        ShaderFunction(library: self, name: name)
    }

    public static func == (lhs: ShaderLibrary, rhs: ShaderLibrary) -> Bool {
        lhs.storage === rhs.storage
    }
}

@dynamicCallable
public struct ShaderFunction: Equatable, Sendable {
    public var library: ShaderLibrary
    public var name: String

    public init(library: ShaderLibrary, name: String) {
        self.library = library
        self.name = name
    }

    public func dynamicallyCall(withArguments args: [Shader.Argument]) -> Shader {
        Shader(function: self, arguments: args)
    }
}

public struct Shader: Equatable, Sendable {
    public struct Argument: Equatable, Sendable {
        enum Storage: Equatable, Sendable {
            case float(Float)
            case float2(Float, Float)
            case float3(Float, Float, Float)
            case float4(Float, Float, Float, Float)
            case floatArray([Float])
            case color(Color)
            case colorArray([Color])
            case resolvedColor(Color.ResolvedHDR)
            case image(Image)
            case data(Data)
            case boundsRect

            static func == (lhs: Storage, rhs: Storage) -> Bool {
                switch (lhs, rhs) {
                case let (.float(a), .float(b)):
                    return a == b
                case let (.float2(a, b), .float2(c, d)):
                    return a == c && b == d
                case let (.float3(a, b, c), .float3(d, e, f)):
                    return a == d && b == e && c == f
                case let (.float4(a, b, c, d), .float4(e, f, g, h)):
                    return a == e && b == f && c == g && d == h
                case let (.floatArray(a), .floatArray(b)):
                    return a == b
                case let (.color(a), .color(b)):
                    return a == b
                case let (.colorArray(a), .colorArray(b)):
                    return a == b
                case let (.resolvedColor(a), .resolvedColor(b)):
                    return a == b
                case let (.image(a), .image(b)):
                    return a == b
                case let (.data(a), .data(b)):
                    return a == b
                case (.boundsRect, .boundsRect):
                    return true
                default:
                    return false
                }
            }
        }

        let storage: Storage

        init(storage: Storage) {
            self.storage = storage
        }

        static func _float(_ x: Float) -> Argument {
            Argument(storage: .float(x))
        }

        static func _float2(_ x: Float, _ y: Float) -> Argument {
            Argument(storage: .float2(x, y))
        }

        static func _float3(_ x: Float, _ y: Float, _ z: Float) -> Argument {
            Argument(storage: .float3(x, y, z))
        }

        static func _float4(_ x: Float, _ y: Float, _ z: Float, _ w: Float) -> Argument {
            Argument(storage: .float4(x, y, z, w))
        }

        public static func float<T>(_ x: T) -> Argument where T: BinaryFloatingPoint {
            _float(Float(x))
        }

        public static func float2<T>(_ x: T, _ y: T) -> Argument where T: BinaryFloatingPoint {
            _float2(Float(x), Float(y))
        }

        public static func float3<T>(_ x: T, _ y: T, _ z: T) -> Argument where T: BinaryFloatingPoint {
            _float3(Float(x), Float(y), Float(z))
        }

        public static func float4<T>(_ x: T, _ y: T, _ z: T, _ w: T) -> Argument where T: BinaryFloatingPoint {
            _float4(Float(x), Float(y), Float(z), Float(w))
        }

        public static func float2(_ point: CGPoint) -> Argument {
            _float2(Float(point.x), Float(point.y))
        }

        public static func float2(_ size: CGSize) -> Argument {
            _float2(Float(size.width), Float(size.height))
        }

        public static func float2(_ vector: CGVector) -> Argument {
            _float2(Float(vector.dx), Float(vector.dy))
        }

        public static func floatArray(_ array: [Float]) -> Argument {
            Argument(storage: .floatArray(array))
        }

        public static var boundingRect: Argument {
            Argument(storage: .boundsRect)
        }

        public static func color(_ color: Color) -> Argument {
            Argument(storage: .color(color))
        }

        public static func colorArray(_ array: [Color]) -> Argument {
            Argument(storage: .colorArray(array))
        }

        public static func image(_ image: Image) -> Argument {
            Argument(storage: .image(image))
        }

        public static func data(_ data: Data) -> Argument {
            Argument(storage: .data(data))
        }
    }

    struct Options: OptionSet, Sendable {
        let rawValue: UInt32

        static let dithersColor = Options(rawValue: 1 << 0)
        static let colorFilter = Options(rawValue: 1 << 1)
        static let distortionFilter = Options(rawValue: 1 << 2)
        static let alphaOnlyLayer = Options(rawValue: 1 << 3)
        static let ignoresSecondaryDOD = Options(rawValue: 1 << 4)
    }

    public var function: ShaderFunction
    public var arguments: [Argument]
    var options: Options

    public var dithersColor: Bool {
        get { options.contains(.dithersColor) }
        set {
            if newValue {
                options.insert(.dithersColor)
            } else {
                options.remove(.dithersColor)
            }
        }
    }

    public init(function: ShaderFunction, arguments: [Argument]) {
        self.function = function
        self.arguments = arguments
        options = []
    }

    public struct UsageType: Hashable, Sendable {
        let rawValue: UInt32

        private init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let shapeStyle = UsageType(rawValue: 0)
        public static let colorEffect = UsageType(rawValue: 1)
        public static let layerEffect = UsageType(rawValue: 2)
        public static let distortionEffect = UsageType(rawValue: 3)

        var resourceTag: String {
            switch rawValue {
            case Self.shapeStyle.rawValue:
                return "shape"
            case Self.colorEffect.rawValue:
                return "color"
            case Self.layerEffect.rawValue:
                return "layer"
            case Self.distortionEffect.rawValue:
                return "distortion"
            default:
                return "shader"
            }
        }
    }

    public func compile(as type: UsageType) async throws {
        if let device = appContext?.graphicsDeviceContext?.device {
            _ = try function.library.storage.backendFunction(
                named: function.name,
                usage: type,
                device: device
            )
        } else {
            try function.library.storage.validateFunction(
                named: function.name,
                usage: type
            )
        }
    }

    public typealias Resolved = Never
}

extension Shader: ShapeStyle {
    public static func _makeView<S>(
        view: _GraphValue<_ShapeView<S, Shader>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where S: Shape {
        _ShapeView<S, Shader>._makeView(view: view, inputs: inputs)
    }

    public func _apply(to shape: inout _ShapeStyle_Shape) {
        shape.shading = .shader(self, bounds: .null)
    }
}

extension Shader {
    struct BackendArguments {
        var pushConstants: Data
        var pushConstantLayouts: [ShaderPushConstantLayout]
        var images: [Image]
    }

    func backendArguments(
        for backendShader: VVD.Shader,
        boundingRect: CGRect,
        environment: EnvironmentValues
    ) throws -> BackendArguments {
        let layouts = backendShader.pushConstantLayouts
        guard layouts.count <= 1 else {
            throw ShaderLibrary.BackendError.pushConstantBlockCount(layouts.count)
        }
        let members = layouts.first?.members ?? []
        let nonImageArguments = arguments.filter {
            if case .image = $0.storage { return false }
            return true
        }
        guard members.count == nonImageArguments.count else {
            throw ShaderLibrary.BackendError.argumentCountMismatch(
                expected: members.count,
                actual: nonImageArguments.count
            )
        }

        let byteCount = max(
            layouts.map { $0.offset + $0.size }.max() ?? 0,
            members.map { $0.offset + $0.size }.max() ?? 0
        )
        var pushConstants = Data(repeating: 0, count: byteCount)
        for (index, pair) in zip(nonImageArguments, members).enumerated() {
            try Self.write(
                argument: pair.0,
                to: pair.1,
                index: index,
                boundingRect: boundingRect,
                environment: environment,
                data: &pushConstants
            )
        }
        return BackendArguments(
            pushConstants: pushConstants,
            pushConstantLayouts: layouts,
            images: arguments.compactMap {
                if case let .image(image) = $0.storage { return image }
                return nil
            }
        )
    }

    private static func write(
        argument: Argument,
        to member: ShaderResourceStructMember,
        index: Int,
        boundingRect: CGRect,
        environment: EnvironmentValues,
        data: inout Data
    ) throws {
        switch argument.storage {
        case let .float(value):
            try require(member, type: .float, index: index)
            try write([value], to: member, index: index, data: &data)
        case let .float2(x, y):
            try require(member, type: .float2, index: index)
            try write([x, y], to: member, index: index, data: &data)
        case let .float3(x, y, z):
            try require(member, type: .float3, index: index)
            try write([x, y, z], to: member, index: index, data: &data)
        case let .float4(x, y, z, w):
            try require(member, type: .float4, index: index)
            try write([x, y, z, w], to: member, index: index, data: &data)
        case let .floatArray(values):
            try require(member, type: .float, count: values.count, index: index)
            try writeArray(values.map { [$0] }, to: member, index: index, data: &data)
        case let .color(color):
            try require(member, type: .float4, index: index)
            try write(
                colorValues(Color.ResolvedHDR(color.resolve(in: environment))),
                to: member,
                index: index,
                data: &data
            )
        case let .resolvedColor(color):
            try require(member, type: .float4, index: index)
            try write(colorValues(color), to: member, index: index, data: &data)
        case let .colorArray(colors):
            try require(member, type: .float4, count: colors.count, index: index)
            try writeArray(colors.map {
                colorValues(Color.ResolvedHDR($0.resolve(in: environment)))
            }, to: member, index: index, data: &data)
        case let .data(bytes):
            try writeRaw(bytes, to: member, index: index, data: &data)
        case .boundsRect:
            try require(member, type: .float4, index: index)
            try write([
                Float(boundingRect.origin.x),
                Float(boundingRect.origin.y),
                Float(boundingRect.size.width),
                Float(boundingRect.size.height),
            ], to: member, index: index, data: &data)
        case .image:
            preconditionFailure("Image arguments are descriptor resources, not push constants.")
        }
    }

    private static func require(
        _ member: ShaderResourceStructMember,
        type: ShaderDataType,
        count: Int = 1,
        index: Int
    ) throws {
        let matchingType = switch (member.dataType, type) {
        case (.float, .float),
             (.float2, .float2),
             (.float3, .float3),
             (.float4, .float4):
            true
        default:
            false
        }
        guard matchingType, member.count == count else {
            let expected = count == 1 ? "\(type)" : "\(type)[\(count)]"
            let actual = member.count == 1
                ? "\(member.dataType)"
                : "\(member.dataType)[\(member.count)]"
            throw ShaderLibrary.BackendError.argumentTypeMismatch(
                index: index,
                expected: expected,
                actual: actual
            )
        }
    }

    private static func write(
        _ values: [Float],
        to member: ShaderResourceStructMember,
        index: Int,
        data: inout Data
    ) throws {
        let bytes = values.withUnsafeBytes { Data($0) }
        try writeRaw(bytes, offset: member.offset, capacity: member.size, index: index, data: &data)
    }

    private static func writeArray(
        _ values: [[Float]],
        to member: ShaderResourceStructMember,
        index: Int,
        data: inout Data
    ) throws {
        let elementCapacity = member.dataType.size()
        let stride = member.stride > 0 ? member.stride : elementCapacity
        for (arrayIndex, value) in values.enumerated() {
            let bytes = value.withUnsafeBytes { Data($0) }
            try writeRaw(
                bytes,
                offset: member.offset + arrayIndex * stride,
                capacity: elementCapacity,
                index: index,
                data: &data
            )
        }
    }

    private static func writeRaw(
        _ bytes: Data,
        to member: ShaderResourceStructMember,
        index: Int,
        data: inout Data
    ) throws {
        try writeRaw(
            bytes,
            offset: member.offset,
            capacity: member.size,
            index: index,
            data: &data
        )
    }

    private static func writeRaw(
        _ bytes: Data,
        offset: Int,
        capacity: Int,
        index: Int,
        data: inout Data
    ) throws {
        guard bytes.count <= capacity else {
            throw ShaderLibrary.BackendError.argumentDataTooLarge(
                index: index,
                size: bytes.count,
                capacity: capacity
            )
        }
        guard offset >= 0, offset + bytes.count <= data.count else {
            throw ShaderLibrary.BackendError.argumentDataTooLarge(
                index: index,
                size: bytes.count,
                capacity: max(data.count - offset, 0)
            )
        }
        data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    private static func colorValues(_ color: Color.ResolvedHDR) -> [Float] {
        [color.linearRed, color.linearGreen, color.linearBlue, color.opacity]
    }
}

extension GraphicsContext {
    func drawCustomShaderLayer(
        _ resolvedShader: Shader.ResolvedShader,
        sourceTexture: Texture,
        frame: CGRect
    ) -> Bool {
        guard let shader = resolvedShader.shader else { return false }
        let usage: Shader.UsageType
        if resolvedShader.options.contains(.colorFilter) {
            usage = .colorEffect
        } else if resolvedShader.options.contains(.distortionFilter) {
            usage = .distortionEffect
        } else {
            usage = .layerEffect
        }

        let sourceBounds = CGRect(
            origin: -contentOffset,
            size: viewport.size / contentScaleFactor
        )
        var outputBounds = frame.standardized
        if outputBounds.isNull || outputBounds.isEmpty || outputBounds.isInfinite {
            outputBounds = sourceBounds
        }
        outputBounds = outputBounds.insetBy(
            dx: -abs(resolvedShader.maxSampleOffset.width),
            dy: -abs(resolvedShader.maxSampleOffset.height)
        ).intersection(sourceBounds)
        guard !outputBounds.isNull, !outputBounds.isEmpty else { return true }

        let transform = self.transform.concatenating(viewTransform)
        let makeVertex = { (point: CGPoint) -> _Vertex in
            let u = Float((point.x - sourceBounds.minX) / sourceBounds.width)
            let v = Float((point.y - sourceBounds.minY) / sourceBounds.height)
            return _Vertex(
                position: Vector2(point).applying(transform).float2,
                texcoord: (u, v),
                color: (1, 1, 1, 1)
            )
        }
        let lowerLeft = makeVertex(CGPoint(x: outputBounds.minX, y: outputBounds.maxY))
        let upperLeft = makeVertex(CGPoint(x: outputBounds.minX, y: outputBounds.minY))
        let lowerRight = makeVertex(CGPoint(x: outputBounds.maxX, y: outputBounds.maxY))
        let upperRight = makeVertex(CGPoint(x: outputBounds.maxX, y: outputBounds.minY))
        let vertices = [
            lowerLeft, upperLeft, lowerRight,
            lowerRight, upperLeft, upperRight,
        ]

        guard let renderPass = beginRenderPass(enableStencil: false) else {
            return false
        }
        let encoded = encodeCustomShaderCommand(
            renderPass: renderPass,
            shader: shader,
            usage: usage,
            boundingRect: frame,
            sourceTexture: sourceTexture,
            stencil: .ignore,
            vertices: vertices,
            blendState: .opaque
        )
        renderPass.end()
        if encoded {
            drawSource()
            recordContentBounds(outputBounds)
        }
        return encoded
    }

    func encodeCustomShaderShadingCommand(
        renderPass: RenderPass,
        shader: Shader,
        boundingRect: CGRect,
        stencil: _Stencil,
        blendState: BlendState
    ) -> Bool {
        let makeVertex = { (x: Float, y: Float, u: Float, v: Float) in
            _Vertex(
                position: (x, y),
                texcoord: (u, v),
                color: (1, 1, 1, 1)
            )
        }
        return encodeCustomShaderCommand(
            renderPass: renderPass,
            shader: shader,
            usage: .shapeStyle,
            boundingRect: boundingRect,
            sourceTexture: nil,
            stencil: stencil,
            vertices: [
                makeVertex(-1, -1, 0, 1),
                makeVertex(-1, 1, 0, 0),
                makeVertex(1, -1, 1, 1),
                makeVertex(1, -1, 1, 1),
                makeVertex(-1, 1, 0, 0),
                makeVertex(1, 1, 1, 0),
            ],
            blendState: blendState
        )
    }

    private func encodeCustomShaderCommand(
        renderPass: RenderPass,
        shader: Shader,
        usage: Shader.UsageType,
        boundingRect: CGRect,
        sourceTexture: Texture?,
        stencil: _Stencil,
        vertices: [_Vertex],
        blendState: BlendState
    ) -> Bool {
        do {
            let device = commandBuffer.device
            let backend = try shader.function.library.storage.backendFunction(
                named: shader.function.name,
                usage: usage,
                device: device
            )
            let arguments = try shader.backendArguments(
                for: backend.shader,
                boundingRect: boundingRect,
                environment: environment
            )
            let imageTextures = try arguments.images.enumerated().map { index, image -> Texture in
                guard let texture = resolve(image).texture else {
                    throw ShaderLibrary.BackendError.imageResolutionFailed(index)
                }
                return texture
            }
            let bindingSets = try backend.makeBindingSets(
                sourceTexture: sourceTexture,
                imageTextures: imageTextures,
                usage: usage,
                device: device,
                sampler: pipeline.defaultSampler
            )
            guard let renderState = backend.renderState(
                pipeline: pipeline,
                colorFormat: renderPass.colorFormat,
                depthFormat: renderPass.depthFormat,
                blendState: blendState,
                sampleCount: renderPass.sampleCount
            ) else {
                throw ShaderLibrary.BackendError.pipelineCreationFailed(shader.function.name)
            }
            guard let depthState = pipeline.depthStencilState(stencil),
                  let vertexBuffer = makeBuffer(vertices) else {
                return false
            }

            let encoder = renderPass.encoder
            encoder.setRenderPipelineState(renderState)
            encoder.setDepthStencilState(depthState)
            for binding in bindingSets {
                encoder.setResource(binding.bindingSet, index: binding.set)
            }
            for layout in arguments.pushConstantLayouts where layout.size > 0 {
                let range = layout.offset..<(layout.offset + layout.size)
                guard range.lowerBound >= 0,
                      range.upperBound <= arguments.pushConstants.count else {
                    throw ShaderLibrary.BackendError.argumentDataTooLarge(
                        index: -1,
                        size: layout.size,
                        capacity: arguments.pushConstants.count
                    )
                }
                encoder.pushConstant(
                    stages: layout.stages,
                    offset: layout.offset,
                    data: arguments.pushConstants[range]
                )
            }
            encoder.setCullMode(.none)
            encoder.setFrontFacing(.clockwise)
            encoder.setStencilReferenceValue(0)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.draw(
                vertexStart: 0,
                vertexCount: vertices.count,
                instanceCount: 1,
                baseInstance: 0
            )
            return true
        } catch {
            Log.error("Custom shader '\(shader.function.name)' failed: \(error.localizedDescription)")
            return false
        }
    }
}

struct ShaderVectorData: VectorArithmetic {
    enum Element: Equatable, Sendable {
        case float(Float)
        case float2(Float, Float)
        case float3(Float, Float, Float)
        case float4(Float, Float, Float, Float)
        case array([Float])
        case zero
    }

    var elements: [Element]

    static var zero: ShaderVectorData {
        ShaderVectorData(elements: [])
    }

    static func + (lhs: ShaderVectorData, rhs: ShaderVectorData) -> ShaderVectorData {
        ShaderVectorData(elements: combine(lhs.elements, rhs.elements, +))
    }

    static func - (lhs: ShaderVectorData, rhs: ShaderVectorData) -> ShaderVectorData {
        ShaderVectorData(elements: combine(lhs.elements, rhs.elements, -))
    }

    mutating func scale(by rhs: Double) {
        let scale = Float(rhs)
        elements = elements.map { element in
            switch element {
            case let .float(a):
                return .float(a * scale)
            case let .float2(a, b):
                return .float2(a * scale, b * scale)
            case let .float3(a, b, c):
                return .float3(a * scale, b * scale, c * scale)
            case let .float4(a, b, c, d):
                return .float4(a * scale, b * scale, c * scale, d * scale)
            case let .array(values):
                return .array(values.map { $0 * scale })
            case .zero:
                return .zero
            }
        }
    }

    var magnitudeSquared: Double {
        elements.reduce(0) { result, element in
            result + element.magnitudeSquared
        }
    }

    private static func combine(
        _ lhs: [Element],
        _ rhs: [Element],
        _ operation: (Float, Float) -> Float
    ) -> [Element] {
        let count = max(lhs.count, rhs.count)
        return (0..<count).map { index in
            combine(
                index < lhs.count ? lhs[index] : .zero,
                index < rhs.count ? rhs[index] : .zero,
                operation
            )
        }
    }

    private static func combine(
        _ lhs: Element,
        _ rhs: Element,
        _ operation: (Float, Float) -> Float
    ) -> Element {
        switch (lhs, rhs) {
        case let (.float(a), .float(b)):
            return .float(operation(a, b))
        case let (.float2(a, b), .float2(c, d)):
            return .float2(operation(a, c), operation(b, d))
        case let (.float3(a, b, c), .float3(d, e, f)):
            return .float3(operation(a, d), operation(b, e), operation(c, f))
        case let (.float4(a, b, c, d), .float4(e, f, g, h)):
            return .float4(operation(a, e), operation(b, f), operation(c, g), operation(d, h))
        case let (.array(a), .array(b)):
            let count = max(a.count, b.count)
            return .array((0..<count).map { index in
                operation(index < a.count ? a[index] : 0, index < b.count ? b[index] : 0)
            })
        case (.zero, let value):
            return value.applyingFromZero(operation)
        case (let value, .zero):
            return value.applyingToZero(operation)
        default:
            return .zero
        }
    }
}

private extension ShaderVectorData.Element {
    var magnitudeSquared: Double {
        switch self {
        case let .float(a):
            return Double(a * a)
        case let .float2(a, b):
            return Double(a * a + b * b)
        case let .float3(a, b, c):
            return Double(a * a + b * b + c * c)
        case let .float4(a, b, c, d):
            return Double(a * a + b * b + c * c + d * d)
        case let .array(values):
            return values.reduce(0) { $0 + Double($1 * $1) }
        case .zero:
            return 0
        }
    }

    func applyingFromZero(_ operation: (Float, Float) -> Float) -> Self {
        map { operation(0, $0) }
    }

    func applyingToZero(_ operation: (Float, Float) -> Float) -> Self {
        map { operation($0, 0) }
    }

    func map(_ transform: (Float) -> Float) -> Self {
        switch self {
        case let .float(a):
            return .float(transform(a))
        case let .float2(a, b):
            return .float2(transform(a), transform(b))
        case let .float3(a, b, c):
            return .float3(transform(a), transform(b), transform(c))
        case let .float4(a, b, c, d):
            return .float4(transform(a), transform(b), transform(c), transform(d))
        case let .array(values):
            return .array(values.map(transform))
        case .zero:
            return .zero
        }
    }
}

extension Shader {
    func resolvePaint(in environment: EnvironmentValues) -> ResolvedShader {
        resolvedShader(
            in: environment,
            maxSampleOffset: .zero,
            enabled: true
        )
    }

    fileprivate func resolvedShader(
        in environment: EnvironmentValues,
        maxSampleOffset: CGSize,
        enabled: Bool
    ) -> ResolvedShader {
        let resolved: Shader?
        if enabled {
            var shader = self
            shader.arguments = arguments.map { argument in
                switch argument.storage {
                case let .color(color):
                    return Argument(storage: .resolvedColor(
                        Color.ResolvedHDR(color.resolve(in: environment))
                    ))
                case let .colorArray(colors):
                    return Argument(storage: .colorArray(colors.map { color in
                        Color(color.resolve(in: environment))
                    }))
                default:
                    return argument
                }
            }
            resolved = shader
        } else {
            resolved = nil
        }
        return ResolvedShader(
            shader: resolved,
            maxSampleOffset: maxSampleOffset,
            options: options
        )
    }

    struct ResolvedShader: Equatable, Animatable, _RendererEffect, MultiViewModifier {
        var shader: Shader?
        var maxSampleOffset: CGSize
        var options: Options

        typealias Body = Never

        var animatableData: ShaderVectorData {
            get {
                ShaderVectorData(elements: shader?.arguments.map(Self.element(for:)) ?? [])
            }
            set {
                guard var shader else { return }
                for index in shader.arguments.indices where index < newValue.elements.count {
                    shader.arguments[index] = Self.argument(
                        from: newValue.elements[index],
                        replacing: shader.arguments[index]
                    )
                }
                self.shader = shader
            }
        }

        func effectValue(size: CGSize) -> DisplayList.Effect {
            _ = size
            guard shader != nil else { return .identity }
            return .shader(self)
        }

        static func _makeView(
            modifier: _GraphValue<Self>,
            inputs: _ViewInputs,
            body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
        ) -> _ViewOutputs {
            _RendererEffectSupport.makeView(effect: modifier, inputs: inputs, body: body)
        }

        static func _makeViewList(
            modifier: _GraphValue<Self>,
            inputs: _ViewListInputs,
            body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
        ) -> _ViewListOutputs {
            _RendererEffectSupport.makeViewList(modifier: modifier, inputs: inputs, body: body)
        }

        private static func element(for argument: Argument) -> ShaderVectorData.Element {
            switch argument.storage {
            case let .float(a):
                return .float(a)
            case let .float2(a, b):
                return .float2(a, b)
            case let .float3(a, b, c):
                return .float3(a, b, c)
            case let .float4(a, b, c, d):
                return .float4(a, b, c, d)
            case let .floatArray(values):
                return .array(values)
            case let .color(color):
                return colorElement(Color.ResolvedHDR(color.resolve(in: EnvironmentValues())))
            case let .colorArray(colors):
                return .array(colors.flatMap { colorValues(Color.ResolvedHDR($0.resolve(in: EnvironmentValues()))) })
            case let .resolvedColor(color):
                return colorElement(color)
            case .image, .data, .boundsRect:
                return .zero
            }
        }

        private static func argument(
            from element: ShaderVectorData.Element,
            replacing argument: Argument
        ) -> Argument {
            switch (argument.storage, element) {
            case (_, .zero):
                return argument
            case (.float, let .float(a)):
                return Argument(storage: .float(a))
            case (.float2, let .float2(a, b)):
                return Argument(storage: .float2(a, b))
            case (.float3, let .float3(a, b, c)):
                return Argument(storage: .float3(a, b, c))
            case (.float4, let .float4(a, b, c, d)):
                return Argument(storage: .float4(a, b, c, d))
            case (.floatArray, let .array(values)):
                return Argument(storage: .floatArray(values))
            case (.color, let .float4(r, g, b, a)),
                 (.resolvedColor, let .float4(r, g, b, a)):
                return Argument(storage: .resolvedColor(Color.ResolvedHDR(
                    Color.Resolved(colorSpace: .sRGBLinear, red: r, green: g, blue: b, opacity: a)
                )))
            case let (.colorArray(colors), .array(values)):
                let resolved = stride(from: 0, to: min(values.count, colors.count * 4), by: 4).map { index in
                    Color(Color.Resolved(
                        colorSpace: .sRGBLinear,
                        red: values[index],
                        green: values[index + 1],
                        blue: values[index + 2],
                        opacity: values[index + 3]
                    ))
                }
                return Argument(storage: .colorArray(resolved))
            default:
                return argument
            }
        }

        private static func colorElement(_ color: Color.ResolvedHDR) -> ShaderVectorData.Element {
            .float4(color.linearRed, color.linearGreen, color.linearBlue, color.opacity)
        }

        private static func colorValues(_ color: Color.ResolvedHDR) -> [Float] {
            [color.linearRed, color.linearGreen, color.linearBlue, color.opacity]
        }
    }
}

public struct _ShaderFilterEffect: Sendable, ViewModifier, VisualEffect, MultiViewModifier {
    var shader: Shader
    var maxSampleOffset: CGSize
    var enabled: Bool

    init(shader: Shader, maxSampleOffset: CGSize, enabled: Bool) {
        self.shader = shader
        self.maxSampleOffset = maxSampleOffset
        self.enabled = enabled
    }

    public typealias Body = Never
    public typealias AnimatableData = EmptyAnimatableData

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        makeResolvedView(modifier: modifier, inputs: inputs, body: body)
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("_ShaderFilterEffect._makeViewList called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }

    public static func _makeVisualEffect(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        makeResolvedView(modifier: effect, inputs: inputs, body: body)
    }

    private static func makeResolvedView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_ShaderFilterEffect called outside an active _AGGraph context.")
        }
        let environment = inputs.base.cachedEnvironment.value.environment
        var resolved = _GraphValue<Shader.ResolvedShader>(
            _attribute: graph.makeStatefulRule(ResolvedEffect(
                _modifier: modifier._attribute,
                _env: environment,
                tracker: _PropertyListTracker()
            ))
        )
        Shader.ResolvedShader._makeAnimatable(value: &resolved, inputs: inputs.base)
        return _RendererEffectSupport.makeView(
            effect: resolved,
            inputs: inputs,
            body: body
        )
    }

    private struct ResolvedEffect: StatefulRule {
        typealias Value = Shader.ResolvedShader

        var _modifier: Attribute<_ShaderFilterEffect>
        var _env: Attribute<EnvironmentValues>
        var tracker: _PropertyListTracker

        mutating func updateValue() {
            let environment = _env.value
            if _AGGraph.currentStatefulOutput(Value.self) != nil,
               !_AGGraph.currentStatefulInputChanged(_modifier.identifier),
               !tracker.hasDifferentUsedValues(environment._plist) {
                return
            }
            tracker.reset()
            let trackedEnvironment = EnvironmentValues(environment._plist, tracker: tracker)
            let modifier = _modifier.value
            _AGGraph.setStatefulOutput(modifier.shader.resolvedShader(
                in: trackedEnvironment,
                maxSampleOffset: modifier.maxSampleOffset,
                enabled: modifier.enabled
            ))
        }
    }
}

extension View {
    public func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some View {
        var shader = shader
        shader.options.insert(.colorFilter)
        return layerEffect(shader, maxSampleOffset: .zero, isEnabled: isEnabled)
    }

    public func distortionEffect(
        _ shader: Shader,
        maxSampleOffset: CGSize,
        isEnabled: Bool = true
    ) -> some View {
        var shader = shader
        shader.options.insert(.distortionFilter)
        return layerEffect(shader, maxSampleOffset: maxSampleOffset, isEnabled: isEnabled)
    }

    public func layerEffect(
        _ shader: Shader,
        maxSampleOffset: CGSize,
        isEnabled: Bool = true
    ) -> some View {
        modifier(_ShaderFilterEffect(
            shader: shader,
            maxSampleOffset: maxSampleOffset,
            enabled: isEnabled
        ))
    }
}

extension VisualEffect {
    public func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some VisualEffect {
        var shader = shader
        shader.options.insert(.colorFilter)
        return layerEffect(shader, maxSampleOffset: .zero, isEnabled: isEnabled)
    }

    public func distortionEffect(
        _ shader: Shader,
        maxSampleOffset: CGSize,
        isEnabled: Bool = true
    ) -> some VisualEffect {
        var shader = shader
        shader.options.insert(.distortionFilter)
        return layerEffect(shader, maxSampleOffset: maxSampleOffset, isEnabled: isEnabled)
    }

    public func layerEffect(
        _ shader: Shader,
        maxSampleOffset: CGSize,
        isEnabled: Bool = true
    ) -> some VisualEffect {
        combining(_ShaderFilterEffect(
            shader: shader,
            maxSampleOffset: maxSampleOffset,
            enabled: isEnabled
        ))
    }
}
