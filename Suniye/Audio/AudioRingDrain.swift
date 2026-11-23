import Foundation

/// A ring that the audio thread writes and the owner's serial queue reads every
/// 20 ms. Only the ring itself is thread-safe: call everything else on the queue.
final class AudioRingDrain {
    private static let capacity = 1_048_576
    private static let blockCapacity = 32_768

    let ring: OpaquePointer
    private let queue: DispatchQueue
    private let block: UnsafeMutablePointer<Float>
    private var timer: DispatchSourceTimer?

    init(queue: DispatchQueue) throws {
        guard let ring = SuniyeAudioRingBufferCreate(Self.capacity) else {
            throw AudioCaptureServiceError.ringBufferUnavailable
        }
        self.ring = ring
        self.queue = queue
        block = .allocate(capacity: Self.blockCapacity)
    }

    deinit {
        timer?.cancel()
        SuniyeAudioRingBufferDestroy(ring)
        block.deallocate()
    }

    var droppedSampleCount: UInt64 {
        SuniyeAudioRingBufferDroppedSamples(ring)
    }

    /// Call only while no writer runs.
    func reset() {
        SuniyeAudioRingBufferReset(ring)
    }

    func startTimer(onTick: @escaping () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20), leeway: .milliseconds(4))
        timer.setEventHandler(handler: onTick)
        self.timer = timer
        timer.resume()
    }

    func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    /// Hands each block to `body` until the ring is empty or `body` returns
    /// false. A `body` that reads the ring again must return false: the block
    /// it holds is then overwritten.
    func read(_ body: (UnsafeBufferPointer<Float>) -> Bool) {
        var count = SuniyeAudioRingBufferRead(ring, block, Self.blockCapacity)
        while count > 0 {
            guard body(UnsafeBufferPointer(start: block, count: count)) else { return }
            count = SuniyeAudioRingBufferRead(ring, block, Self.blockCapacity)
        }
    }
}
