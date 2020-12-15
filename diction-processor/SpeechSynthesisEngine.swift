//
//  SpeechSynthesisEngine.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/31/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

class SpeechSynthesisEngine: NSObject, AVSpeechSynthesizerDelegate {
    // MARK: - Notifications
    
    static let onEchoStart = Notification.Name(Notifications.onEchoStart.rawValue)
    static let onEchoUpdate = Notification.Name(Notifications.onEchoUpdate.rawValue)
    static let onEchoFinish = Notification.Name(Notifications.onEchoFinish.rawValue)
    static let onRequestToUpdateView = Notification.Name(Notifications.onRequestToUpdateView.rawValue)
    
    // MARK: - App Modules
    
    var state: StateManager
    var notifications: NotificationEngine
    var speechPlayer: SpeechPlayerEngine
    weak var speechRecognition: SpeechRecognitionEngine!
    weak var selectionCursor: SelectionCursor!
    weak var entryManager: EntryManager!

    // MARK: - Speech Synthesis Properties
    
    private(set) var speechSynthesizer = AVSpeechSynthesizer()
    private(set) var synthesizerVoice : AVSpeechSynthesisVoice?
    /// Stores a queue of synthesizer tasks to be executed serially
    public var synthesizerQueue = Queue<SynthesizerItem>()
    /// Specifies whether view has been instructed to clear out contents of synthesizer queue
    private(set) var isExhaustingSynthesizerQueue = false
    /// Stores flag that indicates if we've prematurely ended echo utterance
    private(set) var interruptedEcho = false
    /// Stores the rate of the speech synthesis speech
    var echoRate: Float {
        return self.state._echoRate
    }
    private var updateEchoRate = false
    /// Stores a temporary handler to be executed when echo is complete (executes on-demand)
    private(set) var tempOnEchoFinish: (() -> Void)?
    /// Specifies whether echo is currently playing
    private(set) var isPlayingEcho = false
    /// Specifies whether passive echo is currently playing
    private(set) var isPlayingPassiveEcho = false
    /// Specifies whether echo is currently paused (active, but paused vs. inactive)
    public var pausedEcho: Bool {
        return self.speechSynthesizer.isPaused
    }
    /// Stores segment range currently being played
    private(set) var echoSegments: [EntrySegment]? = nil
    /// Stores range of segments in echoSegments
    private(set) var echoRange: Range<Int>? = nil
    /// Stores echoSegments source
    private(set) var echoSegmentsTrackType: EntryTrackType? = nil
    
    // MARK: - Initialization and Deinitialization
    
