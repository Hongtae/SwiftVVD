//
//  File: CommandBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public typealias CommandBufferHandler = (CommandBuffer) -> Void

public protocol CommandBuffer {
    func makeRenderCommandEncoder(descriptor: RenderPassDescriptor) -> RenderCommandEncoder?
    func makeComputeCommandEncoder() -> ComputeCommandEncoder?
    func makeCopyCommandEncoder() -> CopyCommandEncoder?

    func addCompletedHandler(_ handler: @escaping CommandBufferHandler)
    @discardableResult func commit() -> Bool

    var status: CommandBufferStatus { get }
    var commandQueue: CommandQueue { get }
    var device: GraphicsDevice { get }
}

public enum CommandBufferStatus {
    case ready
    case encoding
    case committed
}
