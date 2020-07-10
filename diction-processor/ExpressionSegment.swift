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

let EMPHASIS_DELTA: Double = 0.25
// https://remotepossibilities.wordpress.com/2013/03/10/when-you-speak-how-often-and-how-long-should-you-pause-the-answer-try-1-2-3/
let COMMA_PAUSE_DURATION_MULTIPLIER: Double = 1
let NEW_SENTENCE_PAUSE_DURATION_MULTIPLIER: Double = 2
let NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER: Double = 3
let MAX_SEMANTICALLY_SIMILAR_WORDS = 5

class ExpressionSegment: AVCompositionTrackSegment {
    /// A textual representation of expression segment.
    private var word : String
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
    private var backgroundNoise: Double = Double(Utils.UNKNOWN)
    /// The sound intensity of utterance at the time of recording.
    private var soundIntensity: Double = Double(Utils.UNKNOWN)
    /// Specifies information related to the sentence of the expression segment is a member of.
    private var sentence = Sentence(number: -1, timeRange: CMTimeRange.zero)
    /// Scores text as positive, negative, or neutral based on its sentiment polarity.
    private var sentimentScore: [ScaleUnitType:Float] = [
        .word: -1,
        .sentence: -1,
        .all: -1
    ]
    /// The pitch at which segment was uttered
    private var pitch: Pitch?
    /// The average pause duration between words, measured in seconds.
    private var avgPauseDuration: Double = Double(Utils.UNKNOWN)
    /// The number of words spoken per minute.
    private var speakingRate: Double = Double(Utils.UNKNOWN)
    
