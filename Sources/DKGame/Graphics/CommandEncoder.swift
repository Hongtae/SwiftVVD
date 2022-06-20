//
//  File: CommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol CommandEncoder {
    func endEncoding()
    var isCompleted: Bool { get }

    func waitEvent(_ event: Event)
    func signalEvent(_ event: Event)

    func waitSemaphoreValue(_ semaphore: Semaphore, value: UInt64)
    func signalSemaphoreValue(_ semaphore: Semaphore, value: UInt64)

    var commandBuffer: CommandBuffer { get }
}
