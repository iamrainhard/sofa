import Foundation

@main struct VolumeInteractionChecks {
    static func main() {
        var state = VolumeInteraction()
        state.report(8)
        state.begin(); state.propose(12)
        let first = state.nextRequest()!
        precondition(state.displayed == 12)
        state.report(8)
        precondition(state.displayed == 12, "Old readback must not move the drag")
        state.propose(16)
        precondition(state.nextRequest() == nil, "Only one request in flight")
        state.end()
        precondition(state.displayed == 16, "Release must retain local intent")
        state.complete(id: first.id, actual: 12)
        precondition(state.displayed == 16, "Intermediate result must not snap back")
        let last = state.nextRequest()!
        precondition(last.value == 16, "Coalesce to latest value")
        precondition(!state.complete(id: first.id, actual: 12), "Ignore superseded completion")
        state.complete(id: last.id, actual: 16)
        precondition(state.target == nil && state.displayed == 16)
        state.report(10)
        precondition(state.displayed == 10, "Physical remote changes remain supported")
        state.propose(11); state.propose(state.displayed + 1)
        precondition(state.displayed == 12, "Fast increments accumulate")
        state.cancel()
        precondition(state.displayed == 10 && state.inFlight == nil)
        state.propose(200)
        precondition(state.displayed == 100)
        state.propose(-1)
        precondition(state.displayed == 0)
        state.cancel(); state.propose(15)
        let limited = state.nextRequest()!
        state.complete(id: limited.id, actual: 14)
        precondition(state.displayed == 14 && state.nextRequest() == nil, "Accept TV clamping without retry loop")
        state.begin(); state.propose(20)
        let drag = state.nextRequest()!
        state.complete(id: drag.id, actual: 20)
        precondition(state.displayed == 20)
        state.end()
        precondition(state.target == nil)
        state.report(35); state.begin(); state.propose(100)
        let obsolete = state.supersedeRequest()!
        state.propose(53)
        let newest = state.supersedeRequest()!
        precondition(!state.complete(id: obsolete.id, actual: 100))
        state.report(40)
        precondition(state.displayed == 53, "Keep the thumb at the latest target during TV feedback")
        state.complete(id: newest.id, actual: 55)
        precondition(state.displayed == 53, "Quantization must not move a thumb under the pointer")
        state.end(); state.finishRelativeEdit()
        precondition(state.displayed == 55 && state.target == nil, "Settle once to the nearest native step after release")
        print("Volume interaction checks passed: drag, delayed readback, coalescing, release, stale completion, external change, stepping, cancellation, limits and TV clamping")
    }
}
