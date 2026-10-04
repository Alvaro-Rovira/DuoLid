import Testing
@testable import DuoLidCore

@Suite struct SpatialEffectTests {
    let effect = SpatialEffect()
    let heights = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }
    let progresses = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }

    @Test func hingeIsTheMinimum() {
        for p in [0.3, 0.6, 0.8] {
            #expect(effect.blurFactor(g: 0, p: p) < effect.blurFactor(g: 0.5, p: p))
            #expect(effect.dimAlpha(g: 0, p: p) <= effect.dimAlpha(g: 0.5, p: p))
        }
    }

    @Test func growsTowardsTheTopEdge() {
        for p in progresses {
            let blur = heights.map { effect.blurFactor(g: $0, p: p) }
            let dim = heights.map { effect.dimAlpha(g: $0, p: p) }
            #expect(zip(blur, blur.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(zip(dim, dim.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }

    @Test func growsAsTheLidCloses() {
        for g in heights {
            let blur = progresses.map { effect.blurFactor(g: g, p: $0) }
            let dim = progresses.map { effect.dimAlpha(g: g, p: $0) }
            #expect(zip(blur, blur.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(zip(dim, dim.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }

    @Test func staysWithinZeroAndOne() {
        let extreme = SpatialEffect(gradientExponent: 0.8, darkenFactor: 3, hingeFloor: 0.3, invertGradient: true)
        for candidate in [effect, extreme] {
            for g in [-1.0, 0, 0.5, 1, 2] {
                for p in [-1.0, 0, 0.5, 1, 2] {
                    #expect((0...1).contains(candidate.blurFactor(g: g, p: p)))
                    #expect((0...1).contains(candidate.dimAlpha(g: g, p: p)))
                }
            }
        }
    }

    @Test func farEdgeTurnsBlackBeforeTheEnd() {
        #expect(effect.dimAlpha(g: 1, p: 0.5) == 1)
        #expect(effect.blurFactor(g: 1, p: 0.5) < 1)
    }

    @Test func wholeScreenIsBlackAtFullEffect() {
        for g in heights {
            #expect(effect.dimAlpha(g: g, p: 1) == 1)
        }
    }

    @Test func formulaIsUntouchedBeforeTheBlackout() {
        let p = 0.6
        for g in heights {
            #expect(effect.dimAlpha(g: g, p: p) == min(1, 2.0 * p * effect.weight(atHeight: g)))
        }
    }

    @Test func invisibleWhenOpen() {
        for g in heights {
            #expect(effect.blurFactor(g: g, p: 0) == 0)
            #expect(effect.dimAlpha(g: g, p: 0) == 0)
        }
    }

    @Test func hingeFloorKeepsSomeEffectAtTheHinge() {
        #expect(effect.blurFactor(g: 0, p: 1) > 0)
        #expect(SpatialEffect(hingeFloor: 0).blurFactor(g: 0, p: 1) == 0)
    }

    @Test func invertSwapsTheDirection() {
        let inverted = SpatialEffect(invertGradient: true)
        #expect(inverted.blurFactor(g: 0.2, p: 0.7) == effect.blurFactor(g: 0.8, p: 0.7))
    }

    @Test func stopsGoFromHingeToTop() {
        let alphas = effect.dimAlphas(stops: 16, p: 0.5)
        #expect(alphas.count == 16)
        #expect(alphas.first! == effect.dimAlpha(g: 0, p: 0.5))
        #expect(alphas.last! == effect.dimAlpha(g: 1, p: 0.5))
    }

    @Test func maskRowsStartAtTheTopEdge() {
        // La fila 0 de un CGImage es el borde superior (comprobado en la prueba de variableBlur).
        let rows = effect.maskRows(100)
        #expect(rows.count == 100)
        #expect(rows.first! > rows.last!)
        let inverted = SpatialEffect(invertGradient: true).maskRows(100)
        #expect(inverted.first! < inverted.last!)
    }

    @Test func maskShapeIgnoresDarkeningAndProgress() {
        #expect(SpatialEffect(darkenFactor: 3).maskShape == effect.maskShape)
        #expect(SpatialEffect(gradientExponent: 2).maskShape != effect.maskShape)
        #expect(SpatialEffect(hingeFloor: 0.2).maskShape != effect.maskShape)
        #expect(SpatialEffect(invertGradient: true).maskShape != effect.maskShape)
    }
}
