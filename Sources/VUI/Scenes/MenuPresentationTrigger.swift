//
//  File: MenuPresentationTrigger.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// Standalone Menu opens through a backend control-style trigger rather than the
// gesture responder path. This translates left-click activation into the shared
// popup presentation path.
struct MenuPresentationTrigger {
    private weak var activeResponder: MenuDropdownResponder?

    mutating func reset() {
        activeResponder?.onPressingChanged?(false)
        activeResponder = nil
    }

    @discardableResult
    mutating func handleMouseEvent(_ event: MouseEvent,
                                   viewGraph: ViewGraph,
                                   rootResponder: MultiViewResponder,
                                   open: (MenuDropdownResponder) -> Void) -> Bool {
        guard event.type != .wheel else { return false }

        if let activeResponder {
            switch event.type {
            case .buttonUp:
                if !activeResponder.menuIsOpen {
                    activeResponder.onPressingChanged?(false)
                }
                self.activeResponder = nil
                return true
            case .move, .pointing:
                return true
            default:
                self.activeResponder = nil
                return false
            }
        }

        guard event.type == .buttonDown,
              event.buttonID == 0 else {
            return false
        }

        var consumed = false
        viewGraph.data.withCurrent {
            guard let responder = hitResponder(at: event.location,
                                               rootResponder: rootResponder),
                  responder.snapshotIsEnabled else {
                return
            }
            if responder.menuIsOpen {
                responder.dismissMenu()
                consumed = true
                return
            }
            activeResponder = responder
            responder.onPressingChanged?(true)
            open(responder)
            consumed = true
        }
        return consumed
    }

    private func hitResponder(at location: CGPoint,
                              rootResponder: MultiViewResponder) -> MenuDropdownResponder? {
        let hits = rootResponder.respondersContaining(point: location)
        let menuHits = hits.compactMap { $0 as? MenuDropdownResponder }
        return menuHits.first
    }
}
