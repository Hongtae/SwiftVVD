//
//  File: ToggleStyle.swift
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
                        .fill(configuration.isOn ? Color.blue : Color.primaryFill)
                        .frame(width: 38, height: 22)
                    ZStack {
                        Circle()
                            .fill(BackgroundStyle())
                        Circle()
                            .strokeBorder(Color.secondaryFill, lineWidth: 1)
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
