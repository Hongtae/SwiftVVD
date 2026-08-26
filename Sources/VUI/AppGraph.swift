//
//  File: AppGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// AppGraph — owns the top-level _AGGraph for the app's scene tree.
// Calls App.body._makeScene() with _SceneInputs (SceneList.Key registered),
// then exposes the resulting SceneList.Key AG node for AppWindowsController to consume.
// AppWindowsController owns the window lifecycle.
class AppGraph<A: App>: @unchecked Sendable {

    let graph: _AGGraph

    // Retains the ownership root for the scene graph and any dynamically
    // selected command branches created beneath it.
    let rootSubgraph: AGSubgraphRef

    // The SceneList.Key AG node produced by App.body._makeScene().
    // Read by AppWindowsController.syncWindowControllers (inside graph context)
    // to determine which windows to open/close.
    let sceneListAttr: Attribute<[SceneList.Item]>?

    // The ordered command operations produced by scene command modifiers.
    // Platform hosts may resolve this node into their native menu model.
    let commandsListAttr: Attribute<CommandsList>?

    // The app-root environment remains separate from environments applied by
    // individual scenes. Command-menu hosts materialize their root views from
    // this source while command producers retain their own scene inputs.
    let rootEnvironmentAttr: Attribute<EnvironmentValues>

    // The window-configuration override AG node produced by scene modifiers
    // (.updateFrameRate, .drawDebugInfo). Re-evaluated on every sync and
    // applied to all live WindowControllers.
    let windowConfigurationOverrideAttr: Attribute<WindowConfiguration.Override>?

    init(app: A) {
        let graph = _AGGraph()
        let time = Time(seconds: 0)
        var sceneList: Attribute<[SceneList.Item]>? = nil
        var commandsList: Attribute<CommandsList>? = nil
        var configurationOverride: Attribute<WindowConfiguration.Override>? = nil
        var rootEnvironment: Attribute<EnvironmentValues>!
        var rootSubgraph: AGSubgraphRef!

        _AGGraph.withCurrent(graph) {
            rootSubgraph = AGSubgraph()
            AGSubgraph.withCurrent(rootSubgraph) {
                // Root input nodes seed the graph inputs used while constructing
                // the app's scene tree.
                let timeAttr        = graph.makeInput(value: time)
                let phaseAttr       = graph.makeInput(value: _GraphInputs.Phase())
                let transactionAttr = graph.makeInput(value: Transaction())
                let envAttr         = graph.makeInput(value: EnvironmentValues.tracking())
                rootEnvironment = envAttr

                let graphInputs = _GraphInputs(
                    time: timeAttr,
                    phase: phaseAttr,
                    environment: envAttr,
                    transaction: transactionAttr
                )

                // Register preference keys so that scenes output them in _SceneOutputs.
                var prefKeys = PreferenceKeys()
                prefKeys.add(SceneList.Key.self)
                prefKeys.add(CommandsList.Key.self)
                prefKeys.add(WindowConfiguration.Override.Key.self)
                let hostKeysAttr = graph.makeInput(value: prefKeys)
                let prefsInputs  = PreferencesInputs(keys: prefKeys, hostKeys: hostKeysAttr)

                let sceneInputs = _SceneInputs(base: graphInputs, preferences: prefsInputs)

                // Wire the root scene graph.
                let bodyAttr  = graph.makeInput(value: app.body)
                let sceneGraph = _GraphValue<A.Body>(_attribute: bodyAttr)
                let outputs   = A.Body._makeScene(scene: sceneGraph, inputs: sceneInputs)

                // Locate preference nodes in the outputs.
                // SceneList.Key: TransformSceneListModifier uses replace semantics,
                // so there is always exactly one entry — take it directly.
                sceneList = outputs.preferences.values(for: SceneList.Key.self)
                    .last.map { Attribute($0) }
                commandsList = outputs.preferences.value(for: CommandsList.Key.self)
                    .map { Attribute($0) }

                // Multiple modifiers may each append a window-configuration override
                // (e.g. .updateFrameRate + .drawDebugInfo), so reduce all entries into
                // one AG node using the stored _makeReduceRule.
                configurationOverride = outputs.preferences.reducedValue(
                    for: WindowConfiguration.Override.Key.self,
                    in: graph
                )
            }
        }

        self.graph = graph
        self.rootSubgraph = rootSubgraph
        self.sceneListAttr = sceneList
        self.commandsListAttr = commandsList
        self.rootEnvironmentAttr = rootEnvironment
        self.windowConfigurationOverrideAttr = configurationOverride
    }
}
