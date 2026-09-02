#if os(macOS)
import AppKit
import XCTest
@testable import VVD

final class AppKitMouseEventTests: XCTestCase {
    @MainActor
    func testNativeClickMetadataIsForwarded() throws {
        let window = try XCTUnwrap(
            makeWindow(
                name: "AppKitMouseEventTests",
                style: [.title],
                delegate: nil
            ) as? AppKitWindow
        )
        defer { window.close() }

        let view = try XCTUnwrap(window.nsView)
        let nativeWindow = try XCTUnwrap(view.window)
        let observer = NSObject()
        var events: [MouseEvent] = []
        window.addEventObserver(observer) { (event: MouseEvent) in
            events.append(event)
        }

        let down = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 10.0, y: 12.0),
            modifierFlags: [.shift, .control],
            timestamp: 2.0,
            windowNumber: nativeWindow.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 3,
            pressure: 1.0
        ))
        let up = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: CGPoint(x: 10.0, y: 12.0),
            modifierFlags: [.shift, .control],
            timestamp: 2.1,
            windowNumber: nativeWindow.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 3,
            pressure: 0.0
        ))

        view.mouseDown(with: down)
        view.mouseUp(with: up)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.clickCount), [3, 3])
        XCTAssertEqual(events.map(\.modifiers), [
            [.shift, .control],
            [.shift, .control],
        ])
    }

    @MainActor
    func testNonClickEventForcesZeroClickCount() throws {
        let window = try XCTUnwrap(
            makeWindow(
                name: "AppKitMouseEventTests",
                style: [.title],
                delegate: nil
            ) as? AppKitWindow
        )
        defer { window.close() }

        let view = try XCTUnwrap(window.nsView)
        let nativeWindow = try XCTUnwrap(view.window)
        let observer = NSObject()
        var events: [MouseEvent] = []
        window.addEventObserver(observer) { (event: MouseEvent) in
            events.append(event)
        }

        let entered = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseEntered,
            location: .zero,
            modifierFlags: .option,
            timestamp: 3.0,
            windowNumber: nativeWindow.windowNumber,
            context: nil,
            eventNumber: 3,
            trackingNumber: 1,
            userData: nil
        ))
        view.mouseEntered(with: entered)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.clickCount, 0)
        XCTAssertEqual(events.first?.modifiers, .option)
    }
}
#endif
