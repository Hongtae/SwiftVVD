#if ENABLE_UIKIT

public class UIKitWindow: Window {

    public private(set) var contentBounds: CGRect = .null
    public private(set) var windowFrame: CGRect = .null
    public private(set) var contentScaleFactor: Float = 0.0

    public var origin: CGPoint {
        get { .zero }
        set(value) {
        }
    }
    public var contentSize: CGSize {
        get { .zero }
        set(value) {
        }
    }

    public private(set) var delegate: WindowDelegate?

    public required init(name: String, style: WindowStyle, delegate: WindowDelegate?) {

    }

    public func show() {

    }
    public func hide() {

    }
    public func activate() {

    }
    public func minimize() {

    }

    public func showMouse(_: Bool, forDeviceID: Int) {

    }
    public func isMouseVisible(forDeviceID: Int) -> Bool {
        false
    }
    public func holdMouse(_: Bool, forDeviceID: Int) {

    }
    public func isMouseHeld(forDeviceID: Int) -> Bool {
        false
    }
    public func setMousePosition(_: CGPoint, forDeviceID: Int) {

    }
    public func mousePosition(forDeviceID: Int) -> CGPoint {
        .zero
    }
 
    public func enableTextInput(_: Bool, forDeviceID: Int) {

    }
    public func isTextInputEnabled(forDeviceID: Int) -> Bool {
        false
    }
}

#endif //ENABLE_UIKIT
