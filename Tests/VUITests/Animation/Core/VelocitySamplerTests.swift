import XCTest
@testable import VUI

final class VelocitySamplerTests: XCTestCase {
    func testSmallDeltaSampleReplacesCurrentSampleWithoutShufflingHistory() {
        var sampler = VelocitySampler<Double>()

        sampler.addSample(0, time: 0)
        sampler.addSample(10, time: Double.ulpOfOne * 0.75)
        sampler.addSample(13, time: 1)

        XCTAssertEqual(sampler.lastTime, 1)
        XCTAssertEqual(sampler.velocity.valuePerSecond, 3, accuracy: 1.0e-12)
    }

    func testVelocityMixesCurrentAndPreviousFiniteDifferences() {
        var sampler = VelocitySampler<Double>()

        sampler.addSample(0, time: 0)
        sampler.addSample(10, time: 1)
        sampler.addSample(13, time: 2)

        XCTAssertEqual(sampler.velocity.valuePerSecond, 8.25, accuracy: 1.0e-12)
    }

    func testOlderSampleIsIgnored() {
        var sampler = VelocitySampler<Double>()

        sampler.addSample(0, time: 1)
        sampler.addSample(100, time: 0.5)
        sampler.addSample(4, time: 2)

        XCTAssertEqual(sampler.lastTime, 2)
        XCTAssertEqual(sampler.velocity.valuePerSecond, 4, accuracy: 1.0e-12)
    }
}
