//
//  File: UIKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
@_implementationOnly import UIKit

private final class UIKitViewController: UIViewController {

    var uiView: UIKitView? = nil

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func loadView() {
        if self.uiView == nil {
            self.uiView = makeUIKitView()
        }
        self.view = (self.uiView as! UIView)
    }
}

@MainActor
func makeUIKitViewController() -> AnyObject {
    UIKitViewController()
}

#endif
