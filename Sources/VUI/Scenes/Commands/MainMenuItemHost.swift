//
//  File: MainMenuItemHost.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol MainMenuItemHostDelegate: AnyObject {
    func menuHostDidChangeMenuItems(_ host: MainMenuItemHost)
}

// Applies menu-only graph inputs after the generic platform-item feature has
// installed the requested representations.
private struct MainMenuItemViewGraph: ViewGraphFeature {
    func modifyViewInputs(inputs: inout _ViewInputs, graph: ViewGraph) {
        inputs.addPlatformItemListKey(flags: AllPlatformItemListFlags.self)
        inputs.base.options.insert(.animationsDisabled)

        let context = inputs.base.customInputs.value(
            forKey: StyleContextInput.self
        )
        inputs.base.customInputs.setValue(
            context.pushing(MenuStyleContext.self),
            forKey: StyleContextInput.self
        )
    }
}

// Owns the presenter-neutral graph that turns one resolved top-level command
// menu into semantic platform items. Platform presenters retain this host and
// decide when an invalid generation should be materialized.
final class MainMenuItemHost: ViewRendererHost, ViewGraphRootValueUpdater {
    private struct RootView: View {
        var itemContent: MainMenuItem.Content

        var body: some View {
            itemContent.transformPlatformItemList(
                AllPlatformItemListFlags.self
            ) { list in
                Self.prepareForMainMenu(&list)
            }
        }

        private static func prepareForMainMenu(
            _ list: inout PlatformItemList
        ) {
            list.modify { item in
                item.scaleDownMenuImage = true
                if var children = item.children {
                    prepareForMainMenu(&children)
                    item.children = children
                }
            }
        }
    }

    weak var delegate: (any MainMenuItemHostDelegate)?

    private var item: MainMenuItem
    private var rootEnvironment: EnvironmentValues
    private var rootFocusedValues: FocusedValues
    private var storage: ViewGraph!

    let sceneResources = SceneResources()
    var currentTimestamp = Time(seconds: 0)
    var valuesNeedingUpdate: ViewGraphRootValues = []
    var renderingPhase = ViewRenderingPhase()
    var externalUpdateCount = 0

    init(
        item: MainMenuItem,
        environment: EnvironmentValues,
        focusedValues: FocusedValues = FocusedValues()
    ) {
        self.item = item
        self.rootEnvironment = environment
        self.rootFocusedValues = focusedValues

        let graph = ViewGraph(
            replaceableContent: RootView(itemContent: .item(item)),
            rendererHost: self,
            initialEnvironment: environment,
            requestedOutputs: [.platformItemList, .focus],
            features: [
                PlatformItemListViewGraph(),
                MainMenuItemViewGraph(),
            ]
        )
        storage = graph
        graph.updateDelegate = self
        graph.viewDelegate = self
        graph.graphDelegate = self
        if focusedValues != FocusedValues() {
            graph.valuesNeedingUpdate.insert(.focusedValues)
        }
    }

    var viewGraph: ViewGraph {
        storage
    }

    var responderNode: ResponderNode? {
        nil
    }

    func update(
        item: MainMenuItem,
        environment: EnvironmentValues,
        focusedValues: FocusedValues = FocusedValues()
    ) {
        self.item = item
        rootEnvironment = environment
        var dirty: ViewGraphRootValues = [.rootView, .environment]
        if rootFocusedValues != focusedValues {
            rootFocusedValues = focusedValues
            dirty.insert(.focusedValues)
        }

        // ViewGraphHost consumes the graph's dirty mask when outputs update.
        // Keep replacement deferred by publishing both values to that mask;
        // the delegate callbacks below perform the actual input writes.
        storage.valuesNeedingUpdate.formUnion(dirty)
        storage.setNeedsUpdate(
            mayDeferUpdate: true,
            values: dirty
        )
    }

    func updateFocusedValues(_ focusedValues: FocusedValues) {
        guard rootFocusedValues != focusedValues else { return }
        rootFocusedValues = focusedValues
        let dirty = ViewGraphRootValues.focusedValues
        storage.valuesNeedingUpdate.insert(dirty)
        storage.setNeedsUpdate(
            mayDeferUpdate: true,
            values: dirty
        )
    }

    func menuItems() -> PlatformItemList {
        storage.instantiateIfNeeded()
        storage.updateOutputs(at: currentTimestamp)
        return storage.data.withCurrent {
            storage.platformItemList() ?? PlatformItemList()
        }
    }

    func requestUpdate(after: Double) {
        delegate?.menuHostDidChangeMenuItems(self)
    }

    func `as`<T>(_ type: T.Type) -> T? {
        let requestedType = ObjectIdentifier(type)
        guard requestedType == ObjectIdentifier((any ViewGraphOwner).self)
                || requestedType == ObjectIdentifier(
                    (any ViewGraphDelegate).self
                ) else {
            return nil
        }
        return self as? T
    }

    func updateRootView() {
        storage.rootAnyViewContentInput?.setValue(
            AnyView(RootView(itemContent: .item(item)))
        )
    }

    func updateEnvironment() {
        storage.envAttr?.setValue(rootEnvironment)
    }

    func updateSize() {}
    func updateSafeArea() {}
    func updateContainerSize() {}
    func updateFocusedValues() {
        storage.setFocusedValues(rootFocusedValues)
    }
}
