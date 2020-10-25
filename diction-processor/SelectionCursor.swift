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

public let selectionCursor = SelectionCursor.shared
let CURSOR_X_POS_BUFFER = CGFloat(4)
public final class SelectionCursor: NSObject, UITextViewDelegate {
    static let shared = SelectionCursor()
    
    // MARK: - Composition Properties
    @objc dynamic weak var focus: NoteSegment? = nil
    @objc dynamic weak var anchor: NoteSegment? = nil
    weak var cachedAnchor: NoteSegment? = nil
    weak var note: Note? = nil
    weak var textView: UITextView? = nil
    weak var cursorView: UIView? = nil
    weak var font: UIFont? = nil
    var selectionTimeRange: CMTimeRange? {
        if let anchor = self.anchor, let focus = self.focus, self.direction == .forwards {
            return CMTimeRangeFromTimeToTime(start: anchor.timeMapping.target.start, end: focus.timeMapping.target.end)
        } else if let anchor = anchor, let focus = focus, self.direction == .backwards {
            return CMTimeRangeFromTimeToTime(start: focus.timeMapping.target.start, end: anchor.timeMapping.target.end)
        }
        
        // Have not implemented directionless
        
        return nil
    }
    var selectionTextRange: NSRange? {
        if let anchor = self.anchor,
            let focus = self.focus,
            let note = self.note,
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
        } else if let anchor = self.anchor,
                !anchor.isVoiceCommandWord() && !anchor.isDeleted(),
                let note = self.note,
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
        if let anchor = self.anchor, let focus = self.focus, let note = note, self.direction == .backwards {
            return note.getText(from: focus.timeMapping.target.start, until: anchor.timeMapping.target.end)
        } else if let anchor = self.anchor, let focus = self.focus, let note = note, self.direction == .forwards {
            return note.getText(from: anchor.timeMapping.target.start, until: focus.timeMapping.target.end)
        }
        
