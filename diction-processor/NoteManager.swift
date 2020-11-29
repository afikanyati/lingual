//
//  NoteManager.swift
//  diction-processor
//
//  Created by Afika Nyati on 11/5/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Speech
import Foundation

class NoteManager: NSObject {
    // MARK: - Notifications
    
    static let onCreatedNote = Notification.Name(Notifications.onCreatedNote.rawValue)
    static let onNoteDeleted = Notification.Name(Notifications.onNoteDeleted.rawValue)
    static let onSetNote = Notification.Name(Notifications.onSetNote.rawValue)
    static let onExecuteNoteAction = Notification.Name(Notifications.onExecuteNoteAction.rawValue)
    static let onNoteAudioExported = Notification.Name(Notifications.onNoteAudioExported.rawValue)
    static let onUndoManagerChange = Notification.Name(Notifications.onUndoManagerChange.rawValue)

    // MARK: - App Modules
    
    var state: StateManager
    var speechRecognition: SpeechRecognitionEngine
    var notifications: NotificationEngine
    var speechPlayer: SpeechPlayerEngine
    var speechSynthesis: SpeechSynthesisEngine
    var selectionCursor: SelectionCursor
    var uiManager: UIManager
    var pitchRecognition: PitchRecognitionEngine
    private let _undoManager = UndoManager()
    var undoManager: UndoManager {
        return _undoManager
    }
    
    // MARK: - Note Manager Properties
    
    private(set) var currentIndex: Int? = nil
    var currentNote: Note? {
        if let index = self.currentIndex {
            return self.state.activeNotes[index]
        }
        
        return nil
    }
    @objc dynamic var currentNoteUndoSnapshot: NoteSnapshot? = nil
    private(set) var noteChangeHandler: (() -> Void)? = nil
    
    /// Specifies whether note is currently running
    private(set) var isRunningNote = false
    /// Specifies whether note is currently walking
    private(set) var isWalkingNote = false
    /// Specifies whether note is currently paused walking
    private(set) var pausedWalkingNote = false
    /// Specifies whether note is currently paused running
    private(set) var pausedRunningNote = false
    /// Specifies whether note is currently walking
    private(set) var walkingRange: Range<Int>?
    /// Specifies whether note is currently walking
    private(set) var walkingIndex: Int = 0
    /// Stores a reference to a timer that drives walking loop behavior
    private(set) var walkingTimer: Timer?
    /// Stores a reference to a timer that drives delay of walk loop intiation
    private(set) var walkLoopDelayTimer: Timer?
    /// Stores a reference to a timer that drives delayed echo while walking
    private(set) var echoDelayTimer: Timer?
    /// Stores a reference to a timer that drives passage running
    private(set) var runningTimer: Timer?
    /// Stores whether note is currently being exported
    private(set) var isExportingNote = false
    
    // MARK: - Initialization and Deinitialization
    
    init(
        state: StateManager,
        speechRecognition: SpeechRecognitionEngine,
        notifications: NotificationEngine,
        speechPlayer: SpeechPlayerEngine,
        speechSynthesis: SpeechSynthesisEngine,
        selectionCursor: SelectionCursor,
        uiManager: UIManager,
        pitchRecognition: PitchRecognitionEngine
    ) {
        print("===== Note Manager: Initialization =====")
        self.state = state
        self.speechRecognition = speechRecognition
        self.notifications = notifications
        self.speechPlayer = speechPlayer
        self.speechSynthesis = speechSynthesis
        self.selectionCursor = selectionCursor
        self.uiManager = uiManager
        self.pitchRecognition = pitchRecognition
        
        super.init()
        
        print("\tSetting modules in notes")
        self.setNoteModules() // Removing this will not show preview text on notes within note table
        
        self.configureNotificationObservers()
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)