    init(state: StateManager, speechPlayer: SpeechPlayerEngine, notifications: NotificationEngine) {
        print("===== Speech Synthesis Engine: Initialization =====")
        self.state = state
        self.notifications = notifications
        self.speechPlayer = speechPlayer
        
        super.init()
        
        // Assign delegates
        self.speechSynthesizer.delegate = self
        
        self.configureNotificationObservers()
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Validation
    
    func checkRep() {
        var result = true
        
        // only exhausting queue if yout have items available
        result = result && ((self.isExhaustingSynthesizerQueue && !self.synthesizerQueue.isEmpty) || !self.isExhaustingSynthesizerQueue)
        
        // ony update echo rate if we're playing echo
        result = result && (self.updateEchoRate && (self.isPlayingEcho || self.isPlayingPassiveEcho) || !self.updateEchoRate)
        
        if !result {
            fatalError("===== [Error] Entry Manager Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default

        // SpeechRecognition
        notificationCenter.addObserver(
            self,
            selector: #selector(onWakePhraseDetected(notification:)),
            name: SpeechRecognitionEngine.onWakePhraseDetected,
            object: nil
        )
        
        // VoiceCommandEngine
        notificationCenter.addObserver(
            self,
            selector: #selector(onProcessedVoiceCommand(notification:)),
            name: VoiceCommandEngine.onProcessedVoiceCommand,
            object: nil
        )
        
        // State
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryDeleted(notification:)),
            name: EntryManager.onEntryDeleted,
            object: nil
        )
        
        // DetailViewController
        notificationCenter.addObserver(
            self,
            selector: #selector(onChangedEchoRate(notification:)),
            name: DetailViewController.onChangedEchoRate,
            object: nil
        )
        
        // SpeechPlayer
        notificationCenter.addObserver(
            self,
            selector: #selector(onSpeechStartedPlaying(notification:)),
            name: SpeechPlayerEngine.onStartedPlaying,
            object: nil
        )
        
        // Entry
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryCommittedBuffer(notification:)),
            name: Entry.onEntryCommittedBuffer,
            object: nil
        )
    }
    
    @objc func onWakePhraseDetected(notification: Notification) {
        print("===== Speech Synthesis Engine: On Wake Phrase Detected =====")
        // Remove any speech synthesizing
        self.emptySynthesizerQueue()
    }
    
    @objc func onProcessedVoiceCommand(notification: Notification) {
        print("===== Speech Synthesis Engine: On Processed Voice Command =====")
        let command = notification.userInfo!["command"] as! VoiceCommandEngine.VoiceCommand
        var handler: (() -> Void)?
        if notification.userInfo!["handler"] != nil {
            handler = notification.userInfo!["handler"] as? () -> Void
        }
        
        switch (command) {
        case .INCREASE_ECHO_RATE:
            print("\tVoice Command: Increase Echo Rate")
            self.increaseEchoRate(
                handler: handler
            )
        case .DECREASE_ECHO_RATE:
            print("\tVoice Command: Decrease Echo Rate")
            self.decreaseEchoRate(
                handler: handler
            )
        default:
            // Do nothing
            break
        }
    }
    
    @objc func onEntryDeleted(notification: Notification) {
        print("===== Speech Synthesis Engine: On Entry Deleted =====")
        self.stopEcho(withFeedback: false)
    }
    
    @objc func onChangedEchoRate(notification: Notification) {
        print("===== Speech Synthesis Engine: On Changed Echo Rate =====")
        let rate = notification.userInfo!["rate"] as! Float
        self.setEchoRate(to: rate)
    }
    
    @objc func onSpeechStartedPlaying(notification: Notification) {
        print("===== Speech Synthesis Engine: On Speech Started Playing =====")
        if self.isPlayingEcho || self.isPlayingPassiveEcho {
            self.stopEcho(withFeedback: false)
        }
    }
    
    @objc func onEntryCommittedBuffer(notification: Notification) {
        print("===== Speech Synthesis Engine: On Entry Committed Buffer =====")

        if let entry = self.entryManager.currentEntry, self.state.withPassiveEcho && AVAudioSession.isHeadphonesConnected && self.speechRecognition.isListeningForSpeech && !self.speechRecognition.pausedListeningForSpeech && !self.selectionCursor.isUpdatingSelection {
            print("\tAttempting to execute passive echo...")
            
            if let lastEchoSegmentRange = entry.committedBufferRanges.last {
                print("\tExecuting passive echo with last committed buffer: \(lastEchoSegmentRange)")

                // Echo formatted String
                self.executePassiveEcho(entry: entry)
                
                // Give haptic feedback
                hapticEngine.lightImpact()
            }
        }
    }
    
    // MARK: - Methods
    
    func startEcho(segments: [EntrySegment], allowPlayer: Bool = false, onStartHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
        print("===== Speech Synthesis Engine: Start Echo =====")
        if self.speechPlayer.player.isPlaying && !allowPlayer {
            print("\tStop speech audio to play speech synthesizer")
            self.speechPlayer.stop(withFeedback: false)
        }
        
        if segments.count == 0 {
            // havent recorded anything
            self.notifications.executeError(
                text: "Error starting echo.",
                handler: onStartHandler
            )
            return
        }
        
        // Give audio feedback
        // *** The entry playing is the audio feedback ***
        
        let executeEcho = {
            // Play Sound
            if !self.speechRecognition.isListeningForSpeech &&
                !self.selectionCursor.hasSelection &&
                !self.entryManager.isRunningEntry &&
                !self.entryManager.isWalkingEntry
            {
                soundEngine.play()
            }
            
            // Give feedback
            if !self.entryManager.isWalkingEntry && !self.entryManager.isRunningEntry {
                self.notifications.executeFeedback(
                    visualMessage: "Start Echo",
                    withHaptics: true
                )
            }
            
            if self.pausedEcho {
                // continue last echo
                print("\tContinue existing echo utterance...")
                self.speechSynthesizer.continueSpeaking()
            } else {
                // start new echo
                print("\tInitiate new speech synthesizer utterance...")
                
                let text = Entry.getText(
                    segments: segments,
                    withTemporalSuggestions: false,
                    withPunctuationSuggestions: self.state.withPunctuationSuggestions,
                    withFormattingSuggestions: self.state.withFormattingSuggestions,
                    strictlyAsWord: false,
                    withCapitalization: self.state.withCapitalization,
                    forEcho: false
                )

                let synthesizerItem = SynthesizerItem(
                    synthesizer: self.speechSynthesizer,
                    text: text,
                    voice: Utils.getSynthesizerVoice(withRegister: self.state.speaker.register),
                    rate: self.echoRate,
                    volume: Utils.playbackVolume
                )
                
                self.synthesizerQueue.enqueue(synthesizerItem)
                self.exhaustSynthesizerQueue()
                self.isPlayingEcho = true
                
                // cache range of echo segments
                self.echoSegments = segments
                self.echoSegmentsTrackType = .other
                self.echoRange = 0..<segments.count
                
                if let onFinishHandler = onFinishHandler {
                    self.setEchoHandler(handler: onFinishHandler)
                }
            
                onStartHandler?()
            }
        }
        
        if self.speechRecognition.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            print("\tListening for commands without headphones. Stop while playin echo.")
            self.speechRecognition.pauseListeningForVoiceCommands() {
                executeEcho()
                self.checkRep()
            }
        } else if self.speechRecognition.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
            print("\tListening for commands without headphones. Stop while playin echo.")
            self.speechRecognition.pauseListeningForSpeech(preventListeningForCommands: true) {
                executeEcho()
                self.checkRep()
            }
        } else if (self.speechRecognition.isListeningForCommands || self.speechRecognition.isListeningForSpeech) && AVAudioSession.isHeadphonesConnected {
            executeEcho()
            checkRep()
        }
    }
    
    func pauseEcho(handler: (() -> Void)? = nil) {
        print("===== Speech Synthesis Engine: Pause Echo =====")
        
        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: "Pause Echo",
            audioMessage: "echo paused",
            withHaptics: true
        )
        
        self.speechSynthesizer.pauseSpeaking(at: .immediate)
        
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { timer in
            // we delay handler so that pauseSpeaking can take effect before we
            // process handler which might rely on paused state.
            // e.g. startListeningForSpeech will stopEcho() if it encounters non-paused echo.
            handler?()
        }
        
        checkRep()
    }
    
    @objc func stopEcho(withFeedback: Bool = true, handler: (() -> Void)? = nil) {
        print("===== Speech Synthesis Engine: Stop Echo =====")
        
        // Present Feedback
        if withFeedback && !self.entryManager.isWalkingEntry && !self.entryManager.isRunningEntry {
            self.notifications.executeFeedback(
                visualMessage: "Stop Echo",
                audioMessage: "echo stopped",
                withHaptics: true
            )
        }
        
        self.speechSynthesizer.stopSpeaking(at: .immediate)
        
        self.isPlayingEcho = false
        self.isPlayingPassiveEcho = false
        self.echoRange = nil
        self.echoSegments = nil

        handler?()
        
        NotificationCenter.default.post(
            name: SpeechSynthesisEngine.onEchoFinish,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func exhaustSynthesizerQueue() {
        print("===== Speech Synthesis Engine: Exhaust Synthesizer Queue =====")
        let item = self.synthesizerQueue.dequeue()
        self.isExhaustingSynthesizerQueue = !self.synthesizerQueue.isEmpty

        if let item = item {
            self.runSpeechSynthesizer(item: item)
        }
        
        checkRep()
    }
    
    func emptySynthesizerQueue() {
        print("===== Speech Synthesis Engine: Empty Synthesizer Queue =====")
        if self.speechSynthesizer.isSpeaking {
            self.speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        self.synthesizerQueue.empty()
        self.isExhaustingSynthesizerQueue = false
        
        checkRep()
    }
    
    func executePassiveEcho(entry: Entry) {
        print("===== Speech Synthesis Engine: Execute Passive Echo =====")
        
        guard let echoRange = entry.committedBufferRanges.last else { return }
        
        if self.speechPlayer.player.isPlaying {
            print("\tStop speech audio to play speech synthesizer")
            self.speechPlayer.stop(withFeedback: false)
        }
        
        self.echoRange = echoRange
        print("\tEcho Range: ", self.echoRange ?? "nil")
        self.echoSegmentsTrackType = .committed
        print("\tEcho Segments Track Type: ", self.echoSegmentsTrackType ?? "nil")
        self.echoSegments = entry.entrySegments
        
        // Get echo text
        let text = Entry.getText(segments: Array(entry.entrySegments[echoRange]))
        let echoText = text.trimTrailingPunctuation()
        print("\techoing: \"\(echoText)\"")
        
        
        let synthesizerItem = SynthesizerItem(
            synthesizer: self.speechSynthesizer,
            text: echoText,
            voice: Utils.getSynthesizerVoice(withRegister: self.state.speaker.register),
            rate: self.echoRate,
            volume: Utils.playbackVolume
        )
        
        self.synthesizerQueue.enqueue(synthesizerItem)
        self.exhaustSynthesizerQueue()
        self.isPlayingPassiveEcho = true
        
        checkRep()
    }
    
    // MARK: - Setters
    
    func setEchoHandler(handler: (() -> Void)? = nil) {
        print("===== Speech Synthesis Engine: Set Echo Handler =====")
        self.tempOnEchoFinish = handler
        checkRep()
    }
    
    // Implementing real-time rate change: https://stackoverflow.com/questions/25499803/how-to-change-speech-rate-during-speaking-using-avspeechsynthesizer-in-ios-7
    func setEchoRate(to rate: Float) {
        print("===== Speech Synthesis Engine: Set Echo Rate =====")
        print("\tSet rate to: ", rate)
        
        if self.isPlayingEcho || self.isPlayingPassiveEcho {
            print("\tStaging an echo update on currently playing echo...")
            self.updateEchoRate = true
        }
        
        self.state.setEchoRate(to: rate)
        checkRep()
    }
    
    
    // MARK: - Helper Methods
    
    func runSpeechSynthesizer(item: SynthesizerItem) {
        print("===== Speech Synthesis Engine: Play Speech Synthesizer =====")
        print("\tUttering: ", item.text)
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.rate = item.rate
        utterance.volume = item.volume

        if let voice = item.voice {
            utterance.voice = voice
            item.synthesizer.speak(utterance)
        } else {
            item.synthesizer.speak(utterance)
        }
    }
    
    // MARK: - Speech Synethesizer Delegate
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("===== Speech Synthesis Engine: didStart =====")
        print("\tUtterance: \(utterance.speechString)")
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("===== Speech Synthesis Engine: didPause =====")
        print("\tUtterance: \(utterance.speechString)")
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("===== Speech Synthesis Engine: didContinue =====")
        print("\tUtterance: \(utterance.speechString)")
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("===== Speech Synthesis Engine: didContinue =====")
        print("\tUtterance: \(utterance.speechString)")
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // Highlight word currently being uttered
        if let entry = self.entryManager.currentEntry,
            let echoRange = self.echoRange,
           let echoSegments = self.echoSegments,
           let echoSegmentsTrackType = self.echoSegmentsTrackType,
           echoSegments.count > 0 &&
            echoSegments.count >= echoRange.count &&
            echoSegments.count >= echoRange.upperBound &&
            self.state.appActivated &&
            (
                self.isPlayingEcho ||
                self.isPlayingPassiveEcho
            )
        {
            // We do this so that we have the most recent version of the segment sources
            // When we commit segments, we create new entries and there are sometimes
            // race conditions where the segments in entry do not have their
            // entry reference set, causing their methods (that require that reference)
            // to throw an error
            let passiveSegments: [EntrySegment]
            switch (echoSegmentsTrackType) {
            case .buffer:
                passiveSegments = Array(entry.entryBuffer[echoRange])
            case .committed:
                passiveSegments = Array(entry.entrySegments[echoRange])
            default:
                passiveSegments = Array(echoSegments[echoRange])
            }
            
            guard utterance.speechString.trimTrailingPunctuation() == Entry.getText(
                    segments: passiveSegments, withTemporalSuggestions: false,
                    withPunctuationSuggestions: self.state.withPunctuationSuggestions,
                    withFormattingSuggestions: self.state.withFormattingSuggestions,
                    strictlyAsWord: false,
                    withCapitalization: self.state.withCapitalization,
                    forEcho: false
            ).trimTrailingPunctuation() else { return }
            
            NotificationCenter.default.post(
                name: SpeechSynthesisEngine.onEchoUpdate,
                object: nil,
                userInfo: [ "highlightRange": characterRange]
            )
        }
        
        // Process realtime changes to echo rate
        if let _ = self.entryManager.currentEntry, self.updateEchoRate, self.state.appActivated {
            // Compute unprocessed utterance
            let numProcessedChar = max(0, characterRange.location)
            let unprocessedUtterance = utterance.speechString.substring(fromIndex: numProcessedChar).lowercased()
            
            // Stop speech synthesizer
            self.speechSynthesizer.stopSpeaking(at: .immediate)
            
            // Run remainder utterance
            let synthesizerItem = SynthesizerItem(
                synthesizer: self.speechSynthesizer,
                text: unprocessedUtterance,
                voice: Utils.getSynthesizerVoice(withRegister: self.state.speaker.register),
                rate: self.echoRate,
                volume: Utils.playbackVolume
            )
            self.runSpeechSynthesizer(item: synthesizerItem)
            
            self.updateEchoRate = false
            self.interruptedEcho = true
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("===== Speech Synthesis Engine: didFinish =====")
        print("\tUtterance: \(utterance.speechString)")
        if self.interruptedEcho {
            // We just modified the echo rate while playing echo
            // this ends echo and creates a new one with new rate
            // from the last word uttered
            //
            // Do nothing
            self.interruptedEcho = false
            return
        }
        
        if let _ = self.entryManager.currentEntry, !self.isPlayingPassiveEcho {
            // Avoid updating ui when selection
            // it will remove selection
            NotificationCenter.default.post(
                name: SpeechSynthesisEngine.onEchoFinish,
                object: nil,
                userInfo: [:]
            )
        }
        
        if self.isExhaustingSynthesizerQueue {
            self.exhaustSynthesizerQueue()
        } else if self.isPlayingEcho {
            // turn off isPlayingEcho
            self.isPlayingEcho = false
            self.echoSegments = nil
            self.echoRange = nil
            self.echoSegmentsTrackType = nil
            
            // Update View
            NotificationCenter.default.post(
                name: SpeechSynthesisEngine.onRequestToUpdateView,
                object: nil,
                userInfo: [:]
            )
        } else if isPlayingPassiveEcho {
            // turn off isPlayingPassiveEcho
            self.isPlayingPassiveEcho = false
            self.echoSegments = nil
            self.echoRange = nil
            self.echoSegmentsTrackType = nil
            
            // Update View
            NotificationCenter.default.post(
                name: SpeechSynthesisEngine.onRequestToUpdateView,
                object: nil,
                userInfo: [:]
            )
        }

        self.tempOnEchoFinish?()
        self.tempOnEchoFinish = nil
        
        if self.state.appActivated && self.speechRecognition.pausedListeningForCommands && !self.speechSynthesizer.isSpeaking && !AVAudioSession.isHeadphonesConnected {
            // when headphones are off we don't listen for voice commands while echoing
            // but on completion we turn it back on
            self.speechRecognition.startListeningForVoiceCommands() {
                // Call after isPlayingEcho is set to false by tempOnEchoFinish
                NotificationCenter.default.post(
                    name: SpeechSynthesisEngine.onRequestToUpdateView,
                    object: nil,
                    userInfo: [:]
                )
            }
        } else if let entry = self.entryManager.currentEntry, self.state.appActivated && entry.speechRecognition.pausedListeningForSpeech && !self.speechSynthesizer.isSpeaking && !AVAudioSession.isHeadphonesConnected && !self.entryManager.isRunningEntry && !self.entryManager.isWalkingEntry {
            // when headphones are off we don't listen for speech while echoing
            // but on completion we turn it back on
            entry.speechRecognition.startListeningForSpeech(
                onStartHandler: {
                    // Call after isPlayingEcho is set to false by tempOnEchoFinish
                    NotificationCenter.default.post(
                        name: SpeechSynthesisEngine.onRequestToUpdateView,
                        object: nil,
                        userInfo: [:]
                    )
                }
            )
        }
    }
    
    // MARK: - Voice Commands
    
    func increaseEchoRate(
        handler: (() -> Void)? = nil
    ) {
        print("===== Speech Synthesis Engine: Increase Echo Rate =====")
        print("\tTriggered by voice command.")
        let currentEchoRate = self.echoRate
        let newEchoRate = min(currentEchoRate + Utils.DISCRETE_ECHO_RATE_DELTA, Utils.MAXIMUM_ECHO_RATE).rounded(toPlaces: 2)
        if currentEchoRate < Utils.MAXIMUM_ECHO_RATE {
            // Play Sound
            soundEngine.voiceCommandAccept()
            self.setEchoRate(to: newEchoRate)
    
            handler?()
        } else {
            self.notifications.executeError(
                text: "Echo Rate already at fastest.",
                voiceCommand: true,
                handler: handler
            )
        }
        
        checkRep()
    }
    
    func decreaseEchoRate(
        handler: (() -> Void)? = nil
    ) {
        print("===== Speech Synthesis Engine: Decrease Echo Rate =====")
        print("\tTriggered by voice command.")
        let currentEchoRate = self.echoRate
        let newEchoRate = max(currentEchoRate - Utils.DISCRETE_ECHO_RATE_DELTA, Utils.MINIMUM_ECHO_RATE).rounded(toPlaces: 2)
        if currentEchoRate > Utils.MINIMUM_ECHO_RATE {
            // Play Sound
            soundEngine.voiceCommandAccept()
            self.setEchoRate(to: newEchoRate)
            
            handler?()
        } else {
            self.notifications.executeError(
                text: "Echo Rate already at slowest.",
                voiceCommand: true,
                handler: handler
            )
        }
        
        checkRep()
    }
}

// Best English Voices and Voices with Enhanced
// * US:
//     * Allison (Neutral)
//     * Ava (a bit sensual)
//     * Samantha (high-pitched)
//     * Susan (spunky)
//     * Tom (Deep)
// * Australia:
//     * Karen (good)
//     * Lee (good)
// * Ireland:
//     * Moira (not too good)
// * South Africa:
//     * Tessa (good, but a bit robotic)
// * UK:
//     * Daniel (good and deep, royal)
//     * Kate (slightly robotic but good)
//     * Oliver (good, deep, and pedestrian)
//     * Serena (a bit excited)
