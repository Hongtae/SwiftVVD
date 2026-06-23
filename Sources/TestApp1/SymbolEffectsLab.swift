import VUI

struct SymbolEffectsLabSheet: View {
    let onClose: () -> Void

    @State private var pulseTrigger = 0
    @State private var variableColorTrigger = 0
    @State private var drawHidden = false
    @State private var drawTransitionVisible = true
    @State private var replacementUsesDraw = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Symbol Effects Lab")
                .font(.system(size: 22, weight: .semibold))

            HStack(spacing: 14) {
                Button("Pulse") {
                    pulseTrigger += 1
                }

                symbol("by layer", effect: .pulse.byLayer, value: pulseTrigger)
                symbol("whole", effect: .pulse.wholeSymbol, value: pulseTrigger)
            }

            HStack(spacing: 14) {
                Button("Variable Color") {
                    variableColorTrigger += 1
                }

                symbol(
                    "cumulative",
                    effect: .variableColor.cumulative,
                    value: variableColorTrigger
                )
                symbol(
                    "iterative",
                    effect: .variableColor.iterative,
                    value: variableColorTrigger
                )
            }

            HStack(spacing: 14) {
                Button(drawHidden ? "Restore Draw" : "Hide Draw") {
                    drawHidden.toggle()
                }

                drawSymbol("by layer", effect: .drawOn.byLayer)
                drawSymbol("whole", effect: .drawOn.wholeSymbol)
                drawSymbol("individual", effect: .drawOn.individually)
                drawSymbol(
                    "reversed",
                    effect: .drawOff.individually.reversed
                )
            }

            HStack(spacing: 14) {
                Button("Toggle Draw Transition") {
                    withAnimation {
                        drawTransitionVisible.toggle()
                    }
                }

                if drawTransitionVisible {
                    Image(systemName: "draw")
                        .frame(width: 48, height: 48)
                        .foregroundStyle(Color.blue)
                        .transition(.symbolEffect(.drawOn.individually))
                }
            }

            HStack(spacing: 10) {
                Button("Replace") {
                    withAnimation(.linear(duration: 3)) {
                        replacementUsesDraw.toggle()
                    }
                }

                replacementSymbol("default", effect: .replace)
                replacementSymbol("down-up", effect: .replace.downUp)
                replacementSymbol("up-up", effect: .replace.upUp)
                replacementSymbol("off-up", effect: .replace.offUp)
                replacementSymbol("whole", effect: .replace.wholeSymbol)
            }

            Button("Close") {
                onClose()
            }

            Text("Use this surface for visual symbol-layer, timing, and effect-composition checks.")
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 720, height: 540)
    }

    private func symbol<Effect: DiscreteSymbolEffect & SymbolEffect>(
        _ label: String,
        effect: Effect,
        value: Int
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "photo.fill")
                .frame(width: 48, height: 48)
                .foregroundStyle(Color.blue, Color.orange)
                .symbolEffect(effect, options: .nonRepeating, value: value)
            Text(label)
                .font(.system(.caption))
        }
    }


    private func drawSymbol<Effect: IndefiniteSymbolEffect & SymbolEffect>(
        _ label: String,
        effect: Effect
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "draw")
                .frame(width: 48, height: 48)
                .foregroundStyle(Color.blue)
                .symbolEffect(effect, options: .speed(0.25), isActive: drawHidden)
            Text(label)
                .font(.system(.caption))
        }
    }

    private func replacementSymbol<Effect: ContentTransitionSymbolEffect & SymbolEffect>(
        _ label: String,
        effect: Effect
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: replacementUsesDraw ? "draw" : "photo.fill")
                .frame(width: 48, height: 48)
                .foregroundStyle(Color.blue, Color.orange)
                .contentTransition(.symbolEffect(effect))
            Text(label)
                .font(.system(.caption))
        }
    }
}
