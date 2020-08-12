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
let COMMA_PAUSE_DURATION_MULTIPLIER: Double = 2
let NEW_SENTENCE_PAUSE_DURATION_MULTIPLIER: Double = 4
let NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER: Double = 6 // Very nice
let MAX_SEMANTICALLY_SIMILAR_WORDS = 5

class NoteSegment: AVCompositionTrackSegment {
    /// Reference to it's parent note
    weak private(set) var note: Note?
    /// Index of segment in note track
    private var index: Int = Int(Utils.UNKNOWN)
    /// Index of segment track
    private var trackIndex: Int
    /// A textual representation of note segment.
    internal var word : String
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
    private var sentence = Sentence(number: Int(Utils.UNKNOWN), text: "", timeRange: CMTimeRange.zero)
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
    private var voiceCommandWord: Bool
    
    /// Initializes the NoteSegment class instance
    ///
    /// - Parameters:
    ///     - note: Reference to it's parent note
    ///     - word: Supplies a textual representation of note segment.
    ///     - trackURL: The container file of the media presented by the track segment.
    ///     - trackID: The track ID of the container file of the media presented by the track segment.
    ///     - trackIndex: The track index in which the segment currently resides in the note.
    ///     - phoneticallySimilarWords: Supplies an array of similarly sounding words.
    ///     - timeRange: The time range of the track of the container file of the media presented by the segment.
    ///     - tokenType: Classifies token according to its broad type: word, punctuation, or whitespace.
    ///     - lexicalClass: Classifies token according to class: part of speech, type of punctuation, or whitespace.
    ///     - nameType: Classifies tokens according to whether they are part of a named entity.
    ///     - lemma: Supplies a stem form of a word token, if known.
    ///     - sentimentScore: Scores text as positive, negative, or neutral based on its sentiment polarity.
    init(
        note: Note? = nil,
        word: String,
        trackURL: URL, // Cannot be replaced. Read Only
        trackID: CMPersistentTrackID,
        trackIndex: Int,
        phoneticallySimilarWords: [String]?,
        sourceTimeRange : CMTimeRange,
        targetTimeRange: CMTimeRange,
        tokenType: NLTag?,
        lexicalClass: NLTag?,
        nameType: NLTag?,
        lemma: NLTag?,
        sentimentScore: [ScaleUnitType: Float]?,
        utterPunctuationSuggestion: Bool = false,
        voiceCommandWord: Bool = false
    ) {
        self.word = word
        self.tokenType = tokenType
        self.lexicalClass = lexicalClass
        self.nameType = nameType
        self.lemma = lemma
        self.voiceCommandWord = voiceCommandWord
        self.trackIndex = trackIndex
        
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
        
        if let note = self.note, AVAudioSession.isHeadphonesConnected && utterPunctuationSuggestion && self.isSilence() && self.suggestsNewParagraph() {
            // Received newline punctuation suggestion
            // Headphones are connected
            
            // Give auditory feedback
            let rate: Float = 0.52
            let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

            let synthesizerItem = SynthesizerItem(
                synthesizer: note.speechSynthesizer,
                text: "New line.",
                voice: voice,
                rate: rate,
                volume: note.playbackVolume
            )
            note.synthesizerQueue.enqueue(synthesizerItem)
            
            // Give haptic feedback
            hapticEngine.mediumImpact()
        } else if let note = self.note, !AVAudioSession.isHeadphonesConnected && utterPunctuationSuggestion && self.isSilence() && self.suggestsNewParagraph() {
            // Received newline punctuation suggestion
            // Headphones are connected
            
            // Give visual feedback
            DispatchQueue.main.async {
                note.vc!.registerAppNotification(text: "New line suggestion.")
            }
            
            // Give haptic feedback
            hapticEngine.lightImpact()
        } else if let note = self.note, AVAudioSession.isHeadphonesConnected && note.withPunctuationSuggestions && self.isSilence() && self.suggestsNewSentence() {
            // Received new sentence punctuation suggestion
            // Headphones are connected
            
            // Give auditory feedback
            let rate: Float = 0.52
            let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

            let synthesizerItem = SynthesizerItem(
                synthesizer: note.speechSynthesizer,
                text: "New sentence.",
                voice: voice,
                rate: rate,
                volume: note.playbackVolume
            )
            note.synthesizerQueue.enqueue(synthesizerItem)
            
            // Give haptic feedback
            hapticEngine.mediumImpact()
        } else if let note = self.note, !AVAudioSession.isHeadphonesConnected && note.withPunctuationSuggestions && utterPunctuationSuggestion && self.isSilence() && self.suggestsNewSentence() {
            // Received new sentence punctuation suggestion
            // Headphones are connected
            
            // Give visual feedback
            DispatchQueue.main.async {
                note.vc!.registerAppNotification(text: "New sentence suggestion.")
            }
            
            // Give haptic feedback
            hapticEngine.heavyImpact()
        }
        
        checkRep()
    }
    
