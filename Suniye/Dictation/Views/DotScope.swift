// The listening wave: a field of dots lit by a braided pair of oscilloscope
// traces that follow the voice, and, while the dictation is processed, light
// that flows through the same braid. The shimmer of the formatting step is
// Suniye's own.
//
// Ported from Hex (https://github.com/kitlangton/hex), src/rune_hud/dot_scope.rs
// and src/rune_hud/dot_scope/scope.rs at e117dbe0, and the dot drawing of
// src/rune_hud.wgsl:
//
// MIT License
//
// Copyright (c) 2026 Christopher Langton
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import SwiftUI

/// What the field shows: the voice while the microphone records, light that
/// flows through the braid while the dictation is transcribed, and a shimmer
/// over a dimmer flow while Magic Format works on the text.
enum DotScopeStage: Equatable {
    case listening
    case working
    case formatting
}

/// The microphone's loudness for the field, written by the controller at the
/// capture rate and read by the field once a frame, both on the main thread.
/// It is a plain reference so that a level update never invalidates a view.
final class DotScopeVoice {
    /// The microphone's latest loudness, dBFS.
    var loudness: Float = AudioLevelMeter.silentLoudness
    /// The speaker's recent peak and the room, kept across dictations.
    var autoLevel = DotScopeAutoLevel()
}

/// Hex's slow auto level: the loudest the speaker has recently been reads as
/// full and the room as silent, so a quiet microphone and a loud one move the
/// field alike. The peak rises within 40 ms and falls back over the release;
/// the room level falls to any quieter moment in 0.3 s and creeps up over 6 s,
/// so speech never becomes the room.
struct DotScopeAutoLevel: Equatable {
    private(set) var peak: Float = -30
    private(set) var room: Float = -55

    private static let minimumSpan: Float = 16
    private static let range: Float = 24
    private static let roomMargin: Float = 5
    private static let attack: Float = 0.04
    private static let roomFall: Float = 0.3
    private static let roomRise: Float = 6

    mutating func step(loudness: Float, step h: Float, release: Float, noiseFloor: Float) -> Float {
        let db = max(loudness, -120)
        func follow(_ value: inout Float, _ target: Float, _ time: Float) {
            value += (target - value) * (1 - exp(-h / max(time, 1e-3)))
        }
        follow(&room, db, db < room ? Self.roomFall : Self.roomRise)
        let lowest = max(room, noiseFloor) + Self.minimumSpan
        if db > peak {
            follow(&peak, db, Self.attack)
        } else {
            follow(&peak, lowest, release)
        }
        peak = max(peak, lowest)
        return level(db, noiseFloor: noiseFloor)
    }

    func level(_ loudness: Float, noiseFloor: Float) -> Float {
        let low = max(max(room, noiseFloor) + Self.roomMargin, peak - Self.range)
        return min(max((loudness - low) / max(peak - low, 1), 0), 1)
    }
}

/// The field's simulation. It steps the voice and the traces at a fixed
/// 240 Hz, traces the field once a drawn frame, and yields one (brightness,
/// freshness) pair per dot.
final class DotScope {
    struct Tuning {
        var columns = 47
        var rows = 11
        /// Dot pitch, pt.
        var spacing: Float = 2.6
        var braidSpeed: Float = 1
        /// Helix turns across the plate.
        var helixCycles: Float = 1.6
        var gain: Float = 1
        /// The amplitude spring's frequency, Hz.
        var response: Float = 6.5
        /// How long the level takes to fall, s.
        var release: Float = 0.15
        /// How fast the voice's history travels out from the middle, pt/s.
        var historySpeed: Float = 150
        /// The phosphor tail, s.
        var phosphor: Float = 0.6
        var glow: Float = 1
        /// One working light pass, s.
        var shimmerPass: Float = 0.55
        var shimmer: Float = 1
        /// How long the auto level takes to forget a loud peak, s.
        var autoRelease: Float = 3
        /// Input below this never lights the field, dBFS.
        var noiseFloor: Float = -60
    }

