//
//  SpeechSegment.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/11/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Speech
import AVFoundation
import NaturalLanguage

// https://remotepossibilities.wordpress.com/2013/03/10/when-you-speak-how-often-and-how-long-should-you-pause-the-answer-try-1-2-3/
let MAX_SEMANTICALLY_SIMILAR_WORDS = 5

class NoteSegment: AVCompositionTrackSegment, NSCoding {
    // ===== IMPORTANT =====
    // - When you add new properties to a NoteSegment, make sure to
    // handle these in the following places:
    // 1) NoteSegment Property section
    // 2) NoteSegment.duplicate()
    // 3) NoteSegment.init(coder: NSCoder)
    // 4) NoteSegment.decode(with:)
    // 5) NoteSegment.description
    // 6) Note.normalizeSegments
    // 7) Utils.cleanseSegments
    // 8) Any other place where we manipulate NoteSegment objects
    //
    // - The above relates specifically the transfer of state when we create new NoteSegments
    // and doesn't factor all the places where we instantiate a new one.
    // - If the property will be an intializer argument, make sure to add it to these places too:
    // 1) Note.processTranscriptSegment
    //
    // - Make sure to create a getter method instead of exposing the variable itself
    
    // MARK: - ViewController References
    weak var viewController: ViewController?
    
    // MARK: - Identity Properties
    
    /// Stores a unique identifier for note
    internal var uid: String
    /// Stores UID of segment clip
    internal var clipUID: String
    /// Stores speaker uid of segment clip
    internal var speakerUID: String
    /// Reference to it's parent note
    weak private(set) var note: Note?
    
    // MARK: - General Properties
    
