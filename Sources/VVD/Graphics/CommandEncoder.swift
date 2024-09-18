//
//  File: CommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol CommandEncoder {
    func endEncoding()
    var isCompleted: Bool { get }

    func waitEvent(_ event: GPUEvent)
    func signalEvent(_ event: GPUEvent)

    func waitSemaphoreValue(_ semaphore: GPUSemaphore, value: UInt64)
    func signalSemaphoreValue(_ semaphore: GPUSemaphore, value: UInt64)

    var commandBuffer: CommandBuffer { get }
}
