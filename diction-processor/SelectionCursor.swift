//
//  SelectionCursor.swift
//  diction-processor
//
//  Created by Afika Nyati on 8/13/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit
import Speech

// Reference: https://stackoverflow.com/questions/34922331/getting-and-setting-cursor-position-of-uitextfield-and-uitextview-in-swift

class SelectionCursor: NSObject, UITextViewDelegate {
    // MARK: - Notifications
    
    static let onClipboardChange = Notification.Name(Notifications.onClipboardChange.rawValue)
    
    // MARK: - App Modules
    
    var state: StateManager
    var notifications: NotificationEngine
    var speechPlayer: SpeechPlayerEngine
    var speechSynthesis: SpeechSynthesisEngine
    var speechRecognition: SpeechRecognitionEngine
    var uiManager: UIManager
    weak var entryManager: EntryManager! // we add weak because entry manager has a reference to selection curos
    
    // MARK: - Selection Cursor Properties
    
    @objc dynamic var focusCaret: Caret? = nil
    var focus: EntrySegment? {
        if let focusCaret = self.focusCaret {
            return self.getSegment(caret: focusCaret)
        }
        
        return nil
    }
    @objc dynamic var anchorCaret: Caret? = nil
    var anchor: EntrySegment? {
        if let anchorCaret = self.anchorCaret {
            return self.getSegment(caret: anchorCaret)
        }
        
        return nil
    }
    var cachedAnchorCaret: Caret? = nil
    var cachedAnchor: EntrySegment? {
        if let cachedAnchorCaret = self.cachedAnchorCaret {
            return self.getSegment(caret: cachedAnchorCaret)
        }
        
        return nil
    }
    var textView: UITextView? = nil
    var cursorView: UIView? = nil
    var selectionTimeRange: CMTimeRange? {
        if let anchor = self.anchor,
           let focus = self.focus,
           self.direction == .forwards
        {
            return CMTimeRangeFromTimeToTime(
                start: anchor.timeMapping.target.start,
                end: focus.timeMapping.target.end
            )
        } else if
               let anchor = self.anchor,
               let focus = self.focus,
            self.direction == .backwards
        {
            return CMTimeRangeFromTimeToTime(
                start: focus.timeMapping.target.start,
                end: anchor.timeMapping.target.end
            )
        }
        
        // Have not implemented directionless
        
        return nil
    }
    var selectionTextRange: NSRange? {
        if let entry = self.entryManager.currentEntry,
            let anchor = self.anchor,
            let focus = self.focus,
            let anchorRange = entry.getSegmentTextRange(of: anchor),
            let focusRange = entry.getSegmentTextRange(of: focus) {
            let anchorLocation = anchorRange.location
            let anchorLength = anchorRange.length
            let focusLocation = focusRange.location
            let focusLength = focusRange.length
            
            if self.direction == .backwards {
                return NSRange(location: focusLocation, length: (anchorLocation - focusLocation) + anchorLength)
            } else {
                // forwards
                // directionless
                return NSRange(location: anchorLocation, length: (focusLocation - anchorLocation) + focusLength)
            }
        } else if let entry = self.entryManager.currentEntry,
                  let anchor = self.anchor,
                  !anchor.isVoiceCommandWord() &&
                    !anchor.isDeleted(),
                  let anchorRange = entry.getSegmentTextRange(of: anchor) {
            return anchorRange
        }

        return nil
    }
    var selectionRange: ClosedRange<Int>? {
        if let anchor = self.anchor,
           let focus = self.focus {
            
            if self.direction == .backwards {
                return focus.getIndex()...anchor.getIndex()
            } else {
                return anchor.getIndex()...focus.getIndex()
            }
        }

        return nil
    }
    var selectionText: String? {
        if let entry = self.entryManager.currentEntry,
           let anchor = self.anchor,
           let focus = self.focus,
            self.direction == .backwards
        {
            return entry.getText(
                from: focus.timeMapping.target.start,
                until: anchor.timeMapping.target.end
            )
        } else if let entry = self.entryManager.currentEntry,
            let anchor = self.anchor,
            let focus = self.focus,
            self.direction == .forwards
        {
            return entry.getText(
                from: anchor.timeMapping.target.start,
                until: focus.timeMapping.target.end
            )
        }
        
        return nil
    }
    var selectionSegments: [EntrySegment]? {
        guard let entry = self.entryManager.currentEntry,
              entry.entryBuffer.count == 0 else { return nil }

        var startIndex: Int?
        var endIndex: Int?
        if let anchor = self.anchor,
           let focus = self.focus,
           self.direction == .backwards {
            startIndex = focus.getIndex()
            endIndex = anchor.getIndex()
        } else if let anchor = self.anchor,
                  let focus = self.focus {
            startIndex = anchor.getIndex()
            endIndex = focus.getIndex()
        }
        
        guard startIndex != nil && endIndex != nil else { return nil }
        
        return Array(entry.entrySegments[startIndex!...endIndex!])
    }
    var direction: SelectionDirection {
        if let anchor = self.anchor,
           let focusCaret = self.focusCaret,
           let focus = self.getSegment(caret: focusCaret),
           focus.getIndex() >= anchor.getIndex() {
            return .forwards
        }
        
        return .backwards
    }
    private(set) var clipboard: [EntrySegment]? = nil
    var clipboardText: String? {
        if let entry = self.entryManager.currentEntry, let clipboard = self.clipboard {
            return entry.getText(
                from: clipboard.first!.timeMapping.target.start,
                until: clipboard.last!.timeMapping.target.end
            )
        }
        
        return nil
    }
    @objc dynamic var isCollapsed: Bool {
        return (
                self.anchorCaret != nil &&
                self.focusCaret == nil
        ) || (
            self.anchorCaret == nil &&
            self.focusCaret != nil
        )
    }
    // Allows you to place observer on computed properties: https://stackoverflow.com/questions/36555492/kvo-on-swifts-computed-properties
    @objc class var keyPathsForValuesAffectingIsCollapsed: Set<String> {
        return [ "focusCaret", "anchorCaret" ]
    }
    @objc dynamic var hasSelection: Bool {
        return self.anchorCaret != nil &&
            self.focusCaret != nil &&
            !self.isCollapsed
    }
    // Allows you to place observer on computed properties: https://stackoverflow.com/questions/36555492/kvo-on-swifts-computed-properties
    @objc class var keyPathsForValuesAffectingHasSelection: Set<String> {
        return [ "focusCaret", "anchorCaret", "isCollapsed" ]
    }
    var selectionTransformations: [EntryTransformation]? {
        guard let entry = self.entryManager.currentEntry,
            let anchor = self.anchor else { return nil }
        var transformations = [EntryTransformation]()
        let selectionLowerIndex = anchor.getIndex()
        for transformation in entry.transformations {
            if transformation.entryRange.contains(selectionLowerIndex) {
                transformations.append(transformation)
            }
        }
        return transformations
    }
    var isAtEndOfTextView: Bool {
        guard let entry = self.entryManager.currentEntry else { return false }
        let lastSegment = Utils.getEntryNthLastSegment(
            segments: entry.entrySegments,
            bufferSegments: entry.entryBuffer,
            selectionCursor: self,
            n: 0
        )
        if let anchor = self.anchor,
        let lastSegment = lastSegment {
            // we don't have a selection
            // we have a cursor though
//             print("isAtEndOfTextView 1: ")
            return anchor == lastSegment
        } else if (entry.entrySegments.count == 0 && entry.entryBuffer.count == 0) || entry.getText().count == 0 {
            // we have not captured and speech yet
//             print("isAtEndOfTextView 2: ")
            return true
        }

//         print("isAtEndOfTextView 3: ")
        return false
    }
    var isVisible: Bool {
        return self.cursorView != nil
    }
    private(set) var isUpdatingSelection = false
    private(set) var isPromptingForUpdateAcceptance = false
    var updateSegments: [EntrySegment]? = nil
    var isLoopingSelection = false
    private var manualSelection = false
    private var overrideSelectionUpdates = false
    
    // MARK: - Initialization

