//
//  EntryListManager.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/1/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Foundation
import AVFoundation

class EntryListManager: NSObject {
    // MARK: - Notifications
    
    static let onEntrySelected = Notification.Name(Notifications.onEntrySelected.rawValue)
    static let onExitEntryListWalkRun = Notification.Name(Notifications.onExitEntryListWalkRun.rawValue)

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
        
        // End active timers
        self.invalidateTimers()
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
        
        // App
        notificationCenter.addObserver(
            self,
            selector: #selector(self.appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
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
        print("===== Entry List Manager: App Will Terminate =====")
        
        self.invalidateTimers()
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
            } else if self.isRunningEntryList {
                self.walkNextEntry(runOverride: true) {
                    self.runEntryList(onStartHandler: handler)
                }
            }
        case .SHIFT_PREVIOUS_WALK_ELEMENT:
            if self.isWalkingEntryList {
                self.walkPreviousEntry(handler: handler)
            } else if self.isRunningEntryList {
                self.walkPreviousEntry(runOverride: true) {
                    self.runEntryList(onStartHandler: handler)
                }
            }
        case .PAUSE_RUN:
            if self.isRunningEntryList {
                self.pauseRun(handler: handler)
            }
        case .EXIT_WALK:
            if self.isWalkingEntryList {
                self.exitWalkRun(clearCurrentEntry: true, handler: handler)
            }
        case .ENTER_DICTIONARY:
            self.enterDictionary(handler: handler)
        case .EXIT_DICTIONARY:
            self.exitDictionary(handler: handler)
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
                voiceCommand: true
            )
            
            return
        }
        
        guard let _ = Utils.getNavigationController()?.visibleViewController as? DetailViewController else {
            self.notifications.executeError(
                text: "Already located in entry list.",
                voiceCommand: true
            )
            
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        // Segue to note list
        DispatchQueue.main.async {
            Utils.getNavigationController()?.visibleViewController?.performSegue(withIdentifier: Segues.moveFromDetailToEntryTable.rawValue, sender: nil)
        }
        
        // Remove entry
        self.entryManager.setCurrentEntry()
        
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
                voiceCommand: true
            )
            
            return
        }

        guard !self.speechRecognition.isListeningForSpeech else {
            self.notifications.executeError(
                text: "Cannot walk entry list while creating an entry.",
                voiceCommand: true
            )
            return
        }
        
        guard self.state.activeEntries.count > 0 else {
            self.notifications.executeError(
                text: "No entries available to walk. Say 'start entry' to create create a new entry.",
                voiceCommand: true
            )
            return
        }
        
        // if detail view, exit
        if let _ = Utils.getNavigationController()?.visibleViewController as? DetailViewController {
            self.enterEntryList()
        }
        
        if (self.isWalkingEntryList && !self.pausedWalkingEntryList && !runOverride) {

            self.notifications.executeError(
                text: "Already walking passage.",
                voiceCommand: true
            )

            return
        }

        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: "\(runOverride ? "Run" : "Walk") activated!",
            withHaptics: true
        )
        
        if !AVAudioSession.isHeadphonesConnected {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_NOTIFICATION_DURATION, repeats: false) { timer in
                    self.notifications.executeFeedback(
                        visualMessage: "Use headphones for sound",
                        withHaptics: true
                    )
                }
            }
        }

        // Activate isWalkingEntry if we don't have a run override
        self.isWalkingEntryList = !runOverride
        self.pausedWalkingEntryList = false
        self.pausedRunningEntryList = false
        
        // Set first entry if no current note
        //
        // If we have a note set, it's likely we're
        // coming from a paused run
        
        let index = 0
        
        let handleWalkEntryList = {
            guard let currentEntry = self.entryManager.currentEntry else {
                self.notifications.executeError(
                    text: "Unable to start \(runOverride ? "running" : "walking").",
                    voiceCommand: true
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
                    
                    DispatchQueue.main.async {
                        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                            onStartHandler?()
                        }
                    }
                    
                    return
                }
                
                let previewDuration = CMTimeMake(
                    value: runOverride ? Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION))) : Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * Utils.PREVIEW_ENTRY_DURATION)),
                    timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                )
                print("\tPreview Duration: ", previewDuration.seconds)
                let makeStep = {
                    self.speechPlayer.play(
                        segments: Entry.getDurationSegments(
                            segments: currentEntry.entrySegments,
                            duration: previewDuration,
                            withOmitSilences: self.state.withOmitSilences
                        )
                    )
                }
                
                makeStep()

                if !runOverride {
                    // Make sure that the repeat is at least as long as
                    DispatchQueue.main.async {
                        self.walkingTimer = Timer.scheduledTimer(withTimeInterval: previewDuration.seconds * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: true) { timer in
                            makeStep()
                        }
                    }
                }
            }

            // execute start handler
            onStartHandler?()
            
            self.checkRep()
        }
        
        if self.entryManager.currentIndex == nil {
            self.entryManager.setCurrentEntry(index: index) {
                handleWalkEntryList()
            }
        } else {
            handleWalkEntryList()
        }
    }
    
    func runEntryList(onStartHandler: (() -> Void)? = nil) {
        print("===== Entry List Manager: Run Entry List =====")
        print("\tTriggered by voice command.")
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true
            )
            
            return
        }

        self.isRunningEntryList = true
    
        func nextRunEntry() {
            if let currentIndex = self.entryManager.currentIndex, currentIndex + 1 < self.state.activeEntries.count {
                let currentEntryDuration = self.state.activeEntries[currentIndex].getDuration()
                let previewDuration = CMTimeMake(
                    value: Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntryDuration.seconds, Utils.PREVIEW_ENTRY_DURATION))),
                    timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                )
                // start automated walking
                DispatchQueue.main.async {
                    self.runningTimer = Timer.scheduledTimer(withTimeInterval: previewDuration.seconds * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: false) { [weak self] timer in
                        self?.walkNextEntry(runOverride: true) {
                            nextRunEntry()
                        }
                    }
                }
            } else if let currentIndex = self.entryManager.currentIndex {
                let currentEntryDuration = self.state.activeEntries[currentIndex].getDuration()
                let previewDuration = CMTimeMake(
                    value: Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntryDuration.seconds, Utils.PREVIEW_ENTRY_DURATION))),
                    timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                )
                print("\tDelay Timer Duration: ", previewDuration.seconds)
                DispatchQueue.main.async {
                    self.runningTimer = Timer.scheduledTimer(withTimeInterval: previewDuration.seconds * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: false) { [weak self] timer in
                        self?.exitWalkRun()
                        self?.entryManager.setCurrentEntry()
                    }
                }
            } else {
                self.exitWalkRun()
                self.entryManager.setCurrentEntry()
            }
        }
        
        // Start walk
        if self.entryManager.currentEntry == nil {
            self.walkEntryList(runOverride: true) {
                // start automated walking
                nextRunEntry()
                onStartHandler?()
            }
        } else {
            self.runningTimer?.invalidate()
            self.runningTimer = nil
            nextRunEntry()
            onStartHandler?()
        }

        checkRep()
    }
    
    func walkNextEntry(runOverride: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Walk Next Entry =====")
        print("\tTriggered by voice command.")
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true
            )
            
            return
        }
        
        guard let _ = self.entryManager.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }
        
        if !self.isWalkingEntryList && !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not \(runOverride ? "running" : "walking") entry list.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()

        if let previousIndex = self.entryManager.currentIndex,
           let _ = self.entryManager.currentEntry,
           previousIndex + 1 < self.state.activeEntries.count
        {
            let handleWalkNextEntry = {
                guard let currentIndex = self.entryManager.currentIndex,
                    let currentEntry = self.entryManager.currentEntry else
                {
                    self.notifications.executeError(
                        text: "Unable to retrieve current entry.",
                        voiceCommand: true
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
                        
                        DispatchQueue.main.async {
                            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                                handler?()
                            }
                        }
                        
                        return
                    }
                    let previewDuration = CMTimeMake(
                        value: runOverride ? Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION))) : Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * Utils.PREVIEW_ENTRY_DURATION)),
                        timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                    )
                    print("\tPreview Duration: ", previewDuration.seconds)
                    let makeStep = {
                        self.speechPlayer.play(
                            segments: Entry.getDurationSegments(
                                segments: currentEntry.entrySegments,
                                duration: previewDuration,
                                withOmitSilences: self.state.withOmitSilences
                            )
                        )
                    }
                    
                    makeStep()

                    if !runOverride {
                        // Make sure that the repeat is at least as long as
                        DispatchQueue.main.async {
                            self.walkingTimer = Timer.scheduledTimer(withTimeInterval: previewDuration.seconds * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: true) { timer in
                                makeStep()
                            }
                        }
                    }
                }

                // execute handler
                handler?()
            }
            // Updating walking index
            let currentIndex = previousIndex + 1
            self.entryManager.setCurrentEntry(index: currentIndex) {
                handleWalkNextEntry()
            }
        } else if self.entryManager.isRunningEntry {
            self.exitWalkRun(clearCurrentEntry: true)
        } else {
            self.notifications.executeError(
                text: "At end of entry list.",
                voiceCommand: true
            )
        }
        
        checkRep()
    }
    
    func walkPreviousEntry(runOverride: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Entry Manager: Walk Previous Entry =====")
        print("\tTriggered by voice command.")
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true
            )
            
            return
        }
        
        guard let _ = self.entryManager.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }
        
        if !self.isWalkingEntryList && !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not \(runOverride ? "running" : "walking") entry list.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()

        if let previousIndex = self.entryManager.currentIndex,
           let _ = self.entryManager.currentEntry,
           previousIndex - 1 >= 0
        {
            let handleWalkPreviousEntry = {
                guard let currentIndex = self.entryManager.currentIndex,
                    let currentEntry = self.entryManager.currentEntry else
                {
                    self.notifications.executeError(
                        text: "Unable to retrieve current entry.",
                        voiceCommand: true
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
                        
                        DispatchQueue.main.async {
                            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                                handler?()
                            }
                        }
                        
                        return
                    }
                    
                    let previewDuration = CMTimeMake(
                        value: runOverride ? Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION))) : Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * Utils.PREVIEW_ENTRY_DURATION)),
                        timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                    )
                    let makeStep = {
                        self.speechPlayer.play(
                            segments: Entry.getDurationSegments(
                                segments: currentEntry.entrySegments,
                                duration: previewDuration,
                                withOmitSilences: self.state.withOmitSilences
                            )
                        )
                    }
                    
                    makeStep()

                    if !runOverride {
                        // Make sure that the repeat is at least as long as
                        DispatchQueue.main.async {
                            self.walkingTimer = Timer.scheduledTimer(withTimeInterval: previewDuration.seconds * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: true) { timer in
                                makeStep()
                            }
                        }
                    }
                }

                // execute handler
                handler?()
            }

            // Updating walking index
            let currentIndex = previousIndex - 1
            self.entryManager.setCurrentEntry(index: currentIndex) {
                handleWalkPreviousEntry()
            }
        } else {
            self.notifications.executeError(
                text: "At beginning of entry list.",
                voiceCommand: true
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
                voiceCommand: true
            )
            
            return
        }
        
        guard let _ = self.entryManager.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }
        
        if !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not running entry list.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        if !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not running entry list.",
                voiceCommand: true
            )
            return
        }

        if self.runningTimer == nil {
            self.notifications.executeError(
                text: "Error pausing run.",
                voiceCommand: true
            )
            return
        }

        // Stop running timer
        self.runningTimer?.invalidate()
        self.runningTimer = nil

        // Stop previous walking loop
        self.walkingTimer?.invalidate()
        self.walkingTimer = nil

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
    
    func exitWalkRun(
        clearCurrentEntry: Bool = true,
        withFeedback: Bool = true,
        handler: (() -> Void)? = nil
    ) {
        if self.isRunningEntryList {
            print("===== Entry List Manager: Exit Run =====")
        } else {
            print("===== Entry List Manager: Exit Walk =====")
        }
        print("\tTriggered by voice command.")
        
        guard self.entriesFetched else {
            self.notifications.executeError(
                text: "Still loading entries.",
                voiceCommand: true
            )
            
            return
        }
        
        guard let _ = self.entryManager.currentEntry else {
            self.notifications.executeError(
                text: "No entry selected.",
                voiceCommand: true
            )
            return
        }
        
        if !self.isWalkingEntryList && !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not walking or running entry list.",
                voiceCommand: true
            )
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        if !self.isWalkingEntryList && !self.isRunningEntryList {
            self.notifications.executeError(
                text: "Not walking or running entry list.",
                voiceCommand: true
            )
            return
        }

        if clearCurrentEntry {
            // Clear current entry
            self.entryManager.setCurrentEntry()
            
            NotificationCenter.default.post(
                name: EntryListManager.onExitEntryListWalkRun,
                object: nil,
                userInfo: [:]
            )
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

        let handleExitWalk = {
            var visualMessage: String?
            var audioMessage: String?
            if self.isRunningEntryList {
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
            if let visualMessage = visualMessage, let audioMessage = audioMessage, withFeedback {
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
    
    func enterDictionary(handler: (() -> Void)? = nil) {
        print("===== Entry List Manager: Enter Dictionary =====")
        print("\tTriggered by voice command.")
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        // Segue to note list
        DispatchQueue.main.async {
            Utils.getNavigationController()?.visibleViewController?.performSegue(withIdentifier: Segues.moveFromEntryTableToDictionary.rawValue, sender: nil)
        }

        checkRep()
    }
    
    // Reference: https://stackoverflow.com/questions/28760541/programmatically-go-back-to-previous-viewcontroller-in-swift
    func exitDictionary(handler: (() -> Void)? = nil) {
        print("===== Entry List Manager: Exit Dictionary =====")
        print("\tTriggered by voice command.")
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        // Segue back
        DispatchQueue.main.async {
            Utils.getNavigationController()?.visibleViewController?.performSegue(withIdentifier: Segues.moveFromDictionaryToEntryTable.rawValue, sender: nil)
        }

        checkRep()
    }
    
    // MARK: - Helper Methods
    
    func invalidateTimers() {
        print("===== Entry List Manager: Invalidate Timers =====")
        self.walkingTimer?.invalidate()
        self.runningTimer?.invalidate()
    }
}

// List of tests:

// Useful Resources:
// Viewing App Storage on Device: https://stackoverflow.com/questions/15219511/theres-a-way-to-access-the-document-folder-in-iphone-ipad-real-device-no-simu
// Debugging EXC_BAD_ACCESS: https://code.tutsplus.com/tutorials/what-is-exc_bad_access-and-how-to-debug-it--cms-24544

// ====== Before Wake Phrase =====
// +++++ On-server recognition
// +++++ With and without headphones
// TODO: set withOnDeviceRecognition = false
//
// 1) No words
// Instructions: Open app and wait a minute without saying a word.
// Expected result: Console should continue listening for wake phrase
//
// 2) Some words
// Instructions: Open app and say words, but not the wake phrase
// Expected result: Console should continue listening for wake phrase
//
// 3) No words before a minute. Wake phrase after a minute
// Instructions: Only run if test #1 and #2 pass. Open app. Say wake phrase after a minute.
// Expected result: App should activate.
//
// 4) Some words before a minute. Wake phrase after a minute
// Instructions: Only run if test #1 and #2 pass. Open app and say words, but not the wake phrase. Say wake phrase after a minute.
// Expected result: App should activate.
//
// +++++ On-device recognition
// +++++ With and without headphoness
// TODO: set withOnDeviceRecognition = true
//
// 5) No words
// Instructions: Open app and wait a minute without saying a word.
// Expected result: Console should continue listening for wake phrase
//
// 6) Some words
// Instructions: Open app and say words, but not the wake phrase
// Expected result: Console should continue listening for wake phrase
//
// 7) No words before a minute. Wake phrase after a minute
// Instructions: Only run if test #1 and #2 pass. Open app. Say wake phrase after a minute.
// Expected result: App should activate.
//
// 8) Some words before a minute. Wake phrase after a minute
// Instructions: Only run if test #1 and #2 pass. Open app and say words, but not the wake phrase. Say wake phrase after a minute.
// Expected result: App should activate.
//
// ===== After Wake Phrase =====
// 9) Move to Background / Move to Foreground resets Wake Phrase
// Instructions: Open app. Say wake phrase. Go to Home screen and return to app.
// Expected Result: App should be inactive and listening for wake phrase
//
// +++++ On-server recognition
// +++++ With and without headphoness
// TODO: set withOnDeviceRecognition = true
//
// 10) No words for a minute
// Instructions: Open app. Say wake phrase. Start entry. Wait a minute without saying a word. Say words after a minute.
// Expected Result: No words should be transcribed before a minute. Words shold be transcribed after a minute. Session should be fluid.
//
// 11) Some words in a minute. More words after.
// Instructions: Open app. Say wake phrase. Start entry. Say some words before a minute. Say more words after a minute.
// Expected Result: Some words should be transcribed before a minute. More words should be stranscribed after a minute. Session should be fluid. The timestamps should be accurate for each word.
//
// +++++ On-device recognition
// +++++ With and without headphoness
// TODO: set withOnDeviceRecognition = true
//
// 12) No words for a minute
// Instructions: Open app. Say wake phrase. Start entry. Wait a minute without saying a word. Say words after a minute.
// Expected Result: No words should be transcribed before a minute. Words shold be transcribed after a minute. Session should be fluid.
//
// 13) Some words in a minute. More words after.
// Instructions: Open app. Say wake phrase. Start entry. Say some words before a minute. Say more words after a minute.
// Expected Result: Some words should be transcribed before a minute. More words should be stranscribed after a minute. Session should be fluid. The timestamps should be accurate for each word.
//
// 14) Spaced out audio while using on-device recognition
// Instructions: Speak out an entry with at least five seconds of silence between each word
// Expected result: On playback, the silences should be removed and the focus word on screen should be aligned with the word being uttered.
//
// 15) Test Punctuation Suggestion: Ignore Adjective
// Instructions: Utter the following: "This is a beautiful". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Utter "home".
// Expected Result: There should not be a new paragraph created between 'beautiful' and 'home'.
//
// 16) Test Punctuation Suggestion: End on Adjective
// Instructions: Utter the following: "This is beautiful". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. "you are the best".
// Expected Result: There should be a new paragraph created between "This is beautiful" and "you are the best". "You" should be capitalized and there should be no leading space on second sentence
// Warning: Sometimes the transcript returns back a starting time for "you" that happens well before it is uttered. There is no control of this unfortunately
//
// 17) Test Punctuation Suggestion: End on Negative Adjective
// Instructions: Utter the following: "This is not beautiful". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. "you are the word".
// Expected Result: There should be a new paragraph created between "This is not beautiful" and "you are the worst". "You" should be capitalized and there should be no leading space on second sentence
// Warning: Sometimes the transcript returns back a starting time for "you" that happens well before it is uttered. There is no control of this unfortunately
//
// 18) Test Punctuation Suggestion: End on Negative Quantifier Adjective
// Instructions: Utter the following: "This is so beautiful". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. "Can I have it?". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds.
// Expected Result: There should be a new paragraph created between "This is not beautiful" and "Can I have it?". "Can" should be capitalized and there should be a question mark at the end of the sentence.
// Warning: Sometimes the transcript returns back a starting time for "can" that happens well before it is uttered. There is no control of this unfortunately
//
// 19) Test Punctuation and Temporal Suggestions Active
// Instructions: In createNewEntry() method, set 'withTemporalSuggestions' and 'withPunctuationSuggestions' to true. And open application
// Expected Result:  You should see a 'Conflicting View Modes' error dialog telling you it's selected punctuation suggestions.
//
// 20) Test Change Audio Inputs
// Instructions: Start the app without earphones connected. While on the Wake Phrase Screen, connect earphones. Utter wake phrase.
// Expected Result: The wake phrase should be registered without error
//
// 22) Test Trim Entry: Permanent
//
// ===== Code Needed =====
//entry.trim(keeping: entry.getSentenceDetails(number: 1)!.timeRange, permanent: true) {
//    self.entry.play(
//        onStartHandler: { [weak self] in
//            // print("Successfully executed playback on start handler")
//            DispatchQueue.main.async {
//                self?.playAudioButton.setTitle(PAUSE_ENTRY_LABEL, for: .normal)
//            }
//        },
//        secondElapseHandler: { [weak self] in
//            // print("Successfully executed playback secondT elapsed handler")
//            DispatchQueue.main.async {
//                if !self!.entry.isListeningForSpeech && self!.entry.player.currentTime().seconds != Double.infinity && self!.entry.player.currentTime().seconds != Double.nan && self!.entry.player.currentTime().seconds != -Double.infinity {
//                    self?.navigationBar.topItem?.title = "\(Utils.formattedTime(time: Float(self!.entry.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.entry.getDuration().seconds)))"
//                }
//            }
//        },
//        segmentBoundaryHandler: { [weak self] in
//            // print("Successfully executed playback on segment boundary handler")
//            DispatchQueue.main.async {
//                if let segment = self?.entry.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = self?.entry.getSegmentTextRange(of: segment) {
//                    // update text
//                    self?.updateUIText(text: self!.entry.getText(), highlightRange: highlightRange, transformations: self!.entry.transformations)
//                }
//
//                if let segment = self?.entry.getSegment(type: .current), let pitch = segment.getPitch() {
//                    // update pitch
//                    self?.pitchLabel.text = pitch.note.string
//                }
//            }
//        }, onFinishHandler: { [weak self] in
//            // print("Successfully executed playback on finish handler")
//            DispatchQueue.main.async {
//                self?.updateUIText(text: self!.entry.getText(), transformations: self!.entry.transformations)
//                if !self!.entry.isListeningForSpeech {
//                    self?.navigationBar.topItem?.title = ""
//                }
//
//                self?.adjustCommandBar()
//                self?.adjustMenuBar()
//            }
//        }
//    )
//}
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Utter the following: "This is the first sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the second sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the third sentence".
// Expected Result: System should play back: "This is the second sentence".
//
// 23) Test Trim Entry: Not Permanent
//
// ===== Code Needed =====
//entry.trim(keeping: entry.getSentenceDetails(number: 1)!.timeRange, permanent: false) {
//    self.entry.play(
//        onStartHandler: { [weak self] in
//            // print("Successfully executed playback on start handler")
//            DispatchQueue.main.async {
//                self?.playAudioButton.setTitle(PAUSE_ENTRY_LABEL, for: .normal)
//            }
//        },
//        secondElapseHandler: { [weak self] in
//            // print("Successfully executed playback secondT elapsed handler")
//            DispatchQueue.main.async {
//                if !self!.entry.isListeningForSpeech && self!.entry.player.currentTime().seconds != Double.infinity && self!.entry.player.currentTime().seconds != Double.nan && self!.entry.player.currentTime().seconds != -Double.infinity {
//                    self?.navigationBar.topItem?.title = "\(Utils.formattedTime(time: Float(self!.entry.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.entry.getDuration().seconds)))"
//                }
//            }
//        },
//        segmentBoundaryHandler: { [weak self] in
//            // print("Successfully executed playback on segment boundary handler")
//            DispatchQueue.main.async {
//                if let segment = self?.entry.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = self?.entry.getSegmentTextRange(of: segment) {
//                    // update text
//                    self?.updateUIText(text: self!.entry.getText(), highlightRange: highlightRange, transformations: self!.entry.transformations)
//                }
//
//                if let segment = self?.entry.getSegment(type: .current), let pitch = segment.getPitch() {
//                    // update pitch
//                    self?.pitchLabel.text = pitch.note.string
//                }
//            }
//        }, onFinishHandler: { [weak self] in
//            // print("Successfully executed playback on finish handler")
//            DispatchQueue.main.async {
//                self?.updateUIText(text: self!.entry.getText(), transformations: self!.entry.transformations)
//                if !self!.entry.isListeningForSpeech {
//                    self?.navigationBar.topItem?.title = ""
//                }
//
//                self?.adjustCommandBar()
//                self?.adjustMenuBar()
//            }
//        }
//    )
//}
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Utter the following: "This is the first sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the second sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the third sentence".
// Expected Result: System should play back: "This is the second sentence".
//
// 25) Duplicate Entry
//
// ===== Code Needed =====
//entry.duplicate() { entry in
//    self.tempEntry = entry
//    self.tempEntry?.play() {
//        print("Finished Sentence!")
//    }
//}
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Record any entry.
// Expected Result: System should play back your entry.
//
// 26) Voice Commands
//
// Instructions: Open app and utter wake phrase. Start entry by uttering "Start Entry". Speak an entry. End entry by uttering "Stop Entry". Play entry by uttering "Play Entry".
// Expected Result: Your entry should playback *** without *** 'Stop Entry' in it.
//
// 27) Uttering Voice Command Mid-Entry
//
// Instructions: Open app and utter wake phrase. Start entry by uttering "Start Entry". Speak an entry. Mid entry utter "Play Entry". Let audio play until completion. Continue speaking an entry. End entry by uttering "Stop Entry". Play entry by uttering "Play Entry".
// Expected Result: Mid-entry you should hear yourself utter the entry up until that point. After ending entry, your entry should playback *** without *** 'Stop Entry' in it.
//
// 28) Test track collapsing implementation
//
// Instructions: Open app and utter wake phrase. Start entry by uttering "Start Entry". Utter "this is the first sentence". Then utter "Play Entry". Let audio play until completion. Then utter "this is the second sentence". Then utter "Play Entry". Let audio play until completion. Then utter "this is the third sentence". Then utter "Play Entry". End entry by uttering "Stop Entry"
// Expected Result: At each stage of "play entry", each new utterance should be added to the entry playback without voice command playback between each utterance.

// 29) Double Play Entry Test
//
// Instructions: Open app and utter wake phrase. Start entry by uttering "Start Entry". Speak an entry. Mid entry utter "Play Entry". Let audio play until completion. After completion, utter "Play Entry" again.
// Expected Result: Entry should be played back twice without any voice command utters played back.

// 30) Emphasis Test
//
// Instructions:
// Expected Result:
