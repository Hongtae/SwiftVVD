//
//  File: Application.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol Application {
    func terminate(exitCode : Int)
    static func run(delegate: ApplicationDelegate?) -> Int
    static var shared: Application? { get }
}

public protocol ApplicationDelegate: AnyObject {
    func initialize(application: Application)
    func finalize(application: Application)
}

public func sharedApplication() -> Application? {
    Platform.sharedApplication()
}

public func runApplication(delegate: ApplicationDelegate?) -> Int {
    Platform.runApplication(delegate: delegate)
}
