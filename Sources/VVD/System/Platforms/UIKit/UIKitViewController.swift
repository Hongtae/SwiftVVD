//
//  File: UIKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
import UIKit

final class UIKitViewController: UIViewController {

    var ukview: UIKitView? = nil

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func loadView() {
        if self.ukview == nil {
            self.ukview = UIKitView()
        }
        self.view = self.ukview
    }
}
#endif
