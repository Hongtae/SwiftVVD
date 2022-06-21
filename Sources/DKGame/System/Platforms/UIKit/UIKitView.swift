//
//  File: UIKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
import UIKit

class UIKitView: UIView {
    var textInput: Bool = false
    var windowRect: CGRect = .zero
    var contentRct: CGRect = .zero
    var textField: UITextField? = nil

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
    }
}
#endif
