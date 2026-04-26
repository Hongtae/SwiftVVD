//
//  File: SheetContentModifiers.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// Reset and clear modifier chain applied inside SheetContent.body.

// MARK: - EnvironmentModifier protocol

// EnvironmentModifier: refinement of ViewModifier + _GraphInputsModifier.
// Types conforming to this protocol write multiple EnvironmentValues at once
// via _makeInputs instead of using body(content:).
protocol EnvironmentModifier: ViewModifier, _GraphInputsModifier where Body == Never {}

// MARK: - TintAdjustmentMode environment key

// TintAdjustmentMode controls tint color adjustment behavior.
// Written as nil (Optional.none) by SheetContent.body to reset tint.
enum TintAdjustmentMode: Equatable {
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

// Optional hosting context environment key reset by SheetContent.body.
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

// ResetScrollEnvironmentModifier: ViewModifier, EnvironmentModifier
// body(content:) applies AdditionalResetModifier and TransformScrollStorageModifier<ResetTransform>.
// Wrapped in StaticIf<_SemanticFeature<Semantics_v6>, ...> in SheetContent.body.
struct ResetScrollEnvironmentModifier: ViewModifier {
    // AdditionalResetModifier resets: scrollAnchors, ScrollToTopGestureActionKey,
    // ScrollContentBackgroundKey, popoverAutomaticallyDismissesWhenScrolledOutOfView
    // ResetTransform resets ScrollEnvironmentProperties.
    // These scroll-specific env keys and types are not implemented yet.
    struct AdditionalResetModifier: ViewModifier, _GraphInputsModifier {
        typealias Body = Never
        static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
            // Stub: resets scroll-related environment values (scrollAnchors etc.)
            // Full implementation is deferred until the scroll subsystem is implemented.
        }
    }

    // ResetTransform.update resets ScrollEnvironmentProperties.
    struct ResetTransform {}

    func body(content: _ViewModifier_Content<ResetScrollEnvironmentModifier>) -> some View {
        content
            .modifier(AdditionalResetModifier())
        // Stub: .modifier(TransformScrollStorageModifier(transform: ResetTransform()))
        // TransformScrollStorageModifier is not implemented yet.
    }
}

// MARK: - ResetListStackBehavior

// ListStackBehavior controls list stack-push navigation behavior.
// Written by resetListStackBehavior() to reset to default stack behavior.
// Full fields can be added when list navigation behavior is implemented.
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
// None of these search env keys are implemented yet.
struct ResetSearchEnvironmentModifier: EnvironmentModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        // Stub: resets search-related environment values (SearchFieldPlacementKey etc.)
        // Full implementation is deferred until the search subsystem is implemented.
    }
}

// MARK: - ResetFormEnvironmentModifier

// ResetFormEnvironmentModifier: EnvironmentModifier, _GraphInputsModifier
// Resets form-related environment values for sheet content.
// Env keys reset: FormInsetsKey, FormRowInfoVisibilityKey, FormRowAccessoryVisibilityKey,
//   EffectiveFormStyleKey, GroupedFormSizeVariantKey
// None of these form env keys are implemented yet.
struct ResetFormEnvironmentModifier: EnvironmentModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        // Stub: resets form-related environment values (FormInsetsKey etc.)
        // Full implementation is deferred until the form subsystem is implemented.
    }
}

// MARK: - ResetTabViewEnvironmentModifier

// ResetTabViewEnvironmentModifier: EnvironmentModifier, _GraphInputsModifier
// Resets tab view-related environment values for sheet content.
// Env keys reset: TabBarPlacementKey (rawValue 5 = .automatic), IsTabBarShowingSectionsKey (false)
// These tab view env keys are not implemented yet.
struct ResetTabViewEnvironmentModifier: EnvironmentModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        // Stub: resets tab view-related environment values (TabBarPlacementKey etc.)
        // Full implementation is deferred until the tab view subsystem is implemented.
    }
}

// MARK: - ClearNavigationContextModifier

// ClearNavigationContextModifier: ViewInputsModifier, ViewModifier
// Clears navigation context from _ViewInputs using _makeViewInputs path.
// Has no body(content:) and uses the ViewInputsModifier protocol.
struct ClearNavigationContextModifier: ViewModifier, _ViewInputsModifier {
    typealias Body = Never

    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        // Stub: clears navigation context state from _ViewInputs.customInputs.
        // Full implementation is deferred until the navigation subsystem is implemented.
    }
}

extension View {
    func clearNavigationContext() -> some View {
        modifier(ClearNavigationContextModifier())
    }
}

// MARK: - NavigationEnabled

// NavigationEnabled: written to isNavigationEnabledInternal env key in SheetContent.body.
// Full fields can be added when navigation behavior is implemented.
struct NavigationEnabled: Equatable {
    // Placeholder until the navigation subsystem is implemented.
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
// Full fields can be added when navigation behavior is implemented.
enum NavigationState {
    struct SelectionSeed: Equatable {
        // Placeholder until the navigation subsystem is implemented.
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
// Full fields can be added when sharing behavior is implemented.
struct PresentSharingPickerAction {
    // Placeholder until the sharing subsystem is implemented.
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
