//
//  File: MetalGraphicsDevice.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal
import SPIRV_Cross

final class MetalGraphicsDevice: GraphicsDevice {

    var name: String { device.name }
    let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    init?() {
        if let device = MTLCreateSystemDefaultDevice() {
            self.device = device
        } else {
            return nil
        }
    }

    init?(name: String) {
        var device: MTLDevice? = nil

        if name.isEmpty {
            device = MTLCreateSystemDefaultDevice()
        } else {
#if os(macOS) || targetEnvironment(macCatalyst)
            let devices = MTLCopyAllDevices()
            for dev in devices {
                if name.caseInsensitiveCompare(dev.name) == .orderedSame {
                    device = dev
                    break
                }
            }
#endif
            if device == nil {
                device = MTLCreateSystemDefaultDevice()
            }
        }

        if let device = device {
            self.device = device
        } else {
            return nil
        }
    }

    func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue? {
        if let queue = self.device.makeCommandQueue() {
            return MetalCommandQueue(device: self, queue: queue)
        }
        return nil
    }

    func makeShaderModule(from shader: Shader) -> ShaderModule? {
        if let data = shader.spirvData {
            let stage: SpvExecutionModel
            switch shader.stage {
            case .vertex:       stage = SpvExecutionModelVertex
            case .fragment:     stage = SpvExecutionModelFragment
            case .compute:      stage = SpvExecutionModelGLCompute
            default:
                Log.err("Unsupported shader stage!")
                return nil
            }

            var numBuffers = 0
            var numTextures = 0
            var numSamplers = 0
            var bindings1: [spvc_msl_resource_binding] = []
            var bindings2: [MetalResourceBinding] = []

            bindings1.reserveCapacity(shader.resources.count + 1)
            bindings2.reserveCapacity(shader.resources.count + 1)

            for res in shader.resources {
                let b1 = spvc_msl_resource_binding(stage: stage,
                                                   desc_set: UInt32(res.set),
                                                   binding: UInt32(res.binding),
                                                   msl_buffer: UInt32(numBuffers),
                                                   msl_texture: UInt32(numTextures),
                                                   msl_sampler: UInt32(numSamplers))

                let b2 = MetalResourceBinding(set: res.set,
                                              binding: res.binding,
                                              bufferIndex: numBuffers,
                                              textureIndex: numTextures,
                                              samplerIndex: numSamplers,
                                              type: res.type)
                bindings1.append(b1)
                bindings2.append(b2)

                switch res.type {
                case .buffer:
                    numBuffers += res.count
                case .texture:
                    numTextures += res.count
                case .sampler:
                    numSamplers += res.count
                case .textureSampler:
                    numSamplers += res.count
                    numTextures += res.count
                }
            }
            // from spirv_cross_c.h
            let SPVC_MSL_PUSH_CONSTANT_DESC_SET = ~UInt32(0)
            let SPVC_MSL_PUSH_CONSTANT_BINDING = UInt32(0)

            if shader.pushConstantLayouts.count > 0 {
                assert(shader.pushConstantLayouts.count == 1, "There can be only one push constant block!")

                // add push-constant
                let b1 = spvc_msl_resource_binding(stage: stage,
                                                   desc_set: SPVC_MSL_PUSH_CONSTANT_DESC_SET,
                                                   binding: SPVC_MSL_PUSH_CONSTANT_BINDING,
                                                   msl_buffer: UInt32(numBuffers),
                                                   msl_texture: UInt32(numTextures),
                                                   msl_sampler: UInt32(numSamplers))

                let b2 = MetalResourceBinding(set: Int(SPVC_MSL_PUSH_CONSTANT_DESC_SET),
                                              binding: Int(SPVC_MSL_PUSH_CONSTANT_BINDING),
                                              bufferIndex: numBuffers,
                                              textureIndex: numTextures,
                                              samplerIndex: numSamplers,
                                              type: .buffer)
                bindings1.append(b1)
                bindings2.append(b2)

                numBuffers += 1
            }

            var spvcContext: spvc_context? = nil
            if spvc_context_create(&spvcContext) != SPVC_SUCCESS {
                return nil
            }
            defer { spvc_context_destroy(spvcContext) }

            var spvcParsedIR: spvc_parsed_ir? = nil
            if data.withUnsafeBytes({
                let spvData = $0.bindMemory(to: UInt32.self)
                return spvc_context_parse_spirv(spvcContext, spvData.baseAddress, spvData.count, &spvcParsedIR)
            }) != SPVC_SUCCESS {
                return nil
            }

            var spvcCompiler: spvc_compiler? = nil
            if spvc_context_create_compiler(spvcContext,
                                            SPVC_BACKEND_MSL,
                                            spvcParsedIR,
                                            SPVC_CAPTURE_MODE_TAKE_OWNERSHIP,
                                            &spvcCompiler) != SPVC_SUCCESS {
                return nil
            }
            for var mslBinding in bindings1 {
                if spvc_compiler_msl_add_resource_binding(spvcCompiler, &mslBinding) != SPVC_SUCCESS {
                    return nil
                }
            }
            var spvcEntryPoints: UnsafePointer<spvc_entry_point>? = nil
            var numSpvcEntryPoints = 0
            if spvc_compiler_get_entry_points(spvcCompiler, &spvcEntryPoints, &numSpvcEntryPoints) != SPVC_SUCCESS {
                return nil
            }
            if numSpvcEntryPoints == 0 {
                Log.err("No entry point function!")
                return nil
            }

            var spvcCompilerOptions: spvc_compiler_options? = nil
            if spvc_compiler_create_compiler_options(spvcCompiler, &spvcCompilerOptions) != SPVC_SUCCESS {
                return nil
            }

            // spirv_msl.hpp
            // iOS = 0,
            // macOS = 1
#if os(macOS) || targetEnvironment(macCatalyst)
            spvc_compiler_options_set_uint(spvcCompilerOptions, SPVC_COMPILER_OPTION_MSL_PLATFORM, 1)
#else
            spvc_compiler_options_set_uint(spvcCompilerOptions, SPVC_COMPILER_OPTION_MSL_PLATFORM, 0)
#endif
            let makeMSLVersion = { (major: UInt32, minor: UInt32, patch: UInt32) in
                return (major * 10000) + (minor * 100) + patch
            }
            spvc_compiler_options_set_uint(spvcCompilerOptions, SPVC_COMPILER_OPTION_MSL_VERSION, makeMSLVersion(3, 2, 0))
            spvc_compiler_options_set_bool(spvcCompilerOptions, SPVC_COMPILER_OPTION_MSL_ENABLE_POINT_SIZE_BUILTIN, SPVC_TRUE)

            spvc_compiler_install_compiler_options(spvcCompiler, spvcCompilerOptions)

            var compilerOutputSourcePtr: UnsafePointer<CChar>? = nil
            if spvc_compiler_compile(spvcCompiler, &compilerOutputSourcePtr) != SPVC_SUCCESS {
                return nil
            }
            let mslSource = String(cString: compilerOutputSourcePtr!)
            Log.info("MSL Source: \(mslSource)")

            let compileOptions = MTLCompileOptions()
            compileOptions.mathMode = .fast

            var library: MTLLibrary? = nil
            do {
                try library = self.device.makeLibrary(source: mslSource, options: compileOptions)
            } catch {
                Log.err("MTLLibrary compile error: \(error)")
                return nil
            }
            if let library = library {
                Log.info("MTLLibrary: \(library)")

                var entryPoints: UnsafePointer<spvc_entry_point>? = nil
                var numEntryPoints = 0

                if spvc_compiler_get_entry_points(spvcCompiler, &entryPoints, &numEntryPoints) != SPVC_SUCCESS {
                    return nil
                }

                var nameConversions: [MetalShaderModule.NameConversion] = []
                nameConversions.reserveCapacity(numSpvcEntryPoints)
                for i in 0..<numEntryPoints {
                    let ep = entryPoints![i]
                    let cleansed = spvc_compiler_get_cleansed_entry_point_name(spvcCompiler,
                                                                               ep.name,
                                                                               ep.execution_model)!

                    let nameConversion = MetalShaderModule.NameConversion(original: String(cString: ep.name),
                                                                          cleansed: String(cString: cleansed))

                    nameConversions.append(nameConversion)
                }

                let module = MetalShaderModule(device: self, library: library, names: nameConversions)
                let workgroupSize = shader.threadgroupSize
                module.workgroupSize = MTLSize(width: workgroupSize.x,
                                               height: workgroupSize.y,
                                               depth: workgroupSize.z)

                assert(bindings1.count == bindings2.count)

                var bindingMap = MetalStageResourceBindingMap(resourceBindings: [],
                                                              inputAttributeIndexOffset: 0,
                                                              pushConstantIndex: Int(SPVC_MSL_PUSH_CONSTANT_DESC_SET),
                                                              pushConstantOffset: 0,
                                                              pushConstantSize: 0,
                                                              pushConstantBufferSize: 0)
                bindingMap.resourceBindings.reserveCapacity(bindings1.count)
                for i in 0..<bindings1.count {
                    let b1 = bindings1[i]
                    let b2 = bindings2[i]

                    if spvc_compiler_msl_is_resource_used(spvcCompiler, b1.stage, b1.desc_set, b1.binding) != SPVC_FALSE {
                        if b1.desc_set == SPVC_MSL_PUSH_CONSTANT_DESC_SET &&
                            b1.binding == SPVC_MSL_PUSH_CONSTANT_BINDING {

                            // Only one push-constant binding is allowed.
                            assert(bindingMap.pushConstantIndex == SPVC_MSL_PUSH_CONSTANT_DESC_SET)
                            assert(bindingMap.pushConstantOffset == 0)

                            let layout = shader.pushConstantLayouts[0]
                            bindingMap.pushConstantIndex = Int(b1.msl_buffer)
                            // MTLArgument doesn't have an offset, save info for later use. (pipeline-reflection)
                            bindingMap.pushConstantOffset = layout.offset
                            bindingMap.pushConstantSize = layout.size

                            var bufferSize = layout.size
                            var alignment = 1

                            layout.members.forEach {
                                alignment = max(alignment, $0.mtlAlignment)
                                bufferSize = max(bufferSize, $0.offset + $0.size)
                            }
                            assert(alignment.isPowerOfTwo)

                            bindingMap.pushConstantBufferSize = bufferSize.alignedUp(toMultipleOf: alignment)

                        } else {
                            bindingMap.resourceBindings.append(b2)
                        }
                    }
                }

                bindingMap.resourceBindings.sort { (a, b) in
                    if (a.set == b.set) {
                        return a.binding < b.binding
                    }
                    return a.set < b.set
                }
                bindingMap.inputAttributeIndexOffset = numBuffers
                module.bindings = bindingMap
                
                return module
            }
        }
        return nil
    }

