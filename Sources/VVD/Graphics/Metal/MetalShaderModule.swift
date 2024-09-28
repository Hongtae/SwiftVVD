//
//  File: MetalShaderModule.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

struct MetalResourceBinding {
    var set: Int
    var binding: Int

    var bufferIndex: Int
    var textureIndex: Int
    var samplerIndex: Int

    var type: ShaderResourceType
}

struct MetalStageResourceBindingMap {
    var resourceBindings: [MetalResourceBinding] // spir-v to msl bind mapping
    var inputAttributeIndexOffset: Int
    var pushConstantIndex: Int
    var pushConstantOffset: Int
    var pushConstantSize: Int
    var pushConstantBufferSize: Int     // buffer size in MSL (not spir-v)
}

final class MetalShaderModule: ShaderModule {

    public var device: GraphicsDevice
    let library: MTLLibrary

    struct NameConversion {
        var original: String
        var cleansed: String
    }

    public let functionNames: [String] // spirv names
    let functionNameMap: [String: String]   // spirv to msl table
    var workgroupSize: MTLSize

    var bindings: MetalStageResourceBindingMap


    init(device: MetalGraphicsDevice, library: MTLLibrary, names: [NameConversion]) {
        self.device = device
        self.library = library

        var fnames: [String] = []
        var fnameMap: [String: String] = [:]

        for nc in names {
            fnames.append(nc.original)
            fnameMap[nc.original] = nc.cleansed
        }

        self.functionNames = fnames
        self.functionNameMap = fnameMap
        self.workgroupSize = MTLSize(width: 1, height: 1, depth: 1)
        self.bindings = MetalStageResourceBindingMap(
            resourceBindings: [],
            inputAttributeIndexOffset: 0,
            pushConstantIndex: 0,
            pushConstantOffset: 0,
            pushConstantSize: 0,
            pushConstantBufferSize: 0)

        // Check function availability
        fnames = library.functionNames
        for nc in names {
            if fnames.contains(nc.cleansed) == false {
                Log.err("MTLLibrary function not found: \(nc.cleansed)")
            }
        }
    }

    public func makeFunction(name: String) -> ShaderFunction? {
        if let fname = functionNameMap[name] {
            if let fn = self.library.makeFunction(name: fname) {
                return MetalShaderFunction(module: self, function: fn, workgroupSize: workgroupSize, name: name)
            }
        }
        return nil
    }

    public func makeFunction(name: String, constantValues: [ShaderFunctionConstantValue]) -> ShaderFunction? {
        if constantValues.isEmpty {
            return makeFunction(name: name)
        }

        if let fname = functionNameMap[name] {

            let fcv = MTLFunctionConstantValues()
            for value in constantValues {
                value.data.withUnsafeBytes {
                    if $0.count >= value.size, value.size >= value.type.size() {
                        fcv.setConstantValue($0.baseAddress!,
                                             type: value.type.mtlDataType(),
                                             index: value.index)
                    } else {
                        Log.err("ShaderFunctionConstantValue invalid data! (type:\(value.type), index:\(value.index), size: \(value.size))")
                    }
                }
            }

            do {
                let fn = try self.library.makeFunction(name: fname, constantValues: fcv)
                return MetalShaderFunction(module: self, function: fn, workgroupSize: workgroupSize, name: name)
            } catch {
                Log.err("MTLLibrary.makeFunction failed: \(error.localizedDescription)")
            }
        }
        return nil
    }
}
#endif //if ENABLE_METAL
