//
//  File: CommandQueue.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public struct CommandQueueFlags: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let render = CommandQueueFlags(rawValue: 0x1)   // render, copy commands
    public static let compute = CommandQueueFlags(rawValue: 0x2)  // compute, copy commands

    public static let copy: CommandQueueFlags = [] // copy(transfer) queue, always enabled.
}

public protocol CommandQueue: Sendable {
    func makeCommandBuffer() -> CommandBuffer?
    @MainActor
    func makeSwapChain(target: any Window) -> SwapChain?

    var flags: CommandQueueFlags { get }
    var device: GraphicsDevice { get }
}
