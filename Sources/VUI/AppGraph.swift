//
//  File: AppGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// AppGraph — owns the top-level AttributeGraph for the app's scene tree.
// Calls App.body._makeScene() with _SceneInputs (SceneList.Key registered),
// then exposes the resulting SceneList.Key AG node for AppWindowsController to consume.
// AppWindowsController owns the window lifecycle.
class AppGraph<A: App>: @unchecked Sendable {

    let graph: AttributeGraph

    // The SceneList.Key AG node produced by App.body._makeScene().
    // Read by AppWindowsController.syncWindowControllers (inside graph context)
    // to determine which windows to open/close.
    let sceneListAttr: Attribute<[SceneList.Item]>?

    // The _RuntimeWindowConfigKey AG node produced by scene modifiers
    // (.updateFrameRate, .drawDebugInfo). Re-evaluated on every sync and
    // applied to all live WindowControllers.
    let runtimeWindowConfigAttr: Attribute<_RuntimeWindowConfig>?

    init(app: A) {
        let g = AttributeGraph()
        let time = Time(seconds: 0)
        var sceneList: Attribute<[SceneList.Item]>? = nil
        var runtimeConfig: Attribute<_RuntimeWindowConfig>? = nil

        AttributeGraph.$current.withValue(g) {
            // Stub AG input nodes for _GraphInputs fields.
            let timeAttr        = g.makeInput(value: time)
            let phaseAttr       = g.makeInput(value: Phase(value: 1))
            let transactionAttr = g.makeInput(value: Transaction())
            let envAttr         = g.makeInput(value: EnvironmentValues())

            let graphInputs = _GraphInputs(
                customInputs: PropertyList(),
                time: timeAttr,
                cachedEnvironment: MutableBox(CachedEnvironment(environment: envAttr)),
                phase: phaseAttr,
                transaction: transactionAttr,
                changedDebugProperties: 0,
                options: 0,
                mergedInputs: []
            )

            // Register preference keys so that scenes output them in _SceneOutputs.
            var prefKeys = PreferenceKeys()
            prefKeys.insert(SceneList.Key.self)
            prefKeys.insert(_RuntimeWindowConfig.Key.self)
            let hostKeysAttr = g.makeInput(value: prefKeys)
            let prefsInputs  = PreferencesInputs(keys: prefKeys, hostKeys: hostKeysAttr)

            let sceneInputs = _SceneInputs(base: graphInputs, preferences: prefsInputs)

            // Wire the root scene graph.
            let bodyAttr  = g.makeInput(value: app.body)
            let sceneGraph = _GraphValue<A.Body>(_attribute: bodyAttr)
            let outputs   = A.Body._makeScene(scene: sceneGraph, inputs: sceneInputs)

            // Locate preference nodes in the outputs.
            // SceneList.Key: TransformSceneListModifier uses replace semantics,
            // so there is always exactly one entry — take it directly.
            sceneList = outputs.preferences.values(for: SceneList.Key.self)
                .last.map { Attribute($0) }

            // _RuntimeWindowConfigKey: multiple modifiers may each append an entry
            // (e.g. .updateFrameRate + .drawDebugInfo), so reduce all entries into
            // one AG node using the stored _makeReduceRule.
            runtimeConfig = outputs.preferences.reducedValue(for: _RuntimeWindowConfig.Key.self, in: g)
        }

        self.graph = g
        self.sceneListAttr = sceneList
        self.runtimeWindowConfigAttr = runtimeConfig
    }
}
