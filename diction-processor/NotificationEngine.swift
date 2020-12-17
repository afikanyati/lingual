//
//  NotificationEngine.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/31/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation
import Speech
import UIKit

class NotificationEngine {
    // MARK: - Notifications
    
    static let onStartTimedNotification = Notification.Name(Notifications.onStartTimedNotification.rawValue)
    static let onStartIndefiniteNotification = Notification.Name(Notifications.onStartIndefiniteNotification.rawValue)
    static let onStopNotification = Notification.Name(Notifications.onStopNotification.rawValue)
    
    // MARK: - App Modules
    
    var speechSynthesis: SpeechSynthesisEngine!
    var speechRecognition: SpeechRecognitionEngine!
    
    // MARK: -Notification Properties
    
    public var notificationQueue = Queue<NotificationItem>()
    private(set) var appNotificationTimer: Timer?
    private(set) var successFeedbackTimer: Timer?
    private(set) var errorFeedbackTimer: Timer?
    /// Specifies whether view has been instructed to clear out contents of notification queue
    private(set) var isExhaustingNotificationQueue = false
    private(set) var isPresentingVisualNotification = false
    
    // MARK: - Initialization and Deinitialization
    
    init() {
        print("===== Notification Manager: Initialization =====")
        
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
        
        // only exhausting queue if yout have items available
        result = result && ((self.isExhaustingNotificationQueue && !self.notificationQueue.isEmpty) || !self.isExhaustingNotificationQueue)
        
        if !result {
            fatalError("===== [Error] Notification Engine Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default

        notificationCenter.addObserver(
            self,
            selector: #selector(onWakePhraseDetected(notification:)),
            name: SpeechRecognitionEngine.onWakePhraseDetected,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(onIncorrectWakePhrase(notification:)),
            name: SpeechRecognitionEngine.onIncorrectWakePhrase,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(self.appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc func appWillTerminate() {
        print("===== Notification Engine: App Will Terminate =====")
        
        self.invalidateTimers()
    }
    
    @objc func onWakePhraseDetected(notification: Notification) {
        print("===== Notification Engine: On Wake Phrase Detected =====")
        // Remove voice command hint text
        self.stopNotification()
    }
    
    @objc func onIncorrectWakePhrase(notification: Notification) {
        print("===== Notification Engine: On Incorrect Wake Phrase =====")
        // Remove voice command hint text
        self.stopNotification()
        
        let utterance = notification.userInfo!["utterance"] as! String
        let transcription = notification.userInfo!["transcription"] as! SFTranscription
        if utterance.count > 0 {
            self.executeFeedback(
                visualMessage: "\"\(transcription.segments.count > 3 ? "\(transcription.segments.first!.substring.lowercased())...\(transcription.segments.last!.substring.lowercased())" : utterance.lowercased())\"",
                audioMessage: utterance,
                isVoiceCommand: true,
                discardPrior: true,
                withHaptics: true
            )
        }
    }
    
    // MARK: - Methods
    func scheduleNotification(
        text: String,
        type: NotificationType? = nil,
        isVoiceCommand: Bool = false,
        duration: TimeInterval? = 5
    ) {
        print("===== Notification Engine: Schedule Notification =====")
        let notificationItem = NotificationItem(
            text: text,
            type: type,
            isVoiceCommand: isVoiceCommand,
            duration: duration
        )
        self.notificationQueue.enqueue(notificationItem)
        
        checkRep()
    }
    
    func exhaustNotificationQueue() {
        print("===== Notification Engine: Exhaust Notification Queue =====")
        let item = self.notificationQueue.dequeue()
        self.isExhaustingNotificationQueue = !self.notificationQueue.isEmpty
        
        if let item = item {
            self.runTimedNotification(item: item)
        }
        
        checkRep()
    }
    
    func emptyNotificationQueue() {
        print("===== Notification Engine: Empty Notification Queue =====")
        self.notificationQueue.empty()
        self.speechSynthesis.emptySynthesizerQueue()
        
        checkRep()
    }
    
    func runTimedNotification(item: NotificationItem) {
        print("===== Notification Engine: Run Time Notification =====")
        print("\tPresenting: ", item.text)
        // Stop any prior notification that hasn't completed yet
        if self.appNotificationTimer != nil {
            self.appNotificationTimer?.invalidate()
            self.appNotificationTimer = nil
        }
        
        // Activate presenting notification flag
        self.isPresentingVisualNotification = true
        
        NotificationCenter.default.post(
            name: NotificationEngine.onStartTimedNotification,
            object: nil,
            userInfo: [ "item" : item ]
        )
        
        self.appNotificationTimer = Timer.scheduledTimer(withTimeInterval: item.duration!, repeats: false) {[weak self] timer in
            if self!.isExhaustingNotificationQueue {
                self!.exhaustNotificationQueue()
            } else {
                self?.appNotificationTimer?.invalidate()
                self?.appNotificationTimer = nil
                
                // Deactivate presenting notification flag
                self?.isPresentingVisualNotification = false
                
                NotificationCenter.default.post(
                    name: NotificationEngine.onStopNotification,
                    object: nil,
                    userInfo: [:]
                )
            }
        }
        
        // Give haptic feedback
        if let type = item.type {
            switch (type) {
            case .error:
                hapticEngine.error()
            case .warning:
                hapticEngine.warning()
            default:
                hapticEngine.success()
            }
        }
        
        checkRep()
    }
    
    func presentIndefiniteNotification(item: NotificationItem) {
        print("===== Notification Engine: Present Indefinite Notification =====")
        // Remove any timed notification
        if self.appNotificationTimer != nil {
            self.appNotificationTimer?.invalidate()
            self.appNotificationTimer = nil
        }
        
        // Activate presenting notification flag
        self.isPresentingVisualNotification = true
        
        NotificationCenter.default.post(
            name: NotificationEngine.onStartIndefiniteNotification,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func stopNotification() {
        print("===== Notification Engine: Stop Notification =====")
        
        if self.speechSynthesis.speechSynthesizer.isSpeaking {
            self.speechSynthesis.stopEcho(withFeedback: false)
        }
        
        if self.appNotificationTimer != nil {
            self.appNotificationTimer?.invalidate()
            self.appNotificationTimer = nil
        }
        
        if self.successFeedbackTimer != nil {
            self.successFeedbackTimer?.invalidate()
            self.successFeedbackTimer = nil
        }
        
        if self.errorFeedbackTimer != nil {
            self.errorFeedbackTimer?.invalidate()
            self.errorFeedbackTimer = nil
        }
        
        self.emptyNotificationQueue()
        
        // Deactivate presenting notification flag
        self.isPresentingVisualNotification = false
        
        NotificationCenter.default.post(
            name: NotificationEngine.onStopNotification,
            object: nil,
            userInfo: [:]
        )
        
        checkRep()
    }
    
    func executeFeedback(
        visualMessage: String? = nil,
        audioMessage: String? = nil,
        isVoiceCommand: Bool = false,
        discardPrior: Bool = false,
        withHaptics: Bool = false,
        delay: TimeInterval = Utils.DEFAULT_NOTIFICATION_DELAY
    ) {
        print("===== Notification Engine: Execute Feedback =====")
        
        if discardPrior {
            print("\tDiscarding prior notifications...")
            self.stopNotification()
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.successFeedbackTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { timer in
                // Give visual feedback
                if let visualMessage = visualMessage {
                    print("\tVisual Message: \(visualMessage)")
                    
                    self?.scheduleNotification(
                        text: visualMessage,
                        isVoiceCommand: isVoiceCommand,
                        duration: 3
                    )
                    if !self!.isExhaustingNotificationQueue {
                        self?.exhaustNotificationQueue()
                    }
                }
                
                // Give audio feedback
                if AVAudioSession.isHeadphonesConnected, let audioMessage = audioMessage {
                    print("\tAudio Message: \(audioMessage)")
                    // we don't run when !AVAudioSession.isHeadphonesConnected
                    // because we will will catch the words and process them
                    let voice = Utils.getSynthesizerVoice(withRegister: .female)

                    let synthesizerItem = SynthesizerItem(
                        synthesizer: self!.speechSynthesis.speechSynthesizer,
                        text: audioMessage,
                        voice: voice,
                        rate: self!.speechSynthesis.echoRate,
                        volume: Utils.playbackVolume
                    )

                    self?.speechSynthesis.synthesizerQueue.enqueue(synthesizerItem)
                    if !self!.speechSynthesis.isExhaustingSynthesizerQueue {
                        self?.speechSynthesis.exhaustSynthesizerQueue()
                    }
                }
                
                // Give haptic feedback
                if withHaptics {
                    hapticEngine.success()
                }
            }
        }
        
        checkRep()
    }
    
    func executeError(
        text: String,
        voiceCommand: Bool = false,
        delay: TimeInterval = Utils.DEFAULT_NOTIFICATION_DELAY,
        discardPrior: Bool = false,
        handler: (() -> Void)? = nil
    ) {
        print("===== Notification Engine: Execute Error =====")
        print("\tError: \(text)")
        
        // Stop any previous notification
        if discardPrior {
            self.stopNotification()
        }
        
        self.errorFeedbackTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { timer in
            if voiceCommand {
                // Play Sound
                soundEngine.voiceCommandDeny()
            } else {
                // Play Sound
                soundEngine.error()
            }
            
            // Give visual feedback
            self.scheduleNotification(
                text: text,
                isVoiceCommand: false,
                duration: 3
            )
            self.exhaustNotificationQueue()
            
            // Give haptic feedback
            hapticEngine.error()
            
            let errorHandler: () -> Void  = {
                let voice = Utils.getSynthesizerVoice(withRegister: .female)
                let synthesizerItem = SynthesizerItem(
                    synthesizer: self.speechSynthesis.speechSynthesizer,
                    text: text,
                    voice: voice,
                    rate: self.speechSynthesis.echoRate,
                    volume: Utils.playbackVolume
                )
                
                self.speechSynthesis.emptySynthesizerQueue()
                self.speechSynthesis.synthesizerQueue.enqueue(synthesizerItem)
                self.speechSynthesis.exhaustSynthesizerQueue()
                
                // Execute handler
                handler?()
            }
            
            if self.speechRecognition.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                print("\tIs Listening for Commands. Pause listening...")
                self.speechRecognition.pauseListeningForVoiceCommands() {
                    errorHandler()
                }
            } else if self.speechRecognition.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                print("\tIs Listening for Speech. Pause listening...")
                self.speechRecognition.pauseListeningForSpeech(preventListeningForCommands: true) {
                    errorHandler()
                }
            } else {
                errorHandler()
            }
        }
        
        checkRep()
    }
    
    func invalidateTimers() {
        print("===== Notification Engine: Invalidate Timers =====")
        self.appNotificationTimer?.invalidate()
        self.errorFeedbackTimer?.invalidate()
        self.successFeedbackTimer?.invalidate()
    }
}
