import Foundation
import VUI

private struct FeatureKeyframeValues {
    var scale = 1.0
    var rotation = 0.0
    var offset = 0.0
}

private enum FeaturePhase: CaseIterable {
    case compact
    case expanded
    case faded
}

struct KeyframePhaseLabSheet: View {
    let onClose: () -> Void

    @State private var keyframeTrigger = 0
    @State private var phaseTrigger = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Keyframe & Phase Lab")
                .font(.system(size: 22, weight: .semibold))

            HStack(spacing: 80) {
                VStack(spacing: 14) {
                    Text("KeyframeAnimator")
                        .font(.system(.headline))

                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.blue)
                        .frame(width: 90, height: 70)
                        .keyframeAnimator(
                            initialValue: FeatureKeyframeValues(),
                            trigger: keyframeTrigger
                        ) { content, value in
                            content
                                .scaleEffect(value.scale)
                                .rotationEffect(.degrees(value.rotation))
                                .offset(x: value.offset)
                        } keyframes: { _ in
                            KeyframeTrack(\.scale) {
                                CubicKeyframe(1.35, duration: 0.45)
                                SpringKeyframe(0.86, duration: 0.45)
                                CubicKeyframe(1.0, duration: 0.35)
                            }
                            KeyframeTrack(\.rotation) {
                                LinearKeyframe(20, duration: 0.30)
                                SpringKeyframe(-12, duration: 0.50)
                                CubicKeyframe(0, duration: 0.45)
                            }
                            KeyframeTrack(\.offset) {
                                CubicKeyframe(65, duration: 0.45)
                                SpringKeyframe(-30, duration: 0.50)
                                CubicKeyframe(0, duration: 0.35)
                            }
                        }

                    Button("Run Keyframes") {
                        keyframeTrigger += 1
                    }
                }
                .frame(width: 240, height: 220)

                VStack(spacing: 14) {
                    Text("PhaseAnimator")
                        .font(.system(.headline))

                    Circle()
                        .fill(Color.purple)
                        .frame(width: 86, height: 86)
                        .phaseAnimator(
                            FeaturePhase.allCases,
                            trigger: phaseTrigger
                        ) { content, phase in
                            content
                                .scaleEffect(phase == .expanded ? 1.35 : 0.82)
                                .offset(y: phase == .faded ? 34 : -8)
                                .opacity(phase == .faded ? 0.30 : 1.0)
                        } animation: { phase in
                            switch phase {
                            case .compact:
                                .easeOut(duration: 0.35)
                            case .expanded:
                                .spring(duration: 0.8, bounce: 0.35)
                            case .faded:
                                .easeInOut(duration: 0.55)
                            }
                        }

                    Button("Run Phases") {
                        phaseTrigger += 1
                    }
                }
                .frame(width: 240, height: 220)
            }

            Text("Repeat each trigger and retrigger while motion is active. Compare phase order, keyframe overshoot, and settled geometry.")
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") {
                onClose()
            }
        }
        .padding(24)
        .frame(width: 680, height: 430)
    }
}

struct MatchedGeometryLabSheet: View {
    let onClose: () -> Void

    @Namespace private var namespace
    @State private var expanded = false
    @State private var alternateSource = false

    var body: some View {
        VStack(spacing: 22) {
            Text("Matched Geometry Lab")
                .font(.system(size: 22, weight: .semibold))

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.secondary.opacity(0.10))

                if expanded {
                    HStack {
                        Spacer()
                        matchedCard
                            .frame(width: 230, height: 130)
                    }
                    .padding(24)
                } else {
                    HStack {
                        matchedCard
                            .frame(width: 110, height: 78)
                        Spacer()
                    }
                    .padding(24)
                }
            }
            .frame(width: 560, height: 210)

            HStack(spacing: 12) {
                Button("Toggle Layout") {
                    withAnimation(.spring(duration: 2.0, bounce: 0.25)) {
                        expanded.toggle()
                    }
                }

                Button("Toggle Source Flag") {
                    withAnimation(.easeInOut(duration: 1.2)) {
                        alternateSource.toggle()
                    }
                }
            }