    /// Initializes the ExpressionSegment class instance
    ///
    /// - Parameters:
    ///     - word: Supplies a textual representation of expression segment.
    ///     - trackURL: The container file of the media presented by the track segment.
    ///     - trackID: The track ID of the container file of the media presented by the track segment.
    ///     - phoneticallySimilarWords: Supplies an array of similarly sounding words.
    ///     - timeRange: The time range of the track of the container file of the media presented by the segment.
    ///     - tokenType: Classifies token according to its broad type: word, punctuation, or whitespace.
    ///     - lexicalClass: Classifies token according to class: part of speech, type of punctuation, or whitespace.
    ///     - nameType: Classifies tokens according to whether they are part of a named entity.
    ///     - lemma: Supplies a stem form of a word token, if known.
    ///     - backgroundNoise: Supplies the average background noise at the time of recording.
    ///     - soundIntensity: Supplies the sound intensity of utterance at the time of recording.
    ///     - sentence: Specifies information related to the sentence of the expression segment is a member of.
    ///     - sentimentScore: Scores text as positive, negative, or neutral based on its sentiment polarity.
    ///     - avgPauseDuration: The average pause duration between words, measured in seconds.
    init(
        word: String,
        trackURL: URL,
        trackID: CMPersistentTrackID,
        phoneticallySimilarWords: [String]?,
        timeRange : CMTimeRange,
        tokenType: NLTag?,
        lexicalClass: NLTag?,
        nameType: NLTag?,
        lemma: NLTag?,
        sentimentScore: [ScaleUnitType: Float]?
    ) {
        self.word = word
        self.tokenType = tokenType
        self.lexicalClass = lexicalClass
        self.nameType = nameType
        self.lemma = lemma
        
        
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
            sourceTimeRange: timeRange,
            targetTimeRange: timeRange
        )
    }
    
    // update for new properties
    override var description: String {
        return "ExpressionSegment{\n\tword: '\(self.word)' \n\tpitch: \(String(describing: self.pitch)) \n\ttimeRange: (start: \(self.timeMapping.source.start), end: \(self.timeMapping.source.end.seconds), \n\tduration: \(self.timeMapping.source.duration.seconds)) \n\tphoneticallySimilarWords: \(String(describing: self.phoneticallySimilarWords)) \n\ttokenType: \(String(describing: self.tokenType)) \n\tlexicalClass: \(String(describing: self.lexicalClass)) \n\tnameType: \(String(describing: self.nameType)) \n\tlemma: \(String(describing: self.lemma)) \n\tbackgroundNoise: \(self.backgroundNoise) \n\tsoundIntensity: \(self.soundIntensity) \n\t sentence: \(self.sentence) \n\tsentimentScore: \(String(describing: self.sentimentScore)) \n\tisSilence: \(self.isSilence()) \n\tisPunctuation:\(self.isPunctuation()) \n\tisEmphasized: \(self.isEmphasized()) \n\tisNumber: \(self.isNumber()) \n\tisHomophone: \(self.isHomophone()) \n\tisSentenceTerminator: \(self.isSentenceTerminator()) \n\tavgPauseDuration: \(self.avgPauseDuration) \n\tspeakingRate: \(self.speakingRate)\n}"
    }
    
    static func ==(_ firstSegment: ExpressionSegment, _ secondSegment: ExpressionSegment) -> Bool {
        return firstSegment.sourceURL == secondSegment.sourceURL &&
            firstSegment.sourceTrackID == secondSegment.sourceTrackID &&
            firstSegment.timeMapping.source.start == secondSegment.timeMapping.source.start &&
            firstSegment.timeMapping.source.end == secondSegment.timeMapping.source.end &&
            firstSegment.getText() == secondSegment.getText() &&
            firstSegment.getPhoneticallySimilarWords() == secondSegment.getPhoneticallySimilarWords() &&
            firstSegment.isPunctuation() == secondSegment.isPunctuation() &&
            firstSegment.isSilence() == secondSegment.isSilence() &&
            firstSegment.isEmphasized() == secondSegment.isEmphasized() &&
            firstSegment.isNumber() == secondSegment.isNumber() &&
            firstSegment.isHomophone() == secondSegment.isHomophone() &&
            firstSegment.isSentenceTerminator() == secondSegment.isSentenceTerminator() &&
            firstSegment.getTokenType() == secondSegment.getTokenType() &&
            firstSegment.getNameType() == secondSegment.getNameType() &&
            firstSegment.getLexicalClass() == secondSegment.getLexicalClass() &&
            firstSegment.getLemma() == secondSegment.getLemma() &&
            firstSegment.getSentiment() == secondSegment.getSentiment() &&
            firstSegment.getBackgroundNoise() == secondSegment.getBackgroundNoise() &&
            firstSegment.getSoundIntensity() == secondSegment.getSoundIntensity() &&
            firstSegment.getSentence() == secondSegment.getSentence() &&
            firstSegment.getSpeakingRate() == secondSegment.getSpeakingRate() &&
            firstSegment.getAvgPauseDuration() == secondSegment.getAvgPauseDuration()
    }
    
    /// Returns the text representation of the segment
    ///
    /// - Parameters:
    ///     - withSpaceSuggestions: Whether the result should incorporate spacing modifications based on silence periods
    ///     - withPunctuationSuggestions: Whether the result should incorporate punctuation suggestions based on silence periods
    ///     - withFormattingSuggestions: Whether the result should incorporate formatting suggestions based on sound intensity
    ///     - strictlyAsWord: Whether result should convert all punctuation symbols to words
    ///
    /// - Returns: A new string representation of the segment
    func getText(withSpaceSuggestions: Bool = false, withPunctuationSuggestions: Bool = false, withFormattingSuggestions: Bool = false, strictlyAsWord: Bool = false) -> String {
        var text = ""
        if self.isSilence() && withPunctuationSuggestions, avgPauseDuration != Utils.UNKNOWN {
            let duration = self.timeMapping.source.duration.seconds
            let isFirstSegment = self.timeMapping.source.start == CMTime.zero
            if duration > NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER * max(1, avgPauseDuration) && !isFirstSegment {
                text += "\(self.word).\n\n"
            } else if duration > NEW_SENTENCE_PAUSE_DURATION_MULTIPLIER * max(1, avgPauseDuration) && !isFirstSegment {
                text += "\(self.word)."
            } else if duration > COMMA_PAUSE_DURATION_MULTIPLIER * max(1, avgPauseDuration) && !isFirstSegment {
                text += "\(self.word),"
            }
        }

        if self.isSilence() && withSpaceSuggestions, avgPauseDuration != Utils.UNKNOWN {
            let duration = self.timeMapping.source.duration.seconds
            if duration > NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER * max(1, avgPauseDuration) {
                // We're going to a new paragraph if we have withPunctuationSuggestions on
                if withPunctuationSuggestions {
                    text += ""
                } else {
                    text += String(repeating: " ", count: Int(round(4 * duration)))
                }
            } else if duration > NEW_SENTENCE_PAUSE_DURATION_MULTIPLIER * max(1, avgPauseDuration) {
                text += String(repeating: " ", count: Int(round(2 * duration)))
            } else if duration > COMMA_PAUSE_DURATION_MULTIPLIER * max(1, avgPauseDuration)
            {
                // No need for space here
                text += ""
            }
        }
        
        if withFormattingSuggestions && self.isEmphasized() {
            text += self.word.uppercased()
        }
        
        if strictlyAsWord && self.isPunctuation() {
            text += PunctuationMap[self.word] ?? self.word
        }
        
        if text.count == 0 && !self.isSilence() {
            // process word if none of the above have occurred
            text += self.word
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
        // To implement
        return self.soundIntensity > self.backgroundNoise + EMPHASIS_DELTA
    }
    
    func isNumber() -> Bool {
        return self.tokenType == .number
    }
    
    func isHomophone() -> Bool {
        return self.phoneticallySimilarWords.count > 0
    }
    
    func isSentenceTerminator(withPunctuationSuggestions: Bool = false) -> Bool {
        if withPunctuationSuggestions {
            let text = self.getText(withPunctuationSuggestions: true)
            let textHasSentenceTerminator = text.contains(".")
            return textHasSentenceTerminator || self.lexicalClass == .sentenceTerminator
        }
        
        return self.lexicalClass == .sentenceTerminator
    }
    
    func jumpsToNewParagraph() -> Bool {
        if self.isSilence() && avgPauseDuration != Utils.UNKNOWN {
            let duration = self.timeMapping.source.duration.seconds
            let isFirstSegment = self.timeMapping.source.start == CMTime.zero
            if duration > NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER * max(1, avgPauseDuration) && !isFirstSegment {
                return true
            }
        }
        
        return false
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
    }

    func getSoundIntensity() -> Double {
        return self.soundIntensity
    }
    
    func setSoundIntensity(intensity: Double) {
        self.soundIntensity = intensity
    }
    
    func getSentence() -> Sentence {
        return self.sentence
    }
    
    func setSentence(sentence: Sentence) {
        self.sentence = sentence
    }
    
    func getAvgPauseDuration() -> Double {
        return self.avgPauseDuration
    }
    
    func setAvgPauseDuration(duration: Double) {
        return self.avgPauseDuration = duration
    }
    
    func getSpeakingRate() -> Double {
        return self.speakingRate
    }
    
    func setSpeakingRate(rate: Double) {
        self.speakingRate = rate
    }

    func getSentenceExpression(expression: Expression) -> Expression? {
        let segments = expression.expressionSegments
        var sentenceSegments = [ExpressionSegment]()
        for segment in segments  {
            if segment.timeMapping.source.start >= sentence.timeRange.start && segment.timeMapping.source.end <= sentence.timeRange.end {
                sentenceSegments.append(segment)
            }
        }
        
        let sentence = Expression(
            vc: expression.vc!,
            speaker: expression.speaker,
            minDb: expression.minDb,
            withDeviceRecognition: expression.useOnDeviceRecognition
        )
        sentence.setSegments(segments: sentenceSegments)
        
        return nil
    }

    func setPitch(pitch: Pitch) {
        self.pitch = pitch
    }
    
    func getPitch() -> Pitch? {
        if let pitch = self.pitch {
            return pitch
        }
        
        return nil
    }
}
