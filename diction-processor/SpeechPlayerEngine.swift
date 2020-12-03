//
//  SpeechPlayerEngine.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/31/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

class SpeechPlayerEngine: NSObject {
    // MARK: - Notifications
    
    static let onStartedPlaying = Notification.Name(Notifications.onStartedPlaying.rawValue)
    static let onBoundaryCrossed = Notification.Name(Notifications.onBoundaryCrossed.rawValue)
    static let onSecondElapsed = Notification.Name(Notifications.onSecondElapsed.rawValue)
    static let onStoppedPlaying = Notification.Name(Notifications.onStoppedPlaying.rawValue)
    
    // MARK: - App Modules
    
    var state: StateManager
    var notifications: NotificationEngine
    weak var selectionCursor: SelectionCursor!
    weak var speechSynthesis: SpeechSynthesisEngine!
    weak var speechRecognition: SpeechRecognitionEngine!
    weak var entryManager: EntryManager!
    weak var entryListManager: EntryListManager!
    
    // MARK: - Audio Playback
    
    /// Stores the current playback rate of entry playback
    var playbackRate: Float {
        return self.state._playbackRate
    }
    
    /// Specifies whether entry is currently playing
    var isPlayingEntry: Bool {
        return player.isPlaying
    }
    /// Specifies whether entry is currently paused
    private(set) var pausedPlayingEntry = false
    
    /// Stores a reference to the entry's player object
    private(set) var player = AVPlayer()
    
    /// Specifies the time value at which entry playback should begin
    private(set) var startPlaybackAt: CMTime?
    /// Specifies the time value at which entry playback should end
    private(set) var stopPlaybackAt: CMTime?
    /// Stores a reference to a timer that begins next iteration of looping player
    private(set) var playerLoopTimer: Timer?
    /// Stores a reference to the playback observer that executes after each segment
    private(set) var boundaryObserverToken: Any?
    /// Stores a reference to the playback observer that executes each second
    private(set) var timerObserverToken: Any?
    /// Stores a reference to the playback observer that executes when playback is complete
    private(set) var completionObserverToken: Any?
    /// Stores a reference to the last segment processed during entry playback. Prevents repeat processing.
    private(set) var previousBoundarySegment: EntrySegment?
    
    /// Specifies whether playing external segments
    private(set) var isPlayingExternalSegments = false
    
    /// Stores segment range currently being played
    private(set) var playbackSegments: [EntrySegment]? = nil
    
    /// Stores segments currently being played
    
    /// Stores handlers to be executed when entry is played
    private(set) var onStartHandler: (() -> Void)?
    /// Stores handlers to be executed when entry is finished playing
    private(set) var onFinishHandler: (() -> Void)?

    // MARK: - Initialization and Deinitialization
    
    init(state: StateManager, notifications: NotificationEngine) {
        print("===== Speech Player Engine: Initialization =====")
        self.state = state
        self.notifications = notifications
        
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
        
        // playback elements should be set if we're playing segments
        result = result && ((self.isPlayingEntry && self.playbackSegments != nil && self.playbackSegments!.count > 0 && self.startPlaybackAt != nil && self.stopPlaybackAt != nil) || !self.isPlayingEntry)
        
        if !result {
            fatalError("===== [Error] Entry Manager Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
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
            selector: #selector(onChangedPlayerRate(notification:)),
            name: DetailViewController.onChangedPlayerRate,
            object: nil
        )
    }
    
    @objc func onProcessedVoiceCommand(notification: Notification) {
        print("===== Speech Player Engine: On Processed Voice Command =====")
        let command = notification.userInfo!["command"] as! VoiceCommandEngine.VoiceCommand
        var handler: (() -> Void)?
        if notification.userInfo!["handler"] != nil {
            handler = notification.userInfo!["handler"] as? () -> Void
        }
        
        switch (command) {
        case .INCREASE_PLAYBACK_RATE:
            print("\tVoice Command: Increase Playback Rate")
            self.increasePlaybackRate(
                handler: handler
            )
        case .DECREASE_PLAYBACK_RATE:
            print("\tVoice Command Engine: Decrease Playback Rate")
            self.decreasePlaybackRate(
                handler: handler
            )
        default:
            // Do nothing
            break
        }
    }
    
    @objc func onEntryDeleted(notification: Notification) {
        print("===== Speech Player Engine: On Entry Deleted=====")
        self.stop(withFeedback: false)
        
        checkRep()
    }
    
    @objc func onChangedPlayerRate(notification: Notification) {
        print("===== Speech Player Engine: On Changed Player Entry =====")
        let rate = notification.userInfo!["rate"] as! Float
        let _ = self.setPlayerRate(rate: rate)
        
        checkRep()
    }
    
    // MARK: - Methods
    
    // Requires that the current entry is set
    func play(
        entry: Entry,
        from: CMTime? = nil,
        to: CMTime? = nil,
        onStartHandler: (() -> Void)? = nil,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Speech Player Engine: Play (using Entry) =====")
        
        if entry.entrySegments.count == 0 {
            self.notifications.executeError(
                text: "Entry is empty.",
                handler: onFinishHandler
            )
            return
        }
        
        if self.pausedPlayingEntry {
            print("\tEntry was paused. Resume playback")
            // Play Sound
            if !self.speechRecognition.isListeningForSpeech &&
                !self.selectionCursor.hasSelection &&
                !self.entryManager.isRunningEntry &&
                !self.entryManager.isWalkingEntry &&
                !self.entryListManager.isRunningEntryList
            {
                // should not play if we have a selection
                soundEngine.play()
            }
            
            if onStartHandler != nil {
                self.onStartHandler = onStartHandler
            }
            
            self.pausedPlayingEntry = false
            self.isPlayingExternalSegments = false
            
            if self.speechRecognition.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                self.speechRecognition.pauseListeningForVoiceCommands() {
                    self.player.play()
                }
            } else if self.speechRecognition.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                self.speechRecognition.pauseListeningForSpeech(preventListeningForCommands: true) {
                    self.player.play()
                }
            } else {
                self.player.play()
            }
            
            return
        }
        
