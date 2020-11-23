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
    weak var noteManager: NoteManager!

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
    /// Range of last echo of note segments
    private(set) var lastEchoSegmentRange: Range<Int>?
    
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
            fatalError("===== [Error] Note Manager Representation Invariants were broken =====")
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
            selector: #selector(onNoteDeleted(notification:)),
            name: NoteManager.onNoteDeleted,
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
        
        // Note
        notificationCenter.addObserver(
            self,
            selector: #selector(onNoteCommittedBuffer(notification:)),
            name: Note.onNoteCommittedBuffer,
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
        let command = notification.userInfo!["command"] as! String
        var handler: (() -> Void)?
        if notification.userInfo!["handler"] != nil {
            handler = notification.userInfo!["handler"] as? () -> Void
        }
        
        switch (command) {
        case "increase echo rate":
            print("\tVoice Command: Increase Echo Rate")
            self.increaseEchoRate(
                handler: handler
            )
        case "decrease echo rate":
            print("\tVoice Command: Decrease Echo Rate")
            self.decreaseEchoRate(
                handler: handler
            )
        default:
            // Do nothing
            break
        }
    }
    
    @objc func onNoteDeleted(notification: Notification) {
        print("===== Speech Synthesis Engine: On Deleted Note =====")
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
    
    @objc func onNoteCommittedBuffer(notification: Notification) {
        print("===== Speech Synthesis Engine: On Note Committed Buffer =====")

        if let note = self.noteManager.currentNote, self.state.withPassiveEcho && AVAudioSession.isHeadphonesConnected && self.speechRecognition.isListeningForSpeech && !self.speechRecognition.pausedListeningForSpeech && !self.selectionCursor.isUpdatingSelection {
            print("\tAttempting to execute passive echo...")
            // compute echo text range
            if let lastEchoSegmentRange = note.committedBufferRanges.last {
                self.lastEchoSegmentRange = lastEchoSegmentRange
            } else {
                print("\t[Error] Unable to retrieve last buffer range")
            }
            
            if let lastEchoSegmentRange = self.lastEchoSegmentRange {
                print("\tExecuting passive echo...")
                let text = note.getText(segments: Array(note.noteSegments[lastEchoSegmentRange]))

                // Echo formatted String
                self.executePassiveEcho(text: text)
                
                // Give haptic feedback
                hapticEngine.lightImpact()
            }
        }
    }
    
    // MARK: - Methods
    
    func startEcho(segments: [NoteSegment], allowPlayer: Bool = false, onStartHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
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
        // *** The note playing is the audio feedback ***
        
        let executeEcho = {
            // Play Sound
            if !self.speechRecognition.isListeningForSpeech {
                soundEngine.play()
            }
            
            // Give feedback
            if !self.noteManager.isWalkingNote && !self.noteManager.isRunningNote {
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
                
                let text = Note.getText(
                    segments: segments,
                    withTemporalSuggestions: self.state.withTemporalSuggestions,
                    withPunctuationSuggestions: self.state.withPunctuationSuggestions,
                    withFormattingSuggestions: self.state.withFormattingSuggestions,
                    strictlyAsWord: self.state.withTextStrictlyAsWords,
                    withCapitalization: self.state.withCapitalization
                )

                let synthesizerItem = SynthesizerItem(
                    synthesizer: self.speechSynthesizer,
                    text: text,
                    voice: Utils.getSynthesizerVoice(withGender: self.state.speaker.gender),
                    rate: self.echoRate,
                    volume: Utils.playbackVolume
                )
                
                self.synthesizerQueue.enqueue(synthesizerItem)
                self.exhaustSynthesizerQueue()
                self.isPlayingEcho = true
                
                // cache range of echo segments
                self.lastEchoSegmentRange = segments.first!.getIndex()..<segments.last!.getIndex() + 1
                
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
        if withFeedback && !self.noteManager.isWalkingNote && !self.noteManager.isRunningNote {
            self.notifications.executeFeedback(
                visualMessage: "Stop Echo",
                audioMessage: "echo stopped",
                withHaptics: true
            )
        }
        
        self.speechSynthesizer.stopSpeaking(at: .immediate)
        
        self.isPlayingEcho = false
        self.isPlayingPassiveEcho = false

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
    
    func executePassiveEcho(text: String) {
        print("===== Speech Synthesis Engine: Execute Passive Echo =====")
        
        if self.speechPlayer.player.isPlaying {
            print("\tStop speech audio to play speech synthesizer")
            self.speechPlayer.stop(withFeedback: false)
        }
        
        let echoText = text.trimTrailingPunctuation()
        print("\techoing: \"\(echoText)\"")
        
        
        let synthesizerItem = SynthesizerItem(
            synthesizer: self.speechSynthesizer,
            text: echoText,
            voice: Utils.getSynthesizerVoice(withGender: self.state.speaker.gender),
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

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("===== Speech Synthesis Engine: didContinue =====")
        print("\tUtterance: \(utterance.speechString)")
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("===== Speech Synthesis Engine: didContinue =====")
        print("\tUtterance: \(utterance.speechString)")
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
        
        if let _ = self.noteManager.currentNote, !self.isPlayingPassiveEcho {
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
        } else if let _ = self.noteManager.currentNote, self.isPlayingEcho {
            // turn off isPlayingEcho
            self.isPlayingEcho = false
            
            // Update View
            NotificationCenter.default.post(
                name: SpeechSynthesisEngine.onRequestToUpdateView,
                object: nil,
                userInfo: [:]
            )
        } else if let note = self.noteManager.currentNote, self.isPlayingPassiveEcho && utterance.speechString == Note.getText(segments: Array(note.noteSegments[self.lastEchoSegmentRange!])).trimTrailingPunctuation() {
            // turn off isPlayingPassiveEcho
            self.isPlayingPassiveEcho = false
            
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
        } else if let note = self.noteManager.currentNote, self.state.appActivated && note.speechRecognition.pausedListeningForSpeech && !self.speechSynthesizer.isSpeaking && !AVAudioSession.isHeadphonesConnected && !self.noteManager.isRunningNote && !self.noteManager.isWalkingNote {
            // when headphones are off we don't listen for speech while echoing
            // but on completion we turn it back on
            note.speechRecognition.startListeningForSpeech(
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

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("===== Speech Synthesis Engine: didPause =====")
        print("\tUtterance: \(utterance.speechString)")
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("===== Speech Synthesis Engine: didStart =====")
        print("\tUtterance: \(utterance.speechString)")
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        if let note = self.noteManager.currentNote, let lastEchoSegmentRange = self.lastEchoSegmentRange, note.noteSegments.count >= lastEchoSegmentRange.count {
            print("===== Speech Synthesis Engine: willSpeakRangeOfSpeechString =====")
            print("\tUtterance: \(utterance.speechString)")
            print("\tApp Activated: ", self.state.appActivated)
            print("\tIs Playing Echo: ", self.isPlayingEcho)
            print("\tIs Playing Passive Echo: ", self.isPlayingPassiveEcho)
            print("\tTrimmed Utterance String: ", utterance.speechString.trimTrailingPunctuation())
            print("\tTrimmed Last Commit String: ", note.getText(segments: Array(note.noteSegments[lastEchoSegmentRange])).trimTrailingPunctuation())
            print("\tString equal: ", utterance.speechString.trimTrailingPunctuation() == note.getText(segments: Array(note.noteSegments[lastEchoSegmentRange])).trimTrailingPunctuation())
        }
        
        if let note = self.noteManager.currentNote, self.state.appActivated && (self.isPlayingEcho || self.isPlayingPassiveEcho) && utterance.speechString.trimTrailingPunctuation() == note.getText(segments: Array(note.noteSegments[self.lastEchoSegmentRange!])).trimTrailingPunctuation() {
            var textRange = characterRange
            // find lowest segment that is a word
            var lowestEchoSegment: NoteSegment?
            for segment in note.noteSegments[self.lastEchoSegmentRange!] {
                if !segment.isSilence() && !segment.isVoiceCommandWord() && !segment.isDeleted() {
                    lowestEchoSegment = segment
                    break
                }
            }

            if let note = self.noteManager.currentNote, let lowestEchoSegment = lowestEchoSegment, let lowestEchoSegmentRange = note.getSegmentTextRange(of: lowestEchoSegment), self.speechRecognition.isListeningForSpeech {
                textRange = NSRange(location: lowestEchoSegmentRange.location + characterRange.location, length: characterRange.length)
            }
            
            NotificationCenter.default.post(
                name: SpeechSynthesisEngine.onEchoUpdate,
                object: nil,
                userInfo: [ "highlightRange": textRange]
            )
        }
        
        if let _ = self.noteManager.currentNote, self.updateEchoRate, self.state.appActivated {
            // Compute unprocessed utterance
            let numProcessedChar = max(0, characterRange.location)
            let unprocessedUtterance = utterance.speechString.substring(fromIndex: numProcessedChar).lowercased()
            
            // Stop speech synthesizer
            self.speechSynthesizer.stopSpeaking(at: .immediate)
            
            // Run remainder utterance
            let synthesizerItem = SynthesizerItem(
                synthesizer: self.speechSynthesizer,
                text: unprocessedUtterance,
                voice: Utils.getSynthesizerVoice(withGender: self.state.speaker.gender),
                rate: self.echoRate,
                volume: Utils.playbackVolume
            )
            self.runSpeechSynthesizer(item: synthesizerItem)
            
            self.updateEchoRate = false
            self.interruptedEcho = true
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
            self.notifications.executeFeedback(
                visualMessage: "Echo Rate: \(newEchoRate)",
                audioMessage: "Echo Rate increased to \(newEchoRate)",
                withHaptics: true
            )
    
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
            self.notifications.executeFeedback(
                visualMessage: "Echo Rate: \(newEchoRate)",
                audioMessage: "Echo Rate decreased to \(newEchoRate)",
                withHaptics: true
            )
    
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
