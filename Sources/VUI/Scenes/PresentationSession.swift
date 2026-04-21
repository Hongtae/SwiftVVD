//
//  File: PresentationSession.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// PresentationSession carries lifecycle data for a modal presentation.
// Stored inside ModalChildEntry so WindowController can clean up bindings and callbacks
// when the modal is dismissed, regardless of overlay vs platform-window mode.

// MARK: - PresentationSession

enum PresentationSession: @unchecked Sendable {
    case sheet(SheetPreference)
    case alert(AlertPreference)
    case confirmationDialog(ConfirmationDialogPreference)
    /// ModalWindowScene-based modal. Remove this case once all modals are migrated
    /// to preference-driven (sheet/alert) sessions.
    case legacy

    // Common lifecycle accessors (not meaningful for .legacy).

    var isPresented: Binding<Bool>? {
        switch self {
        case .sheet(let p):              return p.isPresented
        case .alert(let p):              return p.isPresented
        case .confirmationDialog(let p): return p.isPresented
        case .legacy:                    return nil
        }
    }

    var onDismiss: (() -> Void)? {
        switch self {
        case .sheet(let p):              return p.onDismiss
        case .alert(let p):              return p.onDismiss
        case .confirmationDialog(let p): return p.onDismiss
        case .legacy:                    return nil
        }
    }

    // Called by WindowController.removeModalChild when the modal is dismissed.
    // reason drives isPresented reset and onDismiss call semantics.
    // .legacy is handled separately via scene callbacks in removeModalChild.
    func cleanup(reason: ModalDismissReason) {
        if case .legacy = self {
            return  // handled via onModalSession* callbacks, not here
        }
        switch reason {
        case .userAction, .byParent:
            isPresented?.wrappedValue = false
            onDismiss?()
        case .dismissed:
            onDismiss?()
        case .cancelled:
            isPresented?.wrappedValue = false
        }
    }
}

// MARK: - ModalDismissReason

enum ModalDismissReason {
    case userAction   // user closed the window / tapped dismiss
    case dismissed    // programmatic (isPresented already false)
    case byParent     // parent window closed
    case cancelled    // queued but never shown
}

// MARK: - DialogSeverity

// Severity used by alert and confirmation dialog presentations.
public struct DialogSeverity: Equatable, Sendable {
    let rawValue: Int
    private init(_ rawValue: Int) { self.rawValue = rawValue }

    public static let automatic = DialogSeverity(0)
    public static let critical  = DialogSeverity(1)
    public static let standard  = DialogSeverity(2)
}
