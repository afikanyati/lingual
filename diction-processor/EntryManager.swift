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
    static let onSelectionDeleted = Notification.Name(Notifications.onSelectionDeleted.rawValue)
    static let onStartedEntryAudioExport = Notification.Name(Notifications.onStartedEntryAudioExport.rawValue)
    static let onStoppedEntryAudioExport = Notification.Name(Notifications.onStoppedEntryAudioExport.rawValue)
    static let onStartedEntrySetting = Notification.Name(Notifications.onStartedEntrySetting.rawValue)
    static let onStoppedEntrySetting = Notification.Name(Notifications.onStoppedEntrySetting.rawValue)

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
        if let index = self.currentIndex, self.state.activeEntries.count > index {
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
    /// Stores flag of whether we should not accept entry snapshot update after commit
    private(set) var ignoreEntrySnapshotUpdate = false
    /// Stores whether we're setting entry
    private(set) var isSettingEntry = false
    
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
        self._undoManager.groupsByEvent = false
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        // End active timers
        self.invalidateTimers()

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
        
        // App
        notificationCenter.addObserver(
            self,
            selector: #selector(self.appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
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
    
    @objc func appWillTerminate() {
        print("===== Entry Manager: App Will Terminate =====")
        
        self.invalidateTimers()
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
            if let entry = self.currentEntry,
               Utils.getNavigationController()?.visibleViewController as? EntryTableViewController != nil ||
               entry.entrySegments.count > 0 {
                // If we're in Detail Page, only create new entry if the current one has content
                // If we're in Entry Table, also start a new one
                print("\tFound existing entry after receving 'start entry' via voice command. Remove it to trigger new entry creation.")
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
                    voiceCommand: true
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
                    voiceCommand: true
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
                scale: .all,
                handler: handler
            )
        case .SELECT_WORD:
            self.enterSelection(
                scale: .word,
                handler: handler
            )
        case .SELECT_SENTENCE:
            self.enterSelection(
                scale: .sentence,
                handler: handler
            )
        case .SELECT_PARAGRAPH:
            self.enterSelection(
                scale: .paragraph,
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
                direction: .backwards,
                by: 1,
                handler: handler
            )
        case .SHIFT_ANCHOR_RIGHT:
            self.shiftAnchor(
                direction: .forwards,
                by: 1,
                handler: handler
            )
        case .SHIFT_FOCUS_LEFT:
            self.shiftFocus(
                direction: .backwards,
                by: 1,
                handler: handler
            )
        case .SHIFT_FOCUS_RIGHT:
            self.shiftFocus(
                direction: .forwards,
                by: 1,
                handler: handler
            )
        case .SHIFT_SELECTION_FORWARD:
            self.shiftSelection(
                direction: .forwards,
                handler: handler
            )
        case .SHIFT_SELECTION_BACKWARD:
            self.shiftSelection(
                direction: .backwards,
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
               let _ = change?[.oldKey] as? EntrySnapshot,
               !self.ignoreEntrySnapshotUpdate
            {
                print("\tUndo/Redo Entry Snapshot Received! Save to state...")
                let duplicateEntry = newSnapshot.entry

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

                // Make sure all data is correct
                duplicateEntry.refresh()

                // Set Entry
                print("\tSave entry into state...")
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
                    print("\tRunning Entry Change Handler...")
                    entryChangeHandler()
                    self.entryChangeHandler = nil
                }
                
            } else if let entry = self.currentEntry, self.ignoreEntrySnapshotUpdate {
                print("\tMost forward changes to entry snapshot are ignored...")
                
                print("\tUpdate View with text: '\(entry.getText())'")
                entry.handleOnSpeechUpdate(text: entry.getText())

                if let entryChangeHandler = self.entryChangeHandler {
                    print("\tRunning Save Handler...")
                    entryChangeHandler()
                    self.entryChangeHandler = nil
                }
            } else {
                print("\tNo new snapshot...")
                
                if let entryChangeHandler = self.entryChangeHandler {
                    print("\tRunning Save Handler...")
                    entryChangeHandler()
                    self.entryChangeHandler = nil
                }
            }
            
            self.ignoreEntrySnapshotUpdate = false
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        let executeEntry = {
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
        }
        
        if self.entryListManager.isRunningEntryList || self.entryListManager.isWalkingEntryList {
            print("\tCurrently walking entry list. Stop walking before entering entry...")
            self.entryListManager.exitWalkRun(withFeedback: false) {
                executeEntry()
            }
        } else {
            executeEntry()
        }
        
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
            self.notifications.executeError(
                text: "No entry selected",
                voiceCommand: voiceCommand
            )
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
                    feedbackAudioMessage: "Action canceled.",
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
                    self.speechRecognition.requestPermissions(handler: { [weak self] in
                        self?.speechRecognition.configureListening() { [weak self] in
                            self?.speechRecognition.startListeningForVoiceCommands()
                        }
                    })
                }),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: .CANCEL_DIALOG,
                    feedbackVisualMessage: "Canceled!",
                    feedbackAudioMessage: "Action canceled.",
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
                        voiceCommand: voiceCommand
                    )
                } else {
                    self.notifications.executeError(
                        text: "Wait until entry export completion.",
                        voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        if entry.entrySegments.count == 0 {
            self.notifications.executeError(
                text: "No existing entry.",
                voiceCommand: voiceCommand
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
                    self.speechRecognition.requestPermissions(handler: { [weak self] in
                        self?.speechRecognition.configureListening() { [weak self] in
                            self?.speechRecognition.startListeningForVoiceCommands()
                        }
                    })
                }),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: .CANCEL_DIALOG,
                    feedbackVisualMessage: "Canceled!",
                    feedbackAudioMessage: "Action canceled.",
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
                    voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to stop it.",
                voiceCommand: voiceCommand
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
                    voiceCommand: voiceCommand
                )
            } else {
                self.notifications.executeError(
                    text: "Wait until entry export completion.",
                    voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        if !self.speechSynthesis.isPlayingEcho && !self.speechSynthesis.isPlayingPassiveEcho {
            self.notifications.executeError(
                text: "Entry not being echoed.",
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
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
                    NotificationCenter.default.post(
                        name: EntryManager.onStartedEntryAudioExport,
                        object: nil,
                        userInfo: [:]
                    )
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        Utils.exportEntry(
                            state: self!.state,
                            entry: entry,
                            timeRange: selectionTimeRange
                        ) { entryURL in
                            self?.isExportingEntry = false
                            handler?()
                            
                            NotificationCenter.default.post(
                                name: EntryManager.onStoppedEntryAudioExport,
                                object: nil,
                                userInfo: [:]
                            )
                            NotificationCenter.default.post(
                                name: EntryManager.onEntryAudioExported,
                                object: nil,
                                userInfo: [ "entryURL" : entryURL]
                            )
                        }
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
                    feedbackAudioMessage: "Action canceled.",
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
                    NotificationCenter.default.post(
                        name: EntryManager.onStartedEntryAudioExport,
                        object: nil,
                        userInfo: [:]
                    )

                    #if DEBUG
                    let selectionFilename = "entry-\(UUID().uuidString)"
                    let _ = Utils.encodeLingualEntry(entry: entry, filename: entry.filename)
                    NotificationCenter.default.post(
                        name: EntryManager.onStoppedEntryAudioExport,
                        object: nil,
                        userInfo: [:]
                    )
                    NotificationCenter.default.post(
                        name: EntryManager.onEntryAudioExported,
                        object: nil,
                        userInfo: [ "entryURL" : selectionFilename]
                    )
                    #else
                    DispatchQueue.global(qos: .userInitiated).async {
                        Utils.exportEntry(
                            state: self!.state,
                            entry: entry,
                            timeRange: entry.timeRange
                        ) { entryURL in
                            self?.isExportingEntry = false
                            handler?()

                            NotificationCenter.default.post(
                                name: EntryManager.onStoppedEntryAudioExport,
                                object: nil,
                                userInfo: [:]
                            )
                            NotificationCenter.default.post(
                                name: EntryManager.onEntryAudioExported,
                                object: nil,
                                userInfo: [ "entryURL" : entryURL]
                            )
                            
                            // Increment Entry Audio Export Count
                            entry.incrementAudioExportCount()
                        }
                    }
                    #endif
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
                    feedbackAudioMessage: "Action canceled.",
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
                voiceCommand: voiceCommand
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
                    voiceCommand: voiceCommand
                )
                return
            }
            
            self.speechRecognition.pauseListeningForSpeech(userInitiated: true) {
                if withFeedback {
                    self.notifications.executeFeedback(
                        visualMessage: "Pause Entry",
                        audioMessage: "entry paused",
                        withHaptics: voiceCommand
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to play last commit.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        if entry.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let executePlay = {
            let commit = entry.getLastCommit()
            guard let lastCommit = commit else {
                self.notifications.executeError(
                    text: "Unable to find last commit.",
                    voiceCommand: voiceCommand
                )
                return
            }
            print("\tLast Commit: ", Entry.getText(segments: lastCommit))
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        if !self.speechSynthesis.isPlayingEcho {
            self.notifications.executeError(
                text: "Entry not being echoed.",
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        if !self.isWalkingEntry {
            self.notifications.executeError(
                text: "Not walking \(self.selectionCursor.hasSelection ? "selection" : "entry").",
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        if !self.isWalkingEntry {
            self.notifications.executeError(
                text: "Not walking \(self.selectionCursor.hasSelection ? "selection" : "entry").",
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        if !self.isRunningEntry {
            self.notifications.executeError(
                text: "Not running \(self.selectionCursor.hasSelection ? "selection" : "entry").",
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        if !self.isWalkingEntry && !self.isRunningEntry {
            self.notifications.executeError(
                text: "Not walking or running \(self.selectionCursor.hasSelection ? "selection" : "entry").",
                voiceCommand: voiceCommand
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
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        self.selectionCursor.adjustRateSelection(direction: .up) { [weak self] rate in
            print("\tRegistering an entry change to the Undo Manager...")
            self?.registerEntryChange(
                entry: self!.currentEntry!,
                undo: "increasing selection rate",
                handler: handler
            )
            
            self?.notifications.executeFeedback(
                visualMessage: "Increase Selection Rate: \(rate.rounded(toPlaces: 2))",
                audioMessage: "increased selection rate to \(rate.rounded(toPlaces: 2))",
                discardPrior: true,
                withHaptics: true
            )
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
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        self.selectionCursor.adjustRateSelection(direction: .down) { [weak self] rate in
            print("\tRegistering an entry change to the Undo Manager...")
            self?.registerEntryChange(
                entry: self!.currentEntry!,
                undo: "decreasing selection rate",
                handler: handler
            )
            
            self?.notifications.executeFeedback(
                visualMessage: "Decrease Selection Rate: \(rate.rounded(toPlaces: 2))",
                audioMessage: "decreased selection rate to \(rate.rounded(toPlaces: 2))",
                discardPrior: true,
                withHaptics: true
            )
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
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        self.selectionCursor.deleteSelection(isCommit: isCommit) { [weak self] in
            print("\tRegistering an entry change to the Undo Manager...")
            self?.registerEntryChange(
                entry: self!.currentEntry!,
                undo: "deleting '\(self!.selectionCursor.selectionText ?? "selection")'",
                handler: handler
            )
        }
        
        NotificationCenter.default.post(
            name: EntryManager.onSelectionDeleted,
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
                voiceCommand: voiceCommand
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
                voiceCommand: true
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true
            )
            return
        }
        
        if self.selectionCursor.hasSelection && self.selectionCursor.isUpdatingSelection && self.selectionCursor.isPromptingForUpdateAcceptance {
            // Turn off ambient track
            soundEngine.stopModalAmbience()

            // Clear buffer segments
            print("\tClearing entry buffer...")
            entry.clearBuffer()
            
            self.selectionCursor.acceptUpdateSelection(handler: { [weak self] in
                print("\tRegistering an entry change to the Undo Manager...")
                self?.registerEntryChange(
                    entry: self!.currentEntry!,
                    undo: "replacing '\(self?.selectionCursor.selectionText ?? "selection")'",
                    handler: handler
                )
            })
        } else if !self.selectionCursor.hasSelection {
            self.notifications.executeError(
                text: "No existing selection.",
                voiceCommand: true
            )
        } else if !self.selectionCursor.isUpdatingSelection {
            self.notifications.executeError(
                text: "Say \"update\" to replace selection.",
                voiceCommand: true
            )
        } else if !self.selectionCursor.isPromptingForUpdateAcceptance {
            self.notifications.executeError(
                text: "No update yet.",
                voiceCommand: true
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
                voiceCommand: true
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true
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
                voiceCommand: true
            )
        } else if !self.selectionCursor.isUpdatingSelection {
            self.notifications.executeError(
                text: "Say \"update\" to replace selection.",
                voiceCommand: true
            )
        } else if !self.selectionCursor.isPromptingForUpdateAcceptance {
            self.notifications.executeError(
                text: "No update yet.",
                voiceCommand: true
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
            )
        } else if !self.selectionCursor.isUpdatingSelection {
            self.notifications.executeError(
                text: "Update mode not active.",
                voiceCommand: voiceCommand
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
                voiceCommand: voiceCommand
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: voiceCommand
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
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        self.selectionCursor.cutSelection() { [weak self] in
            print("\tRegistering an entry change to the Undo Manager...")
            self?.registerEntryChange(
                entry: self!.currentEntry!,
                undo: "cutting '\(self!.selectionCursor.selectionText ?? "selection")'",
                handler: handler
            )
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
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        guard let _ = self.selectionCursor.clipboard else {
            self.notifications.executeError(
                text: "Clipboard is empty.",
                voiceCommand: voiceCommand
            )
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        self.selectionCursor.pasteClipboard() { [weak self] in
            print("\tRegistering an entry change to the Undo Manager...")
            self?.registerEntryChange(
                entry: self!.currentEntry!,
                undo: "pasting '\(self!.selectionCursor.clipboard != nil ? Entry.getText(segments: self!.selectionCursor.clipboard!) : "clipboard")'",
                handler: handler
            )
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
                voiceCommand: true
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to select last commit.",
                voiceCommand: true
            )
            return
        }

        if entry.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let commit = entry.getLastCommit()
        guard let lastCommit = commit else {
            self.notifications.executeError(
                text: "Unable to find last commit.",
                voiceCommand: true
            )
            return
        }
        print("\tLast Commit: ", Entry.getText(segments: lastCommit))
        
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
                focusCaret: Caret(index: focusIndex, trackType: .committed),
                scale: .all
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
                voiceCommand: true
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to rollback last commit.",
                voiceCommand: true
            )
            return
        }

        if entry.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let executeRollback = {
            // Select Previous Commit
            self.selectCommit()
            
            // Delete current selection
            self.selectionCursor.deleteSelection(isCommit: true) { [weak self] in
                print("\tRegistering an entry change to the Undo Manager...")
                self?.registerEntryChange(
                    entry: self!.currentEntry!,
                    undo: "rolling back last commit",
                    handler: handler
                )
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
            name: EntryManager.onSelectionDeleted,
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
    
    func walkCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Walk Commit =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to walk last commit.",
                voiceCommand: true
            )
            return
        }

        if entry.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true
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
                voiceCommand: true
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to run last commit.",
                voiceCommand: true
            )
            return
        }

        if entry.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true
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
        scale: ScaleUnitType,
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Enter Selection =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }
        
        guard self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Must be editing entry to make selection.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let currentAnchor = self.selectionCursor.cachedAnchor ?? self.selectionCursor.anchor
        var anchorIndex: Int?
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
                anchorIndex = Utils.getSegmentIndex(
                    segment: segment,
                    segments: entry.entrySegments,
                    type: .previous,
                    isWord: true,
                    isCommitted: true
                )
            } else {
                anchorIndex = segment.getIndex()
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
                anchorIndex = Utils.getSegmentIndex(
                    segment: segment,
                    segments: entry.entrySegments,
                    type: .next,
                    isWord: true,
                    isCommitted: true
                )
            } else {
                anchorIndex = segment.getIndex()
            }
        }
        
        print("Anchor Index: ", anchorIndex ?? "nil")
        
        if let anchorIndex = anchorIndex, anchorIndex != Int(Utils.UNKNOWN) {
            let referenceSegment = entry.entrySegments[anchorIndex]
            print("\tFound reference segment: ", referenceSegment.getText())
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            print("\tFind selection...")
            switch (scale) {
            case .paragraph:
                let paragraphDetails = referenceSegment.getParagraph()
                print("Paragraph: ", paragraphDetails)
                var selectionStartIndex = paragraphDetails.entryRange.startIndex
                print("Selection Start Index: ", selectionStartIndex)
                if !entry.entrySegments[selectionStartIndex].isActive(),
                let index = Utils.getSegmentIndex(
                   segment: entry.entrySegments[selectionStartIndex],
                   segments: entry.entrySegments,
                   type: .next,
                   by: 1,
                   isWord: true
                ) {
                    selectionStartIndex = index
                    print("Updated Selection Start Index: ", selectionStartIndex)
                }
                var selectionEndIndex = paragraphDetails.entryRange.endIndex - 1
                print("Selection End Index: ", selectionEndIndex)
                if !entry.entrySegments[selectionEndIndex].isActive(),
                let index = Utils.getSegmentIndex(
                   segment: entry.entrySegments[selectionEndIndex],
                   segments: entry.entrySegments,
                   type: .previous,
                   by: 1,
                   isWord: true
                ) {
                    selectionEndIndex = index
                    print("Updated Selection End Index: ", selectionEndIndex)
                }
                print("\tSetting selection...")
                self.selectionCursor.setSelection(
                    anchorCaret: Caret(index: selectionStartIndex, trackType: .committed),
                    focusCaret: Caret(index: selectionEndIndex, trackType: .committed),
                    scale: scale,
                    scaleRange: paragraphDetails.entryRange
                )
            case .sentence:
                let sentenceDetails = referenceSegment.getSentence()
                print("Sentence: ", sentenceDetails)
                var selectionStartIndex = sentenceDetails.entryRange.startIndex
                print("Selection Start Index: ", selectionStartIndex)
                if !entry.entrySegments[selectionStartIndex].isActive(),
                let index = Utils.getSegmentIndex(
                   segment: entry.entrySegments[selectionStartIndex],
                   segments: entry.entrySegments,
                   type: .next,
                   by: 1,
                   isWord: true
                ) {
                    selectionStartIndex = index
                    print("Updated Selection Start Index: ", selectionStartIndex)
                }
                var selectionEndIndex = sentenceDetails.entryRange.endIndex - 1
                print("Selection End Index: ", selectionEndIndex)
                if !entry.entrySegments[selectionEndIndex].isActive(),
                let index = Utils.getSegmentIndex(
                   segment: entry.entrySegments[selectionEndIndex],
                   segments: entry.entrySegments,
                   type: .previous,
                   by: 1,
                   isWord: true
                ) {
                    selectionEndIndex = index
                    print("Updated Selection End Index: ", selectionEndIndex)
                }
                print("\tSetting selection...")
                self.selectionCursor.setSelection(
                    anchorCaret: Caret(index: selectionStartIndex, trackType: .committed),
                    focusCaret: Caret(index: selectionEndIndex, trackType: .committed),
                    scale: scale,
                    scaleRange: sentenceDetails.entryRange
                )
            default:
                if scale == .word {
                    print("\tUsing reference word...")
                } else {
                    print("\tUsing word: '\(referenceSegment.getText())'")
                }
                
                print("\tSetting selection...")
                self.selectionCursor.setSelection(
                    anchorCaret: Caret(index: anchorIndex, trackType: .committed),
                    focusCaret: Caret(index: anchorIndex, trackType: .committed),
                    scale: scale
                )
                break
            }
            
            var scaleName: String
            switch (scale) {
            case .word:
                scaleName = "word"
            case .sentence:
                scaleName = "sentence"
            case .paragraph:
                scaleName = "paragraph"
            default:
                scaleName = "passage"
            }

            self.notifications.executeFeedback(
                visualMessage: "\(scaleName.capitalizeFirstLetter()) selected!",
                withHaptics: true
            )
            
            handler?()
        } else {
            print("\t[Error] There was a problem making selection. Unable to locate suitable segment.")
            var scaleName: String
            switch (scale) {
            case .word:
                scaleName = "word"
            case .sentence:
                scaleName = "sentence"
            case .paragraph:
                scaleName = "paragraph"
            default:
                scaleName = "passage"
            }
            self.notifications.executeError(
                text: "Unable to locate suitable \(scaleName) to select.",
                voiceCommand: true
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
                voiceCommand: true
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true
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
        direction: SelectionDirection,
        by count: Int,
        withFeedback: Bool = true,
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Shift Anchor \(direction == .forwards ? "Forwards" : "Backwards") =====")
        print("\tTriggered by voice command.")
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true
            )
            return
        }
        
        if withFeedback {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let shifted = self.selectionCursor.shiftAnchorSegment(
            direction: direction,
            by: count
        )
        
        if shifted {
            if withFeedback {
                self.notifications.executeFeedback(
                    visualMessage: "Selection Updated!",
                    withHaptics: true
                )
            }
            print("\tShifted anchor \(direction == .forwards ? "forwards" : "backwards")")
            handler?()
        } else if let currentAnchor = self.selectionCursor.anchor,
              let currentFocus = self.selectionCursor.focus,
              currentAnchor.getUID() == currentFocus.getUID()
          {
              print("\tUnable to shift anchor forwards because we're selecting a single segment")
              self.notifications.executeError(
                  text: "Unable to shift before first word.",
                  voiceCommand: true
              )
          } else {
              print("\t[Error] There was a problem updating selection anchor. Unable to locate suitable segment.")
              self.notifications.executeError(
                text: "Unable to update selection.",
                voiceCommand: true
              )
          }
    }
    
    func shiftFocus(
        direction: SelectionDirection,
        by count: Int,
        withFeedback: Bool = true,
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Shift Focus \(direction == .forwards ? "Forwards" : "Backards") =====")
        print("\tTriggered by voice command.")
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true
            )
            return
        }
        
        if withFeedback {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let shifted = self.selectionCursor.shiftFocusSegment(
            direction: direction,
            by: count
        )
        
        if shifted {
            if withFeedback {
                self.notifications.executeFeedback(
                    visualMessage: "Selection Updated!",
                    withHaptics: true
                )
            }
            print("\tShifted focus \(direction == .forwards ? "forwards" : "backwards")")
            handler?()
        } else if let currentAnchor = self.selectionCursor.anchor,
              let currentFocus = self.selectionCursor.focus,
              currentAnchor.getUID() == currentFocus.getUID()
        {
            print("\tUnable to shift focus backwards because we're selecting a single segment")
            self.notifications.executeError(
                text: "Unable to shift past last word.",
                voiceCommand: true
            )
        } else {
            print("\t[Error] There was a problem updating selection focus. Unable to locate suitable segment.")
            self.notifications.executeError(
                text: "Unable to update selection.",
                voiceCommand: true
            )
        }
    }
    
    // Will shift given scale type in selection cursor
    func shiftSelection(
        direction: SelectionDirection,
        withFeedback: Bool = true,
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Shift Selection =====")
        print("\tTriggered by voice command.")
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let (shiftedAnchor, shiftedFocus) = self.selectionCursor.shift(
            direction: direction,
            by: 1
        )
        
        if !shiftedAnchor {
            print("\t[Error] There was a problem updating selection anchor. Unable to locate suitable segment.")
            self.notifications.executeError(
                text: "There was a problem shifting the selection start.",
                voiceCommand: true
            )
        }
        
        if !shiftedFocus {
            print("\t[Error] There was a problem updating selection focus. Unable to locate suitable segment.")
            self.notifications.executeError(
                text: "There was a problem shifting the selection end.",
                voiceCommand: true
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
                voiceCommand: true
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let (shiftedAnchor, shiftedFocus) = self.selectionCursor.expand(by: 1)
        
        if !shiftedAnchor {
            print("\t[Error] There was a problem updating selection anchor. Unable to locate suitable segment.")
            self.notifications.executeError(
                text: "There was a problem shifting the selection start.",
                voiceCommand: true
            )
        }
        
        if !shiftedFocus {
            print("\t[Error] There was a problem updating selection focus. Unable to locate suitable segment.")
            self.notifications.executeError(
                text: "There was a problem shifting the selection end.",
                voiceCommand: true
            )
        }
    }
    
    func reduceSelection(
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Reduce Selection =====")
        print("\tTriggered by voice command.")
        
        guard let _ = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }
        
        guard self.selectionCursor.hasSelection else {
            self.notifications.executeError(
                text: "Select speech to execute action.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let (shiftedAnchor, shiftedFocus) = self.selectionCursor.reduce(by: 1)
        
        if !shiftedAnchor {
            print("\t[Error] There was a problem updating selection anchor. Unable to locate suitable segment.")
            self.notifications.executeError(
                text: "There was a problem shifting the selection start.",
                voiceCommand: true
            )
        }
        
        if !shiftedFocus {
            print("\t[Error] There was a problem updating selection focus. Unable to locate suitable segment.")
            self.notifications.executeError(
                text: "There was a problem shifting the selection end.",
                voiceCommand: true
            )
        }
    }
    
    func echoCommit(
        handler: (() -> Void)? = nil
    ) {
        print("===== Entry Manager: Echo Commit =====")
        print("\tTriggered by voice command.")
        guard let entry = self.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }

        if entry.committedBufferRanges.count == 0 {
            self.notifications.executeError(
                text: "No previous commits.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let executeEcho = {
            let commit = entry.getLastCommit()
            guard let lastCommit = commit else {
                self.notifications.executeError(
                    text: "Unable to find last commit.",
                    voiceCommand: true
                )
                return
            }
            print("\tLast Commit: ", Entry.getText(segments: lastCommit))

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
    
    // MARK: - Undo/Redo Methods
    
    // message should start with a present progressive verb: -ing
    // so utterance will be: undo verb-ing object
    func registerEntryChange(entry: Entry, undo message: String, ignoreUpdate: Bool = true, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Register Entry Change  =====")

        // Update Undo/Redo History
        print("\tCreating and setting new snapshot...")
        
        DispatchQueue.global(qos: .utility).async {
            let duplicateEntry = entry.duplicate(
                state: self.state,
                speechSynthesis: self.speechSynthesis,
                speechRecognition: self.speechRecognition,
                speechPlayer: self.speechPlayer,
                selectionCursor: self.selectionCursor,
                pitchRecognition: self.pitchRecognition,
                entryManager: self,
                notifications: self.notifications
            )
            
            let newSnapshot = EntrySnapshot(
                entry: duplicateEntry, // we duplicate so there's no memory leaks/pointers to same memory locations
                selectionAnchorCaret: self.selectionCursor.anchorCaret?.duplicate(),
                selectionFocusCaret: self.selectionCursor.focusCaret?.duplicate(),
                selectionCachedAnchorCaret: self.selectionCursor.cachedAnchorCaret?.duplicate(),
                undo: message
            )
            
            self.entryChangeHandler = handler
            
            self.ignoreEntrySnapshotUpdate = ignoreUpdate
            
            self.modifyEntry(snapshot: newSnapshot)
            
            self.checkRep()
        }
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
                discardPrior: true,
                withHaptics: true,
                delay: 0
            )
            
            NotificationCenter.default.post(
                name: EntryManager.onUndoManagerChange,
                object: nil,
                userInfo: [
                    "canUndo": self.undoManager.canUndo,
                    "canRedo": self.undoManager.canRedo
                ]
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
                discardPrior: true,
                withHaptics: true,
                delay: 0
            )
            
            NotificationCenter.default.post(
                name: EntryManager.onUndoManagerChange,
                object: nil,
                userInfo: [
                    "canUndo": self.undoManager.canUndo,
                    "canRedo": self.undoManager.canRedo
                ]
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
    
    func setCurrentEntry(index: Int? = nil, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Set Current Entry =====")
        print("\tSet index to: ", index ?? "nil")
        
        self.currentEntryUndoSnapshot = nil
        self.undoManager.removeAllActions()

        if let index = index {
            self.isSettingEntry = true
            NotificationCenter.default.post(
                name: EntryManager.onStartedEntrySetting,
                object: nil,
                userInfo: [:]
            )
            self.currentIndex = index
            self.setEntryModules(index: index)
            // Increment Entry Views
            if !self.entryListManager.isWalkingEntryList &&
                !self.entryListManager.isRunningEntryList
            {
                self.currentEntry!.incrementViewCount()
            }
            DispatchQueue.global(qos: .userInitiated).async {
                // Make sure all data is correct
                if let currentEntry = self.currentEntry {
                    currentEntry.refresh()
                    let _ = currentEntry.duplicate(
                        state: self.state,
                        speechSynthesis: self.speechSynthesis,
                        speechRecognition: self.speechRecognition,
                        speechPlayer: self.speechPlayer,
                        selectionCursor: self.selectionCursor,
                        pitchRecognition: self.pitchRecognition,
                        entryManager: self,
                        notifications: self.notifications
                    ) { entry in
                        self.currentEntryUndoSnapshot = EntrySnapshot(
                            entry: entry, // we duplicate so there's no memory leaks/pointers to same memory locations
                            selectionAnchorCaret: self.selectionCursor.anchorCaret,
                            selectionFocusCaret: self.selectionCursor.focusCaret,
                            selectionCachedAnchorCaret: self.selectionCursor.cachedAnchorCaret,
                            undo: "to start of entry"
                        )
                        self.isSettingEntry = false
                        NotificationCenter.default.post(
                            name: EntryManager.onStoppedEntrySetting,
                            object: nil,
                            userInfo: [:]
                        )
                        handler?()
                        print("Entry Segments: ", Utils.stringifySegments(segments: currentEntry.entrySegments))
                    }
                } else {
                    print("\t[Error] There was a problem setting the entry.")
                    self.notifications.executeError(
                        text: "Error opening entry"
                    )
                }
            }
        } else {
            self.currentIndex = nil
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
    
    // MARK: - Helper Methods
    
    func invalidateTimers() {
        print("===== Entry Manager: Invalidate Timers =====")
        self.walkingTimer?.invalidate()
        self.walkLoopDelayTimer?.invalidate()
        self.echoDelayTimer?.invalidate()
        self.runningTimer?.invalidate()
    }
}

// MARK: - Undo Manager

extension EntryManager {
  
    private func modifyEntry(snapshot: EntrySnapshot) {

        let oldSnapshot: EntrySnapshot = self.currentEntryUndoSnapshot!

        let stateDiff = oldSnapshot.diffed(with: snapshot)
        entryDidChange(diff: stateDiff)
    }

    private func entryDidChange(diff: EntrySnapshot.Diff) {

        guard diff.hasChanges else {
            return
        }
        
        self.currentEntryUndoSnapshot = diff.to
        
        // Reference: https://medium.com/@swetasheth.ce570/introducing-simple-undo-redo-in-swift-cd7b9b0e349
        // Reference: https://developer.apple.com/documentation/foundation/undomanager/1417407-groupsbyevent
        self.undoManager.beginUndoGrouping()
        self.undoManager.registerUndo(withTarget: self) { target in
            target.modifyEntry(snapshot: diff.from)
        }
        self.undoManager.endUndoGrouping()
        
        if self.speechRecognition.isListeningForSpeech {
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
}
