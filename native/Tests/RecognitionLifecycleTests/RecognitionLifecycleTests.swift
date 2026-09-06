import XCTest
@testable import RecognitionLifecycle

final class RecognitionLifecycleTests: XCTestCase {
    func testOldCallbacksCannotFinishReplacementSession() {
        let lifecycle = RecognitionLifecycle()
        let old = lifecycle.begin()
        let current = lifecycle.begin()
        XCTAssertFalse(lifecycle.complete(old))
        XCTAssertTrue(lifecycle.accepts(current))
    }

    func testFinalTranscriptIsAcceptedWhileFinishing() {
        let lifecycle = RecognitionLifecycle()
        let id = lifecycle.begin()
        lifecycle.finish(id)
        XCTAssertTrue(lifecycle.isFinishing)
        XCTAssertTrue(lifecycle.accepts(id))
        XCTAssertTrue(lifecycle.complete(id))
        XCTAssertFalse(lifecycle.accepts(id))
    }

    func testTimeoutAndCompletionCanOnlyCompleteOnce() {
        let lifecycle = RecognitionLifecycle()
        let id = lifecycle.begin()
        lifecycle.finish(id)
        XCTAssertTrue(lifecycle.complete(id))
        XCTAssertFalse(lifecycle.complete(id))
        XCTAssertFalse(lifecycle.isFinishing)
    }

    func testLateStopCannotAffectNewSession() {
        let lifecycle = RecognitionLifecycle()
        let old = lifecycle.begin()
        let current = lifecycle.begin()
        lifecycle.finish(old)
        XCTAssertFalse(lifecycle.isFinishing)
        XCTAssertTrue(lifecycle.accepts(current))
    }
}