        print("\tInitiate new playback...")
        let playHandler = {
            // Play Sound
            if !self.speechRecognition.isListeningForSpeech &&
                !self.selectionCursor.hasSelection &&
                !self.entryManager.isRunningEntry &&
                !self.entryManager.isWalkingEntry &&
                !self.entryListManager.isRunningEntryList &&
                !self.entryListManager.isWalkingEntryList
            {
                // should not play if we have a selection
                soundEngine.play()
            }
            
            self.pausedPlayingEntry = false
            self.isPlayingExternalSegments = false
            
            if onStartHandler != nil {
                self.onStartHandler = onStartHandler
            }
            
            if onFinishHandler != nil {
                self.onFinishHandler = onFinishHandler
            }
            
            // Set Start and End Times
            self.startPlaybackAt = from != nil ? from : entry.startTime
            self.stopPlaybackAt = to != nil ? to : entry.endTime
            self.playbackSegments = Utils.duplicateSegments(segments: entry.entrySegments)

            // Run Player
            let player = self.runPlayer(
                entry: entry,
                startTime: self.startPlaybackAt!,
                volume: Utils.playbackVolume
            )
            
            // Handle Feedback
            if !self.selectionCursor.isLoopingSelection {
                self.notifications.executeFeedback(
                    visualMessage: "Play",
                    withHaptics: true
                )
            }

            if let player = player {
                if let boundaryObserverToken = self.boundaryObserverToken {
                    self.player.removeTimeObserver(boundaryObserverToken)
                    self.boundaryObserverToken = nil
                }
                
                if let completionObserverToken = self.completionObserverToken {
                    self.player.removeTimeObserver(completionObserverToken)
                    self.completionObserverToken = nil
                }
                
                if let timerObserverToken = self.timerObserverToken {
                    self.player.removeTimeObserver(timerObserverToken)
                    self.timerObserverToken = nil
                }
                
                self.player = player
            }
        }
        
