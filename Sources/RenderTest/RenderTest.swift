import Foundation
import VVD

@main
class RenderTestApp: ApplicationDelegate, WindowDelegate, @unchecked Sendable {
    var window: Window?
    var renderTask: Task<Void, Never>?
    var graphicsContext: GraphicsDeviceContext?
    var appResourcesRoot: String = ""

    let cond = NSCondition()
    var running = false

    func initialize(application: any Application) {
        appResourcesRoot = Bundle.module.resourcePath!
        Log.debug("initialize: (resource-root: \(appResourcesRoot))")

        guard let graphicsContext = GraphicsDeviceContext.makeDefault()
        else {
            fatalError("GraphicsDeviceContext.makeDefault failed")
        }
        guard let window = makeWindow(name: "RenderTest", style: .genericWindow, delegate: self)
        else {
            fatalError("makeWindow failed")
        }

        window.contentSize = CGSize(width: 1024, height: 768)
        window.activate()

        self.graphicsContext = graphicsContext
        self.window = window

        self.running = true
        renderTask = .detached {
            await self.renderLoop()
            self.cond.withLock {
                self.running = false
                self.cond.broadcast()
            }
        }
    }

    func finalize(application: any Application) {
        renderTask?.cancel()
        self.cond.withLock {
            while running { cond.wait() }
        }
        window = nil
        graphicsContext = nil
    }

    func minimumContentSize(window: Window) -> CGSize? {
        CGSize(width: 100, height: 100)
    }

    func shouldClose(window: Window) -> Bool {
        // stop render thread
        sharedApplication()?.terminate(exitCode: 1234)
        return true
    }

