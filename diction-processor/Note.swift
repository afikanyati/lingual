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

class Note: AVMutableComposition {
    // MARK: - Static Properties
    /// Stores the timescale used to scale the values specified for CMTime objects
    static let defaultSegmentTimescale = Double(10000)

    // MARK: - Composition Properties
    /// Stores a unique identifier for note
    private(set) var uid: String
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
    /// The date when note was created
    private(set) var dateCreated: TimeInterval
    /// The date when note was last modified
    private(set) var dateModified: TimeInterval
    /// Stores information about the speaker
    private(set) var speaker: Speaker
    /// Stores a list of high-level representation of note segments
    private(set) var noteSegments: [NoteSegment] = [NoteSegment]()
    /// Stores a list of high-level representation of note segments in staging (before committed to noteSegments)
    private(set) var noteBuffer: [NoteSegment] = [NoteSegment]()
    /// Stores a map of segment uid/ segment index key-value pairs to quickly determine segment membership and location
    private(set) var segmentIndexMap: [String: Int] = [:]
    /// Stores a map of deleted segment uid/ segment index key-value pairs to quickly determine segment membership and location
    private(set) var deletedSegmentIndexMap: [String: Int] = [:]
    /// Range of last committed buffer of note segments
    private(set) var committedBufferRanges = [Range<Int>]()
    /// An array of  transformations applied the note
    private(set) var transformations = [NoteTransformation]()
    /// Stores the starting time of the note
    private(set) var startTime: CMTime = CMTime.zero // When we remove or add we change this
    /// Stores the ending time of the note
    private(set) var endTime: CMTime = CMTime.zero // When we remove or add we change this
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
            if !segment.isVoiceCommandWord() && !segment.isDeleted() {
                speakingRate += segment.getSpeakingRate()
            }
        }
        
        // note buffer
        if self.noteBuffer.count > 0 {
            segmentCount += self.noteBuffer.count
            for segment in self.noteBuffer {
                if !segment.isVoiceCommandWord() && !segment.isDeleted() {
                    speakingRate += segment.getSpeakingRate()
                }
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
    /// Specifies whether note text will contain capitalized words
    private(set) var withCapitalization: Bool
    /// Stores a reference to the main view controller
    weak private(set) var vc: ViewController?
    /// Stores a temporary voice command handler that runs once listening has stopped
    private(set) var tempVoiceCommandHandler: (() -> Void)?
    /// Stores the temporary staged speech command
    private(set) var stagedSpeechCommand: String?
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
    private(set) var onListenUpdate: ((_ text: String, _ highlightRange: NSRange?, _ bufferRange: NSRange?) -> Void)?
    /// Stores a handler to be executed when listening has stopped
    private(set) var onListenStop: (() -> Void)?
    /// Stores a UI handler to be executed when new sound intensity data is received
    private(set) var soundIntensityHandler: ((_ power: Double?) -> Void)?
    /// Stores a UI handler to be executed when new pitch data is received
    private(set) var pitchHandler: ((_ pitchDatum: PitchDatum?) -> Void)?
    
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
    @objc dynamic private(set) var pausedListeningForSpeech = false
    /// Specifies whether note has been paused listening for speech by user
    private(set) var userInitiatedPausedListeningForSpeech = false
    /// Specifies whether note is currently listening for voice commands
    private(set) var isListeningForCommands = false
    /// Specifies whether note has paused listening for commands (active, but paused vs. inactive)
    private(set) var pausedListeningForCommands = false
    /// Indicates whether we have to execute listening for speech handler in isListeningForSpeech method
    private var executedListeningForSpeechStartHandler = true
    /// Stores a list of voice commands executed
    private(set) var voiceCommandStream = [VoiceCommandDatum]()
    /// Indicates whether we have processed a voice command early
    private(set) var earlyVoiceCommandDetection = false
    /// Stores the number of words that occur before a voice command in it's buffer
    private(set) var numWordsBeforeVoiceCommand: Int = 0
    
    // MARK: - Speech Synthesis Properties
    /// Specifies whether passive echo should execute when headphones are connected
    private(set) var withPassiveEcho = true
    /// Specifies whether echo is currently playing
    public var isPlayingEcho = false
    /// Specifies whether passive echo is currently playing
    public var isPlayingPassiveEcho = false
    /// Specifies whether echo is currently paused (active, but paused vs. inactive)
    public var pausedEcho: Bool {
        return self.vc!.speechSynthesizer.isPaused
    }
    /// Stores a handler to be executed when note is complete
    private(set) var onComplete: (() -> Void)?
    /// Schedules a temporary handler to be executed when echo is complete
    private(set) var scheduleTempOnEchoFinishHandler: ((_ handler: @escaping () -> Void) -> Void)?
    /// Range of last echo of note segments
    private(set) var lastEchoSegmentRange: Range<Int>?
    
    // MARK: - Audio Playback Properties
    /// Stores a reference to the note's player object
    private(set) var player = AVPlayer()
    /// Stores a reference to a timer that begins next iteration of looping player
    private var playerLoopTimer: Timer?
    /// Stores a reference to the bus used for audio playback
    private let playbackBus = 1
    /// Stores a reference to the playback observer that executes after each segment
    public var boundaryObserverToken: Any?
    /// Stores a reference to the playback observer that executes each second
    public var timerObserverToken: Any?
    /// Stores a reference to the playback observer that executes when playback is complete
    public var completionObserverToken: Any?
    /// Stores a reference to the last segment processed during note playback. Prevents repeat processing.
    private(set) var previousBoundarySegment: NoteSegment?
    /// Specifies whether note is currently playing
    public var isPlayingNote: Bool {
        return player.isPlaying
    }
    /// Specifies whether note is currently paused
    private(set) var pausedPlayingNote = false
    /// Specifies whether note is currently running
    private(set) var isRunningNote = false
    /// Specifies whether note is currently walking
    @objc dynamic private(set) var isWalkingNote = false
    /// Specifies whether note is currently paused walking
    private(set) var pausedWalkingNote = false
    /// Specifies whether note is currently paused running
    private(set) var pausedRunningNote = false
    /// Specifies whether note is currently walking
    private(set) var walkingRange: Range<Int>?
    /// Specifies whether note is currently walking
    private(set) var walkingIndex: Int = 0
    /// Stores a reference to a timer that drives walking loop behavior
    private var walkingTimer: Timer?
    /// Stores a reference to a timer that drives delay of walk loop intiation
    private var walkLoopDelayTimer: Timer?
    /// Stores a reference to a timer that drives delayed echo while walking
    private var echoDelayTimer: Timer?
    /// Stores a reference to a timer that drives passage running
    private var runningTimer: Timer?
    /// Specifies whether playing external segments
    private(set) var isPlayingExternalSegments = false
    /// Specifies whether segments corresponding to punctuation should be skipped
    private(set) var skipPunctuation = true
    /// Specifies whether segments corresponding to silences should be skipped
    private(set) var omitSilences = true
    /// Specifies the time value at which note playback should begin
    private(set) var startPlaybackAt: CMTime?
    /// Specifies the time value at which note playback should end
    private(set) var stopPlaybackAt: CMTime?
    /// Stores segments currently being played by note
    private(set) var playbackRange: Range<Int>?

    // MARK: - Cached Properties
    /// Stores a cached version of the note's duration
    private(set) var cachedDuration: CMTime?
    /// Stores a cached version of getText() method
    private(set) var cachedText: String?
    /// Stores arguments of last getText() call
    private(set) var cachedTextArgsSet: Set<String>?
    /// Stores segments of last getText() call
    private(set) var cachedSegmentUIDSet: Set<String>?
    /// Stores arguments of last getDuration() call
    private(set) var cachedDurationArgsSet: Set<String>?
    /// Stores cached version of getBackgroundNoise
    private(set) var cachedBackgroundNoise: Double?
    
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
        uid: String,
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
        withCapitalization: Bool = true,
        onListenUpdate: ((_ text: String, _ highlightRange: NSRange?, _ bufferRange: NSRange?) -> Void)? = nil,
        onListenStop: (() -> Void)? = nil,
        onComplete: (() -> Void)? = nil,
        scheduleTempOnEchoFinishHandler: ((_ handler: @escaping () -> Void) -> Void)? = nil
    ) {
        print("===== Instantiating new note: \(filename) =====")
        self.dateCreated = Date().timeIntervalSince1970
        self.dateModified = Date().timeIntervalSince1970
        self.uid = uid
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
        self.withCapitalization = withCapitalization
        
        if let vc = vc {
            self.vc = vc
        }
        
        if withPunctuationSuggestions && withTemporalSuggestions {
            // Inform that only one view mode may be active in any given moment
            self.withTemporalSuggestions = false
            let dialogActions = [
                DialogAction(title: "Close", style: .cancel, handler: nil)
            ]
            
            let dialogItem = DialogItem(
                title: "Conflicting View Modes",
                message: "You've attemped to activate both punctuation and temporal suggestions. Only one can be active at a time, so we've activated punctuation suggestions only.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            Utils.presentDialog(dialogItem: dialogItem, vc: self.vc!)
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
        return "Note {\n\tfilename: \(self.filename) \n\tfileType: \(self.fileType) \n\tdateCreated: \(Utils.getDateString(date: self.dateCreated) ?? "nil") \n\tdateModified: \(Utils.getDateString(date: self.dateModified) ?? "nil") \n\tspeaker: \(self.speaker) \n\tnoteSegments: \(self.noteSegments) \n\tnoteBuffer: \(self.noteBuffer) \n\tsegmentIndexMap: \(self.segmentIndexMap) \n\tdeletedSegmentIndexMap: \(self.deletedSegmentIndexMap) \n\tcommittedBufferRanges: \(String(describing: self.committedBufferRanges)) \n\ttransformations: \(self.transformations) \n\tstartTime: \(self.startTime) \n\tendTime: \(self.endTime) \n\tduration: \(self.getDuration()) \n\tisExporting: \(self.isExporting) \n\tnumSentences: \(self.numSentences) \n\tlanguage: \(String(describing: self.language)) \n\tavgSpeakingRate: \(self.avgSpeakingRate) \n\twithTemporalSuggestions: \(self.withTemporalSuggestions) \n\twithPunctuationSuggestions: \(self.withPunctuationSuggestions) \n\twithFormattingSuggestions: \(self.withFormattingSuggestions) \n\twithTextStrictlyAsWords: \(self.withTextStrictlyAsWords) \n\twithCapitalization: \(self.withCapitalization) \n\tauthorizedToListenForSpeech: \(self.authorizedToListenForSpeech) \n\tclipCount: \(self.clipCount) \n\trecordStartDate: \(String(describing: self.recordStartDate)) \n\taccumulatedDuration: \(self.accumulatedDuration) \n\tsoundIntensityStream: \(self.soundIntensityStream) \n\tminPower: \(self.minPower) \n\tpitchStream: \(self.pitchStream) \n\tuseOnDeviceRecognition: \(self.useOnDeviceRecognition) \n\tisListeningForSpeech: \(self.isListeningForSpeech) \n\tpausedListeningForSpeech: \(self.pausedListeningForSpeech) \n\tuserInititatedPausedListeningForSpeech: \(self.userInitiatedPausedListeningForSpeech) \n\tisListeningForCommands: \(self.isListeningForCommands) \n\tpausedListeningForCommands: \(self.pausedListeningForCommands) \n\texecutedListeningForSpeechStartHandler: \(self.executedListeningForSpeechStartHandler) \n\tvoiceCommandStream: \(self.voiceCommandStream) \n\tearlyVoiceCommandDetection: \(self.earlyVoiceCommandDetection) \n\twithPassiveEcho: \(self.withPassiveEcho) \n\tisPlayingEcho: \(self.isPlayingEcho) \n\tisPlayingPassiveEcho: \(self.isPlayingPassiveEcho) \n\tpausedEcho: \(self.pausedEcho) \n\tpreviousBoundarySegment: \(String(describing: self.previousBoundarySegment)) \n\tisPlayingNote: \(self.isPlayingNote) \n\tpausedPlayingNote: \(self.pausedPlayingNote) \n\tisRunningNote: \(self.isRunningNote) \n\tisWalkingNote: \(self.isWalkingNote) \n\tpausedWalkingNote: \(self.pausedWalkingNote) \n\tpausedRunningNote: \(self.pausedRunningNote) \n\twalkingRange: \(String(describing: self.walkingRange)) \n\twalkingIndex: \(self.walkingIndex) \n\tskipPunctuation: \(self.skipPunctuation) \n\tomitSilences: \(self.omitSilences) \n\tstartPlaybackAt: \(String(describing: self.startPlaybackAt)) \n\tstopPlaybackAt: \(String(describing: self.stopPlaybackAt)) \n\tplaybackRange: \(String(describing: self.playbackRange))\n}"
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
                forWriting: Utils.getFileURL(of: "\(self.filename)-\(self.clipCount)\(self.fileType)"),
                settings: audioEngine.inputNode.inputFormat(forBus: self.recordBus).settings
            )
            authorizedToListenForSpeech = true
            print("\tSource URL for writing note successfully created: \(self.filename)-\(self.clipCount)\(self.fileType)")
        } catch {
            print("\t[Error] There was a problem instantiating the record file")
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
                            pitchHandler: self?.pitchHandler
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
                            pitchHandler: self?.pitchHandler
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
        
        // segmentIndexMap and noteSegments length must be the same
        result = result && self.segmentIndexMap.count == self.noteSegments.count
        // print("segmentIndexMap and noteSegments length must be the same: ", self.segmentIndexMap.count, self.noteSegments.count)
        // print("current result: ", result)
        
        // dateModified must be after dateCreated
        result = result && self.dateModified >= self.dateCreated
        // print("dateModified must be after dateCreated: ", self.dateModified, self.dateCreated)
        // print("current result: ", result)

        // only isListeningForSpeech or isListeningForCommands should be active
        result = result && !(self.isListeningForSpeech && self.isListeningForCommands && !self.pausedListeningForSpeech)
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
        result = result && ((self.isListeningForSpeech && !self.pausedListeningForSpeech) || (self.isListeningForSpeech && self.pausedListeningForSpeech) || (!self.isListeningForSpeech && !self.pausedListeningForSpeech))
//        print("make sure paused listening for speech  only occurs if listening for speech: ", (self.isListeningForSpeech && !self.pausedListeningForSpeech), (self.isListeningForSpeech && self.pausedListeningForSpeech), (!self.isListeningForSpeech && !self.pausedListeningForSpeech))
//        print("current result: ", result)
        
        // make sure paused listening for commands only occurs if listening for commands
        result = result && ((self.isListeningForCommands && !self.pausedListeningForCommands) || (self.isListeningForCommands && self.pausedListeningForCommands) || (!self.isListeningForCommands && !self.pausedListeningForCommands))
//        print("make sure paused listening for speech  only occurs if listening for commands: ", (self.isListeningForCommands && !self.pausedListeningForCommands), (self.isListeningForCommands && self.pausedListeningForCommands), (!self.isListeningForCommands && !self.pausedListeningForCommands))
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
        if forVoiceCommands {
            print("===== Starting Listening For Voice Commands =====")
        } else {
            print("===== Starting Listening for Speech =====")
        }

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
            Utils.executeError(note: self, text: "Note already started.", handler: onStartHandler)
            return
        }
        
        if (self.isPlayingEcho && !self.pausedEcho) || self.isPlayingPassiveEcho {
            // Stop active echo
            self.stopEcho(omitFeedback: true)
        }
        
        if self.isPlayingNote && !self.pausedPlayingNote {
            // stop active playback
            self.stop()
        }
        
        if !forVoiceCommands && !self.pausedListeningForSpeech {
            // Play Sound
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                soundEngine.startListening()
            }
        }
        
        if (!self.isListeningForSpeech || self.pausedListeningForSpeech) &&
            (!self.isListeningForCommands || self.pausedListeningForCommands) {
            // A transcription can be in progress before call to startSpeechRecognition if
            // Apple servers ended dictation session
            // It cannot be if after a continguous clause was completed while on-device recognition
            if forVoiceCommands {
                if !self.isListeningForCommands {
                    self.isListeningForCommands = true
                }
                
                self.lastRecognitionTask = RecognitionTask.VOICE_COMMAND
            } else {
                if !self.isListeningForSpeech {
                    self.isListeningForSpeech = true
                }

                self.lastRecognitionTask = RecognitionTask.SPEECH
            }
        }
        
        // remove paused commands flag
        // must be placed after soundEngine call
        // to prevent always executing startListening sound effect
        // remove paused listening flag
        if self.pausedListeningForSpeech && !forVoiceCommands {
            self.pausedListeningForSpeech = false
        }
        
        if self.userInitiatedPausedListeningForSpeech && !forVoiceCommands {
            self.userInitiatedPausedListeningForSpeech = false
        }

        if self.pausedListeningForCommands {
            self.pausedListeningForCommands = false
        }
        
        // flag to run start handler
        self.executedListeningForSpeechStartHandler = false
        
        // Visually indicate app is listening
        DispatchQueue.main.async {
            self.vc!.activateListeningIndicator(
                withRecording: !forVoiceCommands,
                withStopListeningButton: forVoiceCommands && !self.isListeningForSpeech
            )
        }
        
        // if we have segments in first track, it implies this is n > 1
        // recording session
        // We must prepare a new track if it's not there
        if !forVoiceCommands {
            print("\tIncrementing note clip count from \(self.clipCount) to \(self.clipCount + 1)...")
            // Increment clip count used to create unique track URLs to write audio into
            self.clipCount += 1
            
            // Reset accumulated Duration for next clip capture
            self.accumulatedDuration = TimeInterval(0)

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
            // Capture buffer
            self.request!.append(buffer)

            DispatchQueue.main.async {
                if self.audioEngine.isRunning {
                    if self.recordStartDate == nil {
                        // Place after onStartHandler so notification not overwritten by UITimer
                        if !forVoiceCommands {
                            // Present Feedback
                            Utils.executeFeedback(
                                visualMessage: "Start Note",
                                audioMessage: "note started",
                                note: self,
                                withHaptics: true,
                                delay: 1.2
                            )
                        }
                    }
                    
                    // Begin new record start date
                    if !forVoiceCommands && self.isListeningForSpeech && self.recordStartDate == nil {
                        // We place this here so we start tracking recording from the first buffer chunk we receive
                        self.recordStartDate = Date()
                    }
                    
                    if !self.executedListeningForSpeechStartHandler {
                        self.executedListeningForSpeechStartHandler = true
                        onStartHandler?()
                    }
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
                    print("\t[Error] There was a problem writing speech to file")
                }
            }
        }
        
        // Prepare and start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("\t[Error] There was a problem starting speech recognition")
        }
        
        let handleRecognizer = {
            print("\tUsing On-Device Recognition")
            self.request!.requiresOnDeviceRecognition = true
            
            print("\tLoad contextual strings")
            self.request!.contextualStrings = [
                "play note",
                "pause note",
                "create note",
                "new note",
                "start note",
                "start a note",
                "stop note",
                "resume note",
                "continue note",
                "echo note",
                "play echo",
                "start echo",
                "pause echo",
                "stop echo",
                "play last sentence",
                "play previous sentence",
                "echo last sentence",
                "echo previous sentence",
                "ecko last sentence",
                "ecko previous sentence",
                "activate punctuation",
                "turn on punctuation",
                "deactivate punctuation",
                "turn off punctuation",
                "activate silences",
                "turn on silences",
                "deactivate silences",
                "turn off silences",
                "activate temporal suggestions",
                "turn on temporal suggestions",
                "deactivate temporal suggestions",
                "turn off temporal suggestions",
                "activate punctuation suggestions",
                "turn on punctuation suggestions",
                "deactivate punctuation suggestions",
                "turn off punctuation suggestions",
                "activate formatting suggestions",
                "turn on formatting suggestions",
                "deactivate formatting suggestions",
                "turn off formatting suggestions",
                "activate passive echo",
                "turn on passive echo",
                "deactivate passive echo",
                "turn off passive echo",
                "turn volume up",
                "turn volume down",
                "increase volume",
                "decrease volume",
                "adjust volume up",
                "adjust volume down",
                "volume up",
                "volume down",
                "turn echo rate up",
                "turn echo rate down",
                "increase echo rate",
                "decrease echo rate",
                "adjust echo rate up",
                "adjust echo rate down",
                "echo rate up",
                "echo rate down",
                "turn playback rate up",
                "turn playback rate down",
                "increase playback rate",
                "decrease playback rate",
                "adjust playback rate up",
                "adjust playback rate down",
                "playback rate up",
                "playback rate down",
                "delete",
                "delete selection",
                "update",
                "update selection",
                "copy",
                "copy selection",
                "cut",
                "cut selection",
                "increase rate",
                "increase selection rate",
                "decrease rate",
                "decrease selection rate",
                "export",
                "export selection",
                "move here",
                "place cursor",
                "run",
                "run selection",
                "walk",
                "walk selection",
                "run note",
                "walk note",
                "pause playback",
                "resume playback",
                "continue playback",
                "resume echo",
                "continue echo",
                "edit note",
                "play last commit",
                "play last comment",
                "echo last commit",
                "echo last comment",
                "ecko last commit",
                "ecko last comment",
                "walk commit",
                "walk comment",
                "run commit",
                "run comment",
                "play commit",
                "play comment",
                "echo commit",
                "echo comment",
                "ecko commit",
                "ecko comment",
                "preview clipboard",
                "check clipboard",
                "inspect clipboard",
                "play clipboard",
                "skip backward",
                "skip back",
                "skip forward",
                "skip ahead",
                "stop playback",
                "export note",
                "accept",
                "except",
                "redo",
                "cancel",
                "start selection",
                "begin selection",
                "open selection",
                "make selection",
                "add selection",
                "next",
                "forward",
                "right",
                "up",
                "previous",
                "last",
                "backward",
                "left",
                "down",
                "freeze",
                "freeze run",
                "stop",
                "stop run",
                "halt",
                "holt",
                "halt run",
                "holt run",
                "pause",
                "pause run",
                "remove selection",
                "clear selection",
                "undo",
                "redo",
                "exit",
                "select commit",
                "select comment",
                "delete commit",
                "delete comment",
                "reverse commit",
                "reverse comment",
                "rollback commit",
                "shift start in",
                "shift start out",
                "shift starts in",
                "shift starts out",
                "shift start right",
                "shift start left",
                "shift starts right",
                "shift starts left",
                "shift beginning in",
                "shift beginning out",
                "shift beginning right",
                "shift beginning left",
                "shift anchor in",
                "shift anchor out",
                "shift anchor right",
                "shift anchor left",
                "shift end in",
                "shift end out",
                "shift end left",
                "shift end right",
                "shift ending in",
                "shift ending out",
                "shift ending left",
                "shift ending right",
                "shift finish in",
                "shift finish out",
                "shift finish left",
                "shift finish right",
                "shift focus in",
                "shift focus out",
                "shift focus left",
                "shift focus right",
                "shift right",
                "shift forward",
                "shift up",
                "shift left",
                "shift backward",
                "shift down",
                "move start in",
                "move start out",
                "move starts in",
                "move starts out",
                "move start right",
                "move start left",
                "move starts right",
                "move starts left",
                "move beginning in",
                "move beginning out",
                "move beginning right",
                "move beginning left",
                "move anchor in",
                "move anchor out",
                "move anchor right",
                "move anchor left",
                "move end in",
                "move end out",
                "move end left",
                "move end right",
                "move ending in",
                "move ending out",
                "move ending left",
                "move ending right",
                "move finish in",
                "move finish out",
                "move finish left",
                "move finish right",
                "move focus in",
                "move focus out",
                "move focus left",
                "move focus right",
                "move right",
                "move forward",
                "move up",
                "move left",
                "move backward",
                "move down",
                "expand selection",
                "expand",
                "reduce selection",
                "reduce",
                "paste selection",
                "paste clipboard",
                "help",
                "play",
                "echo"
            ]
            
            if let speechRecognizer = self.speechRecognizer, !speechRecognizer.isAvailable {
                print("\tSpeech Recognizer is not available")
                return
            }
            
            // Check rep invariant
            self.handleMutation()
            self.checkRep()
            
            // Let speech recognizer know we're performing dictation or voice commands
            self.speechRecognizer?.defaultTaskHint = forVoiceCommands ? .search : .dictation
            self.recognitionTask = self.speechRecognizer?.recognitionTask(with: self.request!, delegate: self)
        }

        if let speechRecognizer = self.speechRecognizer, useOnDeviceRecognition && speechRecognizer.supportsOnDeviceRecognition {
            handleRecognizer()
        } else {
            // check again after a second
            Timer.scheduledTimer(withTimeInterval: Utils.LISTENING_LAUNCH_DELAY, repeats: false) { timer in
                if let speechRecognizer = self.speechRecognizer, self.useOnDeviceRecognition && speechRecognizer.supportsOnDeviceRecognition {
                    handleRecognizer()
                    
                } else {
                    // Present error
                    let dialogActions = [
                        DialogAction(title: "Close", style: .cancel, handler: nil)
                    ]
                    
                    let dialogItem = DialogItem(
                        title: "Unable to initiate Voice Recognition",
                        message: "Lingual relies on on-device recognition to deliver a the best user experience. Your device does not support it.",
                        preferredStyle: .alert,
                        actions: dialogActions
                    )
                    Utils.presentDialog(dialogItem: dialogItem, vc: self.vc!)
                }
            }
        }
    }
    
    func pauseListeningForSpeech(onPauseHandler: (() -> Void)? = nil) {
        if !self.isListeningForSpeech {
            Utils.executeError(note: self, text: "No ongoing note.", handler: onPauseHandler)
            return
        }
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Pause Note",
            audioMessage: "note paused",
            note: self,
            withHaptics: true
        )

        print("===== Pause Listening for Speech =====")
        
        if !self.pausedListeningForSpeech {
            self.pausedListeningForSpeech = true
        }
        
        if !self.userInitiatedPausedListeningForSpeech {
            self.userInitiatedPausedListeningForSpeech = true
        }
        
        let node = audioEngine.inputNode
        node.removeTap(onBus: self.recordBus)
        
        audioEngine.pause()
        
        self.startListeningForVoiceCommands(
            soundIntensityHandler: self.soundIntensityHandler!,
            pitchHandler: self.pitchHandler!,
            onStartHandler: {
                // When this is not in the main thread, the recognition task doesn't end correctly
                // which prevents us from receiving the final transcription.
                DispatchQueue.main.async {
                    self.recognitionTask?.finish() // don't wrap in if statement because it is sometimes not .running
                    self.request!.endAudio() // don't add a request = nil because it results in request not being there sometimes.
                    self.pitchEngine.stop()
                    self.vc!.activateListeningIndicator(
                        withRecording: false,
                        withStopListeningButton: true
                    )
                    onPauseHandler?() // Needs to be outside DispatchQueue.main.async so it doesn't accidentally wrap two DispatchQueue.main.async if handler has one
                }
            }
        )
    }
    
    // make sure onStophandler is not also wrapped in DispatchQueue.main.async
    func stopListeningForSpeech(pause: Bool = false, forVoiceCommands: Bool = false, onStopHandler: (() -> Void)? = nil) {
        if !self.isListeningForSpeech && !self.isListeningForCommands {
            Utils.executeError(note: self, text: "No ongoing note.", handler: onStopHandler)
            return
        }
        
        if !forVoiceCommands && !pause {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Stop Note",
                audioMessage: "note stopped",
                note: self,
                withHaptics: true
            )
        }

        if forVoiceCommands {
            print("===== Stopping Listening For Voice Commands =====")
        } else if pause {
            print("===== Pausing Listening for Speech =====")
        } else {
            print("===== Stopping Listening for Speech =====")
        }
        
        if (isListeningForSpeech || isListeningForCommands) && !pause {
            if self.isListeningForSpeech && !forVoiceCommands {
                self.isListeningForSpeech = false
            }
            if self.isListeningForCommands {
                self.isListeningForCommands = false
            }
            if self.pausedListeningForSpeech && !forVoiceCommands {
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
            self.recognitionTask?.finish() // don't wrap in if statement because it is sometimes not .running
            self.request!.endAudio() // don't add a request = nil because it results in request not being there sometimes.
            self.pitchEngine.stop()
            self.vc!.activateListeningIndicator(
                withRecording: false,
                withStopListeningButton: forVoiceCommands && !self.isListeningForSpeech
            )
            onStopHandler?() // Needs to be outside DispatchQueue.main.async so it doesn't accidentally wrap two DispatchQueue.main.async if handler has one
        }
        
        if !forVoiceCommands && !self.isListeningForSpeech  {
            // execute listen stop handler only if end of note
            // If handler is called after text selection while listening, it removes the selection. Hence why we abort
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
        var bufferSegments = self.noteBuffer
        
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
            && bufferSegments.count > 0
            && !bufferSegments.last!.isSentenceTerminator()
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
                sourceTimestamp = floor(Note.defaultSegmentTimescale * Utils.DEFAULT_SEGMENT_DURATION)
                
                // Set duration
                duration = floor(Note.defaultSegmentTimescale * Utils.DEFAULT_SEGMENT_DURATION)
            } else {
                // Set source timestamp
                sourceTimestamp = floor(Note.defaultSegmentTimescale * (Double(transcriptionIndex + 1) * Utils.DEFAULT_SEGMENT_DURATION))
                
                // Set duration
                duration = floor(Note.defaultSegmentTimescale * Utils.DEFAULT_SEGMENT_DURATION)
            }
        } else {
            // enters here when we get the final transcript which has timestamp data
            
            // Set source timestamp
            sourceTimestamp = self.accumulatedDuration + segment.timestamp > 0 ?
                    floor(Note.defaultSegmentTimescale * (self.accumulatedDuration + segment.timestamp))
                :
                    0
            
            // Set duration
            duration = segment.duration > 0 ? floor(Note.defaultSegmentTimescale * segment.duration) : 0
        }
        
        let phoneticallySimilarWords = segment.alternativeSubstrings
        
        let noteSegment = NoteSegment(
            note: self,
            word: word,
            trackURL: Utils.getFileURL(of: "\(self.filename)-\(self.clipCount)\(self.fileType)"),
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
        
        
        if self.noteBuffer.count == 0 || transcriptionIndex >= bufferSegments.count {
            // New segment, append to speechSegments
            bufferSegments.append(noteSegment)
            self.noteBuffer = bufferSegments
            self.handleMutation()
        } else if transcriptionIndex < bufferSegments.count {

            // Existing segment, overwrite old copy
            // This assumes the new version is a better approximation of user speech
            let oldSegment = bufferSegments[transcriptionIndex]
            if oldSegment != noteSegment {
                // determine if we need to replace selection values
                // prevent replacing selection values if we're processing a selection update
                let replaceSelectionAnchor = oldSegment == selectionCursor.anchor && !selectionCursor.isUpdatingSelection
                let replaceSelectionFocus = oldSegment == selectionCursor.focus && !selectionCursor.isUpdatingSelection
                let replaceSelectionCachedAnchor = oldSegment == selectionCursor.cachedAnchor && !selectionCursor.isUpdatingSelection
                
                // set updated segments
                bufferSegments[transcriptionIndex] = noteSegment
                self.noteBuffer = bufferSegments
                
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
                
                self.handleMutation()
            } else {
                // Existing segment without changes encountered.
                // print("Existing segment without changes encountered.")
            }
        } else {
            print("\t[Error] There was a problem with pigeonholing segment")
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
                    let trackURL = Utils.getFileURL(of: "\(self.filename)-\(self.clipCount)\(self.fileType)")

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
                        sourceTimeRange: normalizeType == .source ?
                            CMTimeRangeMake(
                                start: lastEnd,
                                duration: segment.timeMapping.source.start - lastEnd
                            )
                            :
                            segment.timeMapping.source
                        ,
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
                        segment.setPower(power: datum.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))
                    }

                    // Silence Sound Intensity/Background Noise
                    if self.soundIntensityStream.count > 0 {
                        let startOfSilenceDuration: Double = lastEnd.seconds
                        let backgroundNoise = getRecordingSoundIntensityDatum(timestamp: startOfSilenceDuration)
                        silentSegment.setPower(power: backgroundNoise.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))
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
                        sentimentScore: segment.getSentiment(),
                        voiceCommandWord: segment.isVoiceCommandWord(),
                        deleted: segment.isDeleted()
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
                        modifiedSegment.setPower(power: datum.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))
                    }
                    
                    // Silences don't have pitch
                    
                    // Rate
                    modifiedSegment.setRate(rate: segment.getRate())
                    
                    // Save silence index
                    if !segment.isDeleted() {
                        silenceIndices.append(normalizedSegments.count)
                    }
                    
                    // Date Created and Modified
                    modifiedSegment.dateCreated = segment.dateCreated
                    modifiedSegment.dateModified = segment.dateModified
                    
                    // UID
                    modifiedSegment.setUID(uid: segment.getUID())
                    
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
                        sentimentScore: segment.getSentiment(),
                        voiceCommandWord: segment.isVoiceCommandWord(),
                        deleted: segment.isDeleted()
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
                        segment.setPower(power: datum.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))
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
                    
                    // Rate
                    normalizedSegment.setRate(rate: segment.getRate())
                    
                    // UID
                    normalizedSegment.setUID(uid: segment.getUID())
                    
                    // Date Created and Modified
                    normalizedSegment.dateCreated = segment.dateCreated
                    normalizedSegment.dateModified = segment.dateModified
                    
                    // Save silence index
                    if segment.isSilence() && !segment.isDeleted() {
                        silenceIndices.append(normalizedSegments.count)
                    }

                    // Add to segments array
                    normalizedSegments.append(normalizedSegment)
                    
                    // Update last end value
                    lastEnd = CMTimeAdd(lastEnd, segment.timeMapping[normalizeType].duration)
                }
            } else {
                // Save silence index
                if segment.isSilence() && !segment.isDeleted() {
                    silenceIndices.append(normalizedSegments.count)
                }
                
                // Add to segments array
                normalizedSegments.append(segment)
                
                // Update last end value
                lastEnd = segment.timeMapping[normalizeType].end
            }
        }
        
        var avgPauseDuration: Double?
        if silenceIndices.count > 0 {
            avgPauseDuration = silenceIndices.reduce(0, { result, i in
                return result + normalizedSegments[i].timeMapping[normalizeType].duration.seconds
            }) / Double(silenceIndices.count)
            avgPauseDuration = avgPauseDuration!.rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)
        }
        
        var speakingRate: Double = normalizedSegments.reduce(0, { result, item in
            if !item.isPunctuation() && !item.isSilence() && !item.isValidCommaWord() && !item.isDeleted() {
                return result + 1
            }
            
            return result
        }) / Double(self.getDuration(filteredDuration: true).seconds / Double(TimeConstant.secsPerMin))
        speakingRate = speakingRate.rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)
        
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
            let datum = self.getRecordingSoundIntensityDatum(timestamp: segment.timeMapping.target.start.seconds)
            segment.setBackgroundNoise(noise: datum.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))

            // Set avgPauseDuration
            if let avgPauseDuration = avgPauseDuration {
                segment.setAvgPauseDuration(duration: avgPauseDuration)
            }
            
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
                    sentimentScore: segment.getSentiment(),
                    voiceCommandWord: segment.isVoiceCommandWord(),
                    deleted: segment.isDeleted()
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
                    segment.setPower(power: datum.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))
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
                
                // Rate
                shiftedSegment.setRate(rate: segment.getRate())
                
                // Date Created and Modified
                shiftedSegment.dateCreated = segment.dateCreated
                shiftedSegment.dateModified = segment.dateModified
                
                // UID
                shiftedSegment.setUID(uid: segment.getUID())
                
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

            // Check rep invariant
            self.handleMutation()
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
            segments.append(segment.duplicate())
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
        self.clearBuffer()
        
        // normalize segments
        print("\tNormalizing buffer segments...")
        let normalizedSegments = self.normalizeSegments(
            segments: segments,
            omitLeadingSilence: updateCachedAnchor, // remove leading space so that we don't erroneously treat it as a long silence in the event that we are inserting new speech
            returnSegments: true
        )
        
        var lastBufferWordIndex = Int(Utils.UNKNOWN)
        for (index, segment) in normalizedSegments!.reversed().enumerated() {
            if !segment.isSilence() && !segment.isVoiceCommandWord() && !segment.isDeleted() {
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
                if segment.getUID() == lastNormalizedWord.getUID() {
                    // update cached anchor
                    print("\tUpdating cached anchor in selection: ", segment.getText())
                    selectionCursor.setCachedAnchor(segment: segment)
                }
            }
        }

        if let oldAnchor = oldAnchor, oldAnchor.getIndex() == Int(Utils.UNKNOWN) {
            print("\tUpdating anchor...")
            for segment in self.noteSegments {
                if segment.getUID() == oldAnchor.getUID() {
                    // update anchor
                    print("\tUpdated anchor segment in selection cursor: ", segment.getText())
                    selectionCursor.setAnchor(segment: segment)
                }
            }
        }
        
        if let oldFocus = oldFocus, oldFocus.getIndex() == Int(Utils.UNKNOWN) {
            print("\tUpdating focus...")
            for segment in self.noteSegments {
                if segment.getUID() == oldFocus.getUID() {
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
    
    func clearBuffer() {
        print("===== Clear Buffer =====")
        self.noteBuffer = []
    }
    
    // MARK: - Listening Method Helpers
    
    func computeSegmentTags(transcription: SFTranscription, transcriptionIndex: Int) -> ([String : NLTag?], [ScaleUnitType: Float]) {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .tokenType, .sentimentScore, .lemma])
        let segmentText = transcription.segments[transcriptionIndex].substring

        // Determine note string
        var wholeText: String
        if let cachedAnchor = selectionCursor.cachedAnchor {
            wholeText = segmentText.count == 1 && segmentText.first!.isPunctuation ?
                self.getText(until: cachedAnchor.timeMapping.target.start) + segmentText + " \(self.getText(from: cachedAnchor.timeMapping.target.start))"
        :
                self.getText(until: cachedAnchor.timeMapping.target.start) + " \(segmentText) " + self.getText(from: cachedAnchor.timeMapping.target.start)
        } else {
            wholeText = segmentText.count == 1 && segmentText.first!.isPunctuation ?
            self.getText() + segmentText
        :
            self.getText() + " \(segmentText)"
        }
            
        
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

        if let range = range {
            (nameType, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType)
            (lemma, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
            (lexicalClass, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass)
            (tokenType, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .tokenType)
            (nameType, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType)
            (wordSentimentScore, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .sentimentScore)
            (sentenceSentimentScore, _) = tagger.tag(at: range.lowerBound, unit: .sentence, scheme: .sentimentScore)
            (paragraphSentimentScore, _) = tagger.tag(at: range.lowerBound, unit: .paragraph, scheme: .sentimentScore)
        }
        
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
    
    // Can't handle empty strings for segmentText
    // rangeText and index must accurate for a given segment in the segments array argument
    func findSegmentRange(segments: [NoteSegment], wholeText: String, rangeText: String, index: Int? = nil) -> Range<String.Index>? {
        // figure out how many words are before it
        // compute number of processedChar
        var lowerText: String?
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
            print("\t[Error] There was a problem analyzing the index of segment in findSegmentRange")
        }
        
        var lowerIndex: String.Index?
        var upperIndex: String.Index?
        var segmentRange: Range<String.Index>?
        if let lowerText = lowerText {
            lowerIndex = rangeText.count == 1 && rangeText.first!.isPunctuation ?
                wholeText.index(wholeText.startIndex, offsetBy: lowerText.count)
            :
                wholeText.index(wholeText.startIndex, offsetBy: lowerText.count + 1)
            upperIndex = wholeText.index(lowerIndex!, offsetBy: rangeText.count)
            segmentRange = lowerIndex!..<upperIndex!
        }

        return segmentRange
    }
    
    func getRecordingSoundIntensityDatum(timestamp: Double) -> SoundIntensityDatum {
        var datum: SoundIntensityDatum
        var i = 0
        var datumTimestamp = soundIntensityStream[i].date - recordStartDate! - Utils.TRANSCRIPTION_LATENCY_DURATION
        repeat {
            datumTimestamp = soundIntensityStream[i].date - recordStartDate! - Utils.TRANSCRIPTION_LATENCY_DURATION
            datum = soundIntensityStream[i]
            i += 1
        } while datumTimestamp < timestamp && i < soundIntensityStream.count
        
        return datum
    }
    
    func getRecordingPitch(timestamp: Double) -> PitchDatum {
        var pitch: PitchDatum
        var i = 0
        var datumTimestamp = pitchStream[i].date - recordStartDate! - Utils.TRANSCRIPTION_LATENCY_DURATION
        repeat {
            datumTimestamp = pitchStream[i].date - recordStartDate! - Utils.TRANSCRIPTION_LATENCY_DURATION
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
        
        var argumentArr: [String] = [
            "fromTime=\(fromTime.seconds)",
            "forEcho=\(forEcho)"
        ]
        if let untilTime = untilTime {
            argumentArr.append("untilTime=\(untilTime.seconds)")
        }
        let argumentSet: Set = Set(argumentArr)
        var segmentUIDArr = self.segmentIndexMap.map { $0.0 }
        self.noteBuffer.forEach { segment in segmentUIDArr.append(segment.getUID()) }
        let segmentUIDSet: Set = Set(segmentUIDArr)
        // Use cached version if it exists
        if let cachedText = self.cachedText, let cachedSegmentUIDSet = self.cachedSegmentUIDSet, let cachedTextArgsSet = self.cachedTextArgsSet, segments == nil && segmentUIDSet == cachedSegmentUIDSet && argumentSet == cachedTextArgsSet {
            return cachedText
        }
        
        var text = ""
        
        var noteSegments: [NoteSegment]? = nil
        if let segments = segments {
            noteSegments = segments
        }
        
        if let cachedAnchor = selectionCursor.cachedAnchor, noteSegments == nil && cachedAnchor.getIndex() != Int(Utils.UNKNOWN) {
            noteSegments = self.noteSegments
            
            // insert buffer at the correct place based on cursor position
            if !selectionCursor.isUpdatingSelection {
                // We don't want to factor buffer which has speech that has yet to be accepted
                // Would show up in seleectionCursor.selectionText
                
                // By default, insert(contentsOf:, at:) inserts the new elements before the anchor
                // We add one to insert them after the ancher
                let cachedAnchorIndex = cachedAnchor.getIndex()
                noteSegments!.insert(contentsOf: self.noteBuffer, at: cachedAnchorIndex + 1)
            }
        } else if noteSegments == nil {
            noteSegments = self.noteSegments
            
            // insert buffer at the end of segments
            if !selectionCursor.isUpdatingSelection {
                // We don't want to factor buffer which has speech that has yet to be accepted
                // Would show up in seleectionCursor.selectionText
                
                noteSegments = self.noteSegments + self.noteBuffer
            }
        }
        
        // We have been given a specific set of segments to compute on vs. multi segment tracks
        var fromTimeSegmentIndex: Int?
        var isSingleSegment = false
//        print("segments: ", noteSegments!)
        for (index, segment) in noteSegments!.enumerated()  {
            if let untilTime = untilTime, fromTimeSegmentIndex != nil && segment.timeMapping.target.end > untilTime {
                // We've seen all the segments we need to compute text
                break
            } else if let untilTime = untilTime, fromTimeSegmentIndex != nil && segment.timeMapping.target.end <= untilTime && !segment.isVoiceCommandWord() && !segment.isDeleted() {
                let word = segment.getText(
                    withTemporalSuggestions: self.withTemporalSuggestions,
                    withPunctuationSuggestions: self.withPunctuationSuggestions,
                    withFormattingSuggestions: self.withFormattingSuggestions,
                    strictlyAsWord: self.withTextStrictlyAsWords,
                    withCapitalization: self.withCapitalization,
                    withSpacePrefix: true,
                    forEcho: forEcho
                )
                
                text += word
            } else if (segment.timeMapping.target.start >= fromTime || fromTimeSegmentIndex != nil) && !isSingleSegment && !segment.isVoiceCommandWord() && !segment.isDeleted() {
                if fromTimeSegmentIndex == nil && segment.timeMapping.target.start >= fromTime  {
                    fromTimeSegmentIndex = index
                    isSingleSegment = segment.timeMapping.target.start == fromTime && segment.timeMapping.target.end == untilTime
                }

                if fromTimeSegmentIndex != nil {
                    let word = segment.getText(
                        withTemporalSuggestions: self.withTemporalSuggestions,
                        withPunctuationSuggestions: self.withPunctuationSuggestions,
                        withFormattingSuggestions: self.withFormattingSuggestions,
                        strictlyAsWord: self.withTextStrictlyAsWords,
                        withCapitalization: self.withCapitalization,
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
        text = self.withCapitalization ? text.capitalizeFirstLetter() : text
        
        // cache work
        if segments == nil && fromTime == CMTime.zero && untilTime == nil && text.count > 0 && segmentUIDSet.count > 0 {
            self.cachedText = text
            self.cachedTextArgsSet = argumentSet
            self.cachedSegmentUIDSet = segmentUIDSet
        }

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
        print("===== Note: Play =====")
        
        if self.noteSegments.count == 0 {
            Utils.executeError(note: self, text: "Note is empty.", handler: onFinishHandler)
            return
        }
        
        // Stop ongoing echo
        if self.isPlayingEcho || self.isPlayingPassiveEcho {
            self.stopEcho(omitFeedback: true)
        }
        
        if self.pausedPlayingNote {
            print("\tNote was paused. Resume playback")
            // Play Sound
            if !self.isListeningForSpeech && !selectionCursor.hasSelection {
                // should not play if we have a selection
                soundEngine.play()
            }
            
            self.pausedPlayingNote = false
            self.isPlayingExternalSegments = false
            
            if self.vc!.speechSynthesizer.isSpeaking {
                print("\tPause speech synthesizer to play speech audio.\n")
                self.vc!.speechSynthesizer.stopSpeaking(at: .immediate)
            }
            
            if self.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                self.stopListeningForVoiceCommands(pause: true) {
                    self.player.play()
                }
            } else if self.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                self.stopListeningForSpeech(pause: true) {
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
            if !self.isListeningForSpeech && !selectionCursor.hasSelection {
                // should not play if we have a selection
                soundEngine.play()
            }
            
            self.pausedPlayingNote = false
            self.isPlayingExternalSegments = false
            
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
            self.playbackRange = 0..<self.noteSegments.count

            // Run Player
            let player = Utils.runPlayer(
                note: self,
                startTime: self.startPlaybackAt!,
                volume: self.vc!.playbackVolume,
                onStartHandler: onStartHandler
            )
            
            // Handle Feedback
            Utils.executeFeedback(
                visualMessage: "Play",
                note: self,
                withHaptics: true
            )

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
        
        if self.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            self.stopListeningForVoiceCommands(pause: true) {
                playHandler()
            }
        } else if self.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
            self.stopListeningForSpeech(pause: true) {
                playHandler()
            }
        } else {
            playHandler()
        }
    }
    
    func play(
        segments: [NoteSegment],
        onStartHandler: (() -> Void)? = nil,
        secondElapseHandler: (() -> Void)? = nil,
        segmentBoundaryHandler: (() -> Void)? = nil,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Play Note: Segments =====")

        let cleansedSegments = Utils.cleanseSegments(segments: segments)
        let tempComposition = AVMutableComposition()
        tempComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
        do {
            try tempComposition.tracks[0].validateSegments(cleansedSegments)
            tempComposition.tracks[0].segments = cleansedSegments
        } catch {
            print("===== There was a problem creating temporary mutable composition to preview clipboard =====")
        }
        
        // Stop ongoing echo
        if self.isPlayingEcho || self.isPlayingPassiveEcho {
            self.stopEcho(omitFeedback: true)
        }
        
        print("\tInitiate new playback...")
        let playHandler = {
            // Play Sound
            if !self.isListeningForSpeech && !selectionCursor.hasSelection {
                // should not play if we have a selection
                soundEngine.play()
            }
            
            self.pausedPlayingNote = false
            self.isPlayingExternalSegments = true
            
            if self.vc!.speechSynthesizer.isSpeaking {
                print("\tPause speech synthesizer to play speech audio.\n")
                self.vc!.speechSynthesizer.stopSpeaking(at: .immediate)
            }

            if onStartHandler != nil {
                self.observerContext["onStartHandler"] = onStartHandler
            }
            
            if segmentBoundaryHandler != nil {
                self.observerContext["segmentBoundaryHandler"] = segmentBoundaryHandler
            }
            
            if secondElapseHandler != nil {
                self.observerContext["secondElapseHandler"] = secondElapseHandler
            }
            
            if onFinishHandler != nil {
                self.observerContext["onFinishHandler"] = onFinishHandler
            }
            
            // Set Start and End Times
            self.startPlaybackAt = CMTime.zero
            self.stopPlaybackAt = tempComposition.duration
            self.playbackRange = segments.first!.getIndex()..<segments.last!.getIndex() + 1

            // Run Player
            let player = Utils.runPlayer(
                composition: tempComposition,
                note: self,
                startTime: self.startPlaybackAt!,
                volume: self.vc!.playbackVolume,
                onStartHandler: onStartHandler
            )
            
            // Handle Feedback
            if !self.isWalkingNote && !self.isRunningNote {
                Utils.executeFeedback(
                    visualMessage: "Play",
                    note: self,
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
        
        if self.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            self.stopListeningForVoiceCommands(pause: true) {
                playHandler()
            }
        } else if self.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
            self.stopListeningForSpeech(pause: true) {
                playHandler()
            }
        } else {
            playHandler()
        }
    }
    
    func playSentence(
        number: Int,
        onStartHandler: (() -> Void)? = nil,
        secondElapseHandler: (() -> Void)? = nil,
        segmentBoundaryHandler: (() -> Void)? = nil,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Play Sentence: \(number) =====")
        
        // Get sentence details
        let sentenceDetails = self.getSentenceDetails(number: number)
        
        self.play(
            from: sentenceDetails!.timeRange.start,
            to: sentenceDetails!.timeRange.end,
            onStartHandler: onStartHandler,
            secondElapseHandler: secondElapseHandler,
            segmentBoundaryHandler: segmentBoundaryHandler,
            onFinishHandler: onFinishHandler
        )
    }

    func playSentence(
        forTrackTime: CMTime,
        onStartHandler: (() -> Void)? = nil,
        secondElapseHandler: (() -> Void)? = nil,
        segmentBoundaryHandler: (() -> Void)? = nil,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Play Sentence at: \(forTrackTime.seconds) =====")

        // Get sentence details
        let sentenceDetails = self.getSentenceDetails(forTrackTime: forTrackTime)
        
        self.play(
            from: sentenceDetails!.timeRange.start,
            to: sentenceDetails!.timeRange.end,
            onStartHandler: onStartHandler,
            secondElapseHandler: secondElapseHandler,
            segmentBoundaryHandler: segmentBoundaryHandler,
            onFinishHandler: onFinishHandler
        )
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
            print("\t[Error] There was a problem replaying current sentence")
        }
    }
    
    func skip(to time: CMTime, handler: (() -> Void)? = nil) {
        let currentSegment = self.getSegment(type: .current)
        if let _ = currentSegment, self.isPlayingNote {
            self.player.seek(
                to: time,
                toleranceBefore: CMTime.zero,
                toleranceAfter: CMTime.zero
            )
            
            // Handle Feedback
            Utils.executeFeedback(
                visualMessage: "Skip",
                note: self,
                withHaptics: true
            )
        } else {
            if self.noteSegments.count == 0 {
                // havent recorded anything
                Utils.executeError(note: self, text: "Note not playing.", handler: handler)
            }
        }
    }
    
    func pause(handler: (() -> Void)? = nil) {
        print("===== Pause Playing Note =====")
        
        player.pause()
        self.pausedPlayingNote = true
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Pause Playback",
            note: self,
            withHaptics: true
        )
        
        if !self.isListeningForSpeech && self.pausedListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            self.startListeningForVoiceCommands(
                soundIntensityHandler: self.soundIntensityHandler,
                pitchHandler: self.pitchHandler
            )
        } else if self.isListeningForSpeech && (self.pausedListeningForSpeech || self.pausedListeningForCommands) && !AVAudioSession.isHeadphonesConnected {
            self.startListeningForSpeech(
                soundIntensityHandler: self.soundIntensityHandler,
                pitchHandler: self.pitchHandler
            )
        }

        if self.playerLoopTimer != nil {
            self.playerLoopTimer?.invalidate()
        }
        
        if soundEngine.isProcessing {
            soundEngine.stopProcessing()
        }
        
        handler?()
    }
    
    func stop(handler: (() -> Void)? = nil) {
        print("===== Stop Playing Note =====")
        player.pause()
        player.seek(to: CMTime.zero)
        player.replaceCurrentItem(with: nil)
        
        self.playerLoopTimer?.invalidate()

        self.startPlaybackAt = nil
        self.stopPlaybackAt = nil
        self.playbackRange = nil
        self.pausedPlayingNote = false
        self.isPlayingExternalSegments = false
        
        if !self.isListeningForSpeech && self.pausedListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            self.startListeningForVoiceCommands(
                soundIntensityHandler: self.soundIntensityHandler,
                pitchHandler: self.pitchHandler
            )
        } else if self.isListeningForSpeech && (self.pausedListeningForSpeech || self.pausedListeningForCommands) && !AVAudioSession.isHeadphonesConnected {
            self.startListeningForSpeech(
                soundIntensityHandler: self.soundIntensityHandler,
                pitchHandler: self.pitchHandler
            )
        }
        
        if soundEngine.isProcessing {
            soundEngine.stopProcessing()
        }
        
        // Handle Feedback
        if !self.isWalkingNote && !self.isRunningNote {
            Utils.executeFeedback(
                visualMessage: "Stop Playback",
                note: self,
                withHaptics: true
            )
        }

        handler?()
        if !selectionCursor.hasSelection {
            self.handleOnListenUpdate(text: self.getText()) // Will trigger update to Command Bar
        } else {
            self.vc!.adjustCommandBar()
            self.vc!.adjustMenuBar()
        }
    }
    
    // MARK: - Echo Methods
    // Computer understanding of the note
    func startEcho(segments: [NoteSegment], allowPlayer: Bool = false, onStartHandler: (() -> Void)? = nil, onFinishHandler: (() -> Void)? = nil) {
        print("===== Start Echo =====")
        if player.isPlaying && !allowPlayer {
            print("\tStop speech audio to play speech synthesizer")
            self.stop()
        }
        
        if self.noteSegments.count == 0 {
            // havent recorded anything
            Utils.executeError(note: self, text: "Note is empty.", handler: onStartHandler)
            return
        }
        
        // Give audio feedback
        // *** The note playing is the audio feedback ***
        
        let executeEcho = {
            // Play Sound
            if !self.isListeningForSpeech {
                soundEngine.play()
            }
            
            // Give feedback
            if !self.isWalkingNote && !self.isRunningNote {
                Utils.executeFeedback(
                    visualMessage: "Start Echo",
                    note: self,
                    withHaptics: true
                )
            }
            
            if self.pausedEcho {
                // continue last echo
                print("\tContinue existing echo utterance...")
                self.vc!.speechSynthesizer.continueSpeaking()
            } else {
                // start new echo
                print("\tInitiate new speech synthesizer utterance...")
                
                let text = self.getText(segments: segments)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: self.vc!.speechSynthesizer,
                    text: text,
                    voice: self.speaker.playbackVoice,
                    rate: self.vc!.echoRate,
                    volume: self.vc!.playbackVolume
                )
                
                self.vc!.synthesizerQueue.enqueue(synthesizerItem)
                self.vc!.exhaustSynthesizerQueue()
                self.isPlayingEcho = true
                
                // cache range of echo segments
                self.lastEchoSegmentRange = segments.first!.getIndex()..<segments.last!.getIndex() + 1
                
                if let onFinishHandler = onFinishHandler {
                    self.scheduleTempOnEchoFinishHandler?(onFinishHandler)
                }
            
                onStartHandler?()
            }
        }
        
        if (self.isListeningForCommands || self.isListeningForSpeech) && !AVAudioSession.isHeadphonesConnected {
            self.stopListeningForVoiceCommands(pause: true) {
                executeEcho()
            }
        } else if (self.isListeningForCommands || self.isListeningForSpeech) && AVAudioSession.isHeadphonesConnected {
            executeEcho()
        }
    }
    
    func echoSentence(
        forTrackTime: CMTime,
        onStartHandler: (() -> Void)? = nil,
        secondElapseHandler: (() -> Void)? = nil,
        segmentBoundaryHandler: (() -> Void)? = nil,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Echo Sentence at: \(forTrackTime.seconds) =====")

        // Get text
        let sentenceDetails = self.getSentenceDetails(forTrackTime: forTrackTime)
        
        if let sentenceDetails = sentenceDetails {
            self.startEcho(
                segments: Array(self.noteSegments[sentenceDetails.noteRange]),
                onStartHandler: onStartHandler,
                onFinishHandler: onFinishHandler
            )
        }
    }
    
    func echoSentence(
        number: Int,
        onStartHandler: (() -> Void)? = nil,
        secondElapseHandler: (() -> Void)? = nil,
        segmentBoundaryHandler: (() -> Void)? = nil,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Echo Sentence: \(number) =====")
        
        let sentenceDetails = self.getSentenceDetails(number: number)
        
        if let sentenceDetails = sentenceDetails {
            self.startEcho(
                segments: Array(self.noteSegments[sentenceDetails.noteRange]),
                onStartHandler: onStartHandler,
                onFinishHandler: onFinishHandler
            )
        }
    }
    
    func pauseEcho(handler: (() -> Void)? = nil) {
        print("===== Pause Echo =====")
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Pause Echo",
            audioMessage: "echo paused",
            note: self,
            withHaptics: true
        )
        
        self.vc!.speechSynthesizer.pauseSpeaking(at: .immediate)
        
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { timer in
            // we delay handler so that pauseSpeaking can take effect before we
            // process handler which might rely on paused state.
            // e.g. startListeningForSpeech will stopEcho() if it encounters non-paused echo.
            handler?()
        }
    }
    
    func stopEcho(omitFeedback: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Stop Echo =====")
        
        // Present Feedback
        if !omitFeedback && !self.isWalkingNote && !self.isRunningNote {
            Utils.executeFeedback(
                visualMessage: "Stop Echo",
                audioMessage: "echo stopped",
                note: self,
                withHaptics: true
            )
        }
        
        self.vc!.speechSynthesizer.stopSpeaking(at: .immediate)
        
        self.isPlayingEcho = false
        self.isPlayingPassiveEcho = false

        handler?()
        self.handleOnListenUpdate(text: self.getText())
    }
    
    func handlePassiveEcho(text: String) {
        print("===== Handle Passive Echo =====")
        
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
        self.isPlayingPassiveEcho = true
    }
    
    // MARK: - Mutating Methods
    
    // TRACKS MUST BE COLLAPSED INTO SINGLE TRACK TO USE THIS
    func trim(keeping: CMTimeRange, permanent: Bool = false, overwrite: Bool = false, onFinishHandler: (() -> Void)? = nil) {
        let keepRange = keeping
        print("===== Trim Note keeping section starting: \(keepRange.start.seconds) until: \(keepRange.end.seconds) =====")
        if self.noteBuffer.count > 0 {
            print("===== There was a problem trimming note. Note buffer was not committed =====")
            return
        }
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Trim Note",
            audioMessage: "trimming note",
            note: self,
            withHaptics: true
        )
        
        var replaceSelectionAnchor = false
        var replaceSelectionFocus = false
        var replaceSelectionCachedAnchor = false
        var newNoteSegments = [NoteSegment]()
        var silenceIndices = [Int]()

        let handleSegments = {
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
                    } else {
                        let segment = seg.duplicate()
                        
                        // We don't add to silence indices because it should have no effect
                        // on the note
                        
                        // set to deleted
                        segment.setIsDeleted(isDeleted: true)
                        
                        // Add segment to array
                        newNoteSegments.append(segment)
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
                    } else {
                        let segment = seg.duplicate()
                        
                        // We don't add to silence indices because it should have no effect
                        // on the note
                        
                        // set to deleted
                        segment.setIsDeleted(isDeleted: true)
                        
                        // Add segment to array
                        newNoteSegments.append(segment)
                    }
                }
            }
            
            print("\tUpdate index, backgroundNoise, avgPauseDuration, and speakingRate...")

            var avgPauseDuration: Double = silenceIndices.reduce(0, { result, i in
               return result + newNoteSegments[i].timeMapping.target.duration.seconds
            }) / Double(silenceIndices.count)
            avgPauseDuration = avgPauseDuration.rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)

            var speakingRate: Double = newNoteSegments.reduce(0, { result, item in
                if !item.isPunctuation() && !item.isSilence() && !item.isVoiceCommandWord() && !item.isDeleted() {
                   return result + 1
               }
               
               return result
            }) / Double(self.getDuration(filteredDuration: true).seconds / Double(TimeConstant.secsPerMin))
            speakingRate = speakingRate.rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)

            // Update Index, Background Noise, AvgPauseDuration, SpeakingRate, Selection Anchor, Selection Focus, Selection Cached Anchor
            for (index, segment) in newNoteSegments.enumerated() {
                // Set segment index
                // We might need to update indices if we lost segments above
                segment.setIndex(index: index)

                // Set background noise
                let datum = self.getRecordingSoundIntensityDatum(timestamp: segment.timeMapping.target.start.seconds)
                segment.setBackgroundNoise(noise: datum.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))

                // Set avgPauseDuration
                segment.setAvgPauseDuration(duration: avgPauseDuration)

                // Set speakingRate
                segment.setSpeakingRate(rate: speakingRate)
                
                // determine if we need to update selection cursor anchor
                // we need to get these values early before we replace segments
                // so that selection cursor doesn't lose reference to its anchor
                if let _ = selectionCursor.anchor, segment.getUID() == selectionCursor.anchor!.getUID() && !segment.isDeleted() {
                    replaceSelectionAnchor = true
                }
                
                // determine if we need to update selection cursor focus
                // we need to get these values early before we replace segments
                // so that selection cursor doesn't lose reference to its focus
                if let _ = selectionCursor.focus, segment.getUID() == selectionCursor.focus!.getUID() && !segment.isDeleted() {
                    replaceSelectionFocus = true
                }
                
                // determine if we need to update selection cursor cached anchor
                // we need to get these values early before we replace segments
                // so that selection cursor doesn't lose reference to its cached anchor
                if let _ = selectionCursor.cachedAnchor, segment.getUID() == selectionCursor.cachedAnchor!.getUID() && !segment.isDeleted() {
                    replaceSelectionCachedAnchor = true
                }
            }
        }

        if permanent {
            print("\tModify start and end times...")
            
            // Create new filename if not or can't overwrite
            if !overwrite || self._fileType != .m4a {
                print("\tCreate new uid and filename...")
                let uid = UUID().uuidString
                self.uid = uid
                self.filename = "note-\(uid)"
            }
            
            print("\tExporting and modifying segments...")
            Utils.exportNote(
                note: self,
                filename: self.filename,
                fileType: self.fileType,
                timeRange: keepRange
            ) {
                // Handle Segments
                handleSegments()
                
                print("\tUpdate note file type...")
                // Change File Type
                // We need this to be placed before normalizeSegments so newNoteSegments are
                // updated with new trackURL
                self.setFileType(fileType: .m4a)

                print("\tNormalize segments to correct for any time-related errors...")
                // Correct any time-related errors
                // Normalize Segments will setSegments
                // Make sure we update segments to reflect new track URL
                let normalizedSegments = self.normalizeSegments(
                    segments: newNoteSegments,
                    normalizeType: .target,
                    replaceNoteDetails: true,
                    saveSegments: true
                )
                
                if let normalizedSegments = normalizedSegments {
                    // update selection properties
                    for seg in normalizedSegments {
                        // update selection anchor
                        if replaceSelectionAnchor && seg.getUID() == selectionCursor.anchor!.getUID() {
                            selectionCursor.setAnchor(segment: seg)
                        }
                        
                        // update selection focus
                        if replaceSelectionFocus && seg.getUID() == selectionCursor.focus!.getUID() {
                            selectionCursor.setFocus(segment: seg)
                        }
                        
                        // update selection cached anchor
                        if replaceSelectionCachedAnchor && seg.getUID() == selectionCursor.cachedAnchor!.getUID() {
                            selectionCursor.setCachedAnchor(segment: seg)
                        }
                    }
                }
                
                self.startTime = CMTime.zero
                self.endTime = normalizedSegments!.last!.timeMapping.target.end

                // Check Representation Invariant
                self.handleMutation()
                self.checkRep()
                
                // Run Completion Handler
                onFinishHandler?()
            }
        } else {
            // Need to remove right side first because everything shifts
            // if we do left side first
            print("\tRemove time ranges from underlying AVMutableComposition...")
            print("\tChange start times...")
            if CMTimeSubtract(self.getDuration(), keepRange.end) > CMTime.zero && CMTimeSubtract(keepRange.start, CMTime.zero) > CMTime.zero {
                // Remove from right side and left
                print("\tTrim Note from the right and left side...")
                let removeRightRange = CMTimeRangeFromTimeToTime(start: keepRange.end, end: self.getDuration())
                let removeLeftRange = CMTimeRangeFromTimeToTime(start: CMTime.zero, end: keepRange.start)
                
                // Remove Time Range
                self.removeTimeRange(removeRightRange)
                self.removeTimeRange(removeLeftRange)
            } else if CMTimeSubtract(self.getDuration(), keepRange.end) > CMTime.zero && CMTimeSubtract(keepRange.start, CMTime.zero) <= CMTime.zero {
                // Remove from right side only
                print("\tTrim Note from the right side only...")
                let removeRightRange = CMTimeRangeFromTimeToTime(start: keepRange.end, end: self.getDuration())
                
                // Remove Time Range
                self.removeTimeRange(removeRightRange)
            } else if CMTimeSubtract(self.getDuration(), keepRange.end) <= CMTime.zero && CMTimeSubtract(keepRange.start, CMTime.zero) > CMTime.zero {
                // Remove from left side only
                print("\tTrim Note from the left side only...")
                let removeLeftRange = CMTimeRangeFromTimeToTime(start: CMTime.zero, end: keepRange.start)
                
                // Remove Time Range
                self.removeTimeRange(removeLeftRange)
            }

            print("\tModify note start and end times...")

            // Handle segments
            handleSegments()
            
            print("\tUpdate Note Segments...")
            // Update Segments
            // We cannot go through setSegments method because these note segments might not be normalized
            // Compute segment sentences
            let segmentsWithUpdatedSentences = updateSegmentSentences(segments: newNoteSegments)
            self.noteSegments = segmentsWithUpdatedSentences.count == newNoteSegments.count ? segmentsWithUpdatedSentences : newNoteSegments
            
            // update selection properties
            for seg in self.noteSegments {
                // update selection anchor
                if replaceSelectionAnchor && seg.getUID() == selectionCursor.anchor!.getUID() {
                    selectionCursor.setAnchor(segment: seg)
                }
                
                // update selection focus
                if replaceSelectionFocus && seg.getUID() == selectionCursor.focus!.getUID() {
                    selectionCursor.setFocus(segment: seg)
                }
                
                // update selection cached anchor
                if replaceSelectionCachedAnchor && seg.getUID() == selectionCursor.cachedAnchor!.getUID() {
                    selectionCursor.setCachedAnchor(segment: seg)
                }
            }
            
            self.startTime = CMTime.zero
            self.endTime = self.noteSegments.last!.timeMapping.target.end

            // Check Representation Invariant
            self.handleMutation()
            self.checkRep()
            
            // Run Completion Handler
            onFinishHandler?()
        }
    }
    
    // Mutates Segments
    func updateSegmentSentences(segments: [NoteSegment]) -> [NoteSegment] {
        print("===== Update Segment Sentences =====")
        var currentSentenceNumber = 0
        var sentenceText = ""
        var sentenceStartTime = CMTime.zero
        var sentenceStartSegment = segments.first!
        var sentenceEndTime: CMTime
        var sentenceEndSegment: NoteSegment
        // Holds the index of the first segment without a sentence
        var leftStaleSegmentIndex = 0
        // make sure silences get sentence number of prior.
        for (index, segment) in segments.enumerated() {
            if index + 1 == segments.count {
                // We've reached the end of the note. Update sentence data
                sentenceEndSegment = segment
                sentenceEndTime = segment.timeMapping.target.end
                
                if !segment.isVoiceCommandWord() && !segment.isDeleted() {
                    sentenceText += segment.getText(
                        withTemporalSuggestions: self.withTemporalSuggestions,
                        withPunctuationSuggestions: self.withPunctuationSuggestions,
                        withFormattingSuggestions: self.withFormattingSuggestions,
                        strictlyAsWord: self.withTextStrictlyAsWords,
                        withCapitalization: self.withCapitalization,
                        withSpacePrefix: true
                    )
                }
                
                let sentence = Sentence(
                    number: currentSentenceNumber,
                    text: sentenceText.trimmingCharacters(in: .whitespacesAndNewlines),
                    timeRange: CMTimeRangeFromTimeToTime(
                        start: sentenceStartTime,
                        end: sentenceEndTime
                    ),
                    noteRange: sentenceStartSegment.getIndex()..<sentenceEndSegment.getIndex() + 1
                )
                
                // Clear sentence
                sentenceText = ""
                
                // Add sentence to every segment ***including*** this one
                for i in leftStaleSegmentIndex...index {
                    segments[i].setSentence(sentence: sentence)
                }
            } else if segment.isVoiceCommandWord() || segment.isDeleted() {
                // Don't add word to sentenceText
                // We don't want these in Sentence class object instances
            } else if segment.isSentenceTerminator() {
                // We've hit a sentence boundary. Update sentences
                // Update sentence data
                sentenceEndSegment = segment
                sentenceEndTime = segment.timeMapping.target.start
                sentenceText += segment.getText(
                    withTemporalSuggestions: self.withTemporalSuggestions,
                    withPunctuationSuggestions: self.withPunctuationSuggestions,
                    withFormattingSuggestions: self.withFormattingSuggestions,
                    strictlyAsWord: self.withTextStrictlyAsWords,
                    withCapitalization: self.withCapitalization,
                    withSpacePrefix: true
                )
                let sentence = Sentence(
                    number: currentSentenceNumber,
                    text: sentenceText.trimmingCharacters(in: .whitespacesAndNewlines),
                    timeRange: CMTimeRangeFromTimeToTime(
                        start: sentenceStartTime,
                        end: sentenceEndTime
                    ),
                    noteRange: sentenceStartSegment.getIndex()..<sentenceEndSegment.getIndex() + 1
                )
                currentSentenceNumber += 1
                sentenceStartSegment = segment
                sentenceStartTime = segment.timeMapping.target.start
                // Clear sentence
                sentenceText = ""
                
                // Add sentence to every segment before this one
                for i in leftStaleSegmentIndex..<index {
                    segments[i].setSentence(sentence: sentence)
                }
                leftStaleSegmentIndex = index
            } else if segment.isActive() {
                // Add word to sentence
                sentenceText += segment.getText(
                    withTemporalSuggestions: self.withTemporalSuggestions,
                    withPunctuationSuggestions: self.withPunctuationSuggestions,
                    withFormattingSuggestions: self.withFormattingSuggestions,
                    strictlyAsWord: self.withTextStrictlyAsWords,
                    withCapitalization: self.withCapitalization,
                    withSpacePrefix: true
                )
            } else {
                // Silences that are not long enough to be sentence terminators go here
            }
        }
        
        return segments
    }
    
    // time must be at a segment boundary to make everything work correctly
    // assumes buffer is empty
    func insertPassage(segments: [NoteSegment], at time: CMTime) {
        print("===== Inserting Passage =====")
        guard self.noteBuffer.count == 0 else {
            print("\t[Error] There was a problem inserting passage. Buffer was not empty")
            return
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
        
        print("\tCleansing segments...")
        let cleansedSegments = Utils.cleanseSegments(segments: updatedSegments)

        print("\tNormalizing segments...")
        let _ = self.normalizeSegments(
            segments: cleansedSegments,
            normalizeType: .target,
            replaceNoteDetails: true,
            saveSegments: true,
            saveToLowLevelRepr: true
        )

        self.handleOnListenUpdate(text: self.getText())
        
        print("\tSuccessfully inserted passage into note!")
    }
    
    // time must be at a segment boundary to make everything work correctly
    // assumes buffer is empty
    func removePassage(range: CMTimeRange) {
        print("===== Removing Passage =====")
        guard self.noteBuffer.count == 0 else {
            print("\t[Error] There was a problem inserting passage. Buffer was not empty")
            return
        }
        print("\tFiltering out passage segments...")
        var updatedSegments = [NoteSegment]()
        
        let beforeTime = range.start
        let afterTime = range.end

        var updateAnchor = false
        var updateFocus = false
        var updateCachedAnchor = false
        for segment in self.noteSegments {
            if segment.timeMapping.target.start < beforeTime {
                // add to array if before passage to be removed
                updatedSegments.append(segment)
            } else if segment.timeMapping.target.end > afterTime {
                // add to array if after passage to be removed
                updatedSegments.append(segment)
            } else {
                segment.setIsDeleted(isDeleted: true)
                // add as deleted
                updatedSegments.append(segment)
                
                // Check if we need to update selection anchor
                if let _ = selectionCursor.anchor, segment.getUID() == selectionCursor.anchor!.getUID() {
                    print("\tSelection cursor anchor requires updating...")
                    updateAnchor = true
                    // Clear anchor so we get no errors related to selectionRange
                    // When we update anchor when we have a selection, focus will be outdate and cause error
                    selectionCursor.setAnchor()
                }
                
                // Check if we need to update selection focus
                if let _ = selectionCursor.focus, segment.getUID() == selectionCursor.focus!.getUID() {
                    print("\tSelection cursor focus requires updating...")
                    updateFocus = true
                    // Clear focus so we get no errors related to selectionRange
                    // When we update focus when we have a selection, anchor will be outdate and cause error
                    selectionCursor.setFocus()
                }
                
                // Check if we need to update selection cached anchor
                if let _ = selectionCursor.cachedAnchor, segment.getUID() == selectionCursor.cachedAnchor!.getUID() {
                    print("\tSelection cursor cached anchor requires updating...")
                    updateCachedAnchor = true
                    // Clear cached anchor
                    selectionCursor.setCachedAnchor()
                }
            }
        }
        
        print("\tCleansing segments...")
        let cleansedSegments = Utils.cleanseSegments(segments: updatedSegments)

        print("\tNormalizing segments...")
        let _ = self.normalizeSegments(
            segments: cleansedSegments,
            normalizeType: .target,
            replaceNoteDetails: true,
            saveSegments: true,
            saveToLowLevelRepr: true
        )
        
        let thresholdShiftDuration = 0.01 // A very small duration used to swing time to prior segment
        var segment: NoteSegment?
        if updateAnchor || updateFocus || updateCachedAnchor {
            print("\tSearching for replacement segment...")
            segment = self.getSegment(
                forTrackTime: CMTimeMake(
                    value: Int64(Note.defaultSegmentTimescale * (max(0, beforeTime.seconds - thresholdShiftDuration))),
                    timescale: Int32(Note.defaultSegmentTimescale)
                )
            )
            
            while segment != nil && segment!.timeMapping.target.start > CMTime.zero && (segment!.isVoiceCommandWord() || segment!.isDeleted() || segment!.isSilence()) {
                let startTime = segment!.timeMapping.target.start
                segment = self.getSegment(
                    forTrackTime: CMTimeMake(
                        value: Int64(Note.defaultSegmentTimescale * (max(0, startTime.seconds - thresholdShiftDuration))),
                        timescale: Int32(Note.defaultSegmentTimescale)
                    )
                )
            }
        }
        
        if let segment = segment, updateAnchor {
            print("\tUpdating selection cursor anchor..")
            selectionCursor.setAnchor(segment: segment)
        }
        
        if let segment = segment, updateFocus {
            print("\tUpdating selection cursor focus...")
            selectionCursor.setFocus(segment: segment)
        }
        
        if let segment = segment, updateCachedAnchor {
            print("\tUpdating selection cursor cached anchor...")
            selectionCursor.setCachedAnchor(segment: segment)
        }
        
        self.handleOnListenUpdate(text: self.getText())

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

    func handleTransformation(
        type: TransformationType,
        passageText: String,
        value: Float? = nil,
        textRange: NSRange,
        noteRange: ClosedRange<Int>
    ) {
        print("===== Handle Transformation =====")
        // Create transformation
        print("\tCreate initial transformation...")
        
        // Collect segment uids
        // Set new value
        var uids: [String: Int] = [:]
        for segment in self.noteSegments[noteRange] {
            uids[segment.getUID()] = segment.getIndex()
            
            // Set playback rate
            if let value = value, type == .playbackRate {
                segment.setRate(rate: value)
            }
        }

        let transformation = NoteTransformation(
            type: type,
            uids: uids,
            text: passageText,
            value: value,
            textRange: textRange,
            noteRange: noteRange
        )
        
        // Search for existing transformations
        print("\tSearch for existing overlapping transformation...")
        var overlapIndex: Int?
        for (index, trans) in self.transformations.enumerated() {
            if trans.type == type && trans.noteRange.overlaps(noteRange) {
                overlapIndex = index
                print("\tFound existing overlapping transformation at self.transformations index: ", index)
                break
            }
        }
        
        var transformations = [NoteTransformation]()
        
        // Only add if it's not the base value
        if let value = transformation.value, value != 1 {
            print("\tCreate initialize transformations array with initial transformation...")
            transformations.append(transformation)
        } else {
            print("\tInitial transformation has a base value. Ignore it.")
        }
        
        if let overlapIndex = overlapIndex {
            print("\tOverlapping transformation identified. Handle transformation slicing...")
            let overlapTransformation = self.transformations[overlapIndex]
            
            if overlapTransformation.noteRange.contains(transformation.noteRange.lowerBound) &&
                overlapTransformation.noteRange.contains(transformation.noteRange.upperBound) &&
                overlapTransformation.noteRange.lowerBound < transformation.noteRange.lowerBound &&
                overlapTransformation.noteRange.upperBound > transformation.noteRange.upperBound
            {
                // transformation is strictly within the overlap transformation
                // e.g. [2, 3, 4, 5] and [3, 4]
                print("\tTransformation is strictly within the overlap transformation: [2, 3, 4, 5] and [3, 4]")
                
                // Clear transformations array
                print("\tClear initialized transformations array...")
                transformations = []
                
                print("\tSplit transformation into three sections: bottom, middle, top...")
                // ==== Create bottom transformation
                
                let bottomLowerSegment = self.noteSegments[overlapTransformation.noteRange.lowerBound]
                var bottomUpperSegmentIndex = transformation.noteRange.lowerBound - 1
                var bottomUpperSegment = self.noteSegments[bottomUpperSegmentIndex]
                while (bottomUpperSegment.isVoiceCommandWord() || bottomUpperSegment.isSilence() || bottomUpperSegment.isDeleted()) && bottomUpperSegmentIndex > overlapTransformation.noteRange.lowerBound {
                    // must not be a silence or voice command word or deleted
                    bottomUpperSegmentIndex -= 1
                    bottomUpperSegment = self.noteSegments[bottomUpperSegmentIndex]
                }
                
                print("\tCompute bottom section lower and upper segments: '\(bottomLowerSegment.getText())' and '\(bottomUpperSegment.getText())'")

                // Compute text
                let bottomText = self.getText(
                    from: bottomLowerSegment.timeMapping.target.start,
                    until: bottomUpperSegment.timeMapping.target.end
                )
                print("\tCompute bottom section text: ", bottomText)

                // Compute value
                let bottomValue = value
                if let bottomValue = bottomValue {
                    print("\tCompute bottom section value: ", bottomValue)
                }
                
                // Compute text range
                let bottomLowerRange = self.getSegmentTextRange(of: bottomLowerSegment)
                let bottomUpperRange = self.getSegmentTextRange(of: bottomUpperSegment)
                let bottomLowerLocation = bottomLowerRange!.location
                let bottomUpperLocation = bottomUpperRange!.location
                let bottomUpperLength = bottomUpperRange!.length
                let bottomTextRange = NSRange(location: bottomLowerLocation, length: (bottomUpperLocation - bottomLowerLocation) + bottomUpperLength)
                print("\tCompute bottom section textRange: ", bottomTextRange)
                
                // Compute range
                let bottomNoteRange = bottomLowerSegment.getIndex()...bottomUpperSegment.getIndex()
                print("\tCompute bottom section noteRange: ", bottomNoteRange)
                
                // Collect segment uids
                var bottomUIDs: [String: Int] = [:]
                for segment in self.noteSegments[bottomNoteRange] {
                    bottomUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let bottomTransform = NoteTransformation(
                    type: type,
                    uids: bottomUIDs,
                    text: bottomText,
                    value: bottomValue,
                    textRange: bottomTextRange,
                    noteRange: bottomNoteRange
                )
                print("\tInstantiate bottom transformation: ", bottomTransform)
                
                // Add to array
                // Only add if it's not the base value
                if bottomTransform.value != nil && Int(round(bottomTransform.value!)) != 1 {
                    print("\tBottom transformation have a value, but it's not standard value. Add to transformations array...")
                    transformations.append(bottomTransform)
                } else {
                    print("\tBottom transformation has base value. Ignore it.")
                }
                
                // ==== Create middle transformation
                
                let middleLowerSegment = self.noteSegments[transformation.noteRange.lowerBound]
                let middleUpperSegment = self.noteSegments[transformation.noteRange.upperBound]
                
                print("\tCompute middle section lower and upper segments: '\(middleLowerSegment.getText())' and '\(middleUpperSegment.getText())'")

                // Compute text
                let middleText = self.getText(
                    from: middleLowerSegment.timeMapping.target.start,
                    until: middleUpperSegment.timeMapping.target.end
                )
                print("\tCompute middle section text: ", middleText)

                // Compute value
                let middleValue = value
                if let middleValue = middleValue {
                    print("\tCompute middle section value: ", middleValue)
                }
                
                // Compute text range
                let middleLowerRange = self.getSegmentTextRange(of: middleLowerSegment)
                let middleUpperRange = self.getSegmentTextRange(of: middleUpperSegment)
                let middleLowerLocation = middleLowerRange!.location
                let middleUpperLocation = middleUpperRange!.location
                let middleUpperLength = middleUpperRange!.length
                let middleTextRange = NSRange(location: middleLowerLocation, length: (middleUpperLocation - middleLowerLocation) + middleUpperLength)
                print("\tCompute middle section textRange: ", middleTextRange)
                
                // Compute range
                let middleNoteRange = middleLowerSegment.getIndex()...middleUpperSegment.getIndex()
                print("\tCompute middle section noteRange: ", middleNoteRange)
                
                // Collect segment uids
                var middleUIDs: [String: Int] = [:]
                for segment in self.noteSegments[middleNoteRange] {
                    middleUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let middleTransform = NoteTransformation(
                    type: type,
                    uids: middleUIDs,
                    text: middleText,
                    value: middleValue,
                    textRange: middleTextRange,
                    noteRange: middleNoteRange
                )
                print("\tInstantiate middle transformation: ", middleTransform)
                
                // Add to array
                // Only add if it's not the base value
                if middleTransform.value != nil && Int(round(middleTransform.value!)) != 1 {
                    transformations.append(middleTransform)
                    print("\tMiddle transformation has a value, but it's not standard value. Add to transformations array...")
                } else {
                    print("\tMiddle transformation has base value. Ignore it.")
                }
                
                // ==== Create top transformaton
                
                let topUpperSegment = self.noteSegments[overlapTransformation.noteRange.upperBound]
                var topLowerSegmentIndex = transformation.noteRange.upperBound + 1
                var topLowerSegment = self.noteSegments[topLowerSegmentIndex]
                while (topLowerSegment.isVoiceCommandWord() || topLowerSegment.isSilence() || topLowerSegment.isDeleted()) && topLowerSegmentIndex < overlapTransformation.noteRange.upperBound {
                    // must not be a silence or voice command word or is deleted
                    topLowerSegmentIndex += 1
                    topLowerSegment = self.noteSegments[topLowerSegmentIndex]
                }
                print("\tCompute top section lower and upper segments: '\(topLowerSegment.getText())' and '\(topUpperSegment.getText())'")

                // Compute text
                let topText = self.getText(
                    from: topLowerSegment.timeMapping.target.start,
                    until: topUpperSegment.timeMapping.target.end
                )
                print("\tCompute top section text: ", topText)

                // Compute value
                let topValue = value
                if let topValue = topValue {
                    print("\tCompute top section value: ", topValue)
                }
                
                // Compute text range
                let topLowerRange = self.getSegmentTextRange(of: topLowerSegment)
                let topUpperRange = self.getSegmentTextRange(of: topUpperSegment)
                let topLowerLocation = topLowerRange!.location
                let topUpperLocation = topUpperRange!.location
                let topUpperLength = topUpperRange!.length
                let topTextRange = NSRange(location: topLowerLocation, length: (topUpperLocation - topLowerLocation) + topUpperLength)
                print("\tCompute top section textRange: ", topTextRange)
                
                // Compute range
                let topNoteRange = topLowerSegment.getIndex()...topUpperSegment.getIndex()
                print("\tCompute top section noteRange: ", topNoteRange)
                
                // Collect segment uids
                var topUIDs: [String: Int] = [:]
                for segment in self.noteSegments[topNoteRange] {
                    topUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let topTransform = NoteTransformation(
                    type: type,
                    uids: topUIDs,
                    text: topText,
                    value: topValue,
                    textRange: topTextRange,
                    noteRange: topNoteRange
                )
                print("\tInstantiate top transformation: ", topTransform)
                
                // Add to array
                // Only add if it's not the base value
                if topTransform.value != nil && Int(round(topTransform.value!)) != 1 {
                    transformations.append(topTransform)
                    print("\tTop transformation has a value, but it's not standard value. Add to transformations array...")
                } else {
                    print("\tTop transformation has base value. Ignore it.")
                }
            } else if overlapTransformation.noteRange.contains(transformation.noteRange.lowerBound) &&
                overlapTransformation.noteRange.contains(transformation.noteRange.upperBound) &&
                overlapTransformation.noteRange.lowerBound == transformation.noteRange.lowerBound &&
                overlapTransformation.noteRange.upperBound == transformation.noteRange.upperBound {
                // transformation is the same as overlap transformation
                // e.g. [2, 3, 4, 5] and [2, 3, 4, 5]
                print("\tTransformation is the same as overlap transformation: [2, 3, 4, 5] and [2, 3, 4, 5]. Do nothing.")
                // Do nothing
            } else if transformation.noteRange.contains(overlapTransformation.noteRange.lowerBound) &&
                    transformation.noteRange.contains(overlapTransformation.noteRange.upperBound) &&
                    transformation.noteRange.lowerBound < overlapTransformation.noteRange.lowerBound &&
                    transformation.noteRange.upperBound > overlapTransformation.noteRange.upperBound {
                    // overlap transformation is strictly within the transformation
                    // e.g. [3, 4] and [2, 3, 4, 5]
                    print("\tOverlap transformation is strictly within the transformation: [3, 4] and [2, 3, 4, 5].")
                    // Do nothing
            } else if overlapTransformation.noteRange.contains(transformation.noteRange.lowerBound) &&
                (
                    !overlapTransformation.noteRange.contains(transformation.noteRange.upperBound) ||
                    (overlapTransformation.noteRange.contains(transformation.noteRange.upperBound) && transformation.noteRange.count == 1)
                )
            {
                // transformation overlaps at the lower end only
                // e.g. [2, 3, 4, 5] and [0, 1, 2, 3]
                print("\tTransformation overlaps at the lower end only: [2, 3, 4, 5] and [0, 1, 2, 3]")
                
                // Clear transformations array
                print("\tClear initialized transformations array...")
                transformations = []
                
                print("\tSplit transformation into two sections: bottom, top...")
                
                // ==== Create bottom transformation
                
                let bottomLowerSegment = self.noteSegments[overlapTransformation.noteRange.lowerBound]
                var bottomUpperSegmentIndex = transformation.noteRange.lowerBound - 1
                var bottomUpperSegment = self.noteSegments[bottomUpperSegmentIndex]
                while (bottomUpperSegment.isVoiceCommandWord() || bottomUpperSegment.isSilence() || bottomUpperSegment.isDeleted()) && bottomUpperSegmentIndex > overlapTransformation.noteRange.lowerBound {
                    // must not be a silence or voice command word
                    bottomUpperSegmentIndex -= 1
                    bottomUpperSegment = self.noteSegments[bottomUpperSegmentIndex]
                }
                print("\tCompute bottom section lower and upper segments: '\(bottomLowerSegment.getText())' and '\(bottomUpperSegment.getText())'")

                // Compute text
                let bottomText = self.getText(
                    from: bottomLowerSegment.timeMapping.target.start,
                    until: bottomUpperSegment.timeMapping.target.end
                )
                print("\tCompute bottom section text: ", bottomText)

                // Compute value
                let bottomValue = value
                if let bottomValue = bottomValue {
                    print("\tCompute bottom section value: ", bottomValue)
                }
                
                // Compute text range
                let bottomLowerRange = self.getSegmentTextRange(of: bottomLowerSegment)
                let bottomUpperRange = self.getSegmentTextRange(of: bottomUpperSegment)
                let bottomLowerLocation = bottomLowerRange!.location
                let bottomUpperLocation = bottomUpperRange!.location
                let bottomUpperLength = bottomUpperRange!.length
                let bottomTextRange = NSRange(location: bottomLowerLocation, length: (bottomUpperLocation - bottomLowerLocation) + bottomUpperLength)
                print("\tCompute bottom section textRange: ", bottomTextRange)
                
                // Compute range
                let bottomNoteRange = bottomLowerSegment.getIndex()...bottomUpperSegment.getIndex()
                print("\tCompute bottom section noteRange: ", bottomNoteRange)
                
                // Collect segment uids
                var bottomUIDs: [String: Int] = [:]
                for segment in self.noteSegments[bottomNoteRange] {
                    bottomUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let bottomTransform = NoteTransformation(
                    type: type,
                    uids: bottomUIDs,
                    text: bottomText,
                    value: bottomValue,
                    textRange: bottomTextRange,
                    noteRange: bottomNoteRange
                )
                print("\tInstantiate bottom transformation: ", bottomTransform)
                
                // Add to array
                // Only add if it's not the base value
                if bottomTransform.value != nil && Int(round(bottomTransform.value!)) != 1 {
                    print("\tBottom transformation have a value, but it's not standard value. Add to transformations array...")
                    transformations.append(bottomTransform)
                } else {
                    print("\tBottom transformation has base value. Ignore it.")
                }
                
                // ==== Create top transformaton

                let topUpperSegment = self.noteSegments[transformation.noteRange.upperBound]
                let topLowerSegment = self.noteSegments[transformation.noteRange.lowerBound]
                print("\tCompute top section lower and upper segments: '\(topLowerSegment.getText())' and '\(topUpperSegment.getText())'")

                // Compute text
                let topText = self.getText(
                    from: topLowerSegment.timeMapping.target.start,
                    until: topUpperSegment.timeMapping.target.end
                )
                print("\tCompute top section text: ", topText)
                
                // Compute value
                let topValue = value
                if let topValue = topValue {
                    print("\tCompute top section value: ", topValue)
                }
                
                // Compute text range
                let topLowerRange = self.getSegmentTextRange(of: topLowerSegment)
                let topUpperRange = self.getSegmentTextRange(of: topUpperSegment)
                let topLowerLocation = topLowerRange!.location
                let topUpperLocation = topUpperRange!.location
                let topUpperLength = topUpperRange!.length
                let topTextRange = NSRange(location: topLowerLocation, length: (topUpperLocation - topLowerLocation) + topUpperLength)
                print("\tCompute top section textRange: ", topTextRange)
                
                // Compute range
                let topNoteRange = topLowerSegment.getIndex()...topUpperSegment.getIndex()
                print("\tCompute top section noteRange: ", topNoteRange)

                // Collect segment uids
                var topUIDs: [String: Int] = [:]
                for segment in self.noteSegments[topNoteRange] {
                    topUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let topTransform = NoteTransformation(
                    type: type,
                    uids: topUIDs,
                    text: topText,
                    value: topValue,
                    textRange: topTextRange,
                    noteRange: topNoteRange
                )
                print("\tInstantiate top transformation: ", topTransform)
                
                // Add to array
                // Only add if it's not the base value
                if topTransform.value != nil && Int(round(topTransform.value!)) != 1 {
                    transformations.append(topTransform)
                    print("\tTop transformation has a value, but it's not standard value. Add to transformations array...")
                } else {
                    print("\tTop transformation has base value. Ignore it.")
                }
            } else if (
                        !overlapTransformation.noteRange.contains(transformation.noteRange.lowerBound) ||
                        (overlapTransformation.noteRange.contains(transformation.noteRange.lowerBound) && transformation.noteRange.count == 1)
                    ) && overlapTransformation.noteRange.contains(transformation.noteRange.upperBound) {
                // transformation overlaps at the upper end only
                // e.g. [2, 3, 4, 5] and [5, 6, 7]
                print("\tTransformation overlaps at the upper end only: [2, 3, 4, 5] and [5, 6, 7]")
                
                // Clear transformations array
                print("\tClear initialized transformations array...")
                transformations = []
                
                print("\tSplit transformation into two sections: bottom, top...")
                
                // ==== Create bottom transformation
                
                let bottomLowerSegment = self.noteSegments[overlapTransformation.noteRange.lowerBound]
                var bottomUpperSegmentIndex = transformation.noteRange.lowerBound - 1
                var bottomUpperSegment = self.noteSegments[bottomUpperSegmentIndex]
                while (bottomUpperSegment.isVoiceCommandWord() || bottomUpperSegment.isSilence() || bottomUpperSegment.isDeleted()) && bottomUpperSegmentIndex > overlapTransformation.noteRange.lowerBound {
                    // must not be a silence or voice command word
                    bottomUpperSegmentIndex -= 1
                    bottomUpperSegment = self.noteSegments[bottomUpperSegmentIndex]
                }
                print("\tCompute bottom section lower and upper segments: '\(bottomLowerSegment.getText())' and '\(bottomUpperSegment.getText())'")

                // Compute text
                let bottomText = self.getText(
                    from: bottomLowerSegment.timeMapping.target.start,
                    until: bottomUpperSegment.timeMapping.target.end
                )
                print("\tCompute bottom section text: ", bottomText)

                // Compute value
                let bottomValue = value
                if let bottomValue = bottomValue {
                    print("\tCompute bottom section value: ", bottomValue)
                }
                
                // Compute text range
                let bottomLowerRange = self.getSegmentTextRange(of: bottomLowerSegment)
                let bottomUpperRange = self.getSegmentTextRange(of: bottomUpperSegment)
                let bottomLowerLocation = bottomLowerRange!.location
                let bottomUpperLocation = bottomUpperRange!.location
                let bottomUpperLength = bottomUpperRange!.length
                let bottomTextRange = NSRange(location: bottomLowerLocation, length: (bottomUpperLocation - bottomLowerLocation) + bottomUpperLength)
                print("\tCompute bottom section textRange: ", bottomTextRange)
                
                // Compute range
                let bottomNoteRange = bottomLowerSegment.getIndex()...bottomUpperSegment.getIndex()
                print("\tCompute bottom section noteRange: ", bottomNoteRange)
                
                // Collect segment uids
                var bottomUIDs: [String: Int] = [:]
                for segment in self.noteSegments[bottomNoteRange] {
                    bottomUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let bottomTransform = NoteTransformation(
                    type: type,
                    uids: bottomUIDs,
                    text: bottomText,
                    value: bottomValue,
                    textRange: bottomTextRange,
                    noteRange: bottomNoteRange
                )
                print("\tInstantiate bottom transformation: ", bottomTransform)
                
                // Add to array
                // Only add if it's not the base value
                if bottomTransform.value != nil && Int(round(bottomTransform.value!)) != 1 {
                    // bottom transformation have a value, but it's not standard value
                    print("\tBottom transformation have a value, but it's not standard value. Add to transformations array...")
                    transformations.append(bottomTransform)
                } else {
                    print("\tBottom transformation has base value. Ignore it.")
                }
                
                // ==== Create top transformaton
                
                let topLowerSegment = self.noteSegments[transformation.noteRange.lowerBound]
                let topUpperSegment = self.noteSegments[transformation.noteRange.upperBound]
                print("\tCompute top section lower and upper segments: '\(topLowerSegment.getText())' and '\(topUpperSegment.getText())'")

                // Compute text
                let topText = self.getText(
                    from: topLowerSegment.timeMapping.target.start,
                    until: topUpperSegment.timeMapping.target.end
                )
                print("\tCompute top section text: ", topText)

                // Compute value
                let topValue = value
                if let topValue = topValue {
                    print("\tCompute top section value: ", topValue)
                }
                
                // Compute text range
                let topLowerRange = self.getSegmentTextRange(of: topLowerSegment)
                let topUpperRange = self.getSegmentTextRange(of: topUpperSegment)
                let topLowerLocation = topLowerRange!.location
                let topUpperLocation = topUpperRange!.location
                let topUpperLength = topUpperRange!.length
                let topTextRange = NSRange(location: topLowerLocation, length: (topUpperLocation - topLowerLocation) + topUpperLength)
                print("\tCompute top section textRange: ", topTextRange)
                
                // Compute range
                let topNoteRange = topLowerSegment.getIndex()...topUpperSegment.getIndex()
                print("\tCompute top section noteRange: ", topNoteRange)
                
                // Collect segment uids
                var topUIDs: [String: Int] = [:]
                for segment in self.noteSegments[topNoteRange] {
                    topUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let topTransform = NoteTransformation(
                    type: type,
                    uids: topUIDs,
                    text: topText,
                    value: topValue,
                    textRange: topTextRange,
                    noteRange: topNoteRange
                )
                print("\tInstantiate top transformation: ", topTransform)
                
                // Add to array
                // Only add if it's not the base value
                if topTransform.value != nil && Int(round(topTransform.value!)) != 1 {
                    transformations.append(topTransform)
                    print("\tTop transformation has a value, but it's not standard value. Add to transformations array...")
                } else {
                    print("\tTop transformation has base value. Ignore it.")
                }
            } else {
                print("\t[Error] Unhandled Overlap Branch")
            }
            
            // Remove overlap transformation from note.transformations property
            self.transformations.remove(at: overlapIndex)
            print ("\tRemove overlap transformation from stored transformations at index: ", overlapIndex)
        }
        
        // Add transformation to transformations array
        print("\tAdd computed transformations to stored transformations...")
        self.transformations.append(contentsOf: transformations)
        
        // Present Feedback
        if let value = value {
            Utils.executeFeedback(
                visualMessage: "Selection rate: \(value)x",
                audioMessage: "Adjusted selection rate to \(value)x.",
                note: self,
                withHaptics: true
            )
        }
        
        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    func walk(segments: [NoteSegment]? = nil, runOverride: Bool = false, onStartHandler: (() -> Void)? = nil) {
        print("===== Note: \(runOverride ? "Run" : "Walk") Object =====")
        if (self.isWalkingNote && !self.pausedWalkingNote && !runOverride) || (segments != nil && segments!.count == 0) || (segments == nil && self.noteSegments.count == 0) {
            var text: String
            if self.isWalkingNote && !self.pausedWalkingNote && !runOverride {
                text = "Already walking passage."
            } else {
                text = "Note is empty"
            }
            
            Utils.executeError(note: self, text: text)
            
            return
        }
        
        // Get walking segments
        // if they are already set, it means we're starting from an existing walk
        // we likely have gone from walking to running
        if let segments = segments, let firstSegment = segments.first, let lastSegment = segments.last, self.walkingRange == nil {
            self.walkingRange = firstSegment.getIndex()..<lastSegment.getIndex() + 1
            
            // Set walking index
            self.walkingIndex = 0
        } else if self.walkingRange == nil {
            self.walkingRange = 0..<self.noteSegments.count
            
            // Set walking index
            self.walkingIndex = 0
        } else if let anchor = selectionCursor.anchor, let walkingRange = self.walkingRange, self.pausedWalkingNote || self.pausedRunningNote {
            // We likely just updated walk segment
            // We must handle new index placement
            // We must handle segment expanding to multiple words
            // Decision: We keep selection on the first segment only
            self.walkingIndex = anchor.getIndex() - self.noteSegments[walkingRange].first!.getIndex()
        }
        
        guard let walkingRange = self.walkingRange else {
            self.walkingIndex = 0
            self.walkingRange = nil
            Utils.executeError(note: self, text: "Unable to start \(runOverride ? "running" : "walking").", handler: onStartHandler)
            return
        }
        
        var currentSegment: NoteSegment? = Array(self.noteSegments[walkingRange])[self.walkingIndex]
        if let segment = currentSegment, let walkingRange = self.walkingRange, !segment.isActive() {
            currentSegment = self.getSegment(segment: segment, segments: Array(self.noteSegments[walkingRange]), type: .next, isWord: true)
        }
        
        if let currentSegment = currentSegment {
            // Updating walking index
            self.walkingIndex = currentSegment.getIndex() - Array(self.noteSegments[walkingRange]).first!.getIndex()

            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "\(runOverride ? "Run" : "Walk") activated!",
                note: self,
                withHaptics: true
            )
            
            // Activate isWalkingNote if we don't have a run override
            self.isWalkingNote = !runOverride
            self.pausedWalkingNote = false
            self.pausedRunningNote = false
            
            selectionCursor.setSelection(anchor: currentSegment, focus: currentSegment)
            
            // start looping walk
            if AVAudioSession.isHeadphonesConnected {
                let makeStep = {
                    self.play(
                        segments: [currentSegment],
                        segmentBoundaryHandler: { [weak self] in
                            DispatchQueue.main.async {
                                if let highlightRange = self?.getSegmentTextRange(of: currentSegment) {
                                    // update text
                                    self?.handleOnListenUpdate(text: self!.getText(), highlightRange: highlightRange)
                                }
                                
                                // TODO: Show pitch
                            }
                        }, onFinishHandler: { [weak self] in
                            // print("Successfully executed playback on finish handler")
                            DispatchQueue.main.async {
                                self?.handleOnListenUpdate(text: self!.getText())
                            }
                        }
                    )
                    
                    // Play echo
                    self.echoDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_ECHO_DELAY_DURATION * TimeInterval( 1 / self.vc!.playbackRate), repeats: false) { [weak self] timer in
                        self?.startEcho(segments: [currentSegment])
                    }
                }
                
                self.walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let segmentDuration: TimeInterval = currentSegment.timeMapping.target.duration.seconds
                    let stepDuration: TimeInterval = max(segmentDuration + (segmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + segmentDuration + Utils.WALKING_LOOP_BUFFER)
                    self?.walkingTimer = Timer.scheduledTimer(withTimeInterval: max(stepDuration, Utils.WALKING_PERIOD_DURATION) * TimeInterval( 1 / self!.vc!.playbackRate), repeats: true) { timer in
                        makeStep()
                    }
                }
            }
            
            // execute start handler
            onStartHandler?()
        } else {
            self.exitWalk()
            Utils.executeError(note: self, text: "Unable to start \(runOverride ? "running" : "walking").", handler: onStartHandler)
        }
    }
    
    func walkToPreviousSegment(runOverride: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note: \(runOverride ? "Run" : "Walk") To Previous Segment =====")
        if !self.isWalkingNote && !self.isRunningNote {
            var text: String
            text = "\(runOverride ? "Running" : "Walking") not active."
            Utils.executeError(note: self, text: text)
            return
        }
        
        guard let walkingRange = self.walkingRange else {
            Utils.executeError(note: self, text: "Unable to \(runOverride ? "run to" : "walk to") previous.", handler: handler)
            self.exitWalk()
            return
        }
        
        var currentSegment: NoteSegment? = Array(self.noteSegments[walkingRange])[self.walkingIndex]
        if let segment = currentSegment, let walkingRange = self.walkingRange {
            currentSegment = self.getSegment(segment: segment, segments: Array(self.noteSegments[walkingRange]), type: .previous, isWord: true)
        }
        
        if let currentSegment = currentSegment, self.walkingIndex != (currentSegment.getIndex() - Array(self.noteSegments[walkingRange]).first!.getIndex()) {
            
            // Updating walking index
            self.walkingIndex = currentSegment.getIndex() - Array(self.noteSegments[walkingRange]).first!.getIndex()

            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Previous word",
                note: self,
                withHaptics: true
            )
            
            // Stop previous walking loop
            self.walkingTimer?.invalidate()
            self.walkingTimer = nil
            
            // Stop previous walking loop delay
            self.walkLoopDelayTimer?.invalidate()
            self.walkLoopDelayTimer = nil

            // Stop previous echo delay
            self.echoDelayTimer?.invalidate()
            self.echoDelayTimer = nil
            
            // Stop playback
            if self.isPlayingNote {
                self.stop()
            }
            // Stop echo
            if self.isPlayingEcho {
                self.stopEcho(omitFeedback: true)
            }
            
            selectionCursor.setSelection(anchor: currentSegment, focus: currentSegment)
            
            // start looping walk
            if AVAudioSession.isHeadphonesConnected {// play speech
                let makeStep = {
                    self.play(
                        segments: [currentSegment],
                        segmentBoundaryHandler: { [weak self] in
                            DispatchQueue.main.async {
                                if let highlightRange = self?.getSegmentTextRange(of: currentSegment) {
                                    // update text
                                    self?.handleOnListenUpdate(text: self!.getText(), highlightRange: highlightRange)
                                }
                                
                                // TODO: Show pitch
                            }
                        }, onFinishHandler: { [weak self] in
                            DispatchQueue.main.async {
                                self?.handleOnListenUpdate(text: self!.getText())
                            }
                        }
                    )
                    
                    // Play echo
                    self.echoDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_ECHO_DELAY_DURATION * TimeInterval( 1 / self.vc!.playbackRate), repeats: false) { [weak self] timer in
                        self?.startEcho(segments: [currentSegment])
                    }
                }
                
                self.walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let segmentDuration: TimeInterval = currentSegment.timeMapping.target.duration.seconds
                    let stepDuration: TimeInterval = max(segmentDuration + (segmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + segmentDuration + Utils.WALKING_LOOP_BUFFER)
                    self?.walkingTimer = Timer.scheduledTimer(withTimeInterval: max(stepDuration, Utils.WALKING_PERIOD_DURATION) * TimeInterval( 1 / self!.vc!.playbackRate), repeats: true) { timer in
                        makeStep()
                    }
                }
            }

            // execute handler
            handler?()
        } else {
            Utils.executeError(note: self, text: "At beginning of \(runOverride ? "running" : "walking") passage.", handler: handler)
        }
    }
    
    func walkToNextSegment(runOverride: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note: \(runOverride ? "Run" : "Walk") To Next Segment =====")
        if !self.isWalkingNote && !self.isRunningNote {
            var text: String
            text = "\(runOverride ? "Running" : "Walking") not active."
            Utils.executeError(note: self, text: text)
            return
        }
        
        guard let walkingRange = self.walkingRange else {
            Utils.executeError(note: self, text: "Unable to \(runOverride ? "run to" : "walk to") next.", handler: handler)
            self.exitWalk()
            return
        }
        
        var currentSegment: NoteSegment? = Array(self.noteSegments[walkingRange])[self.walkingIndex]
        if let segment = currentSegment, let walkingRange = self.walkingRange {
            currentSegment = self.getSegment(segment: segment, segments: Array(self.noteSegments[walkingRange]), type: .next, isWord: true)
        }

        if let currentSegment = currentSegment, self.walkingIndex != (currentSegment.getIndex() - Array(self.noteSegments[walkingRange]).first!.getIndex()) {
            // Updating walking index
            self.walkingIndex = currentSegment.getIndex() - Array(self.noteSegments[walkingRange]).first!.getIndex()

            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Next word",
                note: self,
                withHaptics: true
            )
            
            // Stop previous walking loop
            self.walkingTimer?.invalidate()
            self.walkingTimer = nil
            
            // Stop previous walking loop delay
            self.walkLoopDelayTimer?.invalidate()
            self.walkLoopDelayTimer = nil

            // Stop previous echo delay
            self.echoDelayTimer?.invalidate()
            self.echoDelayTimer = nil

            // Stop playback
            if self.isPlayingNote {
                self.stop()
            }
            // Stop echo
            if self.isPlayingEcho {
                self.stopEcho(omitFeedback: true)
            }
            
            selectionCursor.setSelection(anchor: currentSegment, focus: currentSegment)
            
            // start looping walk
            if AVAudioSession.isHeadphonesConnected {
                let makeStep = {
                    self.play(
                        segments: [currentSegment],
                        segmentBoundaryHandler: { [weak self] in
                            DispatchQueue.main.async {
                                if let highlightRange = self?.getSegmentTextRange(of: currentSegment) {
                                    // update text
                                    self?.handleOnListenUpdate(text: self!.getText(), highlightRange: highlightRange)
                                }
                                
                                // TODO: Show pitch
                            }
                        }, onFinishHandler: { [weak self] in
                            DispatchQueue.main.async {
                                self?.handleOnListenUpdate(text: self!.getText())
                            }
                        }
                    )
                    
                    // Play echo
                    self.echoDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_ECHO_DELAY_DURATION * TimeInterval( 1 / self.vc!.playbackRate), repeats: false) { [weak self] timer in
                        self?.startEcho(segments: [currentSegment])
                    }
                }
                
                self.walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let segmentDuration: TimeInterval = currentSegment.timeMapping.target.duration.seconds
                    let stepDuration: TimeInterval = max(segmentDuration + (segmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + segmentDuration + Utils.WALKING_LOOP_BUFFER)
                    self?.walkingTimer = Timer.scheduledTimer(withTimeInterval: max(stepDuration, Utils.WALKING_PERIOD_DURATION) * TimeInterval( 1 / self!.vc!.playbackRate), repeats: true) { timer in
                        makeStep()
                    }
                }
            }
            
            // execute handler
            handler?()
        } else if self.isRunningNote {
            self.exitWalk(clearSelection: false)
        } else {
            Utils.executeError(note: self, text: "At end of \(runOverride ? "running" : "walking") passage.", handler: handler)
        }
    }
    
    func run(segments: [NoteSegment]? = nil, onStartHandler: (() -> Void)? = nil) {
        print("===== Note: Run =====")
        
        if self.isRunningNote && !self.pausedRunningNote {
            Utils.executeError(note: self, text: "Already running passage.")
            return
        }
        
        self.isRunningNote = true
        
        // Start walk
        self.walk(segments: segments, runOverride: true, onStartHandler: onStartHandler)
        
        let avgSegmentDuration: TimeInterval = 0.5
        let runInterval: TimeInterval = max(avgSegmentDuration + (avgSegmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + avgSegmentDuration + Utils.WALKING_LOOP_BUFFER)
        // start automated walking
        self.runningTimer = Timer.scheduledTimer(withTimeInterval: runInterval + Utils.WALKING_START_DELAY_DURATION, repeats: true) { [weak self] timer in
            if self!.walkingIndex + 1 < Array(self!.noteSegments[self!.walkingRange!]).count {
                self?.walkToNextSegment(runOverride: true)
            } else {
                self?.haltRun()
            }
        }
    }
    
    func haltRun(handler: (() -> Void)? = nil) {
        print("===== Note: Halt Run =====")
        if !self.isRunningNote {
            Utils.executeError(note: self, text: "Not running passage.")
            return
        }
        
        if self.runningTimer == nil {
            Utils.executeError(note: self, text: "Error halting run.")
            return
        }
        
        // Stop running timer
        self.runningTimer?.invalidate()
        self.runningTimer = nil
        
        // Stop previous walking loop
        self.walkingTimer?.invalidate()
        self.walkingTimer = nil
        
        // Stop previous walking loop delay
        self.walkLoopDelayTimer?.invalidate()
        self.walkLoopDelayTimer = nil

        // Stop previous echo delay
        self.echoDelayTimer?.invalidate()
        self.echoDelayTimer = nil
        
        // Stop playback
        if self.isPlayingNote {
            self.stop()
        }

        // Stop echo
        if self.isPlayingEcho {
            self.stopEcho(omitFeedback: true)
        }
        
        // Turn off running note
        self.isRunningNote = false
        
        guard let walkingRange = self.walkingRange else {
            Utils.executeError(note: self, text: "Unable to halt run.", handler: handler)
            self.exitWalk()
            return
        }
        
        // Convert to walking note
        self.walk(segments: Array(self.noteSegments[walkingRange]), onStartHandler: handler)
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Run Halted!",
            audioMessage: "Run halted to walk",
            note: self,
            withHaptics: true
        )
    }
    
    func exitWalk(pause: Bool = false, clearSelection: Bool = true, withFeedback: Bool = true, handler: (() -> Void)? = nil) {
        if self.isRunningNote {
            print("===== Note: Exit Run =====")
        } else {
            print("===== Note: Exit Walk =====")
        }

        if !self.isWalkingNote && !self.isRunningNote {
            Utils.executeError(note: self, text: "Not walking or running passage.")
            return
        }
        
        if !pause {
            self.walkingIndex = 0
            self.walkingRange = nil
        }
        
        // Stop running timer
        self.runningTimer?.invalidate()
        self.runningTimer = nil
        
        // Stop previous walking loop
        self.walkingTimer?.invalidate()
        self.walkingTimer = nil
        
        // Stop previous walking loop delay
        self.walkLoopDelayTimer?.invalidate()
        self.walkLoopDelayTimer = nil
        
        // Stop previous echo delay
        self.echoDelayTimer?.invalidate()
        self.echoDelayTimer = nil
        
        let handleExitWalk = {
            var visualMessage: String?
            var audioMessage: String?
            if withFeedback {
                if self.isRunningNote {
                    visualMessage = "Exit Run"
                    audioMessage = "run exited."
                } else {
                    visualMessage = "Exit Walk"
                    audioMessage = "walk exited."
                }
            }
            
            if pause && self.isRunningNote {
                self.pausedRunningNote = true
            } else if pause && self.isWalkingNote {
                self.pausedWalkingNote = true
            } else {
                self.isRunningNote = false
                self.isWalkingNote = false
            }
            
            if clearSelection {
                // We only clear the focus so that the cursor remains at given location
                selectionCursor.setFocus()
                if !selectionCursor.isAtEndOfTextView {
                    // We cache the anchor if we're mid-note so that new content is added from given location
                    selectionCursor.setCachedAnchor(segment: selectionCursor.anchor)
                }
            } else if let _ = selectionCursor.anchor, let _ = selectionCursor.focus, !pause {
                // Initiate looping selection behavior when we end walk
                selectionCursor.playSelection(loop: true)
            }
            
            // Present Feedback
            if let visualMessage = visualMessage, let audioMessage = audioMessage, withFeedback {
                Utils.executeFeedback(
                    visualMessage: visualMessage,
                    audioMessage: audioMessage,
                    note: self,
                    withHaptics: true
                )
            }
            
            if !clearSelection && !self.isListeningForCommands {
                self.startListeningForVoiceCommands(
                    soundIntensityHandler: self.soundIntensityHandler,
                    pitchHandler: self.pitchHandler
                ) {
                    handler?()
                    self.vc!.adjustCommandBar()
                    self.vc!.adjustMenuBar()
                }
            } else {
                handler?()
                self.vc!.adjustCommandBar()
                self.vc!.adjustMenuBar()
            }
        }
        
        // Stop playback and echo
        self.stop() {
            self.stopEcho(omitFeedback: true) {
                handleExitWalk()
            }
        }
    }
    
    // MARK: - Setters
    
    func setSpeakerPitch(to pitch: Pitch) {
        speaker.pitch = pitch
        
        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    // Audio variable
    func setSkipPunctuation(to skip: Bool) {
        self.skipPunctuation = skip
        
        if self.skipPunctuation {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Skip Punctuation",
                audioMessage: "skip punctuation activated",
                note: self,
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Include Punctuation",
                audioMessage: "skip punctuation deactivated",
                note: self,
                withHaptics: true
            )
        }

        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    // Audio variable
    func setOmitSilences(to skip: Bool) {
        self.omitSilences = skip
        
        if self.omitSilences {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Activate Silences",
                audioMessage: "silences activated",
                note: self,
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Deactivate Silences",
                audioMessage: "silences deactivated",
                note: self,
                withHaptics: true
            )
        }
        
        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    // Audio variable
    func setWithPassiveEcho(to value: Bool) {
        self.withPassiveEcho = value
        
        if self.withPassiveEcho {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Activate Passive Echo",
                audioMessage: "passive echo activated",
                note: self,
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Deactivate Passive Echo",
                audioMessage: "passive echo deactivated",
                note: self,
                withHaptics: true
            )
        }
        
        // Check rep invariant
        self.handleMutation()
        checkRep()
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
        self.handleOnListenUpdate(text: self.getText())
        
        if self.withTemporalSuggestions {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Activate Temporal Suggestions",
                audioMessage: "temporal suggestions activated",
                note: self,
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Deactivate Temporal Suggestions",
                audioMessage: "temporal suggestions deactivated",
                note: self,
                withHaptics: true
            )
        }
        
        // Check rep invariant
        self.handleMutation()
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
        self.handleOnListenUpdate(text: self.getText())
        
        if self.withPunctuationSuggestions {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Activate Punctuation Suggestions",
                audioMessage: "punctuation suggestions activated",
                note: self,
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Deactivate Punctuation Suggestions",
                audioMessage: "punctuation suggestions deactivated",
                note: self,
                withHaptics: true
            )
        }
        
        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    // Visual variable
    func setWithFormattingSuggestions(to value: Bool) {
        self.withFormattingSuggestions = value
        
        // Make sure new setting is reflecting visually
        self.handleOnListenUpdate(text: self.getText())
        
        if self.withFormattingSuggestions {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Activate Formatting Suggestions",
                audioMessage: "formatting suggestions activated",
                note: self,
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Deactivate Formatting Suggestions",
                audioMessage: "formatting suggestions deactivated",
                note: self,
                withHaptics: true
            )
        }
        
        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    // Visual variable
    func setWithTextStrictlyAsWords(to value: Bool) {
        self.withTextStrictlyAsWords = value
        
        // Make sure new setting is reflecting visually
        self.handleOnListenUpdate(text: self.getText())

        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    // Visual variable
    func setWithCapitalization(to value: Bool) {
        self.withCapitalization = value
        
        // Make sure new setting is reflecting visually
        self.handleOnListenUpdate(text: self.getText())

        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    // We lack a checkRep here because we use it mid
    // operation in trimNote when the representation invariant is broken
    func setFileType(fileType: AVFileType) {
        self._fileType = fileType
        
        // Handle Mutation
        self.handleMutation()
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
            
            // 1. make sure to update selection objects
            // 2. update segmentIndexMap
            print("\tDeterming in updates need to be made to selection cursor properties...")
            print("\tUpdate segment-index map...")
            self.segmentIndexMap = [:]
            self.deletedSegmentIndexMap = [:]
            for segment in self.noteSegments {
                if let _ = selectionCursor.anchor, segment.getUID() == selectionCursor.anchor!.getUID() {
                    print("\tUpdating selection cursor anchor...")
                    selectionCursor.setAnchor(segment: segment)
                }
                
                if let _ = selectionCursor.focus, segment.getUID() == selectionCursor.focus!.getUID() {
                     print("\tUpdating selection cursor focus...")
                    selectionCursor.setFocus(segment: segment)
                }
                if let _ = selectionCursor.cachedAnchor, segment.getUID() == selectionCursor.cachedAnchor!.getUID() {
                     print("\tUpdating selection cursor cached anchor...")
                    selectionCursor.setCachedAnchor(segment: segment)
                }
                
                // Add segment uid-index pair into segmentIndexMap
                self.segmentIndexMap[segment.getUID()] = segment.getIndex()
                
                // Add deleted segment uid-index pair into segmentIndexMap
                if segment.isDeleted() {
                    // Add segment uid-index pair into segmentIndexMap
                    self.deletedSegmentIndexMap[segment.getUID()] = segment.getIndex()
                }
            }

            // Update transformations
            self.transformations = Utils.cleanseTransformations(
                transformations: self.transformations,
                segments: self.noteSegments,
                segmentIndexMap: self.segmentIndexMap,
                omitSilences: false,
                omitVoiceCommands: false,
                omitDeleted: false
            )
            print("\tSuccessfully updated note segments!")
        } catch {
            print("\t[Error] There was a problem updating note segments")
        }

        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    // MARK: - Getters
    
    // https://developer.apple.com/documentation/avfoundation/avassetexportpresetpassthrough
    // https://stackoverflow.com/questions/58025109/exporting-mp3-with-avassetexportsession
    // We do not compute sentences for segments here because the segments lack a reference to an note
    // Without a reference to an note, they cannot compute getText correctly
    // MUST HAVE A SINGLE COLLAPSED TRACK
    func duplicate(onFinishHandler: @escaping (_ note: Note?) -> Void) {
        print("===== Duplicate Note =====")
        guard self.noteBuffer.count == 0 else {
            print("\t[Error] There was a problem inserting passage. Buffer was not empty")
            return
        }

        // Export Note
        let uid = UUID().uuidString
        let duplicateFilename = "note-\(uid)"
        Utils.exportNote(
            note: self,
            filename: duplicateFilename,
            fileType: self.fileType,
            timeRange: CMTimeRangeMake(start: CMTime.zero, duration: self.getDuration())
        ) {
            let duplicateNote = Note(
                vc: self.vc,
                uid: uid,
                filename: duplicateFilename,
                fileType: .m4a,
                speaker: self.speaker,
                minPower: self.minPower,
                segments: self.noteSegments, // Will copy segments so there are not multiple pointers to a single segment
                withOnDeviceRecognition: self.useOnDeviceRecognition,
                withTemporalSuggestions: self.withTemporalSuggestions,
                withPunctuationSuggestions: self.withPunctuationSuggestions,
                withFormattingSuggestions: self.withFormattingSuggestions,
                withTextStrictlyAsWords: self.withTextStrictlyAsWords,
                withCapitalization: self.withCapitalization
            )
                
            // Set Date Created
            duplicateNote.dateCreated = self.dateCreated
            
            // Set Date Modified
            duplicateNote.dateModified = self.dateModified
            
            // Execute handler
            onFinishHandler(duplicateNote)
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
        
        let sentenceSegment = Utils.binarySearch(
            in: self.noteSegments,
            isLower: { segment in
                return segment.getSentence().timeRange.end < forTrackTime
            },
            isHigher: { segment in
                return segment.getSentence().timeRange.start > forTrackTime
            }
        )
        
        if let sentenceSegment = sentenceSegment {
            return sentenceSegment.getSentence()
        }

        return nil
    }
    
    func extractSentence(number: Int, onFinishHandler: @escaping (_ sentence: Note?) -> Void) {
        print("===== Extract Sentence =====")
        guard self.noteBuffer.count == 0 else {
            print("\t[Error] There was a problem inserting passage. Buffer was not empty")
            return
        }
        
        let sentenceSegment = Utils.binarySearch(
            in: self.noteSegments,
            isLower: { segment in
                return segment.getSentence().number < number
            },
            isHigher: { segment in
                return segment.getSentence().number > number
            }
        )
        
        if let sentenceSegment = sentenceSegment {
            sentenceSegment.createSentenceNote() { sentence in
                onFinishHandler(sentence)
            }
            return
        }
    }
    
    func extractSentence(forTrackTime: CMTime, onFinishHandler: @escaping (_ sentence: Note?) -> Void) {
        print("===== Extract Sentence =====")
        guard self.noteBuffer.count == 0 else {
            print("\t[Error] There was a problem inserting passage. Buffer was not empty")
            return
        }
        
        let sentenceSegment = Utils.binarySearch(
            in: self.noteSegments,
            isLower: { segment in
                return segment.getSentence().timeRange.end < forTrackTime
            },
            isHigher: { segment in
                return segment.getSentence().timeRange.start > forTrackTime
            }
        )
        
        if let sentenceSegment = sentenceSegment {
            sentenceSegment.createSentenceNote() { sentence in
                onFinishHandler(sentence)
            }
            return
        }
    }
    
    func extractSentence(type: SentencePosition, onFinishHandler: @escaping (_ sentence: Note?) -> Void) {
        let currentTime = player.currentTime()
        self.extractSentence(forTrackTime: currentTime) { sentence in
            switch type {
            case .current:
                onFinishHandler(sentence)
                break
            case .previous:
                let timestamp = floor(Note.defaultSegmentTimescale * (currentTime.seconds - Utils.TEMPORAL_DELTA))
                let previousTime = CMTimeMake(
                    value: Int64(timestamp),
                    timescale: Int32(Note.defaultSegmentTimescale)
                )
                self.extractSentence(forTrackTime: previousTime) { sentence in
                    onFinishHandler(sentence)
                }
                break
            case .next:
                let timestamp = floor(Note.defaultSegmentTimescale * (currentTime.seconds + Utils.TEMPORAL_DELTA))
                let nextTime = CMTimeMake(
                    value: Int64(timestamp),
                    timescale: Int32(Note.defaultSegmentTimescale)
                )
                self.extractSentence(forTrackTime: nextTime) { sentence in
                    onFinishHandler(sentence)
                }
                break
            }
        }
        
    }
    
    // Assumes playbackSegments are sorted in ascending order of index values
    func getSegment(segment: NoteSegment? = nil, segments: [NoteSegment]? = nil, type: SegmentPosition, isWord: Bool = false, isCommitted: Bool = false) -> NoteSegment? {
        var result: NoteSegment?
        switch type {
        case .current:
            let currentTime = self.player.currentTime()
            result = self.getSegment(forTrackTime: currentTime)
        case .previous:
            guard let segment = segment, let segments = segments else { return nil }
            var currentSegmentIndex = segment.getIndex() - segments[0].getIndex()
            if currentSegmentIndex - 1 >= 0 {
                result = segments[currentSegmentIndex - 1]
            } else {
                // Input segment is the first element in the array
                // We return it because there are no more previous segments
                result = segment
            }
            
            if isWord || isCommitted {
                while let seg = result, (
                    (isWord && (
                        seg.isPunctuation() ||
                        seg.isSilence() ||
                        seg.isVoiceCommandWord() ||
                        seg.isDeleted()
                    )) ||
                    (isCommitted && !seg.isCommitted())
                ) && currentSegmentIndex - 1 >= 0 {
                    currentSegmentIndex -= 1
                    result = segments[currentSegmentIndex]
                }
            }
        case .next:
            guard let segment = segment, let segments = segments else { return nil }
            var currentSegmentIndex = segment.getIndex() - segments[0].getIndex()
            if currentSegmentIndex + 1 < segments.count {
                result = segments[currentSegmentIndex + 1]
            } else {
                // Input segment is the last element in the array
                // We return it because there are no more next segments
                result = segment
            }
            
            if isWord || isCommitted {
                while let seg = result, (
                    (isWord && (
                        seg.isPunctuation() ||
                        seg.isSilence() ||
                        seg.isVoiceCommandWord() ||
                        seg.isDeleted()
                    )) ||
                    (isCommitted && !seg.isCommitted())
                ) && currentSegmentIndex + 1 < segments.count {
                    currentSegmentIndex += 1
                    result = segments[currentSegmentIndex]
                }
            }
        }
        
        if let result = result, (isWord && (
            result.isPunctuation() ||
            result.isSilence() ||
            result.isVoiceCommandWord() ||
            result.isDeleted()
        )) ||
        (isCommitted && !result.isCommitted()) {
            return nil
        } else {
            return result
        }
    }
    
    func getSegment(forTrackTime: CMTime) -> NoteSegment? {
        if let playbackRange = self.playbackRange, self.isPlayingNote {
            let segment = Utils.binarySearch(
                in: Array(self.noteSegments[playbackRange]),
                isLower: { segment in
                    return segment.timeMapping.target.end < forTrackTime
                },
                isHigher: { segment in
                    return segment.timeMapping.target.start > forTrackTime
                }
            )
            return segment
        } else {
            // check committed segments
            let seg = Utils.binarySearch(
                in: self.noteSegments,
                isLower: { segment in
                    return segment.timeMapping.target.end < forTrackTime
                },
                isHigher: { segment in
                    return segment.timeMapping.target.start > forTrackTime
                }
            )
            
            // Only return if we found it
            if let seg = seg {
                return seg
            }
            
            // check buffer segments
            let committedTrackLastSegment = self.noteSegments.last
            if let committedTrackLastSegment = committedTrackLastSegment {
                // We subtract because segments in track two do not factor time from track one
                let boundaryTime = CMTimeSubtract(forTrackTime, committedTrackLastSegment.timeMapping.target.end)
                let segment = Utils.binarySearch(
                    in: self.noteBuffer,
                    isLower: { segment in
                        return segment.timeMapping.target.end < boundaryTime
                    },
                    isHigher: { segment in
                        return segment.timeMapping.target.start > boundaryTime
                    }
                )
                return segment
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
            strictlyAsWord: self.withTextStrictlyAsWords,
            withCapitalization: self.withCapitalization
        ).lowercased()
        let text = self.getText().lowercased()
        if word.count > 0 && segment.timeMapping.target.start.seconds == 0 && segment.isCommitted() && text.count >= word.count {
            characterRange = NSRange(location: 0, length: word.count)
        } else if word.count > 0 && text.count >= word.count {
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
        // Use cached version if it exists
        if let cachedBackgroundNoise = self.cachedBackgroundNoise {
            return cachedBackgroundNoise
        }
        
        if self.soundIntensityStream.count == 0 {
            return Double.infinity
        }
        
        let soundIntensityStream = Utils.cleanseSoundIntensityStream(soundIntensityStream: self.soundIntensityStream)
        
        // Determine sound intensity with greatest frequency
        var counts = [Int: Int]()
        soundIntensityStream.forEach {
            if $0.power != Double.infinity && $0.power != Double.nan && $0.power != -Double.infinity {
                counts[Int($0.power)] = (counts[Int($0.power)] ?? 0) + 1
            }
        }
        if let (value, _) = counts.max(by: {$0.1 < $1.1}) {
            self.cachedBackgroundNoise = Double(value)
            return self.cachedBackgroundNoise!
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
                return (powerSum / numSegments).rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT)
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
                    return (powerSum / numSegments).rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT)
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
    
    func getDuration(filteredDuration: Bool = false) -> CMTime {
        let argumentArr: [String] = [
            "filteredDuration=\(filteredDuration)"
        ]
        let argumentSet: Set = Set(argumentArr)

        // Use cached version if it exists
        if let cachedDuration = self.cachedDuration, let cachedDurationArgsSet = self.cachedDurationArgsSet, argumentSet == cachedDurationArgsSet {
            return cachedDuration
        }

        var duration: CMTime = CMTime.zero
        for segment in self.noteSegments {
            if filteredDuration &&
                !segment.isVoiceCommandWord() &&
                !segment.isDeleted() &&
                !(
                    self.omitSilences &&
                    segment.isSilence() &&
                    segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD
                ) {
                duration = CMTimeAdd(duration, segment.getEffectiveDuration())
            } else {
                duration = CMTimeAdd(duration, segment.getEffectiveDuration())
            }
        }
        
        self.cachedDuration = duration
        self.cachedDurationArgsSet = argumentSet
        
        return self.cachedDuration!
    }
    
    func getDurationListening() -> Float {
        // print("===== Get Duration Listening =====")
        if self.pausedListeningForSpeech {
            return Float(self.endTime.seconds)
        } else if self.clipCount > 1 && self.recordStartDate != nil && self.noteSegments.count > 0 {
            return Float(self.noteSegments.last!.timeMapping.target.end.seconds) + Float(Date().timeIntervalSince(self.recordStartDate!))
        } else if self.recordStartDate != nil {
            return Float(Date().timeIntervalSince(self.recordStartDate!))
        }
        
        return 0
    }
    
    func getDateCreated() -> Date {
        return Date(timeIntervalSince1970: self.dateCreated)
    }
    
    func getDateModified() -> Date {
        return Date(timeIntervalSince1970: self.dateModified)
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
                firstBufferSegment = self.noteBuffer.first!
                if !firstBufferSegment!.isActive() {
                    firstBufferSegment = self.getSegment(segment: firstBufferSegment, segments: self.noteBuffer, type: .next, isWord: true)
                }
                
                // Find last buffer word
                lastBufferSegment = self.noteBuffer.last!
                if !lastBufferSegment!.isActive() {
                    lastBufferSegment = self.getSegment(segment: lastBufferSegment, segments: self.noteBuffer, type: .previous, isWord: true)
                }
            } else if let lastBufferRange = self.committedBufferRanges.last {
                let lastBuffer = self.noteSegments[lastBufferRange]
                // Find first buffer word
                firstBufferSegment = lastBuffer.first!
                if !firstBufferSegment!.isActive() {
                    
                }
                firstBufferSegment = self.getSegment(segment: firstBufferSegment, segments: Array(lastBuffer), type: .next, isWord: true)

                // Find last buffer word
                lastBufferSegment = lastBuffer.last!
                if !lastBufferSegment!.isActive() {
                    lastBufferSegment = self.getSegment(segment: lastBufferSegment, segments: Array(lastBuffer), type: .previous, isWord: true)
                }
            }
            
            if let firstBufferSegment = firstBufferSegment, let lastBufferSegment = lastBufferSegment, firstBufferSegment != lastBufferSegment {
                Utils.executeFeedback(
                    visualMessage: "\"\(firstBufferSegment.getText().lowercased())...\(lastBufferSegment.getText().lowercased())\" committed!",
                    note: self,
                    withHaptics: true
                )
            } else if let firstBufferSegment = firstBufferSegment, let lastBufferSegment = lastBufferSegment, firstBufferSegment == lastBufferSegment {
                Utils.executeFeedback(
                    visualMessage: "\"\(firstBufferSegment.getText().lowercased())\" committed!",
                    note: self,
                    withHaptics: true
                )
            } else {
                print("===== [Error] There was a problem finding the first and last words of buffer =====")
            }
        }
        
        // Present Feedback
//        hapticEngine.lightImpact()
        Utils.executeFeedback(
            note: self,
            withHaptics: true
        )
    }
    
    func prepareSpeechCommandHandler(command: String) {
        self.stagedSpeechCommand = command.lowercased()

        // We put it in a handler so we can run it when we receive final transcript
        self.tempVoiceCommandHandler = {
            print("===== Speech Command Handler =====")
            
            if !selectionCursor.isUpdatingSelection {
                print("\tSeeking lowest voice command index...")
                
                let lastBufferRange = self.committedBufferRanges[self.committedBufferRanges.count - 1]
                let voiceCommandBuffer = self.noteSegments[lastBufferRange]
                var lowestCommandIndex: Int?
                var numWordsEncountered: Int = 0
                for i in voiceCommandBuffer.startIndex..<voiceCommandBuffer.endIndex {
                    let segment = voiceCommandBuffer[i]
                    if segment.isActive() && numWordsEncountered == self.numWordsBeforeVoiceCommand {
                        print("\tFound lowest voice command index: \(i) of \(self.noteSegments.count - 1)")
                        lowestCommandIndex = i
                        break
                    } else if segment.isActive() && numWordsEncountered < self.numWordsBeforeVoiceCommand {
                        numWordsEncountered += 1
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
                            if !segment.isSilence() && !segment.isVoiceCommandWord() && !segment.isDeleted() {
                                lastBufferWord = segment
                                lastBufferWordIndex = index
                                print("\tFound new anchor index: ", lastBufferWordIndex)
                                break
                            }
                        }
                        
                        if let currentAnchor = selectionCursor.anchor, let lastBufferWord = lastBufferWord {
                            updateSelectionAnchor = currentAnchor.getUID() != lastBufferWord.getUID()
                        }
                    } else if selectionCursor.cachedAnchor != nil && self.noteBuffer.count == 0 {
                        print("\tBuffer is empty and Cached Anchor detected to be committed segment...")
                        print("\tFind index of new anchor to use as new anchor value...")
                        let secondLastBufferRange = self.committedBufferRanges[self.committedBufferRanges.count - 2]
                        let lastWordsBuffer = self.noteSegments[secondLastBufferRange]
                        var lastBufferWord: NoteSegment?
                        for (index, segment) in lastWordsBuffer.reversed().enumerated() {
                            if !segment.isSilence() && !segment.isVoiceCommandWord() && !segment.isDeleted() {
                                lastBufferWord = segment
                                lastBufferWordIndex = self.noteSegments.distance(to: secondLastBufferRange.startIndex) + (lastWordsBuffer.count - index - 1)
                                print("\tFound new anchor index: ", lastBufferWordIndex)
                                break
                            }
                        }
                        
                        if let currentAnchor = selectionCursor.anchor, let lastBufferWord = lastBufferWord {
                            updateSelectionAnchor = currentAnchor.getUID() != lastBufferWord.getUID()
                        }
                    } else {
                        print("\tFind index of new anchor to use as new anchor value...")
                        var lastBufferWord: NoteSegment?
                        for (index, segment) in self.noteSegments.reversed().enumerated() {
                            if !segment.isSilence() && !segment.isVoiceCommandWord() && !segment.isDeleted() {
                                lastBufferWord = segment
                                lastBufferWordIndex = self.noteSegments.count - index - 1
                                print("\tFound new anchor index: ", lastBufferWordIndex)
                                break
                            }
                        }
                        
                        if let currentAnchor = selectionCursor.anchor, let lastBufferWord = lastBufferWord {
                            updateSelectionAnchor = currentAnchor.getUID() != lastBufferWord.getUID()
                        }
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
                    
                    self.numWordsBeforeVoiceCommand = 0
                    
                    self.handleMutation()
                    self.checkRep()

                    self.handleOnListenUpdate(text: self.getText())
                    
                    // Handle voice command
                    self.handleVoiceCommand(command: command.lowercased())
                }
            } else {
                // Handle voice command
                self.handleVoiceCommand(command: command.lowercased())
            }
        }
    }
    
    func handleOnListenUpdate(text: String, highlightRange: NSRange? = nil) {
        if self.isListeningForSpeech && self.noteBuffer.count > 0, let firstBufferSegment = self.noteBuffer.first, let lastBufferSegment = self.noteBuffer.last, let firstBufferSegmentTextRange = self.getSegmentTextRange(of: firstBufferSegment), let lastBufferSegmentTextRange = self.getSegmentTextRange(of: lastBufferSegment) {
            let bufferTextRange = NSRange(
                location: firstBufferSegmentTextRange.location,
                length: (lastBufferSegmentTextRange.location - firstBufferSegmentTextRange.location) + lastBufferSegmentTextRange.length
            )
            self.onListenUpdate?(text, highlightRange, bufferTextRange)
        } else if self.isListeningForCommands && !pausedListeningForSpeech {
            // All text is buffer text when listening for commands
            let bufferTextRange = NSRange(
                location: 0,
                length: text.count
            )
            self.onListenUpdate?(text, highlightRange, bufferTextRange)
        } else {
            self.onListenUpdate?(text, highlightRange, nil)
        }
    }
    
    func handleMutation() {
        // Update date modified
        self.dateModified = TimeInterval(Date().timeIntervalSince1970)
        
        // Clear out cached properties so they are computed again
        self.cachedText = nil
        self.cachedDuration = nil
        self.cachedTextArgsSet = nil
        self.cachedSegmentUIDSet = nil
        self.cachedDurationArgsSet = nil
        self.cachedBackgroundNoise = nil
    }
    
    func isValidVoiceCommand(query: String) -> (Bool, String?, Int?) {
        if let (type, numWordsBeforeVoiceCommand) = voiceCommandEngine.includesCommand(passage: query) {
            // Determine if voice command is well spaced from previous voice command
            print("===== Is Valid Voice Command [Checking interval between commands]: ", self.voiceCommandStream.last?.type ?? "nil", type, self.voiceCommandStream.last?.date.addingTimeInterval(Utils.MINIMUM_REST_BETWEEN_VOICE_COMMANDS).timeIntervalSince1970 ?? "nil", Date().timeIntervalSince1970, " =====")
            if let lastVoiceCommand = self.voiceCommandStream.last, lastVoiceCommand.type == type && Date() < lastVoiceCommand.date.addingTimeInterval(Utils.MINIMUM_REST_BETWEEN_VOICE_COMMANDS) {
                // Likely too close to last voice command that was the same voice command
                return (false, type, numWordsBeforeVoiceCommand)
            } else if !selectionCursor.hasSelection && voiceCommandEngine.isSelectionVoiceCommand(command: type) {
                // Attempting to use selection voice command without selection
                return (false, type, numWordsBeforeVoiceCommand)
            } else if type == "stop" && !self.isPlayingNote && !self.isPlayingEcho && !self.isRunningNote {
                // User said stop when no stoppable mode was active
                return (false, type, numWordsBeforeVoiceCommand)
            } else {
                // Well spaced from last voice command
                // or no previous voice commands captured
                return (true, type, numWordsBeforeVoiceCommand)
            }
        } else {
            // Is an invalid voice command
            return (false, nil, nil)
        }
    }
    
    func getLastCommit() -> [NoteSegment]? {
        var lastCommit: [NoteSegment]?
        for range in self.committedBufferRanges.reversed() {
            var allInactive = true
            // search range for active word/s
            for segment in self.noteSegments[range] {
                if segment.isActive() {
                    allInactive = false
                    break
                }
            }
            
            // Look at next range for active word/s
            if allInactive {
                continue
            }
            
            lastCommit = Array(self.noteSegments[range])
            return lastCommit
        }
        
        return nil
    }
    
    // MARK: - Key-Value Observer
    
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ){
//        guard self.noteBuffer.count == 0 else {
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
                print("===== Playing Note =====")
                let timeScale = CMTimeScale(NSEC_PER_SEC)
                let time = CMTime(seconds: 1, preferredTimescale: timeScale)

                if let _ = self.observerContext["secondElapseHandler"] {
                    print("\tSet Playback Second Handler...")
                    self.timerObserverToken = player.addPeriodicTimeObserver(forInterval: time, queue: .main) {time in
                        self.handlePeriodicTimeObserver()
                    }
                }
                
                if let _ = self.observerContext["segmentBoundaryHandler"], let playbackRange = self.playbackRange, !selectionCursor.isLoopingSelection {
                    print("\tSet Playback Segment Boundary Handler...")
                    // if we have a selection, animating through each word removes it
                    var boundaryTimes = [NSValue]()
                    for segment in self.noteSegments[playbackRange] {
                        boundaryTimes.append(NSValue(time: segment.timeMapping.target.start))
                    }
                    
                    self.boundaryObserverToken = player.addBoundaryTimeObserver(forTimes: boundaryTimes, queue: .main) {
                        self.handleBoundaryTimeObserver()
                    }
                }
                
                print("\tSet Playback Finish Handler...")
                self.completionObserverToken = player.addBoundaryTimeObserver(forTimes: [NSValue(time: self.stopPlaybackAt!)], queue: .main) {
                    self.handleCompletionObserver()
                }
                
                // Start note
                player.play()
                
                // Set player rate
                let firstPlayableSegment = self.getSegment(
                    forTrackTime: CMTimeMake(
                        value: Int64(Note.defaultSegmentTimescale * (self.startPlaybackAt!.seconds + Utils.TEMPORAL_DELTA)),
                        timescale: Int32(Note.defaultSegmentTimescale)
                    )
                )
                let rate = firstPlayableSegment != nil && !self.isPlayingExternalSegments ? firstPlayableSegment!.getRate() * self.vc!.playbackRate : self.vc!.playbackRate
                let rateWasSet = Utils.setPlayerRate(player: self.player, rate: rate)
                if rateWasSet {
                    print("\tPlayer rate was successfully set: ", rate)
                } else {
                    print("\t[Error] There was a problem setting player rate. Player had not been started yet.")
                }
                
                if self.startPlaybackAt! == self.startTime && !self.isPlayingExternalSegments {
                    print("\tPlaying from start of recording...")
                } else {
                    print("\tPlaying from \(self.startPlaybackAt!.seconds) seconds ...")
                }
                // Check to see if there is a silence at the start we need to skip
                self.handleBoundaryTimeObserver(start: true)

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
    
    func handlePeriodicTimeObserver() {
        DispatchQueue.main.async {
            if let secondElapseHandler = self.observerContext["secondElapseHandler"] {
                secondElapseHandler()
            }
        }
    }
    
    func handleBoundaryTimeObserver(start: Bool = false) {
        let seekNextSegmentHandler: (_ segment: NoteSegment, _ conditional: Bool) -> Void = { segment, conditional in
            if conditional && (
                (self.skipPunctuation && segment.isPunctuation()) ||
                (self.omitSilences && segment.isSilence() && segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD) ||
                segment.isVoiceCommandWord() ||
                segment.isDeleted()
            ), let nextWord = self.getSegment(segment: segment, segments: Array(self.noteSegments[self.playbackRange!]), type: .next, isWord: true) {
                // skip to next segment
                self.previousBoundarySegment = segment
                self.player.seek(
                    to: nextWord.timeMapping.target.start,
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )
                
                // Turn down volume to not hear stutters from voice command word
                Utils.setPlayerVolume(player: self.player, volume: 0)
            } else {
                self.previousBoundarySegment = segment
                
                // Make sure volume is correctly set
                if self.player.volume != self.vc!.playbackVolume {
                    Utils.setPlayerVolume(player: self.player, volume: self.vc!.playbackVolume)
                }
            }
            
            // Make sure rate is correctly set
            if self.player.rate != segment.getRate() {
                let _ = Utils.setPlayerRate(player: self.player, rate: segment.getRate() * self.vc!.playbackRate)
            }
            
            self.observerContext["segmentBoundaryHandler"]?()
        }
        
        let seekEndPlaybackHandler: (_ segment: NoteSegment, _ conditional: Bool) -> Void = { segment, conditional in
            if conditional && (
                (self.skipPunctuation && segment.isPunctuation()) ||
                (self.omitSilences && segment.isSilence() && segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD) ||
                segment.isVoiceCommandWord() ||
                segment.isDeleted()
            ) {
                // skip to next segment
                self.previousBoundarySegment = nil
                self.player.seek(
                    to: CMTimeMake(
                        value: Int64(Note.defaultSegmentTimescale * (self.player.currentItem!.duration.seconds - Utils.PLAYER_END_PLAYBACK_BUFFER)),
                        timescale: Int32(Note.defaultSegmentTimescale)
                    ),
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero
                )

                // Turn down volume to not hear stutters from voice command word
                Utils.setPlayerVolume(player: self.player, volume: 0)
            } else {
                self.previousBoundarySegment = segment
                
                // Make sure volume is correctly set
                if self.player.volume != self.vc!.playbackVolume {
                    Utils.setPlayerVolume(player: self.player, volume: self.vc!.playbackVolume)
                }
            }
            
            // Make sure rate is correctly set
            if self.player.rate != segment.getRate() {
                let _ = Utils.setPlayerRate(player: self.player, rate: segment.getRate() * self.vc!.playbackRate)
            }
            
            self.observerContext["segmentBoundaryHandler"]?()
        }
        
        let currentSegment = self.getSegment(type: .current)
        if start {
            let segment = Array(self.noteSegments[self.playbackRange!])[0]
            seekNextSegmentHandler(segment, true)
        } else if let segment = currentSegment, segment == self.noteSegments.last! || (
            (
                (self.skipPunctuation && segment.isPunctuation()) ||
                (self.omitSilences && segment.isSilence() && segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD) ||
                segment.isVoiceCommandWord() ||
                segment.isDeleted()
            ) && self.getSegment(segment: segment, segments: Array(self.noteSegments[self.playbackRange!]), type: .next, isWord: true) == nil
        ) {
            // last segment of note
            seekEndPlaybackHandler(segment, true)
        } else if let segment = currentSegment {
            // We do an equality check with the previous boundary to make sure we are strictly moving
            // forward and not stuck in loop of playing an older segment
            seekNextSegmentHandler(segment, self.previousBoundarySegment != nil && segment != previousBoundarySegment)
        } else {
            // Stop
            self.previousBoundarySegment = nil
            self.player.seek(
                to: CMTimeMake(
                    value: Int64(Note.defaultSegmentTimescale * (self.player.currentItem!.duration.seconds - Utils.PLAYER_END_PLAYBACK_BUFFER)),
                    timescale: Int32(Note.defaultSegmentTimescale)
                ),
                toleranceBefore: CMTime.zero,
                toleranceAfter: CMTime.zero
            )

            // Turn down volume to not hear stutters from voice command word
            Utils.setPlayerVolume(player: self.player, volume: 0)
            
            self.observerContext["segmentBoundaryHandler"]?()
        }
    }
    
    func handleCompletionObserver() {
        print("===== Completed Playing Note =====")

        if let stopPlaybackAt = self.stopPlaybackAt, let startPlaybackAt = self.startPlaybackAt, selectionCursor.hasSelection && selectionCursor.isLoopingSelection && !self.isWalkingNote && !self.isRunningNote {
            // Stop Playing
            self.stop()
            
            let delayBetweenLooping = CMTimeSubtract(stopPlaybackAt, startPlaybackAt).seconds + 1
            self.playerLoopTimer = Timer.scheduledTimer(withTimeInterval: delayBetweenLooping, repeats: false) { timer in
                selectionCursor.playSelection(loop: true)
            }
        } else {
            print("\tStop note.")
            // Stop Playing
            self.stop()
            
            if soundEngine.isProcessing {
                soundEngine.stopProcessing()
            }

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
        if voiceCommandEngine.voiceCommandMapping[command] == "stop note" && AVAudioSession.isHeadphonesConnected {
            voiceCommandEngine.process(note: self, query: command) {
                if !selectionCursor.hasSelection {
                    self.handleOnListenUpdate(text: self.getText())
                } else {
                    self.vc!.adjustCommandBar()
                    self.vc!.adjustMenuBar()
                }
            }
        } else if !AVAudioSession.isHeadphonesConnected && (
            voiceCommandEngine.voiceCommandMapping[command] == "play note" ||
            voiceCommandEngine.voiceCommandMapping[command] == "play selection" ||
            voiceCommandEngine.voiceCommandMapping[command] == "play previous sentence" ||
            voiceCommandEngine.voiceCommandMapping[command] == "play commit"
        ) {
            // We don't have headphones connected, so we don't start listening until playback is complete
            // If we listen immediately, the words will be heard and processed
            voiceCommandEngine.process(note: self, query: command) {
                if self.pausedListeningForSpeech {
                    // Start listening for speech again if paused
                    // It won't be paused if the processed voice command was 'stop note'
                    self.startListeningForSpeech(
                        soundIntensityHandler: self.soundIntensityHandler,
                        pitchHandler: self.pitchHandler
                    ) {
                        if !selectionCursor.hasSelection {
                            self.handleOnListenUpdate(text: self.getText())
                        } else {
                            self.vc!.adjustCommandBar()
                            self.vc!.adjustMenuBar()
                        }
                    }
                } else {
                    if !selectionCursor.hasSelection {
                        self.handleOnListenUpdate(text: self.getText())
                    } else {
                        self.vc!.adjustCommandBar()
                        self.vc!.adjustMenuBar()
                    }
                }
            }
        } else if !AVAudioSession.isHeadphonesConnected && (
            voiceCommandEngine.voiceCommandMapping[command] == "echo note"
        ) {
            // We don't have headphones connected, so we don't start listening until playback is complete
            // If we listen immediately, the words will be heard and processed
            voiceCommandEngine.process(note: self, query: command) {
                if !selectionCursor.hasSelection {
                    self.handleOnListenUpdate(text: self.getText())
                } else {
                    self.vc!.adjustCommandBar()
                    self.vc!.adjustMenuBar()
                }
            }
        } else {
            voiceCommandEngine.process(note: self, query: command) {
                let voiceCommand = voiceCommandEngine.voiceCommandMapping[command]
                if (
                    voiceCommand != "pause note" &&
                    voiceCommand != "open selection" &&
                    voiceCommand != "select commit" &&
                    voiceCommand != "rollback commit" &&
                    voiceCommand != "walk commit" &&
                    voiceCommand != "run commit" &&
                    voiceCommand != "walk selection" &&
                    voiceCommand != "run selection" &&
                    voiceCommand != "halt run" &&
                    voiceCommand != "next element" &&
                    voiceCommand != "previous element" &&
                    voiceCommand != "exit mode" &&
                    !selectionCursor.hasSelection
                ) && self.pausedListeningForSpeech {
                    // Start listening for speech again if paused
                    // It won't be paused if the processed voice command was 'stop note'
                    self.startListeningForSpeech(
                        soundIntensityHandler: self.soundIntensityHandler,
                        pitchHandler: self.pitchHandler
                    ) {
                        if !selectionCursor.hasSelection {
                            self.handleOnListenUpdate(text: self.getText())
                        } else {
                            self.vc!.adjustCommandBar()
                            self.vc!.adjustMenuBar()
                        }
                    }
                } else {
                    if !selectionCursor.hasSelection {
                        self.handleOnListenUpdate(text: self.getText())
                    } else {
                        self.vc!.adjustCommandBar()
                        self.vc!.adjustMenuBar()
                    }
                }
            }
        }
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
            
            let onFinishHandler: (() -> Void) = { [weak self] in
                self?.isExporting = false
                // We previously had these in stopListeningForSpeech, but clearing these
                // to soon affects normalization, which rquires recordStartDate to date PitchDatum and SoundIntensityDatum
                self?.accumulatedDuration = TimeInterval(0)
                self?.recordStartDate = nil
                // Start voice commands
                DispatchQueue.main.async {
                    Utils.executeFeedback(
                        visualMessage: "Saved!",
                        audioMessage: "note saved",
                        note: self!,
                        withHaptics: true,
                        delay: 1.0
                    )
                    self?.startListeningForVoiceCommands(
                        soundIntensityHandler: self?.soundIntensityHandler,
                        pitchHandler: self?.pitchHandler
                    )
                }
            }
            
            if self.noteSegments.count > 0 {
                // No need to normalize segments or export note if we haven't captured anything meaningful
                let _ = self.normalizeSegments(
                    normalizeType: .target,
                    saveSegments: true,
                    saveToLowLevelRepr: true
                )
                print("final segments: ", self.noteSegments)
                Utils.executeFeedback(
                    visualMessage: "Saving...",
                    audioMessage: "saving note",
                    note: self,
                    withHaptics: true
                )
                // Export completed note
                self.isExporting = true
                Utils.exportNote(
                    note: self,
                    filename: self.filename,
                    fileType: self.fileType,
                    timeRange: CMTimeRangeMake(start: CMTime.zero, duration: self.getDuration()),
                    onFinishHandler: onFinishHandler
                )
            } else {
                onFinishHandler()
            }
        }
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        DispatchQueue.main.async {
            if self.isListeningForSpeech && !self.pausedListeningForSpeech && Utils.validSpeechPower(soundIntensityStream: self.soundIntensityStream, backgroundNoise: self.getBackgroundNoise()) {
                print("===== Received hypothesis transcription: \(transcription.formattedString) =====")
                // Stop Echo
                if self.vc!.speechSynthesizer.isSpeaking {
                    self.vc!.speechSynthesizer.stopSpeaking(at: .word)
                }

                self.performTranscriptionUpdate(transcription)
                
                if !selectionCursor.isUpdatingSelection && (self.isListeningForSpeech || self.noteSegments.count == 0) {
                    let text = self.getText()
                    // execute listen update handler
                    self.handleOnListenUpdate(text: text)
                }
                
                // Analyze for voice commands
                let (isValidVoiceCommand, voiceCommandType, numWordsBeforeVoiceCommand) = self.isValidVoiceCommand(query: transcription.formattedString)
                
                if let numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand, let voiceCommandType = voiceCommandType, isValidVoiceCommand {
                    print("\tCommand Recognized!: \(transcription.formattedString)")
                    // prepare voice command handler
                    
                    // Set early detection flag on
                    self.earlyVoiceCommandDetection = true
                    
                    // Record how many words occur before voice command
                    self.numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand
                    
                    // Capture Voice Command Datum
                    let voiceCommandDatum = VoiceCommandDatum(
                        date: Date(),
                        utteredSpeech: transcription.formattedString,
                        isValid: true,
                        type: voiceCommandType
                    )
                    self.voiceCommandStream.append(voiceCommandDatum)

                    self.prepareSpeechCommandHandler(command: transcription.formattedString)

                    self.stopListeningForSpeech(pause: true)
                }
            } else if self.isListeningForCommands && Utils.validSpeechPower(soundIntensityStream: self.soundIntensityStream, backgroundNoise: self.getBackgroundNoise()) {
                // Analyze for voice commands
                let (isValidVoiceCommand, voiceCommandType, numWordsBeforeVoiceCommand) = self.isValidVoiceCommand(query: transcription.formattedString)

                // execute listen update handler
                if !self.isListeningForSpeech && self.noteSegments.count == 0 {
                    // Don't clear text if we're mid-note
                    // Dont clear text if we have existing note segments
                    self.handleOnListenUpdate(text: transcription.formattedString)
                }
                
                // We don't want to have double error audio
                if !isValidVoiceCommand {
//                    // Play Sound
//                    soundEngine.voiceCommandDeny()
//
//                    var text = ""
//                    for segment in transcription.segments {
//                        text += " \(segment.substring)"
//                    }
//
//                    text = text.trimTrailingPunctuation()

//                    if text.count > 0 {
//                        Utils.executeFeedback(
//                            visualMessage: "\"\(transcription.segments.count > 3 ? "\(transcription.segments.first!.substring.lowercased())...\(transcription.segments.last!.substring.lowercased())" : text.lowercased())\"",
//                            note: self,
//                            withHaptics: true,
//                            delay: 0
//                        )
//                    }
                    
                    // Capture invalid voice commands
                    let voiceCommandDatum = VoiceCommandDatum(
                        date: Date(),
                        utteredSpeech: transcription.formattedString,
                        isValid: false
                    )
                    self.voiceCommandStream.append(voiceCommandDatum)
                }
                
                if let numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand, let voiceCommandType = voiceCommandType, isValidVoiceCommand {
                    // execute listen update handler
                    if !self.isListeningForSpeech && self.noteSegments.count == 0 {
                        // Don't clear text if we're mid-note
                        self.handleOnListenUpdate(text: "")
                    }
                    
                    // Set early detection flag on
                    self.earlyVoiceCommandDetection = true
                    
                    // Set number of words before voice command
                    self.numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand
                    
                    // Capture Voice Command Datum
                    let voiceCommandDatum = VoiceCommandDatum(
                        date: Date(),
                        utteredSpeech: transcription.formattedString,
                        isValid: true,
                        type: voiceCommandType
                    )
                    self.voiceCommandStream.append(voiceCommandDatum)

                    print("\tCommand Recognized!: \(transcription.formattedString)")
                    // prepare voice command handler
                    voiceCommandEngine.process(note: self, query: transcription.formattedString)
                }
            }
        }
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition result: SFSpeechRecognitionResult) {
        DispatchQueue.main.async {
            let handleFinishRecognition = {
                if !selectionCursor.isUpdatingSelection {
                    // Play Sound
                    soundEngine.commitBuffer()
                }

                // update segments
                self.performTranscriptionUpdate(result.bestTranscription)
                
                // Analyze for voice commands
                let (isValidVoiceCommand, voiceCommandType, numWordsBeforeVoiceCommand) = self.isValidVoiceCommand(query: result.bestTranscription.formattedString)
                
                // trigger commit notification
                if !AVAudioSession.isHeadphonesConnected && !selectionCursor.isUpdatingSelection && !self.earlyVoiceCommandDetection && !isValidVoiceCommand {
                    self.triggerBufferCommitNotification()
                }
                
                if !selectionCursor.isUpdatingSelection {
                    // commit buffer
                    self.commitBuffer()
                    // execute listen update handler
                    self.handleOnListenUpdate(text: self.getText())
                }
                
                // Update duration
                
                // ***** IMPORTANT *****
                // iOS14 has made it such that the duration in a single continguous on-device recognition session
                // does not reset after every didFinishRecognition. As a result, we do not have to accumulate durations
                if #available(iOS 14.0, *) {
                    // do nothing
                } else if !selectionCursor.isUpdatingSelection {
                    self.accumulatedDuration = max(0, Date().timeIntervalSince(self.recordStartDate!) - Utils.TRANSCRIPTION_LATENCY_DURATION)
                }

                if let numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand, let voiceCommandType = voiceCommandType, isValidVoiceCommand && !self.earlyVoiceCommandDetection {
                    print("\tCommand Recognized!: \(result.bestTranscription.formattedString)")
                    // prepare voice command handler
                    // must come before stopListeningForSpeech
                    self.numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand
                    
                    // Capture Voice Command Datum
                    let voiceCommandDatum = VoiceCommandDatum(
                        date: Date(),
                        utteredSpeech: result.bestTranscription.formattedString,
                        isValid: true,
                        type: voiceCommandType
                    )
                    self.voiceCommandStream.append(voiceCommandDatum)

                    self.prepareSpeechCommandHandler(command: result.bestTranscription.formattedString)
                    
                    self.stopListeningForSpeech(pause: true)
                    
                    // Execute Voice Command Handler
                    if let voiceCommandHandler = self.tempVoiceCommandHandler {
                        voiceCommandHandler()
                        self.tempVoiceCommandHandler = nil
                        self.stagedSpeechCommand = nil
                    }
                } else if self.withPassiveEcho && AVAudioSession.isHeadphonesConnected && self.isListeningForSpeech && !self.pausedListeningForSpeech && !selectionCursor.isUpdatingSelection {
                    // compute echo text range
                    if let lastEchoSegmentRange = self.committedBufferRanges.last {
                        self.lastEchoSegmentRange = lastEchoSegmentRange
                    }
                    
                    if let lastEchoSegmentRange = self.lastEchoSegmentRange {
                        let text = self.getText(segments: Array(self.noteSegments[lastEchoSegmentRange]))

                        // Echo formatted String
                        self.handlePassiveEcho(text: text)
                        
                        // Give haptic feedback
                        hapticEngine.lightImpact()
                    }
                } else if selectionCursor.isUpdatingSelection {
                    // handle update selection
                    if !self.pausedListeningForSpeech {
                        // make sure paused
                        self.stopListeningForSpeech(pause: true) {
                            self.startListeningForVoiceCommands(
                                soundIntensityHandler: self.soundIntensityHandler!,
                                pitchHandler: self.pitchHandler!
                            ) {
                                selectionCursor.handleUpdateSelection(segments: self.noteBuffer)
                            }
                        }
                    } else {
                        self.startListeningForVoiceCommands(
                            soundIntensityHandler: self.soundIntensityHandler!,
                            pitchHandler: self.pitchHandler!
                        ) {
                            selectionCursor.handleUpdateSelection(segments: self.noteBuffer)
                        }
                    }
                }
                
                // Turns off early voice commmand detection flag
                self.earlyVoiceCommandDetection = false
            }
            if self.isListeningForSpeech && !self.pausedListeningForSpeech && self.noteBuffer.count > 0 && !self.request!.requiresOnDeviceRecognition && !self.earlyVoiceCommandDetection {
                print("===== Some words heard. Apple servers ended dictation session =====")
                self.stopListeningForSpeech(pause: true) {
                    handleFinishRecognition()
                }
            } else if self.isListeningForSpeech && !self.pausedListeningForSpeech && self.noteBuffer.count > 0 && self.request!.requiresOnDeviceRecognition &&  !self.earlyVoiceCommandDetection {
                handleFinishRecognition()
            } else if self.isListeningForSpeech && self.pausedListeningForSpeech && !self.isListeningForCommands && self.noteBuffer.count > 0 && self.request!.requiresOnDeviceRecognition && self.recordStartDate != nil && self.earlyVoiceCommandDetection {

                self.performTranscriptionUpdate(result.bestTranscription)
                
                if !selectionCursor.isUpdatingSelection {
                    // commit buffer
                    self.commitBuffer()
                    // execute listen update handler
                    self.handleOnListenUpdate(text: self.getText())
                }

                // Execute Voice Command Handler
                if let voiceCommandHandler = self.tempVoiceCommandHandler {
                    voiceCommandHandler()
                    self.tempVoiceCommandHandler = nil
                    self.stagedSpeechCommand = nil
                    self.earlyVoiceCommandDetection = false
                }
            } else if (self.isListeningForCommands && !self.pausedListeningForCommands && !self.earlyVoiceCommandDetection) || (self.isListeningForSpeech && self.pausedListeningForSpeech && !self.isListeningForCommands && self.noteBuffer.count > 0 && self.request!.requiresOnDeviceRecognition && self.recordStartDate == nil && !self.earlyVoiceCommandDetection) {
                // sometimes the voice commands that initiate the note will be sent to be committed erroneously
                // we catch them by identifying that self.recordStartDate == nil, for which they would be if
                // they were processed before note properly started
                print("AYYYYYYY 2")

                if self.noteBuffer.count > 0 {
                    // clear buffer
                    self.clearBuffer()
                }
                
                // Analyze for voice commands
                let (isValidVoiceCommand, voiceCommandType, numWordsBeforeVoiceCommand) = self.isValidVoiceCommand(query: result.bestTranscription.formattedString)
                
                // execute listen update handler
                if !self.isListeningForSpeech && self.noteSegments.count == 0 {
                    // We are not yet starting a note and have no noteSegments. We should remove text on screen
                    self.handleOnListenUpdate(text: "")
                }
                
                if !isValidVoiceCommand {
                    // Play Sound
                    soundEngine.voiceCommandDeny()

                    var text = ""
                    for segment in result.bestTranscription.segments {
                        text += " \(segment.substring)"
                    }
                    
                    text = text.trimTrailingPunctuation()
                    if text.count > 0 {
                        Utils.executeFeedback(
                            visualMessage: "\"\(result.bestTranscription.segments.count > 3 ? "\(result.bestTranscription.segments.first!.substring.lowercased())...\(result.bestTranscription.segments.last!.substring.lowercased())" : text.lowercased())\"",
                            audioMessage: result.bestTranscription.formattedString,
                            note: self,
                            withHaptics: true,
                            delay: 0
                        )
                    }
                    
                    // Capture invalid voice commands
                    let voiceCommandDatum = VoiceCommandDatum(
                        date: Date(),
                        utteredSpeech: result.bestTranscription.formattedString,
                        isValid: false
                    )
                    self.voiceCommandStream.append(voiceCommandDatum)
                    
                    // Turns off early voice commmand detection flag
                    self.earlyVoiceCommandDetection = false
                }

                if let numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand, let voiceCommandType = voiceCommandType, isValidVoiceCommand {
                    // execute listen update handler
                    if !self.isListeningForSpeech && self.noteSegments.count == 0 {
                        // Don't clear text if we're mid-note
                        self.handleOnListenUpdate(text: "")
                    }

                    self.numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand
                    
                    // Capture Voice Command Datum
                    let voiceCommandDatum = VoiceCommandDatum(
                        date: Date(),
                        utteredSpeech: result.bestTranscription.formattedString,
                        isValid: true,
                        type: voiceCommandType
                    )
                    self.voiceCommandStream.append(voiceCommandDatum)

                    print("\tCommand Recognized!: \(result.bestTranscription.formattedString)")
                    voiceCommandEngine.process(note: self, query: result.bestTranscription.formattedString)
                }
            } else {
                // execute listen update handler
                if !self.isListeningForSpeech && self.noteSegments.count == 0 {
                    // We are not yet starting a note and have no noteSegments. We should remove text on screen
                    self.handleOnListenUpdate(text: "")
                }
                
                // Prevents double voice command processing when we are listening for comands
                self.earlyVoiceCommandDetection = false
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
        if pitch.frequency >= MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.soundIntensityStream.count > MIN_SEED_INTENSITY_POINTS && Utils.validSpeechPower(soundIntensityStream: self.soundIntensityStream, backgroundNoise: self.getBackgroundNoise()) {
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
