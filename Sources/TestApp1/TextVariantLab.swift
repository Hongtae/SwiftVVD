import Foundation
import VUI

private struct LabAttributedDateStyle: DiscreteFormatStyle {
    func format(_ value: Date) -> AttributedString {
        var first = AttributedString("Attributed")
        first.foregroundColor = .red
        first.font = .system(size: 18, weight: .bold)

        var second = AttributedString("time")
        second.foregroundColor = .blue
        return first + AttributedString(" ") + second
    }

    func discreteInput(before input: Date) -> Date? {
        input.addingTimeInterval(-1)
    }

    func discreteInput(after input: Date) -> Date? {
        input.addingTimeInterval(1)
    }

    func locale(_ locale: Locale) -> LabAttributedDateStyle { self }
}

struct TextVariantLabSheet: View {
    let onClose: () -> Void

    @State private var constrained = false
    @State private var liveDate = Date.now.addingTimeInterval(8.2)
    @State private var timerInterval: ClosedRange<Date> = {
        let start = Date.now
        return start...start.addingTimeInterval(3_661)
    }()
    @State private var timerPause: Date?
    private let sampleDate = Date.now.addingTimeInterval(93_784)

    var body: some View {
        VStack(spacing: 14) {
            Text("Text Variants")
                .font(.system(size: 22, weight: .semibold))

            Text("Relative time uses the probed multi-size route. Narrow mode should choose a shorter exact candidate instead of truncating.")
                .font(.system(.callout))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(constrained ? "Use Wide Proposal" : "Use Narrow Proposal") {
                constrained.toggle()
            }

            HStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("Fixed")
                        .font(.system(.headline))
                    Text("A size-fitting text sample")
                        .textVariant(.fixed)
                        .frame(width: constrained ? 120 : 220)
                        .border(.gray, width: 1)
                }

                VStack(spacing: 8) {
                    Text("Size Dependent")
                        .font(.system(.headline))
                    Text("A size-fitting text sample")
                        .textVariant(.sizeDependent)
                        .frame(width: constrained ? 120 : 220)
                        .border(.blue, width: 1)
                }
            }

            HStack(spacing: 12) {
                Button("Reset Timer") {
                    let start = Date.now
                    timerInterval = start...start.addingTimeInterval(3_661)
                    timerPause = nil
                }
                Button(timerPause == nil ? "Pause Timer" : "Resume Timer") {
                    timerPause = timerPause == nil ? Date.now : nil
                }
                Text(
                    timerInterval: timerInterval,
                    pauseTime: timerPause,
                    countsDown: true,
                    showsHours: true
                )
                    .lineLimit(1)
                    .frame(width: 90)
                    .border(.orange, width: 1)
                Text(
                    timerInterval: timerInterval,
                    pauseTime: timerPause,
                    countsDown: false,
                    showsHours: false
                )
                    .lineLimit(1)
                    .frame(width: 90)
                    .border(.purple, width: 1)
            }

            HStack(spacing: 12) {
                Text("Attributed Runs")
                    .font(.system(.headline))
                Text(
                    TimeDataSource<Date>.currentDate,
                    format: LabAttributedDateStyle()
                )
                    .frame(width: 180)
                    .border(.gray, width: 1)
            }

            HStack(spacing: 12) {
                Button("Reset Live Relative") {
                    liveDate = Date.now.addingTimeInterval(8.2)
                }
                Text(liveDate, style: .relative)
                    .textVariant(.sizeDependent)
                    .lineLimit(1)
                    .frame(width: 100)
                    .border(.green, width: 1)
            }

            HStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("Relative Fixed")
                        .font(.system(.headline))
                    Text(sampleDate, style: .relative)
                        .textVariant(.fixed)
                        .lineLimit(1)
                        .frame(width: constrained ? 60 : 140)
                        .border(.gray, width: 1)
                }

                VStack(spacing: 8) {
                    Text("Relative Size Dependent")
                        .font(.system(.headline))
                    Text(sampleDate, style: .relative)
                        .textVariant(.sizeDependent)
                        .lineLimit(1)
                        .frame(width: constrained ? 60 : 140)
                        .border(.blue, width: 1)
                }
            }

            Text("The plain-string row remains a single candidate; relative time exercises candidate progression, filter-published links, and scheduled updates.")
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") {
                onClose()
            }
        }
        .padding(20)
        .frame(width: 620, height: 590)
    }
}
