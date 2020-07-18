//
//  Expression.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/17/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Speech
import AVFoundation
import NaturalLanguage

let DIFFERENCE = 0.01
let DEFAULT_SEGMENT_DURATION: Double = 1000
let TRANSCRIPTION_LATENCY_DURATION: Double = 0.3
let SOUND_INTENSITY_SIG_FIG_COUNT = 4
let DEFAULT_FIG_COUNT = 2

class Expression: AVMutableComposition {
    // MARK: - Static Properties
    static let defaultSegmentTimescale = Double(10000)

    // MARK: - Composition Properties
    private(set) var filename: String
    // Change recording format:
    // Reference 1: https://stackoverflow.com/questions/4279311/how-to-record-voice-in-m4a-format
    // Reference 2: https://developer.apple.com/forums/thread/27411
    private var _fileType: AVFileType = .caf // Used when instantiating ExpressionSegment class instances
    public var fileType: String {
        get {
            if _fileType == .caf {
                return ".caf"
            } else if _fileType == .m4a {
                return ".m4a"
            } else {
                fatalError("===== [Error] There was a problem returning the specified file type =====")
            }
        }
    }
    /// Supplies information about the speaker.
    private(set) var speaker: Speaker
    private(set) var expressionSegments = [ExpressionSegment]()
    private(set) var startTime: CMTime = CMTime.zero // When we remove or add we change this
    private(set) var endTime: CMTime = CMTime.zero // When we remove or add we change this
    public override var duration: CMTime {
        return CMTimeSubtract(self.endTime, self.startTime)
    }
    public var numSentences: Int {
        return self.expressionSegments.last!.getSentence().number + 1
    }
    /// The language of the segment
    public var language: NLLanguage? {
        if expressionSegments.count == 0 {
            return nil
        }

        if let firstSegment = expressionSegments.first, let language = NLLanguageRecognizer.dominantLanguage(for: firstSegment.getText()) {
            return language
        }
        
        return nil
    }
    /// The average number of words spoken per minute.
    public var avgSpeakingRate: Double {
        var speakingRate: Double = 0
        // Can be used to vary speed relative to WPM
        let segments = expressionSegments
        
        for segment in segments {
            speakingRate += segment.getSpeakingRate()
        }
        
        speakingRate /= Double(segments.count)

        return speakingRate
    }
    private(set) var withTemporalSuggestions: Bool
    private(set) var withPunctuationSuggestions: Bool
    private(set) var withFormattingSuggestions: Bool
    private(set) var withTextStrictlyAsWords: Bool
    weak private(set) var vc: ViewController?
    private(set) var onListenUpdate: (() -> Void)?
    private(set) var onExpressionComplete: (() -> Void)?
    private var observerContext = [String: (() -> Void)]()
    
    // MARK: - Recording Properties
    let recordBus = 0
    private(set) var authorizedToListen = false
    var activeTrack: Int = 0
    var numTracks: Int {
        return self.tracks.count
    }
    var recordingSession = AVAudioSession.sharedInstance()
    private(set) var isListening = false
    public var recordStartDate: Date?
    private var accumulatedDuration = TimeInterval(0)
    public var recordFile: AVAudioFile?
    private var soundIntensityStream = [SoundIntensityDatum]()
    private lazy var pitchEngine: PitchEngine = { [weak self] in
        let config = Config(
            bufferSize: 1024,
            estimationStrategy: .yin
        )
        let pitchEngine = PitchEngine(config: config, delegate: self)
        pitchEngine.levelThreshold = minDb
        return pitchEngine
    }()
    private var pitchStream = [PitchDatum]()
    
    // MARK: - Speech Recognition Properties
    private(set) var useOnDeviceRecognition: Bool
    private var audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // MARK: - Speech Synthesis Properties
    private let speechSynthesizer = AVSpeechSynthesizer()
    public var isPlayingEcho: Bool {
        return speechSynthesizer.isSpeaking
    }
    public var echoIsPaused: Bool {
        return speechSynthesizer.isPaused
    }
    private(set) var onEchoFinish: (() -> Void)?
    private(set) var tempOnEchoFinish: (() -> Void)?
    private(set) var onEchoUpdate: ((_ range: NSRange) -> Void)?
    
    // MARK: - Audio Playback Properties
    private(set) var player = AVPlayer()
    private let playbackBus = 1
    public let minDb: Float
    private(set) var playbackRate: Float = 1
    private(set) var playbackVolume = Float(1.0)
    private var boundaryObserverToken: Any?
    private var completionObserverToken: Any?
    private var timerObserverToken: Any?
    private var previousBoundarySegment: ExpressionSegment?
    public var isPlayingExpression: Bool {
        return player.isPlaying
    }
    private(set) var skipPunctuation = true
    private(set) var skipSilence = true
    private var soundIntensityHandler: ((_ intensity: Double?) -> Void)?
    private var onListeningStartHandler: (() -> Void)?
    private var delayDate: Date?
    private var delayDuration = 0
    private var startPlaybackAt: CMTime?
    private var stopPlaybackAt: CMTime?
    
    // MARK: - Initializer

    init(
        vc: ViewController? = nil,
        filename: String,
        fileType: AVFileType? = nil,
        speaker: Speaker,
        minDb: Float,
        segments: [ExpressionSegment]? = nil,
        withOnDeviceRecognition: Bool,
        withTemporalSuggestions: Bool = false,
        withPunctuationSuggestions: Bool = false,
        withFormattingSuggestions: Bool = false,
        withTextStrictlyAsWords: Bool = false,
        onListenUpdate: (() -> Void)? = nil,
        onEchoFinish: (() -> Void)? = nil,
        onEchoUpdate: ((_ range: NSRange) -> Void)? = nil,
        onExpressionComplete: (() -> Void)? = nil
    ) {
        self.filename = filename
        self.speaker = speaker
        self.minDb = minDb
        self.useOnDeviceRecognition = withOnDeviceRecognition
        self.onListenUpdate = onListenUpdate
        self.onEchoFinish = onEchoFinish
        self.onEchoUpdate = onEchoUpdate
        self.onExpressionComplete = onExpressionComplete
        self.withPunctuationSuggestions = withPunctuationSuggestions
        self.withFormattingSuggestions = withFormattingSuggestions
        self.withTextStrictlyAsWords = withTextStrictlyAsWords
        
        if let vc = vc {
            self.vc = vc
        }
        
        if withPunctuationSuggestions && withTemporalSuggestions {
            // Inform that only one view mode may be active in any given moment
            self.withTemporalSuggestions = false
            let alertController = UIAlertController(title: "Conflicting View Modes", message: "You've attemped to activate both punctuation and temporal suggestions. Only one can be active at a time, so we've activated punctuation suggestions only.", preferredStyle: .alert)
            let closeAction = UIAlertAction(title: "Close", style: .cancel, handler: nil)
            alertController.addAction(closeAction)

            DispatchQueue.main.async {
                vc?.present(alertController, animated: true, completion: nil)
            }
        } else {
            // We set punctuation suggestions above
            // 1) if punctuation suggestions and temporal suggestions are true, we handle it in if-statement
            // 2) if it's false and temporal suggestions is true, we account for it here
            // 3) if both are false, we acount for it above and here
            self.withTemporalSuggestions = withTemporalSuggestions
        }

        super.init()

        // Ask for permissions
        self.requestPermissions()

        // Add track
        self.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: Int32(kCMPersistentTrackID_Invalid)
        )
        
        if let fileType = fileType {
            self._fileType = fileType
        } else {
            // Configure Audio Write File
            self.configureAudioWriteFile()
        }
        
        // Assign delegates
        speechSynthesizer.delegate = self
        
        // Configure Observers
        self.configureNotificationObservers()
        
        // A user might pass in segments when expression instantiated
        if let segments = segments {
            self.startTime = segments.first!.timeMapping.source.start
            self.endTime = segments.last!.timeMapping.source.end
            self.setSegments(segments: segments, replaceExpressionDetails: true)
        }
        