    func renderLoop() async {
        let queue = self.graphicsContext?.renderQueue()
        guard let queue else {
            fatalError("graphicsContext.renderQueue() failed")
        }
        let swapchain = await queue.makeSwapChain(target: self.window!)
        guard let swapchain else {
            fatalError("makeSwapChain failed")
        }
        let device = queue.device

        // load shader
        let vsPath = appResourcesRoot + "/Shaders/sample.vert.spv"
        let fsPath = appResourcesRoot + "/Shaders/sample.frag.spv"
        guard let vertexShader = loadShader(from: vsPath, device: device) else {
            fatalError("Failed to load vertex shader")
        }
        guard let fragmentShader = loadShader(from: fsPath, device: device) else {
            fatalError("Failed to load fragment shader")
        }

        // setup shader binding
        var shader = MaterialShaderMap(functions: [], resourceSemantics: [:], inputAttributeSemantics: [:])
        shader.resourceSemantics = [
            .location(set: 0, binding: 1, offset: 0): .material(.baseColorTexture),
            .pushConstant(offset: 0): .uniform(.modelViewProjectionMatrix),
            // .pushConstant(offset: 64): .material(.userDefined),
            // .pushConstant(offset: 80): .material(.userDefined),
            // .pushConstant(offset: 96): .material(.userDefined),
        ]
        shader.inputAttributeSemantics = [
            0: .position,
            1: .normal,
            2: .textureCoordinates
        ]
        shader.functions = [ vertexShader, fragmentShader ]

        // load gltf
        let modelPath = appResourcesRoot + "/glTF/Duck/glTF-Binary/Duck.glb"
        let model = loadModel(from: modelPath, shader: shader, queue: queue)
        guard let model else {
            fatalError("Failed to load glTF at path: '\(modelPath)\'.")
        }

        let camPosition = Vector3(0, 120, 200)
        let camTarget = Vector3(0, 100, 0)
        let fov = (80.0).degreeToRadian()

        var sceneState = SceneState(
            view: ViewTransform(position: camPosition,
                                direction: camTarget - camPosition,
                                up: Vector3(0, 1, 0)),
            projection: .perspective(aspect: 1.0,
                                     fov: fov,
                                     near: 1.0,
                                     far: 1000.0),
            model: .identity)

        let meshes: [Mesh] = model.scenes.flatMap {
            var meshes: [Mesh] = []
            $0.forEachNode { node, transform in
                if let mesh = node.mesh {
                    meshes.append(mesh)
                }
            }
            return meshes
        }

        let depthFormat = PixelFormat.depth32Float
        var depthTexture: Texture? = nil

        // set user-defined property values
        let lightDir = Vector3(1, -1, 1)
        let lightColor = Vector3(1, 1, 1)
        let ambientColor = Vector3(0.3, 0.3, 0.3)

        let structuredBufferBinding = false
        if structuredBufferBinding {
            let pcData = (lightDir: lightDir.float3, _: Float(0),
                          lightColor: lightColor.float3, _: Float(0),
                          ambientColor: ambientColor.float3, _: Float(0))

            let data = withUnsafeBytes(of: pcData) {
                MaterialProperty.data($0)
            }
            meshes.forEach {
                if let material = $0.material {
                    material.attachments[0].format = swapchain.pixelFormat
                    material.depthFormat = depthFormat
                    material.userDefinedProperties[.pushConstant(offset: 64)] = data
                }
            }
        } else {
            meshes.forEach {
                if let material = $0.material {
                    material.attachments[0].format = swapchain.pixelFormat
                    material.depthFormat = depthFormat
                    material.userDefinedProperties[.pushConstant(offset: 64)] = .vector(lightDir)
                    material.userDefinedProperties[.pushConstant(offset: 80)] = .vector(lightColor)
                    material.userDefinedProperties[.pushConstant(offset: 96)] = .vector(ambientColor)
                }
            }
        }

        // build pipeline-states (PSO)
        meshes.forEach { mesh in
            var reflection = PipelineReflection()
            if mesh.buildPipelineState(device: device, reflection: &reflection) {
                printPipelineReflection(reflection, logLevel: .debug)
                if !mesh.initResources(device: device, bufferPolicy: .singleBuffer) {
                    Log.error("Mesh.initResources failed")
                }
            } else {
                Log.error("Failed to make pipeline descriptor")
            }
            mesh.updateShadingProperties(sceneState: sceneState)
        }

        let depthStencilState = device.makeDepthStencilState(
            descriptor: DepthStencilDescriptor(depthCompareFunction: .lessEqual,
                                               isDepthWriteEnabled: true))
        guard let depthStencilState else {
            fatalError("device.makeDepthStencilState failed.")
        }

        let frameInterval = 1.0 / 60.0  // 60fps
        var timestamp = SuspendingClock.now
        var delta = 0.0
        var modelTransform: Transform = .identity

        while Task.isCancelled == false {
            var rp = swapchain.currentRenderPassDescriptor()

            let frontAttachment = rp.colorAttachments[0]
            let width = frontAttachment.renderTarget!.width
            let height = frontAttachment.renderTarget!.height

            if depthTexture == nil || depthTexture?.width != width || depthTexture?.height != height {
                // (re)create depth-buffer
                depthTexture = device.makeTransientRenderTarget(type: .type2D,
                                                                pixelFormat: depthFormat,
                                                                width: width,
                                                                height: height,
                                                                depth: 1)
            }

            rp.colorAttachments[0].clearColor = .nonLinearMint
            rp.depthStencilAttachment.renderTarget = depthTexture
            rp.depthStencilAttachment.loadAction = .clear
            rp.depthStencilAttachment.storeAction = .dontCare

            guard let buffer = queue.makeCommandBuffer() else {
                fatalError("queue.makeCommandBuffer failed.")
            }
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: rp) else {
                fatalError("buffer.makeRenderCommandEncoder failed")
            }

            encoder.setDepthStencilState(depthStencilState)
            let angle = delta * .pi * 0.4
            let aspect = Scalar(width) / Scalar(height)
            modelTransform.orientation.concatenate(Quaternion(angle: angle, axis: Vector3(0, 1, 0)))
            sceneState.model = modelTransform.matrix4
            sceneState.projection = .perspective(aspect: aspect,
                                                 fov: fov,
                                                 near: 1.0,
                                                 far: 1000.0)

            model.scenes[model.defaultSceneIndex].forEachNode { node, transform in
                if let mesh = node.mesh {
                    mesh.updateShadingProperties(sceneState: sceneState)
                    mesh.encodeRenderCommand(encoder: encoder)
                }
            }
            encoder.endEncoding()
            buffer.commit()

            let interval: Double = max(frameInterval - timestamp.elapsed, .zero)
            if interval > .zero {
                try? await Task.sleep(for: .seconds(interval))
            } else {
                await Task.yield()
            }

            swapchain.present()

            let t = SuspendingClock.now
            delta = (t - timestamp).seconds
            timestamp = t
        }
    }

    static func main() {
        let app = RenderTestApp()
        runApplication(delegate: app)
    }
}

public extension Duration {
    var seconds: Double {
        let components = self.components
        let nanoseconds = Double(components.attoseconds / 1_000_000_000) / Double(1_000_000_000)
        return Double(components.seconds) + nanoseconds
    }
}

public extension SuspendingClock.Instant {
    var elapsed: Double {
        self.duration(to: .now).seconds
    }
}
