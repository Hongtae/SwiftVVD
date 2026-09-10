//
//  File: FontResourceCatalog.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

/// Resource metadata scoped to one bundle's declared font files.
final class FontResourceCatalog: Sendable {
    enum NameKind: Hashable, Sendable {
        case postScript
        case family
        case fullName
    }

    struct Match: Hashable, Sendable {
        let face: Face
        /// Nil identifies the face's name records, not a selected named instance.
        let instanceIndex: Int?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.face.resource == rhs.face.resource && lhs.instanceIndex == rhs.instanceIndex
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(face.resource)
            hasher.combine(instanceIndex)
        }
    }

    final class Face: Sendable {
        let resource: BundledFontResource
        let metadata: VVD.Font.FaceMetadata

        fileprivate init(resource: BundledFontResource, metadata: VVD.Font.FaceMetadata) {
            self.resource = resource
            self.metadata = metadata
        }
    }

    private final class Source: Sendable {
        let url: URL
        private let faces = Mutex<[Int: Face?]>([:])

        init(url: URL) {
            self.url = url
        }

        func face(at index: Int) -> Face? {
            guard (0...0xffff).contains(index) else { return nil }
            return faces.withLock { faces in
                if let cached = faces[index] {
                    return cached
                }
                let face = VVD.Font.metadata(path: url.path, faceIndex: index).map {
                    Face(resource: BundledFontResource(url: url, faceIndex: index), metadata: $0)
                }
                // Cache failures as well; bundle resources do not change in place.
                faces[index] = .some(face)
                return face
            }
        }
    }

    let resourceDirectory: URL
    private let sources: [String: Source]
    private let names = Mutex<[NameKind: [String: [Match]]]?>(nil)
    private let descriptorResolver = Mutex<FontResourceResolver?>(nil)

    var resolver: FontResourceResolver {
        descriptorResolver.withLock { resolver in
            if let resolver { return resolver }
            let resolved = FontResourceResolver(faces: allFaces)
            resolver = resolved
            return resolved
        }
    }

    init(configuration: FontFallbackConfiguration, resourceDirectory: URL) {
        let resourceDirectory = resourceDirectory.standardizedFileURL
        self.resourceDirectory = resourceDirectory
        let files = Set(configuration.fontDescriptors.values.flatMap {
            $0.sources.map(\.file)
        })
        self.sources = Dictionary(uniqueKeysWithValues: files.map { file in
            (file, Source(url: resourceDirectory.appendingPathComponent(file)))
        })
    }

    /// Returns the shared, immutable snapshot for a declared collection member.
    func face(file: String, index: Int) -> Face? {
        sources[file]?.face(at: index)
    }

    func resource(file: String, index: Int) -> BundledFontResource? {
        guard (0...0xffff).contains(index), let source = sources[file],
              FileManager.default.fileExists(atPath: source.url.path) else {
            return nil
        }
        return BundledFontResource(url: source.url, faceIndex: index)
    }

    /// Collection members are distinct from the named instances in each snapshot.
    /// Enumeration order is resource order, not a font-matching preference.
    var allFaces: [Face] {
        sources.keys.sorted().flatMap { file -> [Face] in
            let source = sources[file]!
            guard let first = source.face(at: 0) else { return [] }
            return [first] + (1..<min(first.metadata.numFaces, 0x10000)).compactMap {
                source.face(at: $0)
            }
        }
    }

    /// Finds source names without selecting or realizing a rendering descriptor.
    /// Generated descriptor aliases and candidate preference belong to resolution.
    func matches(name: String, kind: NameKind) -> [Match] {
        names.withLock { names in
            if names == nil {
                var index: [NameKind: [String: [Match]]] = [:]
                func append(_ name: String?, kind: NameKind, match: Match) {
                    guard let name, !name.isEmpty else { return }
                    let key = name.lowercased()
                    if index[kind]?[key]?.contains(match) != true {
                        index[kind, default: [:]][key, default: []].append(match)
                    }
                }
                for face in allFaces {
                    let base = Match(face: face, instanceIndex: nil)
                    let defaultInstance = Match(
                        face: face,
                        instanceIndex: face.metadata.defaultVariationInstanceIndex
                    )
                    append(face.metadata.familyName, kind: .family, match: base)
                    append(face.metadata.postScriptName, kind: .postScript, match: defaultInstance)
                    for record in face.metadata.sfntNames {
                        switch record.nameID {
                        case 1, 16:
                            append(record.string, kind: .family, match: base)
                        case 4:
                            append(record.string, kind: .fullName, match: base)
                        case 6:
                            append(record.string, kind: .postScript, match: defaultInstance)
                        default:
                            break
                        }
                    }
                    for instance in face.metadata.variationInstances {
                        append(instance.postScriptName, kind: .postScript,
                               match: Match(face: face, instanceIndex: instance.index))
                    }
                }
                names = index
            }
            return names?[kind]?[name.lowercased()] ?? []
        }
    }
}

struct BundledFontCatalog: Sendable {
    private final class BundleSource: Sendable {
        private enum State {
            case unloaded
            case loaded(BundledFontCatalog?)
        }

        let bundle: Bundle
        private let state = Mutex<State>(.unloaded)

        init(bundle: Bundle) {
            self.bundle = bundle
        }

        func load() -> BundledFontCatalog? {
            state.withLock { state in
                if case let .loaded(catalog) = state {
                    return catalog
                }
                guard let url = bundle.url(
                    forResource: "font-config",
                    withExtension: "json",
                    subdirectory: "Fonts"
                ) else {
                    state = .loaded(nil)
                    return nil
                }
                do {
                    let catalog = BundledFontCatalog(
                        configuration: try FontFallbackConfiguration(data: Data(contentsOf: url)),
                        resourceDirectory: url.deletingLastPathComponent()
                    )
                    state = .loaded(catalog)
                    return catalog
                } catch {
                    Log.error("Invalid font configuration at \(url): \(error)")
                    state = .loaded(nil)
                    return nil
                }
            }
        }
    }

    private static let bundles = Mutex<[URL: BundleSource]>([:])

    static let shared: Self = {
        guard let catalog = catalog(in: .module) else {
            fatalError("The bundled font configuration is missing or invalid.")
        }
        return catalog
    }()

    /// Each bundle owns its configuration and metadata independently of window locks.
    static func catalog(in bundle: Bundle) -> Self? {
        let key = bundle.bundleURL.standardizedFileURL
        let source = bundles.withLock { bundles in
            if let source = bundles[key] { return source }
            let source = BundleSource(bundle: bundle)
            bundles[key] = source
            return source
        }
        // File IO and decoding hold only this bundle's lock.
        return source.load()
    }

    let configuration: FontFallbackConfiguration
    let resources: FontResourceCatalog

    init(configuration: FontFallbackConfiguration, resourceDirectory: URL) {
        self.configuration = configuration
        self.resources = FontResourceCatalog(
            configuration: configuration,
            resourceDirectory: resourceDirectory
        )
    }

    func resource(
        for family: BundledFontID,
        locale: Locale,
        weight: CGFloat = 400,
        isItalic: Bool = false
    ) -> BundledFontResource? {
        guard let descriptor = configuration.fontDescriptors[family] else { return nil }
        let source = descriptor.source(for: weight, isItalic: isItalic)
        return resources.resource(file: source.file, index: source.faceIndex(for: locale))
    }
}