        // Check Rep Invariant
        checkRep()
    }
    
    // MARK: - Configuration Methods
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization {authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("===== Speech recognition permission granted =====")
                case .denied:
                    print("===== Speech recognition permission denied =====")
                case .restricted:
                    print("===== Speech recognition not available on device =====")
                case .notDetermined:
                    print("===== Speech recognition not determined =====")
                @unknown default:
                    print("===== Unknown permission state received: \(authStatus) =====")
                }
            }
        }
        
        recordingSession.requestRecordPermission() {
            allowed in
            DispatchQueue.main.async {
                if allowed {
                    print("===== Permission to record audio granted =====")
                } else {
                    print("===== Permission to record audio denied =====")
                }
            }
        }
    }
    
    func configureAudioWriteFile() {
        print("===== Configure Expression Audio Write File =====")
        do {
            try recordFile = AVAudioFile(forWriting: Utils.getFileURL(of: "\(self.filename)\(self.fileType)"), settings: audioEngine.inputNode.inputFormat(forBus: recordBus).settings)
            authorizedToListen = true
        } catch {
            fatalError("\t[Error] There was a problem instantiating the record file")
        }
    }
    
    func configureNotificationObservers() {
        print("===== Configure Notification Observers =====")
        let notificationCenter = NotificationCenter.default
        
        notificationCenter.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc func handleAudioSessionRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
        }

        // Switch over the route change reason.
        switch reason {
        case .newDeviceAvailable: // New device found.
            print("===== New Audio Device Found =====")
            // Reset listening for wake word
            DispatchQueue.main.async {
                if self.isListening {
                    self.stop() {[weak self] in
                        self?.startListeningForSpeech(
                            soundIntensityHandler: self?.soundIntensityHandler,
                            onStartHandler: self?.onListeningStartHandler
                        )
                    }
                } else {
                    // Re-initiate Audio Engine to mend broken graph
                    self.audioEngine = AVAudioEngine()
                }
            }
        case .oldDeviceUnavailable: // Old device removed.
            print("===== Old Audio Device Removed =====")
            // Reset listening for wake word
            DispatchQueue.main.async {
                if self.isListening {
                    self.stop() {[weak self] in
                        self?.startListeningForSpeech(
                            soundIntensityHandler: self?.soundIntensityHandler,
                            onStartHandler: self?.onListeningStartHandler
                        )
                    }
                } else {
                    // Re-initiate Audio Engine to mend broken graph
                    self.audioEngine = AVAudioEngine()
                }
            }
        default: ()
        }
    }
    
    func checkRep() {
        var result = true
        // startTime must be in front of endTime
        result = result && self.endTime >= self.startTime
        // start of expression segments should be the same as startTime
        if let firstSegment = self.expressionSegments.first {
            result = result && firstSegment.timeMapping.source.start == self.startTime
        }
        // end of expression segments should be the same as endTime
        if let lastSegment = self.expressionSegments.last {
            result = result && lastSegment.timeMapping.source.end == self.endTime
        }
        
        // internal durations should be the same
        if let firstSegment = self.expressionSegments.first, let lastSegment = self.expressionSegments.last {
            result = result && CMTimeSubtract(self.endTime, self.startTime) == CMTimeSubtract(lastSegment.timeMapping.source.end, firstSegment.timeMapping.source.start)
        }
        
        // durations should be the same as underlying track segments
        if let firstSegment = self.tracks[self.activeTrack].segments!.first, let lastSegment = self.tracks[self.activeTrack].segments!.last {
            result = result && CMTimeSubtract(self.endTime, self.startTime) == CMTimeSubtract(lastSegment.timeMapping.source.end, firstSegment.timeMapping.source.start)
        }

        if !result {
            fatalError("===== [Error] Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Speech Listening Methods
    
    func startListeningForSpeech(soundIntensityHandler: ((_ intensity: Double?) -> Void)? = nil, onStartHandler: (() -> Void)? = nil) {
        print("===== Starting Listening for Speech =====")
        
        // Play Sound
        sounds.startListening()
        
        if !self.authorizedToListen {
            print("\t [Error] There was a problem while starting to listen for speech. Expression is not authorized to listen.")
            return
        }
        
        // Activate Pitch Recognition
        pitchEngine.start()
        
        if let soundIntensityHandler = soundIntensityHandler {
            self.soundIntensityHandler = soundIntensityHandler
        }
        
        if let onListeningStartHandler = onStartHandler {
            self.onListeningStartHandler = onListeningStartHandler
        }
        
        if recognitionTask != nil {
            recognitionTask?.finish()
            recognitionTask = nil
        }

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: recordBus)
        print("===== Sample Rates ===== \n\tSoftware Format: \(recordingFormat.sampleRate)\n\tHardware Format: \(AVAudioSession.sharedInstance().sampleRate)")
        
//        let recordSettings: [String : AnyObject] = [
//            AVSampleRateKey : NSNumber(value: Float(16000)),
//            AVFormatIDKey : NSNumber(value: Int32(kAudioFormatMPEG4AAC)),
//            AVNumberOfChannelsKey : NSNumber(value: 1),
//            AVEncoderAudioQualityKey : NSNumber(value: Int32(AVAudioQuality.low.rawValue))
//        ]
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request!.shouldReportPartialResults = true
        request!.requiresOnDeviceRecognition = false // Set to false by default, but conditionally changed below

        node.installTap(onBus: recordBus, bufferSize: 1024, format: recordingFormat) { [unowned self] (buffer, _) in
            self.request!.append(buffer)
            // We place this here so we start tracking recording from the first buffer chnk we receive
            DispatchQueue.main.async {
                if !self.isListening {
                    // A transcription can be in progress before call to startSpeechRecognition if
                    // Apple servers ended dictation session
                    // It cannot be if after a continguous clause was completed while on-device recognition
                    self.isListening = true
                    self.recordStartDate = Date()
                    onStartHandler?()
                }
            }

            DispatchQueue.main.async {
                let soundIntensity = Utils.computeNormalizedSoundIntensity(buffer: buffer, minDb: self.minDb)
                if let soundIntensity = soundIntensity {
                    let soundIntensityDatum = SoundIntensityDatum(date: Date(), intensity: soundIntensity)
                    self.soundIntensityStream.append(soundIntensityDatum)
                    soundIntensityHandler?(soundIntensity)
                }
            }
            
            do {
                try self.recordFile!.write(from: buffer)
            } catch {
                fatalError("\t[Error] There was a problem writing speech to file")
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            fatalError("\t[Error] There was a problem starting speech recognition")
        }
        
        do {
            // it’s generally preferable to defer this call until your app begins audio playback
            try recordingSession.setActive(true)
        } catch {
            fatalError("\t[Error] There was a problem activating audio session")
        }
        
        guard let myRecognizer = SFSpeechRecognizer() else {
            fatalError("\t[Error] Speech Recognizer is not supported for current locale")
        }
        
        if useOnDeviceRecognition && myRecognizer.supportsOnDeviceRecognition {
            print("\tUsing On-Device Recognition")
            request!.requiresOnDeviceRecognition = true
        }
        
        if !myRecognizer.isAvailable {
            fatalError("\t[Error] Speech Recognizer is not available")
        }
        
        // Check rep invariant
        checkRep()
        
        speechRecognizer?.defaultTaskHint = .dictation
        recognitionTask = speechRecognizer?.recognitionTask(with: request!, delegate: self)
    }
    
    func stopListeningForSpeech(pause: Bool = false, onStopHandler: (() -> Void)? = nil) {
        print("===== Stopping Listening for Speech =====")
        if isListening && !pause {
            isListening = false
        }
        
        // Play Sound
        sounds.stopListening()
        
        let node = audioEngine.inputNode
        node.removeTap(onBus: self.recordBus)

        if pause {
            audioEngine.pause()
        } else {
            audioEngine.stop()
            audioEngine.reset()
        }
        
        // When this is not in the main thread, the recognition task doesn't end correctly
        // which prevents us from receiving the final transcription.
        DispatchQueue.main.async {
            self.recognitionTask!.finish() // don't wrap in if statement because it is sometimes not .running
            self.request!.endAudio() // don't add a request = nil because it results in request not being there sometimes.
            self.pitchEngine.stop()
            onStopHandler?()
        }
    }
    
    func performTranscriptionUpdate(_ transcription: SFTranscription, finalTranscript: Bool = false) {
        // Find staged segments lower index
        var stagedSegmentsLowestIndex: Int = -1
        for (index, segment) in self.expressionSegments.enumerated() {
            if segment.timeMapping.source.duration.seconds == DEFAULT_SEGMENT_DURATION {
                stagedSegmentsLowestIndex = index
                break
            }
        }

        if finalTranscript {
            var segments = self.expressionSegments
            segments.removeSubrange(stagedSegmentsLowestIndex..<segments.count)
            // Don't ship to setSegments(segments: [ExpressionSegment])
            // It's not normalized yet
            self.expressionSegments = segments
        }
        
        for (index, segment) in transcription.segments.enumerated() {
            processTranscriptSegment(segment: segment, transcriptionIndex: index, stagedSegmentsLowestIndex: stagedSegmentsLowestIndex, transcription: transcription)
        }

        onListenUpdate?()
    }
    
    func processTranscriptSegment(segment: SFTranscriptionSegment, transcriptionIndex: Int, stagedSegmentsLowestIndex: Int, transcription: SFTranscription) {
        // Create Expression Segment
        var segments = self.expressionSegments
        
        // Manage NLP
        var segmentTags: [String : NLTag?]
        var sentiment: [ScaleUnitType: Float]?
        if stagedSegmentsLowestIndex == -1 || transcriptionIndex >= (segments.count - stagedSegmentsLowestIndex) {
             // New segment, compute values
            (segmentTags, sentiment) = computeSegmentTags(transcription: transcription, stagedSegmentsLowestIndex: stagedSegmentsLowestIndex, transcriptionIndex: transcriptionIndex)
        } else if transcriptionIndex < (segments.count - stagedSegmentsLowestIndex) {
            // existing segment, get values
            let existingSegment = self.expressionSegments[stagedSegmentsLowestIndex + transcriptionIndex]
            segmentTags = [
                "nameType": existingSegment.getNameType(),
                "lemma": existingSegment.getLemma(),
                "lexicalClass": existingSegment.getLexicalClass(),
                "tokenType": existingSegment.getTokenType(),
            ]
            if let sentimentScore = existingSegment.getSentiment() {
                sentiment = sentimentScore
            }
        } else {
            fatalError("\t[Error] There was a problem computing segment tags")
        }
        
        let word = transcriptionIndex == 0
            && segments.count > 0
            && !segments.last!.isSentenceTerminator()
            && !Utils.isFirstPersonSingularPronoun(segment.substring) ?
                segment.substring.lowercased()
                :
                segment.substring

        // Compute timestamp and duration
        var timestamp: Double
        var duration: Double
        if segment.duration <= 0 {
            // temporary segment
            // give it default temporary values
            if stagedSegmentsLowestIndex == -1 {
                // First temporary segment
                timestamp = 0
                duration = floor(Expression.defaultSegmentTimescale * DEFAULT_SEGMENT_DURATION)
            } else {
                let processedSeconds: Double = segments[stagedSegmentsLowestIndex].timeMapping.source.start.seconds
                timestamp = floor(Expression.defaultSegmentTimescale * (processedSeconds + Double(transcriptionIndex) * DEFAULT_SEGMENT_DURATION))
                duration = floor(Expression.defaultSegmentTimescale * DEFAULT_SEGMENT_DURATION)
            }
        } else {
            // enters here when we get the final transcript which has timestamp data
            timestamp = self.accumulatedDuration + segment.timestamp > 0 ? floor(Expression.defaultSegmentTimescale * (accumulatedDuration + segment.timestamp)) : 0
            duration = segment.duration > 0 ? floor(Expression.defaultSegmentTimescale * segment.duration) : 0
        }
        
        let phoneticallySimilarWords = segment.alternativeSubstrings
        
        let expressionSegment = ExpressionSegment(
            expression: self,
            word: word,
            trackURL: Utils.getFileURL(of: "\(self.filename)\(self.fileType)"),
            trackID: self.tracks[self.activeTrack].trackID,
            phoneticallySimilarWords: phoneticallySimilarWords,
            timeRange: CMTimeRangeMake(
                start: CMTimeMake(value: Int64(timestamp), timescale: Int32(Expression.defaultSegmentTimescale)),
                duration: CMTimeMake(value: Int64(duration), timescale: Int32(Expression.defaultSegmentTimescale))
            ),
            tokenType: segmentTags["tokenType"]!,
            lexicalClass: segmentTags["lexicalClass"]!,
            nameType: segmentTags["nameType"]!,
            lemma: segmentTags["lemma"]!,
            sentimentScore: sentiment ?? nil
        )
        
        if stagedSegmentsLowestIndex == -1 || transcriptionIndex >= (segments.count - stagedSegmentsLowestIndex) {
            // New segment, append to speechSegments
            segments.append(expressionSegment)
            self.expressionSegments = segments
        } else if transcriptionIndex <= (segments.count - stagedSegmentsLowestIndex) {
            // Existing segment, overwrite old copy
            // This assumes the new version is a better approximation of user speech
            let oldSegment = segments[stagedSegmentsLowestIndex + transcriptionIndex]
            if oldSegment != expressionSegment {
                segments[stagedSegmentsLowestIndex + transcriptionIndex] = expressionSegment
                self.expressionSegments = segments
            } else {
                // Existing segment without changes encountered.
                // print("Existing segment without changes encountered.")
            }
        } else {
            fatalError("\t[Error] There was a problem with pigeonholing segment")
        }
    }
    
    // We set sound intensity here because its when we with certainty have correct time data with pauses factored in
    // We set background noise here because we can identify all the silences
    // We set sentence numbers here because we've built up the entire expression and can compute sentences factoring it all
    // This is where correct values for avgPauseDuration and speakingRate are set
    func normalizeSegments(segments: [ExpressionSegment]? = nil, replaceExpressionDetails: Bool = false) {
        print("===== Normalizing Segments =====")
        var lastEnd = CMTime.zero
        var normalizedSegments = [ExpressionSegment]()
        var silenceIndices = [Int]()
        
        var segs = self.expressionSegments
        if let segments = segments {
            segs = segments
        }
        
        for (index, segment) in segs.enumerated() {
            if segment.timeMapping.source.start.seconds != lastEnd.seconds {
                if segment.timeMapping.source.start.seconds > lastEnd.seconds && !segment.isSilence() {
                    // Add a silent segment in front of current segment to account for early time
                    let silentSegment = ExpressionSegment(
                        expression: self,
                        word: "",
                        trackURL: Utils.getFileURL(of: "\(self.filename)\(self.fileType)"),
                        trackID: self.tracks[self.activeTrack].trackID,
                        phoneticallySimilarWords: [],
                        timeRange: CMTimeRangeMake(
                            start: lastEnd,
                            duration: segment.timeMapping.source.start - lastEnd
                        ),
                        tokenType: nil,
                        lexicalClass: nil,
                        nameType: nil,
                        lemma: nil,
                        sentimentScore: nil // silences have no sentiment
                    )
                    
                    // Segment Sound intensity
                    let startOfSegmentDuration: Double = segment.timeMapping.source.start.seconds
                    if segment.getSoundIntensity() == Utils.UNKNOWN {
                        // Add sound intensity
                        let soundIntensity = getRecordingSoundIntensity(timestamp: startOfSegmentDuration)
                        segment.setSoundIntensity(intensity: soundIntensity.intensity.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                    }
                    
                    // Silence Sound Intensity/Background Noise
                    if self.soundIntensityStream.count > 0 {
                        let startOfSilenceDuration: Double = lastEnd.seconds
                        let backgroundNoise = getRecordingSoundIntensity(timestamp: startOfSilenceDuration)
                        silentSegment.setSoundIntensity(intensity: backgroundNoise.intensity.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                    }
                    
                    if self.pitchStream.count > 0 {
                        // Add pitch
                        let pitch = getRecordingPitch(timestamp: startOfSegmentDuration)
                        segment.setPitch(pitch: pitch.pitch)
                    }
                    
                    // Save silence index
                    silenceIndices.append(normalizedSegments.count)
                    
                    // Add to segments array
                    normalizedSegments.append(silentSegment)
                    normalizedSegments.append(segment)
                    
                    // Update last end value
                    lastEnd = segment.timeMapping.source.end
                } else if segment.timeMapping.source.start.seconds > lastEnd.seconds && segment.isSilence() {
                    // Modify silent segment in front of current segment to account for early time
                    let modifiedSegment = ExpressionSegment(
                        expression: self,
                        word: segment.getText(),
                        trackURL: segment.sourceURL!,
                        trackID: segment.sourceTrackID,
                        phoneticallySimilarWords: segment.getPhoneticallySimilarWords(),
                        timeRange: CMTimeRangeFromTimeToTime(start: lastEnd, end: segment.timeMapping.source.end),
                        tokenType: segment.getTokenType(),
                        lexicalClass: segment.getLexicalClass(),
                        nameType: segment.getNameType(),
                        lemma: segment.getLemma(),
                        sentimentScore: segment.getSentiment()
                    )
                    
                    let startOfSilenceDuration: Double = lastEnd.seconds
                    if segment.getSoundIntensity() == Utils.UNKNOWN {
                        // Add sound intensity
                        let soundIntensity = getRecordingSoundIntensity(timestamp: startOfSilenceDuration)
                        modifiedSegment.setSoundIntensity(intensity: soundIntensity.intensity.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                    }
                    
                    // Save silence index
                    silenceIndices.append(normalizedSegments.count)
                    
                    // Add to segments array
                    normalizedSegments.append(modifiedSegment)
                    
                    // Update last end value
                    lastEnd = segment.timeMapping.source.end
                } else if segment.timeMapping.source.start.seconds < lastEnd.seconds && index != 0 {
                    // segment overlaps with previous segment, shift it forwards
                    let normalizedSegment = ExpressionSegment(
                        expression: self,
                        word: segment.getText(),
                        trackURL: segment.sourceURL!,
                        trackID: segment.sourceTrackID,
                        phoneticallySimilarWords: segment.getPhoneticallySimilarWords(),
                        timeRange: CMTimeRangeMake(
                            start: lastEnd,
                            duration: segment.timeMapping.source.duration
                        ),
                        tokenType: segment.getTokenType(),
                        lexicalClass: segment.getLexicalClass(),
                        nameType: segment.getNameType(),
                        lemma: segment.getLemma(),
                        sentimentScore: segment.getSentiment()
                    )
                    
                    let startOfSegmentDuration: Double = lastEnd.seconds
                    
                    // Sound Intensity
                    if segment.getSoundIntensity() != Utils.UNKNOWN {
                        // Import sound intensity
                        let soundIntensity = segment.getSoundIntensity()
                        normalizedSegment.setSoundIntensity(intensity: soundIntensity)
                    } else if self.soundIntensityStream.count > 0 {
                        // Add sound intensities
                        let soundIntensity = getRecordingSoundIntensity(timestamp: startOfSegmentDuration)
                        segment.setSoundIntensity(intensity: soundIntensity.intensity.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                    }
                    
                    // Pitch
                    if let pitch = segment.getPitch() {
                        // Import pitch
                        normalizedSegment.setPitch(pitch: pitch)
                    } else if self.pitchStream.count > 0 {
                        // Add pitch
                        let pitch = getRecordingPitch(timestamp: startOfSegmentDuration)
                        segment.setPitch(pitch: pitch.pitch)
                    }

                    // Add to segments array
                    normalizedSegments.append(normalizedSegment)
                    // print("Normalized time of segment: \(normalizedSegment.getText())")
                    
                    // Update last end value
                    lastEnd = CMTimeAdd(lastEnd, segment.timeMapping.source.duration)
                }
            } else {
                let middleOfSegmentDuration: Double = segment.timeMapping.source.start.seconds

                // Sound Intensity
                if segment.getSoundIntensity() != Utils.UNKNOWN {
                    // Import sound intensity
                    let soundIntensity = segment.getSoundIntensity()
                    segment.setSoundIntensity(intensity: soundIntensity)
                } else if self.soundIntensityStream.count > 0 {
                    // Add sound intensities
                    let soundIntensity = getRecordingSoundIntensity(timestamp: middleOfSegmentDuration)
                    segment.setSoundIntensity(intensity: soundIntensity.intensity.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                }
                
                // Pitch
                if let pitch = segment.getPitch() {
                    // Import pitch
                    segment.setPitch(pitch: pitch)
                } else if self.pitchStream.count > 0 {
                    // Add pitch
                    let pitch = getRecordingPitch(timestamp: middleOfSegmentDuration)
                    segment.setPitch(pitch: pitch.pitch)
                }
                
                // Add to segments array
                normalizedSegments.append(segment)
                
                // Update last end value
                lastEnd = segment.timeMapping.source.end
            }
        }
        
        // Manage Background Noise = average of silences in transcription
        var backgroundNoise: Double = silenceIndices.reduce(0, { result, i in
            return result + normalizedSegments[i].getSoundIntensity()
        }) / Double(silenceIndices.count)
        backgroundNoise = backgroundNoise.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT)
        
        var avgPauseDuration: Double = silenceIndices.reduce(0, { result, i in
            return result + normalizedSegments[i].timeMapping.source.duration.seconds
        }) / Double(silenceIndices.count)
        avgPauseDuration = avgPauseDuration.rounded(toPlaces: DEFAULT_FIG_COUNT)
        
        var speakingRate: Double = normalizedSegments.reduce(0, { result, item in
            if !item.isPunctuation() && !item.isSilence() {
                return result + 1
            }
            
            return result
        }) / Double(self.duration.seconds / Double(TimeConstant.secsPerMin))
        speakingRate = speakingRate.rounded(toPlaces: DEFAULT_FIG_COUNT)
        
        // Update Index, Background Noise, AvgPauseDuration, SpeakingRate
        for (index, segment) in normalizedSegments.enumerated() {
            // Set segment index
            segment.setIndex(index: index)
            
            // Set backgroundNoise
            segment.setBackgroundNoise(noise: backgroundNoise)

            // Set avgPauseDuration
            segment.setAvgPauseDuration(duration: avgPauseDuration)
            
            // Set speakingRate
            segment.setSpeakingRate(rate: speakingRate)
        }
        
        self.setSegments(segments: normalizedSegments, replaceExpressionDetails: replaceExpressionDetails)
        
        checkRep()
    }
    
    // MARK: - Listening Method Helpers
    
    func computeSegmentTags(transcription: SFTranscription, stagedSegmentsLowestIndex: Int, transcriptionIndex: Int) -> ([String : NLTag?], [ScaleUnitType: Float]) {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .tokenType, .sentimentScore, .lemma])
        let segmentText = transcription.segments[transcriptionIndex].substring
        
        var index: Int
        if stagedSegmentsLowestIndex == -1 || transcriptionIndex > (self.expressionSegments.count - stagedSegmentsLowestIndex) {
            // New segment, append to speechSegments
            index = self.expressionSegments.count
        } else if transcriptionIndex <= (self.expressionSegments.count - stagedSegmentsLowestIndex) {
            // Existing segment, overwrite old copy
            // This assumes the new version is a better approximation of user speech
            index = stagedSegmentsLowestIndex + transcriptionIndex
        } else {
            fatalError("\t[Error] There was a problem computing segment index in computeSegmentTags")
        }
        
        let wholeText = segmentText.count == 1 && segmentText.first!.isPunctuation ?
            getExpressionText() + segmentText
        :
            getExpressionText() + " \(segmentText)"
        tagger.string = wholeText

        var nameType: NLTag?
        var lemma: NLTag?
        var lexicalClass: NLTag?
        var tokenType: NLTag?
        var wordSentimentScore: NLTag?
        var sentenceSentimentScore: NLTag?
        var paragraphSentimentScore: NLTag?
        let range = findSegmentRange(segments: self.expressionSegments, wholeText: wholeText, segmentText: segmentText, index: index)
        let rangeStartIndex: Int = wholeText.distance(from: wholeText.startIndex, to: range.lowerBound)
        let stringIndex = wholeText.index(wholeText.startIndex, offsetBy: rangeStartIndex)
        (nameType, _) = tagger.tag(at: stringIndex, unit: .word, scheme: .nameType)
        (lemma, _) = tagger.tag(at: stringIndex, unit: .word, scheme: .lemma)
        (lexicalClass, _) = tagger.tag(at: stringIndex, unit: .word, scheme: .lexicalClass)
        (tokenType, _) = tagger.tag(at: stringIndex, unit: .word, scheme: .tokenType)
        (nameType, _) = tagger.tag(at: stringIndex, unit: .word, scheme: .nameType)
        (wordSentimentScore, _) = tagger.tag(at: stringIndex, unit: .word, scheme: .sentimentScore)
        (sentenceSentimentScore, _) = tagger.tag(at: stringIndex, unit: .sentence, scheme: .sentimentScore)
        (paragraphSentimentScore, _) = tagger.tag(at: stringIndex, unit: .paragraph, scheme: .sentimentScore)
        
        let sentiment: [ScaleUnitType: Float] = [
            .word: Float(wordSentimentScore?.rawValue ?? "0") ?? 0,
            .sentence: Float(sentenceSentimentScore?.rawValue ?? "0") ?? 0,
            .all: Float(paragraphSentimentScore?.rawValue ?? "0") ?? 0
        ]
        
        let tokenTags: [String : NLTag?] = [
            "nameType": nameType,
            "lemma": lemma,
            "lexicalClass": lexicalClass,
            "tokenType": tokenType,
        ]
        
        return (tokenTags, sentiment)
    }
    
    // For this method, we need to do a for loop because it's used to figure out the initial sentence data
    // So we can't just read segment's sentence property because it hasn't been set yet
    func getSentenceNumber(segments: [ExpressionSegment], segment: ExpressionSegment) -> Int {
        var sentenceNumber = 0

        for seg in segments {
            if seg == segment {
                break
            }

            if seg.isSentenceTerminator(withPunctuationSuggestions: self.withPunctuationSuggestions) {
                sentenceNumber += 1
            }
        }

        return sentenceNumber
    }
    
    // Can't handle empty strings for segmentText
    func findSegmentRange(segments: [ExpressionSegment], wholeText: String, segmentText: String, index: Int) -> Range<String.Index> {
        // figure out how many words are before it
        // compute number of processedChar
        var lowerText: String
        if index >= segments.count && index - segments.count <= 1 {
            // new segment
            lowerText = self.getExpressionText(segments: segments)
        } else if index < segments.count && index > 0 {
            // is in in expressionSegments
            let lowerBoundarySegment = segments[index - 1]
            lowerText = self.getExpressionText(until: lowerBoundarySegment.timeMapping.source.start, segments: segments)
        } else if index == 0 && segments.count == 0 {
            // is first segment
            lowerText = ""
        } else {
            fatalError("\t[Error] There was a problem analyzing the index of segment in findSegmentRange")
        }
        
        let lowerIndex = segmentText.count == 1 && segmentText.first!.isPunctuation ?
            wholeText.index(wholeText.startIndex, offsetBy: lowerText.count)
        :
            wholeText.index(wholeText.startIndex, offsetBy: lowerText.count + 1)
        let upperIndex = wholeText.index(lowerIndex, offsetBy: segmentText.count - 1)
        let segmentRange = lowerIndex..<upperIndex
        
        return segmentRange
    }
    
    func getRecordingSoundIntensity(timestamp: Double) -> SoundIntensityDatum {
        var soundIntensity: SoundIntensityDatum
        var i = 0
        var datumTimestamp = soundIntensityStream[i].date - recordStartDate! - TRANSCRIPTION_LATENCY_DURATION
        repeat {
            datumTimestamp = soundIntensityStream[i].date - recordStartDate! - TRANSCRIPTION_LATENCY_DURATION
            soundIntensity = soundIntensityStream[i]
            i += 1
        } while datumTimestamp < timestamp && i < soundIntensityStream.count
        
        return soundIntensity
    }
    
    func getRecordingPitch(timestamp: Double) -> PitchDatum {
        var pitch: PitchDatum
        var i = 0
        var datumTimestamp = pitchStream[i].date - recordStartDate! - TRANSCRIPTION_LATENCY_DURATION
        repeat {
            datumTimestamp = pitchStream[i].date - recordStartDate! - TRANSCRIPTION_LATENCY_DURATION
            pitch = pitchStream[i]
            i += 1
        } while datumTimestamp < timestamp && i < pitchStream.count
        
        return pitch
    }
    
    // MARK: - Text Methods
    
    func getExpressionText(from time: CMTime = CMTime.zero, segments: [ExpressionSegment]? = nil, forEcho: Bool = false) -> String {
        var text = ""
        
        var expressionSegments = self.expressionSegments
        if let segments = segments {
            expressionSegments = segments
        }

        for segment in expressionSegments  {
            if segment.timeMapping.source.start >= time {
                let word = segment.getText(
                    withTemporalSuggestions: self.withTemporalSuggestions,
                    withPunctuationSuggestions: self.withPunctuationSuggestions,
                    withFormattingSuggestions: self.withFormattingSuggestions,
                    strictlyAsWord: self.withTextStrictlyAsWords,
                    withSpacePrefix: true,
                    forEcho: forEcho
                )
                
                text += word
            }
        }
        
        // Remove whitespaces on edges
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // make sure first letter is capitalized
        // not capitalized when we're dealing with expresssions that come from chopped up expressions
        text = text.capitalizeFirstLetter()

        return text
    }
    
    // We need to deal with segments from different places
    func getExpressionText(until time: CMTime, segments: [ExpressionSegment]? = nil, forEcho: Bool = false) -> String {
        var text = ""
        
        var expressionSegments = self.expressionSegments
        if let segments = segments {
            expressionSegments = segments
        }
        
        for segment in expressionSegments  {
            if segment.timeMapping.source.start <= time {
                let word = segment.getText(
                    withTemporalSuggestions: self.withTemporalSuggestions,
                    withPunctuationSuggestions: self.withPunctuationSuggestions,
                    withFormattingSuggestions: self.withFormattingSuggestions,
                    strictlyAsWord: self.withTextStrictlyAsWords,
                    withSpacePrefix: true,
                    forEcho: forEcho
                )
                
                text += word
            }
        }

        // Remove whitespaces on edges
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // make sure first letter is capitalized
        // not capitalized when we're dealing with expresssions that come from chopped up expressions
        text = text.capitalizeFirstLetter()
        
        return text
    }
    
    // MARK: - Player Methods
    
    func play(from: CMTime? = nil, to: CMTime? = nil, onStartHandler: (() -> Void)? = nil, secondElapseHandler: (() -> Void)? = nil, segmentBoundaryHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
        print("===== Play Expression =====")
        
        // Play Sound
        sounds.play()
        
        if speechSynthesizer.isSpeaking {
            print("\tPause speech synthesizer to play speech audio.\n")
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        if onStartHandler != nil {
            self.observerContext["onStartHandler"] = onStartHandler
        }
        
        if secondElapseHandler != nil {
            self.observerContext["secondElapseHandler"] = secondElapseHandler
        }
        
        if segmentBoundaryHandler != nil {
            self.observerContext["segmentBoundaryHandler"] = segmentBoundaryHandler
        }
        
        if onFinishHandler != nil {
            self.observerContext["onFinishHandler"] = onFinishHandler
        }
        
        // Set Start and End Times
        self.startPlaybackAt = from != nil ? from : self.startTime
        self.stopPlaybackAt = to != nil ? to : self.endTime
        
        // Run Player
        let player = Utils.runPlayer(
            expression: self,
            startTime: self.startPlaybackAt!,
            rate: self.playbackRate,
            volume: self.playbackVolume,
            onStartHandler: onStartHandler
        )
        
        if let player = player {
            self.player = player
        }
    }
    
    func playSentence(number: Int, onStartHandler: (() -> Void)? = nil, secondElapseHandler: (() -> Void)? = nil, segmentBoundaryHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
        
        // Play Sound
        sounds.play()
        
        if speechSynthesizer.isSpeaking {
            print("===== Pause speech synthesizer to play speech audio =====")
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        if onStartHandler != nil {
            self.observerContext["onStartHandler"] = onStartHandler
        }

        if secondElapseHandler != nil {
            self.observerContext["secondElapseHandler"] = secondElapseHandler
        }

        if segmentBoundaryHandler != nil {
            self.observerContext["segmentBoundaryHandler"] = segmentBoundaryHandler
        }

        if onFinishHandler != nil {
            self.observerContext["onFinishHandler"] = onFinishHandler
        }

        // Get sentence details
        let sentenceDetails = getSentenceDetails(number: number)
        
        // Set Start and End Times
        self.startPlaybackAt = sentenceDetails!.timeRange.start
        self.stopPlaybackAt = sentenceDetails!.timeRange.end
        
        // Run Player
        let player = Utils.runPlayer(
            expression: self,
            startTime: self.startPlaybackAt!,
            rate: self.playbackRate,
            volume: self.playbackVolume,
            onStartHandler: onStartHandler
        )
        
        if let player = player {
            self.player = player
        }
    }

    func playSentence(forTrackTime: CMTime, onStartHandler: (() -> Void)? = nil, secondElapseHandler: (() -> Void)? = nil, segmentBoundaryHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
        
        // Play Sound
        sounds.play()
        
        if speechSynthesizer.isSpeaking {
            print("===== Pause speech synthesizer to play speech audio =====")
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        if onStartHandler != nil {
            self.observerContext["onStartHandler"] = onStartHandler
        }

        if secondElapseHandler != nil {
            self.observerContext["secondElapseHandler"] = secondElapseHandler
        }

        if segmentBoundaryHandler != nil {
            self.observerContext["segmentBoundaryHandler"] = segmentBoundaryHandler
        }

        if onFinishHandler != nil {
            self.observerContext["onFinishHandler"] = onFinishHandler
        }

        // Get sentence details
        let sentenceDetails = getSentenceDetails(forTrackTime: forTrackTime)
        
        // Set Start and End Times
        self.startPlaybackAt = sentenceDetails!.timeRange.start
        self.stopPlaybackAt = sentenceDetails!.timeRange.end

        // Run Player
        let player = Utils.runPlayer(
            expression: self,
            startTime: self.startPlaybackAt!,
            rate: self.playbackRate,
            volume: self.playbackVolume,
            onStartHandler: onStartHandler
        )
        
        if let player = player {
            self.player = player
        }
    }
    
    func replayCurrentSentence(handler: (() -> Void)? = nil) {
        
        // Play Sound
        sounds.repeatSegment()

        // Get current time
        let currentTime = player.currentTime()
        
        // Get sentence details
        let sentenceDetails = getSentenceDetails(forTrackTime: currentTime)
        
        if let sentenceDetails = sentenceDetails {
            playSentence(number: sentenceDetails.number)
        } else {
            fatalError("\t[Error] There was a problem replaying current sentence")
        }
    }
    
    func pause(handler: (() -> Void)? = nil) {
        print("===== Pause Expression =====")
        player.pause()
        handler?()
    }
    
    func stop(handler: (() -> Void)? = nil) {
        print("===== Stop Expression =====")
        handleCompletionObserver() // Stops player and resets startPlaybackAt / stopPlaybackAt
        handler?()
    }
    
    // MARK: - Echo Methods
    
    func startEcho(onStartHandler: (() -> Void)? = nil, onCompletionHandler: (() -> Void)? = nil) {
        // Computer understanding of the expression
        print("==== Initiate new speech synthesizer utterance =====")
        let expressionText = self.getExpressionText(forEcho: false) // make forEcho true when we're doing voice only
        let utterance = AVSpeechUtterance(string: expressionText)
        if let voice = speaker.playbackVoice {
            utterance.voice = voice
        }
        utterance.rate = (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) / 2 + AVSpeechUtteranceMinimumSpeechRate
        utterance.volume = self.playbackVolume
        speechSynthesizer.speak(utterance)
        
        if player.isPlaying {
            print("\tStop speech audio to play speech synthesizer")
            player.stop()
        }
        
        if let onCompletionHandler = onCompletionHandler {
            self.tempOnEchoFinish = onCompletionHandler
        }
    
        onStartHandler?()
    }
    
    func pauseEcho(handler: (() -> Void)? = nil) {
        print("===== Pause Echo =====")
        speechSynthesizer.pauseSpeaking(at: .immediate)
        handler?()
    }
    
    func continueEcho(handler: (() -> Void)? = nil) {
        print("===== Continue Echo =====")
        speechSynthesizer.continueSpeaking()
        handler?()
    }
    
    func stopEcho(handler: (() -> Void)? = nil) {
        print("===== Stop Echo =====")
        speechSynthesizer.stopSpeaking(at: .immediate)
        handler?()
    }
    
    func echoText(text: String) {
        print("==== Echo expression snippet =====")
        // Stop existing echo
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Create echo text
        let splitText = text.components(separatedBy: " ")
        var echoText = ""
        for word in splitText {
            if word.count == 1 && word.first!.isPunctuation {
                echoText += " \(PunctuationMap[word] ?? "") \(word)"
            } else {
                echoText += " \(word)"
            }
        }
        echoText = echoText.trimmingCharacters(in: .whitespacesAndNewlines)
        let utterance = AVSpeechUtterance(string: echoText)
        if let voice = speaker.playbackVoice {
            utterance.voice = voice
        }
        utterance.rate = (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) / 2 + AVSpeechUtteranceMinimumSpeechRate
        utterance.volume = self.playbackVolume
        speechSynthesizer.speak(utterance)
        
        if player.isPlaying {
            print("\tStop speech audio to play speech synthesizer")
            player.stop()
        }
    }
    
    // MARK: - Mutating Methods

    func trimExpression(keeping: CMTimeRange, permanent: Bool = false, overwrite: Bool = false, onCompletionHandler: (() -> Void)? = nil) {
        let keepRange = keeping
        print("===== Trim Expression keeping section starting: \(keepRange.start.seconds) until: \(keepRange.end.seconds) =====")
        
        var newExpressionSegments = [ExpressionSegment]()
        var silenceIndices = [Int]()
        if permanent {
            print("\tModify start and end times...")
            self.startTime = CMTime.zero
            self.endTime = keepRange.duration
            
            // Create new filename if not or can't overwrite
            if !overwrite || self._fileType != .m4a {
                print("\tCreate new filename ...")
                self.filename = "expression-\(UUID().uuidString)"
            }
            
            print("\tExporting and modifying segments...")
            Utils.exportExpression(
                expression: self,
                filename: self.filename,
                fileType: self.fileType,
                timeRange: keepRange
            ) {
                // Manage Segments
                var lastEnd = CMTime.zero
                if keepRange.start == CMTime.zero {
                    print("\tExpression Segments don't require time-shifting...")
                    // requires no time-shifting if on the left side of range
                    for (index, seg) in self.expressionSegments.enumerated() {
                        if keepRange.containsTimeRange(seg.timeMapping.source) {
                            let segment = seg.duplicate(index: index)
                            
                            // Save silence index
                            if segment.isSilence() {
                                silenceIndices.append(newExpressionSegments.count)
                            }

                            // Add segment to array
                            newExpressionSegments.append(segment)
                            
                            // Update lastEnd
                            lastEnd = seg.timeMapping.source.end
                        }
                    }
                } else {
                    print("\tExpression Segments require time-shifting...")
                    // requires time-shifting if on the right side of range
                    for (index, seg) in self.expressionSegments.enumerated() {
                        if keepRange.containsTimeRange(seg.timeMapping.source) {
                            let shiftedSegment = seg.duplicate(
                                index: index,
                                timeRange: CMTimeRangeMake(
                                    start: lastEnd,
                                    duration: seg.timeMapping.source.duration
                                )
                            )

                            // Save silence index
                            if shiftedSegment.isSilence() {
                                silenceIndices.append(newExpressionSegments.count)
                            }

                            // Add segment to array
                            newExpressionSegments.append(shiftedSegment)

                            // Update lastEnd
                            lastEnd = CMTimeAdd(lastEnd, seg.timeMapping.source.duration)
                        }
                    }
                }

                print("\tUpdate index, backgroundNoise, avgPauseDuration, and speakingRate...")
                var backgroundNoise: Double = silenceIndices.reduce(0, { result, i in
                   return result + newExpressionSegments[i].getSoundIntensity()
                }) / Double(silenceIndices.count)
                backgroundNoise = backgroundNoise.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT)

                var avgPauseDuration: Double = silenceIndices.reduce(0, { result, i in
                   return result + newExpressionSegments[i].timeMapping.source.duration.seconds
                }) / Double(silenceIndices.count)
                avgPauseDuration = avgPauseDuration.rounded(toPlaces: DEFAULT_FIG_COUNT)

                var speakingRate: Double = newExpressionSegments.reduce(0, { result, item in
                   if !item.isPunctuation() && !item.isSilence() {
                       return result + 1
                   }
                   
                   return result
                }) / Double(self.duration.seconds / Double(TimeConstant.secsPerMin))
                speakingRate = speakingRate.rounded(toPlaces: DEFAULT_FIG_COUNT)

                // Update Index, Background Noise, AvgPauseDuration, SpeakingRate
                for (index, segment) in newExpressionSegments.enumerated() {
                    // Set segment index
                    // We might need to update indices if we lost segments above
                    segment.setIndex(index: index)

                    // Set background noise
                    segment.setBackgroundNoise(noise: backgroundNoise)

                    // Set avgPauseDuration
                    segment.setAvgPauseDuration(duration: avgPauseDuration)

                    // Set speakingRate
                    segment.setSpeakingRate(rate: speakingRate)
                }
                
                print("\tUpdate expression file type...")
                // Change File Type
                // We need this to be placed before normalizeSegments so newExpressionSegments are
                // updated with new trackURL
                self.setFileType(fileType: .m4a)

                print("\tNormalize segments to correct for any time-related errors...")
                // Correct any time-related errors
                // Normalize Segments will setSegments
                // Make sure we update segments to reflect new track URL
                self.normalizeSegments(segments: newExpressionSegments, replaceExpressionDetails: true)

                // Check Representation Invariant
                self.checkRep()
                
                // Run Completion Handler
                onCompletionHandler?()
            }
        } else {
            // Need to remove right side first because everything shifts
            // if we do left side first
            print("\tRemove time ranges from underlying AVMutableComposition...")
            print("\tChange start times...")
            if CMTimeSubtract(self.duration, keepRange.end) > CMTime.zero && CMTimeSubtract(keepRange.start, CMTime.zero) > CMTime.zero {
                // Remove from right side and left
                print("\tTrim Expression from the right and left side...")
                let removeRightRange = CMTimeRangeFromTimeToTime(start: keepRange.end, end: self.duration)
                let removeLeftRange = CMTimeRangeFromTimeToTime(start: CMTime.zero, end: keepRange.start)
                
                // Remove Time Range
                self.removeTimeRange(removeRightRange)
                self.removeTimeRange(removeLeftRange)
            } else if CMTimeSubtract(self.duration, keepRange.end) > CMTime.zero && CMTimeSubtract(keepRange.start, CMTime.zero) <= CMTime.zero {
                // Remove from right side only
                print("\tTrim Expression from the right side only...")
                let removeRightRange = CMTimeRangeFromTimeToTime(start: keepRange.end, end: self.duration)
                
                // Remove Time Range
                self.removeTimeRange(removeRightRange)
            } else if CMTimeSubtract(self.duration, keepRange.end) <= CMTime.zero && CMTimeSubtract(keepRange.start, CMTime.zero) > CMTime.zero {
                // Remove from left side only
                print("\tTrim Expression from the left side only...")
                let removeLeftRange = CMTimeRangeFromTimeToTime(start: CMTime.zero, end: keepRange.start)
                
                // Remove Time Range
                self.removeTimeRange(removeLeftRange)
            }

            print("\tModify expression start and end times...")
            self.startTime = CMTime.zero
            self.endTime = keepRange.duration

            print("\tFiltering expression segments...")
            var lastEnd = CMTime.zero
            if keepRange.start == CMTime.zero {
                print("\tExpression Segments don't require time-shifting...")
                // requires no time-shifting if on the left side of range
                for (index, seg) in self.expressionSegments.enumerated() {
                    if keepRange.containsTimeRange(seg.timeMapping.source) {
                        let segment = seg.duplicate(index: index)
                        
                        // Save silence index
                        if segment.isSilence() {
                            silenceIndices.append(newExpressionSegments.count)
                        }

                        // Add segment to array
                        newExpressionSegments.append(segment)
                        
                        // Update lastEnd
                        lastEnd = seg.timeMapping.source.end
                    }
                }
            } else {
                print("\tExpression Segments require time-shifting...")
                // requires time-shifting if on the right side of range
                for (index, seg) in self.expressionSegments.enumerated() {
                    if keepRange.containsTimeRange(seg.timeMapping.source) {
                        let shiftedSegment = seg.duplicate(
                            index: index,
                            timeRange: CMTimeRangeMake(
                                start: lastEnd,
                                duration: seg.timeMapping.source.duration
                            )
                        )

                        // Save silence index
                        if shiftedSegment.isSilence() {
                            silenceIndices.append(newExpressionSegments.count)
                        }

                        // Add segment to array
                        newExpressionSegments.append(shiftedSegment)

                        // Update lastEnd
                        lastEnd = CMTimeAdd(lastEnd, seg.timeMapping.source.duration)
                    }
                }
            }
            
            print("\tUpdate index, backgroundNoise, avgPauseDuration, and speakingRate...")
            var backgroundNoise: Double = silenceIndices.reduce(0, { result, i in
               return result + newExpressionSegments[i].getSoundIntensity()
            }) / Double(silenceIndices.count)
            backgroundNoise = backgroundNoise.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT)

            var avgPauseDuration: Double = silenceIndices.reduce(0, { result, i in
               return result + newExpressionSegments[i].timeMapping.source.duration.seconds
            }) / Double(silenceIndices.count)
            avgPauseDuration = avgPauseDuration.rounded(toPlaces: DEFAULT_FIG_COUNT)

            var speakingRate: Double = newExpressionSegments.reduce(0, { result, item in
               if !item.isPunctuation() && !item.isSilence() {
                   return result + 1
               }
               
               return result
            }) / Double(self.duration.seconds / Double(TimeConstant.secsPerMin))
            speakingRate = speakingRate.rounded(toPlaces: DEFAULT_FIG_COUNT)

            // Update Index, Background Noise, AvgPauseDuration, SpeakingRate
            for (index, segment) in newExpressionSegments.enumerated() {
                // Set segment index
                // We might need to update indices if we lost segments above
                segment.setIndex(index: index)

                // Set background noise
                segment.setBackgroundNoise(noise: backgroundNoise)

                // Set avgPauseDuration
                segment.setAvgPauseDuration(duration: avgPauseDuration)

                // Set speakingRate
                segment.setSpeakingRate(rate: speakingRate)
            }
            
            print("\tUpdate Expression Segments...")
            // Update Segments
            // We cannot go through setSegments method because these expression segments might not be normalized
            self.expressionSegments = newExpressionSegments
            // Compute segment sentences
            updateSegmentSentences(segments: self.expressionSegments)

            // Check Representation Invariant
            self.checkRep()
            
            // Run Completion Handler
            onCompletionHandler?()
        }
    }
    
    // Mutates Segments
    func updateSegmentSentences(segments: [ExpressionSegment]) {
        print("===== Update Segment Sentences =====")
        var sentenceNumber = 0
        var sentenceText = ""
        var sentenceStartTime = CMTime.zero
        var sentenceEndTime: CMTime
        // Holds the index of the first segment without a sentence
        var leftStaleSegmentIndex = 0
        // make sure silences get sentence number of prior.
        for (index, segment) in segments.enumerated() {
            if index + 1 == segments.count {
                // We've reached the end of the expression. Update sentence data
                sentenceEndTime = segment.timeMapping.source.end
                sentenceText += segment.getText(withSpacePrefix: true)
                let sentence = Sentence(
                    number: sentenceNumber,
                    text: sentenceText.trimmingCharacters(in: .whitespacesAndNewlines),
                    timeRange: CMTimeRangeFromTimeToTime(
                        start: sentenceStartTime,
                        end: sentenceEndTime
                    )
                )
                
                // Clear sentence
                sentenceText = ""
                
                // Add sentence to every segment ***including*** this one
                for i in leftStaleSegmentIndex...index {
                    segments[i].setSentence(sentence: sentence)
                }
            } else if segment.isSilence() {
                if index > 0 && !segments[index - 1].isSentenceTerminator() {
                    // Do nothing
                } else if index > 0 && segments[index - 1].isSentenceTerminator() {
                    // We've hit a sentence boundary. Update sentences
                    // Update sentence data
                    sentenceEndTime = segment.timeMapping.source.start
                    let sentence = Sentence(
                        number: sentenceNumber,
                        text: sentenceText.trimmingCharacters(in: .whitespacesAndNewlines),
                        timeRange: CMTimeRangeFromTimeToTime(
                            start: sentenceStartTime,
                            end: sentenceEndTime
                        )
                    )
                    sentenceNumber += 1
                    sentenceStartTime = segment.timeMapping.source.start
                    // Clear sentence
                    sentenceText = ""
                    
                    // Add sentence to every segment before this one
                    for i in leftStaleSegmentIndex..<index {
                        segments[i].setSentence(sentence: sentence)
                    }
                    leftStaleSegmentIndex = index
                }
            } else if !segment.isSilence() {
                // We can't let silences in here because getSentenceNumber can't handle empty strings
                let number = getSentenceNumber(segments: segments, segment: segment)
                
                if number != sentenceNumber && number == sentenceNumber + 1 {
                    // We've hit a sentence boundary. Update sentences
                    // print("We've hit a sentence boundary. Update sentence data")
                    // Update sentence data
                    sentenceEndTime = segment.timeMapping.source.start
                    let sentence = Sentence(
                        number: sentenceNumber,
                        text: sentenceText.trimmingCharacters(in: .whitespacesAndNewlines),
                        timeRange: CMTimeRangeFromTimeToTime(
                            start: sentenceStartTime,
                            end: sentenceEndTime
                        )
                    )
                    sentenceNumber = number
                    sentenceStartTime = segment.timeMapping.source.start
                    sentenceText += segment.getText(withSpacePrefix: true)
                    
                    // Add sentence to every segment before this one
                    for i in leftStaleSegmentIndex..<index {
                        segments[i].setSentence(sentence: sentence)
                    }

                    leftStaleSegmentIndex = index
                } else if number == sentenceNumber {
                    // Add word to sentence
                    sentenceText += segment.getText(withSpacePrefix: true)
                } else {
                    fatalError("\t[Error] There was a problem updating segment sentences. Unexpected index behavior")
                }
            }
        }
    }
    
    func setPlaybackRate(wpm: Float) {
        self.playbackRate = wpm / Float(self.avgSpeakingRate).rounded(toPlaces: DEFAULT_FIG_COUNT)
    }
    
    // MARK: - Setters
    
    func setGender(as gender: Gender) {
        speaker.gender = gender
        
        checkRep()
    }
    
    func setSkipPunctuation(as skip: Bool) {
        self.skipPunctuation = skip
        
        checkRep()
    }
    
    func setSkipSilence(as skip: Bool) {
        self.skipSilence = skip
        
        checkRep()
    }
    
    // We lack a checkRep here because we use it mid
    // operation in trimExpression when the representation invariant is broken
    func setFileType(fileType: AVFileType) {
        self._fileType = fileType
    }
    
    func setWithTemporalSuggestions(to value: Bool) {
        self.withTemporalSuggestions = value
        
        // We can only have one suggestion type on at a time
        // Deactivate punctuation suggestions if active
        if value && self.withPunctuationSuggestions {
            self.withTemporalSuggestions = false
        }
        
        checkRep()
    }
    
    func setWithPunctuationSuggestions(to value: Bool) {
        self.withPunctuationSuggestions = value
        
        // We can only have one suggestion type on at a time
        // Deactivate space suggestions if active
        if value && self.withTemporalSuggestions {
            self.withTemporalSuggestions = false
        }
        
        checkRep()
    }
    
    func setWithFormattingSuggestions(to value: Bool) {
        self.withFormattingSuggestions = value
        
        checkRep()
    }
    
    func setWithTextStrictlyAsWords(to value: Bool) {
        self.withTextStrictlyAsWords = value
        
        checkRep()
    }
    
    // expression details refer to expression, sourceURL, and trackID
    // we have to duplicate segments to reset these
    // thus is a costly computation
    func setSegments(segments: [ExpressionSegment], replaceExpressionDetails: Bool = false) {
        print("===== Set Segments =====")
        var setSegmentExpression = false
        // set expression reference in segments
        if segments.count > 0 && segments[0].expression == nil {
            setSegmentExpression = true
        }
        
        var updatedSegments = [ExpressionSegment]()
        if replaceExpressionDetails {
            for (index, segment) in segments.enumerated() {
                let seg = segment.duplicate(
                    newExpression: self,
                    index: index
                )

                // Add segment to array
                updatedSegments.append(seg)
            }
        }
        
        if setSegmentExpression && !replaceExpressionDetails {
            // Replace Expression
            for segment in segments {
                segment.setExpression(expression: self)
            }
        }
        
        let finalSegments = replaceExpressionDetails ? updatedSegments : segments

        // attempt to replace segments
        do {
            try self.tracks[self.activeTrack].validateSegments(finalSegments)
            self.expressionSegments = finalSegments
            self.tracks[self.activeTrack].segments = finalSegments
            // Compute segment sentences
            updateSegmentSentences(segments: self.expressionSegments)
            self.endTime = self.expressionSegments.last!.timeMapping.source.end
            print("\tSuccessfully updated expression segments")
        } catch {
            fatalError("\t[Error] There was a problem updating expression segments")
        }

        checkRep()
    }
    
    // MARK: - Getters
    
    // https://developer.apple.com/documentation/avfoundation/avassetexportpresetpassthrough
    // https://stackoverflow.com/questions/58025109/exporting-mp3-with-avassetexportsession
    // We do not compute sentences for segments here because the segments lack a reference to an expression
    // Without a reference to an expression, they cannot compute getText correctly
    func duplicate(onCompletionHandler: @escaping (_ expression: Expression?) -> Void) {
        print("===== Duplicate Expression =====")
        // Export Expression
        let duplicateFilename = "expression-\(UUID().uuidString)"
        Utils.exportExpression(
            expression: self,
            filename: duplicateFilename,
            fileType: self.fileType,
            timeRange: CMTimeRangeMake(start: CMTime.zero, duration: self.duration)
        ) {
            onCompletionHandler(Expression(
                vc: self.vc,
                filename: duplicateFilename,
                fileType: .m4a,
                speaker: self.speaker,
                minDb: self.minDb,
                segments: self.expressionSegments, // Will copy segments so there are not multiple pointers to a single segment
                withOnDeviceRecognition: self.useOnDeviceRecognition,
                withTemporalSuggestions: self.withTemporalSuggestions,
                withPunctuationSuggestions: self.withPunctuationSuggestions,
                withFormattingSuggestions: self.withFormattingSuggestions,
                withTextStrictlyAsWords: self.withTextStrictlyAsWords
            ))
        }
    }
    
    func getSentenceDetails(number: Int) -> Sentence? {
        for segment in expressionSegments {
            if segment.getSentence().number == number {
                return segment.getSentence()
            }
        }
        
        return nil
    }

    func getSentenceDetails(forTrackTime: CMTime) -> Sentence? {
        for segment in expressionSegments {
            if segment.getSentence().timeRange.containsTime(forTrackTime) {
                return segment.getSentence()
            }
        }
        
        return nil
    }
    
    func extractSentence(number: Int, onCompletionHandler: @escaping (_ sentence: Expression?) -> Void) {
        for segment in expressionSegments {
            if segment.getSentence().number == number {
                segment.createSentenceExpression() { sentence in
                    onCompletionHandler(sentence)
                }
                break
            }
        }
    }
    
    func extractSentence(forTrackTime: CMTime, onCompletionHandler: @escaping (_ sentence: Expression?) -> Void) {
        for segment in expressionSegments {
            if segment.getSentence().timeRange.containsTime(forTrackTime) {
                segment.createSentenceExpression() { sentence in
                    onCompletionHandler(sentence)
                }
                break
            }
        }
    }
    
    func extractSentence(type: SentencePosition, onCompletionHandler: @escaping (_ sentence: Expression?) -> Void) {
        let currentTime = player.currentTime()
        self.extractSentence(forTrackTime: currentTime) { sentence in
            switch type {
            case .current:
                onCompletionHandler(sentence)
                break
            case .previous:
                let timestamp = floor(Expression.defaultSegmentTimescale * (currentTime.seconds - DIFFERENCE))
                let previousTime = CMTimeMake(
                    value: Int64(timestamp),
                    timescale: Int32(Expression.defaultSegmentTimescale)
                )
                self.extractSentence(forTrackTime: previousTime) { sentence in
                    onCompletionHandler(sentence)
                }
                break
            case .next:
                let timestamp = floor(Expression.defaultSegmentTimescale * (currentTime.seconds + DIFFERENCE))
                let nextTime = CMTimeMake(
                    value: Int64(timestamp),
                    timescale: Int32(Expression.defaultSegmentTimescale)
                )
                self.extractSentence(forTrackTime: nextTime) { sentence in
                    onCompletionHandler(sentence)
                }
                break
            }
        }
        
    }
    
    func getSegment(type: SegmentPosition) -> ExpressionSegment? {
        let currentTime = player.currentTime()
        let currentSegment = self.getSegment(forTrackTime: currentTime)
        var result: ExpressionSegment?
        if let segment = currentSegment {
            switch type {
            case .current:
                result = segment
                break
            case .previous:
                if let currentSegmentIndex = getSegmentIndex(segment: segment), currentSegmentIndex > 0 {
                    result = expressionSegments[currentSegmentIndex - 1]
                }
                break
            case .next:
                if let currentSegmentIndex = getSegmentIndex(segment: segment), currentSegmentIndex + 1 < expressionSegments.count {
                    result = expressionSegments[currentSegmentIndex + 1]
                }
                break
            }
        }

        return result
    }
    
    func getSegment(forTrackTime: CMTime) -> ExpressionSegment? {
        var segment: ExpressionSegment?
        for seg in expressionSegments {
            if seg.timeMapping.source.containsTime(forTrackTime) {
                segment = seg
            }
        }
        
        return segment
    }
    
    private func getSegmentIndex(segment: ExpressionSegment) -> Int? {
        if segment.getIndex() != Int(Utils.UNKNOWN) {
            return segment.getIndex()
        } else {
            for (index, s) in expressionSegments.enumerated() {
                if (s == segment) {
                    return index
                }
            }
        }
        
        return nil
    }
    
    // We use .lowercased() throughout the method because sometimes word is made uppercase if we have PunctuationSuggestions on which will capitalize on-demand
    // To elimate this we make everything lowercase
    func getSegmentTextRange(of segment: ExpressionSegment) -> NSRange? {
        var characterRange : NSRange
        let word = segment.getText(
            withTemporalSuggestions: self.withTemporalSuggestions,
            withPunctuationSuggestions: self.withPunctuationSuggestions,
            withFormattingSuggestions: self.withFormattingSuggestions,
            strictlyAsWord: self.withTextStrictlyAsWords
        ).lowercased()
        let text = getExpressionText().lowercased()
        if word.count > 0 && segment.timeMapping.source.start.seconds == 0 {
            characterRange = NSRange(location: 0, length: word.count)
        } else if word.count > 0 {
            let numProcessedChar = text.count - getExpressionText(from: segment.timeMapping.source.start).lowercased().count
            let unprocessedTranscription = text.substring(fromIndex: numProcessedChar).lowercased()
            let substringRange = unprocessedTranscription.range(of: word)
            let numCharToSubstring = unprocessedTranscription.count - unprocessedTranscription[substringRange!.lowerBound..<unprocessedTranscription.endIndex].count
            characterRange = NSRange(location: numProcessedChar + numCharToSubstring, length: word.count)
        } else {
            return nil
        }
        
        return characterRange
    }
    
    func getBackgroundNoise(type: ScaleUnitType = .all, sentenceNumber: Int? = nil, segmentTrackTime: CMTime? = nil) -> Double {
        let numSegments: Double = Double(expressionSegments.count)
        var backgroundNoiseSum: Double = 0
        
        switch type {
        case .all:
            for segment in expressionSegments {
                backgroundNoiseSum += segment.getBackgroundNoise()
            }
            
            return backgroundNoiseSum / numSegments
        case .sentence:
            if let sentenceNumber = sentenceNumber {
                for segment in self.expressionSegments {
                    if segment.getSentence().number == sentenceNumber {
                        backgroundNoiseSum += segment.getBackgroundNoise()
                    }
                }

                return backgroundNoiseSum / numSegments
            }
            return Double(Utils.UNKNOWN)
        case .word:
            if let segmentTrackTime = segmentTrackTime, let segment = self.getSegment(forTrackTime: segmentTrackTime) {
                return segment.getBackgroundNoise()
            }
        }
        
        return Utils.UNKNOWN
    }
    
    func getSoundIntensity(type: ScaleUnitType = .all, sentenceNumber: Int? = nil, segmentTrackTime: CMTime? = nil) -> Double {
        // print("===== Get Sound Intensity =====")
        var numSegments: Double = 0
        var soundIntensitySum: Double = 0
        
        switch type {
        case .all:
            for segment in expressionSegments {
                let intensity = segment.getSoundIntensity()
                if intensity != Double(Utils.UNKNOWN) {
                    soundIntensitySum += intensity
                    numSegments += 1
                }
            }
            
            if numSegments > 0 {
                return (soundIntensitySum / numSegments).rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT)
            }
            
            return Double(Utils.UNKNOWN)
        case .sentence:
            if let sentenceNumber = sentenceNumber {
                for segment in self.expressionSegments {
                    if segment.getSentence().number == sentenceNumber {
                        let intensity = segment.getSoundIntensity()
                        if intensity != Double(Utils.UNKNOWN) {
                            soundIntensitySum += intensity
                            numSegments += 1
                        }
                    }
                }

                if numSegments > 0 {
                    return (soundIntensitySum / numSegments).rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT)
                }

                return Double(Utils.UNKNOWN)
            }
            return Double(Utils.UNKNOWN)
        case .word:
            if let segmentTrackTime = segmentTrackTime, let segment = self.getSegment(forTrackTime: segmentTrackTime) {
                return segment.getSoundIntensity()
            }
            break
        }
        
        return Utils.UNKNOWN
    }
    
    func getSentimentScore(type: ScaleUnitType = .word, sentenceNumber: Int? = nil, forTrackTime: CMTime? = nil) -> Float {
        print("===== Get Sentiment Score =====")
        if let forTrackTime = forTrackTime, let segment = self.getSegment(forTrackTime: forTrackTime), let sentiment = segment.getSentimentScore(type: type) {
            return sentiment
        }

        return 0
    }
    
    func getDurationListening() -> Float {
        // print("===== Get Duration Listening =====")
        return Float(Date().timeIntervalSince(self.recordStartDate!))
    }
    
    //    func getLocation() {
    //
    //    }
    
    // MARK: - Key-Value Observer
    
    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
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
                print("===== Playing Recording =====")
                let timeScale = CMTimeScale(NSEC_PER_SEC)
                let time = CMTime(seconds: 1, preferredTimescale: timeScale)

                timerObserverToken = player.addPeriodicTimeObserver(forInterval: time, queue: .main) {time in
                    self.handlePeriodicTimeObserver()
                }

                var times = [NSValue]()
                for segment in self.expressionSegments {
                    times.append(NSValue(time: segment.timeMapping.source.start))
                }

                boundaryObserverToken = player.addBoundaryTimeObserver(forTimes: times, queue: .main) {
                    self.handleBoundaryTimeObserver()
                }
                
                completionObserverToken = player.addBoundaryTimeObserver(forTimes: [NSValue(time: self.stopPlaybackAt!)], queue: .main) {
                    self.handleCompletionObserver()
                }
                
                // Start expression
                player.play()
                
                // Set player rate
                let rateWasSet = Utils.setPlayerRate(player: player, rate: self.playbackRate)
                if rateWasSet {
                    print("\tPlayer rate was successfully set...")
                } else {
                    print("\t[Error] There was a problem setting player rate. Player had not been started yet.")
                }
                
                if self.startPlaybackAt! == CMTime.zero {
                    print("\tPlaying from start of recording...")
                    // Check to see if there is a silence at the start we need to skip
                    self.handleBoundaryTimeObserver(start: true)
                } else {
                    print("\tPlaying from \(self.startPlaybackAt!.seconds) seconds ...")
                    player.seek(to: self.startPlaybackAt!)
                }

                if let onStartHandler = self.observerContext["onStartHandler"] {
                    onStartHandler()
                }
            case .failed:
                print("\t[Error] There was a problem making track ready to play: \(self.filename)\(self.fileType)")
                if let error = player.currentItem!.error {
                    print("\tMessage: \(error.localizedDescription)")
                }
                fatalError()
                break
            case .unknown:
                fatalError("\t[Error] Player not ready")
                break
            @unknown default:
                fatalError("\t[Error] Unknown player status received")
            }
        }
    }
    
    func handlePeriodicTimeObserver() {
        DispatchQueue.main.async {
            if let secondElapseHandler = self.observerContext["secondElapseHandler"] {
                secondElapseHandler()
            }
        }
    }
    
    func handleBoundaryTimeObserver(start: Bool = false) {
        let currentSegment = self.getSegment(type: .current)

        if start {
            let segment = self.expressionSegments[0]
            if self.skipPunctuation && segment.isPunctuation(), let nextSegment = self.getSegment(type: .next) {
                // skip to next segment
                self.previousBoundarySegment = currentSegment
                self.player.seek(
                    to: nextSegment.timeMapping.source.start,
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )
                // print("===== Stumbled on Punctuation and skipped it =====")
            } else if self.skipSilence && segment.isSilence(), let nextSegment = self.getSegment(type: .next) {
                // skip to next segment
                self.previousBoundarySegment = currentSegment
                self.player.seek(
                    to: nextSegment.timeMapping.source.start,
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )
                // print("===== Stumbled on Silence and skipped it =====")
            } else {
                self.previousBoundarySegment = currentSegment
            }
            
            self.observerContext["segmentBoundaryHandler"]?()
        } else if currentSegment == self.expressionSegments.last! {
            // last segment of expression
            // We want to put it just before end
            let segment = self.expressionSegments.last!
            let END_BUFFER_DURATION = 0.05 // makes sure we don't seek to the exact end which causes the completion observer not to run
            if self.skipPunctuation && segment.isPunctuation() {
                // skip to next segment
                self.previousBoundarySegment = currentSegment
                self.player.seek(
                    to: CMTimeMake(
                        value: Int64(Expression.defaultSegmentTimescale * (self.player.currentItem!.duration.seconds - END_BUFFER_DURATION)),
                        timescale: Int32(Expression.defaultSegmentTimescale)
                    ),
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )
                // print("===== Stumbled on Punctuation and skipped it =====")
            } else if self.skipSilence && segment.isSilence() {
                // skip to next segment
                self.previousBoundarySegment = currentSegment
                self.player.seek(
                    to: CMTimeMake(
                        value: Int64(Expression.defaultSegmentTimescale * (self.player.currentItem!.duration.seconds - END_BUFFER_DURATION)),
                        timescale: Int32(Expression.defaultSegmentTimescale)
                    ),
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )
                // print("===== Stumbled on Silence and skipped it =====")
            } else {
                self.previousBoundarySegment = currentSegment
            }
            
            self.observerContext["segmentBoundaryHandler"]?()
        } else if let segment = currentSegment {
            // We do an equality check with the previous boundary to make sure we are strictly moving
            // forward and not stuck in loop of playing an older segment
            if let previousBoundarySegment = self.previousBoundarySegment, currentSegment != previousBoundarySegment && self.skipPunctuation && segment.isPunctuation(), let nextSegment = self.getSegment(type: .next) {
                // skip to next segment
                self.previousBoundarySegment = currentSegment
                self.player.seek(
                    to: nextSegment.timeMapping.source.start,
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )
                // print("===== Stumbled on Punctuation and skipped it =====")
            } else if let previousBoundarySegment = self.previousBoundarySegment, currentSegment != previousBoundarySegment && self.skipSilence && segment.isSilence(), let nextSegment = self.getSegment(type: .next) {
                // skip to next segment
                self.previousBoundarySegment = currentSegment
                self.player.seek(
                    to: nextSegment.timeMapping.source.start,
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )
                // print("===== Stumbled on Silence and skipped it =====")
            } else {
                self.previousBoundarySegment = currentSegment
            }
            
            self.observerContext["segmentBoundaryHandler"]?()
        }
    }
    
    func handleCompletionObserver() {
        print("===== Completed Recording =====")
        // Stop Playing
        self.player.stop()
        self.startPlaybackAt = nil
        self.startPlaybackAt = nil
        
        // Play Finish Handler if present
        self.observerContext["onFinishHandler"]?()
        
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
    }
}