    func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet? {
        return MetalShaderBindingSet(device: self, layout: layout.bindings)
    }

    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor, reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState? {
        var vertexFunction: MetalShaderFunction? = nil
        var fragmentFunction: MetalShaderFunction? = nil

        if let fn = descriptor.vertexFunction {
            assert(fn is MetalShaderFunction)
            vertexFunction = fn as? MetalShaderFunction
            assert(vertexFunction!.function.functionType == .vertex)
        }
        if let fn = descriptor.fragmentFunction {
            assert(fn is MetalShaderFunction)
            fragmentFunction = fn as? MetalShaderFunction
            assert(fragmentFunction!.function.functionType == .fragment)
        }

        // Create MTLRenderPipelineState object.
        let desc = MTLRenderPipelineDescriptor()

        var vertexAttributeOffset = 0

        if let vertexFunction = vertexFunction {
            desc.vertexFunction = vertexFunction.function
            vertexAttributeOffset = vertexFunction.module.bindings.inputAttributeIndexOffset
        }
        if let fragmentFunction = fragmentFunction {
            desc.fragmentFunction = fragmentFunction.function
        }

        let vertexFormat = { (f: VertexFormat) -> MTLVertexFormat in
            switch f {
            case .uchar:                    .uchar
            case .uchar2:                   .uchar2
            case .uchar3:                   .uchar3
            case .uchar4:                   .uchar4
            case .char:                     .char
            case .char2:                    .char2
            case .char3:                    .char3
            case .char4:                    .char4
            case .ucharNormalized:          .ucharNormalized
            case .uchar2Normalized:         .uchar2Normalized
            case .uchar3Normalized:         .uchar3Normalized
            case .uchar4Normalized:         .uchar4Normalized
            case .charNormalized:           .charNormalized
            case .char2Normalized:          .char2Normalized
            case .char3Normalized:          .char3Normalized
            case .char4Normalized:          .char4Normalized
            case .ushort:                   .ushort
            case .ushort2:                  .ushort2
            case .ushort3:                  .ushort3
            case .ushort4:                  .ushort4
            case .short:                    .short
            case .short2:                   .short2
            case .short3:                   .short3
            case .short4:                   .short4
            case .ushortNormalized:         .ushortNormalized
            case .ushort2Normalized:        .ushort2Normalized
            case .ushort3Normalized:        .ushort3Normalized
            case .ushort4Normalized:        .ushort4Normalized
            case .shortNormalized:          .shortNormalized
            case .short2Normalized:         .short2Normalized
            case .short3Normalized:         .short3Normalized
            case .short4Normalized:         .short4Normalized
            case .half:                     .half
            case .half2:                    .half2
            case .half3:                    .half3
            case .half4:                    .half4
            case .float:                    .float
            case .float2:                   .float2
            case .float3:                   .float3
            case .float4:                   .float4
            case .int:                      .int
            case .int2:                     .int2
            case .int3:                     .int3
            case .int4:                     .int4
            case .uint:                     .uint
            case .uint2:                    .uint2
            case .uint3:                    .uint3
            case .uint4:                    .uint4
            case .int1010102Normalized:     .int1010102Normalized
            case .uint1010102Normalized:    .uint1010102Normalized
            case .invalid:
                    .invalid
            }
        }

        let vertexStepFunction = { (step: VertexStepRate) -> MTLVertexStepFunction in
            switch step {
            case .vertex:                   .perVertex
            case .instance:                 .perInstance
            }
        }

        let blendFactor = { (f: BlendFactor) -> MTLBlendFactor in
            switch f {
            case .zero:                         .zero
            case .one:                          .one
            case .sourceColor:                  .sourceColor
            case .oneMinusSourceColor:          .oneMinusSourceColor
            case .sourceAlpha:                  .sourceAlpha
            case .oneMinusSourceAlpha:          .oneMinusSourceAlpha
            case .destinationColor:             .destinationColor
            case .oneMinusDestinationColor:     .oneMinusDestinationColor
            case .destinationAlpha:             .destinationAlpha
            case .oneMinusDestinationAlpha:     .oneMinusDestinationAlpha
            case .sourceAlphaSaturated:         .sourceAlphaSaturated
            case .blendColor:                   .blendColor
            case .oneMinusBlendColor:           .oneMinusBlendColor
            case .blendAlpha:                   .blendAlpha
            case .oneMinusBlendAlpha:           .oneMinusBlendAlpha
            case .source1Color:                 .source1Color
            case .oneMinusSource1Color:         .oneMinusSource1Color
            case .source1Alpha:                 .source1Alpha
            case .oneMinusSource1Alpha:         .oneMinusSource1Alpha
            }
        }

        let blendOperation = { (op: BlendOperation) -> MTLBlendOperation in
            switch op {
            case .add:                      .add
            case .subtract:                 .subtract
            case .reverseSubtract:          .reverseSubtract
            case .min:                      .min
            case .max:                      .max
            }
        }

        let colorWriteMask = { (mask: ColorWriteMask) -> MTLColorWriteMask in
            var value: MTLColorWriteMask = []
            if mask.contains(.red)      { value.insert(.red) }
            if mask.contains(.green)    { value.insert(.green) }
            if mask.contains(.blue)     { value.insert(.blue) }
            if mask.contains(.alpha)    { value.insert(.alpha) }
            return value
        }

        // setup color-attachments
        for attachment in descriptor.colorAttachments {
            let colorAttachmentDesc: MTLRenderPipelineColorAttachmentDescriptor = desc.colorAttachments[attachment.index]
            colorAttachmentDesc.pixelFormat = attachment.pixelFormat.mtlPixelFormat()
            colorAttachmentDesc.writeMask = colorWriteMask(attachment.blendState.writeMask)
            colorAttachmentDesc.isBlendingEnabled = attachment.blendState.enabled
            colorAttachmentDesc.alphaBlendOperation = blendOperation(attachment.blendState.alphaBlendOperation)
            colorAttachmentDesc.rgbBlendOperation = blendOperation(attachment.blendState.rgbBlendOperation)
            colorAttachmentDesc.sourceRGBBlendFactor = blendFactor(attachment.blendState.sourceRGBBlendFactor)
            colorAttachmentDesc.sourceAlphaBlendFactor = blendFactor(attachment.blendState.sourceAlphaBlendFactor)
            colorAttachmentDesc.destinationRGBBlendFactor = blendFactor(attachment.blendState.destinationRGBBlendFactor)
            colorAttachmentDesc.destinationAlphaBlendFactor = blendFactor(attachment.blendState.destinationAlphaBlendFactor)
        }

        // setup depth attachment.
        desc.depthAttachmentPixelFormat = .invalid
        desc.stencilAttachmentPixelFormat = .invalid
        if descriptor.depthStencilAttachmentPixelFormat.isDepthFormat {
            desc.depthAttachmentPixelFormat = descriptor.depthStencilAttachmentPixelFormat.mtlPixelFormat()
        }
        if descriptor.depthStencilAttachmentPixelFormat.isStencilFormat {
            desc.stencilAttachmentPixelFormat = descriptor.depthStencilAttachmentPixelFormat.mtlPixelFormat()
        }

        // setup vertex buffer and attributes.
        if descriptor.vertexDescriptor.attributes.count > 0 || descriptor.vertexDescriptor.layouts.count > 0 {
            let vertexDescriptor = MTLVertexDescriptor()
            for attrDesc in descriptor.vertexDescriptor.attributes {
                let attr: MTLVertexAttributeDescriptor = vertexDescriptor.attributes[attrDesc.location]
                attr.format = vertexFormat(attrDesc.format)
                attr.offset = attrDesc.offset
                attr.bufferIndex = vertexAttributeOffset + attrDesc.bufferIndex
            }
            descriptor.vertexDescriptor.layouts.indices.forEach { index in
                let bufferIndex = vertexAttributeOffset + index
                let layoutDesc = descriptor.vertexDescriptor.layouts[index]
                let layout: MTLVertexBufferLayoutDescriptor = vertexDescriptor.layouts[bufferIndex]
                layout.stepFunction = vertexStepFunction(layoutDesc.stepRate)
                layout.stepRate = 1
                layout.stride = layoutDesc.stride
            }
            desc.vertexDescriptor = vertexDescriptor
        }
        // multisampling
        desc.rasterSampleCount = descriptor.rasterSampleCount

        var pipelineReflection: MTLRenderPipelineReflection? = nil
        let pipelineState: MTLRenderPipelineState
        do {
            if reflection != nil {
                let options: MTLPipelineOption = [.bindingInfo, .bufferTypeInfo]
                pipelineState = try self.device.makeRenderPipelineState(descriptor: desc,
                                                                        options: options,
                                                                        reflection: &pipelineReflection)
            } else {
                pipelineState = try self.device.makeRenderPipelineState(descriptor: desc)
            }
        } catch {
            Log.err("MTLDevice.makeRenderPipelineState error: \(error)")
            return nil
        }

        if let reflection = reflection, let pipelineReflection = pipelineReflection {
            Log.debug("RenderPipelineReflection: \(pipelineReflection)")

            var resources: [ShaderResource] = []
            var inputAttrs: [ShaderAttribute] = []
            var pushConstants: [ShaderPushConstantLayout] = []

            if let vertexFunction = vertexFunction {
                inputAttrs = vertexFunction.stageInputAttributes // copy all inputAttributes
            }

            let numVertexBindings = pipelineReflection.vertexBindings.count
            let numFragmentBindings = pipelineReflection.fragmentBindings.count

            inputAttrs.reserveCapacity(numVertexBindings)
            resources.reserveCapacity(numVertexBindings + numFragmentBindings)

            var shaderBindings: [(shader: MetalShaderFunction, bindings: [any MTLBinding])] = []
            if let vertexFunction {
                shaderBindings.append((vertexFunction, pipelineReflection.vertexBindings))
            }
            if let fragmentFunction {
                shaderBindings.append((fragmentFunction, pipelineReflection.fragmentBindings))
            }
            shaderBindings.forEach { (shader, bindings) in
                let bindingMap = shader.module.bindings
                let stage = shader.stage
                let stageMask = ShaderStageFlags(stage: stage)

                bindings.forEach { binding in
                    if binding.isUsed {
                        if binding.type == .buffer && binding.index >= bindingMap.inputAttributeIndexOffset {
                            // This can be skipped.
                            // We copied all inputAttrs from above.

                            // The Metal pipeline-reflection provides single vertex-buffer information,
                            // rather than separated vertex-stream component informations.
                        } else if binding.type == .buffer && binding.index == bindingMap.pushConstantIndex {
                            if let buffer = binding as? MTLBufferBinding {
                                let layout = ShaderPushConstantLayout.from(mtlBufferBinding: buffer,
                                                                           offset: bindingMap.pushConstantOffset,
                                                                           size: bindingMap.pushConstantSize,
                                                                           stage: stage)

                                assert(bindingMap.pushConstantBufferSize == buffer.bufferDataSize,
                                       "Buffer size mismatch! \(bindingMap.pushConstantBufferSize) != \(buffer.bufferDataSize)")

                                if let index = pushConstants.firstIndex(where: {
                                    $0.offset == layout.offset && $0.size == layout.size
                                }) {
                                    pushConstants[index].stages.formUnion(stageMask)
                                } else {
                                    pushConstants.append(layout)
                                }
                            } else {
                                assertionFailure("Unable to cast buffer binding to MTLBufferBinding")
                            }
                        } else {
                            let res = ShaderResource.from(
                                mtlBinding: binding,
                                bindingMap: bindingMap.resourceBindings,
                                stage: stage)
                            combineShaderResources(&resources, resource: res)
                        }
                    }
                }
            }

            reflection.pointee.resources = resources
            reflection.pointee.inputAttributes = inputAttrs
            reflection.pointee.pushConstantLayouts = pushConstants
        }
        
        let state = MetalRenderPipelineState(device: self, pipelineState: pipelineState)
        state.primitiveType = switch descriptor.primitiveTopology {
        case .point:            .point
        case .line:             .line
        case .lineStrip:        .lineStrip
        case .triangle:         .triangle
        case .triangleStrip:    .triangleStrip
        }
        state.triangleFillMode = switch descriptor.triangleFillMode {
        case .fill:             .fill
        case .lines:            .lines
        }
        if let vertexFunction = vertexFunction {
            state.vertexBindings = vertexFunction.module.bindings
        }
        if let fragmentFunction = fragmentFunction {
            state.fragmentBindings = fragmentFunction.module.bindings
        }
        return state
    }

