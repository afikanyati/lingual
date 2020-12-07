//
//  EntryManager.swift
//  diction-processor
//
//  Created by Afika Nyati on 11/5/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Speech
import Foundation

class EntryManager: NSObject {
    // MARK: - Notifications
    
    static let onEntryCreated = Notification.Name(Notifications.onEntryCreated.rawValue)
    static let onEntryDeleted = Notification.Name(Notifications.onEntryDeleted.rawValue)
    static let onNavigateToDetailPage = Notification.Name(Notifications.onNavigateToDetailPage.rawValue)
    static let onExecuteEntryAction = Notification.Name(Notifications.onExecuteEntryAction.rawValue)
    static let onEntryAudioExported = Notification.Name(Notifications.onEntryAudioExported.rawValue)
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
    var voiceCommandEngine: VoiceCommandEngine
    weak var entryListManager: EntryListManager!
    private let _undoManager = UndoManager()
    var undoManager: UndoManager {
        return _undoManager
    }
    
    // MARK: - Entry Manager Properties
    
    private(set) var currentIndex: Int? = nil
    var currentEntry: Entry? {
        if let index = self.currentIndex {
            return self.state.activeEntries[index]
        }
        
        return nil
    }
    @objc dynamic var currentEntryUndoSnapshot: EntrySnapshot? = nil
    private(set) var entryChangeHandler: (() -> Void)? = nil
    
    /// Specifies whether entry is currently running
    private(set) var isRunningEntry = false
    /// Specifies whether entry is currently walking
    private(set) var isWalkingEntry = false
    /// Specifies whether entry is currently paused walking
    private(set) var pausedWalkingEntry = false
    /// Specifies whether entry is currently paused running
    private(set) var pausedRunningEntry = false
    /// Specifies whether entry is currently walking
    private(set) var walkingRange: Range<Int>?
    /// Specifies whether entry is currently walking
    private(set) var walkingIndex: Int = 0
    /// Stores a reference to a timer that drives walking loop behavior
    private(set) var walkingTimer: Timer?
    /// Stores a reference to a timer that drives delay of walk loop intiation
    private(set) var walkLoopDelayTimer: Timer?
    /// Stores a reference to a timer that drives delayed echo while walking
    private(set) var echoDelayTimer: Timer?
    /// Stores a reference to a timer that drives passage running
    private(set) var runningTimer: Timer?
    /// Stores whether entry is currently being exported
    private(set) var isExportingEntry = false
    
    // MARK: - Initialization and Deinitialization
    
    init(
        state: StateManager,
        speechRecognition: SpeechRecognitionEngine,
        notifications: NotificationEngine,
        speechPlayer: SpeechPlayerEngine,
        speechSynthesis: SpeechSynthesisEngine,
        selectionCursor: SelectionCursor,
        uiManager: UIManager,
        pitchRecognition: PitchRecognitionEngine,
        voiceCommandEngine: VoiceCommandEngine
    ) {
        print("===== Entry Manager: Initialization =====")
        self.state = state
        self.speechRecognition = speechRecognition
        self.notifications = notifications
        self.speechPlayer = speechPlayer
        self.speechSynthesis = speechSynthesis
        self.selectionCursor = selectionCursor
        self.uiManager = uiManager
        self.pitchRecognition = pitchRecognition
        self.voiceCommandEngine = voiceCommandEngine
        
        super.init()
        
        print("\tSetting modules in entries")
        self.setEntryModules() // Removing this will not show preview text on entries within entry table
        
        self.configureNotificationObservers()
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)

