//
//  File: App.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import DKGame

public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Self.Body { get }

    init()
}

class AppMain<A>: ApplicationDelegate where A: App {
    let app: A

    func initialize(application: Application) {
    }

    func finalize(application: Application) {
    }

    init() {
        self.app = A()
    }
}

extension App {
    public static func main() {
        let app = AppMain<Self>()
        let _ = runApplication(delegate: app)
    }
}
