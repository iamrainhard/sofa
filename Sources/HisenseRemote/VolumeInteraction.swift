import Foundation

/// Local intent stays visible until its own readback completes. At most one write is in flight.
struct VolumeInteraction {
    struct Request: Equatable { let id: Int; let value: Double }
    private(set) var confirmed: Double = 0
    private(set) var target: Double?
    private(set) var inFlight: Request?
    private(set) var editing = false
    private var sequence = 0
    var displayed: Double { target ?? confirmed }
    mutating func begin() { editing = true }
    mutating func end() {
        editing = false
        if inFlight == nil, target == confirmed { target = nil }
    }
    mutating func propose(_ value: Double) { target = min(100, max(0, value.rounded())) }
    mutating func report(_ value: Double) {
        // Broadcasts can be older than the outstanding SOAP write/readback.
        if target == nil && inFlight == nil { confirmed = min(100, max(0, value)) }
    }
    /// Relative-key adapters replace pending intent immediately, so reversing a
    /// drag cannot leave the TV walking toward an obsolete endpoint.
    mutating func supersedeRequest() -> Request? {
        guard let target else { return nil }
        sequence += 1
        let request = Request(id: sequence, value: target)
        inFlight = request
        return request
    }
    mutating func nextRequest() -> Request? {
        guard inFlight == nil, let target else { return nil }
        if target == confirmed {
            if !editing { self.target = nil }
            return nil
        }
        sequence += 1
        let request = Request(id: sequence, value: target)
        inFlight = request
        return request
    }
    @discardableResult mutating func complete(id: Int, actual: Double) -> Bool {
        guard let request = inFlight, request.id == id else { return false }
        confirmed = min(100, max(0, actual))
        inFlight = nil
        if target == request.value, !editing { target = nil }
        return true
    }
    mutating func finishRelativeEdit() { if inFlight == nil { target = nil } }
    mutating func cancel() { target = nil; inFlight = nil; editing = false }
}
