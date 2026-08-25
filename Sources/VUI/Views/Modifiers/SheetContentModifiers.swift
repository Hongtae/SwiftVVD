//
//  File: SheetContentModifiers.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// Reset/clear modifier chain applied inside SheetContent.body.

// MARK: - EnvironmentModifier protocol

// EnvironmentModifier writes a complete environment transformation through
// the graph-input modifier path.
protocol EnvironmentModifier: _GraphInputsModifier {
    static func makeEnvironment(
        modifier: Attribute<Self>,
        environment: inout EnvironmentValues
    )
}

extension EnvironmentModifier {
    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeInputs called outside an active _AGGraph context.")
        }
        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let environment = graph.makeRule {
            var environment = parentEnvironment.value.trackingCopy()
            Self.makeEnvironment(
                modifier: modifier._attribute,
                environment: &environment
            )
            return environment
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }
}

// MARK: - TintAdjustmentMode environment key

// TintAdjustmentMode controls tint color adjustment behavior.
// Written as nil (Optional.none) by SheetContent.body to reset tint.
enum TintAdjustmentMode: Hashable {
    case automatic
    case dimmed
    case normal
}

private struct _TintAdjustmentModeKey: EnvironmentKey {
    static var defaultValue: TintAdjustmentMode? { nil }
}

extension EnvironmentValues {
    var tintAdjustmentMode: TintAdjustmentMode? {
        get { self[_TintAdjustmentModeKey.self] }
        set { self[_TintAdjustmentModeKey.self] = newValue }
    }
}

// MARK: - IsSheetPresentedKey

// IsSheetPresentedKey: Bool environment key.
// SheetContent.body writes false to reset the sheet-presented state for sheet content.
struct IsSheetPresentedKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    var isSheetPresented: Bool {
        get { self[IsSheetPresentedKey.self] }
        set { self[IsSheetPresentedKey.self] = newValue }
    }
}

// MARK: - _SheetHostingContextKey (anonymous Optional<Bool>)

// Anonymous Optional<Bool> environment key set in step 3 of SheetContent.body chain.
// The exact public/private property name is unavailable, so this file keeps a
// local key dedicated to sheet hosting context reset.
// Value is always nil (Optional<Bool>.none) in SheetContent.body.
private struct _SheetHostingContextKey: EnvironmentKey {
    static var defaultValue: Bool? { nil }
}

extension EnvironmentValues {
    var _sheetHostingContext: Bool? {
        get { self[_SheetHostingContextKey.self] }
        set { self[_SheetHostingContextKey.self] = newValue }
    }
}

// MARK: - ResetScrollEnvironmentModifier

// This modifier keeps nested scroll containers from inheriting scroll-specific
// environment policies that belong to their enclosing container.
struct ResetScrollEnvironmentModifier: ViewModifier, EnvironmentModifier {
    static func makeEnvironment(
        modifier: Attribute<Self>,
        environment: inout EnvironmentValues
    ) {}

    // AdditionalResetModifier also owns scroll-anchor, gesture, and popover
    // reset values as those carriers become available.
    // ResetTransform resets ScrollEnvironmentProperties.
    // Other unavailable reset channels remain unchanged for now.
    struct AdditionalResetModifier: ViewModifier, EnvironmentModifier {
        typealias Body = Never
        static func makeEnvironment(
            modifier: Attribute<Self>,
            environment: inout EnvironmentValues
        ) {
            // A nested scroll container starts with a fresh content-background policy.
            environment.scrollContentBackground = ScrollContentBackground()
        }
    }

    // ResetTransform belongs to the coupled scroll-storage replacement.
    struct ResetTransform {}

    func body(content: _ViewModifier_Content<ResetScrollEnvironmentModifier>) -> some View {
        content
            .modifier(AdditionalResetModifier())
        // TransformScrollStorageModifier(transform:) belongs here once scroll
        // environment storage is available.
    }
}

// MARK: - ResetListStackBehavior

// ListStackBehavior controls list stack-push navigation behavior.
// Written by resetListStackBehavior() to reset to default stack behavior.
// List navigation fields are added by the navigation subsystem.
struct ListStackBehavior: Equatable {}

private struct _ListHasStackBehaviorKey: EnvironmentKey {
    static var defaultValue: ListStackBehavior { ListStackBehavior() }
}

extension EnvironmentValues {
    var _listHasStackBehavior: ListStackBehavior {
        get { self[_ListHasStackBehaviorKey.self] }
        set { self[_ListHasStackBehaviorKey.self] = newValue }
    }
}

extension View {
    // resetListStackBehavior() calls View.environment(WritableKeyPath, ListStackBehavior)
    // to reset list stack-push behavior for sheet content.
    func resetListStackBehavior() -> some View {
        environment(\._listHasStackBehavior, ListStackBehavior())
    }
}

// MARK: - ResetSearchEnvironmentModifier

