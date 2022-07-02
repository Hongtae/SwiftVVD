//
//  File: UIKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
import UIKit
import QuartzCore

class UIKitView: UIView, UITextFieldDelegate {

    var defaultTextFieldHeight: Int { 30 }
    var defaultTextFieldMargin: Int { 2 }

    var appActivated: Bool = false

    var textInput: Bool = false {
        didSet {
            if (textInput)
            {
                Log.info("TextInput enabled.\n")
                self.textField.isHidden = false
                self.textField.becomeFirstResponder()
            }
            else
            {
                Log.info("TextInput disabled.\n")
                self.textField.resignFirstResponder()
                self.textField.isHidden = true
            }

        }
    }

    var windowFrame: CGRect {
        let frame = self.window?.frame ?? self.bounds
        return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    var contentBounds: CGRect {
        let bounds = self.bounds
        return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
    }

    var textField: UITextField

    var touches: [UITouch] = []
    var observers: [NSObjectProtocol] = []

    weak var proxyWindow: UIKitWindow?

    override var isHidden: Bool {
        didSet {
            if self.isHidden != oldValue {
                if self.appActivated {
                    if self.isHidden {
                        self.postWindowEvent(type: .hidden)
                    } else {
                        self.postWindowEvent(type: .shown)
                    }
                }
            }
        }
    }

    override var canBecomeFirstResponder: Bool { true }
    override var canResignFirstResponder: Bool { true }
    override class var layerClass: AnyClass { CAMetalLayer.self }

    override init(frame: CGRect) {
        self.textField = UITextField()
        super.init(frame: frame)
        self.setup()
    }

    required init?(coder: NSCoder) {
        self.textField = UITextField()
        super.init(coder: coder)
        self.setup()
    }

    func setup() {

        self.backgroundColor = UIColor.clear
        self.isMultipleTouchEnabled = true
        self.isExclusiveTouch = true
        self.isUserInteractionEnabled = true
        super.isHidden = true

        self.textInput = false

        let frame = self.bounds
        self.textField.frame = CGRect(
            x: 0, y: 0,
            width: frame.width - CGFloat(self.defaultTextFieldMargin * 2),
            height: CGFloat(self.defaultTextFieldHeight))
        self.textField.delegate = self
        self.textField.textAlignment = .center
        self.textField.contentVerticalAlignment = .center
        self.textField.backgroundColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.4)
        self.textField.textColor = .black
        self.textField.borderStyle = .roundedRect
        self.textField.clearButtonMode = .always
        self.textField.isHidden = true
        self.textField.clearsOnBeginEditing = true
        self.textField.autoresizingMask = .flexibleWidth
        self.textField.adjustsFontSizeToFitWidth = false
        self.textField.addTarget(self, action: #selector(updateTextField(_:)), for: .editingChanged)

        let queue = OperationQueue.main
        let center = NotificationCenter.default
        self.observers = [
            center.addObserver(forName: UIResponder.keyboardWillShowNotification,
                               object: nil,
                               queue: queue) { [weak self](notification) in
                                   self?.keyboardWillShow(notification)
                               },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification,
                               object: nil,
                               queue: queue) { [weak self](notification) in
                                   self?.keyboardWillHide(notification)
                               },
            center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                               object: nil,
                               queue: queue) { [weak self](notification) in
                                   self?.keyboardWillChangeFrame(notification)
                               },
            center.addObserver(forName: UIResponder.keyboardDidChangeFrameNotification,
                               object: nil,
                               queue: queue) { [weak self](notification) in
                                   self?.keyboardDidChangeFrame(notification)
                               },
            center.addObserver(forName: UIApplication.willResignActiveNotification,
                               object: nil,
                               queue: queue) { [weak self](notification) in
                                   self?.applicationWillResignActive(notification)
                               },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                               object: nil,
                               queue: queue) { [weak self](notification) in
                                   self?.applicationDidBecomeActive(notification)
                               },
        ]

        self.appActivated = UIApplication.shared.applicationState == .active
    }

    deinit {
        self.textField.removeTarget(self, action: nil, for: .editingChanged)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func becomeFirstResponder() -> Bool {
        if super.becomeFirstResponder() {
            if self.appActivated {
                self.postWindowEvent(type: .activated)
            }
        }
        return false
    }

    override func resignFirstResponder() -> Bool {
        if super.resignFirstResponder() {
            if self.appActivated {
                self.postWindowEvent(type: .inactivated)
            }
        }
        return false
    }

    @objc func updateTextField(_ textField: UITextField) {
        self.postTextCompositionEvent(textField.text ?? "")
    }

    // MARK: - Notifications
    func keyboardWillShow(_ notification: Notification) {
    }

    func keyboardWillHide(_ notification: Notification) {
    }

    func keyboardWillChangeFrame(_ notification: Notification) {
    }

    func keyboardDidChangeFrame(_ notification: Notification) {
    }

    func applicationWillResignActive(_ notification: Notification) {
        self.appActivated = false
        if self.isHidden == false {
            if self.isFirstResponder {
                self.postWindowEvent(type: .inactivated)
            }
            self.postWindowEvent(type: .hidden)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        self.appActivated = true
        if self.isHidden == false {
            self.postWindowEvent(type: .shown)

            if self.isFirstResponder {
                self.postWindowEvent(type: .activated)
            }
        }
    }

    // MARK: - Event
    func postWindowEvent(type: WindowEventType) {
        if let window = self.proxyWindow {
            window.postWindowEvent(type: type)
        }
    }

    func postTextCompositionEvent(_ text: String) {
        if let window = self.proxyWindow {
            window.postKeyboardEvent(KeyboardEvent(type: .textComposition,
                                                   window: window,
                                                   deviceID: 0,
                                                   key: .none,
                                                   text: text))
        }
    }

}
#endif
