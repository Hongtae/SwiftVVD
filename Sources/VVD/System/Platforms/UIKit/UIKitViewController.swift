//
//  File: UIKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
internal import UIKit

final class UIKitViewController: UIViewController {

    var uiView: UIKitView? = nil

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func loadView() {
        if self.uiView == nil {
            self.uiView = UIKitView()
        }
        self.view = self.uiView
    }
}

#endif
