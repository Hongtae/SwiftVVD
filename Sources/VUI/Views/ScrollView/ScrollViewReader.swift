//
//  File: ScrollViewReader.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ScrollViewReader<Content>: View where Content: View {
    public var content: (ScrollViewProxy) -> Content

    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
    }

    public var body: some View {
        ScrollablePreferenceKey._delay { value in
            content(ScrollViewProxy(_values: value.attribute))
        }
    }
}

public struct ScrollViewProxy {
    var _values: WeakAttribute<[any Scrollable]>

    init(_values: WeakAttribute<[any Scrollable]>) {
        self._values = _values
    }

    public func scrollTo<ID>(_ id: ID, anchor: UnitPoint? = nil) where ID: Hashable {
        var transaction = Transaction.current
        if let anchor {
            transaction.scrollTargetAnchor = anchor
        }
        withTransaction(transaction) {
            apply { scrollable in
                scrollable.scroll(to: id)
            }
        }
    }

    private func apply(to body: (any Scrollable) -> Bool) {
        if let host = _AGGraphContext.current?.context as? GraphHost {
            precondition(
                !host.isUpdating,
                "ScrollViewProxy.scrollTo may not be called during view updates."
            )
        }
        Update.ensure {
            guard let graph = _AGGraph.current,
                  _values.isValid(in: graph) else {
                return
            }
            for scrollable in _values.toStrong().value {
                if body(scrollable) {
                    break
                }
            }
        }
    }
}