    func makeComputePipelineState(descriptor: ComputePipelineDescriptor, reflection: UnsafeMutablePointer<PipelineReflection>?) -> ComputePipelineState? {
        if descriptor.computeFunction == nil {
            return nil
        }

        assert(descriptor.computeFunction is MetalShaderFunction)
        let computeFunction = descriptor.computeFunction as! MetalShaderFunction
        assert(computeFunction.function.functionType == .kernel)

        let desc = MTLComputePipelineDescriptor()
        desc.computeFunction = computeFunction.function
        var options: MTLPipelineOption = []
        if reflection != nil {
            options = [.bindingInfo, .bufferTypeInfo]
        }

        var pipelineReflection: MTLComputePipelineReflection? = nil
        let pipelineState: MTLComputePipelineState
        do {
            pipelineState = try self.device.makeComputePipelineState(descriptor: desc,
                                                                     options: options,
                                                                     reflection: &pipelineReflection)
        } catch {
            Log.err("MTLDevice.makeComputePipelineState error: \(error)")
            return nil
        }

        if let reflection = reflection, let pipelineReflection = pipelineReflection {
            Log.debug("ComputePipelineReflection: \(pipelineReflection)")

            var resources: [ShaderResource] = []
            var pushConstants: [ShaderPushConstantLayout] = []

            resources.reserveCapacity(pipelineReflection.bindings.count)
            pushConstants.reserveCapacity(pipelineReflection.bindings.count)

            let bindingMap = computeFunction.module.bindings
            let stage = computeFunction.stage
            pipelineReflection.bindings.forEach { binding in
                if binding.isUsed {
                    if binding.type == .buffer && binding.index >= bindingMap.inputAttributeIndexOffset {
                    }
                    else if binding.type == .buffer && binding.index == bindingMap.pushConstantIndex {
                        if let buffer = binding as? MTLBufferBinding {
                            let layout = ShaderPushConstantLayout.from(mtlBufferBinding: buffer,
                                                                       offset: bindingMap.pushConstantOffset,
                                                                       size: bindingMap.pushConstantSize,
                                                                       stage: stage)

                            assert(bindingMap.pushConstantBufferSize == buffer.bufferDataSize,
                                   "Buffer size mismatch! \(bindingMap.pushConstantBufferSize) != \(buffer.bufferDataSize)")

                            pushConstants.append(layout)
                        } else {
                            assertionFailure("Unable to cast buffer binding to MTLBufferBinding")
                        }
                    } else {
                        let res = ShaderResource.from(mtlBinding: binding,
                                                      bindingMap: bindingMap.resourceBindings,
                                                      stage: stage)
                        combineShaderResources(&resources, resource: res)
                    }
                }
            }

            reflection.pointee.resources = resources
            reflection.pointee.pushConstantLayouts = pushConstants
        }

        return MetalComputePipelineState(device: self,
                                         pipelineState: pipelineState,
                                         workgroupSize: computeFunction.module.workgroupSize,
                                         bindings: computeFunction.module.bindings)
    }

