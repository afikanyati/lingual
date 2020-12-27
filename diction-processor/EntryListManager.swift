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
                    value: Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION))),
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
                        value: Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION))),
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
                        value: Int64(floor(Utils.DEFAULT_SEGMENT_TIMESCALE * min(currentEntry.getDuration().seconds, Utils.PREVIEW_ENTRY_DURATION))),
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
