import XCTest
@testable import VUI

final class GeometryEffectSurfaceTests: XCTestCase {
    func testIdentityEffectCanonicalizationUnwrapsOneChild() throws {
        let childIdentity = _DisplayList_Identity()
        var contents = DisplayList()
        contents.appendItem(
            kind: .text,
            bounds: CGRect(x: 2, y: 3, width: 4, height: 5)
        ) { _ in }
        contents.items[0].identity = childIdentity
        contents.items[0].version = DisplayList.Version(value: 7)

        var item = DisplayList.Item(
            effect: .identity,
            contents: contents,
            frame: CGRect(x: 10, y: 20, width: 30, height: 40),
            identity: _DisplayList_Identity(),
            version: DisplayList.Version(value: 3)
        )
        item.canonicalize(options: [])

        XCTAssertEqual(item.frame, CGRect(x: 12, y: 23, width: 4, height: 5))
        XCTAssertEqual(item.version, DisplayList.Version(value: 7))
        XCTAssertEqual(item.identity, childIdentity)
        guard case .content = item.value else {
            return XCTFail("A one-child identity effect must unwrap its child value")
        }
    }

    func testIdentityEffectCanonicalizationHonorsDisableOption() {
        var contents = DisplayList()
        contents.appendItem(
            kind: .text,
            bounds: CGRect(x: 2, y: 3, width: 4, height: 5)
        ) { _ in }
        var item = DisplayList.Item(
            effect: .identity,
            contents: contents,
            frame: CGRect(x: 10, y: 20, width: 30, height: 40)
        )

        item.canonicalize(options: .disableCanonicalization)

        XCTAssertEqual(item.frame, CGRect(x: 10, y: 20, width: 30, height: 40))
        guard case .effect(.identity, _) = item.value else {
            return XCTFail("Disabled canonicalization must retain the wrapper")
        }
    }

    // ASSERTIONS displayListAddEffectLocalOriginNormalizationObserved
    func testAddEffectRetainsOuterFrameAndNormalizesChildOrigin() throws {
        var source = DisplayList()
        source.appendItem(
            bounds: CGRect(x: -9, y: 4, width: 48, height: 48)
        ) { _ in }
        var item = try XCTUnwrap(source.items.first)
        let originalFrame = item.frame

        item.addEffect(.identity)

        XCTAssertEqual(item.frame, originalFrame)
        guard case let .effect(.identity, contents) = item.value else {
            return XCTFail("Expected the added effect wrapper")
        }
        let child = try XCTUnwrap(contents.items.first)
        XCTAssertEqual(child.frame.origin, .zero)
        XCTAssertEqual(child.frame.size, originalFrame.size)
        XCTAssertEqual(contents.interpolationBounds, child.frame)
    }

    func testIgnoredByLayoutForwardsEffectAndAnimatableData() {
        var ignored = ProbeGeometryEffect(x: 3).ignoredByLayout()

        XCTAssertEqual(MemoryLayout.size(ofValue: ignored), 8)
        XCTAssertEqual(MemoryLayout.stride(ofValue: ignored), 8)
        XCTAssertEqual(MemoryLayout.alignment(ofValue: ignored), 8)
        XCTAssertFalse(type(of: ignored)._affectsLayout)

        assertTransform(
            ignored.effectValue(size: CGSize(width: 10, height: 8)),
            [1, 0, 0, 0, 1, 0, 13, 4, 1]
        )
        XCTAssertEqual(ignored.animatableData, 3)

        ignored.animatableData = 7
        XCTAssertEqual(ignored.animatableData, 7)
        assertTransform(
            ignored.effectValue(size: CGSize(width: 10, height: 8)),
            [1, 0, 0, 0, 1, 0, 17, 4, 1]
        )

        XCTAssertEqual(ignored, ProbeGeometryEffect(x: 7).ignoredByLayout())
        XCTAssertNotEqual(ignored, ProbeGeometryEffect(x: 8).ignoredByLayout())

        let offsetIgnored = _OffsetEffect(offset: CGSize(width: 2, height: 5)).ignoredByLayout()
        XCTAssertEqual(MemoryLayout.size(ofValue: offsetIgnored), 16)
        XCTAssertEqual(MemoryLayout.stride(ofValue: offsetIgnored), 16)
        XCTAssertEqual(MemoryLayout.alignment(ofValue: offsetIgnored), 8)
        XCTAssertFalse(type(of: offsetIgnored)._affectsLayout)
        XCTAssertEqual(offsetIgnored.animatableData.first, 2)
        XCTAssertEqual(offsetIgnored.animatableData.second, 5)
    }

