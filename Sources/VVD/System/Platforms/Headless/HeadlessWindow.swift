//
//  File: HeadlessWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

@MainActor
final class HeadlessWindow: Window {
    
    var activated: Bool = false
    var visible: Bool = false
    
    var contentBounds: CGRect = .zero
    var windowFrame: CGRect = .zero
    var contentScaleFactor: CGFloat = 1.0
    var resolution: CGSize = .zero
    
    var origin: CGPoint = .zero
    var contentSize: CGSize = .zero
    
    var title: String

    weak var delegate: WindowDelegate?

    var platformHandle: OpaquePointer? { nil }
    var isValid: Bool { true }

    var eventObservers = WindowEventObserverContainer()

    required init?(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) {
        self.title = name
        self.delegate = delegate
    }

    deinit {
    }

    func show() {
    }

    func hide() {
    }
    
    func activate() {
    }

    func minimize() {
    }
    
    func requestToClose() -> Bool {
        true
    }

    func close() {
    }

    func convertPointToScreen(_ pt: CGPoint) -> CGPoint {
        pt + self.origin
    }
    
    func convertPointFromScreen(_ pt: CGPoint) -> CGPoint {
        pt - self.origin
    }
}
