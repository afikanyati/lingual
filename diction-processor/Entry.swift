//
//  Entry.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/17/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Speech
import AVFoundation
import NaturalLanguage

class Entry: AVMutableComposition, NSCoding {
    // MARK: - Notifications
    static let onRequestToUpdateView = Notification.Name(Notifications.onRequestToUpdateView.rawValue)
    static let onEntryListenUpdate = Notification.Name(Notifications.onEntryListenUpdate.rawValue)
    static let onEntryListenStop = Notification.Name(Notifications.onEntryListenStop.rawValue)
    static let onEntryComplete = Notification.Name(Notifications.onEntryComplete.rawValue)
    static let onEntryCommittedBuffer = Notification.Name(Notifications.onEntryCommittedBuffer.rawValue)
    
    // MARK: - App Modules
    var state: StateManager!
    var speechSynthesis: SpeechSynthesisEngine!
    var speechRecognition: SpeechRecognitionEngine!
    var speechPlayer: SpeechPlayerEngine!
    var pitchRecognition: PitchRecognitionEngine!
    var notifications: NotificationEngine!
    var selectionCursor: SelectionCursor!
    var entryManager: EntryManager!

    // MARK: - Composition Properties
    /// Stores the name of the entry
    public var title: String?
    /// Stores a unique identifier for entry
    private(set) var uid: String
    /// Stores the filename of the entry
    private(set) var filename: String
    // Change recording format:
    // Reference 1: https://stackoverflow.com/questions/4279311/how-to-record-voice-in-m4a-format
    // Reference 2: https://developer.apple.com/forums/thread/27411
    /// Stores the private AVFileType of the source URL
    private var _fileType: AVFileType = .caf // Used when instantiating EntrySegment class instances
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
    /// Stores the time range of the entry
    public var timeRange: CMTimeRange {
        return CMTimeRangeMake(start: CMTime.zero, duration: self.getDuration())
    }
    /// The date when entry was created
    private(set) var dateCreated: TimeInterval = Date().timeIntervalSince1970
    /// The date when entry was last modified
    private(set) var dateModified: TimeInterval = Date().timeIntervalSince1970
    /// Stores the creator's uid
    private(set) var creatorUID: String
    /// Stores a list of high-level representation of entry segments
    private(set) var entrySegments: [EntrySegment] = [EntrySegment]()
    /// Stores a list of high-level representation of entry segments in staging (before committed to entrySegments)
    private(set) var entryBuffer: [EntrySegment] = [EntrySegment]()
    /// Range of last committed buffer of entry segments
    private(set) var committedBufferRanges = [Range<Int>]()
    /// An array of  transformations applied the entry
    private(set) var transformations = [EntryTransformation]()
    /// Stores the starting time of the entry
    private(set) var startTime: CMTime = CMTime.zero // When we remove or add we change this
    /// Stores the ending time of the entry
    private(set) var endTime: CMTime = CMTime.zero // When we remove or add we change this
    /// Stores the number of paragraphs in the entry
    public var paragraphCount: Int {
        var paragraphCount = Int(Utils.UNKNOWN)
        if let lastSegment = self.entryBuffer.last, self.entryBuffer.count > 0 && lastSegment.getParagraph().number != Int(Utils.UNKNOWN) {
            paragraphCount = lastSegment.getParagraph().number + 1
        } else if let lastSegment = self.entrySegments.last, self.entrySegments.count > 0 && lastSegment.getParagraph().number != Int(Utils.UNKNOWN) {
            paragraphCount = lastSegment.getParagraph().number + 1
        }
        
        return paragraphCount
    }
    /// Stores the number of sentences in the entry
    public var sentenceCount: Int {
        var sentenceCount = Int(Utils.UNKNOWN)
        if let lastSegment = self.entryBuffer.last, self.entryBuffer.count > 0 && lastSegment.getSentence().number != Int(Utils.UNKNOWN) {
            sentenceCount = lastSegment.getSentence().number + 1
        } else if let lastSegment = self.entrySegments.last, self.entrySegments.count > 0 && lastSegment.getSentence().number != Int(Utils.UNKNOWN) {
            sentenceCount = lastSegment.getSentence().number + 1
        }
        
        return sentenceCount
    }
    /// Stores the number of words in the entry
    public var wordCount: Int {
        let wordCount: Int = self.entrySegments.reduce(0, { result, segment in
            if segment.isValidWord() {
                return result + 1
            }
            
            return result
        })
        return wordCount
    }
    /// The language of the entry
    public var language: NLLanguage? {
        if let firstSegment = self.entrySegments.first, let language = NLLanguageRecognizer.dominantLanguage(for: firstSegment.getText()) {
            return language
        }
        
        return nil
    }
    /// Stores avg background noise over the course of entry
    public var avgBackgroundNoise: Double {
        guard self.entrySegments.count > 0 else { return 0 }
        let avgBackgroundNoise: Double = self.entrySegments.reduce(Double.zero, { result, segment in
            let backgroundNoise: Double = segment.getBackgroundNoise()
            if segment.isValidWord() &&
                backgroundNoise.isNormal &&
                backgroundNoise.isFinite &&
                !backgroundNoise.isNaN
            {
                return result + backgroundNoise
            }
            
            return result
        }) / Double(self.entrySegments.count)
        
        return avgBackgroundNoise
    }
    /// The average number of words spoken per minute.
    public var avgSpeakingRate: Double {
        // Can be used to vary speed relative to WPM
        var speakingRate: Double = 0
        var segmentCount = self.entrySegments.count
        
        // entry segments
        for segment in self.entrySegments {
            if !segment.isVoiceCommandWord() && !segment.isDeleted() {
                speakingRate += segment.getSpeakingRate()
            }
        }
        
        // entry buffer
        if self.entryBuffer.count > 0 {
            segmentCount += self.entryBuffer.count
            for segment in self.entryBuffer {
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
    /// Stores whether entry is authorized to listen for speech. This is typically false when then source filetype is .m4a vs. .caf, which happens on entry export
    private(set) var authorizedToListenForSpeech = false
    /// Stores a count of the number of unique clips that have been recording throughout entry (factors recording breaks due to voice commands)
    private(set) var clips: Set<String> = []
    /// Stores the current clip UID
    private(set) var currentClipUID: String?
    /// Stores a reference to the moment current entry clip started listening
    private(set) var recordStartDate: Date?
    /// Stores the total duration of time across segments capturing during the current listening clip
    private(set) var accumulatedDuration = TimeInterval(0) // Only relevant on < OS13 where timer restarts after every onFinishedRecognition
    /// Stores a reference to the audio file where listening buffers are being saved to
    private(set) var recordFile: AVAudioFile?
    /// Stores whether clip is deleted
    private(set) var isDeleted = false

    // MARK: - Cached Properties
    /// Stores a cached version of the entry's duration
    private(set) var cachedDuration: CMTime?
    /// Stores a cached version of getText() method
    private(set) var cachedText: String?
    /// Stores arguments of last getText() call
    private(set) var cachedTextArgsSet: Set<String>?
    /// Stores segments of last getText() call
    private(set) var cachedSegmentUIDSet: Set<String>?
    /// Stores cached version of getBackgroundNoise
    private(set) var cachedBackgroundNoise: Double?
    
    // MARK: - Telemetry
    private(set) var views = [TimeInterval]()
    private(set) var plays = [TimeInterval]()
    private(set) var textExports = [TimeInterval]()
    private(set) var audioExports = [TimeInterval]()
    
    // MARK: - Initializer

    /// Initializes the Entry class instance
    ///
    /// - Parameters:
    ///     - vc: Suppliess a reference to the main view controller
    ///     - filename: Supplies the filename of the entry
    ///     - fileType: Suppliess the filetype of the source URL
    ///     - creatorUID: Supplies the creator's uid
    ///     - segments: Supplies an optional array of entry segments to seed the entry
    ///     - onComplete: Supplies a handler to be executed when entry is complete.
    init(
        uid: String,
        filename: String,
        fileType: AVFileType? = nil,
        creatorUID: String,
        segments: [EntrySegment]? = nil,
        state: StateManager? = nil,
        speechSynthesis: SpeechSynthesisEngine? = nil,
        speechRecognition: SpeechRecognitionEngine? = nil,
        speechPlayer: SpeechPlayerEngine? = nil,
        selectionCursor: SelectionCursor? = nil,
        pitchRecognition: PitchRecognitionEngine? = nil,
        entryManager: EntryManager? = nil,
        notifications: NotificationEngine? = nil
    ) {
        print("===== Entry: Initialization =====")
        print("\tFilename: ", filename)
        self.uid = uid
        self.filename = filename
        self.creatorUID = creatorUID
        
        if let state = state {
            self.state = state
        }
        if let speechSynthesis = speechSynthesis {
            self.speechSynthesis = speechSynthesis
        }
        if let speechRecognition = speechRecognition {
            self.speechRecognition = speechRecognition
        }
        if let speechPlayer = speechPlayer {
            self.speechPlayer = speechPlayer
        }
        if let selectionCursor = selectionCursor {
            self.selectionCursor = selectionCursor
        }
        if let pitchRecognition = pitchRecognition {
            self.pitchRecognition = pitchRecognition
        }
        if let entryManager = entryManager {
            self.entryManager = entryManager
        }
        if let notifications = notifications {
            self.notifications = notifications
        }
        
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
        
        if let segments = segments, segments.count > 0 {
            print("\tDuplicate and save each segment...")
            var entrySegments = [EntrySegment](repeating: segments.first!, count: segments.count)
            DispatchQueue.concurrentPerform(iterations: segments.count) { [weak self] index in
                let duplicateSegment = segments[index].duplicate()
                duplicateSegment.setEntry(entry: self!)
                entrySegments[index] = duplicateSegment
            }
            
            self.startTime = entrySegments.first!.timeMapping.target.start
            self.endTime = entrySegments.last!.timeMapping.target.end
            
            self.setSegments(
                segments: entrySegments,
                replaceEntryDetails: false,
                saveToLowLevelRepr: true,
                saveToState: false
            )
        } else {
            print("\tNo segments to insert. Return entry...")
        }
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.uid, forKey: "uid")
        coder.encode(self.filename, forKey: "filename")
        coder.encode(self._fileType, forKey: "fileType")
        coder.encode(self.dateCreated, forKey: "dateCreated")
        coder.encode(self.dateModified, forKey: "dateModified")
        coder.encode(self.creatorUID, forKey: "creatorUID")
        coder.encode(self.entrySegments, forKey: "entrySegments")
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
        self.entrySegments = coder.decodeObject(forKey: "entrySegments") as! [EntrySegment]
        if let committedBufferDictRanges = coder.decodeObject(forKey: "committedBufferRanges") as? [[String:Int]] {
            var committedBufferRanges = [Range<Int>]()
            for dictRange in committedBufferDictRanges {
                let range = dictRange["startIndex"]!..<dictRange["endIndex"]!
                committedBufferRanges.append(range)
            }
            self.committedBufferRanges = committedBufferRanges
        }
        self.transformations = coder.decodeObject(forKey: "transformations") as! [EntryTransformation]
        self.authorizedToListenForSpeech = coder.decodeBool(forKey: "authorizedToListenForSpeech")
        self.clips = coder.decodeObject(forKey: "clips") as! Set<String>
        self.startTime = self.entrySegments.count > 0 ? self.entrySegments.first!.timeMapping.target.start : CMTime.zero
        self.endTime = self.entrySegments.count > 0 ? self.entrySegments.last!.timeMapping.target.end : CMTime.zero
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
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    public override var description: String {
        return "Entry {\n\tuid: \(self.uid) \n\tfilename: \(self.filename) \n\tfileType: \(self.fileType) \n\tdateCreated: \(Utils.getDateString(date: self.dateCreated) ?? "nil") \n\tdateModified: \(Utils.getDateString(date: self.dateModified) ?? "nil") \n\tcreatorUID: \(self.creatorUID) \n\tentrySegments: \(self.entrySegments) \n\tentryBuffer: \(self.entryBuffer) \n\tcommittedBufferRanges: \(String(describing: self.committedBufferRanges)) \n\ttransformations: \(self.transformations) \n\tstartTime: \(self.startTime) \n\tendTime: \(self.endTime) \n\tduration: \(self.getDuration()) \n\tsentenceCount: \(self.sentenceCount) \n\twordCount: \(self.wordCount) \n\tlanguage: \(String(describing: self.language)) \n\tavgSpeakingRate: \(self.avgSpeakingRate) \n\tauthorizedToListenForSpeech: \(self.authorizedToListenForSpeech) \n\tclips: \(self.clips) \n\tcurrentClipUID: \(self.currentClipUID ?? "nil") \n\trecordStartDate: \(String(describing: self.recordStartDate)) \n\taccumulatedDuration: \(self.accumulatedDuration) \n\tisDeleted: \(self.isDeleted) \n\tviews: \(self.views) \n\tplays: \(self.plays) \n\ttextExports: \(self.textExports) \n\taudioExports: \(self.audioExports)\n}"
    }
    
    static func ==(_ firstEntry: Entry, _ secondEntry: Entry) -> Bool {
        return firstEntry.uid == secondEntry.uid &&
            firstEntry.filename == secondEntry.filename &&
            firstEntry._fileType == secondEntry._fileType &&
            firstEntry.dateCreated == secondEntry.dateCreated &&
            firstEntry.dateModified == secondEntry.dateModified &&
            firstEntry.creatorUID == secondEntry.creatorUID &&
            firstEntry.entrySegments.elementsEqual(secondEntry.entrySegments) &&
            firstEntry.entryBuffer.elementsEqual(secondEntry.entryBuffer) &&
            firstEntry.committedBufferRanges.elementsEqual(secondEntry.committedBufferRanges) &&
            firstEntry.transformations.elementsEqual(secondEntry.transformations) &&
            firstEntry.startTime == secondEntry.startTime &&
            firstEntry.endTime == secondEntry.endTime &&
            firstEntry.authorizedToListenForSpeech == secondEntry.authorizedToListenForSpeech &&
            firstEntry.clips == secondEntry.clips &&
            firstEntry.currentClipUID == secondEntry.currentClipUID &&
            firstEntry.recordStartDate == secondEntry.recordStartDate &&
            firstEntry.accumulatedDuration == secondEntry.accumulatedDuration &&
            firstEntry.recordFile == secondEntry.recordFile &&
            firstEntry.isDeleted == secondEntry.isDeleted &&
            firstEntry.views.elementsEqual(secondEntry.views) &&
            firstEntry.plays.elementsEqual(secondEntry.plays) &&
            firstEntry.textExports.elementsEqual(secondEntry.textExports) &&
            firstEntry.audioExports.elementsEqual(secondEntry.audioExports)
    }
    
    // MARK: - Configuration Methods
    
    func configureAudioWriteFile() {
        print("===== Configure Entry Audio Write File =====")
        do {
            try recordFile = AVAudioFile(
                forWriting: Utils.getFileURL(of: "\(self.filename)-\(self.currentClipUID!)\(self.fileType)"),
                settings: self.speechRecognition.audioEngine.inputNode.inputFormat(forBus: Utils.RECORD_FILE_BUS).settings
            )
            authorizedToListenForSpeech = true
            print("\tSource URL for writing entry successfully created: \(self.filename)-\(self.currentClipUID!)\(self.fileType)")
        } catch {
            print("\t[Error] There was a problem instantiating the record file")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        print("===== Entry: Configure Notification Observers =====")
        let notificationCenter = NotificationCenter.default
        
        // SpeechRecognitionEngine
        notificationCenter.addObserver(
            self,
            selector: #selector(onStartedListeningForSpeech(notification:)),
            name: SpeechRecognitionEngine.onStartedListeningForSpeech,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onRequestPrepareAudioFile(notification:)),
            name: SpeechRecognitionEngine.onRequestPrepareAudioFile,
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
    
    @objc func onRequestPrepareAudioFile(notification: Notification) {
        if self.entryManager == nil ||
            self.isDeleted ||
            entryManager.currentEntry == nil ||
            (
                self.entryManager!.currentEntry != nil &&
                self.entryManager!.currentEntry!.uid != self.uid
            ) { return }
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry writing to one file, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            return
        }
        print("===== Entry \(self.uid): On Request Prepare Audio File =====")
        
        // Create and save new clip used to create unique track URLs to write audio into
        self.generateNewClip()
        
        // Reset accumulated Duration for next clip capture
        self.accumulatedDuration = TimeInterval(0)

        // Configure Audio Write File
        self.configureAudioWriteFile()
    }
    
    @objc func onStartedListeningForSpeech(notification: Notification) {
        if self.entryManager == nil ||
            self.isDeleted ||
            entryManager.currentEntry == nil ||
            (
                self.entryManager!.currentEntry != nil &&
                self.entryManager!.currentEntry!.uid != self.uid
            ) { return }
        print("===== Entry \(self.uid): On Start Listening For Speech =====")
        
        if !self.authorizedToListenForSpeech {
            print("\t[Error] There was a problem while starting to listen for speech. Entry is not authorized to listen.")
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
        if self.entryManager == nil ||
            self.isDeleted ||
            entryManager.currentEntry == nil ||
            (
                self.entryManager!.currentEntry != nil &&
                self.entryManager!.currentEntry!.uid != self.uid
            ) { return }
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry writing to one file, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            return
        }

        if let entryManager = self.entryManager, let recordFile = self.recordFile, let entry = entryManager.currentEntry, entry.uid == self.uid && self.speechRecognition.isListeningForSpeech {
//            print("===== Entry: On Buffer Item =====")
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
        if self.entryManager == nil || self.tracks.count == 0 || self.isDeleted || self.entryManager!.currentEntry == nil || (self.entryManager!.currentEntry != nil && self.entryManager!.currentEntry!.uid != self.uid) { return }
        
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry updating segments, we only allow the one that matches memory addresses with currentEntry through
        guard Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(self.entryManager.currentEntry!).toOpaque() else {
            print("\t[Error] Entry has different memory address of current Entry:")
            print("\tSelf: ", Unmanaged.passUnretained(self).toOpaque())
            print("\tCurrent Entry: ", Unmanaged.passUnretained(self.entryManager.currentEntry!).toOpaque())
            return
        }
        print("===== Entry \(self.uid): On Speech Update =====")
        
        let transcription = notification.userInfo!["transcription"] as! SFTranscription
        let isVoiceCommand = notification.userInfo!["isVoiceCommand"] as! Bool
        let voiceCommandType = notification.userInfo!["voiceCommandType"] as? String
        let voiceCommandIndices = notification.userInfo!["voiceCommandIndices"] as? [Int]
        let isFinalTranscription = notification.userInfo!["isFinalTranscription"] as! Bool

        if self.speechRecognition.isListeningForSpeech || (isVoiceCommand && voiceCommandType == "stop entry") {
            print("\tProcessing transcript...")
            self.performTranscriptionUpdate(transcription)
            print("\tBuffer: ", Utils.stringifySegments(segments: self.entryBuffer))
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
                    self.selectionCursor.handleUpdateSelection(segments: self.entryBuffer)
                }
            } else {
                self.selectionCursor.handleUpdateSelection(segments: self.entryBuffer)
            }
        } else if isFinalTranscription && !self.selectionCursor.isUpdatingSelection && (self.speechRecognition.isListeningForSpeech || (isVoiceCommand && voiceCommandType == "stop entry") || self.speechRecognition.pausedListeningForSpeech) {
            print("\tReceived final transcript. Commit buffer.")
            
            // Commit Speech
            if self.entryBuffer.count > 0 {
                // We want to process voice commands before we commit so we avoid punctuation suggestions being formed for new segments
                if let voiceCommandIndices = voiceCommandIndices, isVoiceCommand {
                    print("\tProcess voice command...")
                    self.processVoiceCommandSegments(
                        command: transcription.formattedString,
                        voiceCommandIndices: voiceCommandIndices
                    )
                }
                
                // commit buffer
                if !self.speechRecognition.pausedListeningForSpeech {
                    if !isVoiceCommand {
                        // We don't want to pay commit buffer sound if we processed a voice command
                        
                        // Play Sound
                        soundEngine.commitBuffer()
                    }

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
                
                NotificationCenter.default.post(
                    name: Entry.onEntryCommittedBuffer,
                    object: nil,
                    userInfo: [:]
                )
            }
        } else if self.recordStartDate != nil {
            print("\tDo not commit buffer.")
            if let voiceCommandIndices = voiceCommandIndices, isVoiceCommand && (self.speechRecognition.isListeningForSpeech || voiceCommandType == "stop entry" || self.speechRecognition.pausedListeningForSpeech) && self.entrySegments.count > 0 {
                print("\tProcess voice command...")
                self.processVoiceCommandSegments(
                    command: transcription.formattedString,
                    voiceCommandIndices: voiceCommandIndices
                )
            }
            
            // Don't keep buffer if we're not listening
            if self.speechRecognition.pausedListeningForSpeech {
                self.clearBuffer()
            }
        }
        
        if !self.selectionCursor.isUpdatingSelection {
            print("\tUpdate View...")
            // execute listen update handler
            let text = self.getText()
            self.handleOnSpeechUpdate(text: text)
        }
        
        // Save changes
        if !self.speechRecognition.isListeningForSpeech && self.entrySegments.count > 0 && self.recordStartDate != nil {
            print("\tProcess entry finishing...")
            self.handleFinish(normalize: true)
        } else if isFinalTranscription &&
            !isVoiceCommand
        {
            // If we only allow to enter here if we have an existing snapshot,
            // Undoing to the start will make us have no snapshots and then we will never be able to register another entry change
            self.entryManager.registerEntryChange(entry: self, undo: "committing new speech", ignoreUpdate: true)
        }
    }
    
    @objc func onStoppedListeningForSpeech(notification: Notification) {
//        if let entryManager = self.entryManager, self.isDeleted || entryManager.currentEntry == nil || (entryManager.currentEntry != nil && entryManager.currentEntry!.uid != self.uid) { return }
//
//        print("===== Entry \(self.uid): On Stopped Listening For Speech =====")
    }
    
    // MARK: - Validation
    
    func checkRep() {
        var result = true
        
        // dateModified must be after dateCreated
        result = result && self.dateModified >= self.dateCreated
//         print("dateModified must be after dateCreated: ", self.dateModified >= self.dateCreated, self.dateModified, self.dateCreated)
//         print("current result: ", result)

        // startTime must be in front of endTime
        result = result && self.endTime >= self.startTime
//        print("startTime must be in front of endTime: ", self.endTime >= self.startTime, self.endTime, self.startTime)
//        print("current result: ", result)

        // start of entry segments should be the same as startTime
        if let firstSegment = self.entrySegments.first {
            result = result && firstSegment.timeMapping.target.start == self.startTime
//            print("start of entry segments should be the same as startTime: ", firstSegment.timeMapping.target.start == self.startTime, firstSegment.timeMapping.target.start.seconds, self.startTime.seconds)
//            print("current result: ", result)
        }

        // end of entry segments should be the same as endTime
        if let lastSegment = self.entrySegments.last {
            result = result && self.endTime == lastSegment.timeMapping.target.end
//            print("end of entry segments should be the same as endTime: ", self.endTime == lastSegment.timeMapping.target.end, self.endTime.seconds, lastSegment.timeMapping.target.end.seconds)
//            print("current result: ", result)
        }

        // internal durations should be the same
        if let firstSegment = self.entrySegments.first, let lastSegment = self.entrySegments.last {
            result = result && CMTimeSubtract(self.endTime, self.startTime) == CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start)
//            print("internal durations should be the same: ", CMTimeSubtract(self.endTime, self.startTime) == CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start), CMTimeSubtract(self.endTime, self.startTime).seconds, CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start).seconds)
//            print("current result: ", result)
        }

        // duration of segments should be the same as underlying track segments
        // we only check is we have two entry tracks because that's when we're guaranteed to have saved entry segments to lower level track representation
        if self.entrySegments.count > 0, let firstSegment = self.tracks[0].segments.first, let lastSegment = self.tracks[0].segments.last {
            result = result && CMTimeSubtract(self.entrySegments.last!.timeMapping.target.end, self.entrySegments.first!.timeMapping.target.start) == CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start)
//            print("duration of first track should be the same as underlying track segments: ", CMTimeSubtract(self.entrySegments.last!.timeMapping.target.end, self.entrySegments.first!.timeMapping.target.start) == CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start), CMTimeSubtract(self.entrySegments.last!.timeMapping.target.end, self.entrySegments.first!.timeMapping.target.start).seconds, CMTimeSubtract(lastSegment.timeMapping.target.end, firstSegment.timeMapping.target.start).seconds)
//            print("current result: ", result)
        }
        
        if !result {
            fatalError("===== [Error] Entry Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Speech Listening Methods
    
    func performTranscriptionUpdate(_ transcription: SFTranscription) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override performTranscriptionUpdate method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Perform Transcription Update =====")
        print("\tTranscript Text: ", transcription.formattedString)
        var nextBuffer = [EntrySegment]()
        for (index, segment) in transcription.segments.enumerated() {
            let segment = self.processTranscriptSegment(
                segment: segment,
                transcriptionIndex: index,
                transcription: transcription,
                nextBuffer: nextBuffer
            )

            if let segment = segment {
                nextBuffer.append(segment)
            }
        }
        print ("\tOld Buffer: ", Utils.stringifySegments(segments: self.entryBuffer))
        print("\tUpdating buffer...")
        self.entryBuffer = nextBuffer
        print ("\tNew Buffer: ", Utils.stringifySegments(segments: self.entryBuffer))
    }
    
    func processTranscriptSegment(
        segment: SFTranscriptionSegment,
        transcriptionIndex: Int,
        transcription: SFTranscription,
        nextBuffer: [EntrySegment]
    ) -> EntrySegment? {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override processTranscriptSegment method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return nil
        }
        
        // Manage NLP
        var segmentTags: [String : NLTag?]
        var sentiment: [ScaleUnitType: Float]?
        if transcriptionIndex < self.entryBuffer.count &&
            self.entryBuffer[transcriptionIndex].getText().lowercased() == segment.substring.lowercased()
        {
            // existing segment, get values
            let existingSegment = self.entryBuffer[transcriptionIndex]
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
            (segmentTags, sentiment) = computeSegmentTags(
                transcription: transcription,
                transcriptionIndex: transcriptionIndex
            )
        }
        
        // Compute segment text
        let word = transcriptionIndex == 0
            && nextBuffer.count > 0
            && !nextBuffer.last!.isSentenceTerminator()
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
            if nextBuffer.count == 0 {
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
            return nil
        }
        let entrySegment = EntrySegment(
            entry: self,
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
            sentimentScore: sentiment,
            withPunctuationSuggestions: self.state.withPunctuationSuggestions,
            voiceCommandWord: false
        )
        
        // Existing segment, overwrite old copy
        if self.entryBuffer.count > transcriptionIndex {
            let oldSegment = self.entryBuffer[transcriptionIndex]
            // determine if we need to replace selection values
            // prevent replacing selection values if we're processing a selection update
            let replaceSelectionAnchor = oldSegment == self.selectionCursor.anchor && !self.selectionCursor.isUpdatingSelection
            let replaceSelectionFocus = oldSegment == self.selectionCursor.focus && !self.selectionCursor.isUpdatingSelection
            let replaceSelectionCachedAnchor = oldSegment == self.selectionCursor.cachedAnchor && !self.selectionCursor.isUpdatingSelection
            
            // Transfer voice command status
            let isVoiceCommandWord = oldSegment.isVoiceCommandWord()
            entrySegment.setIsVoiceCommandWord(to: isVoiceCommandWord)
            
            // update selection anchor
            if replaceSelectionAnchor {
                self.selectionCursor.setAnchorCaret(caret: Caret(index: transcriptionIndex, trackType: .buffer))
            }
            
            // update selection focus
            if replaceSelectionFocus {
                self.selectionCursor.setFocusCaret(caret: Caret(index: transcriptionIndex, trackType: .buffer))
            }
            
            // update selection cached anchor
            if replaceSelectionCachedAnchor {
                self.selectionCursor.setCachedAnchorCaret(caret: Caret(index: transcriptionIndex, trackType: .buffer))
            }
        }
        
        return entrySegment
    }
    
    // We set sound intensity here because its when we with certainty have correct time data with pauses factored in
    // We set background noise here because we can identify all the silences
    // We set sentence numbers here because we've built up the entire entry and can compute sentences factoring it all
    // This is where correct values for avgPauseDuration and speakingRate are set
    func normalizeSegments(
        segments: [EntrySegment]? = nil,
        normalizeType: TimeNormalizerType = .source,
        replaceEntryDetails: Bool = false,
        omitLeadingSilence: Bool = false,
        saveSegments: Bool = false,
        saveToLowLevelRepr: Bool = false,
        returnSegments: Bool = false,
        saveToState: Bool = true,
        startTime: CMTime = CMTime.zero,
        startIndex: Int? = nil
    ) -> [EntrySegment]? {
        print("===== Entry: Normalize Segments =====")
        var lastEnd = startTime
        var normalizedSegments = [EntrySegment]()
        var silenceIndices = [Int]()
        print("\tStart Time: ", startTime.seconds)
        print("\tStartIndex: ", startIndex ?? "nil")
        
        var segs = self.entryBuffer.count > 0 ? self.entryBuffer : self.entrySegments
        if let segments = segments {
            print("\tReceived custom segments. Setting as normalization contents...")
            print("\tSegments: ", Utils.stringifySegments(segments: segments))
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

                    if let lastCommittedSegment = self.entrySegments.last,
                       index == 0 && segments != nil &&
                        segments!.first! != self.entrySegments.first! &&
                        self.entrySegments.count > 0 &&
                        normalizeType == .source &&
                        lastCommittedSegment.sourceURL!.absoluteString == trackURL.absoluteString
                    {
                        // first segment is silence
                        // we are normalizing source
                        // entrySegments is not empty
                        // we are on the same source url as the last segment in entrySegments
                        // we are passed in segments
                        // the first segment of entrySegments and passed in segments are not the same
                        lastEnd = lastCommittedSegment.timeMapping.source.end
                    }

                    // Add a silent segment in front of current segment to account for early time
                    let silentSegment = EntrySegment(
                        entry: self,
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
                    let newDuration = normalizeType == .source ?
                        CMTimeSubtract(segment.timeMapping.source.end, lastEnd)
                        :
                        CMTimeSubtract(segment.timeMapping.target.end, lastEnd)
                    let sourceTimeRange = normalizeType == .source ?
                    CMTimeRangeMake(start: lastEnd, duration: newDuration)
                    :
                    CMTimeRangeMake(start: segment.timeMapping.source.start, duration: newDuration)
                    
                    let targetTimeRange = normalizeType == .target ?
                    CMTimeRangeMake(start: lastEnd, duration: newDuration)
                    :
                    CMTimeRangeMake(start: segment.timeMapping.target.start, duration: newDuration)
                    let modifiedSegment = EntrySegment(
                        entry: self,
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
                    let normalizedSegment = EntrySegment(
                        entry: self,
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
        
        var speakingRate: Double = normalizedSegments.reduce(0, { result, segment in
            if segment.isValidWord() {
                return result + 1
            }
            
            return result
        }) / Double(self.getDuration().seconds / Double(TimeConstant.secsPerMin))
        speakingRate = speakingRate.rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)
        
        var initialSilenceDuration: CMTime?
        if omitLeadingSilence && normalizedSegments.first!.isSilence() {
            print("\tOmitting leading silence...")
            initialSilenceDuration = normalizedSegments.first!.timeMapping.target.end
            normalizedSegments.removeFirst()
        }
        
        // Update Index, Background Noise, AvgPauseDuration, SpeakingRate
        var fullyNormalizedSegments = [EntrySegment]()
        for (index, segment) in normalizedSegments.enumerated() {
            // Set segment index
            if let startIndex = startIndex {
                segment.setIndex(index: startIndex + index)
            } else {
                segment.setIndex(index: index)
            }
            
            // Set background noise
            segment.setBackgroundNoise(noise: self.getBackgroundNoise())

            // Set avgPauseDuration
            if let avgPauseDuration = avgPauseDuration {
                segment.setAvgPauseDuration(duration: avgPauseDuration)
            }
            
            // Set speakingRate
            segment.setSpeakingRate(rate: speakingRate)
            
            if omitLeadingSilence, let initialSilenceDuration = initialSilenceDuration {
                // segment overlaps with previous segment, shift it forwards
                let shiftedSegment = EntrySegment(
                    entry: self,
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
                replaceEntryDetails: replaceEntryDetails,
                saveToLowLevelRepr: saveToLowLevelRepr,
                saveToState: saveToState
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
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override commitBuffer method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        guard self.entryBuffer.count > 0 else { return }
        print("===== Entry: Commit Buffer =====")

        // duplicate entry tracks
        let segments = self.entryBuffer
        
        print("\tBuffer Segments: ", Utils.stringifySegments(segments: segments))
        
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
            numSegmentsAheadCursorBeforeInsertion = self.entrySegments.count - numSegmentsBehindCursorBeforeInsertion
        } else {
            print("\tInsert time identified to be at end of entry...")
            // Find insert time
            insertTime = self.entrySegments.count > 0 ? self.entrySegments.last!.timeMapping.target.end : CMTime.zero
            
            // cache count of segments before insert to set last buffer range
            numSegmentsBehindCursorBeforeInsertion = self.entrySegments.count
            numSegmentsAheadCursorBeforeInsertion = self.entrySegments.count - numSegmentsBehindCursorBeforeInsertion
        }
        
        var oldAnchor: EntrySegment?
        if let anchor = self.selectionCursor.anchor {
            print("\tSelection anchor identified: ", anchor.getText())
            oldAnchor = anchor.duplicate()
        }
        
        var oldFocus: EntrySegment?
        if let focus = self.selectionCursor.focus {
            print("\tSelection focus identified...")
            oldFocus = focus.duplicate()
        }
        
        // Clear buffer segments
        print("\tClearing entry buffer...")
        self.clearBuffer()
        
        // normalize segments
        var startTime = CMTime.zero
        var startIndex = 0
        if let lastSegment = self.entrySegments.last {
            // We want to normalize segments assuming they'll be at the end of the entry
            // We do this to save on computation
            startTime = lastSegment.timeMapping.target.end
            startIndex = lastSegment.getIndex() + 1
        }
        let normalizedSourceSegments = self.normalizeSegments(
            segments: segments,
            normalizeType: .source,
            omitLeadingSilence: updateCachedAnchor, // remove leading space so that we don't erroneously treat it as a long silence in the event that we are inserting new speech
            returnSegments: true,
            saveToState: false
        )
        print("\tNormalizing buffer segments with start time: \(startTime.seconds) and initial index: \(startIndex)")
        let normalizedSegments = self.normalizeSegments(
            segments: normalizedSourceSegments,
            normalizeType: .target,
            omitLeadingSilence: updateCachedAnchor, // remove leading space so that we don't erroneously treat it as a long silence in the event that we are inserting new speech
            returnSegments: true,
            saveToState: false,
            startTime: startTime,
            startIndex: startIndex
        )
        print("\tNormalized Segments: ", Utils.stringifySegments(segments: normalizedSegments!))
        let lastBufferWordIndex = Utils.getEntryNthLastSegmentIndex(
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
            at: insertTime,
            saveToState: true
        )
        
        if let lastBufferWordIndex = lastBufferWordIndex, updateCachedAnchor && cachedAnchorIndex != Int(Utils.UNKNOWN) {
            let lastNormalizedWord = self.entrySegments[cachedAnchorIndex + lastBufferWordIndex + 1] // We add one because we want the last buffer word to be the new index
            print("\tUpdating cached anchor...")
            print("\tUpdating cached anchor in selection: ", lastNormalizedWord.getText())
            self.selectionCursor.setCachedAnchorCaret(caret: Caret(index: lastNormalizedWord.getIndex(), trackType: .committed))
        }

        if let oldAnchor = oldAnchor,
           let newAnchor = self.entrySegments.first(where: { $0.getUID() == oldAnchor.getUID() }),
           oldAnchor.getIndex() == Int(Utils.UNKNOWN)
        {
            print("\tUpdating anchor...")
            print("\tUpdated anchor segment in selection cursor: ", newAnchor.getText())
            self.selectionCursor.setAnchorCaret(caret: Caret(index: newAnchor.getIndex(), trackType: .committed))
        }
        
        if let oldFocus = oldFocus,
           let newFocus = self.entrySegments.first(where: { $0.getUID() == oldFocus.getUID() }),
           oldFocus.getIndex() == Int(Utils.UNKNOWN)
        {
            print("\tUpdating focus...")
            print("\tUpdated focus segment in selection cursor: ", newFocus.getText())
            self.selectionCursor.setFocusCaret(caret: Caret(index: newFocus.getIndex(), trackType: .committed))
        }
        
        // Set range of last buffer
        print("\tSet last buffer range in entry properties...")
        let numNormalizedBufferSegments = self.entrySegments.count - (numSegmentsBehindCursorBeforeInsertion + numSegmentsAheadCursorBeforeInsertion)
        print(
            "\tLast Buffer Range: ",
            numSegmentsBehindCursorBeforeInsertion..<(numSegmentsBehindCursorBeforeInsertion + numNormalizedBufferSegments),
            "'\(self.entrySegments[numSegmentsBehindCursorBeforeInsertion].getText())'..<'\(self.entrySegments[numSegmentsBehindCursorBeforeInsertion + numNormalizedBufferSegments - 1].getText())'"
        )
        self.committedBufferRanges.append(numSegmentsBehindCursorBeforeInsertion..<(numSegmentsBehindCursorBeforeInsertion + numNormalizedBufferSegments))
    }
    
    func clearBuffer() {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override clearBuffer method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Clear Buffer =====")
        self.entryBuffer = []
    }
    
    func handleSave(handler: (() -> Void)? = nil) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override handleSave method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Handle Save =====")
        
        if let speechRecognition = self.speechRecognition, speechRecognition.isListeningForSpeech {
            print("\tHandle intermediate saving...")
            self.state.save()
        }
    }
    
    func handleFinish(normalize: Bool = false) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override handleFinish method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Handle Finish =====")
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
            self?.selectionCursor.setAnchorCaret()
            self?.selectionCursor.setFocusCaret()
            self?.selectionCursor.setCachedAnchorCaret()
            self?.state.save()
            
            // Feedback
            self?.notifications.executeFeedback(
                visualMessage: "Saved!",
                audioMessage: "entry saved",
                withHaptics: true,
                delay: 1.0
            )

            self!.speechRecognition.startListeningForVoiceCommands() { [weak self] in
                print("\tFinal Entry Segments: ", self!.entrySegments)
                print("\tFinal Entry Transformations: ", self!.transformations)
                NotificationCenter.default.post(
                    name: Entry.onEntryComplete,
                    object: nil,
                    userInfo: [ "text": self!.getText()]
                )
            }
        }
        
        NotificationCenter.default.post(
            name: Entry.onEntryListenStop,
            object: nil,
            userInfo: [ "text": self.getText()]
        )
        
        if self.entryBuffer.count > 0 {
            print("\tEntry buffer has uncommitted segments. Trash them.")
            print("\tClearing entry buffer...")
            self.clearBuffer()
            if normalize && self.entrySegments.count > 0 {
                print("\tNormalizing \(self.entrySegments.count) segments before saving entry.")
                let _ = self.normalizeSegments(
                    normalizeType: .target,
                    saveSegments: true,
                    saveToLowLevelRepr: true,
                    saveToState: true
                )
            }
            onFinishHandler()
        } else if self.entrySegments.count > 0 {
            // No need to normalize segments or export entry if we haven't captured anything meaningful
            if normalize && self.entrySegments.count > 0 {
                print("\tNormalizing \(self.entrySegments.count) segments before saving entry.")
                let _ = self.normalizeSegments(
                    normalizeType: .target,
                    saveSegments: true,
                    saveToLowLevelRepr: true,
                    saveToState: true
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

        // Determine entry string
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

        // Compute entrySegments array
        var entrySegments: [EntrySegment]? = nil
        var index: Int?
        if let anchor = self.selectionCursor.anchor, anchor.getIndex() != Int(Utils.UNKNOWN) {
            // insert buffer at the correct place based on cursor position
            entrySegments = self.entrySegments
            let anchorIndex = anchor.getIndex()
            entrySegments!.insert(contentsOf: self.entryBuffer, at: anchorIndex)
            index = anchorIndex + transcriptionIndex
        } else {
            // insert buffer at the end of segments
            entrySegments = self.entrySegments + self.entryBuffer
            index = self.entrySegments.count + transcriptionIndex
        }

        var nameType: NLTag?
        var lemma: NLTag?
        var lexicalClass: NLTag?
        var tokenType: NLTag?
        var wordSentimentScore: NLTag?
        var sentenceSentimentScore: NLTag?
        var paragraphSentimentScore: NLTag?
        let range = findSegmentRange(
            segments: entrySegments!,
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
    func findSegmentRange(segments: [EntrySegment], wholeText: String, rangeText: String, index: Int? = nil) -> Range<String.Index>? {
        // figure out how many words are before it
        // compute number of processedChar
        var lowerText: String?
        if let index = index, index >= segments.count && index - segments.count <= 1 {
            // new segment
            lowerText = Entry.getText(segments: segments)
        } else if let index = index, index < segments.count && index > 0 {
            // is in in entrySegments
            let lowerBoundarySegment = segments[index - 1]
            lowerText = Entry.getText(segments: segments, until: lowerBoundarySegment.timeMapping.target.start) // We assume that this is only called when source == target, so using either is fine
        } else if index == nil {
            // is in in entrySegments
            let lowerBoundarySegment = segments[segments.count - 1]
            lowerText = Entry.getText(segments: segments, until: lowerBoundarySegment.timeMapping.target.start) // We assume that this is only called when source == target, so using either is fine
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
        #if DEBUG
        var segmentUIDArr = [String]()
        self.entryBuffer.forEach { segment in segmentUIDArr.append(segment.getUID()) }
        #else
        var segmentUIDArr = [String](repeating: "", count: self.entrySegments.count + self.entryBuffer.count)
        DispatchQueue.concurrentPerform(iterations: self.entrySegments.count + self.entryBuffer.count) { [weak self] index in
            if index < self!.entrySegments.count {
                segmentUIDArr[index] = self!.entrySegments[index].getUID()
            } else {
                segmentUIDArr[index] = self!.entryBuffer[index - self!.entrySegments.count].getUID()
            }
        }
        #endif
        let segmentUIDSet: Set = Set(segmentUIDArr)
        // Use cached version if it exists
        if let cachedText = self.cachedText,
           let cachedSegmentUIDSet = self.cachedSegmentUIDSet,
           let cachedTextArgsSet = self.cachedTextArgsSet,
           segmentUIDSet == cachedSegmentUIDSet &&
            argumentSet == cachedTextArgsSet
        {
            return cachedText
        }
        
        var text = ""
        
        var entrySegments: [EntrySegment]? = nil
        if let selectionCursor = self.selectionCursor, let cachedAnchor = selectionCursor.cachedAnchor, entrySegments == nil && cachedAnchor.getIndex() != Int(Utils.UNKNOWN) {
            entrySegments = self.entrySegments
            
            // insert buffer at the correct place based on cursor position
            if !self.selectionCursor.isUpdatingSelection {
                // We don't want to factor buffer which has speech that has yet to be accepted
                // Would show up in seleectionCursor.selectionText
                
                // By default, insert(contentsOf:, at:) inserts the new elements before the anchor
                // We add one to insert them after the ancher
                let cachedAnchorIndex = cachedAnchor.getIndex()
                entrySegments!.insert(contentsOf: self.entryBuffer, at: cachedAnchorIndex + 1)
            }
        } else if entrySegments == nil {
            entrySegments = self.entrySegments
            
            // insert buffer at the end of segments
            if let selectionCursor = self.selectionCursor, !selectionCursor.isUpdatingSelection {
                // We don't want to factor buffer which has speech that has yet to be accepted
                // Would show up in seleectionCursor.selectionText
                
                entrySegments = self.entrySegments + self.entryBuffer
            }
        }
        
        if let entrySegments = entrySegments, let _ = self.state, entrySegments.count > 0 {
            text = entrySegments.last!.getTextHistory(
                withTemporalSuggestions: self.state.withTemporalSuggestions,
                withPunctuationSuggestions: self.state.withPunctuationSuggestions,
                withFormattingSuggestions: self.state.withFormattingSuggestions,
                strictlyAsWord: self.state.withTextStrictlyAsWords,
                withCapitalization: self.state.withCapitalization,
                withSpacePrefix: true,
                forEcho: forEcho,
                index: entrySegments.count - 1,
                segments: entrySegments,
                segmentsUIDSet: segmentUIDSet,
                from: fromTime,
                until: untilTime
            )
        }
        
        // Remove whitespaces on edges
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // make sure first letter is capitalized
        // not capitalized when we're dealing with expresssions that come from chopped up entriesRange
        if let state = self.state {
            text = state.withCapitalization ? text.capitalizeFirstLetter() : text
        }
        
        // cache work
        if fromTime == CMTime.zero && untilTime == nil && text.count > 0 && segmentUIDSet.count > 0 {
            self.cachedText = text
            self.cachedTextArgsSet = argumentSet
            self.cachedSegmentUIDSet = segmentUIDSet
        }

        return text
    }
    
    public static func getText(
        segments: [EntrySegment],
        from fromTime: CMTime = CMTime.zero,
        until untilTime: CMTime? = nil,
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
            if segment.timeMapping.target.start >= fromTime &&
                (
                    untilTime == nil ||
                    segment.timeMapping.target.end <= untilTime!
                ) &&
                !segment.isVoiceCommandWord() &&
                !segment.isDeleted()
            {
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
        // not capitalized when we're dealing with expresssions that come from chopped up entriesRange
        text = withCapitalization ? text.capitalizeFirstLetter() : text

        return text
    }
    
    // MARK: - Mutating Methods
    
    // Mutates Segments
    func updateSegmentSentencesAndParagraphs(
        segments: [EntrySegment],
        processRange: Range<Int>,
        startTime: CMTime = CMTime.zero,
        startNumber: Int = 0
    ) -> [EntrySegment] {
        print("===== Entry: Update Segment Sentences =====")
        
        // Sentence
        var currentSentenceNumber = startNumber
        var sentenceText = ""
        var sentenceStartTime = startTime
        var sentenceStartSegment = segments[processRange.startIndex]
        // Holds the index of the first segment without a sentence
        var leftStaleSentenceSegmentIndex = processRange.startIndex
        
        // Paragraph
        var currentParagraphNumber = 0
        var paragraphText = ""
        var paragraphStartTime = startTime
        var paragraphStartSegment = segments[processRange.startIndex]
        // Holds the index of the first segment without a paragraph
        var leftStaleParagraphSegmentIndex = processRange.startIndex
        if paragraphStartSegment.getParagraph().number != Int(Utils.UNKNOWN) {
            let priorParagraphSegments = Array(segments[paragraphStartSegment.getParagraph().entryRange.startIndex..<processRange.startIndex])
            currentParagraphNumber = paragraphStartSegment.getParagraph().number
            paragraphText = Entry.getText(segments: priorParagraphSegments)
            paragraphStartTime = paragraphStartSegment.getParagraph().timeRange.start
            let startIndex = paragraphStartSegment.getParagraph().entryRange.startIndex
            paragraphStartSegment = segments[startIndex]
            leftStaleParagraphSegmentIndex = startIndex
        }
        
        // Used by both
        var endTime: CMTime
        var endSegment: EntrySegment
        
        // make sure silences get sentence number of prior.
        print("\tProcess Segments: ", Utils.stringifySegments(segments: Array(segments[processRange])))
        for (index, segment) in segments[processRange].enumerated() {
            if index + 1 == segments[processRange].count {
                // We've reached the end of the entry. Update sentence data
                endSegment = segment
                endTime = segment.timeMapping.target.end
                
                if !segment.isVoiceCommandWord() && !segment.isDeleted() {
                    let segmentText = segment.getText(
                        withTemporalSuggestions: self.state?.withTemporalSuggestions ?? Utils.DEFAULT_WITH_TEMPORAL_SUGGESTIONS,
                        withPunctuationSuggestions: self.state?.withPunctuationSuggestions ?? Utils.DEFAULT_WITH_PUNCTUATION_SUGGESTIONS,
                        withFormattingSuggestions: self.state?.withFormattingSuggestions ?? Utils.DEFAULT_WITH_FORMATTING_SUGGESTIONS,
                        strictlyAsWord: self.state?.withTextStrictlyAsWords ?? Utils.DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS,
                        withCapitalization: self.state?.withCapitalization ?? Utils.DEFAULT_WITH_CAPITALIZATION,
                        withSpacePrefix: true
                    )
                    
                    sentenceText += segmentText
                    paragraphText += segmentText
                }
                
                // Create last sentence
                let sentence = Sentence(
                    number: currentSentenceNumber,
                    text: sentenceText.trimmingCharacters(in: .whitespacesAndNewlines),
                    timeRange: CMTimeRangeFromTimeToTime(
                        start: sentenceStartTime,
                        end: endTime
                    ),
                    entryRange: sentenceStartSegment.getIndex()..<endSegment.getIndex() + 1
                )
                
                // Clear sentence
                sentenceText = ""
                print("\tNew sentence: ", sentence)
                
                // Create last paragraph
                let paragraph = Paragraph(
                    number: currentParagraphNumber,
                    text: paragraphText.trimmingCharacters(in: .whitespacesAndNewlines),
                    timeRange: CMTimeRangeFromTimeToTime(
                        start: paragraphStartTime,
                        end: endTime
                    ),
                    entryRange: paragraphStartSegment.getIndex()..<endSegment.getIndex() + 1
                )
                
                // Clear paragraph
                paragraphText = ""
                print("\tNew paragraph: ", paragraph)
                
                // Add sentence to every segment ***including*** this one
                for i in leftStaleSentenceSegmentIndex...(processRange.startIndex + index) {
                    segments[i].setSentence(sentence: sentence)
                }
                
                // Add paragraph to every segment ***including*** this one
                for i in leftStaleParagraphSegmentIndex...(processRange.startIndex + index) {
                    segments[i].setParagraph(paragraph: paragraph)
                }
            } else if segment.isVoiceCommandWord() || segment.isDeleted() {
                // Don't add word to sentenceText
                // We don't want these in Sentence class object instances
            } else if segment.isSentenceTerminator() {
                // We've hit a sentence boundary. Update sentences
                // Update sentence data
                endSegment = segment
                endTime = segment.timeMapping.target.start
                let segmentText = segment.getText(
                    withTemporalSuggestions: self.state?.withTemporalSuggestions ?? Utils.DEFAULT_WITH_TEMPORAL_SUGGESTIONS,
                    withPunctuationSuggestions: self.state?.withPunctuationSuggestions ?? Utils.DEFAULT_WITH_PUNCTUATION_SUGGESTIONS,
                    withFormattingSuggestions: self.state?.withFormattingSuggestions ?? Utils.DEFAULT_WITH_FORMATTING_SUGGESTIONS,
                    strictlyAsWord: self.state?.withTextStrictlyAsWords ?? Utils.DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS,
                    withCapitalization: self.state?.withCapitalization ?? Utils.DEFAULT_WITH_CAPITALIZATION,
                    withSpacePrefix: true
                )
                
                sentenceText += segmentText
                paragraphText += segmentText

                let sentence = Sentence(
                    number: currentSentenceNumber,
                    text: sentenceText.trimmingCharacters(in: .whitespacesAndNewlines),
                    timeRange: CMTimeRangeFromTimeToTime(
                        start: sentenceStartTime,
                        end: endTime
                    ),
                    entryRange: sentenceStartSegment.getIndex()..<endSegment.getIndex() + 1
                )
                
                currentSentenceNumber += 1
                if index + 1 < segments[processRange].count {
                    let nextSegment = segments[index + 1]
                    sentenceStartSegment = nextSegment
                    sentenceStartTime = nextSegment.timeMapping.target.start
                }
                
                // Clear sentence
                sentenceText = ""
                print("\tNew sentence: ", sentence)
                
                // Add sentence to every segment before this one
                for i in leftStaleSentenceSegmentIndex..<(processRange.startIndex + index) {
                    segments[i].setSentence(sentence: sentence)
                }
                leftStaleSentenceSegmentIndex = processRange.startIndex + index
                
                if segment.isParagraphTerminator() {
                    // This is the end of a paragraph too
                    let paragraph = Paragraph(
                        number: currentParagraphNumber,
                        text: paragraphText.trimmingCharacters(in: .whitespacesAndNewlines),
                        timeRange: CMTimeRangeFromTimeToTime(
                            start: paragraphStartTime,
                            end: endTime
                        ),
                        entryRange: paragraphStartSegment.getIndex()..<endSegment.getIndex() + 1
                    )
                    currentParagraphNumber += 1
                    if index + 1 < segments[processRange].count {
                        let nextSegment = segments[index + 1]
                        paragraphStartSegment = nextSegment
                        paragraphStartTime = nextSegment.timeMapping.target.start
                    }
                    // Clear paragraph
                    paragraphText = ""
                    print("\tNew paragraph: ", paragraph)
                    
                    // Add sentence to every segment before this one
                    for i in leftStaleParagraphSegmentIndex..<(processRange.startIndex + index) {
                        segments[i].setParagraph(paragraph: paragraph)
                    }
                    leftStaleParagraphSegmentIndex = processRange.startIndex + index
                }
            } else if segment.isActive() {
                let segmentText = segment.getText(
                    withTemporalSuggestions: self.state?.withTemporalSuggestions ?? Utils.DEFAULT_WITH_TEMPORAL_SUGGESTIONS,
                    withPunctuationSuggestions: self.state?.withPunctuationSuggestions ?? Utils.DEFAULT_WITH_PUNCTUATION_SUGGESTIONS,
                    withFormattingSuggestions: self.state?.withFormattingSuggestions ?? Utils.DEFAULT_WITH_FORMATTING_SUGGESTIONS,
                    strictlyAsWord: self.state?.withTextStrictlyAsWords ?? Utils.DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS,
                    withCapitalization: self.state?.withCapitalization ?? Utils.DEFAULT_WITH_CAPITALIZATION,
                    withSpacePrefix: true
                )
                
                sentenceText += segmentText
                paragraphText += segmentText
            } else {
                // Silences that are not long enough to be sentence terminators go here
            }
        }
        
        return segments
    }
    
    // time must be at a segment boundary to make everything work correctly
    // assumes buffer is empty
    //
    // We make assumption that if we're adding segments at end of entry
    // the times are correctly calculated (we bypass normalization)
    //
    // We make this assumption to overcome O(n) complexity when adding to end of entry
    // This causes severe lag.
    // There is no way currently to overcome this if segments are insert into existing segments
    func insertPassage(segments: [EntrySegment], at time: CMTime, saveToState: Bool = true) {
        guard let _ = self.state else {
            print("\t[Error] Override insertPassage method call because we attempted to modify entry without state.")
            return
        }
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        print("===== Entry: Insert Passage =====")
//        guard self.entryBuffer.count == 0 else {
//            print("\t[Error] There was a problem inserting passage. Buffer was not empty")
//            return
//        }
        print("\tMerging argument segments into committed segments...")
        var updatedSegments = [EntrySegment]()
        // Add to state clips
        print("\tUpdating entry references, and sourcing all unique segment clips...")
        var segmentClips = [String]()
        for segment in segments {
            // Handle segment clips
            segmentClips.append(segment.getClipUID())
            // Set entry
            segment.setEntry(entry: self)
        }
        
        let uniqueSegmentClips = Set(segmentClips)
        
        if uniqueSegmentClips.count > 0 {
            print("\tAssociating all unique clips with entry in state...")
            for uid in uniqueSegmentClips {
                self.state.setClip(clipUID: uid, entryUID: self.uid)
            }
        }
        
        print("\tPassage: ", Utils.stringifySegments(segments: segments))
        
        var insertingAtEndOfEntry = false
        var lastSentenceDetails: Sentence?
        if self.entrySegments.count > 0 {
            print("\tPlace within existing \(self.entrySegments.count) segments...")
            if let lastSegment = self.entrySegments.last, lastSegment.timeMapping.target.end == time {
                print("\tSegments are being added to end of entry...")
                insertingAtEndOfEntry = true
                lastSentenceDetails = lastSegment.getSentence()
                updatedSegments = self.entrySegments + segments
            } else {
                print("\tSearch for insert segment...")
                let insertSegment = Utils.binarySearch(
                    in: self.entrySegments,
                    isLower: { segment in
                        return segment.timeMapping.target.end < time
                    },
                    isHigher: { segment in
                        return segment.timeMapping.target.start > time
                    }
                )
                
                if let insertSegment = insertSegment {
                    let insertIndex = insertSegment.getIndex() + 1
                    print("\tLocated insert segment at index: ", insertIndex)
                    print("\tStitching new segments together...")
                    updatedSegments = Array(self.entrySegments[0..<insertIndex]) + segments + self.entrySegments[insertIndex..<self.entrySegments.count]
                } else {
                    print("\t[Error] There was a problem locating insert segment.")
                }
            }
        } else {
            print("\tInserted segments are the first in entry.")
            // we do not have segments yet
            // set passage as new segments
            updatedSegments = segments
        }
        
        if insertingAtEndOfEntry {
            print("\tWe're inserting segments to the end of entry. We'll assume timing is shifted to assume they occur at the end of the entry to overcome O(n) when adding to note...")
            print("\tBypass normalization...")
            print("\tUpdate sentences...")
            // Compute segment sentences
            if let lastSentenceDetails = lastSentenceDetails {
                let insertRange = (updatedSegments.count - segments.count)..<updatedSegments.count
                let insertedSegments = Array(updatedSegments[insertRange])
                
                print("\tSearch for any segments that might trigger punctuation suggestion and reset sentence terminator and text...")
                DispatchQueue.concurrentPerform(iterations: insertedSegments.count) { index in
                    let segment = insertedSegments[index]
                    segment.handleMutation()
                    segment.runNotificationSearch()
                }
                
                // We don't know if we ended on a correct sentence
                // So we include last sentence in here as well
                // Reset cache values for each inserted segment to determine if sentence terminator
                //
                // We perform sentence/paragraph update here so we avoid having to do it over all segments
                let segmentsWithUpdatedSentencesAndParagraphs = self.updateSegmentSentencesAndParagraphs(
                    segments: updatedSegments,
                    processRange: lastSentenceDetails.entryRange.startIndex..<updatedSegments.count,
                    startTime: lastSentenceDetails.timeRange.start,
                    startNumber: lastSentenceDetails.number
                )

                self.setSegments(
                    segments: segmentsWithUpdatedSentencesAndParagraphs,
                    replaceEntryDetails: false,
                    saveToLowLevelRepr: true,
                    saveToState: saveToState,
                    computeSentencesAndParagraphs: false
                )
                
                // Check rep invariant
                self.handleMutation()
            } else {
                print("\t[Error] There was a problem updating inserted segments sentence/paragraph metadata, so we were unable to save segments")
            }
        } else if self.entrySegments.count == 0 {
            print("\tCleansing segments...")
            let cleansedSegments = Utils.cleanseSegments(
                segments: updatedSegments
            )

            print("\tNormalizing segments...")
            let _ = self.normalizeSegments(
                segments: cleansedSegments,
                normalizeType: .target,
                replaceEntryDetails: true,
                saveSegments: true,
                saveToLowLevelRepr: true,
                saveToState: saveToState
            )
        } else {
            print("\tCleansing segments...")
            let cleansedSegments = Utils.cleanseSegments(
                segments: updatedSegments
            )

            print("\tNormalizing segments...")
            let _ = self.normalizeSegments(
                segments: cleansedSegments,
                normalizeType: .target,
                replaceEntryDetails: true,
                saveSegments: true,
                saveToLowLevelRepr: true,
                saveToState: saveToState
            )
            
            // Check rep invariant
            self.handleMutation()
        }

        if !self.selectionCursor.isUpdatingSelection {
            self.handleOnSpeechUpdate(text: self.getText())
        }
        
        print("\tSuccessfully inserted passage into entry!")
    }
    
    // time must be at a segment boundary to make everything work correctly
    // assumes buffer is empty
    func removePassage(range: CMTimeRange, saveToState: Bool = true) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override removePassage method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Remove Passage =====")
//        guard self.entryBuffer.count == 0 else {
//            print("\t[Error] There was a problem removing passage. Buffer was not empty")
//            return
//        }
        print("\tFiltering out passage segments...")
        let beforeTime = range.start
        let afterTime = range.end

        var updateAnchor = false
        var updateFocus = false
        var updateCachedAnchor = false
        
        var removeRangeLeftSegment: EntrySegment?
        if let firstSegment = self.entrySegments.first, beforeTime == CMTime.zero {
            print("\tBefore time in zero. We select first segment...")
            removeRangeLeftSegment = firstSegment
        } else {
            print("\tSearching for index of left segment of removal segments...")
            removeRangeLeftSegment = Utils.binarySearch(
                in: self.entrySegments,
                isLower: { segment in
                    return segment.timeMapping.target.end < beforeTime
                },
                isHigher: { segment in
                    return segment.timeMapping.target.start > beforeTime
                }
            )
        }
        
        var removeRangeRightSegment: EntrySegment?
        if let lastSegment = self.entrySegments.last, afterTime == lastSegment.timeMapping.target.end {
            print("\tAfter time is the same as last entry segment. We select it...")
            removeRangeRightSegment = lastSegment
        } else {
            print("\tSearching for index of right segment of removal segments...")
            removeRangeRightSegment = Utils.binarySearch(
                in: self.entrySegments,
                isLower: { segment in
                    return segment.timeMapping.target.end < afterTime
                },
                isHigher: { segment in
                    return segment.timeMapping.target.start > afterTime
                }
            )
        }
        
        if let removeRangeLeftSegment = removeRangeLeftSegment,
           let removeRangeRightSegment = removeRangeRightSegment
        {
            print("\tWe located left and right removal segments. Removal passage is mid-entry...")
            let leftIndex = removeRangeLeftSegment.getIndex()
            let rightIndex = removeRangeRightSegment.getIndex()
            print("\tLocated left segment at index: ", leftIndex)
            print("\tLocated right segment at index: ", rightIndex)
            
            // Removal Segments
            print("\tFlipping delete flag for all segments within removal range...")
            DispatchQueue.concurrentPerform(iterations: removeRangeRightSegment.getIndex() - removeRangeLeftSegment.getIndex() + 1) { [weak self] index in
                let segment = self!.entrySegments[removeRangeLeftSegment.getIndex() + index]
                segment.setIsDeleted(isDeleted: true)
                print("\tFlip deleted flag: ", segment.getText())
                
                // Check if we need to update selection anchor
                if let anchor = self?.selectionCursor.anchor, segment.getUID() == anchor.getUID() {
                    print("\tSelection cursor anchor requires updating...")
                    updateAnchor = true
                    // Clear anchor so we get no errors related to selectionRange
                    // When we update anchor when we have a selection, focus will be outdate and cause error
                    self?.selectionCursor.setAnchorCaret()
                }
                
                // Check if we need to update selection focus
                if let focus = self?.selectionCursor.focus, segment.getUID() == focus.getUID() {
                    print("\tSelection cursor focus requires updating...")
                    updateFocus = true
                    // Clear focus so we get no errors related to selectionRange
                    // When we update focus when we have a selection, anchor will be outdate and cause error
                    self?.selectionCursor.setFocusCaret()
                }
                
                // Check if we need to update selection cached anchor
                if let cachedAnchor = self?.selectionCursor.cachedAnchor, segment.getUID() == cachedAnchor.getUID() {
                    print("\tSelection cursor cached anchor requires updating...")
                    updateCachedAnchor = true
                    // Clear cached anchor
                    self?.selectionCursor.setCachedAnchorCaret()
                }
            }
            
            // After Segments
            DispatchQueue.concurrentPerform(iterations: self.entrySegments.count - rightIndex) { [weak self] index in
                print("\tReset text history: ", self?.entrySegments[rightIndex + index].getText() ?? "nil", self?.entrySegments[rightIndex + index].getIndex() ?? "nil")
                self?.entrySegments[rightIndex + index].handleMutation()
            }
        } else if let _ = removeRangeLeftSegment, removeRangeRightSegment == nil {
            print("\t[Error] We only located left removal segment even though we predicted to find left and right removal segments for any segment in entry.")
        } else if let _ = removeRangeRightSegment, removeRangeLeftSegment == nil {
            print("\t[Error] We only located right removal segment even though we predicted to find left and right removal segments for any segment in entry.")
        }
        
        print("\tWe bypass cleansing and normalizing segments because no segments we're removed. We only mutate properties")
        
        var segment: EntrySegment?
        if updateAnchor || updateFocus || updateCachedAnchor {
            print("\tSearching for replacement segment...")
            segment = Utils.getSegment(
                forTrackTime: CMTimeMake(
                    value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (max(0, beforeTime.seconds - Utils.TEMPORAL_DELTA))),
                    timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                ),
                entry: self
            )
            
            while segment != nil && segment!.timeMapping.target.start > CMTime.zero && (segment!.isVoiceCommandWord() || segment!.isDeleted() || segment!.isSilence()) {
                let startTime = segment!.timeMapping.target.start
                segment = Utils.getSegment(
                    forTrackTime: CMTimeMake(
                        value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (max(0, startTime.seconds - Utils.TEMPORAL_DELTA))),
                        timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                    ),
                    entry: self
                )
            }
        }
        
        if let segment = segment, updateAnchor && segment.isActive() {
            print("\tUpdating selection cursor anchor..")
            self.selectionCursor.setAnchorCaret(caret: Caret(index: segment.getIndex(), trackType: .committed))
        }
        
        if let segment = segment, updateFocus && segment.isActive() {
            print("\tUpdating selection cursor focus...")
            self.selectionCursor.setFocusCaret(caret: Caret(index: segment.getIndex(), trackType: .committed))
        }
        
        if let segment = segment, updateCachedAnchor && segment.isActive() {
            print("\tUpdating selection cursor cached anchor...")
            self.selectionCursor.setCachedAnchorCaret(caret: Caret(index: segment.getIndex(), trackType: .committed))
        }
        
        // we don't change text view in this mode, so text won't be available
        if !self.selectionCursor.isUpdatingSelection {
            self.handleOnSpeechUpdate(text: self.getText())
        }
        
        // Process mutation
        self.handleMutation()

        print("\tSuccessfully removed passage from entry!")
    }
    
    func updatePassage(segments: [EntrySegment], range: CMTimeRange) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override updatePassage method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Update Passage =====")
        print("\tRemoving current passsage from entry...")
        self.removePassage(range: range, saveToState: false)
        print("\tAdding new passage to entry...")
        let _ = self.insertPassage(
            segments: segments,
            at: range.start,
            saveToState: true
        )
        print("\tSuccessfully updated passage in entry!")
    }

    func handleTransformation(
        type: TransformationType,
        passageText: String,
        value: Float? = nil,
        textRange: NSRange,
        entryRange: ClosedRange<Int>
    ) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override handleTransformation method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Handle Transformation =====")
        // Create transformation
        print("\tCreate initial transformation...")
        
        // Collect segment uids
        // Set new value
        var uids: [String: Int] = [:]
        for segment in self.entrySegments[entryRange] {
            uids[segment.getUID()] = segment.getIndex()
            
            // Set playback rate
            if let value = value, type == .playbackRate {
                segment.setRate(rate: value)
            }
        }

        let transformation = EntryTransformation(
            type: type,
            uids: uids,
            text: passageText,
            value: value,
            textRange: textRange,
            entryRange: entryRange
        )
        
        // Search for existing transformations
        print("\tSearch for existing overlapping transformation...")
        var overlapIndex: Int?
        for (index, trans) in self.transformations.enumerated() {
            if trans.type == type && trans.entryRange.overlaps(entryRange) {
                overlapIndex = index
                print("\tFound existing overlapping transformation at self.transformations index: ", index)
                break
            }
        }
        
        var transformations = [EntryTransformation]()
        
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
            
            if overlapTransformation.entryRange.contains(transformation.entryRange.lowerBound) &&
                overlapTransformation.entryRange.contains(transformation.entryRange.upperBound) &&
                overlapTransformation.entryRange.lowerBound < transformation.entryRange.lowerBound &&
                overlapTransformation.entryRange.upperBound > transformation.entryRange.upperBound
            {
                // transformation is strictly within the overlap transformation
                // e.g. [2, 3, 4, 5] and [3, 4]
                print("\tTransformation is strictly within the overlap transformation: [2, 3, 4, 5] and [3, 4]")
                
                // Clear transformations array
                print("\tClear initialized transformations array...")
                transformations = []
                
                print("\tSplit transformation into three sections: bottom, middle, top...")
                // ==== Create bottom transformation
                
                let bottomLowerSegment = self.entrySegments[overlapTransformation.entryRange.lowerBound]
                var bottomUpperSegmentIndex = transformation.entryRange.lowerBound - 1
                var bottomUpperSegment = self.entrySegments[bottomUpperSegmentIndex]
                while (bottomUpperSegment.isVoiceCommandWord() || bottomUpperSegment.isSilence() || bottomUpperSegment.isDeleted()) && bottomUpperSegmentIndex > overlapTransformation.entryRange.lowerBound {
                    // must not be a silence or voice command word or deleted
                    bottomUpperSegmentIndex -= 1
                    bottomUpperSegment = self.entrySegments[bottomUpperSegmentIndex]
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
                let bottomEntryRange = bottomLowerSegment.getIndex()...bottomUpperSegment.getIndex()
                print("\tCompute bottom section entryRange: ", bottomEntryRange)
                
                // Collect segment uids
                var bottomUIDs: [String: Int] = [:]
                for segment in self.entrySegments[bottomEntryRange] {
                    bottomUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let bottomTransform = EntryTransformation(
                    type: type,
                    uids: bottomUIDs,
                    text: bottomText,
                    value: bottomValue,
                    textRange: bottomTextRange,
                    entryRange: bottomEntryRange
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
                
                let middleLowerSegment = self.entrySegments[transformation.entryRange.lowerBound]
                let middleUpperSegment = self.entrySegments[transformation.entryRange.upperBound]
                
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
                let middleEntryRange = middleLowerSegment.getIndex()...middleUpperSegment.getIndex()
                print("\tCompute middle section entryRange: ", middleEntryRange)
                
                // Collect segment uids
                var middleUIDs: [String: Int] = [:]
                for segment in self.entrySegments[middleEntryRange] {
                    middleUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let middleTransform = EntryTransformation(
                    type: type,
                    uids: middleUIDs,
                    text: middleText,
                    value: middleValue,
                    textRange: middleTextRange,
                    entryRange: middleEntryRange
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
                
                let topUpperSegment = self.entrySegments[overlapTransformation.entryRange.upperBound]
                var topLowerSegmentIndex = transformation.entryRange.upperBound + 1
                var topLowerSegment = self.entrySegments[topLowerSegmentIndex]
                while (topLowerSegment.isVoiceCommandWord() || topLowerSegment.isSilence() || topLowerSegment.isDeleted()) && topLowerSegmentIndex < overlapTransformation.entryRange.upperBound {
                    // must not be a silence or voice command word or is deleted
                    topLowerSegmentIndex += 1
                    topLowerSegment = self.entrySegments[topLowerSegmentIndex]
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
                let topEntryRange = topLowerSegment.getIndex()...topUpperSegment.getIndex()
                print("\tCompute top section entryRange: ", topEntryRange)
                
                // Collect segment uids
                var topUIDs: [String: Int] = [:]
                for segment in self.entrySegments[topEntryRange] {
                    topUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let topTransform = EntryTransformation(
                    type: type,
                    uids: topUIDs,
                    text: topText,
                    value: topValue,
                    textRange: topTextRange,
                    entryRange: topEntryRange
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
            } else if overlapTransformation.entryRange.contains(transformation.entryRange.lowerBound) &&
                overlapTransformation.entryRange.contains(transformation.entryRange.upperBound) &&
                overlapTransformation.entryRange.lowerBound == transformation.entryRange.lowerBound &&
                overlapTransformation.entryRange.upperBound == transformation.entryRange.upperBound {
                // transformation is the same as overlap transformation
                // e.g. [2, 3, 4, 5] and [2, 3, 4, 5]
                print("\tTransformation is the same as overlap transformation: [2, 3, 4, 5] and [2, 3, 4, 5]. Do nothing.")
                // Do nothing
            } else if transformation.entryRange.contains(overlapTransformation.entryRange.lowerBound) &&
                    transformation.entryRange.contains(overlapTransformation.entryRange.upperBound) &&
                    transformation.entryRange.lowerBound < overlapTransformation.entryRange.lowerBound &&
                    transformation.entryRange.upperBound > overlapTransformation.entryRange.upperBound {
                    // overlap transformation is strictly within the transformation
                    // e.g. [3, 4] and [2, 3, 4, 5]
                    print("\tOverlap transformation is strictly within the transformation: [3, 4] and [2, 3, 4, 5].")
                    // Do nothing
            } else if overlapTransformation.entryRange.contains(transformation.entryRange.lowerBound) &&
                (
                    !overlapTransformation.entryRange.contains(transformation.entryRange.upperBound) ||
                    (overlapTransformation.entryRange.contains(transformation.entryRange.upperBound) && transformation.entryRange.count == 1)
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
                
                let bottomLowerSegment = self.entrySegments[overlapTransformation.entryRange.lowerBound]
                var bottomUpperSegmentIndex = transformation.entryRange.lowerBound - 1
                var bottomUpperSegment = self.entrySegments[bottomUpperSegmentIndex]
                while (bottomUpperSegment.isVoiceCommandWord() || bottomUpperSegment.isSilence() || bottomUpperSegment.isDeleted()) && bottomUpperSegmentIndex > overlapTransformation.entryRange.lowerBound {
                    // must not be a silence or voice command word
                    bottomUpperSegmentIndex -= 1
                    bottomUpperSegment = self.entrySegments[bottomUpperSegmentIndex]
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
                let bottomEntryRange = bottomLowerSegment.getIndex()...bottomUpperSegment.getIndex()
                print("\tCompute bottom section entryRange: ", bottomEntryRange)
                
                // Collect segment uids
                var bottomUIDs: [String: Int] = [:]
                for segment in self.entrySegments[bottomEntryRange] {
                    bottomUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let bottomTransform = EntryTransformation(
                    type: type,
                    uids: bottomUIDs,
                    text: bottomText,
                    value: bottomValue,
                    textRange: bottomTextRange,
                    entryRange: bottomEntryRange
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

                let topUpperSegment = self.entrySegments[transformation.entryRange.upperBound]
                let topLowerSegment = self.entrySegments[transformation.entryRange.lowerBound]
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
                let topEntryRange = topLowerSegment.getIndex()...topUpperSegment.getIndex()
                print("\tCompute top section entryRange: ", topEntryRange)

                // Collect segment uids
                var topUIDs: [String: Int] = [:]
                for segment in self.entrySegments[topEntryRange] {
                    topUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let topTransform = EntryTransformation(
                    type: type,
                    uids: topUIDs,
                    text: topText,
                    value: topValue,
                    textRange: topTextRange,
                    entryRange: topEntryRange
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
                        !overlapTransformation.entryRange.contains(transformation.entryRange.lowerBound) ||
                        (overlapTransformation.entryRange.contains(transformation.entryRange.lowerBound) && transformation.entryRange.count == 1)
                    ) && overlapTransformation.entryRange.contains(transformation.entryRange.upperBound) {
                // transformation overlaps at the upper end only
                // e.g. [2, 3, 4, 5] and [5, 6, 7]
                print("\tTransformation overlaps at the upper end only: [2, 3, 4, 5] and [5, 6, 7]")
                
                // Clear transformations array
                print("\tClear initialized transformations array...")
                transformations = []
                
                print("\tSplit transformation into two sections: bottom, top...")
                
                // ==== Create bottom transformation
                
                let bottomLowerSegment = self.entrySegments[overlapTransformation.entryRange.lowerBound]
                var bottomUpperSegmentIndex = transformation.entryRange.lowerBound - 1
                var bottomUpperSegment = self.entrySegments[bottomUpperSegmentIndex]
                while (bottomUpperSegment.isVoiceCommandWord() || bottomUpperSegment.isSilence() || bottomUpperSegment.isDeleted()) && bottomUpperSegmentIndex > overlapTransformation.entryRange.lowerBound {
                    // must not be a silence or voice command word
                    bottomUpperSegmentIndex -= 1
                    bottomUpperSegment = self.entrySegments[bottomUpperSegmentIndex]
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
                let bottomEntryRange = bottomLowerSegment.getIndex()...bottomUpperSegment.getIndex()
                print("\tCompute bottom section entryRange: ", bottomEntryRange)
                
                // Collect segment uids
                var bottomUIDs: [String: Int] = [:]
                for segment in self.entrySegments[bottomEntryRange] {
                    bottomUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let bottomTransform = EntryTransformation(
                    type: type,
                    uids: bottomUIDs,
                    text: bottomText,
                    value: bottomValue,
                    textRange: bottomTextRange,
                    entryRange: bottomEntryRange
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
                
                let topLowerSegment = self.entrySegments[transformation.entryRange.lowerBound]
                let topUpperSegment = self.entrySegments[transformation.entryRange.upperBound]
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
                let topEntryRange = topLowerSegment.getIndex()...topUpperSegment.getIndex()
                print("\tCompute top section entryRange: ", topEntryRange)
                
                // Collect segment uids
                var topUIDs: [String: Int] = [:]
                for segment in self.entrySegments[topEntryRange] {
                    topUIDs[segment.getUID()] = segment.getIndex()
                }
                
                let topTransform = EntryTransformation(
                    type: type,
                    uids: topUIDs,
                    text: topText,
                    value: topValue,
                    textRange: topTextRange,
                    entryRange: topEntryRange
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
            
            // Remove overlap transformation from entry.transformations property
            self.transformations.remove(at: overlapIndex)
            print ("\tRemove overlap transformation from stored transformations at index: ", overlapIndex)
        }
        
        // Add transformation to transformations array
        print("\tAdd computed transformations to stored transformations...")
        self.transformations.append(contentsOf: transformations)
        
        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    func walk(segments: [EntrySegment]? = nil, runOverride: Bool = false, onStartHandler: (() -> Void)? = nil) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override walk method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: \(runOverride ? "Run" : "Walk") =====")
        if (self.entryManager.isWalkingEntry && !self.entryManager.pausedWalkingEntry && !runOverride) || (segments != nil && segments!.count == 0) || (segments == nil && self.entrySegments.count == 0) {
            var text: String
            if self.entryManager.isWalkingEntry && !self.entryManager.pausedWalkingEntry && !runOverride {
                text = "Already walking passage."
            } else {
                text = "Entry is empty"
            }
            
            self.notifications.executeError(
                text: text
            )
            
            return
        }
        
        // Get walking segments
        // if they are already set, it means we're starting from an existing walk
        // we likely have gone from walking to running
        if let segments = segments, let firstSegment = segments.first, let lastSegment = segments.last, self.entryManager.walkingRange == nil {
            print("\tWe were passed segments. Use segments as walking range: \(firstSegment.getIndex())..<\(lastSegment.getIndex() + 1)")
            // Set walking range
            self.entryManager.setWalkingRange(range: firstSegment.getIndex()..<lastSegment.getIndex() + 1)
            
            // Set walking index
            self.entryManager.setWalkingIndex(index: 0)
        } else if self.entryManager.walkingRange == nil {
            print("\tWe weren't passed segments. Use entry segments as walking range: 0..<\(self.entrySegments.count)")
            // Set walking range
            self.entryManager.setWalkingRange(range: 0..<self.entrySegments.count)
            
            // Set walking index
            self.entryManager.setWalkingIndex(index: 0)
        } else if let anchor = self.selectionCursor.anchor, let walkingRange = self.entryManager.walkingRange, self.entryManager.pausedWalkingEntry || self.entryManager.pausedRunningEntry {
            print("\tWe had existing walking range. We likely updated selection. Set new walking index: ", anchor.getIndex() - self.entrySegments[walkingRange].first!.getIndex())
            // We likely just updated walk segment
            // We must handle new index placement
            // We must handle segment expanding to multiple words
            // Decision: We keep selection on the first segment only
            self.entryManager.setWalkingIndex(index: anchor.getIndex() - self.entrySegments[walkingRange].first!.getIndex())
        }
        
        guard let walkingRange = self.entryManager.walkingRange else {
            self.entryManager.setWalkingIndex(index: 0)
            self.entryManager.setWalkingRange()
            self.notifications.executeError(
                text: "Unable to start \(runOverride ? "running" : "walking").",
                handler: onStartHandler
            )
            return
        }
        
        let currentSegment: EntrySegment? = Array(self.entrySegments[walkingRange])[self.entryManager.walkingIndex]
        var currentSegmentIndex: Int? = self.entryManager.walkingIndex
        if let segment = currentSegment, let walkingRange = self.entryManager.walkingRange, !segment.isValidWord() {
            print("\tCurrent walking segment in not a valid word. Find next valid word...")
            currentSegmentIndex = Utils.getSegmentIndex(
                segment: segment,
                segments: Array(self.entrySegments[walkingRange]),
                type: .next,
                isWord: true
            )
        } else if let segment = currentSegment, segment.isValidWord() {
            print("\tCurrent walking segment is fine. Proceed as usual...")
        }
        
        // when current segment is != nil, it means the first segment
        // was valid and we didn't need to update walking index
        //
        // when current segment index != self.entryManager.walkingIndex it means we had to
        // update walking index
        if let currentSegmentIndex = currentSegmentIndex {
            // Updating walking index
            if currentSegmentIndex != self.entryManager.walkingIndex {
                print("\tIndex of current segment did not match the walking index. Set walking idex to current segment index...")
                self.entryManager.setWalkingIndex(index: currentSegmentIndex)
            }

            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "\(runOverride ? "Run" : "Walk") activated!",
                withHaptics: true
            )
            
            // Activate isWalkingEntry if we don't have a run override
            self.entryManager.setIsWalkingEntry(to: !runOverride)
            self.entryManager.setPausedWalkingEntry(to: false)
            self.entryManager.setPausedRunningEntry(to: false)
            
            self.selectionCursor.setSelection(
                anchorCaret: Caret(index: self.entryManager.walkingRange!.startIndex + currentSegmentIndex, trackType: .committed),
                focusCaret: Caret(index: self.entryManager.walkingRange!.startIndex + currentSegmentIndex, trackType: .committed),
                scale: .word
            )
            
            // start looping walk
            if AVAudioSession.isHeadphonesConnected {
                let currentSegment = Array(self.entrySegments[walkingRange])[currentSegmentIndex]
                let makeStep = {
                    self.speechPlayer.play(segments: [currentSegment])
                    
                    // Play echo
                    let echoDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_ECHO_DELAY_DURATION * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: false) { [weak self] timer in
                        self?.speechSynthesis.startEcho(segments: [currentSegment])
                    }
                    
                    self.entryManager.setEchoDelayTimer(timer: echoDelayTimer)
                }
                
                let walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let segmentDuration: TimeInterval = currentSegment.timeMapping.target.duration.seconds
                    let stepDuration: TimeInterval = max(segmentDuration + (segmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + segmentDuration + Utils.WALKING_LOOP_BUFFER)
                    let walkingTimer = Timer.scheduledTimer(withTimeInterval: max(stepDuration, Utils.WALKING_PERIOD_DURATION) * TimeInterval( 1 / self!.speechPlayer.playbackRate), repeats: true) { timer in
                        makeStep()
                    }
                    
                    self?.entryManager.setWalkingTimer(timer: walkingTimer)
                }
                
                self.entryManager.setWalkLoopDelayTimer(timer: walkLoopDelayTimer)
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
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override walkToPreviousSegment method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: \(runOverride ? "Run" : "Walk") To Previous Segment =====")
        if !self.entryManager.isWalkingEntry && !self.entryManager.isRunningEntry {
            var text: String
            text = "\(runOverride ? "Running" : "Walking") not active."
            self.notifications.executeError(
                text: text
            )
            return
        }
        
        guard let walkingRange = self.entryManager.walkingRange else {
            self.notifications.executeError(
                text: "Unable to \(runOverride ? "run to" : "walk to") previous.",
                handler: handler
            )
            self.exitWalk()
            return
        }
        
        let currentSegment: EntrySegment? = Array(self.entrySegments[walkingRange])[self.entryManager.walkingIndex]
        var currentSegmentIndex: Int? = nil
        if let segment = currentSegment, let walkingRange = self.entryManager.walkingRange {
            print("\tCurrent walking segment in not a valid word. Find previous valid word...")
            currentSegmentIndex = Utils.getSegmentIndex(
                segment: segment,
                segments: Array(self.entrySegments[walkingRange]),
                type: .previous,
                isWord: true
            )
        }
        
        if let currentSegmentIndex = currentSegmentIndex, self.entryManager.walkingIndex != currentSegmentIndex {
            
            // Updating walking index
            self.entryManager.setWalkingIndex(index: currentSegmentIndex)

            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Previous word",
                withHaptics: true
            )
            
            // Stop previous walking loop
            self.entryManager.setWalkingTimer()
            
            // Stop previous walking loop delay
            self.entryManager.setWalkLoopDelayTimer()

            // Stop previous echo delay
            self.entryManager.setEchoDelayTimer()
            
            // Stop playback
            if self.speechPlayer.isPlayingEntry {
                self.speechPlayer.stop(withFeedback: false)
            }
            // Stop echo
            if self.speechSynthesis.isPlayingEcho {
                self.speechSynthesis.stopEcho(withFeedback: false)
            }
            
            self.selectionCursor.setSelection(
                anchorCaret: Caret(index: self.entryManager.walkingRange!.startIndex + currentSegmentIndex, trackType: .committed),
                focusCaret: Caret(index: self.entryManager.walkingRange!.startIndex + currentSegmentIndex, trackType: .committed),
                scale: .word
            )
            
            // start looping walk
            if AVAudioSession.isHeadphonesConnected { // play speech
                let currentSegment = Array(self.entrySegments[walkingRange])[currentSegmentIndex]
                let makeStep = {
                    self.speechPlayer.play(segments: [currentSegment])
                    
                    // Play echo
                    let echoDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_ECHO_DELAY_DURATION * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: false) { [weak self] timer in
                        self?.speechSynthesis.startEcho(segments: [currentSegment])
                    }
                    
                    self.entryManager.setEchoDelayTimer(timer: echoDelayTimer)
                }
                
                let walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let segmentDuration: TimeInterval = currentSegment.timeMapping.target.duration.seconds
                    let stepDuration: TimeInterval = max(segmentDuration + (segmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + segmentDuration + Utils.WALKING_LOOP_BUFFER)
                    let walkingTimer = Timer.scheduledTimer(withTimeInterval: max(stepDuration, Utils.WALKING_PERIOD_DURATION) * TimeInterval( 1 / self!.speechPlayer.playbackRate), repeats: true) { timer in
                        makeStep()
                    }
                    
                    self?.entryManager.setWalkingTimer(timer: walkingTimer)
                }
                
                self.entryManager.setWalkLoopDelayTimer(timer: walkLoopDelayTimer)
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
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override walkToNextSegment method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: \(runOverride ? "Run" : "Walk") To Next Segment =====")
        if !self.entryManager.isWalkingEntry && !self.entryManager.isRunningEntry {
            var text: String
            text = "\(runOverride ? "Running" : "Walking") not active."
            self.notifications.executeError(
                text: text
            )
            return
        }
        
        guard let walkingRange = self.entryManager.walkingRange else {
            self.notifications.executeError(
                text: "Unable to \(runOverride ? "run to" : "walk to") next.",
                handler: handler
            )
            self.exitWalk()
            return
        }
        
        let currentSegment: EntrySegment? = Array(self.entrySegments[walkingRange])[self.entryManager.walkingIndex]
        var currentSegmentIndex: Int? = nil
        if let segment = currentSegment, let walkingRange = self.entryManager.walkingRange {
            print("\tCurrent walking segment in not a valid word. Find next valid word...")
            currentSegmentIndex = Utils.getSegmentIndex(
                segment: segment,
                segments: Array(self.entrySegments[walkingRange]),
                type: .next,
                isWord: true
            )
        }

        if let currentSegmentIndex = currentSegmentIndex, self.entryManager.walkingIndex != currentSegmentIndex {
            // Updating walking index
            self.entryManager.setWalkingIndex(index: currentSegmentIndex)

            // Present Feedback
            self.notifications.executeFeedback(
                visualMessage: "Next word",
                withHaptics: true
            )
            
            // Stop previous walking loop
            self.entryManager.setWalkingTimer()
            
            // Stop previous walking loop delay
            self.entryManager.setWalkLoopDelayTimer()

            // Stop previous echo delay
            self.entryManager.setEchoDelayTimer()

            // Stop playback
            if self.speechPlayer.isPlayingEntry {
                self.speechPlayer.stop(withFeedback: false)
            }
            // Stop echo
            if self.speechSynthesis.isPlayingEcho {
                self.speechSynthesis.stopEcho(withFeedback: false)
            }
            
            self.selectionCursor.setSelection(
                anchorCaret: Caret(index: self.entryManager.walkingRange!.startIndex + currentSegmentIndex, trackType: .committed),
                focusCaret: Caret(index: self.entryManager.walkingRange!.startIndex + currentSegmentIndex, trackType: .committed),
                scale: .word
            )
            
            // start looping walk
            if AVAudioSession.isHeadphonesConnected {
                let currentSegment = Array(self.entrySegments[walkingRange])[currentSegmentIndex]
                let makeStep = {
                    self.speechPlayer.play(segments: [currentSegment])
                    
                    // Play echo
                    let echoDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_ECHO_DELAY_DURATION * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: false) { [weak self] timer in
                        self?.speechSynthesis.startEcho(segments: [currentSegment])
                    }
                    
                    self.entryManager.setEchoDelayTimer(timer: echoDelayTimer)
                }
                
                let walkLoopDelayTimer = Timer.scheduledTimer(withTimeInterval: Utils.WALKING_START_DELAY_DURATION, repeats: false) { [weak self] timer in
                    makeStep()

                    // Make sure that the repeat is at least as long as
                    let segmentDuration: TimeInterval = currentSegment.timeMapping.target.duration.seconds
                    let stepDuration: TimeInterval = max(segmentDuration + (segmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + segmentDuration + Utils.WALKING_LOOP_BUFFER)
                    let walkingTimer = Timer.scheduledTimer(withTimeInterval: max(stepDuration, Utils.WALKING_PERIOD_DURATION) * TimeInterval( 1 / self!.speechPlayer.playbackRate), repeats: true) { timer in
                        makeStep()
                    }
                    
                    self?.entryManager.setWalkingTimer(timer: walkingTimer)
                }
                
                self.entryManager.setWalkLoopDelayTimer(timer: walkLoopDelayTimer)
            }
            
            // execute handler
            handler?()
        } else if self.entryManager.isRunningEntry {
            self.exitWalk(clearSelection: false)
        } else {
            self.notifications.executeError(
                text: "At end of \(runOverride ? "running" : "walking") passage.",
                handler: handler
            )
        }
    }
    
    func run(segments: [EntrySegment]? = nil, onStartHandler: (() -> Void)? = nil) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override run method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        if self.entryManager.isRunningEntry && !self.entryManager.pausedRunningEntry {
            self.notifications.executeError(
                text: "Already running passage."
            )
            return
        }
        
        self.entryManager.setIsRunningEntry(to: true)
        
        let runHandler = {
            onStartHandler?()
            
            let avgSegmentDuration: TimeInterval = 0.5
            let runInterval: TimeInterval = max(avgSegmentDuration + (avgSegmentDuration - Utils.WALKING_ECHO_DELAY_DURATION + Utils.WALKING_LOOP_BUFFER), Utils.WALKING_ECHO_DELAY_DURATION + avgSegmentDuration + Utils.WALKING_LOOP_BUFFER)
            // start automated walking
            let runningTimer = Timer.scheduledTimer(withTimeInterval: runInterval * TimeInterval( 1 / self.speechPlayer.playbackRate), repeats: true) { [weak self] timer in
                if self!.entryManager.walkingIndex + 1 < Array(self!.entrySegments[self!.entryManager.walkingRange!]).count {
                    self?.walkToNextSegment(runOverride: true)
                } else {
                    self?.pauseRun()
                }
            }
            
            self.entryManager.setRunningTimer(timer: runningTimer)
        }
        
        // Start walk
        self.walk(segments: segments, runOverride: true, onStartHandler: runHandler)
    }
    
    func pauseRun(handler: (() -> Void)? = nil) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override pauseRun method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Pause Run =====")
        if !self.entryManager.isRunningEntry {
            self.notifications.executeError(
                text: "Not running passage."
            )
            return
        }
        
        if self.entryManager.runningTimer == nil {
            self.notifications.executeError(
                text: "Error pausing run."
            )
            return
        }
        
        // Stop running timer
        self.entryManager.setRunningTimer()
        
        // Stop previous walking loop
        self.entryManager.setWalkingTimer()
        
        // Stop previous walking loop delay
        self.entryManager.setWalkLoopDelayTimer()

        // Stop previous echo delay
        self.entryManager.setEchoDelayTimer()
        
        // Stop playback
        if self.speechPlayer.isPlayingEntry {
            self.speechPlayer.stop(withFeedback: false)
        }

        // Stop echo
        if self.speechSynthesis.isPlayingEcho {
            self.speechSynthesis.stopEcho(withFeedback: false)
        }
        
        // Turn off running entry
        self.entryManager.setIsRunningEntry(to: false)
        
        guard let walkingRange = self.entryManager.walkingRange else {
            self.notifications.executeError(
                text: "Unable to pause run.",
                handler: handler
            )
            self.exitWalk()
            return
        }
        
        // Convert to walking entry
        self.walk(segments: Array(self.entrySegments[walkingRange]), onStartHandler: handler)
        
        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: "Run Paused!",
            audioMessage: "Run paused to walk",
            withHaptics: true
        )
    }
    
    func exitWalk(pause: Bool = false, clearSelection: Bool = true, withFeedback: Bool = true, handler: (() -> Void)? = nil) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override exitWalk method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        if self.entryManager.isRunningEntry {
            print("===== Entry: Exit Run =====")
        } else {
            print("===== Entry: Exit Walk =====")
        }

        if !self.entryManager.isWalkingEntry && !self.entryManager.isRunningEntry {
            self.notifications.executeError(
                text: "Not walking or running passage."
            )
            return
        }
        
        if !pause {
            self.entryManager.setWalkingIndex(index: 0)
            self.entryManager.setWalkingRange()
        }
        
        // Stop current playback
        if self.speechPlayer.isPlayingExternalSegments || self.speechPlayer.isPlayingEntry {
            self.speechPlayer.stop(withFeedback: false)
        }
        
        // Stop currrent echo
        if self.speechSynthesis.isPlayingEcho || self.speechSynthesis.isPlayingPassiveEcho {
            self.speechSynthesis.stopEcho(withFeedback: false)
        }
        
        // Stop running timer
        self.entryManager.setRunningTimer()
        
        // Stop previous walking loop
        self.entryManager.setWalkingTimer()
        
        // Stop previous walking loop delay
        self.entryManager.setWalkLoopDelayTimer()
        
        // Stop previous echo delay
        self.entryManager.setEchoDelayTimer()
        
        let handleExitWalk = {
            var visualMessage: String?
            var audioMessage: String?
            if withFeedback {
                if self.entryManager.isRunningEntry {
                    visualMessage = "Exit Run"
                    audioMessage = "run exited."
                } else {
                    visualMessage = "Exit Walk"
                    audioMessage = "walk exited."
                }
            }
            
            if pause && self.entryManager.isRunningEntry {
                self.entryManager.setPausedRunningEntry(to: true)
            } else if pause && self.entryManager.isWalkingEntry {
                self.entryManager.setPausedWalkingEntry(to: true)
            } else {
                self.entryManager.setIsWalkingEntry(to: false)
                self.entryManager.setIsRunningEntry(to: false)
                self.entryManager.setPausedRunningEntry(to: false)
                self.entryManager.setPausedWalkingEntry(to: false)
            }
            
            if clearSelection {
                // We only clear the focus so that the cursor remains at given location
                self.selectionCursor.setFocusCaret()
                if let anchorCaret = self.selectionCursor.anchorCaret,
                   !self.selectionCursor.isAtEndOfTextView
                {
                    // We cache the anchor if we're mid-entry so that new content is added from given location
                    self.selectionCursor.setCachedAnchorCaret(caret: anchorCaret)
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
                        name: Entry.onRequestToUpdateView,
                        object: nil,
                        userInfo: [:]
                    )
                }
            } else {
                handler?()
                // Notify observers of loading
                NotificationCenter.default.post(
                    name: Entry.onRequestToUpdateView,
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
        self.setCurrentClipUID(uid: UUID().uuidString)
        self.clips.insert(self.currentClipUID!)
        print("\tAdding new clip: ", self.currentClipUID!)
        self.state.setClip(clipUID: self.currentClipUID!, entryUID: self.uid)
    }
    
    func duplicate(
        state: StateManager? = nil,
        speechSynthesis: SpeechSynthesisEngine? = nil,
        speechRecognition: SpeechRecognitionEngine? = nil,
        speechPlayer: SpeechPlayerEngine? = nil,
        selectionCursor: SelectionCursor? = nil,
        pitchRecognition: PitchRecognitionEngine? = nil,
        entryManager: EntryManager? = nil,
        notifications: NotificationEngine? = nil,
        processSegments: Bool = true
    ) -> Entry {
        print("===== Entry \(self.uid): Duplicate ======")
        let entry = Entry(
            uid: self.uid,
            filename: self.filename,
            creatorUID: self.creatorUID,
            segments: self.entrySegments,
            state: state,
            speechSynthesis: speechSynthesis,
            speechRecognition: speechRecognition,
            speechPlayer: speechPlayer,
            selectionCursor: selectionCursor,
            pitchRecognition: pitchRecognition,
            entryManager: entryManager,
            notifications: notifications
        )
        
        // Set Date Created
        entry.dateCreated = self.dateCreated
        
        // Set Date Modified
        entry.dateModified = self.dateModified

        // Set Committed Buffer Ranges
        if self.committedBufferRanges.count > 0 {
            var committedBufferRanges = [Range<Int>](repeating: 0..<1, count: self.committedBufferRanges.count)
            DispatchQueue.concurrentPerform(iterations: self.committedBufferRanges.count) { [weak self] index in
                let duplicateRange = self!.committedBufferRanges[index].lowerBound..<self!.committedBufferRanges[index].upperBound
                committedBufferRanges[index] = duplicateRange
            }

            entry.committedBufferRanges = committedBufferRanges
        }
        
        // Set Transformations
        if self.transformations.count > 0 {
            var transformations = [EntryTransformation](repeating: self.transformations.first!, count: self.transformations.count)
            DispatchQueue.concurrentPerform(iterations: self.transformations.count) { [weak self] index in
                let duplicateTransformation = EntryTransformation(
                    type: self!.transformations[index].type,
                    uids: self!.transformations[index].uids,
                    text: self!.transformations[index].text,
                    value: self!.transformations[index].value,
                    textRange: self!.transformations[index].textRange,
                    entryRange: self!.transformations[index].entryRange
                )
                transformations[index] = duplicateTransformation
            }
            entry.transformations = transformations
        }
        
        // Set Authorized To Listen For Speech
        entry.authorizedToListenForSpeech = self.authorizedToListenForSpeech

        // Set Clips
        entry.clips = self.clips
        
        // Set Current Clip UID
        entry.setCurrentClipUID(uid: self.currentClipUID)

        // Set Record Start Date
        entry.recordStartDate = self.recordStartDate
        
        // Set Accumulated Duration
        entry.accumulatedDuration = self.accumulatedDuration
        
        // Set Record File
        entry.recordFile = self.recordFile
        
        // Set Is Deleted
        entry.isDeleted = self.isDeleted
        
        // Set Views
        if self.views.count > 0 {
            var views = [TimeInterval](repeating: 0, count: self.views.count)
            DispatchQueue.concurrentPerform(iterations: self.views.count) { [weak self] index in
                views[index] = self!.views[index]
            }
            entry.views = views
        }
        
        // Set Plays
        if self.plays.count > 0 {
            var plays = [TimeInterval](repeating: 0, count: self.plays.count)
            DispatchQueue.concurrentPerform(iterations: self.plays.count) { [weak self] index in
                plays[index] = self!.plays[index]
            }
            entry.plays = plays
        }
        
        // Set Text Exports
        if self.textExports.count > 0 {
            var textExports = [TimeInterval](repeating: 0, count: self.textExports.count)
            DispatchQueue.concurrentPerform(iterations: self.textExports.count) { [weak self] index in
                textExports[index] = self!.textExports[index]
            }
            entry.textExports = textExports
        }
        
        // Audio Exports
        if self.audioExports.count > 0 {
            var audioExports = [TimeInterval](repeating: 0, count: self.audioExports.count)
            DispatchQueue.concurrentPerform(iterations: self.audioExports.count) { [weak self] index in
                audioExports[index] = self!.audioExports[index]
            }
            entry.audioExports = audioExports
        }
        
        return entry
    }
    
    // MARK: - Telemetry
    
    func incrementViewCount() {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override incrementViewCount method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Increment View Count =====")
        let timeInterval = Date().timeIntervalSince1970
        self.views.append(timeInterval)
        
        // Increment State Aggregate Count
        self.state.incrementEntryViewCount(timeInterval: timeInterval)
    }
    
    func incrementPlayCount() {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override incrementPlayCount method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Increment Play Count =====")
        let timeInterval = Date().timeIntervalSince1970
        self.plays.append(timeInterval)
        
        // Increment State Aggregate Count
        self.state.incrementEntryPlayCount(timeInterval: timeInterval)
    }
    
    func incrementTextExportCount() {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override incrementTextExportCount method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Increment Text Export Count =====")
        let timeInterval = Date().timeIntervalSince1970
        self.textExports.append(timeInterval)
        
        // Increment State Aggregate Count
        self.state.incrementEntryTextExportCount(timeInterval: timeInterval)
    }
    
    func incrementAudioExportCount() {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override incrementAudioExportCount method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Increment Audio Export Count =====")
        let timeInterval = Date().timeIntervalSince1970
        self.audioExports.append(timeInterval)
        
        // Increment State Aggregate Count
        self.state.incrementEntryAudioExportCount(timeInterval: timeInterval)
    }
    
    // MARK: - Setters
    
    // We lack a checkRep here because we use it mid
    // operation in trimEntry when the representation invariant is broken
    func setFileType(fileType: AVFileType) {
        self._fileType = fileType
        
        // Handle Mutation
        self.handleMutation()
    }
    
    // entry details refer to entry, sourceURL, and trackID
    // we have to duplicate segments to reset these
    // thus is a costly computation
    // TODO: Confirm that source and target don't affect setting segments to low-level representation
    private func setSegments(
        segments: [EntrySegment],
        replaceEntryDetails: Bool = false,
        saveToLowLevelRepr: Bool = false,
        saveToState: Bool = true,
        computeSentencesAndParagraphs: Bool = true
    ) {
        print("===== Entry: Set Segments =====")
        
        if self.entrySegments.count == 0 {
            // We set it here because segments will be referencing it to compute
            // values like isSentenceTerminator
            self.entrySegments = segments
        }
        
        var setSegmentEntry = false
        // set entry reference in segments
        if segments.count > 0 && segments[0].entry == nil {
            print("\tSegments have no entry reference. Turning on flag to set reference with currrent entry...")
            setSegmentEntry = true
        }
        
        var updatedSegments = [EntrySegment]()
        if replaceEntryDetails && segments.count > 0 {
            print("\tReplacing entry details...")
            updatedSegments = [EntrySegment](repeating: segments.first!, count: segments.count)
            DispatchQueue.concurrentPerform(iterations: segments.count) { [weak self] index in
                updatedSegments[index] = segments[index].duplicate(newEntry: self!)
            }
        }
        
        if let entryManager = self.entryManager,
           let entry = entryManager.currentEntry,
            setSegmentEntry &&
            !replaceEntryDetails &&
            Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(entry).toOpaque()
        {
            // Replace Entry
            DispatchQueue.concurrentPerform(iterations: segments.count) { [weak self] index in
                segments[index].setEntry(entry: self!)
            }
        }
        
        var finalSegments = replaceEntryDetails ? updatedSegments : segments

        // attempt to replace segments
        do {
            // Compute segment sentences
            var segmentsWithUpdatedSentencesAndParagraphs: [EntrySegment]?
            if computeSentencesAndParagraphs && finalSegments.count > 0 {
                segmentsWithUpdatedSentencesAndParagraphs = self.updateSegmentSentencesAndParagraphs(
                    segments: finalSegments,
                    processRange: 0..<finalSegments.count
                )
            }
            finalSegments = segmentsWithUpdatedSentencesAndParagraphs != nil &&
                segmentsWithUpdatedSentencesAndParagraphs!.count == finalSegments.count &&
                computeSentencesAndParagraphs ?
                    segmentsWithUpdatedSentencesAndParagraphs!
                :
                    finalSegments
            
            self.entrySegments = finalSegments

            if saveToLowLevelRepr {
                // only save to mutable track if we're on first take or explicit flag is set
                print("\tUpdating lower level track representation: ", Utils.stringifySegments(segments: finalSegments))
                try self.tracks[0].validateSegments(finalSegments)
                print("\tNew segments are valid! Set to lower level track representation...")
                self.tracks[0].segments = finalSegments
            }
            
            if self.entrySegments.count > 0 {
                self.endTime = self.entrySegments.last!.timeMapping.target.end
            }
            
            // Update transformations
            if let _ = self.state, self.transformations.count > 0 {
                var segmentIndexMap: [String : Int] = [:]
                self.entrySegments.forEach { segmentIndexMap[$0.getUID()] = $0.getIndex() }
                self.transformations = Utils.cleanseTransformations(
                    transformations: self.transformations,
                    segments: self.entrySegments,
                    segmentIndexMap: segmentIndexMap,
                    omitSilences: false,
                    omitVoiceCommands: false,
                    omitDeleted: false
                )
            }
            print("\tSuccessfully updated \(self.entrySegments.count) entry segments!")
            print("\tSuccessfully updated \(self.transformations.count) entry transformations!")
            
            if saveToState {
                // Save entry
                // We don't run handle save when entry ended. We run it at the end of on speech update
                self.handleSave()
            }
        } catch {
            print("\t[Error] There was a problem updating entry segments")
        }

        // Check rep invariant
        self.handleMutation()
        checkRep()
    }
    
    func setState(state: StateManager) {
        print("===== Entry: Set State =====")
        self.state = state
    }
    
    func setSpeechSynthesis(speechSynthesis: SpeechSynthesisEngine) {
        print("===== Entry: Set Speech Synthesis =====")
        self.speechSynthesis = speechSynthesis
    }
    
    func setSpeechRecognition(speechRecognition: SpeechRecognitionEngine) {
        print("===== Entry: Set Speech Recognition =====")
        self.speechRecognition = speechRecognition
    }
    
    func setSpeechPlayer(speechPlayer: SpeechPlayerEngine) {
        print("===== Entry: Set Speech Player =====")
        self.speechPlayer = speechPlayer
    }
    
    func setSelectionCursor(selectionCursor: SelectionCursor) {
        print("===== Entry: Set Selection Cursor =====")
        self.selectionCursor = selectionCursor
    }
    
    func setPitchRecognition(pitchRecognition: PitchRecognitionEngine) {
        print("===== Entry: Set Pitch Recognition  =====")
        self.pitchRecognition = pitchRecognition
    }
    
    func setEntryManager(entryManager: EntryManager) {
        print("===== Entry: Set Entry Manager =====")
        self.entryManager = entryManager
    }
    
    func setNotifications(notifications: NotificationEngine) {
        print("===== Entry: Set Notifications =====")
        self.notifications = notifications
    }
    
    func setIsDeleted(to isDeleted: Bool) {
        print("===== Entry: Set Is Deleted =====")
        self.isDeleted = isDeleted
        
        // Handle Mutation
        self.handleMutation()
    }
    
    func setCurrentClipUID(uid: String?) {
        print("===== Entry: Set Current Clip UID =====")
        self.currentClipUID = uid
        
        // Handle Mutation
        self.handleMutation()
    }
    
    func setRecordStartDate(date: Date?) {
        print("===== Entry: Set Record Start Date =====")
        self.recordStartDate = date
        
        // Handle Mutation
        self.handleMutation()
    }
    
    func setAccumulatedDuration(interval: TimeInterval) {
        print("===== Entry: Set Accumulated Duration =====")
        self.accumulatedDuration = interval
        
        // Handle Mutation
        self.handleMutation()
    }
    
    func setRecordFile(file: AVAudioFile?) {
        print("===== Entry: Set Record File =====")
        self.recordFile = file
        
        // Handle Mutation
        self.handleMutation()
    }
    
    // MARK: - Getters
    
    func getLastCommit() -> [EntrySegment]? {
        var lastCommit: [EntrySegment]?
        for range in self.committedBufferRanges.reversed() {
            var allInactive = true
            // search range for active word/s
            for segment in self.entrySegments[range] {
                if segment.isActive() {
                    allInactive = false
                    break
                }
            }
            
            // Look at next range for active word/s
            if allInactive {
                continue
            }
            
            lastCommit = Array(self.entrySegments[range])
            return lastCommit
        }
        
        return nil
    }
    
    func getSentenceDetails(number: Int) -> Sentence? {
        print("===== Entry: Get Sentence Details =====")

        for segment in self.entrySegments {
            if segment.getSentence().number == number {
                return segment.getSentence()
            }
        }
        
        return nil
    }

    func getSentenceDetails(forTrackTime: CMTime) -> Sentence? {
        print("===== Entry: Get Sentence Details =====")
        
        let sentenceSegment = Utils.binarySearch(
            in: self.entrySegments,
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
    
    func getParagraphDetails(number: Int) -> Paragraph? {
        print("===== Entry: Get Paragraph Details =====")

        for segment in self.entrySegments {
            if segment.getParagraph().number == number {
                return segment.getParagraph()
            }
        }
        
        return nil
    }

    func getParagraphDetails(forTrackTime: CMTime) -> Paragraph? {
        print("===== Entry: Get Paragraph Details =====")

        let paragraphSegment = Utils.binarySearch(
            in: self.entrySegments,
            isLower: { segment in
                return segment.getParagraph().timeRange.end < forTrackTime
            },
            isHigher: { segment in
                return segment.getParagraph().timeRange.start > forTrackTime
            }
        )
        
        if let paragraphSegment = paragraphSegment {
            return paragraphSegment.getParagraph()
        }

        return nil
    }
    
    // We use .lowercased() throughout the method because sometimes word is made uppercase if we have PunctuationSuggestions on which will capitalize on-demand
    // To elimate this we make everything lowercase
    func getSegmentTextRange(of segment: EntrySegment) -> NSRange? {
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
    
    func getPower(type: ScaleUnitType = .all, sentenceNumber: Int? = nil, paragraphNumber: Int? = nil, segmentTrackTime: CMTime? = nil) -> Double {
        // print("===== Get Sound Intensity =====")
        var numSegments: Double = 0
        var powerSum: Double = 0
        
        switch type {
        case .all:
            // add committed
            for segment in self.entrySegments {
                let power = segment.getPower()
                if power != Double.infinity {
                    powerSum += power
                    numSegments += 1
                }
            }
            
            // add buffer
            for segment in self.entryBuffer {
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
        case .paragraph:
            if let paragraphNumber = paragraphNumber {
                // add committed
                for segment in self.entrySegments {
                    if segment.getParagraph().number == paragraphNumber {
                        let power = segment.getPower()
                        if power != Double.infinity {
                            powerSum += power
                            numSegments += 1
                        }
                    }
                }
                
                // add buffer
                for segment in self.entryBuffer {
                    if segment.getParagraph().number == paragraphNumber {
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
        case .sentence:
            if let sentenceNumber = sentenceNumber {
                // add committed
                for segment in self.entrySegments {
                    if segment.getSentence().number == sentenceNumber {
                        let power = segment.getPower()
                        if power != Double.infinity {
                            powerSum += power
                            numSegments += 1
                        }
                    }
                }
                
                // add buffer
                for segment in self.entryBuffer {
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
            if let segmentTrackTime = segmentTrackTime,
               let segment = Utils.getSegment(forTrackTime: segmentTrackTime, entry: self)
            {
                return segment.getPower()
            }
            break
        }
        
        return Double.infinity
    }
    
    func getSentimentScore(type: ScaleUnitType = .word, sentenceNumber: Int? = nil, forTrackTime: CMTime? = nil) -> Float {
        print("===== Get Sentiment Score =====")
        if let forTrackTime = forTrackTime,
           let segment = Utils.getSegment(forTrackTime: forTrackTime, entry: self),
           let sentiment = segment.getSentimentScore(type: type)
        {
            return sentiment
        }

        return 0
    }
    
    func getDuration() -> CMTime {
        // Use cached version if it exists
        if let cachedDuration = self.cachedDuration
        {
            return cachedDuration
        }
        
        var duration: CMTime = CMTime.zero
        for segment in self.entrySegments {
            if !segment.isVoiceCommandWord() &&
                !segment.isDeleted() &&
                (
                    !self.state.withOmitSilences ||
                    !(
                        self.state.withOmitSilences &&
                        segment.isSilence() &&
                        segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD
                    )
                )
            {
                duration = CMTimeAdd(duration, segment.getEffectiveDuration())
            } else if !self.state.withOmitSilences {
                duration = CMTimeAdd(duration, segment.getEffectiveDuration())
            }
        }
        
        self.cachedDuration = duration
        
        return self.cachedDuration!
    }
    
    static func getDuration(segments: [EntrySegment], withOmitSilences: Bool) -> CMTime {
        var duration: CMTime = CMTime.zero
        for segment in segments {
            if !segment.isVoiceCommandWord() &&
                !segment.isDeleted() &&
                (
                    !withOmitSilences ||
                    !(
                        withOmitSilences &&
                        segment.isSilence() &&
                        segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD
                    )
                )
            {
                duration = CMTimeAdd(duration, segment.getEffectiveDuration())
            } else if !withOmitSilences {
                duration = CMTimeAdd(duration, segment.getEffectiveDuration())
            }
        }
        
        return duration
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
        var firstBufferSegmentIndex: Int?
        var lastBufferSegmentIndex: Int?
        var trackType: EntryTrackType?
        if self.entryBuffer.count > 0 {
            // Find first buffer word
            let firstBufferSegment = self.entryBuffer.first
            if let firstBufferSegment = firstBufferSegment, !firstBufferSegment.isActive() {
                firstBufferSegmentIndex = Utils.getSegmentIndex(
                    segment: firstBufferSegment,
                    segments: self.entryBuffer,
                    type: .next,
                    isWord: true
                )
            } else if let _ = firstBufferSegment {
                firstBufferSegmentIndex = 0
            }
            
            // Find last buffer word
            let lastBufferSegment = self.entryBuffer.last
            if let lastBufferSegment = lastBufferSegment, !lastBufferSegment.isActive() {
                lastBufferSegmentIndex = Utils.getSegmentIndex(
                    segment: lastBufferSegment,
                    segments: self.entryBuffer,
                    type: .previous,
                    isWord: true
                )
            } else if let _ = lastBufferSegment {
                lastBufferSegmentIndex = self.entryBuffer.count - 1
            }
            
            // Set trackt ype
            trackType = .buffer
        } else if let lastBufferRange = self.committedBufferRanges.last {
            let lastBuffer = self.entrySegments[lastBufferRange]
            // Find first buffer word
            let firstBufferSegment = lastBuffer.first
            if let firstBufferSegment = firstBufferSegment, !firstBufferSegment.isActive() {
                firstBufferSegmentIndex = Utils.getSegmentIndex(
                    segment: firstBufferSegment,
                    segments: Array(lastBuffer),
                    type: .next,
                    isWord: true
                )
            } else if let _ = firstBufferSegment {
                firstBufferSegmentIndex = lastBufferRange.lowerBound
            }
            

            // Find last buffer word
            let lastBufferSegment = lastBuffer.last
            if let lastBufferSegment = lastBufferSegment, !lastBufferSegment.isActive() {
                lastBufferSegmentIndex = Utils.getSegmentIndex(
                    segment: lastBufferSegment,
                    segments: Array(lastBuffer),
                    type: .previous,
                    isWord: true
                )
            } else if let _ = lastBufferSegment {
                lastBufferSegmentIndex = lastBufferRange.upperBound - 1
            }
            
            trackType = .committed
        }
        
        if let firstBufferSegmentIndex = firstBufferSegmentIndex,
           let lastBufferSegmentIndex = lastBufferSegmentIndex,
           let trackType = trackType,
           firstBufferSegmentIndex != lastBufferSegmentIndex
        {
            let segments = trackType == .committed ? self.entrySegments : self.entryBuffer
            let firstBufferSegment = segments[firstBufferSegmentIndex]
            let lastBufferSegment = segments[lastBufferSegmentIndex]
            self.notifications.executeFeedback(
                visualMessage: "\"\(firstBufferSegment.getText().lowercased())...\(lastBufferSegment.getText().lowercased())\" committed!",
                withHaptics: true
            )
        } else if let firstBufferSegmentIndex = firstBufferSegmentIndex,
            let lastBufferSegmentIndex = lastBufferSegmentIndex,
            let trackType = trackType,
            firstBufferSegmentIndex == lastBufferSegmentIndex
        {
            let segments = trackType == .committed ? self.entrySegments : self.entryBuffer
            let firstBufferSegment = segments[firstBufferSegmentIndex]
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
    
    func processVoiceCommandSegments(command: String, voiceCommandIndices: [Int]) {
        // When we create duplicates of entries because of the undo manager, so remain in memory
        // To avoid multiple copies of the same entry mutating values, we only allow the one that matches memory addresses with currentEntry through
        guard let entryManager = self.entryManager, let currentEntry = entryManager.currentEntry, Unmanaged.passUnretained(self).toOpaque() == Unmanaged.passUnretained(currentEntry).toOpaque() else {
            print("\t[Error] Override processVoiceCommandSegments method call because we attempted to modify entry that's not currently set in Entry Manager.")
            return
        }
        
        print("===== Entry: Process Voice Command Segments =====")
        print("\tSeeking lowest voice command index...")
        
        var lastBufferRange: Range<Int>
        if self.entryBuffer.count > 0 {
            print("\tSourcing segments from entry buffer because we haven't committed yet.")
            lastBufferRange = 0..<self.entryBuffer.count
        } else {
            print("\tSourcing segments from committed segments because buffer is empty.")
            lastBufferRange = self.committedBufferRanges[self.committedBufferRanges.count - 1]
        }
        
        var replaceSelectionAnchor = false
        var replaceSelectionFocus = false
        var replaceSelectionCachedAnchor = false
        print("\tFlipping every segment after lowest voice command index to be voice command word...")
        let bufferSource = self.entryBuffer.count > 0 ? self.entryBuffer : Array(self.entrySegments[lastBufferRange])
        for index in voiceCommandIndices {
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
            if self.entryBuffer.count > 0 {
                self.entryBuffer[index] = duplicateSegment
            } else {
                self.entrySegments[index] = duplicateSegment
            }
            
            // determine track type
            let trackType: EntryTrackType = self.entryBuffer.count > 0 ? .buffer : .committed
            let index = self.entryBuffer.count > 0 ? index : duplicateSegment.getIndex()
            
            // update selection anchor
            if duplicateSegment == self.selectionCursor.anchor {
                print("\tReplacing Selection Cursor Anchor with version that is not voice command word...")
                self.selectionCursor.setAnchorCaret(caret: Caret(index: index, trackType: trackType))
            }
            
            // update selection focus
            if duplicateSegment == self.selectionCursor.focus {
                print("\tReplacing Selection Cursor Focus with version that is voice command word...")
                self.selectionCursor.setFocusCaret(caret: Caret(index: index, trackType: trackType))
            }
            
            // update selection cached anchor
            if duplicateSegment == self.selectionCursor.cachedAnchor {
                print("\tReplacing Selection Cursor Cached Anchor with version that is voice command word...")
                self.selectionCursor.setCachedAnchorCaret(caret: Caret(index: index, trackType: trackType))
            }
        }
        
        if let anchor = self.selectionCursor.anchor, replaceSelectionAnchor && self.entryBuffer.count > 0 && !anchor.isCommitted() {
            print("\tReplacing anchor. We cannot have a voice command anchor.")
            print("\tSearching in entry buffer...")
            var newAnchorIndex = Utils.getEntryNthLastSegmentIndex(
                segments: self.entryBuffer,
                selectionCursor: self.selectionCursor,
                n: 0
            ).1
            var newAnchorTrackType: EntryTrackType
            
            if let newAnchorIndex = newAnchorIndex {
                newAnchorTrackType = .buffer
                let newAnchor = self.entryBuffer[newAnchorIndex]
                print("\tFound new anchor: '\(newAnchor.getText())'")
            } else {
                print("\tUnable to find replacement anchor in buffer. Search in committed segments...")
                let segments = self.selectionCursor.cachedAnchor != nil ? Array(self.entrySegments[0..<self.selectionCursor.cachedAnchor!.getIndex() + 1]) : self.entrySegments // We add one because we want to include cached anchor
                newAnchorIndex = Utils.getEntryNthLastSegmentIndex(
                    segments: segments,
                    selectionCursor: self.selectionCursor,
                    n: 0
                ).1
                newAnchorTrackType = .committed
                
                if let newAnchorIndex = newAnchorIndex {
                    let newAnchor = segments[newAnchorIndex]
                    print("\tFound new anchor: '\(newAnchor.getText())'")
                }
            }
            
            if let newAnchorIndex = newAnchorIndex {
                print("\tUpdating Selection Anchor...")
                self.selectionCursor.setAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: newAnchorTrackType))
            }
        } else if let _ = self.selectionCursor.anchor, replaceSelectionAnchor {
            print("\tReplacing anchor. We cannot have a voice command anchor.")
            print("\tSearching in entry committed segments...")
            let segments = self.selectionCursor.cachedAnchor != nil ? Array(self.entrySegments[0..<self.selectionCursor.cachedAnchor!.getIndex() + 1]) : self.entrySegments // We add one because we want to include cached anchor
            let newAnchorIndex = Utils.getEntryNthLastSegmentIndex(
                segments: segments,
                selectionCursor: self.selectionCursor,
                n: 0
            ).1
            let newAnchorTrackType: EntryTrackType = .committed
            
            if let newAnchorIndex = newAnchorIndex {
                let newAnchor = segments[newAnchorIndex]
                print("\tFound new anchor: '\(newAnchor.getText())'")
            }
            
            if let newAnchorIndex = newAnchorIndex {
                print("\tUpdating Selection Anchor...")
                self.selectionCursor.setAnchorCaret(caret: Caret(index: newAnchorIndex, trackType: newAnchorTrackType))
            }
        }
        
        print("\tClear focus...")
        if !self.selectionCursor.hasSelection {
            self.selectionCursor.setFocusCaret()
        }
        
        if let cachedAnchor = self.selectionCursor.cachedAnchor, replaceSelectionCachedAnchor && self.entryBuffer.count > 0 && !cachedAnchor.isCommitted() {
            print("\tReplacing cached anchor. We cannot have a voice command cached anchor.")
            print("\tSearching in entry buffer...")
            let newCachedAnchorIndex = Utils.getEntryNthLastSegmentIndex(
                segments: Array(self.entryBuffer[0..<cachedAnchor.getIndex() + 1]), // We add one because we want to include cached anchor
                selectionCursor: self.selectionCursor,
                n: 0
            ).1
            var newCachedAnchorTrackType: EntryTrackType
            
            if let newCachedAnchorIndex = newCachedAnchorIndex {
                newCachedAnchorTrackType = .buffer
                let newCachedAnchor = Array(self.entryBuffer[0..<cachedAnchor.getIndex() + 1])[newCachedAnchorIndex] // We add one because we want to include cached anchor
                print("\tFound new cached anchor: ", newCachedAnchor)
            } else {
                print("\tUnable to find replacement cached anchor in buffer. Search in committed segments...")
                let newCachedAnchorIndex = Utils.getEntryNthLastSegmentIndex(
                    segments: self.entrySegments,
                    selectionCursor: self.selectionCursor,
                    n: 0
                ).1
                newCachedAnchorTrackType = .committed
                
                if let newCachedAnchorIndex = newCachedAnchorIndex {
                    let newCachedAnchor = self.entrySegments[newCachedAnchorIndex]
                    print("\tFound new cached anchor: ", newCachedAnchor)
                }
            }
            
            if let newCachedAnchorIndex = newCachedAnchorIndex {
                print("\tUpdating Selection Cached Anchor...")
                self.selectionCursor.setCachedAnchorCaret(caret: Caret(index: newCachedAnchorIndex, trackType: newCachedAnchorTrackType))
            }
        } else if let cachedAnchor = self.selectionCursor.cachedAnchor, replaceSelectionCachedAnchor {
            print("\tReplacing cached anchor. We cannot have a voice command anchor.")
            print("\tSearching in entry committed segments...")
            let newCachedAnchorIndex = Utils.getEntryNthLastSegmentIndex(
                segments: Array(self.entryBuffer[0..<cachedAnchor.getIndex() + 1]), // We add one because we want to include cached anchor
                selectionCursor: self.selectionCursor,
                n: 0
            ).1
            let newCachedAnchorTrackType: EntryTrackType = .committed
            
            if let newCachedAnchorIndex = newCachedAnchorIndex {
                let newCachedAnchor = Array(self.entryBuffer[0..<cachedAnchor.getIndex() + 1])[newCachedAnchorIndex] // We add one because we want to include cached anchor
                print("\tFound new cached anchor: ", newCachedAnchor)
            }
            
            if let newCachedAnchorIndex = newCachedAnchorIndex {
                print("\tUpdating Selection Cached Anchor...")
                self.selectionCursor.setCachedAnchorCaret(caret: Caret(index: newCachedAnchorIndex, trackType: newCachedAnchorTrackType))
            }
        }
        
        print("\tSegment count after processing voice commands: \(self.entrySegments.count) committed and \(self.entryBuffer.count) in buffer.")
        self.handleMutation()
        self.checkRep()
    }
    
    func handleOnSpeechUpdate(text: String, highlightRange: NSRange? = nil) {
        print("===== Entry: Handle On Listen Update =====")
        
        if self.entryBuffer.count > 0 {
            // Find first buffer word
            let firstBufferSegment = self.entryBuffer.first
            var firstBufferSegmentIndex: Int?
            if let segment = firstBufferSegment, !segment.isActive() {
                firstBufferSegmentIndex = Utils.getSegmentIndex(
                    segment: segment,
                    segments: self.entryBuffer,
                    type: .next,
                    isWord: true
                )
            } else if let _ = firstBufferSegment {
                firstBufferSegmentIndex = 0
            }
            
            // Find last buffer word
            let lastBufferSegment = self.entryBuffer.last
            var lastBufferSegmentIndex: Int?
            if let segment = lastBufferSegment, !segment.isActive() {
                lastBufferSegmentIndex = Utils.getSegmentIndex(
                    segment: segment,
                    segments: self.entryBuffer,
                    type: .previous,
                    isWord: true
                )
            } else if let _ = lastBufferSegment {
                lastBufferSegmentIndex = self.entryBuffer.count - 1
            }
            
            if let firstBufferSegmentIndex = firstBufferSegmentIndex,
               let lastBufferSegmentIndex = lastBufferSegmentIndex,
               let firstBufferSegmentTextRange = self.getSegmentTextRange(of: self.entryBuffer[firstBufferSegmentIndex]),
               let lastBufferSegmentTextRange = self.getSegmentTextRange(of: self.entryBuffer[lastBufferSegmentIndex]),
               self.speechRecognition.isListeningForSpeech &&
                self.entryBuffer.count > 0 &&
                self.entryBuffer[firstBufferSegmentIndex].isActive() &&
                self.entryBuffer[lastBufferSegmentIndex].isActive()
            {
                let bufferRange = NSRange(
                    location: firstBufferSegmentTextRange.location,
                    length: (lastBufferSegmentTextRange.location - firstBufferSegmentTextRange.location) + lastBufferSegmentTextRange.length
                )
                
                // Notify observers of entry update
                var userInfo: [String : Any] = [
                    "text": text,
                    "bufferRange": bufferRange,
                    "transformations": self.transformations
                ]
                
                if let highlightRange = highlightRange {
                    userInfo["highlightRange"] = highlightRange
                }
                
                NotificationCenter.default.post(
                    name: Entry.onEntryListenUpdate,
                    object: nil,
                    userInfo: userInfo
                )
            } else {
                // Notify observers of entry update
                var userInfo: [String : Any] = [
                    "text": text,
                    "transformations": self.transformations
                ]
                
                if let highlightRange = highlightRange {
                    userInfo["highlightRange"] = highlightRange
                }
                
                NotificationCenter.default.post(
                    name: Entry.onEntryListenUpdate,
                    object: nil,
                    userInfo: userInfo
                )
            }
        } else if self.speechRecognition.isListeningForCommands && !self.speechRecognition.isListeningForSpeech && !self.speechRecognition.pausedListeningForSpeech && self.entrySegments.count == 0 {
            // All text is buffer text when listening for commands
            let bufferRange = NSRange(
                location: 0,
                length: text.count
            )
            
            // Notify observers of entry update
            var userInfo: [String : Any] = [
                "text": text,
                "bufferRange": bufferRange,
                "transformations": self.transformations
            ]
            
            if let highlightRange = highlightRange {
                userInfo["highlightRange"] = highlightRange
            }
            
            NotificationCenter.default.post(
                name: Entry.onEntryListenUpdate,
                object: nil,
                userInfo: userInfo
            )
        } else {
            // Notify observers of entry update
            var userInfo: [String : Any] = [
                "text": text,
                "transformations": self.transformations
            ]
            
            if let highlightRange = highlightRange {
                userInfo["highlightRange"] = highlightRange
            }
            
            NotificationCenter.default.post(
                name: Entry.onEntryListenUpdate,
                object: nil,
                userInfo: userInfo
            )
        }
    }
    
    // Used when we set a new entry
    // Not used during listening
    func refresh() {
        print("===== Entry: Refresh =====")
        DispatchQueue.concurrentPerform(iterations: self.entrySegments.count) { [weak self] index in
            self!.entrySegments[index].handleMutation()
        }

        self.setSegments(
            segments: self.entrySegments,
            replaceEntryDetails: true,
            saveToLowLevelRepr: true,
            saveToState: false
        )
    }
    
    func handleMutation() {
        // Update date modified
        self.dateModified = TimeInterval(Date().timeIntervalSince1970)
        
        // Clear out cached properties so they are computed again
        self.cachedText = nil
        self.cachedDuration = nil
        self.cachedTextArgsSet = nil
        self.cachedSegmentUIDSet = nil
        self.cachedBackgroundNoise = nil
    }
    
    // Reference: http://www.gwtproject.org/javadoc/latest/com/google/gwt/i18n/client/DateTimeFormat.html
    func getTitle(attributes: [NSAttributedString.Key: Any] = [:], withDashes: Bool = false) -> NSMutableAttributedString {
        if let title = self.title {
            return NSMutableAttributedString(string: title, attributes: attributes)
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE MMM dd, yyyy"
        let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: self.dateCreated))
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h\(withDashes ? "-" : ":")mm\(withDashes ? "-" : ":")ss a"
        let timeString = timeFormatter.string(from: Date(timeIntervalSince1970: self.dateCreated))
        
        return NSMutableAttributedString(string: "Entry\(withDashes ? " -" : "") \(dateString) at \(timeString)", attributes: attributes)
    }
}
