//
//  File: ClothBody.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public final class ClothBody: XPBDBody {
    public var particles: [XPBDParticle]

    public init(particles: [XPBDParticle] = []) {
        self.particles = particles
    }
}
