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

private struct RootToolbarCommandContextFocusedValueKey: FocusedValueKey {
    typealias Value = RootToolbarCommandContext
}

enum RootToolbarCommand: Equatable, Sendable {
    case toggleVisibility
    case customize
}

struct RootToolbarCommandContext {
    var visibility: Visibility
    var canToggleVisibility: Bool
    var canCustomize: Bool
    var customizationIsPresented: Bool
}

extension FocusedValues {
    var toolbarVisibility: Visibility? {
        get { self[ToolbarVisibilityFocusedValueKey.self] }
        set { self[ToolbarVisibilityFocusedValueKey.self] = newValue }
    }

    var rootToolbarCommandContext: RootToolbarCommandContext? {
        get { self[RootToolbarCommandContextFocusedValueKey.self] }
        set {
            self[RootToolbarCommandContextFocusedValueKey.self] = newValue
        }
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
        var visibleItemIDs: Set<ToolbarStorage.ID>

        var customizationID: String? {
            storage.configuration?.customizationID
        }
    }

    final class CustomizationSession {
        let customizationID: String

        init(customizationID: String) {
            self.customizationID = customizationID
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
    private(set) var customizationSession: CustomizationSession?
    @ObservationIgnored private var signature: Signature?
    @ObservationIgnored
    private var customizedVisibleItems: [String: Set<ToolbarStorage.ID>] = [:]
    @ObservationIgnored
    private var knownCustomizationItems: [String: Set<ToolbarStorage.ID>] = [:]

    @discardableResult
    func update(storage: ToolbarStorage) -> Bool {
        let newSignature = Self.signature(for: storage)
        let isPresent = storage.configuration != nil
            && (!storage.items.isEmpty || storage.searchItem != nil)

        guard isPresent else {
            let changed = snapshot != nil
                || signature != nil
                || customizationSession != nil
            guard changed else { return false }
            snapshot = nil
            signature = nil
            customizationSession = nil
            return true
        }

        let changed = signature != newSignature || snapshot == nil
        guard changed else { return false }

        let visibility = snapshot?.visibility ?? .visible
        let visibleItemIDs = visibleItemIDs(for: storage)
        if customizationSession?.customizationID
            != storage.configuration?.customizationID {
            customizationSession = nil
        }
        snapshot = Snapshot(
            storage: storage,
            visibility: visibility,
            visibleItemIDs: visibleItemIDs
        )
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

    @discardableResult
    func perform(_ command: RootToolbarCommand) -> Bool {
        switch command {
        case .toggleVisibility:
            guard customizationSession == nil else { return false }
            return toggleVisibility()
        case .customize:
            return beginCustomization()
        }
    }

    @discardableResult
    func beginCustomization() -> Bool {
        guard var snapshot,
              let customizationID = snapshot.customizationID else {
            return false
        }
        if snapshot.visibility == .hidden {
            // The customization palette operates on the visible toolbar. Its
            // session also prevents the visibility command from hiding it.
            snapshot.visibility = .visible
            self.snapshot = snapshot
        }
        guard customizationSession?.customizationID != customizationID else {
            return false
        }
        customizationSession = CustomizationSession(
            customizationID: customizationID
        )
        return true
    }

    @discardableResult
    func endCustomization() -> Bool {
        guard customizationSession != nil else { return false }
        customizationSession = nil
        return true
    }

    @discardableResult
    func toggleCustomizationItem(_ id: ToolbarStorage.ID) -> Bool {
        guard let session = customizationSession,
              var snapshot,
              snapshot.customizationID == session.customizationID,
              snapshot.storage.items.contains(where: { $0.id == id }) else {
            return false
        }
        if snapshot.visibleItemIDs.contains(id) {
            snapshot.visibleItemIDs.remove(id)
        } else {
            snapshot.visibleItemIDs.insert(id)
        }
        customizedVisibleItems[session.customizationID] =
            snapshot.visibleItemIDs
        self.snapshot = snapshot
        return true
    }

    var commandContext: RootToolbarCommandContext? {
        snapshot.map { snapshot in
            RootToolbarCommandContext(
                visibility: snapshot.visibility,
                canToggleVisibility: customizationSession == nil,
                canCustomize: snapshot.customizationID != nil,
                customizationIsPresented: customizationSession != nil
            )
        }
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

    private func visibleItemIDs(
        for storage: ToolbarStorage
    ) -> Set<ToolbarStorage.ID> {
        let itemIDs = Set(storage.items.map(\.id))
        let defaultVisible = Set(
            storage.items.lazy.filter(\.showsByDefault).map(\.id)
        )
        guard let customizationID = storage.configuration?.customizationID else {
            return defaultVisible
        }

        let previousKnown = knownCustomizationItems[customizationID] ?? []
        var visible = customizedVisibleItems[customizationID]
            ?? defaultVisible
        // Preserve choices for known items, include newly declared default
        // items, and discard identities no longer produced by the toolbar.
        let newItems = itemIDs.subtracting(previousKnown)
        visible.formUnion(defaultVisible.intersection(newItems))
        visible.formIntersection(itemIDs)
        knownCustomizationItems[customizationID] = itemIDs
        customizedVisibleItems[customizationID] = visible
        return visible
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
            .focusedSceneValue(
                \.rootToolbarCommandContext,
                bridge.commandContext
            )
    }

    @ViewBuilder private var content: some View {
        if let snapshot = bridge.snapshot,
           snapshot.visibility != .hidden {
            ZStack(alignment: .top) {
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

                if let session = bridge.customizationSession {
                    RootToolbarCustomizationPalette(
                        bridge: bridge,
                        snapshot: snapshot,
                        session: session
                    )
                    .padding(.top, Self.toolbarHeight + 12)
                }
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
                snapshot.storage.items.filter {
                    snapshot.visibleItemIDs.contains($0.id)
                },
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

private struct RootToolbarCustomizationPalette: View {
    var bridge: RootToolbarBridge
    var snapshot: RootToolbarBridge.Snapshot
    var session: RootToolbarBridge.CustomizationSession

    var body: some View {
        // Renderer-owned toolbars keep customization in the same root host so
        // the session and item choices survive replaceable toolbar snapshots.
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customize Toolbar")
                        .font(.system(.headline))
                    Text(session.customizationID)
                        .font(.system(.caption))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                Button("Done") {
                    bridge.endCustomization()
                }
            }

            Divider()

            ForEach(snapshot.storage.items, id: \.id) { item in
                let isVisible = snapshot.visibleItemIDs.contains(item.id)
                HStack(spacing: 12) {
                    item.view
                        .disabled(true)
                    Spacer(minLength: 0)
                    Button(isVisible ? "Remove" : "Add") {
                        bridge.toggleCustomizationItem(item.id)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 360)
        .background(Color(white: 0.97))
        .border(Color(white: 0.62, opacity: 0.55))
    }
}