    func makeDepthStencilState(descriptor: DepthStencilDescriptor) -> DepthStencilState? {
        let compareFunction = { (fn: CompareFunction) -> MTLCompareFunction in
            switch fn {
            case .never:            .never
            case .less:             .less
            case .equal:            .equal
            case .lessEqual:        .lessEqual
            case .greater:          .greater
            case .notEqual:         .notEqual
            case .greaterEqual:     .greaterEqual
            case .always:           .always
            }
        }
        let stencilOperation = { (op: StencilOperation) -> MTLStencilOperation in
            switch op {
            case .keep:             .keep
            case .zero:             .zero
            case .replace:          .replace
            case .incrementClamp:   .incrementClamp
            case .decrementClamp:   .decrementClamp
            case .invert:           .invert
            case .incrementWrap:    .incrementWrap
            case .decrementWrap:    .decrementWrap
            }
        }
        let setStencilDescriptor = { (stencil: inout MTLStencilDescriptor, desc: StencilDescriptor) in
            stencil.stencilFailureOperation = stencilOperation(desc.stencilFailureOperation)
            stencil.depthFailureOperation = stencilOperation(desc.depthFailOperation)
            stencil.depthStencilPassOperation = stencilOperation(desc.depthStencilPassOperation)
            stencil.stencilCompareFunction = compareFunction(desc.stencilCompareFunction)
            stencil.readMask = desc.readMask
            stencil.writeMask = desc.writeMask
        }

        // Create MTLDepthStencilState object.
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = compareFunction(descriptor.depthCompareFunction)
        depthStencilDescriptor.isDepthWriteEnabled = descriptor.isDepthWriteEnabled
        setStencilDescriptor(&depthStencilDescriptor.frontFaceStencil, descriptor.frontFaceStencil)
        setStencilDescriptor(&depthStencilDescriptor.backFaceStencil, descriptor.backFaceStencil)

        if let depthStencilState = self.device.makeDepthStencilState(descriptor: depthStencilDescriptor) {
            return MetalDepthStencilState(device: self,
                                          depthStencilState: depthStencilState)
        }
        Log.err("MTLDevice.makeDepthStencilState(descriptor:) failed.")
        return nil
    }

