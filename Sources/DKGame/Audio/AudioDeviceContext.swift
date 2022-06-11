import Foundation
import OpenAL

public struct AudioListener {
    public var gain: Float = 0.0
    public var position: Vector3 = .zero
    public var orientation: Matrix3 = .identity

    public var forward: Vector3 = Vector3(x: 0, y: 0, z: -1)
    public var up: Vector3 = Vector3(x: 0, y: 1, z: 0)
}

public class AudioDeviceContext {
    public let device: AudioDevice
    public let listener: AudioListener
    public let context: ALCcontext

    public private(set) var players: [AudioPlayer] = []
    private let lock = NSLock()

    public init?(device: AudioDevice) {
        guard let context = alcCreateContext(device.device, nil) else { return nil }

        self.device = device
        self.context = context
        alcMakeContextCurrent(self.context)

        self.listener = AudioListener()

        Task.detached(priority: .background) { @AudioActor [weak self] in
            numberOfThreadsToWaitBeforeExiting.increment()
            defer { numberOfThreadsToWaitBeforeExiting.decrement() }

            Log.info("AudioDeviceContext playback task is started.")

            while true {
                guard let self = self else { break }

                let players = synchronizedBy(locking: self.lock) {
                    self.players
                }

                // update all active audio streams!
                for player in players {
                    if player.source?.state == .playing {
                        //guard let stream = player.stream else { continue }
                        //let source = player.source!


                    }
                }

                await Task.yield()
            }

            Log.info("AudioDeviceContext playback task is finished.")
        }
    }

    deinit {
        if alcGetCurrentContext() == self.context {
            alcMakeContextCurrent(nil)
        }
        alcDestroyContext(self.context)
    }

    public func makePlayer(stream: AudioStream) -> AudioPlayer? {
        return nil
    }
}

public func makeAudioDeviceContext() -> AudioDeviceContext? {
    let devices = AvailableALDevices()
    if devices.count > 0 {
        if let device = AudioDevice(deviceName: devices[0].name) {
            return AudioDeviceContext(device: device)
        }
    }
    return nil
}
