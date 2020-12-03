//
//  EntryListManager.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/1/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

class EntryListManager: NSObject {
    // MARK: - Notifications
    
    static let onEntrySelected = Notification.Name(Notifications.onEntrySelected.rawValue)

    // MARK: - App Modules
    
    var state: StateManager
    var speechPlayer: SpeechPlayerEngine
    var entryManager: EntryManager
    var notifications: NotificationEngine
    var speechRecognition: SpeechRecognitionEngine
    
    // MARK: - Entry List Manager Properties

    /// Specifies whether entries have been fetched
    private(set) var entriesFetched = false
    /// Specifies whether entry list is currently running
    private(set) var isRunningEntryList = false
    /// Specifies whether entry list is currently walking
    private(set) var isWalkingEntryList = false
    /// Specifies whether entry list is currently paused walking
    private(set) var pausedWalkingEntryList = false
    /// Specifies whether entry list is currently paused running
    private(set) var pausedRunningEntryList = false
    /// Stores a reference to a timer that drives walking loop behavior
    private(set) var walkingTimer: Timer?
    /// Stores a reference to a timer that drives delay of walk loop intiation
    private(set) var walkLoopDelayTimer: Timer?
    /// Stores a reference to a timer that drives delayed echo while walking
    private(set) var runningTimer: Timer?
    
    // MARK: - Initialization and Deinitialization
    
