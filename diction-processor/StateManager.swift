//
//  ModelController.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/31/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Speech
import Foundation
import AVFoundation

class StateManager: NSObject {
    // MARK: - Notifications
    
    static let onFetchedEntries = Notification.Name(Notifications.onFetchedEntries.rawValue)
    
    // MARK: - App Modules
    
    var storageManager: StorageManager
    var notifications: NotificationEngine
    var uiManager: UIManager
    
    // MARK: - User Settings
    
    /// Specifies whether speech recognition should use on-device compute or cloud compute
    private(set) var withOnDeviceRecognition = Utils.DEFAULT_WITH_ON_DEVICE_RECOGNITION
    /// Specifies whether entry will present visual indications of temporal silences on screen
    private(set) var withTemporalSuggestions = Utils.DEFAULT_WITH_TEMPORAL_SUGGESTIONS
    /// Specifies whether entry will present punctuation suggestions based on duration of silences
    private(set) var withPunctuationSuggestions = Utils.DEFAULT_WITH_PUNCTUATION_SUGGESTIONS
    /// Specifies whether entry will present emphasis suggestions based on fluctuating sound intensity of speaker
    private(set) var withFormattingSuggestions = Utils.DEFAULT_WITH_FORMATTING_SUGGESTIONS
    /// Specifies whether entry will only present written language as words (versus numerals or punctuation symbols)
    private(set) var withTextStrictlyAsWords = Utils.DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS
    /// Specifies whether entry text will contain capitalized words
    private(set) var withCapitalization = Utils.DEFAULT_WITH_CAPITALIZATION
    /// Specifies whether segments corresponding to punctuation should be skipped
    private(set) var withSkipPunctuation = Utils.DEFAULT_WITH_SKIP_PUNCTUATION
    /// Specifies whether segments corresponding to silences should be skipped
    private(set) var withOmitSilences = Utils.DEFAULT_WITH_OMIT_SILENCES
    /// Specifies whether passive echo should execute when headphones are connected
    private(set) var withPassiveEcho = Utils.DEFAULT_WITH_PASSIVE_ECHO
    
    // MARK: - Telemetry
    
    private(set) var appOpens = [TimeInterval]()
    private(set) var audioDeviceUse = [AudioDeviceDatum]()
    private(set) var entryViews = [TimeInterval]()
    private(set) var entryPlays = [TimeInterval]()
    private(set) var entryTextExports = [TimeInterval]()
    private(set) var entryAudioExports = [TimeInterval]()
    private(set) var voiceCommands = [TimeInterval]()
    
    // MARK: - General
    
    private(set) var appActivated = false
    private(set) var mainViewReady = false
    private(set) var detailViewReady = false
    private(set) var entryTableViewReady = false
    private(set) var playedStartupSound = false
    private(set) var font = UIFont.systemFont(ofSize: Utils.DEFAULT_FONT_SIZE)
    
    // MARK: - Entries
    
    @objc dynamic private(set) var entries = [Entry]()
    var activeEntries: [Entry] {
        return self.entries.filter { !$0.isDeleted }
    }
    private(set) var clips = [String: Set<String>]()
    private(set) var speaker = Speaker(uid: UUID().uuidString, device: UIDevice.current.name)
    
    // MARK: - Playback
    
    /// Stores the current playback rate of entry playback
    private(set) var _playbackRate: Float = Utils.DEFAULT_PLAYBACK_RATE
    private(set) var _echoRate: Float = Utils.DEFAULT_ECHO_RATE
    
    // MARK: - Initialization and Deinitialization
    
