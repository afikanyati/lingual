//
//  Note.swift
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
let DEFAULT_SEGMENT_DURATION: Double = 100000 // Must be high enough such that no user will record a note of this duration
let TRANSCRIPTION_LATENCY_DURATION: Double = 0.3
let SOUND_INTENSITY_SIG_FIG_COUNT = 4
let DEFAULT_FIG_COUNT = 2

class Note: AVMutableComposition {
    // MARK: - Static Properties
    /// Stores the timescale used to scale the values specified for CMTime objects
    static let defaultSegmentTimescale = Double(10000)

    // MARK: - Composition Properties
    /// Stores the filename of the note
    private(set) var filename: String
    // Change recording format:
    // Reference 1: https://stackoverflow.com/questions/4279311/how-to-record-voice-in-m4a-format
    // Reference 2: https://developer.apple.com/forums/thread/27411
    /// Stores the private AVFileType of the source URL
    private var _fileType: AVFileType = .caf // Used when instantiating NoteSegment class instances
    /// Stores the filetype of the source URL
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
    /// Stores information about the speaker
    private(set) var speaker: Speaker
    /// Stores a list of high-level representation of note segments
    private(set) var noteSegments: [NoteSegment] = [NoteSegment]()
    /// Stores a list of high-level representation of note segments in staging (before committed to noteSegments)
    private(set) var noteBuffer: [NoteSegment] = [NoteSegment]()
    /// Range of last committed buffer of note segments
    private(set) var committedBufferRanges = [Range<Int>]()
    /// Stores the starting time of the note
    private(set) var startTime: CMTime = CMTime.zero // When we remove or add we change this
    /// Stores the ending time of the note
    private(set) var endTime: CMTime = CMTime.zero // When we remove or add we change this
    /// Stores the duration of the note
    public override var duration: CMTime {
        return CMTimeSubtract(self.endTime, self.startTime)
    }
    /// Stores whether note is currently being exported
    private(set) var isExporting = false
    /// Stores the number of sentences in the note
    public var numSentences: Int {
        var sentenceCount = Int(Utils.UNKNOWN)
        if let lastSegment = self.noteBuffer.last, self.noteBuffer.count > 0 && lastSegment.getSentence().number != Int(Utils.UNKNOWN) {
            sentenceCount = lastSegment.getSentence().number + 1
        } else if let lastSegment = self.noteSegments.last, self.noteSegments.count > 0 && lastSegment.getSentence().number != Int(Utils.UNKNOWN) {
            sentenceCount = lastSegment.getSentence().number + 1
        }
        
        return sentenceCount
    }
    /// The language of the note
    public var language: NLLanguage? {
        if let firstSegment = self.noteSegments.first, let language = NLLanguageRecognizer.dominantLanguage(for: firstSegment.getText()) {
            return language
        }
        
        return nil
    }
    /// The average number of words spoken per minute.
    public var avgSpeakingRate: Double {
        // Can be used to vary speed relative to WPM
        var speakingRate: Double = 0
        var segmentCount = self.noteSegments.count
        
        // note segments
        for segment in self.noteSegments {
            speakingRate += segment.getSpeakingRate()
        }
        
        // note buffer
        if self.noteBuffer.count > 0 {
            segmentCount += self.noteBuffer.count
            for segment in self.noteBuffer {
                speakingRate += segment.getSpeakingRate()
            }
        }
        
        // prevent divide by zero
        if segmentCount > 0 {
            speakingRate /= Double(segmentCount)
        }

        return speakingRate
    }
    /// Specifies whether note will present visual indications of temporal silences on screen
    private(set) var withTemporalSuggestions: Bool
    /// Specifies whether note will present punctuation suggestions based on duration of silences
    private(set) var withPunctuationSuggestions: Bool
    /// Specifies whether note will present emphasis suggestions based on fluctuating sound intensity of speaker
    private(set) var withFormattingSuggestions: Bool
    /// Specifies whether note will only present written language as words (versus numerals or punctuation symbols)
    private(set) var withTextStrictlyAsWords: Bool
    /// Stores a reference to the main view controller
    weak private(set) var vc: ViewController?
    /// Stores a temporary voice command handler that runs once listening has stopped
    private(set) var tempVoiceCommandHandler: (() -> Void)?
    /// Stores handlers to be executed when note is played
    private var observerContext = [String: (() -> Void)]()
    
    // MARK: - Recording Properties
    /// Stores the bus from which audio input will be extracted
    let recordBus = 0
    /// Stores whether note is authorized to listen for speech. This is typically false when then source filetype is .m4a vs. .caf, which happens on note export
    private(set) var authorizedToListenForSpeech = false
    /// Stores a count of the number of unique clips that have been recording throughout note (factors recording breaks due to voice commands)
    private(set) var clipCount: Int = 0
    /// Stores a reference to the shared audio session object
    var recordingSession = AVAudioSession.sharedInstance()
    /// Stores a reference to the moment current note clip started listening
    public var recordStartDate: Date?
    /// Stores the total duration of time across segments capturing during the current listening clip
    private var accumulatedDuration = TimeInterval(0)
    /// Stores a reference to the audio file where listening buffers are being saved to
    public var recordFile: AVAudioFile?
    /// Stores a stream of sound intensity values received throughout the process of listening
    private var soundIntensityStream = [SoundIntensityDatum]()
    /// Stores a reference to the minimum power value accepted for sound intensity datum
    public let minPower: Float
    /// Stores a reference to the note's pitch engine which computes pitch values in real-time
    private lazy var pitchEngine: PitchEngine = { [weak self] in
        let config = Config(
            bufferSize: 1024,
            estimationStrategy: .yin
        )
        let pitchEngine = PitchEngine(config: config, delegate: self)
        pitchEngine.levelThreshold = minPower
        return pitchEngine
    }()
    /// Stores a stream of pitch values received throughout the process of listening
    private var pitchStream = [PitchDatum]()
    /// Stores a handler to be executed when a new listening buffer is received and processed
    private(set) var onListenUpdate: ((_ bufferRange: NSRange?) -> Void)?
    /// Stores a handler to be executed when listening has stopped
    private(set) var onListenStop: (() -> Void)?
    /// Stores a UI handler to be executed when new sound intensity data is received
    private var soundIntensityHandler: ((_ power: Double?) -> Void)?
    /// Stores a UI handler to be executed when new pitch data is received
    private var pitchHandler: ((_ pitchDatum: PitchDatum?) -> Void)?
    
    // MARK: - Speech Recognition Properties
    /// Specifies whether speech recognition should use on-device compute or cloud compute
    private(set) var useOnDeviceRecognition: Bool
    /// Stores a reference to note's audio engine used for speech recognition
    private var audioEngine = AVAudioEngine()
    /// Stores a reference to the note's speech recognizer object
    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    /// Stores a reference to the audio buffer used by the speech recognition system to process listening buffer blocks
    private var request: SFSpeechAudioBufferRecognitionRequest?
    /// Stores a reference to the speech recognition task object
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Stores the type of recognition last executed e.g. speech or voice command
    private var lastRecognitionTask: RecognitionTask?
    /// Specifies whether note is currently listening for speech
    @objc dynamic private(set) var isListeningForSpeech = false
    /// Specifies whether note has paused listening for speech (active, but paused vs. inactive)
    private(set) var pausedListeningForSpeech = false
    /// Specifies whether note is currently listening for voice commands
    private(set) var isListeningForCommands = false
    /// Specifies whether note has paused listening for commands (active, but paused vs. inactive)
    private(set) var pausedListeningForCommands = false
    /// Stores a handler to be executed when listening starts
    private var onListeningStartHandler: (() -> Void)?
    
    // MARK: - Speech Synthesis Properties
    /// Specifies whether passive echo should execute when headphones are connected
    private(set) var withPassiveEcho = true
    /// Specifies whether echo is currently playing
    public var isPlayingEcho = false
    /// Specifies whether echo is currently paused (active, but paused vs. inactive)
    public var echoIsPaused: Bool {
        return self.vc!.speechSynthesizer.isPaused
    }
    /// Stores a handler to be executed when note is complete
    private(set) var onComplete: (() -> Void)?
    /// Schedules a temporary handler to be executed when echo is complete
    private var scheduleTempOnEchoFinishHandler: ((_ handler: @escaping () -> Void) -> Void)?
    /// Range of last echo of note segments
    private(set) var lastEchoSegmentRange: Range<Int>?
    
    // MARK: - Audio Playback Properties
    /// Stores a reference to the note's player object
    private(set) var player = AVPlayer()
    /// Stores a reference to a timer that begins next iteration of looping player
    private var playerLoopTimer: Timer?
    /// Stores a reference to the bus used for audio playback
    private let playbackBus = 1
    /// Stores the current playback rate of note playback
    private(set) var playbackRate: Float = 1
    /// Stores a reference to the playback observer that executes after each segment
    public var boundaryObserverToken: Any?
    /// Stores a reference to the playback observer that executes each second
    public var timerObserverToken: Any?
    /// Stores a reference to the playback observer that executes when playback is complete
    public var completionObserverToken: Any?
    /// Stores a reference to the last segment processed during note playback. Prevents repeat processing.
    private var previousBoundarySegment: NoteSegment?
    /// Specifies whether note is currently playing
    public var isPlayingNote: Bool {
        return player.isPlaying
    }
    /// Specifies whether segments corresponding to punctuation should be skipped
    private(set) var skipPunctuation = true
    /// Specifies whether segments corresponding to silences should be skipped
    private(set) var skipSilence = true
    /// Specifies the time value at which note playback should begin
    private(set) var startPlaybackAt: CMTime?
    /// Specifies the time value at which note playback should end
    private(set) var stopPlaybackAt: CMTime?
    
    // MARK: - Initializer

    /// Initializes the Note class instance
    ///
    /// - Parameters:
    ///     - vc: Suppliess a reference to the main view controller
    ///     - filename: Supplies the filename of the note
    ///     - fileType: Suppliess the filetype of the source URL
    ///     - speaker: Suppliess information about the speaker
    ///     - minPower: Supplies the minimum power value accepted for sound intensity datum
    ///     - segments: Supplies an optional array of note segments to seed the note
    ///     - withOnDeviceRecognition: Supplies whether speech recognition should use on-device compute or cloud compute
    ///     - withTemporalSuggestions: Supplies whether note will present visual indications of temporal silences on screen
    ///     - withPunctuationSuggestions: Supplies whether note will present punctuation suggestions based on duration of silences
    ///     - withFormattingSuggestions: Supplies whether note will present emphasis suggestions based on fluctuating sound intensity of speaker
    ///     - withTextStrictlyAsWords: Supplies whether note will only present written language as words (versus numerals or punctuation symbols)
    ///     - onListenUpdate: Supplies a handler to be executed when a new listening buffer is received and processed
    ///     - onListenStop: Supplies a handler to be executed when listening has stopped
    ///     - onComplete: Supplies a handler to be executed when note is complete.
    ///     - scheduleTempOnEchoFinishHandler: Schedules a temporary handler to be executed when echo is complete
    init(
        vc: ViewController? = nil,
        filename: String,
        fileType: AVFileType? = nil,
        speaker: Speaker,
        minPower: Float,
        segments: [NoteSegment]? = nil,
        withOnDeviceRecognition: Bool,
        withTemporalSuggestions: Bool = false,
        withPunctuationSuggestions: Bool = false,
        withFormattingSuggestions: Bool = false,
        withTextStrictlyAsWords: Bool = false,
        onListenUpdate: ((_ bufferRange: NSRange?) -> Void)? = nil,
        onListenStop: (() -> Void)? = nil,
        onComplete: (() -> Void)? = nil,
        scheduleTempOnEchoFinishHandler: ((_ handler: @escaping () -> Void) -> Void)? = nil
    ) {
        print("===== Instantiating new note: \(filename) =====")
        self.filename = filename
        self.speaker = speaker
        self.minPower = minPower
        self.useOnDeviceRecognition = withOnDeviceRecognition
        self.onListenUpdate = onListenUpdate
        self.onListenStop = onListenStop
        self.onComplete = onComplete
        self.scheduleTempOnEchoFinishHandler = scheduleTempOnEchoFinishHandler
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
        }
        
        // Configure Observers
        self.configureNotificationObservers()
        
        // A user might pass in segments when note instantiated
        if let segments = segments {
            self.startTime = segments.first!.timeMapping.target.start
            self.endTime = segments.last!.timeMapping.target.end
            self.setSegments(segments: segments, replaceNoteDetails: true)
        }
        