    func makeBuffer(length: Int, storageMode: StorageMode, cpuCacheMode: CPUCacheMode) -> GPUBuffer? {
        if length > 0 {
            var options: MTLResourceOptions = []
            switch storageMode {
            case .shared:
                options.insert(.storageModeShared)
            case .private:
                options.insert(.storageModePrivate)
            }
            switch cpuCacheMode {
            case .defaultCache:
                break
            case .writeCombined:
                options.insert(.cpuCacheModeWriteCombined)
            }

            if let buffer = device.makeBuffer(length: length, options: options) {
                return MetalBuffer(device: self, buffer: buffer)
            } else
            {
                Log.err("MTLDevice.makeBuffer failed.")
            }
        }
        return nil
    }

    func makeTexture(descriptor: TextureDescriptor) -> Texture? {
        let pixelFormat = descriptor.pixelFormat.mtlPixelFormat()
        let arrayLength = descriptor.arrayLength

        if arrayLength == 0 {
            Log.err("MetalGraphicsDevice.makeTexture error: Invalid array length!")
            return nil
        }
        if pixelFormat == .invalid {
            Log.err("MetalGraphicsDevice.makeTexture error: Invalid pixel format!")
            return nil
        }
        if descriptor.width < 1 || descriptor.height < 1 || descriptor.depth < 1 {
            Log.error("Texture dimensions (width, height, depth) value must be greater than or equal to 1.")
            return nil
        }

        let desc = MTLTextureDescriptor()
        switch descriptor.textureType {
        case .type1D:
            desc.textureType = (arrayLength > 1) ? .type1DArray : .type1D
        case .type2D:
            if descriptor.sampleCount > 1 {
                desc.textureType = (arrayLength > 1) ? .type2DMultisampleArray : .type2DMultisample
            } else {
                desc.textureType = (arrayLength > 1) ? .type2DArray : .type2D
            }
        case .typeCube:
            desc.textureType = (arrayLength > 1) ? .typeCubeArray : .typeCube
        case .type3D:
            desc.textureType = .type3D
        case .unknown:
            Log.err("MetalGraphicsDevice.makeTexture error: Unknown texture type!")
            return nil
        }
        desc.pixelFormat = pixelFormat
        desc.width = descriptor.width
        desc.height = descriptor.height
        desc.depth = descriptor.depth
        desc.mipmapLevelCount = descriptor.mipmapLevels
        desc.sampleCount = descriptor.sampleCount
        desc.arrayLength = arrayLength
        //desc.resourceOptions = .storageModePrivate
        desc.cpuCacheMode = .defaultCache
        desc.storageMode = .private
        desc.allowGPUOptimizedContents = true

        desc.usage = [] // MTLTextureUsageUnknown
        if descriptor.usage.intersection([.sampled, .shaderRead]).isEmpty == false {
            desc.usage.insert(.shaderRead)
        }
        if descriptor.usage.intersection([.storage, .shaderWrite]).isEmpty == false {
            desc.usage.insert(.shaderWrite)
        }
        if descriptor.usage.contains(.renderTarget) {
            desc.usage.insert(.renderTarget)
        }
        if descriptor.usage.contains(.pixelFormatView) {
            desc.usage.insert(.pixelFormatView) // view with a different pixel format.
        }

        if let texture = device.makeTexture(descriptor: desc) {
            return MetalTexture(device: self, texture: texture)
        } else {
            Log.err("MTLDevice.makeTexture failed!")
        }

        return nil
    }

