//
//  File: Application.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol Application: AnyObject {
    var activationPolicy: ActivationPolicy { get set }
    var isActive: Bool { get }
    func terminate(exitCode: Int)
    @MainActor static func run(delegate: ApplicationDelegate?) -> Int

    var screens: [any Screen] { get }
    var mainScreen: (any Screen)? { get }

    /// The application-wide system clipboard, when provided by the backend.
    var clipboard: (any Clipboard)? { get }
}

public extension Application {
    var clipboard: (any Clipboard)? { nil }
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

public enum ActivationPolicy {
    case regular
    case accessory
}
