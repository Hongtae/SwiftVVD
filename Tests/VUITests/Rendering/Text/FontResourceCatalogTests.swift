import Dispatch
import Foundation
import Synchronization
import XCTest
@testable import VUI

final class FontResourceCatalogTests: XCTestCase {
    private static let roboto = "Roboto/Roboto-VariableFont_wdth,wght.ttf"

    private func fixtureBundle() throws -> (Bundle, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bundle", isDirectory: true)
        let fonts = directory.appendingPathComponent("Contents/Resources/Fonts", isDirectory: true)
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>font-catalog.\(UUID().uuidString)</string>
        <key>CFBundlePackageType</key><string>BNDL</string>
        </dict></plist>
        """.utf8).write(to: directory.appendingPathComponent("Contents/Info.plist"))
        // Non-Darwin Bundle uses the flat resource layout.
        #if !canImport(Darwin)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("Fonts"), withDestinationURL: fonts
        )
        #endif
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return (try XCTUnwrap(Bundle(url: directory)), fonts)
    }

    private func configure(_ fonts: URL, file: String = "Font.ttf") throws {
        let data = Data("""
        {
          "version": 2,
          "fonts": {
            "Primary": {"sources": [{"file": "\(file)", "faceIndex": 0,
              "weightAxis": {"tag": "wght", "minimum": 100, "maximum": 900}}],
              "syntheticWeight": false},
            "Terminal": {"sources": [{"file": "\(file)", "faceIndex": 0,
              "weight": 400}], "syntheticWeight": false}
          },
          "defaultLocale": "en",
          "designs": {"default": {"systemFont": "Primary", "locales": {"en": ["Primary"]}}},
          "missingGlyphFont": "Terminal"
        }
        """.utf8)
        try data.write(to: fonts.appendingPathComponent("font-config.json"))
        try FileManager.default.copyItem(
            at: BundledFontCatalog.shared.resources.resourceDirectory.appendingPathComponent(Self.roboto),
            to: fonts.appendingPathComponent(file)
        )
    }

    func testCatalogRetainsEveryCollectionFaceAndNamedInstance() {
        let resources = BundledFontCatalog.shared.resources
        let faces = resources.allFaces
        XCTAssertEqual(faces.count, 60)
        XCTAssertEqual(Set(faces.map(\.resource)).count, 60)
        XCTAssertEqual(faces.reduce(0) { $0 + $1.metadata.variationInstances.count }, 400)
        let noto = faces.filter { $0.resource.url.lastPathComponent == "NotoSansCJK-VF.otf.ttc" }
        XCTAssertEqual(noto.map(\.resource.faceIndex), [0, 1, 2, 3, 4])
        for (first, second) in zip(faces, resources.allFaces) {
            XCTAssertTrue(first === second)
        }
    }

    func testPostScriptLookupPreservesInstanceIdentityAndCoordinates() throws {
        let catalog = BundledFontCatalog.shared.resources
        let matches = catalog.matches(name: "Roboto-ExtraLight", kind: .postScript)
        XCTAssertEqual(matches.count, 1)
        let match = try XCTUnwrap(matches.first)
        XCTAssertEqual(match.instanceIndex, 2)
        let instance = try XCTUnwrap(match.face.metadata.variationInstances.first {
            $0.index == match.instanceIndex
        })
        XCTAssertEqual(instance.coordinates, [200, 100])
        for face in catalog.allFaces {
            for instance in face.metadata.variationInstances {
                let name = try XCTUnwrap(instance.postScriptName)
                XCTAssertTrue(catalog.matches(name: name, kind: .postScript).contains {
                    $0.face === face && $0.instanceIndex == instance.index
                }, name)
            }
        }
        // The base name and the default named instance identify one tuple.
        XCTAssertEqual(catalog.matches(name: "Roboto-Regular", kind: .postScript).count, 1)
    }

    func testSourceNamesRemainSeparateFromGeneratedDescriptorAliases() throws {
        let catalog = BundledFontCatalog.shared.resources
        let families = catalog.matches(name: "Roboto", kind: .family)
        XCTAssertEqual(families.count, 2)
        XCTAssertTrue(families.allSatisfy { $0.instanceIndex == nil })
        XCTAssertEqual(catalog.matches(name: "Roboto Regular", kind: .fullName).count, 1)
        XCTAssertTrue(catalog.matches(name: "Roboto ExtraLight", kind: .fullName).isEmpty)
        XCTAssertTrue(catalog.matches(name: "Roboto", kind: .postScript).isEmpty)
        XCTAssertEqual(catalog.matches(name: "ROBOTO-EXTRALIGHT", kind: .postScript),
                       catalog.matches(name: "roboto-extralight", kind: .postScript))
        XCTAssertTrue(catalog.matches(name: " Roboto-ExtraLight", kind: .postScript).isEmpty)
        XCTAssertTrue(catalog.matches(name: "Roboto-ExtraLight ", kind: .postScript).isEmpty)
    }

    func testNonRegularDefaultDoesNotReplaceNamedRegularIdentity() throws {
        let catalog = BundledFontCatalog.shared.resources
        let base = try XCTUnwrap(catalog.matches(name: "NanumSquareNeo-Variable", kind: .postScript).first)
        let regular = try XCTUnwrap(catalog.matches(name: "NanumSquareNeovariable-Regular", kind: .postScript).first)
        XCTAssertTrue(base.face === regular.face)
        XCTAssertEqual(base.instanceIndex, 1)
        XCTAssertEqual(regular.instanceIndex, 2)
        XCTAssertEqual(base.face.metadata.variationAxes.map(\.defaultValue), [100])
        XCTAssertEqual(base.face.metadata.variationInstances[1].coordinates, [300])
        XCTAssertEqual(base.face.metadata.styleName, "Regular")
    }

    func testBundlesKeepSeparateResourcesAndShareRepeatedCatalogLoads() throws {
        let (firstBundle, firstFonts) = try fixtureBundle()
        let (secondBundle, secondFonts) = try fixtureBundle()
        try configure(firstFonts)
        try configure(secondFonts)
        let first = try XCTUnwrap(BundledFontCatalog.catalog(in: firstBundle))
        let second = try XCTUnwrap(BundledFontCatalog.catalog(in: secondBundle))
        XCTAssertFalse(first.resources === second.resources)
        XCTAssertTrue(first.resources === BundledFontCatalog.catalog(in: firstBundle)?.resources)
        let a = try XCTUnwrap(first.resources.matches(name: "Roboto-Regular", kind: .postScript).first)
        let b = try XCTUnwrap(second.resources.matches(name: "Roboto-Regular", kind: .postScript).first)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a.face.resource, b.face.resource)
        XCTAssertEqual(a.face.metadata, b.face.metadata)
        XCTAssertEqual(first.resources.allFaces.count, 1) // Repeated file declarations are one resource.
        XCTAssertEqual(first.resource(for: BundledFontID("Primary"), locale: Locale(identifier: "en"))?.url,
                       firstFonts.appendingPathComponent("Font.ttf"))
    }

    func testCatalogCreationAndResourceSelectionDoNotInspectFaces() throws {
        let (bundle, fonts) = try fixtureBundle()
        try configure(fonts)
        let catalog = try XCTUnwrap(BundledFontCatalog.catalog(in: bundle))
        XCTAssertNotNil(catalog.resource(for: BundledFontID("Primary"), locale: Locale(identifier: "en")))
        // If either operation eagerly inspected the face, the valid snapshot would be cached.
        try Data([0]).write(to: fonts.appendingPathComponent("Font.ttf"))
        XCTAssertNil(catalog.resources.face(file: "Font.ttf", index: 0))
        XCTAssertTrue(catalog.resources.allFaces.isEmpty)
    }

    func testSnapshotAndNameIndexOutliveTheInspectedFile() throws {
        let (bundle, fonts) = try fixtureBundle()
        try configure(fonts)
        let catalog = try XCTUnwrap(BundledFontCatalog.catalog(in: bundle)).resources
        let face = try XCTUnwrap(catalog.face(file: "Font.ttf", index: 0))
        try FileManager.default.removeItem(at: fonts.appendingPathComponent("Font.ttf"))
        XCTAssertTrue(face === catalog.face(file: "Font.ttf", index: 0))
        let match = try XCTUnwrap(catalog.matches(name: "Roboto-ExtraLight", kind: .postScript).first)
        XCTAssertTrue(face === match.face)
        XCTAssertEqual(match.instanceIndex, 2)
        XCTAssertFalse(face.metadata.sfntNames.isEmpty)
    }

    func testConcurrentFirstLookupPublishesOneCatalogAndFace() throws {
        let (bundle, fonts) = try fixtureBundle()
        try configure(fonts)
        let results = Mutex<[FontResourceCatalog.Match]>([])
        DispatchQueue.concurrentPerform(iterations: 24) { _ in
            let values = BundledFontCatalog.catalog(in: bundle)?.resources
                .matches(name: "Roboto-Regular", kind: .postScript) ?? []
            results.withLock { $0.append(contentsOf: values) }
        }
        let matches = results.withLock { $0 }
        XCTAssertEqual(matches.count, 24)
        let first = try XCTUnwrap(matches.first)
        XCTAssertTrue(matches.allSatisfy { $0.face === first.face })
        XCTAssertEqual(Set(matches).count, 1)
    }

    func testMissingConfigurationAndUndeclaredFilesDoNotBecomeCatalogEntries() throws {
        let (bundle, _) = try fixtureBundle()
        XCTAssertNil(BundledFontCatalog.catalog(in: bundle))
        let catalog = BundledFontCatalog.shared.resources
        XCTAssertNil(catalog.face(file: "../Roboto.ttf", index: 0))
        XCTAssertNil(catalog.resource(file: Self.roboto, index: 0x10000))
        XCTAssertNil(catalog.face(file: Self.roboto, index: -1))
        XCTAssertNil(catalog.face(file: Self.roboto, index: 1))
    }
}
