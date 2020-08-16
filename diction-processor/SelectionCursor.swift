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

// Reference: https://stackoverflow.com/questions/34922331/getting-and-setting-cursor-position-of-uitextfield-and-uitextview-in-swift

public let selectionCursor = SelectionCursor.shared
let CURSOR_X_POS_BUFFER = CGFloat(4)
public final class SelectionCursor: NSObject, UITextViewDelegate {
    static let shared = SelectionCursor()
    
    // MARK: - Composition Properties
    var focus: NoteSegment? = nil
    var anchor: NoteSegment? = nil
    var note: Note? = nil
    var textView: UITextView? = nil
    var cursorView: UIView? = nil
    var selectionTimeRange: CMTimeRange? {
        if let anchor = self.anchor, let focus = self.focus, self.direction == .forwards {
            return CMTimeRangeFromTimeToTime(start: anchor.timeMapping.target.start, end: focus.timeMapping.target.end)
        } else if let anchor = anchor, let focus = focus, self.direction == .backwards {
            return CMTimeRangeFromTimeToTime(start: focus.timeMapping.target.start, end: anchor.timeMapping.target.end)
        }
        
        // Have not implemented directionless
        
        return nil
    }
    var selectionRange: NSRange? {
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
                let note = self.note,
                let anchorRange = note.getSegmentTextRange(of: anchor) {
            return anchorRange
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
    var selectionSegments: [NoteSegment] {
        var segments = [NoteSegment]()
        var startTime: CMTime?
        var endTime: CMTime?
        if let focus = self.focus, let anchor = self.anchor, self.direction == .backwards {
            startTime = focus.timeMapping.target.start
            endTime = anchor.timeMapping.target.end
        } else if let focus = self.focus, let anchor = self.anchor {
            startTime = anchor.timeMapping.target.start
            endTime = focus.timeMapping.target.end
        }
        
        guard let note = self.note, startTime != nil && endTime != nil else { return segments }
        
        for segment in note.noteTracks[0] {
            if segment.timeMapping.target.start <= startTime! {
                // add to array if before passage to be removed
                segments.append(segment)
            } else if segment.timeMapping.target.end >= endTime! {
                // add to array if after passage to be removed
                segments.append(segment)
            }
        }
        
        return segments
    }
    var clipboard: [NoteSegment]? = nil
    var isCollapsed: Bool {
        return focus == anchor || (focus == nil && anchor == nil)
    }
    var direction: SelectionDirection {
        if let anchor = self.anchor, let focus = self.focus, focus.getIndex() >= anchor.getIndex() {
            return .forwards
        }
        
        return .backwards
    }
    var isReplacingSelection = false
    
    // MARK: - Initializer

    private override init() {}
    
    // MARK: - Methods
    
    func checkRep() {
        let result = true
        
        // We either have no anchor and focus or both are set, but never one or the other?
        
        // if we don't have selection, we have a cursor and we only have the anchor positioned at the end of the anchor segment
        
        if !result {
            fatalError("===== [Error] SelectionCursor Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Action Methods
    
    func collapse(toAnchorSegment: Bool = false) {
        if toAnchorSegment {
            focus = anchor
        } else {
            anchor = focus
        }
        
        checkRep()
    }
    
    // When playing note
    // When playing echo
    // ballistic movement
    //
    // moves as a cursor
    func moveCursor(time: CMTime) {
        self.collapse()
        
        if let note = note, let segment = note.getSegment(forTrackTime: time) {
            // update model
            self.setAnchor(segment: segment)
            self.focus = nil
            
            // update view
            if let selectionRange = self.selectionRange, let textView = self.textView {
                self.moveCaret(textPosition: selectionRange.toTextRange(textInput: textView)!.end)
            } else {
                fatalError("===== [Error] There was a problem updating SelectionCursor =====")
            }
        }
        
        checkRep()
    }

    // ballistic movement
    //
    // moves as a cursor
    func moveCursor(trackIndex: Int, segmentIndex: Int) {
        self.collapse()
        
        if let note = note {
            // update model
            let segment = note.noteTracks[0][segmentIndex]
            self.setAnchor(segment: segment)
            self.focus = nil
            
            // update view
            if let selectionRange = self.selectionRange, let textView = self.textView {
                self.moveCaret(textPosition: selectionRange.toTextRange(textInput: textView)!.end)
            } else {
                fatalError("===== [Error] There was a problem updating SelectionCursor =====")
            }
        }
        
        checkRep()
    }
    
    func isSegmentInRange(segment: NoteSegment) -> Bool {
        guard let note = self.note, let selectionRange = self.selectionRange else { return false }

        let segmentRange = note.getSegmentTextRange(of: segment)
        
        if let segmentRange = segmentRange {
            return NSIntersectionRange(selectionRange, segmentRange).length > 0
        }
        
        return false
    }
    
    func playNeighborhood() {
            var startTime: CMTime?
            var endTime: CMTime?
            if let focus = self.focus, let anchor = self.anchor, self.direction == .backwards {
                startTime = focus.getSentence().timeRange.start
                endTime = anchor.getSentence().timeRange.end
            } else if let focus = self.focus, let anchor = self.anchor {
                startTime = anchor.getSentence().timeRange.start
                endTime = focus.getSentence().timeRange.end
            }
            
            if let note = self.note, let startTime = startTime, let endTime = endTime {
                note.play(
                    from: startTime,
                    to: endTime,
                    onStartHandler: {
                        DispatchQueue.main.async {
                            if !note.isListeningForSpeech {
                                note.vc!.playAudioButton.setTitle(ViewController.PAUSE_NOTE_LABEL, for: .normal)
                            }
                        }
                    },
                    secondElapseHandler: {
                        DispatchQueue.main.async {
                            if !note.isListeningForSpeech {
                                note.vc!.navigationItem.title = "\(Utils.formattedTime(time: Float((note.player.currentTime().seconds))))/\(note.duration.seconds)"
                            }
                        }
                    },
                    segmentBoundaryHandler: {
                        DispatchQueue.main.async {
                            if let segment = note.vc!.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let range = note.vc!.note.getSegmentTextRange(of: segment) {
                                note.vc!.updateUIText(range: range)
                            }
                        }
                    }, onFinishHandler: {
                        DispatchQueue.main.async {
                            note.vc!.updateUIText()
                            note.vc!.note.player.replaceCurrentItem(with: nil)
                            if !note.isListeningForSpeech {
                                note.vc!.navigationItem.title = ""
                                note.vc!.playAudioButton.setTitle(ViewController.PLAY_NOTE_LABEL, for: .normal)
                            }
                        }
                    }
                )
            }
            
            checkRep()
        }
        
        func playSelection() {
            var startTime: CMTime?
            var endTime: CMTime?
            if let focus = self.focus, let anchor = self.anchor, self.direction == .backwards {
                startTime = focus.timeMapping.target.start
                endTime = anchor.timeMapping.target.end
            } else if let focus = self.focus, let anchor = self.anchor {
                startTime = anchor.timeMapping.target.start
                endTime = focus.timeMapping.target.end
            }
            
            if let note = self.note, let startTime = startTime, let endTime = endTime {
                note.play(
                    from: startTime,
                    to: endTime,
                    onStartHandler: {
                        DispatchQueue.main.async {
                            if !note.isListeningForSpeech {
                                note.vc!.playAudioButton.setTitle(ViewController.PAUSE_NOTE_LABEL, for: .normal)
                            }
                        }
                    },
                    secondElapseHandler: {
                        DispatchQueue.main.async {
                            if !note.isListeningForSpeech {
                                note.vc!.navigationItem.title = "\(Utils.formattedTime(time: Float((note.player.currentTime().seconds))))/\(note.duration.seconds)"
                            }
                        }
                    },
                    segmentBoundaryHandler: {
                        DispatchQueue.main.async {
                            if let segment = note.vc!.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let range = note.vc!.note.getSegmentTextRange(of: segment) {
                                note.vc!.updateUIText(range: range)
                            }
                        }
                    }, onFinishHandler: {
                        DispatchQueue.main.async {
                            note.vc!.updateUIText()
                            note.vc!.note.player.replaceCurrentItem(with: nil)
                            if !note.isListeningForSpeech {
                                note.vc!.navigationItem.title = ""
                                note.vc!.playAudioButton.setTitle(ViewController.PLAY_NOTE_LABEL, for: .normal)
                            }
                        }
                    }
                )
            }

            checkRep()
        }
        
        // micro-movement
        // requires there to be a selection
        func shift(shiftDirection: SelectionShiftDirection, by count: Int = 1) {
            self.shiftAnchorSegment(shiftDirection: shiftDirection, by: count)
            self.shiftFocusSegment(shiftDirection: shiftDirection, by: count)
            checkRep()
        }
        
        func shiftFocusSegment(shiftDirection: SelectionShiftDirection, by count: Int = 1) {
            // prevent illegal moves
            if let note = note, let anchor = self.anchor, let focus = self.focus {
                let numSegments = note.noteTracks[0].count

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
                    let nextFocus = note.noteTracks[0][nextFocusIndex]
                    self.setFocus(segment: nextFocus)
                } else {
                    fatalError("===== [Error] There was a problem computing new focus segment index =====")
                }
            }
            
            checkRep()
        }
        
        func shiftAnchorSegment(shiftDirection: SelectionShiftDirection, by count: Int = 1) {
            // prevent illegal moves
            if let note = note, let anchor = self.anchor, let focus = self.focus {
                let numSegments = note.noteTracks[0].count
                
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
                    let nextAnchor = note.noteTracks[0][nextAnchorIndex]
                    self.setAnchor(segment: nextAnchor)
                } else {
                    fatalError("===== [Error] There was a problem computing new anchor segment index =====")
                }
            }
            
            checkRep()
        }
        
        func expand(by count: Int = 1) {
            let anchorShiftDirection: SelectionShiftDirection = self.direction == .forwards ? .previous : .next
            let focusShiftDirection: SelectionShiftDirection = self.direction == .forwards ? .next : .previous
            self.shiftAnchorSegment(shiftDirection: anchorShiftDirection, by: count)
            self.shiftFocusSegment(shiftDirection: focusShiftDirection, by: count)
            
            checkRep()
        }
        
        func reduce(by count: Int = 1) {
            let anchorShiftDirection: SelectionShiftDirection = self.direction == .forwards ? .next : .previous
            let focusShiftDirection: SelectionShiftDirection = self.direction == .forwards ? .previous : .next
            self.shiftAnchorSegment(shiftDirection: anchorShiftDirection, by: count)
            self.shiftFocusSegment(shiftDirection: focusShiftDirection, by: count)

            checkRep()
        }
        
        func delete() {
            if let note = note, let selectionTimeRange = self.selectionTimeRange {
                // remove passage
                note.removePassage(range: selectionTimeRange)
                
                // move cursor
                self.moveCursor(time: selectionTimeRange.start)
            }

            // play to hear difference
            checkRep()
        }
        
        func replace() {
            if let note = note {
                // delete selection
                self.delete()

                // signal that we'll be replacing selection
                self.isReplacingSelection = true
                
                // Start recording to replace segment
                note.startListeningForSpeech(soundIntensityHandler: { power in
                    if let power = power {
                        DispatchQueue.main.async {
                            let height = CGFloat(Utils.normalizedPower(power: power, minPower: note.minPower)) * note.vc!.view.safeAreaLayoutGuide.layoutFrame.height
                            let soundIntensityHeight: CGFloat = CGFloat(min(height, note.vc!.view.safeAreaLayoutGuide.layoutFrame.height))
                            note.vc!.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                        }
                    }
                }, onStartHandler: {
                    note.vc!.startRecordingUITimer(recording: true)
                })
            }

            // play to hear difference
            checkRep()
        }
        
        func copySelection() {
            self.clipboard = self.selectionSegments
            
            checkRep()
        }
        
        func cutSelection() {
            // copy selection
            self.copySelection()
            
            // delete selection
            self.delete()

            // play to hear difference
            checkRep()
        }
        
        func export() {
            let selectionFilename = "note-\(UUID().uuidString)"
            if let note = self.note, let selectionTimeRange = self.selectionTimeRange {
                Utils.exportNote(
                    note: note,
                    filename: selectionFilename,
                    fileType: note.fileType,
                    timeRange: selectionTimeRange
                ) {
                    // Handler
                }
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
        guard let note = self.note else { return }
        let location = self.textView!.offset(from: self.textView!.beginningOfDocument, to: textRange.start)
        let length = self.textView!.offset(from: textRange.start, to: textRange.end)
        let selectionRange = NSRange(location: location, length: length)
        
        let noteText = note.getText()
        let rangeStringIndex = Range(selectionRange, in: noteText)
        
        if let rangeStringIndex = rangeStringIndex {
            let rangeText = noteText[rangeStringIndex]
            
            var focus: NoteSegment? = nil
            var anchor: NoteSegment? = nil
            for segment in note.noteTracks[0] {
                let segmentRange = note.findSegmentRange(segments: [segment], wholeText: noteText, rangeText: String(rangeText))
                if anchor == nil && segmentRange.lowerBound == rangeStringIndex.lowerBound {
                    anchor = segment
                }
                
                if focus == nil && segmentRange.lowerBound == rangeStringIndex.upperBound {
                    focus = segment
                }
                
                if anchor != nil && focus != nil {
                    self.anchor = anchor
                    self.focus = focus
                    break
                }
            }
        }
        
        self.moveCaret(textPosition: textRange.end)
        
        checkRep()
    }
    
    func setSelection(anchor: NoteSegment, focus: NoteSegment) {
        self.anchor = anchor
        self.focus = focus
        
        if let selectionRange = self.selectionRange, let textView = self.textView {
            self.moveCaret(textPosition: selectionRange.toTextRange(textInput: textView)!.end)
        } else {
            fatalError("===== [Error] There was a problem updating SelectionCursor =====")
        }

        checkRep()
    }
    
    func setNote(note: Note?) {
        if let note = note {
            self.note = note
        } else {
            self.note = nil
        }
        
        checkRep()
    }
    
    func setTextView(textView: UITextView?) {
        // store text view
        if let textView = textView {
            // remove any previous textview
            if let oldTextView = self.textView {
                oldTextView.removeObserver(self, forKeyPath: "selectedTextRange")
                oldTextView.delegate = nil
            }
            
            // Add new one
            self.textView = textView
            
            // Add Selection Observer
            self.textView!.addObserver(
                self,
                forKeyPath: "selectedTextRange",
                options: [.old, .new],
                context: nil
            )
            
            // Assign as text change delegate
            textView.delegate = self
        } else {
            // remove any previous textview
            if let oldTextView = self.textView {
                oldTextView.removeObserver(self, forKeyPath: "selectedTextRange")
                oldTextView.delegate = nil
            }
            
            // clear text view
            self.textView = nil
        }
    }
    
    func setCursorView(cursorView: UIView?) {
        // store cursor view
        if let cursorView = cursorView {
            // Add new one
            self.cursorView = cursorView
        } else {
            // clear text view
            self.cursorView = nil
        }
    }
    
    func setAnchor(segment: NoteSegment) {
        self.anchor = segment
        
        checkRep()
    }
    
    func setFocus(segment: NoteSegment) {
        self.focus = segment
        
        checkRep()
    }
    
    // MARK: - Getters
    
    func getNeighborhood() -> [NoteSegment] {
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
        
        guard let note = self.note, startTime != nil && endTime != nil else { return neighborhood }
        
        for segment in note.noteTracks[0] {
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
    
    func moveCaret(textPosition: UITextPosition) {
        let caretRect = self.textView!.caretRect(for: textPosition)
        let windowRect = self.textView!.convert(caretRect, to: nil)
        
        // compute x and y positions
        let xPos = windowRect.minX + CURSOR_X_POS_BUFFER
        let yPos = windowRect.minY + ((self.textView!.font!.lineHeight - self.textView!.font!.pointSize) / 2)
        let width = Utils.CURSOR_WIDTH

        // Create new cursor frame
        let frame: CGRect = CGRect(
            x: xPos,
            y: yPos,
            width: CGFloat(width),
            height: CGFloat(self.textView!.font!.lineHeight)
        )
        
        self.cursorView!.frame = frame
    }
    // MARK: - Key-Value Observer
        
    // Reference: https://stackoverflow.com/questions/8579400/whats-the-best-way-to-get-uitextfield-selection-changed-notifications
    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "selectedTextRange" {
            if let newSelectionRange = change?[.newKey] as? UITextRange {
                self.setSelection(textRange: newSelectionRange)
            }
        }
        
        // snap to end of word
    }
    
    // MARK: - Delegates
    
    // Reference: https://stackoverflow.com/questions/25064465/uitextview-data-change-swift
    // Reference: https://stackoverflow.com/questions/43166781/cursor-position-in-relation-to-self-view
    // Will not be called by programmatic changes: https://stackoverflow.com/questions/16115344/textviewdidchange-is-not-call-when-change-uitextview-inputview
    public func textViewDidChange(_ textView: UITextView) {
        if let note = note {
            self.moveCursor(trackIndex: note.activeTrack, segmentIndex: note.noteTracks[note.activeTrack].count - 1)
        }
    }
}

