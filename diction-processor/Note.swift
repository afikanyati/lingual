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

class Note: AVMutableComposition, NSCoding {
    // MARK: - Notifications
    static let onRequestToUpdateView = Notification.Name(Notifications.onRequestToUpdateView.rawValue)
    static let onNoteListenUpdate = Notification.Name(Notifications.onNoteListenUpdate.rawValue)
    static let onNoteListenStop = Notification.Name(Notifications.onNoteListenStop.rawValue)
    static let onNoteComplete = Notification.Name(Notifications.onNoteComplete.rawValue)
    static let onNoteCommittedBuffer = Notification.Name(Notifications.onNoteCommittedBuffer.rawValue)
    
    // MARK: - App Modules
    var state: StateManager!
    var speechSynthesis: SpeechSynthesisEngine!
    var speechRecognition: SpeechRecognitionEngine!
    var speechPlayer: SpeechPlayerEngine!
    var pitchRecognition: PitchRecognitionEngine!
    var notifications: NotificationEngine!
    var selectionCursor: SelectionCursor!
    var noteManager: NoteManager!

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
    /// Stores the time range of the note
    public var timeRange: CMTimeRange {
        return CMTimeRangeMake(start: CMTime.zero, duration: self.getDuration())
    }
    /// The date when note was created
    private(set) var dateCreated: TimeInterval = Date().timeIntervalSince1970
    /// The date when note was last modified
    private(set) var dateModified: TimeInterval = Date().timeIntervalSince1970
    /// Stores the creator's uid
    private(set) var creatorUID: String
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

    // MARK: - Recording Properties
    /// Stores whether note is authorized to listen for speech. This is typically false when then source filetype is .m4a vs. .caf, which happens on note export
    private(set) var authorizedToListenForSpeech = false
    /// Stores a count of the number of unique clips that have been recording throughout note (factors recording breaks due to voice commands)
    private(set) var clips: Set<String> = []
    /// Stores the current clip UID
    private(set) var currentClipUID: String?
    /// Stores a reference to the moment current note clip started listening
    public var recordStartDate: Date?
    /// Stores the total duration of time across segments capturing during the current listening clip
    private var accumulatedDuration = TimeInterval(0)
    /// Stores a reference to the audio file where listening buffers are being saved to
    public var recordFile: AVAudioFile?
    /// Stores whether clip is deleted
    private(set) var isDeleted = false
    /// Stores the timestamp when we last started listening
    private(set) var lastStartedListeningTimestamp: TimeInterval?

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
    
    // MARK: - Telemetry
    private(set) var views = [TimeInterval]()
    private(set) var plays = [TimeInterval]()
    private(set) var textExports = [TimeInterval]()
    private(set) var audioExports = [TimeInterval]()
    
    // MARK: - Initializer