        // remove observer from snapshot
        self.removeObserver(
            self,
            forKeyPath: "currentNoteUndoSnapshot",
            context: nil
        )
    }
    
    // MARK: - Validation
    
    func checkRep() {
        var result = true
        
        // exporting note can only be active if we have a current note
        result = result && ((self.currentNote != nil && self.isExportingNote) || !self.isExportingNote)
        
        // cannot pause walking if walking is inactive
        result = result && (!self.pausedWalkingNote || self.isWalkingNote)
        
        // cannot pause running if walking is inactive
        result = result && (!self.pausedRunningNote || self.isRunningNote)
        
        if !result {
            fatalError("===== [Error] Note Manager Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
        // Note Manager
        self.addObserver(
            self,
            forKeyPath: "currentNoteUndoSnapshot",
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
        
        // State Manager
        notificationCenter.addObserver(
            self,
            selector: #selector(onFetchedNotes(notification:)),
            name: StateManager.onFetchedNotes,
            object: nil
        )
    }
    
    @objc func onFetchedNotes(notification: Notification) {
        print("===== Note Manager: On Fetched Notes =====")
        print("\tSetting modules in notes")
        self.setNoteModules()
    }
    
    @objc func onProcessedVoiceCommand(notification: Notification) {
        print("===== Note Manager: On Processed Voice Command =====")
        let command = notification.userInfo!["command"] as! String
        var handler: (() -> Void)?
        if notification.userInfo!["handler"] != nil {
            handler = notification.userInfo!["handler"] as? () -> Void
        }
        
        if voiceCommandEngine.isNoteManagerCommand(command: command) && self.currentNote == nil && command != "start note" {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            
            return
        }

        switch (command) {
        case "play note", "play selection":
            self.playNote(voiceCommand: true, onFinishHandler: handler)
        case "pause note":
            self.pauseNote(voiceCommand: true, handler: handler)
        case "start note":
            if let _ = Utils.getNavigationController()?.visibleViewController as? NoteTableViewController, let _ = self.currentNote {
                print("\tFound existing note while in Note List after receving 'start note' via voice command. Remove it to trigger new note creation.")
                self.setCurrentNote()
            }
            self.startNote(voiceCommand: true, handler: handler)
        case "create note":
            self.startNote(voiceCommand: true, handler: handler)
        case "stop note":
            if self.speechPlayer.isPlayingNote {
                self.stopPlayingNote(voiceCommand: true, handler: handler)
            } else if let _ = self.currentNote {
                self.stopNote(voiceCommand: true, handler: handler)
            }
        case "resume note":
            self.resumeNote(voiceCommand: true, handler: handler)
        case "echo note":
            self.echoNote(voiceCommand: true, handler: handler)
        case "pause echo":
            self.pauseEcho(voiceCommand: true, handler: handler)
        case "stop echo":
            self.stopEcho(voiceCommand: true, handler: handler)
        case "delete selection":
            self.deleteSelection(voiceCommand: true, handler: handler)
        case "update selection":
            self.updateSelection(voiceCommand: true, handler: handler)
        case "copy selection":
            self.copySelection(voiceCommand: true, handler: handler)
        case "cut selection":
            self.cutSelection(voiceCommand: true, handler: handler)
        case "increase selection rate":
            self.increaseRateSelection(voiceCommand: true, handler: handler)
        case "decrease selection rate":
            self.decreaseRateSelection(voiceCommand: true, handler: handler)
        case "export", "export note", "export selection":
            self.exportNote(voiceCommand: true, handler: handler)
        case "pause playback":
            self.pauseNote(voiceCommand: true, handler: handler)
        case "resume echo":
            self.echoNote(voiceCommand: true, handler: handler)
        case "edit note":
            self.editNote(voiceCommand: true, handler: handler)
        case "play commit":
            self.playCommit(voiceCommand: true, onFinishHandler: handler)
        case "skip backward":
            self.skipBackward(voiceCommand: true, handler: handler)
        case "skip forward":
            self.skipForward(voiceCommand: true, handler: handler)
        case "stop playback":
            self.stopPlayingNote(voiceCommand: true, handler: handler)
        case "pause":
            if let _ = self.currentNote, self.speechPlayer.isPlayingNote {
                self.pauseNote(voiceCommand: true, handler: handler)
            } else if let _ = self.currentNote, self.speechSynthesis.isPlayingEcho {
                self.pauseEcho(voiceCommand: true, handler: handler)
            } else if let note = self.currentNote, self.isRunningNote {
                // Play Sound
                soundEngine.voiceCommandAccept()

                note.pauseRun(handler: handler)
            }
        case "stop":
            if let _ = self.currentNote, self.speechPlayer.isPlayingNote {
                self.stopPlayingNote(voiceCommand: true, handler: handler)
            } else if let _ = self.currentNote, self.speechSynthesis.isPlayingEcho {
                self.stopEcho(voiceCommand: true, handler: handler)
            } else if let note = self.currentNote, self.isRunningNote {
                // Play Sound
                soundEngine.voiceCommandAccept()
                
                note.pauseRun(handler: handler)
            }
        case "delete":
            if self.selectionCursor.hasSelection {
                self.deleteSelection(voiceCommand: true, handler: handler)
            } else if let _ = self.currentNote {
                self.deleteNote(voiceCommand: true, handler: handler)
            }
        case "echo":
            if self.selectionCursor.hasSelection {
                self.echoNote(voiceCommand: true, handler: handler)
            } else if let _ = self.currentNote {
                self.echoNote(voiceCommand: true, handler: handler)
            }
        case "paste clipboard":
            self.pasteClipboard(voiceCommand: true, handler: handler)
        case "resume playback":
            if self.speechRecognition.pausedListeningForSpeech {
                self.notifications.executeError(
                    text: "Note not paused.",
                    voiceCommand: true,
                    handler: handler
                )
                return
            }
            
            self.startNote(voiceCommand: true, handler: handler)
        case "select commit":
            self.selectCommit(
                handler: handler
            )
        case "walk commit":
            self.walkCommit(
                handler: handler
            )
        case "run commit":
            self.runCommit(
                handler: handler
            )
        case "rollback commit":
            self.rollbackCommit(
                handler: handler
            )
        case "open selection":
            self.openSelection(
                handler: handler
            )
        case "remove selection":
            self.removeSelection(
                handler: handler
            )
        case "cancel":
            if self.selectionCursor.isUpdatingSelection && !self.selectionCursor.isPromptingForUpdateAcceptance {
                self.cancelUpdateSelection(
                    voiceCommand: true,
                    handler:  {
                        self.notifications.executeFeedback(
                            visualMessage: "Canceled!",
                            audioMessage: "Command canceled",
                            withHaptics: true
                        )
                        handler?()
                    }
                )
            }
        case "shift anchor left":
            self.shiftAnchor(
                direction: .left,
                handler: handler
            )
        case "shift anchor right":
            self.shiftAnchor(
                direction: .right,
                handler: handler
            )
        case "shift focus left":
            self.shiftFocus(
                direction: .left,
                handler: handler
            )
        case "shift focus right":
            self.shiftFocus(
                direction: .right,
                handler: handler
            )
        case "shift forward":
            self.shiftSelection(
                direction: .right,
                handler: handler
            )
        case "shift backward":
            self.shiftSelection(
                direction: .left,
                handler: handler
            )
        case "expand selection":
            self.expandSelection(
                handler: handler
            )
        case "reduce selection":
            self.reduceSelection(
                handler: handler
            )
        case "echo commit":
            self.echoCommit(
                handler: handler
            )
        case "echo previous sentence":
            self.echoPreviousSentence(
                handler: handler
            )
        case "play previous sentence":
            self.playPreviousSentence(
                handler: handler
            )
        case "run note", "run selection":
            self.runNote(voiceCommand: true, handler: handler)
        case "walk note", "walk selection":
            self.walkNote(voiceCommand: true, handler: handler)
        case "next element":
            self.walkNextElement(voiceCommand: true, handler: handler)
        case "previous element":
            self.walkPreviousElement(voiceCommand: true, handler: handler)
        case "pause run":
            self.pauseRun(voiceCommand: true, handler: handler)
        case "exit mode":
            self.exitWalkRun(voiceCommand: true, handler: handler)
        case "undo":
            self.undo(handler: handler)
        case "redo":
            if !self.selectionCursor.isUpdatingSelection && !self.selectionCursor.isPromptingForUpdateAcceptance {
                self.redo(handler: handler)
            }
        default:
            // Do Nothing
            break
        }
    }
    
    // MARK: - Key-Value Observer
    
    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        print("===== Note Manager: Observe Value =====")

        if keyPath == "currentNoteUndoSnapshot" {
            print("\tKeyPath: currentNoteUndoSnapshot")
            if let newSnapshot = change?[.newKey] as? NoteSnapshot,
               let _ = change?[.oldKey] as? NoteSnapshot
            {
                print("\tNew Note Snapshot Received! Save to state")
                let duplicateNote = newSnapshot.note.duplicate()
                
                // Handle Current Clip UID
                if let note = self.currentNote,
                   duplicateNote.currentClipUID == nil &&
                    note.currentClipUID != nil &&
                    self.speechRecognition.isListeningForSpeech
                {
                    print("\tDuplicate note has no currentClipUID. Give it existing note's currentClipUID...")
                    let currentClipUID = note.currentClipUID
                    duplicateNote.setCurrentClipUID(uid: currentClipUID)
                }
                
                // Handle Record Start Date
                if let note = self.currentNote,
                   duplicateNote.recordStartDate == nil &&
                    note.recordStartDate != nil &&
                    self.speechRecognition.isListeningForSpeech
                {
                    print("\tDuplicate note has no recordStartDate. Give it existing note's recordStartDate...")
                    let recordStartDate = note.recordStartDate
                    duplicateNote.setRecordStartDate(date: recordStartDate)
                }
                
                // Handle Record File
                if let note = self.currentNote,
                   duplicateNote.recordFile == nil &&
                    note.recordFile != nil &&
                    self.speechRecognition.isListeningForSpeech
                {
                    print("\tDuplicate note has no recordFile. Give it existing note's recordFile...")
                    let recordFile = note.recordFile
                    duplicateNote.setRecordFile(file: recordFile)
                }

                // Set Note
                self.state.saveNote(note: duplicateNote) // we duplicate so there's no memory leaks/pointers to same memory locations
                
                print("\tSet Node Modules...")
                self.setNoteModules(index: self.currentIndex)
                
                print("\tUpdate selection carets...")
                if let anchorCaret = newSnapshot.selectionAnchorCaret {
                    print("\tUpdated selection achor:")
                    print("\tFrom: ", self.selectionCursor.anchorCaret ?? "nil")
                    print("\tTo: ", anchorCaret)
                    self.selectionCursor.setAnchorCaret(caret: anchorCaret.duplicate())
                } else {
                    print("\tUpdated selection anchor:")
                    print("\tFrom: ", self.selectionCursor.anchorCaret ?? "nil")
                    print("\tTo: nil")
                    self.selectionCursor.setAnchorCaret()
                }
                
                if let focusCaret = newSnapshot.selectionFocusCaret {
                    print("\tUpdated selection focus:")
                    print("\tFrom: ", self.selectionCursor.focusCaret ?? "nil")
                    print("\tTo: ", focusCaret)
                    self.selectionCursor.setFocusCaret(caret: focusCaret.duplicate())
                } else {
                    print("\tUpdated selection focus:")
                    print("\tFrom: ", self.selectionCursor.focusCaret ?? "nil")
                    print("\tTo: nil")
                    self.selectionCursor.setFocusCaret()
                }
                
                if let cachedAnchorCaret = newSnapshot.selectionCachedAnchorCaret {
                    print("\tUpdated selection cached anchor:")
                    print("\tFrom: ", self.selectionCursor.cachedAnchorCaret ?? "nil")
                    print("\tTo: ", cachedAnchorCaret)
                    self.selectionCursor.setCachedAnchorCaret(caret: cachedAnchorCaret.duplicate())
                } else {
                    print("\tUpdated selection cached anchor:")
                    print("\tFrom: ", self.selectionCursor.cachedAnchorCaret ?? "nil")
                    print("\tTo: nil")
                    self.selectionCursor.setCachedAnchorCaret()
                }
                
                if let note = self.currentNote {
                    print("\tUpdate View with text: '\(note.getText())'")
                    note.handleOnSpeechUpdate(text: note.getText())
                }
                
                if let noteChangeHandler = self.noteChangeHandler {
                    print("\tRunning Save Handler...")
                    noteChangeHandler()
                    self.noteChangeHandler = nil
                }
            } else {
                print("\tNo new snapshot...")
            }
        }
    }
    
    // MARK: - Methods
    
    func setNoteModules(index: Int? = nil) {
        print("===== Note Manager: Set Note Modules =====")
        let handleNote: (_ note: Note) -> Void = { note in
            print("\tHandled Note UID: ", note.uid)
            if note.state == nil {
                note.setState(state: self.state)
            }
            if note.speechSynthesis == nil {
                note.setSpeechSynthesis(speechSynthesis: self.speechSynthesis)
            }
            if note.speechRecognition == nil {
                note.setSpeechRecognition(speechRecognition: self.speechRecognition)
            }
            if note.speechPlayer == nil {
                note.setSpeechPlayer(speechPlayer: self.speechPlayer)
            }
            if note.selectionCursor == nil {
                note.setSelectionCursor(selectionCursor: self.selectionCursor)
            }
            if note.pitchRecognition == nil {
                note.setPitchRecognition(pitchRecognition: self.pitchRecognition)
            }
            if note.noteManager == nil {
                note.setNoteManager(noteManager: self)
            }
            if note.notifications == nil {
                note.setNotifications(notifications: self.notifications)
            }
        }
        
        if let index = index {
            print("\tHandle individual note.")
            let note = self.state.activeNotes[index]
            handleNote(note)
        } else {
            print("\tHandle all notes.")
            for note in self.state.activeNotes {
                handleNote(note)
            }
        }
    }
    
    func getNote(uid: String) -> Note? {
        for note in self.state.activeNotes {
            if note.uid == uid {
                return note
            }
        }
        
        return nil
    }
    
    func createNote(voiceCommand: Bool = false, withListening: Bool = false, handler: (() -> Void)? = nil) -> String {
        print("===== Note Manager: Create Note =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }

        let uid = UUID().uuidString
        let note = Note(
            uid: uid,
            filename: "note-\(uid)",
            creatorUID: self.state.speaker.uid
        )
        
        print("\tNew Note UID: ", uid)
        
        // Add new note
        let index = self.state.appendNote(note: note)
        
        self.setNoteModules(index: index)
        
        NotificationCenter.default.post(
            name: NoteManager.onCreatedNote,
            object: nil,
            userInfo: [:]
        )
        
        if withListening {
            // Start Listening Immediately
            self.setCurrentNote(index: index)
            
            self.notifications.executeFeedback(
                visualMessage: "Create Note",
                audioMessage: "new note created",
                withHaptics: true,
                delay: 1
            )
            
            self.startNote(voiceCommand: voiceCommand, handler: handler)
        } else {
            self.notifications.executeFeedback(
                visualMessage: "Create Note",
                audioMessage: "new note created",
                withHaptics: true,
                delay: 1
            )
            
            handler?()
        }
        
        checkRep()
        
        return uid
    }
    
    @objc func deleteNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Delete Note (using screen button or voice command) =====")
        guard let index = self.currentIndex else {
            self.notifications.executeError(text: "No note selected")
            return
        }
        
        self.deleteNote(index: index, handler: handler)
    }
    
    func deleteNote(index: Int, withConfirmation: Bool = true, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Delete Note (using index) =====")
        
        let handleDelete: (_ handler: (() -> Void)?) -> Void = { [weak self] handler in
            // Reset Selection Cursor
            self?.selectionCursor.reset()
            
            // Set Note to Deleted
            let noteUID = self!.state.activeNotes[index].uid
            if let note = self?.getNote(uid: noteUID) {
                note.setIsDeleted(to: true)
            }
            
            // save changes
            self?.state.save()
            
            // Handle Note Clips
    //        self.state.manageClipRemoval(note: note)
            
            // Remove Current Note
            if index == self?.currentIndex {
                self?.setCurrentNote()
            }
            
            NotificationCenter.default.post(
                name: NoteManager.onNoteDeleted,
                object: nil,
                userInfo: [:]
            )
            
            self?.notifications.executeFeedback(
                visualMessage: "Delete Note",
                audioMessage: "note deleted",
                withHaptics: true,
                delay: 0
            )
            
            handler?()
            
            self?.checkRep()
            
            // Play sound
            soundEngine.delete()
            
            // Give haptic feedback
    //        hapticEngine.mediumImpact()
            hapticEngine.success()
        }
        
        // Find note
        if withConfirmation {
            print("\tHandle delete with confirmation dialog.")
            
            let dialogActions = [
                DialogAction(
                    title: "Delete",
                    voiceCommand: "delete",
                    feedbackVisualMessage: "Delete Note",
                    feedbackAudioMessage: "note deleted",
                    style: .default,
                    handler: { action in
                        handleDelete(handler)
                    }
                ),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: "cancel",
                    feedbackVisualMessage: "Canceled!",
                    feedbackAudioMessage: "Command canceled.",
                    style: .cancel,
                    handler: { action in
                        handler?()
                    }
                )
            ]
            
            let dialogItem = DialogItem(
                title: "Confirm Delete",
                message: "Are you sure you want to delete note? Say 'delete' to continue, or 'cancel' to dismiss.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            self.uiManager.presentDialog(dialogItem: dialogItem)
        } else if !withConfirmation {
            print("\tHandle delete without confirmation dialog.")
            handleDelete(handler)
        } else {
            print("\t[Error] There was a problem deleting note at index \(index). Unable to find it.")
        }
    }
    
    func deleteNote(uid: String, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Delete Note (using uid) =====")

        // Find note
        let note = self.getNote(uid: uid)
        if let note = note {

            // Set Note to Deleted
            note.setIsDeleted(to: true)
            
            // save changes
            self.state.save()
            
            // Handle Note Clips
    //        self.state.manageClipRemoval(note: note)
            
            NotificationCenter.default.post(
                name: NoteManager.onNoteDeleted,
                object: nil,
                userInfo: [:]
            )
            
            self.notifications.executeFeedback(
                visualMessage: "Delete Note",
                audioMessage: "note deleted",
                withHaptics: true,
                delay: 0
            )
            handler?()
            checkRep()
            
            // Play sound
            soundEngine.delete()
            
            // Give haptic feedback
    //        hapticEngine.mediumImpact()
            hapticEngine.success()
        } else {
            print("\t[Error] There was a problem deleting note with uid \(uid). Unable to find it.")
        }
    }

    func startNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Start Note =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if self.speechRecognition.isListeningForSpeech {
            self.notifications.executeError(
                text: "Note already started.",
                voiceCommand: voiceCommand
            )
            
            return
        }
        
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if self.speechRecognition.session.recordPermission != .granted || authStatus != .authorized {
            let dialogActions = [
                DialogAction(
                    title: "Grant Permission",
                    voiceCommand: "grant permission",
                    feedbackVisualMessage: "Permission Granted!",
                    feedbackAudioMessage: "permission granted",
                    style: .default,
                    handler: { action in
                    self.speechRecognition.requestPermissions(handler: {
                        self.speechRecognition.configureListeningForWakePhrase()
                    })
                }),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: "cancel",
                    feedbackVisualMessage: "Canceled!",
                    feedbackAudioMessage: "Command canceled.",
                    style: .cancel,
                    handler: nil
                )
            ]
            
            let dialogItem = DialogItem(
                title: "Speech Recognition Permission Denied",
                message: "App requires permission to continue. Say 'grant permission' to continue, or 'cancel' to dismiss.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            self.uiManager.presentDialog(dialogItem: dialogItem)
            
            return
        }
        
        if authStatus == .authorized && self.speechRecognition.session.recordPermission == .granted {
            if let _ = self.currentNote, !self.speechRecognition.isListeningForSpeech && !self.isExportingNote {
                if  !self.speechRecognition.isListeningForCommands {
                    // User switched off listening with the button
                    // Change button to normal again
                }
                
                if voiceCommand {
                    // Play Sound
                    soundEngine.voiceCommandAccept()
                }
                
                print("\tStarting Note...")
                self.speechRecognition.startListeningForSpeech() {
                    self.notifications.executeFeedback(
                        visualMessage: "Start Note",
                        audioMessage: "note started",
                        withHaptics: true
                    )
                    
                    handler?()
                }
            } else if self.currentNote == nil && !self.speechRecognition.isListeningForSpeech {
                print("\tCreating new note...")
                let _ = self.createNote(voiceCommand: voiceCommand, withListening: true, handler: handler)
            } else {
                if self.speechRecognition.isListeningForSpeech {
                    self.notifications.executeError(
                        text: "Note already started.",
                        voiceCommand: voiceCommand,
                        handler: handler
                    )
                } else {
                    self.notifications.executeError(
                        text: "Wait until note export completion.",
                        voiceCommand: voiceCommand,
                        handler: handler
                    )
                }
                print("\t[Error] There was a problem starting note. System does not have record permissions.")
            }
        } else {
            self.notifications.executeError(
                text: "Unable to start note.",
                voiceCommand: voiceCommand
            )
            print("\t[Error] There was a problem starting note. System does not have record permissions.")
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func resumeNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Resume Note =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let _ = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if self.speechRecognition.isListeningForSpeech && self.speechRecognition.pausedListeningForSpeech && self.speechRecognition.isListeningForCommands {
            if voiceCommand {
                // Play Sound
                soundEngine.voiceCommandAccept()
            }

            self.speechRecognition.startListeningForSpeech() {
                self.notifications.executeFeedback(
                    visualMessage: "Resume Note",
                    audioMessage: "note resumed",
                    withHaptics: true,
                    delay: 0
                )
                handler?()
            }
        } else {
            self.notifications.executeError(
                text: "No ongoing note.",
                handler: handler
            )
            return
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func editNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Edit Note =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if note.noteSegments.count == 0 {
            self.notifications.executeError(
                text: "No existing note.",
                voiceCommand: voiceCommand,
                handler: handler
            )
        }
        
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if self.speechRecognition.session.recordPermission != .granted || authStatus != .authorized {
            let dialogActions = [
                DialogAction(
                    title: "Grant Permission",
                    voiceCommand: "grant permission",
                    feedbackVisualMessage: "Permission Granted!",
                    feedbackAudioMessage: "permission granted",
                    style: .default,
                    handler: { action in
                    self.speechRecognition.requestPermissions() {
                        self.speechRecognition.configureListeningForWakePhrase()
                    }
                }),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: "cancel",
                    feedbackVisualMessage: "Canceled!",
                    feedbackAudioMessage: "Command canceled.",
                    style: .cancel,
                    handler: nil
                )
            ]
            
            let dialogItem = DialogItem(
                title: "Speech Recognition Permission Denied",
                message: "App requires permission to continue. Say 'grant permission' to continue, or 'cancel' to dismiss.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            self.uiManager.presentDialog(dialogItem: dialogItem)
            
            handler?()
            return
        }
        
        if authStatus == .authorized && self.speechRecognition.session.recordPermission == .granted {
            if !self.speechRecognition.isListeningForSpeech && !self.isExportingNote {
                if voiceCommand {
                    // Play Sound
                    soundEngine.voiceCommandAccept()
                }
                print("\tStarting Note...")
                self.speechRecognition.startListeningForSpeech() {
                    self.notifications.executeFeedback(
                        visualMessage: "Edit Note",
                        audioMessage: "note editing started",
                        withHaptics: true,
                        delay: 0
                    )
                    handler?()
                }
            } else {
                self.notifications.executeError(
                    text: "Unable to start note.",
                    voiceCommand: voiceCommand,
                    handler: handler
                )
                print("\t[Error] There was a problem starting note. System does not have record permissions.")
            }
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func stopNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Stop Note =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if self.speechRecognition.isListeningForSpeech && !self.isExportingNote {
            print("\tStopping Note...")
            if voiceCommand {
                // No sound here
                // We omit sound for stopping note
            }

            self.speechRecognition.stopListeningForSpeech() {
                // Perform finish cleanup
                // We handle finish for voice commands within Note
                // We might also get a call fro within note
                // if we receive final speech update from speech recognition engine
                note.handleFinish(normalize: true)
                
                // Present feedback
                self.notifications.executeFeedback(
                    visualMessage: "Stop Note",
                    audioMessage: "note stopped",
                    withHaptics: true,
                    delay: 0
                )
                
                handler?()
            }
        } else {
            if !self.speechRecognition.isListeningForSpeech {
                self.notifications.executeError(
                    text: "No ongoing note.",
                    voiceCommand: voiceCommand,
                    handler: handler
                )
            } else {
                self.notifications.executeError(
                    text: "Wait until note export completion.",
                    voiceCommand: voiceCommand,
                    handler: handler
                )
            }
            print("\t[Error] There was a problem stopping note. We're not listening for speech or are exporting note.")
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    // Should never be called when headphones on while we have a selection
    // Will be looping selection and have isPlayingNote set to true
    // Which should hide playButton
    func playNote(from startTime: CMTime = CMTime.zero, voiceCommand: Bool = false, onStartHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
        print("===== Note Manager: Play \(self.selectionCursor.hasSelection ? "Selection" : "Note") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: onFinishHandler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let playSegments: (_ segments: [NoteSegment]) -> Void = { segments in
            self.speechPlayer.play(
                segments: segments,
                onStartHandler: onStartHandler,
                onFinishHandler: onFinishHandler
            )
        }
        
        let executePlay = {
            if self.pausedWalkingNote || self.pausedRunningNote {
                print("\tPlay \(self.pausedWalkingNote ? "walking" : "running") range.")
                playSegments(Array(note.noteSegments[self.walkingRange!]))
            } else if let selectionSegments = self.selectionCursor.selectionSegments, self.selectionCursor.hasSelection {
                print("\tPlay selection.")
                playSegments(selectionSegments)
            } else {
                print("\tPlay note from: \(startTime.seconds)")
                self.speechPlayer.play(
                    note: note,
                    from: startTime,
                    onStartHandler: onStartHandler,
                    onFinishHandler: onFinishHandler
                )
                
                // increment play count
                // Only increment if we're playing from the start
                if startTime == CMTime.zero {
                    self.currentNote?.incrementPlayCount()
                }
            }
        }
        
        if self.isWalkingNote || self.isRunningNote {
            print("\tIs currently \(self.isWalkingNote ? "walking" : "running"). Stop and play \(self.selectionCursor.hasSelection ? "selection" : "note").")
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
            print("\tIs currently playing prior speech. Stop and play new \(self.selectionCursor.hasSelection ? "selection" : "note").")
            self.speechPlayer.stop(withFeedback: false) {
                executePlay()
            }
        } else {
            executePlay()
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func stopPlayingNote(withFeedback: Bool = true, voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Stop Playing \(self.selectionCursor.hasSelection ? "Selection" : "Note") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Stop Note
        self.speechPlayer.stop(withFeedback: withFeedback) { [weak self] in
            if self!.pausedWalkingNote {
                note.walk() {
                    handler?()
                }
            } else if self!.pausedRunningNote {
                note.run() {
                    handler?()
                }
            } else {
                handler?()
            }
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func echoNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Echo \(self.selectionCursor.hasSelection ? "Selection" : "Note") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let executeEcho = {
            print("\tSpeech synthesizer \(self.speechSynthesis.pausedEcho ? "continue" : "starts") speaking...")
            var segments: [NoteSegment]
            if self.pausedWalkingNote || self.pausedRunningNote {
                segments = Array(note.noteSegments[self.walkingRange!])
            } else if self.selectionCursor.hasSelection {
                segments = self.selectionCursor.selectionSegments!
            } else {
                segments = note.noteSegments
            }
            self.speechSynthesis.startEcho(
                segments: segments,
                onFinishHandler: { [weak self] in
                    if self!.pausedWalkingNote {
                        note.walk() {
                            handler?()
                        }
                    } else if self!.pausedRunningNote {
                        note.run() {
                            handler?()
                        }
                    } else {
                        handler?()
                    }
                }
            )
        }
        
        if self.isWalkingNote || self.isRunningNote {
            note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                if self.speechSynthesis.isPlayingEcho {
                    self.speechSynthesis.stopEcho(withFeedback: false) {
                        executeEcho()
                    }
                } else {
                    executeEcho()
                }
            }
        } else if self.speechSynthesis.isPlayingEcho {
            self.speechSynthesis.stopEcho(withFeedback: false) {
                executeEcho()
            }
        } else {
            executeEcho()
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func stopEcho(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Stop Echo =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.speechSynthesis.isPlayingEcho && !self.speechSynthesis.isPlayingPassiveEcho {
            self.notifications.executeError(
                text: "Note not being echoed.",
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if self.speechSynthesis.isPlayingEcho || self.speechSynthesis.isPlayingPassiveEcho {
            self.speechSynthesis.stopEcho(withFeedback: false) { [weak self] in
                if self!.pausedWalkingNote {
                    note.walk() {
                        handler?()
                    }
                } else if self!.pausedRunningNote {
                    note.run() {
                        handler?()
                    }
                } else {
                    handler?()
                }
            }
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func walkNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Walk \(self.selectionCursor.hasSelection ? "Selection" : "Note") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if let selectionSegments = self.selectionCursor.selectionSegments, self.selectionCursor.hasSelection {
            // Walk Selection
            note.walk(segments: selectionSegments, onStartHandler: handler)
        } else {
            // Walk Note
            note.walk(onStartHandler: handler)
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    // Reference: https://www.hackingwithswift.com/example-code/system/how-to-copy-text-to-the-clipboard-using-uipasteboard
    func exportNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Export \(self.selectionCursor.hasSelection ? "Selection" : "Note") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if let selectionTimeRange = self.selectionCursor.selectionTimeRange, let note = self.currentNote, self.selectionCursor.hasSelection {
            // Export Selection
            let dialogActions = [
                DialogAction(
                    title: "Export Audio",
                    voiceCommand: "export audio",
                    feedbackVisualMessage: "Exporting audio",
                    feedbackAudioMessage: "Exporting audio. Select selection destination on the screen.",
                    style: .default,
                    handler: { [weak self] action in
                    self?.isExportingNote = true
                    let selectionFilename = "note-\(UUID().uuidString)"
                    
                    Utils.exportNote(
                        state: self!.state,
                        note: note,
                        filename: selectionFilename,
                        fileType: note.fileType,
                        timeRange: selectionTimeRange
                    ) { noteURL in
                        self?.isExportingNote = false
                        handler?()
                        
                        NotificationCenter.default.post(
                            name: NoteManager.onNoteAudioExported,
                            object: nil,
                            userInfo: [ "noteURL" : noteURL]
                        )
                    }
                }),
                DialogAction(
                    title: "Export Text",
                    voiceCommand: "export text",
                    feedbackVisualMessage: "Selection text copied!",
                    feedbackAudioMessage: "Selection text copied to clipboard",
                    style: .default,
                    handler: { [weak self]  action in
                    let pasteboard = UIPasteboard.general
                    pasteboard.string = self!.selectionCursor.selectionText
                }),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: "cancel",
                    feedbackVisualMessage: "Canceled!",
                    feedbackAudioMessage: "Command canceled.",
                    style: .cancel,
                    handler: nil
                )
            ]
            
            let dialogItem = DialogItem(
                title: "Export Selection",
                message: "Choose export format. Say 'export audio', 'export text', or 'cancel' to dismiss.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            self.uiManager.presentDialog(dialogItem: dialogItem)
        } else if let note = self.currentNote {
            // Export Note
            let dialogActions = [
                DialogAction(
                    title: "Export Audio",
                    voiceCommand: "export audio",
                    feedbackVisualMessage: "Exporting audio",
                    feedbackAudioMessage: "Exporting audio. Select note destination on the screen.",
                    style: .default,
                    handler: { [weak self]  action in
                    self?.isExportingNote = true
                    let selectionFilename = "note-\(UUID().uuidString)"
                    
                    Utils.exportNote(
                        state: self!.state,
                        note: note,
                        filename: selectionFilename,
                        fileType: note.fileType,
                        timeRange: note.timeRange
                    ) { noteURL in
                        self?.isExportingNote = false
                        handler?()
                        
                        NotificationCenter.default.post(
                            name: NoteManager.onNoteAudioExported,
                            object: nil,
                            userInfo: [ "noteURL" : noteURL]
                        )
                    }
                    
                    // Increment Note Audio Export Count
                    note.incrementAudioExportCount()
                }),
                DialogAction(
                    title: "Export Text",
                    voiceCommand: "export text",
                    feedbackVisualMessage: "Selection text copied!",
                    feedbackAudioMessage: "Selection text copied to clipboard",
                    style: .default,
                    handler: { action in
                    let pasteboard = UIPasteboard.general
                    pasteboard.string = note.getText()
                    
                    // Increment Note Text Export Count
                    note.incrementTextExportCount()
                }),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: "cancel",
                    feedbackVisualMessage: "Canceled!",
                    feedbackAudioMessage: "Command canceled.",
                    style: .cancel,
                    handler: nil
                )
            ]
            
            let dialogItem = DialogItem(
                title: "Export Note",
                message: "Choose export format. Say 'export audio', 'export text', or 'cancel' to dismiss.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            self.uiManager.presentDialog(dialogItem: dialogItem)
        }
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func runNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Run \(self.selectionCursor.hasSelection ? "Selection" : "Note") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if let selectionSegments = self.selectionCursor.selectionSegments, self.selectionCursor.hasSelection {
            // Run Selection
            note.run(segments: selectionSegments, onStartHandler: handler)
        } else {
            // Run Note
            note.run(onStartHandler: handler)
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func pauseNote(withFeedback: Bool = true, voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Pause \(self.selectionCursor.hasSelection ? "Selection" : "Note") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if self.speechPlayer.isPlayingNote {
            print("\tPausing Playing Note...")
            self.speechPlayer.pause(withFeedback: withFeedback) {
                if withFeedback {
                    self.notifications.executeFeedback(
                        visualMessage: "Pause Playback",
                        audioMessage: "playback paused",
                        withHaptics: true
                    )
                }
                handler?()
            }
        } else if self.speechRecognition.isListeningForSpeech {
            print("\tPausing Listening Note....")
            self.speechRecognition.pauseListeningForSpeech(userInitiated: true) {
                if withFeedback {
                    self.notifications.executeFeedback(
                        visualMessage: "Pause Note",
                        audioMessage: "note paused",
                        withHaptics: true
                    )
                }
                
                handler?()
            }
        } else {
            print("\tUnhandled Branch")
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func playCommit(voiceCommand: Bool = false, onStartHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
        print("===== Note Manager: Play Commit =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: onFinishHandler
            )
            return
        }
        
        if note.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                handler: onFinishHandler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let executePlay = {
            let commit = note.getLastCommit()
            print("\tLast Commit: ", note.getText(segments: commit))
            guard let lastCommit = commit else {
                self.notifications.executeError(
                    text: "Unable to find last commit.",
                    handler: onFinishHandler
                )
                return
            }
            let fromTime = lastCommit.first!.timeMapping.target.start
            let toTime = lastCommit.last!.timeMapping.target.end
            
            self.speechPlayer.play(
                note: note,
                from: fromTime,
                to: toTime,
                onStartHandler: onStartHandler,
                onFinishHandler: onFinishHandler
            )
        }
        
        if self.isWalkingNote || self.isRunningNote {
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
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func pauseEcho(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Pause Echo =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let _ = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.speechSynthesis.isPlayingEcho {
            self.notifications.executeError(
                text: "Note not being echoed.",
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        self.speechSynthesis.pauseEcho() {
            if self.speechRecognition.pausedListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                // when headphones are off we don't listen for voice commands while echoing
                // but on completion we turn it back on
                self.speechRecognition.startListeningForVoiceCommands() {
                    handler?()
                }
            } else if self.speechRecognition.pausedListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                // when headphones are off we don't listen for speech while echoing
                // but on completion we turn it back on
                self.speechRecognition.startListeningForSpeech() {
                    handler?()
                }
            }
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func skipBackward(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Skip Backward =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let currentSegment = self.speechPlayer.getCurrentSegment()
        
        if let currentSegment = currentSegment, self.speechPlayer.isPlayingNote, CMTimeMake(
            value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
        ) > CMTime.zero {
            let time = CMTimeMake(
                value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
                timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
            )
            self.speechPlayer.skip(to: time)
            
        } else if let currentSegment = currentSegment, self.speechPlayer.isPlayingNote, CMTimeMake(
            value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
        ) <= CMTime.zero {
            // Will skip past end of track
            self.notifications.executeError(
                text: "Skipping would exceed duration",
                handler: handler
            )
            
            return
        }
        
        handler?()
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func skipForward(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Skip Forward =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let currentSegment = self.speechPlayer.getCurrentSegment()
        
        if let currentSegment = currentSegment, let currentItem = self.speechPlayer.player.currentItem, self.speechPlayer.isPlayingNote, CMTimeMake(
            value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
        ) < currentItem.duration {
            let time = CMTimeMake(
                value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
                timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
            )
            self.speechPlayer.skip(to: time)
        } else if let currentSegment = currentSegment, let currentItem = self.speechPlayer.player.currentItem, self.speechPlayer.isPlayingNote, CMTimeMake(
            value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
        ) >= currentItem.duration {
            // Will skip past end of track
            self.notifications.executeError(
                text: "Skipping would exceed duration",
                handler: handler
            )
            
            return
        }
        
        handler?()
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func walkNextElement(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Walk Next Element =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isWalkingNote {
            self.notifications.executeError(
                text: "Not walking note or selection.",
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        note.walkToNextSegment(handler: handler)

        handler?()
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func walkPreviousElement(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Walk Previous Element =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isWalkingNote {
            self.notifications.executeError(
                text: "Not walking note or selection.",
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        note.walkToPreviousSegment(handler: handler)
        
        handler?()
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func pauseRun(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Pause Run =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isRunningNote {
            self.notifications.executeError(
                text: "Not running note or selection.",
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        note.pauseRun(handler: handler)
        
        handler?()
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func exitWalkRun(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Exit Walk Run =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isWalkingNote && !self.isRunningNote {
            self.notifications.executeError(
                text: "Not walking or running note or selection.",
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        note.exitWalk() {
            handler?()
            NotificationCenter.default.post(
                name: NoteManager.onExecuteNoteAction,
                object: nil,
                userInfo: ["type": "exit mode"]
            )
        }
        
        checkRep()
    }
    
    func increaseRateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Increase Rate Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        print("\tRegistering a note change to the Undo Manager...")
        self.registerNoteChange(note: note, undo: "selecting '\(self.selectionCursor.selectionText ?? "speech")'") { [weak self] in
            self?.selectionCursor.adjustRateSelection(direction: .up) { [weak self] rate in
                print("\tRegistering a note change to the Undo Manager...")
                self?.registerNoteChange(
                    note: self!.currentNote!,
                    undo: "increasing selection rate",
                    handler: handler
                )
                
                self?.notifications.executeFeedback(
                    visualMessage: "Increase Selection Rate: \(rate.rounded(toPlaces: 2))",
                    audioMessage: "increased selection rate to \(rate.rounded(toPlaces: 2))",
                    withHaptics: true
                )
            }
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func decreaseRateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Decrease Rate Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        print("\tRegistering a note change to the Undo Manager...")
        self.registerNoteChange(note: note, undo: "selecting '\(self.selectionCursor.selectionText ?? "speech")'") { [weak self] in
            self?.selectionCursor.adjustRateSelection(direction: .down) { [weak self] rate in
                print("\tRegistering a note change to the Undo Manager...")
                self?.registerNoteChange(
                    note: self!.currentNote!,
                    undo: "decreasing selection rate",
                    handler: handler
                )
                
                self?.notifications.executeFeedback(
                    visualMessage: "Decrease Selection Rate: \(rate.rounded(toPlaces: 2))",
                    audioMessage: "decreased selection rate to \(rate.rounded(toPlaces: 2))",
                    withHaptics: true
                )
            }
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func deleteSelection(voiceCommand: Bool = false, isCommit: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Delete Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        let undoMessage = "deleting '\(self.selectionCursor.selectionText ?? "selection")'"
        
        print("\tRegistering a note change to the Undo Manager...")
        self.registerNoteChange(note: note, undo: "selecting '\(self.selectionCursor.selectionText ?? "speech")'") { [weak self] in
            self?.selectionCursor.deleteSelection(isCommit: isCommit) { [weak self] in
                print("\tRegistering a note change to the Undo Manager...")
                self?.registerNoteChange(
                    note: self!.currentNote!,
                    undo: undoMessage,
                    handler: handler
                )
            }
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func updateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Update Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Turn on ambient track
        if !soundEngine.isPlayingModalAmbience {
            soundEngine.startModalAmbience()
        }
        
        // Execute update selection
        self.selectionCursor.initiateUpdateSelection()

        handler?()
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func acceptUpdateSelection(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Accept Update Selection =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if self.selectionCursor.hasSelection && self.selectionCursor.isUpdatingSelection && self.selectionCursor.isPromptingForUpdateAcceptance {
            // Turn off ambient track
            soundEngine.stopModalAmbience()

            // Clear buffer segments
            print("\tClearing note buffer...")
            note.clearBuffer()
            
            print("\tRegistering a note change to the Undo Manager...")
            self.registerNoteChange(note: note, undo: "selecting '\(self.selectionCursor.selectionText ?? "speech")'") { [weak self] in
                self?.selectionCursor.acceptUpdateSelection(handler: { [weak self] in
                    print("\tRegistering a note change to the Undo Manager...")
                    self?.registerNoteChange(
                        note: self!.currentNote!,
                        undo: "replacing '\(self?.selectionCursor.selectionText ?? "selection")'",
                        handler: handler
                    )
                })
            }
        } else if !self.selectionCursor.hasSelection {
            self.notifications.executeError(
                text: "No existing selection.",
                voiceCommand: true,
                handler: handler
            )
        } else if !self.selectionCursor.isUpdatingSelection {
            self.notifications.executeError(
                text: "Say \"update\" to replace selection.",
                voiceCommand: true,
                handler: handler
            )
        } else if !self.selectionCursor.isPromptingForUpdateAcceptance {
            self.notifications.executeError(
                text: "No update yet.",
                voiceCommand: true,
                handler: handler
            )
        }
    }
    
    func redoUpdateSelection(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Redo Update Selection =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if self.selectionCursor.hasSelection && self.selectionCursor.isUpdatingSelection && self.selectionCursor.isPromptingForUpdateAcceptance {
            // Turn on ambient track
            if !soundEngine.isPlayingModalAmbience {
                soundEngine.startModalAmbience()
            }

            // Clear buffer segments
            print("\tClearing note buffer...")
            note.clearBuffer()
            
            // Redo Update Selection
            print("\tRedoing Update Selection...")
            self.selectionCursor.initiateUpdateSelection(handler: handler)
        } else if !self.selectionCursor.hasSelection {
            self.notifications.executeError(
                text: "No existing selection.",
                voiceCommand: true,
                handler: handler
            )
        } else if !self.selectionCursor.isUpdatingSelection {
            self.notifications.executeError(
                text: "Say \"update\" to replace selection.",
                voiceCommand: true,
                handler: handler
            )
        } else if !self.selectionCursor.isPromptingForUpdateAcceptance {
            self.notifications.executeError(
                text: "No update yet.",
                voiceCommand: true,
                handler: handler
            )
        }
    }
    
    func cancelUpdateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Cancel Update Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if self.selectionCursor.hasSelection && self.selectionCursor.isUpdatingSelection {
            // Turn off ambient track
            soundEngine.stopModalAmbience()

            // Clear buffer segments
            print("\tClearing note buffer...")
            note.clearBuffer()
            
            // Cancel Update Selection
            print("\tCanceling Update Selection...")
            self.selectionCursor.cancelUpdateSelection(handler: handler)
        } else if !self.selectionCursor.hasSelection {
            self.notifications.executeError(
                text: "No existing selection.",
                voiceCommand: true,
                handler: handler
            )
        } else if !self.selectionCursor.isUpdatingSelection {
            self.notifications.executeError(
                text: "Update mode not active.",
                voiceCommand: true,
                handler: handler
            )
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: ["type": "cancel update selection"]
        )
        
        checkRep()
    }
    
    func copySelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Copy Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        self.selectionCursor.copySelection()
        
        handler?()
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func cutSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Cut Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let undoMessage = "cutting '\(self.selectionCursor.selectionText ?? "selection")'"
        
        print("\tRegistering a note change to the Undo Manager...")
        self.registerNoteChange(note: note, undo: "selecting '\(self.selectionCursor.selectionText ?? "speech")'") { [weak self] in
            self?.selectionCursor.cutSelection() { [weak self] in
                print("\tRegistering a note change to the Undo Manager...")
                self?.registerNoteChange(
                    note: self!.currentNote!,
                    undo: undoMessage,
                    handler: handler
                )
            }
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func pasteClipboard(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Paste Clipboard: \(self.selectionCursor.clipboard != nil ? Note.getText(segments: self.selectionCursor.clipboard!) : "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let undoMessage = "pasting '\(self.selectionCursor.clipboard != nil ? Note.getText(segments: self.selectionCursor.clipboard!) : "clipboard")'"
        
        print("\tRegistering a note change to the Undo Manager...")
        self.registerNoteChange(note: note, undo: "moving cursor") { [weak self] in
            self?.selectionCursor.pasteClipboard() { [weak self] in
                print("\tRegistering a note change to the Undo Manager...")
                self?.registerNoteChange(
                    note: self!.currentNote!,
                    undo: undoMessage,
                    handler: handler
                )
            }
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func selectCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Select Commit =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if note.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let commit = note.getLastCommit()
        print("\tLast Commit: ", note.getText(segments: commit))
        guard let lastCommit = commit else {
            self.notifications.executeError(
                text: "Unable to find last commit.",
                handler: handler
            )
            return
        }
        
        let newAnchor: NoteSegment?  = lastCommit.first
        var newAnchorIndex: Int?
        if let anchor = newAnchor, !anchor.isActive() {
            print("\tSearching for valid anchor...")
            newAnchorIndex = Utils.getSegmentIndex(
                segment: anchor,
                segments: Array(lastCommit),
                type: .next,
                isWord: true
            )
        } else if let anchor = newAnchor, anchor.isActive() {
            newAnchorIndex = anchor.getIndex()
        }
        
        let newFocus: NoteSegment? = lastCommit.last
        var newFocusIndex: Int?
        if let focus = newFocus, !focus.isActive() {
            print("\tSearching for valid focus...")
            newFocusIndex = Utils.getSegmentIndex(
                segment: focus,
                segments: Array(lastCommit),
                type: .previous,
                isWord: true
            )
        } else if let focus = newFocus, focus.isActive() {
            newFocusIndex = focus.getIndex()
        }
        
        if let anchorIndex = newAnchorIndex,
           let focusIndex = newFocusIndex
        {
            // Select Previous Commit
            print("\tSetting selection...")
            self.selectionCursor.setSelection(
                anchorCaret: Caret(index: anchorIndex, trackType: .committed),
                focusCaret: Caret(index: focusIndex, trackType: .committed)
            )
        }
        
        handler?()
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func rollbackCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Rollback Commit =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if note.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let executeRollback = {
            print("\tRegistering a note change to the Undo Manager...")
            self.registerNoteChange(note: note, undo: "moving cursor") { [weak self] in
                // Select Previous Commit
                self?.selectCommit()
                
                // Delete current selection
                self?.selectionCursor.deleteSelection(isCommit: true) { [weak self] in
                    print("\tRegistering a note change to the Undo Manager...")
                    self?.registerNoteChange(
                        note: self!.currentNote!,
                        undo: "rolling back last commit",
                        handler: handler
                    )
                }
            }
        }
        
        if !self.speechRecognition.pausedListeningForSpeech {
            self.speechRecognition.pauseListeningForSpeech(preventListeningForCommands: true) {
                executeRollback()
            }
        } else {
            executeRollback()
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func walkCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Walk Commit =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if note.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        // Select Previous Commit
        self.selectCommit()
        
        // Walk current selection
        self.walkNote(voiceCommand: true, handler: handler)
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func runCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Run Commit =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if note.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        // Select Previous Commit
        self.selectCommit()
        
        // Run current selection
        self.runNote(voiceCommand: true, handler: handler)
        
        NotificationCenter.default.post(
            name: NoteManager.onExecuteNoteAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func openSelection(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Open Selection =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        let currentAnchor = self.selectionCursor.anchor
        var selectionIndex: Int?
        if let segment = currentAnchor, self.selectionCursor.isAtEndOfTextView {
            print("\tAttempt to set last word as selection...")
            // set last word as selection
            if !segment.isValidWord() {
                print("\tCurrent segment is invalid word. Find new one (previous):")
                print("\tIs Punctuation: ", segment.isPunctuation())
                print("\tIs Number: ", segment.isNumber())
                print("\tIs Deleted: ", segment.isDeleted())
                print("\tIs Voice Command Word: ", segment.isVoiceCommandWord())
                print("\tIs Silence: ", segment.isSilence())
                selectionIndex = Utils.getSegmentIndex(
                    segment: segment,
                    segments: note.noteSegments,
                    type: .previous,
                    isWord: true,
                    isCommitted: true
                )
            } else {
                selectionIndex = segment.getIndex()
            }
        } else if let segment = currentAnchor {
            // set word after anchor as selection
            print("\tAttempt to set word after anchor as selection...")
            if !segment.isValidWord() {
                print("\tCurrent segment is invalid word. Find new one (next):")
                print("\tIs Punctuation: ", segment.isPunctuation())
                print("\tIs Number: ", segment.isNumber())
                print("\tIs Deleted: ", segment.isDeleted())
                print("\tIs Voice Command Word: ", segment.isVoiceCommandWord())
                print("\tIs Silence: ", segment.isSilence())
                selectionIndex = Utils.getSegmentIndex(
                    segment: segment,
                    segments: note.noteSegments,
                    type: .next,
                    isWord: true,
                    isCommitted: true
                )
            } else {
                selectionIndex = segment.getIndex()
            }
        }
        
        print("Selection Index: ", selectionIndex ?? "nil")
        
        if let selectionIndex = selectionIndex {
            let selection = note.noteSegments[selectionIndex]
            print("\tFound selection: ", selection.getText())
            // Play Sound
            soundEngine.voiceCommandAccept()

            self.selectionCursor.setSelection(
                anchorCaret: Caret(index: selectionIndex, trackType: .committed),
                focusCaret: Caret(index: selectionIndex, trackType: .committed)
            )
            
            self.notifications.executeFeedback(
                visualMessage: "Selection Opened!",
                withHaptics: true
            )
            
            handler?()
        } else {
            print("\t[Error] There was a problem opening selection. Unable to locate suitable segment.")
            self.notifications.executeError(
                text: "Unable to locate suitable word to select.",
                handler: handler
            )
        }
    }
    
    func removeSelection(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Remove Selection =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.selectionCursor.hasSelection {
            self.notifications.executeError(
                text: "No selection exists.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        let executeRemoveSelection = { [weak self] in
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            self?.selectionCursor.clearSelection(withFeedback: true) {
                // Notify observers of loading
                NotificationCenter.default.post(
                    name: Note.onRequestToUpdateView,
                    object: nil,
                    userInfo: [:]
                )
            }
            
            handler?()
        }
        
        if self.isWalkingNote || self.isRunningNote {
            print("\tIs \(self.isWalkingNote ? "walking" : "running") note. Stop runnning then execute 'remove selection' command...")
            note.exitWalk(clearSelection: false, withFeedback: false) {
                executeRemoveSelection()
            }
        } else {
            executeRemoveSelection()
        }
    }
    
    func shiftAnchor(
        direction: DirectionType,
        withFeedback: Bool = true,
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Shift Anchor \(direction == .left ? "Left" : "Right") =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if !self.selectionCursor.hasSelection {
            self.notifications.executeError(
                text: "No existing selection.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        var newAnchorIndex: Int?
        if let currentAnchor = self.selectionCursor.anchor, direction == .left {
            newAnchorIndex = Utils.getSegmentIndex(
                segment: currentAnchor,
                segments: note.noteSegments,
                type: .previous,
                isWord: true
            )
        } else if let currentAnchor = self.selectionCursor.anchor,
            let currentFocus = self.selectionCursor.focus,
            direction == .right &&
            currentAnchor.getUID() != currentFocus.getUID()
        {
            newAnchorIndex = Utils.getSegmentIndex(
                segment: currentAnchor,
                segments: note.noteSegments,
                type: .next,
                isWord: true
            )
        }
        
        if let newAnchorIndex = newAnchorIndex {
            if withFeedback {
                // Play Sound
                soundEngine.voiceCommandAccept()
            }

            self.selectionCursor.setAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: .committed))
            
            if withFeedback {
                self.notifications.executeFeedback(
                    visualMessage: "Selection Updated!",
                    withHaptics: true
                )
            }
            print("\tShifted anchor \(direction == .left ? "left" : "right")")
            handler?()
        } else if let currentAnchor = self.selectionCursor.anchor,
            let currentFocus = self.selectionCursor.focus,
            currentAnchor.getUID() == currentFocus.getUID()
        {
            print("\tUnable to shift anchor right because we're selecting a single segment")
            self.notifications.executeError(
                text: "Unable to shift before first word.",
                voiceCommand: true,
                handler: handler
            )
        } else {
            print("\t[Error] There was a problem updating selection anchor. Unable to locate suitable segment.")
            self.notifications.executeError(
                text: "Unable to update selection.",
                handler: handler
            )
        }
    }
    
    func shiftFocus(
        direction: DirectionType,
        withFeedback: Bool = true,
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Shift Focus \(direction == .left ? "Left" : "Right") =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.selectionCursor.hasSelection {
            self.notifications.executeError(
                text: "No existing selection.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        var newFocusIndex: Int?
        if let currentFocus = self.selectionCursor.focus,
           let currentAnchor = self.selectionCursor.anchor,
           direction == .left &&
            currentAnchor.getUID() != currentFocus.getUID()
        {
            newFocusIndex = Utils.getSegmentIndex(
                segment: currentFocus,
                segments: note.noteSegments,
                type: .previous,
                isWord: true
            )
        } else if let currentFocus = self.selectionCursor.focus,
            direction == .right
        {
            newFocusIndex = Utils.getSegmentIndex(
                segment: currentFocus,
                segments: note.noteSegments,
                type: .next,
                isWord: true
            )
        }
        
        if let newFocusIndex = newFocusIndex {
            if withFeedback {
                // Play Sound
                soundEngine.voiceCommandAccept()
            }

            self.selectionCursor.setFocusCaret(caret: Caret(index: newFocusIndex, trackType: .committed))
            
            if withFeedback {
                self.notifications.executeFeedback(
                    visualMessage: "Selection Updated!",
                    withHaptics: true
                )
            }
            print("\tShifted focus \(direction == .left ? "left" : "right")")
            handler?()
        } else if let currentAnchor = self.selectionCursor.anchor,
              let currentFocus = self.selectionCursor.focus,
              currentAnchor.getUID() == currentFocus.getUID()
        {
            print("\tUnable to shift focus left because we're selecting a single segment")
            self.notifications.executeError(
                text: "Unable to shift past last word.",
                voiceCommand: true,
                handler: handler
            )
        } else {
            print("\t[Error] There was a problem updating selection focus. Unable to locate suitable segment.")
            self.notifications.executeError(
                text: "Unable to update selection.",
                handler: handler
            )
        }
    }
    
    func shiftSelection(
        direction: DirectionType,
        withFeedback: Bool = true,
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Shift Selection =====")
        print("\tTriggered by voice command.")
        
        if direction == .right {
            // We want focus to move first
            self.shiftFocus(
                direction: direction,
                handler: handler
            )
            self.shiftAnchor(
                direction: direction,
                withFeedback: false
            )
        } else if direction == .left {
            // We want anchor to move first
            self.shiftAnchor(
                direction: direction,
                withFeedback: false
            )
            self.shiftFocus(
                direction: direction,
                handler: handler
            )
        }
    }
    
    func expandSelection(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Expand Selection =====")
        print("\tTriggered by voice command.")
        self.shiftAnchor(
            direction: .left,
            withFeedback: false
        )
        self.shiftFocus(
            direction: .right,
            handler: handler
        )
    }
    
    func reduceSelection(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Reduce Selection =====")
        print("\tTriggered by voice command.")
        self.shiftAnchor(
            direction: .right,
            withFeedback: false
        )
        self.shiftFocus(
            direction: .left,
            handler: handler
        )
    }
    
    func echoCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Echo Commit =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if note.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let executeEcho = {
            let commit = note.getLastCommit()
            print("\tLast Commit: ", note.getText(segments: commit))
            guard let lastCommit = commit else {
                self.notifications.executeError(
                    text: "Unable to find last commit.",
                    handler: handler
                )
                return
            }

            self.speechSynthesis.startEcho(
                segments: Array(lastCommit),
                onStartHandler: {
                    NotificationCenter.default.post(
                        name: Note.onRequestToUpdateView,
                        object: nil,
                        userInfo: [:]
                    )
                },
                onFinishHandler: {
                    NotificationCenter.default.post(
                        name: Note.onRequestToUpdateView,
                        object: nil,
                        userInfo: [:]
                    )
                    if self.pausedWalkingNote {
                        note.walk() {
                            handler?()
                        }
                    } else if self.pausedRunningNote {
                        note.run() {
                            handler?()
                        }
                    } else {
                        handler?()
                    }
                }
            )
        }
        
        if self.isWalkingNote || self.isRunningNote {
            note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                if self.speechSynthesis.isPlayingEcho {
                    self.speechSynthesis.stopEcho(withFeedback: false) {
                        executeEcho()
                    }
                } else {
                    executeEcho()
                }
            }
        } else if self.speechSynthesis.isPlayingEcho {
            self.speechSynthesis.stopEcho(withFeedback: false) {
                executeEcho()
            }
        } else {
            executeEcho()
        }
    }
    
    func echoPreviousSentence(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Echo Previous Sentence =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if note.noteSegments.count == 0 {
            self.notifications.executeError(
                text: "Note is empty.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        let previousSentenceIndex = max(note.numSentences - 1, 0)
        
        if note.numSentences == 1 {
            self.notifications.executeError(
                text: "No previous sentence exists.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()

        note.echoSentence(number: previousSentenceIndex, onFinishHandler: handler)
    }
    
    func playPreviousSentence(
        handler: (() -> Void)? = nil
    ) {
        print("===== Note Manager: Play Previous Sentence =====")
        print("\tTriggered by voice command.")
        guard let note = self.currentNote else {
            self.notifications.executeError(
                text: "No note selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
    
        if note.noteSegments.count == 0 {
            self.notifications.executeError(
                text: "Note is empty.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        let executePlay = {
            let previousSentenceIndex = max(note.numSentences - 1, 0)
            
            if note.numSentences == 1 {
                self.notifications.executeError(
                    text: "No previous sentence exists.",
                    voiceCommand: true,
                    handler: handler
                )
                return
            }
            
            // Play Sound
            soundEngine.voiceCommandAccept()

            note.playSentence(number: previousSentenceIndex)
        }
        
        if self.isWalkingNote || self.isRunningNote {
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
    }
    
    // MARK: - Undo/Redo Methods
    
    // message should start with a present progressive verb: -ing
    // so utterance will be: undo verb-ing object
    func registerNoteChange(note: Note, undo message: String, handler: (() -> Void)? = nil) {
        print("===== Note Manager: Register Note Change  =====")

        // Update Undo/Redo History
        print("\tCreating and setting new snapshot...")
        
        let newSnapshot = NoteSnapshot(
            note: note.duplicate(), // we duplicate so there's no memory leaks/pointers to same memory locations
            selectionAnchorCaret: self.selectionCursor.anchorCaret?.duplicate(),
            selectionFocusCaret: self.selectionCursor.focusCaret?.duplicate(),
            selectionCachedAnchorCaret: self.selectionCursor.cachedAnchorCaret?.duplicate(),
            undo: message
        )
        
        self.noteChangeHandler = handler
        
        self.modifyNote(snapshot: newSnapshot)
        
        checkRep()
    }
    
    @objc func undo(handler: (() -> Void)? = nil) {
        print("===== Note Manager: Undo  =====")
        let executeUndo = {
            let undoMessage = self.currentNoteUndoSnapshot!.message
            self.undoManager.undo()
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Undo",
                audioMessage: "undo \(undoMessage)",
                withHaptics: true,
                delay: 0
            )
        }
        
        if self.undoManager.canUndo {
            // Stop any active echo
            // If segments change, it might throw error
            if self.speechSynthesis.isPlayingEcho || self.speechSynthesis.isPlayingPassiveEcho {
                self.speechSynthesis.stopEcho(withFeedback: false) {
                    executeUndo()
                }
            } else {
                executeUndo()
            }
        } else {
            self.notifications.executeError(text: "Undo changes exhausted.")
        }
        
        handler?()
    }
    
    @objc func redo(handler: (() -> Void)? = nil) {
        print("===== Note Manager: Redo  =====")
        
        let executeRedo = {
            self.undoManager.redo()
            let redoMessage = self.currentNoteUndoSnapshot!.message
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Redo",
                audioMessage: "redo \(redoMessage)",
                withHaptics: true,
                delay: 0
            )
        }
        
        if self.undoManager.canRedo {
            // Stop any active echo
            // If segments change, it might throw error
            if self.speechSynthesis.isPlayingEcho || self.speechSynthesis.isPlayingPassiveEcho {
                self.speechSynthesis.stopEcho(withFeedback: false) {
                    executeRedo()
                }
            } else {
                executeRedo()
            }
        } else {
            self.notifications.executeError(text: "Redo changes exhausted.")
        }
        
        handler?()
    }
    
    // MARK: - Setters
    
    func setCurrentNote(index: Int? = nil) {
        print("===== Note Manager: Set Current Note =====")
        print("\tSet index to: ", index ?? "nil")
        if let index = index {
            self.currentIndex = index
            self.setNoteModules(index: index)
            // Increment Note Views
            self.currentNote!.incrementViewCount()
            
            self.currentNoteUndoSnapshot = NoteSnapshot(
                note: self.currentNote!.duplicate(), // we duplicate so there's no memory leaks/pointers to same memory locations
                selectionAnchorCaret: self.selectionCursor.anchorCaret,
                selectionFocusCaret: self.selectionCursor.focusCaret,
                selectionCachedAnchorCaret: self.selectionCursor.cachedAnchorCaret,
                undo: "to start of note"
            )
            
            print("Note Segments: ", self.currentNote!.noteSegments)
        } else {
            self.currentIndex = nil
            self.currentNoteUndoSnapshot = nil
            self.undoManager.removeAllActions()
        }

        var userInfo: [String : Int] = [:]
        if let currentIndex = self.currentIndex {
            userInfo["currentNoteIndex"] = currentIndex
        }
        NotificationCenter.default.post(
            name: NoteManager.onSetNote,
            object: nil,
            userInfo: userInfo
        )
        
        checkRep()
    }
    
    func setWalkingIndex(index: Int) {
        print("===== Note Manager: Set Walking Index =====")
        print("\tSet index to: ", index)
        self.walkingIndex = index
        
        checkRep()
    }
    
    func setWalkingRange(range: Range<Int>? = nil) {
        print("===== Note Manager: Set Walking Range =====")
        print("\tSet range to: ", range ?? "nil")
        self.walkingRange = range
        
        checkRep()
    }
    
    func setIsWalkingNote(to isWalking: Bool) {
        print("===== Note Manager: Set Is Walking Note =====")
        print("\tSet to: ", isWalking)
        self.isWalkingNote = isWalking
        
        checkRep()
    }
    
    func setIsRunningNote(to isRunning: Bool) {
        print("===== Note Manager: Set Is Running Note =====")
        print("\tSet to: ", isRunning)
        self.isRunningNote = isRunning
        
        checkRep()
    }
    
    func setPausedWalkingNote(to paused: Bool) {
        print("===== Note Manager: Set Paused Walking Note =====")
        print("\tSet to: ", paused)
        self.pausedWalkingNote = paused
        
        checkRep()
    }
    
    func setPausedRunningNote(to paused: Bool) {
        print("===== Note Manager: Set Paused Running Note =====")
        print("\tSet to: ", paused)
        self.pausedRunningNote = paused
        
        checkRep()
    }
    
    func setWalkingTimer(timer: Timer? = nil) {
        print("===== Note Manager: Set Walking Timer =====")
        if let _ = timer {
            print("\tSet new timer.")
        } else {
            print("\tCleared timer.")
        }
        self.walkingTimer?.invalidate()
        self.walkingTimer = timer
        
        checkRep()
    }
    
    func setWalkLoopDelayTimer(timer: Timer? = nil) {
        print("===== Note Manager: Set Walk Loop Delay Timer =====")
        if let _ = timer {
            print("\tSet new timer.")
        } else {
            print("\tCleared timer.")
        }
        self.walkLoopDelayTimer?.invalidate()
        self.walkLoopDelayTimer = timer
        
        checkRep()
    }
    
    func setEchoDelayTimer(timer: Timer? = nil) {
        print("===== Note Manager: Set Echo Delay Timer =====")
        if let _ = timer {
            print("\tSet new timer.")
        } else {
            print("\tCleared timer.")
        }
        self.echoDelayTimer?.invalidate()
        self.echoDelayTimer = timer
        
        checkRep()
    }
    
    func setRunningTimer(timer: Timer? = nil) {
        print("===== Note Manager: Set Running Timer =====")
        if let _ = timer {
            print("\tSet new timer.")
        } else {
            print("\tCleared timer.")
        }
        self.runningTimer?.invalidate()
        self.runningTimer = timer
        
        checkRep()
    }
}

// MARK: - Undo Manager

extension NoteManager {
  
    private func modifyNote(snapshot: NoteSnapshot) {

        let oldSnapshot: NoteSnapshot = self.currentNoteUndoSnapshot!

        let stateDiff = oldSnapshot.diffed(with: snapshot)
        stateDidChange(diff: stateDiff)
    }

    private func stateDidChange(diff: NoteSnapshot.Diff) {

        guard diff.hasChanges else { return }

        self.currentNoteUndoSnapshot = diff.to

        self.undoManager.registerUndo(withTarget: self) { target in
            target.modifyNote(snapshot: diff.from)
        }
        
        NotificationCenter.default.post(
            name: NoteManager.onUndoManagerChange,
            object: nil,
            userInfo: [
                "canUndo": self.undoManager.canUndo,
                "canRedo": self.undoManager.canRedo
            ]
        )
    }
}
