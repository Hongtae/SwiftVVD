//
//  File: Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

final class _TextResourceResolutionState {
    private(set) var pendingVersion: Int?
    private var pendingTransaction = Transaction()
    private var preparedVersion: Int?

    func transaction(for version: Int, candidate: Transaction) -> Transaction {
        guard pendingVersion != version else {
            return pendingTransaction
        }
        pendingVersion = version
        pendingTransaction = candidate
        return candidate
    }

    func didResolve(version: Int) {
        guard pendingVersion == version else { return }
        pendingVersion = nil
        pendingTransaction = Transaction()
    }

    func requiresPreparation(version: Int) -> Bool {
        preparedVersion != version
    }

    func didPrepare(version: Int) {
        preparedVersion = version
    }
}

// TextAlignment: horizontal alignment for multi-line text.
public enum TextAlignment: Hashable, CaseIterable {
    case leading
    case center
    case trailing
}

private struct MultilineTextAlignmentKey: EnvironmentKey {
    static var defaultValue: TextAlignment { .leading }
}

extension EnvironmentValues {
    public var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }
}

extension View {
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }
}

protocol TextResolutionContext {
    var environment: EnvironmentValues { get set }
    var sceneResources: SceneResources { get }
    var contentScaleFactor: CGFloat { get }

    func resolveTextAttachment(_ image: Image) -> ImageDrawing?
}

extension TextResolutionContext {
    /// Resolves the independent missing-attribute font in logical points.
    func defaultTextLineMetrics() -> FontLineMetrics? {
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let resource = Font.system(size: 12).platformFont(in: environment.fontResolutionContext)
        let font = Font(typefaceProvider: resource.provider)
        guard let face = font.typeface(forContext: sceneResources, dpi: UInt32(defaultDPI)),
              let metrics = resource.resolvedMetrics(for: face, scaleFactor: 1) else { return nil }
        return FontLineMetrics(metrics: metrics, pointSize: resource.pointSize,
            isTextStyle: false, scale: contentScaleFactor)
    }

    var displayScale: CGFloat {
        environment.displayScale
    }

    var contentScaleFactor: CGFloat {
        environment._contentScaleFactor
    }
}

extension GraphicsContext: TextResolutionContext {
    func resolveTextAttachment(_ image: Image) -> ImageDrawing? {
        resolveImageDrawing(image)
    }
}

struct GraphTextResolutionContext: TextResolutionContext {
    var environment: EnvironmentValues
    let sceneResources: SceneResources

    func resolveTextAttachment(_ image: Image) -> ImageDrawing? {
        var resolved: ImageDrawing
        if let symbol = image.provider.makeVectorSymbol() {
            resolved = ImageDrawing(
                symbol: symbol.applyingEffectiveFontMetrics(in: environment)
            )
        } else if let svg = image.provider.makeSVG() {
            resolved = ImageDrawing(svg: svg)
        } else {
            return nil
        }
        resolved.applyResizingProvider(image.provider)
        return resolved
    }
}

class AnyTextStorage: CustomDebugStringConvertible {
    var debugDescription: String {
        let typeName = String(describing: type(of: self))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let text = resolveText(in: EnvironmentValues())
        return "<\(typeName): \(pointer)>: \(String(reflecting: text))"
    }

