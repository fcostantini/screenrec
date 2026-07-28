/// How a count-in ended (M18-T4). Cancelling returns to idle with nothing written.
public enum CountInOutcome: Sendable, Equatable {
    case finished
    case cancelled
}