    init(storageManager: StorageManager, notifications: NotificationEngine, uiManager: UIManager) {
        print("===== State Manager : Initialization =====")
        self.storageManager = storageManager
        self.notifications = notifications
        self.uiManager = uiManager
        
        super.init()

        self.configureNotificationObservers()
        self.fetchStoredState()
        self.incrementOpenCount()
        
        // We set punctuation suggestions
        // 1) if punctuation suggestions and temporal suggestions are true, we handle it in if-statement
        if self.withPunctuationSuggestions && self.withTemporalSuggestions {
            // Inform that only one view mode may be active in any given moment
            self.setWithTemporalSuggestions(to: false)

            let dialogActions = [
                DialogAction(
                    title: "Continue",
                    voiceCommand: "continue",
                    style: .cancel,
                    handler: nil
                )
            ]
            
            let dialogItem = DialogItem(
                title: "Conflicting View Modes",
                message: "You've attemped to activate both punctuation and temporal suggestions. Only one can be active at a time, so we've activated punctuation suggestions only.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            self.uiManager.presentDialog(
                dialogItem: dialogItem
            )
        }
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Validation
    
    func checkRep() {
        var result = true
        
        // on device recognition always on
        result = result && self.withOnDeviceRecognition
        
        if !result {
            fatalError("===== [Error] State Manager Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
        // add observer to snapshot
        self.addObserver(
            self,
            forKeyPath: "snapshot",
            options: [.old, .new],
            context: nil
        )
        
        // App
        notificationCenter.addObserver(
            self,
            selector: #selector(self.appLosesFocus),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(self.audioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        // Speech Recognition Engine
        notificationCenter.addObserver(
            self,
            selector: #selector(onWakePhraseDetected(notification:)),
            name: SpeechRecognitionEngine.onWakePhraseDetected,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onViewDidLoad(notification:)),
            name: ViewController.onDidLoad,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryTableViewDidLoad(notification:)),
            name: EntryTableViewController.onDidLoad,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onDetailViewDidLoad(notification:)),
            name: DetailViewController.onDidLoad,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onViewWillDisappear(notification:)),
            name: ViewController.onWillDisappear,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryTableViewWillDisappear(notification:)),
            name: EntryTableViewController.onWillDisappear,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onDetailViewWillDisappear(notification:)),
            name: DetailViewController.onWillDisappear,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onProcessedVoiceCommand(notification:)),
            name: VoiceCommandEngine.onProcessedVoiceCommand,
            object: nil
        )
        
        // StorageManager
        notificationCenter.addObserver(
            self,
            selector: #selector(onFetchedStoredState(notification:)),
            name: StorageManager.onFetchedStoredState,
            object: nil
        )
    }
    
    @objc func appGainsFocus() {
        print("===== State Manager: App Gains Focus =====")
    }
    
    @objc func appLosesFocus() {
        print("===== State Manager: App Lost Focus =====")
        // Will occur when open control center
    }
    
    @objc func audioSessionRouteChange(notification: Notification) {
        print("===== State Manager: Audio Session Route Change =====")
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
        }
        print("\tReason: ", reason)

        // Switch over the route change reason.
        switch reason {
        case .newDeviceAvailable: // New device found.
            self.handleAudioDeviceChange()
        case .oldDeviceUnavailable: // Old device removed.
            break
        default:
            break
        }
    }
    
    @objc func onWakePhraseDetected(notification: Notification) {
        print("===== State Manager: On Wake Phrase Detected =====")
        self.setAppActive(as: true)
    }
    
    @objc func onViewDidLoad(notification: Notification) {
        print("===== State Manager: On View Did Load =====")
        if !self.playedStartupSound {
            // Play Startup Sound
            soundEngine.startup()
            self.playedStartupSound = true
        }
        
        self.mainViewReady = true
    }
    
    @objc func onEntryTableViewDidLoad(notification: Notification) {
        print("===== State Manager: On Entry Table View Did Load =====")
        self.entryTableViewReady = true
    }
    
    @objc func onDetailViewDidLoad(notification: Notification) {
        print("===== State Manager: On Detail View Did Load =====")
        self.detailViewReady = true
    }
    
    @objc func onViewWillDisappear(notification: Notification) {
        print("===== State Manager: On View Will Disappear =====")
        self.mainViewReady = false
    }
    
    @objc func onEntryTableViewWillDisappear(notification: Notification) {
        print("===== State Manager: On Entry Table View Will Disappear =====")
        self.entryTableViewReady = false
    }
    
    @objc func onDetailViewWillDisappear(notification: Notification) {
        print("===== State Manager: On Detail View Will Disappear =====")
        self.detailViewReady = false
    }
    
    @objc func onProcessedVoiceCommand(notification: Notification) {
        print("===== State Manager: On Processed Voice Command =====")
        let command = notification.userInfo!["command"] as! String
        var handler: (() -> Void)?
        if notification.userInfo!["handler"] != nil {
            handler = notification.userInfo!["handler"] as? () -> Void
        }
        
        switch (command) {
        case "activate punctuation":
            print("\tVoice Command: Activate Skip Punctuation")
            
            // Play Sound
            soundEngine.voiceCommandAccept()

            self.setWithSkipPunctuation(to: false)
            handler?()
        case "deactivate punctuation":
            print("\tVoice Command: Deactivate Skip Punctuation")
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            self.setWithSkipPunctuation(to: true)
            handler?()
        case "activate silences":
            print("\tVoice Command: Activate Silence")
            
            // Play Sound
            soundEngine.voiceCommandAccept()

            self.setWithOmitSilences(to: false)
            handler?()
        case "deactivate silences":
            print("\tVoice Command: Deactivate Silence")
            
            // Play Sound
            soundEngine.voiceCommandAccept()

            self.setWithOmitSilences(to: true)
            handler?()
        case "activate temporal suggestions":
            print("\tVoice Command: Activate Temporal Suggestions")

            // Play Sound
            soundEngine.voiceCommandAccept()

            self.setWithTemporalSuggestions(to: true)
            handler?()
        case "deactivate temporal suggestions":
            print("\tVoice Command: Deactivate Temporal Suggestions")

            // Play Sound
            soundEngine.voiceCommandAccept()

            self.setWithTemporalSuggestions(to: false)
            handler?()
        case "activate punctuation suggestions":
            print("\tVoice Command: Activate Punctuation Suggestions")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
        
            self.setWithPunctuationSuggestions(to: true)
            handler?()
        case "deactivate punctuation suggestions":
            print("\tVoice Command: Deactivate Punctuation Suggestions")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
        
            self.setWithPunctuationSuggestions(to: false)
            handler?()
        case "activate formatting suggestions":
            print("\tVoice Command: Activate Formatting Suggestions")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            self.setWithFormattingSuggestions(to: true)
            handler?()
        case "deactivate formatting suggestions":
            print("\tVoice Command: Deactivate Formatting Suggestions")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            self.setWithFormattingSuggestions(to: false)
            handler?()
        case "activate passive echo":
            print("\tVoice Command: Activate Passive Echo")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            self.setWithPassiveEcho(to: true)
            handler?()
        case "deactivate passive echo":
            print("\tVoice Command: Deactivate Passive Echo")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            self.setWithPassiveEcho(to: false)
            handler?()
        case "increase volume":
            print("\tVoice Command: Increase Volume")
            self.handleIncreaseVolume(
                handler: handler
            )
        case "decrease volume":
            print("\tVoice Command: Decrease Volume")
            self.handleDecreaseVolume(
                handler: handler
            )
//        case "adjust volume":
//            startListeningForVolume(entry: entry)
        default:
            // Do nothing
            break
        }
    }
    
    @objc func onFetchedStoredState(notification: Notification) {
        print("===== State Manager: On Fetch Stored State =====")
        // Entries
        self.entries = notification.userInfo!["entries"] as? [Entry] ?? [Entry]()
        
        // User Settings
        let userSettings = notification.userInfo!["userSettings"] as? [String: Any]
        if let userSettings = userSettings {
            print("\tAble to cast userSettings as [String: Any]")
            self.speaker = userSettings["speaker"] as? Speaker ?? Speaker(uid: UUID().uuidString, device: UIDevice.current.name)
            self.withOnDeviceRecognition = userSettings["withOnDeviceRecognition"] as? Bool ?? Utils.DEFAULT_WITH_ON_DEVICE_RECOGNITION
            self.withTemporalSuggestions = userSettings["withTemporalSuggestions"] as? Bool ?? Utils.DEFAULT_WITH_TEMPORAL_SUGGESTIONS
            self.withPunctuationSuggestions = userSettings["withPunctuationSuggestions"] as? Bool ?? Utils.DEFAULT_WITH_PUNCTUATION_SUGGESTIONS
            self.withFormattingSuggestions = userSettings["withFormattingSuggestions"] as? Bool ?? Utils.DEFAULT_WITH_FORMATTING_SUGGESTIONS
            self.withTextStrictlyAsWords = userSettings["withTextStrictlyAsWords"] as? Bool ?? Utils.DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS
            self.withCapitalization = userSettings["withCapitalization"] as? Bool ?? Utils.DEFAULT_WITH_CAPITALIZATION
            self.withSkipPunctuation = userSettings["withSkipPunctuation"] as? Bool ?? Utils.DEFAULT_WITH_SKIP_PUNCTUATION
            self.withOmitSilences = userSettings["withOmitSilences"] as? Bool ?? Utils.DEFAULT_WITH_OMIT_SILENCES
            self.withPassiveEcho = userSettings["withPassiveEcho"] as? Bool ?? Utils.DEFAULT_WITH_PASSIVE_ECHO
            self._playbackRate = userSettings["playbackRate"] as? Float ?? Utils.DEFAULT_PLAYBACK_RATE
            self._echoRate = userSettings["echoRate"] as? Float ?? Utils.DEFAULT_ECHO_RATE
            if let fontSize = userSettings["fontSize"] as? CGFloat {
                self.font = UIFont.systemFont(ofSize: fontSize)
            } else {
                self.font = UIFont.systemFont(ofSize: Utils.DEFAULT_FONT_SIZE)
            }
        } else {
            print("\t[Error] Unable to cast userSettings as [String: Any]")
            self.speaker = Speaker(uid: UUID().uuidString, device: UIDevice.current.name)
            self.withOnDeviceRecognition = Utils.DEFAULT_WITH_ON_DEVICE_RECOGNITION
            self.withTemporalSuggestions = Utils.DEFAULT_WITH_TEMPORAL_SUGGESTIONS
            self.withPunctuationSuggestions = Utils.DEFAULT_WITH_PUNCTUATION_SUGGESTIONS
            self.withFormattingSuggestions = Utils.DEFAULT_WITH_FORMATTING_SUGGESTIONS
            self.withTextStrictlyAsWords = Utils.DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS
            self.withCapitalization = Utils.DEFAULT_WITH_CAPITALIZATION
            self.withSkipPunctuation = Utils.DEFAULT_WITH_SKIP_PUNCTUATION
            self.withOmitSilences = Utils.DEFAULT_WITH_OMIT_SILENCES
            self.withPassiveEcho = Utils.DEFAULT_WITH_PASSIVE_ECHO
            self._playbackRate = Utils.DEFAULT_PLAYBACK_RATE
            self._echoRate = Utils.DEFAULT_ECHO_RATE
            self.font = UIFont.systemFont(ofSize: Utils.DEFAULT_FONT_SIZE)
        }
        
        // App Telemetry
        let appTelemetry = notification.userInfo!["appTelemetry"] as? [String: Any]
        if let appTelemetry = appTelemetry {
            print("\tAble to cast appTelemetry as [String: Any]")
            self.appOpens = appTelemetry["appOpens"] as? [TimeInterval] ?? [TimeInterval]()
            self.audioDeviceUse = appTelemetry["audioDeviceUse"] as?  [AudioDeviceDatum] ?? [AudioDeviceDatum]()
            self.entryViews = appTelemetry["entryViews"] as? [TimeInterval] ?? [TimeInterval]()
            self.entryPlays = appTelemetry["entryPlays"] as? [TimeInterval] ?? [TimeInterval]()
            self.entryTextExports = appTelemetry["entryTextExports"] as? [TimeInterval] ?? [TimeInterval]()
            self.entryAudioExports = appTelemetry["entryAudioExports"] as? [TimeInterval] ?? [TimeInterval]()
            self.voiceCommands = appTelemetry["voiceCommands"] as? [TimeInterval] ?? [TimeInterval]()
        } else {
            print("\t[Error] Unable to cast appTelemetry as [String: Any]")
            self.appOpens = [TimeInterval]()
            self.audioDeviceUse = [AudioDeviceDatum]()
            self.entryViews = [TimeInterval]()
            self.entryPlays = [TimeInterval]()
            self.entryTextExports = [TimeInterval]()
            self.entryAudioExports = [TimeInterval]()
            self.voiceCommands = [TimeInterval]()
        }

        NotificationCenter.default.post(
            name: StateManager.onFetchedEntries,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    // MARK: - Methods
    
    func incrementOpenCount() {
        print("===== State Manager: Increment Open Count =====")
        self.appOpens.append(Date().timeIntervalSince1970)
        self.storageManager.save(state: self)
        
        checkRep()
    }
    
    func fetchStoredState() {
        print("===== State Manager: Fetch Stored State  =====")
        self.storageManager.fetch()
        
        checkRep()
    }
    
    func saveEntry(entry: Entry) {
        print("===== State Manager: Save Entry =====")
        for (index, n) in self.entries.enumerated() {
            if n.uid == entry.uid {
                print("\tFound and replaced existing entry: ")
                print("\tOld Entry Segment Count: ", n.entrySegments.count)
                print("\tNew Entry Segment Count: ", entry.entrySegments.count)
                self.entries[index] = entry
            }
        }
        
        self.save()
    }
    
    // message should start with a present progressive verb: -ing
    // so utterance will be: undo verb-ing object
    func save() {
        print("===== State Manager: Save  =====")
        self.storageManager.save(state: self)
        
        checkRep()
    }
    
    // MARK: - Telemetry
    
    func incrementEntryViewCount(timeInterval: TimeInterval) {
        print("===== State Manager: Increment Entry View Count =====")
        self.entryViews.append(timeInterval)
    }
    
    func incrementEntryPlayCount(timeInterval: TimeInterval) {
        print("===== State Manager: Increment Entry Play Count =====")
        self.entryPlays.append(timeInterval)
    }
    
    func incrementEntryTextExportCount(timeInterval: TimeInterval) {
        print("===== State Manager: Increment Entry Text Export Count =====")
        self.entryTextExports.append(timeInterval)
    }
    
    func incrementEntryAudioExportCount(timeInterval: TimeInterval) {
        print("===== State Manager: Increment Audio Export Count =====")
        self.entryAudioExports.append(timeInterval)
    }
    
    func incrementVoiceCommandCount(timeInterval: TimeInterval) {
        print("===== State Manager: Increment Voice Command Count =====")
        self.voiceCommands.append(timeInterval)
    }
    
    // MARK: - Setters
    
    func setAppActive(as value: Bool) {
        print("===== State Manager: Set App Active: \(value)  =====")
        self.appActivated = value
        
        checkRep()
    }
    
    func setPlaybackRate(to rate: Float) {
        print("===== State Manager: Set Playback Rate: \(rate.rounded(toPlaces: 2)) =====")
        
        if rate > self._playbackRate {
            self.notifications.executeFeedback(
                visualMessage: "Increase Playback Rate: \(rate.rounded(toPlaces: 2))",
                audioMessage: "increased rate to \(rate.rounded(toPlaces: 2))",
                discardPrior: true,
                withHaptics: true
            )
        } else if rate < self._playbackRate {
            self.notifications.executeFeedback(
                visualMessage: "Decrease Playback Rate: \(rate.rounded(toPlaces: 2))",
                audioMessage: "decreased rate to \(rate.rounded(toPlaces: 2))",
                discardPrior: true,
                withHaptics: true
            )
        }
        
        self._playbackRate = rate
        
        self.save()
        checkRep()
    }
    
    // Implementing real-time rate change: https://stackoverflow.com/questions/25499803/how-to-change-speech-rate-during-speaking-using-avspeechsynthesizer-in-ios-7
    func setEchoRate(to rate: Float) {
        print("===== State Manager: Set Echo Rate: \(rate.rounded(toPlaces: 2)) =====")
        
        if rate > self._echoRate {
            self.notifications.executeFeedback(
                visualMessage: "Increase Echo Rate: \(rate.rounded(toPlaces: 2))",
                audioMessage: "increased echo to \(rate.rounded(toPlaces: 2))",
                discardPrior: true,
                withHaptics: true
            )
        } else if rate < self._echoRate {
            self.notifications.executeFeedback(
                visualMessage: "Decrease Echo Rate: \(rate.rounded(toPlaces: 2))",
                audioMessage: "decreased echo to \(rate.rounded(toPlaces: 2))",
                discardPrior: true,
                withHaptics: true
            )
        }
        
        self._echoRate = rate
        
        self.save()
        checkRep()
    }
    
    // Audio variable
    func setWithSkipPunctuation(to skip: Bool) {
        print("===== State Manager: Set With Skip Punctuation: \(skip) =====")
        self.withSkipPunctuation = skip
        
        if self.withSkipPunctuation {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Skip Punctuation",
                audioMessage: "skip punctuation activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Include Punctuation",
                audioMessage: "skip punctuation deactivated",
                withHaptics: true
            )
        }
        
        self.save()
        checkRep()
    }
    
    // Audio variable
    func setWithOmitSilences(to skip: Bool) {
        print("===== State Manager: Set With Omit Silences: \(skip)  =====")
        self.withOmitSilences = skip
        
        if self.withOmitSilences {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Activate Silences",
                audioMessage: "silences activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Deactivate Silences",
                audioMessage: "silences deactivated",
                withHaptics: true
            )
        }
        
        self.save()
        checkRep()
    }
    
    // Audio variable
    func setWithPassiveEcho(to value: Bool) {
        print("===== State Manager: Set With Passive Echo: \(value) =====")
        self.withPassiveEcho = value
        
        if self.withPassiveEcho {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Activate Passive Echo",
                audioMessage: "passive echo activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Deactivate Passive Echo",
                audioMessage: "passive echo deactivated",
                withHaptics: true
            )
        }
        
        self.save()
        checkRep()
    }
    
    // Visual variable
    func setWithTemporalSuggestions(to value: Bool) {
        print("===== State Manager: Set With Temporal Suggestions: \(value)  =====")
        self.withTemporalSuggestions = value
        
        // We can only have one suggestion type on at a time
        // Deactivate punctuation suggestions if active
        if value && self.withPunctuationSuggestions {
            self.withTemporalSuggestions = false
        }
        
        // Make sure new setting is reflecting visually
        // TODO => UPDATE ENTRY DETAIL
        
        if self.withTemporalSuggestions {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Activate Temporal Suggestions",
                audioMessage: "temporal suggestions activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Deactivate Temporal Suggestions",
                audioMessage: "temporal suggestions deactivated",
                withHaptics: true
            )
        }
        
        self.save()
        checkRep()
    }
    
    // Visual variable
    func setWithPunctuationSuggestions(to value: Bool) {
        print("===== State Manager: Set With Punctuation Suggestions: \(value) =====")
        self.withPunctuationSuggestions = value
        
        // We can only have one suggestion type on at a time
        // Deactivate space suggestions if active
        if value && self.withTemporalSuggestions {
            self.withTemporalSuggestions = false
        }
        
        // Make sure new setting is reflecting visually
        // TODO => UPDATE ENTRY DETAIL
        
        if self.withPunctuationSuggestions {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Activate Punctuation Suggestions",
                audioMessage: "punctuation suggestions activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Deactivate Punctuation Suggestions",
                audioMessage: "punctuation suggestions deactivated",
                withHaptics: true
            )
        }
        
        self.save()
        checkRep()
    }
    
    // Visual variable
    func setWithFormattingSuggestions(to value: Bool) {
        print("===== State Manager: Set With Formatting Suggestions: \(value) =====")
        self.withFormattingSuggestions = value
        
        // Make sure new setting is reflecting visually
        // TODO => UPDATE ENTRY DETAIL
        
        if self.withFormattingSuggestions {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Activate Formatting Suggestions",
                audioMessage: "formatting suggestions activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Deactivate Formatting Suggestions",
                audioMessage: "formatting suggestions deactivated",
                withHaptics: true
            )
        }
        
        self.save()
        checkRep()
    }
    
    // Visual variable
    func setWithTextStrictlyAsWords(to value: Bool) {
        print("===== State Manager: Set With Text Strictly As Words: \(value) =====")
        self.withTextStrictlyAsWords = value
        
        // Make sure new setting is reflecting visually
        // TODO => UPDATE ENTRY DETAIL
        
        self.save()
        checkRep()
    }
    
    // Visual variable
    func setWithCapitalization(to value: Bool) {
        print("===== State Manager: Set With Capitalization: \(value) =====")
        self.withCapitalization = value
        
        // Make sure new setting is reflecting visually
        // TODO => UPDATE ENTRY DETAIL
        
        self.save()
        checkRep()
    }
    
    func appendEntry(entry: Entry) -> Int {
        print("===== State Manager: Append Entry  =====")
        self.entries.insert(entry, at: 0)
        
        self.save()
        checkRep()
        
        return 0 // we add entries in reverse order
    }
    
    func setClip(clipUID: String, entryUID: String) {
        print("===== State Manager: Set Clip =====")
        if self.clips[clipUID] != nil {
            print("\tInserted entry uid into existing clip set...")
            self.clips[clipUID]?.insert(entryUID)
        } else {
            print("\tCreated new clip set for clip uid...")
            let entrySet: Set = [entryUID]
            self.clips[clipUID] = entrySet
        }
    }
    
    func setSpeakerPitch(to pitch: Pitch?) {
//        print("===== State Manager: Set Speaker Pitch =====")
//        print("\tSet to: ", pitch?.entry.string ?? "nil")
        self.speaker.setSpeakerPitch(to: pitch)
    }
    
    // MARK: - Voice Commands
    
    func handleIncreaseVolume(
        handler: (() -> Void)? = nil
    ) {
        print("===== State Manager: Hanlde Increase Volume  =====")
        let currentVolume = Utils.playbackVolume
        let newVolume = min(currentVolume + Utils.DISCRETE_VOLUME_DELTA, Utils.MAXIMUM_VOLUME).rounded(toPlaces: 2)
        if currentVolume < Utils.MAXIMUM_VOLUME {
            // Play Sound
            soundEngine.voiceCommandAccept()
            Utils.setMainVolume(to: newVolume)

            self.notifications.executeFeedback(
                visualMessage: "Volume increase: \(newVolume)",
                audioMessage: "Volume increased to \(newVolume)",
                withHaptics: true
            )
            
            handler?()
        } else {
            self.notifications.executeError(
                text: "Volume already at maximum.",
                voiceCommand: true,
                handler: handler
            )
        }
        
        checkRep()
    }
    
    func handleDecreaseVolume(
        handler: (() -> Void)? = nil
    ) {
        print("===== State Manager: Handle Decrease Volume =====")
        let currentVolume = Utils.playbackVolume
        let newVolume = max(currentVolume - Utils.DISCRETE_VOLUME_DELTA, Utils.MINIMUM_VOLUME).rounded(toPlaces: 2)
        if currentVolume > Utils.MINIMUM_VOLUME {
            // Play Sound
            soundEngine.voiceCommandAccept()
            Utils.setMainVolume(to: newVolume)
            
            self.notifications.executeFeedback(
                visualMessage: "Volume decrease: \(newVolume)",
                audioMessage: "Volume decreased to \(newVolume)",
                withHaptics: true
            )
            
            handler?()
        } else {
            self.notifications.executeError(
                text: "Volume already at minimum.",
                voiceCommand: true,
                handler: handler
            )
        }
        
        checkRep()
    }
    
    // MARK: - Helpers
    
    func manageClipRemoval(entry: Entry) {
        for clipUID in entry.clips {
            guard var clipEntries = self.clips[clipUID] else {
                print("[Error] There was a problem removing entry clips from state. Clip UID \(clipUID) doesn't exist.")
                return
            }
            
            guard !clipEntries.contains(entry.uid) else {
                print("[Error] There was a problem removing entry clips from state. Clip UID \(clipUID) isn't associated with entry UID \(entry.uid).")
                return
            }
            
            if clipEntries.count > 1 {
                // Remove entryUID from clipEntries
                clipEntries.remove(entry.uid)
                
                // Set as new clipEntries for clipUID
                self.clips[clipUID] = clipEntries
            } else {
                // entryUID is the last uid associated with clip
                // remove clip from clips tracker
                self.clips.removeValue(forKey: clipUID)
                
                // Delete Clip
                let filePath = Utils.getFileURL(of: "\(entry.filename)-\(clipUID)\(entry.fileType)").absoluteString
                Utils.deleteExistingFile(atPath: filePath)
            }
        }
        
        checkRep()
    }
    
    func handleAudioDeviceChange() {
        if AVAudioSession.isHeadphonesConnected && AVAudioSession.bluetoothAudioConnected {
            // Bluetooth Headphones
            let audioDeviceDatum = AudioDeviceDatum(
                date: Date(),
                deviceType: .bluetoothHeadphones
            )
            self.audioDeviceUse.append(audioDeviceDatum)
        } else if AVAudioSession.isHeadphonesConnected && !AVAudioSession.bluetoothAudioConnected {
            // Wired Headphones
            let audioDeviceDatum = AudioDeviceDatum(
                date: Date(),
                deviceType: .wiredHeadphones
            )
            self.audioDeviceUse.append(audioDeviceDatum)
        } else {
            // Speakers
            let audioDeviceDatum = AudioDeviceDatum(
                date: Date(),
                deviceType: .speakers
            )
            self.audioDeviceUse.append(audioDeviceDatum)
        }
    }
}