    func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        fatalError("This method should be overridden by subclasses.")
    }
    func resolveText(in environment: EnvironmentValues) -> String {
        fatalError("This method should be overridden by subclasses.")
    }
    func resolveText(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> String {
        resolveText(in: environment)
    }
    func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext,
        referenceDate: Date
    ) -> ResolvedTextSource? {
        resolve(style: style, properties: &properties, text: &text, options: options, context: context)
    }
    func resolveTransitionText(in environment: EnvironmentValues) -> String? {
        resolveText(in: environment)
    }
    func sizeVariantTexts(in environment: EnvironmentValues) -> [(TextSizeVariant, String)]? {
        nil
    }
    func sizeVariantTexts(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> [(TextSizeVariant, String)]? {
        sizeVariantTexts(in: environment)
    }
    func nextUpdateDelay(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> TimeInterval? {
        nil
    }
    func needsDynamicRenderingInArchive(in environment: EnvironmentValues) -> Bool {
        false
    }
    func requiresBackendResolution(in environment: EnvironmentValues) -> Bool {
        false
    }
    func contentHash(
        into hasher: inout Hasher,
        environment: EnvironmentValues,
        referenceDate: Date
    ) {
        hasher.combine(resolveText(in: environment, referenceDate: referenceDate))
    }
    func isEqual(to other: AnyTextStorage) -> Bool {
        self === other
    }
    func isStyled(options: Text.ResolveOptions) -> Bool {
        fatalError("This method should be overridden by subclasses.")
    }
    /// Whether root resolution may inherit the environment's typesetting language.
    func allowsTypesettingLanguage() -> Bool {
        false
    }
}

class AnyTextModifier {
    func modify(style: inout Text.Style) {
        preconditionFailure("Abstract text modifier")
    }

    func isEqual(to other: AnyTextModifier) -> Bool {
        self === other
    }

    func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    func isStyled(options: Text.ResolveOptions) -> Bool {
        true
    }
}

private func _dynamicArchiveStorage(
    for storage: NSAttributedString,
    enabled: Bool
) -> NSAttributedString? {
    guard enabled else { return nil }
    let dynamicStorage = NSMutableAttributedString(attributedString: storage)
    if dynamicStorage.length > 0 {
        dynamicStorage.addAttribute(
            .updateSchedule,
            value: true,
            range: NSRange(location: 0, length: dynamicStorage.length)
        )
    }
    return dynamicStorage
}

private class AnyFormatStyleBox {
    func resolve(
        locale: Locale,
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        fatalError("This method should be overridden by subclasses.")
    }

    func resolveText(locale: Locale) -> String {
        fatalError("This method should be overridden by subclasses.")
    }

    func isEqual(to other: AnyFormatStyleBox) -> Bool {
        false
    }
}

private final class FormatStyleBox<Style>: AnyFormatStyleBox
where Style: FormatStyle, Style.FormatInput: Equatable {
    let input: Style.FormatInput
    let format: Style

    init(input: Style.FormatInput, format: Style) {
        self.input = input
        self.format = format
    }

    override func resolve(
        locale: Locale,
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        let output = format.locale(locale).format(input)
        if let string = output as? String {
            return style.resolve(string, context: context, properties: &properties, text: &text, options: options)
        }
        if let attributed = output as? AttributedString {
            return _resolvedAttributedText(
                attributed,
                style: style, properties: &properties, text: &text, options: options,
                context: context
            )
        }
        return .init(
            runs: [],
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    override func resolveText(locale: Locale) -> String {
        let output = format.locale(locale).format(input)
        if let string = output as? String { return string }
        if let attributed = output as? AttributedString {
            return String(attributed.characters)
        }
        return String(describing: output)
    }

    override func isEqual(to other: AnyFormatStyleBox) -> Bool {
        guard let other = other as? FormatStyleBox<Style> else {
            return false
        }
        return input == other.input && format == other.format
    }
}

private final class FormatStyleStorage: AnyTextStorage {
    let storage: AnyFormatStyleBox

    init<Style>(input: Style.FormatInput, format: Style)
    where Style: FormatStyle, Style.FormatInput: Equatable {
        self.storage = FormatStyleBox(input: input, format: format)
    }

    override func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        storage.resolve(
            locale: context.environment.locale,
            style: style, properties: &properties, text: &text, options: options,
            context: context
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        storage.resolveText(locale: environment.locale)
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        guard let other = other as? FormatStyleStorage else { return false }
        return storage.isEqual(to: other.storage)
    }

    override func isStyled(options: Text.ResolveOptions) -> Bool {
        // General format-style storage is classified structurally. Formatting
        // and inspection of the produced value happen later during resolution.
        false
    }
}

private final class LocalizedStringResourceStorage: AnyTextStorage {
    let resource: LocalizedStringResource

    init(_ resource: LocalizedStringResource) {
        self.resource = resource
    }

    override func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        _resolvedAttributedText(
            resource.resolve(in: context.environment),
            style: style, properties: &properties, text: &text, options: options,
            context: context
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        String(resource.resolve(in: environment).characters)
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        guard let other = other as? LocalizedStringResourceStorage else {
            return false
        }
        return resource == other.resource
    }

    override func isStyled(options: Text.ResolveOptions) -> Bool {
        AttributedString(localized: resource).isStyled
    }
}

private final class DateTextStorage: AnyTextStorage {
    enum Storage: Equatable {
        case interval(interval: DateInterval)
    }

    let storage: Storage

    init(_ storage: Storage) {
        self.storage = storage
    }

    override func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        style.resolve(resolveText(in: context.environment), context: context, properties: &properties, text: &text, options: options)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        switch storage {
        case let .interval(interval):
            format(interval: interval, environment: environment)
        }
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        guard let other = other as? DateTextStorage else { return false }
        return storage == other.storage
    }

    override func isStyled(options: Text.ResolveOptions) -> Bool {
        false
    }

    private func format(
        interval: DateInterval,
        environment: EnvironmentValues
    ) -> String {
        var calendar = environment.calendar
        calendar.timeZone = environment.timeZone

        let formatter = DateFormatter()
        formatter.locale = environment.locale
        formatter.calendar = calendar
        formatter.timeZone = environment.timeZone

        let day = calendar.dateComponents(
            [.day],
            from: interval.start,
            to: interval.end
        ).day
        if day != 0 {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: interval.start) +
                " – " + formatter.string(from: interval.end)
        }

        formatter.setLocalizedDateFormatFromTemplate("jm")
        var start = formatter.string(from: interval.start)
        let end = formatter.string(from: interval.end)
        let startHour = calendar.component(.hour, from: interval.start)
        let endHour = calendar.component(.hour, from: interval.end)
        // Foundation exposes different nullability for these symbols by platform.
        let startDesignatorSymbol: String? = (
            startHour < 12 ? formatter.amSymbol : formatter.pmSymbol
        )
        let endDesignatorSymbol: String? = (
            endHour < 12 ? formatter.amSymbol : formatter.pmSymbol
        )
        let startDesignator = startDesignatorSymbol ?? ""
        let endDesignator = endDesignatorSymbol ?? ""
        if !startDesignator.isEmpty,
           startDesignator == endDesignator,
           let range = start.range(of: startDesignator) {
            start.removeSubrange(range)
            start = start.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return start + "–" + end
    }
}

private protocol _TimeDataFormattingSource: Equatable {
    associatedtype Value

    func value(referenceDate: Date) -> Value
    func date(for value: Value) -> Date?
    var pausesUpdates: Bool { get }
}

private extension _TimeDataFormattingSource {
    var pausesUpdates: Bool { false }
}

private struct _DateTimeDataSourceStorage: _TimeDataFormattingSource {
    var date: Date

    func value(referenceDate: Date) -> Date {
        date
    }

    func date(for value: Date) -> Date? { value }
}

private struct _TimerIntervalTimeDataSourceStorage: _TimeDataFormattingSource {
    enum Storage: Equatable {
        case identity
        case identityWithPause(Date)
    }

    var storage: Storage

    var pausesUpdates: Bool {
        if case .identityWithPause = storage { return true }
        return false
    }

    func value(referenceDate: Date) -> Date {
        switch storage {
        case .identity:
            referenceDate
        case .identityWithPause(let pauseDate):
            pauseDate
        }
    }

    func date(for value: Date) -> Date? { value }
}

private struct _PublicTimeDataSourceStorage<Value>: _TimeDataFormattingSource {
    var source: TimeDataSource<Value>

    func value(referenceDate: Date) -> Value {
        source.box.value(for: referenceDate)
    }

    func date(for value: Value) -> Date? {
        source.box.date(for: value)
    }

    static func == (
        lhs: _PublicTimeDataSourceStorage<Value>,
        rhs: _PublicTimeDataSourceStorage<Value>
    ) -> Bool {
        lhs.source.box.identity == rhs.source.box.identity
    }
}

private protocol _TimeDataFormat: Equatable {
    associatedtype Input
    associatedtype Output: Equatable & Hashable

    func format(
        _ input: Input,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle,
        referenceDate: Date,
        locale: Locale
    ) -> Output
    func resolvedText(
        _ output: Output,
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource?
    func plainText(_ output: Output) -> String
    func nextUpdateDelay(
        for input: Input,
        referenceDate: Date,
        sourceDate: (Input) -> Date?
    ) -> TimeInterval
    var producesRelativeSizeVariants: Bool { get }
}

private extension _TimeDataFormat where Output == String {
    func resolvedText(
        _ output: String,
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        style.resolve(output, context: context, properties: &properties, text: &text, options: options)
    }

    func plainText(_ output: String) -> String { output }
}

private struct _DateStyleTimeDataFormat: _TimeDataFormat {
    var style: Text.DateStyle

    var producesRelativeSizeVariants: Bool {
        style == .relative
    }

    func format(
        _ date: Date,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle,
        referenceDate: Date,
        locale: Locale
    ) -> String {
        switch style.kind {
        case .time:
            date.formatted(.dateTime.hour().minute())
        case .date:
            date.formatted(.dateTime.year().month().day())
        case .relative:
            Duration.seconds(abs(date.timeIntervalSince(referenceDate))).formatted(
                .units(
                    allowed: [.days, .hours, .minutes, .seconds],
                    width: unitsStyle == .narrow ? .narrow : .abbreviated,
                    maximumUnitCount: 2
                ).locale(locale)
            )
        case .offset:
            offsetString(for: date, referenceDate: referenceDate, locale: locale)
        case .timer:
            timerString(for: date, referenceDate: referenceDate)
        }
    }

    func nextUpdateDelay(
        for date: Date,
        referenceDate: Date,
        sourceDate: (Date) -> Date?
    ) -> TimeInterval {
        let interval = date.timeIntervalSince(referenceDate)
        let magnitude = abs(interval)
        let unit: TimeInterval
        switch style.kind {
        case .relative:
            if magnitude >= 86_400 {
                unit = 3_600
            } else if magnitude >= 3_600 {
                unit = 60
            } else {
                unit = 1
            }
        case .offset:
            if magnitude >= 86_400 {
                unit = 86_400
            } else if magnitude >= 3_600 {
                unit = 3_600
            } else if magnitude >= 60 {
                unit = 60
            } else {
                unit = 1
            }
        case .timer:
            unit = 1
        case .time, .date:
            return .infinity
        }

        let remainder = magnitude.truncatingRemainder(dividingBy: unit)
        let delay = interval >= 0 ? remainder : unit - remainder
        return delay > 1e-6 ? delay : unit
    }

    private func offsetString(
        for date: Date,
        referenceDate: Date,
        locale: Locale
    ) -> String {
        let interval = date.timeIntervalSince(referenceDate)
        let value = Duration.seconds(abs(interval)).formatted(
            .units(
                allowed: [.days, .hours, .minutes, .seconds],
                width: .wide,
                maximumUnitCount: 1
            ).locale(locale)
        )
        return interval > 0 ? "−\(value)" : "+\(value)"
    }

    private func timerString(for date: Date, referenceDate: Date) -> String {
        Duration.seconds(abs(date.timeIntervalSince(referenceDate))).formatted(
            .time(pattern: .hourMinuteSecond)
        )
    }
}

private struct _TimerIntervalTimeDataFormat: _TimeDataFormat {
    var interval: ClosedRange<Date>
    var countsDown: Bool
    var showsHours: Bool

    var producesRelativeSizeVariants: Bool { false }

    func format(
        _ date: Date,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle,
        referenceDate: Date,
        locale: Locale
    ) -> String {
        let duration = max(interval.upperBound.timeIntervalSince(interval.lowerBound), 0)
        let elapsed = min(
            max(date.timeIntervalSince(interval.lowerBound), 0),
            duration
        )
        let seconds: Int
        if countsDown {
            seconds = Int(ceil(max(duration - elapsed, 0)))
        } else {
            seconds = Int(floor(elapsed))
        }
        return timerString(seconds: seconds)
    }

    func nextUpdateDelay(
        for date: Date,
        referenceDate: Date,
        sourceDate: (Date) -> Date?
    ) -> TimeInterval {
        guard date >= interval.lowerBound, date < interval.upperBound else {
            if date < interval.lowerBound {
                return interval.lowerBound.timeIntervalSince(date)
            }
            return .infinity
        }
        let elapsed = date.timeIntervalSince(interval.lowerBound)
        let remainder = elapsed.truncatingRemainder(dividingBy: 1)
        return remainder > 1e-6 ? 1 - remainder : 1
    }

    private func timerString(seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if showsHours, hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        let totalMinutes = seconds / 60
        return String(format: "%d:%02d", totalMinutes, remainingSeconds)
    }
}

private struct _DiscreteStringTimeDataFormat<Format>: _TimeDataFormat
where Format: DiscreteFormatStyle, Format.FormatOutput == String {
    var style: Format

    var producesRelativeSizeVariants: Bool { false }

    func format(
        _ input: Format.FormatInput,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle,
        referenceDate: Date,
        locale: Locale
    ) -> String {
        style.locale(locale).format(input)
    }

    func nextUpdateDelay(
        for input: Format.FormatInput,
        referenceDate: Date,
        sourceDate: (Format.FormatInput) -> Date?
    ) -> TimeInterval {
        guard let nextInput = style.discreteInput(after: input),
              let nextDate = sourceDate(nextInput) else {
            return .infinity
        }
        let delay = nextDate.timeIntervalSince(referenceDate)
        return delay > 1e-6 ? delay : .infinity
    }
}

private struct _DiscreteAttributedTimeDataFormat<Format>: _TimeDataFormat
where Format: DiscreteFormatStyle, Format.FormatOutput == AttributedString {
    var style: Format

    var producesRelativeSizeVariants: Bool { false }

    func format(
        _ input: Format.FormatInput,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle,
        referenceDate: Date,
        locale: Locale
    ) -> AttributedString {
        style.locale(locale).format(input)
    }

    func resolvedText(
        _ output: AttributedString,
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        _resolvedAttributedText(
            output,
            style: style, properties: &properties, text: &text, options: options,
            context: context
        )
    }

    func plainText(_ output: AttributedString) -> String {
        String(output.characters)
    }

    func nextUpdateDelay(
        for input: Format.FormatInput,
        referenceDate: Date,
        sourceDate: (Format.FormatInput) -> Date?
    ) -> TimeInterval {
        guard let nextInput = style.discreteInput(after: input),
              let nextDate = sourceDate(nextInput) else {
            return .infinity
        }
        let delay = nextDate.timeIntervalSince(referenceDate)
        return delay > 1e-6 ? delay : .infinity
    }
}

private final class TimeDataFormattingStorage<Source, Format>: AnyTextStorage
where Source: _TimeDataFormattingSource,
      Format: _TimeDataFormat,
      Source.Value == Format.Input {
    let source: Source
    let format: Format
    let reducedLuminanceBudget: Double?

    init(source: Source, format: Format, reducedLuminanceBudget: Double? = nil) {
        self.source = source
        self.format = format
        self.reducedLuminanceBudget = reducedLuminanceBudget
    }

    override func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        resolve(style: style, properties: &properties, text: &text, options: options, context: context, referenceDate: Date())
    }

    override func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext,
        referenceDate: Date
    ) -> ResolvedTextSource? {
        let value = source.value(referenceDate: referenceDate)
        let output = format.format(
            value,
            unitsStyle: .wide,
            referenceDate: referenceDate,
            locale: context.environment.locale
        )
        return format.resolvedText(output, style: style, properties: &properties, text: &text, options: options, context: context)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        resolveText(in: environment, referenceDate: Date())
    }

    override func resolveText(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> String {
        format.plainText(format.format(
            source.value(referenceDate: referenceDate),
            unitsStyle: .wide,
            referenceDate: referenceDate,
            locale: environment.locale
        ))
    }

    override func sizeVariantTexts(
        in environment: EnvironmentValues
    ) -> [(TextSizeVariant, String)]? {
        sizeVariantTexts(in: environment, referenceDate: Date())
    }

    override func sizeVariantTexts(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> [(TextSizeVariant, String)]? {
        guard format.producesRelativeSizeVariants else { return nil }
        let value = source.value(referenceDate: referenceDate)
        let regular = format.plainText(format.format(
            value,
            unitsStyle: .wide,
            referenceDate: referenceDate,
            locale: environment.locale
        ))
        let compact = format.plainText(format.format(
            value,
            unitsStyle: .narrow,
            referenceDate: referenceDate,
            locale: environment.locale
        ))
        guard regular != compact else {
            return [(.regular, regular)]
        }
        return [(.regular, regular), (.compact, compact)]
    }

    override func nextUpdateDelay(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> TimeInterval? {
        guard !source.pausesUpdates else { return nil }
        let value = source.value(referenceDate: referenceDate)
        let delay = format.nextUpdateDelay(
            for: value,
            referenceDate: referenceDate,
            sourceDate: source.date(for:)
        )
        return delay.isFinite ? delay : nil
    }

    override func needsDynamicRenderingInArchive(in environment: EnvironmentValues) -> Bool {
        true
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        guard let other = other as? TimeDataFormattingStorage<Source, Format> else {
            return false
        }
        return source == other.source &&
            format == other.format &&
            reducedLuminanceBudget == other.reducedLuminanceBudget
    }

    override func isStyled(options: Text.ResolveOptions) -> Bool {
        // Live time storage differs from general format-style storage: its
        // declared output family determines whether it carries rich text.
        Format.Output.self == AttributedString.self
    }

    override func contentHash(
        into hasher: inout Hasher,
        environment: EnvironmentValues,
        referenceDate: Date
    ) {
        hasher.combine(format.format(
            source.value(referenceDate: referenceDate),
            unitsStyle: .wide,
            referenceDate: referenceDate,
            locale: environment.locale
        ))
    }
}

class LocalizedTextStorage: AnyTextStorage {
    let key: LocalizedStringKey
    let table: String?
    let bundle: Bundle?
    init(key: LocalizedStringKey, table: String?, bundle: Bundle?) {
        self.key = key
        self.table = table
        self.bundle = bundle
    }

    override func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        let segments = resolve(in: context.environment)
        var runs: [ResolvedTextSource.Run] = []
        for segment in segments {
            switch segment {
            case let .attributedString(value):
                runs.append(contentsOf: _resolvedAttributedText(
                    value,
                    style: style, properties: &properties, text: &text, options: options,
                    context: context
                ).runs)
            case let .text(child):
                guard let resolved = child._resolve(
                    context: context, referenceDate: Date(),
                    style: style, properties: &properties, text: &text, options: options
                ) else {
                    return nil
                }
                runs.append(contentsOf: resolved.runs)
            }
        }
        return .init(
            runs: runs,
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        resolve(in: environment).reduce(into: String()) { result, segment in
            switch segment {
            case let .attributedString(value):
                result.append(contentsOf: value.characters)
            case let .text(text):
                result.append(text._resolveText(in: environment))
            }
        }
    }

    override func requiresBackendResolution(
        in environment: EnvironmentValues
    ) -> Bool {
        resolve(in: environment).contains { segment in
            guard case let .text(text) = segment else { return false }
            return text._requiresBackendResolution(in: environment)
        }
    }

    private func resolve(in environment: EnvironmentValues) -> [LocalizedStringKey.ResolvedSegment] {
        let selection = localizedBundle(for: environment.locale)
        return key.resolve(
            table: table,
            bundle: selection.bundle,
            environment: environment,
            fallbackLanguageIdentifier: selection.fallbackLanguageIdentifier
        )
    }

    private func localizedBundle(for locale: Locale) -> (bundle: Bundle, fallbackLanguageIdentifier: String?) {
        let rootBundle = bundle ?? .main
#if !canImport(Darwin)
        // The compatibility resolver owns locale selection and language metadata.
        return (rootBundle, nil)
#else
        let localization = LocalizationResolver.localizationCandidates(
            from: rootBundle.localizations, for: locale
        ).first
        let selectedBundle: Bundle
        if let localization,
           let path = rootBundle.path(forResource: localization, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            selectedBundle = localizedBundle
        } else {
            selectedBundle = rootBundle
        }
        // Select the localization before looking for a table. A missing table
        // must not switch the text to another language's translated value.
        let tableName = table ?? "Localizable"
        let hasTable = selectedBundle.url(forResource: tableName, withExtension: "strings") != nil
            || selectedBundle.url(forResource: tableName, withExtension: "stringsdict") != nil
        return (selectedBundle, hasTable ? nil : rootBundle.developmentLocalization)
#endif
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.key == other.key && self.table == other.table && self.bundle == other.bundle
        }
        return false
    }

    override func isStyled(options: Text.ResolveOptions) -> Bool {
        key.isStyled
    }
}

class ConcatenatedTextStorage: AnyTextStorage {
    let first: Text
    let second: Text
    init(first: Text, second: Text) {
        self.first = first
        self.second = second
    }

    override func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        guard let first = first._resolve(context: context, referenceDate: Date(), style: style, properties: &properties, text: &text, options: options),
              let second = second._resolve(context: context, referenceDate: Date(), style: style, properties: &properties, text: &text, options: options) else {
            return nil
        }
        return .init(
            runs: first.runs + second.runs,
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        first._resolveText(in: environment) + second._resolveText(in: environment)
    }

    override func resolveTransitionText(in environment: EnvironmentValues) -> String? {
        guard let first = first._resolveTransitionText(in: environment),
              let second = second._resolveTransitionText(in: environment) else {
            return nil
        }
        return first + second
    }

    override func requiresBackendResolution(
        in environment: EnvironmentValues
    ) -> Bool {
        first._requiresBackendResolution(in: environment) ||
            second._requiresBackendResolution(in: environment)
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.first == other.first && self.second == other.second
        }
        return false
    }

    override func isStyled(options: Text.ResolveOptions) -> Bool {
        first.isStyled(options: options) || second.isStyled(options: options)
    }

    override func allowsTypesettingLanguage() -> Bool {
        first.allowsTypesettingLanguage() && second.allowsTypesettingLanguage()
    }
}

class AttachmentTextStorage: AnyTextStorage {
    let image: Image
    init(_ image: Image) {
        self.image = image
    }

    override func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        var imageContext = context
        imageContext.environment = context.environment.untrackedCopy()
        imageContext.environment.font = style.baseFont.resolve(in: context.environment, includeDefaultAttributes: true)
        imageContext.environment.fontModifiers += style.fontModifiers
        guard let image = imageContext.resolveTextAttachment(self.image) else {
            return nil
        }
        let attributes = style.nsAttributes(in: context.environment, properties: &properties, options: options)
        let typefaces = style.typefaces(attributes: attributes, context: context)
        properties.registerCustomAttachment(at: text.utf16.count)
        text += "\u{fffc}"
        return .init(
            runs: [.attachment(typefaces, image)],
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        String()
    }

    override func resolveTransitionText(in environment: EnvironmentValues) -> String? {
        nil
    }

    override func requiresBackendResolution(
        in environment: EnvironmentValues
    ) -> Bool {
        image.provider.requiresBackendResolution
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.image == other.image
        }
        return false
    }

    override func isStyled(options: Text.ResolveOptions) -> Bool {
        true
    }
}

public struct Text: Equatable, _AGTypeDescriptorEquatable {
    enum Storage: Equatable {
        case verbatim(String)
        case anyTextStorage(AnyTextStorage)

        static func == (lhs: Text.Storage, rhs: Text.Storage) -> Bool {
            if case let .verbatim(s1) = lhs, case let .verbatim(s2) = rhs {
                return s1 == s2
            }
            if case let .anyTextStorage(s1) = lhs, case let .anyTextStorage(s2) = rhs {
                return s1.isEqual(to: s2)
            }
            return false
        }

        func isStyled(options: ResolveOptions) -> Bool {
            guard case let .anyTextStorage(storage) = self else { return false }
            return storage.isStyled(options: options)
        }

        func allowsTypesettingLanguage() -> Bool {
            switch self {
            case .verbatim: true
            case let .anyTextStorage(storage): storage.allowsTypesettingLanguage()
            }
        }
    }

    struct ResolveOptions: OptionSet {
        let rawValue: Int

        static let includeAccessibility = ResolveOptions(rawValue: 0x1)
        static let foregroundKeyColor = ResolveOptions(rawValue: 0x2)
        static let writeAuxiliaryMetadata = ResolveOptions(rawValue: 0x4)
        static let includeTransitions = ResolveOptions(rawValue: 0x8)
        static let disableLinkColor = ResolveOptions(rawValue: 0x10)
        static let allowsKeyColors = ResolveOptions(rawValue: 0x20)
        static let allowsTextSuffix = ResolveOptions(rawValue: 0x40)
        static let includeSupportForRepeatedResolution = ResolveOptions(
            rawValue: 0x80
        )
        static let ignoreMarkdown = ResolveOptions(rawValue: 0x100)
    }

    var storage: Storage

    public enum Case: Hashable {
        case lowercase
        case uppercase
    }

    public struct LineStyle: Hashable, Sendable {
        public struct Pattern: Equatable, Sendable {
            let rawValue: Int

            public static let solid = Pattern(rawValue: 0)
            public static let dot = Pattern(rawValue: 0x100)
            public static let dash = Pattern(rawValue: 0x200)
            public static let dashDot = Pattern(rawValue: 0x300)
            public static let dashDotDot = Pattern(rawValue: 0x400)
        }

        let nsUnderlineStyleValue: Int
        let color: Color?
        var pattern: Pattern {
            Pattern(rawValue: nsUnderlineStyleValue & 0xF00)
        }

        public init(pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) {
            self.nsUnderlineStyleValue = 1 | pattern.rawValue
            self.color = color
        }

        public static let single = LineStyle()
    }

    public struct DateStyle: Equatable, Codable, Sendable {
        fileprivate enum Storage: UInt8, Codable, Sendable {
            case time
            case date
            case relative
            case offset
            case timer
        }

        private struct UnitsConfiguration: Equatable, Codable, @unchecked Sendable {
            enum Style: UInt8, Codable, Sendable {
                case short
                case brief
                case full
            }

            var _units: CodableRawRepresentable<NSCalendar.Unit>
            var style: Style
        }

        private var storage: Storage
        private var unitConfiguration: UnitsConfiguration?

        fileprivate var kind: Storage {
            storage
        }

        private init(_ storage: Storage) {
            self.storage = storage
            self.unitConfiguration = nil
        }

        public static let time = DateStyle(.time)
        public static let date = DateStyle(.date)
        public static let relative = DateStyle(.relative)
        public static let offset = DateStyle(.offset)
        public static let timer = DateStyle(.timer)

        private enum CodingKeys: String, CodingKey {
            case storage
            case unitConfiguration
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            storage = try container.decode(Storage.self, forKey: .storage)
            unitConfiguration = try container.decodeIfPresent(
                UnitsConfiguration.self,
                forKey: .unitConfiguration
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(storage, forKey: .storage)
            try container.encodeIfPresent(unitConfiguration, forKey: .unitConfiguration)
        }
    }

    enum Modifier: Equatable {
        case color(Color?)
        case font(Font?)
        case italic
        case weight(Font.Weight?)
        case kerning(CGFloat)
        case tracking(CGFloat)
        case baseline(CGFloat)
        case rounded
        case anyTextModifier(AnyTextModifier)

        static func == (lhs: Modifier, rhs: Modifier) -> Bool {
            switch (lhs, rhs) {
            case let (.color(lhs), .color(rhs)):
                lhs == rhs
            case let (.font(lhs), .font(rhs)):
                lhs == rhs
            case (.italic, .italic), (.rounded, .rounded):
                true
            case let (.weight(lhs), .weight(rhs)):
                lhs == rhs
            case let (.kerning(lhs), .kerning(rhs)),
                 let (.tracking(lhs), .tracking(rhs)),
                 let (.baseline(lhs), .baseline(rhs)):
                lhs == rhs
            case let (.anyTextModifier(lhs), .anyTextModifier(rhs)):
                lhs.isEqual(to: rhs)
            default:
                false
            }
        }

        func hashResolution(into hasher: inout Hasher) {
            switch self {
            case let .color(value):
                hasher.combine(0)
                hasher.combine(value)
            case let .font(value):
                hasher.combine(1)
                hasher.combine(value)
            case .italic:
                hasher.combine(2)
            case let .weight(value):
                hasher.combine(3)
                hasher.combine(value)
            case let .kerning(value):
                hasher.combine(4)
                hasher.combine(value)
            case let .tracking(value):
                hasher.combine(5)
                hasher.combine(value)
            case let .baseline(value):
                hasher.combine(6)
                hasher.combine(value)
            case .rounded:
                hasher.combine(7)
            case let .anyTextModifier(value):
                hasher.combine(8)
                value.hashResolution(into: &hasher)
            }
        }

        func isStyled(options: ResolveOptions) -> Bool {
            // Every ordinary modifier is a style marker, including optional or
            // Boolean payloads that are visually inactive. Boxed modifiers own
            // their option-dependent classification.
            guard case let .anyTextModifier(modifier) = self else { return true }
            return modifier.isStyled(options: options)
        }
    }

    var modifiers: [Modifier]

    func isStyled(options: ResolveOptions = []) -> Bool {
        storage.isStyled(options: options) || modifiers.contains {
            $0.isStyled(options: options)
        }
    }

    func allowsTypesettingLanguage() -> Bool {
        storage.allowsTypesettingLanguage()
    }

    func assertUnstyled(
        _ context: String,
        options: ResolveOptions = []
    ) {
        // This advisory does not interrupt construction or resolution. Report
        // every invalid use so attaching or detaching a debugger cannot change
        // whether the issue is visible.
        guard isStyled(options: options) else {
            return
        }
        Log.warning("Only unstyled text can be used with \(context)")
    }

    public init(
        _ key: LocalizedStringKey,
        tableName: String? = nil,
        bundle: Bundle? = nil,
        comment: StaticString? = nil
    ) {
        self.storage = .anyTextStorage(
            LocalizedTextStorage(key: key, table: tableName, bundle: bundle)
        )
        self.modifiers = []
    }

    @_disfavoredOverload
    public init<S>(_ content: S) where S: StringProtocol {
        self.storage = .verbatim(String(content))
        self.modifiers = []
    }

    public init(verbatim content: String) {
        self.storage = .verbatim(content)
        self.modifiers = []
    }

    @_disfavoredOverload
    public init(_ attributedContent: AttributedString) {
        self.storage = .anyTextStorage(AttributedStringTextStorage(attributedContent))
        self.modifiers = []
    }

    public init(_ image: Image) {
        self.storage = .anyTextStorage(AttachmentTextStorage(image))
        self.modifiers = []
    }

    public init<F>(_ input: F.FormatInput, format: F)
    where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == String {
        self.storage = .anyTextStorage(
            FormatStyleStorage(input: input, format: format)
        )
        self.modifiers = []
    }

    public init<F>(_ input: F.FormatInput, format: F)
    where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == AttributedString {
        self.storage = .anyTextStorage(
            FormatStyleStorage(input: input, format: format)
        )
        self.modifiers = []
    }

    @_disfavoredOverload
    public init(_ resource: LocalizedStringResource) {
        self.storage = .anyTextStorage(LocalizedStringResourceStorage(resource))
        self.modifiers = []
    }

    public init(_ date: Date, style: DateStyle) {
        switch style.kind {
        case .time:
            self.storage = .anyTextStorage(
                FormatStyleStorage(
                    input: date,
                    format: Date.FormatStyle.dateTime.hour().minute()
                )
            )
        case .date:
            self.storage = .anyTextStorage(
                FormatStyleStorage(
                    input: date,
                    format: Date.FormatStyle.dateTime.year().month().day()
                )
            )
        case .relative, .offset, .timer:
            self.storage = .anyTextStorage(
                TimeDataFormattingStorage(
                    source: _DateTimeDataSourceStorage(date: date),
                    format: _DateStyleTimeDataFormat(style: style)
                )
            )
        }
        self.modifiers = []
    }

    public init(_ dates: ClosedRange<Date>) {
        self.storage = .anyTextStorage(DateTextStorage(
            .interval(interval: DateInterval(
                start: dates.lowerBound,
                end: dates.upperBound
            ))
        ))
        self.modifiers = []
    }

    public init(_ interval: DateInterval) {
        self.storage = .anyTextStorage(DateTextStorage(
            .interval(interval: interval)
        ))
        self.modifiers = []
    }

    public init(
        timerInterval: ClosedRange<Date>,
        pauseTime: Date? = nil,
        countsDown: Bool = true,
        showsHours: Bool = true
    ) {
        let sourceStorage: _TimerIntervalTimeDataSourceStorage.Storage
        if let pauseTime {
            let resolvedPause: Date
            if countsDown {
                resolvedPause = timerInterval.lowerBound.addingTimeInterval(
                    timerInterval.upperBound.timeIntervalSince(pauseTime)
                )
            } else {
                resolvedPause = pauseTime
            }
            sourceStorage = .identityWithPause(resolvedPause)
        } else {
            sourceStorage = .identity
        }
        self.storage = .anyTextStorage(
            TimeDataFormattingStorage(
                source: _TimerIntervalTimeDataSourceStorage(storage: sourceStorage),
                format: _TimerIntervalTimeDataFormat(
                    interval: timerInterval,
                    countsDown: countsDown,
                    showsHours: showsHours
                ),
                reducedLuminanceBudget: 60
            )
        )
        self.modifiers = []
    }

    @_disfavoredOverload
    public init<Value, Format>(
        _ source: TimeDataSource<Value>,
        format: Format
    ) where Value == Format.FormatInput,
            Format: DiscreteFormatStyle,
            Format.FormatOutput == String {
        self.storage = .anyTextStorage(
            TimeDataFormattingStorage(
                source: _PublicTimeDataSourceStorage(source: source),
                format: _DiscreteStringTimeDataFormat(style: format)
            )
        )
        self.modifiers = []
    }

    public init<Value, Format>(
        _ source: TimeDataSource<Value>,
        format: Format
    ) where Value == Format.FormatInput,
            Format: DiscreteFormatStyle,
            Format.FormatOutput == AttributedString {
        self.storage = .anyTextStorage(
            TimeDataFormattingStorage(
                source: _PublicTimeDataSourceStorage(source: source),
                format: _DiscreteAttributedTimeDataFormat(style: format)
            )
        )
        self.modifiers = []
    }

    init(storage: Storage, modifiers: [Modifier]) {
        self.storage = storage
        self.modifiers = modifiers
    }

    public func _resolveText(in environment: EnvironmentValues) -> String {
        _resolveText(in: environment, referenceDate: Date())
    }

    func _resolveText(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> String {
        if case let .verbatim(text) = self.storage {
            return text
        }
        if case let .anyTextStorage(storage) = self.storage {
            return storage.resolveText(in: environment, referenceDate: referenceDate)
        }
        return String()
    }

    func _resolveTransitionText(in environment: EnvironmentValues) -> String? {
        if case let .verbatim(text) = self.storage {
            return text
        }
        if case let .anyTextStorage(storage) = self.storage {
            return storage.resolveTransitionText(in: environment)
        }
        return nil
    }

    func _resolve(context: GraphicsContext) -> ResolvedTextSource {
        _resolve(context: context, referenceDate: Date())
    }

    func _resolve(
        context: GraphicsContext,
        referenceDate: Date
    ) -> ResolvedTextSource {
        guard let resolved = _resolve(
            context: context as any TextResolutionContext,
            referenceDate: referenceDate
        ) else {
            fatalError("A graphics text context must resolve every attachment.")
        }
        return resolved
    }

    func _resolve(
        context: any TextResolutionContext,
        referenceDate: Date,
        options: ResolveOptions = .includeTransitions
    ) -> ResolvedTextSource? {
        var properties = ResolvedProperties()
        if options.contains([.allowsKeyColors, .allowsTextSuffix]) {
            properties.styles = context.environment[TextSuffixKey.self].styles
            if !properties.styles.isEmpty { properties.features.insert(.keyColor) }
        }
        var string = String()
        var style = Style()
        style.typesettingConfiguration = context.environment.typesettingConfiguration
        if !allowsTypesettingLanguage() {
            // Localized runs supply their own fallback language. Keep the
            // environment's line-height ratio across this root-only reset.
            style.typesettingConfiguration.language = .automatic
        }
        guard var resolved = _resolve(context: context, referenceDate: referenceDate,
                                      style: style, properties: &properties, text: &string, options: options) else { return nil }
        if TextLineBreak.requiresDefaultFont(in: string) {
            resolved.defaultLineMetrics = context.defaultTextLineMetrics()
        }
        properties.markParagraphBoundary(at: string.utf16.count, in: string, environment: context.environment)
        if options.contains(.allowsTextSuffix) {
            let suffix = context.environment[TextSuffixKey.self]
            if case let .alwaysVisible(line, _) = suffix {
                let attachment = ConcreteCustomTextAttachment(LineAttachment(line: line, bounds: line.typographicBounds))
                resolved = resolved.appending(attachment, context: context)
                properties.registerCustomAttachment(at: string.utf16.count)
            }
            properties.suffix = suffix
        }
        resolved.resolvedProperties = properties
        resolved.fontResolutionContext = GraphTextResolutionContext(
            environment: context.environment.untrackedCopy(), sceneResources: context.sceneResources)
        return resolved
    }

    func _resolve(context: any TextResolutionContext, referenceDate: Date,
                  style parentStyle: Style, properties: inout ResolvedProperties,
                  text: inout String, options: ResolveOptions = .includeTransitions) -> ResolvedTextSource? {
        var style = parentStyle
        for modifier in modifiers.reversed() { modifier.modify(style: &style) }
        switch storage {
        case let .verbatim(string):
            return style.resolve(string, context: context, properties: &properties, text: &text, options: options)
        case let .anyTextStorage(storage):
            return storage.resolve(style: style, properties: &properties, text: &text, options: options,
                                   context: context, referenceDate: referenceDate)
        }
    }

    func _sizeVariantTexts(in environment: EnvironmentValues) -> [(TextSizeVariant, String)]? {
        _sizeVariantTexts(in: environment, referenceDate: Date())
    }

    func _sizeVariantTexts(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> [(TextSizeVariant, String)]? {
        guard case let .anyTextStorage(storage) = storage else { return nil }
        return storage.sizeVariantTexts(in: environment, referenceDate: referenceDate)
    }

    func _nextUpdateDelay(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> TimeInterval? {
        guard case let .anyTextStorage(storage) = storage else { return nil }
        return storage.nextUpdateDelay(in: environment, referenceDate: referenceDate)
    }

    func _needsDynamicRenderingInArchive(in environment: EnvironmentValues) -> Bool {
        guard case let .anyTextStorage(storage) = storage else { return false }
        return storage.needsDynamicRenderingInArchive(in: environment)
    }

    func _requiresBackendResolution(in environment: EnvironmentValues) -> Bool {
        guard case let .anyTextStorage(storage) = storage else { return false }
        return storage.requiresBackendResolution(in: environment)
    }

    func _contentHash(
        into hasher: inout Hasher,
        environment: EnvironmentValues,
        referenceDate: Date
    ) {
        switch storage {
        case let .verbatim(text):
            hasher.combine(text)
        case let .anyTextStorage(storage):
            storage.contentHash(
                into: &hasher,
                environment: environment,
                referenceDate: referenceDate
            )
        }
    }

    func _resolutionVersion(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> Int {
        var hasher = Hasher()
        _contentHash(
            into: &hasher,
            environment: environment,
            referenceDate: referenceDate
        )
        hasher.combine(environment.effectiveFont.hashValue)
        hasher.combine(environment.defaultFontRenderingMode)
        hasher.combine(environment.emojiFontPreset)
        hasher.combine(environment.resourceBundle?.bundleURL)
        hasher.combine(environment.displayScale)
        hasher.combine(environment._contentScaleFactor)
        hasher.combine(environment.fontModifiers)
        hasher.combine(environment.typesettingConfiguration)
        hasher.combine(environment.textScale)
        hasher.combine(environment.textJustification)
        hasher.combine(environment.paragraphTypesetting.storage)
        hasher.combine(environment.avoidsOrphans)
        hasher.combine(environment.textWritingDirection)
        hasher.combine(environment.textAlignmentStrategy)
        hasher.combine(environment.writingMode)
        hasher.combine(environment.layoutDirection)
        hasher.combine(environment.lineHeight)
        hasher.combine(environment.lineSpacing)
        hasher.combine(environment.lineHeightMultiple)
        hasher.combine(environment.maximumLineHeight)
        hasher.combine(environment.minimumLineHeight)
        hasher.combine(environment.hyphenationFactor)
        hasher.combine(environment.hyphenationDisabled)
        hasher.combine(environment.allowsTightening)
        hasher.combine(environment.bodyHeadOutdent)
        hasher.combine(environment.shouldRedactContent)
        for modifier in modifiers {
            modifier.hashResolution(into: &hasher)
        }
        customAttributes.hash(into: &hasher)
        return hasher.finalize()
    }

    func _resolveStyledText(
        context: any TextResolutionContext,
        referenceDate: Date,
        archiveOptions: ArchivedViewInput.Value,
        features: ResolvedProperties.Features,
        sizeFitting: Bool,
        options: ResolveOptions = .includeTransitions
    ) -> ResolvedStyledText? {
        guard let resolved = _resolve(
            context: context,
            referenceDate: referenceDate,
            options: options
        ) else {
            return nil
        }

        let environment = context.environment
        let layoutProperties = environment[TextLayoutProperties.Key.self]
        let transitionText = _resolveTransitionText(in: environment)
        let needsDynamicArchive = _needsDynamicRenderingInArchive(in: environment)
        let version = _resolutionVersion(
            in: environment,
            referenceDate: referenceDate
        )

        func makeStyledText(
            _ source: ResolvedTextSource,
            additionalFeatures: ResolvedProperties.Features = []
        ) -> ResolvedStyledText {
            var resolved = source
            resolved.shading = foregroundShading(in: environment)
            let attributedStorage = resolved.attributedStorage
            let resolvedString = _resolveText(
                in: environment,
                referenceDate: referenceDate
            )
            let storage: NSAttributedString
            if attributedStorage.length == 0 && !resolvedString.isEmpty {
                storage = NSAttributedString(string: resolvedString)
            } else {
                storage = attributedStorage
            }
            let features = features.union(resolved.resolvedFeatures).union(additionalFeatures)
            let managerFeatures: ResolvedProperties.Features = [
                .customRenderer, .useTextLayoutManager, .produceTextLayout, .checkInterpolationStrategy
            ]
            let suffix = source.resolvedProperties?.suffix ?? .none
            let attachments = source.resolvedProperties?.customAttachments ?? .init()
            let owner: ResolvedStyledText.Type = features.isDisjoint(with: managerFeatures) &&
                suffix == .none && attachments.isEmpty
                ? ResolvedStyledText.StringDrawing.self : ResolvedStyledText.TextLayoutManager.self
            return owner.init(
                storage: needsDynamicArchive
                    ? _dynamicArchiveStorage(
                        for: storage,
                        enabled: true
                    ) ?? storage
                    : storage,
                layoutProperties: layoutProperties,
                layoutMargins: source.resolvedProperties?.insets ?? EdgeInsets(),
                archiveOptions: archiveOptions,
                features: features,
                suffix: suffix,
                attachments: attachments,
                styles: source.resolvedProperties?.styles ?? [],
                transitions: source.resolvedProperties?.transitions ?? [],
                lineHeightMetrics: source.resolvedProperties?.lineHeightMetrics ?? .init(),
                resolvedText: resolved,
                version: version,
                transitionText: transitionText
            )
        }

        guard sizeFitting,
              let variants = _resolveSizeVariants(
                context: context,
                referenceDate: referenceDate,
                options: options
              ) else {
            return makeStyledText(resolved)
        }

        var styledVariants = variants.map { _, variant in
            makeStyledText(variant, additionalFeatures: .isUniqueSizeVariant)
        }
        if let terminal = variants.last?.1 {
            styledVariants.append(makeStyledText(terminal))
        }
        guard let first = styledVariants.first else {
            return makeStyledText(resolved)
        }
        first.setSizeVariantCandidates(styledVariants)
        return first
    }

    func _resolveSizeVariants(
        context: any TextResolutionContext,
        referenceDate: Date = Date(),
        options: ResolveOptions = .includeTransitions
    ) -> [(TextSizeVariant, ResolvedTextSource)]? {
        guard let variants = _sizeVariantTexts(
            in: context.environment,
            referenceDate: referenceDate
        ),
              variants.count > 1 else {
            return nil
        }

        return variants.compactMap { variant, string in
            var leaf = self
            leaf.storage = .verbatim(string)
            guard let resolved = leaf._resolve(context: context, referenceDate: referenceDate, options: options) else { return nil }
            return (variant, resolved)
        }
    }

}

final class BoldTextModifier: AnyTextModifier {
    override func modify(style: inout Text.Style) {
        if isActive { style.addFontModifier(.static(Font.BoldModifier.self)) }
        else { style.removeFontModifier(Font.BoldModifier.self) }
    }
    let isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? BoldTextModifier)?.isActive == isActive
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(BoldTextModifier.self))
        hasher.combine(isActive)
    }
}

final class ItalicTextModifier: AnyTextModifier {
    override func modify(style: inout Text.Style) {
        if isActive { style.addFontModifier(.static(Font.ItalicModifier.self)) }
        else { style.removeFontModifier(Font.ItalicModifier.self) }
    }
    let isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? ItalicTextModifier)?.isActive == isActive
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(ItalicTextModifier.self))
        hasher.combine(isActive)
    }
}

