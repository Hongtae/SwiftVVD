import Foundation
import OpenAL

public class AudioDeviceContext {
    public let device: AudioDevice
    public let listener: AudioListener

    struct Player {
        weak var player: AudioPlayer?
    }
    private var players: [Player] = []
    private let lock = NSLock()

    public init(device: AudioDevice) {
        self.device = device
        self.listener = AudioListener(device: self.device)

        Task.detached(priority: .background) { @AudioActor [weak self] in
            numberOfThreadsToWaitBeforeExiting.increment()
            defer { numberOfThreadsToWaitBeforeExiting.decrement() }

            Log.info("AudioDeviceContext playback task is started.")

            var buffer: UnsafeMutableRawBufferPointer = .allocate(byteCount: 1024, alignment: 1)

            while true {
                guard let self = self else { break }

                let players: [AudioPlayer] = synchronizedBy(locking: self.lock) {
                    let r = self.players.compactMap{ $0.player }
                    self.players = r.map { Player(player: $0) }
                    return r
                }

                let maxBufferCount = 3

                // update all active audio streams!
                for player in players {
                    let source = player.source
                    let bufferSize = player.bufferSize
                    if bufferSize > 0 {
                        if source.numberOfBuffersInQueue() >= maxBufferCount { continue }

                        let stream = player.stream
                        if bufferSize > buffer.count {
                            buffer.deallocate()
                            buffer = .allocate(byteCount: player.bufferSize, alignment: 1)
                        }

                        let bufferPos = stream.timePosition
                        let bytesRead = stream.read(buffer.baseAddress!, count: bufferSize)
                        if bytesRead > 0 {
                            if player.buffering == false {
                                player.buffering = true
                                player.bufferingStateChanged(true, timeStamp: bufferPos)
                            }
                            player.processStream(data: buffer.baseAddress!, byteCount: bufferSize, timeStamp: bufferPos)

                            if source.enqueueBuffer(sampleRate: stream.sampleRate,
                                                    bits: stream.bits,
                                                    channels: stream.channels,
                                                    data: buffer.baseAddress!,
                                                    byteCount: bufferSize,
                                                    timeStamp: bufferPos) {
                                source.state = .playing
                                player.playing = true
                                player.bufferedPosition = stream.timePosition
                            } else {    // error
                                Log.err("AudioSource.enqueueBuffer failed")

                                player.buffering = false
                                player.playing = false

                                player.bufferingStateChanged(false, timeStamp: stream.timePosition)
                                player.playbackStateChanged(false, position: player.playbackPosition)
                            }
                        } else if bytesRead == 0 {  // buffering finished.
                            source.dequeueBuffers()
                            if player.playLoopCount > 1 {
                                player.playLoopCount -= 1
                                _=stream.seek(pcm: 0)   // rewind
                                if player.playing == false {
                                    player.playing = true
                                    player.playbackStateChanged(true, position: player.playbackPosition)
                                } else {
                                    if player.buffering {
                                        player.buffering = false
                                        player.bufferingStateChanged(false, timeStamp: stream.timePosition)
                                    }

                                    if source.state != .playing {
                                        if player.playing {
                                            player.playing = false
                                            player.playbackStateChanged(false, position: player.playbackPosition)
                                        }
                                    }
                                }

                            }

                        } else { // error, stop playing
                            Log.err("AudioStream.read failed.")
                        }
                    } else { // bufferSize == 0
                        source.dequeueBuffers()

                        if source.state != .playing {
                            if player.playing {
                                player.playing = false
                                player.playbackStateChanged(false, position: player.playbackPosition)
                            }
                        }
                        if player.buffering {
                            player.buffering = false
                            player.bufferingStateChanged(false, timeStamp: player.bufferedPosition)
                        }
                    }

                    if player.playing {
                        player.playbackPosition = source.timePosition
                        player.playbackStateChanged(true, position: player.playbackPosition)
                    }                    
                }

                //await Task.yield()
                do {
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                } catch {
                    await Task.yield()
                }
            }

            buffer.deallocate()

            Log.info("AudioDeviceContext playback task is finished.")
        }
    }

    deinit {
        self.players.removeAll()
    }

    public func makePlayer(stream: AudioStream) async -> AudioPlayer? {
        if let source = device.makeSource() {
            let t = Task { @AudioActor ()-> AudioPlayer in
                let player = AudioPlayer(source: source, stream: stream)
                synchronizedBy(locking: self.lock) {
                    self.players.append(Player(player: player))
                }
                return player
            }
            return await t.value
        }
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
