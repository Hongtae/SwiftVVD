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

    // Common lifecycle accessors.

    var isPresented: Binding<Bool>? {
        switch self {
        case .sheet:                     return nil
        case .alert(let p):              return p.isPresented
        case .confirmationDialog(let p): return p.isPresented
        }
    }

    var onDismiss: (() -> Void)? {
        switch self {
        case .sheet(let p):              return p.onDismiss
        case .alert(let p):              return p.onDismiss
        case .confirmationDialog(let p): return p.onDismiss
        }
    }

    // Called by WindowController.removeModal(child:reason:) when the modal is dismissed.
    // reason drives isPresented reset and onDismiss call semantics.
    func cleanup(reason: ModalDismissReason, notifyDismiss: Bool = true) {
        if case .sheet(let p) = self {
            if notifyDismiss {
                switch reason {
                case .userAction, .dismissed, .byParent:
                    p.onDismiss?()
                case .cancelled:
                    break
                }
            }
            return
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

enum ModalDismissReason: Equatable {
    case userAction   // user closed the window / tapped dismiss
    case dismissed    // programmatic (isPresented already false)
    case byParent     // parent window closed
    case cancelled    // queued but never shown
}

// MARK: - Visibility

// Confirmation-dialog title visibility.
public enum Visibility: Hashable, CaseIterable, Sendable {
    case automatic
    case visible
    case hidden
}

// MARK: - DialogSuppressionConfiguration

// Suppression configuration surface. Suppression UI is not implemented yet.
public struct DialogSuppressionConfiguration: Hashable, Sendable {}

extension DialogSuppressionConfiguration {
    struct Key: EnvironmentKey {
        static let defaultValue: DialogSuppressionConfiguration? = nil
    }
}

// MARK: - DialogSeverity

// Dialog severity values used by alert/dialog presentation.
public struct DialogSeverity: Equatable, Sendable {
    let rawValue: Int
    init(_ rawValue: Int) { self.rawValue = rawValue }

    public static let automatic = DialogSeverity(0)
    public static let critical  = DialogSeverity(1)
    public static let standard  = DialogSeverity(2)
}

private struct DialogSeverityEnvironmentKey: EnvironmentKey {
    static let defaultValue: DialogSeverity = .automatic
}

private struct DialogPreventsAppTerminationKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private struct DialogIconEnvironmentKey: EnvironmentKey {
    static let defaultValue: Image? = nil
}

private struct DialogTintColorEnvironmentKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

private struct DialogColorSchemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: ColorScheme? = nil
}

extension EnvironmentValues {
    var dialogSeverity: DialogSeverity {
        get { self[DialogSeverityEnvironmentKey.self] }
        set { self[DialogSeverityEnvironmentKey.self] = newValue }
    }

    var dialogPreventsAppTermination: Bool? {
        get { self[DialogPreventsAppTerminationKey.self] }
        set { self[DialogPreventsAppTerminationKey.self] = newValue }
    }

    var dialogIcon: Image? {
        get { self[DialogIconEnvironmentKey.self] }
        set { self[DialogIconEnvironmentKey.self] = newValue }
    }

    var dialogTintColor: Color? {
        get { self[DialogTintColorEnvironmentKey.self] }
        set { self[DialogTintColorEnvironmentKey.self] = newValue }
    }

    var dialogColorScheme: ColorScheme? {
        get { self[DialogColorSchemeEnvironmentKey.self] }
        set { self[DialogColorSchemeEnvironmentKey.self] = newValue }
    }

    var dialogSuppression: DialogSuppressionConfiguration? {
        get { self[DialogSuppressionConfiguration.Key.self] }
        set { self[DialogSuppressionConfiguration.Key.self] = newValue }
    }
}

extension View {
    nonisolated public func dialogIcon(_ icon: Image?) -> some View {
        environment(\.dialogIcon, icon)
    }

    nonisolated public func dialogSeverity(_ severity: DialogSeverity) -> some View {
        environment(\.dialogSeverity, severity)
    }

    nonisolated public func dialogPreventsAppTermination(_ prevents: Bool?) -> some View {
        environment(\.dialogPreventsAppTermination, prevents)
    }
}

extension Scene {
    nonisolated public func dialogIcon(_ icon: Image?) -> some Scene {
        environment(\.dialogIcon, icon)
    }

    nonisolated public func dialogSeverity(_ severity: DialogSeverity) -> some Scene {
        environment(\.dialogSeverity, severity)
    }
}
