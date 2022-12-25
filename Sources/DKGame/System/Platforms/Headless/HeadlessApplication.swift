//
//  File: HeadlessApplication.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public class HeadlessApplication: Application {
    
    public static func run(delegate: ApplicationDelegate?) -> Int {
        let app = HeadlessApplication()
        self.shared = app
        delegate?.initialize(application: app)

        dispatchMain()

        delegate?.finalize(application: app)
        self.shared = nil        
        return 0
    }

    public func terminate(exitCode : Int) {
    }
    
    public static var shared: Application? = nil

    private init() {
    }

    deinit {
    }
}
