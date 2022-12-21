//
//  File: WaylandApplication.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation

public class WaylandApplication: Application {
    public func terminate(exitCode : Int) {

    }

    public static func run(delegate: ApplicationDelegate?) -> Int {
        0
    }
    
    public static var shared: Application? = nil
}

#endif //if ENABLE_UIKIT
