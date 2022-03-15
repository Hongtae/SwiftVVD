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

    public func showMouse(_: Bool, forDeviceId: Int) {

    }
    public func isMouseVisible(forDeviceId: Int) -> Bool {
        false
    }
    public func holdMouse(_: Bool, forDeviceId: Int) {

    }
    public func isMouseHeld(forDeviceId: Int) -> Bool {
        false
    }
    public func setMousePosition(_: CGPoint, forDeviceId: Int) {

    }
    public func mousePosition(forDeviceId: Int) -> CGPoint {
        .zero
    }
 
    public func enableTextInput(_: Bool, forDeviceId: Int) {

    }
    public func isTextInputEnabled(forDeviceId: Int) -> Bool {
        false
    }
}

#endif //ENABLE_UIKIT