        // Check Rep Invariant
        checkRep()
    }
    
    deinit {}
    
    public override var description: String {
        return "Note {\n\tfilename: \(self.filename) \n\tfileType: \(self.fileType) \n\tspeaker: \(self.speaker) \n\tnoteSegments: \(self.noteSegments) \n\tnoteBuffer: \(self.noteBuffer) \n\tcommittedBufferRanges: \(String(describing: self.committedBufferRanges)) \n\tstartTime: \(self.startTime) \n\tendTime: \(self.endTime) \n\tduration: \(self.duration) \n\tisExporting: \(self.isExporting) \n\tnumSentences: \(self.numSentences) \n\tlanguage: \(String(describing: self.language)) \n\tavgSpeakingRate: \(self.avgSpeakingRate) \n\twithTemporalSuggestions: \(self.withTemporalSuggestions) \n\twithPunctuationSuggestions: \(self.withPunctuationSuggestions) \n\twithFormattingSuggestions: \(self.withFormattingSuggestions) \n\twithTextStrictlyAsWords: \(self.withTextStrictlyAsWords) \n\tauthorizedToListenForSpeech: \(self.authorizedToListenForSpeech) \n\tclipCount: \(self.clipCount) \n\trecordStartDate: \(String(describing: self.recordStartDate)) \n\taccumulatedDuration: \(self.accumulatedDuration) \n\tsoundIntensityStream: \(self.soundIntensityStream) \n\tminPower: \(self.minPower) \n\tpitchStream: \(self.pitchStream) \n\tuseOnDeviceRecognition: \(self.useOnDeviceRecognition) \n\tisListeningForSpeech: \(self.isListeningForSpeech) \n\tpausedListeningForSpeech: \(self.pausedListeningForSpeech) \n\tisListeningForCommands: \(self.isListeningForCommands) \n\tpausedListeningForCommands: \(self.pausedListeningForCommands) \n\twithPassiveEcho: \(self.withPassiveEcho) \n\tisPlayingEcho: \(self.isPlayingEcho) \n\techoIsPaused: \(self.echoIsPaused) \n\tplaybackRate: \(self.playbackRate) \n\tpreviousBoundarySegment: \(String(describing: self.previousBoundarySegment)) \n\tisPlayingNote: \(self.isPlayingNote) \n\tskipPunctuation: \(self.skipPunctuation) \n\tskipSilence: \(self.skipSilence) \n\tstartPlaybackAt: \(String(describing: self.startPlaybackAt)) \n\tstopPlaybackAt: \(String(describing: self.stopPlaybackAt))\n}"
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
        print("===== Configure Note Audio Write File =====")
        do {
            try recordFile = AVAudioFile(
                forWriting: Utils.getTempFileURL(of: "\(self.filename)-\(self.clipCount)\(self.fileType)"),
                settings: audioEngine.inputNode.inputFormat(forBus: self.recordBus).settings
            )
            authorizedToListenForSpeech = true
            print("\tSource URL for writing note successfully created: \(self.filename)-\(self.clipCount)\(self.fileType)")
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
                if self.isListeningForSpeech {
                    self.stop() {[weak self] in
                        self?.startListeningForSpeech(
                            soundIntensityHandler: self?.soundIntensityHandler,
                            pitchHandler: self?.pitchHandler,
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
                if self.isListeningForSpeech {
                    self.stop() {[weak self] in
                        self?.startListeningForSpeech(
                            soundIntensityHandler: self?.soundIntensityHandler,
                            pitchHandler: self?.pitchHandler,
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
        // only isListeningForSpeech or isListeningForCommands should be active
        result = result && !(self.isListeningForSpeech && self.isListeningForCommands)
//        print("only isListeningForSpeech or isListeningForCommands should be active: ", !(self.isListeningForSpeech && self.isListeningForCommands))
//        print("current result: ", result)

        // startTime must be in front of endTime
        result = result && self.endTime >= self.startTime
//        print("startTime must be in front of endTime: ", self.endTime >= self.startTime)
//        print("current result: ", result)

        // start of note segments should be the same as startTime
        if let firstSegment = self.noteSegments.first {
            result = result && firstSegment.timeMapping.target.start == self.startTime
//            print("start of note segments should be the same as startTime: ", firstSegment.timeMapping.target.start == self.startTime, firstSegment.timeMapping.target.start.seconds, self.startTime.seconds)
//            print("current result: ", result)
        }

        // end of note segments should be the same as endTime
        if let lastSegment = self.noteSegments.last {
            result = result && self.endTime == lastSegment.timeMapping.target.end
//            print("end of note segments should be the same as endTime: ", self.endTime == lastSegment.timeMapping.target.end, self.endTime.seconds, lastSegment.timeMapping.target.end.seconds)
//            print("current result: ", result)
        }

        // internal durations should be the same
        if let firstSegment = self.noteSegments.first, let lastSegment = self.noteSegments.last {
            result = result && CMTimeSubtract(self.endTime, self.startTime) == CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start)
//            print("internal durations should be the same: ", CMTimeSubtract(self.endTime, self.startTime) == CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start), CMTimeSubtract(self.endTime, self.startTime).seconds, CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start).seconds)
//            print("current result: ", result)
        }

        // duration of segments should be the same as underlying track segments
        // we only check is we have two note tracks because that's when we're guaranteed to have saved note segments to lower level track representation
        if self.noteSegments.count > 0, let firstSegment = self.tracks[0].segments.first, let lastSegment = self.tracks[0].segments.last {
            result = result && CMTimeSubtract(self.noteSegments.last!.timeMapping.target.end, self.noteSegments.first!.timeMapping.target.start) == CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start)
//            print("duration of first track should be the same as underlying track segments: ", CMTimeSubtract(self.noteSegments.last!.timeMapping.target.end, self.noteSegments.first!.timeMapping.target.start) == CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start), CMTimeSubtract(self.noteSegments.last!.timeMapping.target.end, self.noteSegments.first!.timeMapping.target.start).seconds, CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start).seconds)
//            print("current result: ", result)
        }

        // make sure paused listening for speech only occurs if listening for speech
        result = result && (self.isListeningForSpeech || (!self.isListeningForSpeech && !self.pausedListeningForSpeech))
//        print("make sure paused listening for speech  only occurs if listening for speech: ", (self.isListeningForSpeech || (!self.isListeningForSpeech && !self.pausedListeningForSpeech)))
//        print("current result: ", result)
        
        // make sure paused listening for commands only occurs if listening for commands
        result = result && (self.isListeningForCommands || (!self.isListeningForCommands && !self.pausedListeningForCommands))
        //        print("make sure paused listening for speech  only occurs if listening for commands: ", (self.isListeningForCommands || (!self.isListeningForCommands && !self.pausedListeningForCommands)))
        //        print("current result: ", result)

        if !result {
            fatalError("===== [Error] Note Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Speech Listening Methods
    
    func startListeningForSpeech(
        soundIntensityHandler: ((_ power: Double?) -> Void)? = nil,
        pitchHandler: ((_ pitchDatum: PitchDatum?) -> Void)? = nil,
        forVoiceCommands: Bool = false,
        onStartHandler: (() -> Void)? = nil
    ) {
        // Make sure we're not listening for voice commands or speech already
        if self.isListeningForCommands {
            self.stopListeningForVoiceCommands() {
                self.startListeningForSpeech(
                    soundIntensityHandler: soundIntensityHandler,
                    pitchHandler: pitchHandler,
                    forVoiceCommands: forVoiceCommands,
                    onStartHandler: onStartHandler
                )
            }
            
            return
        } else if self.isListeningForSpeech && !self.pausedListeningForSpeech {
            // Play Sound
            soundEngine.error()
            
            // Give haptic feedback
            hapticEngine.error()

            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {[weak self] timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: self!.vc)
                let synthesizerItem = SynthesizerItem(
                    synthesizer: self!.vc!.speechSynthesizer,
                    text: "Note already started.",
                    voice: voice,
                    rate: self!.vc!.echoRate,
                    volume: self!.vc!.playbackVolume
                )
                
                Utils.runSpeechSynthesizer(item: synthesizerItem)
            }
            
            // Execute start Handler
            onStartHandler?()
            return
        }

        if forVoiceCommands {
            print("===== Starting Listening For Voice Commands =====")
        } else {
            print("===== Starting Listening for Speech =====")
        }
        
        if !forVoiceCommands && !self.pausedListeningForSpeech {
            // Play Sound
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                soundEngine.startListening()
            }
            
            // Give haptic feedback
            hapticEngine.heavyImpact()
        }
        
        // Visually indicate app is listening
        self.vc!.activateListeningIndicator()
        
        // if we have segments in first track, it implies this is n > 1
        // recording session
        // We must prepare a new track if it's not there
        if !forVoiceCommands {
            print("\tIncrementing note clip count from \(self.clipCount) to \(self.clipCount + 1)...")
            // Increment clip count used to create unique track URLs to write audio into
            self.clipCount += 1

            // Configure Audio Write File
            self.configureAudioWriteFile()
        }
        
        if !forVoiceCommands && !self.authorizedToListenForSpeech {
            print("\t[Error] There was a problem while starting to listen for speech. Note is not authorized to listen.")
            return
        }
        
        // Activate Pitch Recognition
        pitchEngine.start()
        
        // Set sound intensity handler
        if let soundIntensityHandler = soundIntensityHandler {
            self.soundIntensityHandler = soundIntensityHandler
        }
        
        // Set pitch handler
        if let pitchHandler = pitchHandler {
            self.pitchHandler = pitchHandler
        }
        
        // Set listening handler
        if let onListeningStartHandler = onStartHandler {
            self.onListeningStartHandler = onListeningStartHandler
        }
        
        // Make sure any previous recognition tasks are finished
        if recognitionTask != nil {
            recognitionTask?.finish()
            recognitionTask = nil
        }

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: self.recordBus)
        print("===== Recording Info ===== \n\tSoftware Format: \(recordingFormat.sampleRate)\n\tHardware Format: \(AVAudioSession.sharedInstance().sampleRate) \n\tInput Latency: \(recordingSession.inputLatency.rounded(toPlaces: 5)) \n\tOutput Latency: \(recordingSession.outputLatency.rounded(toPlaces: 5)) \n\tIOBufferDuration: \(recordingSession.ioBufferDuration.rounded(toPlaces: 5))")
        
//        let recordSettings: [String : AnyObject] = [
//            AVSampleRateKey : NSNumber(value: Float(16000)),
//            AVFormatIDKey : NSNumber(value: Int32(kAudioFormatMPEG4AAC)),
//            AVNumberOfChannelsKey : NSNumber(value: 1),
//            AVEncoderAudioQualityKey : NSNumber(value: Int32(AVAudioQuality.low.rawValue))
//        ]
        
        // Set up values for speech recognition
        request = SFSpeechAudioBufferRecognitionRequest()
        request!.shouldReportPartialResults = true
        request!.requiresOnDeviceRecognition = false // Set to false by default, but conditionally changed below

        // Tap into microphone bus to receive and process audio input buffers
        node.installTap(onBus: self.recordBus, bufferSize: 1024, format: recordingFormat) { [unowned self] (buffer, _) in
            self.request!.append(buffer)
            // We place this here so we start tracking recording from the first buffer chnk we receive
            DispatchQueue.main.async {
                if self.audioEngine.isRunning &&
                    (!self.isListeningForSpeech || self.pausedListeningForSpeech) &&
                    (!self.isListeningForCommands || self.pausedListeningForCommands) {
                    // A transcription can be in progress before call to startSpeechRecognition if
                    // Apple servers ended dictation session
                    // It cannot be if after a continguous clause was completed while on-device recognition
                    if forVoiceCommands {
                        if !self.isListeningForCommands {
                            self.isListeningForCommands = true
                        }
                        if self.pausedListeningForCommands {
                            self.pausedListeningForCommands = false
                        }
                        
                        self.lastRecognitionTask = RecognitionTask.VOICE_COMMAND
                    } else {
                        if !self.isListeningForSpeech {
                            self.isListeningForSpeech = true
                        }
                        if self.pausedListeningForSpeech {
                            self.pausedListeningForSpeech = false
                        }
                        self.lastRecognitionTask = RecognitionTask.SPEECH
                        self.recordStartDate = Date()
                    }

                    onStartHandler?()
                }
            }
            
            // Handle sound intensity and pitch information
            DispatchQueue.main.async {
                // Sound Intensity
                let power = Utils.computeSoundIntensity(buffer: buffer)
                if let power = power {
                    let datum = SoundIntensityDatum(date: Date(), power: power)
                    self.soundIntensityStream.append(datum)
                    soundIntensityHandler?(power)
                }
                
                // Pitch
                if let lastPitchDatum = self.pitchStream.last, !self.isPlayingNote {
                    pitchHandler?(lastPitchDatum)
                }
            }
            
            // Write buffer data to audio file
            if !forVoiceCommands {
                do {
                    try self.recordFile!.write(from: buffer)
                } catch {
                    fatalError("\t[Error] There was a problem writing speech to file")
                }
            }
        }
        
        // Prepare and start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            fatalError("\t[Error] There was a problem starting speech recognition")
        }
        
        // Make sure we have support for speech recognition
        guard let myRecognizer = SFSpeechRecognizer() else {
            fatalError("\t[Error] Speech Recognizer is not supported for current locale")
        }
        
        // Set on-device recognition to desired setting
        if useOnDeviceRecognition && myRecognizer.supportsOnDeviceRecognition {
            print("\tUsing On-Device Recognition")
            request!.requiresOnDeviceRecognition = true
        }
        
        // Confirm  that speech recognizer is available for speech recogition
        if !myRecognizer.isAvailable {
            fatalError("\t[Error] Speech Recognizer is not available")
        }
        
        // Check rep invariant
        checkRep()
        
        // Let speech recognizer know we're performing dictation or voice commands
        speechRecognizer?.defaultTaskHint = forVoiceCommands ? .search : .dictation
        recognitionTask = speechRecognizer?.recognitionTask(with: request!, delegate: self)
    }
    
    // make sure onStophandler is not also wrapped in DispatchQueue.main.async
    func stopListeningForSpeech(pause: Bool = false, forVoiceCommands: Bool = false, onStopHandler: (() -> Void)? = nil) {
        if !isListeningForSpeech && !isListeningForCommands {
            // Play Sound
            soundEngine.error()
            
            // Give haptic feedback
            hapticEngine.heavyImpact()
            
            // Delay error message to allow error earcon to complete
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {[weak self] timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: self!.vc)
                let synthesizerItem = SynthesizerItem(
                    synthesizer: self!.vc!.speechSynthesizer,
                    text: "No ongoing note.",
                    voice: voice,
                    rate: self!.vc!.echoRate,
                    volume: self!.vc!.playbackVolume
                )
                
                Utils.runSpeechSynthesizer(item: synthesizerItem)
            }
            
            // Execute handler
            onStopHandler?()
            return
        }

        if forVoiceCommands {
            print("===== Stopping Listening For Voice Commands =====")
        } else {
            print("===== Stopping Listening for Speech =====")
        }
        
        if (isListeningForSpeech || isListeningForCommands) && !pause {
            if self.isListeningForSpeech {
                self.isListeningForSpeech = false
            }
            if self.isListeningForCommands {
                self.isListeningForCommands = false
            }
            if self.pausedListeningForSpeech {
                self.pausedListeningForSpeech = false
            }
            if self.pausedListeningForCommands {
                self.pausedListeningForCommands = false
            }
        } else if pause && !forVoiceCommands {
            if !self.pausedListeningForSpeech {
                self.pausedListeningForSpeech = true
            }
        } else if pause && forVoiceCommands {
            if !self.pausedListeningForCommands {
                self.pausedListeningForCommands = true
            }
        }

        if !forVoiceCommands {
            // Play Sound
            // soundEngine.stopListening()
        }
        
        let node = audioEngine.inputNode
        node.removeTap(onBus: self.recordBus)
        
        if pause {
            audioEngine.pause()
        } else {
            audioEngine.stop()
        }

        // When this is not in the main thread, the recognition task doesn't end correctly
        // which prevents us from receiving the final transcription.
        DispatchQueue.main.async {
            self.recognitionTask!.finish() // don't wrap in if statement because it is sometimes not .running
            self.request!.endAudio() // don't add a request = nil because it results in request not being there sometimes.
            self.pitchEngine.stop()
            self.vc!.deactivateListeningIndicator()
            onStopHandler?() // Needs to be outside DispatchQueue.main.async so it doesn't accidentally wrap two DispatchQueue.main.async if handler has one
        }
        
        if !forVoiceCommands {
            // execute listen stop handler
            self.onListenStop?()
        }
    }
    
    func startListeningForVoiceCommands(
        soundIntensityHandler: ((_ power: Double?) -> Void)? = nil,
        pitchHandler: ((_ pitchDatum: PitchDatum?) -> Void)? = nil,
        onStartHandler: (() -> Void)? = nil
    ) {
        startListeningForSpeech(
            soundIntensityHandler: soundIntensityHandler,
            pitchHandler: pitchHandler,
            forVoiceCommands: true,
            onStartHandler: onStartHandler
        )
    }
    
    func stopListeningForVoiceCommands(pause: Bool = false, onStopHandler: (() -> Void)? = nil) {
        stopListeningForSpeech(pause: pause, forVoiceCommands: true, onStopHandler: onStopHandler)
    }
    
    func performTranscriptionUpdate(_ transcription: SFTranscription) {
        for (index, segment) in transcription.segments.enumerated() {
            processTranscriptSegment(
                segment: segment,
                transcriptionIndex: index,
                transcription: transcription
            )
        }
    }
    
    func processTranscriptSegment(segment: SFTranscriptionSegment, transcriptionIndex: Int, transcription: SFTranscription) {
        // get existing segments
        var segments = self.noteBuffer
        
        // Manage NLP
        var segmentTags: [String : NLTag?]
        var sentiment: [ScaleUnitType: Float]?
        if self.noteBuffer.count == 0 || transcriptionIndex >= self.noteBuffer.count {
             // New segment, compute values
            (segmentTags, sentiment) = computeSegmentTags(
                transcription: transcription,
                transcriptionIndex: transcriptionIndex
            )
        } else if transcriptionIndex < self.noteBuffer.count {
            // existing segment, get values
            let existingSegment = self.noteBuffer[transcriptionIndex]
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
        
        // Compute segment text
        let word = transcriptionIndex == 0
            && segments.count > 0
            && !segments.last!.isSentenceTerminator()
            && !Utils.isFirstPersonSingularPronoun(segment.substring) ?
                segment.substring.lowercased()
                :
                segment.substring

        // Compute timestamp and duration
        var sourceTimestamp: Double
        var duration: Double
        if segment.duration <= 0 {
            // temporary segment
            // give it default temporary values
            if self.noteBuffer.count == 0 {
                // First temporary segment
                
                // Set source timestamp
                sourceTimestamp = floor(Note.defaultSegmentTimescale * DEFAULT_SEGMENT_DURATION)
                
                // Set duration
                duration = floor(Note.defaultSegmentTimescale * DEFAULT_SEGMENT_DURATION)
            } else {
                // Set source timestamp
                sourceTimestamp = floor(Note.defaultSegmentTimescale * (Double(transcriptionIndex + 1) * DEFAULT_SEGMENT_DURATION))
                
                // Set duration
                duration = floor(Note.defaultSegmentTimescale * DEFAULT_SEGMENT_DURATION)
            }
        } else {
            // enters here when we get the final transcript which has timestamp data
            
            // Set source timestamp
            sourceTimestamp = self.accumulatedDuration + segment.timestamp > 0 ?
                    floor(Note.defaultSegmentTimescale * (accumulatedDuration + segment.timestamp))
                :
                    0
            
            // Set duration
            duration = segment.duration > 0 ? floor(Note.defaultSegmentTimescale * segment.duration) : 0
        }
        
        let phoneticallySimilarWords = segment.alternativeSubstrings
        
        let noteSegment = NoteSegment(
            note: self,
            word: word,
            trackURL: Utils.getTempFileURL(of: "\(self.filename)-\(self.clipCount)\(self.fileType)"),
            trackID: self.tracks[0].trackID,
            phoneticallySimilarWords: phoneticallySimilarWords,
            sourceTimeRange: CMTimeRangeMake(
                start: CMTimeMake(value: Int64(sourceTimestamp), timescale: Int32(Note.defaultSegmentTimescale)),
                duration: CMTimeMake(value: Int64(duration), timescale: Int32(Note.defaultSegmentTimescale))
            ),
            targetTimeRange: CMTimeRangeMake( // This will be properly set in normalize Segments
                start: CMTimeMake(value: Int64(sourceTimestamp), timescale: Int32(Note.defaultSegmentTimescale)),
                duration: CMTimeMake(value: Int64(duration), timescale: Int32(Note.defaultSegmentTimescale))
            ),
            tokenType: segmentTags["tokenType"]!,
            lexicalClass: segmentTags["lexicalClass"]!,
            nameType: segmentTags["nameType"]!,
            lemma: segmentTags["lemma"]!,
            sentimentScore: sentiment ?? nil
        )
        
        
        if self.noteBuffer.count == 0 || transcriptionIndex >= segments.count {
            // New segment, append to speechSegments
            segments.append(noteSegment)
            self.noteBuffer = segments
        } else if transcriptionIndex < segments.count {
            // Existing segment, overwrite old copy
            // This assumes the new version is a better approximation of user speech
            let oldSegment = segments[transcriptionIndex]
            if oldSegment != noteSegment {
                // determine if we need to replace selection values
                let replaceSelectionAnchor = oldSegment == selectionCursor.anchor
                let replaceSelectionFocus = oldSegment == selectionCursor.focus
                let replaceSelectionCachedAnchor = oldSegment == selectionCursor.cachedAnchor
                
                // set updated segments
                segments[transcriptionIndex] = noteSegment
                self.noteBuffer = segments
                
                // update selection anchor
                if replaceSelectionAnchor {
                    selectionCursor.setAnchor(segment: self.noteBuffer[transcriptionIndex])
                }
                
                // update selection focus
                if replaceSelectionFocus {
                    selectionCursor.setFocus(segment: self.noteBuffer[transcriptionIndex])
                }
                
                // update selection cached anchor
                if replaceSelectionCachedAnchor {
                    selectionCursor.setCachedAnchor(segment: self.noteBuffer[transcriptionIndex])
                }
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
    // We set sentence numbers here because we've built up the entire note and can compute sentences factoring it all
    // This is where correct values for avgPauseDuration and speakingRate are set
    func normalizeSegments(
        segments: [NoteSegment]? = nil,
        normalizeType: TimeNormalizerType = .source,
        replaceNoteDetails: Bool = false,
        omitLeadingSilence: Bool = false,
        saveSegments: Bool = false,
        saveToLowLevelRepr: Bool = false,
        returnSegments: Bool = false
    ) -> [NoteSegment]? {
        print("===== Normalizing Segments =====")
        var lastEnd = CMTime.zero
        var normalizedSegments = [NoteSegment]()
        var silenceIndices = [Int]()
        
        var segs = self.noteBuffer.count > 0 ? self.noteBuffer : self.noteSegments
        if let segments = segments {
            print("\tReceived custom segments. Setting as normalization contents...")
            segs = segments
        }
        
        for (index, segment) in segs.enumerated() {
            if segment.timeMapping[normalizeType].start.seconds != lastEnd.seconds {
                if segment.timeMapping[normalizeType].start.seconds > lastEnd.seconds && !segment.isSilence() {
                    let trackURL = Utils.getTempFileURL(of: "\(self.filename)-\(self.clipCount)\(self.fileType)")

                    if let lastCommittedSegment = self.noteSegments.last, index == 0 && segments != nil && segments!.first! != self.noteSegments.first! && self.noteSegments.count > 0 && normalizeType == .source && lastCommittedSegment.sourceURL!.absoluteString == trackURL.absoluteString {
                        // first segment is silence
                        // we are normalizing source
                        // noteSegments is not empty
                        // we are on the same source url as the last segment in noteSegments
                        // we are passed in segments
                        // the first segment of noteSegments and passed in segments are not the same
                        lastEnd = lastCommittedSegment.timeMapping.source.end
                    }

                    // Add a silent segment in front of current segment to account for early time
                    let silentSegment = NoteSegment(
                        note: self,
                        word: "",
                        trackURL: trackURL,
                        trackID: self.tracks[0].trackID,
                        phoneticallySimilarWords: [],
                        // If we're normalizing target, this might be wrong
                        sourceTimeRange: CMTimeRangeMake(
                            start: lastEnd,
                            duration: segment.timeMapping.source.start - lastEnd
                        ),
                        // If we're normalizing source, this might be wrong
                        targetTimeRange: CMTimeRangeMake(
                            start: lastEnd,
                            duration: segment.timeMapping.target.start - lastEnd
                        ),
                        tokenType: nil,
                        lexicalClass: nil,
                        nameType: nil,
                        lemma: nil,
                        sentimentScore: nil, // silences have no sentiment
                        utterPunctuationSuggestion: true // give feedback that we're on a new sentence or paragraph.
                    )
                    
                    // Segment Sound intensity
                    let startOfSegmentDuration: Double = lastEnd.seconds
                    
                    // Sound Intensity
                    if segment.getPower() != Double.infinity {
                        // Import sound intensity
                        let power = segment.getPower()
                        segment.setPower(power: power)
                    } else if self.soundIntensityStream.count > 0 {
                        // Add sound intensities
                        let datum = getRecordingSoundIntensityDatum(timestamp: startOfSegmentDuration)
                        segment.setPower(power: datum.power.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                    }

                    // Silence Sound Intensity/Background Noise
                    if self.soundIntensityStream.count > 0 {
                        let startOfSilenceDuration: Double = lastEnd.seconds
                        let backgroundNoise = getRecordingSoundIntensityDatum(timestamp: startOfSilenceDuration)
                        silentSegment.setPower(power: backgroundNoise.power.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                    }
                    
                    // Pitch
                    if let pitch = segment.getPitch() {
                        // Import pitch
                        segment.setPitch(pitch: pitch)
                    } else if self.pitchStream.count > 0 {
                        // Add pitch
                        let pitch = getRecordingPitch(timestamp: startOfSegmentDuration)
                        segment.setPitch(pitch: pitch.pitch)
                    }
                    
                    // Silences don't have pitch
                    
                    // Save silence index
                    silenceIndices.append(normalizedSegments.count)
                    
                    // Add to segments array
                    normalizedSegments.append(silentSegment)
                    normalizedSegments.append(segment)
                    
                    // Update last end value
                    lastEnd = segment.timeMapping[normalizeType].end
                } else if segment.timeMapping[normalizeType].start.seconds > lastEnd.seconds && segment.isSilence() {
                    // Modify silent segment in front of current segment to account for early time
                    let newDuration = normalizeType == .source ? CMTimeSubtract(segment.timeMapping.source.end, lastEnd) : CMTimeSubtract(segment.timeMapping.target.end, lastEnd)
                    let sourceTimeRange = normalizeType == .source ?
                    CMTimeRangeMake(start: lastEnd, duration: newDuration)
                    :
                    CMTimeRangeMake(start: segment.timeMapping.source.start, duration: newDuration)
                    
                    let targetTimeRange = normalizeType == .target ?
                    CMTimeRangeMake(start: lastEnd, duration: newDuration)
                    :
                    CMTimeRangeMake(start: segment.timeMapping.target.start, duration: newDuration)
                    let modifiedSegment = NoteSegment(
                        note: self,
                        word: segment.getText(),
                        trackURL: segment.sourceURL!,
                        trackID: segment.sourceTrackID,
                        phoneticallySimilarWords: segment.getPhoneticallySimilarWords(),
                        sourceTimeRange: sourceTimeRange,
                        targetTimeRange: targetTimeRange,
                        tokenType: segment.getTokenType(),
                        lexicalClass: segment.getLexicalClass(),
                        nameType: segment.getNameType(),
                        lemma: segment.getLemma(),
                        sentimentScore: segment.getSentiment()
                    )
                    
                    let startOfSilenceDuration: Double = lastEnd.seconds
                    
                    // Sound Intensity
                    if segment.getPower() != Double.infinity {
                        // Import sound intensity
                        let power = segment.getPower()
                        modifiedSegment.setPower(power: power)
                    } else if self.soundIntensityStream.count > 0 {
                        // Add sound intensities
                        let datum = getRecordingSoundIntensityDatum(timestamp: startOfSilenceDuration)
                        modifiedSegment.setPower(power: datum.power.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                    }
                    
                    // Silences don't have pitch
                    
                    // Is Voice Command
                    modifiedSegment.setIsVoiceCommandWord(to: segment.isVoiceCommandWord())
                    
                    // Save silence index
                    silenceIndices.append(normalizedSegments.count)
                    
                    // Add to segments array
                    normalizedSegments.append(modifiedSegment)
                    
                    // Update last end value
                    lastEnd = segment.timeMapping[normalizeType].end
                } else if segment.timeMapping[normalizeType].start.seconds < lastEnd.seconds {
                    // segment overlaps with previous segment, shift it forwards
                    let normalizedSegment = NoteSegment(
                        note: self,
                        word: segment.getText(),
                        trackURL: segment.sourceURL!,
                        trackID: segment.sourceTrackID,
                        phoneticallySimilarWords: segment.getPhoneticallySimilarWords(),
                        sourceTimeRange: normalizeType == .source ?
                            CMTimeRangeMake(
                                start: lastEnd,
                                duration: segment.timeMapping.source.duration
                            )
                            :
                            segment.timeMapping.source,
                        targetTimeRange: normalizeType == .target ?
                            CMTimeRangeMake(
                                start: lastEnd,
                                duration: segment.timeMapping.target.duration
                            )
                            :
                            segment.timeMapping.target,
                        tokenType: segment.getTokenType(),
                        lexicalClass: segment.getLexicalClass(),
                        nameType: segment.getNameType(),
                        lemma: segment.getLemma(),
                        sentimentScore: segment.getSentiment()
                    )
                    
                    let startOfSegmentDuration: Double = lastEnd.seconds
                    
                    // Sound Intensity
                    if segment.getPower() != Double.infinity {
                        // Import sound intensity
                        let power = segment.getPower()
                        normalizedSegment.setPower(power: power)
                    } else if self.soundIntensityStream.count > 0 {
                        // Add sound intensities
                        let datum = getRecordingSoundIntensityDatum(timestamp: startOfSegmentDuration)
                        segment.setPower(power: datum.power.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
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
                    
                    // Is Voice Command
                    normalizedSegment.setIsVoiceCommandWord(to: segment.isVoiceCommandWord())

                    // Add to segments array
                    normalizedSegments.append(normalizedSegment)
                    
                    // Update last end value
                    lastEnd = CMTimeAdd(lastEnd, segment.timeMapping[normalizeType].duration)
                }
            } else {
                // Save silence index
                if segment.isSilence() {
                    silenceIndices.append(normalizedSegments.count)
                }
                
                // Add to segments array
                normalizedSegments.append(segment)
                
                // Update last end value
                lastEnd = segment.timeMapping[normalizeType].end
            }
        }
        
        var avgPauseDuration: Double = silenceIndices.reduce(0, { result, i in
            return result + normalizedSegments[i].timeMapping[normalizeType].duration.seconds
        }) / Double(silenceIndices.count)
        avgPauseDuration = avgPauseDuration.rounded(toPlaces: DEFAULT_FIG_COUNT)
        
        var speakingRate: Double = normalizedSegments.reduce(0, { result, item in
            if !item.isPunctuation() && !item.isSilence() {
                return result + 1
            }
            
            return result
        }) / Double(self.duration.seconds / Double(TimeConstant.secsPerMin))
        speakingRate = speakingRate.rounded(toPlaces: DEFAULT_FIG_COUNT)
        
        var initialSilenceDuration: CMTime?
        if omitLeadingSilence && normalizedSegments.first!.isSilence() {
            print("\tOmitting leading silence...")
            initialSilenceDuration = normalizedSegments.first!.timeMapping.target.end
            normalizedSegments.removeFirst()
        }
        
        // Update Index, Background Noise, AvgPauseDuration, SpeakingRate
        var fullyNormalizedSegments = [NoteSegment]()
        for (index, segment) in normalizedSegments.enumerated() {
            // Set segment index
            segment.setIndex(index: index)
            
            // Set backgroundNoise
            segment.setBackgroundNoise(noise: self.getBackgroundNoise())

            // Set avgPauseDuration
            segment.setAvgPauseDuration(duration: avgPauseDuration)
            
            // Set speakingRate
            segment.setSpeakingRate(rate: speakingRate)
            
            if omitLeadingSilence, let initialSilenceDuration = initialSilenceDuration {
                // segment overlaps with previous segment, shift it forwards
                let shiftedSegment = NoteSegment(
                    note: self,
                    word: segment.getText(),
                    trackURL: segment.sourceURL!,
                    trackID: segment.sourceTrackID,
                    phoneticallySimilarWords: segment.getPhoneticallySimilarWords(),
                    sourceTimeRange: segment.timeMapping.source,
                    targetTimeRange: CMTimeRangeMake(
                        start: segment.timeMapping.target.start - initialSilenceDuration,
                        duration: segment.timeMapping.target.duration
                    ),
                    tokenType: segment.getTokenType(),
                    lexicalClass: segment.getLexicalClass(),
                    nameType: segment.getNameType(),
                    lemma: segment.getLemma(),
                    sentimentScore: segment.getSentiment()
                )
                
                let startOfSegmentDuration: Double = lastEnd.seconds
                
                // Sound Intensity
                if segment.getPower() != Double.infinity {
                    // Import sound intensity
                    let power = segment.getPower()
                    shiftedSegment.setPower(power: power)
                } else if self.soundIntensityStream.count > 0 {
                    // Add sound intensities
                    let datum = getRecordingSoundIntensityDatum(timestamp: startOfSegmentDuration)
                    segment.setPower(power: datum.power.rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT))
                }
                
                // Pitch
                if let pitch = segment.getPitch() {
                    // Import pitch
                    shiftedSegment.setPitch(pitch: pitch)
                } else if self.pitchStream.count > 0 {
                    // Add pitch
                    let pitch = getRecordingPitch(timestamp: startOfSegmentDuration)
                    segment.setPitch(pitch: pitch.pitch)
                }
                
                // Is Voice Command
                shiftedSegment.setIsVoiceCommandWord(to: segment.isVoiceCommandWord())
                
                // add to array
                fullyNormalizedSegments.append(shiftedSegment)
            } else {
                fullyNormalizedSegments.append(segment)
            }
        }
        
        if saveSegments {
            print("\tSaving segments...")
            self.setSegments(
                segments: fullyNormalizedSegments,
                replaceNoteDetails: replaceNoteDetails,
                saveToLowLevelRepr: saveToLowLevelRepr
            )
            checkRep()
        }
            
        if returnSegments {
            print("\tReturning segments...")
            return fullyNormalizedSegments
        }
        
        return nil
    }
    
    func commitBuffer() {
        guard self.noteBuffer.count > 0 else { return }
        print("===== Commit Buffer =====")

        // duplicate note tracks
        print("\tDuplicating buffer segments...")
        var segments = [NoteSegment]()
        for segment in self.noteBuffer {
            segments.append(segment)
        }
        
        print("\tIdentifying insert time...")
        var insertTime: CMTime
        var updateCachedAnchor = false
        var cachedAnchorIndex = Int(Utils.UNKNOWN)
        var numSegmentsBehindCursorBeforeInsertion: Int
        var numSegmentsAheadCursorBeforeInsertion: Int
        if let cachedAnchor = selectionCursor.cachedAnchor {
            print("\tInsert time identified to be at cached anchor...")
            // Get cached anchor
            cachedAnchorIndex = cachedAnchor.getIndex()
            
            // Activate update cached anchor flag
            updateCachedAnchor = true
            
            // Find insert time
            insertTime = cachedAnchor.timeMapping.target.end
            
            // cache count of segments before insert to set last buffer range
            numSegmentsBehindCursorBeforeInsertion = cachedAnchor.getIndex() + 1
            numSegmentsAheadCursorBeforeInsertion = self.noteSegments.count - numSegmentsBehindCursorBeforeInsertion
        } else {
            print("\tInsert time identified to be at end of note...")
            // Find insert time
            insertTime = self.noteSegments.count > 0 ? self.noteSegments.last!.timeMapping.target.end : CMTime.zero
            
            // cache count of segments before insert to set last buffer range
            numSegmentsBehindCursorBeforeInsertion = self.noteSegments.count
            numSegmentsAheadCursorBeforeInsertion = self.noteSegments.count - numSegmentsBehindCursorBeforeInsertion
        }
        
        var oldAnchor: NoteSegment?
        if let anchor = selectionCursor.anchor {
            print("\tSelection anchor identified: ", anchor.getText())
            oldAnchor = anchor.duplicate()
        }
        
        var oldFocus: NoteSegment?
        if let focus = selectionCursor.focus {
            print("\tSelection focus identified...")
            oldFocus = focus.duplicate()
        }
        
        // Clear buffer segments
        print("\tClearing note buffer...")
        self.noteBuffer = []
        
        // normalize segments
        print("\tNormalizing buffer segments...")
        let normalizedSegments = self.normalizeSegments(
            segments: segments,
            omitLeadingSilence: updateCachedAnchor, // remove leading space so that we don't erroneously treat it as a long silence in the event that we are inserting new speech
            returnSegments: true
        )
        
        var lastBufferWordIndex = Int(Utils.UNKNOWN)
        for (index, segment) in normalizedSegments!.reversed().enumerated() {
            if !segment.isSilence() && !segment.isVoiceCommandWord() {
                lastBufferWordIndex = normalizedSegments!.count - index
                break
            }
        }
        
        self.insertPassage(
            segments: normalizedSegments!,
            at: insertTime
        )
        
        if updateCachedAnchor {
            let lastNormalizedWord = self.noteSegments[cachedAnchorIndex + lastBufferWordIndex]
            print("\tUpdating cached anchor...")
            for segment in self.noteSegments {
                if segment.isEqual(lastNormalizedWord) {
                    // update cached anchor
                    print("\tUpdating cached anchor in selection: ", segment.getText())
                    selectionCursor.setCachedAnchor(segment: segment)
                }
            }
        }

        if let oldAnchor = oldAnchor, oldAnchor.getIndex() == Int(Utils.UNKNOWN) {
            print("\tUpdating anchor...")
            for segment in self.noteSegments {
                if segment.isEqual(oldAnchor) {
                    // update anchor
                    print("\tUpdated anchor segment in selection cursor: ", segment.getText())
                    selectionCursor.setAnchor(segment: segment)
                }
            }
        }
        
        if let oldFocus = oldFocus, oldFocus.getIndex() == Int(Utils.UNKNOWN) {
            print("\tUpdating focus...")
            for segment in self.noteSegments {
                if segment.isEqual(oldFocus) {
                    // update focus
                    print("\tUpdated focus segment in selection cursor: ", segment.getText())
                    selectionCursor.setAnchor(segment: segment)
                }
            }
        }
        
        // Set range of last buffer
        print("\tSet last buffer range in note properties...")
        let numNormalizedBufferSegments = self.noteSegments.count - (numSegmentsBehindCursorBeforeInsertion + numSegmentsAheadCursorBeforeInsertion)
        self.committedBufferRanges.append(numSegmentsBehindCursorBeforeInsertion..<(numSegmentsBehindCursorBeforeInsertion + numNormalizedBufferSegments))
    }
    
    // MARK: - Listening Method Helpers
    
    func computeSegmentTags(transcription: SFTranscription, transcriptionIndex: Int) -> ([String : NLTag?], [ScaleUnitType: Float]) {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .tokenType, .sentimentScore, .lemma])
        let segmentText = transcription.segments[transcriptionIndex].substring

        // Determine note string
        let wholeText = segmentText.count == 1 && segmentText.first!.isPunctuation ?
            self.getText() + segmentText
        :
            self.getText() + " \(segmentText)"
        
        // Set string for NLTagger
        tagger.string = wholeText

        // Compute noteSegments array
        var noteSegments: [NoteSegment]? = nil
        var index: Int?
        if let anchor = selectionCursor.anchor, anchor.getIndex() != Int(Utils.UNKNOWN) {
            // insert buffer at the correct place based on cursor position
            noteSegments = self.noteSegments
            let anchorIndex = anchor.getIndex()
            noteSegments!.insert(contentsOf: self.noteBuffer, at: anchorIndex)
            index = anchorIndex + transcriptionIndex
        } else {
            // insert buffer at the end of segments
            noteSegments = self.noteSegments + self.noteBuffer
            index = self.noteSegments.count + transcriptionIndex
        }

        var nameType: NLTag?
        var lemma: NLTag?
        var lexicalClass: NLTag?
        var tokenType: NLTag?
        var wordSentimentScore: NLTag?
        var sentenceSentimentScore: NLTag?
        var paragraphSentimentScore: NLTag?
        let range = findSegmentRange(
            segments: noteSegments!,
            wholeText: wholeText,
            rangeText: segmentText,
            index: index!
        )

        (nameType, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType)
        (lemma, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
        (lexicalClass, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass)
        (tokenType, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .tokenType)
        (nameType, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType)
        (wordSentimentScore, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .sentimentScore)
        (sentenceSentimentScore, _) = tagger.tag(at: range.lowerBound, unit: .sentence, scheme: .sentimentScore)
        (paragraphSentimentScore, _) = tagger.tag(at: range.lowerBound, unit: .paragraph, scheme: .sentimentScore)
        
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
    func getSentenceNumber(segments: [NoteSegment], segment: NoteSegment) -> Int {
        var sentenceNumber = 0

        for seg in segments {
            if seg == segment {
                break
            }

            if seg.isSentenceTerminator() {
                sentenceNumber += 1
            }
        }

        return sentenceNumber
    }
    
    // Can't handle empty strings for segmentText
    // rangeText and index must accurate for a given segment in the segments array argument
    func findSegmentRange(segments: [NoteSegment], wholeText: String, rangeText: String, index: Int? = nil) -> Range<String.Index> {
        // figure out how many words are before it
        // compute number of processedChar
        var lowerText: String
        if let index = index, index >= segments.count && index - segments.count <= 1 {
            // new segment
            lowerText = self.getText(segments: segments)
        } else if let index = index, index < segments.count && index > 0 {
            // is in in noteSegments
            let lowerBoundarySegment = segments[index - 1]
            lowerText = self.getText(until: lowerBoundarySegment.timeMapping.target.start, segments: segments) // We assume that this is only called when source == target, so using either is fine
        } else if index == nil {
            // is in in noteSegments
            let lowerBoundarySegment = segments[segments.count - 1]
            lowerText = self.getText(until: lowerBoundarySegment.timeMapping.target.start, segments: segments) // We assume that this is only called when source == target, so using either is fine
        } else if index == 0 && segments.count == 0 {
            // is first segment
            lowerText = ""
        } else {
            fatalError("\t[Error] There was a problem analyzing the index of segment in findSegmentRange")
        }
        
        let lowerIndex = rangeText.count == 1 && rangeText.first!.isPunctuation ?
            wholeText.index(wholeText.startIndex, offsetBy: lowerText.count)
        :
            wholeText.index(wholeText.startIndex, offsetBy: lowerText.count + 1)
        let upperIndex = wholeText.index(lowerIndex, offsetBy: rangeText.count)
        let segmentRange = lowerIndex..<upperIndex
        
        return segmentRange
    }
    
    func getRecordingSoundIntensityDatum(timestamp: Double) -> SoundIntensityDatum {
        var datum: SoundIntensityDatum
        var i = 0
        var datumTimestamp = soundIntensityStream[i].date - recordStartDate! - TRANSCRIPTION_LATENCY_DURATION
        repeat {
            datumTimestamp = soundIntensityStream[i].date - recordStartDate! - TRANSCRIPTION_LATENCY_DURATION
            datum = soundIntensityStream[i]
            i += 1
        } while datumTimestamp < timestamp && i < soundIntensityStream.count
        
        return datum
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
    
    func getText(
        from fromTime: CMTime = CMTime.zero,
        until untilTime: CMTime? = nil,
        segments: [NoteSegment]? = nil,
        forEcho: Bool = false
    ) -> String {
        
        guard untilTime == nil || fromTime <= untilTime!  else {
            fatalError("===== [Error] There was a problem computing text. untilTime is greater than fromTime =====")
        }
        
        var text = ""
        
        var noteSegments: [NoteSegment]? = nil
        if let segments = segments {
            noteSegments = segments
        }
        
        if let cachedAnchor = selectionCursor.cachedAnchor, noteSegments == nil && cachedAnchor.getIndex() != Int(Utils.UNKNOWN) {
            // insert buffer at the correct place based on cursor position
            noteSegments = self.noteSegments
            // By default, insert(contentsOf:, at:) inserts the new elements before the anchor
            // We add one to insert them after the ancher
            let cachedAnchorIndex = cachedAnchor.getIndex()
            noteSegments!.insert(contentsOf: self.noteBuffer, at: cachedAnchorIndex + 1)
        } else if noteSegments == nil {
            // insert buffer at the end of segments
            noteSegments = self.noteSegments + self.noteBuffer
        }
        
        // We have been given a specific set of segments to compute on vs. multi segment tracks
        var fromTimeSegmentIndex: Int?
//        print("segments: ", noteSegments!)
        for (index, segment) in noteSegments!.enumerated()  {
            if let untilTime = untilTime, segment.timeMapping.target.end <= untilTime && !segment.isVoiceCommandWord() {
                let word = segment.getText(
                    withTemporalSuggestions: self.withTemporalSuggestions,
                    withPunctuationSuggestions: self.withPunctuationSuggestions,
                    withFormattingSuggestions: self.withFormattingSuggestions,
                    strictlyAsWord: self.withTextStrictlyAsWords,
                    withSpacePrefix: true,
                    forEcho: forEcho
                )
                
                text += word
            } else if (segment.timeMapping.target.start >= fromTime || fromTimeSegmentIndex != nil) && !segment.isVoiceCommandWord() {
                if fromTimeSegmentIndex == nil && segment.timeMapping.target.start >= fromTime  {
                    fromTimeSegmentIndex = index
                }

                if fromTimeSegmentIndex != nil {
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
        }
        
        // Remove whitespaces on edges
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // make sure first letter is capitalized
        // not capitalized when we're dealing with expresssions that come from chopped up notesRange
        text = text.capitalizeFirstLetter()

        return text
    }
    
    // MARK: - Player Methods
    
    func play(
        from: CMTime? = nil,
        to: CMTime? = nil,
        onStartHandler: (() -> Void)? = nil,
        secondElapseHandler: (() -> Void)? = nil,
        segmentBoundaryHandler: (() -> Void)? = nil,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Play Note =====")
        
        if self.tracks[0].segments.count == 0 {
            // havent recorded anything
            // Play Sound
            soundEngine.error()
            
            // Give haptic feedback
            hapticEngine.error()

            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {[weak self] timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: self!.vc)
                let synthesizerItem = SynthesizerItem(
                    synthesizer: self!.vc!.speechSynthesizer,
                    text: "Note is empty.",
                    voice: voice,
                    rate: self!.vc!.echoRate,
                    volume: self!.vc!.playbackVolume
                )
                
                Utils.runSpeechSynthesizer(item: synthesizerItem)
            }
            
            // Execute start Handler
            onStartHandler?()
            return
        }
        
        if self.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            self.stopListeningForVoiceCommands(pause: true)
        }
        
        // Play Sound
        if !self.isListeningForSpeech {
            soundEngine.play()
        }
        
        if self.vc!.speechSynthesizer.isSpeaking {
            print("\tPause speech synthesizer to play speech audio.\n")
            self.vc!.speechSynthesizer.stopSpeaking(at: .immediate)
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
            note: self,
            startTime: self.startPlaybackAt!,
            rate: self.playbackRate,
            volume: self.vc!.playbackVolume,
            onStartHandler: onStartHandler
        )

        if let player = player {
            self.player = player
        }
    }
    
    func playSentence(
        number: Int,
        onStartHandler: (() -> Void)? = nil,
        secondElapseHandler: (() -> Void)? = nil,
        segmentBoundaryHandler: (() -> Void)? = nil,
        onFinishHandler: (() -> Void)? = nil
    ) {
        
        // Get current time
        let currentTime = player.currentTime()
        if currentTime > CMTime.zero {
            player.play()
            return
        }
        
        if self.tracks[0].segments.count == 0 {
            // havent recorded anything
            // Play Sound
            soundEngine.error()

            // Give haptic feedback
            hapticEngine.error()

            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {[weak self] timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: self!.vc)
                let synthesizerItem = SynthesizerItem(
                    synthesizer: self!.vc!.speechSynthesizer,
                    text: "Note is empty.",
                    voice: voice,
                    rate: self!.vc!.echoRate,
                    volume: self!.vc!.playbackVolume
                )
                
                Utils.runSpeechSynthesizer(item: synthesizerItem)
            }
            
            // Execute start Handler
            onStartHandler?()
            return
        }
        
        // Play Sound
        soundEngine.play()
        
        if self.vc!.speechSynthesizer.isSpeaking {
            print("===== Pause speech synthesizer to play speech audio =====")
            self.vc!.speechSynthesizer.stopSpeaking(at: .immediate)
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
            note: self,
            startTime: self.startPlaybackAt!,
            rate: self.playbackRate,
            volume: self.vc!.playbackVolume,
            onStartHandler: onStartHandler
        )
        
        if let player = player {
            self.player = player
        }
    }

    func playSentence(
        forTrackTime: CMTime,
        onStartHandler: (() -> Void)? = nil,
        secondElapseHandler: (() -> Void)? = nil,
        segmentBoundaryHandler: (() -> Void)? = nil,
        onFinishHandler: (() -> Void)? = nil
    ) {
        
        // Get current time
        let currentTime = player.currentTime()
        if currentTime > CMTime.zero {
            player.play()
            return
        }
        
        if self.tracks[0].segments.count == 0 {
            // havent recorded anything
            // Play Sound
            soundEngine.error()
            
            // Give haptic feedback
            hapticEngine.error()

            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {[weak self] timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: self!.vc)
                let synthesizerItem = SynthesizerItem(
                    synthesizer: self!.vc!.speechSynthesizer,
                    text: "Note is empty.",
                    voice: voice,
                    rate: self!.vc!.echoRate,
                    volume: self!.vc!.playbackVolume
                )
                
                Utils.runSpeechSynthesizer(item: synthesizerItem)
            }
            
            // Execute start Handler
            onStartHandler?()
            return
        }
        
        // Play Sound
        soundEngine.play()
        
        if self.vc!.speechSynthesizer.isSpeaking {
            print("===== Pause speech synthesizer to play speech audio =====")
            self.vc!.speechSynthesizer.stopSpeaking(at: .immediate)
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
            note: self,
            startTime: self.startPlaybackAt!,
            rate: self.playbackRate,
            volume: self.vc!.playbackVolume,
            onStartHandler: onStartHandler
        )
        
        if let player = player {
            self.player = player
        }
    }
    
    func replayCurrentSentence(handler: (() -> Void)? = nil) {
        
        // Play Sound
        soundEngine.repeatSegment()

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
        print("===== Pause Playing Note =====")
        player.pause()
        handler?()
    }
    
    func stop(handler: (() -> Void)? = nil) {
        print("===== Stop Playing Note =====")
        player.pause()
        player.replaceCurrentItem(with: nil)
        self.startPlaybackAt = nil
        self.startPlaybackAt = nil
        
        if self.pausedListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            self.startListeningForVoiceCommands(
                soundIntensityHandler: self.soundIntensityHandler,
                pitchHandler: self.pitchHandler
            )
        }
        
        if self.playerLoopTimer != nil {
            self.playerLoopTimer?.invalidate()
        }

        handler?()
    }
    
    // MARK: - Echo Methods
    // Computer understanding of the note
    func startEcho(onStartHandler: (() -> Void)? = nil, onCompletionHandler: (() -> Void)? = nil) {
        if player.isPlaying {
            print("\tStop speech audio to play speech synthesizer")
            self.stop()
        }
        
        if self.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            self.stopListeningForVoiceCommands(pause: true) {
                self.handleEcho(onStartHandler: onStartHandler, onCompletionHandler: onCompletionHandler)
            }
        } else if self.isListeningForCommands && AVAudioSession.isHeadphonesConnected {
            self.handleEcho(onStartHandler: onStartHandler, onCompletionHandler: onCompletionHandler)
        }
        
        if self.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
            self.stopListeningForSpeech(pause: true) {
                self.handleEcho(onStartHandler: onStartHandler, onCompletionHandler: onCompletionHandler)
            }
        } else if self.isListeningForSpeech && AVAudioSession.isHeadphonesConnected {
            self.handleEcho(onStartHandler: onStartHandler, onCompletionHandler: onCompletionHandler)
        }
    }
    
    func pauseEcho(handler: (() -> Void)? = nil) {
        print("===== Pause Echo =====")
        self.vc!.speechSynthesizer.pauseSpeaking(at: .immediate)
        handler?()
    }
    
    func stopEcho(handler: (() -> Void)? = nil) {
        print("===== Stop Echo =====")
        self.vc!.speechSynthesizer.stopSpeaking(at: .immediate)
        handler?()
    }
    
    func handleEcho(onStartHandler: (() -> Void)? = nil, onCompletionHandler: (() -> Void)? = nil) {
        // Play Sound
        soundEngine.play()
        
        if self.echoIsPaused {
            // continue last echo
            print("===== Continue Echo =====")
            self.vc!.speechSynthesizer.continueSpeaking()
        } else {
            // start new echo
            print("===== Start Echo =====")
            print("\tInitiate new speech synthesizer utterance")
            let noteText = self.getText() // make forEcho true when we're doing voice only
            let synthesizerItem = SynthesizerItem(
                synthesizer: self.vc!.speechSynthesizer,
                text: noteText,
                voice: speaker.playbackVoice,
                rate: self.vc!.echoRate,
                volume: self.vc!.playbackVolume
            )
            
            self.vc!.synthesizerQueue.enqueue(synthesizerItem)
            self.vc!.exhaustSynthesizerQueue()
            self.isPlayingEcho = true
            
            // cache range of echo segments
            self.lastEchoSegmentRange = 0..<(self.noteSegments.count + self.noteBuffer.count)
            
            if let onCompletionHandler = onCompletionHandler {
                self.scheduleTempOnEchoFinishHandler?(onCompletionHandler)
            }
        
            onStartHandler?()
        }
    }
    
    func echoText(text: String) {
        print("===== Echo note text =====")
        
        // Stop existing echo
        if self.vc!.speechSynthesizer.isSpeaking {
            self.vc!.speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        if player.isPlaying {
            print("\tStop speech audio to play speech synthesizer")
            self.stop()
        }
        
        let echoText = text.trimTrailingPunctuation()
        print("\techoing: \"\(echoText)\"")
        
        
        let synthesizerItem = SynthesizerItem(
            synthesizer: self.vc!.speechSynthesizer,
            text: echoText,
            voice: speaker.playbackVoice,
            rate: self.vc!.echoRate,
            volume: self.vc!.playbackVolume
        )
        
        self.vc!.synthesizerQueue.enqueue(synthesizerItem)
        self.vc!.exhaustSynthesizerQueue()
        self.isPlayingEcho = true
    }
    
    // MARK: - Mutating Methods
    
    // TRACKS MUST BE COLLAPSED INTO SINGLE TRACK TO USE THIS
    func trim(keeping: CMTimeRange, permanent: Bool = false, overwrite: Bool = false, onCompletionHandler: (() -> Void)? = nil) {
        let keepRange = keeping
        print("===== Trim Note keeping section starting: \(keepRange.start.seconds) until: \(keepRange.end.seconds) =====")
        if self.noteBuffer.count > 0 {
            fatalError("===== There was a problem trimming note. Note buffer was not committed =====")
        }
        
        var newNoteSegments = [NoteSegment]()
        var silenceIndices = [Int]()
        if permanent {
            print("\tModify start and end times...")
            self.startTime = CMTime.zero
            self.endTime = keepRange.duration
            
            // Create new filename if not or can't overwrite
            if !overwrite || self._fileType != .m4a {
                print("\tCreate new filename ...")
                self.filename = "note-\(UUID().uuidString)"
            }
            
            print("\tExporting and modifying segments...")
            Utils.exportNote(
                note: self,
                filename: self.filename,
                fileType: self.fileType,
                timeRange: keepRange
            ) {
                // Manage Segments
                var lastEnd = CMTime.zero
                if keepRange.start == CMTime.zero {
                    print("\tNote Segments don't require time-shifting...")
                    // requires no time-shifting if on the left side of range
                    for seg in self.noteSegments {
                        if keepRange.containsTimeRange(seg.timeMapping.target) {
                            let segment = seg.duplicate()
                            
                            // Save silence index
                            if segment.isSilence() {
                                silenceIndices.append(newNoteSegments.count)
                            }

                            // Add segment to array
                            newNoteSegments.append(segment)
                            
                            // Update lastEnd
                            lastEnd = seg.timeMapping.target.end
                        }
                    }
                } else {
                    print("\tNote Segments require time-shifting...")
                    // requires time-shifting if on the right side of range
                    for seg in self.noteSegments {
                        if keepRange.containsTimeRange(seg.timeMapping.target) {
                            let shiftedSegment = seg.duplicate(
                                timeRange: CMTimeRangeMake(
                                    start: lastEnd,
                                    duration: seg.timeMapping.target.duration
                                )
                            )

                            // Save silence index
                            if shiftedSegment.isSilence() {
                                silenceIndices.append(newNoteSegments.count)
                            }

                            // Add segment to array
                            newNoteSegments.append(shiftedSegment)

                            // Update lastEnd
                            lastEnd = CMTimeAdd(lastEnd, seg.timeMapping.target.duration)
                        }
                    }
                }

                print("\tUpdate index, backgroundNoise, avgPauseDuration, and speakingRate...")
                var avgPauseDuration: Double = silenceIndices.reduce(0, { result, i in
                   return result + newNoteSegments[i].timeMapping.target.duration.seconds
                }) / Double(silenceIndices.count)
                avgPauseDuration = avgPauseDuration.rounded(toPlaces: DEFAULT_FIG_COUNT)

                var speakingRate: Double = newNoteSegments.reduce(0, { result, item in
                   if !item.isPunctuation() && !item.isSilence() {
                       return result + 1
                   }
                   
                   return result
                }) / Double(self.duration.seconds / Double(TimeConstant.secsPerMin))
                speakingRate = speakingRate.rounded(toPlaces: DEFAULT_FIG_COUNT)

                // Update Index, Background Noise, AvgPauseDuration, SpeakingRate
                for (index, segment) in newNoteSegments.enumerated() {
                    // Set segment index
                    // We might need to update indices if we lost segments above
                    segment.setIndex(index: index)

                    // Set background noise
                    segment.setBackgroundNoise(noise: self.getBackgroundNoise())

                    // Set avgPauseDuration
                    segment.setAvgPauseDuration(duration: avgPauseDuration)

                    // Set speakingRate
                    segment.setSpeakingRate(rate: speakingRate)
                }
                
                print("\tUpdate note file type...")
                // Change File Type
                // We need this to be placed before normalizeSegments so newNoteSegments are
                // updated with new trackURL
                self.setFileType(fileType: .m4a)

                print("\tNormalize segments to correct for any time-related errors...")
                // Correct any time-related errors
                // Normalize Segments will setSegments
                // Make sure we update segments to reflect new track URL
                let _ = self.normalizeSegments(
                    segments: newNoteSegments,
                    normalizeType: .target,
                    replaceNoteDetails: true,
                    saveSegments: true
                )

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
                print("\tTrim Note from the right and left side...")
                let removeRightRange = CMTimeRangeFromTimeToTime(start: keepRange.end, end: self.duration)
                let removeLeftRange = CMTimeRangeFromTimeToTime(start: CMTime.zero, end: keepRange.start)
                
                // Remove Time Range
                self.removeTimeRange(removeRightRange)
                self.removeTimeRange(removeLeftRange)
            } else if CMTimeSubtract(self.duration, keepRange.end) > CMTime.zero && CMTimeSubtract(keepRange.start, CMTime.zero) <= CMTime.zero {
                // Remove from right side only
                print("\tTrim Note from the right side only...")
                let removeRightRange = CMTimeRangeFromTimeToTime(start: keepRange.end, end: self.duration)
                
                // Remove Time Range
                self.removeTimeRange(removeRightRange)
            } else if CMTimeSubtract(self.duration, keepRange.end) <= CMTime.zero && CMTimeSubtract(keepRange.start, CMTime.zero) > CMTime.zero {
                // Remove from left side only
                print("\tTrim Note from the left side only...")
                let removeLeftRange = CMTimeRangeFromTimeToTime(start: CMTime.zero, end: keepRange.start)
                
                // Remove Time Range
                self.removeTimeRange(removeLeftRange)
            }

            print("\tModify note start and end times...")
            self.startTime = CMTime.zero
            self.endTime = keepRange.duration

            print("\tFiltering note segments...")
            var lastEnd = CMTime.zero
            if keepRange.start == CMTime.zero {
                print("\tNote Segments don't require time-shifting...")
                // requires no time-shifting if on the left side of range
                for seg in self.noteSegments {
                    if keepRange.containsTimeRange(seg.timeMapping.target) {
                        let segment = seg.duplicate()
                        
                        // Save silence index
                        if segment.isSilence() {
                            silenceIndices.append(newNoteSegments.count)
                        }

                        // Add segment to array
                        newNoteSegments.append(segment)
                        
                        // Update lastEnd
                        lastEnd = seg.timeMapping.target.end
                    }
                }
            } else {
                print("\tNote Segments require time-shifting...")
                // requires time-shifting if on the right side of range
                for seg in self.noteSegments {
                    if keepRange.containsTimeRange(seg.timeMapping.target) {
                        let shiftedSegment = seg.duplicate(
                            timeRange: CMTimeRangeMake(
                                start: lastEnd,
                                duration: seg.timeMapping.target.duration
                            )
                        )

                        // Save silence index
                        if shiftedSegment.isSilence() {
                            silenceIndices.append(newNoteSegments.count)
                        }

                        // Add segment to array
                        newNoteSegments.append(shiftedSegment)

                        // Update lastEnd
                        lastEnd = CMTimeAdd(lastEnd, seg.timeMapping.target.duration)
                    }
                }
            }
            
            print("\tUpdate index, backgroundNoise, avgPauseDuration, and speakingRate...")

            var avgPauseDuration: Double = silenceIndices.reduce(0, { result, i in
               return result + newNoteSegments[i].timeMapping.target.duration.seconds
            }) / Double(silenceIndices.count)
            avgPauseDuration = avgPauseDuration.rounded(toPlaces: DEFAULT_FIG_COUNT)

            var speakingRate: Double = newNoteSegments.reduce(0, { result, item in
               if !item.isPunctuation() && !item.isSilence() {
                   return result + 1
               }
               
               return result
            }) / Double(self.duration.seconds / Double(TimeConstant.secsPerMin))
            speakingRate = speakingRate.rounded(toPlaces: DEFAULT_FIG_COUNT)

            // Update Index, Background Noise, AvgPauseDuration, SpeakingRate, Selection Anchor, Selection Focus, Selection Cached Anchor
            var replaceSelectionAnchor = false
            var replaceSelectionFocus = false
            var replaceSelectionCachedAnchor = false
            for (index, segment) in newNoteSegments.enumerated() {
                // Set segment index
                // We might need to update indices if we lost segments above
                segment.setIndex(index: index)

                // Set background noise
                segment.setBackgroundNoise(noise: self.getBackgroundNoise())

                // Set avgPauseDuration
                segment.setAvgPauseDuration(duration: avgPauseDuration)

                // Set speakingRate
                segment.setSpeakingRate(rate: speakingRate)
                
                // determine if we need to update selection cursor anchor
                // we need to get these values early before we replace segments
                // so that selection cursor doesn't lose reference to its anchor
                if segment == selectionCursor.anchor {
                    replaceSelectionAnchor = true
                }
                
                // determine if we need to update selection cursor focus
                // we need to get these values early before we replace segments
                // so that selection cursor doesn't lose reference to its focus
                if segment == selectionCursor.focus {
                    replaceSelectionFocus = true
                }
                
                // determine if we need to update selection cursor cached anchor
                // we need to get these values early before we replace segments
                // so that selection cursor doesn't lose reference to its cached anchor
                if segment == selectionCursor.cachedAnchor {
                    replaceSelectionCachedAnchor = true
                }
            }
            
            print("\tUpdate Note Segments...")
            // Update Segments
            // We cannot go through setSegments method because these note segments might not be normalized
            // Compute segment sentences
            let segmentsWithUpdatedSentences = updateSegmentSentences(segments: newNoteSegments)
            self.noteSegments = segmentsWithUpdatedSentences.count == newNoteSegments.count ? segmentsWithUpdatedSentences : newNoteSegments
            
            // update selection properties
            for seg in self.noteSegments {
                // update selection anchor
                if replaceSelectionAnchor && seg.isEqual(selectionCursor.anchor) {
                    selectionCursor.setAnchor(segment: seg)
                }
                
                // update selection focus
                if replaceSelectionFocus && seg.isEqual(selectionCursor.focus) {
                    selectionCursor.setFocus(segment: seg)
                }
                
                // update selection cached anchor
                if replaceSelectionCachedAnchor && seg.isEqual(selectionCursor.cachedAnchor) {
                    selectionCursor.setCachedAnchor(segment: seg)
                }
            }

            // Check Representation Invariant
            self.checkRep()
            
            // Run Completion Handler
            onCompletionHandler?()
        }
    }
    
    // Mutates Segments
    func updateSegmentSentences(segments: [NoteSegment]) -> [NoteSegment] {
        print("===== Update Segment Sentences =====")
        var currentSentenceNumber = 0
        var sentenceText = ""
        var sentenceStartTime = CMTime.zero
        var sentenceEndTime: CMTime
        // Holds the index of the first segment without a sentence
        var leftStaleSegmentIndex = 0
        // make sure silences get sentence number of prior.
        for (index, segment) in segments.enumerated() {
            if index + 1 == segments.count {
                // We've reached the end of the note. Update sentence data
                sentenceEndTime = segment.timeMapping.target.end
                
                if !segment.isVoiceCommandWord() {
                    sentenceText += segment.getText(
                        withTemporalSuggestions: self.withTemporalSuggestions,
                        withPunctuationSuggestions: self.withPunctuationSuggestions,
                        withFormattingSuggestions: self.withFormattingSuggestions,
                        strictlyAsWord: self.withTextStrictlyAsWords,
                        withSpacePrefix: true
                    )
                }
                
                let sentence = Sentence(
                    number: currentSentenceNumber,
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
            } else if segment.isVoiceCommandWord() {
                // Don't add word to sentenceText
                // We don't want these in Sentence class object instances
            } else if segment.isSilence() {
                if index > 0 && !segments[index - 1].isSentenceTerminator() {
                    // Do nothing if last segment wasn't a sentence boundary
                } else if index > 0 && segments[index - 1].isSentenceTerminator() {
                    // We've hit a sentence boundary. Update sentences
                    // Update sentence data
                    sentenceEndTime = segment.timeMapping.target.start
                    sentenceText += segment.getText(
                        withTemporalSuggestions: self.withTemporalSuggestions,
                        withPunctuationSuggestions: self.withPunctuationSuggestions,
                        withFormattingSuggestions: self.withFormattingSuggestions,
                        strictlyAsWord: self.withTextStrictlyAsWords,
                        withSpacePrefix: true
                    )
                    let sentence = Sentence(
                        number: currentSentenceNumber,
                        text: sentenceText.trimmingCharacters(in: .whitespacesAndNewlines),
                        timeRange: CMTimeRangeFromTimeToTime(
                            start: sentenceStartTime,
                            end: sentenceEndTime
                        )
                    )
                    currentSentenceNumber += 1
                    sentenceStartTime = segment.timeMapping.target.start
                    // Clear sentence
                    sentenceText = ""
                    
                    // Add sentence to every segment before this one
                    for i in leftStaleSegmentIndex..<index {
                        segments[i].setSentence(sentence: sentence)
                    }
                    leftStaleSegmentIndex = index
                }
            } else if !segment.isSilence() && !segment.isVoiceCommandWord() {
                // We can't let silences in here because getSentenceNumber can't handle empty strings
                let sentenceNumber = getSentenceNumber(segments: segments, segment: segment)
                
                if sentenceNumber != currentSentenceNumber && sentenceNumber == currentSentenceNumber + 1 {
                    // We've hit a sentence boundary. Update sentences
                    // print("We've hit a sentence boundary. Update sentence data")
                    // Update sentence data
                    sentenceEndTime = segment.timeMapping.target.start
                    let sentence = Sentence(
                        number: currentSentenceNumber,
                        text: sentenceText.trimmingCharacters(in: .whitespacesAndNewlines),
                        timeRange: CMTimeRangeFromTimeToTime(
                            start: sentenceStartTime,
                            end: sentenceEndTime
                        )
                    )
                    currentSentenceNumber = sentenceNumber
                    sentenceStartTime = segment.timeMapping.target.start
                    // New sentence
                    sentenceText = segment.getText(
                        withTemporalSuggestions: self.withTemporalSuggestions,
                        withPunctuationSuggestions: self.withPunctuationSuggestions,
                        withFormattingSuggestions: self.withFormattingSuggestions,
                        strictlyAsWord: self.withTextStrictlyAsWords,
                        withSpacePrefix: true
                    )
                    
                    // Add sentence to every segment before this one
                    for i in leftStaleSegmentIndex..<index {
                        segments[i].setSentence(sentence: sentence)
                    }

                    leftStaleSegmentIndex = index
                } else if sentenceNumber == currentSentenceNumber {
                    // Add word to sentence
                    sentenceText += segment.getText(
                        withTemporalSuggestions: self.withTemporalSuggestions,
                        withPunctuationSuggestions: self.withPunctuationSuggestions,
                        withFormattingSuggestions: self.withFormattingSuggestions,
                        strictlyAsWord: self.withTextStrictlyAsWords,
                        withSpacePrefix: true
                    )
                } else {
                    fatalError("\t[Error] There was a problem updating segment sentences. Unexpected index behavior")
                }
            }
        }
        
        return segments
    }
    
    // time must be at a segment boundary to make everything work correctly
    // assumes buffer is empty
    func insertPassage(segments: [NoteSegment], at time: CMTime) {
        print("===== Inserting Passage =====")
        guard self.noteBuffer.count == 0 else {
            fatalError("\t[Error] There was a problem inserting passage. Buffer was not empty")
        }
        print("\tMerging argument segments into committed segments...")
        var updatedSegments = [NoteSegment]()
        var insertedSegments = false
        
        if self.noteSegments.count > 0 {
            // if we have segments
            // find out where to insert passage
            for segment in self.noteSegments {
                if segment.timeMapping.target.end < time {
                    // add to array if before insert time
                    updatedSegments.append(segment)
                } else if segment.timeMapping.target.end >= time && !insertedSegments {
                    // encountered first segment that occurs after insert time
                    // add segment array here
                    insertedSegments = true
                    updatedSegments.append(segment)
                    updatedSegments = updatedSegments + segments
                } else if segment.timeMapping.target.end >= time {
                    // place remaining segments after inserted segments
                    updatedSegments.append(segment)
                }
            }
        } else {
            // we do not have segments yet
            // set passage as new segments
            updatedSegments = segments
        }

        let _ = self.normalizeSegments(
            segments: updatedSegments,
            normalizeType: .target,
            replaceNoteDetails: true,
            saveSegments: true,
            saveToLowLevelRepr: true
        )
        
        print("\tSuccessfully inserted passage into note!")
    }
    
    // time must be at a segment boundary to make everything work correctly
    // assumes buffer is empty
    func removePassage(range: CMTimeRange) {
        print("===== Removing Passage =====")
        guard self.noteBuffer.count == 0 else {
            fatalError("\t[Error] There was a problem inserting passage. Buffer was not empty")
        }
        print("\tFiltering out passage segments...")
        var updatedSegments = [NoteSegment]()
        
        let beforeTime = range.start
        let afterTime = range.end

        for segment in self.noteSegments {
            if segment.timeMapping.target.start <= beforeTime {
                // add to array if before passage to be removed
                updatedSegments.append(segment)
            } else if segment.timeMapping.target.end >= afterTime {
                // add to array if after passage to be removed
                updatedSegments.append(segment)
            }
        }

        let _ = self.normalizeSegments(
            segments: updatedSegments,
            normalizeType: .target,
            replaceNoteDetails: true,
            saveSegments: true,
            saveToLowLevelRepr: true
        )

        print("\tSuccessfully removed passage from note!")
    }
    
    func updatePassage(segments: [NoteSegment], range: CMTimeRange) {
        print("===== Updating Passage =====")
        print("\tRemoving current passsage from note...")
        self.removePassage(range: range)
        print("\tAdding new passage to note...")
        let _ = self.insertPassage(segments: segments, at: range.start)
        print("\tSuccessfully updated passage in note!")
    }
    
    // MARK: - Setters
    
    func setSpeakerPitch(to pitch: Pitch) {
        speaker.pitch = pitch
        
        checkRep()
    }
    
    // Audio variable
    func setSkipPunctuation(to skip: Bool) {
        self.skipPunctuation = skip
        
        checkRep()
    }
    
    // Audio variable
    func setSkipSilence(to skip: Bool) {
        self.skipSilence = skip
        
        checkRep()
    }
    
    // Audio variable
    func setWithPassiveEcho(to value: Bool) {
        self.withPassiveEcho = value
        
        checkRep()
    }
    
    func setPlaybackRate(to rate: Float) {
        print("===== Set Playback Rate: \(rate) =====")
        self.playbackRate = rate
        
        if self.isPlayingNote {
            player.rate = self.playbackRate
        }

        checkRep()
    }
    
    func setPlaybackRate(wpm: Float) {
        print("===== Set Playback Rate: \(wpm)wpm =====")
        self.playbackRate = wpm / Float(self.avgSpeakingRate).rounded(toPlaces: DEFAULT_FIG_COUNT)
        
        if self.isPlayingNote {
            player.rate = self.playbackRate
        }

        checkRep()
    }
    
    // We lack a checkRep here because we use it mid
    // operation in trimNote when the representation invariant is broken
    func setFileType(fileType: AVFileType) {
        self._fileType = fileType
    }
    
    // Visual variable
    func setWithTemporalSuggestions(to value: Bool) {
        self.withTemporalSuggestions = value
        
        // We can only have one suggestion type on at a time
        // Deactivate punctuation suggestions if active
        if value && self.withPunctuationSuggestions {
            self.withTemporalSuggestions = false
        }
        
        // Make sure new setting is reflecting visually
        self.handleOnListenUpdate()
        
        checkRep()
    }
    
    // Visual variable
    func setWithPunctuationSuggestions(to value: Bool) {
        self.withPunctuationSuggestions = value
        
        // We can only have one suggestion type on at a time
        // Deactivate space suggestions if active
        if value && self.withTemporalSuggestions {
            self.withTemporalSuggestions = false
        }
        
        // Make sure new setting is reflecting visually
        self.handleOnListenUpdate()
        
        checkRep()
    }
    
    // Visual variable
    func setWithFormattingSuggestions(to value: Bool) {
        self.withFormattingSuggestions = value
        
        // Make sure new setting is reflecting visually
        self.handleOnListenUpdate()
        
        checkRep()
    }
    
    // Visual variable
    func setWithTextStrictlyAsWords(to value: Bool) {
        self.withTextStrictlyAsWords = value
        
        // Make sure new setting is reflecting visually
        self.handleOnListenUpdate()

        checkRep()
    }
    
    // note details refer to note, sourceURL, and trackID
    // we have to duplicate segments to reset these
    // thus is a costly computation
    // TODO: Confirm that source and target don't affect setting segments to low-level representation
    func setSegments(segments: [NoteSegment], replaceNoteDetails: Bool = false, saveToLowLevelRepr: Bool = false) {
        print("===== Set Segments =====")
        var setSegmentNote = false
        // set note reference in segments
        if segments.count > 0 && segments[0].note == nil {
            print("\tSegments have no note reference. Turning on flag to set reference with currrent note...")
            setSegmentNote = true
        }
        
        var updatedSegments = [NoteSegment]()
        if replaceNoteDetails {
            print("\tReplacing note details...")
            for segment in segments {
                var seg: NoteSegment
                seg = segment.duplicate(
                    newNote: self
                )

                // Add segment to array
                updatedSegments.append(seg)
            }
        }
        
        if setSegmentNote && !replaceNoteDetails {
            // Replace Note
            for segment in segments {
                segment.setNote(note: self)
            }
        }
        
        var finalSegments = replaceNoteDetails ? updatedSegments : segments

        // attempt to replace segments
        do {
            // Compute segment sentences
            let segmentsWithUpdatedSentences = updateSegmentSentences(segments: finalSegments)
            finalSegments = segmentsWithUpdatedSentences.count == finalSegments.count ? segmentsWithUpdatedSentences : finalSegments
            
            self.noteSegments = finalSegments

            if saveToLowLevelRepr {
                // only save to mutable track if we're on first take or explicit flag is set
                print("\tUpdating lower level track representation...")
                try self.tracks[0].validateSegments(finalSegments)
                self.tracks[0].segments = finalSegments
            }
            
            self.endTime = self.noteSegments.last!.timeMapping.target.end
            
            // make sure to update selection objects
            print("\tDeterming in updates need to be made to selection cursor properties...")
            for segment in self.noteSegments {
                if segment.isEqual(selectionCursor.anchor) {
                    print("\tUpdating selection cursor anchor...")
                    selectionCursor.setAnchor(segment: segment)
                }
                
                if segment.isEqual(selectionCursor.focus) {
                     print("\tUpdating selection cursor focus...")
                    selectionCursor.setFocus(segment: segment)
                }
                if segment.isEqual(selectionCursor.cachedAnchor) {
                     print("\tUpdating selection cursor cached anchor...")
                    selectionCursor.setCachedAnchor(segment: segment)
                }
            }

            print("\tSuccessfully updated note segments!")
        } catch {
            fatalError("\t[Error] There was a problem updating note segments")
        }

        checkRep()
    }
    
    // MARK: - Getters
    
    // https://developer.apple.com/documentation/avfoundation/avassetexportpresetpassthrough
    // https://stackoverflow.com/questions/58025109/exporting-mp3-with-avassetexportsession
    // We do not compute sentences for segments here because the segments lack a reference to an note
    // Without a reference to an note, they cannot compute getText correctly
    // MUST HAVE A SINGLE COLLAPSED TRACK
    func duplicate(onCompletionHandler: @escaping (_ note: Note?) -> Void) {
        print("===== Duplicate Note =====")
        guard self.noteBuffer.count == 0 else {
            fatalError("\t[Error] There was a problem inserting passage. Buffer was not empty")
        }

        // Export Note
        let duplicateFilename = "note-\(UUID().uuidString)"
        Utils.exportNote(
            note: self,
            filename: duplicateFilename,
            fileType: self.fileType,
            timeRange: CMTimeRangeMake(start: CMTime.zero, duration: self.duration)
        ) {
            onCompletionHandler(Note(
                vc: self.vc,
                filename: duplicateFilename,
                fileType: .m4a,
                speaker: self.speaker,
                minPower: self.minPower,
                segments: self.noteSegments, // Will copy segments so there are not multiple pointers to a single segment
                withOnDeviceRecognition: self.useOnDeviceRecognition,
                withTemporalSuggestions: self.withTemporalSuggestions,
                withPunctuationSuggestions: self.withPunctuationSuggestions,
                withFormattingSuggestions: self.withFormattingSuggestions,
                withTextStrictlyAsWords: self.withTextStrictlyAsWords
            ))
        }
    }
    
    func getSentenceDetails(number: Int) -> Sentence? {
        print("===== Get Sentence Details =====")
        guard self.noteBuffer.count == 0 else {
            fatalError("\t[Error] There was a problem inserting passage. Buffer was not empty")
        }

        for segment in self.noteSegments {
            if segment.getSentence().number == number {
                return segment.getSentence()
            }
        }
        
        return nil
    }

    func getSentenceDetails(forTrackTime: CMTime) -> Sentence? {
        print("===== Get Sentence Details =====")
        guard self.noteBuffer.count == 0 else {
            fatalError("\t[Error] There was a problem inserting passage. Buffer was not empty")
        }

        for segment in self.noteSegments {
            if segment.getSentence().timeRange.containsTime(forTrackTime) {
                return segment.getSentence()
            }
        }
        
        return nil
    }
    
    func extractSentence(number: Int, onCompletionHandler: @escaping (_ sentence: Note?) -> Void) {
        print("===== Extract Sentence =====")
        guard self.noteBuffer.count == 0 else {
            fatalError("\t[Error] There was a problem inserting passage. Buffer was not empty")
        }

        for segment in self.noteSegments {
            if segment.getSentence().number == number {
                segment.createSentenceNote() { sentence in
                    onCompletionHandler(sentence)
                }
                return
            }
        }
    }
    
    func extractSentence(forTrackTime: CMTime, onCompletionHandler: @escaping (_ sentence: Note?) -> Void) {
        print("===== Extract Sentence =====")
        guard self.noteBuffer.count == 0 else {
            fatalError("\t[Error] There was a problem inserting passage. Buffer was not empty")
        }

        for segment in self.noteSegments {
            if segment.getSentence().timeRange.containsTime(forTrackTime) {
                segment.createSentenceNote() { sentence in
                    onCompletionHandler(sentence)
                }
                break
            }
        }
    }
    
    func extractSentence(type: SentencePosition, onCompletionHandler: @escaping (_ sentence: Note?) -> Void) {
        let currentTime = player.currentTime()
        self.extractSentence(forTrackTime: currentTime) { sentence in
            switch type {
            case .current:
                onCompletionHandler(sentence)
                break
            case .previous:
                let timestamp = floor(Note.defaultSegmentTimescale * (currentTime.seconds - DIFFERENCE))
                let previousTime = CMTimeMake(
                    value: Int64(timestamp),
                    timescale: Int32(Note.defaultSegmentTimescale)
                )
                self.extractSentence(forTrackTime: previousTime) { sentence in
                    onCompletionHandler(sentence)
                }
                break
            case .next:
                let timestamp = floor(Note.defaultSegmentTimescale * (currentTime.seconds + DIFFERENCE))
                let nextTime = CMTimeMake(
                    value: Int64(timestamp),
                    timescale: Int32(Note.defaultSegmentTimescale)
                )
                self.extractSentence(forTrackTime: nextTime) { sentence in
                    onCompletionHandler(sentence)
                }
                break
            }
        }
        
    }
    
    func getSegment(segment: NoteSegment? = nil, type: SegmentPosition) -> NoteSegment? {
        var currentTime: CMTime
        if let segment = segment {
            currentTime = segment.timeMapping.target.start
        } else {
            currentTime = player.currentTime()
        }
        let currentSegment = self.getSegment(forTrackTime: currentTime)
        var result: NoteSegment?
        if let segment = currentSegment {
            switch type {
            case .current:
                result = segment
                break
            case .previous:
                if let (currentNoteTrackType, currentSegmentIndex) = getSegmentLocation(segment: segment), currentSegmentIndex > 0 {
                    if currentNoteTrackType == .committed {
                        // committed
                        result = self.noteSegments[currentSegmentIndex - 1]
                    } else {
                        // buffer
                        result = self.noteBuffer[currentSegmentIndex - 1]
                    }
                }
                break
            case .next:
                if let (currentNoteTrackType, currentSegmentIndex) = getSegmentLocation(segment: segment), currentSegmentIndex + 1 < self.noteSegments.count {
                    if currentNoteTrackType == .committed {
                        // committed
                        result = self.noteSegments[currentSegmentIndex + 1]
                    } else {
                        // buffer
                        result = self.noteBuffer[currentSegmentIndex + 1]
                    }
                }
                break
            }
        }

        return result
    }
    
    func getSegment(forTrackTime: CMTime) -> NoteSegment? {
        var segment: NoteSegment?
        // check committed segments
        for seg in self.noteSegments {
            if seg.timeMapping.target.containsTime(forTrackTime) {
                segment = seg
                return segment
            }
        }
        
        let committedTrackLastSegment = self.noteSegments.last
        // check buffer segments
        for seg in self.noteBuffer {
            // We subtract because segments in track two do not factor time from track one
            if let committedTrackLastSegment = committedTrackLastSegment, seg.timeMapping.target.containsTime(CMTimeSubtract(forTrackTime, committedTrackLastSegment.timeMapping.target.end)) {
                segment = seg
                return segment
            }
        }
        
        return nil
    }
    
    func getSegmentLocation(segment: NoteSegment) -> (NoteTrackType, Int)? {
        if segment.isCommitted() {
            // only committed segments have an index
            return (.committed, segment.getIndex())
        } else {
            // check commmitted
            for (index, s) in self.noteSegments.enumerated() {
                if (s == segment) {
                    return (.committed, index)
                }
            }
            
            // check buffer
            for (index, s) in self.noteBuffer.enumerated() {
                if (s == segment) {
                    return (.buffer, index)
                }
            }
        }
        
        return nil
    }
    
    // We use .lowercased() throughout the method because sometimes word is made uppercase if we have PunctuationSuggestions on which will capitalize on-demand
    // To elimate this we make everything lowercase
    func getSegmentTextRange(of segment: NoteSegment) -> NSRange? {
        var characterRange : NSRange
        let word = segment.getText(
            withTemporalSuggestions: self.withTemporalSuggestions,
            withPunctuationSuggestions: self.withPunctuationSuggestions,
            withFormattingSuggestions: self.withFormattingSuggestions,
            strictlyAsWord: self.withTextStrictlyAsWords
        ).lowercased()
        let text = self.getText().lowercased()
        if word.count > 0 && segment.timeMapping.target.start.seconds == 0 && segment.isCommitted() {
            characterRange = NSRange(location: 0, length: word.count)
        } else if word.count > 0 {
            let numProcessedChar = text.count - self.getText(from: segment.timeMapping.target.start).lowercased().count
            let unprocessedTranscription = text.substring(fromIndex: numProcessedChar).lowercased()
            let substringRange = unprocessedTranscription.range(of: word)
            let numCharToSubstring = unprocessedTranscription.count - unprocessedTranscription[substringRange!.lowerBound..<unprocessedTranscription.endIndex].count
            characterRange = NSRange(location: numProcessedChar + numCharToSubstring, length: word.count)
        } else {
            return nil
        }
        
        return characterRange
    }
    
    func getBackgroundNoise() -> Double {
        if self.soundIntensityStream.count == 0 {
            return Double.infinity
        }
        var counts = [Int: Int]()
        self.soundIntensityStream.forEach {
            if $0.power != Double.infinity && $0.power != Double.nan && $0.power != -Double.infinity {
                counts[Int($0.power)] = (counts[Int($0.power)] ?? 0) + 1
            }
        }
        if let (value, _) = counts.max(by: {$0.1 < $1.1}) {
            return Double(value)
        }
        
        return Double.infinity
    }
    
    func getPower(type: ScaleUnitType = .all, sentenceNumber: Int? = nil, segmentTrackTime: CMTime? = nil) -> Double {
        // print("===== Get Sound Intensity =====")
        var numSegments: Double = 0
        var powerSum: Double = 0
        
        switch type {
        case .all:
            // add committed
            for segment in self.noteSegments {
                let power = segment.getPower()
                if power != Double.infinity {
                    powerSum += power
                    numSegments += 1
                }
            }
            
            // add buffer
            for segment in self.noteBuffer {
                let power = segment.getPower()
                if power != Double.infinity {
                    powerSum += power
                    numSegments += 1
                }
            }
            
            if numSegments > 0 {
                // prevent divide by zero
                return (powerSum / numSegments).rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT)
            }
            
            return Double.infinity
        case .sentence:
            if let sentenceNumber = sentenceNumber {
                // add committed
                for segment in self.noteSegments {
                    if segment.getSentence().number == sentenceNumber {
                        let power = segment.getPower()
                        if power != Double.infinity {
                            powerSum += power
                            numSegments += 1
                        }
                    }
                }
                
                // add buffer
                for segment in self.noteBuffer {
                    if segment.getSentence().number == sentenceNumber {
                        let power = segment.getPower()
                        if power != Double.infinity {
                            powerSum += power
                            numSegments += 1
                        }
                    }
                }

                if numSegments > 0 {
                    return (powerSum / numSegments).rounded(toPlaces: SOUND_INTENSITY_SIG_FIG_COUNT)
                }

                return Double.infinity
            }
            return Double.infinity
        case .word:
            if let segmentTrackTime = segmentTrackTime, let segment = self.getSegment(forTrackTime: segmentTrackTime) {
                return segment.getPower()
            }
            break
        }
        
        return Double.infinity
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
        if self.clipCount > 1 && self.recordStartDate != nil {
            return Float(self.noteSegments.last!.timeMapping.target.end.seconds) + Float(Date().timeIntervalSince(self.recordStartDate!))
        } else if self.recordStartDate != nil {
            return Float(Date().timeIntervalSince(self.recordStartDate!))
        }
        
        return 0
    }
    
    //    func getLocation() {
    //
    //    }
    
    // MARK: - Helper Methods
    
    func triggerBufferCommitNotification() {
        // Give visual feedback
        DispatchQueue.main.async {
            var firstBufferSegment: NoteSegment?
            var lastBufferSegment: NoteSegment?
            if self.noteBuffer.count > 0 {
                // Find first buffer word
                for segment in self.noteBuffer {
                    if !segment.isVoiceCommandWord() && !segment.isSilence() && firstBufferSegment == nil {
                        firstBufferSegment = segment
                        break
                    }
                }

                // Find last buffer word
                for segment in self.noteBuffer.reversed() {
                    if !segment.isVoiceCommandWord() && !segment.isSilence() && lastBufferSegment == nil {
                        lastBufferSegment = segment
                        break
                    }
                }
            } else if let lastBufferRange = self.committedBufferRanges.last {
                let lastBuffer = self.noteSegments[lastBufferRange]
                // Find first buffer word
                for segment in lastBuffer {
                    if !segment.isVoiceCommandWord() && !segment.isSilence() && firstBufferSegment == nil {
                        firstBufferSegment = segment
                        break
                    }
                }

                // Find last buffer word
                for segment in lastBuffer.reversed() {
                    if !segment.isVoiceCommandWord() && !segment.isSilence() && lastBufferSegment == nil {
                        lastBufferSegment = segment
                        break
                    }
                }
            }
            
            if let firstBufferSegment = firstBufferSegment, let lastBufferSegment = lastBufferSegment, firstBufferSegment != lastBufferSegment {
                self.vc!.scheduleNotification(text: "\"\(firstBufferSegment.getText())...\(lastBufferSegment.getText())\" committed!")
                self.vc!.exhaustNotificationQueue()
            } else if let firstBufferSegment = firstBufferSegment, let lastBufferSegment = lastBufferSegment, firstBufferSegment == lastBufferSegment {
                self.vc!.scheduleNotification(text: "\"\(firstBufferSegment.getText())\" committed!")
                self.vc!.exhaustNotificationQueue()
            } else {
                print("===== [Error] There was a problem finding the first and last words of buffer =====")
            }
        }
        
        // Give haptic feedback
        hapticEngine.lightImpact()
    }
    
    func prepareVoiceCommandHandler(command: String) {
        // We put it in a handler so we can run it when we receive final transcript
        self.tempVoiceCommandHandler = {
            print("===== Voice Command Handler =====")
            let firstCommandWord = command.components(separatedBy: " ").first!
            var lowestCommandIndex: Int?

            print("\tSeeking lowest voice command index...")
            let lastBufferRange = self.committedBufferRanges[self.committedBufferRanges.count - 1]
            let voiceCommandBuffer = self.noteSegments[lastBufferRange]
            for (index, segment) in voiceCommandBuffer.reversed().enumerated() {
                if segment.getText().lowercased() == firstCommandWord.lowercased() {
                    lowestCommandIndex = self.noteSegments.distance(to: lastBufferRange.startIndex) + (voiceCommandBuffer.count - index - 1)
                    print("\tFound lowest voice command index: \(lowestCommandIndex!) of \(self.noteSegments.count)")
                    break
                }
            }
            
            if let lowestCommandIndex = lowestCommandIndex {
                print("\tFlipping every segment after lowest voice command index to be voice command word...")

                for index in lowestCommandIndex..<self.noteSegments.distance(to: lastBufferRange.endIndex) {
                    // duplicate segment
                    let duplicateSegment = self.noteSegments[index].duplicate()
                    
                    // determine if we need to replace selection values
                    let replaceSelectionAnchor = duplicateSegment == selectionCursor.anchor
                    let replaceSelectionFocus = duplicateSegment == selectionCursor.focus
                    let replaceSelectionCachedAnchor = duplicateSegment == selectionCursor.cachedAnchor
                    
                    // set duplicate segment as voice command word
                    duplicateSegment.setIsVoiceCommandWord(to: true)
                    
                    // set duplicate segment
                    self.noteSegments[index] = duplicateSegment
                    
                    // update selection anchor
                    if replaceSelectionAnchor {
                        print("\tReplacing Selection Cursor Anchor with version that is not voice command word...")
                        selectionCursor.setAnchor(segment: self.noteSegments[index])
                    }
                    
                    // update selection focus
                    if replaceSelectionFocus {
                        print("\tReplacing Selection Cursor Focus with version that is voice command word...")
                        selectionCursor.setFocus(segment: self.noteSegments[index])
                    }
                    
                    // update selection cached anchor
                    if replaceSelectionCachedAnchor {
                        print("\tReplacing Selection Cursor Cached Anchor with version that is voice command word...")
                        selectionCursor.setCachedAnchor(segment: self.noteSegments[index])
                    }
                }
                
                // we can't have a voice command as the anchor
                var updateSelectionAnchor = false
                var lastBufferWordIndex = Int(Utils.UNKNOWN)
                if selectionCursor.cachedAnchor != nil && self.noteBuffer.count > 0 && !selectionCursor.cachedAnchor!.isCommitted() {
                    print("\tBuffer non-empty and Cached Anchor detected to be buffer segment...")
                    print("\tFind index of new anchor to use as new anchor value...")
                    var lastBufferWord: NoteSegment?
                    for (index, segment) in self.noteBuffer.reversed().enumerated() {
                        if !segment.isSilence() && !segment.isVoiceCommandWord() {
                            lastBufferWord = segment
                            lastBufferWordIndex = index
                            print("\tFound new anchor index: ", lastBufferWordIndex)
                            break
                        }
                    }
                    updateSelectionAnchor = selectionCursor.anchor != nil && lastBufferWord != nil && !selectionCursor.anchor!.isEqual(lastBufferWord!)
                } else if selectionCursor.cachedAnchor != nil && self.noteBuffer.count == 0 {
                    print("\tBuffer is empty and Cached Anchor detected to be committed segment...")
                    print("\tFind index of new anchor to use as new anchor value...")
                    let secondLastBufferRange = self.committedBufferRanges[self.committedBufferRanges.count - 2]
                    let lastWordsBuffer = self.noteSegments[secondLastBufferRange]
                    var lastBufferWord: NoteSegment?
                    for (index, segment) in lastWordsBuffer.reversed().enumerated() {
                        if !segment.isSilence() && !segment.isVoiceCommandWord() {
                            lastBufferWord = segment
                            lastBufferWordIndex = self.noteSegments.distance(to: secondLastBufferRange.startIndex) + (lastWordsBuffer.count - index - 1)
                            print("\tFound new anchor index: ", lastBufferWordIndex)
                            break
                        }
                    }
                    updateSelectionAnchor = selectionCursor.anchor != nil && lastBufferWord != nil && !selectionCursor.anchor!.isEqual(lastBufferWord!)
                } else {
                    print("\tFind index of new anchor to use as new anchor value...")
                    var lastBufferWord: NoteSegment?
                    for (index, segment) in self.noteSegments.reversed().enumerated() {
                        if !segment.isSilence() && !segment.isVoiceCommandWord() {
                            lastBufferWord = segment
                            lastBufferWordIndex = self.noteSegments.count - index - 1
                            print("\tFound new anchor index: ", lastBufferWordIndex)
                            break
                        }
                    }
                    updateSelectionAnchor = selectionCursor.anchor != nil && lastBufferWord != nil && !selectionCursor.anchor!.isEqual(lastBufferWord)
                }
                
                if updateSelectionAnchor {
                    print("\tSelection Anchor needs to be updated from voice command word: ", selectionCursor.anchor?.getText() ?? "nil")
                } else {
                    print("\tIndex of new anchor not found. Abort updating selection cursor anchor...")
                }
                
                if updateSelectionAnchor && self.noteBuffer.count == 0 && lastBufferWordIndex != Int(Utils.UNKNOWN) {
                    print("\tUpdating Selection Anchor...")
                    let segment = self.noteSegments[lastBufferWordIndex]
                    print("\tNew Selection Anchor: ", segment.getText())
                    selectionCursor.setAnchor(segment: segment)
                } else if updateSelectionAnchor && self.noteBuffer.count > 0 && lastBufferWordIndex != Int(Utils.UNKNOWN) && !selectionCursor.cachedAnchor!.isCommitted()  {
                    print("\tUpdating Selection Anchor...")
                    let segment = self.noteBuffer[lastBufferWordIndex]
                    print("\tNew Selection Anchor: ", segment.getText())
                    selectionCursor.setAnchor(segment: segment)
                }
            }

            self.handleOnListenUpdate()
            
            // Handle voice command
            self.handleVoiceCommand(command: command)
        }
    }
    
    func handleOnListenUpdate() {
        if self.noteBuffer.count > 0, let firstBufferSegment = self.noteBuffer.first, let lastBufferSegment = self.noteBuffer.last, let firstBufferSegmentTextRange = self.getSegmentTextRange(of: firstBufferSegment), let lastBufferSegmentTextRange = self.getSegmentTextRange(of: lastBufferSegment) {
            let bufferTextRange = NSRange(
                location: firstBufferSegmentTextRange.location,
                length: (lastBufferSegmentTextRange.location - firstBufferSegmentTextRange.location) + lastBufferSegmentTextRange.length
            )
            self.onListenUpdate?(bufferTextRange)
        } else {
            self.onListenUpdate?(nil)
        }
    }
    
    // MARK: - Key-Value Observer
    
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ){
        guard self.noteBuffer.count == 0 else {
            fatalError("===== [Error] There was a problem inserting passage. Buffer was not empty =====")
        }

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
                print("===== Playing Note =====")
                let timeScale = CMTimeScale(NSEC_PER_SEC)
                let time = CMTime(seconds: 1, preferredTimescale: timeScale)

                timerObserverToken = player.addPeriodicTimeObserver(forInterval: time, queue: .main) {time in
                    self.handlePeriodicTimeObserver()
                }
                
                if !selectionCursor.isLoopingSelection {
                    // if we have a selection, animating through each word removes it
                    var boundaryTimes = [NSValue]()
                    for segment in self.noteSegments {
                        boundaryTimes.append(NSValue(time: segment.timeMapping.target.start))
                    }
                    
                    boundaryObserverToken = player.addBoundaryTimeObserver(forTimes: boundaryTimes, queue: .main) {
                        self.handleBoundaryTimeObserver()
                    }
                }
                
                completionObserverToken = player.addBoundaryTimeObserver(forTimes: [NSValue(time: self.stopPlaybackAt!)], queue: .main) {
                    self.handleCompletionObserver()
                }
                
                // Start note
                player.play()
                
                // Set player rate
                let rateWasSet = Utils.setPlayerRate(player: player, rate: self.playbackRate)
                if rateWasSet {
                    print("\tPlayer rate was successfully set...")
                } else {
                    print("\t[Error] There was a problem setting player rate. Player had not been started yet.")
                }
                
                if self.startPlaybackAt! == self.startTime {
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
                print("\t[Error] There was a problem making track ready to play: \(self.tracks[0].segments.first!.sourceURL!)")
                if let error = player.currentItem!.error {
                    print("\tMessage: \(error.localizedDescription)")
                }

                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                // wait for sound
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                    fatalError()
                }
                break
            case .unknown:
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                // wait for sound
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                    fatalError("\t[Error] Player not ready")
                }
                break
            @unknown default:
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                // wait for sound
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                    fatalError("\t[Error] Unknown player status received")
                }
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
            let segment = self.noteSegments[0]
            if (
                (self.skipPunctuation && segment.isPunctuation()) ||
                (self.skipSilence && segment.isSilence() && segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD) ||
                segment.isVoiceCommandWord()
            ), let nextSegment = self.getSegment(type: .next) {
                // skip to next segment
                self.previousBoundarySegment = currentSegment
                self.player.seek(
                    to: nextSegment.timeMapping.target.start,
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )
                
                // Turn down volume to not hear stutters from voice command word
                Utils.setPlayerVolume(player: self.player, volume: 0)
            } else {
                self.previousBoundarySegment = currentSegment
                
                // Make sure volume is correctly set
                if self.player.volume != self.vc!.playbackVolume {
                    Utils.setPlayerVolume(player: self.player, volume: self.vc!.playbackVolume)
                }
            }
            
            self.observerContext["segmentBoundaryHandler"]?()
        } else if let segment = currentSegment, segment == self.noteSegments.last! {
            // last segment of note
            // We want to put it just before end
            let END_BUFFER_DURATION = 0.05 // makes sure we don't seek to the exact end which causes the completion observer not to run
            if (
                (self.skipPunctuation && segment.isPunctuation()) ||
                (self.skipSilence && segment.isSilence() && segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD) ||
                segment.isVoiceCommandWord()
            ) {
                // skip to next segment
                self.previousBoundarySegment = segment
                self.player.seek(
                    to: CMTimeMake(
                        value: Int64(Note.defaultSegmentTimescale * (self.player.currentItem!.duration.seconds - END_BUFFER_DURATION)),
                        timescale: Int32(Note.defaultSegmentTimescale)
                    ),
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )

                // Turn down volume to not hear stutters from voice command word
                Utils.setPlayerVolume(player: self.player, volume: 0)
            } else {
                self.previousBoundarySegment = currentSegment
                
                // Make sure volume is correctly set
                if self.player.volume != self.vc!.playbackVolume {
                    Utils.setPlayerVolume(player: self.player, volume: self.vc!.playbackVolume)
                }
            }
            
            self.observerContext["segmentBoundaryHandler"]?()
        } else if let segment = currentSegment {
            // We do an equality check with the previous boundary to make sure we are strictly moving
            // forward and not stuck in loop of playing an older segment
            if let previousBoundarySegment = self.previousBoundarySegment,
                currentSegment != previousBoundarySegment &&
                (
                    (self.skipPunctuation && segment.isPunctuation()) ||
                    (self.skipSilence && segment.isSilence() && segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD) ||
                    segment.isVoiceCommandWord()
                ), let nextSegment = self.getSegment(type: .next) {
                // skip to next segment
                self.previousBoundarySegment = currentSegment
                self.player.seek(
                    to: nextSegment.timeMapping.target.start,
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )
                
                // Turn down volume to not hear stutters from voice command word
                Utils.setPlayerVolume(player: self.player, volume: 0)
            } else {
                self.previousBoundarySegment = currentSegment
                
                // Make sure volume is correctly set
                if self.player.volume != self.vc!.playbackVolume {
                    Utils.setPlayerVolume(player: self.player, volume: self.vc!.playbackVolume)
                }
            }
            
            self.observerContext["segmentBoundaryHandler"]?()
        }
    }
    
    func handleCompletionObserver() {
        print("===== Completed Playing Note =====")

        if selectionCursor.isLoopingSelection {
            print("\tPause playback.")
            player.pause()
            print("\tLoop selection.")
            // loop again
            self.playerLoopTimer?.invalidate()
            self.playerLoopTimer = Timer.scheduledTimer(withTimeInterval: CMTimeSubtract(self.stopPlaybackAt!, self.startPlaybackAt!).seconds + 1, repeats: false) { timer in
                selectionCursor.playSelection(loop: true)
            }
        } else {
            print("\tStop note.")
            // Stop Playing
            self.stop()
            
            // Play Finish Handler if present
            self.observerContext["onFinishHandler"]?()
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
    
    func handleVoiceCommand(command: String) {
        if command == "stop note" && AVAudioSession.isHeadphonesConnected {
            voiceCommandEngine.process(note: self, query: command)
        } else if !AVAudioSession.isHeadphonesConnected && (
            voiceCommandEngine.voiceCommandMapping[command] == "play note"
        ) {
            // We don't have headphones connected, so we don't start listening until playback is complete
            // If we listen immediately, the words will be heard and processed
            voiceCommandEngine.process(note: self, query: command) {
                // Reset accumulated Duration for next clip capture
                self.accumulatedDuration = TimeInterval(0)

                if self.pausedListeningForSpeech {
                    // Start listening for speech again if paused
                    // It won't be paused if the processed voice command was 'stop note'
                    self.startListeningForSpeech(
                        soundIntensityHandler: self.soundIntensityHandler,
                        pitchHandler: self.pitchHandler,
                        onStartHandler: self.onListeningStartHandler
                    )
                }
            }
        } else if !AVAudioSession.isHeadphonesConnected && (
            voiceCommandEngine.voiceCommandMapping[command] == "echo note"
        ) {
            // We don't have headphones connected, so we don't start listening until playback is complete
            // If we listen immediately, the words will be heard and processed
            voiceCommandEngine.process(note: self, query: command) {
                // Reset accumulated Duration for next clip capture
                self.accumulatedDuration = TimeInterval(0)
            }
        } else {
            voiceCommandEngine.process(note: self, query: command)
            
            // Reset accumulated Duration for next clip capture
            self.accumulatedDuration = TimeInterval(0)

            if self.pausedListeningForSpeech {
                // Start listening for speech again if paused
                // It won't be paused if the processed voice command was 'stop note'
                self.startListeningForSpeech(
                    soundIntensityHandler: self.soundIntensityHandler,
                    pitchHandler: self.pitchHandler,
                    onStartHandler: self.onListeningStartHandler
                )
            }
        }

        self.handleOnListenUpdate()
    }
}

// MARK: - Speech Recognition Delegate Extension

extension Note: SFSpeechRecognitionTaskDelegate {
    func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {
        print("===== System is no longer accepting new speech input =====")
        
        // Play sound
        soundEngine.error()
        
        // Give haptic feedback
        hapticEngine.error()
    }
    
    func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {
        print("===== Note cancelled looking listening for new speech ===== ")
        
        // Play sound
        soundEngine.error()
        
        // Give haptic feedback
        hapticEngine.error()
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        if !self.isListeningForSpeech && !self.useOnDeviceRecognition {
            print("===== Note successfully finished listening for new speech =====")

            self.onComplete?()
        } else if let lastRecognitionTask = self.lastRecognitionTask, !self.isListeningForSpeech && self.useOnDeviceRecognition && lastRecognitionTask == RecognitionTask.SPEECH {
            print("===== Note successfully finished listening for new speech =====")
            // Completion of speech recognition section
            if soundEngine.isProcessing {
                print("\tSound Engine playing 'Processing Sound'. Turning off..")
                soundEngine.stopProcessing()
            }
            
            self.onComplete?()
            let _ = self.normalizeSegments(
                normalizeType: .target,
                saveSegments: true,
                saveToLowLevelRepr: true
            )
            print("final segments: ", self.noteSegments)
            // Export completed note
            self.isExporting = true
            Utils.exportNote(
                note: self,
                filename: self.filename,
                fileType: self.fileType,
                timeRange: CMTimeRangeMake(start: CMTime.zero, duration: self.duration),
                onCompletionHandler: {
                    self.isExporting = false
                    // We previously had these in stopListeningForSpeech, but clearing these
                    // to soon affects normalization, which rquires recordStartDate to date PitchDatum and SoundIntensityDatum
                    self.accumulatedDuration = TimeInterval(0)
                    self.recordStartDate = nil
                    // Start voice commands
                    DispatchQueue.main.async {
                        self.startListeningForVoiceCommands(
                            soundIntensityHandler: self.soundIntensityHandler,
                            pitchHandler: self.pitchHandler
                        )
                    }
                }
            )
        }
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        DispatchQueue.main.async {
            if self.isListeningForSpeech {
                print("===== Received hypothesis transcription: ", transcription.formattedString)
                // Stop Echo
                if self.vc!.speechSynthesizer.isSpeaking {
                    self.vc!.speechSynthesizer.stopSpeaking(at: .word)
                }

                self.performTranscriptionUpdate(transcription)
                
                // execute listen update handler
                self.handleOnListenUpdate()
                
                if let command = voiceCommandEngine.includesCommand(passage: transcription.formattedString) {
                    print("\tCommand Recognized!")
                    // prepare voice command handler
                    // must come before stopListeningForSpeech
                    self.prepareVoiceCommandHandler(command: command)
                    
                    self.stopListeningForSpeech(pause: true)
                }
            }
        }
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition result: SFSpeechRecognitionResult) {
        DispatchQueue.main.async {
            if self.isListeningForCommands {
                voiceCommandEngine.process(note: self, query: result.bestTranscription.formattedString)
            } else if self.isListeningForSpeech && !self.pausedListeningForSpeech && !self.request!.requiresOnDeviceRecognition {
                print("===== Some words heard. Apple servers ended dictation session =====")
                self.stopListeningForSpeech(pause: true) {[weak self] in
                    // Play Sound
                    soundEngine.commitBuffer()
                    // update segments
                    self?.performTranscriptionUpdate(result.bestTranscription)
                    
                    // trigger commit notification
                    // must happen before committing so we still have the segments in the buffer
                    if !AVAudioSession.isHeadphonesConnected {
                        self?.triggerBufferCommitNotification()
                    }
                    
                    // commit buffer
                    self?.commitBuffer()
                    
                    // execute listen update handler
                    self?.handleOnListenUpdate()

                    // Update duration
                    self?.accumulatedDuration = max(0, Date().timeIntervalSince(self!.recordStartDate!) - TRANSCRIPTION_LATENCY_DURATION)

                    self?.startListeningForSpeech(
                        soundIntensityHandler: self?.soundIntensityHandler,
                        pitchHandler: self?.pitchHandler,
                        onStartHandler: self?.onListeningStartHandler
                    )
                }
            } else if self.isListeningForSpeech && !self.pausedListeningForSpeech && self.request!.requiresOnDeviceRecognition {
                // Play Sound
                soundEngine.commitBuffer()

                // update segments
                self.performTranscriptionUpdate(result.bestTranscription)
                
                // trigger commit notification
                if !AVAudioSession.isHeadphonesConnected {
                    self.triggerBufferCommitNotification()
                }
                
                // commit buffer
                self.commitBuffer()
                // execute listen update handler
                self.handleOnListenUpdate()
                
                // Update duration
                self.accumulatedDuration = max(0, Date().timeIntervalSince(self.recordStartDate!) - TRANSCRIPTION_LATENCY_DURATION)

                // print("===== A contiguous clause was completed: \(self.noteSegments)")
                
                if let command = voiceCommandEngine.includesCommand(passage: result.bestTranscription.formattedString) {
                    print("\tCommand Recognized!")
                    // prepare voice command handler
                    // must come before stopListeningForSpeech
                    self.prepareVoiceCommandHandler(command: command)
                    
                    self.stopListeningForSpeech(pause: true)
                } else if self.withPassiveEcho && AVAudioSession.isHeadphonesConnected {
                    // compute echo text range
                    if let lastEchoSegmentRange = self.committedBufferRanges.last {
                        self.lastEchoSegmentRange = lastEchoSegmentRange
                    }
                    
                    if let lastEchoSegmentRange = self.lastEchoSegmentRange {
                        let text = self.getText(segments: Array(self.noteSegments[lastEchoSegmentRange]))

                        // Echo formatted String
                        self.echoText(text: text)
                        
                        // Give haptic feedback
                        hapticEngine.lightImpact()
                    }
                }
            } else if self.isListeningForSpeech && self.pausedListeningForSpeech && self.request!.requiresOnDeviceRecognition {
                // Only the on-server recognition should go here in theory
                
                self.performTranscriptionUpdate(result.bestTranscription)
                
                // commit buffer
                self.commitBuffer()
                
                // execute listen update handler
                self.handleOnListenUpdate()
                
                // print("===== Completed note: \(self.noteSegments)")

                if let voiceCommandHandler = self.tempVoiceCommandHandler {
                    voiceCommandHandler()
                    self.tempVoiceCommandHandler = nil
                }
            }
        }
    }
    
    func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        print("===== System has detected first incident of speech input =====")
    }
}

// MARK: - Pitch Recognition Delegate Extension

extension Note: PitchEngineDelegate {
    func pitchEngine(_ pitchEngine: PitchEngine, didReceivePitch pitch: Pitch) {
        if let lastSoundIntensity = self.soundIntensityStream.last, pitch.frequency >= MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.soundIntensityStream.count > MIN_SEED_INTENSITY_POINTS && lastSoundIntensity.power > self.getBackgroundNoise() + Utils.TALKING_POWER_DELTA {
            let pitchDatum = PitchDatum(date: Date(), pitch: pitch)
            self.pitchStream.append(pitchDatum)
            
            if self.speaker.pitch == nil {
                let numPitches: Double = Double(self.pitchStream.count)

                var pitchSum: Double = 0

                for datum in self.pitchStream {
                    pitchSum += datum.pitch.frequency
                }
                
                do {
                    let avgPitch = try Pitch(frequency: pitchSum / numPitches)
                    self.setSpeakerPitch(to: avgPitch)
                } catch {
                    print("===== [Error] There was a problem setting speaker pitch =====")
                }
            }
        }
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
// Vocal Range: https://en.wikipedia.org/wiki/Vocal_range
// Male: [85, 180]
// Female: [165, 255]
