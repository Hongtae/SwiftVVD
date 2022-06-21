//
//  File: UIKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
import UIKit

class UIKitViewController: UIViewController {

    var dkGameView: UIKitView? = nil

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func loadView() {
        if self.dkGameView == nil {
            self.dkGameView = UIKitView()
        }
        self.view = self.dkGameView
    }
}
#endif
