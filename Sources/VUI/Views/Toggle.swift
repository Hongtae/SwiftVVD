//
//  File: Toggle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public enum ToggleState: UInt, Sendable, Codable, CaseIterable, Hashable,
    StronglyHashable, CustomDebugStringConvertible {
    case on
    case off
    case mixed

    init(_ isOn: Bool) {
        self = isOn ? .on : .off
    }

    init(isOn: Bool) {
        self.init(isOn)
    }

    mutating func toggle() {
        self = self == .on ? .off : .on
    }

    public var debugDescription: String {
        switch self {
        case .on: "on"
        case .off: "off"
        case .mixed: "mixed"
        }
    }

    var isOn: Bool {
        self == .on
    }
}

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

public struct ToggleStyleConfiguration {
    public struct Label: View, ViewAlias {
        public typealias Body = Never
    }

    enum Effect: Sendable {
        case binding
    }

    public let label: ToggleStyleConfiguration.Label
    @Binding public var isOn: Bool
    var _toggleState: Binding<ToggleState>
    public var isMixed: Bool
    var effect: Effect

    init(label: ToggleStyleConfiguration.Label = ToggleStyleConfiguration.Label(),
         isOn: Binding<Bool>,
         toggleState: Binding<ToggleState>,
         isMixed: Bool = false,
         effect: Effect = .binding) {
        self.label = label
        self._isOn = isOn
        self._toggleState = toggleState
        self.isMixed = isMixed
        self.effect = effect
    }
}

extension ToggleStyleConfiguration.Label: PrimitiveView {}

public protocol ToggleStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ToggleStyleConfiguration
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

public struct DefaultToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        SwitchToggleStyle().makeBody(configuration: configuration)
    }
}

public struct SwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        SwitchToggleStyleBody(configuration: configuration)
    }
}

private struct SwitchToggleStyleBody: View {
    let configuration: ToggleStyleConfiguration

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Color.blue : Color(white: 0.75))
                        .frame(width: 38, height: 22)
                    ZStack {
                        Circle()
                            .fill(Color.white)
                        Circle()
                            .strokeBorder(Color(white: 0.84), lineWidth: 1)
                    }
                    .frame(width: 18, height: 18)
                    .padding(2)
                }
                .frame(width: 38, height: 22)
                .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle() {
        let binding = configuration.$isOn
        binding.wrappedValue.toggle()
    }
}

public struct ButtonToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            let binding = configuration.$isOn
            binding.wrappedValue.toggle()
        }) {
            configuration.label
        }
    }
}

struct CheckmarkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            let binding = configuration.$isOn
            binding.wrappedValue.toggle()
        }) {
            configuration.label
        }
    }
}

extension ToggleStyle where Self == DefaultToggleStyle {
    public static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}

extension ToggleStyle where Self == ButtonToggleStyle {
    public static var button: ButtonToggleStyle { ButtonToggleStyle() }
}

extension View {
    func platformItemToggleState(_ state: ToggleState) -> some View {
        transformPlatformItemList(LayoutPlatformItemListFlags.self) {
            itemList in
            itemList.modify { item in
                item.toggleState = state
            }
        }
    }

    public func toggleStyle<S>(_ style: S) -> some View where S: ToggleStyle {
        modifier(ToggleStyleModifier(style: style))
    }
}
