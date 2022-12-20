//
//  File: WaylandApplication.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND

public class WaylandApplication: Application {
    public func terminate(exitCode : Int) {

    }

    static func run(delegate: ApplicationDelegate?) -> Int {
        0
    }
    
    static var shared: Application? = nil
}

#endif //if ENABLE_UIKIT
