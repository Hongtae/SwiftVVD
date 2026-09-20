import XCTest
import VGame
import VVD

final class PhysicsSettingsArchiveTests: XCTestCase {
    func testRuntimeRoundTripsEveryCCDModeAndSubsteps() throws {
        for mode in CCDConfiguration.Mode.allCases {
            var configuration = ScenePhysicsConfiguration.default
            configuration.ccd.mode = mode
            configuration.ccd.substepCount = 4
            let data = try PhysicsSettingsArchive.encode(configuration)
            XCTAssertEqual(try PhysicsSettingsArchive.decode(data), configuration)
        }
    }

    func testRuntimeSavesAndLoadsResourceFileWithoutEditor() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vvd-physics-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let configuration = ScenePhysicsConfiguration.Preset.accurateImpacts.configuration
        try PhysicsSettingsArchive.save(configuration, to: url)
        let loaded = try PhysicsSettingsArchive.load(from: url)
        let runtime = try WorldPhysics(configuration: loaded)
        XCTAssertEqual(runtime.configuration, configuration)

        var invalid = configuration
        invalid.fixedTimeStep = -1
        XCTAssertThrowsError(try PhysicsSettingsArchive.save(invalid, to: url))
        XCTAssertEqual(try PhysicsSettingsArchive.load(from: url), configuration)
    }

    func testRuntimeRejectsMalformedUnknownVersionAndInvalidSettings() throws {
        XCTAssertThrowsError(try PhysicsSettingsArchive.decode(Data("invalid".utf8)))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:
            PhysicsSettingsArchive.encode(.default)) as? [String: Any])
        json["version"] = 99
        XCTAssertThrowsError(try PhysicsSettingsArchive.decode(JSONSerialization.data(withJSONObject: json)))
        json["version"] = 1
        var settings = try XCTUnwrap(json["configuration"] as? [String: Any])
        settings["velocityIterations"] = 0
        json["configuration"] = settings
        XCTAssertThrowsError(try PhysicsSettingsArchive.decode(JSONSerialization.data(withJSONObject: json)))
    }
}
