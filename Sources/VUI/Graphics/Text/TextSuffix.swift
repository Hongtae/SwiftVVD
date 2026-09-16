//
//  File: TextSuffix.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Text {
    struct Suffix: Equatable {
        enum Storage: Equatable {
            case truncated(Text)
            case alwaysVisible(Text)
            case automatic
            case none
        }

        var storage: Storage

        static func truncated(_ text: Text) -> Self { Self(storage: .truncated(text)) }
        static func alwaysVisible(_ text: Text) -> Self { Self(storage: .alwaysVisible(text)) }
        static var automatic: Self { Self(storage: .automatic) }
        static var none: Self { Self(storage: .none) }

        var text: Text? {
            switch storage {
            case let .truncated(text), let .alwaysVisible(text): text
            case .automatic, .none: nil
            }
        }

        func resolve(text: ResolvedStyledText?) -> ResolvedTextSuffix {
            guard let text else { return .none }
            let size = text.sizeThatFits(.unspecified)
            guard let layout = text.makeLayout(in: CGRect(origin: .zero, size: size), with: size,
                shading: text.resolvedText?.shading ?? .foreground,
                layoutDirection: text.layoutProperties.layoutDirection), layout.count == 1 else {
                return .none
            }
            switch storage {
            case .truncated: return .truncated(layout[0], text.styles)
            case .alwaysVisible: return .alwaysVisible(layout[0], text.styles)
            case .automatic, .none: return .none
            }
        }
    }
}

struct TextSuffixKey: EnvironmentKey {
    static var defaultValue: ResolvedTextSuffix { .none }
}