        return nil
    }
    var selectionSegments: [NoteSegment]? {
        guard let note = self.note, note.noteBuffer.count == 0 else { return nil }

        var startIndex: Int?
        var endIndex: Int?
        if let focus = self.focus, let anchor = self.anchor, self.direction == .backwards {
            startIndex = focus.getIndex()
            endIndex = anchor.getIndex()
        } else if let focus = self.focus, let anchor = self.anchor {
            startIndex = anchor.getIndex()
            endIndex = focus.getIndex()
        }
        
        guard startIndex != nil && endIndex != nil else { return nil }
        
        return Array(note.noteSegments[startIndex!...endIndex!])
    }
    var direction: SelectionDirection {
        if let anchor = self.anchor, let focus = self.focus, focus.getIndex() >= anchor.getIndex() {
            return .forwards
        }
        
        return .backwards
    }
    @objc dynamic var clipboard: [NoteSegment]? = nil
    var clipboardText: String? {
        if let note = self.note, let clipboard = self.clipboard {
            return note.getText(
                from: clipboard.first!.timeMapping.target.start,
                until: clipboard.last!.timeMapping.target.end
            )
        }
        
        return nil
    }
    @objc dynamic var isCollapsed: Bool {
        return (self.anchor != nil && self.focus == nil) || (self.anchor == nil && self.focus != nil)
    }
    // Allows you to place observer on computed properties: https://stackoverflow.com/questions/36555492/kvo-on-swifts-computed-properties
    @objc class var keyPathsForValuesAffectingIsCollapsed: Set<String> {
        return [ "focus", "anchor" ]
    }
    @objc dynamic var hasSelection: Bool {
        return self.focus != nil && self.anchor != nil && !self.isCollapsed
    }
    var selectionTransformations: [NoteTransformation]? {
        guard let note = self.note, let anchor = self.anchor else { return nil }
        var transformations = [NoteTransformation]()
        let selectionLowerIndex = anchor.getIndex()
        for transformation in note.transformations {
            if transformation.noteRange.contains(selectionLowerIndex) {
                transformations.append(transformation)
            }
        }
        return transformations
    }
    // Allows you to place observer on computed properties: https://stackoverflow.com/questions/36555492/kvo-on-swifts-computed-properties
    @objc class var keyPathsForValuesAffectingHasSelection: Set<String> {
        return [ "focus", "anchor", "isCollapsed" ]
    }
    var isAtEndOfTextView: Bool {
        let lastSegment = self.getNoteNthLastSegment(n: 0)
        
        if let _ = self.anchor, let focus = self.focus, let lastSegment = lastSegment {
            // print("isAtEndOfTextView 1: ", focus == lastSegment, focus, lastSegment, note!.noteSegments, note!.noteBuffer)
            // we have a selection
            return focus == lastSegment
        } else if let anchor = self.anchor, let lastSegment = lastSegment {
            // we don't have a selection
            // we have a cursor though
            // print("isAtEndOfTextView 2: ", anchor == lastSegment, anchor, lastSegment, note!.noteSegments, note!.noteBuffer)
            return anchor == lastSegment
        } else if let note = note, note.noteSegments.count == 0 && note.noteBuffer.count == 0 {
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
    @objc dynamic var isUpdatingSelection = false
    @objc dynamic var isPromptingForUpdateAcceptance = false
    var updateSegments: [NoteSegment]? = nil
    var isLoopingSelection = false
    private var manualSelection = false
    
    // MARK: - Initializer

    private override init() {
        super.init()

        // add observer to anchor
        self.addObserver(
            self,
            forKeyPath: "anchor",
            options: [.old, .new],
            context: nil
        )
        
        // add observer to focus
        self.addObserver(
            self,
            forKeyPath: "focus",
            options: [.old, .new],
            context: nil
        )
    }

    deinit {
        // remove observer from text view
        self.textView?.removeObserver(
            self,
            forKeyPath: "selectedTextRange",
            context: nil
        )
        
        // remove observer from anchor
        self.removeObserver(
            self,
            forKeyPath: "anchor",
            context: nil
        )
        
        // remove observer from focus
        self.removeObserver(
            self,
            forKeyPath: "focus",
            context: nil
        )
    }
    
    // MARK: - Methods
    
    func checkRep() {
        let result = true
        
        // We either have no anchor and focus or both are set, but never one or the other?
        
        // if we don't have selection, we have a cursor and we only have the anchor positioned at the end of the anchor segment
        
        if !result {
            fatalError("===== [Error] SelectionCursor Representation Invariants were broken =====")
        }
    }
    
    public override var description: String {
        return "SelectionCursor {\n\tfocus: \(String(describing: self.focus)) \n\tanchor: \(String(describing: self.anchor)) \n\tnote: \(String(describing: self.note)) \t\nselectionTimeRange: \(String(describing: self.selectionTimeRange)) \n\tselectionTextRange: \(String(describing: self.selectionTextRange)) \n\tselectionRange: \(String(describing: self.selectionRange)) \n\tselectionText: \(String(describing: self.selectionText)) \n\tselectionSegments: \(String(describing: self.selectionSegments)) \n\tdirection: \(self.direction) \n\tclipboard: \(String(describing: self.clipboard)) \n\tisCollapsed: \(self.isCollapsed) \n\tisAtEndOfView: \(self.isAtEndOfTextView) \n\tisUpdatingSelection: \(self.isUpdatingSelection) \n\tisPromptingForUpdateAcceptance: \(self.isPromptingForUpdateAcceptance) \n\tupdateSegments: \(String(describing: self.updateSegments)) \n\tisLoopingSelection: \(self.isLoopingSelection) \n\tmanualSelection: \(self.manualSelection)\n}"
    }
    
    // MARK: - Action Methods
    
    func collapse(toAnchorSegment: Bool = false) {
        print("===== Selection Cursor: Collapse =====")
        if toAnchorSegment {
            self.willChangeValue(forKey: "focus")
            self.focus = self.anchor
            self.didChangeValue(forKey: "focus")
            
        } else {
            self.willChangeValue(forKey: "anchor")
            self.anchor = self.focus
            self.didChangeValue(forKey: "anchor")
        }
        
        checkRep()
    }
    
    // When playing note
    // When playing echo
    // ballistic movement
    //
    // moves as a cursor
    func moveCursor(time: CMTime, cache: Bool = false) {
        guard let note = self.note, let segment = note.getSegment(forTrackTime: time) else { return }
        print("===== Selection Cursor: Move - Time =====")
        
        if let note = self.note, AVAudioSession.isHeadphonesConnected {
            if note.isPlayingNote {
                print("\tNote is playing. Turning off...")
                self.stopPlayingSelection()
            }
            
            if self.isLoopingSelection {
                print("\tisLoopingSelection activate. Turning off...")
                self.stopPlayingSelection()
            }
        }
        
        // update model
        print("\tSetting carets...")
        self.setAnchor(segment: segment)
        self.setFocus()
        
        // Used when we want to insert a buffer into the committed segments
        // allows us to determine segment of interest
        if cache && !self.isAtEndOfTextView {
            self.setCachedAnchor(segment: self.anchor)
        } else if self.isAtEndOfTextView {
            self.setCachedAnchor()
        }
        
        // update view
        if let selectionTextRange = self.selectionTextRange, let textView = self.textView, let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: selectionTextRange.toTextRange(textInput: textView)!.end) {
            self.moveCaretView(to: caretViewRect)
        } else {
            print("===== [Error] There was a problem updating SelectionCursor: moveCursor(time: cache:) =====")
        }
        
        checkRep()
    }

    // ballistic movement
    //
    // moves as a cursor
    func moveCursor(segment: NoteSegment, cache: Bool = false) {
        guard let note = self.note else { return }
        print("===== Selection Cursor: Move - Track and Index =====")
        
        let trackType: NoteTrackType = segment.isCommitted() ? .committed : .buffer
        var segmentIndex = segment.isCommitted() ? segment.getIndex() : nil
        if segmentIndex == nil {
            for (index, s) in note.noteBuffer.enumerated() {
                if s.getUID() == segment.getUID() {
                    segmentIndex = index
                    break
                }
            }
        }
        
        if let segmentIndex = segmentIndex {
            if let note = self.note, AVAudioSession.isHeadphonesConnected {
                if note.isPlayingNote {
                    print("\tNote is playing. Turning off...")
                    self.stopPlayingSelection()
                }
                
                if self.isLoopingSelection {
                    print("\tisLoopingSelection activate. Turning off...")
                    self.stopPlayingSelection()
                }
            }
            
            // update model
            var seg: NoteSegment?
            if trackType == .committed {
                print("\tSegment is a commited segment...")
                seg = note.noteSegments[segmentIndex]
            } else if trackType == .buffer {
                print("\tSegment is a buffer segment...")
                seg = note.noteBuffer[segmentIndex]
            }

            // set new selection
            print("\tSetting carets...")
            self.setAnchor(segment: seg!)
            self.setFocus()
            
            // Used when we want to insert a buffer into the committed segments
            // allows us to determine segment of interest
            if cache && !self.isAtEndOfTextView {
                self.setCachedAnchor(segment: self.anchor)
            } else if self.isAtEndOfTextView {
                self.setCachedAnchor()
            }
            
            // update view
            if let selectionTextRange = self.selectionTextRange, let textView = self.textView, let textPosition = selectionTextRange.toTextRange(textInput: textView)?.end, let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: textPosition) {
                print("\tUpdate cursor caret screen position...")
                self.moveCaretView(to: caretViewRect)
            }

            checkRep()
        }
    }
    
    func moveCursor(textPosition: UITextPosition, cache: Bool = false) {
        guard let note = self.note else { return }
        print("=====  Selection Cursor: Move - TextPosition =====")
        
        // update model
        let cursorLocation = self.textView!.offset(from: self.textView!.beginningOfDocument, to: textPosition)
        let noteText = note.getText()
        var cursorIndex = noteText.index(noteText.startIndex, offsetBy: Int(cursorLocation))
        var beforeCursorText = String(noteText[noteText.startIndex..<cursorIndex]).replace("\n\n", with: " ")
        var afterCursorText = String(noteText[cursorIndex..<noteText.endIndex]).replace("\n\n", with: " ")
        
        var numLowerWords = beforeCursorText.split(separator: " ").count
        // first character of rangeText should be a space
        var i = 0
        while afterCursorText.count > 0 && beforeCursorText.last != " " && afterCursorText.first != " "  {
            i += 1
            cursorIndex = noteText.index(noteText.startIndex, offsetBy: Int(cursorLocation) + i)
            beforeCursorText = String(noteText[noteText.startIndex..<cursorIndex]).replace("\n\n", with: " ")
            afterCursorText = String(noteText[cursorIndex..<noteText.endIndex]).replace("\n\n", with: " ")
            numLowerWords = beforeCursorText.split(separator: " ").count
        }
        
        var noteSegments: [NoteSegment]? = nil
        if let anchor = selectionCursor.anchor, noteSegments == nil {
            // insert buffer at the correct place based on cursor position
            noteSegments = note.noteSegments
            let anchorIndex = anchor.getIndex()
            if anchorIndex != Int(Utils.UNKNOWN) {
                noteSegments!.insert(contentsOf: note.noteBuffer, at: anchorIndex)
            } else {
                noteSegments! += note.noteBuffer
            }
        } else if noteSegments == nil {
            // insert buffer at the end of segments
            noteSegments = note.noteSegments + note.noteBuffer
        }
        
        var numProcessedWords: Int = 0
        var anchor: NoteSegment?
        let lowerWords = beforeCursorText.split(separator: " ")
        for i in 0..<noteSegments!.count {
            let segment = noteSegments![i]
            if !segment.isVoiceCommandWord() && !segment.isSilence() && !segment.isDeleted() {
                numProcessedWords += 1
            }
            
            if !segment.isVoiceCommandWord() && !segment.isSilence() && !segment.isDeleted() && segment.getText().lowercased().trimTrailingPunctuation() == lowerWords.last!.lowercased().trimTrailingPunctuation() && numProcessedWords == numLowerWords {
                anchor = segment
                break
            }
        }
        
        if let anchor = anchor {
            print("\tSetting carets...")
            // Set anchor
            self.setAnchor(segment: anchor)
            self.setFocus()
            
            // Used when we want to insert a buffer into the committed segments
            // allows us to determine segment of interest
            if cache && !self.isAtEndOfTextView {
                self.setCachedAnchor(segment: anchor)
            } else if self.isAtEndOfTextView {
                self.setCachedAnchor()
            }
        } else {
            print("===== [Error] There was a problem finding cursor note segment =====")
        }
        
        // update view
        let updatedTextPosition = self.textView!.position(from: textPosition, offset: i)
        if let updatedTextPosition = updatedTextPosition, let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: updatedTextPosition) {
            self.moveCaretView(to: caretViewRect)
        }
        
        checkRep()
    }
    
    func isSegmentInRange(segment: NoteSegment) -> Bool {
        guard let note = self.note, let selectionTextRange = self.selectionTextRange else { return false }

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
        if let focus = self.focus, let anchor = self.anchor, self.direction == .backwards {
            print("\tSelection has backwards direction.")
            print("\tSelection start and end times retrieved.")
            startTime = focus.getSentence().timeRange.start
            endTime = anchor.getSentence().timeRange.end
        } else if let focus = self.focus, let anchor = self.anchor {
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
        if let focus = self.focus, let anchor = self.anchor, self.direction == .backwards {
            print("\tSelection has backwards direction.")
            print("\tSelection start and end times retrieved.")
            startTime = focus.timeMapping.target.start
            endTime = anchor.timeMapping.target.end
        } else if let focus = self.focus, let anchor = self.anchor {
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
        if self.isLoopingSelection, let note = self.note {
            self.isLoopingSelection = false
            
            // Stop Sound
            if soundEngine.isProcessing {
                print("\tSound Engine playing 'Processing Sound'. Turning off..")
                soundEngine.stopProcessing()
            }
            
            if let _ = note.player.currentItem {
                print("\tArtifact of selection player item found in Note Player. Discarding it...")
                note.player.replaceCurrentItem(with: nil)
            }
            
            // Stop Note
            if note.isPlayingNote {
                note.stop()
            }
        }
    }
    
    func playPassage(startTime: CMTime, endTime: CMTime, loop: Bool = false) {
        print("===== Selection Cursor: \(startTime.seconds) to \(endTime.seconds) =====")

        if let note = self.note {
            print("\tPreparing to play selection.")
            if loop {
                print("\tActivated looping selection.")
                self.isLoopingSelection = true
            } else {
                print("\tDeactivated looping selection.")
                self.stopPlayingSelection()
            }

            note.play(
                from: startTime,
                to: endTime,
                segmentBoundaryHandler: {
                    DispatchQueue.main.async {
                        if let segment = note.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = note.getSegmentTextRange(of: segment) {
                            // update text
                            note.handleOnListenUpdate(text: note.getText(), highlightRange: highlightRange)
                        }
                        
                        // TODO: Show pitch
                    }
                }, onFinishHandler: {
                    DispatchQueue.main.async {
                        note.handleOnListenUpdate(text: note.getText())
                    }
                }
            )
        } else if let note = self.note, AVAudioSession.isHeadphonesConnected {
            print("\tNo selection start and end times found. Abort method.")

            if note.isPlayingNote {
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
        guard let note = self.note, let anchor = self.anchor, let focus = self.focus, note.noteBuffer.count == 0 else { return }
        
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
            let nextFocus = note.noteSegments[nextFocusIndex]
            self.setFocus(segment: nextFocus)
        } else {
            print("===== [Error] There was a problem computing new focus segment index =====")
        }
        
        checkRep()
    }
    
    func shiftAnchorSegment(shiftDirection: SelectionShiftDirection, by count: Int = 1) {
        print("===== Selection Cursor: Shift Anchor Segment \(shiftDirection) =====")
        // prevent illegal moves
        guard let note = self.note, let anchor = self.anchor, let focus = self.focus, note.noteBuffer.count == 0 else { return }

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
            let nextAnchor = note.noteSegments[nextAnchorIndex]
            self.setAnchor(segment: nextAnchor)
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

    func adjustRateSelection(direction: DirectionType) {
        print("===== Selection Cursor: Adjust Rate =====")
        // prevent illegal deletions
        guard let note = self.note, self.hasSelection else {
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
    }
    
    func deleteSelection(isCommit: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Delete =====")
        // prevent illegal deletions
        guard let note = self.note, let selectionTimeRange = self.selectionTimeRange else {
            print("====== [Error] There was a problem deleting selection. TimeRange could not be computed =====")
            return
        }
        
        // Play sound
        soundEngine.delete()
        
        let handleDeleteSelection = {
            // remove focus
            self.setFocus() // So that we don't update it with a new focus
            
            // remove passage
            note.removePassage(range: selectionTimeRange)
            
            // cache anchor if not at end of note
            if !self.isAtEndOfTextView {
                self.setCachedAnchor(segment: self.anchor)
            }
            
            // move cursor
            if let anchor = self.anchor {
                self.moveCursor(segment: anchor)
            }
            
            if isCommit {
                // Present Feedback
                Utils.executeFeedback(
                    visualMessage: "Delete Commit",
                    audioMessage: "commit deleted",
                    note: note,
                    withHaptics: true
                )
            } else {
                // Present Feedback
                Utils.executeFeedback(
                    visualMessage: "Delete Selection",
                    audioMessage: "selection deleted",
                    note: note,
                    withHaptics: true
                )
            }
            
            
            handler?()

            // play to hear difference
            self.checkRep()
        }
        
        // Stop walking/running if currently doing so
        if note.isWalkingNote || note.isRunningNote {
            note.exitWalk(clearSelection: false, withFeedback: false) {
                handleDeleteSelection()
            }
        } else {
            handleDeleteSelection()
        }
    }
    
    func initiateUpdateSelection(handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Initiate Update Selection =====")
        // prevent illegal updating
        guard let note = self.note else { return }
        
        // Stop playback
        if note.isPlayingNote {
            note.stop()
        }
        // Stop echo
        if note.isPlayingEcho {
            note.stopEcho()
        }
        
        if self.isUpdatingSelection {
            Utils.executeError(note: note, text: "Already updating selection.")
    
            note.startListeningForSpeech(
                soundIntensityHandler: note.soundIntensityHandler,
                pitchHandler: note.pitchHandler,
                onStartHandler: handler
            )
            return
        }
        
        let handleInitiateUpdateSelection = {
            // Start recording to update segment
            note.startListeningForSpeech(
                soundIntensityHandler: note.soundIntensityHandler,
                pitchHandler: note.pitchHandler,
                onStartHandler: handler
            )
            
            if self.isUpdatingSelection {
                // Present Feedback
                Utils.executeFeedback(
                    visualMessage: "Redo Update",
                    audioMessage: "redo update selection.",
                    note: note,
                    withHaptics: true
                )
            } else {
                // Present Feedback
                Utils.executeFeedback(
                    visualMessage: "Initiate Update",
                    audioMessage: "listening for update",
                    note: note,
                    withHaptics: true
                )
            }
            
            // clear update segments
            self.updateSegments = nil
            
            // signal that we'll be updating selection
            self.isUpdatingSelection = true
            
            // turn off prompting for selection acceptance flag
            self.isPromptingForUpdateAcceptance = false

            // play to hear difference
            self.checkRep()
        }
        
        // Pause walking / running
        if note.isWalkingNote || note.isRunningNote {
            note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                handleInitiateUpdateSelection()
            }
        } else {
            handleInitiateUpdateSelection()
        }
    }
    
    func handleUpdateSelection(segments: [NoteSegment]) {
        print("===== Selection Cursor: Handle Update Selection =====")
        guard let note = self.note, let selectionText = self.selectionText, segments.count > 0 else { return }

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
        
        // turn on prompting for selection acceptance flag
        self.isPromptingForUpdateAcceptance = true
        
        // Svae presumed update segments
        self.updateSegments = normalizedUpdateSegments
        
        // Compute update selectiont text
        let updateText = note.getText(segments: self.updateSegments)
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Confirm Update",
            audioMessage: "Update selection to '\(updateText)'. Accept, redo or cancel?",
            note: note,
            withHaptics: true
        )
        
        // Present Update Dialog
        let dialogActions = [
            DialogAction(title: "Accept", style: .default, handler: { [weak self] action in
                // Turn off ambient track
                soundEngine.stopModalAmbience()

                // Clear buffer segments
                print("\tClearing note buffer...")
                note.clearBuffer()
                
                // Accept Update
                print("\tAccepting Update Selection...")
                self?.acceptUpdateSelection()
            }),
            DialogAction(title: "Redo", style: .destructive, handler: { action in
                // Turn off ambient track
                soundEngine.stopModalAmbience()

                // Clear buffer segments
                print("\tClearing note buffer...")
                note.clearBuffer()
                
                // Redo Update Selection
                print("\tRedoing Update Selection...")
                self.initiateUpdateSelection()
            }),
            DialogAction(title: "Cancel", style: .cancel, handler: { action in
                // Turn off ambient track
                soundEngine.stopModalAmbience()

                // Clear buffer segments
                print("\tClearing note buffer...")
                note.clearBuffer()
                
                // Cancel Update Selection
                print("\tCanceling Update Selection...")
                self.cancelUpdateSelection()
            })
        ]
        
        let dialogItem = DialogItem(
            title: "Update Selection",
            message: "Update \"\(selectionText)\" with \"\(updateText)\"",
            preferredStyle: .alert,
            actions: dialogActions
        )
        Utils.presentDialog(dialogItem: dialogItem, vc: note.vc!)
    }
    
    func acceptUpdateSelection(handler: (() -> Void)? = nil) {
        print("===== Selection Cursor Commit: Commit Updated Selection =====")

        // prevent illegal updating
        guard let note = self.note, let selectionTimeRange = self.selectionTimeRange, let updateSegments = self.updateSegments else { return }
        
        var segments = [NoteSegment]()
        for segment in updateSegments {
            let duplicateSegment = segment.duplicate(withNewUID: true)
            segments.append(duplicateSegment)
        }
        
        // Update to new anchor
        self.setAnchor(segment: segments.first!, broadcastChange: false)

        // Update to new focus
        self.setFocus(segment: segments.last!, broadcastChange: false)
        
        // Update to new cached anchor
        if let _ = self.cachedAnchor {
            self.setCachedAnchor(segment: segments.first!)
        }

        // Update Selection
        note.updatePassage(
            segments: segments,
            range: selectionTimeRange
        )
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Updated!",
            audioMessage: "selection updated",
            note: note,
            withHaptics: true
        )
        
        // Update UI
        note.handleOnListenUpdate(text: note.getText())
        
        // turn off update selection flag
        self.isUpdatingSelection = false

        // clear update segments
        self.updateSegments = nil

        // turn off prompting for selection acceptance flag
        self.isPromptingForUpdateAcceptance = false
        
        if note.pausedWalkingNote {
            note.walk() {
                handler?()
            }
        } else if note.pausedRunningNote {
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
        print("===== Selection Cursor: Cancel Update =====")
        // prevent illegal updating
        guard let note = self.note else { return }
        
        let handleCancelUpdate = {
            // turn off update selection flag
            self.isUpdatingSelection = false
            
            // clear update segments
            self.updateSegments = nil
            
            // turn off prompting for selection acceptance flag
            self.isPromptingForUpdateAcceptance = false
            
            if !note.pausedListeningForSpeech {
                note.stopListeningForSpeech(pause: true) {
                    note.startListeningForVoiceCommands(
                        soundIntensityHandler: note.vc!.soundIntensityHandler!,
                        pitchHandler: note.vc!.pitchHandler!,
                        onStartHandler: handler
                    )
                }
            } else {
                note.startListeningForVoiceCommands(
                    soundIntensityHandler: note.vc!.soundIntensityHandler!,
                    pitchHandler: note.vc!.pitchHandler!,
                    onStartHandler: handler
                )
            }
            
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Canceled!",
                audioMessage: "selection update canceled",
                note: note,
                withHaptics: true
            )

            // play to hear difference
            self.checkRep()
        }
        
        if note.pausedWalkingNote {
            note.walk() {
                handleCancelUpdate()
            }
        } else if note.pausedRunningNote {
            note.run() {
                handleCancelUpdate()
            }
        } else {
            handleCancelUpdate()
        }
    }
    
    func copySelection() {
        print("===== Selection Cursor: Copy =====")
        // prevent illegal updating
        guard let note = self.note else { return }

        if let selectionSegments = self.selectionSegments {
            var duplicateSegments = [NoteSegment]()
            for segment in selectionSegments {
                duplicateSegments.append(segment.duplicate())
            }
            self.clipboard = duplicateSegments
        }
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Copy Selection",
            audioMessage: "selection copied",
            note: note,
            withHaptics: true
        )
        
        checkRep()
    }
    
    func cutSelection() {
        print("===== Selection Cursor: Cut =====")
        // prevent illegal updating
        guard let note = self.note else { return }

        // copy selection
        self.copySelection()
        
        // delete selection
        self.deleteSelection()
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Cut Selection",
            audioMessage: "selection cut",
            note: note,
            withHaptics: true
        )

        // play to hear difference
        checkRep()
    }

    func pasteSelection() {
        print("===== Selection Cursor: Paste =====")
        if let note = self.note, let anchor = self.anchor, let clipboard = self.clipboard {
            
            var pastedSegments = [NoteSegment]()
            for segment in clipboard {
                let duplicateSegment = segment.duplicate(withNewUID: true)
                pastedSegments.append(duplicateSegment)
            }
            
            // Update to new anchor
            self.setAnchor(segment: pastedSegments.last!)
            
            // Update to new cached anchor
            if let _ = self.cachedAnchor {
                self.setCachedAnchor(segment: pastedSegments.last!)
            }
            
            // Insert selection into note
            note.insertPassage(
                segments: pastedSegments,
                at: anchor.timeMapping.target.end
            )
            
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Pasted!",
                audioMessage: "selection pasted",
                note: note,
                withHaptics: true
            )
        } else if let note = self.note, self.clipboard == nil {
            Utils.executeError(note: note, text: "Clipboard is empty.")
        }
        // We don't clear clipboard. Mimics behavior of copy/paste on computers
        checkRep()
    }
    
    func exportSelection(handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Export =====")
        // prevent illegal updating
        guard let note = self.note, let selectionTimeRange = self.selectionTimeRange else { return }
        
        Utils.executeFeedback(
            visualMessage: "Exporting Selection",
            audioMessage: "exporting selection",
            note: note,
            withHaptics: true
        )

        let selectionFilename = "note-\(UUID().uuidString)"
        
        Utils.exportNote(
            note: note,
            filename: selectionFilename,
            fileType: note.fileType,
            timeRange: selectionTimeRange
        ) {
            handler?()
            
            Utils.executeFeedback(
                visualMessage: "Selection Exported!",
                audioMessage: "selection exported",
                note: note,
                withHaptics: true
            )
        }

        checkRep()
    }
        
    //    func walk() {
    //
    //    }
        
    //    func loop() {
    //
    //    }
    
    // MARK: - Setters
    
    // Used when a user selects text from screen
    func setSelection(textRange: UITextRange) {
        guard let note = self.note, let textView = self.textView else { return }
        print("===== Selection Cursor: Set Selection - TextRange =====")

        let location = textView.offset(from: self.textView!.beginningOfDocument, to: textRange.start)
        let length = textView.offset(from: textRange.start, to: textRange.end)
        let noteText = note.getText()
        var lowerIndex = noteText.index(noteText.startIndex, offsetBy: Int(location))
        var upperIndex = noteText.index(noteText.startIndex, offsetBy: Int(location) + length)
        var selectionRangeStringIndex = lowerIndex..<upperIndex
        var rangeText = String(noteText[selectionRangeStringIndex]).replace("\n\n", with: " ")
        var beforeRangeText = String(noteText[noteText.startIndex..<lowerIndex]).replace("\n\n", with: " ")
        var afterRangeText = String(noteText[upperIndex..<noteText.endIndex]).replace("\n\n", with: " ")
        
        var numLowerWords = beforeRangeText.split(separator: " ").count
        var numLowerSpaces = beforeRangeText.filter { $0 == " " }.count
        // first character of rangeText should be a space
        var i = 0
        while numLowerWords > numLowerSpaces && beforeRangeText.count > 0 && beforeRangeText.last != " " {
            i += 1
            lowerIndex = noteText.index(noteText.startIndex, offsetBy: Int(location - i))
            selectionRangeStringIndex = lowerIndex..<upperIndex
            rangeText = String(noteText[selectionRangeStringIndex]).replace("\n\n", with: " ")
            beforeRangeText = String(noteText[noteText.startIndex..<lowerIndex]).replace("\n\n", with: " ")
            numLowerWords = beforeRangeText.split(separator: " ").count
            numLowerSpaces = beforeRangeText.filter { $0 == " " }.count
        }
        
        var numRangeWords = rangeText.split(separator: " ").count
        var numRangeSpaces = rangeText.filter { $0 == " " }.count
        // first character of rangeText should be a space
        var j = 0
        while numRangeSpaces <= numRangeWords && afterRangeText.count > 0 && afterRangeText.first != " " {
            j += 1
            upperIndex = noteText.index(noteText.startIndex, offsetBy: Int(location) + length + j)
            selectionRangeStringIndex = lowerIndex..<upperIndex
            rangeText = String(noteText[selectionRangeStringIndex]).replace("\n\n", with: " ")
            afterRangeText = String(noteText[upperIndex..<noteText.endIndex]).replace("\n\n", with: " ")
            numRangeWords = rangeText.split(separator: " ").count
            numRangeSpaces = rangeText.filter { $0 == " " }.count
        }
        
        var noteSegments: [NoteSegment]? = nil
        if let anchor = selectionCursor.anchor, noteSegments == nil {
            // insert buffer at the correct place based on cursor position
            noteSegments = note.noteSegments
            let anchorIndex = anchor.getIndex()
            if anchorIndex != Int(Utils.UNKNOWN) {
                noteSegments!.insert(contentsOf: note.noteBuffer, at: anchorIndex)
            } else {
                noteSegments! += note.noteBuffer
            }
        } else if noteSegments == nil {
            // insert buffer at the end of segments
            noteSegments = note.noteSegments + note.noteBuffer
        }
        
        var numProcessedWords: Int = 0
        var rangeSegments = [NoteSegment]()
        for i in 0..<noteSegments!.count {
            let segment = noteSegments![i]
            if !segment.isVoiceCommandWord() && !segment.isSilence() && !segment.isDeleted() {
                numProcessedWords += 1
            }
            
            if !segment.isVoiceCommandWord() && !segment.isSilence() && !segment.isDeleted() && numProcessedWords > numLowerWords && numProcessedWords < numLowerWords + numRangeWords + 1 {
                rangeSegments.append(segment)
            }
            
            if numProcessedWords > numLowerWords + numRangeWords {
                break
            }
        }
        
        if rangeSegments.count > 0 {
            // Set anchor and focus
            self.setAnchor(segment: rangeSegments.first!)
            self.setFocus(segment: rangeSegments.last!)
        } else {
            print("===== [Error] There was a problem finding selection note segments =====")
        }
        
        if let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: textRange.end, includeXPosBuffer: false) {
            self.moveCaretView(to: caretViewRect)
        }
        
        checkRep()
    }
    
    func setSelection(anchor: NoteSegment, focus: NoteSegment) {
        print("===== Selection Cursor: Set Selection - Anchor and Focus =====")
        // Set anchor and focus
        self.setAnchor(segment: anchor)
        self.setFocus(segment: focus)
        
        if let selectionTextRange = self.selectionTextRange, let textView = self.textView, let textPosition = selectionTextRange.toTextRange(textInput: textView)?.end, let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: textPosition, includeXPosBuffer: false) {
            self.moveCaretView(to: caretViewRect)
        } else {
            print("\tNo need to update caret position...")
        }

        checkRep()
    }
    
    func clearSelection(withFeedback: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Selection Cursor: Clear Selection =====")
        if let note = self.note, let textView = self.textView {
            if note.isPlayingNote {
                print("\tNote is playing. Turning off...")
                self.stopPlayingSelection()
            }
            
            if self.isLoopingSelection {
                print("\tisLoopingSelection activate. Turning off...")
                self.stopPlayingSelection()
            }
            
            print("\tCache anchor if not at end of text view")
            if !self.isAtEndOfTextView {
                // We cache the anchor if we're mid-note so that new content is added from given location
                self.setCachedAnchor(segment: selectionCursor.anchor)
            }
            
            print("\tRemove selection in view.")
            textView.selectedTextRange = nil
            print("\tClear selection in model.")
            selectionCursor.setAnchor()
            selectionCursor.setFocus()
            handler?()
            
            if withFeedback {
                Utils.executeFeedback(
                    visualMessage: "Selection Removed!",
                    audioMessage: "selection remove",
                    note: note,
                    withHaptics: true
                )
            }
        }
    }
    
    func setNote(note: Note? = nil) {
        print("===== Selection Cursor: Set Note =====")
        if let note = note {
            print("\tSet note.")
            self.note = note
        } else {
            print("\tClear note.")
            self.note = nil
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
    }
    
    func setFont(font: UIFont? = nil) {
        print("===== Selection Cursor: Set Cursor View =====")
        // store cursor view
        if let font = font {
            // Add new one
            print("\tSet font.")
            self.font = font
        } else {
            // clear font
            print("\tClear font.")
            self.font = nil
        }
    }
    
    func setAnchor(segment: NoteSegment? = nil, broadcastChange: Bool = true) {
        print("===== Selection Cursor: Set Anchor =====")
        print("\tnew: ", segment?.getText() ?? "nil")
        print("\told: ", self.anchor?.getText() ?? "nil")
        if let segment = segment, segment != self.anchor || Unmanaged.passUnretained(segment).toOpaque() != Unmanaged.passUnretained(self.anchor!).toOpaque() {
            print("\tNew anchor: \(segment.getText())")
            if broadcastChange {
                self.willChangeValue(forKey: "anchor")
                self.anchor = segment
                self.didChangeValue(forKey: "anchor")
            } else {
                self.anchor = segment
            }
        } else if let _ = self.anchor, segment == nil {
            print("\tClear anchor.")
            if broadcastChange {
                self.willChangeValue(forKey: "anchor")
                self.anchor = nil
                self.didChangeValue(forKey: "anchor")
            } else {
                self.anchor = nil
            }
        } else if let segment = segment, let anchor = self.anchor, segment == anchor {
            print("\tAnchor argument is the same as current anchor: \(self.anchor!.getText())")
        } else if self.anchor == nil && segment == nil {
            print("\tAnchor argument is empty and current anchor is already empty.")
        } else {
            print("\tUnhandled anchor argument.")
        }
        
        checkRep()
    }
    
    func setFocus(segment: NoteSegment? = nil, broadcastChange: Bool = true) {
        print("===== Selection Cursor: Set Focus =====")
        print("\tnew: ", segment?.getText() ?? "nil")
        print("\told: ", self.focus?.getText() ?? "nil")
        if let segment = segment, segment != self.focus || Unmanaged.passUnretained(segment).toOpaque() != Unmanaged.passUnretained(self.focus!).toOpaque() {
            print("\tNew focus: \(segment.getText())")
            if broadcastChange {
                self.willChangeValue(forKey: "focus")
                self.focus = segment
                self.didChangeValue(forKey: "focus")
            } else {
                self.focus = segment
            }
        } else if let _ = self.focus, segment == nil {
            print("\tClear focus.")
            if broadcastChange {
                self.willChangeValue(forKey: "focus")
                self.focus = nil
                self.didChangeValue(forKey: "focus")
            } else {
                self.focus = nil
            }
        } else if let segment = segment, let focus = self.focus, segment == focus {
            print("\tFocus argument is the same as current focus: \(self.focus!.getText())")
            
        } else if self.focus == nil && segment == nil {
            print("\tFocus argument is empty and current focus is already empty.")
        } else {
            print("\tUnhandled focus argument.")
        }
        
        checkRep()
    }
    
    func setCachedAnchor(segment: NoteSegment? = nil) {
        print("===== Selection Cursor: Set Cached Anchor =====")
        if let segment = segment {
            print("\tSet cached anchor: ", segment.getText())
            self.cachedAnchor = segment
        } else {
            print("\tClear cached anchor.")
            self.cachedAnchor = nil
        }
        
        checkRep()
    }
    
    func reset() {
        print("===== Selection Cursor: Reset =====")
        self.setAnchor()
        self.setFocus()
        self.setCachedAnchor()
        self.setNote()
        self.setTextView()
        self.setCursorView()
        self.clipboard = nil
        self.isUpdatingSelection = false
        self.isPromptingForUpdateAcceptance = false
        self.updateSegments = nil
        self.isLoopingSelection = false
    }
    
    // MARK: - Getters
    
    func getNeighborhood() -> [NoteSegment] {
        print("===== Selection Cursor: Get Neightborhood =====")
        var neighborhood = [NoteSegment]()
        var startTime: CMTime?
        var endTime: CMTime?
        if let focus = self.focus, let anchor = self.anchor, self.direction == .backwards {
            startTime = focus.getSentence().timeRange.start
            endTime = anchor.getSentence().timeRange.end
        } else if let focus = self.focus, let anchor = self.anchor {
            startTime = anchor.getSentence().timeRange.start
            endTime = focus.getSentence().timeRange.end
        }
        
        guard let note = self.note, startTime != nil && endTime != nil, note.noteBuffer.count == 0 else { return neighborhood }
        
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
            if let selectionTextRange = self.selectionTextRange, let textView = self.textView, let textPosition = selectionTextRange.toTextRange(textInput: textView)?.end, let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: textPosition) {
                self.moveCaretView(to: caretViewRect)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    func getLastUsedTrack() -> NoteTrackType? {
        guard let note = self.note else { return nil }

        var trackType: NoteTrackType = .committed
        if note.noteBuffer.count > 0 {
            trackType = .buffer
        }
        
        return trackType
    }
    
    func getNoteNthLastSegmentIndex(n: Int) -> (NoteTrackType?, Int?) {
        guard let note = self.note else { return (nil, nil) }

        var lastSegmentIndex: Int?
        var trackType: NoteTrackType?
        if note.noteBuffer.count == 0 {
            trackType = .committed
            var i = 0
            for (index, segment) in note.noteSegments.reversed().enumerated() {
                if !segment.isVoiceCommandWord() && !segment.isSilence() && !segment.isDeleted() && lastSegmentIndex == nil && i == n {
                    lastSegmentIndex = note.noteSegments.count - index - 1
                    break
                } else if !segment.isVoiceCommandWord() && !segment.isSilence() && !segment.isDeleted() && lastSegmentIndex == nil {
                    i += 1
                }
            }
        } else {
            trackType = .buffer
            if self.cachedAnchor == nil {
                var i = 0
                for (index, segment) in note.noteBuffer.reversed().enumerated() {
                    if !segment.isVoiceCommandWord() && !segment.isSilence() && !segment.isDeleted() && lastSegmentIndex == nil && i == n {
                        lastSegmentIndex = note.noteBuffer.count - index - 1
                        break
                    } else if !segment.isVoiceCommandWord() && !segment.isSilence() && !segment.isDeleted() && lastSegmentIndex == nil {
                        i += 1
                    }
                }
            }
            
            // if hasn't been found, check committed segments
            var j = note.noteBuffer.count
            if lastSegmentIndex == nil && note.noteSegments.count > n - note.noteBuffer.count {
                for (index, segment) in note.noteSegments.reversed().enumerated() {
                    if !segment.isVoiceCommandWord() && !segment.isSilence() && !segment.isDeleted() && lastSegmentIndex == nil && j == n {
                        lastSegmentIndex = note.noteSegments.count - index - 1
                        trackType = .committed
                        break
                    } else if !segment.isVoiceCommandWord() && !segment.isSilence() && !segment.isDeleted() && lastSegmentIndex == nil {
                        j += 1
                    }
                }
            }
        }
        
        return (trackType, lastSegmentIndex)
    }
    
    func getNoteNthLastSegment(n: Int) -> NoteSegment? {
        guard let note = self.note else { return nil }

        let lastSegmentTuple = self.getNoteNthLastSegmentIndex(n: n)
        if let trackType = lastSegmentTuple.0, let lastSegmentIndex = lastSegmentTuple.1, trackType == .committed {
            return note.noteSegments[lastSegmentIndex]
        } else if let trackType = lastSegmentTuple.0, let lastSegmentIndex = lastSegmentTuple.1, trackType == .buffer {
            return note.noteBuffer[lastSegmentIndex]
        }
        
        return nil
    }
    
    func executeSelectionUpdates(type: SelectionChangeType) {
        print("===== Selection Cursor: Execute Selection Updates =====")
        if type == .view {
            print("\tProcessing changes to screen via touch...")
            // changes to screen via touch
            if let selectionTextRange = self.textView?.selectedTextRange, let selectedText = self.textView?.text(in: selectionTextRange), selectedText.count > 0 {
                print("\tScreen has selected text range.")
                // set selection in model
                print("\tSyncing up selection in model with selection on screen: ", selectionTextRange)
                self.setSelection(textRange: selectionTextRange)
                
                // loop selection audio
                // turn on processing sound
                if let note = self.note, AVAudioSession.isHeadphonesConnected && !note.isRunningNote && !note.isWalkingNote {
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
            if let _ = self.focus, let _ = self.anchor, let selectedRange = self.selectionTextRange {
                print("\tModel has selected text range.")
                // set selection on screen
                print("\tSyncing up selection on screen with selection in model: ", selectedRange)
                self.manualSelection(range: selectedRange)
                
                // begin looping selection audio
                // turn on processing sound
                if let note = self.note, AVAudioSession.isHeadphonesConnected && !note.isRunningNote && !note.isWalkingNote {
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
            xPos += CURSOR_X_POS_BUFFER
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
            print("\tRelates to 'contentSize'")
            if let newContentSize = change?[.newKey] as? CGSize, let oldContentSize = change?[.oldKey] as? CGSize, newContentSize.height > self.textView!.frame.height && self.isAtEndOfTextView {
                print("\tNew Observation Value (contentSize):\n\t\tnew: '\(newContentSize)'\n\t\told: '\(oldContentSize)'")
                self.scrollToBottom()
            } else {
                print("\tUnhandled Content Size Change...")
            }
        } else if keyPath == "selectedTextRange" {
            print("\tRelates to 'selectionTextRange'")
            if let newSelectionRange = change?[.newKey] as? UITextRange, !self.manualSelection {
                print("\tNew Observation Value (selectionTextRange): ", newSelectionRange)
                self.executeSelectionUpdates(type: .view)
            } else if self.manualSelection {
                print("Turn off manual selection flag...")
                self.manualSelection = false
            } else {
                print("\tNo selection range. Clear selectionTextRange in model...")
            }
        } else if keyPath == "anchor" {
            print("\tRelates to 'anchor'")
            if let newAnchor = change?[.newKey] as? NoteSegment, let oldAnchor = change?[.oldKey] as? NoteSegment, let note = self.note {
                print("\tNew Observation Value (Anchor):\n\t\tnew: '\(newAnchor.getText())'\n\t\told: '\(oldAnchor.getText())'")
                if note.isListeningForSpeech {
                    self.executeSelectionUpdates(type: .model)
                }
            } else if let newAnchor = change?[.newKey] as? NoteSegment, let note = self.note {
                print("\tNew Observation Value (Anchor):\n\t\tnew: '\(newAnchor.getText())'\n\t\told: nil")
                if note.isListeningForSpeech {
                    self.executeSelectionUpdates(type: .model)
                }
            } else {
                print("\tUnhandled Anchor: ", self.anchor?.getText() ?? "nil")
            }
        } else if keyPath == "focus" {
            print("\tRelates to 'focus'")
            if let newFocus = change?[.newKey] as? NoteSegment, let oldFocus = change?[.oldKey] as? NoteSegment, let note = self.note {
                print("New Observation Value (Focus):\n\t\tnew: '\(newFocus.getText())'\n\t\told: '\(oldFocus.getText())'")
                if note.isListeningForSpeech {
                    self.executeSelectionUpdates(type: .model)
                }
            } else if let newFocus = change?[.newKey] as? NoteSegment, let note = self.note {
                print("\tNew Observation Value (Focus):\n\t\tnew: '\(newFocus.getText())'\n\t\told: nil")
                if note.isListeningForSpeech {
                    self.executeSelectionUpdates(type: .model)
                }
            } else {
                print("\tUnhandled Focus: ", self.anchor?.getText() ?? "nil")
            }
        }
    }
    
    public override class func automaticallyNotifiesObservers(forKey key: String) -> Bool {
        if key == "anchor" {
            return false
        } else if key == "focus" {
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
        // print("===== SelectionCursor: textViewDidChange =====")
        guard let note = self.note else { return }
        let secondLastSegment = self.getNoteNthLastSegment(n: 1)
        let lastSegment = self.getNoteNthLastSegment(n: 0)

        if self.cachedAnchor != nil && !self.cachedAnchor!.isVoiceCommandWord() && !self.cachedAnchor!.isDeleted() && note.noteBuffer.count > 0 && !self.isUpdatingSelection, let newAnchor = note.noteBuffer.last {
            // Moves the cursor to the last segment in the buffer if we have a cached anchor and non-empty buffer
            self.moveCursor(segment: newAnchor)
        } else if self.cachedAnchor != nil && !self.cachedAnchor!.isVoiceCommandWord() && !self.cachedAnchor!.isDeleted() && note.noteBuffer.count == 0  && !self.isUpdatingSelection {
            // Moves the cursor to the cached anchor if it exists and if the buffer is empty
            // This occurs after a buffer is committed while we have a cached anchor
            // The cached anchor is updated to be the last segment of the recently committed buffer
            self.moveCursor(segment: self.cachedAnchor!)
        } else if let lastSegment = lastSegment, note.noteBuffer.count > 0 && ((secondLastSegment != nil && self.anchor == secondLastSegment) || (self.anchor != lastSegment) || (self.anchor == nil)) {
            // Moves cursor to the end of the note if there is no cached anchor and one of the following cases:
            // 1) The second last segment in the non-empty buffer is the current anchor, but we have a new buffer segment
            // 2) The current anchor is the same as the last segment in the non-empty buffer
            // 3) We have no anchor
            self.moveCursor(segment: lastSegment)
        } else if let selectionTextRange = self.selectionTextRange, let textView = self.textView, let textPosition = selectionTextRange.toTextRange(textInput: textView)?.end, let caretViewRect = self.caretViewPositionRequiresUpdate(textPosition: textPosition) {
            self.moveCaretView(to: caretViewRect)
        } else if let textView = self.textView, let cursorView = self.cursorView, let font = self.font, textView.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).length == 0 {
            // reset cursor position
            Utils.initializeCursor(
                textView: textView,
                cursorView: cursorView,
                font: font
            )
        } else {
            print("===== Selection Cursor: textViewDidChange - Unhandled Anchor: ", self.anchor?.getText() ?? "nil", " =====")
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
