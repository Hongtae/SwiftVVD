//
//  File: Application.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

public protocol Application {
    func terminate(exitCode: Int)
    @MainActor static func run(delegate: ApplicationDelegate?) -> Int
    static var shared: Application? { get }
}

public protocol ApplicationDelegate: AnyObject {
    @MainActor func initialize(application: Application)
    @MainActor func finalize(application: Application)
}

public func sharedApplication() -> Application? {
    Platform.sharedApplication()
}

@MainActor @discardableResult
public func runApplication(delegate: ApplicationDelegate?) -> Int {
    Platform.runApplication(delegate: delegate)
}
