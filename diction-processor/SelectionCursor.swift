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
    weak var noteManager: NoteManager! // we add weak because note manager has a reference to selection curos
    
    // MARK: - Selection Cursor Properties
    
    @objc dynamic var focusCaret: Caret? = nil
    var focus: NoteSegment? {
        if let focusCaret = self.focusCaret {
            return self.getSegment(caret: focusCaret)
        }
        
        return nil
    }
    @objc dynamic var anchorCaret: Caret? = nil
    var anchor: NoteSegment? {
        if let anchorCaret = self.anchorCaret {
            return self.getSegment(caret: anchorCaret)
        }
        
        return nil
    }
    var cachedAnchorCaret: Caret? = nil
    var cachedAnchor: NoteSegment? {
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
                end: focus.timeMapping.target.start
            )
        } else if
               let anchor = self.anchor,
               let focus = self.focus,
            self.direction == .backwards
        {
            return CMTimeRangeFromTimeToTime(
                start: focus.timeMapping.target.start,
                end: anchor.timeMapping.target.start
            )
        }
        
        // Have not implemented directionless
        
        return nil
    }
    var selectionTextRange: NSRange? {
        if let note = self.noteManager.currentNote,
            let anchor = self.anchor,
            let focus = self.focus,
            let anchorRange = note.getSegmentTextRange(of: anchor),
            let focusRange = note.getSegmentTextRange(of: focus) {
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
        } else if let note = self.noteManager.currentNote,
                  let anchor = self.anchor,
                  !anchor.isVoiceCommandWord() && !anchor.isDeleted(),
                  let anchorRange = note.getSegmentTextRange(of: anchor) {
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
        if let note = self.noteManager.currentNote,
           let anchor = self.anchor,
           let focus = self.focus,
            self.direction == .backwards
        {
            return note.getText(from: focus.timeMapping.target.start, until: anchor.timeMapping.target.end)
        } else if let note = self.noteManager.currentNote,
            let anchor = self.anchor,
            let focus = self.focus,
            self.direction == .forwards
        {
            return note.getText(from: anchor.timeMapping.target.start, until: focus.timeMapping.target.end)
        }
        
        return nil
    }
    var selectionSegments: [NoteSegment]? {
        guard let note = self.noteManager.currentNote, note.noteBuffer.count == 0 else { return nil }

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
        
        return Array(note.noteSegments[startIndex!...endIndex!])
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
    private(set) var clipboard: [NoteSegment]? = nil
    var clipboardText: String? {
        if let note = self.noteManager.currentNote, let clipboard = self.clipboard {
            return note.getText(
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
    var selectionTransformations: [NoteTransformation]? {
        guard let note = self.noteManager.currentNote,
            let anchor = self.anchor else { return nil }
        var transformations = [NoteTransformation]()
        let selectionLowerIndex = anchor.getIndex()
        for transformation in note.transformations {
            if transformation.noteRange.contains(selectionLowerIndex) {
                transformations.append(transformation)
            }
        }
        return transformations
    }
    var isAtEndOfTextView: Bool {
        guard let note = self.noteManager.currentNote else { return false }
        let lastSegment = Utils.getNoteNthLastSegment(
            segments: note.noteSegments,
            bufferSegments: note.noteBuffer,
            selectionCursor: self,
            n: 0
        )
        if let _ = self.anchor,
           let focus = self.focus,
           let lastSegment = lastSegment {
            // print("isAtEndOfTextView 1: ", focus == lastSegment, focus, lastSegment, note!.noteSegments, note!.noteBuffer)
            // we have a selection
            return focus == lastSegment
        } else if let anchor = self.anchor,
                  let lastSegment = lastSegment {
            // we don't have a selection
            // we have a cursor though
            // print("isAtEndOfTextView 2: ", anchor == lastSegment, anchor, lastSegment, note!.noteSegments, note!.noteBuffer)
            return anchor == lastSegment
        } else if (note.noteSegments.count == 0 && note.noteBuffer.count == 0) || note.getText().count == 0 {
            // we have not captured and speech yet
            // print("isAtEndOfTextView 3: ", true, note.noteSegments, note.noteBuffer)
            return true
        }

        // print("isAtEndOfTextView 4: ", false, note!.noteSegments, note!.noteBuffer)
        return false
    }
    var isVisible: Bool {
        return self.cursorView != nil
    }
    private(set) var isUpdatingSelection = false
    private(set) var isPromptingForUpdateAcceptance = false
    var updateSegments: [NoteSegment]? = nil
    var isLoopingSelection = false
    private var manualSelection = false
    
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
        
        // Dont be visible without note
        result = result && ((self.isVisible && self.noteManager.currentNote != nil) || !self.isVisible)
        
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
        let command = notification.userInfo!["command"] as! String
        var handler: (() -> Void)?
        if notification.userInfo!["handler"] != nil {
            handler = notification.userInfo!["handler"] as? () -> Void
        }
        switch (command) {
        case "inspect clipboard":
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
            self.focusCaret = Caret(index: anchorCaret!.index, trackType: anchorCaret!.trackType)
            self.didChangeValue(forKey: "focusCaret")
            
        } else {
            self.willChangeValue(forKey: "anchorCaret")
            self.anchorCaret = Caret(index: focusCaret!.index, trackType: focusCaret!.trackType)
            self.didChangeValue(forKey: "anchorCaret")
        }
        
        checkRep()
    }

    // ballistic movement
    //
    // moves as a cursor
    func moveCursor(caret: Caret, cache: Bool = false) {
        guard let _ = self.noteManager.currentNote else { return }
        print("===== Selection Cursor: Move (using track and index) =====")
        let segment = self.getSegment(caret: caret)
        print("\tSegment: '\(segment?.getText() ?? "nil")'")
        
        if AVAudioSession.isHeadphonesConnected {
            if self.speechPlayer.isPlayingNote {
                print("\tNote is playing. Turning off...")
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
        self.setAnchorCaret(caret: Caret(index: caret.index, trackType: caret.trackType))
        self.setFocusCaret()
        
        // Used when we want to insert a buffer into the committed segments
        // allows us to determine segment of interest
        if cache && !self.isAtEndOfTextView {
            self.setCachedAnchorCaret(caret: Caret(index: caret.index, trackType: caret.trackType))
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
        guard let note = self.noteManager.currentNote else { return }
        print("=====  Selection Cursor: Move (using textPosition) =====")
        
        var noteSegments: [NoteSegment]
        var oldAnchorIndex = Int(Utils.UNKNOWN)
        if let anchorCaret = self.anchorCaret {
            // insert buffer at the correct place based on cursor position
            noteSegments = note.noteSegments
            oldAnchorIndex = anchorCaret.index
            if oldAnchorIndex != Int(Utils.UNKNOWN) {
                noteSegments.insert(contentsOf: note.noteBuffer, at: oldAnchorIndex)
            } else {
                noteSegments += note.noteBuffer
            }
        } else {
            // insert buffer at the end of segments
            noteSegments = note.noteSegments + note.noteBuffer
        }
        
        let (index, rightOffsetFromCaret) = Utils.getIndexAtTextPosition(
            textPosition: textPosition,
            textView: self.textView!,
            note: note,
            segments: noteSegments
        )
        
        if let index = index {
            print("\tSetting carets...")
            let anchor = noteSegments[index]
            let trackType: NoteTrackType = anchor.isCommitted() ? .buffer : .committed
            var newAnchorIndex: Int
            if trackType == .committed {
                // Get index relative to committed segments
                newAnchorIndex = anchor.getIndex()
            } else {
                // Get index relative to buffer segments
                // The old anchor index should be the start of the buffer
                //
                // If old anchor index is Utils.UNKNOWN then buffer is at end of note
                newAnchorIndex = oldAnchorIndex != Int(Utils.UNKNOWN) ? index - oldAnchorIndex : index - note.noteSegments.count
            }
            
            // we know this is an active word because Utils.getIndexAtTextPosition only returns active words
            self.setAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: trackType))
            self.setFocusCaret()
            
            // Used when we want to insert a buffer into the committed segments
            // allows us to determine segment of interest
            if cache && !self.isAtEndOfTextView {
                self.setCachedAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: trackType))
            } else if self.isAtEndOfTextView {
                self.setCachedAnchorCaret()
            }
        } else {
            print("===== [Error] There was a problem finding cursor note segment =====")
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
    
    func isSegmentInRange(segment: NoteSegment) -> Bool {
        guard let note = self.noteManager.currentNote, let selectionTextRange = self.selectionTextRange else { return false }

        let segmentRange = note.getSegmentTextRange(of: segment)
        
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
            
            // Stop Note
            self.speechPlayer.stop(withFeedback: false)
        }
        
        checkRep()
    }
    
    func playPassage(startTime: CMTime, endTime: CMTime, loop: Bool = false) {
        print("===== Selection Cursor: Play Passage =====")
        print("\tPlaying from: \(startTime.seconds) to \(endTime.seconds)")

        if let note = self.noteManager.currentNote {
            print("\tPreparing to play selection.")
            if loop {
                print("\tActivated looping selection.")
                self.isLoopingSelection = true
            } else {
                print("\tDeactivated looping selection.")
                self.stopPlayingSelection()
            }

            self.speechPlayer.play(
                note: note,
                from: startTime,
                to: endTime
            )
        } else if AVAudioSession.isHeadphonesConnected {
            print("\tNo selection start and end times found. Abort method.")

            if self.speechPlayer.isPlayingNote {
                print("\tNote is playing. Turning off...")
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
        guard let note = self.noteManager.currentNote,
              let focus = self.focus,
              let anchor = self.anchor,
              note.noteBuffer.count == 0 else { return }
        
        let numSegments = note.noteSegments.count
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
        guard let note = self.noteManager.currentNote,
              let focus = self.focus,
              let anchor = self.anchor,
              note.noteBuffer.count == 0 else { return }

        let numSegments = note.noteSegments.count
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
        guard let note = self.noteManager.currentNote, self.hasSelection else {
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
        for segment in note.noteSegments[selectionRange] {
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
            var lowerSegment = note.noteSegments[lowerSegmentIndex]
            var upperSegment = note.noteSegments[upperSegmentIndex]
            while (lowerSegment.isVoiceCommandWord() || lowerSegment.isSilence() || lowerSegment.isDeleted()) && lowerSegmentIndex < range.upperBound {
                // must not be a silence or voice command word
                lowerSegmentIndex += 1
                lowerSegment = note.noteSegments[lowerSegmentIndex]
            }
            while (upperSegment.isVoiceCommandWord() || upperSegment.isSilence() || lowerSegment.isDeleted()) && upperSegmentIndex > range.lowerBound {
                // must not be a silence or voice command word
                upperSegmentIndex -= 1
                upperSegment = note.noteSegments[upperSegmentIndex]
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
            let text = note.getText(
                from: lowerSegment.timeMapping.target.start,
                until: upperSegment.timeMapping.target.end,
                segments: note.noteSegments
            )
            print("\tCompute transformation text: ", text)
            
            // Compute text range
            let lowerRange = note.getSegmentTextRange(of: lowerSegment)
            let upperRange = note.getSegmentTextRange(of: upperSegment)
            let lowerLocation = lowerRange!.location
            let upperLocation = upperRange!.location
            let upperLength = upperRange!.length
            let textRange = NSRange(location: lowerLocation, length: (upperLocation - lowerLocation) + upperLength)
            
            // Store transformation
            print("\tStore transformation...")
            note.handleTransformation(
                type: .playbackRate,
                passageText: text,
                value: newRate,
                textRange: textRange,
                noteRange: range
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
    
    func deleteSelection(isCommit: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Delete Selection =====")
        // prevent illegal deletions
        guard let note = self.noteManager.currentNote, let selectionTimeRange = self.selectionTimeRange else {
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
            
            // cache anchor if not at end of note
            if let anchor = self.anchor,
               !self.isAtEndOfTextView
            {
                print("\tCursor not at end of text view; update cached anchor...")
                
                let newCachedAnchorIndex = Utils.getSegmentIndex(
                    segment: anchor,
                    segments: note.noteSegments,
                    type: .previous,
                    isWord: true,
                    isCommitted: true
                )
                
                if let newCachedAnchorIndex = newCachedAnchorIndex {
                    let cachedAnchor = self.getSegment(caret: Caret(index: newCachedAnchorIndex, trackType: .committed))
                    print("\tNew cached anchor found: \(cachedAnchor?.getText() ?? "nil")")
                    self.setCachedAnchorCaret(caret: Caret(index: newCachedAnchorIndex, trackType: .committed))
                } else {
                    print("\t[Error] New cached anchor not found...")
                    self.setCachedAnchorCaret()
                }
            } else {
                print("\tCursor at end of text view. Clear any cached anchor")
                self.setCachedAnchorCaret()
            }
            
            // remove passage
            print("\tRemove selection")
            note.removePassage(range: selectionTimeRange)
            
            // move cursor
            if let cachedAnchorCaret = self.cachedAnchorCaret {
                print("\tMove cursor to cached anchor")
                self.moveCursor(caret: cachedAnchorCaret)
            }
            
            if isCommit {
                // Present Feedback
                self.notifications.executeFeedback(
                    visualMessage: "Delete Commit",
                    audioMessage: "commit deleted",
                    withHaptics: true
                )
            } else {
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
        if self.noteManager.isWalkingNote || self.noteManager.isRunningNote {
            note.exitWalk(clearSelection: false, withFeedback: false) {
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
        guard let note = self.noteManager.currentNote else { return }
        
        // Stop playback
        if AVAudioSession.isHeadphonesConnected {
            if self.speechPlayer.isPlayingNote {
                print("\tNote is playing. Turning off...")
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
            
            // turn off prompting for selection acceptance flag
            self.isPromptingForUpdateAcceptance = false

            // play to hear difference
            self.checkRep()
        }
        
        // Pause walking / running
        if self.noteManager.isWalkingNote || self.noteManager.isRunningNote {
            note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                handleInitiateUpdateSelection()
            }
        } else {
            handleInitiateUpdateSelection()
        }
    }
    
    func handleUpdateSelection(segments: [NoteSegment]) {
        print("===== Selection Cursor: Handle Update Selection =====")
        guard let note = self.noteManager.currentNote, let selectionText = self.selectionText, segments.count > 0 else {
            print("\t[Error]: ", self.noteManager.currentNote != nil, self.selectionText != nil, segments.count > 0)
            return
        }
        
        // turn on prompting for selection acceptance flag
        self.isPromptingForUpdateAcceptance = true

        // duplicate note tracks
        print("\tDuplicating buffer segments...")
        var updateSegments = [NoteSegment]()
        for segment in segments {
            updateSegments.append(segment.duplicate())
        }
        
        // normalize segments
        print("\tNormalizing update segments...")
        let normalizedUpdateSegments = note.normalizeSegments(
            segments: segments,
            omitLeadingSilence: true,
            returnSegments: true
        )
        
        // Svae presumed update segments
        self.updateSegments = normalizedUpdateSegments
        
        // Compute update selectiont text
        let updateText = note.getText(segments: self.updateSegments)
        
        // Present Update Dialog
        let dialogActions = [
            DialogAction(
                title: "Accept",
                voiceCommand: "accept",
                feedbackVisualMessage: "Updated!",
                feedbackAudioMessage: "selection updated",
                style: .default,
                handler: { [weak self] action in
                    // Accept Update
                    print("\tAccepting Update Selection...")
                    self?.noteManager.acceptUpdateSelection()
                }
            ),
            DialogAction(
                title: "Redo",
                voiceCommand: "redo",
                feedbackVisualMessage: "Redo Update",
                feedbackAudioMessage: "redo update",
                style: .destructive,
                handler: { [weak self] action in
                    // Redo Update Selection
                    print("\tRedoing Update Selection...")
                    self?.noteManager.redoUpdateSelection()
                }
            ),
            DialogAction(
                title: "Cancel",
                voiceCommand: "cancel",
                feedbackVisualMessage: "Canceled!",
                feedbackAudioMessage: "Command canceled",
                style: .cancel,
                handler: { [weak self] action in
                    // Cancel Update Selection
                    print("\tCanceling Update Selection...")
                    self?.noteManager.cancelUpdateSelection()
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
        print("===== Selection Cursor Commit: Accept Update Selection =====")

        // prevent illegal updating
        guard let note = self.noteManager.currentNote, let selectionTimeRange = self.selectionTimeRange, let updateSegments = self.updateSegments else { return }
        
        var segments = [NoteSegment]()
        for segment in updateSegments {
            let duplicateSegment = segment.duplicate(withNewUID: true)
            segments.append(duplicateSegment)
        }
        
        // Update to new anchor
        let firstSegment = segments.first
        var anchorIndex: Int? = nil
        if let segment = firstSegment, !firstSegment!.isActive() {
            anchorIndex = Utils.getSegmentIndex(
                segment: segment,
                segments: segments,
                type: .next,
                isWord: true
            )
        }
        
        if let anchorIndex = anchorIndex {
            let index = self.anchorCaret != nil ? self.anchorCaret!.index + anchorIndex : note.noteSegments.count + anchorIndex
            self.setAnchorCaret(caret: Caret(index: index, trackType: .committed), broadcastChange: false)
        }
        

        // Update to new focus
        let lastSegment = segments.last
        var focusIndex: Int? = nil
        if let _ = lastSegment, !lastSegment!.isActive() {
            let (_, index) = Utils.getNoteNthLastSegmentIndex(
                segments: segments,
                selectionCursor: self,
                n: 0
            )
            focusIndex = index
        }
        
        if let focusIndex = focusIndex {
            let index = self.anchorCaret != nil ?
                self.anchorCaret!.index + focusIndex
                :
                note.noteSegments.count + focusIndex
            self.setFocusCaret(caret: Caret(index: index, trackType: .committed), broadcastChange: false)
        }
        
        // Update to new cached anchor
        if let _ = self.cachedAnchorCaret, let anchorIndex = anchorIndex {
            let index = self.anchorCaret != nil ?
                self.anchorCaret!.index + anchorIndex
                :
                note.noteSegments.count + anchorIndex
            self.setCachedAnchorCaret(caret: Caret(index: index, trackType: .committed))
        }

        // Update Selection
        note.updatePassage(
            segments: segments,
            range: selectionTimeRange
        )
        
        // Clear accumulated buffer
        note.clearBuffer()
        
        // turn off update selection flag
        self.isUpdatingSelection = false

        // clear update segments
        self.updateSegments = nil

        // turn off prompting for selection acceptance flag
        self.isPromptingForUpdateAcceptance = false
        
        // begin looping selection audio
        // turn on processing sound
        if AVAudioSession.isHeadphonesConnected &&
            !self.noteManager.isRunningNote &&
            !self.noteManager.isWalkingNote &&
            !self.speechPlayer.isPlayingNote &&
            !self.isUpdatingSelection
        {
            print("\t[Headphones connected] Play Selection Audio.")
            self.playSelection(loop: true)
            print("\t[Headphones connected] Play Processing Sound Effect.")
            
            soundEngine.startProcessing()
        }
        
        if self.noteManager.pausedWalkingNote {
            note.walk() {
                handler?()
            }
        } else if self.noteManager.pausedRunningNote {
            note.run() {
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
        guard let note = self.noteManager.currentNote else { return }
        
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
                !self.noteManager.isRunningNote &&
                !self.noteManager.isWalkingNote &&
                !self.speechPlayer.isPlayingNote &&
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
        
        if self.noteManager.pausedWalkingNote {
            note.walk() {
                handleCancelUpdate()
            }
        } else if self.noteManager.pausedRunningNote {
            note.run() {
                handleCancelUpdate()
            }
        } else {
            handleCancelUpdate()
        }
    }
    
    func copySelection() {
        print("===== Selection Cursor: Copy Selection =====")

        if let selectionSegments = self.selectionSegments {
            var duplicateSegments = [NoteSegment]()
            for segment in selectionSegments {
                duplicateSegments.append(segment.duplicate())
            }
            self.clipboard = duplicateSegments
        }
        
        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: "Copy Selection",
            audioMessage: "selection copied",
            withHaptics: true
        )
        
        // Notify Observers of Clipboard Change
        NotificationCenter.default.post(
            name: SelectionCursor.onClipboardChange,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func cutSelection() {
        print("===== Selection Cursor: Cut Selection =====")
        // copy selection
        self.copySelection()
        
        // delete selection
        self.deleteSelection()
        
        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: "Cut Selection",
            audioMessage: "selection cut",
            withHaptics: true
        )

        // play to hear difference
        checkRep()
    }

    func pasteClipboard() {
        print("===== Selection Cursor: Paste Clipboard =====")
        if let note = self.noteManager.currentNote,
           let anchor = self.anchor,
           let clipboard = self.clipboard,
           clipboard.count > 0 {
            
            var pastedSegments = [NoteSegment]()
            for segment in clipboard {
                let duplicateSegment = segment.duplicate(withNewUID: true)
                pastedSegments.append(duplicateSegment)
            }

            // Update to new anchor
            let lastSegment = pastedSegments.last
            var newIndex: Int?
            if let _ = lastSegment, !lastSegment!.isActive() {
                let (_, index) = Utils.getNoteNthLastSegmentIndex(
                    segments: pastedSegments,
                    selectionCursor: self,
                    n: 0
                )
                
                newIndex = index
            }
            
            guard let relativeIndex = newIndex, pastedSegments[relativeIndex].isCommitted() else {
                print("\t[Error] new anchor must be committed.")
                return
            }
            
            let index = anchorCaret!.index + relativeIndex
            
            self.setAnchorCaret(caret: Caret(index: index, trackType: .committed))
            
            // Update to new cached anchor
            if let _ = self.cachedAnchorCaret {
                self.setCachedAnchorCaret(caret: Caret(index: index, trackType: .committed))
            }
            
            // Insert selection into note
            note.insertPassage(
                segments: pastedSegments,
                at: anchor.timeMapping.target.end
            )
            
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Pasted!",
                audioMessage: "clipboard pasted",
                withHaptics: true
            )
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
        
        guard let note = self.noteManager.currentNote else {
            print("\t[Error] There was a problem executing command. Note not detected.")
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
            
            if self.noteManager.isWalkingNote || self.noteManager.isRunningNote {
                note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                    if self.speechPlayer.isPlayingNote {
                        self.speechPlayer.stop(withFeedback: false) {
                            executePlay()
                        }
                    } else {
                        executePlay()
                    }
                }
            } else if self.speechPlayer.isPlayingNote {
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
        guard let note = self.noteManager.currentNote, let textView = self.textView else { return }
        print("===== Selection Cursor: Set Selection (using TextRange) =====")
        
        var noteSegments: [NoteSegment]
        var oldAnchorIndex = Int(Utils.UNKNOWN)
        if let anchorCaret = self.anchorCaret {
            // insert buffer at the correct place based on cursor position
            noteSegments = note.noteSegments
            oldAnchorIndex = anchorCaret.index
            if oldAnchorIndex != Int(Utils.UNKNOWN) {
                noteSegments.insert(contentsOf: note.noteBuffer, at: oldAnchorIndex)
            } else {
                noteSegments += note.noteBuffer
            }
        } else {
            // insert buffer at the end of segments
            noteSegments = note.noteSegments + note.noteBuffer
        }
        
        let selectionIndices = Utils.getIndicesInTextRange(
            textRange: textRange,
            textView: textView,
            note: note,
            segments: noteSegments
        )
        
        if selectionIndices.count > 0 {
            // Update to new anchor
            let anchorIndex = selectionIndices.first!
            let anchor = noteSegments[anchorIndex]
            let anchorTrackType: NoteTrackType = anchor.isCommitted() ? .buffer : .committed
            var newAnchorIndex: Int
            if anchorTrackType == .committed {
                // Get index relative to committed segments
                newAnchorIndex = anchor.getIndex()
            } else {
                // Get index relative to buffer segments
                newAnchorIndex = oldAnchorIndex != Int(Utils.UNKNOWN) ?
                    anchorIndex - oldAnchorIndex
                    :
                    anchorIndex - note.noteSegments.count
            }
            
            // we know this is an active word because Utils.getIndicesInTextRange only returns active words
            self.setAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: anchorTrackType))

            // Update to new focus
            let focusIndex = selectionIndices.last!
            let focus = noteSegments[focusIndex]
            let focusTrackType: NoteTrackType = focus.isCommitted() ? .buffer : .committed
            let newFocusIndex = newAnchorIndex + (selectionIndices.count - 1)
            
            // we know this is an active word because Utils.getIndicesInTextRange only returns active words
            self.setFocusCaret(caret: Caret(index: newFocusIndex, trackType: focusTrackType))
        } else {
            print("===== [Error] There was a problem finding selection note segments =====")
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
                // We cache the anchor if we're mid-note so that new content is added from given location
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
        print("===== Selection Cursor: Set Anchor =====")
        print("\tnew: '\(caret != nil ? self.getSegment(caret: caret!)?.getText() ?? "nil" : "nil")'")
        print("\told: '\(self.anchorCaret != nil ? self.getSegment(caret: self.anchorCaret!)?.getText() ?? "nil" : "nil")'")
        if let caret = caret,
           let segment = self.getSegment(caret: caret),
           caret != self.anchorCaret
        {
            print("\tNew anchor: \(segment.getText())")
            if broadcastChange {
                self.willChangeValue(forKey: "anchorCaret")
                self.anchorCaret = Caret(index: caret.index, trackType: caret.trackType)
                self.didChangeValue(forKey: "anchorCaret")
            } else {
                self.anchorCaret = Caret(index: caret.index, trackType: caret.trackType)
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
        print("===== Selection Cursor: Set Focus =====")
        print("\tnew: '\(caret != nil ? self.getSegment(caret: caret!)?.getText() ?? "nil" : "nil")'")
        print("\told: '\(self.focusCaret != nil ? self.getSegment(caret: self.focusCaret!)?.getText() ?? "nil" : "nil")'")
        if let caret = caret,
           let segment = self.getSegment(caret: caret),
           caret != self.focusCaret {
            print("\tNew focus: \(segment.getText())")
            if broadcastChange {
                self.willChangeValue(forKey: "focusCaret")
                self.focusCaret = Caret(index: caret.index, trackType: caret.trackType)
                self.didChangeValue(forKey: "focusCaret")
            } else {
                self.focusCaret = Caret(index: caret.index, trackType: caret.trackType)
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
            self.cachedAnchorCaret = Caret(index: caret.index, trackType: caret.trackType)
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
    
    func getNeighborhood() -> [NoteSegment] {
        print("===== Selection Cursor: Get Neightborhood =====")
        var neighborhood = [NoteSegment]()
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
        
        guard let note = self.noteManager.currentNote,
            startTime != nil &&
            endTime != nil,
            note.noteBuffer.count == 0 else { return neighborhood }
        
        for segment in note.noteSegments {
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
    
    func getLastUsedTrack() -> NoteTrackType? {
        guard let note = self.noteManager.currentNote else { return nil }

        var trackType: NoteTrackType = .committed
        if note.noteBuffer.count > 0 {
            trackType = .buffer
        }
        
        return trackType
    }
    
    func getSegment(caret: Caret) -> NoteSegment? {
        guard let note = self.noteManager.currentNote,
            caret.index >= 0 &&
            (
                (
                    caret.trackType == .buffer &&
                    caret.index < note.noteBuffer.count
                ) ||
                (
                    caret.trackType == .committed &&
                    caret.index < note.noteSegments.count
                )
            ) else { return nil }
        
        if caret.trackType == .buffer {
            return note.noteBuffer[caret.index]
        } else {
            return note.noteSegments[caret.index]
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
                    !self.noteManager.isRunningNote &&
                    !self.noteManager.isWalkingNote &&
                    !self.speechPlayer.isPlayingNote &&
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
            if let _ = self.focusCaret, let _ = self.anchorCaret,
               let selectedRange = self.selectionTextRange
            {
                print("\tModel has selected text range.")
                // set selection on screen
                print("\tSyncing up selection on screen with selection in model: ", selectedRange)
                self.manualSelection(range: selectedRange)
                
                // begin looping selection audio
                // turn on processing sound
                if AVAudioSession.isHeadphonesConnected &&
                    !self.noteManager.isRunningNote &&
                    !self.noteManager.isWalkingNote &&
                    !self.speechPlayer.isPlayingNote &&
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
            print("\tKeyPath: contentSize")
            if let newContentSize = change?[.newKey] as? CGSize,
               let oldContentSize = change?[.oldKey] as? CGSize,
               newContentSize.height > self.textView!.frame.height &&
                self.isAtEndOfTextView
            {
                print("\tNew Observation Value (contentSize):\n\t\tnew: '\(newContentSize)'\n\t\told: '\(oldContentSize)'")
                self.scrollToBottom()
            } else {
                print("\tUnhandled Content Size Change...")
            }
        } else if keyPath == "selectedTextRange" {
            print("\tKeyPath: selectionTextRange")
            if let newSelectionRange = change?[.newKey] as? UITextRange, !self.manualSelection {
                print("\tNew Observation Value (selectionTextRange): ", newSelectionRange)
                self.executeSelectionUpdates(type: .view)
            } else if self.manualSelection {
                print("Turn off manual selection flag...")
                self.manualSelection = false
            } else {
                print("\tNo selection range. Clear selectionTextRange in model...")
            }
        } else if keyPath == "anchorCaret" {
            print("\tKeyPath: anchor")
            if let newAnchor = change?[.newKey] as? NoteSegment,
               let oldAnchor = change?[.oldKey] as? NoteSegment
            {
                print("\tNew Observation Value (Anchor):\n\t\tnew: '\(newAnchor.getText())'\n\t\told: '\(oldAnchor.getText())'")
                if self.speechRecognition.isListeningForSpeech {
                    self.executeSelectionUpdates(type: .model)
                }
            } else if let newAnchor = change?[.newKey] as? NoteSegment {
                print("\tNew Observation Value (Anchor):\n\t\tnew: '\(newAnchor.getText())'\n\t\told: nil")
                if self.speechRecognition.isListeningForSpeech {
                    self.executeSelectionUpdates(type: .model)
                }
            } else {
                print("\tUnhandled Anchor: ", self.anchorCaret != nil ? self.getSegment(caret: self.anchorCaret!)?.getText() ?? "nil" : "nil")
            }
        } else if keyPath == "focusCaret" {
            print("\tKeyPath: focus")
            if let newFocus = change?[.newKey] as? NoteSegment,
               let oldFocus = change?[.oldKey] as? NoteSegment {
                print("New Observation Value (Focus):\n\t\tnew: '\(newFocus.getText())'\n\t\told: '\(oldFocus.getText())'")
                if self.speechRecognition.isListeningForSpeech {
                    self.executeSelectionUpdates(type: .model)
                }
            } else if let newFocus = change?[.newKey] as? NoteSegment {
                print("\tNew Observation Value (Focus):\n\t\tnew: '\(newFocus.getText())'\n\t\told: nil")
                if self.speechRecognition.isListeningForSpeech {
                    self.executeSelectionUpdates(type: .model)
                }
            } else {
                print("\tUnhandled Focus: ", self.focusCaret != nil ? self.getSegment(caret: self.focusCaret!)?.getText() ?? "nil" : "nil")
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
        guard let note = self.noteManager.currentNote else { return }
        let (secondLastSegmentTrackType, secondLastSegmentIndex) = Utils.getNoteNthLastSegmentIndex(
            segments: note.noteSegments,
            bufferSegments: note.noteBuffer,
            selectionCursor: self,
            n: 1
        )
        let (lastSegmentTrackType, lastSegmentIndex) = Utils.getNoteNthLastSegmentIndex(
            segments: note.noteSegments,
            bufferSegments: note.noteBuffer,
            selectionCursor: self,
            n: 0
        )

        if let cachedAnchorCaret = self.cachedAnchorCaret,
           let cachedAnchor = self.getSegment(caret: cachedAnchorCaret),
           let caretIndex = lastSegmentIndex,
           let caretTrackType = lastSegmentTrackType,
           !cachedAnchor.isVoiceCommandWord() &&
            !cachedAnchor.isDeleted() &&
            note.noteBuffer.count > 0 &&
            !self.isUpdatingSelection &&
            !self.hasSelection
        {
            // Moves the cursor to the last segment in the buffer if we have a cached anchor and non-empty buffer
            print("\tMoves the cursor to the last segment in the buffer if we have a cached anchor and non-empty buffer")
            self.moveCursor(caret: Caret(index: caretIndex, trackType: caretTrackType))
        } else if let cachedAnchorCaret = self.cachedAnchorCaret,
            let cachedAnchor = self.getSegment(caret: cachedAnchorCaret),
            !cachedAnchor.isVoiceCommandWord() &&
            !cachedAnchor.isDeleted() &&
            note.noteBuffer.count == 0  &&
            !self.isUpdatingSelection &&
            !self.hasSelection
        {
            // Moves the cursor to the cached anchor if it exists and if the buffer is empty
            // This occurs after a buffer is committed while we have a cached anchor
            // The cached anchor is updated to be the last segment of the recently committed buffer
            print("\tMoves the cursor to the cached anchor if it exists and if the buffer is empty.")
            print("\tThis occurs after a buffer is committed while we have a cached anchor.")
            print("\tThe cached anchor is updated to be the last segment of the recently committed buffer.")
            self.moveCursor(caret: cachedAnchorCaret)
        } else if let lastSegmentIndex = lastSegmentIndex,
            let lastSegmentTrackType = lastSegmentTrackType,
            note.noteBuffer.count > 0 &&
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
            // Moves cursor to the end of the note if there is no cached anchor and one of the following cases:
            // 1) The second last segment in the non-empty buffer is the current anchor, but we have a new buffer segment
            // 2) The current anchor is the same as the last segment in the non-empty buffer
            // 3) We have no anchor
            print("\tMoves cursor to the end of the note if there is no cached anchor and one of the following cases:")
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