final class MonospacedTextModifier: AnyTextModifier {
    override func modify(style: inout Text.Style) {
        if isActive { style.addFontModifier(.static(Font.MonospacedModifier.self)) }
        else { style.removeFontModifier(Font.MonospacedModifier.self) }
    }
    let isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? MonospacedTextModifier)?.isActive == isActive
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(MonospacedTextModifier.self))
        hasher.combine(isActive)
    }
}

final class MonospacedDigitTextModifier: AnyTextModifier {
    override func modify(style: inout Text.Style) { style.addFontModifier(.static(Font.MonospacedDigitModifier.self)) }
    override func isEqual(to other: AnyTextModifier) -> Bool {
        other is MonospacedDigitTextModifier
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(MonospacedDigitTextModifier.self))
    }
}

/// Adds a font-provided stylistic set to the ordered text style.
final class StylisticAlternativeTextModifier: AnyTextModifier {
    let value: Font._StylisticAlternative

    init(value: Font._StylisticAlternative) {
        self.value = value
    }

    override func modify(style: inout Text.Style) {
        style.addFontModifier(.dynamic(Font.StylisticAlternativeModifier(alternative: value)))
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? StylisticAlternativeTextModifier)?.value == value
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(StylisticAlternativeTextModifier.self))
        hasher.combine(value)
    }
}

