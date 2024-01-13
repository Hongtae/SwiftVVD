//
//  File: SwapChain.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol SwapChain {
    var pixelFormat: PixelFormat { get set }
    var maximumBufferCount: Int { get }

    func currentRenderPassDescriptor() -> RenderPassDescriptor
    func present(waitEvents: [GPUEvent]) -> Bool
    func present() -> Bool

    var commandQueue: CommandQueue { get }
}

extension SwapChain {
    public func present() -> Bool {
        return present(waitEvents:[])
    }
}
