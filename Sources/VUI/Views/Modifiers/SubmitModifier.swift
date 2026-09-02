//
//  File: SubmitModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct SubmitTriggers: OptionSet, Sendable {
    public typealias RawValue = Int

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let text = SubmitTriggers(rawValue: 1 << 0)
    public static let search = SubmitTriggers(rawValue: 1 << 2)
}

struct TriggerSubmitAction {
    let action: (SubmitTriggers) -> Void

    func callAsFunction(_ triggers: SubmitTriggers) {
        action(triggers)
    }
}

private struct TriggerSubmitActionKey: EnvironmentKey {
    static var defaultValue: TriggerSubmitAction? { nil }
}

extension EnvironmentValues {
    var triggerSubmission: TriggerSubmitAction? {
        get { self[TriggerSubmitActionKey.self] }
        set { self[TriggerSubmitActionKey.self] = newValue }
    }
}

struct OnSubmitModifier: ViewModifier {
    let allowed: SubmitTriggers
    let action: () -> Void
    @Environment(\.triggerSubmission) private var existingTrigger

    func body(content: Content) -> some View {
        content.environment(
            \.triggerSubmission,
            TriggerSubmitAction { triggers in
                guard allowed.intersection(triggers).isEmpty == false else {
                    return
                }
                existingTrigger?(triggers)
                action()
            }
        )
    }
}

struct SubmitScopeModifier: ViewModifier {
    let isBlocking: Bool
    let triggersToBlock: SubmitTriggers = [.text, .search]
    @Environment(\.triggerSubmission) private var triggerSubmission

    func body(content: Content) -> some View {
        content.environment(
            \.triggerSubmission,
            TriggerSubmitAction { triggers in
                if isBlocking,
                   triggersToBlock.intersection(triggers).isEmpty == false {
                    return
                }
                triggerSubmission?(triggers)
            }
        )
    }
}

extension View {
    nonisolated public func onSubmit(
        of triggers: SubmitTriggers = .text,
        _ action: @escaping () -> Void
    ) -> some View {
        modifier(OnSubmitModifier(allowed: triggers, action: action))
    }

    nonisolated public func submitScope(
        _ isBlocking: Bool = true
    ) -> some View {
        modifier(SubmitScopeModifier(isBlocking: isBlocking))
    }
}
