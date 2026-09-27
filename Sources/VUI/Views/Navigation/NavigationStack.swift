//
//  File: NavigationStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

struct AnyNavigationPath {
    var base: NavigationPath

    init(_ base: NavigationPath = NavigationPath()) {
        self.base = base
    }

    var count: Int { base.count }
    var isEmpty: Bool { base.isEmpty }
    var elements: [NavigationPathElement] { base.navigationElements }

    mutating func append(_ item: NavigationPathItem) {
        base.append(item)
    }

    mutating func removeLast(_ count: Int = 1) {
        base.removeLast(count)
    }

    static func projecting(
        _ binding: Binding<NavigationPath>
    ) -> Binding<AnyNavigationPath> {
        Binding<AnyNavigationPath>(
            get: { AnyNavigationPath(binding.wrappedValue) },
            set: { binding.wrappedValue = $0.base }
        )
        .transaction(binding.transaction)
    }

    static func projecting<Data>(
        _ binding: Binding<Data>
    ) -> Binding<AnyNavigationPath>
    where
        Data: MutableCollection & RandomAccessCollection
            & RangeReplaceableCollection,
        Data.Element: Hashable
    {
        Binding<AnyNavigationPath>(
            get: {
                AnyNavigationPath(NavigationPath(binding.wrappedValue))
            },
            set: { path in
                let elements = path.elements
                var replacement = Data()
                replacement.reserveCapacity(elements.count)
                for element in elements {
                    let candidate: Data.Element?
                    if Data.Element.self == AnyHashable.self {
                        candidate = element.value as? Data.Element
                    } else {
                        candidate = element.value?.base as? Data.Element
                    }
                    guard let candidate else { return }
                    replacement.append(candidate)
                }
                binding.wrappedValue = replacement
            }
        )
        .transaction(binding.transaction)
    }
}

struct NavigationRequest {
}

final class NavigationSelectionHost {
}

final class NavigationSeedHost {
}

final class NavigationHostingControllerCache {
}

struct NavigationPresentationState {
    var id: AnyHashable
    var onDismiss: () -> Void
}

@Observable
final class NavigationStateHost {
    var navigationState: NavigationState?
    var pendingRequests: [NavigationRequest]?
    var selectionHost: NavigationSelectionHost
    var seedHost: NavigationSeedHost
    var controllerCache: NavigationHostingControllerCache?
    var initializedNavState: Bool

    init() {
        navigationState = NavigationState()
        pendingRequests = nil
        selectionHost = NavigationSelectionHost()
        seedHost = NavigationSeedHost()
        controllerCache = nil
        initializedNavState = false
    }

    var presentedDestination: NavigationPresentationState? {
        navigationState?.presentations.last
    }

    var hasBackAction: Bool {
        guard let navigationState else { return false }
        return navigationState.pathDepth > 0
            || !navigationState.presentations.isEmpty
    }

    func setPathDepth(_ depth: Int) {
        var state = navigationState ?? NavigationState()
        guard state.pathDepth != depth else { return }
        state.pathDepth = depth
        navigationState = state
        initializedNavState = true
    }

    func installPresentation(_ presentation: NavigationPresentationState) {
        var state = navigationState ?? NavigationState()
        if let index = state.presentations.firstIndex(where: {
            $0.id == presentation.id
        }) {
            state.presentations[index] = presentation
        } else {
            state.presentations.append(presentation)
        }
        navigationState = state
        initializedNavState = true
    }

    func removePresentation(id: AnyHashable) {
        guard var state = navigationState else { return }
        state.presentations.removeAll { $0.id == id }
        navigationState = state
    }
}

struct NavigationStackContext {
    var key: Namespace.ID
    var append: (NavigationPathItem) -> Void
}

private struct NavigationStackContextKey: EnvironmentKey {
    static var defaultValue: NavigationStackContext? { nil }
}

extension EnvironmentValues {
    var navigationStackContext: NavigationStackContext? {
        get { self[NavigationStackContextKey.self] }
        set { self[NavigationStackContextKey.self] = newValue }
    }
}

public struct NavigationStack<Data, Root>: View where Root: View {
    var root: Root
    @Namespace private var namespace
    @StateOrBinding private var path: AnyNavigationPath
    @State private var localStateHost = NavigationStateHost()

    public init(
        @ViewBuilder root: () -> Root
    ) where Data == NavigationPath {
        self.root = root()
        _path = StateOrBinding(wrappedValue: AnyNavigationPath())
    }

