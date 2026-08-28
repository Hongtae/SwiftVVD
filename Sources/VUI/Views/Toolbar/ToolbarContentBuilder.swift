//
//  File: ToolbarContentBuilder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - TupleToolbarContent

// @ToolbarContentBuilder produces TupleToolbarContent<C> (single) or
// TupleToolbarContent<(C0, C1, ...)> (multiple items, C = tuple).
// Field iteration reflects over the content tuple and visits view-typed fields.
// Public visibility keeps result-builder expansion usable across module boundaries.
public struct TupleToolbarContent<C>:
    ToolbarContent,
    CustomizableToolbarContent
{
    public var value: C
    public init(_ value: C) { self.value = value }

    public typealias Body = Never

    public var body: Never {
        fatalError("TupleToolbarContent may not have Body == Never")
    }

    public static func _makeToolbar(
        content: _GraphValue<Self>,
        inputs: _ToolbarInputs
    ) -> _ToolbarOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("TupleToolbarContent._makeToolbar called outside AG context")
        }
        var allOutputs: [_ToolbarOutputs] = []

        func makeWholeValue<T: ToolbarContent>(_: T.Type) {
            let value: Attribute<T> = graph.makeRule {
                content._attribute.value.value as! T
            }
            allOutputs.append(T._makeToolbar(
                content: _GraphValue(_attribute: value),
                inputs: inputs
            ))
        }
        if let contentType = C.self as? any ToolbarContent.Type {
            _openExistential(contentType, do: makeWholeValue)
            return mergeToolbarOutputs(allOutputs, in: graph)
        }

        func makeChild<T: ToolbarContent>(_: T.Type, offset: Int) {
            let childAttr: Attribute<T> = graph.makeRule {
                withUnsafeBytes(of: content._attribute.value.value) { buf in
                    buf.baseAddress!.advanced(by: offset)
                        .assumingMemoryBound(to: T.self).pointee
                }
            }
            allOutputs.append(T._makeToolbar(
                content: _GraphValue(_attribute: childAttr),
                inputs: inputs
            ))
        }
        _forEachField(of: C.self) { _, offset, fieldType in
            if let toolbarType = fieldType as? any ToolbarContent.Type {
                func open<T: ToolbarContent>(_: T.Type) {
                    makeChild(T.self, offset: offset)
                }
                _openExistential(toolbarType, do: open)
            }
            return true
        }
        return mergeToolbarOutputs(allOutputs, in: graph)
    }

    public static func _makeContent(
        content: _GraphValue<Self>,
        inputs: _GraphInputs,
        resolved: inout _ToolbarItemList
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("TupleToolbarContent._makeContent called outside AG context")
        }

        func makeWholeValue<T: ToolbarContent>(_: T.Type) {
            let value: Attribute<T> = graph.makeRule {
                content._attribute.value.value as! T
            }
            T._makeContent(
                content: _GraphValue(_attribute: value),
                inputs: inputs,
                resolved: &resolved
            )
        }
        if let contentType = C.self as? any ToolbarContent.Type {
            _openExistential(contentType, do: makeWholeValue)
            return
        }

        func makeChild<T: ToolbarContent>(_: T.Type, offset: Int) {
            let childAttr: Attribute<T> = graph.makeRule {
                withUnsafeBytes(of: content._attribute.value.value) { buf in
                    buf.baseAddress!.advanced(by: offset)
                        .assumingMemoryBound(to: T.self).pointee
                }
            }
            T._makeContent(
                content: _GraphValue(_attribute: childAttr),
                inputs: inputs,
                resolved: &resolved
            )
        }
        _forEachField(of: C.self) { _, offset, fieldType in
            if let toolbarType = fieldType as? any ToolbarContent.Type {
                func open<T: ToolbarContent>(_: T.Type) {
                    makeChild(T.self, offset: offset)
                }
                _openExistential(toolbarType, do: open)
            }
            return true
        }
    }
}
// MARK: - ToolbarContentBuilder

// The builder uses @resultBuilder for toolbar content builder semantics.
// buildBlock methods are @inlinable so the public TupleToolbarContent type is usable at call sites.
@resultBuilder
public struct ToolbarContentBuilder {
    public static func buildBlock(_ content: Never) -> Never {}

    @inlinable
    public static func buildBlock<C: ToolbarContent>(
        _ c: C
    ) -> some ToolbarContent {
        TupleToolbarContent(c)
    }

    @inlinable
    public static func buildBlock<C: CustomizableToolbarContent>(
        _ c: C
    ) -> some CustomizableToolbarContent {
        TupleToolbarContent(c)
    }

    @inlinable
    public static func buildBlock<each Content>(
        _ content: repeat each Content
    ) -> some ToolbarContent where repeat each Content: ToolbarContent {
        TupleToolbarContent((repeat each content))
    }

    @inlinable
    public static func buildBlock<each Content>(
        _ content: repeat each Content
    ) -> some CustomizableToolbarContent
    where repeat each Content: CustomizableToolbarContent {
        TupleToolbarContent((repeat each content))
    }

    public static func buildEither<T: ToolbarContent, F: ToolbarContent>(
        first: T
    ) -> _ConditionalContent<T, F> {
        .init(storage: .trueContent(first))
    }

    public static func buildEither<T: ToolbarContent, F: ToolbarContent>(
        second: F
    ) -> _ConditionalContent<T, F> {
        .init(storage: .falseContent(second))
    }

    public static func buildIf<C: ToolbarContent>(_ c: C?) -> C? { c }
    public static func buildExpression<C: ToolbarContent>(_ c: C) -> C { c }
    public static func buildExpression<C: CustomizableToolbarContent>(
        _ c: C
    ) -> C {
        c
    }
}

// MARK: - _ConditionalContent ToolbarContent conformance

extension _ConditionalContent: ToolbarContent
where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
    public typealias Body = Never

    public var body: Never {
        fatalError("_ConditionalContent may not have Body == Never")
    }
}

extension _ConditionalContent: CustomizableToolbarContent
where TrueContent: CustomizableToolbarContent,
      FalseContent: CustomizableToolbarContent {
}