    private static let step: Float = 1 / 240
    private static let historyLength = 512
    private static let samplesPerColumn = 3
    private static let speeds: [Float] = [0.8, 1.25, 1.85, 2.6]
    private static let base: [Float] = [0.55, 0.42, 0.3, 0.2]
    private static let spatial: [Float] = [1.4, 2.4, 3.8, 5.6]
    private static let enter: Float = 0.42
    private static let phosphorHead: Float = 0.15
    private static let breathPeriod: Float = 5.5
    private static let workHelix: Float = 2.6
    private static let flowSpacing: Float = 0.7
    private static let carrierRest: Float = 0.14
    /// How much of the flowing light stays while formatting.
    private static let formatFlow: Float = 0.4
    private static let sparkleLight: Float = 0.6
    private static let tau = Float.pi * 2

    let tuning: Tuning

    /// Each dot's brightness and freshness, row by row.
    private(set) var power: [Float]
    private(set) var freshness: [Float]
    /// The glow behind the voice, 0 to about 1.
    private(set) var glow: Float = 0
    /// How far the unlit grid has faded in, 0 to 1.
    private(set) var grid: Float = 0
    /// 1 while the voice drives the field, falling to 0 after.
    private(set) var live: Float = 0
    /// 0 while listening, 1 while working: the colours cool.
    private(set) var cool: Float = 0
    /// 0 until Magic Format works, then 1: the shimmer and its hue.
    private(set) var format: Float = 0

