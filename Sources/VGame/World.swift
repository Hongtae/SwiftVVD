//
//  File: World.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public final class World {
    public let physics: WorldPhysics

    public init<Content>(physics: WorldPhysics = WorldPhysics(),
                         @EntityBuilder content: () -> Content) where Content: Entity {
        self.physics = physics
    }
}
