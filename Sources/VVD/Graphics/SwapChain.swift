//
//  File: SwapChain.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public protocol SwapChain: Sendable {
    var pixelFormat: PixelFormat { get set }
    var maximumBufferCount: Int { get }
    var displaySyncEnabled: Bool { get set }

    func currentRenderPassDescriptor() -> RenderPassDescriptor
    func present(waitEvents: [GPUEvent]) -> Bool
    @discardableResult
    func present() -> Bool

    var commandQueue: CommandQueue { get }
}

extension SwapChain {
    public func present() -> Bool {
        return present(waitEvents:[])
    }
}