    /// Initializes the Note class instance
    ///
    /// - Parameters:
    ///     - vc: Suppliess a reference to the main view controller
    ///     - filename: Supplies the filename of the note
    ///     - fileType: Suppliess the filetype of the source URL
    ///     - creatorUID: Supplies the creator's uid
    ///     - segments: Supplies an optional array of note segments to seed the note
    ///     - onComplete: Supplies a handler to be executed when note is complete.
    init(
        uid: String,
        filename: String,
        fileType: AVFileType? = nil,
        creatorUID: String,
        segments: [NoteSegment]? = nil
    ) {
        print("===== Note: Initialization =====")
        print("\tFilename: ", filename)
        self.uid = uid
        self.filename = filename
        self.creatorUID = creatorUID
        
        super.init()
        
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
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.uid, forKey: "uid")
        coder.encode(self.filename, forKey: "filename")
        coder.encode(self._fileType, forKey: "fileType")
        coder.encode(self.dateCreated, forKey: "dateCreated")
        coder.encode(self.dateModified, forKey: "dateModified")
        coder.encode(self.creatorUID, forKey: "creatorUID")
        coder.encode(self.noteSegments, forKey: "noteSegments")
        coder.encode(self.segmentIndexMap, forKey: "segmentIndexMap")
        coder.encode(self.deletedSegmentIndexMap, forKey: "deletedSegmentIndexMap")
        var committedBufferRanges = [[String:Int]]()
        for range in self.committedBufferRanges {
            let dictRange: [String:Int] = [
                "startIndex": range.startIndex,
                "endIndex": range.endIndex
            ]
            committedBufferRanges.append(dictRange)
        }
        coder.encode(committedBufferRanges, forKey: "committedBufferRanges") // Can't handle Range objects
        coder.encode(self.transformations, forKey: "transformations")
        print("TRANSFORMATIONS IN: ", self.transformations)
        coder.encode(self.authorizedToListenForSpeech, forKey: "authorizedToListenForSpeech")
        coder.encode(self.clips, forKey: "clips")
        coder.encode(self.views, forKey: "views")
        coder.encode(self.plays, forKey: "plays")
        coder.encode(self.textExports, forKey: "textExports")
        coder.encode(self.audioExports, forKey: "audioExports")
        coder.encode(self.isDeleted, forKey: "isDeleted")
    }
    
    required init?(coder: NSCoder) {
        self.uid = coder.decodeObject(forKey: "uid") as! String
        self.filename = coder.decodeObject(forKey: "filename") as! String
        self._fileType = coder.decodeObject(forKey: "fileType") as! AVFileType
        self.dateCreated = coder.decodeDouble(forKey: "dateCreated")
        self.dateModified = coder.decodeDouble(forKey: "dateModified")
        self.creatorUID = coder.decodeObject(forKey: "creatorUID") as! String
        self.noteSegments = coder.decodeObject(forKey: "noteSegments") as! [NoteSegment]
        self.segmentIndexMap = coder.decodeObject(forKey: "segmentIndexMap") as! [String: Int]
        self.deletedSegmentIndexMap = coder.decodeObject(forKey: "deletedSegmentIndexMap") as! [String: Int]
        if let committedBufferDictRanges = coder.decodeObject(forKey: "committedBufferRanges") as? [[String:Int]] {
            var committedBufferRanges = [Range<Int>]()
            for dictRange in committedBufferDictRanges {
                let range = dictRange["startIndex"]!..<dictRange["endIndex"]!
                committedBufferRanges.append(range)
            }
            self.committedBufferRanges = committedBufferRanges
        }
        self.transformations = coder.decodeObject(forKey: "transformations") as! [NoteTransformation]
        print("TRANSFORMATIONS OUT: ", self.transformations)
        self.authorizedToListenForSpeech = coder.decodeBool(forKey: "authorizedToListenForSpeech")
        self.clips = coder.decodeObject(forKey: "clips") as! Set<String>
        self.startTime = self.noteSegments.count > 0 ? self.noteSegments.first!.timeMapping.target.start : CMTime.zero
        self.endTime = self.noteSegments.count > 0 ? self.noteSegments.last!.timeMapping.target.end : CMTime.zero
        self.views = coder.decodeObject(forKey: "views") as! [TimeInterval]
        self.plays = coder.decodeObject(forKey: "plays") as! [TimeInterval]
        self.textExports = coder.decodeObject(forKey: "textExports") as! [TimeInterval]
        self.audioExports = coder.decodeObject(forKey: "audioExports") as! [TimeInterval]
        self.isDeleted = coder.decodeBool(forKey: "isDeleted")
        
        super.init()
        
        // Add track
        self.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: Int32(kCMPersistentTrackID_Invalid)
        )
        
        // Configure Observers
        self.configureNotificationObservers()
        
        // Make sure segments are set in underlying track
        if self.noteSegments.count > 0 {
            self.setSegments(
                segments: self.noteSegments,
                replaceNoteDetails: true,
                saveToLowLevelRepr: true
            )
        }
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    public override var description: String {
        return "Note {\n\tfilename: \(self.filename) \n\tfileType: \(self.fileType) \n\tdateCreated: \(Utils.getDateString(date: self.dateCreated) ?? "nil") \n\tdateModified: \(Utils.getDateString(date: self.dateModified) ?? "nil") \n\tcreatorUID: \(self.creatorUID) \n\tnoteSegments: \(self.noteSegments) \n\tnoteBuffer: \(self.noteBuffer) \n\tsegmentIndexMap: \(self.segmentIndexMap) \n\tdeletedSegmentIndexMap: \(self.deletedSegmentIndexMap) \n\tcommittedBufferRanges: \(String(describing: self.committedBufferRanges)) \n\ttransformations: \(self.transformations) \n\tstartTime: \(self.startTime) \n\tendTime: \(self.endTime) \n\tduration: \(self.getDuration()) \n\tnumSentences: \(self.numSentences) \n\tlanguage: \(String(describing: self.language)) \n\tavgSpeakingRate: \(self.avgSpeakingRate) \n\tauthorizedToListenForSpeech: \(self.authorizedToListenForSpeech) \n\tclips: \(self.clips) \n\trecordStartDate: \(String(describing: self.recordStartDate)) \n\taccumulatedDuration: \(self.accumulatedDuration) \n\tisDeleted: \(self.isDeleted)\n}"
    }
    
    // MARK: - Configuration Methods
    
    func configureAudioWriteFile() {
        print("===== Configure Note Audio Write File =====")
        do {
            try recordFile = AVAudioFile(
                forWriting: Utils.getFileURL(of: "\(self.filename)-\(self.currentClipUID!)\(self.fileType)"),
                settings: self.speechRecognition.audioEngine.inputNode.inputFormat(forBus: self.speechRecognition.recordBus).settings
            )
            authorizedToListenForSpeech = true
            print("\tSource URL for writing note successfully created: \(self.filename)-\(self.currentClipUID!)\(self.fileType)")
        } catch {
            print("\t[Error] There was a problem instantiating the record file")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        print("===== Note: Configure Notification Observers =====")
        let notificationCenter = NotificationCenter.default
        
        // SpeechRecognitionEngine
        notificationCenter.addObserver(
            self,
            selector: #selector(onStartListeningForSpeech(notification:)),
            name: SpeechRecognitionEngine.onStartedListeningForSpeech,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStoppedListeningForSpeech(notification:)),
            name: SpeechRecognitionEngine.onStoppedListeningForSpeech,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onBufferItem(notification:)),
            name: SpeechRecognitionEngine.onBufferItem,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onSpeechUpdate(notification:)),
            name: SpeechRecognitionEngine.onSpeechUpdate,
            object: nil
        )
    }
    
    @objc func onStartListeningForSpeech(notification: Notification) {
        if self.noteManager == nil || self.isDeleted || noteManager.currentNote == nil || (self.noteManager!.currentNote != nil && self.noteManager!.currentNote!.uid != self.uid) { return }
        print("===== Note \(self.uid): On Start Listening For Speech =====")
        
        // Create and save new clip used to create unique track URLs to write audio into
        self.generateNewClip()
        
        // Reset accumulated Duration for next clip capture
        self.accumulatedDuration = TimeInterval(0)
        
        // Capture last started listening timestamp
        self.lastStartedListeningTimestamp = Date().timeIntervalSince1970

        // Configure Audio Write File
        self.configureAudioWriteFile()
        
        if !self.authorizedToListenForSpeech {
            print("\t[Error] There was a problem while starting to listen for speech. Note is not authorized to listen.")
            return
        }
        
        // Begin new record start date
        if self.speechRecognition.isListeningForSpeech && self.recordStartDate == nil {
            // We place this here so we start tracking recording from the first buffer chunk we receive
            self.recordStartDate = Date()
        }
        
        // Check rep invariant
        self.handleMutation()
        self.checkRep()
    }
    
    @objc func onBufferItem(notification: Notification) {
        if self.noteManager == nil || self.isDeleted || (self.noteManager != nil && self.noteManager!.currentNote == nil) || (self.noteManager != nil && self.noteManager!.currentNote != nil && self.noteManager!.currentNote!.uid != self.uid) { return }

        if let noteManager = self.noteManager, let recordFile = self.recordFile, let note = noteManager.currentNote, note.uid == self.uid && self.speechRecognition.isListeningForSpeech {
//            print("===== Note: On Buffer Item =====")
            let buffer = notification.userInfo!["buffer"] as! AVAudioPCMBuffer
            
            // Write buffer data to audio file
            do {
                try recordFile.write(from: buffer)
            } catch {
                print("\t[Error] There was a problem writing speech to file")
            }
            
//            // Check rep invariant
//            self.handleMutation()
//            self.checkRep()
        }
    }
    
    @objc func onSpeechUpdate(notification: Notification) {
        if self.noteManager == nil || self.tracks.count == 0 || self.isDeleted || self.noteManager!.currentNote == nil || (self.noteManager!.currentNote != nil && self.noteManager!.currentNote!.uid != self.uid) { return }
        print("===== Note \(self.uid): On Speech Update =====")
        
        let transcription = notification.userInfo!["transcription"] as! SFTranscription
        let isVoiceCommand = notification.userInfo!["isVoiceCommand"] as! Bool
        let voiceCommandType = notification.userInfo!["voiceCommandType"] as? String
        let numWordsBeforeVoiceCommand = notification.userInfo!["numWordsBeforeVoiceCommand"] as? Int
        let isFinalTranscription = notification.userInfo!["isFinalTranscription"] as! Bool

        if self.speechRecognition.isListeningForSpeech || (isVoiceCommand && voiceCommandType == "stop note") {
            print("\tProcessing transcript...")
            self.performTranscriptionUpdate(transcription)
            print("\tBuffer: ", self.noteBuffer.map { $0.getText() })
        }
        
        if self.selectionCursor.isUpdatingSelection && !self.selectionCursor.isPromptingForUpdateAcceptance && !isVoiceCommand && isFinalTranscription {
            // we don't let voice command in here, because it is likely a "cancel" voice command
            print("\tProcess selection update...")
            // we need to set this early to avoid second call (from didFinish) to trigger
            // in latency time between first call and setting this property
            self.selectionCursor.setIsPromptingForUpdateAcceptance(to: true)
            // handle update selection
            if !self.speechRecognition.pausedListeningForSpeech {
                // make sure paused
                self.speechRecognition.pauseListeningForSpeech() {
                    self.selectionCursor.handleUpdateSelection(segments: self.noteBuffer)
                }
            } else {
                self.selectionCursor.handleUpdateSelection(segments: self.noteBuffer)
            }
        } else if isFinalTranscription && !self.selectionCursor.isUpdatingSelection && (self.speechRecognition.isListeningForSpeech || (isVoiceCommand && voiceCommandType == "stop note") || self.speechRecognition.pausedListeningForSpeech) {
            print("\tReceived final transcript. Commit buffer.")
            
            // Commit Speech
            if self.noteBuffer.count > 0 {
                // We want to process voice commands before we commit so we avoid punctuation suggestions being formed for new segments
                if let numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand, isVoiceCommand {
                    print("\tProcess voice command...")
                    self.processVoiceCommandSegments(
                        command: transcription.formattedString,
                        numWordsBeforeVoiceCommand: numWordsBeforeVoiceCommand
                    )
                }
                
                // commit buffer
                if !self.speechRecognition.pausedListeningForSpeech {
                    // Play Sound
                    soundEngine.commitBuffer()

                    self.commitBuffer()
                    
                    // trigger commit notification
                    if !AVAudioSession.isHeadphonesConnected && !isVoiceCommand {
                        self.triggerBufferCommitNotification()
                    }
                } else {
                    self.clearBuffer()
                }
                
                // ***** IMPORTANT *****
                // iOS14 has made it such that the duration in a single continguous on-device recognition session
                // does not reset after every didFinishRecognition. As a result, we do not have to accumulate durations
                if #available(iOS 14.0, *) {
                    // do nothing
                } else {
                    self.accumulatedDuration = max(0, Date().timeIntervalSince(self.recordStartDate!) - Utils.TRANSCRIPTION_LATENCY_DURATION)
                }
            }
            
            NotificationCenter.default.post(
                name: Note.onNoteCommittedBuffer,
                object: nil,
                userInfo: [:]
            )
        } else if self.recordStartDate != nil {
            print("\tDo not commit buffer.")
            if let numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand, isVoiceCommand && (self.speechRecognition.isListeningForSpeech || voiceCommandType == "stop note" || self.speechRecognition.pausedListeningForSpeech) && self.noteSegments.count > 0 {
                print("\tProcess voice command...")
                self.processVoiceCommandSegments(
                    command: transcription.formattedString,
                    numWordsBeforeVoiceCommand: numWordsBeforeVoiceCommand
                )
            }
            
            // Don't keep buffer if we're not listening
            if self.speechRecognition.pausedListeningForSpeech {
                self.clearBuffer()
            }
        }
        
        if !self.selectionCursor.isUpdatingSelection {
            // execute listen update handler
            let text = self.getText()
            self.handleOnSpeechUpdate(text: text)
        }
        
        // Save finished app
        if !self.speechRecognition.isListeningForSpeech && self.noteSegments.count > 0 && self.recordStartDate != nil {
            print("\tProcess note finishing...")
            self.handleFinish(normalize: true)
        }
    }
    
    @objc func onStoppedListeningForSpeech(notification: Notification) {
//        if let noteManager = self.noteManager, self.isDeleted || noteManager.currentNote == nil || (noteManager.currentNote != nil && noteManager.currentNote!.uid != self.uid) { return }
//
//        print("===== Note \(self.uid): On Stopped Listening For Speech =====")
    }
    
    // MARK: - Validation
    
    func checkRep() {
        var result = true
        
        // segmentIndexMap and noteSegments length must be the same
        result = result && self.segmentIndexMap.count == self.noteSegments.count
//         print("segmentIndexMap and noteSegments length must be the same: ", self.segmentIndexMap.count, self.noteSegments.count)
//         print("current result: ", result)
        
        // dateModified must be after dateCreated
        result = result && self.dateModified >= self.dateCreated
//         print("dateModified must be after dateCreated: ", self.dateModified, self.dateCreated)
//         print("current result: ", result)

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
        
        if !result {
            fatalError("===== [Error] Note Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Speech Listening Methods
    
    func performTranscriptionUpdate(_ transcription: SFTranscription) {
        print("===== Note: Perform Transcription Update =====")
        print("Transcript Text: ", transcription.formattedString)
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
                sourceTimestamp = floor(Utils.DEFAULT_SEGMENT_TIMESCALE * Utils.DEFAULT_SEGMENT_DURATION)
                
                // Set duration
                duration = floor(Utils.DEFAULT_SEGMENT_TIMESCALE * Utils.DEFAULT_SEGMENT_DURATION)
            } else {
                // Set source timestamp
                sourceTimestamp = floor(Utils.DEFAULT_SEGMENT_TIMESCALE * (Double(transcriptionIndex + 1) * Utils.DEFAULT_SEGMENT_DURATION))
                
                // Set duration
                duration = floor(Utils.DEFAULT_SEGMENT_TIMESCALE * Utils.DEFAULT_SEGMENT_DURATION)
            }
        } else {
            // enters here when we get the final transcript which has timestamp data
            
            // Set source timestamp
            sourceTimestamp = self.accumulatedDuration + segment.timestamp > 0 ?
                    floor(Utils.DEFAULT_SEGMENT_TIMESCALE * (self.accumulatedDuration + segment.timestamp))
                :
                    0
            
            // Set duration
            duration = segment.duration > 0 ? floor(Utils.DEFAULT_SEGMENT_TIMESCALE * segment.duration) : 0
        }
        
        let phoneticallySimilarWords = segment.alternativeSubstrings
        
        guard let currentClipUID = self.currentClipUID else {
            print("\t[Error] There was a problem processing segment. Missing Clip UID")
            return
        }
        let noteSegment = NoteSegment(
            note: self,
            speakerUID: self.creatorUID,
            word: word,
            clipUID: currentClipUID,
            trackURL: Utils.getFileURL(of: "\(self.filename)-\(currentClipUID)\(self.fileType)"),
            trackID: self.tracks[0].trackID,
            phoneticallySimilarWords: phoneticallySimilarWords,
            sourceTimeRange: CMTimeRangeMake(
                start: CMTimeMake(value: Int64(sourceTimestamp), timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)),
                duration: CMTimeMake(value: Int64(duration), timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE))
            ),
            targetTimeRange: CMTimeRangeMake( // This will be properly set in normalize Segments
                start: CMTimeMake(value: Int64(sourceTimestamp), timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)),
                duration: CMTimeMake(value: Int64(duration), timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE))
            ),
            tokenType: segmentTags["tokenType"]!,
            lexicalClass: segmentTags["lexicalClass"]!,
            nameType: segmentTags["nameType"]!,
            lemma: segmentTags["lemma"]!,
            sentimentScore: sentiment ?? nil,
            withPunctuationSuggestions: self.state.withPunctuationSuggestions,
            voiceCommandWord: false
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
                let replaceSelectionAnchor = oldSegment == self.selectionCursor.anchor && !self.selectionCursor.isUpdatingSelection
                let replaceSelectionFocus = oldSegment == self.selectionCursor.focus && !self.selectionCursor.isUpdatingSelection
                let replaceSelectionCachedAnchor = oldSegment == self.selectionCursor.cachedAnchor && !self.selectionCursor.isUpdatingSelection
                
                // Transfer voice command status
                let isVoiceCommandWord = oldSegment.isVoiceCommandWord()
                noteSegment.setIsVoiceCommandWord(to: isVoiceCommandWord)
                
                // set updated segments
                bufferSegments[transcriptionIndex] = noteSegment
                self.noteBuffer = bufferSegments
                
                // update selection anchor
                if replaceSelectionAnchor {
                    self.selectionCursor.setAnchor(segment: self.noteBuffer[transcriptionIndex])
                }
                
                // update selection focus
                if replaceSelectionFocus {
                    self.selectionCursor.setFocus(segment: self.noteBuffer[transcriptionIndex])
                }
                
                // update selection cached anchor
                if replaceSelectionCachedAnchor {
                    self.selectionCursor.setCachedAnchor(segment: self.noteBuffer[transcriptionIndex])
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
        print("===== Note: Normalize Segments =====")
        var lastEnd = CMTime.zero
        var normalizedSegments = [NoteSegment]()
        var silenceIndices = [Int]()
        
        var segs = self.noteBuffer.count > 0 ? self.noteBuffer : self.noteSegments
        if let segments = segments {
            print("\tReceived custom segments. Setting as normalization contents...")
            segs = segments
        }
        
        guard let currentClipUID = self.currentClipUID else {
            print("\t[Error] There was a problem normalizing segments. Missing Clip UID")
            return nil
        }
        
        for (index, segment) in segs.enumerated() {
            if segment.timeMapping[normalizeType].start.seconds != lastEnd.seconds {
                if segment.timeMapping[normalizeType].start.seconds > lastEnd.seconds && !segment.isSilence() {
                    let trackURL = Utils.getFileURL(of: "\(self.filename)-\(currentClipUID)\(self.fileType)")

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
                        speakerUID: self.creatorUID,
                        word: "",
                        clipUID: currentClipUID,
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
                        withPunctuationSuggestions: self.state.withPunctuationSuggestions,
                        utterPunctuationSuggestion: true, // give feedback that we're on a new sentence or paragraph.
                        voiceCommandWord: segment.isVoiceCommandWord()
                    )
                    
                    // Segment Sound intensity
                    let startOfSegmentDuration: Double = lastEnd.seconds
                    
                    // Sound Intensity
                    if segment.getPower() != Double.infinity {
                        // Import sound intensity
                        let power = segment.getPower()
                        segment.setPower(power: power)
                    } else if self.speechRecognition.soundIntensityStream.count > 0 {
                        // Add sound intensities
                        let datum = self.speechRecognition.getRecordingSoundIntensityDatum(timestamp: startOfSegmentDuration)
                        segment.setPower(power: datum.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))
                    }

                    // Silence Sound Intensity/Background Noise
                    if self.speechRecognition.soundIntensityStream.count > 0 {
                        let startOfSilenceDuration: Double = lastEnd.seconds
                        let backgroundNoise = self.speechRecognition.getRecordingSoundIntensityDatum(timestamp: startOfSilenceDuration)
                        silentSegment.setPower(power: backgroundNoise.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))
                    }
                    
                    // Pitch
                    if let pitch = segment.getPitch() {
                        // Import pitch
                        segment.setPitch(pitch: pitch)
                    } else if self.pitchRecognition.pitchStream.count > 0 {
                        // Add pitch
                        let pitch = self.pitchRecognition.getRecordingPitch(timestamp: startOfSegmentDuration)
                        if let p = pitch.pitch {
                            segment.setPitch(pitch: p)
                        }
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
                        speakerUID: segment.getSpeakerUID(),
                        word: segment.getText(),
                        clipUID: currentClipUID,
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
                        withPunctuationSuggestions: self.state.withPunctuationSuggestions,
                        voiceCommandWord: segment.isVoiceCommandWord(),
                        deleted: segment.isDeleted()
                    )
                    
                    let startOfSilenceDuration: Double = lastEnd.seconds
                    
                    // Sound Intensity
                    if segment.getPower() != Double.infinity {
                        // Import sound intensity
                        let power = segment.getPower()
                        modifiedSegment.setPower(power: power)
                    } else if self.speechRecognition.soundIntensityStream.count > 0 {
                        // Add sound intensities
                        let datum = self.speechRecognition.getRecordingSoundIntensityDatum(timestamp: startOfSilenceDuration)
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
                        speakerUID: segment.getSpeakerUID(),
                        word: segment.getText(),
                        clipUID: currentClipUID,
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
                        withPunctuationSuggestions: self.state.withPunctuationSuggestions,
                        voiceCommandWord: segment.isVoiceCommandWord(),
                        deleted: segment.isDeleted()
                    )
                    
                    let startOfSegmentDuration: Double = lastEnd.seconds
                    
                    // Sound Intensity
                    if segment.getPower() != Double.infinity {
                        // Import sound intensity
                        let power = segment.getPower()
                        normalizedSegment.setPower(power: power)
                    } else if self.speechRecognition.soundIntensityStream.count > 0 {
                        // Add sound intensities
                        let datum = self.speechRecognition.getRecordingSoundIntensityDatum(timestamp: startOfSegmentDuration)
                        segment.setPower(power: datum.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))
                    }
                    
                    // Pitch
                    if let pitch = segment.getPitch() {
                        // Import pitch
                        normalizedSegment.setPitch(pitch: pitch)
                    } else if self.pitchRecognition.pitchStream.count > 0 {
                        // Add pitch
                        let pitch = self.pitchRecognition.getRecordingPitch(timestamp: startOfSegmentDuration)
                        if let p = pitch.pitch {
                            segment.setPitch(pitch: p)
                        }
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
            let datum = self.speechRecognition.getRecordingSoundIntensityDatum(timestamp: segment.timeMapping.target.start.seconds)
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
                    speakerUID: segment.getSpeakerUID(),
                    word: segment.getText(),
                    clipUID: currentClipUID,
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
                    withPunctuationSuggestions: self.state.withPunctuationSuggestions,
                    voiceCommandWord: segment.isVoiceCommandWord(),
                    deleted: segment.isDeleted()
                )
                
                let startOfSegmentDuration: Double = lastEnd.seconds
                
                // Sound Intensity
                if segment.getPower() != Double.infinity {
                    // Import sound intensity
                    let power = segment.getPower()
                    shiftedSegment.setPower(power: power)
                } else if self.speechRecognition.soundIntensityStream.count > 0 {
                    // Add sound intensities
                    let datum = self.speechRecognition.getRecordingSoundIntensityDatum(timestamp: startOfSegmentDuration)
                    segment.setPower(power: datum.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))
                }
                
                // Pitch
                if let pitch = segment.getPitch() {
                    // Import pitch
                    shiftedSegment.setPitch(pitch: pitch)
                } else if self.pitchRecognition.pitchStream.count > 0 {
                    // Add pitch
                    let pitch = self.pitchRecognition.getRecordingPitch(timestamp: startOfSegmentDuration)
                    if let p = pitch.pitch {
                        segment.setPitch(pitch: p)
                    }
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
        print("===== Note: Commit Buffer =====")

        // duplicate note tracks
        print("\tDuplicating buffer segments...")
        var bufferText = "\tBuffer Segments: "
        var segments = [NoteSegment]()
        for segment in self.noteBuffer {
            bufferText += "'\(segment.getText())', "
            segments.append(segment.duplicate())
        }
        
        print(bufferText)
        
        print("\tIdentifying insert time...")
        var insertTime: CMTime
        var updateCachedAnchor = false
        var cachedAnchorIndex = Int(Utils.UNKNOWN)
        var numSegmentsBehindCursorBeforeInsertion: Int
        var numSegmentsAheadCursorBeforeInsertion: Int
        if let cachedAnchor = self.selectionCursor.cachedAnchor {
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
        if let anchor = self.selectionCursor.anchor {
            print("\tSelection anchor identified: ", anchor.getText())
            oldAnchor = anchor.duplicate()
        }
        
        var oldFocus: NoteSegment?
        if let focus = self.selectionCursor.focus {
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
        
        let lastBufferWordIndex = Utils.getNoteNthLastSegmentIndex(
            segments: normalizedSegments!,
            selectionCursor: self.selectionCursor,
            n: 0
        ).1
        if let lastBufferWordIndex = lastBufferWordIndex {
            print("\tLast Buffer Word Index: ", lastBufferWordIndex)
        }
        
        print("\tInserting buffer segments...")
        self.insertPassage(
            segments: normalizedSegments!,
            at: insertTime
        )
        
        if let lastBufferWordIndex = lastBufferWordIndex, updateCachedAnchor && cachedAnchorIndex != Int(Utils.UNKNOWN) {
            let lastNormalizedWord = self.noteSegments[cachedAnchorIndex + lastBufferWordIndex + 1] // We add one because we want the last buffer word to be the new index
            print("\tUpdating cached anchor...")
            
            for segment in self.noteSegments {
                if segment.getUID() == lastNormalizedWord.getUID() {
                    // update cached anchor
                    print("\tUpdating cached anchor in selection: ", segment.getText())
                    self.selectionCursor.setCachedAnchor(segment: segment)
                }
            }
        }

        if let oldAnchor = oldAnchor, oldAnchor.getIndex() == Int(Utils.UNKNOWN) {
            print("\tUpdating anchor...")
            for segment in self.noteSegments {
                if segment.getUID() == oldAnchor.getUID() {
                    // update anchor
                    print("\tUpdated anchor segment in selection cursor: ", segment.getText())
                    self.selectionCursor.setAnchor(segment: segment)
                }
            }
        }
        
        if let oldFocus = oldFocus, oldFocus.getIndex() == Int(Utils.UNKNOWN) {
            print("\tUpdating focus...")
            for segment in self.noteSegments {
                if segment.getUID() == oldFocus.getUID() {
                    // update focus
                    print("\tUpdated focus segment in selection cursor: ", segment.getText())
                    self.selectionCursor.setAnchor(segment: segment)
                }
            }
        }
        
        // Set range of last buffer
        print("\tSet last buffer range in note properties...")
        let numNormalizedBufferSegments = self.noteSegments.count - (numSegmentsBehindCursorBeforeInsertion + numSegmentsAheadCursorBeforeInsertion)
        print("\tLast Buffer Range: ", numSegmentsBehindCursorBeforeInsertion..<(numSegmentsBehindCursorBeforeInsertion + numNormalizedBufferSegments))
        self.committedBufferRanges.append(numSegmentsBehindCursorBeforeInsertion..<(numSegmentsBehindCursorBeforeInsertion + numNormalizedBufferSegments))
    }
    
    func clearBuffer() {
        print("===== Note: Clear Buffer =====")
        self.noteBuffer = []
    }
    
    func handleSave() {
        print("===== Note: Handle Save =====")
        
        if let speechRecognition = self.speechRecognition, speechRecognition.isListeningForSpeech {
            print("\tHandle intermediate saving...")
            self.state.save()
        }
    }
    
    func handleFinish(normalize: Bool = false) {
        print("===== Note: Handle Finish =====")
        print("\tHandle final saving...")
        // Completion of speech recognition section
        if soundEngine.isProcessing {
            print("\tSound Engine playing 'Processing Sound'. Turning off..")
            soundEngine.stopProcessing()
        }
        
        let onFinishHandler: (() -> Void) = { [weak self] in
            // We previously had these in stopListeningForSpeech, but clearing these
            // to soon affects normalization, which rquires recordStartDate to date PitchDatum and SoundIntensityDatum
            self?.accumulatedDuration = TimeInterval(0)
            self?.recordStartDate = nil
            self?.clearBuffer()
            self?.selectionCursor.setAnchor()
            self?.selectionCursor.setFocus()
            self?.selectionCursor.setCachedAnchor()
            self?.state.save()
            
            // Feedback
            self?.notifications.executeFeedback(
                visualMessage: "Saved!",
                audioMessage: "note saved",
                withHaptics: true,
                delay: 1.0
            )

            self!.speechRecognition.startListeningForVoiceCommands() { [weak self] in
                print("Final Note Segments: ", self!.noteSegments)
                print("Final Note Transformations: ", self!.transformations)
                NotificationCenter.default.post(
                    name: Note.onNoteComplete,
                    object: nil,
                    userInfo: [ "text": self!.getText()]
                )
            }
        }
        
        NotificationCenter.default.post(
            name: Note.onNoteListenStop,
            object: nil,
            userInfo: [ "text": self.getText()]
        )
        
        if self.noteBuffer.count > 0 {
            print("\tNote buffer has uncommitted segments. Trash them.")
            print("\tClearing note buffer...")
            self.clearBuffer()
            if normalize {
                print("\tNormalizing \(self.noteSegments.count) segments before saving note.")
                let _ = self.normalizeSegments(
                    normalizeType: .target,
                    saveSegments: true,
                    saveToLowLevelRepr: true
                )
            }
            onFinishHandler()
        } else if self.noteSegments.count > 0 {
            // No need to normalize segments or export note if we haven't captured anything meaningful
            if normalize {
                print("\tNormalizing \(self.noteSegments.count) segments before saving note.")
                let _ = self.normalizeSegments(
                    normalizeType: .target,
                    saveSegments: true,
                    saveToLowLevelRepr: true
                )
            }
            onFinishHandler()
        } else {
            onFinishHandler()
        }
    }
    
    // MARK: - Listening Method Helpers
    
    func computeSegmentTags(transcription: SFTranscription, transcriptionIndex: Int) -> ([String : NLTag?], [ScaleUnitType: Float]) {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .tokenType, .sentimentScore, .lemma])
        let segmentText = transcription.segments[transcriptionIndex].substring

        // Determine note string
        var wholeText: String
        if let cachedAnchor = self.selectionCursor.cachedAnchor {
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
        if let anchor = self.selectionCursor.anchor, anchor.getIndex() != Int(Utils.UNKNOWN) {
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
        
        if let selectionCursor = self.selectionCursor, let cachedAnchor = selectionCursor.cachedAnchor, noteSegments == nil && cachedAnchor.getIndex() != Int(Utils.UNKNOWN) {
            noteSegments = self.noteSegments
            
            // insert buffer at the correct place based on cursor position
            if !self.selectionCursor.isUpdatingSelection {
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
            if let selectionCursor = self.selectionCursor, !selectionCursor.isUpdatingSelection {
                // We don't want to factor buffer which has speech that has yet to be accepted
                // Would show up in seleectionCursor.selectionText
                
                noteSegments = self.noteSegments + self.noteBuffer
            }
        }
        
        if let noteSegments = noteSegments {
            // We have been given a specific set of segments to compute on vs. multi segment tracks
            var fromTimeSegmentIndex: Int?
            var isSingleSegment = false
    //        print("segments: ", noteSegments!)
            for (index, segment) in noteSegments.enumerated()  {
                if let untilTime = untilTime, fromTimeSegmentIndex != nil && segment.timeMapping.target.end > untilTime {
                    // We've seen all the segments we need to compute text
                    break
                } else if let _ = self.state, let untilTime = untilTime, fromTimeSegmentIndex != nil && segment.timeMapping.target.end <= untilTime && !segment.isVoiceCommandWord() && !segment.isDeleted() {
                    let word = segment.getText(
                        withTemporalSuggestions: self.state.withTemporalSuggestions,
                        withPunctuationSuggestions: self.state.withPunctuationSuggestions,
                        withFormattingSuggestions: self.state.withFormattingSuggestions,
                        strictlyAsWord: self.state.withTextStrictlyAsWords,
                        withCapitalization: self.state.withCapitalization,
                        withSpacePrefix: true,
                        forEcho: forEcho
                    )
                    
                    text += word
                } else if (segment.timeMapping.target.start >= fromTime || fromTimeSegmentIndex != nil) && !isSingleSegment && !segment.isVoiceCommandWord() && !segment.isDeleted() {
                    if fromTimeSegmentIndex == nil && segment.timeMapping.target.start >= fromTime  {
                        fromTimeSegmentIndex = index
                        isSingleSegment = segment.timeMapping.target.start == fromTime && segment.timeMapping.target.end == untilTime
                    }

                    if let _ = self.state, fromTimeSegmentIndex != nil {
                        let word = segment.getText(
                            withTemporalSuggestions: self.state.withTemporalSuggestions,
                            withPunctuationSuggestions: self.state.withPunctuationSuggestions,
                            withFormattingSuggestions: self.state.withFormattingSuggestions,
                            strictlyAsWord: self.state.withTextStrictlyAsWords,
                            withCapitalization: self.state.withCapitalization,
                            withSpacePrefix: true,
                            forEcho: forEcho
                        )
                        
                        text += word
                    }
                }
            }
        }
        
        // Remove whitespaces on edges
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // make sure first letter is capitalized
        // not capitalized when we're dealing with expresssions that come from chopped up notesRange
        if let state = self.state {
            text = state.withCapitalization ? text.capitalizeFirstLetter() : text
        }
        
        // cache work
        if segments == nil && fromTime == CMTime.zero && untilTime == nil && text.count > 0 && segmentUIDSet.count > 0 {
            self.cachedText = text
            self.cachedTextArgsSet = argumentSet
            self.cachedSegmentUIDSet = segmentUIDSet
        }

        return text
    }
    
    public static func getText(
        segments: [NoteSegment],
        withTemporalSuggestions: Bool = false,
        withPunctuationSuggestions: Bool = true,
        withFormattingSuggestions: Bool = true,
        strictlyAsWord: Bool = false,
        withCapitalization: Bool = true,
        withSpacePrefix: Bool = true,
        forEcho: Bool = false
    ) -> String {
        var text = ""

        for segment in segments {
            if !segment.isVoiceCommandWord() && !segment.isDeleted() {
                let word = segment.getText(
                    withTemporalSuggestions: withTemporalSuggestions,
                    withPunctuationSuggestions: withPunctuationSuggestions,
                    withFormattingSuggestions: withFormattingSuggestions,
                    strictlyAsWord: strictlyAsWord,
                    withCapitalization: withCapitalization,
                    withSpacePrefix: withSpacePrefix,
                    forEcho: forEcho
                )
                
                text += word
            }
        }
        
        // Remove whitespaces on edges
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // make sure first letter is capitalized
        // not capitalized when we're dealing with expresssions that come from chopped up notesRange
        text = withCapitalization ? text.capitalizeFirstLetter() : text

        return text
    }
    
    // MARK: - Player Methods

    func playSentence(
        number: Int,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Note: Play Sentence: \(number) =====")
        
        // Get sentence details
        let sentenceDetails = self.getSentenceDetails(number: number)
        
        self.speechPlayer.play(
            note: self,
            from: sentenceDetails!.timeRange.start,
            to: sentenceDetails!.timeRange.end,
            onFinishHandler: onFinishHandler
        )
    }

    func playSentence(
        forTrackTime: CMTime,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Note: Play Sentence at: \(forTrackTime.seconds) =====")

        // Get sentence details
        let sentenceDetails = self.getSentenceDetails(forTrackTime: forTrackTime)
        
        self.speechPlayer.play(
            note: self,
            from: sentenceDetails!.timeRange.start,
            to: sentenceDetails!.timeRange.end,
            onFinishHandler: onFinishHandler
        )
    }
    
    func replayCurrentSentence(handler: (() -> Void)? = nil) {
        
        // Play Sound
        soundEngine.repeatSegment()

        // Get current time
        let currentTime = self.speechPlayer.getCurrentTime()
        
        // Get sentence details
        let sentenceDetails = getSentenceDetails(forTrackTime: currentTime)
        
        if let sentenceDetails = sentenceDetails {
            self.playSentence(
                number: sentenceDetails.number,
                onFinishHandler: handler
            )
        } else {
            print("\t[Error] There was a problem replaying current sentence")
        }
    }
    
    // MARK: - Echo Methods
    // Computer understanding of the note
    
    
    func echoSentence(
        forTrackTime: CMTime,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Note: Echo Sentence at: \(forTrackTime.seconds) =====")

        // Get text
        let sentenceDetails = self.getSentenceDetails(forTrackTime: forTrackTime)
        
        if let sentenceDetails = sentenceDetails {
            self.speechSynthesis.startEcho(
                segments: Array(self.noteSegments[sentenceDetails.noteRange]),
                onFinishHandler: onFinishHandler
            )
        }
    }
    
    func echoSentence(
        number: Int,
        onFinishHandler: (() -> Void)? = nil
    ) {
        print("===== Note: Echo Sentence: \(number) =====")
        
        let sentenceDetails = self.getSentenceDetails(number: number)
        
        if let sentenceDetails = sentenceDetails {
            self.speechSynthesis.startEcho(
                segments: Array(self.noteSegments[sentenceDetails.noteRange]),
                onFinishHandler: onFinishHandler
            )
        }
    }
    
    // MARK: - Mutating Methods
    
    // TRACKS MUST BE COLLAPSED INTO SINGLE TRACK TO USE THIS
    func trim(keeping: CMTimeRange, permanent: Bool = false, overwrite: Bool = false, onFinishHandler: (() -> Void)? = nil) {
        let keepRange = keeping
        print("===== Note: Trim =====")
        print("\tKeeping section starting: \(keepRange.start.seconds) until: \(keepRange.end.seconds)")
        if self.noteBuffer.count > 0 {
            print("===== There was a problem trimming note. Note buffer was not committed =====")
            return
        }
        
        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: "Trim Note",
            audioMessage: "trimming note",
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
                let datum = self.speechRecognition.getRecordingSoundIntensityDatum(timestamp: segment.timeMapping.target.start.seconds)
                segment.setBackgroundNoise(noise: datum.power.rounded(toPlaces: Utils.SOUND_INTENSITY_SIG_FIG_COUNT))

                // Set avgPauseDuration
                segment.setAvgPauseDuration(duration: avgPauseDuration)

                // Set speakingRate
                segment.setSpeakingRate(rate: speakingRate)
                
                // determine if we need to update selection cursor anchor
                // we need to get these values early before we replace segments
                // so that selection cursor doesn't lose reference to its anchor
                if let _ = self.selectionCursor.anchor, segment.getUID() == self.selectionCursor.anchor!.getUID() && !segment.isDeleted() {
                    replaceSelectionAnchor = true
                }
                
                // determine if we need to update selection cursor focus
                // we need to get these values early before we replace segments
                // so that selection cursor doesn't lose reference to its focus
                if let _ = self.selectionCursor.focus, segment.getUID() == self.selectionCursor.focus!.getUID() && !segment.isDeleted() {
                    replaceSelectionFocus = true
                }
                
                // determine if we need to update selection cursor cached anchor
                // we need to get these values early before we replace segments
                // so that selection cursor doesn't lose reference to its cached anchor
                if let _ = self.selectionCursor.cachedAnchor, segment.getUID() == self.selectionCursor.cachedAnchor!.getUID() && !segment.isDeleted() {
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
                state: self.state,
                note: self,
                filename: self.filename,
                fileType: self.fileType,
                timeRange: keepRange
            ) { noteURL in
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
                        if replaceSelectionAnchor && seg.getUID() == self.selectionCursor.anchor!.getUID() {
                            self.selectionCursor.setAnchor(segment: seg)
                        }
                        
                        // update selection focus
                        if replaceSelectionFocus && seg.getUID() == self.selectionCursor.focus!.getUID() {
                            self.selectionCursor.setFocus(segment: seg)
                        }
                        
                        // update selection cached anchor
                        if replaceSelectionCachedAnchor && seg.getUID() == self.selectionCursor.cachedAnchor!.getUID() {
                            self.selectionCursor.setCachedAnchor(segment: seg)
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
                if replaceSelectionAnchor && seg.getUID() == self.selectionCursor.anchor!.getUID() {
                    self.selectionCursor.setAnchor(segment: seg)
                }
                
                // update selection focus
                if replaceSelectionFocus && seg.getUID() == self.selectionCursor.focus!.getUID() {
                    self.selectionCursor.setFocus(segment: seg)
                }
                
                // update selection cached anchor
                if replaceSelectionCachedAnchor && seg.getUID() == self.selectionCursor.cachedAnchor!.getUID() {
                    self.selectionCursor.setCachedAnchor(segment: seg)
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
        print("===== Note: Update Segment Sentences =====")
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
                        withTemporalSuggestions: self.state?.withTemporalSuggestions ?? Utils.DEFAULT_WITH_TEMPORAL_SUGGESTIONS,
                        withPunctuationSuggestions: self.state?.withPunctuationSuggestions ?? Utils.DEFAULT_WITH_PUNCTUATION_SUGGESTIONS,
                        withFormattingSuggestions: self.state?.withFormattingSuggestions ?? Utils.DEFAULT_WITH_FORMATTING_SUGGESTIONS,
                        strictlyAsWord: self.state?.withTextStrictlyAsWords ?? Utils.DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS,
                        withCapitalization: self.state?.withCapitalization ?? Utils.DEFAULT_WITH_CAPITALIZATION,
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
                    withTemporalSuggestions: self.state?.withTemporalSuggestions ?? Utils.DEFAULT_WITH_TEMPORAL_SUGGESTIONS,
                    withPunctuationSuggestions: self.state?.withPunctuationSuggestions ?? Utils.DEFAULT_WITH_PUNCTUATION_SUGGESTIONS,
                    withFormattingSuggestions: self.state?.withFormattingSuggestions ?? Utils.DEFAULT_WITH_FORMATTING_SUGGESTIONS,
                    strictlyAsWord: self.state?.withTextStrictlyAsWords ?? Utils.DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS,
                    withCapitalization: self.state?.withCapitalization ?? Utils.DEFAULT_WITH_CAPITALIZATION,
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
                    withTemporalSuggestions: self.state?.withTemporalSuggestions ?? Utils.DEFAULT_WITH_TEMPORAL_SUGGESTIONS,
                    withPunctuationSuggestions: self.state?.withPunctuationSuggestions ?? Utils.DEFAULT_WITH_PUNCTUATION_SUGGESTIONS,
                    withFormattingSuggestions: self.state?.withFormattingSuggestions ?? Utils.DEFAULT_WITH_FORMATTING_SUGGESTIONS,
                    strictlyAsWord: self.state?.withTextStrictlyAsWords ?? Utils.DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS,
                    withCapitalization: self.state?.withCapitalization ?? Utils.DEFAULT_WITH_CAPITALIZATION,
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
        print("===== Note: Insert Passage =====")
//        guard self.noteBuffer.count == 0 else {
//            print("\t[Error] There was a problem inserting passage. Buffer was not empty")
//            return
//        }
        print("\tMerging argument segments into committed segments...")
        var updatedSegments = [NoteSegment]()
        var insertedSegments = false
        
        // Add to state clips
        for segment in segments {
            // Handle segment clips
            self.state.setClip(clipUID: segment.getClipUID(), noteUID: self.uid)
        }
        
        if self.noteSegments.count > 0 {
            print("\tPlace within existing \(self.noteSegments.count) segments...")
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
            print("\tInserted segments are the first in note.")
            // we do not have segments yet
            // set passage as new segments
            updatedSegments = segments
        }
        
        //
        
        print("\tCleansing segments...")
        let cleansedSegments = Utils.cleanseSegments(
            segments: updatedSegments
        )

        print("\tNormalizing segments...")
        let _ = self.normalizeSegments(
            segments: cleansedSegments,
            normalizeType: .target,
            replaceNoteDetails: true,
            saveSegments: true,
            saveToLowLevelRepr: true
        )

        if !self.selectionCursor.isUpdatingSelection {
            self.handleOnSpeechUpdate(text: self.getText())
        }
        
        print("\tSuccessfully inserted passage into note!")
    }
    
    // time must be at a segment boundary to make everything work correctly
    // assumes buffer is empty
    func removePassage(range: CMTimeRange) {
        print("===== Note: Remove Passage =====")
//        guard self.noteBuffer.count == 0 else {
//            print("\t[Error] There was a problem removing passage. Buffer was not empty")
//            return
//        }
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
                if let _ = self.selectionCursor.anchor, segment.getUID() == self.selectionCursor.anchor!.getUID() {
                    print("\tSelection cursor anchor requires updating...")
                    updateAnchor = true
                    // Clear anchor so we get no errors related to selectionRange
                    // When we update anchor when we have a selection, focus will be outdate and cause error
                    self.selectionCursor.setAnchor()
                }
                
                // Check if we need to update selection focus
                if let _ = self.selectionCursor.focus, segment.getUID() == self.selectionCursor.focus!.getUID() {
                    print("\tSelection cursor focus requires updating...")
                    updateFocus = true
                    // Clear focus so we get no errors related to selectionRange
                    // When we update focus when we have a selection, anchor will be outdate and cause error
                    self.selectionCursor.setFocus()
                }
                
                // Check if we need to update selection cached anchor
                if let _ = self.selectionCursor.cachedAnchor, segment.getUID() == self.selectionCursor.cachedAnchor!.getUID() {
                    print("\tSelection cursor cached anchor requires updating...")
                    updateCachedAnchor = true
                    // Clear cached anchor
                    self.selectionCursor.setCachedAnchor()
                }
            }
        }
        
        print("\tCleansing segments...")
        let cleansedSegments = Utils.cleanseSegments(
            segments: updatedSegments
        )

        print("\tNormalizing segments...")
        let _ = self.normalizeSegments(
            segments: cleansedSegments,
            normalizeType: .target,
            replaceNoteDetails: true,
            saveSegments: true,
            saveToLowLevelRepr: true
        )
        
        var segment: NoteSegment?
        if updateAnchor || updateFocus || updateCachedAnchor {
            print("\tSearching for replacement segment...")
            segment = self.speechPlayer.getSegment(
                forTrackTime: CMTimeMake(
                    value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (max(0, beforeTime.seconds - Utils.TEMPORAL_DELTA))),
                    timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                )
            )
            
            while segment != nil && segment!.timeMapping.target.start > CMTime.zero && (segment!.isVoiceCommandWord() || segment!.isDeleted() || segment!.isSilence()) {
                let startTime = segment!.timeMapping.target.start
                segment = self.speechPlayer.getSegment(
                    forTrackTime: CMTimeMake(
                        value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (max(0, startTime.seconds - Utils.TEMPORAL_DELTA))),
                        timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                    )
                )
            }
        }
        
        if let segment = segment, updateAnchor && segment.isActive() {
            print("\tUpdating selection cursor anchor..")
            self.selectionCursor.setAnchor(segment: segment)
        }
        
        if let segment = segment, updateFocus && segment.isActive() {
            print("\tUpdating selection cursor focus...")
            self.selectionCursor.setFocus(segment: segment)
        }
        
        if let segment = segment, updateCachedAnchor && segment.isActive() {
            print("\tUpdating selection cursor cached anchor...")
            self.selectionCursor.setCachedAnchor(segment: segment)
        }
        
        // we don't change text view in this mode, so text won't be available
        if !self.selectionCursor.isUpdatingSelection {
            self.handleOnSpeechUpdate(text: self.getText())
        }

        print("\tSuccessfully removed passage from note!")
    }
    
    func updatePassage(segments: [NoteSegment], range: CMTimeRange) {
        print("===== Note: Update Passage =====")
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
        print("===== Note: Handle Transformation =====")
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
            self.notifications.executeFeedback(
                visualMessage: "Selection rate: \(value)x",
                audioMessage: "Adjusted selection rate to \(value)x.",
                withHaptics: true
            )
        }
        
        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    func walk(segments: [NoteSegment]? = nil, runOverride: Bool = false, onStartHandler: (() -> Void)? = nil) {
        print("===== Note: \(runOverride ? "Run" : "Walk") =====")
        if (self.noteManager.isWalkingNote && !self.noteManager.pausedWalkingNote && !runOverride) || (segments != nil && segments!.count == 0) || (segments == nil && self.noteSegments.count == 0) {
            var text: String
            if self.noteManager.isWalkingNote && !self.noteManager.pausedWalkingNote && !runOverride {
                text = "Already walking passage."
            } else {
                text = "Note is empty"
            }
            
            self.notifications.executeError(
                text: text
            )
            
            return
        }
        
        // Get walking segments
        // if they are already set, it means we're starting from an existing walk
        // we likely have gone from walking to running
        if let segments = segments, let firstSegment = segments.first, let lastSegment = segments.last, self.noteManager.walkingRange == nil {
            // Set walking range
            self.noteManager.setWalkingRange(range: firstSegment.getIndex()..<lastSegment.getIndex() + 1)
            
            // Set walking index
            self.noteManager.setWalkingIndex(index: 0)
        } else if self.noteManager.walkingRange == nil {
            // Set walking range
            self.noteManager.setWalkingRange(range: 0..<self.noteSegments.count)
            
            // Set walking index
            self.noteManager.setWalkingIndex(index: 0)
        } else if let anchor = self.selectionCursor.anchor, let walkingRange = self.noteManager.walkingRange, self.noteManager.pausedWalkingNote || self.noteManager.pausedRunningNote {
            // We likely just updated walk segment
            // We must handle new index placement
            // We must handle segment expanding to multiple words
            // Decision: We keep selection on the first segment only
            self.noteManager.setWalkingIndex(index: anchor.getIndex() - self.noteSegments[walkingRange].first!.getIndex())
        }
        
        guard let walkingRange = self.noteManager.walkingRange else {
            self.noteManager.setWalkingIndex(index: 0)
            self.noteManager.setWalkingRange()
            self.notifications.executeError(
                text: "Unable to start \(runOverride ? "running" : "walking").",
                handler: onStartHandler
            )
            return
        }
        
        var currentSegment: NoteSegment? = Array(self.noteSegments[walkingRange])[self.noteManager.walkingIndex]
        if let segment = currentSegment, let walkingRange = self.noteManager.walkingRange, !segment.isActive() {
            currentSegment = self.speechPlayer.getSegment(segment: segment, segments: Array(self.noteSegments[walkingRange]), type: .next, isWord: true)
        }
        
        if let currentSegment = currentSegment {
            // Updating walking index
            self.noteManager.setWalkingIndex(index: currentSegment.getIndex() - Array(self.noteSegments[walkingRange]).first!.getIndex())

            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "\(runOverride ? "Run" : "Walk") activated!",
                withHaptics: true
            )
            
            // Activate isWalkingNote if we don't have a run override
            self.noteManager.setIsWalkingNote(to: !runOverride)
            self.noteManager.setPausedWalkingNote(to: false)
            self.noteManager.setPausedRunningNote(to: false)
            
            self.selectionCursor.setSelection(anchor: currentSegment, focus: currentSegment)
            
            // start looping walk
            if AVAudioSession.isHeadphonesConnected {
                let makeStep = {
                    self.speechPlayer.play(segments: [currentSegment])
                    
                    // Play echo
                    let echoDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_ECHO_DELAY_DURATION * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: false) { [weak self] timer in
                        self?.speechSynthesis.startEcho(segments: [currentSegment])
                    }
                    
                    self.noteManager.setEchoDelayTimer(timer: echoDelayTimer)
                }
                
                let walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let segmentDuration: TimeInterval = currentSegment.timeMapping.target.duration.seconds
                    let stepDuration: TimeInterval = max(segmentDuration + (segmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + segmentDuration + Utils.WALKING_LOOP_BUFFER)
                    let walkingTimer = Timer.scheduledTimer(withTimeInterval: max(stepDuration, Utils.WALKING_PERIOD_DURATION) * TimeInterval( 1 / self!.speechPlayer.playbackRate), repeats: true) { timer in
                        makeStep()
                    }
                    
                    self?.noteManager.setWalkingTimer(timer: walkingTimer)
                }
                
                self.noteManager.setWalkLoopDelayTimer(timer: walkLoopDelayTimer)
            }
            
            // execute start handler
            onStartHandler?()
        } else {
            self.exitWalk()
            self.notifications.executeError(
                text: "Unable to start \(runOverride ? "running" : "walking").",
                handler: onStartHandler
            )
        }
    }
    
    func walkToPreviousSegment(runOverride: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note: \(runOverride ? "Run" : "Walk") To Previous Segment =====")
        if !self.noteManager.isWalkingNote && !self.noteManager.isRunningNote {
            var text: String
            text = "\(runOverride ? "Running" : "Walking") not active."
            self.notifications.executeError(
                text: text
            )
            return
        }
        
        guard let walkingRange = self.noteManager.walkingRange else {
            self.notifications.executeError(
                text: "Unable to \(runOverride ? "run to" : "walk to") previous.",
                handler: handler
            )
            self.exitWalk()
            return
        }
        
        var currentSegment: NoteSegment? = Array(self.noteSegments[walkingRange])[self.noteManager.walkingIndex]
        if let segment = currentSegment, let walkingRange = self.noteManager.walkingRange {
            currentSegment = self.speechPlayer.getSegment(segment: segment, segments: Array(self.noteSegments[walkingRange]), type: .previous, isWord: true)
        }
        
        if let currentSegment = currentSegment, self.noteManager.walkingIndex != (currentSegment.getIndex() - Array(self.noteSegments[walkingRange]).first!.getIndex()) {
            
            // Updating walking index
            self.noteManager.setWalkingIndex(index: currentSegment.getIndex() - Array(self.noteSegments[walkingRange]).first!.getIndex())

            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Previous word",
                withHaptics: true
            )
            
            // Stop previous walking loop
            self.noteManager.setWalkingTimer()
            
            // Stop previous walking loop delay
            self.noteManager.setWalkLoopDelayTimer()

            // Stop previous echo delay
            self.noteManager.setEchoDelayTimer()
            
            // Stop playback
            if self.speechPlayer.isPlayingNote {
                self.speechPlayer.stop(withFeedback: false)
            }
            // Stop echo
            if self.speechSynthesis.isPlayingEcho {
                self.speechSynthesis.stopEcho(withFeedback: false)
            }
            
            self.selectionCursor.setSelection(anchor: currentSegment, focus: currentSegment)
            
            // start looping walk
            if AVAudioSession.isHeadphonesConnected {// play speech
                let makeStep = {
                    self.speechPlayer.play(segments: [currentSegment])
                    
                    // Play echo
                    let echoDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_ECHO_DELAY_DURATION * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: false) { [weak self] timer in
                        self?.speechSynthesis.startEcho(segments: [currentSegment])
                    }
                    
                    self.noteManager.setEchoDelayTimer(timer: echoDelayTimer)
                }
                
                let walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let segmentDuration: TimeInterval = currentSegment.timeMapping.target.duration.seconds
                    let stepDuration: TimeInterval = max(segmentDuration + (segmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + segmentDuration + Utils.WALKING_LOOP_BUFFER)
                    let walkingTimer = Timer.scheduledTimer(withTimeInterval: max(stepDuration, Utils.WALKING_PERIOD_DURATION) * TimeInterval( 1 / self!.speechPlayer.playbackRate), repeats: true) { timer in
                        makeStep()
                    }
                    
                    self?.noteManager.setWalkingTimer(timer: walkingTimer)
                }
                
                self.noteManager.setWalkLoopDelayTimer(timer: walkLoopDelayTimer)
            }

            // execute handler
            handler?()
        } else {
            self.notifications.executeError(
                text: "At beginning of \(runOverride ? "running" : "walking") passage.",
                handler: handler
            )
        }
    }
    
    func walkToNextSegment(runOverride: Bool = false, handler: (() -> Void)? = nil) {
        print("===== Note: \(runOverride ? "Run" : "Walk") To Next Segment =====")
        if !self.noteManager.isWalkingNote && !self.noteManager.isRunningNote {
            var text: String
            text = "\(runOverride ? "Running" : "Walking") not active."
            self.notifications.executeError(
                text: text
            )
            return
        }
        
        guard let walkingRange = self.noteManager.walkingRange else {
            self.notifications.executeError(
                text: "Unable to \(runOverride ? "run to" : "walk to") next.",
                handler: handler
            )
            self.exitWalk()
            return
        }
        
        var currentSegment: NoteSegment? = Array(self.noteSegments[walkingRange])[self.noteManager.walkingIndex]
        if let segment = currentSegment, let walkingRange = self.noteManager.walkingRange {
            currentSegment = self.speechPlayer.getSegment(segment: segment, segments: Array(self.noteSegments[walkingRange]), type: .next, isWord: true)
        }

        if let currentSegment = currentSegment, self.noteManager.walkingIndex != (currentSegment.getIndex() - Array(self.noteSegments[walkingRange]).first!.getIndex()) {
            // Updating walking index
            self.noteManager.setWalkingIndex(index: currentSegment.getIndex() - Array(self.noteSegments[walkingRange]).first!.getIndex())

            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Next word",
                withHaptics: true
            )
            
            // Stop previous walking loop
            self.noteManager.setWalkingTimer()
            
            // Stop previous walking loop delay
            self.noteManager.setWalkLoopDelayTimer()

            // Stop previous echo delay
            self.noteManager.setEchoDelayTimer()

            // Stop playback
            if self.speechPlayer.isPlayingNote {
                self.speechPlayer.stop(withFeedback: false)
            }
            // Stop echo
            if self.speechSynthesis.isPlayingEcho {
                self.speechSynthesis.stopEcho(withFeedback: false)
            }
            
            self.selectionCursor.setSelection(anchor: currentSegment, focus: currentSegment)
            
            // start looping walk
            if AVAudioSession.isHeadphonesConnected {
                let makeStep = {
                    self.speechPlayer.play(segments: [currentSegment])
                    
                    // Play echo
                    let echoDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_ECHO_DELAY_DURATION * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: false) { [weak self] timer in
                        self?.speechSynthesis.startEcho(segments: [currentSegment])
                    }
                    
                    self.noteManager.setEchoDelayTimer(timer: echoDelayTimer)
                }
                
                let walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let segmentDuration: TimeInterval = currentSegment.timeMapping.target.duration.seconds
                    let stepDuration: TimeInterval = max(segmentDuration + (segmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + segmentDuration + Utils.WALKING_LOOP_BUFFER)
                    let walkingTimer = Timer.scheduledTimer(withTimeInterval: max(stepDuration, Utils.WALKING_PERIOD_DURATION) * TimeInterval( 1 / self!.speechPlayer.playbackRate), repeats: true) { timer in
                        makeStep()
                    }
                    
                    self?.noteManager.setWalkingTimer(timer: walkingTimer)
                }
                
                self.noteManager.setWalkLoopDelayTimer(timer: walkLoopDelayTimer)
            }
            
            // execute handler
            handler?()
        } else if self.noteManager.isRunningNote {
            self.exitWalk(clearSelection: false)
        } else {
            self.notifications.executeError(
                text: "At end of \(runOverride ? "running" : "walking") passage.",
                handler: handler
            )
        }
    }
    
    func run(segments: [NoteSegment]? = nil, onStartHandler: (() -> Void)? = nil) {
        if self.noteManager.isRunningNote && !self.noteManager.pausedRunningNote {
            self.notifications.executeError(
                text: "Already running passage."
            )
            return
        }
        
        self.noteManager.setIsRunningNote(to: true)
        
        // Start walk
        self.walk(segments: segments, runOverride: true, onStartHandler: onStartHandler)
        
        let avgSegmentDuration: TimeInterval = 0.5
        let runInterval: TimeInterval = max(avgSegmentDuration + (avgSegmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + avgSegmentDuration + Utils.WALKING_LOOP_BUFFER)
        // start automated walking
        let runningTimer = Timer.scheduledTimer(withTimeInterval: runInterval + Utils.WALKING_START_DELAY_DURATION, repeats: true) { [weak self] timer in
            if self!.noteManager.walkingIndex + 1 < Array(self!.noteSegments[self!.noteManager.walkingRange!]).count {
                self?.walkToNextSegment(runOverride: true)
            } else {
                self?.pauseRun()
            }
        }
        
        self.noteManager.setRunningTimer(timer: runningTimer)
    }
    
    func pauseRun(handler: (() -> Void)? = nil) {
        print("===== Note: Pause Run =====")
        if !self.noteManager.isRunningNote {
            self.notifications.executeError(
                text: "Not running passage."
            )
            return
        }
        
        if self.noteManager.runningTimer == nil {
            self.notifications.executeError(
                text: "Error pausing run."
            )
            return
        }
        
        // Stop running timer
        self.noteManager.setRunningTimer()
        
        // Stop previous walking loop
        self.noteManager.setWalkingTimer()
        
        // Stop previous walking loop delay
        self.noteManager.setWalkLoopDelayTimer()

        // Stop previous echo delay
        self.noteManager.setEchoDelayTimer()
        
        // Stop playback
        if self.speechPlayer.isPlayingNote {
            self.speechPlayer.stop(withFeedback: false)
        }

        // Stop echo
        if self.speechSynthesis.isPlayingEcho {
            self.speechSynthesis.stopEcho(withFeedback: false)
        }
        
        // Turn off running note
        self.noteManager.setIsRunningNote(to: false)
        
        guard let walkingRange = self.noteManager.walkingRange else {
            self.notifications.executeError(
                text: "Unable to pause run.",
                handler: handler
            )
            self.exitWalk()
            return
        }
        
        // Convert to walking note
        self.walk(segments: Array(self.noteSegments[walkingRange]), onStartHandler: handler)
        
        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: "Run Paused!",
            audioMessage: "Run paused to walk",
            withHaptics: true
        )
    }
    
    func exitWalk(pause: Bool = false, clearSelection: Bool = true, withFeedback: Bool = true, handler: (() -> Void)? = nil) {
        if self.noteManager.isRunningNote {
            print("===== Note: Exit Run =====")
        } else {
            print("===== Note: Exit Walk =====")
        }

        if !self.noteManager.isWalkingNote && !self.noteManager.isRunningNote {
            self.notifications.executeError(
                text: "Not walking or running passage."
            )
            return
        }
        
        if !pause {
            self.noteManager.setWalkingIndex(index: 0)
            self.noteManager.setWalkingRange()
        }
        
        // Stop current playback
        if self.speechPlayer.isPlayingExternalSegments || self.speechPlayer.isPlayingNote {
            self.speechPlayer.stop(withFeedback: false)
        }
        
        // Stop currrent echo
        if self.speechSynthesis.isPlayingEcho || self.speechSynthesis.isPlayingPassiveEcho {
            self.speechSynthesis.stopEcho(withFeedback: false)
        }
        
        // Stop running timer
        self.noteManager.setRunningTimer()
        
        // Stop previous walking loop
        self.noteManager.setWalkingTimer()
        
        // Stop previous walking loop delay
        self.noteManager.setWalkLoopDelayTimer()
        
        // Stop previous echo delay
        self.noteManager.setEchoDelayTimer()
        
        let handleExitWalk = {
            var visualMessage: String?
            var audioMessage: String?
            if withFeedback {
                if self.noteManager.isRunningNote {
                    visualMessage = "Exit Run"
                    audioMessage = "run exited."
                } else {
                    visualMessage = "Exit Walk"
                    audioMessage = "walk exited."
                }
            }
            
            if pause && self.noteManager.isRunningNote {
                self.noteManager.setPausedRunningNote(to: true)
            } else if pause && self.noteManager.isWalkingNote {
                self.noteManager.setPausedWalkingNote(to: true)
            } else {
                self.noteManager.setIsWalkingNote(to: false)
                self.noteManager.setIsRunningNote(to: false)
                self.noteManager.setPausedRunningNote(to: false)
                self.noteManager.setPausedWalkingNote(to: false)
            }
            
            if clearSelection {
                // We only clear the focus so that the cursor remains at given location
                self.selectionCursor.setFocus()
                if !self.selectionCursor.isAtEndOfTextView {
                    // We cache the anchor if we're mid-note so that new content is added from given location
                    self.selectionCursor.setCachedAnchor(segment: self.selectionCursor.anchor)
                }
            } else if let _ = self.selectionCursor.anchor, let _ = self.selectionCursor.focus, !pause {
                // Initiate looping selection behavior when we end walk
                self.selectionCursor.playSelection(loop: true)
            }
            
            // Present Feedback
            if let visualMessage = visualMessage, let audioMessage = audioMessage, withFeedback {
                self.notifications.executeFeedback(
                    visualMessage: visualMessage,
                    audioMessage: audioMessage,
                    withHaptics: true
                )
            }
            
            if !clearSelection && !self.speechRecognition.isListeningForCommands {
                self.speechRecognition.startListeningForVoiceCommands() {
                    handler?()
                    // Notify observers of loading
                    NotificationCenter.default.post(
                        name: Note.onRequestToUpdateView,
                        object: nil,
                        userInfo: [:]
                    )
                }
            } else {
                handler?()
                // Notify observers of loading
                NotificationCenter.default.post(
                    name: Note.onRequestToUpdateView,
                    object: nil,
                    userInfo: [:]
                )
            }
        }
        
        // Stop playback and echo
        self.speechPlayer.stop(withFeedback: false) {
            self.speechSynthesis.stopEcho(withFeedback: false) {
                handleExitWalk()
            }
        }
    }
    
    func generateNewClip() {
        self.currentClipUID = UUID().uuidString
        self.clips.insert(self.currentClipUID!)
        print("\tAdding new clip: ", self.currentClipUID!)
        self.state.setClip(clipUID: self.currentClipUID!, noteUID: self.uid)
    }
    
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
            state: self.state,
            note: self,
            filename: duplicateFilename,
            fileType: self.fileType,
            timeRange: CMTimeRangeMake(start: CMTime.zero, duration: self.getDuration())
        ) { noteURL in
            let duplicateNote = Note(
                uid: uid,
                filename: duplicateFilename,
                fileType: .m4a,
                creatorUID: self.creatorUID,
                segments: self.noteSegments // Will copy segments so there are not multiple pointers to a single segment
            )
                
            // Set Date Created
            duplicateNote.dateCreated = self.dateCreated
            
            // Set Date Modified
            duplicateNote.dateModified = self.dateModified
            
            // Execute handler
            onFinishHandler(duplicateNote)
        }
    }
    
    // MARK: - Telemetry
    
    func incrementViewCount() {
        self.views.append(Date().timeIntervalSince1970)
    }
    
    func incrementPlayCount() {
        self.plays.append(Date().timeIntervalSince1970)
    }
    
    func incrementTextExportCount() {
        self.textExports.append(Date().timeIntervalSince1970)
    }
    
    func incrementAudioExportCount() {
        self.audioExports.append(Date().timeIntervalSince1970)
    }
    
    // MARK: - Setters
    
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
        print("===== Note: Set Segments =====")
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
            let segmentsWithUpdatedSentences = self.updateSegmentSentences(segments: finalSegments)
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
                if let selectionCursor = self.selectionCursor, let anchor = selectionCursor.anchor, segment.getUID() == anchor.getUID() {
                    print("\tUpdating selection cursor anchor...")
                    self.selectionCursor.setAnchor(segment: segment)
                }
                
                if let selectionCursor = self.selectionCursor, let focus = selectionCursor.focus, segment.getUID() == focus.getUID() {
                     print("\tUpdating selection cursor focus...")
                    self.selectionCursor.setFocus(segment: segment)
                }
                if let selectionCursor = self.selectionCursor, let cachedAnchor = selectionCursor.cachedAnchor, segment.getUID() == cachedAnchor.getUID() {
                     print("\tUpdating selection cursor cached anchor...")
                    self.selectionCursor.setCachedAnchor(segment: segment)
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
            if let _ = self.state {
                self.transformations = Utils.cleanseTransformations(
                    transformations: self.transformations,
                    segments: self.noteSegments,
                    segmentIndexMap: self.segmentIndexMap,
                    omitSilences: false,
                    omitVoiceCommands: false,
                    omitDeleted: false
                )
            }
            print("\tSuccessfully updated \(self.noteSegments.count) note segments!")
            print("\tSuccessfully updated \(self.transformations.count) note transformations!")
            
            // Save note
            // We don't run handle save when note ended. We run it at the end of on speech update
            self.handleSave()
        } catch {
            print("\t[Error] There was a problem updating note segments")
        }

        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    func setState(state: StateManager) {
        print("===== Note: Set State =====")
        self.state = state
    }
    
    func setSpeechSynthesis(speechSynthesis: SpeechSynthesisEngine) {
        print("===== Note: Set Speech Synthesis =====")
        self.speechSynthesis = speechSynthesis
    }
    
    func setSpeechRecognition(speechRecognition: SpeechRecognitionEngine) {
        print("===== Note: Set Speech Recognition =====")
        self.speechRecognition = speechRecognition
    }
    
    func setSpeechPlayer(speechPlayer: SpeechPlayerEngine) {
        print("===== Note: Set Speech Player =====")
        self.speechPlayer = speechPlayer
    }
    
    func setSelectionCursor(selectionCursor: SelectionCursor) {
        print("===== Note: Set Selection Cursor =====")
        self.selectionCursor = selectionCursor
    }
    
    func setPitchRecognition(pitchRecognition: PitchRecognitionEngine) {
        print("===== Note: Set Pitch Recognition  =====")
        self.pitchRecognition = pitchRecognition
    }
    
    func setNoteManager(noteManager: NoteManager) {
        print("===== Note: Set Note Manager =====")
        self.noteManager = noteManager
    }
    
    func setNotifications(notifications: NotificationEngine) {
        print("===== Note: Set Notifications =====")
        self.notifications = notifications
    }
    
    func setIsDeleted(to isDeleted: Bool) {
        print("===== Note: Set Is Deleted =====")
        self.isDeleted = isDeleted
    }
    
    // MARK: - Getters
    
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
        let currentTime = self.speechPlayer.getCurrentTime()
        self.extractSentence(forTrackTime: currentTime) { sentence in
            switch type {
            case .current:
                onFinishHandler(sentence)
                break
            case .previous:
                let timestamp = floor(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentTime.seconds - Utils.TEMPORAL_DELTA))
                let previousTime = CMTimeMake(
                    value: Int64(timestamp),
                    timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                )
                self.extractSentence(forTrackTime: previousTime) { sentence in
                    onFinishHandler(sentence)
                }
                break
            case .next:
                let timestamp = floor(Utils.DEFAULT_SEGMENT_TIMESCALE * (currentTime.seconds + Utils.TEMPORAL_DELTA))
                let nextTime = CMTimeMake(
                    value: Int64(timestamp),
                    timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                )
                self.extractSentence(forTrackTime: nextTime) { sentence in
                    onFinishHandler(sentence)
                }
                break
            }
        }
        
    }
    
    // We use .lowercased() throughout the method because sometimes word is made uppercase if we have PunctuationSuggestions on which will capitalize on-demand
    // To elimate this we make everything lowercase
    func getSegmentTextRange(of segment: NoteSegment) -> NSRange? {
        var characterRange : NSRange
        let word = segment.getText(
            withTemporalSuggestions: self.state.withTemporalSuggestions,
            withPunctuationSuggestions: self.state.withPunctuationSuggestions,
            withFormattingSuggestions: self.state.withFormattingSuggestions,
            strictlyAsWord: self.state.withTextStrictlyAsWords,
            withCapitalization: self.state.withCapitalization
        ).lowercased()
        let text = self.getText().lowercased()
        if word.count > 0 && segment.timeMapping.target.start.seconds == 0 && segment.isCommitted() && text.count >= word.count {
            characterRange = NSRange(location: 0, length: word.count)
        } else if word.count > 0 && text.count >= word.count {
            let numUprocessedChar = self.getText(from: segment.timeMapping.target.start).lowercased().count
            let numProcessedChar = text.count - numUprocessedChar
            let unprocessedTranscription = text.substring(fromIndex: numProcessedChar).lowercased()
            let substringRange = unprocessedTranscription.range(of: word)
            if let substringRange = substringRange {
                let numCharToSubstring = unprocessedTranscription.count - unprocessedTranscription[substringRange.lowerBound..<unprocessedTranscription.endIndex].count
                characterRange = NSRange(location: numProcessedChar + numCharToSubstring, length: word.count)
            } else {
                return nil
            }
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
        
        if self.speechRecognition.soundIntensityStream.count == 0 {
            return Double.infinity
        }
        
        let soundIntensityStream = Utils.cleanseSoundIntensityStream(soundIntensityStream: self.speechRecognition.soundIntensityStream)
        
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
            if let segmentTrackTime = segmentTrackTime, let segment = self.speechPlayer.getSegment(forTrackTime: segmentTrackTime) {
                return segment.getPower()
            }
            break
        }
        
        return Double.infinity
    }
    
    func getSentimentScore(type: ScaleUnitType = .word, sentenceNumber: Int? = nil, forTrackTime: CMTime? = nil) -> Float {
        print("===== Get Sentiment Score =====")
        if let forTrackTime = forTrackTime, let segment = self.speechPlayer.getSegment(forTrackTime: forTrackTime), let sentiment = segment.getSentimentScore(type: type) {
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
                    self.state.withOmitSilences &&
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
        var firstBufferSegment: NoteSegment?
        var lastBufferSegment: NoteSegment?
        if self.noteBuffer.count > 0 {
            // Find first buffer word
            firstBufferSegment = self.noteBuffer.first!
            if !firstBufferSegment!.isActive() {
                firstBufferSegment = self.speechPlayer.getSegment(segment: firstBufferSegment, segments: self.noteBuffer, type: .next, isWord: true)
            }
            
            // Find last buffer word
            lastBufferSegment = self.noteBuffer.last!
            if !lastBufferSegment!.isActive() {
                lastBufferSegment = self.speechPlayer.getSegment(segment: lastBufferSegment, segments: self.noteBuffer, type: .previous, isWord: true)
            }
        } else if let lastBufferRange = self.committedBufferRanges.last {
            let lastBuffer = self.noteSegments[lastBufferRange]
            // Find first buffer word
            firstBufferSegment = lastBuffer.first!
            if !firstBufferSegment!.isActive() {
                
            }
            firstBufferSegment = self.speechPlayer.getSegment(segment: firstBufferSegment, segments: Array(lastBuffer), type: .next, isWord: true)

            // Find last buffer word
            lastBufferSegment = lastBuffer.last!
            if !lastBufferSegment!.isActive() {
                lastBufferSegment = self.speechPlayer.getSegment(segment: lastBufferSegment, segments: Array(lastBuffer), type: .previous, isWord: true)
            }
        }
        
        if let firstBufferSegment = firstBufferSegment, let lastBufferSegment = lastBufferSegment, firstBufferSegment != lastBufferSegment {
            self.notifications.executeFeedback(
                visualMessage: "\"\(firstBufferSegment.getText().lowercased())...\(lastBufferSegment.getText().lowercased())\" committed!",
                withHaptics: true
            )
        } else if let firstBufferSegment = firstBufferSegment, let lastBufferSegment = lastBufferSegment, firstBufferSegment == lastBufferSegment {
            self.notifications.executeFeedback(
                visualMessage: "\"\(firstBufferSegment.getText().lowercased())\" committed!",
                withHaptics: true
            )
        } else {
            print("===== [Error] There was a problem finding the first and last words of buffer =====")
        }
        
        // Present Feedback
//        hapticEngine.lightImpact()
        self.notifications.executeFeedback(
            withHaptics: true
        )
    }
    
    func processVoiceCommandSegments(command: String, numWordsBeforeVoiceCommand: Int) {
        print("===== Note: Process Voice Command Segments =====")
        print("\tSeeking lowest voice command index...")
        
        var lastBufferRange: Range<Int>
        if self.noteBuffer.count > 0 {
            print("\tSourcing segments from note buffer because we haven't committed yet.")
            lastBufferRange = 0..<self.noteBuffer.count
        } else {
            print("\tSourcing segments from committed segments because buffer is empty.")
            lastBufferRange = self.committedBufferRanges[self.committedBufferRanges.count - 1]
        }

        var lowestCommandIndex: Int?
        var numWordsEncountered: Int = 0
        if self.noteBuffer.count > 0 {
            for i in self.noteBuffer.startIndex..<self.noteBuffer.endIndex {
                let segment = self.noteBuffer[i]
                if segment.isActive() && numWordsEncountered == numWordsBeforeVoiceCommand {
                    print("\tFound lowest voice command index: \(i) of \(self.noteBuffer.count - 1)")
                    print("\tFound in note buffer...")
                    lowestCommandIndex = i
                    break
                } else if segment.isActive() && numWordsEncountered < numWordsBeforeVoiceCommand {
                    numWordsEncountered += 1
                }
            }
        } else {
            for i in Array(self.noteSegments[lastBufferRange]).startIndex..<Array(self.noteSegments[lastBufferRange]).endIndex {
                let segment = Array(self.noteSegments[lastBufferRange])[i]
                if segment.isActive() && numWordsEncountered == numWordsBeforeVoiceCommand {
                    print("\tFound lowest voice command index: \(i) of \(Array(self.noteSegments[lastBufferRange]).count - 1)")
                    print("\tFound in note committed segments...")
                    lowestCommandIndex = i
                    break
                } else if segment.isActive() && numWordsEncountered < numWordsBeforeVoiceCommand {
                    numWordsEncountered += 1
                }
            }
        }
        
        var replaceSelectionAnchor = false
        var replaceSelectionFocus = false
        var replaceSelectionCachedAnchor = false
        if let lowestCommandIndex = lowestCommandIndex {
            print("\tFlipping every segment after lowest voice command index to be voice command word...")
            let bufferSource = self.noteBuffer.count > 0 ? self.noteBuffer : Array(self.noteSegments[lastBufferRange])
            for index in lowestCommandIndex..<bufferSource.distance(to: lastBufferRange.endIndex) {
                // duplicate segment
                let duplicateSegment = bufferSource[index].duplicate()
                
                // determine if we need to replace selection values
                replaceSelectionAnchor = replaceSelectionAnchor || duplicateSegment == self.selectionCursor.anchor && self.selectionCursor.anchor != nil
                replaceSelectionFocus = replaceSelectionFocus || duplicateSegment == self.selectionCursor.focus && self.selectionCursor.focus != nil
                replaceSelectionCachedAnchor = replaceSelectionCachedAnchor || duplicateSegment == self.selectionCursor.cachedAnchor && self.selectionCursor.cachedAnchor != nil
                
                // set duplicate segment as voice command word
                duplicateSegment.setIsVoiceCommandWord(to: true)
                print("\t'\(duplicateSegment.getText())' == Voice Command")
                
                // set duplicate segment
                if self.noteBuffer.count > 0 {
                    self.noteBuffer[index] = duplicateSegment
                } else {
                    self.noteSegments[index] = duplicateSegment
                }
                
                // update selection anchor
                if duplicateSegment == self.selectionCursor.anchor {
                    print("\tReplacing Selection Cursor Anchor with version that is not voice command word...")
                    self.selectionCursor.setAnchor(segment: duplicateSegment)
                }
                
                // update selection focus
                if duplicateSegment == self.selectionCursor.focus {
                    print("\tReplacing Selection Cursor Focus with version that is voice command word...")
                    self.selectionCursor.setFocus(segment: duplicateSegment)
                }
                
                // update selection cached anchor
                if duplicateSegment == self.selectionCursor.cachedAnchor {
                    print("\tReplacing Selection Cursor Cached Anchor with version that is voice command word...")
                    self.selectionCursor.setCachedAnchor(segment: duplicateSegment)
                }
            }
            
            if let anchor = self.selectionCursor.anchor, replaceSelectionAnchor && self.noteBuffer.count > 0 && !anchor.isCommitted() {
                print("\tReplacing anchor. We cannot have a voice command anchor.")
                print("\tSearching in note buffer...")
                var newAnchor: NoteSegment?
                let newAnchorIndex = Utils.getNoteNthLastSegmentIndex(
                    segments: Array(self.noteBuffer[0..<lowestCommandIndex]),
                    selectionCursor: self.selectionCursor,
                    n: 0
                ).1
                
                if let newAnchorIndex = newAnchorIndex {
                    newAnchor = Array(self.noteBuffer[0..<lowestCommandIndex])[newAnchorIndex]
                    print("\tFound new anchor: ", newAnchor ?? "nil")
                }
                
                if newAnchor == nil {
                    print("\tUnable to find replacement anchor in buffer. Search in committed segments...")
                    let segments = self.selectionCursor.cachedAnchor != nil ? Array(self.noteSegments[0..<self.selectionCursor.cachedAnchor!.getIndex() + 1]) : self.noteSegments // We add one because we want to include cached anchor
                    let newAnchorIndex = Utils.getNoteNthLastSegmentIndex(
                        segments: segments,
                        selectionCursor: self.selectionCursor,
                        n: 0
                    ).1
                    
                    if let newAnchorIndex = newAnchorIndex {
                        newAnchor = segments[newAnchorIndex]
                        print("\tFound new anchor: ", newAnchor ?? "nil")
                    }
                }
                
                if let newAnchor = newAnchor {
                    print("\tUpdating Selection Anchor...")
                    self.selectionCursor.setAnchor(segment: newAnchor)
                }
            } else if let _ = self.selectionCursor.anchor, replaceSelectionAnchor {
                print("\tReplacing anchor. We cannot have a voice command anchor.")
                print("\tSearching in note committed segments...")
                var newAnchor: NoteSegment?
                let segments = self.selectionCursor.cachedAnchor != nil ? Array(self.noteSegments[0..<self.selectionCursor.cachedAnchor!.getIndex() + 1]) : self.noteSegments // We add one because we want to include cached anchor
                let newAnchorIndex = Utils.getNoteNthLastSegmentIndex(
                    segments: segments,
                    selectionCursor: self.selectionCursor,
                    n: 0
                ).1
                
                if let newAnchorIndex = newAnchorIndex {
                    newAnchor = segments[newAnchorIndex]
                    print("\tFound new anchor: ", newAnchor ?? "nil")
                }
                
                if let newAnchor = newAnchor {
                    print("\tUpdating Selection Anchor...")
                    self.selectionCursor.setAnchor(segment: newAnchor)
                }
            }
            
            print("\tClear focus...")
            if !self.selectionCursor.hasSelection {
                self.selectionCursor.setFocus()
            }
            
            if let cachedAnchor = self.selectionCursor.cachedAnchor, replaceSelectionCachedAnchor && self.noteBuffer.count > 0 && !cachedAnchor.isCommitted() {
                print("\tReplacing cached anchor. We cannot have a voice command cached anchor.")
                print("\tSearching in note buffer...")
                var newCachedAnchor: NoteSegment?
                let newCachedAnchorIndex = Utils.getNoteNthLastSegmentIndex(
                    segments: Array(self.noteBuffer[0..<cachedAnchor.getIndex() + 1]), // We add one because we want to include cached anchor
                    selectionCursor: self.selectionCursor,
                    n: 0
                ).1
                
                if let newCachedAnchorIndex = newCachedAnchorIndex {
                    newCachedAnchor = Array(self.noteBuffer[0..<cachedAnchor.getIndex() + 1])[newCachedAnchorIndex] // We add one because we want to include cached anchor
                    print("\tFound new cached anchor: ", newCachedAnchor ?? "nil")
                }
                
                if newCachedAnchor == nil {
                    print("\tUnable to find replacement cached anchor in buffer. Search in committed segments...")
                    let newCachedAnchorIndex = Utils.getNoteNthLastSegmentIndex(
                        segments: self.noteSegments,
                        selectionCursor: self.selectionCursor,
                        n: 0
                    ).1
                    
                    if let newCachedAnchorIndex = newCachedAnchorIndex {
                        newCachedAnchor = self.noteSegments[newCachedAnchorIndex]
                        print("\tFound new cached anchor: ", newCachedAnchor ?? "nil")
                    }
                }
                
                if let newCachedAnchor = newCachedAnchor {
                    print("\tUpdating Selection Cached Anchor...")
                    self.selectionCursor.setCachedAnchor(segment: newCachedAnchor)
                }
            } else if let cachedAnchor = self.selectionCursor.cachedAnchor, replaceSelectionCachedAnchor {
                print("\tReplacing cached anchor. We cannot have a voice command anchor.")
                print("\tSearching in note committed segments...")
                var newCachedAnchor: NoteSegment?
                let newCachedAnchorIndex = Utils.getNoteNthLastSegmentIndex(
                    segments: Array(self.noteBuffer[0..<cachedAnchor.getIndex() + 1]), // We add one because we want to include cached anchor
                    selectionCursor: self.selectionCursor,
                    n: 0
                ).1
                
                if let newCachedAnchorIndex = newCachedAnchorIndex {
                    newCachedAnchor = Array(self.noteBuffer[0..<cachedAnchor.getIndex() + 1])[newCachedAnchorIndex] // We add one because we want to include cached anchor
                    print("\tFound new cached anchor: ", newCachedAnchor ?? "nil")
                }
                
                if let newCachedAnchor = newCachedAnchor {
                    print("\tUpdating Selection Cached Anchor...")
                    self.selectionCursor.setCachedAnchor(segment: newCachedAnchor)
                }
            }
            
            print("\tSegment count after processing voice commands: \(self.noteSegments.count) committed and \(self.noteBuffer.count) in buffer.")
            self.handleMutation()
            self.checkRep()
        }
    }
    
    func handleOnSpeechUpdate(text: String, highlightRange: NSRange? = nil) {
        print("===== Note: Handle On Listen Update =====")
        
        if self.noteBuffer.count > 0 {
            // Find first buffer word
            var firstBufferSegment = self.noteBuffer.first
            if let segment = firstBufferSegment, !segment.isActive() {
                firstBufferSegment = self.speechPlayer.getSegment(segment: segment, segments: self.noteBuffer, type: .next, isWord: true)
            }
            
            // Find last buffer word
            var lastBufferSegment = self.noteBuffer.last
            if let segment = lastBufferSegment, !segment.isActive() {
                lastBufferSegment = self.speechPlayer.getSegment(segment: segment, segments: self.noteBuffer, type: .previous, isWord: true)
            }
            
            if self.speechRecognition.isListeningForSpeech && self.noteBuffer.count > 0, let firstBufferSegment = firstBufferSegment, let lastBufferSegment = lastBufferSegment, let firstBufferSegmentTextRange = self.getSegmentTextRange(of: firstBufferSegment), let lastBufferSegmentTextRange = self.getSegmentTextRange(of: lastBufferSegment), firstBufferSegment.isActive() && lastBufferSegment.isActive() {
                let bufferRange = NSRange(
                    location: firstBufferSegmentTextRange.location,
                    length: (lastBufferSegmentTextRange.location - firstBufferSegmentTextRange.location) + lastBufferSegmentTextRange.length
                )
                
                // Notify observers of note update
                var userInfo: [String : Any] = [
                    "text": text,
                    "bufferRange": bufferRange,
                    "transformations": self.transformations
                ]
                
                if let highlightRange = highlightRange {
                    userInfo["highlightRange"] = highlightRange
                }
                
                NotificationCenter.default.post(
                    name: Note.onNoteListenUpdate,
                    object: nil,
                    userInfo: userInfo
                )
            } else {
                // Notify observers of note update
                var userInfo: [String : Any] = [
                    "text": text,
                    "transformations": self.transformations
                ]
                
                if let highlightRange = highlightRange {
                    userInfo["highlightRange"] = highlightRange
                }
                
                NotificationCenter.default.post(
                    name: Note.onNoteListenUpdate,
                    object: nil,
                    userInfo: userInfo
                )
            }
        } else if self.speechRecognition.isListeningForCommands && !self.speechRecognition.isListeningForSpeech && !self.speechRecognition.pausedListeningForSpeech && self.noteSegments.count == 0 {
            // All text is buffer text when listening for commands
            let bufferRange = NSRange(
                location: 0,
                length: text.count
            )
            
            // Notify observers of note update
            var userInfo: [String : Any] = [
                "text": text,
                "bufferRange": bufferRange,
                "transformations": self.transformations
            ]
            
            if let highlightRange = highlightRange {
                userInfo["highlightRange"] = highlightRange
            }
            
            NotificationCenter.default.post(
                name: Note.onNoteListenUpdate,
                object: nil,
                userInfo: userInfo
            )
        } else {
            // Notify observers of note update
            var userInfo: [String : Any] = [
                "text": text,
                "transformations": self.transformations
            ]
            
            if let highlightRange = highlightRange {
                userInfo["highlightRange"] = highlightRange
            }
            
            NotificationCenter.default.post(
                name: Note.onNoteListenUpdate,
                object: nil,
                userInfo: userInfo
            )
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
}