final class UnderlineTextModifier: AnyTextModifier {
    override func modify(style: inout Text.Style) { style.underline = lineStyle.map(Text.Style.LineStyle.explicit) ?? .default }
    let lineStyle: Text.LineStyle?

    init(lineStyle: Text.LineStyle?) {
        self.lineStyle = lineStyle
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? UnderlineTextModifier)?.lineStyle == lineStyle
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(UnderlineTextModifier.self))
        hasher.combine(lineStyle)
    }
}

final class StrikethroughTextModifier: AnyTextModifier {
    override func modify(style: inout Text.Style) { style.strikethrough = lineStyle.map(Text.Style.LineStyle.explicit) ?? .default }
    let lineStyle: Text.LineStyle?

    init(lineStyle: Text.LineStyle?) {
        self.lineStyle = lineStyle
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? StrikethroughTextModifier)?.lineStyle == lineStyle
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(StrikethroughTextModifier.self))
        hasher.combine(lineStyle)
    }
}

class TextAttributeModifierBase: AnyTextModifier {
    override func modify(style: inout Text.Style) { style.customAttributes.append(self) }
    func apply(to attributes: inout _TextAttributeValues) {}
}

private final class TextAttributeModifier<Value>: TextAttributeModifierBase
where Value: TextAttribute {
    let value: Value

    init(value: Value) {
        self.value = value
    }

    override func apply(to attributes: inout _TextAttributeValues) {
        attributes.set(_AnyTextAttribute(value))
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? TextAttributeModifier<Value>)?.value == value
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(Value.self))
        hasher.combine(value)
    }
}

