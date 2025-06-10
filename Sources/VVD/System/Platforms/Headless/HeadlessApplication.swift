//
//  File: HeadlessApplication.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

final class HeadlessApplication: Application, @unchecked Sendable {

    private var requestExitWithCode: Int?
    nonisolated(unsafe) static var shared: HeadlessApplication? = nil

    public static func run(delegate: ApplicationDelegate?) -> Int {
        precondition(Thread.isMainThread, "\(#function) must be called on the main thread.")

        let app = HeadlessApplication()
        self.shared = app
        delegate?.initialize(application: app)

        var exitCode = -1
        while true {
            if let code = app.requestExitWithCode {
                exitCode = code
                break
            }

            let next = RunLoop.main.limitDate(forMode: .default)
            let s = next?.timeIntervalSinceNow ?? 1.0
            if s > 0.0 {
                Thread.sleep(forTimeInterval: min(s, 0.01))
            }
        }

        delegate?.finalize(application: app)
        self.shared = nil        
        return exitCode
    }

    public func terminate(exitCode: Int) {
        Task { @MainActor in self.requestExitWithCode = exitCode }
    }

    private init() {
    }
}
