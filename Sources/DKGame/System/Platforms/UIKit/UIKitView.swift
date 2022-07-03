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

    var defaultTextFieldHeight: CGFloat { 30 }
    var defaultTextFieldMargin: CGFloat { 2 }

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

    var textField: UITextField

    var touches: [UITouch?] = []
    var observers: [NSObjectProtocol] = []

    weak var proxyWindow: UIKitWindow?

    override var canBecomeFirstResponder: Bool { true }
    override var canResignFirstResponder: Bool { true }
    override class var layerClass: AnyClass { CAMetalLayer.self }

    override var frame: CGRect {
        didSet {
            if let window = self.proxyWindow {
                if frame != oldValue {
                    if frame.size == oldValue.size {
                        window.postWindowEvent(type: .moved)
                    } else {
                        window.postWindowEvent(type: .resized)
                    }
                }
            }
        }
    }

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

    var windowFrame: CGRect {
        let frame = self.window?.frame ?? self.bounds
        return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    var contentBounds: CGRect {
        let bounds = self.bounds
        return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
    }

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
            width: frame.width - self.defaultTextFieldMargin * 2,
            height: self.defaultTextFieldHeight)
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
        self.textField.delegate = nil
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

    func touchLocation(atIndex index: Int) -> CGPoint? {
        if index < self.touches.count {
            if let touch = self.touches[index] {
                return touch.location(in: self)
            }
        }
        return nil
    }

    @objc func updateTextField(_ textField: UITextField) {
        self.postTextCompositionEvent(textField.text ?? "")
    }

    // MARK: - UITouch, Touch Events
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            var index = self.touches.count
            // find empty slot in self.touches
            for i in 0..<self.touches.count {
                if self.touches[i] == nil {
                    index = i
                    break
                }
            }
            if index == self.touches.count {    // no empty slot, add one
                self.touches.append(nil)
            }

            if let window = self.proxyWindow {
                let device: MouseEventDevice = touch.type == .stylus ? .stylus : .touch
                let pos = touch.location(in: self)
                let tilt = CGPoint(x: touch.azimuthAngle(in: self), y: touch.altitudeAngle)
                window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                 window: window,
                                                 device: device,
                                                 deviceID: index,
                                                 buttonID: 0,
                                                 location: pos,
                                                 delta: .zero,
                                                 tilt: tilt,
                                                 pressure: touch.force))
            }
            self.touches[index] = touch
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let window = self.proxyWindow else { return }

        for touch in touches {
            var processed = false

            for index in 0..<self.touches.count {
                if self.touches[index] === touch {
                    let device: MouseEventDevice = touch.type == .stylus ? .stylus : .touch
                    let pos = touch.location(in: self)
                    let old = touch.previousLocation(in: self)
                    let delta = CGPoint(x: pos.x - old.x, y: pos.y - old.y)
                    let tilt = CGPoint(x: touch.azimuthAngle(in: self), y: touch.altitudeAngle)
                    window.postMouseEvent(MouseEvent(type: .move,
                                                     window: window,
                                                     device: device,
                                                     deviceID: index,
                                                     buttonID: 0,
                                                     location: pos,
                                                     delta: delta,
                                                     tilt: tilt,
                                                     pressure: touch.force))
                    processed = true
                    break
                }
            }
            if processed == false {
                Log.err("Untrackable touch event: \(touch)")
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            var processed = false

            for index in 0..<self.touches.count {
                if self.touches[index] === touch {


                    if let window = self.proxyWindow {
                        let device: MouseEventDevice = touch.type == .stylus ? .stylus : .touch
                        let pos = touch.location(in: self)
                        let old = touch.previousLocation(in: self)
                        let delta = CGPoint(x: pos.x - old.x, y: pos.y - old.y)
                        let tilt = CGPoint(x: touch.azimuthAngle(in: self), y: touch.altitudeAngle)
                        window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                         window: window,
                                                         device: device,
                                                         deviceID: index,
                                                         buttonID: 0,
                                                         location: pos,
                                                         delta: delta,
                                                         tilt: tilt,
                                                         pressure: touch.force))
                    }
                    self.touches[index] = nil
                    processed = true
                    break
                }
            }
            if processed == false {
                Log.err("Untrackable touch event: \(touch)")
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.touchesEnded(touches, with: event)
    }

    override func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionBegan(motion, with: event)
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
    }

    override func motionCancelled(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionCancelled(motion, with: event)
    }

    // MARK: - UITextFieldDelegate
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
    }

    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        Log.info("textFieldDidEndEditing, textField.text: \(String(describing: textField.text))")

        if textField.text?.isEmpty == false {
            self.postTextInputEvent(textField.text!)
        }
        self.postTextInputEvent("\u{27}")  // \e (esc)
        self.postTextInputEvent("")
        self.textInput = false
    }

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        return true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        self.postTextCompositionEvent("")
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField.text?.isEmpty == false {
            self.postTextInputEvent(textField.text!)
        }
        self.postTextInputEvent("\n")
        textField.text = ""
        return true
    }

    // MARK: - Notifications
    func keyboardWillShow(_ notification: Notification) {
    }

    func keyboardWillHide(_ notification: Notification) {
    }

    func keyboardWillChangeFrame(_ notification: Notification) {
    }

    func keyboardDidChangeFrame(_ notification: Notification) {
        if let keyboardFrameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            var keyboardFrame: CGRect = keyboardFrameValue.cgRectValue
            keyboardFrame = self.convert(keyboardFrame, from: nil)

            var textFieldFrame = self.textField.frame
            textFieldFrame.origin.y = keyboardFrame.origin.y - textFieldFrame.size.height - self.defaultTextFieldMargin
            self.textField.frame = textFieldFrame
        }
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

    func postTextInputEvent(_ text: String) {
        if let window = self.proxyWindow {
            window.postKeyboardEvent(KeyboardEvent(type: .textInput,
                                                   window: window,
                                                   deviceID: 0,
                                                   key: .none,
                                                   text: text))
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