    private var stage: DotScopeStage = .listening
    private var elapsed: Float = 0
    private var time: Float = 0
    private var pending: Float = 0
    private var reduceMotion = false
    private var width: Float = 1
    private var flowOffset: Float = 0
    private var flowTurn: Float = 0
    private var carrier: Float = 0
    private var coolVelocity: Float = 0
    private var formatVelocity: Float = 0
    /// Each dot's shimmer phase and rate, fixed per field.
    private let sparklePhase: [Float]
    private let sparkleRate: [Float]
    private var voices = [Voice(), Voice()]
    private var traces = [Trace(phases: [0.1, 1.7, 3.3, 4.6]), Trace(phases: [2.4, 0.6, 5.1, 1.9])]
    /// Per trace, flat: trace k's values start at `k * dots` or `k * samples`.
    private var head: [Float]
    private var tail: [Float]
    private var ys: [Float]
    private var brightness: [Float]
    private let samples: Int
    private var lastDate: Date?

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
        let dots = tuning.columns * tuning.rows
        samples = (tuning.columns - 1) * Self.samplesPerColumn + 1
        power = Array(repeating: 0, count: dots)
        freshness = Array(repeating: 0, count: dots)
        head = Array(repeating: 0, count: 2 * dots)
        tail = head
        ys = Array(repeating: 0, count: 2 * samples)
        brightness = ys
        sparklePhase = (0 ..< dots).map { Self.hash($0, 1) * Self.tau }
        sparkleRate = (0 ..< dots).map { 0.55 + 0.6 * Self.hash($0, 2) }
    }

    /// Advances to `date`, at most a quarter second at once, in fixed steps.
    /// `width` is the plate's width in points this frame.
    func advance(
        to date: Date,
        stage newStage: DotScopeStage,
        width newWidth: Float,
        voice: DotScopeVoice,
        reduceMotion newReduceMotion: Bool
    ) {
        defer { lastDate = date }
        guard let lastDate else { return }
        let dt = Float(date.timeIntervalSince(lastDate))
        guard dt > 0 else { return }
        // Between the two busy steps nothing restarts: the flow keeps its
        // place and only `format` eases, however short the first step was.
        if newStage != stage {
            if stage == .listening {
                flowOffset = -width / 2 - 4
                elapsed = 0
            } else if newStage == .listening {
                elapsed = 0
            }
            stage = newStage
        }
        width = max(newWidth, 1)
        reduceMotion = newReduceMotion
        pending += min(max(dt, 0), 0.25)
        var stepped: Float = 0
        while pending >= Self.step {
            pending -= Self.step
            step(voice: voice)
            stepped += Self.step
        }
        // Hex traces every second step (120 Hz); the field is drawn once a
        // frame, so it is traced once a frame over the time that passed.
        if stepped > 0 {
            beam(stepped)
        }
    }

    private func step(voice: DotScopeVoice) {
        let h = Self.step
        let listening = stage == .listening
        let level: Float
        if listening {
            let auto = voice.autoLevel.step(loudness: voice.loudness, step: h, release: tuning.autoRelease, noiseFloor: tuning.noiseFloor)
            level = min(max(auto * tuning.gain, 0), 1)
        } else {
            level = 0
        }
        voices[0].step(level, h)
        voices[1].step(level * 0.85, h)
        live += ((listening ? 1 : 0) - live) * (1 - exp(-h / 0.55))
        let speed = reduceMotion ? 0 : tuning.braidSpeed
        for k in 0 ..< 2 {
            traces[k].tick(voices[k], live: live, speed: speed, tuning: tuning, h: h)
        }
        let energy = max(voices[0].energy, voices[1].energy)
        let working = stage != .listening
        flowTurn += ((working ? 1 : 0) - flowTurn) * (1 - exp(-h / 0.25))
        if working {
            flowOffset += flowSpeed * h
        }
        let rest = Self.carrierRest + 0.22 * energy
        let turn = rest + (flowTurnHz - rest) * flowTurn
        carrier = (carrier + h * Self.tau * turn * speed).truncatingRemainder(dividingBy: Self.tau)

        // The colours cool, and the shimmer comes and goes, on critically
        // damped springs: 0.3 s, or Hex's 0.16 s fade with Reduce Motion.
        let omega = Self.tau / (reduceMotion ? 0.16 : 0.3)
        Self.ease(&cool, velocity: &coolVelocity, to: working ? 1 : 0, omega: omega, h: h)
        Self.ease(&format, velocity: &formatVelocity, to: stage == .formatting ? 1 : 0, omega: omega, h: h)

        elapsed += h
        time += h
    }

    private var workPeriod: Float { 2 * max(tuning.shimmerPass, 0.05) }
    private var flowSpacingPoints: Float { Self.flowSpacing * width }
    private var flowSpeed: Float { flowSpacingPoints / workPeriod }
    private var flowTurnHz: Float { flowSpeed * tuning.helixCycles / max(width, 1) }

    private struct Scan {
        var helix: Float
        var grid: Float
        var envelope: Envelope
    }

    private enum Envelope {
        case enter(reach: Float, head: Float, unfold: Float)
        case work(offset: Float, spacing: Float, head: Float, swell: Float)
    }

    private func scan() -> Scan {
        let e = elapsed
        if reduceMotion {
            return Scan(helix: 1, grid: 1, envelope: .enter(reach: 1e4, head: 0, unfold: 1))
        }
        switch stage {
        case .listening:
            return Scan(
                helix: 1,
                grid: min(e / 0.3, 1),
                envelope: .enter(
                    reach: (width / 2 + 12) * Self.passPosition(e / Self.enter),
                    head: 2.8 * (1 - Self.smoothstep(0.08, Self.enter, e)),
                    unfold: Self.smoothstep(0, 0.1, e)
                )
            )
        case .working, .formatting:
            let enter = Self.smoothstep(0, 0.35, e)
            let flow = 1 - (1 - Self.formatFlow) * format
            return Scan(
                helix: 1 + (Self.workHelix - 1) * enter,
                grid: 1,
                envelope: .work(
                    offset: flowOffset,
                    spacing: flowSpacingPoints,
                    head: 2.5 * Self.smoothstep(0.05, 0.3, e) * tuning.shimmer * flow,
                    swell: 0.9 * enter * flow
                )
            )
        }
    }

    /// (amplitude, brightness, swell) at `x` points from the middle.
    private static func sample(_ envelope: Envelope, at x: Float) -> (Float, Float, Float) {
        switch envelope {
        case let .enter(reach, head, unfold):
            let d = abs(x)
            let drawn = unfold * (1 - smoothstep(max(reach - 14, 0), max(reach, 0.001), d))
            let amplitude = drawn * (1 - smoothstep(max(reach - 22, 0), max(reach - 3, 0.001), d))
            let beam = head * bump(d - reach, 6)
            let swell = 1.8 * unfold * (head / 2.8) * bump(d - max(reach - 14, 0), 14)
            return (amplitude, amplitude + beam, swell)
        case let .work(offset, spacing, head, swell):
            let shifted = x - offset + spacing / 2
            let d = shifted - spacing * (shifted / spacing).rounded(.down) - spacing / 2
            let light = bump(d, 7)
            return (1, 1 + head * light, swell * light)
        }
    }

    /// Draws both traces into the dot field and decays the phosphor over `hb`
    /// seconds.
    private func beam(_ hb: Float) {
        let columns = tuning.columns
        let rows = tuning.rows
        let dots = columns * rows
        let sub = Self.samplesPerColumn
        let samples = samples
        let pitch = tuning.spacing
        let scan = scan()
        grid = scan.grid
        let mid = Float(rows - 1) / 2
        let half = mid - 0.55
        let breath: Float = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(time * Self.tau / Self.breathPeriod)
        let rest = (0.55 + 0.35 * breath) * (0.4 + 0.6 * live) * scan.helix
        let halfWidth = width / 2
        let traces = traces
        let tuning = tuning

        ys.withUnsafeMutableBufferPointer { ys in
            brightness.withUnsafeMutableBufferPointer { brightness in
                for k in 0 ..< 2 {
                    let trace = traces[k]
                    let sign: Float = k == 0 ? 1 : -1
                    let base = k * samples
                    for s in 0 ..< samples {
                        let x = (Float(s) / Float(sub) - Float(columns - 1) / 2) * pitch
                        if abs(x) > halfWidth {
                            ys[base + s] = mid
                            brightness[base + s] = 0
                            continue
                        }
                        let (amplitude, bright, swell) = Self.sample(scan.envelope, at: x)
                        let own = abs(x)
                        let xn = (x + halfWidth) / width
                        let ends = min(
                            Self.smoothstep(-halfWidth + 3, -halfWidth + 17, x),
                            Self.smoothstep(-halfWidth + 3, -halfWidth + 17, -x)
                        )
                        let reach = 1 - 0.8 * Self.smoothstep(14, halfWidth, own)
                        let delay = own / tuning.historySpeed
                        let a = trace.past(delay, channel: 0)
                        var spread: Float = 0
                        for c in 0 ..< 4 {
                            spread += trace.past(delay, channel: 1 + c) * sin(Self.tau * Self.spatial[c] * xn - trace.phases[c])
                        }
                        let helix = (rest + swell + half * 0.55 * a * reach) * sin(Self.tau * tuning.helixCycles * xn - carrier)
                        let y = half * tanh((helix + half * 0.7 * spread * reach) / half) * ends * amplitude
                        ys[base + s] = mid - sign * y
                        let spatialLight = (0.3 + 0.7 * min(a * 1.8, 1)) * (0.45 + 0.55 * ends)
                        brightness[base + s] = spatialLight * amplitude + 0.36 * max(bright - amplitude, 0)
                    }
                    for s in 0 ..< samples {
                        let slope = (ys[base + min(s + 1, samples - 1)] - ys[base + max(s - 1, 0)]) * Float(sub) / 2
                        brightness[base + s] *= 1 - 0.55 + 0.55 / (1 + 0.22 * slope * slope).squareRoot()
                    }
                }

                let headKeep = exp(-hb / Self.phosphorHead)
                let tailKeep = exp(-hb / tuning.phosphor)
                let dx = 1 / Float(sub)
                head.withUnsafeMutableBufferPointer { head in
                    tail.withUnsafeMutableBufferPointer { tail in
                        power.withUnsafeMutableBufferPointer { power in
                            freshness.withUnsafeMutableBufferPointer { freshness in
                                for i in 0 ..< columns {
                                    let s0 = max(i - 3, 0) * sub
                                    let s1 = min((i + 3) * sub, samples - 1)
                                    for j in 0 ..< rows {
                                        let n = j * columns + i
                                        var now: Float = 0
                                        var total: Float = 0
                                        var lit0: Float = 0
                                        var lit1: Float = 0
                                        for k in 0 ..< 2 {
                                            let base = k * samples
                                            var best = Float.greatestFiniteMagnitude
                                            var nearest = i * sub
                                            for s in s0 ..< s1 {
                                                let ay = ys[base + s]
                                                let dy = ys[base + s + 1] - ay
                                                let px = Float(i) - Float(s) * dx
                                                let py = Float(j) - ay
                                                let t = min(max((px * dx + py * dy) / (dx * dx + dy * dy), 0), 1)
                                                let ex = px - t * dx
                                                let ey = py - t * dy
                                                let d2 = ex * ex + ey * ey
                                                if d2 < best {
                                                    best = d2
                                                    nearest = s
                                                }
                                            }
                                            let b = brightness[base + nearest]
                                            let onBeam = exp(-best / 0.25)
                                            let instant = min(onBeam + 0.5 * exp(-best.squareRoot() / 0.8), 1.2) * b
                                            let core = onBeam * b
                                            let slot = k * dots + n
                                            head[slot] = max(head[slot] * headKeep, core)
                                            tail[slot] = max(tail[slot] * tailKeep, core)
                                            let light = max(max(instant, head[slot]), 0.55 * tail[slot])
                                            if k == 0 {
                                                lit0 = light
                                            } else {
                                                lit1 = light
                                            }
                                            now += instant
                                            total += light
                                        }
                                        let combined = 1 - (1 - min(lit0, 1)) * (1 - min(lit1, 1))
                                        let spark = sparkle(n)
                                        power[n] = min(max(1 - (1 - combined) * (1 - spark), 0), 1)
                                        freshness[n] = max(min(now / max(total, 1e-4), 1), min(spark * 1.6, 1))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        glow = (traces[0].glow + traces[1].glow) / 2 * tuning.glow
    }

    /// Dot `n`'s shimmer: short, soft flashes at its own phase and rate,
    /// scaled by `format`. None with Reduce Motion, where the hue alone shows
    /// the step.
    private func sparkle(_ n: Int) -> Float {
        guard format > 0.001, !reduceMotion else { return 0 }
        let wave = max(sin(sparklePhase[n] + Self.tau * sparkleRate[n] * time), 0)
        let flash = wave * wave * wave * wave
        return Self.sparkleLight * format * flash * flash * flash
    }

    /// One step of a critically damped spring from `value` toward `target`.
    private static func ease(_ value: inout Float, velocity: inout Float, to target: Float, omega: Float, h: Float) {
        let offset = value - target
        let decay = exp(-omega * h)
        let next = (offset + (velocity + omega * offset) * h) * decay
        velocity = (velocity - omega * (velocity + omega * offset) * h) * decay
        value = target + next
    }

    /// A fixed pseudo-random value in 0..<1 for dot `n`.
    private static func hash(_ n: Int, _ salt: UInt32) -> Float {
        var x = UInt32(truncatingIfNeeded: n) &* 0x9E37_79B9 &+ salt &* 0x85EB_CA6B
        x ^= x >> 16
        x = x &* 0x7FEB_352D
        x ^= x >> 15
        return Float(x >> 8) / Float(1 << 24)
    }

    static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func bump(_ d: Float, _ w: Float) -> Float {
        exp(-(d / w) * (d / w))
    }

    private static func passPosition(_ p: Float) -> Float {
        0.5 - 0.5 * cos(Float.pi * min(max(p, 0), 1))
    }

    private struct Voice {
        var level: Float = 0
        var reservoir: Float = 0
        var energy: Float = 0
        var kick: Float = 0
        var kickVelocity: Float = 0
        var band: Float = 0

        mutating func step(_ raw: Float, _ h: Float) {
            let previous = level
            level += (raw - level) * (1 - exp(-h / (raw > level ? 0.035 : 0.095)))
            let rise = max((level - previous) / h, 0)
            reservoir += (1.75 * level * level - reservoir / 1.8) * h
            energy = 1 - exp(-reservoir * 1.45)
            let w = DotScope.tau * 1.3
            let z: Float = 0.22
            kickVelocity += (-w * w * kick - 2 * z * w * kickVelocity + 15 * rise + 2.2 * level) * h
            kick += kickVelocity * h
            band += (raw - band) * (1 - exp(-h / (raw > band ? 0.025 : 0.14)))
        }
    }

    private struct Trace {
        var envelope: Float = 0
        var amplitude: Float = 0
        var amplitudeVelocity: Float = 0
        var glowFast: Float = 0
        var glowSpring: Float = 0
        var glowSpringVelocity: Float = 0
        var glowSlow: Float = 0
        var glow: Float = 0
        var phases: [Float]
        var history = Array(repeating: Float(0), count: DotScope.historyLength * 5)
        var head = 0

        init(phases: [Float]) {
            self.phases = phases
        }

        mutating func tick(_ voice: Voice, live: Float, speed: Float, tuning: Tuning, h: Float) {
            func follow(_ value: inout Float, _ target: Float, _ rise: Float, _ fall: Float) {
                value += (target - value) * (1 - exp(-h / (target > value ? rise : fall)))
            }
            follow(&envelope, voice.level, 0.022, tuning.release)
            let w = DotScope.tau * tuning.response
            let z: Float = 0.52
            amplitudeVelocity += (-w * w * (amplitude - envelope) - 2 * z * w * amplitudeVelocity) * h
            amplitude += amplitudeVelocity * h
            follow(&glowFast, voice.level, 0.045, 0.13)
            let gw = DotScope.tau * 3.6
            let gz: Float = 0.5
            glowSpringVelocity += (-gw * gw * (glowSpring - glowFast) - 2 * gz * gw * glowSpringVelocity) * h
            glowSpring += glowSpringVelocity * h
            follow(&glowSlow, voice.level, 0.15, 0.7)
            let swell = 0.8 * max(glowSpring - 0.25, 0) + 0.04 * max(voice.kick, -0.5)
            glow = min(max(swell, 0) + 0.42 * glowSlow + 0.2 * voice.energy, 1.15) * live
            let go = 0.6 + 1.1 * min(envelope * 1.6, 1)
            for c in 0 ..< 4 {
                phases[c] = (phases[c] + h * DotScope.tau * DotScope.speeds[c] * go * speed).truncatingRemainder(dividingBy: DotScope.tau)
            }
            let emphasis = 0.35 + 0.65 * min(voice.band / (voice.band + 0.06), 2)
            let offset = head * 5
            let value = max(amplitude, 0) * live
            history[offset] = value
            for c in 0 ..< 4 {
                history[offset + 1 + c] = value * DotScope.base[c] * emphasis
            }
            head = (head + 1) % DotScope.historyLength
        }

        func past(_ delay: Float, channel: Int) -> Float {
            let d = min(delay / DotScope.step, Float(DotScope.historyLength - 2))
            let i = Int(d)
            let k = d - Float(i)
            let a = (head + 2 * DotScope.historyLength - 1 - i) % DotScope.historyLength
            let b = (a + DotScope.historyLength - 1) % DotScope.historyLength
            return history[a * 5 + channel] * (1 - k) + history[b * 5 + channel] * k
        }
    }
}

/// The dot field, drawn the way Hex's shader draws it: a soft glow behind the
/// voice, then each dot's halo and dot, sized and lit by its brightness, and
/// faded where the plate's capsule ends.
struct DotScopeField: View {
    let stage: DotScopeStage
    let palette: DotScopePalette
    let voice: DotScopeVoice
    let reduceMotion: Bool
    @State private var scope = DotScope()
    @State private var layout = DotScopeLayout()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                scope.advance(
                    to: timeline.date,
                    stage: stage,
                    width: Float(size.width),
                    voice: voice,
                    reduceMotion: reduceMotion
                )
                layout.update(size: size, tuning: scope.tuning)
                draw(in: &context, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    /// Opacity steps of a drawn dot, and colour steps from the base toward the
    /// core colour: dots that share both are filled as one path, so a frame
    /// issues a few dozen fills instead of one per dot.
    private static let alphaSteps: Float = 24
    private static let liftSteps = 6
    private static let maximumLift: Float = 0.9

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let scope = scope
        let base = palette.base.mix(palette.workBase, scope.cool).mix(palette.formatBase, scope.format)
        let core = palette.core.mix(palette.workCore, scope.cool).mix(palette.formatCore, scope.format)

        let glow = scope.glow
        if glow > 0.01 {
            let plate = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2, style: .continuous)
            let center = base.mix(core, 0.5)
            context.fill(plate, with: .radialGradient(
                Gradient(stops: [
                    .init(color: center.color(opacity: Double(0.3 * 0.55 * min(1, glow))), location: 0),
                    .init(color: base.color(opacity: 0), location: 1),
                ]),
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: 0,
                endRadius: CGFloat(34 + 20 * glow)
            ))
        }

        let alphaSteps = Self.alphaSteps
        let liftSteps = Self.liftSteps
        let pitch = scope.tuning.spacing
        let presence = 0.5 + 0.5 * max(scope.live, scope.cool)
        let unlit: Float = 0.07 * presence * scope.grid
        let full: Float = 0.96
        let curve: Float = 0.9
        let bucketCount = (Int(alphaSteps) + 1) * liftSteps
        var dots = Array(repeating: Path(), count: bucketCount)
        var halos = Array(repeating: Path(), count: bucketCount)
        var drawnDots = Array(repeating: false, count: bucketCount)
        var drawnHalos = Array(repeating: false, count: bucketCount)
        let power = scope.power
        let freshness = scope.freshness

        for slot in layout.dots.indices {
            let dot = layout.dots[slot]
            let level = max(power[dot.index], 1e-5)
            let fresh = freshness[dot.index]
            let floorAlpha = unlit * dot.rowFade
            let alpha = (floorAlpha + (full - floorAlpha) * pow(level, curve * (1.4 - 0.4 * fresh))) * dot.mask
            let sizeFactor = 1 + ((0.82 + 0.18 * fresh) - 1) * DotScope.smoothstep(0.03, 0.2, level)
            let radius = CGFloat((0.25 + 0.17 * pow(level, 0.6)) * sizeFactor * pitch)
            let lift = min(max(level * level * 1.1, 0), Self.maximumLift) * (0.3 + 0.7 * fresh)
            let liftIndex = min(Int((lift / Self.maximumLift * Float(liftSteps - 1)).rounded()), liftSteps - 1)

            let alphaIndex = Int((alpha * alphaSteps).rounded())
            if alphaIndex > 0 {
                let bucket = alphaIndex * liftSteps + liftIndex
                dots[bucket].addEllipse(in: CGRect(x: dot.center.x - radius, y: dot.center.y - radius, width: radius * 2, height: radius * 2))
                drawnDots[bucket] = true
            }
            if level > 0.05 {
                let haloIndex = Int((0.132 * level * level * dot.mask * alphaSteps).rounded())
                if haloIndex > 0 {
                    let bucket = haloIndex * liftSteps + liftIndex
                    let halo = radius * 2
                    halos[bucket].addEllipse(in: CGRect(x: dot.center.x - halo, y: dot.center.y - halo, width: halo * 2, height: halo * 2))
                    drawnHalos[bucket] = true
                }
            }
        }

        let colors = (0 ..< liftSteps).map { step in
            base.mix(core, Float(step) / Float(liftSteps - 1) * Self.maximumLift)
        }
        for bucket in 0 ..< bucketCount where drawnHalos[bucket] {
            let opacity = Double(Float(bucket / liftSteps) / alphaSteps)
            context.fill(halos[bucket], with: .color(colors[bucket % liftSteps].color(opacity: opacity)))
        }
        for bucket in 0 ..< bucketCount where drawnDots[bucket] {
            let opacity = Double(Float(bucket / liftSteps) / alphaSteps)
            context.fill(dots[bucket], with: .color(colors[bucket % liftSteps].color(opacity: opacity)))
        }
    }
}

/// The dots' fixed geometry for one canvas size: where each dot sits, how much
/// the capsule's edge fades it, and how much the unlit grid fades toward the
/// top and bottom rows. Recomputed only when the size changes.
final class DotScopeLayout {
    struct Dot {
        var index: Int
        var center: CGPoint
        var mask: Float
        var rowFade: Float
    }

    private(set) var dots: [Dot] = []
    private var size: CGSize = .zero

    func update(size: CGSize, tuning: DotScope.Tuning) {
        guard size != self.size else { return }
        self.size = size
        let halfWidth = Float(size.width) / 2
        let halfHeight = Float(size.height) / 2
        let pitch = tuning.spacing
        var dots: [Dot] = []
        for j in 0 ..< tuning.rows {
            let y = (Float(j) - Float(tuning.rows - 1) / 2) * pitch
            let rowFade = 1 - 0.7 * DotScope.smoothstep(0.35, 0.95, abs(y) / halfHeight)
            for i in 0 ..< tuning.columns {
                let x = (Float(i) - Float(tuning.columns - 1) / 2) * pitch
                let mask = DotScope.smoothstep(1.4, 4.6, -Self.roundedBox(x: x, y: y, halfWidth: halfWidth, halfHeight: halfHeight))
                guard mask > 0 else { continue }
                dots.append(Dot(
                    index: j * tuning.columns + i,
                    center: CGPoint(x: size.width / 2 + CGFloat(x), y: size.height / 2 + CGFloat(y)),
                    mask: mask,
                    rowFade: rowFade
                ))
            }
        }
        self.dots = dots
    }

    /// Signed distance from a point to the capsule around the middle.
    private static func roundedBox(x: Float, y: Float, halfWidth: Float, halfHeight: Float) -> Float {
        let radius = halfHeight
        let qx = abs(x) - halfWidth + radius
        let qy = abs(y) - halfHeight + radius
        let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot()
        return outside + min(max(qx, qy), 0) - radius
    }
}

/// The field's colours, sRGB: warm pearl while listening, cooling toward blue
/// while working. Edit Mode listens in violet.
struct DotScopePalette: Equatable {
    var base: DotScopeColor
    var core: DotScopeColor
    var workBase = DotScopeColor(0.70, 0.78, 0.90)
    var workCore = DotScopeColor(0.92, 0.95, 1.0)
    var formatBase = DotScopeColor(0.62, 0.84, 0.82)
    var formatCore = DotScopeColor(0.88, 1.0, 0.97)

    static let dictation = DotScopePalette(base: DotScopeColor(0.86, 0.83, 0.77), core: DotScopeColor(0.98, 0.96, 0.92))
    static let edit = DotScopePalette(base: DotScopeColor(0.78, 0.69, 0.98), core: DotScopeColor(0.95, 0.91, 1.0))
    /// Ink on the light plate: the same hues, dark enough to read.
    static let dictationLight = DotScopePalette(
        base: DotScopeColor(0.42, 0.40, 0.37),
        core: DotScopeColor(0.12, 0.11, 0.10),
        workBase: DotScopeColor(0.36, 0.50, 0.78),
        workCore: DotScopeColor(0.06, 0.32, 0.82),
        formatBase: DotScopeColor(0.30, 0.58, 0.56),
        formatCore: DotScopeColor(0.04, 0.45, 0.42)
    )
    static let editLight = DotScopePalette(
        base: DotScopeColor(0.56, 0.42, 0.88),
        core: DotScopeColor(0.34, 0.16, 0.74),
        workBase: DotScopeColor(0.36, 0.50, 0.78),
        workCore: DotScopeColor(0.06, 0.32, 0.82),
        formatBase: DotScopeColor(0.30, 0.58, 0.56),
        formatCore: DotScopeColor(0.04, 0.45, 0.42)
    )
}

struct DotScopeColor: Equatable {
    var red: Float
    var green: Float
    var blue: Float

    init(_ red: Float, _ green: Float, _ blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    func mix(_ other: DotScopeColor, _ t: Float) -> DotScopeColor {
        DotScopeColor(red + (other.red - red) * t, green + (other.green - green) * t, blue + (other.blue - blue) * t)
    }

    func color(opacity: Double) -> Color {
        Color(.sRGB, red: Double(red), green: Double(green), blue: Double(blue), opacity: opacity)
    }
}
