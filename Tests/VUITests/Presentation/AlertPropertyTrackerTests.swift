import XCTest
@testable import VUI

final class AlertPropertyTrackerTests: XCTestCase {
    func testMakeAlertStorageTracksPlatformWindowEnvironment() {
        let graph = _AGGraph()
        let presentation = BoolBox(true)

        _AGGraph.withCurrent(graph) {
            var environment = EnvironmentValues.tracking()
            environment.modalSessionUsingPlatformWindow = false
            let environmentAttr = graph.makeInput(value: environment)
            let modifierAttr = graph.makeInput(
                value: alertModifier(isPresented: binding(to: presentation))
            )
            let itemListAttr = graph.makeInput(value: PlatformItemList())
            let phaseAttr = graph.makeInput(value: Phase())
            let tracker = _PropertyListTracker()
            let storageAttr: Attribute<MakeAlertStorage<EmptyView, EmptyView>.Value> =
                graph.makeStatefulRule(
                    MakeAlertStorage(
                        environment: environmentAttr,
                        modifier: modifierAttr,
                        actionsItemList: itemListAttr.asWeak(),
                        messageItemList: itemListAttr.asWeak(),
                        phase: phaseAttr,
                        identityTracker: ViewIdentity.Tracker(),
                        propertyTracker: tracker,
                        lastTitle: nil,
                        lastColorScheme: nil,
                        lastIcon: nil,
                        lastTintColor: nil,
                        lastSeverity: .standard,
                        lastSuppressionConfiguration: nil,
                        lastAccessibilityTitle: nil,
                        lastDialogPreventsTermination: nil
                    )
                )

            var preference = alertPreference(from: storageAttr)
            XCTAssertEqual(preference?.usesPlatformWindow, false)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.modalSessionUsingPlatformWindow = true
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)

            preference = alertPreference(from: storageAttr)
            XCTAssertEqual(preference?.usesPlatformWindow, true)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))
        }
    }

    func testMakeAlertStorageUsesTrackedDialogSeverityEnvironment() {
        let graph = _AGGraph()
        let presentation = BoolBox(true)

        _AGGraph.withCurrent(graph) {
            var environment = EnvironmentValues.tracking()
            let environmentAttr = graph.makeInput(value: environment)
            let modifierAttr = graph.makeInput(
                value: alertModifier(isPresented: binding(to: presentation))
            )
            let itemListAttr = graph.makeInput(value: PlatformItemList())
            let phaseAttr = graph.makeInput(value: Phase())
            let tracker = _PropertyListTracker()
            let storageAttr = alertStorageAttribute(
                graph: graph,
                environment: environmentAttr,
                modifier: modifierAttr,
                itemList: itemListAttr,
                phase: phaseAttr,
                tracker: tracker
            )

            var preference = alertPreference(from: storageAttr)
            XCTAssertEqual(preference?.severity, .automatic)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.dialogSeverity = .critical
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)

            preference = alertPreference(from: storageAttr)
            XCTAssertEqual(preference?.severity, .critical)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))
        }
    }

    func testMakeAlertStorageTracksDialogPreventsTerminationEnvironment() {
        let graph = _AGGraph()
        let presentation = BoolBox(true)

        _AGGraph.withCurrent(graph) {
            var environment = EnvironmentValues.tracking()
            let environmentAttr = graph.makeInput(value: environment)
            let modifierAttr = graph.makeInput(
                value: alertModifier(isPresented: binding(to: presentation))
            )
            let itemListAttr = graph.makeInput(value: PlatformItemList())
            let phaseAttr = graph.makeInput(value: Phase())
            let tracker = _PropertyListTracker()
            let storageAttr = alertStorageAttribute(
                graph: graph,
                environment: environmentAttr,
                modifier: modifierAttr,
                itemList: itemListAttr,
                phase: phaseAttr,
                tracker: tracker
            )

            XCTAssertNotNil(alertPreference(from: storageAttr))
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.dialogPreventsAppTermination = true
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)

            XCTAssertNotNil(alertPreference(from: storageAttr))
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))
        }
    }

    func testMakeAlertStorageTracksBridgeCacheEnvironmentFields() {
        let graph = _AGGraph()
        let presentation = BoolBox(true)
        let icon = Image("tracked-dialog-icon")

        _AGGraph.withCurrent(graph) {
            var environment = EnvironmentValues.tracking()
            environment.explicitPreferredColorScheme = .dark
            let environmentAttr = graph.makeInput(value: environment)
            let modifierAttr = graph.makeInput(
                value: alertModifier(isPresented: binding(to: presentation))
            )
            let itemListAttr = graph.makeInput(value: PlatformItemList())
            let phaseAttr = graph.makeInput(value: Phase())
            let tracker = _PropertyListTracker()
            let storageAttr = alertStorageAttribute(
                graph: graph,
                environment: environmentAttr,
                modifier: modifierAttr,
                itemList: itemListAttr,
                phase: phaseAttr,
                tracker: tracker
            )

            var storage = alertStorage(from: storageAttr)
            XCTAssertEqual(storage?.title, "Tracked Alert")
            XCTAssertEqual(storage?.colorScheme, .dark)
            XCTAssertNil(storage?.icon)
            XCTAssertNil(storage?.tintColor)
            XCTAssertNil(storage?.suppressionConfiguration)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.dialogColorScheme = .light
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)
            storage = alertStorage(from: storageAttr)
            XCTAssertEqual(storage?.colorScheme, .light)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.dialogIcon = icon
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)
            storage = alertStorage(from: storageAttr)
            XCTAssertEqual(storage?.icon, icon)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.dialogTintColor = .red
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)
            storage = alertStorage(from: storageAttr)
            XCTAssertEqual(storage?.tintColor, Color.red.resolve(in: environment))
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.dialogSuppression = DialogSuppressionConfiguration()
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)
            storage = alertStorage(from: storageAttr)
            XCTAssertNotNil(storage?.suppressionConfiguration)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))
        }
    }

    func testMakeAlertStorageTracksAccessibilityEnabledForAccessibilityTitle() {
        let graph = _AGGraph()
        let presentation = BoolBox(true)

        _AGGraph.withCurrent(graph) {
            var environment = EnvironmentValues.tracking()
            environment.accessibilityEnabled = false
            let environmentAttr = graph.makeInput(value: environment)
            let modifierAttr = graph.makeInput(
                value: alertModifier(isPresented: binding(to: presentation))
            )
            let itemListAttr = graph.makeInput(value: PlatformItemList())
            let phaseAttr = graph.makeInput(value: Phase())
            let tracker = _PropertyListTracker()
            let storageAttr = alertStorageAttribute(
                graph: graph,
                environment: environmentAttr,
                modifier: modifierAttr,
                itemList: itemListAttr,
                phase: phaseAttr,
                tracker: tracker
            )

            var storage = alertStorage(from: storageAttr)
            XCTAssertNil(storage?.accessibilityTitle)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.accessibilityEnabled = true
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)

            storage = alertStorage(from: storageAttr)
            XCTAssertNil(storage?.accessibilityTitle)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))
        }
    }

    func testMakeAlertStorageKeepsOutputForNonInputRefreshWhenTrackedEnvironmentIsUnchanged() {
        let graph = _AGGraph()
        let presentation = BoolBox(true)

        _AGGraph.withCurrent(graph) {
            let environment = EnvironmentValues.tracking()
            let environmentAttr = graph.makeInput(value: environment)
            let modifierAttr = graph.makeInput(
                value: alertModifier(isPresented: binding(to: presentation))
            )
            let itemListAttr = graph.makeInput(value: PlatformItemList())
            let phaseAttr = graph.makeInput(value: Phase())
            let tracker = _PropertyListTracker()
            let storageAttr = alertStorageAttribute(
                graph: graph,
                environment: environmentAttr,
                modifier: modifierAttr,
                itemList: itemListAttr,
                phase: phaseAttr,
                tracker: tracker
            )

            XCTAssertNotNil(alertStorage(from: storageAttr))
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            presentation.value = false
            graph.markNeedsEvaluation(storageAttr.identifier, inputsChanged: false)
            XCTAssertNotNil(alertStorage(from: storageAttr))

            modifierAttr.setValue(alertModifier(isPresented: binding(to: presentation)))
            XCTAssertNil(alertStorage(from: storageAttr))
        }
    }

    private func alertModifier(isPresented: Binding<Bool>) -> AlertModifier<EmptyView, EmptyView> {
        AlertModifier(
            presentedValue: isPresented.wrappedValue,
            isPresented: isPresented,
            title: Text("Tracked Alert"),
            actions: EmptyView(),
            message: EmptyView(),
            auxiliaryContent: nil,
            representsError: false,
            severity: .standard
        )
    }

    private func alertPreference(
        from attribute: Attribute<MakeAlertStorage<EmptyView, EmptyView>.Value>
    ) -> AlertPreference? {
        alertStorage(from: attribute)?.preference
    }

    private func alertStorage(
        from attribute: Attribute<MakeAlertStorage<EmptyView, EmptyView>.Value>
    ) -> AlertStorage? {
        var values = AlertStorage.PreferenceKey.defaultValue
        attribute.value(&values)
        return values.values.first
    }

    private func alertStorageAttribute(
        graph: _AGGraph,
        environment: Attribute<EnvironmentValues>,
        modifier: Attribute<AlertModifier<EmptyView, EmptyView>>,
        itemList: Attribute<PlatformItemList>,
        phase: Attribute<Phase>,
        tracker: _PropertyListTracker
    ) -> Attribute<MakeAlertStorage<EmptyView, EmptyView>.Value> {
        graph.makeStatefulRule(
            MakeAlertStorage(
                environment: environment,
                modifier: modifier,
                actionsItemList: itemList.asWeak(),
                messageItemList: itemList.asWeak(),
                phase: phase,
                identityTracker: ViewIdentity.Tracker(),
                propertyTracker: tracker,
                lastTitle: nil,
                lastColorScheme: nil,
                lastIcon: nil,
                lastTintColor: nil,
                lastSeverity: .standard,
                lastSuppressionConfiguration: nil,
                lastAccessibilityTitle: nil,
                lastDialogPreventsTermination: nil
            )
        )
    }

    private func binding(to box: BoolBox) -> Binding<Bool> {
        Binding(
            get: { box.value },
            set: { box.value = $0 }
        )
    }
}

private final class BoolBox {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}