    public init(
        path: Binding<NavigationPath>,
        @ViewBuilder root: () -> Root
    ) where Data == NavigationPath {
        self.root = root()
        _path = StateOrBinding(AnyNavigationPath.projecting(path))
    }

    public init(
        path: Binding<Data>,
        @ViewBuilder root: () -> Root
    ) where
        Data: MutableCollection & RandomAccessCollection
            & RangeReplaceableCollection,
        Data.Element: Hashable
    {
        self.root = root()
        _path = StateOrBinding(AnyNavigationPath.projecting(path))
    }

    public var body: some View {
        NavigationStackReader(
            id: namespace,
            path: $path,
            root: root,
            hasImplicitState: {
                if case .state = _path { true } else { false }
            }(),
            stateHost: localStateHost
        )
        .modifier(NavigationCommonModifier())
    }
}

@available(*, unavailable)
extension NavigationStack: Sendable {
}

struct NavigationStackReader<Root>: View where Root: View {
    var id: Namespace.ID
    var path: Binding<AnyNavigationPath>
    var root: Root
    var hasImplicitState: Bool
    var stateHost: NavigationStateHost

    var body: some View {
        let context = NavigationStackContext(
            key: id,
            append: { item in
                var path = path.wrappedValue
                path.append(item)
                self.path.wrappedValue = path
            }
        )

        root
            .modifier(
                ViewInputFlagModifier(
                    flag: InvertedViewInputPredicate<
                        DisableNavigationDestination
                    >()
                )
            )
            .overlayPreferenceValue(
                NavigationDestinationsKey.self,
                alignment: .center
            ) { destinations in
                NavigationStackOverlay(
                    path: path,
                    stateHost: stateHost,
                    destinations: destinations
                )
            }
            .environment(\.navigationStackContext, context)
            .toolbar {
                ToolbarItem(
                    identifier: "com.vui.navigationStack.back",
                    placement: .navigation,
                    content: NavigationStackBackButton(
                        path: path,
                        stateHost: stateHost
                    ),
                    showsByDefault: true,
                    isEmpty: false,
                    defaultItemKind: nil
                )
            }
    }
}

private enum NavigationStackLayerID: Hashable {
    case path(Int, AnyHashable)
    case presentation(AnyHashable)
}

private struct NavigationStackLayer: Identifiable {
    var id: NavigationStackLayerID
    var content: AnyView
}

private struct NavigationStackOverlay: View {
    var path: Binding<AnyNavigationPath>
    var stateHost: NavigationStateHost
    var destinations: ResolvedNavigationDestinations

    private var layers: [NavigationStackLayer] {
        var result: [NavigationStackLayer] = []
        for (index, element) in path.wrappedValue.elements.enumerated() {
            guard let content = destinations.resolve(element) else { break }
            result.append(NavigationStackLayer(
                id: .path(index, element.id),
                content: AnyView(
                    content
                        .onAppear {
                            stateHost.setPathDepth(index + 1)
                        }
                        .onDisappear {
                            stateHost.setPathDepth(path.wrappedValue.count)
                        }
                )
            ))
        }
        result.append(contentsOf: destinations.presentations.map {
            let presentation = NavigationPresentationState(
                id: $0.id,
                onDismiss: $0.onDismiss
            )
            return NavigationStackLayer(
                id: .presentation($0.id),
                content: AnyView(
                    $0.content
                        .onAppear {
                            stateHost.installPresentation(presentation)
                        }
                        .onDisappear {
                            stateHost.removePresentation(id: presentation.id)
                        }
                )
            )
        })
        return result
    }

    var body: some View {
        let layers = layers
        ZStack {
            ForEach(layers) { layer in
                layer.content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BackgroundStyle())
                    .opacity(layer.id == layers.last?.id ? 1 : 0)
                    .disabled(layer.id != layers.last?.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NavigationStackBackButton: View {
    var path: Binding<AnyNavigationPath>
    var stateHost: NavigationStateHost

    var body: some View {
        let hasBackAction = stateHost.hasBackAction
        Button("Back") {
            if let presentation = stateHost.presentedDestination {
                presentation.onDismiss()
            } else if !path.wrappedValue.isEmpty {
                var value = path.wrappedValue
                value.removeLast()
                path.wrappedValue = value
            }
        }
        .opacity(hasBackAction ? 1 : 0)
        .disabled(!hasBackAction)
    }
}

struct NavigationStackRootDecoratingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

struct NavigationCommonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
