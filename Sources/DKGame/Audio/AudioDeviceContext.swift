import Foundation
import OpenAL

public class AudioDeviceContext {
    public let device: AudioDevice
    public let listener: AudioListener

    public private(set) var players: [AudioPlayer] = []
    private let lock = NSLock()

    public init(device: AudioDevice) {
        self.device = device
        self.listener = AudioListener(device: self.device)

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
                    if player.source.state == .playing {
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
        self.players.removeAll()
    }

    public func makePlayer(stream: AudioStream) -> AudioPlayer? {
        if let source = device.makeSource() {
            let player = AudioPlayer(source: source, stream: stream)
            player.playbackContext = self
            return player
        }
        return nil
    }

    func bindPlayer(_ player: AudioPlayer) {
        synchronizedBy(locking: self.lock) {
            if self.players.contains(where: { $0 === player }) == false {
                self.players.append(player)
            }
        }
    }

    func unbindPlayer(_ player: AudioPlayer) {
        synchronizedBy(locking: self.lock) {
            if let index = self.players.firstIndex(where: { $0 === player } ) {
                self.players.remove(at: index)
            }
        }
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