    init(
        state: StateManager,
        speechPlayer: SpeechPlayerEngine,
        speechSynthesis: SpeechSynthesisEngine,
        speechRecognition: SpeechRecognitionEngine,
        notifications: NotificationEngine,
        uiManager: UIManager
    ) {
        print("===== Selection Cursor: Initialization =====")
        self.state = state
        self.speechPlayer = speechPlayer
        self.speechSynthesis = speechSynthesis
        self.speechRecognition = speechRecognition
        self.notifications = notifications
        self.uiManager = uiManager
        
        super.init()

        self.configureNotificationObservers()
    }

    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)

        // remove observer from text view
        self.textView?.removeObserver(
            self,
            forKeyPath: "selectedTextRange",
            context: nil
        )
        
        // remove observer from anchor
        self.removeObserver(
            self,
            forKeyPath: "anchorCaret",
            context: nil
        )
        
        // remove observer from focus
        self.removeObserver(
            self,
            forKeyPath: "focusCaret",
            context: nil
        )
    }
    
    // MARK: - Methods
    
    func checkRep() {
        var result = true
        
        // We either have no anchor and focus or both are set, but never one or the other?
        
        // if we don't have selection, we have a cursor and we only have the anchor positioned at the end of the anchor segment
        
        // Don't have update segments unless you're updating
        result = result && ((self.updateSegments != nil && self.isUpdatingSelection) || self.updateSegments == nil)
        
        if !result {
            fatalError("===== [Error] SelectionCursor Representation Invariants were broken =====")
        }
    }
    
    public override var description: String {
        return "SelectionCursor {\n\tfocusCaret: \(String(describing: self.focusCaret)) \n\tanchorCaret: \(String(describing: self.anchorCaret)) \n\tcachedAnchorCaret: \(String(describing: self.cachedAnchorCaret)) \t\nselectionTimeRange: \(String(describing: self.selectionTimeRange)) \n\tselectionTextRange: \(String(describing: self.selectionTextRange)) \n\tselectionRange: \(String(describing: self.selectionRange)) \n\tselectionText: \(String(describing: self.selectionText)) \n\tselectionSegments: \(String(describing: self.selectionSegments)) \n\tdirection: \(self.direction) \n\tclipboard: \(String(describing: self.clipboard)) \n\tisCollapsed: \(self.isCollapsed) \n\tisAtEndOfView: \(self.isAtEndOfTextView) \n\tisUpdatingSelection: \(self.isUpdatingSelection) \n\tisPromptingForUpdateAcceptance: \(self.isPromptingForUpdateAcceptance) \n\tupdateSegments: \(String(describing: self.updateSegments)) \n\tisLoopingSelection: \(self.isLoopingSelection) \n\tmanualSelection: \(self.manualSelection)\n}"
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
        // add observer to anchor
        self.addObserver(
            self,
            forKeyPath: "anchorCaret",
            options: [.old, .new],
            context: nil
        )
        
        // add observer to focus
        self.addObserver(
            self,
            forKeyPath: "focusCaret",
            options: [.old, .new],
            context: nil
        )
        
        // Voice Commands
        notificationCenter.addObserver(
            self,
            selector: #selector(onProcessedVoiceCommand(notification:)),
            name: VoiceCommandEngine.onProcessedVoiceCommand,
            object: nil
        )
    }
    
    @objc func onProcessedVoiceCommand(notification: Notification) {
        print("===== Selection Cursor: On Processed Voice Command =====")
        let command = notification.userInfo!["command"] as! VoiceCommandEngine.VoiceCommand
        var handler: (() -> Void)?
        if notification.userInfo!["handler"] != nil {
            handler = notification.userInfo!["handler"] as? () -> Void
        }
        switch (command) {
        case .INSPECT_CLIPBOARD:
            self.inspectClipboard(voiceCommand: true, handler: handler)
        default:
            // Do Nothing
            break
        }
    }
    
    // MARK: - Action Methods
    
    func collapse(toAnchorSegment: Bool = false) {
        print("===== Selection Cursor: Collapse =====")
        if toAnchorSegment {
            self.willChangeValue(forKey: "focusCaret")
            self.focusCaret = anchorCaret?.duplicate()
            self.didChangeValue(forKey: "focusCaret")
            
        } else {
            self.willChangeValue(forKey: "anchorCaret")
            self.anchorCaret = focusCaret?.duplicate()
            self.didChangeValue(forKey: "anchorCaret")
        }
        
        checkRep()
    }

    // ballistic movement
    //
    // moves as a cursor
    func moveCursor(caret: Caret, cache: Bool = false) {
        guard let _ = self.entryManager.currentEntry else { return }
        print("===== Selection Cursor: Move (using track and index) =====")
        let segment = self.getSegment(caret: caret)
        print("\tSegment: '\(segment?.getText() ?? "nil")'")
        
        if AVAudioSession.isHeadphonesConnected {
            if self.speechPlayer.isPlayingEntry {
                print("\tEntry is playing. Turning off...")
                self.stopPlayingSelection()
            }
            
            if self.isLoopingSelection {
                print("\tisLoopingSelection activate. Turning off...")
                self.stopPlayingSelection()
            }
        }
        
        // update model
        if caret.trackType == .committed {
            print("\tSegment is a commited segment...")
        } else if caret.trackType == .buffer {
            print("\tSegment is a buffer segment...")
        }

        // set new selection
        print("\tSetting carets...")
        self.setAnchorCaret(caret: caret.duplicate())
        self.setFocusCaret()
        
        // Used when we want to insert a buffer into the committed segments
        // allows us to determine segment of interest
        if cache && !self.isAtEndOfTextView {
            self.setCachedAnchorCaret(caret: caret.duplicate())
        } else if self.isAtEndOfTextView {
            self.setCachedAnchorCaret()
        }
        
        // update view
        if let selectionTextRange = self.selectionTextRange,
           let textView = self.textView,
           let textPosition = selectionTextRange.toTextRange(textInput: textView)?.end,
           let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: textPosition)
        {
            print("\tUpdate cursor caret screen position...")
            self.moveCaretView(to: caretViewRect)
        }

        checkRep()
    }
    
    func moveCursor(textPosition: UITextPosition, cache: Bool = false) {
        guard let entry = self.entryManager.currentEntry else { return }
        print("=====  Selection Cursor: Move (using textPosition) =====")
        
        var entrySegments: [EntrySegment]
        var oldAnchorIndex = Int(Utils.UNKNOWN)
        if let cachedAnchorCaret = self.cachedAnchorCaret {
            // insert buffer at the correct place based on cursor position
            entrySegments = entry.entrySegments
            oldAnchorIndex = cachedAnchorCaret.index
            if oldAnchorIndex != Int(Utils.UNKNOWN) {
                entrySegments.insert(contentsOf: entry.entryBuffer, at: oldAnchorIndex)
            } else {
                entrySegments += entry.entryBuffer
            }
        } else {
            // insert buffer at the end of segments
            entrySegments = entry.entrySegments + entry.entryBuffer
        }
        
        let (index, rightOffsetFromCaret) = Utils.getIndexAtTextPosition(
            textPosition: textPosition,
            textView: self.textView!,
            entry: entry,
            segments: entrySegments
        )
        
        if let index = index {
            // Setting carets...
            var trackType: EntryTrackType?
            var newAnchorIndex: Int?
            if let cachedAnchorCaret = self.cachedAnchorCaret {
                // Cached Anchor Caret exists. Seek for track type and index by dividing segments array into three sections
                if index < cachedAnchorCaret.index {
                    // Index is before location where buffer was inserted...
                    trackType = .committed
                    newAnchorIndex = index
                } else if index >= cachedAnchorCaret.index && index < cachedAnchorCaret.index + entry.entryBuffer.count
                {
                    // Index is in buffer...
                    trackType = .buffer
                    newAnchorIndex = index - cachedAnchorCaret.index
                } else if index >= cachedAnchorCaret.index + entry.entryBuffer.count {
                    // Index is after buffer...
                    trackType = .committed
                    newAnchorIndex = index - entry.entryBuffer.count
                }
            } else {
                // Cached Anchor Caret doesn't exist. Seek for track type and index by dividing segments array into two sections...
                if index >= entry.entrySegments.count {
                    // Index is in buffer...
                    trackType = .buffer
                    newAnchorIndex = index - entry.entrySegments.count
                } else {
                    // Index is committed segment (before buffer)...
                    trackType = .committed
                    newAnchorIndex = index
                }
            }
            
            if let newAnchorIndex = newAnchorIndex, let trackType = trackType {
                // Setting anchor caret...
                // we know this is an active word because Utils.getIndexAtTextPosition only returns active words
                self.setAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: trackType))
                self.setFocusCaret()
            }
            
            // Used when we want to insert a buffer into the committed segments
            // allows us to determine segment of interest
            if let newAnchorIndex = newAnchorIndex,
               let trackType = trackType,
               cache &&
                !self.isAtEndOfTextView
            {
                // Update cached anchor index because we're not at the end of the text view...
                self.setCachedAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: trackType))
            } else if self.isAtEndOfTextView {
                self.setCachedAnchorCaret()
            }
        } else {
            print("===== [Error] There was a problem finding cursor entry segment =====")
        }
        
        // update view
        if let rightOffsetFromCaret = rightOffsetFromCaret {
            let updatedTextPosition = self.textView!.position(from: textPosition, offset: rightOffsetFromCaret)
            if let updatedTextPosition = updatedTextPosition, let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: updatedTextPosition) {
                self.moveCaretView(to: caretViewRect)
            }
        }
        
        checkRep()
    }
    
    func isSegmentInRange(segment: EntrySegment) -> Bool {
        guard let entry = self.entryManager.currentEntry, let selectionTextRange = self.selectionTextRange else { return false }

        let segmentRange = entry.getSegmentTextRange(of: segment)
        
        if let segmentRange = segmentRange {
            return NSIntersectionRange(selectionTextRange, segmentRange).length > 0
        }
        
        return false
    }
    
    func playNeighborhood(loop: Bool = false) {
        print("==== Selection Cursor: Play Neighborbood =====")
        var startTime: CMTime?
        var endTime: CMTime?
        if let focus = self.focus,
           let anchor = self.anchor,
           self.direction == .backwards
        {
            print("\tSelection has backwards direction.")
            print("\tSelection start and end times retrieved.")
            startTime = focus.getSentence().timeRange.start
            endTime = anchor.getSentence().timeRange.end
        } else if let focus = self.focus,
            let anchor = self.anchor
        {
            print("\tSelection has forward direction.")
            print("\tSelection start and end times retrieved.")
            startTime = anchor.getSentence().timeRange.start
            endTime = focus.getSentence().timeRange.end
        }
        
        if let startTime = startTime, let endTime = endTime {
            self.playPassage(startTime: startTime, endTime: endTime, loop: loop)
        }
        
        checkRep()
    }
        
    func playSelection(loop: Bool = false) {
        print("===== Selection Cursor: Play Selection =====")
        var startTime: CMTime?
        var endTime: CMTime?
        if let focus = self.focus,
           let anchor = self.anchor,
           self.direction == .backwards
        {
            print("\tSelection has backwards direction.")
            print("\tSelection start and end times retrieved.")
            startTime = focus.timeMapping.target.start
            endTime = anchor.timeMapping.target.end
        } else if let focus = self.focus,
            let anchor = self.anchor
        {
            print("\tSelection has forward direction.")
            print("\tSelection start and end times retrieved.")
            startTime = anchor.timeMapping.target.start
            endTime = focus.timeMapping.target.end
        }
        
        if let startTime = startTime, let endTime = endTime {
            self.playPassage(startTime: startTime, endTime: endTime, loop: loop)
        }

        checkRep()
    }
    
    func stopPlayingSelection() {
        print("===== Selection Cursor: Stop Playing Selection =====")
        if self.isLoopingSelection {
            self.isLoopingSelection = false
            
            // Stop Sound
            if soundEngine.isProcessing {
                print("\tSound Engine playing 'Processing Sound'. Turning off..")
                soundEngine.stopProcessing()
            }
            
            // Stop Entry
            self.speechPlayer.stop(withFeedback: false)
        }
        
        checkRep()
    }
    
    func playPassage(startTime: CMTime, endTime: CMTime, loop: Bool = false) {
        print("===== Selection Cursor: Play Passage =====")
        print("\tPlaying from: \(startTime.seconds) to \(endTime.seconds)")

        if let entry = self.entryManager.currentEntry {
            print("\tPreparing to play selection.")
            if loop {
                print("\tActivated looping selection.")
                self.isLoopingSelection = true
            } else {
                print("\tDeactivated looping selection.")
                self.stopPlayingSelection()
            }

            self.speechPlayer.play(
                entry: entry,
                from: startTime,
                to: endTime
            )
        } else if AVAudioSession.isHeadphonesConnected {
            print("\tNo selection start and end times found. Abort method.")

            if self.speechPlayer.isPlayingEntry {
                print("\tEntry is playing. Turning off...")
                self.stopPlayingSelection()
            }
            
            if self.isLoopingSelection {
                print("\tisLoopingSelection activate. Turning off...")
                self.stopPlayingSelection()
            }
        }

        checkRep()
    }
    
    // micro-movement
    // requires there to be a selection
    func shift(shiftDirection: SelectionShiftDirection, by count: Int = 1) {
        print("===== Selection Cursor: Shift \(shiftDirection) =====")
        self.shiftAnchorSegment(shiftDirection: shiftDirection, by: count)
        self.shiftFocusSegment(shiftDirection: shiftDirection, by: count)
        checkRep()
    }
    
    func shiftFocusSegment(shiftDirection: SelectionShiftDirection, by count: Int = 1) {
        print("===== Selection Cursor: Shift Focus Segment \(shiftDirection) =====")
        // prevent illegal moves
        guard let entry = self.entryManager.currentEntry,
              let focus = self.focus,
              let anchor = self.anchor,
              entry.entryBuffer.count == 0 else { return }
        
        let numSegments = entry.entrySegments.count
        var nextFocusIndex: Int?
        if shiftDirection == .next && self.direction == .forwards {
            // next
            // forwards
            let shiftLength = focus.getIndex() + count >= numSegments ? (numSegments - 1) - focus.getIndex() : count
            nextFocusIndex = focus.getIndex() + shiftLength
        } else if shiftDirection == .next && self.direction == .backwards {
            // next
            // backwards
            let shiftLength = anchor.getIndex() + count >= numSegments ? (numSegments - 1) - anchor.getIndex() : count
            nextFocusIndex = focus.getIndex() + shiftLength
        } else if shiftDirection == .previous && self.direction == .forwards {
            // previous
            // forwards
            let shiftLength = anchor.getIndex() - count < 0 ? anchor.getIndex() : count
            nextFocusIndex = focus.getIndex() - shiftLength
        } else if shiftDirection == .previous && self.direction == .backwards {
            // previous
            // backwards
            let shiftLength = focus.getIndex() - count < 0 ? focus.getIndex() : count
            nextFocusIndex = focus.getIndex() - shiftLength
        }
        
        if let nextFocusIndex = nextFocusIndex {
            self.setFocusCaret(caret: Caret(index: nextFocusIndex, trackType: .committed))
        } else {
            print("===== [Error] There was a problem computing new focus segment index =====")
        }
        
        checkRep()
    }
    
    func shiftAnchorSegment(shiftDirection: SelectionShiftDirection, by count: Int = 1) {
        print("===== Selection Cursor: Shift Anchor Segment \(shiftDirection) =====")
        // prevent illegal moves
        guard let entry = self.entryManager.currentEntry,
              let focus = self.focus,
              let anchor = self.anchor,
              entry.entryBuffer.count == 0 else { return }

        let numSegments = entry.entrySegments.count
        var nextAnchorIndex: Int?
        if shiftDirection == .next && self.direction == .forwards {
            // next
            // forwards
            let shiftLength = focus.getIndex() + count >= numSegments ? (numSegments - 1) - focus.getIndex() : count
            nextAnchorIndex = anchor.getIndex() + shiftLength
        } else if shiftDirection == .next && self.direction == .backwards {
            // next
            // backwards
            let shiftLength = anchor.getIndex() + count >= numSegments ? (numSegments - 1) - anchor.getIndex() : count
            nextAnchorIndex = anchor.getIndex() + shiftLength
        } else if shiftDirection == .previous && self.direction == .forwards {
            // previous
            // forwards
            let shiftLength = anchor.getIndex() - count < 0 ? anchor.getIndex() : count
            nextAnchorIndex = anchor.getIndex() - shiftLength
        } else if shiftDirection == .previous && self.direction == .backwards {
            // previous
            // backwards
            let shiftLength = focus.getIndex() - count < 0 ? focus.getIndex() : count
            nextAnchorIndex = anchor.getIndex() - shiftLength
        }
        
        if let nextAnchorIndex = nextAnchorIndex {
            self.setAnchorCaret(caret: Caret(index: nextAnchorIndex, trackType: .committed))
        } else {
            print("===== [Error] There was a problem computing new anchor segment index =====")
        }
        
        checkRep()
    }
    
    func expand(by count: Int = 1) {
        print("===== Selection Cursor: Expand =====")
        let anchorShiftDirection: SelectionShiftDirection = self.direction == .forwards ? .previous : .next
        let focusShiftDirection: SelectionShiftDirection = self.direction == .forwards ? .next : .previous
        self.shiftAnchorSegment(shiftDirection: anchorShiftDirection, by: count)
        self.shiftFocusSegment(shiftDirection: focusShiftDirection, by: count)
        
        checkRep()
    }
    
    func reduce(by count: Int = 1) {
        print("===== Selection Cursor: Reduce =====")
        let anchorShiftDirection: SelectionShiftDirection = self.direction == .forwards ? .next : .previous
        let focusShiftDirection: SelectionShiftDirection = self.direction == .forwards ? .previous : .next
        self.shiftAnchorSegment(shiftDirection: anchorShiftDirection, by: count)
        self.shiftFocusSegment(shiftDirection: focusShiftDirection, by: count)

        checkRep()
    }

    func adjustRateSelection(direction: DirectionType, handler: ((_ rate: Float) -> Void)? = nil) {
        print("===== Selection Cursor: Adjust Rate \(direction) =====")
        // prevent illegal deletions
        guard let entry = self.entryManager.currentEntry, self.hasSelection else {
            print("====== [Error] There was a problem adjust selection rate =====")
            return
        }
        
        guard let selectionRange = self.selectionRange else { return }
        
        print("\tSlice transformation into ranges with equal rates...")
        
        var startIndex: Int?
        var lastIndex: Int?
        var lastRate: Float?
        var transformationRanges = [ClosedRange<Int>]()
        print("\tLocating first transformation range...")
        for segment in entry.entrySegments[selectionRange] {
            if lastRate == nil {
                // first segment
                startIndex = segment.getIndex()
                lastIndex = segment.getIndex()
                lastRate = segment.getRate()
                print("\tNew transformation range lower bound index: ", startIndex!)
            } else if startIndex != nil && lastIndex != nil && segment.getRate() != lastRate! {
                // create transformation range
                transformationRanges.append(startIndex!...lastIndex!)
                print("New transformation range: ", startIndex!...lastIndex!)
                
                // reinitialize start index
                startIndex = segment.getIndex()
                lastIndex = segment.getIndex()
                lastRate = segment.getRate()
                print("\tNew transformation range lower bound index: ", startIndex!)
            } else {
                // increment last index
                lastIndex = segment.getIndex()
                lastRate = segment.getRate()
            }
        }
        
        // create last segment
        if startIndex != nil && lastIndex != nil {
            // create transformation range
            transformationRanges.append(startIndex!...lastIndex!)
            print("\tNew transformation range: ", startIndex!...lastIndex!)
        }
        
        for range in transformationRanges {
            var lowerSegmentIndex = range.lowerBound
            var upperSegmentIndex = range.upperBound
            var lowerSegment = entry.entrySegments[lowerSegmentIndex]
            var upperSegment = entry.entrySegments[upperSegmentIndex]
            while (lowerSegment.isVoiceCommandWord() || lowerSegment.isSilence() || lowerSegment.isDeleted()) && lowerSegmentIndex < range.upperBound {
                // must not be a silence or voice command word
                lowerSegmentIndex += 1
                lowerSegment = entry.entrySegments[lowerSegmentIndex]
            }
            while (upperSegment.isVoiceCommandWord() || upperSegment.isSilence() || lowerSegment.isDeleted()) && upperSegmentIndex > range.lowerBound {
                // must not be a silence or voice command word
                upperSegmentIndex -= 1
                upperSegment = entry.entrySegments[upperSegmentIndex]
            }

            // Compute rate value
            var newRate = lowerSegment.getRate()
            if direction == .up {
                newRate += Utils.DISCRETE_PLAYBACK_DELTA
            } else {
                newRate -= Utils.DISCRETE_PLAYBACK_DELTA
            }
            
            // Round off new rate
            newRate = newRate.rounded(toPlaces: 1)
            
            print("\tStore transformation with range: \(range) and rate: \(newRate)")
            
            // Compute text
            let text = entry.getText(
                from: lowerSegment.timeMapping.target.start,
                until: upperSegment.timeMapping.target.end,
                segments: entry.entrySegments
            )
            print("\tCompute transformation text: ", text)
            
            // Compute text range
            let lowerRange = entry.getSegmentTextRange(of: lowerSegment)
            let upperRange = entry.getSegmentTextRange(of: upperSegment)
            let lowerLocation = lowerRange!.location
            let upperLocation = upperRange!.location
            let upperLength = upperRange!.length
            let textRange = NSRange(location: lowerLocation, length: (upperLocation - lowerLocation) + upperLength)
            
            // Store transformation
            print("\tStore transformation...")
            entry.handleTransformation(
                type: .playbackRate,
                passageText: text,
                value: newRate,
                textRange: textRange,
                entryRange: range
            )
        }

        // Play Sound
        soundEngine.voiceCommandAccept()        
        
        checkRep()
        
        if let rate = lastRate {
            var newRate = rate
            if direction == .up {
                newRate += Utils.DISCRETE_PLAYBACK_DELTA
            } else {
                newRate -= Utils.DISCRETE_PLAYBACK_DELTA
            }
            
            handler?(newRate)
        }
    }
    
    func deleteSelection(withFeedback: Bool = true, isCommit: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Delete Selection =====")
        // prevent illegal deletions
        guard let entry = self.entryManager.currentEntry, let selectionTimeRange = self.selectionTimeRange else {
            print("====== [Error] There was a problem deleting selection. TimeRange could not be computed =====")
            return
        }
        
        let handleDeleteSelection = {
            // stop playback
            print("\tStop playing selection...")
            self.stopPlayingSelection()
            
            // remove focus
            print("\tRemove focus...")
            self.setFocusCaret() // So that we don't update it with a new focus
            
            // cache anchor if not at end of entry
            if let anchor = self.anchor,
               !self.isAtEndOfTextView
            {
                print("\tCursor not at end of text view; update cached anchor...")
                
                let newAnchorIndex = Utils.getSegmentIndex(
                    segment: anchor,
                    segments: entry.entrySegments,
                    type: .previous,
                    isWord: true,
                    isCommitted: true
                )

                if let newAnchorIndex = newAnchorIndex {
                    print("\tSetting new anchor with index: ", newAnchorIndex)
                    self.setAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: .committed))
                }
                
                if let newAnchorIndex = newAnchorIndex, !self.isAtEndOfTextView {
                    print("\tSetting new cached anchor with index: ", newAnchorIndex)
                    self.setCachedAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: .committed))
                } else {
                    print("\t[Error] New anchor not found...")
                    self.setCachedAnchorCaret()
                }
            } else {
                print("\tCursor at end of text view. Clear any anchors")
                self.setAnchorCaret()
                self.setCachedAnchorCaret()
            }
            
            // remove passage
            print("\tRemove selection with time range: start =\(selectionTimeRange.start.seconds), end =\(selectionTimeRange.start.seconds + selectionTimeRange.duration.seconds)")
            entry.removePassage(range: selectionTimeRange)
            
            // move cursor
            if let cachedAnchorCaret = self.cachedAnchorCaret {
                print("\tMove cursor to cached anchor")
                self.moveCursor(caret: cachedAnchorCaret)
            }
            
            if isCommit && withFeedback {
                // Present Feedback
                self.notifications.executeFeedback(
                    visualMessage: "Delete Commit",
                    audioMessage: "commit deleted",
                    withHaptics: true
                )
            } else if withFeedback {
                // Present Feedback
                self.notifications.executeFeedback(
                    visualMessage: "Delete Selection",
                    audioMessage: "selection deleted",
                    withHaptics: true
                )
            }
            
            
            handler?()

            // play to hear difference
            self.checkRep()
        }
        
        // Stop walking/running if currently doing so
        if self.entryManager.isWalkingEntry || self.entryManager.isRunningEntry {
            entry.exitWalk(clearSelection: false, withFeedback: false) {
                handleDeleteSelection()
            }
        } else {
            handleDeleteSelection()
        }
        
        // Play sound
        soundEngine.delete()
    }
    
    func initiateUpdateSelection(handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Initiate Update Selection =====")
        // prevent illegal updating
        guard let entry = self.entryManager.currentEntry else { return }
        
        // Stop playback
        if AVAudioSession.isHeadphonesConnected {
            if self.speechPlayer.isPlayingEntry {
                print("\tEntry is playing. Turning off...")
                self.stopPlayingSelection()
            }
            
            if self.isLoopingSelection {
                print("\tisLoopingSelection activate. Turning off...")
                self.stopPlayingSelection()
            }
        }

        // Stop echo
        if self.speechSynthesis.isPlayingEcho {
            self.speechSynthesis.stopEcho(withFeedback: false)
        }
        
//        if self.isUpdatingSelection {
//            self.notifications.executeError(
//                text: "Already updating selection."
//            )
//
//            self.speechRecognition.startListeningForSpeech(
//                onStartHandler: handler
//            )
//            return
//        }
        
        // signal that we'll be updating selection
        //
        // we place it as early as possible so that other
        // methods that read the property get the new value early
        // e.g. executeSelectionUpdates
        if !self.isUpdatingSelection {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Initiate Update",
                audioMessage: "listening for update",
                withHaptics: true
            )
        }

        self.isUpdatingSelection = true
        
        let handleInitiateUpdateSelection = {
            // Start recording to update segment
            self.speechRecognition.startListeningForSpeech() {
                handler?()
            }
            
            // clear update segments
            self.updateSegments = nil
            
            // IMPORTANT: turn off prompting for selection acceptance flag
            self.isPromptingForUpdateAcceptance = false

            // play to hear difference
            self.checkRep()
        }
        
        // Pause walking / running
        if self.entryManager.isWalkingEntry || self.entryManager.isRunningEntry {
            entry.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                handleInitiateUpdateSelection()
            }
        } else {
            handleInitiateUpdateSelection()
        }
    }
    
    func handleUpdateSelection(segments: [EntrySegment]) {
        print("===== Selection Cursor: Handle Update Selection =====")
        guard let entry = self.entryManager.currentEntry, let selectionText = self.selectionText, segments.count > 0 else {
            print("\t[Error]: ", self.entryManager.currentEntry != nil, self.selectionText != nil, segments.count > 0)
            return
        }
        
        // turn on prompting for selection acceptance flag
        self.isPromptingForUpdateAcceptance = true

        // duplicate entry tracks
        print("\tDuplicating buffer segments...")
        var updateSegments = [EntrySegment]()
        for segment in segments {
            updateSegments.append(segment.duplicate())
        }
        
        // normalize segments
        print("\tNormalizing update segments...")
        let normalizedUpdateSegments = entry.normalizeSegments(
            segments: segments,
            omitLeadingSilence: true,
            returnSegments: true
        )
        
        // Svae presumed update segments
        self.updateSegments = normalizedUpdateSegments
        
        // Compute update selectiont text
        let updateText = entry.getText(segments: self.updateSegments)
        
        // Present Update Dialog
        let dialogActions = [
            DialogAction(
                title: "Accept",
                voiceCommand: .ACCEPT_SELECTION_UPDATE,
                feedbackVisualMessage: "Updated!",
                feedbackAudioMessage: "selection updated",
                style: .default,
                handler: { [weak self] action in
                    // Accept Update
                    print("\tAccepting Update Selection...")
                    self?.entryManager.acceptUpdateSelection()
                }
            ),
            DialogAction(
                title: "Redo",
                voiceCommand: .REDO_SELECTION_UPDATE,
                feedbackVisualMessage: "Redo Update",
                feedbackAudioMessage: "redo update",
                style: .destructive,
                handler: { [weak self] action in
                    // Redo Update Selection
                    print("\tRedoing Update Selection...")
                    self?.entryManager.redoUpdateSelection()
                }
            ),
            DialogAction(
                title: "Cancel",
                voiceCommand: .CANCEL_DIALOG,
                feedbackVisualMessage: "Canceled!",
                feedbackAudioMessage: "Command canceled",
                style: .cancel,
                handler: { [weak self] action in
                    // Cancel Update Selection
                    print("\tCanceling Update Selection...")
                    self?.entryManager.cancelUpdateSelection()
                }
            )
        ]
        
        let dialogItem = DialogItem(
            title: "Update Selection",
            message: "Update \"\(selectionText)\" with \"\(updateText)\". Say 'accept', 'redo', or 'cancel' to dismiss?",
            preferredStyle: .alert,
            actions: dialogActions
        )

        self.uiManager.presentDialog(
            dialogItem: dialogItem
        )
        
        checkRep()
    }
    
    func acceptUpdateSelection(handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Accept Update Selection =====")

        // prevent illegal updating
        guard let entry = self.entryManager.currentEntry, let selectionTimeRange = self.selectionTimeRange, let updateSegments = self.updateSegments else { return }
        
        var segments = [EntrySegment]()
        for segment in updateSegments {
            let duplicateSegment = segment.duplicate(withNewUID: true)
            segments.append(duplicateSegment)
        }
        
        // Update to new anchor
        let lastSegment = segments.last
        var newAnchorIndex: Int? = nil
        if let _ = lastSegment, !lastSegment!.isActive() {
            let (_, index) = Utils.getEntryNthLastSegmentIndex(
                segments: segments,
                selectionCursor: self,
                n: 0
            )
            newAnchorIndex = index
        } else if let _ = lastSegment, lastSegment!.isActive() {
            newAnchorIndex = segments.count - 1
        }
        
        var anchorIndex: Int?
        var cachedAnchorIndex: Int?
        if let index = newAnchorIndex, let cachedAnchorCaret = self.cachedAnchorCaret {
            print("\tCached Anchor and Anchor exist...")
            print("\tUpdate anchor and cached anchor to be first segment in updated segments")
            anchorIndex = cachedAnchorCaret.index + index
            cachedAnchorIndex = cachedAnchorCaret.index + index
        } else if let index = newAnchorIndex, let anchorCaret = self.anchorCaret {
            print("\tOnly Anchor exists...")
            print("\tUpdate anchor to be first segment in updated segments")
            anchorIndex = anchorCaret.index + index
        } else {
            print("\tNeither anchor nor cached anchor exist")
            print("\tDo nothing.")
        }
        
        // Update to new focus
        let firstSegment = segments.first
        var newFocusIndex: Int? = nil
        if let segment = firstSegment, !firstSegment!.isActive() {
            newFocusIndex = Utils.getSegmentIndex(
                segment: segment,
                segments: segments,
                type: .next,
                isWord: true
            )
        } else if let _ = firstSegment, firstSegment!.isActive() {
            newFocusIndex = 0
        }
        
        var focusIndex: Int?
        if let index = newFocusIndex, let anchorCaret = self.anchorCaret {
            print("\tUpdate focus to be last segment in updated segments")
            focusIndex = anchorCaret.index + index
        } else {
            print("\tFocus or anchor does not exist.")
            print("\tDo nothing.")
        }
        
        // Update Selection
        entry.updatePassage(
            segments: segments,
            range: selectionTimeRange
        )
        
        if let anchorIndex = anchorIndex,
           let focusIndex = focusIndex {
            print("\tSetting new selection: \(anchorIndex)...\(focusIndex)")
            self.setSelection(
                anchorCaret: Caret(index: anchorIndex, trackType: .committed),
                focusCaret: Caret(index: focusIndex, trackType: .committed)
            )
        } else if let index = anchorIndex {
            print("\tSetting new anchor: ", index)
            self.setAnchorCaret(caret: Caret(index: index, trackType: .committed))
        } else if let index = focusIndex {
            print("\tSetting new focus: ", index)
            self.setFocusCaret(caret: Caret(index: index, trackType: .committed))
        }
        
        if let index = cachedAnchorIndex {
            print("\tSetting new cached anchor: ", index)
            self.setCachedAnchorCaret(caret: Caret(index: index, trackType: .committed))
        }
    
        // Clear accumulated buffer
        entry.clearBuffer()
        
        // turn off update selection flag
        self.isUpdatingSelection = false

        // clear update segments
        self.updateSegments = nil

        // turn off prompting for selection acceptance flag
        self.isPromptingForUpdateAcceptance = false
        
        // begin looping selection audio
        // turn on processing sound
        if AVAudioSession.isHeadphonesConnected &&
            !self.entryManager.isRunningEntry &&
            !self.entryManager.isWalkingEntry &&
            !self.speechPlayer.isPlayingEntry &&
            !self.isUpdatingSelection
        {
            print("\t[Headphones connected] Play Selection Audio.")
            self.playSelection(loop: true)
            print("\t[Headphones connected] Play Processing Sound Effect.")
            
            soundEngine.startProcessing()
        }
        
        if self.entryManager.pausedWalkingEntry {
            entry.walk() {
                handler?()
            }
        } else if self.entryManager.pausedRunningEntry {
            entry.run() {
                handler?()
            }
        } else {
            handler?()
        }

        // play to hear difference
        checkRep()
    }
    
    func cancelUpdateSelection(handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Cancel Update Selection =====")
        // prevent illegal updating
        guard let entry = self.entryManager.currentEntry else { return }
        
        let handleCancelUpdate = {
            // turn off update selection flag
            print("\tTurning off update selection flag...")
            self.isUpdatingSelection = false
            
            // clear update segments
            print("\tClearing update segments...")
            self.updateSegments = nil
            
            // turn off prompting for selection acceptance flag
            print("\tTurning off prompting for selection acceptance flag...")
            self.isPromptingForUpdateAcceptance = false
            
            // begin looping selection audio
            // turn on processing sound
            if AVAudioSession.isHeadphonesConnected &&
                !self.entryManager.isRunningEntry &&
                !self.entryManager.isWalkingEntry &&
                !self.speechPlayer.isPlayingEntry &&
                !self.isUpdatingSelection
            {
                print("\t[Headphones connected] Play Selection Audio.")
                self.playSelection(loop: true)
                print("\t[Headphones connected] Play Processing Sound Effect.")
                
                soundEngine.startProcessing()
            }
            
            if !self.speechRecognition.pausedListeningForSpeech {
                print(
                    "\tPause listening for speech and listen for commands...",
                    self.speechRecognition.pausedListeningForSpeech,
                    self.speechRecognition.isListeningForCommands
                )
                self.speechRecognition.pauseListeningForSpeech(onPauseHandler: handler)
            } else if !self.speechRecognition.isListeningForCommands {
                print("\tStart listening for commands...")
                self.speechRecognition.startListeningForVoiceCommands(
                    onStartHandler: handler
                )
            }

            // play to hear difference
            self.checkRep()
        }
        
        if self.entryManager.pausedWalkingEntry {
            entry.walk() {
                handleCancelUpdate()
            }
        } else if self.entryManager.pausedRunningEntry {
            entry.run() {
                handleCancelUpdate()
            }
        } else {
            handleCancelUpdate()
        }
    }
    
    func copySelection(withFeedback: Bool = true) {
        print("===== Selection Cursor: Copy Selection =====")

        if let selectionSegments = self.selectionSegments {
            var duplicateSegments = [EntrySegment]()
            for segment in selectionSegments {
                duplicateSegments.append(segment.duplicate())
            }
            self.clipboard = duplicateSegments
        }
        
        if withFeedback {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Copy Selection",
                audioMessage: "selection copied",
                withHaptics: true
            )
        }
        
        // Notify Observers of Clipboard Change
        NotificationCenter.default.post(
            name: SelectionCursor.onClipboardChange,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func cutSelection(handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Cut Selection =====")
        // copy selection
        self.copySelection(withFeedback: false)
        
        // delete selection
        self.deleteSelection(withFeedback: false)
        
        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: "Cut Selection",
            audioMessage: "selection cut",
            withHaptics: true
        )
        
        handler?()

        // play to hear difference
        checkRep()
    }

    func pasteClipboard(handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Paste Clipboard =====")
        if let entry = self.entryManager.currentEntry,
           let anchor = self.anchor,
           let clipboard = self.clipboard,
           clipboard.count > 0 {
            
            var pastedSegments = [EntrySegment]()
            for segment in clipboard {
                let duplicateSegment = segment.duplicate(withNewUID: true)
                duplicateSegment.setEntry(entry: entry)
                pastedSegments.append(duplicateSegment)
            }

            // Update to new anchor
            let (_, newIndex) = Utils.getEntryNthLastSegmentIndex(
                segments: entry.entrySegments,
                // we treat the pasted segments as a 'buffer' to compute cursor position
                bufferSegments: pastedSegments,
                fromBuffer: true,
                selectionCursor: self,
                n: 0
            )
            
            var anchorIndex: Int?
            if let index = newIndex, let cachedAnchorCaret = self.cachedAnchorCaret {
                print("\tCached Anchor and Anchor exist...")
                print("\tUpdate anchor and cached anchor to be last segment in pasted segments")
                anchorIndex = cachedAnchorCaret.index + index + 1
            } else if let index = newIndex, let anchorCaret = self.anchorCaret {
                print("\tOnly Anchor exists...")
                print("\tUpdate anchor to be last segment in pasted segments")
                anchorIndex = anchorCaret.index + index + 1
            } else {
                print("\tNeither anchor nor cached anchor exist")
                print("\tDo nothing.")
            }
            
            // Insert selection into entry
            entry.insertPassage(
                segments: pastedSegments,
                at: anchor.timeMapping.target.end
            )
            
            if let index = anchorIndex, let _ = self.cachedAnchorCaret {
                print("\tSetting new anchor and cached anchor: ", index)
                self.setAnchorCaret(caret: Caret(index: index, trackType: .committed))
                self.setCachedAnchorCaret(caret: Caret(index: index, trackType: .committed))
            } else if let index = anchorIndex, let _ = self.anchorCaret {
                print("\tSetting new anchor: ", index)
                self.setAnchorCaret(caret: Caret(index: index, trackType: .committed))
            }
            
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Pasted!",
                audioMessage: "clipboard pasted",
                withHaptics: true
            )
            
            handler?()
        } else if self.clipboard == nil || self.clipboard!.count == 0 {
            self.notifications.executeError(
                text: "Clipboard is empty."
            )
        }
        // We don't clear clipboard. Mimics behavior of copy/paste on computers
        checkRep()
    }
    
    func moveHere(handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Move Here =====")
        
        if true {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
        
        checkRep()
    }
    
    func inspectClipboard(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Inspect Clipboard =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        print("Clipboard Text: \(self.clipboardText ?? "nil")")
        
        guard let entry = self.entryManager.currentEntry else {
            print("\t[Error] There was a problem executing command. Entry not detected.")
            return
        }
        
        if let clipboardSelection = self.clipboard, clipboardSelection.count > 0 {
            if voiceCommand {
                // Play Sound
                soundEngine.voiceCommandAccept()
            }

            let executePlay = {
                self.speechPlayer.play(segments: clipboardSelection)
            }
            
            if self.entryManager.isWalkingEntry || self.entryManager.isRunningEntry {
                entry.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                    if self.speechPlayer.isPlayingEntry {
                        self.speechPlayer.stop(withFeedback: false) {
                            executePlay()
                        }
                    } else {
                        executePlay()
                    }
                }
            } else if self.speechPlayer.isPlayingEntry {
                self.speechPlayer.stop(withFeedback: false) {
                    executePlay()
                }
            } else {
                executePlay()
            }
        } else {
            // havent recorded anything
            self.notifications.executeError(
                text:  "Clipboard is empty.",
                handler: handler
            )
            return
        }
        
        checkRep()
    }
        
    //    func loop() {
    //
    //    }
    
    // MARK: - Setters
    
    // Used when a user selects text from screen
    func setSelection(textRange: UITextRange) {
        guard let entry = self.entryManager.currentEntry, let textView = self.textView else { return }
        print("===== Selection Cursor: Set Selection (using TextRange) =====")
        
        var entrySegments: [EntrySegment]
        var oldAnchorIndex = Int(Utils.UNKNOWN)
        if let anchorCaret = self.anchorCaret {
            // insert buffer at the correct place based on cursor position
            entrySegments = entry.entrySegments
            oldAnchorIndex = anchorCaret.index
            if oldAnchorIndex != Int(Utils.UNKNOWN) {
                entrySegments.insert(contentsOf: entry.entryBuffer, at: oldAnchorIndex)
            } else {
                entrySegments += entry.entryBuffer
            }
        } else {
            // insert buffer at the end of segments
            entrySegments = entry.entrySegments + entry.entryBuffer
        }
        
        let selectionIndices = Utils.getIndicesInTextRange(
            textRange: textRange,
            textView: textView,
            entry: entry,
            segments: entrySegments
        )
        
        if selectionIndices.count > 0 {
            // Setting carets...
            
            // Update anchor
            let anchorIndex = selectionIndices.first!
            var anchorTrackType: EntryTrackType?
            var newAnchorIndex: Int?
            if let cachedAnchorCaret = self.cachedAnchorCaret {
                // Cached Anchor Caret exists. Seek for track type and index by dividing segments array into three sections
                if anchorIndex < cachedAnchorCaret.index {
                    // Index is before location where buffer was inserted...
                    anchorTrackType = .committed
                    newAnchorIndex = anchorIndex
                } else if anchorIndex >= cachedAnchorCaret.index && anchorIndex < cachedAnchorCaret.index + entry.entryBuffer.count
                {
                    // Index is in buffer...
                    anchorTrackType = .buffer
                    newAnchorIndex = anchorIndex - cachedAnchorCaret.index
                } else if anchorIndex >= cachedAnchorCaret.index + entry.entryBuffer.count {
                    // Index is after buffer...
                    anchorTrackType = .committed
                    newAnchorIndex = anchorIndex - entry.entryBuffer.count
                }
            } else {
                // Cached Anchor Caret doesn't exist. Seek for track type and index by dividing segments array into two sections...
                if anchorIndex >= entry.entrySegments.count {
                    // Index is in buffer...
                    anchorTrackType = .buffer
                    newAnchorIndex = anchorIndex - entry.entrySegments.count
                } else {
                    // Index is committed segment (before buffer)...
                    anchorTrackType = .committed
                    newAnchorIndex = anchorIndex
                }
            }
            
            if let anchorTrackType = anchorTrackType, let newAnchorIndex = newAnchorIndex {
                // we know this is an active word because Utils.getIndicesInTextRange only returns active words
                self.setAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: anchorTrackType))
            }
            
            // Update focus
            let focusIndex = selectionIndices.last!
            var focusTrackType: EntryTrackType?
            var newFocusIndex: Int?
            if let cachedAnchorCaret = self.cachedAnchorCaret {
                // Cached Anchor Caret exists. Seek for track type and index by dividing segments array into three sections
                if focusIndex < cachedAnchorCaret.index {
                    // Index is before location where buffer was inserted...
                    focusTrackType = .committed
                    newFocusIndex = focusIndex
                } else if focusIndex >= cachedAnchorCaret.index && focusIndex < cachedAnchorCaret.index + entry.entryBuffer.count
                {
                    // Index is in buffer...
                    focusTrackType = .buffer
                    newFocusIndex = focusIndex - cachedAnchorCaret.index
                } else if focusIndex >= cachedAnchorCaret.index + entry.entryBuffer.count {
                    // Index is after buffer...
                    focusTrackType = .committed
                    newFocusIndex = focusIndex - entry.entryBuffer.count
                }
            } else {
                // Cached Anchor Caret doesn't exist. Seek for track type and index by dividing segments array into two sections...
                if focusIndex >= entry.entrySegments.count {
                    // Index is in buffer...
                    focusTrackType = .buffer
                    newFocusIndex = focusIndex - entry.entrySegments.count
                } else {
                    // Index is committed segment (before buffer)...
                    focusTrackType = .committed
                    newFocusIndex = focusIndex
                }
            }
            
            if let focusTrackType = focusTrackType, let newFocusIndex = newFocusIndex {
                // we know this is an active word because Utils.getIndicesInTextRange only returns active words
                self.setFocusCaret(caret: Caret(index: newFocusIndex, trackType: focusTrackType))
            }
        } else {
            print("===== [Error] There was a problem finding selection entry segments =====")
        }
        
        if let caretViewRect = self.caretViewPositionRequiresUpdate(
                textPosition: textRange.end,
                includeXPosBuffer: false
            )
        {
            self.moveCaretView(to: caretViewRect)
        }
        
        checkRep()
    }
    
    func setSelection(anchorCaret: Caret, focusCaret: Caret) {
        print("===== Selection Cursor: Set Selection (using Anchor and Focus) =====")
        // Set anchor and focus
        self.setAnchorCaret(caret: anchorCaret)
        self.setFocusCaret(caret: focusCaret)
        
        if let selectionTextRange = self.selectionTextRange,
           let textView = self.textView,
           let textPosition = selectionTextRange.toTextRange(textInput: textView)?.end,
           let caretViewRect = self.caretViewPositionRequiresUpdate(
            textPosition: textPosition,
            includeXPosBuffer: false
           )
        {
            self.moveCaretView(to: caretViewRect)
        } else {
            print("\tNo need to update caret position...")
        }

        checkRep()
    }
    
    func clearSelection(withFeedback: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Clear Selection =====")
        if let textView = self.textView {
            if self.isLoopingSelection {
                print("\tisLoopingSelection activate. Turning off...")
                self.stopPlayingSelection()
            }
            
            if !self.isAtEndOfTextView {
                print("\tCache anchor if not at end of text view")
                // We cache the anchor if we're mid-entry so that new content is added from given location
                self.setCachedAnchorCaret(caret: self.anchorCaret)
            }
            
            print("\tRemove selection in view.")
            textView.selectedTextRange = nil
            print("\tClear selection in model.")
            if self.isAtEndOfTextView {
                self.setAnchorCaret()
            }
            self.setFocusCaret()
            handler?()
            
            if withFeedback {
                self.notifications.executeFeedback(
                    visualMessage: "Selection Removed!",
                    audioMessage: "selection removed",
                    withHaptics: true
                )
            }
        }
        
        checkRep()
    }
    
    func setTextView(textView: UITextView? = nil) {
        print("===== Selection Cursor: Set Text View =====")
        // store text view
        if let textView = textView {
            print("\tMethod passed text view argument...")

            // remove any previous textview
            if let oldTextView = self.textView {
                print("\tOld Text View detected. Removing observer from old text view...")
                oldTextView.removeObserver(self, forKeyPath: "selectedTextRange")
                oldTextView.delegate = nil
            }
            
            // Add new one
            print("\tSet new text view.")
            self.textView = textView
            
            // Add Selection Observer
            print("\tAdd observer to new text view")
            self.textView!.addObserver(
                self,
                forKeyPath: "selectedTextRange",
                options: [.old, .new],
                context: nil
            )
            self.textView!.addObserver(
                self,
                forKeyPath: "contentSize",
                options: [.old, .new],
                context: nil
            )
            
            // Assign as text change delegate
            textView.delegate = self
        } else {
            print("\tMethod not passed text view argument...")

            // remove any previous textview
            if let oldTextView = self.textView {
                print("\tOld Text View detected. Removing observer from old text view...")
                oldTextView.removeObserver(self, forKeyPath: "selectedTextRange")
                oldTextView.removeObserver(self, forKeyPath: "contentSize")
                oldTextView.delegate = nil
            }
            
            // clear text view
            print("\tReset text view property.")
            self.textView = nil
        }
        
        checkRep()
    }
    
    func setCursorView(cursorView: UIView? = nil) {
        print("===== Selection Cursor: Set Cursor View =====")
        // store cursor view
        if let cursorView = cursorView {
            // Add new one
            print("\tSet cursor view.")
            self.cursorView = cursorView
        } else {
            // clear text view
            print("\tClear cursor view.")
            self.cursorView = nil
        }
        
        checkRep()
    }
    
    func setAnchorCaret(caret: Caret? = nil, broadcastChange: Bool = true) {
        print("===== Selection Cursor: Set Anchor Caret =====")
        print("\tnew: '\(caret != nil ? self.getSegment(caret: caret!)?.getText() ?? "nil" : "nil")'")
        print("\told: '\(self.anchorCaret != nil ? self.getSegment(caret: self.anchorCaret!)?.getText() ?? "nil" : "nil")'")
        if let caret = caret,
           let segment = self.getSegment(caret: caret),
           caret != self.anchorCaret
        {
            print("\tNew anchor: \(segment.getText())")
            if broadcastChange {
                self.willChangeValue(forKey: "anchorCaret")
                self.anchorCaret = caret.duplicate()
                self.didChangeValue(forKey: "anchorCaret")
            } else {
                self.anchorCaret = caret.duplicate()
            }
        } else if let _ = self.anchorCaret, caret == nil {
            print("\tClear anchor.")
            if broadcastChange {
                self.willChangeValue(forKey: "anchorCaret")
                self.anchorCaret = nil
                self.didChangeValue(forKey: "anchorCaret")
            } else {
                self.anchorCaret = nil
            }
        } else if let caret = caret,
                  let segment = self.getSegment(caret: caret),
                  let anchor = self.anchor,
                  segment == anchor
        {
            print("\tAnchor argument is the same as current anchor: \(anchor.getText())")
        } else if self.anchorCaret == nil && caret == nil {
            print("\tAnchor argument is empty and current anchor is already empty.")
        } else {
            print("\tUnhandled anchor argument.")
        }
        
        checkRep()
    }
    
    func setFocusCaret(caret: Caret? = nil, broadcastChange: Bool = true) {
        print("===== Selection Cursor: Set Focus Caret =====")
        print("\tnew: '\(caret != nil ? self.getSegment(caret: caret!)?.getText() ?? "nil" : "nil")'")
        print("\told: '\(self.focusCaret != nil ? self.getSegment(caret: self.focusCaret!)?.getText() ?? "nil" : "nil")'")
        if let caret = caret,
           let segment = self.getSegment(caret: caret),
           caret != self.focusCaret {
            print("\tNew focus: \(segment.getText())")
            if broadcastChange {
                self.willChangeValue(forKey: "focusCaret")
                self.focusCaret = caret.duplicate()
                self.didChangeValue(forKey: "focusCaret")
            } else {
                self.focusCaret = caret.duplicate()
            }
        } else if let _ = self.focusCaret, caret == nil {
            print("\tClear focus.")
            if broadcastChange {
                self.willChangeValue(forKey: "focusCaret")
                self.focusCaret = nil
                self.didChangeValue(forKey: "focusCaret")
            } else {
                self.focusCaret = nil
            }
        } else if let caret = caret,
                  let segment = self.getSegment(caret: caret),
                  let focus = self.focus,
                  segment == focus
        {
            print("\tFocus argument is the same as current focus: \(focus.getText())")
            
        } else if self.focusCaret == nil && caret == nil {
            print("\tFocus argument is empty and current focus is already empty.")
        } else {
            print("\tUnhandled focus argument.")
        }
        
        checkRep()
    }
    
    func setCachedAnchorCaret(caret: Caret? = nil) {
        print("===== Selection Cursor: Set Cached Anchor =====")
        if let caret = caret {
            print("\tSet cached anchor: '\(self.getSegment(caret: caret)?.getText() ?? "nil")'")
            self.cachedAnchorCaret = caret.duplicate()
        } else {
            print("\tClear cached anchor.")
            self.cachedAnchorCaret = nil
        }
        
        checkRep()
    }
    
    func setIsPromptingForUpdateAcceptance(to value: Bool) {
        print("===== Selection Cursor: Set Is Prompting For Update Acceptance =====")
        self.isPromptingForUpdateAcceptance = value
    }
    
    func reset() {
        print("===== Selection Cursor: Reset =====")
        self.setAnchorCaret()
        self.setFocusCaret()
        self.setCachedAnchorCaret()
        self.setTextView()
        self.setCursorView()
        self.clipboard = nil
        self.isUpdatingSelection = false
        self.isPromptingForUpdateAcceptance = false
        self.updateSegments = nil
        self.isLoopingSelection = false
        
        // Notify Observers of Clipboard Change
        NotificationCenter.default.post(
            name: SelectionCursor.onClipboardChange,
            object: nil,
            userInfo: [:]
        )
        checkRep()
    }
    
    // MARK: - Getters
    
    func getNeighborhood() -> [EntrySegment] {
        print("===== Selection Cursor: Get Neightborhood =====")
        var neighborhood = [EntrySegment]()
        var startTime: CMTime?
        var endTime: CMTime?
        if let focus = self.focus,
           let anchor = self.anchor,
           self.direction == .backwards {
            startTime = focus.getSentence().timeRange.start
            endTime = anchor.getSentence().timeRange.end
        } else if let focus = self.focus,
                  let anchor = self.anchor
        {
            startTime = anchor.getSentence().timeRange.start
            endTime = focus.getSentence().timeRange.end
        }
        
        guard let entry = self.entryManager.currentEntry,
            startTime != nil &&
            endTime != nil,
            entry.entryBuffer.count == 0 else { return neighborhood }
        
        for segment in entry.entrySegments {
            if segment.timeMapping.target.start <= startTime! {
                // add to array if before passage to be removed
                neighborhood.append(segment)
            } else if segment.timeMapping.target.end >= endTime! {
                // add to array if after passage to be removed
                neighborhood.append(segment)
            }
        }
        
        return neighborhood
    }
    
    // MARK: - UI Methods
    
    func moveCaretView(to frame: CGRect) {
        UIView.animate(
            withDuration: Utils.CURSOR_TRANSITION_DURATION,
            delay: 0,
            options: [.curveEaseIn],
            animations: {
                self.cursorView!.frame = frame
            }
        )
    }
    
    func scrollToBottom() {
        print("===== Selection Cursor: Scroll To Bottom =====")
        let contentOffset = CGPoint(x: 0, y: self.textView!.contentSize.height - self.textView!.frame.height)
        self.textView!.setContentOffset(contentOffset, animated: true)
        self.handleScroll(delay: 0.5)
    }
    
    func handleScroll(delay: TimeInterval) {
        print("===== Selection Cursor: Handle Scroll =====")
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { timer in
            if let selectionTextRange = self.selectionTextRange,
               let textView = self.textView,
               let textPosition = selectionTextRange.toTextRange(textInput: textView)?.end,
               let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: textPosition)
            {
                self.moveCaretView(to: caretViewRect)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    func getLastUsedTrack() -> EntryTrackType? {
        guard let entry = self.entryManager.currentEntry else { return nil }

        var trackType: EntryTrackType = .committed
        if entry.entryBuffer.count > 0 {
            trackType = .buffer
        }
        
        return trackType
    }
    
    func getSegment(caret: Caret) -> EntrySegment? {
        guard let entry = self.entryManager.currentEntry,
            caret.index >= 0 &&
            (
                (
                    caret.trackType == .buffer &&
                    caret.index < entry.entryBuffer.count
                ) ||
                (
                    caret.trackType == .committed &&
                    caret.index < entry.entrySegments.count
                )
            ) else { return nil }
        
        if caret.trackType == .buffer {
            return entry.entryBuffer[caret.index]
        } else {
            return entry.entrySegments[caret.index]
        }
    }
    
    func executeSelectionUpdates(type: SelectionChangeType) {
        print("===== Selection Cursor: Execute Selection Updates =====")
        if type == .view {
            print("\tProcessing changes to screen via touch...")
            // changes to screen via touch
            if let selectionTextRange = self.textView?.selectedTextRange,
               let selectedText = self.textView?.text(in: selectionTextRange),
               selectedText.count > 0
            {
                print("\tScreen has selected text range.")
                // set selection in model
                print("\tSyncing up selection in model with selection on screen: ", selectionTextRange)
                self.setSelection(textRange: selectionTextRange)
                
                // loop selection audio
                // turn on processing sound
                if AVAudioSession.isHeadphonesConnected &&
                    !self.entryManager.isRunningEntry &&
                    !self.entryManager.isWalkingEntry &&
                    !self.speechPlayer.isPlayingEntry &&
                    !self.isUpdatingSelection
                {
                    print("\t[Headphones connected] Play Selection Audio.")
                    self.playSelection(loop: true)
                    print("\t[Headphones connected] Play Processing Sound Effect.")
                    
                    soundEngine.startProcessing()
                }
            } else if self.hasSelection {
                // Remove selection if it exists
                self.clearSelection()
            }
        } else {
            print("\tProcessing changes to model via voice or internal system...")
            // changes to model via voice
            if let _ = self.focusCaret,
               let _ = self.anchorCaret,
               let selectedRange = self.selectionTextRange
            {
                print("\tModel has selected text range.")
                // set selection on screen
                print("\tSyncing up selection on screen with selection in model: ", selectedRange)
                self.manualSelection(range: selectedRange)
                
                // begin looping selection audio
                // turn on processing sound
                if AVAudioSession.isHeadphonesConnected &&
                    !self.entryManager.isRunningEntry &&
                    !self.entryManager.isWalkingEntry &&
                    !self.speechPlayer.isPlayingEntry &&
                    !self.isUpdatingSelection
                {
                    print("\t[Headphones connected] Play Selection Audio.")
                    self.playSelection(loop: true)
                    print("\t[Headphones connected] Play Processing Sound Effect.")
                    
                    soundEngine.startProcessing()
                }
            }
        }
        
        checkRep()
    }
    
    func caretViewPositionRequiresUpdate(textPosition: UITextPosition, includeXPosBuffer: Bool = true) -> CGRect? {
        guard let _ = self.cursorView, let _ = self.textView else { return nil }
        
        let caretRect = self.textView!.caretRect(for: textPosition)
        let windowRect = self.textView!.convert(caretRect, to: nil)
        
        // compute x and y positions
        var xPos = windowRect.minX
        if includeXPosBuffer {
            xPos += Utils.CURSOR_X_POS_BUFFER
        }
        let yPos = windowRect.minY + ((self.textView!.font!.lineHeight - self.textView!.font!.pointSize) / 2)
        let width = Utils.CURSOR_WIDTH
        
//        if self.textView!.frame.height > self.textView!.contentSize.height {
//            yPos -= (self.textView!.contentOffset.y - Utils.TEXT_VIEW_PADDING_BOTTOM)
//        }

        // Create new cursor frame
        let frame: CGRect = CGRect(
            x: xPos,
            y: yPos,
            width: CGFloat(width),
            height: CGFloat(self.textView!.font!.lineHeight)
        )
        
        if frame != self.cursorView?.frame {
            return frame
        }
        
        return nil
    }
    
    // Reference: https://stackoverflow.com/questions/1708608/uitextview-selectedrange-not-displaying-when-set-programmatically
    func manualSelection(range: NSRange) {
        print("===== Selection Cursor: Manual Selection =====")
        self.manualSelection = true
        if let textView = self.textView {
            textView.select(self)
            textView.selectedRange = range
        }
    }
    
    func setOverrideSelectionUpdates(to value: Bool) {
        print("===== Selection Cursor: Set Override Selection Updates =====")
        self.overrideSelectionUpdates = value
    }

    // MARK: - Key-Value Observer
        
    // Reference: https://stackoverflow.com/questions/8579400/whats-the-best-way-to-get-uitextfield-selection-changed-notifications
    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        print("===== Selection Cursor: Observe Value =====")
        if keyPath == "contentSize" {
//            print("\tKeyPath: contentSize")
            if let newContentSize = change?[.newKey] as? CGSize,
               let oldContentSize = change?[.oldKey] as? CGSize,
               newContentSize.height > self.textView!.frame.height &&
                self.isAtEndOfTextView
            {
                print("\tKeyPath: contentSize")
                print("\tNew Observation Value (contentSize):\n\t\tnew: '\(newContentSize)'\n\t\told: '\(oldContentSize)'")
                self.scrollToBottom()
            } else {
//                print("\tUnhandled Content Size Change...")
            }
        } else if keyPath == "selectedTextRange" {
            print("\tKeyPath: selectionTextRange")
            if let newSelectionRange = change?[.newKey] as? UITextRange,
               !self.manualSelection &&
                !self.overrideSelectionUpdates // prevents selection updates from happening when user is adjusting selection
            {
                print("\tNew Observation Value (selectionTextRange): ", newSelectionRange)
                self.setOverrideSelectionUpdates(to: true)
                self.executeSelectionUpdates(type: .view)
            } else if self.manualSelection {
                print("Turn off manual selection flag...")
                self.manualSelection = false
            } else {
                print("\tNo selection range. Clear selectionTextRange in model...")
            }
        } else if keyPath == "anchorCaret" {
            print("\tKeyPath: anchorCaret")
            if let newAnchorCaret = change?[.newKey] as? Caret,
               let oldAnchorCaret = change?[.oldKey] as? Caret
            {
                print("\tNew Observation Value (Anchor Caret):\n\t\tnew: '\(self.getSegment(caret: newAnchorCaret)?.getText() ?? "nil")'\n\t\told: '\(self.getSegment(caret: oldAnchorCaret)?.getText() ?? "nil")'")
                self.executeSelectionUpdates(type: .model)
            } else if let newAnchorCaret = change?[.newKey] as? Caret {
                print("\tNew Observation Value (Anchor Caret):\n\t\tnew: '\(self.getSegment(caret: newAnchorCaret)?.getText() ?? "nil")'\n\t\told: nil")
                self.executeSelectionUpdates(type: .model)
            } else {
                print("\tUnhandled Anchor Caret: ", self.anchorCaret != nil ? self.getSegment(caret: self.anchorCaret!)?.getText() ?? "nil" : "nil")
            }
        } else if keyPath == "focusCaret" {
            print("\tKeyPath: focusCaret")
            if let newFocusCaret = change?[.newKey] as? Caret,
               let oldFocusCaret = change?[.oldKey] as? Caret
            {
                print("New Observation Value (Focus Caret):\n\t\tnew: '\(self.getSegment(caret: newFocusCaret)?.getText() ?? "nil")'\n\t\told: '\(self.getSegment(caret: oldFocusCaret)?.getText() ?? "nil")'")
                self.executeSelectionUpdates(type: .model)
            } else if let newFocusCaret = change?[.newKey] as? Caret {
                print("\tNew Observation Value (Focus Caret):\n\t\tnew: '\(self.getSegment(caret: newFocusCaret)?.getText() ?? "nil")'\n\t\told: nil")
                self.executeSelectionUpdates(type: .model)
            } else {
                print("\tUnhandled Focus Caret: ", self.focusCaret != nil ? self.getSegment(caret: self.focusCaret!)?.getText() ?? "nil" : "nil")
            }
        }
    }
    
    public override class func automaticallyNotifiesObservers(forKey key: String) -> Bool {
        if key == "anchorCaret" {
            return false
        } else if key == "focusCaret" {
            return false
        } else {
            return super.automaticallyNotifiesObservers(forKey: key)
        }
    }
    
    // MARK: - Delegates
    
    // Reference: https://stackoverflow.com/questions/25064465/uitextview-data-change-swift
    // Reference: https://stackoverflow.com/questions/43166781/cursor-position-in-relation-to-self-view
    // Will not be called by programmatic changes: https://stackoverflow.com/questions/16115344/textviewdidchange-is-not-call-when-change-uitextview-inputview
    public func textViewDidChange(_ textView: UITextView) {
        print("===== SelectionCursor: textViewDidChange =====")
        guard let entry = self.entryManager.currentEntry else { return }
        let (secondLastSegmentTrackType, secondLastSegmentIndex) = Utils.getEntryNthLastSegmentIndex(
            segments: entry.entrySegments,
            bufferSegments: entry.entryBuffer,
            selectionCursor: self,
            n: 1
        )
        let (lastSegmentTrackType, lastSegmentIndex) = Utils.getEntryNthLastSegmentIndex(
            segments: entry.entrySegments,
            bufferSegments: entry.entryBuffer,
            selectionCursor: self,
            n: 0
        )
        let (lastBufferSegmentTrackType, lastBufferSegmentIndex) = Utils.getEntryNthLastSegmentIndex(
            segments: entry.entrySegments,
            bufferSegments: entry.entryBuffer,
            fromBuffer: true,
            selectionCursor: self,
            n: 0
        )

        if let cachedAnchorCaret = self.cachedAnchorCaret,
           let cachedAnchor = self.getSegment(caret: cachedAnchorCaret),
           let caretIndex = lastBufferSegmentIndex,
           let caretTrackType = lastBufferSegmentTrackType,
           cachedAnchor.isActive() &&
            entry.entryBuffer.count > 0 &&
            !self.isUpdatingSelection &&
            !self.hasSelection
        {
            // Moves the cursor to the last segment in the buffer if we have a cached anchor and non-empty buffer
            print("\tMoves the cursor to the last segment in the buffer if we have a cached anchor and non-empty buffer")
            self.moveCursor(caret: Caret(index: caretIndex, trackType: caretTrackType))
        } else if let cachedAnchorCaret = self.cachedAnchorCaret,
            let cachedAnchor = self.getSegment(caret: cachedAnchorCaret),
            cachedAnchor.isActive() &&
            entry.entryBuffer.count == 0  &&
            !self.isUpdatingSelection &&
            !self.hasSelection
        {
            // Moves the cursor to the cached anchor if it exists and if the buffer is empty
            // This occurs after a buffer is committed while we have a cached anchor
            // The cached anchor is updated to be the last segment of the recently committed buffer
            print("\tMoves the cursor to the cached anchor if it exists and if the buffer is empty.")
            print("\tThis occurs after a buffer is committed while we have a cached anchor.")
            print("\tThe cached anchor is updated to be the last segment of the recently committed buffer.")
            self.moveCursor(caret: cachedAnchorCaret.duplicate())
        } else if let lastSegmentIndex = lastSegmentIndex,
            let lastSegmentTrackType = lastSegmentTrackType,
            entry.entryBuffer.count > 0 &&
            !self.hasSelection &&
            (
                (
                    secondLastSegmentIndex != nil &&
                    secondLastSegmentTrackType != nil &&
                    self.anchorCaret == Caret(index: secondLastSegmentIndex!, trackType: secondLastSegmentTrackType!)
                ) ||
                (
                    self.anchorCaret != Caret(index: lastSegmentIndex, trackType: lastSegmentTrackType)
                ) ||
                (
                    self.anchorCaret == nil
                )
            )
        {
            // Moves cursor to the end of the entry if there is no cached anchor and one of the following cases:
            // 1) The second last segment in the non-empty buffer is the current anchor, but we have a new buffer segment
            // 2) The current anchor is the same as the last segment in the non-empty buffer
            // 3) We have no anchor
            print("\tMoves cursor to the end of the entry if there is no cached anchor and one of the following cases:")
            print("\t1) The second last segment in the non-empty buffer is the current anchor, but we have a new buffer segment")
            print("\t2) The current anchor is the same as the last segment in the non-empty buffer")
            print("\t3) We have no anchor")
            self.moveCursor(caret: Caret(index: lastSegmentIndex, trackType: lastSegmentTrackType))
        } else if let selectionTextRange = self.selectionTextRange,
            let textView = self.textView,
            let textPosition = selectionTextRange.toTextRange(textInput: textView)?.end,
            let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: textPosition)
        {
            self.moveCaretView(to: caretViewRect)
        } else if let textView = self.textView,
            let cursorView = self.cursorView,
            textView.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).length == 0
        {
            // reset cursor position
            Utils.initializeCursor(
                textView: textView,
                cursorView: cursorView,
                font: self.state.font
            )
        } else {
            print("===== Selection Cursor: textViewDidChange - Unhandled Anchor: ", self.anchorCaret != nil ? self.getSegment(caret: self.anchorCaret!)?.getText() ?? "nil" : "nil", " =====")
        }
    }
}

// MARK: - Scroll View Delegate Extension
extension SelectionCursor: UIScrollViewDelegate {
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        print("===== Scroll View Did End Dragging =====")
        self.handleScroll(delay: Utils.TEXT_VIEW_SCROLL_TRANSITION_DURATION)
    }
}
