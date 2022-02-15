import Foundation

public enum DragOperation {
    case none, copy, move, link
}

public protocol DragTargetDelegate {
    func draggingEntered(files: [String], keyState: [Int], pt: CGPoint) -> DragOperation
    func draggingUpdated(files: [String], keyState: [Int], pt: CGPoint) -> DragOperation
    func draggingExited(files: [String], pt: CGPoint) -> DragOperation
    func draggingDropped(files: [String], pt: CGPoint) -> DragOperation
}

extension DragTargetDelegate {
    public func draggingEntered(files: [String], keyState: [Int], pt: CGPoint) -> DragOperation {
        return .none
    }
    public func draggingUpdated(files: [String], keyState: [Int], pt: CGPoint) -> DragOperation {
        return .none
    }
    public func draggingExited(files: [String], pt: CGPoint) -> DragOperation {
        return .none
    }
    public func draggingDropped(files: [String], pt: CGPoint) -> DragOperation {
        return .none
    }
}

public protocol WindowDelegate: DragTargetDelegate {
    func shouldClose() -> Bool
}

extension WindowDelegate {
    public func shouldClose() { true }
}

public protocol Window {
    func show()
    func hide()
}

public func makeWindow(name: String = "", delegate: WindowDelegate? = nil) -> Window { 
    return Platform.makeWindow(name: name, delegate: delegate)
}