extension Text {
    func modified(with modifier: Modifier) -> Text {
        Text(storage: storage, modifiers: modifiers + [modifier])
    }

    public func foregroundColor(_ color: Color?) -> Text {
        modified(with: .color(color))
    }

    var foregroundColor: Color? {
        for modifier in modifiers {
            if case let .color(color) = modifier {
                return color
            }
        }
        return nil
    }

    func foregroundShading(in environment: EnvironmentValues) -> GraphicsContext.Shading {
        if let foregroundColor {
            return .color(foregroundColor)
        }
        if let style = environment.currentForegroundStyle {
            var shape = _ShapeStyle_Shape(
                operation: .fallbackColor(level: 0),
                environment: environment
            )
            style._apply(to: &shape)
            if let shading = shape.resolvedShading {
                return shading
            }
        }
        return .foreground
    }

    public func font(_ font: Font?) -> Text {
        modified(with: .font(font))
    }

    var font: Font? {
        for modifier in modifiers {
            if case let .font(font) = modifier {
                return font
            }
        }
        return nil
    }

    public func fontWeight(_ weight: Font.Weight?) -> Text {
        modified(with: .weight(weight))
    }

    var fontWeight: Font.Weight? {
        for modifier in modifiers {
            if case let .weight(weight) = modifier {
                return weight
            }
        }
        return nil
    }

