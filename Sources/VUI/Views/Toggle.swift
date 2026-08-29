//
//  File: Toggle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

private extension Binding where Value == Bool {
    var toggleStateBinding: Binding<ToggleState> {
        Binding<ToggleState>(
            get: { ToggleState(isOn: self.wrappedValue) },
            set: { state, transaction in
                let binding = self.transaction(transaction)
                binding.wrappedValue = state.isOn
            }
        )
    }
}

private extension Binding where Value == ToggleState {
    var boolBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.wrappedValue.isOn },
            set: { isOn, transaction in
                let binding = self.transaction(transaction)
                binding.wrappedValue = ToggleState(isOn: isOn)
            }
        )
    }
}

public struct Toggle<Label>: View where Label: View {
    var _toggleState: Binding<ToggleState>
    let label: Label
    let appIntentAction: _AppIntentActionStorage?

    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self._toggleState = isOn.toggleStateBinding
        self.label = label()
        self.appIntentAction = nil
    }

    public var body: some View {
        // ResolvedToggleStyle + StaticSourceWriter + Static selects
        // CheckmarkToggleStyle for the menu branch.
        ResolvedToggleStyle(configuration: ToggleStyleConfiguration(
            isOn: _toggleState.boolBinding,
            toggleState: _toggleState
        ))
        .modifier(StaticSourceWriter<ToggleStyleConfiguration.Label, Label>(source: label))
        .modifier(
            StaticIf<StyleContextAcceptsPredicate<MenuStyleContext>,
                     ToggleStyleModifier<CheckmarkToggleStyle>,
                     EmptyModifier>(
                trueBody: ToggleStyleModifier(style: CheckmarkToggleStyle()),
                falseBody: EmptyModifier()
            )
        )
    }
}

extension Toggle where Label == Text {
    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) {
        self.init(isOn: isOn) {
            Text(titleKey)
        }
    }

    public init<S>(_ title: S, isOn: Binding<Bool>) where S: StringProtocol {
        self.init(isOn: isOn) {
            Text(title)
        }
    }
}

extension Toggle where Label == VUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) {
            Label(titleKey, systemImage: systemImage)
        }
    }

    public init<S>(_ title: S, systemImage: String, isOn: Binding<Bool>) where S: StringProtocol {
        self.init(isOn: isOn) {
            Label(title, systemImage: systemImage)
        }
    }
}

extension Toggle where Label == ToggleStyleConfiguration.Label {
    public init(_ configuration: ToggleStyleConfiguration) {
        self._toggleState = configuration._toggleState
        self.label = configuration.label
        self.appIntentAction = nil
    }
}

struct ResolvedToggleStyle: StyleableView {
    typealias Configuration = ToggleStyleConfiguration
    var configuration: ToggleStyleConfiguration

    var body: some View {
        Toggle(configuration)
            .platformItemToggleState(
                configuration._toggleState.wrappedValue
            )
    }

    typealias DefaultStyleModifier = ToggleStyleModifier<DefaultToggleStyle>
    static var defaultStyleModifier: ToggleStyleModifier<DefaultToggleStyle> {
        ToggleStyleModifier(style: DefaultToggleStyle())
    }
}