    func testProjectionAndTransformEffectsUseStoredTransforms() {
        var projection = ProjectionTransform(
            CGAffineTransform(a: 1.5, b: 0.2, c: -0.3, d: 2.0, tx: 7, ty: -5)
        )
        projection.m13 = 0.125
        projection.m23 = -0.25
        projection.m33 = 0.75

        let projectionEffect = _ProjectionEffect(transform: projection)
        XCTAssertEqual(MemoryLayout.size(ofValue: projectionEffect), 72)
        XCTAssertEqual(MemoryLayout.stride(ofValue: projectionEffect), 72)
        XCTAssertEqual(MemoryLayout.alignment(ofValue: projectionEffect), 8)
        assertTransform(
            projectionEffect.effectValue(size: CGSize(width: 80, height: 40)),
            [1.5, 0.2, 0.125, -0.3, 2.0, -0.25, 7.0, -5.0, 0.75]
        )
        XCTAssertEqual(projectionEffect.animatableData, EmptyAnimatableData())
        XCTAssertEqual(projectionEffect, _ProjectionEffect(transform: projection))

        var differentProjection = projection
        differentProjection.m31 += 1
        XCTAssertNotEqual(projectionEffect, _ProjectionEffect(transform: differentProjection))

        let affine = CGAffineTransform(a: 1.25, b: 0.5, c: -0.25, d: 1.75, tx: 9, ty: -3)
        let transformEffect = _TransformEffect(transform: affine)
        XCTAssertEqual(MemoryLayout.size(ofValue: transformEffect), 48)
        XCTAssertEqual(MemoryLayout.stride(ofValue: transformEffect), 48)
        XCTAssertEqual(MemoryLayout.alignment(ofValue: transformEffect), 8)
        assertTransform(
            transformEffect.effectValue(size: CGSize(width: 80, height: 40)),
            [1.25, 0.5, 0, -0.25, 1.75, 0, 9, -3, 1]
        )
        XCTAssertEqual(transformEffect.animatableData, EmptyAnimatableData())
        XCTAssertEqual(transformEffect, _TransformEffect(transform: affine))
        XCTAssertNotEqual(transformEffect, _TransformEffect(transform: affine.translatedBy(x: 1, y: 0)))

        XCTAssertTrue(ProjectionTransform().isAffine)
        XCTAssertTrue(ProjectionTransform(CGAffineTransform(translationX: 3, y: 4)).isAffine)
        XCTAssertTrue(ProjectionTransform().isInvertible)

        var perspective = ProjectionTransform()
        perspective.m13 = 0.01
        XCTAssertFalse(perspective.isAffine)

        var singular = ProjectionTransform()
        singular.m11 = 0
        XCTAssertFalse(singular.isInvertible)
    }

