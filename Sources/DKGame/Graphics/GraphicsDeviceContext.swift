public class GraphicsDeviceContext {
    public let device: GraphicsDevice
    public var cachedDeviceResources: [String: AnyObject] = [:]

    public init(device: GraphicsDevice) {
        self.device = device
    }

    deinit {
        self.cachedDeviceResources.removeAll()        
        self.renderQueues.removeAll()
        self.computeQueues.removeAll()
        self.copyQueues.removeAll()
    }

    // cached command queue.
    public func renderQueue() -> CommandQueue? {
        if renderQueues.isEmpty {
            if let queue = device.makeCommandQueue(flags: .render) {
                if queue.flags.contains(.render) {
                    renderQueues.append(queue)
                }
                if queue.flags.contains(.compute) {
                    computeQueues.append(queue)
                }
                copyQueues.append(queue)

                if queue.flags.contains(.render) {
                    return queue
                }
            }                        
        }
        return renderQueues.first
    }

    public func computeQueue() -> CommandQueue? {
        if computeQueues.isEmpty {
            if let queue = device.makeCommandQueue(flags: .compute) {
                if queue.flags.contains(.render) {
                    renderQueues.append(queue)
                }
                if queue.flags.contains(.compute) {
                    computeQueues.append(queue)
                }
                copyQueues.append(queue)

                if queue.flags.contains(.compute) {
                    return queue
                }
            }                        
        }
        return computeQueues.first
    }

    public func copyQueue() -> CommandQueue? {
        if copyQueues.isEmpty {
            if let queue = device.makeCommandQueue(flags: .copy) {
                if queue.flags.contains(.render) {
                    renderQueues.append(queue)
                }
                if queue.flags.contains(.compute) {
                    computeQueues.append(queue)
                }
                copyQueues.append(queue)

                return queue
            }                        
        }
        return copyQueues.first
    }

    private var renderQueues: [CommandQueue] = []
    private var computeQueues: [CommandQueue] = []
    private var copyQueues: [CommandQueue] = []
}

public func makeGraphicsDeviceContext(api: GraphicsAPI = .auto) -> GraphicsDeviceContext?  {
    if let device = makeGraphicsDevice(api: api) {
        return GraphicsDeviceContext(device: device)
    }
    return nil
}