    // update for new properties
    override var description: String {
        return "NoteSegment {\n\trawWord: '\(self.word)' \n\tdisplayedWord: '\(self.getText(withTemporalSuggestions: self.note?.withTemporalSuggestions ?? false, withPunctuationSuggestions: self.note?.withPunctuationSuggestions ?? false, withFormattingSuggestions: self.note?.withFormattingSuggestions ?? false, strictlyAsWord: self.note?.withTextStrictlyAsWords ?? false, withSpacePrefix: true))' \n\tsourceURL: \(self.sourceURL!.lastPathComponent) \n\tpitch: \(self.pitch?.note.string ?? "nil") \n\tsourceTimeRange: (\n\t\tstart: \(self.timeMapping.source.start.seconds),\n\t\tend: \(self.timeMapping.source.end.seconds),\n\t\tduration: \(self.timeMapping.source.duration.seconds)\n\t) \n\ttargetTimeRange: (\n\t\tstart: \(self.timeMapping.target.start.seconds),\n\t\tend: \(self.timeMapping.target.end.seconds),\n\t\tduration: \(self.timeMapping.target.duration.seconds)\n\t) \n\ttrackIndex: \(self.trackIndex) \n\tindex: \(self.index) \n\tphoneticallySimilarWords: \(String(describing: self.phoneticallySimilarWords)) \n\ttokenType: \(self.tokenType ?? NLTag(rawValue: "nil")) \n\tlexicalClass: \(self.lexicalClass ?? NLTag(rawValue: "nil")) \n\tnameType: \(self.nameType ?? NLTag(rawValue: "nil")) \n\tlemma: \(self.lemma ?? NLTag(rawValue: "nil")) \n\tbackgroundNoise: \(self.backgroundNoise) \n\tpower: \(self.power) \n\tavgNotePower: \(self.avgNotePower) \n\tsentence: \(String(describing: self.sentence)) \n\tsentimentScore: \(String(describing: self.sentimentScore)) \n\tisSilence: \(self.isSilence()) \n\tisPunctuation: \(self.isPunctuation()) \n\tisEmphasized: \(self.isEmphasized()) \n\tisNumber: \(self.isNumber()) \n\tisHomophone: \(self.isHomophone()) \n\tisSentenceTerminator: \(self.isSentenceTerminator()) \n\tisVoiceCommandWord: \(self.voiceCommandWord) \n\tavgPauseDuration: \(self.avgPauseDuration) \n\tspeakingRate: \(self.speakingRate)\n}"
    }
    