    func testViewTransformInverseFlagPreservesBothStoredDirections() {
        let affine = CGAffineTransform(
            a: 1.5,
            b: 0,
            c: 0.25,
            d: 2,
            tx: 7,
            ty: -5
        )
        let localPoints = [
            CGPoint(x: 4, y: 6),
            CGPoint(x: 12, y: -3),
        ]
        let expectedGlobal = localPoints.map { $0.applying(affine) }

        var forwardStored = ViewTransform.identity
        forwardStored.appendProjectionTransform(
            ProjectionTransform(affine),
            inverse: true
        )
        var forwardGlobal = localPoints
        forwardStored.convertGlobal(from: .local, points: &forwardGlobal)
        XCTAssertEqual(forwardGlobal, expectedGlobal)
        forwardStored.convertGlobal(to: .local, points: &forwardGlobal)
        assertPointsEqual(forwardGlobal, localPoints)

        var inverseStored = ViewTransform.identity
        inverseStored.appendAffineTransform(affine.inverted(), inverse: false)
        var inverseGlobal = localPoints
        inverseStored.convertGlobal(from: .local, points: &inverseGlobal)
        XCTAssertEqual(inverseGlobal, expectedGlobal)
        inverseStored.convertGlobal(to: .local, points: &inverseGlobal)
        assertPointsEqual(inverseGlobal, localPoints)
    }

    func testRotation3DEffectMatrixAndAnimatableDataScaling() {
        XCTAssertEqual(MemoryLayout<_Rotation3DEffect>.size, 64)
        XCTAssertEqual(MemoryLayout<_Rotation3DEffect>.stride, 64)
        XCTAssertEqual(MemoryLayout<_Rotation3DEffect>.alignment, 8)

        assertRotation3D(
            "zeroY",
            _Rotation3DEffect(angle: .degrees(0), axis: (x: 0, y: 1, z: 0)),
            [1, 0, 0, 0, 1, 0, 0, 0, 1],
            isAffine: true
        )
        assertRotation3D(
            "y90",
            _Rotation3DEffect(angle: .degrees(90), axis: (x: 0, y: 1, z: 0)),
            [0.5, 0.333333, 0.008333, 0, 1, 0, 30, -20, 0.5],
            isAffine: false
        )
        assertRotation3D(
            "x45",
            _Rotation3DEffect(angle: .degrees(45), axis: (x: 1, y: 0, z: 0)),
            [1, 0, 0, -0.353553, 0.471405, -0.005893, 14.142136, 21.143819, 1.235702],
            isAffine: false
        )
        assertRotation3D(
            "z30",
            _Rotation3DEffect(angle: .degrees(30), axis: (x: 0, y: 0, z: 1)),
            [0.866025, 0.5, 0, -0.5, 0.866025, 0, 28.038476, -24.641016, 1],
            isAffine: true
        )
        assertRotation3D(
            "mixed",
            _Rotation3DEffect(
                angle: .degrees(60),
                axis: (x: 1, y: 2, z: 3),
                anchor: UnitPoint(x: 0.25, y: 0.75),
                anchorZ: 5,
                perspective: 0.5
            ),
            [0.580185, 0.854735, 0.001482, -0.678654, 0.531422, -0.001857, 50.976819, 3.585251, 1.084077],
            isAffine: false
        )
        assertRotation3D(
            "zeroAxis",
            _Rotation3DEffect(
                angle: .degrees(60),
                axis: (x: 0, y: 0, z: 0),
                anchor: UnitPoint(x: 0.25, y: 0.75),
                anchorZ: 5,
                perspective: 0.5
            ),
            [1, 0, 0, 0, 1, 0, 0.625, 1.25, 1.020833],
            isAffine: false
        )

        var effect = _Rotation3DEffect(
            angle: .degrees(60),
            axis: (x: 1, y: 2, z: 3),
            anchor: UnitPoint(x: 0.25, y: 0.75),
            anchorZ: 5,
            perspective: 0.5
        )
        let data = effect.animatableData
        XCTAssertEqual(data.first, Angle.degrees(60).radians * 128, accuracy: 0.000_001)
        XCTAssertEqual(data.second.first, 128, accuracy: 0.000_001)
        XCTAssertEqual(data.second.second.first, 256, accuracy: 0.000_001)
        XCTAssertEqual(data.second.second.second.first, 384, accuracy: 0.000_001)
        XCTAssertEqual(data.second.second.second.second.first.first, 32, accuracy: 0.000_001)
        XCTAssertEqual(data.second.second.second.second.first.second, 96, accuracy: 0.000_001)
        XCTAssertEqual(data.second.second.second.second.second.first, 5, accuracy: 0.000_001)
        XCTAssertEqual(data.second.second.second.second.second.second, 64, accuracy: 0.000_001)

        var mutatedData = data
        mutatedData.first += 0.25
        mutatedData.second.first += 0.5
        mutatedData.second.second.first += 0.75
        mutatedData.second.second.second.first += 1.0
        mutatedData.second.second.second.second.first.first += 0.125
        mutatedData.second.second.second.second.first.second += 0.25
        mutatedData.second.second.second.second.second.first += 1.25
        mutatedData.second.second.second.second.second.second += 0.375
        effect.animatableData = mutatedData

        XCTAssertEqual(effect.angle.radians, Angle.degrees(60).radians + 0.25 / 128, accuracy: 0.000_001)
        XCTAssertEqual(effect.axis.x, 1 + 0.5 / 128, accuracy: 0.000_001)
        XCTAssertEqual(effect.axis.y, 2 + 0.75 / 128, accuracy: 0.000_001)
        XCTAssertEqual(effect.axis.z, 3 + 1.0 / 128, accuracy: 0.000_001)
        XCTAssertEqual(effect.anchor.x, 0.25 + 0.125 / 128, accuracy: 0.000_001)
        XCTAssertEqual(effect.anchor.y, 0.75 + 0.25 / 128, accuracy: 0.000_001)
        XCTAssertEqual(effect.anchorZ, 6.25, accuracy: 0.000_001)
        XCTAssertEqual(effect.perspective, 0.5 + 0.375 / 128, accuracy: 0.000_001)

        XCTAssertEqual(
            _Rotation3DEffect(
                angle: .degrees(20),
                axis: (x: 1, y: 2, z: 3),
                anchor: UnitPoint(x: 0.1, y: 0.2),
                anchorZ: 4,
                perspective: 0.7
            ),
            _Rotation3DEffect(
                angle: .degrees(20),
                axis: (x: 1, y: 2, z: 3),
                anchor: UnitPoint(x: 0.1, y: 0.2),
                anchorZ: 4,
                perspective: 0.7
            )
        )
        XCTAssertNotEqual(
            _Rotation3DEffect(
                angle: .degrees(20),
                axis: (x: 1, y: 2, z: 3),
                anchor: UnitPoint(x: 0.1, y: 0.2),
                anchorZ: 4,
                perspective: 0.7
            ),
            _Rotation3DEffect(
                angle: .degrees(20),
                axis: (x: 1, y: 2, z: 3.1),
                anchor: UnitPoint(x: 0.1, y: 0.2),
                anchorZ: 4,
                perspective: 0.7
            )
        )
    }