            Text("Toggle repeatedly during flight. The shared card should preserve identity, corner interpolation, text placement, and velocity continuity.")
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") {
                onClose()
            }
        }
        .padding(24)
        .frame(width: 660, height: 460)
    }

    private var matchedCard: some View {
        RoundedRectangle(cornerRadius: expanded ? 30 : 12)
            .fill(
                alternateSource
                    ? Color.orange
                    : Color.indigo
            )
            .overlay {
                Text(expanded ? "Destination" : "Source")
                    .font(.system(.headline))
                    .foregroundColor(.white)
            }
            .matchedGeometryEffect(
                id: "matched-card",
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: !alternateSource
            )
    }
}

struct ContentTransitionLabSheet: View {
    let onClose: () -> Void

    @State private var count = 0
    @State private var alternateText = false
    @State private var cardVisible = true

    var body: some View {
        VStack(spacing: 24) {
            Text("Content & View Transition Lab")
                .font(.system(size: 22, weight: .semibold))

            HStack(spacing: 70) {
                VStack(spacing: 12) {
                    Text("Numeric Text")
                        .font(.system(.headline))
                    Text("\(count)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: Double(count)))
                    Button("Increment") {
                        withAnimation(.spring(duration: 1.2, bounce: 0.2)) {
                            count += 17
                        }
                    }
                }
                .frame(width: 200)

                VStack(spacing: 12) {
                    Text("Interpolate")
                        .font(.system(.headline))
                    Text(alternateText ? "Expanded value" : "Compact")
                        .font(
                            .system(
                                size: alternateText ? 30 : 20,
                                weight: .semibold
                            )
                        )
                        .foregroundColor(alternateText ? .purple : .blue)
                        .contentTransition(.interpolate)
                    Button("Change Text") {
                        withAnimation(.easeInOut(duration: 1.4)) {
                            alternateText.toggle()
                        }
                    }
                }
                .frame(width: 240)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                if cardVisible {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.green)
                        .frame(width: 180, height: 82)
                        .overlay {
                            Text("Transitioned view")
                                .font(.system(.headline))
                                .foregroundColor(.white)
                        }
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.65)
                                    .combined(with: .opacity),
                                removal: .move(edge: .trailing)
                                    .combined(with: .opacity)
                            )
                        )
                }
            }
            .frame(width: 430, height: 125)

            Button(cardVisible ? "Remove View" : "Insert View") {
                withAnimation(.easeInOut(duration: 2.0)) {
                    cardVisible.toggle()
                }
            }

            Text("Compare numeric direction, interpolated glyph/style changes, retained removal, asymmetric motion, and final layout.")
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") {
                onClose()
            }
        }
        .padding(24)
        .frame(width: 680, height: 540)
    }
}

struct TimelineLabSheet: View {
    let onClose: () -> Void

    @State private var paused = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Timeline Lab")
                .font(.system(size: 22, weight: .semibold))

            TimelineView(
                .animation(minimumInterval: 1.0 / 30.0, paused: paused)
            ) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let angle = Angle.degrees(
                    time.truncatingRemainder(dividingBy: 4) * 90
                )

                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.30), lineWidth: 2)
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 22, height: 22)
                            .offset(y: -72)
                            .rotationEffect(angle)
                    }
                    .frame(width: 180, height: 180)

                    Text(context.date, style: .timer)
                        .font(.system(.body, design: .monospaced))
                    Text("cadence: \(String(describing: context.cadence))")
                        .font(.system(.caption))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button(paused ? "Resume Timeline" : "Pause Timeline") {
                    paused.toggle()
                }
                Button("Close") {
                    onClose()
                }
            }

            Text("Observe continuous cadence, pause/resume behavior, time publication, and frame continuity after the sheet is covered and revealed.")
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 560, height: 470)
    }
}

struct VisualMeshLabSheet: View {
    let onClose: () -> Void

    @State private var shifted = false