    static func ==(_ firstSegment: NoteSegment, _ secondSegment: NoteSegment) -> Bool {
        return firstSegment.sourceURL == secondSegment.sourceURL &&
            firstSegment.sourceTrackID == secondSegment.sourceTrackID &&
            firstSegment.getTrackIndex() == secondSegment.getTrackIndex() &&
            firstSegment.timeMapping.source.start == secondSegment.timeMapping.source.start &&
            firstSegment.timeMapping.source.end == secondSegment.timeMapping.source.end &&
            firstSegment.timeMapping.target.start == secondSegment.timeMapping.target.start &&
            firstSegment.timeMapping.target.end == secondSegment.timeMapping.target.end &&
            firstSegment.getText() == secondSegment.getText() &&
            firstSegment.getPhoneticallySimilarWords() == secondSegment.getPhoneticallySimilarWords() &&
            firstSegment.isPunctuation() == secondSegment.isPunctuation() &&
            firstSegment.isSilence() == secondSegment.isSilence() &&
            firstSegment.isEmphasized() == secondSegment.isEmphasized() &&
            firstSegment.isNumber() == secondSegment.isNumber() &&
            firstSegment.isHomophone() == secondSegment.isHomophone() &&
            firstSegment.isSentenceTerminator() == secondSegment.isSentenceTerminator() &&
            firstSegment.isVoiceCommandWord() == secondSegment.isVoiceCommandWord() &&
            firstSegment.getTokenType() == secondSegment.getTokenType() &&
            firstSegment.getNameType() == secondSegment.getNameType() &&
            firstSegment.getLexicalClass() == secondSegment.getLexicalClass() &&
            firstSegment.getLemma() == secondSegment.getLemma() &&
            firstSegment.getSentiment() == secondSegment.getSentiment() &&
            firstSegment.getBackgroundNoise() == secondSegment.getBackgroundNoise() &&
            firstSegment.getPower() == secondSegment.getPower() &&
            firstSegment.getSentence() == secondSegment.getSentence() &&
            firstSegment.getSpeakingRate() == secondSegment.getSpeakingRate() &&
            firstSegment.getAvgPauseDuration() == secondSegment.getAvgPauseDuration()
    }
    
