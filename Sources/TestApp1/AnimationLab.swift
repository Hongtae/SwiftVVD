import Foundation
import VUI

private final class AnimationLabTraceAction: @unchecked Sendable {
    let body: () -> Void

    init(_ body: @escaping () -> Void) {
        self.body = body
    }
}

struct AnimationLabSheet: View {
    private static let inspectionAnimationDuration = 5.0
    private static let sequenceTransitionDelay: DispatchTimeInterval = .milliseconds(5_500)

    let onClose: () -> Void

    @State private var expanded = false
    @State private var showRetainedChild = true
    @State private var runCount = 0
    @State private var completionStatus = "idle"
    @State private var didStartAutomatedTrace = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 12) {
            Text("Animation Lab")
                .font(.system(size: 22, weight: .semibold))

            Text(String(
                format: "Run %d: %@ · scale %.1fx",
                runCount,
                completionStatus,
                displayScale
            ))
                .font(.system(.callout))
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button("Spring Move") {
                    runSpringMove()
                }

                Button(showRetainedChild ? "Remove Child" : "Insert Child") {
                    toggleRetainedChild()
                }

                Button("Sequence") {
                    runSequence()
                }

                Button("Close") {
                    onClose()
                }
            }

            HStack(spacing: 28) {
                RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                    .fill(expanded ? Color.purple : Color.blue)
                    .frame(
                        width: expanded ? 180 : 72,
                        height: expanded ? 96 : 72
                    )
                    .scaleEffect(expanded ? 1.08 : 0.78)
                    .rotationEffect(.degrees(expanded ? 8 : -8))
                    .offset(x: expanded ? 42 : -42, y: expanded ? 8 : -8)
                    .opacity(expanded ? 0.92 : 0.55)

                VStack(spacing: 8) {
                    Text("Retained removal")
                        .font(.system(.headline))
                        .foregroundStyle(
                            ProcessInfo.processInfo.environment[
                                "VUI_ANIMATION_TRACE_SCENARIO"
                            ] != nil
                                ? Color(red: 1, green: 0, blue: 1)
                                : Color.black
                        )
                    if showRetainedChild {
                        VStack(spacing: 6) {
                            Text("Animated child")
                                .font(.system(.subheadline))
                            Text(expanded ? "expanded" : "compact")
                                .font(.system(.caption))
                                .foregroundColor(.secondary)
                        }
                        .padding(18)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    expanded
                                        ? Color.orange.opacity(0.35)
                                        : Color.green.opacity(0.35)
                                )
                        }
                        .scaleEffect(expanded ? 1.0 : 0.82)
                        .offset(y: expanded ? -8 : 8)
                        .transition(
                            .scale(scale: 0.72)
                                .combined(with: .opacity)
                                .animation(
                                    .easeInOut(
                                        duration: Self.inspectionAnimationDuration
                                    )
                                )
                        )
                    } else {
                        Text("child removed")
                            .font(.system(.caption))
                            .foregroundColor(.secondary)
                            .padding(18)
                    }
                }
                .frame(width: 190, height: 150)
                .border(
                    ProcessInfo.processInfo.environment["VUI_ANIMATION_TRACE_SCENARIO"] != nil
                        ? Color.red
                        : Color.gray,
                    width: ProcessInfo.processInfo.environment["VUI_ANIMATION_TRACE_SCENARIO"] != nil
                        ? 2
                        : 1
                )
            }
            .frame(height: 170)

            Text("Use this as a manual smoke surface for state animation, transition removal, and sheet/modal presentation running together.")
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 560, height: 360)
        .onAppear {
            runAutomatedTraceIfRequested()
        }
    }

    private func runSpringMove() {
        let nextRun = runCount + 1
        runCount = nextRun
        completionStatus = "spring running"
        withAnimation(
            .spring(duration: Self.inspectionAnimationDuration, bounce: 0.35),
            completionCriteria: .logicallyComplete
        ) {
            expanded.toggle()
        } completion: {
            completionStatus = "spring logical completion \(nextRun)"
        }
    }

    private func toggleRetainedChild() {
        let nextRun = runCount + 1
        let wasVisible = showRetainedChild
        runCount = nextRun
        completionStatus = wasVisible ? "removal running" : "insertion running"
        withAnimation(
            .easeInOut(duration: Self.inspectionAnimationDuration),
            completionCriteria: wasVisible ? .removed : .logicallyComplete
        ) {
            showRetainedChild.toggle()
        } completion: {
            completionStatus = wasVisible
                ? "removed completion \(nextRun)"
                : "inserted completion \(nextRun)"
        }
    }

    private func runSequence() {
        let nextRun = runCount + 1
        runCount = nextRun
        completionStatus = "sequence spring"
        withAnimation(
            .spring(duration: Self.inspectionAnimationDuration, bounce: 0.2)
        ) {
            expanded.toggle()
        }
        let completion = $completionStatus
        let retainedChild = $showRetainedChild
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sequenceTransitionDelay) {
            completion.wrappedValue = "sequence transition"
            withAnimation(
                .easeInOut(duration: Self.inspectionAnimationDuration),
                completionCriteria: retainedChild.wrappedValue ? .removed : .logicallyComplete
            ) {
                retainedChild.wrappedValue.toggle()
            } completion: {
                completion.wrappedValue = "sequence complete \(nextRun)"
            }
        }
    }

    private func runAutomatedTraceIfRequested() {
        guard let scenario = ProcessInfo.processInfo.environment[
            "VUI_ANIMATION_TRACE_SCENARIO"
        ], !didStartAutomatedTrace else {
            return
        }
        didStartAutomatedTrace = true

        func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) {
            // The trace harness only invokes actions on the main queue.
            let action = AnimationLabTraceAction(action)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                action.body()
            }
        }

        switch scenario {
        case "repeated":
            let startDelay = 3.5
            for cycle in 0..<20 {
                let base = startDelay + Double(cycle) * 1.2
                schedule(base) {
                    toggleRetainedChild()
                }
                schedule(base + 0.1) {
                    toggleRetainedChild()
                }
                schedule(base + 0.4) {
                    runSpringMove()
                }
            }
        default:
            schedule(3.5) {
                runSpringMove()
            }
            schedule(4.5) {
                toggleRetainedChild()
            }
            schedule(5.5) {
                runSpringMove()
            }
        }
    }
}