    func makeTransientRenderTarget(type textureType: TextureType,
                                   pixelFormat: PixelFormat,
                                   width: Int,
                                   height: Int,
                                   depth: Int,
                                   sampleCount: Int) -> Texture? {
        let pixelFormat = pixelFormat.mtlPixelFormat()
        if pixelFormat == .invalid {
            Log.err("MetalGraphicsDevice.makeTexture error: Invalid pixel format!")
            return nil
        }
        if width < 1 || height < 1 || depth < 1 {
            Log.error("Texture dimensions (width, height, depth) value must be greater than or equal to 1.")
            return nil
        }
        if sampleCount.isPowerOfTwo == false {
            Log.error("MetalGraphicsDevice.makeTexture error: Sample count must be a power of two!")
            return nil
        }
        if sampleCount > 64 {
            Log.error("MetalGraphicsDevice.makeTexture error: Sample count must be less than or equal to 64!")
            return nil
        }

        let desc = MTLTextureDescriptor()
        switch textureType {
        case .type1D:       desc.textureType = .type1D
        case .type2D:
            desc.textureType = sampleCount > 1 ? .type2DMultisample : .type2D
        case .typeCube:     desc.textureType = .typeCube
        case .type3D:       desc.textureType = .type3D
        case .unknown:
            Log.err("MetalGraphicsDevice.makeTexture error: Unknown texture type!")
            return nil
        }
        desc.pixelFormat = pixelFormat
        desc.width = width
        desc.height = height
        desc.depth = depth
        desc.mipmapLevelCount = 1
        desc.sampleCount = sampleCount
        desc.arrayLength = 1
        desc.resourceOptions = .storageModeMemoryless
        desc.cpuCacheMode = .defaultCache
        desc.storageMode = .memoryless
        desc.allowGPUOptimizedContents = true
        desc.usage = .renderTarget

        if let texture = device.makeTexture(descriptor: desc) {
            return MetalTexture(device: self, texture: texture)
        } else {
            Log.err("MTLDevice.makeTexture failed!")
        }
        return nil
    }