// MARK: - Speech Recognition Delegate Extension

extension Expression: SFSpeechRecognitionTaskDelegate {
    func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {
        print("===== System is no longer accepting new speech input =====")
    }
    
    func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {
        print("===== Expression cancelled looking listening for new speech ===== ")
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        print("===== Expression successfully finished listening for new speech ===== ")
        if !self.isListening && !self.useOnDeviceRecognition {
            self.onExpressionComplete?()
        } else if !self.isListening && self.useOnDeviceRecognition {
            // Completion of speech recognition section
            self.onExpressionComplete?()
        }
        
        // Play sound
        sounds.saveExpression()
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        DispatchQueue.main.async {
            if self.isListening {
                print("===== Received hypothesis transcription: ", transcription.formattedString)
                self.performTranscriptionUpdate(transcription)
            }
        }
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition result: SFSpeechRecognitionResult) {
        DispatchQueue.main.async {
            if self.isListening && !self.request!.requiresOnDeviceRecognition {
                print("===== Some words heard. Apple servers ended dictation session =====")
                self.stopListeningForSpeech(pause: true) {[weak self] in
                    self?.performTranscriptionUpdate(result.bestTranscription, finalTranscript: true)
                    self?.normalizeSegments()
                    // Update duration
                    self?.accumulatedDuration = max(0, Date().timeIntervalSince(self!.recordStartDate!) - TRANSCRIPTION_LATENCY_DURATION)
                    self?.startListeningForSpeech(
                        soundIntensityHandler: self?.soundIntensityHandler,
                        onStartHandler: self?.onListeningStartHandler
                    )
                    
                    // Play Sound
                    sounds.commitBuffer()
                }
            } else if self.isListening && self.request!.requiresOnDeviceRecognition {
                self.performTranscriptionUpdate(result.bestTranscription, finalTranscript: true)
                self.normalizeSegments()
                // Update duration
                self.accumulatedDuration = max(0, Date().timeIntervalSince(self.recordStartDate!) - TRANSCRIPTION_LATENCY_DURATION)
                // print("===== A contiguous clause was completed: \(self.expressionSegments)")
                
                // Play Sound
                sounds.commitBuffer()
                
                // Echo formatted String
                if AVAudioSession.isHeadphonesConnected {
                    self.echoText(text: result.bestTranscription.formattedString)
                }
            } else {
                // Only the on-server recognition should go here in theory
                self.performTranscriptionUpdate(result.bestTranscription, finalTranscript: true)
                self.normalizeSegments()
                // print("===== Completed expression: \(self.expressionSegments)")
                
                // Play Sound
                sounds.commitBuffer()
            }
        }
    }
    