    func checkRep() {
        var result = true
        // sourceTimeRange and targetTimeRange should have the same duration
        result = result && self.timeMapping.source.duration == self.timeMapping.target.duration
        // print("sourceTimeRange and targetTimeRange should have the same duration: ", self.timeMapping.source.duration.seconds, self.timeMapping.source.duration.seconds)
        // print("current result: ", result)

        if !result {
            print("sourceTimeRange and targetTimeRange should have the same duration: ", self.timeMapping.source.duration.seconds, self.timeMapping.target.duration.seconds)
            fatalError("===== [Error] Representation Invariants were broken =====")
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
        withSpacePrefix: Bool = false,
        forEcho: Bool = false
    ) -> String {
        var text = ""
        var capitalizeWord = false
        var exclaimWord = false
        var removeLeadingSpace = false
        var previousWordIsSentenceTerminator = false
        var previousWordIsValidLastSentenceWord = false
        var previousSegmentIsVoiceCommand = false // If previous segment is voice command, don't use punctuation suggestion for silence
        var i = 1
        if let note = self.note, self.index != Int(Utils.UNKNOWN) && self.index > 0 && note.noteTracks[self.trackIndex].count > self.index {
            while self.index - i >= 0 {
                let previousSegment = note.noteTracks[self.trackIndex][self.index - i]
                if previousSegment.isSilence() || previousSegment.isVoiceCommandWord() {
                    i += 1
                    capitalizeWord = previousSegment.isSentenceTerminator() && withPunctuationSuggestions // we include withPunctuationSuggestions here to override value in isSentenceTerminator that comes from the note and not the getText argument
                    previousSegmentIsVoiceCommand = previousSegment.isVoiceCommandWord()
                    previousWordIsSentenceTerminator = previousSegment.isSentenceTerminator()
                    
                    if !previousSegment.isVoiceCommandWord() {
                        removeLeadingSpace = withPunctuationSuggestions && previousSegment.suggestsNewParagraph() // Should only be determined on spaces
                    }
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
        var nextSegmentIsVoiceCommand = false // If next segment is punctuation, it is not a sentence terminator
        var j = 1
        var existsWordsAfterVoiceCommand = false // If there are no words after the voice command, we want to have a sentence terminator
        if let note = self.note, self.index != Int(Utils.UNKNOWN) && self.index + 1 < note.noteTracks[self.trackIndex].count  {
            let nextSegment = note.noteTracks[self.trackIndex][self.index + 1]
            nextWordIsConjunction = nextSegment.getLexicalClass() == .conjunction
            nextSegmentIsPunctuation = nextSegment.isPunctuation()
            nextSegmentIsVoiceCommand = nextSegment.isVoiceCommandWord()
            
            while self.index + j < note.noteTracks[self.trackIndex].count {
                let nextSegment = note.noteTracks[self.trackIndex][self.index + j]
                if !nextSegment.isVoiceCommandWord() {
                    existsWordsAfterVoiceCommand = true
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
                text += "\n\n"
            } else if ((!previousWordIsSentenceTerminator && previousWordIsValidLastSentenceWord) || (self.trackIndex == 1 && self.index == 0)) && !nextSegmentIsPunctuation && (!nextSegmentIsVoiceCommand || !existsWordsAfterVoiceCommand) && suggestsNewParagraph() {
                let terminator = self.sentence.text.count > 0 && Utils.isQuestion(sentence: self.sentence.text) ? "?" : "."
                let exclaimedTerminator = self.sentence.text.count > 0 && Utils.isQuestion(sentence: self.sentence.text) ? "?!" : "!"
                text += "\(exclaimWord ? exclaimedTerminator : terminator)\n\n"
            } else if ((!previousWordIsSentenceTerminator && previousWordIsValidLastSentenceWord) || (self.trackIndex == 1 && self.index == 0)) && !nextSegmentIsPunctuation && (!nextSegmentIsVoiceCommand || !existsWordsAfterVoiceCommand) && suggestsNewSentence() {
                let terminator = Utils.isQuestion(sentence: self.sentence.text) ? "?" : "."
                let exclaimedTerminator = Utils.isQuestion(sentence: self.sentence.text) ? "?!" : "!"
                text += "\(exclaimWord ? exclaimedTerminator : terminator)"
            } else if !previousWordIsSentenceTerminator && nextWordIsConjunction && !previousSegmentIsVoiceCommand && suggestsNewComma() {
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
        if withFormattingSuggestions && self.isEmphasized() && !self.isSilence() && !self.isPunctuation() {
            text += self.word.uppercased()
        } else if !self.isSilence() && !self.isPunctuation() {
            // process word if none of the above have occurred
            text += capitalizeWord ? self.word.capitalized : self.word
        }

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
        if self.power != Double.infinity && self.avgNotePower != Double.infinity && !isSilence() && !isVoiceCommandWord() {
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
    
    func isValidSentenceLastWord() -> Bool {
        if self.voiceCommandWord {
            return false
        }
        
        var previousWordLexicalClass: NLTag?
        var previousWord = ""
        var i = 1
        if let note = self.note, self.index != Int(Utils.UNKNOWN) && self.index > 0 && note.noteTracks[self.trackIndex].count > self.index {
            while self.index - i >= 0 {
                let previousSegment = note.noteTracks[self.trackIndex][self.index - i]
                if previousSegment.isSilence() || previousSegment.isVoiceCommandWord() {
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
        
        return isValidSentenceLastWord
    }
    
    func isSentenceTerminator() -> Bool {
        var withPunctuationSuggestions = false
        if let note = self.note {
            withPunctuationSuggestions = note.withPunctuationSuggestions
        }

        var previousWordIsValidLastSentenceWord = false
        var previousWordIsSentenceTerminator = false
        var i = 1
        if let note = self.note, self.index != Int(Utils.UNKNOWN) && self.index > 0 && note.noteTracks[self.trackIndex].count > self.index {
            while self.index - i >= 0 {
                let previousSegment = note.noteTracks[self.trackIndex][self.index - i]
                if previousSegment.isSilence() || previousSegment.isVoiceCommandWord() {
                    i += 1
                    previousWordIsSentenceTerminator = previousSegment.isSentenceTerminator()
                } else {
                    previousWordIsValidLastSentenceWord = previousSegment.isValidSentenceLastWord()
                    previousWordIsSentenceTerminator = previousSegment.isSentenceTerminator()
                    break
                }
            }
        }

        var nextSegmentIsPunctuation = false // If next segment is punctuation, don't show suggested punctuation.
        var nextSegmentIsVoiceCommand = false // If next segment is punctuation, it is not a sentence terminator
        var j = 1
        var existsWordsAfterVoiceCommand = false
        if let note = self.note, self.index != Int(Utils.UNKNOWN) && self.index + 1 < note.noteTracks[self.trackIndex].count  {
            let nextSegment = note.noteTracks[self.trackIndex][self.index + 1]
            nextSegmentIsPunctuation = nextSegment.isPunctuation()
            nextSegmentIsVoiceCommand = nextSegment.isVoiceCommandWord()
            
            while self.index + j < note.noteTracks[self.trackIndex].count {
                let nextSegment = note.noteTracks[self.trackIndex][self.index + j]
                if !nextSegment.isVoiceCommandWord() {
                    existsWordsAfterVoiceCommand = true
                    break
                }
                
                j += 1
            }
        }
        
        if self.isSilence() && withPunctuationSuggestions && avgPauseDuration != Utils.UNKNOWN {
            if !previousWordIsSentenceTerminator && previousWordIsValidLastSentenceWord && !nextSegmentIsPunctuation && (!nextSegmentIsVoiceCommand || !existsWordsAfterVoiceCommand) && suggestsNewParagraph() {
                return true
            } else if !previousWordIsSentenceTerminator && previousWordIsValidLastSentenceWord && !nextSegmentIsPunctuation && (!nextSegmentIsVoiceCommand || !existsWordsAfterVoiceCommand) && suggestsNewSentence() {
                return true
            }
        }
        
        return self.lexicalClass == .sentenceTerminator
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
        
        checkRep()
    }

    func getPower() -> Double {
        return self.power
    }
    
    func setPower(power: Double) {
        self.power = power
        
        checkRep()
    }
    
    func getSentence() -> Sentence {
        return self.sentence
    }
    
    func setSentence(sentence: Sentence) {
        self.sentence = sentence
        
        checkRep()
    }
    
    func getAvgPauseDuration() -> Double {
        return self.avgPauseDuration
    }
    
    func setAvgPauseDuration(duration: Double) {
        self.avgPauseDuration = duration
        
        checkRep()
    }
    
    func getSpeakingRate() -> Double {
        return self.speakingRate
    }
    
    func setSpeakingRate(rate: Double) {
        self.speakingRate = rate
        
        checkRep()
    }
    
    func setIndex(index: Int) {
        self.index = index
        
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
        
        checkRep()
    }
    
    func setIsVoiceCommandWord(to value: Bool) {
        self.voiceCommandWord = value
        
        checkRep()
    }
    
    func getTrackIndex() -> Int {
        return self.trackIndex
    }
    
    func setTrackIndex(index: Int) {
        self.trackIndex = index
        
        checkRep()
    }
    
    // MARK: - Mutating Methods
    
    func duplicate(newNote: Note? = nil, index: Int, trackIndex: Int? = nil, timeRange: CMTimeRange? = nil) -> NoteSegment {
        let duplicateSegment = NoteSegment(
            word: self.word,
            trackURL: self.sourceURL!,
            trackID: newNote != nil ? newNote!.tracks[0].trackID : self.sourceTrackID,
            trackIndex: trackIndex != nil ? trackIndex! : self.trackIndex,
            phoneticallySimilarWords: self.getPhoneticallySimilarWords(),
            sourceTimeRange: self.timeMapping.source,
            targetTimeRange: timeRange != nil ? timeRange! : self.timeMapping.target,
            tokenType: self.tokenType,
            lexicalClass: self.lexicalClass,
            nameType: self.nameType,
            lemma: self.lemma,
            sentimentScore: self.sentimentScore
        )
        
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
        
        return duplicateSegment
    }
    
    // creates new sentence note object
    func createSentenceNote(onCompletionHandler: @escaping (_ sentence: Note?) -> Void) {
        if let note = self.note {
            let range = self.sentence.timeRange
            Utils.trimNote(note: note, keeping: range, permanent: true) { note in
                onCompletionHandler(note)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    func suggestsNewParagraph(includingFirstSegment: Bool = false) -> Bool {
//        if self.isSilence() && avgPauseDuration != Utils.UNKNOWN {
        if self.isSilence() {
            let duration = self.timeMapping.target.duration.seconds
            let isFirstSegment = self.timeMapping.target.start == CMTime.zero
            if duration > NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER && (includingFirstSegment || !isFirstSegment) {
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
            if duration > NEW_SENTENCE_PAUSE_DURATION_MULTIPLIER && (includingFirstSegment || !isFirstSegment) {
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
            if duration > COMMA_PAUSE_DURATION_MULTIPLIER && (includingFirstSegment || !isFirstSegment) {
                return true
            }
        }
        
        return false
    }
}