    /// The date when note was created
    internal var dateCreated: TimeInterval
    /// The date when note was last modified
    internal var dateModified: TimeInterval
    /// Index of segment in note track
    private var index: Int = Int(Utils.UNKNOWN)
    /// Specifies whether segment is deleted
    private var deleted: Bool = false
    /// A textual representation of note segment.
    internal var word : String
    /// The rate at which segment should be played
    private var rate: Float = 1
    /// The effective duration of segment
    private var effectiveDuration: CMTime {
        let baseDuration = Float(self.timeMapping.source.duration.seconds)
        let trueDuration = rate * baseDuration
        return CMTimeMake(value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * Double (trueDuration)), timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE))
    }
    /// An array of similarly sounding words.
    private var phoneticallySimilarWords : [String]
    /// An array of words with similar meaning
    private var semanticallySimilarWords = [(String, NLDistance)]()
    /// Classifies token according to its broad type: word, punctuation, or whitespace.
    private var tokenType: NLTag?
    /// Classifies token according to class: part of speech, type of punctuation, or whitespace.
    private var lexicalClass: NLTag?
    /// Classifies tokens according to whether they are part of a named entity.
    private var nameType: NLTag?
    /// A stem form of a word token, if known.
    private var lemma: NLTag?
    /// The average background noise at the time of recording.
    private var backgroundNoise: Double = Double.infinity
    /// The sound intensity of utterance at the time of recording.
    private var power: Double = Double.infinity
    private var avgNotePower: Double {
        if let expr = self.note {
            return expr.getPower()
        }
        
        return Double.infinity
    }
    /// Specifies information related to the sentence of the note segment is a member of.
    private var sentence = Sentence(number: Int(Utils.UNKNOWN), text: "", timeRange: CMTimeRange.zero, noteRange: 0..<1)
    /// Scores text as positive, negative, or neutral based on its sentiment polarity.
    private var sentimentScore: [ScaleUnitType:Float] = [
        .word: Float.infinity,
        .sentence: Float.infinity,
        .all: Float.infinity
    ]
    /// The pitch at which segment was uttered
    private var pitch: Pitch?
    /// The average pause duration between words, measured in seconds.
    private var avgPauseDuration: Double = Double(Utils.UNKNOWN)
    /// The number of words spoken per minute.
    private var speakingRate: Double = Double(Utils.UNKNOWN)
    /// Indicates whether segment is a voice command word
    private var voiceCommandWord: Bool
    /// Schedules visual or audio notification once index is set
    private var scheduleNotificationSearch: Bool = false
    
    // MARK: - Cached Properties
    
    /// Stores a cached version of getText() method
    private(set) var cachedText: String?
    /// Stores arguments of last getText() call
    private(set) var cachedGetTextArguments: Set<String>?
    /// Stores a cached version of isValidLastSentenceWord() method
    private(set) var cachedIsValidSentenceLastWord: Bool?
    /// Stores a cached version of isValidCommaWord() method
    private(set) var cachedIsValidCommaWord: Bool?
    /// Stores a cached version of isSentenceTerminator() method
    private(set) var cachedIsSentenceTerminator: Bool?
    
    /// Initializes the NoteSegment class instance
    ///
    /// - Parameters:
    ///     - note: Reference to it's parent note
    ///     - word: Supplies a textual representation of note segment.
    ///     - trackURL: The container file of the media presented by the track segment.
    ///     - trackID: The track ID of the container file of the media presented by the track segment.
    ///     - phoneticallySimilarWords: Supplies an array of similarly sounding words.
    ///     - timeRange: The time range of the track of the container file of the media presented by the segment.
    ///     - tokenType: Classifies token according to its broad type: word, punctuation, or whitespace.
    ///     - lexicalClass: Classifies token according to class: part of speech, type of punctuation, or whitespace.
    ///     - nameType: Classifies tokens according to whether they are part of a named entity.
    ///     - lemma: Supplies a stem form of a word token, if known.
    ///     - sentimentScore: Scores text as positive, negative, or neutral based on its sentiment polarity.
    init(
        note: Note? = nil,
        speakerUID: String,
        rate: Float = 1.0,
        word: String,
        clipUID: String,
        trackURL: URL, // Cannot be replaced. Read Only
        trackID: CMPersistentTrackID,
        phoneticallySimilarWords: [String]?,
        sourceTimeRange : CMTimeRange,
        targetTimeRange: CMTimeRange,
        tokenType: NLTag?,
        lexicalClass: NLTag?,
        nameType: NLTag?,
        lemma: NLTag?,
        sentimentScore: [ScaleUnitType: Float]?,
        withPunctuationSuggestions: Bool,
        utterPunctuationSuggestion: Bool = false,
        voiceCommandWord: Bool = false,
        deleted: Bool = false
    ) {
        self.uid = UUID().uuidString
        self.clipUID = clipUID
        self.dateCreated = Date().timeIntervalSince1970
        self.dateModified = Date().timeIntervalSince1970
        self.word = word
        self.tokenType = tokenType
        self.lexicalClass = lexicalClass
        self.nameType = nameType
        self.lemma = lemma
        self.voiceCommandWord = voiceCommandWord
        self.deleted = deleted
        self.rate = rate.rounded(toPlaces: 1)
        self.speakerUID = speakerUID
        
        if let note = note {
            self.note = note
        }
        
        if let sentimentScore = sentimentScore {
            self.sentimentScore = sentimentScore
        }

        if let phoneticallySimilarWords = phoneticallySimilarWords {
            self.phoneticallySimilarWords = phoneticallySimilarWords
        } else {
            self.phoneticallySimilarWords = []
        }
        
        if let language = NLLanguageRecognizer.dominantLanguage(for: word), language != .undetermined && tokenType == .word, let embedding = NLEmbedding.wordEmbedding(for: language) {
            let semanticallySimilarWords = embedding.neighbors(for: self.word, maximumCount: MAX_SEMANTICALLY_SIMILAR_WORDS)
            self.semanticallySimilarWords = semanticallySimilarWords
        }
        
        super.init(
            url: trackURL,
            trackID: trackID,
            sourceTimeRange: sourceTimeRange,
            targetTimeRange: targetTimeRange
        )
        
        if AVAudioSession.isHeadphonesConnected && withPunctuationSuggestions && utterPunctuationSuggestion && !voiceCommandWord && !deleted && self.isSilence() && self.suggestsNewParagraph() {
            // Received newline punctuation suggestion
            // Headphones are connected
            self.scheduleNotificationSearch = true
        } else if !AVAudioSession.isHeadphonesConnected && withPunctuationSuggestions && utterPunctuationSuggestion && !voiceCommandWord && !deleted && self.isSilence() && self.suggestsNewParagraph() {
            // Received newline punctuation suggestion
            // Headphones not are connected
            self.scheduleNotificationSearch = true
        } else if AVAudioSession.isHeadphonesConnected && withPunctuationSuggestions && utterPunctuationSuggestion && !voiceCommandWord && !deleted && self.isSilence() && self.suggestsNewSentence() {
            // Received new sentence punctuation suggestion
            // Headphones are connected
            self.scheduleNotificationSearch = true
        } else if !AVAudioSession.isHeadphonesConnected && withPunctuationSuggestions && utterPunctuationSuggestion && !voiceCommandWord && !deleted && self.isSilence() && self.suggestsNewSentence() {
            // Received new sentence punctuation suggestion
            // Headphones not are connected
            self.scheduleNotificationSearch = true
        }
        
        checkRep()
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.uid, forKey: "uid")
        coder.encode(self.clipUID, forKey: "clipUID")
        coder.encode(self.note, forKey: "note")
        coder.encode(self.speakerUID, forKey: "speakerUID")
        coder.encode(self.dateCreated, forKey: "dateCreated")
        coder.encode(self.dateModified, forKey: "dateModified")
        coder.encode(self.index, forKey: "index")
        coder.encode(self.deleted, forKey: "deleted")
        coder.encode(self.word, forKey: "word")
        coder.encode(self.rate, forKey: "rate")
        coder.encode(self.phoneticallySimilarWords, forKey: "phoneticallySimilarWords")
        var semanticallySimilarWords = [String: Double]()
        for word in self.semanticallySimilarWords {
            semanticallySimilarWords[word.0] = word.1
        }
        coder.encode(semanticallySimilarWords, forKey: "semanticallySimilarWords")
        coder.encode(self.tokenType, forKey: "tokenType")
        coder.encode(self.lexicalClass, forKey: "lexicalClass")
        coder.encode(self.nameType, forKey: "nameType")
        coder.encode(self.lemma, forKey: "lemma")
        coder.encode(self.backgroundNoise, forKey: "backgroundNoise")
        coder.encode(self.power, forKey: "power")
        coder.encode(self.sentence, forKey: "sentence")
        let sentimentScore: [String: Float] = [
            "word": self.sentimentScore[.word]!,
            "sentence": self.sentimentScore[.sentence]!,
            "all": self.sentimentScore[.all]!
        ]
        coder.encode(sentimentScore, forKey: "sentimentScore")
        if let frequency = self.pitch?.frequency {
            coder.encode(frequency, forKey: "pitchFrequency")
        }
        coder.encode(self.avgPauseDuration, forKey: "avgPauseDuration")
        coder.encode(self.speakingRate, forKey: "speakingRate")
        coder.encode(self.voiceCommandWord, forKey: "voiceCommandWord")
        coder.encode(self.sourceURL?.lastPathComponent, forKey: "trackURL")
        coder.encode(self.sourceTrackID, forKey: "trackID")
        let sourceTimeRange: [String: [String: Int]] = [
            "start": [
                "value": Int(self.timeMapping.source.start.value),
                "timescale": Int(self.timeMapping.source.start.timescale)
            ],
            "end": [
                "value": Int(self.timeMapping.source.end.value),
                "timescale": Int(self.timeMapping.source.end.timescale)
            ]
        ]
        coder.encode(sourceTimeRange, forKey: "sourceTimeRange")
        let targetTimeRange: [String: [String: Int]] = [
            "start": [
                "value": Int(self.timeMapping.target.start.value),
                "timescale": Int(self.timeMapping.target.start.timescale)
            ],
            "end": [
                "value": Int(self.timeMapping.target.end.value),
                "timescale": Int(self.timeMapping.target.end.timescale)
            ]
        ]
        coder.encode(targetTimeRange, forKey: "targetTimeRange")
    }
    
    required init?(coder: NSCoder) {
        self.uid = coder.decodeObject(forKey: "uid") as! String
        self.clipUID = coder.decodeObject(forKey: "clipUID") as! String
        self.note = coder.decodeObject(forKey: "note") as! Note?
        self.speakerUID = coder.decodeObject(forKey: "speakerUID") as! String
        self.dateCreated = coder.decodeDouble(forKey: "dateCreated")
        self.dateModified = coder.decodeDouble(forKey: "dateModified")
        self.index = Int(truncatingIfNeeded: coder.decodeInt64(forKey: "index"))
        self.deleted = coder.decodeBool(forKey: "deleted")
        self.word = coder.decodeObject(forKey: "word") as! String
        self.rate = coder.decodeFloat(forKey: "rate")
        self.phoneticallySimilarWords = coder.decodeObject(forKey: "phoneticallySimilarWords") as! [String]
        let semanticallySimilarWords = coder.decodeObject(forKey: "semanticallySimilarWords") as! [String: Double]
        for word in semanticallySimilarWords.keys {
            self.semanticallySimilarWords.append((word, semanticallySimilarWords[word]!))
        }
        self.tokenType = coder.decodeObject(forKey: "tokenType") as! NLTag?
        self.lexicalClass = coder.decodeObject(forKey: "lexicalClass") as! NLTag?
        self.nameType = coder.decodeObject(forKey: "nameType") as! NLTag?
        self.lemma = coder.decodeObject(forKey: "lemma") as! NLTag?
        self.backgroundNoise = coder.decodeDouble(forKey: "backgroundNoise")
        self.power = coder.decodeDouble(forKey: "power")
        self.sentence = coder.decodeObject(forKey: "sentence") as! Sentence
        let sentimentScore = coder.decodeObject(forKey: "sentimentScore") as! [String:Float]
        self.sentimentScore = [
            .word: sentimentScore["word"]!,
            .sentence: sentimentScore["sentence"]!,
            .all: sentimentScore["all"]!
        ]
        let frequency = coder.decodeDouble(forKey: "pitchFrequency")
        if frequency > 0 {
            do {
                self.pitch = try Pitch(frequency: frequency)
            } catch {
                print("\t[Error] There was a problem reproducing NoteSegment pitch")
            }
        }
        self.avgPauseDuration = coder.decodeDouble(forKey: "avgPauseDuration")
        self.speakingRate = coder.decodeDouble(forKey: "speakingRate")
        self.voiceCommandWord = coder.decodeBool(forKey: "voiceCommandWord")
        let trackURL = Utils.getFileURL(of: coder.decodeObject(forKey: "trackURL") as! String)
        let trackID: CMPersistentTrackID = coder.decodeInt32(forKey: "trackID")
        let storedSourceTimeRange = coder.decodeObject(forKey: "sourceTimeRange") as! [String: [String: Int]]
        let sourceTimeRange = CMTimeRangeFromTimeToTime(
            start: CMTimeMake(
                value: Int64(storedSourceTimeRange["start"]!["value"]!),
                timescale: Int32(storedSourceTimeRange["start"]!["timescale"]!)
            ),
            end: CMTimeMake(
                value: Int64(storedSourceTimeRange["end"]!["value"]!),
                timescale: Int32(storedSourceTimeRange["end"]!["timescale"]!)
            )
        )
        let storedTargetTimeRange = coder.decodeObject(forKey: "targetTimeRange") as! [String: [String: Int]]
        let targetTimeRange = CMTimeRangeFromTimeToTime(
            start: CMTimeMake(
                value: Int64(storedTargetTimeRange["start"]!["value"]!),
                timescale: Int32(storedTargetTimeRange["start"]!["timescale"]!)
            ),
            end: CMTimeMake(
                value: Int64(storedTargetTimeRange["end"]!["value"]!),
                timescale: Int32(storedTargetTimeRange["end"]!["timescale"]!)
            )
        )
        super.init(
            url: trackURL,
            trackID: trackID,
            sourceTimeRange: sourceTimeRange,
            targetTimeRange: targetTimeRange
        )
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // update for new properties
    override var description: String {
        return "NoteSegment {\n\tuid: \(self.uid) \n\tclipUID: \(self.clipUID) \n\tspeakerUID: \(self.speakerUID) \n\tdateCreated: \(Utils.getDateString(date: self.dateCreated) ?? "nil") \n\tdateModified: \(Utils.getDateString(date: self.dateModified) ?? "nil") \n\tisDeleted: \(self.deleted) \n\trawWord: '\(self.word)' \n\tdisplayedWord: '\(self.getText(withTemporalSuggestions: self.note!.state?.withTemporalSuggestions ?? Utils.DEFAULT_WITH_TEMPORAL_SUGGESTIONS, withPunctuationSuggestions: self.note!.state?.withPunctuationSuggestions ?? Utils.DEFAULT_WITH_PUNCTUATION_SUGGESTIONS, withFormattingSuggestions: self.note!.state?.withFormattingSuggestions ?? Utils.DEFAULT_WITH_FORMATTING_SUGGESTIONS, strictlyAsWord: self.note!.state?.withTextStrictlyAsWords ?? Utils.DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS, withSpacePrefix: true))' \n\tsourceURL: \(self.sourceURL!.lastPathComponent) \n\trate: \(self.rate) \n\teffectiveDuration: \(self.effectiveDuration.seconds) \n\tpitch: \(self.pitch?.note.string ?? "nil") \n\tsourceTimeRange: (\n\t\tstart: \(self.timeMapping.source.start.seconds),\n\t\tend: \(self.timeMapping.source.end.seconds),\n\t\tduration: \(self.timeMapping.source.duration.seconds)\n\t) \n\ttargetTimeRange: (\n\t\tstart: \(self.timeMapping.target.start.seconds),\n\t\tend: \(self.timeMapping.target.end.seconds),\n\t\tduration: \(self.timeMapping.target.duration.seconds)\n\t) \n\tindex: \(self.index) \n\tphoneticallySimilarWords: \(String(describing: self.phoneticallySimilarWords)) \n\ttokenType: \(self.tokenType ?? NLTag(rawValue: "nil")) \n\tlexicalClass: \(self.lexicalClass ?? NLTag(rawValue: "nil")) \n\tnameType: \(self.nameType ?? NLTag(rawValue: "nil")) \n\tlemma: \(self.lemma ?? NLTag(rawValue: "nil")) \n\tbackgroundNoise: \(self.backgroundNoise) \n\tpower: \(self.power) \n\tavgNotePower: \(self.avgNotePower) \n\tsentence: \(String(describing: self.sentence)) \n\tsentimentScore: \(String(describing: self.sentimentScore)) \n\tisSilence: \(self.isSilence()) \n\tisPunctuation: \(self.isPunctuation()) \n\tisEmphasized: \(self.isEmphasized()) \n\tisNumber: \(self.isNumber()) \n\tisHomophone: \(self.isHomophone()) \n\tisSentenceTerminator: \(self.isSentenceTerminator()) \n\tisVoiceCommandWord: \(self.voiceCommandWord) \n\tavgPauseDuration: \(self.avgPauseDuration) \n\tspeakingRate: \(self.speakingRate)\n}"
    }
    
    // strong object equavalence
    static func ==(_ firstSegment: NoteSegment, _ secondSegment: NoteSegment) -> Bool {
        // We omit:
        // cachedText => not relevant
        // cachedGetTextArguments => not relevant
        // cachedIsValidLastSentenceWord => not relevant
        // cachedIsSentenceTerminator => not relevant
        return firstSegment.sourceURL == secondSegment.sourceURL &&
            firstSegment.sourceTrackID == secondSegment.sourceTrackID &&
            firstSegment.timeMapping.source.start == secondSegment.timeMapping.source.start &&
            firstSegment.timeMapping.source.end == secondSegment.timeMapping.source.end &&
            firstSegment.timeMapping.target.start == secondSegment.timeMapping.target.start &&
            firstSegment.timeMapping.target.end == secondSegment.timeMapping.target.end &&
            firstSegment.getUID() == secondSegment.getUID() &&
            firstSegment.getClipUID() == secondSegment.getClipUID() &&
            firstSegment.getSpeakerUID() == secondSegment.getSpeakerUID() &&
            firstSegment.getDateCreated() == secondSegment.getDateCreated() &&
            firstSegment.getDateModified() == secondSegment.getDateModified() &&
            firstSegment.isDeleted() == secondSegment.isDeleted() &&
            firstSegment.getText() == secondSegment.getText() &&
            firstSegment.getPhoneticallySimilarWords().elementsEqual(secondSegment.getPhoneticallySimilarWords()) &&
            firstSegment.isPunctuation() == secondSegment.isPunctuation() &&
            firstSegment.isSilence() == secondSegment.isSilence() &&
            firstSegment.isEmphasized() == secondSegment.isEmphasized() &&
            firstSegment.isNumber() == secondSegment.isNumber() &&
            firstSegment.isHomophone() == secondSegment.isHomophone() &&
            firstSegment.isVoiceCommandWord() == secondSegment.isVoiceCommandWord() &&
            firstSegment.isCommitted() == secondSegment.isCommitted() &&
            firstSegment.isValidSentenceLastWord() == secondSegment.isValidSentenceLastWord() &&
            firstSegment.isValidWord() == secondSegment.isValidWord() &&
            firstSegment.isActive() == secondSegment.isActive() &&
            firstSegment.isSentenceTerminator() == secondSegment.isSentenceTerminator() &&
            firstSegment.getTokenType() == secondSegment.getTokenType() &&
            firstSegment.getNameType() == secondSegment.getNameType() &&
            firstSegment.getLexicalClass() == secondSegment.getLexicalClass() &&
            firstSegment.getLemma() == secondSegment.getLemma() &&
            firstSegment.getSentiment() == secondSegment.getSentiment() &&
            firstSegment.getBackgroundNoise() == secondSegment.getBackgroundNoise() &&
            firstSegment.getPower() == secondSegment.getPower() &&
            firstSegment.getSentence() == secondSegment.getSentence() &&
            firstSegment.getSpeakingRate() == secondSegment.getSpeakingRate() &&
            firstSegment.getAvgPauseDuration() == secondSegment.getAvgPauseDuration() &&
            firstSegment.getIndex() == secondSegment.getIndex() &&
            firstSegment.getPitch() == secondSegment.getPitch() &&
            firstSegment.getNote() == secondSegment.getNote() &&
            firstSegment.getRate() == secondSegment.getRate() &&
            firstSegment.effectiveDuration == secondSegment.effectiveDuration
    }
    
    func checkRep() {
        var result = true
        // sourceTimeRange and targetTimeRange should have the same duration
        result = result && self.timeMapping.source.duration == self.timeMapping.target.duration
        // print("sourceTimeRange and targetTimeRange should have the same duration: ", self.timeMapping.source.duration.seconds, self.timeMapping.source.duration.seconds)
        // print("current result: ", result)
        
        // dateModified must be after dateCreated
        result = result && self.dateModified >= self.dateCreated
        // print("dateModified must be after dateCreated: ", self.dateModified, self.dateCreated)
        // print("current result: ", result)

        if !result {
            print("sourceTimeRange and targetTimeRange should have the same duration: ", self.timeMapping.source.duration.seconds, self.timeMapping.target.duration.seconds)
            fatalError("===== [Error] NoteSegment Representation Invariants were broken =====")
        }
    }
    
    /// Returns the text representation of the segment
    ///
    /// - Parameters:
    ///     - withTemporalSuggestions: Whether the result should incorporate spacing modifications based on silence periods
    ///     - withPunctuationSuggestions: Whether the result should incorporate punctuation suggestions based on silence periods
    ///     - withFormattingSuggestions: Whether the result should incorporate formatting suggestions based on sound intensity
    ///     - strictlyAsWord: Whether result should convert all punctuation symbols to words
    ///
    /// - Returns: A new string representation of the segment
    func getText(
        withTemporalSuggestions: Bool = false,
        withPunctuationSuggestions: Bool = false,
        withFormattingSuggestions: Bool = false,
        strictlyAsWord: Bool = false,
        withCapitalization: Bool = true,
        withSpacePrefix: Bool = false,
        forEcho: Bool = false
    ) -> String {
        guard let note = self.note else {
            fatalError("===== [Error] Segment is not associated with a note =====")
        }
        
        var argumentArr: [String] = []
        if withTemporalSuggestions {
            argumentArr.append("withTemporalSuggestions")
        }
        if withPunctuationSuggestions {
            argumentArr.append("withPunctuationSuggestions")
        }
        if withFormattingSuggestions {
            argumentArr.append("withFormattingSuggestions")
        }
        if strictlyAsWord {
            argumentArr.append("strictlyAsWord")
        }
        if withCapitalization {
            argumentArr.append("withCapitalization")
        }
        if withSpacePrefix {
            argumentArr.append("withSpacePrefix")
        }
        if forEcho {
            argumentArr.append("forEcho")
        }
        
        let argumentSet: Set = Set(argumentArr)
        
        // Use cached version if it exists
        if let cachedText = self.cachedText, let cachedGetTextArguments = self.cachedGetTextArguments, argumentSet == cachedGetTextArguments {
            return cachedText
        }
        
        var text = ""
        var capitalizeWord = false
        var exclaimWord = false
        var removeLeadingSpace = false
        var previousWordIsSentenceTerminator = false
        var previousWordIsValidLastSentenceWord = false
        var i = 1
        if self.isCommitted() && self.index > 0 && note.noteSegments.count > self.index {
            while self.index - i >= 0 {
                let segments = self.isCommitted() ? note.noteSegments : note.noteBuffer
                let previousSegment = segments[self.index - i]
                if previousSegment.isSilence() && !previousSegment.isVoiceCommandWord() && !previousSegment.isDeleted() {
                    if (self.index - i + 1) < segments.count && !segments[self.index - i + 1].isVoiceCommandWord() && !segments[self.index - i + 1].isDeleted() {
                        // IMPORTANT: A silence before voice command words is marked as not a sentence terminator to prevent double sentence termination when factoring silence after a voice command
                        // For this reason we must factor them when computing capitalizeWord

                        // we include withPunctuationSuggestions here to override value in isSentenceTerminator that comes from the note and not the getText argument
                        capitalizeWord = previousSegment.isSentenceTerminator() && withPunctuationSuggestions && withCapitalization
                        removeLeadingSpace = previousSegment.suggestsNewParagraph() && withPunctuationSuggestions // Should only be determined on silences
                    }

                    i += 1 // Only increment after we compute capitalizeWord so that we're using the right indices to fetch the right segments
                    previousWordIsSentenceTerminator = previousSegment.isSentenceTerminator()
                } else if previousSegment.isVoiceCommandWord() && !previousSegment.isDeleted() {
                    i += 1
                } else if previousSegment.isDeleted() {
                    i += 1
                } else {
                    previousWordIsSentenceTerminator = previousSegment.isSentenceTerminator()
                    previousWordIsValidLastSentenceWord = previousSegment.isValidSentenceLastWord()
                    exclaimWord = previousSegment.isEmphasized()
                    break
                }
            }
        }
        
        var nextWordIsConjunction = false
        var nextSegmentIsPunctuation = false // If next segment is punctuation, don't show suggested punctuation.
        var nextSegmentIsVoiceCommand = false // If next segment is voice command, it is not a sentence terminator
        var nextSegmentIsDeleted = false // If next segment is deleted, it is not a sentence terminator
        var nextSegmentIsSentenceTerminator = false // If next segment is a sentence terminator, we won't have a comma
        var j = 1
        var existsWordsAfterVoiceCommandAndDeleted = false // If there are no words after the voice command, we want to have a sentence terminator
        if self.isCommitted() && self.index + 1 < note.noteSegments.count  {
            let nextSegment = note.noteSegments[self.index + 1]
            nextWordIsConjunction = nextSegment.getLexicalClass() == .conjunction
            nextSegmentIsPunctuation = nextSegment.isPunctuation()
            nextSegmentIsVoiceCommand = nextSegment.isVoiceCommandWord()
            nextSegmentIsDeleted = nextSegment.isDeleted()
            nextSegmentIsSentenceTerminator = nextSegment.isSentenceTerminator()
            
            while self.index + j < note.noteSegments.count {
                let nextSegment = note.noteSegments[self.index + j]
                if !nextSegment.isVoiceCommandWord() && !nextSegment.isDeleted() {
                    existsWordsAfterVoiceCommandAndDeleted = true
                    break
                }
                
                j += 1
            }
        }

        // Handle Punctuation Suggestions
        if self.isSilence() && withPunctuationSuggestions && avgPauseDuration != Utils.UNKNOWN {
            // no need for self.word to be injected in string because
            // its the empty string for silence
            if previousWordIsSentenceTerminator && suggestsNewParagraph() {
                // New line
                text += "\n\n"
            } else if (!previousWordIsSentenceTerminator && previousWordIsValidLastSentenceWord) && !nextSegmentIsPunctuation && ((!nextSegmentIsVoiceCommand && !nextSegmentIsDeleted) || !existsWordsAfterVoiceCommandAndDeleted) && suggestsNewParagraph() {
                // New Paragraph
                // Sentence Terminators: Exclamation Mark, Question Mark, Period
                let terminator = self.sentence.text.count > 0 && Utils.isQuestion(sentence: self.sentence.text) ? "?" : "."
                let exclaimedTerminator = self.sentence.text.count > 0 && Utils.isQuestion(sentence: self.sentence.text) ? "?!" : "!"
                text += "\(exclaimWord ? exclaimedTerminator : terminator)\n\n"
            } else if (!previousWordIsSentenceTerminator && previousWordIsValidLastSentenceWord) && !nextSegmentIsPunctuation && ((!nextSegmentIsVoiceCommand && !nextSegmentIsDeleted) || !existsWordsAfterVoiceCommandAndDeleted) && suggestsNewSentence() {
                // Same Paragraph
                // Sentence Terminators: Exclamation Mark, Question Mark, Period
                let terminator = Utils.isQuestion(sentence: self.sentence.text) ? "?" : "."
                let exclaimedTerminator = Utils.isQuestion(sentence: self.sentence.text) ? "?!" : "!"
                text += "\(exclaimWord ? exclaimedTerminator : terminator)"
            } else if !previousWordIsSentenceTerminator && !nextSegmentIsSentenceTerminator && nextWordIsConjunction && suggestsNewComma() {
                // Comma
                text += ","
            }
        }

        // Handle Space Suggestions
        if self.isSilence() && withTemporalSuggestions && avgPauseDuration != Utils.UNKNOWN {
            let duration = self.timeMapping.target.duration.seconds
            if suggestsNewParagraph(includingFirstSegment: true) {
                // We're going to a new paragraph if we have withPunctuationSuggestions on
                text += String(repeating: " ", count: Int(ceil(2 * duration)))
            } else if suggestsNewSentence(includingFirstSegment: true) {
                text += String(repeating: " ", count: Int(ceil(2 * duration)))
            } else if suggestsNewComma(includingFirstSegment: true) {
                // No need for space here
                text += ""
            }
        }
        
        // Handle Space Prefix
        if !self.isSilence() && !self.isPunctuation() && withSpacePrefix && !removeLeadingSpace {
            text += " "
        }
        
        // Handle Punctuation
        if forEcho && self.isPunctuation() {
            text += " \(PunctuationMap[self.word] ?? "") \(self.word)"
        } else if strictlyAsWord && self.isPunctuation() {
            text += PunctuationMap[self.word] ?? self.word
        } else if self.isPunctuation() {
            text += self.word
        }
        
        // Handle alphanumerals
        if withFormattingSuggestions && !withCapitalization && self.isEmphasized() && !self.isSilence() && !self.isPunctuation() {
            text += self.word.uppercased()
        } else if !self.isSilence() && !self.isPunctuation() {
            // process word if none of the above have occurred
            text += capitalizeWord ? self.word.capitalized : self.word
        }
        
        // remove capitalization
        if !withCapitalization {
            text = text.lowercased()
        }
        
        if self.isValidCommaWord() {
            text += ","
        }

        // cached values
        self.cachedText = text
        self.cachedGetTextArguments = argumentSet
        return text
    }
    
    func getPhoneticallySimilarWords() -> [String] {
        return self.phoneticallySimilarWords
    }
    
    func getSemanticallySimilarWords() -> [(String, NLDistance)] {
        return self.semanticallySimilarWords
    }
    
    func isPunctuation() -> Bool {
        return self.tokenType == .punctuation || word.count == 1 && word.first!.isPunctuation
    }
    
    func isSilence() -> Bool {
        return self.word.count == 0
    }
    
    func isEmphasized() -> Bool {
        if self.power != Double.infinity && self.avgNotePower != Double.infinity && !self.isSilence() && !self.isVoiceCommandWord() && !self.isDeleted() {
            return self.power > self.avgNotePower + Utils.EMPHASIS_POWER_DELTA
        }
        
        return false
    }
    
    func isNumber() -> Bool {
        return self.tokenType == .number
    }
    
    func isHomophone() -> Bool {
        return self.phoneticallySimilarWords.count > 0
    }
    
    func isVoiceCommandWord() -> Bool {
        return self.voiceCommandWord
    }
    
    func isCommitted() -> Bool {
        return self.index != Int(Utils.UNKNOWN)
    }
    
    func isValidSentenceLastWord() -> Bool {
        guard let note = self.note, !self.voiceCommandWord else { return false }
        
        if let cachedIsValidSentenceLastWord = self.cachedIsValidSentenceLastWord {
            return cachedIsValidSentenceLastWord
        }
        
        var previousWordLexicalClass: NLTag?
        var previousWord = ""
        var i = 1
        if self.isCommitted() && self.index > 0 && note.noteSegments.count > self.index {
            while self.index - i >= 0 {
                let previousSegment = note.noteSegments[self.index - i]
                if previousSegment.isSilence() || previousSegment.isVoiceCommandWord() || previousSegment.isDeleted() {
                    i += 1
                } else {
                    previousWordLexicalClass = previousSegment.getLexicalClass()
                    previousWord = previousSegment.word
                    break
                }
            }
        }

        var isValidSentenceLastWord = false
        if let previousWordLexicalClass = previousWordLexicalClass, previousWordLexicalClass == .verb || (previousWordLexicalClass == .determiner && Determiners.isDemonstrative(previousWord)) || previousWordLexicalClass == .adverb, let lexicalClass = self.lexicalClass {
            // adjectives are allowed
            // e.g. it is beautiful
            // we can end sentence after "beautiful"
            // "is" is a verb
            // e.g. it is not that beautiful
            // we can end sentence after "beautiful"
            // determiners are allowed too
            // "that" is a determiner
            // e.g. it is not beautiful
            // adverbs are allowed too
            // I am doing this
            // "this" is a demonstrative
            // we can end after "this"
            isValidSentenceLastWord = lexicalClass != .conjunction && lexicalClass != .preposition && (lexicalClass != .determiner || (lexicalClass == .determiner && previousWord.count > 0 && (Determiners.isDemonstrative(self.word) || Determiners.isPossessivePronoun(self.word))))
        } else if let lexicalClass = self.lexicalClass {
            // e.g. that is a beautiful
            // we can't end sentence after beautiful
            // "a" is a determiner, more specifically an article
            // we can't end on an article
            isValidSentenceLastWord = lexicalClass != .conjunction && lexicalClass != .preposition && lexicalClass != .adjective && (lexicalClass != .determiner || (lexicalClass == .determiner && previousWord.count > 0 && (Determiners.isDemonstrative(self.word) || Determiners.isPossessivePronoun(self.word))))
        }
        
        // cached value
        self.cachedIsValidSentenceLastWord = isValidSentenceLastWord
        return isValidSentenceLastWord
    }
    
    func isValidCommaWord() -> Bool {
        guard let note = self.note, !self.voiceCommandWord else { return false }
        
        if let cachedIsValidCommaWord = self.cachedIsValidCommaWord {
            return cachedIsValidCommaWord
        }
        
        var nextSegmentLexicalClass: NLTag?
        var nextSegmentIsVoiceCommand = false // If next segment is voice command, it is not a sentence terminator
        var nextSegmentIsDeleted = false // If next segment is deleted, it is not a sentence terminator
        var nextSegmentIsSentenceTerminator = false // If next segment is a sentence terminator, we won't have a comma
        var j = 1
        if self.isCommitted() && self.index + 1 < note.noteSegments.count  {
            let nextSegment = note.noteSegments[self.index + 1]
            nextSegmentIsVoiceCommand = nextSegment.isVoiceCommandWord()
            nextSegmentIsDeleted = nextSegment.isDeleted()
            nextSegmentIsSentenceTerminator = nextSegment.isSentenceTerminator()
            
            while self.index + j < note.noteSegments.count {
                let nextSegment = note.noteSegments[self.index + j]
                if !nextSegment.isVoiceCommandWord() && !nextSegment.isDeleted() {
                    nextSegmentLexicalClass = nextSegment.getLexicalClass()
                    break
                }
                
                j += 1
            }
        }

        var isValidCommaWord = false
        if let lexicalClass = self.lexicalClass, let nextSegmentLexicalClass = nextSegmentLexicalClass, lexicalClass == .adjective && nextSegmentLexicalClass == .adjective && !nextSegmentIsVoiceCommand && !nextSegmentIsDeleted && !nextSegmentIsSentenceTerminator  {
            // list of adjectives
            isValidCommaWord = true
        }
        
        // cached value
        self.cachedIsValidCommaWord = isValidCommaWord
        return isValidCommaWord
    }
    
    /// Dependencies: computeSegmentTags
    func isSentenceTerminator() -> Bool {
        guard let note = self.note else { return false }
        
        if let cachedIsSentenceTerminator = self.cachedIsSentenceTerminator {
            return cachedIsSentenceTerminator
        }

        let withPunctuationSuggestions = self.note?.state?.withPunctuationSuggestions ?? false

        var previousWordIsValidLastSentenceWord = false
        var previousWordIsSentenceTerminator = false
        var i = 1
        if self.isCommitted() && self.index > 0 && note.noteSegments.count > self.index {
            while self.index - i >= 0 {
                let previousSegment = note.noteSegments[self.index - i]
                
                if previousSegment.isSilence() && !previousSegment.isVoiceCommandWord() && !previousSegment.isDeleted() {
                    i += 1
                    previousWordIsSentenceTerminator = previousSegment.isSentenceTerminator()
                } else if previousSegment.isVoiceCommandWord() && !previousSegment.isDeleted() {
                    i += 1
                } else if previousSegment.isDeleted() {
                    i += 1
                } else {
                    previousWordIsValidLastSentenceWord = previousSegment.isValidSentenceLastWord()
                    previousWordIsSentenceTerminator = previousSegment.isSentenceTerminator()
                    break
                }
            }
        }

        var nextSegmentIsPunctuation = false // If next segment is punctuation, don't show suggested punctuation.
        var nextSegmentIsVoiceCommand = false // If next segment is voice command, it is not a sentence terminator
        var nextSegmentIsDeleted = false // If next segment is deleted, it is not a sentence terminator
        var j = 1
        var existsWordsAfterVoiceCommandAndDeleted = false
        if self.isCommitted() && self.index + 1 < note.noteSegments.count  {
            let nextSegment = note.noteSegments[self.index + 1]
            nextSegmentIsPunctuation = nextSegment.isPunctuation()
            nextSegmentIsVoiceCommand = nextSegment.isVoiceCommandWord()
            nextSegmentIsDeleted = nextSegment.isDeleted()
            
            while self.index + j < note.noteSegments.count {
                let nextSegment = note.noteSegments[self.index + j]
                if !nextSegment.isVoiceCommandWord() && !nextSegment.isDeleted() {
                    existsWordsAfterVoiceCommandAndDeleted = true
                    break
                }
                
                j += 1
            }
        }
        
        if self.isSilence() && withPunctuationSuggestions && avgPauseDuration != Utils.UNKNOWN {
            if !previousWordIsSentenceTerminator && previousWordIsValidLastSentenceWord && !nextSegmentIsPunctuation && ((!nextSegmentIsVoiceCommand && !nextSegmentIsDeleted) || !existsWordsAfterVoiceCommandAndDeleted) && suggestsNewParagraph() {
                // cache value
                self.cachedIsSentenceTerminator = true
                return true
            } else if !previousWordIsSentenceTerminator && previousWordIsValidLastSentenceWord && !nextSegmentIsPunctuation && ((!nextSegmentIsVoiceCommand && !nextSegmentIsDeleted) || !existsWordsAfterVoiceCommandAndDeleted) && suggestsNewSentence() {
                // cache value
                self.cachedIsSentenceTerminator = true
                return true
            }
        }
        
        // cache value
        self.cachedIsSentenceTerminator = self.lexicalClass == .sentenceTerminator
        return self.lexicalClass == .sentenceTerminator
    }
    
    func isValidWord() -> Bool {
        return !self.isPunctuation() &&
            !self.isNumber() &&
            !self.isDeleted() &&
            !self.isVoiceCommandWord() &&
            !self.isSilence()
    }
    
    func isActive() -> Bool {
        return !self.isDeleted() &&
            !self.isVoiceCommandWord() &&
            !self.isSilence()
    }
    
    func getEffectiveDuration() -> CMTime {
        return self.effectiveDuration
    }
    
    func getTokenType() -> NLTag? {
        return self.tokenType
    }
    
    func getNameType() -> NLTag? {
        return self.nameType
    }
    
    func getLexicalClass() -> NLTag? {
        return self.lexicalClass
    }
    
    func getLemma() -> NLTag? {
        return self.lemma
    }
    
    func getSentiment() -> [ScaleUnitType:Float]? {
        if !isSilence() {
            return self.sentimentScore
        }
        
        return nil
    }
    
    func getSentimentScore(type: ScaleUnitType = .word) -> Float? {
        if !isSilence() {
            return self.sentimentScore[type]
        }
        
        return nil
    }
    
    func getBackgroundNoise() -> Double {
        return self.backgroundNoise
    }
    
    func setBackgroundNoise(noise: Double) {
        self.backgroundNoise = noise
        
        self.handleMutation()
        checkRep()
    }

    func getPower() -> Double {
        return self.power
    }
    
    func setPower(power: Double) {
        self.power = power
        
        self.handleMutation()
        checkRep()
    }
    
    func getSentence() -> Sentence {
        return self.sentence
    }
    
    func setSentence(sentence: Sentence) {
        self.sentence = sentence
        
        self.handleMutation()
        checkRep()
    }
    
    func getAvgPauseDuration() -> Double {
        return self.avgPauseDuration
    }
    
    func setAvgPauseDuration(duration: Double) {
        self.avgPauseDuration = duration
        
        self.handleMutation()
        checkRep()
    }
    
    func getSpeakingRate() -> Double {
        return self.speakingRate
    }
    
    func getSpeakerUID() -> String {
        return self.speakerUID
    }
    
    func setSpeakingRate(rate: Double) {
        self.speakingRate = rate
        
        self.handleMutation()
        checkRep()
    }
    
    func setIndex(index: Int) {
        self.index = index
        if self.scheduleNotificationSearch {
            self.runNotificationSearch()
        }
        
        self.handleMutation()
        checkRep()
    }
    
    func getIndex() -> Int {
        return self.index
    }

    func setPitch(pitch: Pitch) {
        if self.isSilence() {
            return
        }
        self.pitch = pitch
        
        self.handleMutation()
        checkRep()
    }
    
    func getPitch() -> Pitch? {
        if let pitch = self.pitch {
            return pitch
        }
        
        return nil
    }
    
    func setNote(note: Note) {
        self.note = note
        
        self.handleMutation()
        checkRep()
    }
    
    func getNote() -> Note? {
        return self.note
    }
    
    func setRate(rate: Float) {
        self.rate = rate.rounded(toPlaces: 1)
        
        self.handleMutation()
        checkRep()
    }
    
    func getRate() -> Float {
        return self.rate
    }
    
    func getDateCreated() -> Date {
        return Date(timeIntervalSince1970: self.dateCreated)
    }
    
    func getDateModified() -> Date {
        return Date(timeIntervalSince1970: self.dateModified)
    }
    
    func setIsVoiceCommandWord(to value: Bool) {
        self.voiceCommandWord = value
        
        self.handleMutation()
        checkRep()
    }
    
    func getUID() -> String {
        return self.uid
    }
    
    func getClipUID() -> String {
        return self.clipUID
    }
    
    func setUID(uid: String) {
        self.uid = uid
        
        self.handleMutation()
        checkRep()
    }
    
    func isDeleted() -> Bool {
        return self.deleted
    }
    
    func setIsDeleted(isDeleted: Bool) {
        self.deleted = isDeleted
        
        self.handleMutation()
        checkRep()
    }
    
    // MARK: - Mutating Methods
    
    func duplicate(newNote: Note? = nil, timeRange: CMTimeRange? = nil, withNewUID: Bool = false) -> NoteSegment {
        let duplicateSegment = NoteSegment(
            speakerUID: self.speakerUID,
            word: self.word,
            clipUID: self.clipUID,
            trackURL: self.sourceURL!,
            trackID: newNote != nil ? newNote!.tracks[0].trackID : self.sourceTrackID,
            phoneticallySimilarWords: self.getPhoneticallySimilarWords(),
            sourceTimeRange: self.timeMapping.source,
            targetTimeRange: timeRange != nil ? timeRange! : self.timeMapping.target,
            tokenType: self.tokenType,
            lexicalClass: self.lexicalClass,
            nameType: self.nameType,
            lemma: self.lemma,
            sentimentScore: self.sentimentScore,
            withPunctuationSuggestions: false,
            voiceCommandWord: self.voiceCommandWord
        )
        
        // Set UID
        let uid = withNewUID ? UUID().uuidString : self.uid
        duplicateSegment.uid = uid
        
        // Set Date Created
        duplicateSegment.dateCreated = self.dateCreated
        
        // Set Date Modified
        duplicateSegment.dateModified = self.dateModified
        
        // Set Is Delete
        duplicateSegment.setIsDeleted(isDeleted: self.deleted)
        
        // Set Note
        duplicateSegment.setNote(note: newNote != nil ? newNote! : self.note!)
        
        // Set segment index
        duplicateSegment.setIndex(index: self.index)
        
        // Set power
        duplicateSegment.setPower(power: self.power)
        
        // Set pitch
        if let pitch = self.pitch {
            // Import pitch
            duplicateSegment.setPitch(pitch: pitch)
        }
        
        // Set background noise
        duplicateSegment.setBackgroundNoise(noise: self.backgroundNoise)

        // Set avgPauseDuration
        duplicateSegment.setAvgPauseDuration(duration: self.avgPauseDuration)
        
        // Set speakingRate
        duplicateSegment.setSpeakingRate(rate: self.speakingRate)
        
        // Set Sentence
        duplicateSegment.setSentence(sentence: self.sentence)
        
        // Set is voice command
        duplicateSegment.setIsVoiceCommandWord(to: self.voiceCommandWord)
        
        // Set rate
        duplicateSegment.setRate(rate: self.rate)
        
        return duplicateSegment
    }
    
    // creates new sentence note object
    func createSentenceNote() -> Note? {
        if let note = self.note {
            let range = self.sentence.noteRange
            let segments = Array(note.noteSegments[range])
            let duplicateSegments = Utils.duplicateSegments(segments: segments)
            let uid = UUID().uuidString
            let note = Note(
                uid: uid,
                filename: "note-\(uid)",
                creatorUID: note.state.speaker.uid,
                segments: duplicateSegments
            )
            
            return note
        }
        
        return nil
    }
    
    func runNotificationSearch() {
        self.scheduleNotificationSearch = false

        if let note = self.note, note.speechRecognition.isListeningForSpeech && !note.noteManager.isExportingNote && AVAudioSession.isHeadphonesConnected && note.state.withPunctuationSuggestions && !self.voiceCommandWord && !self.deleted && self.isSilence() && self.suggestsNewParagraph() && self.isCommitted() && self.index >= 0 && (self.index + 1) < note.noteSegments.count && !note.noteSegments[self.index + 1].isVoiceCommandWord() {
            print("===== Note Segment: Run Notification Search =====")
            print("\tNote Segment is a new line. Present audio feedback")
            // Received newline punctuation suggestion
            // Headphones are connected
            
            // Give audio feedback
            let voice = Utils.getSynthesizerVoice(
                withGender: .female
            )
            let synthesizerItem = SynthesizerItem(
                synthesizer: note.speechSynthesis.speechSynthesizer,
                text: "New line.",
                voice: voice,
                rate: note.speechSynthesis.echoRate,
                volume: Utils.playbackVolume
            )
            note.speechSynthesis.synthesizerQueue.enqueue(synthesizerItem)
            // We intentionally do not exhaust queue here to it happens before passive echo if it has it
            if !note.state.withPassiveEcho {
                note.speechSynthesis.exhaustSynthesizerQueue()
            }
        } else if let note = self.note, note.speechRecognition.isListeningForSpeech && !note.noteManager.isExportingNote && AVAudioSession.isHeadphonesConnected && note.state.withPunctuationSuggestions && !self.voiceCommandWord && !self.deleted && self.isSilence() && self.suggestsNewSentence() && self.isCommitted() && self.index >= 0 && (self.index + 1) < note.noteSegments.count && !note.noteSegments[self.index + 1].isVoiceCommandWord() {
            print("===== Note Segment: Run Notification Search =====")
            print("\tNote Segment is a new sentence. Present audio feedback")
            // Received new sentence punctuation suggestion
            // Headphones are connected
            
            // Give audiio feedback
            let voice = Utils.getSynthesizerVoice(
                withGender: .female
            )
            let synthesizerItem = SynthesizerItem(
                synthesizer: note.speechSynthesis.speechSynthesizer,
                text: "New sentence.",
                voice: voice,
                rate: note.speechSynthesis.echoRate,
                volume: Utils.playbackVolume
            )
            note.speechSynthesis.synthesizerQueue.enqueue(synthesizerItem)
            // We intentionally do not exhaust queue here to it happens before passive echo if it has it
            if !note.state.withPassiveEcho {
                note.speechSynthesis.exhaustSynthesizerQueue()
            }
        }
        
        if let note = self.note, note.speechRecognition.isListeningForSpeech && !note.noteManager.isExportingNote && note.state.withPunctuationSuggestions && !self.voiceCommandWord && !self.deleted && self.isSilence() && self.suggestsNewParagraph() && self.isCommitted() && self.index >= 0 && (self.index + 1) < note.noteSegments.count && !note.noteSegments[self.index + 1].isVoiceCommandWord() {
            print("\tNote Segment is a new line. Present visual feedback")
            // Received newline punctuation suggestion
            // Headphones not are connected
            
            // Give visual feedback
            note.notifications.scheduleNotification(
                text: "New line suggestion.",
                duration: 3
            )
            note.notifications.exhaustNotificationQueue()
        } else if let note = self.note, note.speechRecognition.isListeningForSpeech && !note.noteManager.isExportingNote && note.state.withPunctuationSuggestions && !self.voiceCommandWord && !self.deleted && self.isSilence() && self.suggestsNewSentence() && self.isCommitted() && self.index >= 0 && (self.index + 1) < note.noteSegments.count && !note.noteSegments[self.index + 1].isVoiceCommandWord() {
            print("\tNote Segment is a new line. Present visual feedback")
            // Received new sentence punctuation suggestion
            // Headphones not are connected
            
            // Give visual feedback
            note.notifications.scheduleNotification(
                text: "New sentence suggestion.",
                duration: 3
            )
            note.notifications.exhaustNotificationQueue()
        }
    }
    
    // MARK: - Helper Functions
    
    func handleMutation() {
        // Update date modified
        self.dateModified = TimeInterval(Date().timeIntervalSince1970)
        
        // Clear out cached properties so they are computed again
        self.cachedText = nil
        self.cachedGetTextArguments = nil
        self.cachedIsValidSentenceLastWord = nil
        self.cachedIsSentenceTerminator = nil
    }
    
    func suggestsNewParagraph(includingFirstSegment: Bool = false) -> Bool {
//        if self.isSilence() && avgPauseDuration != Utils.UNKNOWN {
        if self.isSilence() {
            let duration = self.timeMapping.target.duration.seconds
            let isFirstSegment = self.timeMapping.target.start == CMTime.zero
            if duration > Utils.NEW_PARAGRAPH_PAUSE_DURATION && (includingFirstSegment || !isFirstSegment) {
                return true
            }
        }

        return false
    }
    
    func suggestsNewSentence(includingFirstSegment: Bool = false) -> Bool {
//        if self.isSilence() && avgPauseDuration != Utils.UNKNOWN {
        if self.isSilence() {
            let duration = self.timeMapping.target.duration.seconds
            let isFirstSegment = self.timeMapping.target.start == CMTime.zero
            if duration > Utils.NEW_SENTENCE_PAUSE_DURATION && (includingFirstSegment || !isFirstSegment) {
                return true
            }
        }
        
        return false
    }
    
    func suggestsNewComma(includingFirstSegment: Bool = false) -> Bool {
//        if self.isSilence() && avgPauseDuration != Utils.UNKNOWN {
        if self.isSilence() {
            let duration = self.timeMapping.target.duration.seconds
            let isFirstSegment = self.timeMapping.target.start == CMTime.zero
            if duration > Utils.COMMA_PAUSE_DURATION && (includingFirstSegment || !isFirstSegment) {
                return true
            }
        }
        
        return false
    }
}