    func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        print("===== System has detected first incident of speech input =====")
    }
}

// MARK: - Speech Synthesizer Delegate Extension

extension Expression: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("===== Speech synthesis was cancelled =====")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("===== Paused speech synthesis successfully instructed to continue =====")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully completed =====")
        self.onEchoFinish?()
        self.tempOnEchoFinish?()
        self.tempOnEchoFinish = nil
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully paused =====")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully started =====")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        if !self.isListening {
            self.onEchoUpdate?(characterRange)
        }
    }
}

// MARK: - Pitch Recognition Delegate Extension

extension Expression: PitchEngineDelegate {
    func pitchEngine(_ pitchEngine: PitchEngine, didReceivePitch pitch: Pitch) {
        // TODO: Timing
        // print("Pitch { \n\tpitch: \(pitch.note.string) \n\tfrequency: \(pitch.frequency)\n}")
        let pitchDatum = PitchDatum(date: Date(), pitch: pitch)
        self.pitchStream.append(pitchDatum)
    }

    func pitchEngine(_ pitchEngine: PitchEngine, didReceiveError error: Error) {
        // print("===== Pitch Error: \(error.localizedDescription)")
    }

    public func pitchEngineWentBelowLevelThreshold(_ pitchEngine: PitchEngine) {
        // print("===== Pitch Engine below level threshold =====")
    }
}