        if self.speechRecognition.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            print("\tListening for commands without headphones. Stop listening while we play speech...")
            self.speechRecognition.pauseListeningForVoiceCommands() {
                playHandler()
            }
        } else if self.speechRecognition.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
            print("\tListening for speech without headphones. Stop listening while we play speech...")
            self.speechRecognition.pauseListeningForSpeech(preventListeningForCommands: true) {
                playHandler()
            }
        } else {
            playHandler()
        }
        
        checkRep()
    }
    
    func play(
        segments: [EntrySegment],
        onStartHandler: (() -> Void)? = nil,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Speech Player Engine: Play (using segments) =====")

        let cleansedSegments = Utils.cleanseSegments(
            segments: segments
        )

        let tempComposition = AVMutableComposition()
        tempComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
        do {
            try tempComposition.tracks[0].validateSegments(cleansedSegments)
            tempComposition.tracks[0].segments = cleansedSegments
        } catch {
            print("===== There was a problem creating temporary mutable composition to preview clipboard =====")
        }
        
        print("\tInitiate new playback...")
        let playHandler = {
            // Play Sound
            if !self.speechRecognition.isListeningForSpeech &&
                !self.selectionCursor.hasSelection &&
                !self.entryManager.isRunningEntry &&
                !self.entryManager.isWalkingEntry &&
                !self.entryListManager.isRunningEntryList &&
                !self.entryListManager.isWalkingEntryList
            {
                // should not play if we have a selection
                soundEngine.play()
            }
            
            self.pausedPlayingEntry = false
            self.isPlayingExternalSegments = true
            
            if onStartHandler != nil {
                self.onStartHandler = onStartHandler
            }
            
            if onFinishHandler != nil {
                self.onFinishHandler = onFinishHandler
            }
            
            // Set Start and End Times
            self.startPlaybackAt = CMTime.zero
            self.stopPlaybackAt = tempComposition.duration
            self.playbackSegments = Utils.duplicateSegments(segments: segments)

            // Run Player
            let player = self.runPlayer(
                composition: tempComposition,
                startTime: self.startPlaybackAt!,
                volume: Utils.playbackVolume
            )
            
            // Handle Feedback
            if !self.entryManager.isWalkingEntry && !self.entryManager.isRunningEntry {
                self.notifications.executeFeedback(
                    visualMessage: "Play",
                    withHaptics: true
                )
            }

            if let player = player {
                if let boundaryObserverToken = self.boundaryObserverToken {
                    self.player.removeTimeObserver(boundaryObserverToken)
                    self.boundaryObserverToken = nil
                }
                
                if let completionObserverToken = self.completionObserverToken {
                    self.player.removeTimeObserver(completionObserverToken)
                    self.completionObserverToken = nil
                }
                
                if let timerObserverToken = self.timerObserverToken {
                    self.player.removeTimeObserver(timerObserverToken)
                    self.timerObserverToken = nil
                }
                
                self.player = player
            }
        }
        
        if self.speechRecognition.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            self.speechRecognition.pauseListeningForVoiceCommands() {
                playHandler()
            }
        } else if self.speechRecognition.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
            self.speechRecognition.pauseListeningForSpeech() {
                playHandler()
            }
        } else {
            playHandler()
        }
        
        checkRep()
    }
    
    func stop(withFeedback: Bool = true, handler: (() -> Void)? = nil) {
        print("===== Speech Player Engine: Stop =====")
        player.pause()
        player.seek(to: CMTime.zero)
        player.replaceCurrentItem(with: nil)
        
        self.playerLoopTimer?.invalidate()

        self.startPlaybackAt = nil
        self.stopPlaybackAt = nil
        self.playbackSegments = nil
        self.pausedPlayingEntry = false
        self.isPlayingExternalSegments = false
        
        if soundEngine.isProcessing && (!self.selectionCursor.hasSelection || self.entryManager.isWalkingEntry && self.entryManager.isRunningEntry) {
            soundEngine.stopProcessing()
        }
        
        // Handle Feedback
        if !self.entryManager.isWalkingEntry && !self.entryManager.isRunningEntry && !self.selectionCursor.hasSelection && withFeedback {
            self.notifications.executeFeedback(
                visualMessage: "Stop Playback",
                withHaptics: true
            )
        }
        
        var userInfo: [String : () -> Void] = [:]
        if let handler = handler {
            userInfo["handler"] = handler
        }
        NotificationCenter.default.post(
            name: SpeechPlayerEngine.onStoppedPlaying,
            object: nil,
            userInfo: userInfo
        )
        
        checkRep()
    }
    
    func skip(to time: CMTime, handler: (() -> Void)? = nil) {
        print("===== Speech Player Engine: Skip =====")
        print("\tSkiping to: ", time.seconds)
        let currentSegment = self.getCurrentSegment()
        if let _ = currentSegment, self.isPlayingEntry {
            self.player.seek(
                to: time,
                toleranceBefore: CMTime.zero,
                toleranceAfter: CMTime.zero
            )
            
            // Handle Feedback
            self.notifications.executeFeedback(
                visualMessage: "Skip",
                withHaptics: true
            )
        } else {
            if self.playbackSegments == nil {
                // havent recorded anything
                self.notifications.executeError(
                    text: "Entry not playing.",
                    handler: handler
                )
            }
        }
        
        checkRep()
    }
    
    func pause(withFeedback: Bool = true, handler: (() -> Void)? = nil) {
        print("===== Speech Player Engine: Pause =====")
        
        player.pause()
        self.pausedPlayingEntry = true
        
        // Present Feedback
        if withFeedback {
            self.notifications.executeFeedback(
                visualMessage: "Pause Playback",
                withHaptics: true
            )
        }
        
        if !self.speechRecognition.isListeningForSpeech && self.speechRecognition.pausedListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            self.speechRecognition.startListeningForVoiceCommands()
        } else if self.speechRecognition.isListeningForSpeech && (self.speechRecognition.pausedListeningForSpeech || self.speechRecognition.pausedListeningForCommands) && !AVAudioSession.isHeadphonesConnected {
            self.speechRecognition.startListeningForSpeech()
        }

        if self.playerLoopTimer != nil {
            self.playerLoopTimer?.invalidate()
        }
        
        if soundEngine.isProcessing {
            soundEngine.stopProcessing()
        }
        
        handler?()
        
        checkRep()
    }
    
    // MARK: - Setters
    
    func setPlaybackRate(to rate: Float) {
        print("===== Speech Player Engine: Set Playback Rate =====")
        print("\tSetting rate to: ", rate)

        if self.isPlayingEntry {
            self.player.rate = rate
        }
        
        self.state.setPlaybackRate(to: rate)
        
        checkRep()
    }

    // sets relative to wpm of current entry
    func setPlaybackRate(wpm: Float) {
        print("===== Speech Player Engine: Set Playback Rate =====")
        print("Setting rate to \(wpm)wpm")
        guard let entry = self.entryManager.currentEntry else {
            print("\t[Error] There was a problem setting playback rate. Unable to locate entry.")
            return
        }
        
        let rate = wpm / Float(entry.avgSpeakingRate).rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)

        if self.isPlayingEntry {
            player.rate = rate
        }
        
        self.state.setPlaybackRate(to: self.playbackRate)
        
        checkRep()
    }
    
    func setPlayerRate(rate: Float) -> Bool {
        print("===== Speech Player Engine: Set Player Rate =====")
        print("Setting rate to: ", rate)

        // Player must be playing to set rate
        // Reference: https://stackoverflow.com/questions/36378642/avplayeritems-canplayslowforward-property-never-called
        if !player.isPlaying {
            return false
        }
        
        // Set Rate
        if rate > 1.0 {
            // Play fast forward
            print("\tWill play entry in fast forward at rate: \(rate)")
            self.player.rate = rate
        } else if rate > 0.0 && rate < 1.0 {
            // Play slow forward
            print("\tWill play entry in slow forward at rate: \(rate)")
            self.player.rate = rate
        } else if rate < 0.0 && rate > -1.0 {
            // Play slow reverse
            print("\tWill play entry in slow reverse at rate: \(rate)")
            self.player.rate = rate
        } else if rate < -1.0 {
            // Play fast reverse
            print("\tWill play entry in fast reverse at rate: \(rate)")
            self.player.rate = rate
        } else {
            // Play as normal if rate = 1.0
            // Stop if rate = 0.0
            print("\tWill play entry at rate: \(rate)")
            self.player.rate = rate
        }
        
        checkRep()
        
        return true
    }
    
    func setPlayerVolume(player: AVPlayer, volume: Float) {
        print("===== Speech Player Engine: Set Player Volume =====")
        print("\tSetting volume to: ", volume)
        // print("===== Set Player Volume =====")
        
        // Set volume
        // print("\tWill play entry at volume: \(volume)")
        player.volume = volume
        
        checkRep()
    }
    
    // MARK: - Getters
    
    func getCurrentTime() -> CMTime {
        return self.player.currentTime()
    }
    
    func getCurrentSegment() -> EntrySegment? {
        let currentTime = self.player.currentTime()
        return Utils.getSegment(
            forTrackTime: currentTime,
            segments: self.playbackSegments,
            entry: self.entryManager.currentEntry,
            isPlayingEntry: self.isPlayingEntry
        )
    }
    
    // MARK: - Voice Commands
    
    func increasePlaybackRate(
        handler: (() -> Void)? = nil
    ) {
        print("===== Speech Player Engine: Increase Playback Rate =====")
        print("\tTriggered by voice command.")
        let currentPlaybackRate = self.playbackRate
        let newPlaybackRate = min(currentPlaybackRate + Utils.DISCRETE_PLAYBACK_DELTA, Utils.MAXIMUM_PLAYBACK_RATE).rounded(toPlaces: 2)
        if currentPlaybackRate < Utils.MAXIMUM_PLAYBACK_RATE {
            // Play Sound
            soundEngine.voiceCommandAccept()
            self.setPlaybackRate(to: newPlaybackRate)

            handler?()
        } else {
            self.notifications.executeError(
                text: "Playback Rate already at fastest.",
                voiceCommand: true,
                handler: handler
            )
        }
    }
    
    func decreasePlaybackRate(
        handler: (() -> Void)? = nil
    ) {
        print("===== Speech Player Engine: Decrease Playback Rate =====")
        print("\tTriggered by voice command.")
        let currentPlaybackRate = self.playbackRate
        let newPlaybackRate = max(currentPlaybackRate - Utils.DISCRETE_PLAYBACK_DELTA, Utils.MINIMUM_PLAYBACK_RATE).rounded(toPlaces: 2)
        if currentPlaybackRate > Utils.MINIMUM_PLAYBACK_RATE {
            // Play Sound
            soundEngine.voiceCommandAccept()
            self.setPlaybackRate(to: newPlaybackRate)

            handler?()
        } else {
            self.notifications.executeError(
                text: "Playback Rate already at slowest.",
                voiceCommand: true,
                handler: handler
            )
        }
    }
    
    // MARK: - Helpers
    
    func runPlayer(
        entry: Entry,
        startTime: CMTime,
        volume: Float
    ) -> AVPlayer? {
        print("===== Run Player: Entry =====")
        return self.handleRunPlayer(
            entry: entry,
            startTime: startTime,
            volume: volume
        )
    }
    
    func runPlayer(
        composition: AVMutableComposition,
        startTime: CMTime,
        volume: Float
    ) -> AVPlayer? {
        print("===== Run Player: Composition =====")
        return self.handleRunPlayer(
            composition: composition,
            startTime: startTime,
            volume: volume
        )
    }
    
    func handleRunPlayer(
        composition: AVMutableComposition? = nil,
        entry: Entry? = nil,
        startTime: CMTime,
        volume: Float
    ) -> AVPlayer? {
        print("===== Speech Player Engine: Handle Run Player =====")
        if let composition = composition, self.player.currentItem == nil, let snapshot = composition.copy() as? AVAsset {
            print("\tInitiating AVPlayer with Composition...")
            let assetKeys = [
                   "playable",
                   "duration",
                   "hasProtectedContent"
               ]
            let playerItem = AVPlayerItem(asset: snapshot, automaticallyLoadedAssetKeys: assetKeys)

            playerItem.addObserver(
                self,
                forKeyPath: #keyPath(AVPlayerItem.status),
                options: [.old, .new],
                context: nil
            )
            
            let player = AVPlayer(playerItem: playerItem)

            // Set Volume
            self.setPlayerVolume(player: player, volume: volume)
            
            return player
        } else if let entry = entry, self.player.currentItem == nil, let snapshot = entry.copy() as? AVAsset {
            print("\tInitiating AVPlayer with Entry...")
            let assetKeys = [
                   "playable",
                   "duration",
                   "hasProtectedContent"
               ]
            let playerItem = AVPlayerItem(asset: snapshot, automaticallyLoadedAssetKeys: assetKeys)

            playerItem.addObserver(
                self,
                forKeyPath: #keyPath(AVPlayerItem.status),
                options: [.old, .new],
                context: nil
            )

            let player = AVPlayer(playerItem: playerItem)

            // Set Volume
            self.setPlayerVolume(player: player, volume: volume)

            return player
        } else if self.player.status != .readyToPlay {
            // just wait for item to be ready
            print("\tWaiting for AVPlayerItem to be ready...\n")
        } else if self.player.currentItem != nil {
            print("\tImmediately Playing Item\n")
            let _ = self.handleStartPlaying()
            
            return self.player
        }
        return nil
    }
    
    func handleStartPlaying() -> EntrySegment? {
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 1, preferredTimescale: timeScale)

        print("\tSet Playback Second Handler...")
        self.timerObserverToken = self.player.addPeriodicTimeObserver(forInterval: time, queue: .main) {time in
            self.handlePeriodicTimeObserver()
        }
        
        if let playbackSegments = self.playbackSegments {
            print("\tSet Playback Segment Boundary Handler...")
            // if we have a selection, animating through each word removes it
            var boundaryTimes = [NSValue]()
            for segment in playbackSegments {
                boundaryTimes.append(NSValue(time: segment.timeMapping.target.start))
            }

            self.boundaryObserverToken = self.player.addBoundaryTimeObserver(forTimes: boundaryTimes, queue: .main) {
                self.handleBoundaryTimeObserver()
            }
        }
        
        print("\tSet Playback Finish Handler...")
        if let stopPlaybackAt = self.stopPlaybackAt {
            self.completionObserverToken = self.player.addBoundaryTimeObserver(forTimes: [NSValue(time: stopPlaybackAt)], queue: .main) {
                self.handleCompletionObserver()
            }
        }
        
        let firstPlayableSegment = Utils.getSegment(
            forTrackTime: CMTime.zero,
            segments: self.playbackSegments,
            entry: self.entryManager.currentEntry,
            isWord: true
        )
        
        print("\tPlaying from: \(self.startPlaybackAt!.seconds)")
        self.player.seek(to: self.startPlaybackAt!)
        self.player.play()
        if let firstPlayableSegment = firstPlayableSegment,
           let playbackSegments = self.playbackSegments,
           firstPlayableSegment.getIndex() > playbackSegments[0].getIndex()
        {
            self.handleBoundaryTimeObserver(start: true)
        }
        
        print("\tPlaying asset with duration: \(self.player.currentItem!.duration.seconds)s and \(self.player.currentItem!.asset.tracks[0].segments.count) segments.")
        
        let rate = firstPlayableSegment?.getRate() ?? self.playbackRate
        let rateWasSet = self.setPlayerRate(rate: rate)
        if rateWasSet {
            print("\tPlayer rate was successfully set: ", rate)
        } else {
            print("\t[Error] There was a problem setting player rate. Player had not been started yet.")
        }
        
        print("\tExecute On Start Handler...")
        self.onStartHandler?()
        self.onStartHandler = nil
        
        return firstPlayableSegment
    }
    
    func handlePeriodicTimeObserver() {
        print("===== Speech Player Engine: Handle Periodic Time Observer =====")
        // Broadcast Second Elapsing
        NotificationCenter.default.post(
            name: SpeechPlayerEngine.onSecondElapsed,
            object: nil,
            userInfo: ["seconds": self.player.currentTime().seconds]
        )
    }
    
    func handleBoundaryTimeObserver(start: Bool = false) {
        print("===== Speech Player Engine: Handle Boundary Time Observer =====")
        guard let playbackSegments = self.playbackSegments else {
            print("\t[Error] Playback Segments are not set. Abort Method.")
            return
        }
        let seekNextSegmentHandler: (_ segment: EntrySegment, _ conditional: Bool) -> Void = { segment, conditional in
            print("\tSeek next segment...")
            let nextSegmentIndex = Utils.getSegmentIndex(
                segment: segment,
                segments: playbackSegments,
                type: .next,
                isWord: true
            )
            
            if conditional && (
                (self.state.withSkipPunctuation && segment.isPunctuation()) ||
                    (self.state.withOmitSilences && segment.isSilence() && segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD) ||
                segment.isVoiceCommandWord() ||
                segment.isDeleted()
            ), let nextSegmentIndex = nextSegmentIndex {
                print("\tSkip to next segment...")
                let nextSegment = playbackSegments[nextSegmentIndex]
                print("Next word '\(nextSegment.getText())' at \(nextSegment.timeMapping.target.start.seconds) seconds...")
                // skip to next segment
                self.previousBoundarySegment = segment
                self.player.seek(
                    to: nextSegment.timeMapping.target.start,
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )
                
                print("\tTurn down volume to not hear stutters from voice command word...")
                // Turn down volume to not hear stutters from voice command word
                self.setPlayerVolume(player: self.player, volume: 0)
            } else {
                print("\tDon't skip...")
                self.previousBoundarySegment = segment
                
                // Make sure volume is correctly set
                if self.player.volume != Utils.playbackVolume {
                    self.setPlayerVolume(player: self.player, volume: Utils.playbackVolume)
                }
            }
            
            // Make sure rate is correctly set
            if self.player.rate != segment.getRate() {
                let _ = self.setPlayerRate(rate: segment.getRate() * self.playbackRate)
            }
            
            var userInfo: [String: EntrySegment] = ["previous": self.previousBoundarySegment!]
            if let nextSegmentIndex = nextSegmentIndex {
                userInfo["next"] = playbackSegments[nextSegmentIndex]
            }
            // Broadcast Boundary Crossing
            NotificationCenter.default.post(
                name: SpeechPlayerEngine.onBoundaryCrossed,
                object: nil,
                userInfo: userInfo
            )
        }
        
        let seekEndPlaybackHandler: (_ segment: EntrySegment, _ conditional: Bool) -> Void = { segment, conditional in
            print("\tSeek end playback...")
            if conditional && (
                (self.state.withSkipPunctuation && segment.isPunctuation()) ||
                    (self.state.withOmitSilences && segment.isSilence() && segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD) ||
                segment.isVoiceCommandWord() ||
                segment.isDeleted()
            ) {
                print("\tSkip to end asset...")
                // skip to end asset
                self.previousBoundarySegment = nil
                self.player.seek(
                    to: CMTimeMake(
                        value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (self.player.currentItem!.duration.seconds - Utils.PLAYER_END_PLAYBACK_BUFFER)),
                        timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                    ),
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )

                print("\tTurn down volume to not hear stutters from voice command word...")
                // Turn down volume to not hear stutters from voice command word
                self.setPlayerVolume(player: self.player, volume: 0)
            } else {
                print("\tDon't skip...")
                self.previousBoundarySegment = segment
                
                // Make sure volume is correctly set
                if self.player.volume != Utils.playbackVolume {
                    self.setPlayerVolume(player: self.player, volume: Utils.playbackVolume)
                }
            }
            
            // Make sure rate is correctly set
            if self.player.rate != segment.getRate() {
                let _ = self.setPlayerRate(rate: segment.getRate() * self.playbackRate)
            }
            
            var userInfo: [String: EntrySegment] = [:]
            if let previousBoundarySegment = self.previousBoundarySegment {
                userInfo["previous"] = previousBoundarySegment
            }
            // Broadcast Boundary Crossing
            NotificationCenter.default.post(
                name: SpeechPlayerEngine.onBoundaryCrossed,
                object: nil,
                userInfo: userInfo
            )
        }
        
        let currentSegment = self.getCurrentSegment()
        if  let entry = self.entryManager.currentEntry,
            let segment = Utils.getSegment(
                forTrackTime: self.startPlaybackAt!,
                segments: self.playbackSegments,
                entry: entry,
                isPlayingEntry: self.isPlayingEntry,
                isWord: self.state.withOmitSilences
            ),
            start
        {
            print("\tStarting Segment: '\(segment.getText())' at \(segment.timeMapping.target.start.seconds)")
            self.previousBoundarySegment = segment
            self.player.seek(
                to: segment.timeMapping.target.start,
                toleranceBefore: CMTime.zero,
                toleranceAfter: CMTime.zero
            )
        } else if let segment = currentSegment, segment == self.playbackSegments!.last! || (
            (
                (self.state.withSkipPunctuation && segment.isPunctuation()) ||
                (self.state.withOmitSilences && segment.isSilence() && segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD) ||
                segment.isVoiceCommandWord() ||
                segment.isDeleted()
            ) && Utils.getSegmentIndex(
                segment: segment,
                segments: self.playbackSegments!,
                type: .next,
                isWord: true
            ) == nil
        ) {
            // last segment of entry
            seekEndPlaybackHandler(segment, true)
        } else if let segment = currentSegment {
            // We do an equality check with the previous boundary to make sure we are strictly moving
            // forward and not stuck in loop of playing an older segment
            seekNextSegmentHandler(segment, self.previousBoundarySegment != nil && segment != previousBoundarySegment)
        } else {
            print("\tStop playback...")
            // Stop
            self.previousBoundarySegment = nil
            self.player.seek(
                to: CMTimeMake(
                    value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (self.player.currentItem!.duration.seconds - Utils.PLAYER_END_PLAYBACK_BUFFER)),
                    timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                ),
                toleranceBefore: CMTime.zero,
                toleranceAfter: CMTime.zero
            )

            // Turn down volume to not hear stutters from voice command word
            self.setPlayerVolume(player: self.player, volume: 0)
            
            var userInfo: [String: EntrySegment] = [:]
            if let previousBoundarySegment = self.previousBoundarySegment {
                userInfo["previous"] = previousBoundarySegment
            }
            // Broadcast Boundary Crossing
            NotificationCenter.default.post(
                name: SpeechPlayerEngine.onBoundaryCrossed,
                object: nil,
                userInfo: userInfo
            )
        }
    }
    
    func handleCompletionObserver() {
        print("===== Speech Player Engine: Handle Completion Observer =====")

        if let stopPlaybackAt = self.stopPlaybackAt, let startPlaybackAt = self.startPlaybackAt, self.selectionCursor.hasSelection && self.selectionCursor.isLoopingSelection && !self.entryManager.isWalkingEntry && !self.entryManager.isRunningEntry {
            // Stop Playing
            self.stop(withFeedback: false)
            
            let delayBetweenLooping = CMTimeSubtract(stopPlaybackAt, startPlaybackAt).seconds + 1
            self.playerLoopTimer = Timer.scheduledTimer(withTimeInterval: delayBetweenLooping, repeats: false) { timer in
                self.selectionCursor.playSelection(loop: true)
            }
        } else {
            print("\tStop entry.")
            // Stop Playing
            self.stop()
            
            if soundEngine.isProcessing {
                soundEngine.stopProcessing()
            }
            
            if self.state.appActivated && self.speechRecognition.pausedListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                print("\tStart listening for commands again...")
                // when headphones are off we don't listen for voice commands while echoing
                // but on completion we turn it back on
                self.speechRecognition.startListeningForVoiceCommands() {
                    NotificationCenter.default.post(
                        name: SpeechSynthesisEngine.onRequestToUpdateView,
                        object: nil,
                        userInfo: [:]
                    )
                }
            } else if let entry = self.entryManager.currentEntry, self.state.appActivated && self.speechRecognition.pausedListeningForSpeech && !AVAudioSession.isHeadphonesConnected && !self.entryManager.isRunningEntry && !self.entryManager.isWalkingEntry {
                print("\tStart listening for speech again.")
                // when headphones are off we don't listen for speech while echoing
                // but on completion we turn it back on
                entry.speechRecognition.startListeningForSpeech(
                    onStartHandler: {
                        NotificationCenter.default.post(
                            name: SpeechSynthesisEngine.onRequestToUpdateView,
                            object: nil,
                            userInfo: [:]
                        )
                    }
                )
            }
            
            self.onFinishHandler?()

            // Broadcast On Stop Playing
            NotificationCenter.default.post(
                name: SpeechPlayerEngine.onStoppedPlaying,
                object: nil,
                userInfo: [:]
            )
        }

        if let boundaryObserverToken = self.boundaryObserverToken {
            self.player.removeTimeObserver(boundaryObserverToken)
            self.boundaryObserverToken = nil
            // print("===== Cleared Player Boundary Token =====")
        }
        
        if let completionObserverToken = self.completionObserverToken {
            self.player.removeTimeObserver(completionObserverToken)
            self.completionObserverToken = nil
            // print("===== Cleared Player Completion Token =====")
        }
        
        if let timerObserverToken = self.timerObserverToken {
            self.player.removeTimeObserver(timerObserverToken)
            self.timerObserverToken = nil
            // print("===== Cleared Player Timer Token =====")
        }
        
        checkRep()
    }
    
    // MARK: - Key-Value Observer
    
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ){
        print("===== Speech Player Engine: Observe Value =====")
        print("Key Path: ", keyPath ?? "nil")
//        guard self.entryBuffer.count == 0 else {
//            print("===== [Error] There was a problem inserting passage. Buffer was not empty =====")
//        }

        if keyPath == #keyPath(AVPlayerItem.status) {
            let status: AVPlayerItem.Status
            
            // Get the status change from the change dictionary
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }
            
            // Switch over the status
            switch status {
            case .readyToPlay:
                print("===== Playing Entry =====")
                let firstPlayableSegment = self.handleStartPlaying()
                
                var userInfo: [String: EntrySegment] = [:]
                if let firstSegment = firstPlayableSegment {
                    userInfo["next"] = firstSegment
                }
                // Broadcast Started Playing
                NotificationCenter.default.post(
                    name: SpeechPlayerEngine.onStartedPlaying,
                    object: nil,
                    userInfo: userInfo
                )
                
                checkRep()
            case .failed:
                print("\t[Error] There was a problem making track ready to play")
                if let error = player.currentItem!.error {
                    print("\tMessage: \(error.localizedDescription)")
                }

                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                // wait for sound
//                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
//                    fatalError()
//                }
                break
            case .unknown:
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                // wait for sound
//                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
//                    fatalError("\t[Error] Player not ready")
//                }
                break
            @unknown default:
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                // wait for sound
//                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
//                    fatalError("\t[Error] Unknown player status received")
//                }
            }
        }
    }
}