        // remove observer from snapshot
        self.removeObserver(
            self,
            forKeyPath: "currentEntryUndoSnapshot",
            context: nil
        )
    }
    
    // MARK: - Validation
    
    func checkRep() {
        var result = true
        
        // exporting entry can only be active if we have a current entry
        result = result && ((self.currentEntry != nil && self.isExportingEntry) || !self.isExportingEntry)
        
        // cannot pause walking if walking is inactive
        result = result && (!self.pausedWalkingEntry || self.isWalkingEntry)
        
        // cannot pause running if walking is inactive
        result = result && (!self.pausedRunningEntry || self.isRunningEntry)
        
        if !result {
            fatalError("===== [Error] Entry Manager Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
        // Entry Manager
        self.addObserver(
            self,
            forKeyPath: "currentEntryUndoSnapshot",
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
            selector: #selector(onFetchedEntries(notification:)),
            name: StateManager.onFetchedEntries,
            object: nil
        )
    }
    
    @objc func onFetchedEntries(notification: Notification) {
        print("===== Entry Manager: On Fetched Entries =====")
        print("\tSetting modules in entries")
        self.setEntryModules()
    }
    
    @objc func onProcessedVoiceCommand(notification: Notification) {
        print("===== Entry Manager: On Processed Voice Command =====")
        let command = notification.userInfo!["command"] as! VoiceCommandEngine.VoiceCommand
        var handler: (() -> Void)?
        if notification.userInfo!["handler"] != nil {
            handler = notification.userInfo!["handler"] as? () -> Void
        }

        switch (command) {
        case .ENTER_ENTRY:
            self.enterEntry(voiceCommand: true, handler: handler)
        case .PLAY_ENTRY, .PLAY_SELECTION:
            self.playEntry(voiceCommand: true, onFinishHandler: handler)
        case .PAUSE_ENTRY:
            self.pauseEntry(voiceCommand: true, handler: handler)
        case .START_ENTRY:
            if let _ = Utils.getNavigationController()?.visibleViewController as? EntryTableViewController, let _ = self.currentEntry {
                print("\tFound existing entry while in Entry List after receving 'start entry' via voice command. Remove it to trigger new entry creation.")
                self.setCurrentEntry()
            }
            self.startEntry(voiceCommand: true, handler: handler)
        case .CREATE_ENTRY:
            let _ = self.createEntry(voiceCommand: true, handler: handler)
        case .STOP_ENTRY:
            if self.speechPlayer.isPlayingEntry {
                self.stopPlayingEntry(voiceCommand: true, handler: handler)
            } else if let _ = self.currentEntry {
                self.stopEntry(voiceCommand: true, handler: handler)
            }
        case .RESUME_ENTRY:
            if self.speechRecognition.pausedListeningForSpeech {
                self.notifications.executeError(
                    text: "Entry not paused.",
                    voiceCommand: true,
                    handler: handler
                )
                return
            }

            self.resumeEntry(voiceCommand: true, handler: handler)
        case .ECHO_ENTRY, .ECHO_SELECTION:
            self.echoEntry(voiceCommand: true, handler: handler)
        case .PAUSE_ECHO:
            self.pauseEcho(voiceCommand: true, handler: handler)
        case .STOP_ECHO:
            self.stopEcho(voiceCommand: true, handler: handler)
        case .DELETE_SELECTION:
            self.deleteSelection(voiceCommand: true, handler: handler)
        case .UPDATE_SELECTION:
            self.updateSelection(voiceCommand: true, handler: handler)
        case .COPY_SELECTION:
            self.copySelection(voiceCommand: true, handler: handler)
        case .CUT_SELECTION:
            self.cutSelection(voiceCommand: true, handler: handler)
        case .INCREASE_SELECTION_RATE:
            self.increaseRateSelection(voiceCommand: true, handler: handler)
        case .DECREASE_SELECTION_RATE:
            self.decreaseRateSelection(voiceCommand: true, handler: handler)
        case .EXPORT_ENTRY, .EXPORT_SELECTION:
            self.exportEntry(voiceCommand: true, handler: handler)
        case .PAUSE_PLAYBACK:
            self.pauseEntry(voiceCommand: true, handler: handler)
        case .RESUME_ECHO:
            self.echoEntry(voiceCommand: true, handler: handler)
        case .EDIT_ENTRY:
            self.editEntry(voiceCommand: true, handler: handler)
        case .PLAY_COMMIT:
            self.playCommit(voiceCommand: true, onFinishHandler: handler)
        case .SKIP_PLAYBACK_BACKWARD:
            self.skipBackward(voiceCommand: true, handler: handler)
        case .SKIP_PLAYBACK_FORWARD:
            self.skipForward(voiceCommand: true, handler: handler)
        case .STOP_PLAYBACK:
            self.stopPlayingEntry(voiceCommand: true, handler: handler)
        case .DELETE_ENTRY:
            if !self.uiManager.dialogIsVisible {
                self.deleteEntry(voiceCommand: true, handler: handler)
            }
        case .PASTE_CLIPBOARD:
            self.pasteClipboard(voiceCommand: true, handler: handler)
        case .RESUME_PLAYBACK:
            if self.speechPlayer.pausedPlayingEntry {
                self.notifications.executeError(
                    text: "Playback not paused.",
                    voiceCommand: true,
                    handler: handler
                )
                return
            }
            
            self.playEntry(voiceCommand: true, onFinishHandler: handler)
        case .SELECT_COMMIT:
            self.selectCommit(
                handler: handler
            )
        case .WALK_COMMIT:
            self.walkCommit(
                handler: handler
            )
        case .RUN_COMMIT:
            self.runCommit(
                handler: handler
            )
        case .ROLLBACK_COMMIT:
            self.rollbackCommit(
                handler: handler
            )
        case .ENTER_SELECTION:
            self.enterSelection(
                handler: handler
            )
        case .REMOVE_SELECTION:
            self.removeSelection(
                handler: handler
            )
        case .CANCEL_SELECTION_UPDATE:
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
        case .SHIFT_ANCHOR_LEFT:
            self.shiftAnchor(
                direction: .left,
                handler: handler
            )
        case .SHIFT_ANCHOR_RIGHT:
            self.shiftAnchor(
                direction: .right,
                handler: handler
            )
        case .SHIFT_FOCUS_LEFT:
            self.shiftFocus(
                direction: .left,
                handler: handler
            )
        case .SHIFT_FOCUS_RIGHT:
            self.shiftFocus(
                direction: .right,
                handler: handler
            )
        case .SHIFT_SELECTION_FORWARD:
            self.shiftSelection(
                direction: .right,
                handler: handler
            )
        case .SHIFT_SELECTION_BACKWARD:
            self.shiftSelection(
                direction: .left,
                handler: handler
            )
        case .EXPAND_SELECTION:
            self.expandSelection(
                handler: handler
            )
        case .REDUCE_SELECTION:
            self.reduceSelection(
                handler: handler
            )
        case .ECHO_COMMIT:
            self.echoCommit(
                handler: handler
            )
        case .ECHO_PREVIOUS_SENTENCE:
            self.echoPreviousSentence(
                handler: handler
            )
        case .PLAY_PREVIOUS_SENTENCE:
            self.playPreviousSentence(
                handler: handler
            )
        case .RUN_ENTRY, .RUN_SELECTION:
            self.runEntry(voiceCommand: true, handler: handler)
        case .WALK_ENTRY, .WALK_SELECTION:
            self.walkEntry(voiceCommand: true, handler: handler)
        case .SHIFT_NEXT_WALK_ELEMENT:
            if self.isWalkingEntry {
                self.walkNextWord(voiceCommand: true, handler: handler)
            }
        case .SHIFT_PREVIOUS_WALK_ELEMENT:
            if self.isWalkingEntry {
                self.walkPreviousWord(voiceCommand: true, handler: handler)
            }
        case .PAUSE_RUN:
            if self.isRunningEntry {
                self.pauseRun(voiceCommand: true, handler: handler)
            }
        case .EXIT_WALK:
            if self.isWalkingEntry {
                self.exitWalkRun(voiceCommand: true, handler: handler)
            }
        case .UNDO_CHANGE:
            self.undo(handler: handler)
        case .REDO_CHANGE:
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
        print("===== Entry Manager: Observe Value =====")

        if keyPath == "currentEntryUndoSnapshot" {
            print("\tKeyPath: currentEntryUndoSnapshot")
            if let newSnapshot = change?[.newKey] as? EntrySnapshot,
               let _ = change?[.oldKey] as? EntrySnapshot
            {
                print("\tNew Entry Snapshot Received! Save to state")
                let duplicateEntry = newSnapshot.entry.duplicate()
                
                // Handle Current Clip UID
                if let entry = self.currentEntry,
                   duplicateEntry.currentClipUID == nil &&
                    entry.currentClipUID != nil &&
                    self.speechRecognition.isListeningForSpeech
                {
                    print("\tDuplicate entry has no currentClipUID. Give it existing entry's currentClipUID...")
                    let currentClipUID = entry.currentClipUID
                    duplicateEntry.setCurrentClipUID(uid: currentClipUID)
                }
                
                // Handle Record Start Date
                if let entry = self.currentEntry,
                   duplicateEntry.recordStartDate == nil &&
                    entry.recordStartDate != nil &&
                    self.speechRecognition.isListeningForSpeech
                {
                    print("\tDuplicate entry has no recordStartDate. Give it existing entry's recordStartDate...")
                    let recordStartDate = entry.recordStartDate
                    duplicateEntry.setRecordStartDate(date: recordStartDate)
                }
                
                // Handle Record File
                if let entry = self.currentEntry,
                   duplicateEntry.recordFile == nil &&
                    entry.recordFile != nil &&
                    self.speechRecognition.isListeningForSpeech
                {
                    print("\tDuplicate entry has no recordFile. Give it existing entry's recordFile...")
                    let recordFile = entry.recordFile
                    duplicateEntry.setRecordFile(file: recordFile)
                }

                // Set Entry
                self.state.saveEntry(entry: duplicateEntry) // we duplicate so there's no memory leaks/pointers to same memory locations
                
                print("\tSet Node Modules...")
                self.setEntryModules(index: self.currentIndex)
                
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
                
                if let entry = self.currentEntry {
                    print("\tUpdate View with text: '\(entry.getText())'")
                    entry.handleOnSpeechUpdate(text: entry.getText())
                }
                
                if let entryChangeHandler = self.entryChangeHandler {
                    print("\tRunning Save Handler...")
                    entryChangeHandler()
                    self.entryChangeHandler = nil
                }
            } else {
                print("\tNo new snapshot...")
            }
        }
    }
    
    // MARK: - Methods
    
    func setEntryModules(index: Int? = nil) {
        print("===== Entry Manager: Set Entry Modules =====")
        let handleEntry: (_ entry: Entry) -> Void = { entry in
            print("\tHandled Entry UID: ", entry.uid)
            if entry.state == nil {
                entry.setState(state: self.state)
            }
            if entry.speechSynthesis == nil {
                entry.setSpeechSynthesis(speechSynthesis: self.speechSynthesis)
            }
            if entry.speechRecognition == nil {
                entry.setSpeechRecognition(speechRecognition: self.speechRecognition)
            }
            if entry.speechPlayer == nil {
                entry.setSpeechPlayer(speechPlayer: self.speechPlayer)
            }
            if entry.selectionCursor == nil {
                entry.setSelectionCursor(selectionCursor: self.selectionCursor)
            }
            if entry.pitchRecognition == nil {
                entry.setPitchRecognition(pitchRecognition: self.pitchRecognition)
            }
            if entry.entryManager == nil {
                entry.setEntryManager(entryManager: self)
            }
            if entry.notifications == nil {
                entry.setNotifications(notifications: self.notifications)
            }
        }
        
        if let index = index {
            print("\tHandle individual entry.")
            let entry = self.state.activeEntries[index]
            handleEntry(entry)
        } else {
            print("\tHandle all entries.")
            for entry in self.state.activeEntries {
                handleEntry(entry)
            }
        }
    }
    
    func getEntry(uid: String) -> Entry? {
        for entry in self.state.activeEntries {
            if entry.uid == uid {
                return entry
            }
        }
        
        return nil
    }
    
    func enterEntry(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Enter Entry =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        // Navigate to detail page
        NotificationCenter.default.post(
            name: EntryManager.onNavigateToDetailPage,
            object: nil,
            userInfo: [:]
        )
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func createEntry(voiceCommand: Bool = false, withListening: Bool = false, handler: (() -> Void)? = nil) -> String {
        print("===== Entry Manager: Create Entry =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }

        let uid = UUID().uuidString
        let entry = Entry(
            uid: uid,
            filename: "entry-\(uid)",
            creatorUID: self.state.speaker.uid! // This might not always hold true
        )
        
        print("\tNew Entry UID: ", uid)
        
        // Add new entry
        let index = self.state.appendEntry(entry: entry)
        
        self.setEntryModules(index: index)
        
        NotificationCenter.default.post(
            name: EntryManager.onEntryCreated,
            object: nil,
            userInfo: [:]
        )
        
        if withListening {
            // Start Listening Immediately
            self.setCurrentEntry(index: index)
            
            self.notifications.executeFeedback(
                visualMessage: "Create Entry",
                audioMessage: "new entry created",
                withHaptics: true,
                delay: 1
            )
            
            self.startEntry(voiceCommand: voiceCommand, handler: handler)
        } else {
            self.notifications.executeFeedback(
                visualMessage: "Create Entry",
                audioMessage: "new entry created",
                withHaptics: true,
                delay: 1
            )
            
            handler?()
        }
        
        checkRep()
        
        return uid
    }
    
    @objc func deleteEntry(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Delete Entry (using screen button or voice command) =====")
        guard let index = self.currentIndex else {
            self.notifications.executeError(text: "No entry selected")
            return
        }
        
        self.deleteEntry(index: index, handler: handler)
    }
    
    func deleteEntry(index: Int, withConfirmation: Bool = true, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Delete Entry (using index) =====")
        
        let handleDelete: (_ handler: (() -> Void)?) -> Void = { [weak self] handler in
            // Reset Selection Cursor
            if let _ = Utils.getNavigationController()?.visibleViewController as? DetailViewController {
                self?.selectionCursor.reset()
            }
            
            // Set Entry to Deleted
            let entryUID = self!.state.activeEntries[index].uid
            if let entry = self?.getEntry(uid: entryUID) {
                entry.setIsDeleted(to: true)
            }
            
            // save changes
            self?.state.save()
            
            // Handle Entry Clips
    //        self.state.manageClipRemoval(entry: entry)
            
            // Remove Current Entry
            if index == self?.currentIndex {
                self?.setCurrentEntry()
            }
            
            NotificationCenter.default.post(
                name: EntryManager.onEntryDeleted,
                object: nil,
                userInfo: [:]
            )
            
            self?.notifications.executeFeedback(
                visualMessage: "Delete Entry",
                audioMessage: "entry deleted",
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
        
        // Find entry
        if withConfirmation {
            print("\tHandle delete with confirmation dialog.")
            
            let dialogActions = [
                DialogAction(
                    title: "Delete",
                    voiceCommand: .DELETE_ENTRY,
                    feedbackVisualMessage: "Delete Entry",
                    feedbackAudioMessage: "entry deleted",
                    style: .default,
                    handler: { action in
                        handleDelete(handler)
                    }
                ),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: .CANCEL_DIALOG,
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
                message: "Are you sure you want to delete entry? Say 'delete' to continue, or 'cancel' to dismiss.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            self.uiManager.presentDialog(dialogItem: dialogItem)
        } else if !withConfirmation {
            print("\tHandle delete without confirmation dialog.")
            handleDelete(handler)
        } else {
            print("\t[Error] There was a problem deleting entry at index \(index). Unable to find it.")
        }
    }
    
    func deleteEntry(uid: String, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Delete Entry (using uid) =====")

        // Find entry
        let entry = self.getEntry(uid: uid)
        if let entry = entry {

            // Set Entry to Deleted
            entry.setIsDeleted(to: true)
            
            // save changes
            self.state.save()
            
            // Handle Entry Clips
    //        self.state.manageClipRemoval(entry: entry)
            
            NotificationCenter.default.post(
                name: EntryManager.onEntryDeleted,
                object: nil,
                userInfo: [:]
            )
            
            self.notifications.executeFeedback(
                visualMessage: "Delete Entry",
                audioMessage: "entry deleted",
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
            print("\t[Error] There was a problem deleting entry with uid \(uid). Unable to find it.")
        }
    }

    func startEntry(voiceCommand: Bool = false, new: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Start Entry =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if self.speechRecognition.isListeningForSpeech {
            self.notifications.executeError(
                text: "Entry already started.",
                voiceCommand: voiceCommand
            )
            
            return
        }
        
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if self.speechRecognition.session.recordPermission != .granted || authStatus != .authorized {
            let dialogActions = [
                DialogAction(
                    title: "Grant Permission",
                    voiceCommand: .GRANT_PERMISSION,
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
                    voiceCommand: .CANCEL_DIALOG,
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
        
        if let _ = self.currentEntry, new {
            // Clear past entry and make way for new one
            self.setCurrentEntry()
        }
        
        if authStatus == .authorized && self.speechRecognition.session.recordPermission == .granted {
            if let _ = self.currentEntry, !self.speechRecognition.isListeningForSpeech && !self.isExportingEntry {
                if  !self.speechRecognition.isListeningForCommands {
                    // User switched off listening with the button
                    // Change button to normal again
                }
                
                if voiceCommand {
                    // Play Sound
                    soundEngine.voiceCommandAccept()
                }
                
                // Navigate to detail page if we're not there already
                NotificationCenter.default.post(
                    name: EntryManager.onNavigateToDetailPage,
                    object: nil,
                    userInfo: [:]
                )
                
                print("\tStarting Entry...")
                self.speechRecognition.startListeningForSpeech() {
                    self.notifications.executeFeedback(
                        visualMessage: "Start Entry",
                        audioMessage: "entry started",
                        withHaptics: true
                    )
                    
                    handler?()
                }
            } else if self.currentEntry == nil && !self.speechRecognition.isListeningForSpeech {
                print("\tCreating new entry...")
                let _ = self.createEntry(voiceCommand: voiceCommand, withListening: true, handler: handler)
            } else {
                if self.speechRecognition.isListeningForSpeech {
                    self.notifications.executeError(
                        text: "Entry already started.",
                        voiceCommand: voiceCommand,
                        handler: handler
                    )
                } else {
                    self.notifications.executeError(
                        text: "Wait until entry export completion.",
                        voiceCommand: voiceCommand,
                        handler: handler
                    )
                }
                print("\t[Error] There was a problem starting entry. System does not have record permissions.")
            }
        } else {
            self.notifications.executeError(
                text: "Unable to start entry.",
                voiceCommand: voiceCommand
            )
            print("\t[Error] There was a problem starting entry. System does not have record permissions.")
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func resumeEntry(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Resume Entry =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
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
            
            // Navigate to detail page if we're not there already
            NotificationCenter.default.post(
                name: EntryManager.onNavigateToDetailPage,
                object: nil,
                userInfo: [:]
            )

            self.speechRecognition.startListeningForSpeech() {
                self.notifications.executeFeedback(
                    visualMessage: "Resume Entry",
                    audioMessage: "entry resumed",
                    withHaptics: true,
                    delay: 0
                )
                handler?()
            }
        } else {
            self.notifications.executeError(
                text: "No ongoing entry.",
                handler: handler
            )
            return
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func editEntry(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Edit Entry =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if entry.entrySegments.count == 0 {
            self.notifications.executeError(
                text: "No existing entry.",
                voiceCommand: voiceCommand,
                handler: handler
            )
        }
        
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if self.speechRecognition.session.recordPermission != .granted || authStatus != .authorized {
            let dialogActions = [
                DialogAction(
                    title: "Grant Permission",
                    voiceCommand: .GRANT_PERMISSION,
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
                    voiceCommand: .CANCEL_DIALOG,
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
            if !self.speechRecognition.isListeningForSpeech && !self.isExportingEntry {
                if voiceCommand {
                    // Play Sound
                    soundEngine.voiceCommandAccept()
                }
                
                // Navigate to detail page if we're not there already
                NotificationCenter.default.post(
                    name: EntryManager.onNavigateToDetailPage,
                    object: nil,
                    userInfo: [:]
                )
                
                print("\tStarting Entry...")
                self.speechRecognition.startListeningForSpeech() {
                    self.notifications.executeFeedback(
                        visualMessage: "Edit Entry",
                        audioMessage: "entry editing started",
                        withHaptics: true,
                        delay: 0
                    )
                    handler?()
                }
            } else {
                self.notifications.executeError(
                    text: "Unable to start entry.",
                    voiceCommand: voiceCommand,
                    handler: handler
                )
                print("\t[Error] There was a problem starting entry. System does not have record permissions.")
            }
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func stopEntry(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Stop Entry =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to stop it.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if self.speechRecognition.isListeningForSpeech && !self.isExportingEntry {
            print("\tStopping Entry...")
            if voiceCommand {
                // No sound here
                // We omit sound for stopping entry
            }

            self.speechRecognition.stopListeningForSpeech() {
                // Perform finish cleanup
                // We handle finish for voice commands within Entry
                // We might also get a call fro within entry
                // if we receive final speech update from speech recognition engine
                entry.handleFinish(normalize: true)
                
                // Present feedback
                self.notifications.executeFeedback(
                    visualMessage: "Stop Entry",
                    audioMessage: "entry stopped",
                    withHaptics: true,
                    delay: 0
                )
                
                handler?()
            }
        } else {
            if !self.speechRecognition.isListeningForSpeech {
                self.notifications.executeError(
                    text: "No ongoing entry.",
                    voiceCommand: voiceCommand,
                    handler: handler
                )
            } else {
                self.notifications.executeError(
                    text: "Wait until entry export completion.",
                    voiceCommand: voiceCommand,
                    handler: handler
                )
            }
            print("\t[Error] There was a problem stopping entry. We're not listening for speech or are exporting entry.")
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    // Should never be called when headphones on while we have a selection
    // Will be looping selection and have isPlayingEntry set to true
    // Which should hide playButton
    func playEntry(from startTime: CMTime = CMTime.zero, voiceCommand: Bool = false, onStartHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
        print("===== Entry Manager: Play \(self.selectionCursor.hasSelection ? "Selection" : "Entry") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: onFinishHandler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let playSegments: (_ segments: [EntrySegment]) -> Void = { segments in
            self.speechPlayer.play(
                segments: segments,
                onStartHandler: onStartHandler,
                onFinishHandler: onFinishHandler
            )
        }
        
        let executePlay = {
            if self.pausedWalkingEntry || self.pausedRunningEntry {
                print("\tPlay \(self.pausedWalkingEntry ? "walking" : "running") range.")
                playSegments(Array(entry.entrySegments[self.walkingRange!]))
            } else if let selectionSegments = self.selectionCursor.selectionSegments, self.selectionCursor.hasSelection {
                print("\tPlay selection.")
                playSegments(selectionSegments)
            } else {
                // Navigate to detail page if we're not there already
                NotificationCenter.default.post(
                    name: EntryManager.onNavigateToDetailPage,
                    object: nil,
                    userInfo: [:]
                )
                
                print("\tPlay entry from: \(startTime.seconds)")
                self.speechPlayer.play(
                    entry: entry,
                    from: startTime,
                    onStartHandler: onStartHandler,
                    onFinishHandler: onFinishHandler
                )
                
                // increment play count
                // Only increment if we're playing from the start
                if startTime == CMTime.zero &&
                    !self.entryListManager.isWalkingEntryList &&
                    !self.entryListManager.isRunningEntryList
                {
                    self.currentEntry?.incrementPlayCount()
                }
            }
        }
        
        if self.isWalkingEntry || self.isRunningEntry {
            print("\tIs currently \(self.isWalkingEntry ? "walking" : "running"). Stop and play \(self.selectionCursor.hasSelection ? "selection" : "entry").")
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
            print("\tIs currently playing prior speech. Stop and play new \(self.selectionCursor.hasSelection ? "selection" : "entry").")
            self.speechPlayer.stop(withFeedback: false) {
                executePlay()
            }
        } else {
            executePlay()
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func stopPlayingEntry(withFeedback: Bool = true, voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Stop Playing \(self.selectionCursor.hasSelection ? "Selection" : "Entry") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Stop Entry
        self.speechPlayer.stop(withFeedback: withFeedback) { [weak self] in
            if self!.pausedWalkingEntry {
                entry.walk() {
                    handler?()
                }
            } else if self!.pausedRunningEntry {
                entry.run() {
                    handler?()
                }
            } else {
                handler?()
            }
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func echoEntry(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Echo \(self.selectionCursor.hasSelection ? "Selection" : "Entry") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
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
            var segments: [EntrySegment]
            if self.pausedWalkingEntry || self.pausedRunningEntry {
                segments = Array(entry.entrySegments[self.walkingRange!])
            } else if self.selectionCursor.hasSelection {
                segments = self.selectionCursor.selectionSegments!
            } else {
                // Navigate to detail page if we're not there already
                NotificationCenter.default.post(
                    name: EntryManager.onNavigateToDetailPage,
                    object: nil,
                    userInfo: [:]
                )
                
                segments = entry.entrySegments
            }
            self.speechSynthesis.startEcho(
                segments: segments,
                onFinishHandler: { [weak self] in
                    if self!.pausedWalkingEntry {
                        entry.walk() {
                            handler?()
                        }
                    } else if self!.pausedRunningEntry {
                        entry.run() {
                            handler?()
                        }
                    } else {
                        handler?()
                    }
                }
            )
        }
        
        if self.isWalkingEntry || self.isRunningEntry {
            entry.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
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
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func stopEcho(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Stop Echo =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.speechSynthesis.isPlayingEcho && !self.speechSynthesis.isPlayingPassiveEcho {
            self.notifications.executeError(
                text: "Entry not being echoed.",
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
                if self!.pausedWalkingEntry {
                    entry.walk() {
                        handler?()
                    }
                } else if self!.pausedRunningEntry {
                    entry.run() {
                        handler?()
                    }
                } else {
                    handler?()
                }
            }
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func walkEntry(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Walk \(self.selectionCursor.hasSelection ? "Selection" : "Entry") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Navigate to detail page if we're not there already
        NotificationCenter.default.post(
            name: EntryManager.onNavigateToDetailPage,
            object: nil,
            userInfo: [:]
        )
        
        if let selectionSegments = self.selectionCursor.selectionSegments, self.selectionCursor.hasSelection {
            // Walk Selection
            entry.walk(segments: selectionSegments, onStartHandler: handler)
        } else {
            // Walk Entry
            entry.walk(onStartHandler: handler)
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    // Reference: https://www.hackingwithswift.com/example-code/system/how-to-copy-text-to-the-clipboard-using-uipasteboard
    func exportEntry(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Export \(self.selectionCursor.hasSelection ? "Selection" : "Entry") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if let selectionTimeRange = self.selectionCursor.selectionTimeRange, let entry = self.currentEntry, self.selectionCursor.hasSelection {
            // Export Selection
            let dialogActions = [
                DialogAction(
                    title: "Export Audio",
                    voiceCommand: .EXPORT_AUDIO,
                    feedbackVisualMessage: "Exporting audio",
                    feedbackAudioMessage: "Exporting audio. Select selection destination on the screen.",
                    style: .default,
                    handler: { [weak self] action in
                    self?.isExportingEntry = true
                    let selectionFilename = "entry-\(UUID().uuidString)"
                    
                    Utils.exportEntry(
                        state: self!.state,
                        entry: entry,
                        filename: selectionFilename,
                        fileType: entry.fileType,
                        timeRange: selectionTimeRange
                    ) { entryURL in
                        self?.isExportingEntry = false
                        handler?()
                        
                        NotificationCenter.default.post(
                            name: EntryManager.onEntryAudioExported,
                            object: nil,
                            userInfo: [ "entryURL" : entryURL]
                        )
                    }
                }),
                DialogAction(
                    title: "Export Text",
                    voiceCommand: .EXPORT_TEXT,
                    feedbackVisualMessage: "Selection text copied!",
                    feedbackAudioMessage: "Selection text copied to clipboard",
                    style: .default,
                    handler: { [weak self]  action in
                    let pasteboard = UIPasteboard.general
                    pasteboard.string = self!.selectionCursor.selectionText
                }),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: .CANCEL_DIALOG,
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
        } else if let entry = self.currentEntry {
            // Export Entry
            let dialogActions = [
                DialogAction(
                    title: "Export Audio",
                    voiceCommand: .EXPORT_AUDIO,
                    feedbackVisualMessage: "Exporting audio",
                    feedbackAudioMessage: "Exporting audio. Select entry destination on the screen.",
                    style: .default,
                    handler: { [weak self]  action in
                    self?.isExportingEntry = true
                    let selectionFilename = "entry-\(UUID().uuidString)"
                    
                    Utils.exportEntry(
                        state: self!.state,
                        entry: entry,
                        filename: selectionFilename,
                        fileType: entry.fileType,
                        timeRange: entry.timeRange
                    ) { entryURL in
                        self?.isExportingEntry = false
                        handler?()
                        
                        NotificationCenter.default.post(
                            name: EntryManager.onEntryAudioExported,
                            object: nil,
                            userInfo: [ "entryURL" : entryURL]
                        )
                    }
                    
                    // Increment Entry Audio Export Count
                    entry.incrementAudioExportCount()
                }),
                DialogAction(
                    title: "Export Text",
                    voiceCommand: .EXPORT_TEXT,
                    feedbackVisualMessage: "Selection text copied!",
                    feedbackAudioMessage: "Selection text copied to clipboard",
                    style: .default,
                    handler: { action in
                    let pasteboard = UIPasteboard.general
                    pasteboard.string = entry.getText()
                    
                    // Increment Entry Text Export Count
                    entry.incrementTextExportCount()
                }),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: .CANCEL_DIALOG,
                    feedbackVisualMessage: "Canceled!",
                    feedbackAudioMessage: "Command canceled.",
                    style: .cancel,
                    handler: nil
                )
            ]
            
            let dialogItem = DialogItem(
                title: "Export Entry",
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
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func runEntry(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Run \(self.selectionCursor.hasSelection ? "Selection" : "Entry") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Navigate to detail page if we're not there already
        NotificationCenter.default.post(
            name: EntryManager.onNavigateToDetailPage,
            object: nil,
            userInfo: [:]
        )
        
        if let selectionSegments = self.selectionCursor.selectionSegments, self.selectionCursor.hasSelection {
            // Run Selection
            entry.run(segments: selectionSegments, onStartHandler: handler)
        } else {
            // Run Entry
            entry.run(onStartHandler: handler)
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func pauseEntry(withFeedback: Bool = true, voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Pause \(self.selectionCursor.hasSelection ? "Selection" : "Entry") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if self.speechPlayer.isPlayingEntry {
            print("\tPausing Playing Entry...")
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
            print("\tPausing Listening Entry....")
            guard self.speechRecognition.isListeningForSpeech else {
                self.notifications.executeError(
                    text: "Must be editing entry to pause it.",
                    voiceCommand: true,
                    handler: handler
                )
                return
            }
            
            self.speechRecognition.pauseListeningForSpeech(userInitiated: true) {
                if withFeedback {
                    self.notifications.executeFeedback(
                        visualMessage: "Pause Entry",
                        audioMessage: "entry paused",
                        withHaptics: true
                    )
                }
                
                handler?()
            }
        } else {
            print("\tUnhandled Branch")
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func playCommit(voiceCommand: Bool = false, onStartHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
        print("===== Entry Manager: Play Commit =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: onFinishHandler
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to play last commit.",
                voiceCommand: true,
                handler: onStartHandler
            )
            return
        }
        
        if entry.committedBufferRanges.count == 0 {
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
            let commit = entry.getLastCommit()
            print("\tLast Commit: ", entry.getText(segments: commit))
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
                entry: entry,
                from: fromTime,
                to: toTime,
                onStartHandler: onStartHandler,
                onFinishHandler: onFinishHandler
            )
        }
        
        if self.isWalkingEntry || self.isRunningEntry {
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
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func pauseEcho(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Pause Echo =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.speechSynthesis.isPlayingEcho {
            self.notifications.executeError(
                text: "Entry not being echoed.",
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
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func skipBackward(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Skip Backward =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard self.speechPlayer.isPlayingEntry else {
            self.notifications.executeError(
                text: "No entry currently playing.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let currentSegment = self.speechPlayer.getCurrentSegment()
        
        if let currentSegment = currentSegment, self.speechPlayer.isPlayingEntry, CMTimeMake(
            value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
        ) > CMTime.zero {
            let time = CMTimeMake(
                value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
                timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
            )
            self.speechPlayer.skip(to: time)
            
        } else if let currentSegment = currentSegment, self.speechPlayer.isPlayingEntry, CMTimeMake(
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
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func skipForward(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Skip Forward =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard self.speechPlayer.isPlayingEntry else {
            self.notifications.executeError(
                text: "No entry currently playing.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let currentSegment = self.speechPlayer.getCurrentSegment()
        
        if let currentSegment = currentSegment, let currentItem = self.speechPlayer.player.currentItem, self.speechPlayer.isPlayingEntry, CMTimeMake(
            value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
        ) < currentItem.duration {
            let time = CMTimeMake(
                value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
                timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
            )
            self.speechPlayer.skip(to: time)
        } else if let currentSegment = currentSegment, let currentItem = self.speechPlayer.player.currentItem, self.speechPlayer.isPlayingEntry, CMTimeMake(
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
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func walkNextWord(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Walk Next Word =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isWalkingEntry {
            self.notifications.executeError(
                text: "Not walking \(self.selectionCursor.hasSelection ? "selection" : "entry").",
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        entry.walkToNextSegment(handler: handler)

        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func walkPreviousWord(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Walk Previous Word =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isWalkingEntry {
            self.notifications.executeError(
                text: "Not walking \(self.selectionCursor.hasSelection ? "selection" : "entry").",
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        entry.walkToPreviousSegment(handler: handler)
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func pauseRun(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Pause Run =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isRunningEntry {
            self.notifications.executeError(
                text: "Not running \(self.selectionCursor.hasSelection ? "selection" : "entry").",
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        entry.pauseRun(handler: handler)
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func exitWalkRun(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Exit Walk Run =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isWalkingEntry && !self.isRunningEntry {
            self.notifications.executeError(
                text: "Not walking or running \(self.selectionCursor.hasSelection ? "selection" : "entry").",
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        entry.exitWalk() {
            handler?()
            NotificationCenter.default.post(
                name: EntryManager.onExecuteEntryAction,
                object: nil,
                userInfo: ["type": VoiceCommandEngine.VoiceCommand.EXIT_WALK]
            )
        }
        
        checkRep()
    }
    
    func increaseRateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Increase Rate Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        print("\tRegistering a entry change to the Undo Manager...")
        self.registerEntryChange(entry: entry, undo: "selecting '\(self.selectionCursor.selectionText ?? "speech")'") { [weak self] in
            self?.selectionCursor.adjustRateSelection(direction: .up) { [weak self] rate in
                print("\tRegistering a entry change to the Undo Manager...")
                self?.registerEntryChange(
                    entry: self!.currentEntry!,
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
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func decreaseRateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Decrease Rate Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        print("\tRegistering a entry change to the Undo Manager...")
        self.registerEntryChange(entry: entry, undo: "selecting '\(self.selectionCursor.selectionText ?? "speech")'") { [weak self] in
            self?.selectionCursor.adjustRateSelection(direction: .down) { [weak self] rate in
                print("\tRegistering a entry change to the Undo Manager...")
                self?.registerEntryChange(
                    entry: self!.currentEntry!,
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
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func deleteSelection(voiceCommand: Bool = false, isCommit: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Delete Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        let undoMessage = "deleting '\(self.selectionCursor.selectionText ?? "selection")'"
        
        print("\tRegistering a entry change to the Undo Manager...")
        self.registerEntryChange(entry: entry, undo: "selecting '\(self.selectionCursor.selectionText ?? "speech")'") { [weak self] in
            self?.selectionCursor.deleteSelection(isCommit: isCommit) { [weak self] in
                print("\tRegistering a entry change to the Undo Manager...")
                self?.registerEntryChange(
                    entry: self!.currentEntry!,
                    undo: undoMessage,
                    handler: handler
                )
            }
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func updateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Update Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        // Turn on ambient track
        if !soundEngine.isPlayingModalAmbience {
            soundEngine.startModalAmbience()
        }
        
        // Execute update selection
        self.selectionCursor.initiateUpdateSelection()

        handler?()
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func acceptUpdateSelection(
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Accept Update Selection =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if self.selectionCursor.hasSelection && self.selectionCursor.isUpdatingSelection && self.selectionCursor.isPromptingForUpdateAcceptance {
            // Turn off ambient track
            soundEngine.stopModalAmbience()

            // Clear buffer segments
            print("\tClearing entry buffer...")
            entry.clearBuffer()
            
            print("\tRegistering a entry change to the Undo Manager...")
            self.registerEntryChange(entry: entry, undo: "selecting '\(self.selectionCursor.selectionText ?? "speech")'") { [weak self] in
                self?.selectionCursor.acceptUpdateSelection(handler: { [weak self] in
                    print("\tRegistering a entry change to the Undo Manager...")
                    self?.registerEntryChange(
                        entry: self!.currentEntry!,
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
        print("===== Entry Manager: Redo Update Selection =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
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
            print("\tClearing entry buffer...")
            entry.clearBuffer()
            
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
        print("===== Entry Manager: Cancel Update Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
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
            print("\tClearing entry buffer...")
            entry.clearBuffer()
            
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
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: ["type": VoiceCommandEngine.VoiceCommand.CANCEL_SELECTION_UPDATE]
        )
        
        checkRep()
    }
    
    func copySelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Copy Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        self.selectionCursor.copySelection()
        
        handler?()
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func cutSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Cut Selection: \(self.selectionCursor.selectionText ?? "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
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
        
        print("\tRegistering a entry change to the Undo Manager...")
        self.registerEntryChange(entry: entry, undo: "selecting '\(self.selectionCursor.selectionText ?? "speech")'") { [weak self] in
            self?.selectionCursor.cutSelection() { [weak self] in
                print("\tRegistering a entry change to the Undo Manager...")
                self?.registerEntryChange(
                    entry: self!.currentEntry!,
                    undo: undoMessage,
                    handler: handler
                )
            }
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func pasteClipboard(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Paste Clipboard: \(self.selectionCursor.clipboard != nil ? Entry.getText(segments: self.selectionCursor.clipboard!) : "nil") =====")
        if !voiceCommand {
            print("\tTriggered by screen button.")
        } else {
            print("\tTriggered by voice command.")
        }
        
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard let _ = self.selectionCursor.clipboard else {
            self.notifications.executeError(
                text: "Clipboard is empty.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let undoMessage = "pasting '\(self.selectionCursor.clipboard != nil ? Entry.getText(segments: self.selectionCursor.clipboard!) : "clipboard")'"
        
        print("\tRegistering a entry change to the Undo Manager...")
        self.registerEntryChange(entry: entry, undo: "moving cursor") { [weak self] in
            self?.selectionCursor.pasteClipboard() { [weak self] in
                print("\tRegistering a entry change to the Undo Manager...")
                self?.registerEntryChange(
                    entry: self!.currentEntry!,
                    undo: undoMessage,
                    handler: handler
                )
            }
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func selectCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Select Commit =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to select last commit.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if entry.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let commit = entry.getLastCommit()
        print("\tLast Commit: ", entry.getText(segments: commit))
        guard let lastCommit = commit else {
            self.notifications.executeError(
                text: "Unable to find last commit.",
                handler: handler
            )
            return
        }
        
        let newAnchor: EntrySegment?  = lastCommit.first
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
        
        let newFocus: EntrySegment? = lastCommit.last
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
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func rollbackCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Rollback Commit =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to rollback last commit.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if entry.committedBufferRanges.count == 0 {
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
            print("\tRegistering a entry change to the Undo Manager...")
            self.registerEntryChange(entry: entry, undo: "moving cursor") { [weak self] in
                // Select Previous Commit
                self?.selectCommit()
                
                // Delete current selection
                self?.selectionCursor.deleteSelection(isCommit: true) { [weak self] in
                    print("\tRegistering a entry change to the Undo Manager...")
                    self?.registerEntryChange(
                        entry: self!.currentEntry!,
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
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func walkCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Walk Commit =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to walk last commit.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if entry.committedBufferRanges.count == 0 {
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
        self.walkEntry(voiceCommand: true, handler: handler)
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func runCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Run Commit =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to run last commit.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if entry.committedBufferRanges.count == 0 {
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
        self.runEntry(voiceCommand: true, handler: handler)
        
        NotificationCenter.default.post(
            name: EntryManager.onExecuteEntryAction,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func enterSelection(
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Enter Selection =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to make selection.",
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
                    segments: entry.entrySegments,
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
                    segments: entry.entrySegments,
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
            let selection = entry.entrySegments[selectionIndex]
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
        print("===== Entry Manager: Remove Selection =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to remove selection.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
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
                    name: Entry.onRequestToUpdateView,
                    object: nil,
                    userInfo: [:]
                )
            }
            
            handler?()
        }
        
        if self.isWalkingEntry || self.isRunningEntry {
            print("\tIs \(self.isWalkingEntry ? "walking" : "running") entry. Stop runnning then execute 'remove selection' command...")
            entry.exitWalk(clearSelection: false, withFeedback: false) {
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
        print("===== Entry Manager: Shift Anchor \(direction == .left ? "Left" : "Right") =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        var newAnchorIndex: Int?
        if let currentAnchor = self.selectionCursor.anchor, direction == .left {
            newAnchorIndex = Utils.getSegmentIndex(
                segment: currentAnchor,
                segments: entry.entrySegments,
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
                segments: entry.entrySegments,
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
        print("===== Entry Manager: Shift Focus \(direction == .left ? "Left" : "Right") =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
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
                segments: entry.entrySegments,
                type: .previous,
                isWord: true
            )
        } else if let currentFocus = self.selectionCursor.focus,
            direction == .right
        {
            newFocusIndex = Utils.getSegmentIndex(
                segment: currentFocus,
                segments: entry.entrySegments,
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
        print("===== Entry Manager: Shift Selection =====")
        print("\tTriggered by voice command.")
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
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
        print("===== Entry Manager: Expand Selection =====")
        print("\tTriggered by voice command.")
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
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
        print("===== Entry Manager: Reduce Selection =====")
        print("\tTriggered by voice command.")
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
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
        print("===== Entry Manager: Echo Commit =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if entry.committedBufferRanges.count == 0 {
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
            let commit = entry.getLastCommit()
            print("\tLast Commit: ", entry.getText(segments: commit))
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
                        name: Entry.onRequestToUpdateView,
                        object: nil,
                        userInfo: [:]
                    )
                },
                onFinishHandler: {
                    NotificationCenter.default.post(
                        name: Entry.onRequestToUpdateView,
                        object: nil,
                        userInfo: [:]
                    )
                    if self.pausedWalkingEntry {
                        entry.walk() {
                            handler?()
                        }
                    } else if self.pausedRunningEntry {
                        entry.run() {
                            handler?()
                        }
                    } else {
                        handler?()
                    }
                }
            )
        }
        
        if self.isWalkingEntry || self.isRunningEntry {
            entry.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
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
        print("===== Entry Manager: Echo Previous Sentence =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to echo previous sentence.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        if entry.entrySegments.count == 0 {
            self.notifications.executeError(
                text: "Entry is empty.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        let previousSentenceIndex = max(entry.sentenceCount - 1, 0)
        
        if entry.sentenceCount == 1 {
            self.notifications.executeError(
                text: "No previous sentence exists.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()

        entry.echoSentence(number: previousSentenceIndex, onFinishHandler: handler)
    }
    
    func playPreviousSentence(
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Play Previous Sentence =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to play previous sentence.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
    
        if entry.entrySegments.count == 0 {
            self.notifications.executeError(
                text: "Entry is empty.",
                voiceCommand: true,
                handler: handler
            )
            return
        }

        let executePlay = {
            let previousSentenceIndex = max(entry.sentenceCount - 1, 0)
            
            if entry.sentenceCount == 1 {
                self.notifications.executeError(
                    text: "No previous sentence exists.",
                    voiceCommand: true,
                    handler: handler
                )
                return
            }
            
            // Play Sound
            soundEngine.voiceCommandAccept()

            entry.playSentence(number: previousSentenceIndex)
        }
        
        if self.isWalkingEntry || self.isRunningEntry {
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
    }
    
    // MARK: - Undo/Redo Methods
    
    // message should start with a present progressive verb: -ing
    // so utterance will be: undo verb-ing object
    func registerEntryChange(entry: Entry, undo message: String, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Register Entry Change  =====")

        // Update Undo/Redo History
        print("\tCreating and setting new snapshot...")
        
        let newSnapshot = EntrySnapshot(
            entry: entry.duplicate(), // we duplicate so there's no memory leaks/pointers to same memory locations
            selectionAnchorCaret: self.selectionCursor.anchorCaret?.duplicate(),
            selectionFocusCaret: self.selectionCursor.focusCaret?.duplicate(),
            selectionCachedAnchorCaret: self.selectionCursor.cachedAnchorCaret?.duplicate(),
            undo: message
        )
        
        self.entryChangeHandler = handler
        
        self.modifyEntry(snapshot: newSnapshot)
        
        checkRep()
    }
    
    @objc func undo(handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Undo  =====")
        let executeUndo = {
            let undoMessage = self.currentEntryUndoSnapshot!.message
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
        print("===== Entry Manager: Redo  =====")
        
        let executeRedo = {
            self.undoManager.redo()
            let redoMessage = self.currentEntryUndoSnapshot!.message
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
    
    func setCurrentEntry(index: Int? = nil) {
        print("===== Entry Manager: Set Current Entry =====")
        print("\tSet index to: ", index ?? "nil")
        if let index = index {
            self.currentIndex = index
            self.setEntryModules(index: index)
            // Increment Entry Views
            if !self.entryListManager.isWalkingEntryList &&
                !self.entryListManager.isRunningEntryList
            {
                self.currentEntry!.incrementViewCount()
            }
            
            self.currentEntryUndoSnapshot = EntrySnapshot(
                entry: self.currentEntry!.duplicate(), // we duplicate so there's no memory leaks/pointers to same memory locations
                selectionAnchorCaret: self.selectionCursor.anchorCaret,
                selectionFocusCaret: self.selectionCursor.focusCaret,
                selectionCachedAnchorCaret: self.selectionCursor.cachedAnchorCaret,
                undo: "to start of entry"
            )
            
            print("Entry Segments: ", Utils.stringifySegments(segments: self.currentEntry!.entrySegments))
        } else {
            self.currentIndex = nil
            self.currentEntryUndoSnapshot = nil
            self.undoManager.removeAllActions()
        }

        var userInfo: [String : Int] = [:]
        if let currentIndex = self.currentIndex {
            userInfo["currentEntryIndex"] = currentIndex
        }

        checkRep()
    }
    
    func setWalkingIndex(index: Int) {
        print("===== Entry Manager: Set Walking Index =====")
        print("\tSet index to: ", index)
        self.walkingIndex = index
        
        checkRep()
    }
    
    func setWalkingRange(range: Range<Int>? = nil) {
        print("===== Entry Manager: Set Walking Range =====")
        print("\tSet range to: ", range ?? "nil")
        self.walkingRange = range
        
        checkRep()
    }
    
    func setIsWalkingEntry(to isWalking: Bool) {
        print("===== Entry Manager: Set Is Walking Entry =====")
        print("\tSet to: ", isWalking)
        self.isWalkingEntry = isWalking
        
        checkRep()
    }
    
    func setIsRunningEntry(to isRunning: Bool) {
        print("===== Entry Manager: Set Is Running Entry =====")
        print("\tSet to: ", isRunning)
        self.isRunningEntry = isRunning
        
        checkRep()
    }
    
    func setPausedWalkingEntry(to paused: Bool) {
        print("===== Entry Manager: Set Paused Walking Entry =====")
        print("\tSet to: ", paused)
        self.pausedWalkingEntry = paused
        
        checkRep()
    }
    
    func setPausedRunningEntry(to paused: Bool) {
        print("===== Entry Manager: Set Paused Running Entry =====")
        print("\tSet to: ", paused)
        self.pausedRunningEntry = paused
        
        checkRep()
    }
    
    func setWalkingTimer(timer: Timer? = nil) {
        print("===== Entry Manager: Set Walking Timer =====")
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
        print("===== Entry Manager: Set Walk Loop Delay Timer =====")
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
        print("===== Entry Manager: Set Echo Delay Timer =====")
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
        print("===== Entry Manager: Set Running Timer =====")
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

extension EntryManager {
  
    private func modifyEntry(snapshot: EntrySnapshot) {

        let oldSnapshot: EntrySnapshot = self.currentEntryUndoSnapshot!

        let stateDiff = oldSnapshot.diffed(with: snapshot)
        stateDidChange(diff: stateDiff)
    }

    private func stateDidChange(diff: EntrySnapshot.Diff) {

        guard diff.hasChanges else { return }

        self.currentEntryUndoSnapshot = diff.to

        self.undoManager.registerUndo(withTarget: self) { target in
            target.modifyEntry(snapshot: diff.from)
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onUndoManagerChange,
            object: nil,
            userInfo: [
                "canUndo": self.undoManager.canUndo,
                "canRedo": self.undoManager.canRedo
            ]
        )
    }
}