    public func bold() -> Text {
        bold(true)
    }

    public func bold(_ isActive: Bool) -> Text {
        modified(with: .anyTextModifier(BoldTextModifier(
            isActive: isActive
        )))
    }

    var boldValue: Bool? {
        for modifier in modifiers {
            guard case let .anyTextModifier(value) = modifier,
                  let value = value as? BoldTextModifier else {
                continue
            }
            return value.isActive
        }
        return nil
    }

    public func italic() -> Text {
        modified(with: .italic)
    }

    public func italic(_ isActive: Bool) -> Text {
        if isActive {
            return italic()
        }
        return modified(with: .anyTextModifier(ItalicTextModifier(
            isActive: false
        )))
    }

    var italicValue: Bool? {
        for modifier in modifiers {
            switch modifier {
            case .italic:
                return true
            case let .anyTextModifier(value):
                if let value = value as? ItalicTextModifier {
                    return value.isActive
                }
            default:
                continue
            }
        }
        return nil
    }

    public func monospaced(_ isActive: Bool = true) -> Text {
        modified(with: .anyTextModifier(MonospacedTextModifier(
            isActive: isActive
        )))
    }

    var monospacedValue: Bool? {
        for modifier in modifiers {
            guard case let .anyTextModifier(value) = modifier,
                  let value = value as? MonospacedTextModifier else {
                continue
            }
            return value.isActive
        }
        return nil
    }

