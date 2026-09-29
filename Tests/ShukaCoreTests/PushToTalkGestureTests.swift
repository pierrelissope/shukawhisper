import Testing
@testable import ShukaCore

@Suite struct PushToTalkGestureTests {
    @Test func holdAndReleaseFinishes() {
        var gesture = PushToTalkGesture()
        #expect(gesture.handle(.keyDown(at: 0)) == [.startRecording])
        #expect(gesture.handle(.keyUp(at: 2)) == [.finish])
        #expect(gesture.state == .idle)
    }

    @Test func singleShortTapCancelsAfterTimeout() {
        var gesture = PushToTalkGesture()
        _ = gesture.handle(.keyDown(at: 0))
        #expect(gesture.handle(.keyUp(at: 0.1)) == [.scheduleTapTimeout(gesture.doubleTapWindow)])
        #expect(gesture.handle(.tapTimeout) == [.cancel])
        #expect(gesture.state == .idle)
    }

    @Test func doubleTapLocksThenNextPressFinishes() {
        var gesture = PushToTalkGesture()
        _ = gesture.handle(.keyDown(at: 0))
        _ = gesture.handle(.keyUp(at: 0.1))
        #expect(gesture.handle(.keyDown(at: 0.25)) == [.lock])
        #expect(gesture.handle(.keyUp(at: 0.3)) == [])
        #expect(gesture.state == .locked)
        #expect(gesture.handle(.keyDown(at: 10)) == [.finish])
        #expect(gesture.handle(.keyUp(at: 10.1)) == [])
        #expect(gesture.state == .idle)
    }

    @Test func usingKeyAsModifierCancels() {
        var gesture = PushToTalkGesture()
        _ = gesture.handle(.keyDown(at: 0))
        #expect(gesture.handle(.otherKey) == [.cancel])
        #expect(gesture.handle(.keyUp(at: 0.2)) == [])
    }

    @Test func otherKeysAreIgnoredWhileHandsFree() {
        var gesture = PushToTalkGesture()
        _ = gesture.handle(.keyDown(at: 0))
        _ = gesture.handle(.keyUp(at: 0.1))
        _ = gesture.handle(.keyDown(at: 0.2))
        #expect(gesture.handle(.otherKey) == [])
        #expect(gesture.state == .locked)
    }

    @Test func escapeCancelsFromAnyActiveState() {
        var gesture = PushToTalkGesture()
        #expect(gesture.handle(.escape) == [])
        _ = gesture.handle(.keyDown(at: 0))
        #expect(gesture.handle(.escape) == [.cancel])

        _ = gesture.handle(.keyDown(at: 1))
        _ = gesture.handle(.keyUp(at: 1.1))
        _ = gesture.handle(.keyDown(at: 1.2))
        #expect(gesture.handle(.escape) == [.cancel])
        #expect(gesture.state == .idle)
    }

    @Test func staleTimeoutIsIgnored() {
        var gesture = PushToTalkGesture()
        #expect(gesture.handle(.tapTimeout) == [])
        _ = gesture.handle(.keyDown(at: 0))
        #expect(gesture.handle(.tapTimeout) == [])
        #expect(gesture.state == .holding(since: 0))
    }
}
