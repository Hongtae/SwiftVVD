//
//  File: AppearanceAnimationView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum AppearanceAnimationStrategy: Hashable {
    case withAnimation
    case animationValue
}

struct AppearanceAnimationView<Content: View, Value: View>: View {
    var content: Content
    var from: Value
    var to: Value
    var animation: Animation
    var strategy: AppearanceAnimationStrategy

    init(
        content: Content,
        from: Value,
        to: Value,
        animation: Animation,
        strategy: AppearanceAnimationStrategy
    ) {
        self.content = content
        self.from = from
        self.to = to
        self.animation = animation
        self.strategy = strategy
    }

    @ViewBuilder
    var body: some View {
        switch strategy {
        case .withAnimation:
            NormalBody_WithAnimation(view: self)
        case .animationValue:
            NormalBody_AnimationValue(view: self)
        }
    }

    var displayListAnimation: (any _DisplayList_AnyEffectAnimation)? {
        if let from = from as? ModifiedContent<Content, _OpacityEffect>,
           let to = to as? ModifiedContent<Content, _OpacityEffect> {
            return DisplayList.OpacityAnimation(
                from: from.modifier,
                to: to.modifier,
                animation: animation
            )
        }
        if let from = from as? ModifiedContent<Content, _OffsetEffect>,
           let to = to as? ModifiedContent<Content, _OffsetEffect> {
            return DisplayList.OffsetAnimation(
                from: from.modifier,
                to: to.modifier,
                animation: animation
            )
        }
        if let from = from as? ModifiedContent<Content, _ScaleEffect>,
           let to = to as? ModifiedContent<Content, _ScaleEffect> {
            return DisplayList.ScaleAnimation(
                from: from.modifier,
                to: to.modifier,
                animation: animation
            )
        }
        if let from = from as? ModifiedContent<Content, _RotationEffect>,
           let to = to as? ModifiedContent<Content, _RotationEffect> {
            return DisplayList.RotationAnimation(
                from: from.modifier,
                to: to.modifier,
                animation: animation
            )
        }
        return nil
    }

    var archivedBody: some View {
        content.modifier(AnimationEffect(animation: displayListAnimation))
    }

    struct AnimationEffect: _RendererEffect, MultiViewModifier {
        var animation: (any _DisplayList_AnyEffectAnimation)?

        func effectValue(size: CGSize) -> DisplayList.Effect {
            animation.map(DisplayList.Effect.animation) ?? .identity
        }

        typealias Body = Never

        static func _makeView(
            modifier: _GraphValue<Self>,
            inputs: _ViewInputs,
            body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
        ) -> _ViewOutputs {
            _RendererEffectSupport.makeView(
                effect: modifier,
                inputs: inputs,
                body: body
            )
        }

        static func _makeViewList(
            modifier: _GraphValue<Self>,
            inputs: _ViewListInputs,
            body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
        ) -> _ViewListOutputs {
            _RendererEffectSupport.makeViewList(
                modifier: modifier,
                inputs: inputs,
                body: body
            )
        }
    }

    private struct AnimationState {
        var seed: UInt32 = 0
        var active = false
    }

    private struct NormalBody_WithAnimation: View {
        @State private var state = AnimationState()
        var view: AppearanceAnimationView

        var body: some View {
            let value = state.active ? view.to : view.from
            return value
                .id(state.seed)
                .modifier(
                    _AppearanceActionModifier(
                        appear: {
                            withAnimation(view.animation) {
                                state.active.toggle()
                            }
                        },
                        disappear: reset
                    )
                )
        }

        private func reset() {
            state.active = false
            state.seed &+= 1
        }
    }

    private struct NormalBody_AnimationValue: View {
        @State private var state = AnimationState()
        var view: AppearanceAnimationView

        var body: some View {
            let value = state.active ? view.to : view.from
            return value
                .animation(view.animation, value: state.active)
                .id(state.seed)
                .modifier(
                    _AppearanceActionModifier(
                        appear: { state.active.toggle() },
                        disappear: reset
                    )
                )
        }

        private func reset() {
            state.active = false
            state.seed &+= 1
        }
    }
}

extension View {
    func appearanceAnimation<Modified: View>(
        animation: Animation = .default,
        strategy: AppearanceAnimationStrategy = .withAnimation,
        modifier: (Self, Bool) -> Modified
    ) -> some View {
        AppearanceAnimationView(
            content: self,
            from: modifier(self, false),
            to: modifier(self, true),
            animation: animation,
            strategy: strategy
        )
    }
}