    public func monospacedDigit() -> Text {
        modified(with: .anyTextModifier(MonospacedDigitTextModifier()))
    }

    public func _stylisticAlternative(_ alternative: Font._StylisticAlternative) -> Text {
        modified(with: .anyTextModifier(StylisticAlternativeTextModifier(value: alternative)))
    }

    var usesMonospacedDigits: Bool {
        modifiers.contains { modifier in
            guard case let .anyTextModifier(value) = modifier else {
                return false
            }
            return value is MonospacedDigitTextModifier
        }
    }

    public func strikethrough(
        _ isActive: Bool = true,
        color: Color? = nil
    ) -> Text {
        strikethrough(isActive, pattern: .solid, color: color)
    }

    public func strikethrough(
        _ isActive: Bool = true,
        pattern: LineStyle.Pattern,
        color: Color? = nil
    ) -> Text {
        modified(with: .anyTextModifier(StrikethroughTextModifier(
            lineStyle: isActive
                ? LineStyle(pattern: pattern, color: color)
                : nil
        )))
    }

    public func underline(
        _ isActive: Bool = true,
        color: Color? = nil
    ) -> Text {
        underline(isActive, pattern: .solid, color: color)
    }

    public func underline(
        _ isActive: Bool = true,
        pattern: LineStyle.Pattern,
        color: Color? = nil
    ) -> Text {
        modified(with: .anyTextModifier(UnderlineTextModifier(
            lineStyle: isActive
                ? LineStyle(pattern: pattern, color: color)
                : nil
        )))
    }

    public func kerning(_ kerning: CGFloat) -> Text {
        modified(with: .kerning(kerning))
    }

    public func tracking(_ tracking: CGFloat) -> Text {
        modified(with: .tracking(tracking))
    }

    public func baselineOffset(_ baselineOffset: CGFloat) -> Text {
        modified(with: .baseline(baselineOffset))
    }
}

extension Text {
    public func customAttribute<T>(_ value: T) -> Text where T: TextAttribute {
        modified(with: .anyTextModifier(TextAttributeModifier(value: value)))
    }

    var customAttributes: _TextAttributeValues {
        var attributes = _TextAttributeValues()
        for modifier in modifiers {
            guard case let .anyTextModifier(value) = modifier,
                  let value = value as? TextAttributeModifierBase else {
                continue
            }
            value.apply(to: &attributes)
        }
        return attributes
    }

    public static func + (lhs: Text, rhs: Text) -> Text {
        .init(storage: .anyTextStorage(ConcatenatedTextStorage(first: lhs,
                                                               second: rhs)),
              modifiers: [])
    }
}

extension Text: View {
    struct MakeRepresentableContext: Rule {
        var _text: Attribute<ResolvedStyledText>
        var _referenceDate: WeakAttribute<Date?>
        var _environment: Attribute<EnvironmentValues>

        var value: PlatformTextRepresentableContext {
            let context = ResolvableStringResolutionContext(
                referenceDate: _referenceDate.value.flatMap { $0 },
                environment: _environment.value,
                maximumWidth: nil
            )
            let text = _text.value
            return PlatformTextRepresentableContext(
                text: text.resolvedContent(in: context) ?? text.storage
            )
        }
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        // 1. Internal state nodes for the graph-side resolver and backend resource pass.
        let initialResolvedStyledText = ResolvedStyledText()
        let backendResolvedStyledTextAttr = graph.makeInput(value: initialResolvedStyledText)
        let backendResolvedTextTransactionAttr = graph.makeInput(value: Transaction())
        let resourceResolutionState = _TextResourceResolutionState()
        let inheritedTransactionAttr = inputs.base.transaction
        // Extract inputs to avoid capturing the entire `inputs` struct
        let cachedEnvironmentAttr = inputs.base.cachedEnvironment
        let environmentAttr = cachedEnvironmentAttr.value.environment
        let timeAttr = inputs.base.time
        let inbox = graph.inbox
        let animatedSizeAttr: Attribute<ViewSize>
        let targetSizeAttr: Attribute<ViewSize>
        if inputs.needsGeometry {
            var cachedEnvironment = cachedEnvironmentAttr.value
            animatedSizeAttr = cachedEnvironment.animatedSize(for: inputs)
            guard let animatedFrame = cachedEnvironment.animatedFrame else {
                fatalError("Text geometry animation requires an animated frame.")
            }
            targetSizeAttr = animatedFrame.size
            cachedEnvironmentAttr.value = cachedEnvironment
        } else {
            animatedSizeAttr = inputs.size
            targetSizeAttr = inputs.size
        }
        let textRendererAttr = inputs[TextRendererInput.self]
        let archiveOptions = inputs[ArchivedViewInput.self]
        let textFeatures: ResolvedProperties.Features = archiveOptions.isArchived ? [] : .useTextSuffix
        let resolvedTextFeatures = textRendererAttr.attribute == nil
            ? textFeatures
            : textFeatures.union([.customRenderer, .produceTextLayout])
        let usesSizeFittingText = inputs.base[VariantThatFitsFlag.self]
        let resolvedTextHelper = ResolvedTextHelper(
            _time: timeAttr,
            _referenceDate: inputs[ReferenceDateInput.self],
            archiveOptions: archiveOptions,
            features: resolvedTextFeatures
        )
        let graphResolvedStyledTextAttr = graph.makeStatefulRule(
            ResolvedTextFilter(
                _text: view._attribute,
                _environment: environmentAttr,
                helper: resolvedTextHelper
            )
        )
        let resolvedStyledTextAttr: Attribute<ResolvedStyledText> = graph.makeRule {
            let graphResolved = graphResolvedStyledTextAttr.value
            guard graphResolved.resolvedText == nil else {
                return graphResolved
            }
            return backendResolvedStyledTextAttr.value
        }
        let resolvedStyledTextTransactionAttr: Attribute<Transaction> = graph.makeRule {
            let graphResolved = graphResolvedStyledTextAttr.value
            if graphResolved.resolvedText != nil {
                return inheritedTransactionAttr.value
            }
            return backendResolvedTextTransactionAttr.value
        }

