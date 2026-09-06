import XCTest
import AVFoundation
import UIKit
@testable import diction_processor

final class diction_processorTests: XCTestCase {
    func testMicrophoneBusExistsOnInputNode() {
        let engine = AVAudioEngine()
        XCTAssertLessThan(Utils.SPEECH_RECOGNITION_BUS, engine.inputNode.numberOfOutputs)
    }
    func testSelectionCommandsDoNotAdvertiseDeletion() {
        XCTAssertEqual(VoiceCommandEngine.VoiceCommand.SELECT_SENTENCE.rawValue, "select sentence")
        XCTAssertEqual(VoiceCommandEngine.VoiceCommand.SELECT_PARAGRAPH.rawValue, "select paragraph")
    }
    func testRecognitionCompletionDoesNotConsumeReplacementSession() {
        let lifecycle = RecognitionLifecycle()
        let old = lifecycle.begin()
        let next = lifecycle.begin()
        XCTAssertFalse(lifecycle.complete(old))
        XCTAssertTrue(lifecycle.accepts(next))
        lifecycle.finish(next)
        XCTAssertTrue(lifecycle.complete(next))
        XCTAssertFalse(lifecycle.complete(next))
    }
}

/// Pure queue and notification contracts from "Lingual Tests to Specify:" (LTS-004, LTS-008).
final class LingualNotificationSpecifications: XCTestCase {
    func testLTS004QueueIsFIFOAndPeekDoesNotConsume() {
        var queue = Queue<String>()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.dequeue())
        for value in ["first", "second", "third"] { queue.enqueue(value) }
        XCTAssertEqual(queue.peek(), "first")
        XCTAssertEqual(queue.peek(), "first")
        for value in ["first", "second", "third"] { XCTAssertEqual(queue.dequeue(), value) }
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.peek())
    }

    func testLTS004QueueCanBeClearedAndReused() {
        var queue = Queue<Int>()
        for value in 0..<1000 { queue.enqueue(value) }
        queue.empty()
        XCTAssertTrue(queue.isEmpty)
        queue.enqueue(42)
        XCTAssertEqual(queue.dequeue(), 42)
        queue.empty()
        XCTAssertNil(queue.dequeue())
    }

    func testLTS004NotificationsAdvanceInOrderAndReleaseTimer() {
        let engine = NotificationEngine()
        var received: [String] = []
        let token = NotificationCenter.default.addObserver(forName: NotificationEngine.onStartTimedNotification, object: nil, queue: nil) { notification in
            if let item = notification.userInfo?["item"] as? NotificationItem { received.append(item.text) }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        engine.scheduleNotification(text: "first", duration: 60)
        engine.scheduleNotification(text: "second", duration: 60)
        engine.exhaustNotificationQueue()
        XCTAssertEqual(received, ["first"])
        XCTAssertTrue(engine.isExhaustingNotificationQueue)
        engine.appNotificationTimer?.fire()
        XCTAssertEqual(received, ["first", "second"])
        XCTAssertFalse(engine.isExhaustingNotificationQueue)
        engine.appNotificationTimer?.fire()
        XCTAssertNil(engine.appNotificationTimer)
        XCTAssertFalse(engine.isPresentingVisualNotification)
    }

    func testLTS008IndefiniteNotificationCarriesItsMessageAndCancelsPriorTimer() {
        let engine = NotificationEngine()
        engine.runTimedNotification(item: NotificationItem(text: "old", isVoiceCommand: false, duration: 60))
        let oldTimer = engine.appNotificationTimer
        var received: NotificationItem?
        let token = NotificationCenter.default.addObserver(forName: NotificationEngine.onStartIndefiniteNotification, object: nil, queue: nil) { notification in
            received = notification.userInfo?["item"] as? NotificationItem
        }
        defer { NotificationCenter.default.removeObserver(token) }
        engine.presentIndefiniteNotification(item: NotificationItem(text: "selection", isVoiceCommand: true, duration: nil))
        XCTAssertEqual(received?.text, "selection")
        XCTAssertEqual(received?.isVoiceCommand, true)
        XCTAssertNil(engine.appNotificationTimer)
        XCTAssertEqual(oldTimer?.isValid, false)
        XCTAssertTrue(engine.isPresentingVisualNotification)
    }

    func testLTS004ClearingAnActiveQueueResetsExhaustion() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let navigation = try XCTUnwrap(scene.windows.first?.rootViewController as? UINavigationController)
        let controller = try XCTUnwrap(navigation.viewControllers.first as? EntryTableViewController)
        let engine = NotificationEngine()
        engine.speechSynthesis = controller.speechSynthesis
        engine.scheduleNotification(text: "first", duration: 60)
        engine.scheduleNotification(text: "second", duration: 60)
        engine.exhaustNotificationQueue()
        engine.emptyNotificationQueue()
        XCTAssertFalse(engine.isExhaustingNotificationQueue)
        XCTAssertTrue(engine.notificationQueue.isEmpty)
        engine.appNotificationTimer?.fire()
        XCTAssertFalse(engine.isPresentingVisualNotification)
    }

    func testLTS004DeinitializingNotificationEngineInvalidatesItsTimer() {
        var engine: NotificationEngine? = NotificationEngine()
        engine?.runTimedNotification(item: NotificationItem(text: "temporary", isVoiceCommand: false, duration: 60))
        let timer = engine?.appNotificationTimer
        weak var released = engine
        engine = nil
        XCTAssertNil(released)
        XCTAssertEqual(timer?.isValid, false)
    }
}

/// Persistence must preserve decimal speeds and UTF-16 selection offsets (LTS-049, LTS-055, LTS-154).
final class LingualTransformationSpecifications: XCTestCase {
    func testLTS049DecimalRateAndRangesSurviveArchiving() throws {
        let original = EntryTransformation(type: .playbackRate, uids: ["word": 3], text: "café 🌍", value: 1.2, textRange: NSRange(location: 4, length: 7), entryRange: 2...5)
        let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: false)
        let restored = try XCTUnwrap(NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? EntryTransformation)
        XCTAssertEqual(restored.type, original.type)
        XCTAssertEqual(restored.value, original.value)
        XCTAssertEqual(restored.textRange, original.textRange)
        XCTAssertEqual(restored.entryRange, original.entryRange)
        XCTAssertEqual(restored.uids, original.uids)
        XCTAssertEqual(restored.text, original.text)
    }

    func testLTS055AbsentRateIsNotDecodedAsZero() throws {
        let original = EntryTransformation(type: .playbackRate, uids: [:], text: "", textRange: NSRange(location: 0, length: 0), entryRange: 0...0)
        let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: false)
        let restored = try XCTUnwrap(NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? EntryTransformation)
        XCTAssertNil(restored.value)
        XCTAssertEqual(restored.entryRange, 0...0)
    }
}
