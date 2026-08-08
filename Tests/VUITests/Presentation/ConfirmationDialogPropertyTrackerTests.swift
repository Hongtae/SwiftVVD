import Foundation
import XCTest
@testable import VUI

final class ConfirmationDialogPropertyTrackerTests: XCTestCase {
    func testMakeConfirmationDialogTracksPlatformWindowEnvironment() {
        let graph = _AGGraph()
        let presentation = BoolBox(true)

        _AGGraph.withCurrent(graph) {
            var environment = EnvironmentValues.tracking()
            environment.modalSessionUsingPlatformWindow = false
            let environmentAttr = graph.makeInput(value: environment)
            let modifierAttr = graph.makeInput(
                value: confirmationDialogModifier(isPresented: binding(to: presentation))
            )
            let itemListAttr = graph.makeInput(value: PlatformItemList())
            let phaseAttr = graph.makeInput(value: _GraphInputs.Phase())
            let positionAttr = graph.makeInput(value: CGPoint.zero)
            let sizeAttr = graph.makeInput(value: CGSize.zero)
            let transformAttr = graph.makeInput(value: ViewTransform())
            let tracker = _PropertyListTracker()
            let storageAttr = confirmationDialogStorageAttribute(
                graph: graph,
                environment: environmentAttr,
                modifier: modifierAttr,
                itemList: itemListAttr,
                phase: phaseAttr,
                position: positionAttr,
                size: sizeAttr,
                transform: transformAttr,
                tracker: tracker
            )

            var preference = confirmationDialogPreference(from: storageAttr)
            XCTAssertEqual(preference?.usesPlatformWindow, false)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.modalSessionUsingPlatformWindow = true
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)

            preference = confirmationDialogPreference(from: storageAttr)
            XCTAssertEqual(preference?.usesPlatformWindow, true)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))
        }
    }

    func testMakeConfirmationDialogTracksBridgeCacheEnvironmentFields() {
        let graph = _AGGraph()
        let presentation = BoolBox(true)
        let icon = Image("tracked-confirmation-icon")

        _AGGraph.withCurrent(graph) {
            var environment = EnvironmentValues.tracking()
            environment.explicitPreferredColorScheme = .dark
            let environmentAttr = graph.makeInput(value: environment)
            let modifierAttr = graph.makeInput(
                value: confirmationDialogModifier(isPresented: binding(to: presentation))
            )
            let itemListAttr = graph.makeInput(value: PlatformItemList())
            let phaseAttr = graph.makeInput(value: _GraphInputs.Phase())
            let positionAttr = graph.makeInput(value: CGPoint.zero)
            let sizeAttr = graph.makeInput(value: CGSize.zero)
            let transformAttr = graph.makeInput(value: ViewTransform())
            let tracker = _PropertyListTracker()
            let storageAttr = confirmationDialogStorageAttribute(
                graph: graph,
                environment: environmentAttr,
                modifier: modifierAttr,
                itemList: itemListAttr,
                phase: phaseAttr,
                position: positionAttr,
                size: sizeAttr,
                transform: transformAttr,
                tracker: tracker
            )

            var storage = confirmationDialogStorage(from: storageAttr)
            XCTAssertEqual(storage?.title, "Tracked Confirmation")
            XCTAssertEqual(storage?.colorScheme, .dark)
            XCTAssertNil(storage?.icon)
            XCTAssertNil(storage?.tintColor)
            XCTAssertNil(storage?.suppressionConfiguration)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.dialogColorScheme = .light
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)
            storage = confirmationDialogStorage(from: storageAttr)
            XCTAssertEqual(storage?.colorScheme, .light)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.dialogIcon = icon
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)
            storage = confirmationDialogStorage(from: storageAttr)
            XCTAssertEqual(storage?.icon, icon)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.dialogTintColor = .red
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)
            storage = confirmationDialogStorage(from: storageAttr)
            XCTAssertEqual(storage?.tintColor, Color.red.resolve(in: environment))
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            environment.dialogSuppression = DialogSuppressionConfiguration()
            XCTAssertTrue(tracker.hasDifferentUsedValues(environment._plist))
            environmentAttr.setValue(environment)
            storage = confirmationDialogStorage(from: storageAttr)
            XCTAssertNotNil(storage?.suppressionConfiguration)
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))
        }
    }

    func testMakeConfirmationDialogKeepsOutputForNonInputRefreshWhenTrackedEnvironmentIsUnchanged() {
        let graph = _AGGraph()
        let presentation = BoolBox(true)

        _AGGraph.withCurrent(graph) {
            let environment = EnvironmentValues.tracking()
            let environmentAttr = graph.makeInput(value: environment)
            let modifierAttr = graph.makeInput(
                value: confirmationDialogModifier(isPresented: binding(to: presentation))
            )
            let itemListAttr = graph.makeInput(value: PlatformItemList())
            let phaseAttr = graph.makeInput(value: _GraphInputs.Phase())
            let positionAttr = graph.makeInput(value: CGPoint.zero)
            let sizeAttr = graph.makeInput(value: CGSize.zero)
            let transformAttr = graph.makeInput(value: ViewTransform())
            let tracker = _PropertyListTracker()
            let storageAttr = confirmationDialogStorageAttribute(
                graph: graph,
                environment: environmentAttr,
                modifier: modifierAttr,
                itemList: itemListAttr,
                phase: phaseAttr,
                position: positionAttr,
                size: sizeAttr,
                transform: transformAttr,
                tracker: tracker
            )

            XCTAssertNotNil(confirmationDialogStorage(from: storageAttr))
            XCTAssertFalse(tracker.hasDifferentUsedValues(environment._plist))

            presentation.value = false
            graph.markNeedsEvaluation(storageAttr.identifier, inputsChanged: false)
            XCTAssertNotNil(confirmationDialogStorage(from: storageAttr))

            modifierAttr.setValue(confirmationDialogModifier(isPresented: binding(to: presentation)))
            XCTAssertNil(confirmationDialogStorage(from: storageAttr))
        }
    }

    private func confirmationDialogModifier(
        isPresented: Binding<Bool>
    ) -> ConfirmationDialogModifier<EmptyView, EmptyView> {
        ConfirmationDialogModifier(
            presentedValue: isPresented.wrappedValue,
            title: Text("Tracked Confirmation"),
            titleVisibility: .automatic,
            actions: EmptyView(),
            message: EmptyView(),
            isPresented: isPresented
        )
    }

    private func confirmationDialogPreference(
        from attribute: Attribute<MakeConfirmationDialog<EmptyView, EmptyView>.Value>
    ) -> ConfirmationDialogPreference? {
        confirmationDialogStorage(from: attribute)?.preference
    }

    private func confirmationDialogStorage(
        from attribute: Attribute<MakeConfirmationDialog<EmptyView, EmptyView>.Value>
    ) -> ConfirmationDialog? {
        var values = ConfirmationDialog.PreferenceKey.defaultValue
        attribute.value(&values)
        return values.values.first
    }

    private func confirmationDialogStorageAttribute(
        graph: _AGGraph,
        environment: Attribute<EnvironmentValues>,
        modifier: Attribute<ConfirmationDialogModifier<EmptyView, EmptyView>>,
        itemList: Attribute<PlatformItemList>,
        phase: Attribute<_GraphInputs.Phase>,
        position: Attribute<CGPoint>,
        size: Attribute<CGSize>,
        transform: Attribute<ViewTransform>,
        tracker: _PropertyListTracker
    ) -> Attribute<MakeConfirmationDialog<EmptyView, EmptyView>.Value> {
        graph.makeStatefulRule(
            MakeConfirmationDialog(
                environment: environment,
                modifier: modifier,
                actionsItemList: itemList.asWeak(),
                messageItemList: itemList.asWeak(),
                phase: phase,
                position: position,
                size: size,
                transform: transform,
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
