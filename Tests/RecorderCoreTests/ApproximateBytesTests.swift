import Foundation
import Testing
@testable import RecorderCore

/// The shared ≈-grade byte figure: the armed buffer's memory and an export's weight per minute
/// both quote a model, and a model must not print like a measurement.
@Suite struct ApproximateBytesTests {

    @Test func roundsToTwoSignificantFiguresSoTheEstimateReadsAsOne() {
        #expect(ApproximateBytes.roundedToTwoSignificantFigures(183_133_368) == 180_000_000)
        #expect(ApproximateBytes.roundedToTwoSignificantFigures(2_663_000_000) == 2_700_000_000)
        #expect(ApproximateBytes.roundedToTwoSignificantFigures(8_243_000) == 8_200_000)
        #expect(ApproximateBytes.roundedToTwoSignificantFigures(0) == 0)
    }

    @Test func formatsTheMP4PickWeightsTheSizePickerStates() {
        // The three rows for a 4112 × 2570 source (M19-T4): 46 / 81 / 167 MB per minute, each
        // rounded so the row reads as the estimate it is.
        #expect(ApproximateBytes.formatted(46_200_000).contains("46"))
        #expect(ApproximateBytes.formatted(81_200_000).contains("81"))
        #expect(ApproximateBytes.formatted(167_075_000).contains("170"))
    }
}