    func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState? {
        let addressMode = { (m: SamplerAddressMode) -> MTLSamplerAddressMode in
            switch m {
            case .clampToEdge:      .clampToEdge
            case .repeat:           .repeat
            case .mirrorRepeat:     .mirrorRepeat
            case .clampToZero:      .clampToZero
            }
        }
        let minMagFilter = { (f: SamplerMinMagFilter) -> MTLSamplerMinMagFilter in
            switch f {
            case .nearest:          .nearest
            case .linear:           .linear
            }
        }
        let mipFilter = { (f: SamplerMipFilter) -> MTLSamplerMipFilter in
            switch f {
            case .notMipmapped:     .notMipmapped
            case .nearest:          .nearest
            case .linear:           .linear
            }
        }
        let compareFunction = { (fn: CompareFunction) -> MTLCompareFunction in
            switch fn {
            case .never:            .never
            case .less:             .less
            case .equal:            .equal
            case .lessEqual:        .lessEqual
            case .greater:          .greater
            case .notEqual:         .notEqual
            case .greaterEqual:     .greaterEqual
            case .always:           .always
            }
        }

        let desc = MTLSamplerDescriptor()
        desc.sAddressMode = addressMode(descriptor.addressModeU)
        desc.tAddressMode = addressMode(descriptor.addressModeV)
        desc.rAddressMode = addressMode(descriptor.addressModeW)
        desc.minFilter = minMagFilter(descriptor.minFilter)
        desc.magFilter = minMagFilter(descriptor.magFilter)
        desc.mipFilter = mipFilter(descriptor.mipFilter)
        desc.lodMinClamp = descriptor.lodMinClamp
        desc.lodMaxClamp = descriptor.lodMaxClamp
        desc.maxAnisotropy = descriptor.maxAnisotropy
        desc.normalizedCoordinates = descriptor.normalizedCoordinates
        if descriptor.normalizedCoordinates == false {
            desc.magFilter = desc.minFilter
            desc.sAddressMode = .clampToEdge
            desc.tAddressMode = .clampToEdge
            desc.rAddressMode = .clampToEdge
            desc.mipFilter = .notMipmapped
            desc.maxAnisotropy = 1
        }
        desc.compareFunction = compareFunction(descriptor.compareFunction)

        if let samplerState = device.makeSamplerState(descriptor: desc) {
            return MetalSamplerState(device: self, sampler: samplerState)
        } else {
            Log.err("MTLDevice.makeSamplerState failed.")
        }
        return nil
    }

    func makeEvent() -> GPUEvent? {
        if let event = device.makeEvent() {
            return MetalEvent(device: self, event: event)
        }
        return nil
    }

    func makeSemaphore() -> GPUSemaphore? {
        if let event = device.makeEvent() {
            return MetalSemaphore(device: self, event: event)
        }
        return nil
    }
}
#endif //if ENABLE_METAL