// Useful Links:

// Transcription: https://developer.apple.com/documentation/speech/sftranscription
// Segment: https://developer.apple.com/documentation/speech/sftranscriptionsegment

// Behavior
// App should continue to record when the phone is locked.

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

// MIDI Sequencing:

// ===== SpeechRecognition =====

// ** There are throttling limits **
// Per device per day
// Per app per day (global limitations for all users of your app) - 1000 calls an hour across apps on a single device = 4 calls every 15 seconds => very generous
// Error Code: 203
// https://developer.apple.com/library/archive/qa/qa1951/_index.html
// One minute limitation for a single utterance (from start to end of a recognition task)

// ===== On Device Recognition =====
// There is no continuous learning like you have on the Cloud. This can lead to less accuracy on the device. Moreover, the language support is limited to about 10 languages currently.
// lets you do speech recognition for an unlimited amount of time

// iOS 13 SFSpeechRecognizer is smart enough to recognize punctuations in your speech.
// how many users have iOS 13?

// ===== Pitch Recognition =====
// We use Beethoven to conduct pitch recognition: https://github.com/vadymmarkov/Beethoven
// Theory: https://medium.com/@neurodatalab/pitch-tracking-or-how-to-estimate-the-fundamental-frequency-in-speech-on-the-examples-of-praat-fe0ca50f61fd

// Adult Male Vocal Range: Bass = E2 - F4 , Baritone = G2 - Ab4, Tenor = Bb2 - C5
// Adult Female Vocal Range: Alto = F3 - A5, Soprano = A3 - C6
// Source: https://www.quora.com/What-is-the-average-vocal-range-for-an-adult-male-and-for-an-adult-female#:~:text=Adult%20male%20professional%20singers%20may%20have%20up%20to%20three%20octave,and%20Contraltos%20may%20have%20less.
// Speaking: https://en.wikipedia.org/wiki/Voice_frequency
// Male: [85, 180]
// Female: [165, 255]