// ResetSearchEnvironmentModifier: EnvironmentModifier, _GraphInputsModifier
// Resets search-related environment values for sheet content.
// Env keys reset: SearchFieldPlacementKey, SearchFieldToolbarItemPlacementKey,
//   __Key_searchStorage, IsSearchingKey, SearchScopeActivationKey,
//   SearchFocusContextKey, __Key_searchTextClearAction
// Search environment storage is added by the search subsystem.
struct ResetSearchEnvironmentModifier: ViewModifier, EnvironmentModifier {
    typealias Body = Never

    static func makeEnvironment(
        modifier: Attribute<Self>,
        environment: inout EnvironmentValues
    ) {
        // Writes the search reset values once search environment storage is available.
    }
}

// MARK: - ResetFormEnvironmentModifier

// ResetFormEnvironmentModifier: EnvironmentModifier, _GraphInputsModifier
// Resets form-related environment values for sheet content.
// Env keys reset: FormInsetsKey, FormRowInfoVisibilityKey, FormRowAccessoryVisibilityKey,
//   EffectiveFormStyleKey, GroupedFormSizeVariantKey
// Form environment storage is added by the form subsystem.
struct ResetFormEnvironmentModifier: ViewModifier, EnvironmentModifier {
    typealias Body = Never

    static func makeEnvironment(
        modifier: Attribute<Self>,
        environment: inout EnvironmentValues
    ) {
        // Writes the form reset values once form environment storage is available.
    }
}

// MARK: - ResetTabViewEnvironmentModifier

// ResetTabViewEnvironmentModifier: EnvironmentModifier, _GraphInputsModifier
// Resets tab view-related environment values for sheet content.
// Env keys reset: TabBarPlacementKey (rawValue 5 = .automatic), IsTabBarShowingSectionsKey (false)
// Tab view environment storage is added by the tab view subsystem.
struct ResetTabViewEnvironmentModifier: ViewModifier, EnvironmentModifier {
    typealias Body = Never

    static func makeEnvironment(
        modifier: Attribute<Self>,
        environment: inout EnvironmentValues
    ) {
        // Writes the tab view reset values once tab view environment storage is available.
    }
}

// MARK: - ClearNavigationContextModifier

// ClearNavigationContextModifier: ViewInputsModifier, ViewModifier
// Clears navigation context from _ViewInputs using _makeViewInputs path.
// Has no body(content:). Uses ViewInputsModifier protocol (_makeViewInputs).
struct ClearNavigationContextModifier: ViewInputsModifier {
    typealias Body = Never

    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        // Clears navigation context once navigation input storage is available.
    }
}

extension View {
    func clearNavigationContext() -> some View {
        modifier(ClearNavigationContextModifier())
    }
}

// MARK: - NavigationBarControlledNavigation

struct NavigationBarControlledNavigation: ViewInputBoolFlag {}

// MARK: - NavigationEnabled

// NavigationEnabled: written to isNavigationEnabledInternal env key in SheetContent.body.
// Navigation state fields are added by the navigation subsystem.
struct NavigationEnabled: Equatable {
}

private struct _NavigationEnabledKey: EnvironmentKey {
    static var defaultValue: NavigationEnabled { NavigationEnabled() }
}

extension EnvironmentValues {
    var isNavigationEnabledInternal: NavigationEnabled {
        get { self[_NavigationEnabledKey.self] }
        set { self[_NavigationEnabledKey.self] = newValue }
    }
}

// MARK: - NavigationState.SelectionSeed

// NavigationState.SelectionSeed: written to navigationSelectionSeed env key in SheetContent.body.
// Selection seed fields are added by the navigation subsystem.
enum NavigationState {
    struct SelectionSeed: Equatable {
    }
}

private struct _NavigationSelectionSeedKey: EnvironmentKey {
    static var defaultValue: NavigationState.SelectionSeed { NavigationState.SelectionSeed() }
}

extension EnvironmentValues {
    var navigationSelectionSeed: NavigationState.SelectionSeed {
        get { self[_NavigationSelectionSeedKey.self] }
        set { self[_NavigationSelectionSeedKey.self] = newValue }
    }
}

// MARK: - clearSharingPickerHost

// PresentSharingPickerAction: env value for presenting the sharing picker.
// Written as nil (Optional.none) by clearSharingPickerHost() to reset sharing context.
// Sharing action fields are added by the sharing subsystem.
struct PresentSharingPickerAction {
}

private struct _PresentSharingPickerKey: EnvironmentKey {
    static var defaultValue: PresentSharingPickerAction? { nil }
}

extension EnvironmentValues {
    var presentSharingPicker: PresentSharingPickerAction? {
        get { self[_PresentSharingPickerKey.self] }
        set { self[_PresentSharingPickerKey.self] = newValue }
    }
}

extension View {
    // clearSharingPickerHost() writes PresentSharingPickerKey to nil via UnidentifiedSharingPickerModifier.
    func clearSharingPickerHost() -> some View {
        environment(\.presentSharingPicker, nil)
    }
}