    var body: some View {
        let visualShifted = shifted

        VStack(spacing: 22) {
            Text("Visual Effect & Mesh Lab")
                .font(.system(size: 22, weight: .semibold))

            HStack(spacing: 44) {
                VStack(spacing: 12) {
                    Text("VisualEffect")
                        .font(.system(.headline))

                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.purple)
                        .frame(width: 180, height: 130)
                        .visualEffect { effect, proxy in
                            effect
                                .scaleEffect(visualShifted ? 1.14 : 0.82)
                                .rotationEffect(
                                    .degrees(visualShifted ? 12 : -12)
                                )
                                .offset(
                                    x: visualShifted
                                        ? proxy.size.width * 0.18
                                        : -proxy.size.width * 0.18
                                )
                                .opacity(visualShifted ? 0.92 : 0.58)
                        }
                }

                VStack(spacing: 12) {
                    Text("MeshGradient")
                        .font(.system(.headline))

                    RoundedRectangle(cornerRadius: 18)
                        .fill(meshGradient)
                        .frame(width: 230, height: 150)
                }
            }

            Button("Animate Visuals") {
                withAnimation(.easeInOut(duration: 3.0)) {
                    shifted.toggle()
                }
            }

            Text("Compare transform composition, opacity, mesh point/color interpolation, clipping, and the exact settled corners.")
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") {
                onClose()
            }
        }
        .padding(24)
        .frame(width: 690, height: 470)
    }

    private var meshGradient: MeshGradient {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5],
                shifted ? [0.68, 0.30] : [0.32, 0.70],
                [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: shifted
                ? [
                    .red, .orange, .yellow,
                    .purple, .pink, .green,
                    .blue, .cyan, .mint,
                ]
                : [
                    .blue, .cyan, .mint,
                    .indigo, .purple, .pink,
                    .green, .yellow, .orange,
                ],
            background: .black,
            smoothsColors: true,
            colorSpace: .perceptual
        )
    }
}

private struct FeatureLinearCustomAnimation: CustomAnimation {
    var duration: TimeInterval

    func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard time < duration else {
            context.isLogicallyComplete = true
            return nil
        }
        var output = value
        output.scale(by: max(time / duration, 0))
        return output
    }
}

private struct FeatureWave: Shape {
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let samples = 100
        for index in 0...samples {
            let progress = Double(index) / Double(samples)
            let x = rect.minX + rect.width * progress
            let angle = progress * .pi * 4 + phase * .pi * 2
            let y = rect.midY + sin(angle) * rect.height * 0.28
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

struct CustomAnimationLabSheet: View {
    let onClose: () -> Void

    @State private var expanded = false
    @State private var wavePhase = 0.0
    @State private var completionStatus = "idle"

    var body: some View {
        VStack(spacing: 24) {
            Text("Custom Animation & Animatable Lab")
                .font(.system(size: 22, weight: .semibold))

            HStack(spacing: 70) {
                VStack(spacing: 12) {
                    Text("CustomAnimation")
                        .font(.system(.headline))
                    RoundedRectangle(cornerRadius: expanded ? 30 : 10)
                        .fill(
                            expanded
                                ? Color.orange
                                : Color.blue
                        )
                        .frame(
                            width: expanded ? 190 : 85,
                            height: expanded ? 105 : 70
                        )
                        .rotationEffect(.degrees(expanded ? 10 : -10))
                    Text(completionStatus)
                        .font(.system(.caption))
                        .foregroundColor(.secondary)
                }
                .frame(width: 240, height: 210)

                VStack(spacing: 12) {
                    Text("Animatable Shape")
                        .font(.system(.headline))
                    FeatureWave(phase: wavePhase)
                        .stroke(
                            Color.purple,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 240, height: 110)
                }
                .frame(width: 260, height: 210)
            }

            HStack(spacing: 12) {
                Button("Run Custom Animation") {
                    completionStatus = "running"
                    withAnimation(
                        Animation(
                            FeatureLinearCustomAnimation(duration: 2.0)
                        ),
                        completionCriteria: .logicallyComplete
                    ) {
                        expanded.toggle()
                    } completion: {
                        completionStatus = "logical completion"
                    }
                }

                Button("Animate Shape") {
                    withAnimation(.easeInOut(duration: 2.0)) {
                        wavePhase += 1
                    }
                }
            }

            Text("Retarget both controls during flight. Compare custom progress, logical completion, Shape.animatableData interpolation, and final geometry.")
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") {
                onClose()
            }
        }
        .padding(24)
        .frame(width: 690, height: 470)
    }
}