    init(
        state: StateManager,
        speechPlayer: SpeechPlayerEngine,
        entryManager: EntryManager,
        notifications: NotificationEngine,
        speechRecognition: SpeechRecognitionEngine
    ) {
        print("===== Entry List Manager: Initialization =====")
        self.state = state
        self.speechPlayer = speechPlayer
        self.entryManager = entryManager
        self.notifications = notifications
        self.speechRecognition = speechRecognition
        
        super.init()
        
        self.configureNotificationObservers()
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Validation
    
    func checkRep() {
        var result = true

        // cannot pause walking if walking is inactive
        result = result && (!self.pausedWalkingEntryList || self.isWalkingEntryList)
        
        // cannot pause running if walking is inactive
        result = result && (!self.pausedRunningEntryList || self.isRunningEntryList)
        
        if !result {
            fatalError("===== [Error] Entry Manager Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
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
        print("===== Entry List Manager: On Fetched Entries =====")
        self.entriesFetched = true
    }
    
    @objc func onProcessedVoiceCommand(notification: Notification) {
        print("===== Entry List Manager: On Processed Voice Command =====")
        let command = notification.userInfo!["command"] as! VoiceCommandEngine.VoiceCommand
        var handler: (() -> Void)?
        if notification.userInfo!["handler"] != nil {
            handler = notification.userInfo!["handler"] as? () -> Void
        }

        switch (command) {
        case .ENTER_ENTRY_LIST:
            self.enterEntryList(handler: handler)
        case .WALK_ENTRY_LIST:
            self.walkEntryList(onStartHandler: handler)
        case .RUN_ENTRY_LIST:
            self.runEntryList(onStartHandler: handler)
        case .SHIFT_NEXT_WALK_ELEMENT:
            if self.isWalkingEntryList {
                self.walkNextEntry(handler: handler)
            }
        case .SHIFT_PREVIOUS_WALK_ELEMENT:
            if self.isWalkingEntryList {
                self.walkPreviousEntry(handler: handler)
            }
        case .PAUSE_RUN:
            if self.isRunningEntryList {
                self.pauseRun(handler: handler)
            }
        case .EXIT_WALK:
            if self.isWalkingEntryList {
                self.exitWalkRun(handler: handler)
            }
        default:
            // Do Nothing
            break
        }
    }
    
    // MARK: - Methods
    
    func enterEntryList(handler: (() -> Void)? = nil) {
        print("===== Entry List Manager: Enter Entry List =====")
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true,
                handler: handler
            )
            
            return
        }
        
        guard let _ = Utils.getNavigationController()?.visibleViewController as? DetailViewController else {
            self.notifications.executeError(
                text: "Already located in entry list.",
                voiceCommand: true,
                handler: handler
            )
            
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        // Segue to note list
        DispatchQueue.main.async { [weak self] in
            self?.notifications.executeFeedback(
                visualMessage: "Navigate to Entry List",
                audioMessage: "Navigated to entry list.",
                discardPrior: true,
                withHaptics: true
            )
            Utils.getNavigationController()?.visibleViewController?.performSegue(withIdentifier: Segues.moveFromDetailToEntryTable.rawValue, sender: nil)
        }
        
        // Remove entry
        self.entryManager.setCurrentEntry()
        
        self.notifications.executeFeedback(
            visualMessage: "Navigate to Entry List",
            audioMessage: "Navigated to entry list.",
            withHaptics: true
        )
        
        checkRep()
    }
    
    func walkEntryList(runOverride: Bool = false, onStartHandler: (() -> Void)? = nil) {
        print("===== Entry List Manager: Walk Entry List =====")
        print("\tTriggered by voice command.")
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true,
                handler: onStartHandler
            )
            
            return
        }

        guard !self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Cannot walk entry list while creating an entry.",
                voiceCommand: true,
                handler: onStartHandler
            )
            return
        }
        
        guard self.state.activeEntries.count > 0 else {
            self.notifications.executeError(
                text: "No entries available to walk. Say 'start entry' to create create a new entry.",
                voiceCommand: true,
                handler: onStartHandler
            )
            return
        }
        
        // if detail view, exit
        if let _ = Utils.getNavigationController()?.visibleViewController as? DetailViewController {
            self.enterEntryList()
        }
        
        if (self.isWalkingEntryList && !self.pausedWalkingEntryList && !runOverride) {

            self.notifications.executeError(
                text: "Already walking passage."
            )

            return
        }

        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: "\(runOverride ? "Run" : "Walk") activated!",
            withHaptics: true
        )

        // Activate isWalkingEntry if we don't have a run override
        self.isWalkingEntryList = !runOverride
        self.pausedWalkingEntryList = false
        self.pausedRunningEntryList = false
        
        // Set first entry if no current note
        //
        // If we have a note set, it's likely we're
        // coming from a paused run
        
        let index = 0
        
        if self.entryManager.currentIndex == nil {
            self.entryManager.setCurrentEntry(index: index)
        }
        
        guard let currentEntry = self.entryManager.currentEntry else {
            self.notifications.executeError(
                text: "Unable to start \(runOverride ? "running" : "walking").",
                handler: onStartHandler
            )
            return
        }
        
        // Send out notification so view can select entry
        NotificationCenter.default.post(
            name: EntryListManager.onEntrySelected,
            object: nil,
            userInfo: ["index" : index]
        )
        
        // start looping walk
        if AVAudioSession.isHeadphonesConnected {
            guard currentEntry.entrySegments.count > 0 else {
                // Present Feedback
                self.notifications.executeFeedback(
                    visualMessage: "Empty entry.",
                    audioMessage: "Empty entry.",
                    withHaptics: true
                )
                
                onStartHandler?()
                return
            }
            
            let previewDuration = CMTimeMake(
                value: Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION))),
                timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
            )
            let makeStep = {
                self.speechPlayer.play(
                    entry: currentEntry,
                    from: CMTime.zero,
                    to: previewDuration
                )
            }

            let walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                makeStep()

                // Make sure that the repeat is at least as long as
                let walkingTimer = Timer.scheduledTimer(withTimeInterval: min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION) * TimeInterval( 1 / self!.speechPlayer.playbackRate), repeats: true) { timer in
                    makeStep()
                }

                self?.walkingTimer = walkingTimer
            }

            self.walkLoopDelayTimer = walkLoopDelayTimer
        }

        // execute start handler
        onStartHandler?()
        
        checkRep()
    }
    
    func runEntryList(onStartHandler: (() -> Void)? = nil) {
        print("===== Entry List Manager: Run Entry List =====")
        print("\tTriggered by voice command.")
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true,
                handler: onStartHandler
            )
            
            return
        }
        
        if self.isRunningEntryList && !self.pausedRunningEntryList {
            self.notifications.executeError(
                text: "Already running entry list."
            )
            return
        }

        self.isRunningEntryList = true
        
        let runHandler = {
            onStartHandler?()
            
            // start automated walking
            let runningTimer = Timer.scheduledTimer(withTimeInterval: Utils.PREVIEW_ENTRY_DURATION, repeats: true) { [weak self] timer in
                if let currentIndex = self?.entryManager.currentIndex, currentIndex + 1 < self!.state.activeEntries.count {
                    self?.walkNextEntry(runOverride: true)
                } else {
                    self?.pauseRun()
                }
            }

            self.runningTimer = runningTimer
        }

        // Start walk
        self.walkEntryList(runOverride: true, onStartHandler: runHandler)

        checkRep()
    }
    
    func walkNextEntry(runOverride: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Walk Next Entry =====")
        print("\tTriggered by voice command.")
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true,
                handler: handler
            )
            
            return
        }
        
        guard let _ = self.entryManager.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isWalkingEntryList && !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not \(runOverride ? "running" : "walking") entry list.",
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()

        if let previousIndex = self.entryManager.currentIndex,
           let _ = self.entryManager.currentEntry,
           previousIndex + 1 < self.state.activeEntries.count
        {
            // Updating walking index
            let currentIndex = previousIndex + 1
            self.entryManager.setCurrentEntry(index: currentIndex)
            
            guard let currentEntry = self.entryManager.currentEntry else {
                self.notifications.executeError(
                    text: "Unable to retrieve current entry.",
                    handler: handler
                )
                return
            }

            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Next entry",
                withHaptics: true
            )

            // Stop previous walking loop
            self.walkingTimer?.invalidate()
            self.walkingTimer = nil

            // Stop previous walking loop delay
            self.walkLoopDelayTimer?.invalidate()
            self.walkLoopDelayTimer = nil

            // Stop playback
            if self.speechPlayer.isPlayingEntry {
                self.speechPlayer.stop(withFeedback: false)
            }
            
            // Send out notification so view can select entry
            NotificationCenter.default.post(
                name: EntryListManager.onEntrySelected,
                object: nil,
                userInfo: ["index" : currentIndex]
            )

            // start looping walk
            if AVAudioSession.isHeadphonesConnected {
                
                guard currentEntry.entrySegments.count > 0 else {
                    // Present Feedback
                    self.notifications.executeFeedback(
                        visualMessage: "Empty entry.",
                        audioMessage: "Empty entry.",
                        withHaptics: true
                    )
                    
                    handler?()
                    return
                }
                let previewDuration = CMTimeMake(
                    value: Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION))),
                    timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                )
                let makeStep = {
                    self.speechPlayer.play(
                        entry: currentEntry,
                        from: CMTime.zero,
                        to: previewDuration
                    )
                }

                let walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let walkingTimer = Timer.scheduledTimer(withTimeInterval: min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION) * TimeInterval( 1 / self!.speechPlayer.playbackRate), repeats: true) { timer in
                        makeStep()
                    }

                    self?.walkingTimer = walkingTimer
                }

                self.walkLoopDelayTimer = walkLoopDelayTimer
            }

            // execute handler
            handler?()
        } else if self.entryManager.isRunningEntry {
            self.exitWalkRun()
        } else {
            self.notifications.executeError(
                text: "At end of entry list.",
                handler: handler
            )
        }
        
        checkRep()
    }
    
    func walkPreviousEntry(handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Walk Previous Entry =====")
        print("\tTriggered by voice command.")
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true,
                handler: handler
            )
            
            return
        }
        
        guard let _ = self.entryManager.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isWalkingEntryList && !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not walking entry list.",
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()

        if let previousIndex = self.entryManager.currentIndex,
           let _ = self.entryManager.currentEntry,
           previousIndex - 1 >= 0
        {
            // Updating walking index
            let currentIndex = previousIndex - 1
            self.entryManager.setCurrentEntry(index: currentIndex)
            
            guard let currentEntry = self.entryManager.currentEntry else {
                self.notifications.executeError(
                    text: "Unable to retrieve current entry.",
                    handler: handler
                )
                return
            }

            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Previous word",
                withHaptics: true
            )

            // Stop previous walking loop
            self.walkingTimer?.invalidate()
            self.walkingTimer = nil

            // Stop previous walking loop delay
            self.walkLoopDelayTimer?.invalidate()
            self.walkLoopDelayTimer = nil

            // Stop playback
            if self.speechPlayer.isPlayingEntry {
                self.speechPlayer.stop(withFeedback: false)
            }
            
            // Send out notification so view can select entry
            NotificationCenter.default.post(
                name: EntryListManager.onEntrySelected,
                object: nil,
                userInfo: ["index" : currentIndex]
            )

            // start looping walk
            if AVAudioSession.isHeadphonesConnected {
                guard currentEntry.entrySegments.count > 0 else {
                    // Present Feedback
                    self.notifications.executeFeedback(
                        visualMessage: "Empty entry.",
                        audioMessage: "Empty entry.",
                        withHaptics: true
                    )
                    
                    handler?()
                    return
                }
                
                let previewDuration = CMTimeMake(
                    value: Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION))),
                    timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                )
                let makeStep = {
                    self.speechPlayer.play(
                        entry: currentEntry,
                        from: CMTime.zero,
                        to: previewDuration
                    )
                }

                let walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let walkingTimer = Timer.scheduledTimer(withTimeInterval: min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION) * TimeInterval( 1 / self!.speechPlayer.playbackRate), repeats: true) { timer in
                        makeStep()
                    }

                    self?.walkingTimer = walkingTimer
                }

                self.walkLoopDelayTimer = walkLoopDelayTimer
            }

            // execute handler
            handler?()
        } else {
            self.notifications.executeError(
                text: "At beginning of entry list.",
                handler: handler
            )
        }
        
        checkRep()
    }
    
    func pauseRun(handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Pause Run =====")
        print("\tTriggered by voice command.")
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true,
                handler: handler
            )
            
            return
        }
        
        guard let _ = self.entryManager.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not running entry list.",
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        if !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not running entry list."
            )
            return
        }

        if self.runningTimer == nil {
            self.notifications.executeError(
                text: "Error pausing run."
            )
            return
        }

        // Stop running timer
        self.runningTimer?.invalidate()
        self.runningTimer = nil

        // Stop previous walking loop
        self.walkingTimer?.invalidate()
        self.walkingTimer = nil

        // Stop previous walking loop delay
        self.walkLoopDelayTimer?.invalidate()
        self.walkLoopDelayTimer = nil

        // Stop playback
        if self.speechPlayer.isPlayingEntry {
            self.speechPlayer.stop(withFeedback: false)
        }
        
        // Turn off running entry
        self.isRunningEntryList = false

        // Convert to walking entry
        self.walkEntryList(runOverride: false, onStartHandler: handler)

        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: "Run Paused!",
            audioMessage: "Run paused to walk",
            withHaptics: true
        )
        
        checkRep()
    }
    
    func exitWalkRun(clearCurrentEntry: Bool = true, handler: (() -> Void)? = nil) {
        if self.isRunningEntryList {
            print("===== Entry: Exit Run =====")
        } else {
            print("===== Entry: Exit Walk =====")
        }
        print("\tTriggered by voice command.")
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true,
                handler: handler
            )
            
            return
        }
        
        guard let _ = self.entryManager.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true,
                handler: handler
            )
            return
        }
        
        if !self.isWalkingEntryList && !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not walking or running entry list.",
                handler: handler
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        if !self.isWalkingEntryList && !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not walking or running entry list."
            )
            return
        }

        if clearCurrentEntry {
            // Clear current entry
            self.entryManager.setCurrentEntry()
        }

        // Stop current playback
        if self.speechPlayer.isPlayingExternalSegments || self.speechPlayer.isPlayingEntry {
            self.speechPlayer.stop(withFeedback: false)
        }

        // Stop running timer
        self.runningTimer?.invalidate()
        self.runningTimer = nil

        // Stop previous walking loop
        self.walkingTimer?.invalidate()
        self.walkingTimer = nil

        // Stop previous walking loop delay
        self.walkLoopDelayTimer?.invalidate()
        self.walkLoopDelayTimer = nil

        let handleExitWalk = {
            var visualMessage: String?
            var audioMessage: String?
            if self.entryManager.isRunningEntry {
                visualMessage = "Exit Run"
                audioMessage = "run exited."
            } else {
                visualMessage = "Exit Walk"
                audioMessage = "walk exited."
            }

            self.isWalkingEntryList = false
            self.isRunningEntryList = false
            self.pausedWalkingEntryList = false
            self.pausedRunningEntryList = false

            // Present Feedback
            if let visualMessage = visualMessage, let audioMessage = audioMessage {
                self.notifications.executeFeedback(
                    visualMessage: visualMessage,
                    audioMessage: audioMessage,
                    withHaptics: true
                )
            }

            if !self.speechRecognition.isListeningForCommands {
                self.speechRecognition.startListeningForVoiceCommands() {
                    handler?()
                    // Notify observers of loading
                    NotificationCenter.default.post(
                        name: Entry.onRequestToUpdateView,
                        object: nil,
                        userInfo: [:]
                    )
                }
            } else {
                handler?()
            }
        }

        // Stop playback
        self.speechPlayer.stop(withFeedback: false) {
            handleExitWalk()
        }
        
        checkRep()
    }
}
