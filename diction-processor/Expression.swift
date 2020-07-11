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
    // MARK: - Composition Properties
    private(set) var expressionSegments = [ExpressionSegment]()
    /// Supplies information about the speaker.
    private(set) var speaker: Speaker
    static let defaultSegmentTimescale = Double(10000)
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
    public override var duration: CMTime {
        return self.expressionSegments.last!.timeMapping.source.end
    }
    private(set) var withSpaceSuggestions: Bool
    private(set) var withPunctuationSuggestions: Bool
    private(set) var withFormattingSuggestions: Bool
    private(set) var withTextStrictlyAsWords: Bool
    weak private(set) var vc: ViewController?
    private(set) var onListenUpdate: (() -> Void)?
    private(set) var onExpressionComplete: (() -> Void)?
    private var observerContext = [String: (() -> Void)]()
    
    // MARK: - Recording Properties
    var recordingSession = AVAudioSession.sharedInstance()
    private(set) var isListening = false
    let recordBus = 0
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
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // MARK: - Speech Synthesis Properties
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var synthesizerVoice : AVSpeechSynthesisVoice? {
        return Utils.getSynthesizerVoice(withGender: speaker.gender, vc: vc)
    }
    var defaultVolume = Float(1.0)
    public var isPlayingEcho: Bool {
        return speechSynthesizer.isSpeaking
    }
    public var echoIsPaused: Bool {
        return speechSynthesizer.isPaused
    }
    private(set) var onEchoFinish: (() -> Void)?
    private(set) var onEchoUpdate: ((_ range: NSRange) -> Void)?
    
    // MARK: - Audio Playback Properties
    private(set) var player = AVPlayer()
    private let playbackBus = 1
    public let minDb: Float
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
    
    // MARK: - Initializer

    init(
        vc: ViewController,
        speaker: Speaker,
        minDb: Float,
        withDeviceRecognition: Bool,
        withSpaceSuggestions: Bool = false,
        withPunctuationSuggestions: Bool = false,
        withFormattingSuggestions: Bool = false,
        withTextStrictlyAsWords: Bool = false,
        onListenUpdate: (() -> Void)? = nil,
        onEchoFinish: (() -> Void)? = nil,
        onEchoUpdate: ((_ range: NSRange) -> Void)? = nil,
        onExpressionComplete: (() -> Void)? = nil
    ) {
        self.speaker = speaker
        self.minDb = minDb
        self.useOnDeviceRecognition = withDeviceRecognition
        self.vc = vc
        self.onListenUpdate = onListenUpdate
        self.onEchoFinish = onEchoFinish
        self.onEchoUpdate = onEchoUpdate
        self.onExpressionComplete = onExpressionComplete
        self.withSpaceSuggestions = withSpaceSuggestions
        self.withPunctuationSuggestions = withPunctuationSuggestions
        self.withFormattingSuggestions = withFormattingSuggestions
        self.withTextStrictlyAsWords = withTextStrictlyAsWords

        super.init()

        // Ask for permissions
        self.requestPermissions()

        // Add track
        self.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: Int32(kCMPersistentTrackID_Invalid)
        )
        
        // Assign delegates
        speechSynthesizer.delegate = self
        
        // Configure Audio Write File
        self.configureAudioWriteFile()
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
        do {
            try recordFile = AVAudioFile(forWriting: Utils.getFileURL(of: "expression.caf"), settings: audioEngine.inputNode.inputFormat(forBus: recordBus).settings)
        } catch {
            print("===== Error instantiating record file =====")
        }
    }
    
    // MARK: - Speech Listening Methods
    
    func startListeningForSpeech(soundIntensityHandler: ((_ intensity: Double?) -> Void)? = nil, onStartHandler: (() -> Void)? = nil) {
        print("===== Starting Listening for Speech =====")
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
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request!.shouldReportPartialResults = true
        request!.requiresOnDeviceRecognition = false
        
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
                print("===== Error writing speech to file =====")
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch let error {
            print("[Error] There was a problem starting speech recognition: \(error.localizedDescription)")
        }
        
        do {
            // it’s generally preferable to defer this call until your app begins audio playback
            try recordingSession.setActive(true)
        } catch {
            print("===== Unable to activate audio session =====")
        }
        
        guard let myRecognizer = SFSpeechRecognizer() else {
            print("===== Speech Recognizer is not supported for current locale =====")
            return
        }
        
        if useOnDeviceRecognition && myRecognizer.supportsOnDeviceRecognition {
            print("===== Using On-Device Recognition =====")
            request!.requiresOnDeviceRecognition = true
        }
        
        if !myRecognizer.isAvailable {
            print("===== Speech Recognizer is not available =====")
            return
        }
        
        speechRecognizer?.defaultTaskHint = .dictation
        recognitionTask = speechRecognizer?.recognitionTask(with: request!, delegate: self)
    }
    
    func stopListeningForSpeech(pause: Bool = false, onStopHandler: (() -> Void)? = nil) {
        print("===== Stopping Listening for Speech =====")
        if isListening && !pause {
            isListening = false
        }
        
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
    
    func performTranscriptionUpdate(_ transcription: SFTranscription, final: Bool = false) {
        print("===== Transcription Update: ", transcription.formattedString)
        var lowerStagingIndex: Int = -1
        for (index, segment) in expressionSegments.enumerated() {
            if segment.timeMapping.source.duration.seconds == DEFAULT_SEGMENT_DURATION {
                lowerStagingIndex = index
                break
            }
        }

        if final {
            var segments = self.expressionSegments
            segments.removeSubrange(lowerStagingIndex..<segments.count)
            do {
                try self.tracks[0].validateSegments(segments)
                self.tracks[0].segments = segments
                self.expressionSegments = segments
                print("===== Successfully validated and updated expression shortened segments array =====")
            } catch {
                print("===== Error removing temporary segments =====")
            }
        }
        
        for (index, segment) in transcription.segments.enumerated() {
            processTranscriptSegment(segment: segment, transcriptionIndex: index, lowerStagingIndex: lowerStagingIndex, transcription: transcription, final: final)
        }

        onListenUpdate?()
    }
    
    func processTranscriptSegment(segment: SFTranscriptionSegment, transcriptionIndex: Int, lowerStagingIndex: Int, transcription: SFTranscription, final: Bool) {
        // Create Expression Segment
        var segments = self.expressionSegments
        
        // Manage NLP
        var segmentTags: [String : NLTag?]
        var sentiment: [ScaleUnitType: Float]?
        if lowerStagingIndex == -1 || transcriptionIndex >= (segments.count - lowerStagingIndex) {
             // New segment, compute values
            (segmentTags, sentiment) = computeSegmentTags(transcription: transcription, lowerStagingIndex: lowerStagingIndex, transcriptionIndex: transcriptionIndex)
        } else if transcriptionIndex < (segments.count - lowerStagingIndex) {
            // existing segment, get values
            let existingSegment = self.expressionSegments[lowerStagingIndex + transcriptionIndex]
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
            print("Error computing Segment Tags")
            fatalError()
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
            if lowerStagingIndex == -1 {
                // First temporary segment
                timestamp = 0
                duration = floor(Expression.defaultSegmentTimescale * DEFAULT_SEGMENT_DURATION)
            } else {
                let processedSeconds: Double = segments[lowerStagingIndex].timeMapping.source.start.seconds
                timestamp = floor(Expression.defaultSegmentTimescale * (processedSeconds + Double(transcriptionIndex) * DEFAULT_SEGMENT_DURATION))
                duration = floor(Expression.defaultSegmentTimescale * DEFAULT_SEGMENT_DURATION)
            }
        } else {
            // enters here when we get the final transcript which has timestamp data
            timestamp = accumulatedDuration + segment.timestamp > 0 ? floor(Expression.defaultSegmentTimescale * (accumulatedDuration + segment.timestamp)) : 0
            duration = segment.duration > 0 ? floor(Expression.defaultSegmentTimescale * segment.duration) : 0
        }
        
        let phoneticallySimilarWords = segment.alternativeSubstrings
        
        let expressionSegment = ExpressionSegment(
            expression: self,
            word: word,
            trackURL: Utils.getFileURL(of: "expression.caf"),
            trackID: self.tracks[0].trackID,
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
        
        if lowerStagingIndex == -1 || transcriptionIndex >= (segments.count - lowerStagingIndex) {
            // New segment, append to speechSegments
            segments.append(expressionSegment)
            self.expressionSegments = segments
        } else if transcriptionIndex <= (segments.count - lowerStagingIndex) {
            // Existing segment, overwrite old copy
            // This assumes the new version is a better approximation of user speech
            let oldSegment = segments[lowerStagingIndex + transcriptionIndex]
            if oldSegment != expressionSegment {
                segments[lowerStagingIndex + transcriptionIndex] = expressionSegment
                self.expressionSegments = segments
            } else {
                // print("Existing segment without changes encountered.")
            }
        } else {
            print("oops: ", index, segments.count, lowerStagingIndex)
            fatalError()
        }
    }
    
    // We set sound intensity here because its when we with certainty have correct time data with pauses factored in
    // We set background noise here because we can identify all the silences
    // We set sentence numbers here because we've built up the entire expression and can compute sentences factoring it all
    // This is where correct values for avgPauseDuration and speakingRate are set
    func normalizeSegments() {
        print("===== Normalizing Segments =====")
        var lastEnd = CMTime.zero
        var segments = self.expressionSegments
        var normalizedSegments = [ExpressionSegment]()
        var silenceIndices = [Int]()
        
        for (index, segment) in segments.enumerated() {
            if segment.timeMapping.source.start.seconds != lastEnd.seconds {
                // Add a segment in the first position to account for early time
                if segment.timeMapping.source.start.seconds > lastEnd.seconds {
                    let silentSegment = ExpressionSegment(
                        expression: self,
                        word: "",
                        trackURL: Utils.getFileURL(of: "expression.caf"),
                        trackID: self.tracks[0].trackID,
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
                    
                    // Add sound intensities
                    let middleOfSilenceDuration: Double = lastEnd.seconds
                    let backgroundNoise = getRecordingSoundIntensity(timestamp: middleOfSilenceDuration)
                    silentSegment.setSoundIntensity(intensity: backgroundNoise.intensity.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                    // print("Silence Sound Intensity: \(backgroundNoise.intensity)")
                    let middleOfSegmentDuration: Double = segment.timeMapping.source.start.seconds
                    let soundIntensity = getRecordingSoundIntensity(timestamp: middleOfSegmentDuration)
                    segment.setSoundIntensity(intensity: soundIntensity.intensity.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                    // print("Segment Sound Intensity: \(soundIntensity.intensity)")
                    // Add pitch
                    let pitch = getRecordingPitch(timestamp: middleOfSegmentDuration)
                    segment.setPitch(pitch: pitch.pitch)
                    // print("Segment Pitch: \(pitch.pitch)")
                    
                    // Save silence index
                    silenceIndices.append(normalizedSegments.count)
                    // print("Found silence: \(silentSegment.timeMapping.source.duration.seconds)")
                    
                    // Add to segments array
                    normalizedSegments.append(silentSegment)
                    normalizedSegments.append(segment)
                    
                    // Update last end value
                    lastEnd = segment.timeMapping.source.end
                } else if segment.timeMapping.source.start.seconds < lastEnd.seconds && index != 0 {
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
                    
                    let middleOfSegmentDuration: Double = lastEnd.seconds
                    
                    // Sound Intensity
                    if segment.getSoundIntensity() != Utils.UNKNOWN {
                        // Import sound intensity
                        let soundIntensity = segment.getSoundIntensity()
                        normalizedSegment.setSoundIntensity(intensity: soundIntensity)
                    } else {
                        // Add sound intensities
                        let soundIntensity = getRecordingSoundIntensity(timestamp: middleOfSegmentDuration)
                        segment.setSoundIntensity(intensity: soundIntensity.intensity.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                    }
                    
                    // Background Intensity
                    if segment.getBackgroundNoise() != Utils.UNKNOWN {
                        // Import background noise
                        let backgroundNoise = segment.getBackgroundNoise()
                        normalizedSegment.setBackgroundNoise(noise: backgroundNoise)
                    }
                    
                    // Pitch
                    if let pitch = segment.getPitch() {
                        // Import pitch
                        normalizedSegment.setPitch(pitch: pitch)
                    } else {
                        // Add pitch
                        let pitch = getRecordingPitch(timestamp: middleOfSegmentDuration)
                        segment.setPitch(pitch: pitch.pitch)
                    }
                    
                    // Average Pause Duration
                    if segment.getAvgPauseDuration() != Utils.UNKNOWN {
                        // Import average pause duration
                        let avgPauseDuration = segment.getAvgPauseDuration()
                        normalizedSegment.setAvgPauseDuration(duration: avgPauseDuration)
                    }
                    
                    // Speaking Rate
                    if segment.getSpeakingRate() != Utils.UNKNOWN {
                        // Import speaking  rate
                        let speakingRate = segment.getSpeakingRate()
                        normalizedSegment.setSpeakingRate(rate: speakingRate)
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
                } else {
                    // Add sound intensities
                    let soundIntensity = getRecordingSoundIntensity(timestamp: middleOfSegmentDuration)
                    segment.setSoundIntensity(intensity: soundIntensity.intensity.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                }
                
                // Background Intensity
                if segment.getBackgroundNoise() != Utils.UNKNOWN {
                    // Import background noise
                    let backgroundNoise = segment.getBackgroundNoise()
                    segment.setBackgroundNoise(noise: backgroundNoise)
                }
                
                // Pitch
                if let pitch = segment.getPitch() {
                    // Import pitch
                    segment.setPitch(pitch: pitch)
                } else {
                    // Add pitch
                    let pitch = getRecordingPitch(timestamp: middleOfSegmentDuration)
                    segment.setPitch(pitch: pitch.pitch)
                }
                
                // Average Pause Duration
                if segment.getAvgPauseDuration() != Utils.UNKNOWN {
                    // Import average pause duration
                    let avgPauseDuration = segment.getAvgPauseDuration()
                    segment.setAvgPauseDuration(duration: avgPauseDuration)
                }
                
                // Speaking Rate
                if segment.getSpeakingRate() != Utils.UNKNOWN {
                    // Import speaking  rate
                    let speakingRate = segment.getSpeakingRate()
                    segment.setSpeakingRate(rate: speakingRate)
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
        
        // Compute sentences
        var sentences = [Sentence]()
        var sentenceNumber = 0
        var sentenceStartTime = CMTime.zero
        var sentenceEndTime: CMTime
        // Holds the index of the first segment without a sentence
        var lastUpdatedSegmentIndex = 0
        // make sure silences get sentence number of prior.
        for (index, segment) in normalizedSegments.enumerated() {
            // Set segment index
            segment.setIndex(index: index)
            
            // Set background noise
            if segment.getBackgroundNoise() == Double(Utils.UNKNOWN) {
                segment.setBackgroundNoise(noise: backgroundNoise)
            }
            
            // Set avgPauseDuration
            if segment.getAvgPauseDuration() == Double(Utils.UNKNOWN) {
                segment.setAvgPauseDuration(duration: avgPauseDuration)
            }
            
            // Set speakingRate
            if segment.getSpeakingRate() == Double(Utils.UNKNOWN) {
                segment.setSpeakingRate(rate: speakingRate)
            }

            if index + 1 == normalizedSegments.count {
                // We've reached the end of the expression. Update sentence data
                // print("We've reached the end of the expression. Update sentence data")
                
                sentenceEndTime = segment.timeMapping.source.end
                let sentence = Sentence(
                    number: sentenceNumber,
                    timeRange: CMTimeRangeFromTimeToTime(
                        start: sentenceStartTime,
                        end: sentenceEndTime
                    )
                )
                
                // Add sentence to every segment ***including*** this one
                for i in lastUpdatedSegmentIndex...index {
                    normalizedSegments[i].setSentence(sentence: sentence)
                }
                
                // Add sentence to sentence Array
                sentences.append(sentence)
                // print("added new sentence: \(sentence), \(sentences)")
            } else if segment.isSilence() {
                if index > 0 && !normalizedSegments[index - 1].isSentenceTerminator() {
                    // Do nothing
                } else if index > 0 && normalizedSegments[index - 1].isSentenceTerminator() {
                    // We've hit a sentence boundary. Update sentences
                    // print("We've hit a sentence boundary. Update sentence data")
                    // Update sentence data
                    sentenceEndTime = segment.timeMapping.source.start
                    let sentence = Sentence(
                        number: sentenceNumber,
                        timeRange: CMTimeRangeFromTimeToTime(
                            start: sentenceStartTime,
                            end: sentenceEndTime
                        )
                    )
                    sentenceNumber += 1
                    sentenceStartTime = segment.timeMapping.source.start
                    
                    // Add sentence to every segment before this one
                    for i in lastUpdatedSegmentIndex..<index {
                        normalizedSegments[i].setSentence(sentence: sentence)
                    }
                    lastUpdatedSegmentIndex = index
                    
                    // Add sentence to sentence Array
                    sentences.append(sentence)
                    // print("added new sentence: \(sentence), \(sentences)")
                }
            } else if !segment.isSilence() {
                // We can't let silences in here because getSentenceNumber can't handle empty strings
                let number = getSentenceNumber(segments: normalizedSegments, segment: segment, index: index)
                
                if number != sentenceNumber && number == sentenceNumber + 1 {
                    // We've hit a sentence boundary. Update sentences
                    // print("We've hit a sentence boundary. Update sentence data")
                    // Update sentence data
                    sentenceEndTime = segment.timeMapping.source.start
                    let sentence = Sentence(
                        number: sentenceNumber,
                        timeRange: CMTimeRangeFromTimeToTime(
                            start: sentenceStartTime,
                            end: sentenceEndTime
                        )
                    )
                    sentenceNumber = number
                    sentenceStartTime = segment.timeMapping.source.start
                    
                    // Add sentence to every segment before this one
                    for i in lastUpdatedSegmentIndex..<index {
                        normalizedSegments[i].setSentence(sentence: sentence)
                    }
                    lastUpdatedSegmentIndex = index
                    
                    // Add sentence to sentence Array
                    sentences.append(sentence)
                    // print("added new sentence: \(sentence), \(sentences)")
                } else if number == sentenceNumber {
                    // Do nothing
                } else {
                    print("We have hit a state we shouldn't hit. Number and Sentence Number are not the same, but differ more than by 1")
                }
            }
        }
        
        // print("Sentence Array: \(sentences)")
        segments = normalizedSegments
        do {
            try self.tracks[0].validateSegments(segments)
            self.tracks[0].segments = segments
            self.expressionSegments = segments
            print("===== Successfully normalized and updated expression segments =====")
        } catch {
            print("===== Error updatings expression segments in normalize segments =====")
        }
    }
    
    // MARK: - Listening Method Helpers
    
    func computeSegmentTags(transcription: SFTranscription, lowerStagingIndex: Int, transcriptionIndex: Int) -> ([String : NLTag?], [ScaleUnitType: Float]) {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .tokenType, .sentimentScore, .lemma])
        let segmentText = transcription.segments[transcriptionIndex].substring
        
        var index: Int
        if lowerStagingIndex == -1 || transcriptionIndex > (self.expressionSegments.count - lowerStagingIndex) {
            // New segment, append to speechSegments
            index = self.expressionSegments.count
        } else if transcriptionIndex <= (self.expressionSegments.count - lowerStagingIndex) {
            // Existing segment, overwrite old copy
            // This assumes the new version is a better approximation of user speech
            index = lowerStagingIndex + transcriptionIndex
        } else {
            print("oops: ", transcriptionIndex, self.expressionSegments.count, lowerStagingIndex)
            fatalError()
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
    
    func getSentenceNumber(segments: [ExpressionSegment], segment: ExpressionSegment, index: Int) -> Int {
        if segment.isSilence() || segment.getLexicalClass() == .otherWhitespace || segment.getLexicalClass() == .paragraphBreak {
            return Int(Utils.UNKNOWN)
        }
        
        // Contants
        let word = segment.getText(
            withSpaceSuggestions: self.withSpaceSuggestions,
            withPunctuationSuggestions: self.withPunctuationSuggestions,
            withFormattingSuggestions: self.withFormattingSuggestions,
            strictlyAsWord: self.withTextStrictlyAsWords
        )
        let wholeText = self.getExpressionText()
        
        // Return Value
        var sentenceNumber = -1
        
        // Find segment index
        var segmentStartIndex : String.Index
        if word.count > 0 && segment.timeMapping.source.start.seconds == 0 {
            segmentStartIndex = word.index(word.startIndex, offsetBy: word.count / 2)
        } else if word.count > 0 {
            let segmentRange = findSegmentRange(segments: segments, wholeText: wholeText, segmentText: word, index: index)
            segmentStartIndex = segmentRange.lowerBound
        } else {
            return sentenceNumber
        }
        
        // Compute Sentences
        var sentenceRanges = [Range<String.Index>]()
        wholeText.enumerateSubstrings(in: wholeText.startIndex..., options: [.bySentences]) { (_, range, _, _) in
            sentenceRanges.append(range)
        }
        
        // Find sentence number
        for (index, range) in sentenceRanges.enumerated() {
            if range.contains(segmentStartIndex) {
                sentenceNumber = index
            }
        }
        
        return sentenceNumber
    }
    
    // Can't handle empty strings for segmentText
    func findSegmentRange(segments: [ExpressionSegment], wholeText: String, segmentText: String, index: Int) -> Range<String.Index> {
        var lowerText: String
        // figure out how many words are before it
        // compute number of processedChar
        if index >= segments.count && index - segments.count <= 1 {
            // new segment
            lowerText = self.getExpressionText()
        } else if index < segments.count && index > 0 {
            // is in in expressionSegments
            let lowerBoundarySegment = segments[index - 1]
            lowerText = self.getExpressionText(until: lowerBoundarySegment.timeMapping.source.start, segments: segments)
        } else if index == 0 && segments.count == 0 {
            // is first segment
            lowerText = ""
        } else {
            print("index error: ", index, segments.count)
            fatalError()
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
    
    func getExpressionText(from time: CMTime = CMTime.zero, forEcho: Bool = false) -> String {
        var text = ""

        for segment in expressionSegments  {
            if segment.timeMapping.source.start >= time {
                let word = segment.getText(
                    withSpaceSuggestions: self.withSpaceSuggestions,
                    withPunctuationSuggestions: self.withPunctuationSuggestions,
                    withFormattingSuggestions: self.withFormattingSuggestions,
                    strictlyAsWord: self.withTextStrictlyAsWords,
                    withSpacePrefix: true,
                    forEcho: forEcho
                )
                
                text += word
            }
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return text
    }
    
    // We need to deal with segments from different places
    func getExpressionText(until time: CMTime, segments: [ExpressionSegment]?, forEcho: Bool = false) -> String {
        var text = ""
        
        var expressionSegments = self.expressionSegments
        if let segments = segments {
            expressionSegments = segments
        }
        
        for segment in expressionSegments  {
            if segment.timeMapping.source.start <= time {
                let word = segment.getText(
                    withSpaceSuggestions: self.withSpaceSuggestions,
                    withPunctuationSuggestions: self.withPunctuationSuggestions,
                    withFormattingSuggestions: self.withFormattingSuggestions,
                    strictlyAsWord: self.withTextStrictlyAsWords,
                    withSpacePrefix: true,
                    forEcho: forEcho
                )
                
                text += word
            }
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return text
    }
    
    // MARK: - Player Methods
    
    func play(onStartHandler: (() -> Void)? = nil, secondElapseHandler: (() -> Void)? = nil, segmentBoundaryHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
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
        
        if player.currentItem == nil, let snapshot = self.copy() as? AVAsset {
            print("===== Initiate AVPlayer =====")
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
            
            player = AVPlayer(playerItem: playerItem)
        } else if player.status != .readyToPlay {
            // just wait for item to be ready
            print("===== Just wait for AVPlayerItem to be ready =====")
        } else {
            print("===== Play item =====")
            player.play()
            onStartHandler?()
        }
    }
    
    func playSentence(number: Int, onStartHandler: (() -> Void)? = nil, secondElapseHandler: (() -> Void)? = nil, segmentBoundaryHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
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

        // Generate sentence object
        let sentence = getSentence(number: number)
        
        if let sentence = sentence, player.currentItem == nil, let snapshot = sentence.copy() as? AVAsset {
            print("===== Initiate AVPlayer =====")
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
            
            player = AVPlayer(playerItem: playerItem)
        } else if player.status != .readyToPlay {
            // just wait for item to be ready
            print("===== Just wait for AVPlayerItem to be ready =====")
        } else {
            print("===== Play item =====")
            player.play()
            onStartHandler?()
        }
    }
    
    func playSentence(forTrackTime: CMTime, onStartHandler: (() -> Void)? = nil, secondElapseHandler: (() -> Void)? = nil, segmentBoundaryHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
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
        
        // Generate sentence object
        let sentence = getSentence(forTrackTime: forTrackTime)
        
        if let sentence = sentence, player.currentItem == nil, let snapshot = sentence.copy() as? AVAsset {
            print("===== Initiate AVPlayer =====")
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
            
            player = AVPlayer(playerItem: playerItem)
        } else if player.status != .readyToPlay {
            // just wait for item to be ready
            print("===== Just wait for AVPlayerItem to be ready =====")
        } else {
            print("===== Play item =====")
            player.play()
            onStartHandler?()
        }
    }
    
    func replayCurrentSentence(handler: (() -> Void)? = nil) {
        let currentTime = player.currentTime()
        let currentSegment = self.getSegment(forTrackTime: currentTime)
        if let segment = currentSegment {
            playSentence(number: segment.getSentence().number)
        }
    }
    
    func pause(handler: (() -> Void)? = nil) {
        player.pause()
        handler?()
    }
    
    // MARK: - Echo Methods
    
    func startEcho(handler: (() -> Void)? = nil) {
        // Computer understanding of the expression
        print("==== Initiate new speech synthesizer utterance =====")
        let expressionText = self.getExpressionText(forEcho: false) // make forEcho true when we're doing voice only
        let utterance = AVSpeechUtterance(string: expressionText)
        if let voice = synthesizerVoice {
            utterance.voice = voice
        }
        utterance.rate = (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) / 2 + AVSpeechUtteranceMinimumSpeechRate
        utterance.volume = defaultVolume
        speechSynthesizer.speak(utterance)
        
        if player.isPlaying {
            print("===== Stop speech audio to play speech synthesizer =====")
            player.stop()
        }
    
        handler?()
    }
    
    func pauseEcho(handler: (() -> Void)? = nil) {
        speechSynthesizer.pauseSpeaking(at: .immediate)
        handler?()
    }
    
    func continueEcho(handler: (() -> Void)? = nil) {
        speechSynthesizer.continueSpeaking()
        handler?()
    }
    
    func stopEcho(handler: (() -> Void)? = nil) {
        handler?()
    }
    
    // MARK: - Setters
    
    func setGender(as gender: Gender) {
        speaker.gender = gender
    }
    
    func setSkipPunctuation(as skip: Bool) {
        self.skipPunctuation = skip
    }
    
    func setSkipSilence(as skip: Bool) {
        self.skipSilence = skip
    }
    
    func setWithSpaceSuggestions(to value: Bool) {
        self.withSpaceSuggestions = value
    }
    
    func setWithPunctuationSuggestions(to value: Bool) {
        self.withPunctuationSuggestions = value
    }
    
    func setWithFormattingSuggestions(to value: Bool) {
        self.withFormattingSuggestions = value
    }
    
    func setWithTextStrictlyAsWords(to value: Bool) {
        self.withTextStrictlyAsWords = value
    }
    
    func setSegments(segments: [ExpressionSegment]) {
        do {
            try self.tracks[0].validateSegments(segments)
            self.expressionSegments = segments
            self.tracks[0].segments = segments
            print("===== Successfully updated expression segments =====")
        } catch {
            print("===== Error updatings expression segments =====")
        }
    }
    
    // MARK: - Getters
    
    func getSentence(number: Int) -> Expression? {
        var sentence: Expression?
        for segment in expressionSegments {
            if segment.getSentence().number == number {
                sentence = segment.getSentenceExpression()
            }
        }
        
        return sentence
    }
    
    func getSentence(forTrackTime: CMTime) -> Expression? {
        var sentence: Expression?
        for segment in expressionSegments {
            if segment.getSentence().timeRange.start <= forTrackTime && segment.getSentence().timeRange.end > forTrackTime {
                sentence = segment.getSentenceExpression()
            }
        }
        
        return sentence
    }
    
    func getSentence(type: SentencePosition) -> Expression? {
        let currentTime = player.currentTime()
        let currentSentence = self.getSentence(forTrackTime: currentTime)
        var result: Expression?
        if let sentence = currentSentence {
            switch type {
            case .current:
                result = sentence
                break
            case .previous:
                let timestamp = floor(Expression.defaultSegmentTimescale * (currentTime.seconds - DIFFERENCE))
                let previousTime = CMTimeMake(
                    value: Int64(timestamp),
                    timescale: Int32(Expression.defaultSegmentTimescale)
                )

                result = self.getSentence(forTrackTime: previousTime)
                break
            case .next:
                let timestamp = floor(Expression.defaultSegmentTimescale * (currentTime.seconds + DIFFERENCE))
                let nextTime = CMTimeMake(
                    value: Int64(timestamp),
                    timescale: Int32(Expression.defaultSegmentTimescale)
                )
                result = self.getSentence(forTrackTime: nextTime)
                break
            }
        }

        return result
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
        for s in expressionSegments {
            if s.timeMapping.source.start <= forTrackTime && s.timeMapping.source.end > forTrackTime {
                segment = s
            }
        }
        // segment = self.tracks[0].segment(forTrackTime: forTrackTime) as? ExpressionSegment
        
        return segment
    }
    
    private func getSegmentIndex(segment: ExpressionSegment) -> Int? {
        for (index, s) in expressionSegments.enumerated() {
            if (s == segment) {
                return index
            }
        }
        
        return nil
    }
    
    // We use .lowercased() throughout the method because sometimes word is made uppercase if we have PunctuationSuggestions on which will capitalize on-demand
    // To elimate this we make everything lowercase
    func getSegmentTextRange(of segment: ExpressionSegment) -> NSRange? {
        var characterRange : NSRange
        let word = segment.getText(
            withSpaceSuggestions: self.withSpaceSuggestions,
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
            if let sentenceNumber = sentenceNumber, let sentence = self.getSentence(number: sentenceNumber){
                for segment in sentence.expressionSegments {
                    backgroundNoiseSum += segment.getBackgroundNoise()
                }
                
                return backgroundNoiseSum / numSegments
            }
        case .word:
            if let segmentTrackTime = segmentTrackTime, let segment = self.getSegment(forTrackTime: segmentTrackTime) {
                return segment.getBackgroundNoise()
            }
        }
        
        return Utils.UNKNOWN
    }
    
    func getSoundIntensity(type: ScaleUnitType = .all, sentenceNumber: Int? = nil, segmentTrackTime: CMTime? = nil) -> Double {
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
                return soundIntensitySum / numSegments
            }
            
            return Double(Utils.UNKNOWN)
        case .sentence:
            if let sentenceNumber = sentenceNumber, let sentence = self.getSentence(number: sentenceNumber) {
                for segment in sentence.expressionSegments {
                    let intensity = segment.getSoundIntensity()
                    if intensity != Double(Utils.UNKNOWN) {
                        soundIntensitySum += intensity
                        numSegments += 1
                    }
                }
                
                if numSegments > 0 {
                    return soundIntensitySum / numSegments
                }
                
                return Double(Utils.UNKNOWN)
            }
            break
        case .word:
            if let segmentTrackTime = segmentTrackTime, let segment = self.getSegment(forTrackTime: segmentTrackTime) {
                return segment.getSoundIntensity()
            }
            break
        }
        
        return Utils.UNKNOWN
    }
    
    func getSentimentScore(type: ScaleUnitType = .word, sentenceNumber: Int? = nil, forTrackTime: CMTime? = nil) -> Float {
        if let forTrackTime = forTrackTime, let segment = self.getSegment(forTrackTime: forTrackTime), let sentiment = segment.getSentimentScore(type: type) {
            return sentiment
        }

        return 0
    }
    
    func getDurationListening() -> Float {
        return Float(Date().timeIntervalSince(self.recordStartDate!))
    }
    
    //    func getLocation() {
    //
    //    }
    
    // MARK: - Key-Value Observer
    
    open override func observeValue(forKeyPath keyPath: String?,
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
                
                completionObserverToken = player.addBoundaryTimeObserver(forTimes: [NSValue(time: player.currentItem!.duration)], queue: .main) {
                    self.handleCompletionObserver()
                }
                
                // Start expression
                player.play()
                // Check to see if there is a silence at the start we need to skip
                self.handleBoundaryTimeObserver(start: true)

                if let onStartHandler = self.observerContext["onStartHandler"] {
                    onStartHandler()
                }
            case .failed:
                print("Failed to make track ready to play")
                break
            case .unknown:
                print("Player not ready")
                break
            @unknown default:
                print("Unknown status received")
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
            
            if let segmentBoundaryHandler = self.observerContext["segmentBoundaryHandler"] {
                segmentBoundaryHandler()
            }
        } else if currentSegment == self.expressionSegments.last! {
            // last segment of expression
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
            
            if let segmentBoundaryHandler = self.observerContext["segmentBoundaryHandler"] {
                segmentBoundaryHandler()
            }
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
            
            if let segmentBoundaryHandler = self.observerContext["segmentBoundaryHandler"] {
                segmentBoundaryHandler()
            }
        }
    }
    
    func handleCompletionObserver() {
        if let onFinishHandler = self.observerContext["onFinishHandler"] {
            onFinishHandler()
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
            print(self.expressionSegments)
            self.onExpressionComplete?()
        }
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
                    self?.performTranscriptionUpdate(result.bestTranscription, final: true)
                    self?.normalizeSegments()
                    // Update duration
                    self?.accumulatedDuration = max(0, Date().timeIntervalSince(self!.recordStartDate!) - TRANSCRIPTION_LATENCY_DURATION)
                    self?.startListeningForSpeech(
                        soundIntensityHandler: self?.soundIntensityHandler,
                        onStartHandler: self?.onListeningStartHandler
                    )
                }
            } else if self.isListening && self.request!.requiresOnDeviceRecognition {
                self.performTranscriptionUpdate(result.bestTranscription, final: true)
                self.normalizeSegments()
                // Update duration
                self.accumulatedDuration = max(0, Date().timeIntervalSince(self.recordStartDate!) - TRANSCRIPTION_LATENCY_DURATION)
                // print("===== A contiguous clause was completed: \(self.expressionSegments)")
            } else {
                // Only the on-server recognition should go here in theory
                self.performTranscriptionUpdate(result.bestTranscription, final: true)
                self.normalizeSegments()
                // print("===== Completed expression: \(self.expressionSegments)")
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
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully paused =====")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully started =====")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        self.onEchoUpdate?(characterRange)
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