    private func assertRotation3D(
        _ label: String,
        _ effect: _Rotation3DEffect,
        _ expected: [CGFloat],
        isAffine: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let transform = effect.effectValue(size: CGSize(width: 120, height: 80))
        assertTransform(transform, expected, file: file, line: line)
        XCTAssertEqual(transform.isAffine, isAffine, label, file: file, line: line)
    }
}

private struct ProbeGeometryEffect: GeometryEffect, Equatable {
    var x: CGFloat

    var animatableData: CGFloat {
        get { x }
        set { x = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: x + size.width,
                y: size.height * 0.5
            )
        )
    }
}

private func assertTransform(
    _ actual: ProjectionTransform,
    _ expected: [CGFloat],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(expected.count, 9, file: file, line: line)
    guard expected.count == 9 else { return }

    let actualValues = [
        actual.m11, actual.m12, actual.m13,
        actual.m21, actual.m22, actual.m23,
        actual.m31, actual.m32, actual.m33,
    ]
    for index in actualValues.indices {
        XCTAssertEqual(
            actualValues[index],
            expected[index],
            accuracy: 0.000_001,
            "index \(index)",
            file: file,
            line: line
        )
    }
}

private func assertPointsEqual(
    _ actual: [CGPoint],
    _ expected: [CGPoint],
    accuracy: CGFloat = 0.000_001,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for (actual, expected) in zip(actual, expected) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    }
}