        let debugLayoutAttr: Attribute<Bool> = graph.makeRule {
            cachedEnvironmentAttr.value.environment.value._debugLayout
        }

        // 2. Resource pass (Resource Rule)
        // Evaluated before drawing (in updateView) to upload resources to the GPU.
        let resourceAttr: Attribute<ResourceList> = graph.makeRule { graphRef in
            let graph = graphRef.graph
            let text = view._attribute.value // Dependency 1: Text content and modifiers
            let environment = cachedEnvironmentAttr.value.environment.value // Dependency 2: Environment (scale, theme, font)
            let referenceDate = Date()
            let renderEnvironment = environment.untrackedCopy()
            let currentVersion = text._resolutionVersion(
                in: environment,
                referenceDate: referenceDate
            )

            let graphResolvedStyledText = graphResolvedStyledTextAttr.value
            if let resolved = graphResolvedStyledText.resolvedText {
                guard resourceResolutionState.requiresPreparation(
                    version: currentVersion
                ) else {
                    return ResourceList()
                }
                var list = ResourceList()
                list.items.append(ResourceList.Task(
                    transaction: Transaction(),
                    updatesGraph: false,
                    isPending: {
                        resourceResolutionState.requiresPreparation(
                            version: currentVersion
                        )
                    }
                ) { _ in
                    resolved.prepareResources()
                    resourceResolutionState.didPrepare(version: currentVersion)
                })
                return list
            }

            let backendResolvedStyledText = backendResolvedStyledTextAttr.value
            if backendResolvedStyledText.version == currentVersion,
               backendResolvedStyledText.resolvedText != nil {
                resourceResolutionState.didResolve(version: currentVersion)
                return ResourceList()
            }

            let contextualTransaction = _AGGraph.currentRuleContextAttribute
                .flatMap { graph.transaction(for: $0) } ?? Transaction()
            let inheritedTransaction = inheritedTransactionAttr.value
            let candidateTransaction = contextualTransaction.isEmpty
                ? inheritedTransaction
                : contextualTransaction
            let resourceTransaction = resourceResolutionState.transaction(
                for: currentVersion,
                candidate: candidateTransaction
            )
            // If loading is required, create a new ResourceList(Task) to propagate upwards.
            var list = ResourceList()

            let weakGraph = _AGGraphWeakRef(graph)
            list.items.append(ResourceList.Task(transaction: resourceTransaction) { context in
                guard let graph = weakGraph.graph else { return }
                var context = context
                context.copyOnWrite()
                context.environment = renderEnvironment
                guard let resolved = text._resolveStyledText(
                    context: context,
                    referenceDate: referenceDate,
                    archiveOptions: archiveOptions,
                    features: resolvedTextFeatures,
                    sizeFitting: usesSizeFittingText,
                    options: resolvedTextFeatures.contains(.useTextSuffix)
                        ? [.includeTransitions, .allowsKeyColors, .allowsTextSuffix]
                        : [.includeTransitions, .allowsKeyColors]
                ) else {
                    fatalError("A graphics text context must resolve backend attachments.")
                }
                resolved.resolvedText?.prepareResources()
                let boxedResolved = UnsafeSendableBox(resolved)
                let boxedTransaction = UnsafeSendableBox(resourceTransaction)

                let publish: @Sendable () -> Void = {
                    backendResolvedTextTransactionAttr.setValue(boxedTransaction.value)
                    backendResolvedStyledTextAttr.setValue(
                        boxedResolved.value,
                        transaction: boxedTransaction.value
                    )
                }
                if _AGGraph.current === graph {
                    publish()
                } else {
                    inbox.enqueue(transaction: resourceTransaction, publish)
                }
            })

            return list
        }

        // 3. Layout pass (Layout Rule)
        let displayedStyledTextAttr: Attribute<ResolvedStyledText>
        let lcAttr: Attribute<LayoutComputer>
        if usesSizeFittingText {
            let cache = SizeFittingTextCache(
                resolver: resolvedTextHelper,
                logic: StickyTextSizeFittingLogic(),
                input: ResolvedTextHelper.Input(
                    text: initialResolvedStyledText,
                    renderer: nil
                )
            )
            displayedStyledTextAttr = graph.makeStatefulRule(
                SizeFittingTextFilter(
                    size: animatedSizeAttr,
                    text: resolvedStyledTextAttr,
                    environment: environmentAttr,
                    isArchived: archiveOptions.isArchived,
                    cache: cache
                )
            )
            lcAttr = graph.makeStatefulRule(
                SizeFittingTextLayoutComputer(
                    _text: resolvedStyledTextAttr,
                    _environment: environmentAttr,
                    _renderer: textRendererAttr,
                    cache: cache
                )
            )
        } else {
            displayedStyledTextAttr = resolvedStyledTextAttr
            lcAttr = graph.makeStatefulRule(
                StyledTextLayoutComputer(
                    _textView: graph.makeRule {
                        let styledText = resolvedStyledTextAttr.value
                        return StyledTextContentView(
                            text: styledText,
                            renderer: textRendererAttr.value,
                            needsDrawingGroup: styledText.needsDrawingGroup
                        )
                    }
                )
            )
        }

        let textViewAttr: Attribute<StyledTextContentView> = graph.makeRule {
            let styledText = displayedStyledTextAttr.value
            return StyledTextContentView(
                text: styledText,
                renderer: textRendererAttr.value,
                needsDrawingGroup: styledText.needsDrawingGroup
            )
        }
        var cachedEnvironment = cachedEnvironmentAttr.value
        let styles = cachedEnvironment.resolvedShapeStyles(
            for: inputs,
            role: .fill
        )
        cachedEnvironmentAttr.value = cachedEnvironment
        let interpolatorGroup = _ShapeStyle_InterpolatorGroup()
        var leafInputs = inputs
        leafInputs.size = targetSizeAttr
        leafInputs.containerPosition = cachedEnvironment.animatedPosition(
            for: inputs
        )
        cachedEnvironmentAttr.value = cachedEnvironment
        var outputs = StyledTextContentView.makeLeafView(
            view: _GraphValue(_attribute: textViewAttr),
            inputs: leafInputs,
            styles: styles,
            interpolatorGroup: interpolatorGroup
        )
        outputs._layoutComputer = OptionalAttribute(lcAttr)

        // 5. Propagate ResourceList and DisplayList upwards via the Preference channel!
        outputs.preferences.append(ResourceList.Key.self, node: resourceAttr.identifier)
        if inputs.preferences.keys.contains(DisplayList.Key.self) {
            let debugDisplayList: Attribute<DisplayList> = graph.makeRule {
                var list = DisplayList()
                if debugLayoutAttr.value {
                    appendDebugOverlay(
                        to: &list,
                        frame: CGRect(
                            origin: .zero,
                            size: targetSizeAttr.value.value
                        ),
                        category: .primitiveView
                    )
                }
                return list
            }
            outputs.preferences.append(
                DisplayList.Key.self,
                node: debugDisplayList.identifier
            )
        }
        var interpolatorInputs = inputs
        interpolatorInputs.base.transaction = resolvedStyledTextTransactionAttr
        interpolatorInputs.size = targetSizeAttr
        outputs.applyInterpolatorGroup(
            interpolatorGroup,
            content: displayedStyledTextAttr,
            inputs: interpolatorInputs,
            animatesSize: false,
            defersRender: false
        )
        if let representable = inputs.requestedTextRepresentation,
           representable.shouldMakeRepresentation(inputs: inputs) {
            _ = representable.representationOptions(inputs: inputs)
            let context: Attribute<PlatformTextRepresentableContext> =
                graph.makeRule(MakeRepresentableContext(
                    _text: resolvedStyledTextAttr,
                    _referenceDate: inputs[ReferenceDateInput.self],
                    _environment: environmentAttr
                ))
            representable.makeRepresentation(
                inputs: inputs,
                context: context,
                outputs: &outputs
            )
        }

        return outputs
    }

    public static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        1
    }
}

extension Text: PrimitiveView {
}
