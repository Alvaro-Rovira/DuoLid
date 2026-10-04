import Testing
@testable import DuoLidCore

@Suite struct EffectCurveTests {
    let curve = EffectCurve(fullEffectAngle: 12, invisibleAngle: 100)

    @Test func maximumIsReachedBeforeTheLidCloses() {
        #expect(curve.progress(atAngle: 0) == 1)
        #expect(curve.progress(atAngle: 12) == 1)
    }

    @Test func invisibleWhenOpen() {
        #expect(curve.progress(atAngle: 100) == 0)
        #expect(curve.progress(atAngle: 115) == 0)
    }

    @Test func decreasesMonotonicallyWhileOpening() {
        var previous = 1.0
        for angle in stride(from: 12.0, through: 100, by: 0.5) {
            let p = curve.progress(atAngle: angle)
            #expect(p <= previous)
            previous = p
        }
    }

    @Test func degenerateRangeDoesNotDivideByZero() {
        let flat = EffectCurve(fullEffectAngle: 50, invisibleAngle: 50)
        #expect(flat.progress(atAngle: 40) == 1)
        #expect(flat.progress(atAngle: 60) == 0)
    }
}

@Suite struct AngleSmootherTests {
    /// Simula el sensor real: lecturas a 10 Hz redondeadas a 1°, animación a 60 Hz.
    private func run(
        motion: (Double) -> Double, duration: Double, smoother: inout AngleSmoother
    ) -> [Double] {
        var frames: [Double] = []
        var lastReported: Double?
        let frame = 1.0 / 60
        var time = 0.0
        var nextSample = 0.0
        while time <= duration {
            if time >= nextSample {
                let reading = motion(time).rounded()
                if reading != lastReported {  // el sensor solo informa de cambios
                    smoother.add(angle: reading, at: time)
                    lastReported = reading
                }
                nextSample += 0.1
            }
            time += frame
            smoother.advance(to: time, by: frame)
            frames.append(smoother.value)
        }
        return frames
    }

    @Test func fastClosingIsSmoothInsteadOfStepped() {
        // Cierre a 90°/s, como en el diagnóstico: 105° → 0° en ~1,2 s.
        var smoother = AngleSmoother(angle: 105)
        smoother.jump(to: 105, at: 0)
        let frames = run(motion: { max(105 - 90 * $0, 0) }, duration: 1.0, smoother: &smoother)

        // Sin suavizado habría saltos de 9° cada 6 fotogramas. Con él, tras el arranque brusco
        // (de 0 a 90°/s en un instante), cada fotograma avanza lo que avanza la tapa: 1,5°.
        let steps = zip(frames, frames.dropFirst()).map { abs($1 - $0) }
        #expect(steps.max()! < 3.5)
        #expect(steps[20..<55].allSatisfy { abs($0 - 1.5) < 0.3 })
        // Y la animación no se queda muy por detrás del movimiento real.
        #expect(abs(frames.last! - (105 - 90 * 1.0)) < 12)
    }

    @Test func settlesOnTheLastReadingWhenTheLidStops() {
        var smoother = AngleSmoother(angle: 100)
        smoother.jump(to: 100, at: 0)
        _ = run(motion: { $0 < 0.6 ? 100 - 100 * $0 : 40 }, duration: 2.0, smoother: &smoother)
        #expect(abs(smoother.value - 40) < 0.1)
        #expect(smoother.isSettled(at: 2.0))
    }

    @Test func stopOvershootStaysSmall() {
        var smoother = AngleSmoother(angle: 100)
        smoother.jump(to: 100, at: 0)
        let frames = run(motion: { $0 < 0.6 ? 100 - 100 * $0 : 40 }, duration: 2.0, smoother: &smoother)
        #expect(frames.min()! > 40 - 8)
    }
}
