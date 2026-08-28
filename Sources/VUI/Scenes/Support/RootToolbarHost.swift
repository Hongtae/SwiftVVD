//
//  File: RootToolbarHost.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

private struct ToolbarVisibilityFocusedValueKey: FocusedValueKey {
    typealias Value = Visibility
}

extension FocusedValues {
    var toolbarVisibility: Visibility? {
        get { self[ToolbarVisibilityFocusedValueKey.self] }
        set { self[ToolbarVisibilityFocusedValueKey.self] = newValue }
    }
}

// Receives the reduced root-toolbar value while the owning ViewGraph is
// evaluating. Presentation children do not install this feature, so toolbar
// ownership remains at the static Scene root.
protocol RootToolbarStorageHost: AnyObject {
    func rootToolbarStorageDidChange(_ storage: ToolbarStorage)
}

struct RootToolbarViewGraph: ViewGraphFeature {
    func modifyViewInputs(inputs: inout _ViewInputs, graph: ViewGraph) {
        inputs.preferences.add(ToolbarKey.self)
    }

    func modifyViewOutputs(
        outputs: inout _ViewOutputs,
        inputs: _ViewInputs,
        graph: ViewGraph
    ) {
        let nodes = outputs.preferences.values(for: ToolbarKey.self)
        let storage: Attribute<ToolbarStorage> = graph.data.graph.makeRule {
            var combined = ToolbarKey.defaultValue
            for node in nodes {
                let next = Attribute<ToolbarStorage>(node).value
                ToolbarKey.reduce(value: &combined) { next }
            }
            return combined
        }
        graph.data.graph.makeSideEffectRule { [weak graph] in
            guard let host = graph?.rendererHost as? RootToolbarStorageHost else {
                return
            }
            host.rootToolbarStorageDidChange(storage.value)
        }
    }
}

// Keeps root-toolbar semantic state alive independently from any particular
// rendered toolbar value. WindowController owns one bridge for its static
// Scene root and replaces only the snapshot installed in the root view.
@Observable
final class RootToolbarBridge {
    struct Snapshot {
        var storage: ToolbarStorage
        var visibility: Visibility

        var customizationID: String? {
            storage.configuration?.customizationID
        }
    }

    private struct ItemSignature: Equatable {
        var id: ToolbarStorage.ID
        var placement: ToolbarItemPlacement.Role
        var showsByDefault: Bool
        var viewStorage: ObjectIdentifier
        var generator: AGWeakAttribute?
        var viewType: ObjectIdentifier?
    }

    private struct Signature: Equatable {
        var customizationID: String?
        var items: [ItemSignature]
        var hasSearchItem: Bool
    }

    private(set) var snapshot: Snapshot?
    @ObservationIgnored private var signature: Signature?

    @discardableResult
    func update(storage: ToolbarStorage) -> Bool {
        let newSignature = Self.signature(for: storage)
        let isPresent = storage.configuration != nil
            && (!storage.items.isEmpty || storage.searchItem != nil)

        guard isPresent else {
            let changed = snapshot != nil || signature != nil
            snapshot = nil
            signature = nil
            return changed
        }

        let changed = signature != newSignature || snapshot == nil
        guard changed else { return false }

        let visibility = snapshot?.visibility ?? .visible
        snapshot = Snapshot(storage: storage, visibility: visibility)
        signature = newSignature
        return true
    }

    @discardableResult
    func toggleVisibility() -> Bool {
        guard var snapshot else { return false }
        switch snapshot.visibility {
        case .hidden:
            snapshot.visibility = .visible
        case .automatic, .visible:
            snapshot.visibility = .hidden
        }
        self.snapshot = snapshot
        return true
    }

    var allocatedHeight: CGFloat {
        guard snapshot?.visibility != .hidden else { return 0 }
        return snapshot == nil ? 0 : RootToolbarHost.toolbarHeight
    }

    private static func signature(for storage: ToolbarStorage) -> Signature {
        Signature(
            customizationID: storage.configuration?.customizationID,
            items: storage.items.map { item in
                ItemSignature(
                    id: item.id,
                    placement: item.placement,
                    showsByDefault: item.showsByDefault,
                    viewStorage: ObjectIdentifier(item.view.storage),
                    generator: item.generator?.view,
                    viewType: item.generator.map {
                        ObjectIdentifier($0.viewType)
                    }
                )
            },
            hasSearchItem: storage.searchItem != nil
        )
    }
}

struct RootToolbarHost: View {
    // Renderer-owned toolbar chrome is allocated outside the Scene's logical
    // content size. Keep the metric centralized for a later style/theme hook.
    static let toolbarHeight: CGFloat = 40

    var sceneContent: AnyView
    var bridge: RootToolbarBridge

    var body: some View {
        content
            .focusedSceneValue(\.toolbarVisibility, bridge.snapshot?.visibility)
    }

    @ViewBuilder private var content: some View {
        if let snapshot = bridge.snapshot,
           snapshot.visibility != .hidden {
            VStack(spacing: 0) {
                RootToolbarBar(snapshot: snapshot)
                sceneContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        } else {
            sceneContent
        }
    }

    static func hostRootView(
        sceneContent: AnyView,
        bridge: RootToolbarBridge
    ) -> AnyView {
        AnyView(
            RootToolbarHost(
                sceneContent: sceneContent,
                bridge: bridge
            )
        )
    }
}

private struct RootToolbarBar: View {
    var snapshot: RootToolbarBridge.Snapshot

    var body: some View {
        HStack(spacing: 8) {
            ForEach(
                snapshot.storage.items.filter(\.showsByDefault),
                id: \.id
            ) { item in
                // Root chrome outlives the preference-producing toolbar
                // subtree. Rebuild the erased item value in this host instead
                // of retaining the temporary weak generator used by sheets.
                item.view
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: RootToolbarHost.toolbarHeight)
        .background(Color(white: 0.94))
    }
}
