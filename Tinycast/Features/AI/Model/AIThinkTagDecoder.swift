import Foundation

struct AIThinkTagDecoder: Sendable {
    private enum Phase { case undecided, reasoning, answer }

    private var phase = Phase.undecided
    private var buffer = ""
    private var trimmingAnswer = false
    private let opening = "<think>"
    private let closing = "</think>"

    mutating func feed(_ fragment: String) -> [AIStreamEvent] {
        if phase == .answer { return answer(fragment) }
        buffer += fragment
        if phase == .undecided {
            let candidate = buffer.drop(while: \.isWhitespace)
            if candidate.hasPrefix(opening) {
                buffer = String(candidate.dropFirst(opening.count))
                phase = .reasoning
            } else if opening.hasPrefix(candidate) {
                return []
            } else {
                phase = .answer
                let text = buffer
                buffer = ""
                return answer(text)
            }
        }
        if let close = buffer.range(of: closing) {
            let text = String(buffer[close.upperBound...])
            buffer = ""
            phase = .answer
            trimmingAnswer = true
            return answer(text)
        }
        var tail = min(buffer.count, closing.count - 1)
        while tail > 0, !closing.hasPrefix(buffer.suffix(tail)) { tail -= 1 }
        buffer = String(buffer.suffix(tail))
        return []
    }

    mutating func finish() -> [AIStreamEvent] {
        let pending = buffer
        buffer = ""
        let events: [AIStreamEvent]
        switch phase {
        case .undecided: events = pending.isEmpty ? [] : [.text(pending)]
        case .reasoning, .answer: events = []
        }
        phase = .answer
        return events
    }

    private mutating func answer(_ text: String) -> [AIStreamEvent] {
        let text = trimmingAnswer ? String(text.drop(while: \.isWhitespace)) : text
        guard !text.isEmpty else { return [] }
        trimmingAnswer = false
        return [.text(text)]
    }
}
