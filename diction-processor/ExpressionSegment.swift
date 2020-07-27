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

let EMPHASIS_DELTA: Double = 0.15
// https://remotepossibilities.wordpress.com/2013/03/10/when-you-speak-how-often-and-how-long-should-you-pause-the-answer-try-1-2-3/
let COMMA_PAUSE_DURATION_MULTIPLIER: Double = 2
let NEW_SENTENCE_PAUSE_DURATION_MULTIPLIER: Double = 4
let NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER: Double = 6 // Very nice
let MAX_SEMANTICALLY_SIMILAR_WORDS = 5

class ExpressionSegment: AVCompositionTrackSegment {
    /// Reference to it's parent expression
    weak private(set) var expression: Expression?
    /// Index of segment in expression
    private var index: Int = Int(Utils.UNKNOWN)
    /// A textual representation of expression segment.
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
    private var backgroundNoise: Double = Double(Utils.UNKNOWN)
    /// The sound intensity of utterance at the time of recording.
    private var soundIntensity: Double = Double(Utils.UNKNOWN)
    private var avgExpressionSoundIntensity: Double {
        if let expr = self.expression {
            return expr.getSoundIntensity()
        }
        
        return Utils.UNKNOWN
    }
    /// Specifies information related to the sentence of the expression segment is a member of.
    private var sentence = Sentence(number: Int(Utils.UNKNOWN), text: "", timeRange: CMTimeRange.zero)
    /// Scores text as positive, negative, or neutral based on its sentiment polarity.
    private var sentimentScore: [ScaleUnitType:Float] = [
        .word: Float(Utils.UNKNOWN),
        .sentence: Float(Utils.UNKNOWN),
        .all: Float(Utils.UNKNOWN)
    ]
    /// The pitch at which segment was uttered
    private var pitch: Pitch?
    /// The average pause duration between words, measured in seconds.
    private var avgPauseDuration: Double = Double(Utils.UNKNOWN)
    /// The number of words spoken per minute.
    private var speakingRate: Double = Double(Utils.UNKNOWN)
    private var voiceCommandWord: Bool
    
    /// Initializes the ExpressionSegment class instance
    ///
    /// - Parameters:
    ///     - expression: Reference to it's parent expression
    ///     - word: Supplies a textual representation of expression segment.
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
        expression: Expression? = nil,
        word: String,
        trackURL: URL, // Cannot be replaced. Read Only
        trackID: CMPersistentTrackID,
        phoneticallySimilarWords: [String]?,
        timeRange : CMTimeRange,
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
        
        if let expression = expression {
            self.expression = expression
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
            sourceTimeRange: timeRange,
            targetTimeRange: timeRange
        )
        
        if let expression = self.expression, AVAudioSession.isHeadphonesConnected && utterPunctuationSuggestion && self.suggestsNewParagraph() {
            let rate: Float = 0.5
            let voice = Utils.getSynthesizerVoice(withGender: .female, vc: expression.vc)

            let synthesizerItem = SynthesizerItem(
                synthesizer: expression.speechSynthesizer,
                text: "New line.",
                voice: voice,
                rate: rate,
                volume: expression.playbackVolume
            )
            expression.synthesizerQueue.enqueue(synthesizerItem)
        } else if let expression = self.expression, AVAudioSession.isHeadphonesConnected && expression.withPunctuationSuggestions, utterPunctuationSuggestion && self.suggestsNewSentence() {
            let rate: Float = 0.5
            let voice = Utils.getSynthesizerVoice(withGender: .female, vc: expression.vc)

            let synthesizerItem = SynthesizerItem(
                synthesizer: expression.speechSynthesizer,
                text: "New sentence.",
                voice: voice,
                rate: rate,
                volume: expression.playbackVolume
            )
            expression.synthesizerQueue.enqueue(synthesizerItem)
        }
    }
    
    // update for new properties
    override var description: String {
        return "ExpressionSegment{\n\tword: '\(self.word)' \n\tpitch: \(self.pitch?.note.string ?? "nil") \n\ttimeRange: (start: \(self.timeMapping.source.start), end: \(self.timeMapping.source.end.seconds), \n\tduration: \(self.timeMapping.source.duration.seconds)) \n\tphoneticallySimilarWords: \(String(describing: self.phoneticallySimilarWords)) \n\ttokenType: \(self.tokenType ?? NLTag(rawValue: "nil")) \n\tlexicalClass: \(self.lexicalClass ?? NLTag(rawValue: "nil")) \n\tnameType: \(self.nameType ?? NLTag(rawValue: "nil")) \n\tlemma: \(self.lemma ?? NLTag(rawValue: "nil")) \n\tbackgroundNoise: \(self.backgroundNoise) \n\tsoundIntensity: \(self.soundIntensity) \n\tavgExpressionSoundIntensity: \(self.avgExpressionSoundIntensity) \n\t sentence: \(self.sentence) \n\tsentimentScore: \(String(describing: self.sentimentScore)) \n\tisSilence: \(self.isSilence()) \n\tisPunctuation:\(self.isPunctuation()) \n\tisEmphasized: \(self.isEmphasized()) \n\tisNumber: \(self.isNumber()) \n\tisHomophone: \(self.isHomophone()) \n\tisSentenceTerminator: \(self.isSentenceTerminator()) \n\tisVoiceCommandWord: \(self.voiceCommandWord) \n\tavgPauseDuration: \(self.avgPauseDuration) \n\tspeakingRate: \(self.speakingRate)\n}"
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
            firstSegment.isVoiceCommandWord() == secondSegment.isVoiceCommandWord() &&
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
    ///     - withTemporalSuggestions: Whether the result should incorporate spacing modifications based on silence periods
    ///     - withPunctuationSuggestions: Whether the result should incorporate punctuation suggestions based on silence periods
    ///     - withFormattingSuggestions: Whether the result should incorporate formatting suggestions based on sound intensity
    ///     - strictlyAsWord: Whether result should convert all punctuation symbols to words
    ///
    /// - Returns: A new string representation of the segment
    func getText(withTemporalSuggestions: Bool = false, withPunctuationSuggestions: Bool = false, withFormattingSuggestions: Bool = false, strictlyAsWord: Bool = false, withSpacePrefix: Bool = false, forEcho: Bool = false) -> String {
        var text = ""
        var capitalizeWord = false
        var exclaimWord = false
        var removeLeadingSpace = false
        var previousWordIsPunctuation = false
        var previousWordLexicalClass: NLTag?
        var previousWord = ""
        var i = 1
        if let expression = self.expression, self.index != Int(Utils.UNKNOWN) && self.index > 0 && expression.expressionSegments.count > self.index {
            while self.index - i >= 0 {
                let previousSegment = expression.expressionSegments[self.index - i]
                if previousSegment.isSilence() {
                    i += 1
                    capitalizeWord = previousSegment.isSentenceTerminator(withPunctuationSuggestions: withPunctuationSuggestions)
                    removeLeadingSpace = withPunctuationSuggestions && previousSegment.suggestsNewParagraph()
                } else {
                    previousWordIsPunctuation = previousSegment.isPunctuation()
                    previousWordLexicalClass = previousSegment.getLexicalClass()
                    previousWord = previousSegment.word
                    exclaimWord = previousSegment.isEmphasized()
                    break
                }
            }
        }
        
        var previousPreviousWordLexicalClass: NLTag?
//        var previousPreviousWord: String
        var j = i + 1
        if let expression = self.expression, self.index != Int(Utils.UNKNOWN) && self.index > 1 && expression.expressionSegments.count > self.index {
            while self.index - j >= 0 {
                let previousPreviousSegment = expression.expressionSegments[self.index - j]
                if previousPreviousSegment.isSilence() {
                    j += 1
                } else {
                    previousPreviousWordLexicalClass = previousPreviousSegment.getLexicalClass()
//                    previousPreviousWord = previousPreviousSegment.word
                    break
                }
            }
        }
        
        var previousWordIsValidLastSentenceWord = false
        if let previousPreviousWordLexicalClass = previousPreviousWordLexicalClass, previousPreviousWordLexicalClass == .verb, let previousWordLexicalClass = previousWordLexicalClass {
            // adjectives are allowed
            // e.g. that is beautiful
            // we can end sentence after "beautiful"
            // "is" is a verb
            // demonstratives are allowed too
            // I am doing this
            // "this" is a demonstrative
            // we can end after "this"
            previousWordIsValidLastSentenceWord = previousWordLexicalClass != .conjunction && previousWordLexicalClass != .preposition && (previousWordLexicalClass != .determiner || (previousWordLexicalClass == .determiner && previousWord.count > 0 && (Determiners.isDemonstrative(previousWord) || Determiners.isPossessivePronoun(previousWord))))
        } else if let previousWordLexicalClass = previousWordLexicalClass {
            // e.g. that is a beautifl
            // we can't end sentence after beautiful
            // "a" is a determiner, more specifically an article
            // we can't end on an article
            previousWordIsValidLastSentenceWord = previousWordLexicalClass != .conjunction && previousWordLexicalClass != .preposition && previousWordLexicalClass != .adjective && (previousWordLexicalClass != .determiner || (previousWordLexicalClass == .determiner && previousWord.count > 0 && (Determiners.isDemonstrative(previousWord) || Determiners.isPossessivePronoun(previousWord))))
            
        }
        
        var nextWordIsConjunction = false
        var nextWordIsPunctuation = false // If next segment is punctuation, don't show suggested punctuation.
        if let expression = self.expression, self.index != Int(Utils.UNKNOWN) && self.index + 1 < expression.expressionSegments.count  {
            let nextSegment = expression.expressionSegments[self.index + 1]
            nextWordIsConjunction = nextSegment.getLexicalClass() == .conjunction
            nextWordIsPunctuation = nextSegment.isPunctuation()
        }

        // Handle Punctuation Suggestions
        if self.isSilence() && withPunctuationSuggestions && avgPauseDuration != Utils.UNKNOWN {
            // no need for self.word to be injected in string because
            // its the empty string for silence
            if previousWordIsPunctuation && previousWordIsValidLastSentenceWord && suggestsNewParagraph() {
                text += "\n\n"
            } else if !previousWordIsPunctuation && previousWordIsValidLastSentenceWord && !nextWordIsPunctuation && suggestsNewParagraph() {
                let terminator = self.sentence.text.count > 0 && Utils.isQuestion(sentence: self.sentence.text) ? "?" : "."
                let exclaimedTerminator = self.sentence.text.count > 0 && Utils.isQuestion(sentence: self.sentence.text) ? "?!" : "!"
                text += "\(exclaimWord ? exclaimedTerminator : terminator)\n\n"
            } else if !previousWordIsPunctuation && previousWordIsValidLastSentenceWord && !nextWordIsPunctuation && suggestsNewSentence() {
                let terminator = Utils.isQuestion(sentence: self.sentence.text) ? "?" : "."
                let exclaimedTerminator = Utils.isQuestion(sentence: self.sentence.text) ? "?!" : "!"
                text += "\(exclaimWord ? exclaimedTerminator : terminator)"
            } else if !previousWordIsPunctuation && nextWordIsConjunction && !nextWordIsPunctuation && suggestsNewComma() {
                text += ","
            }
        }

        // Handle Space Suggestions
        if self.isSilence() && withTemporalSuggestions && avgPauseDuration != Utils.UNKNOWN {
            let duration = self.timeMapping.source.duration.seconds
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
        if self.soundIntensity != Double(Utils.UNKNOWN) && self.avgExpressionSoundIntensity != Double(Utils.UNKNOWN) {
            return self.soundIntensity > self.avgExpressionSoundIntensity + EMPHASIS_DELTA
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
    
    func isSentenceTerminator(withPunctuationSuggestions: Bool = false) -> Bool {
        var nextWordIsPunctuation = false // If next segment is punctuation, don't show suggested punctuation.
        if let expression = self.expression, self.index != Int(Utils.UNKNOWN) && self.index + 1 < expression.expressionSegments.count  {
            let nextSegment = expression.expressionSegments[self.index + 1]
            nextWordIsPunctuation = nextSegment.isPunctuation()
        }
        
        if withPunctuationSuggestions && (suggestsNewSentence() || suggestsNewParagraph()) && !nextWordIsPunctuation {
            return true
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
    
    func setIndex(index: Int) {
        self.index = index
    }
    
    func getIndex() -> Int {
        return self.index
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
    
    func setExpression(expression: Expression) {
        self.expression = expression
    }
    
    func setIsVoiceCommandWord(to value: Bool) {
        self.voiceCommandWord = value
    }
    
    // MARK: - Mutating Methods
    
    func duplicate(newExpression: Expression? = nil, index: Int, timeRange: CMTimeRange? = nil) -> ExpressionSegment {
        let duplicateSegment = ExpressionSegment(
            word: self.word,
            trackURL: newExpression != nil ? Utils.getFileURL(of: "\(newExpression!.filename)\(newExpression!.fileType)") : self.sourceURL!,
            trackID: newExpression != nil ? newExpression!.tracks[newExpression!.activeTrack].trackID : self.sourceTrackID,
            phoneticallySimilarWords: self.getPhoneticallySimilarWords(),
            timeRange: timeRange != nil ? timeRange! : self.timeMapping.source,
            tokenType: self.tokenType,
            lexicalClass: self.lexicalClass,
            nameType: self.nameType,
            lemma: self.lemma,
            sentimentScore: self.sentimentScore
        )
        
        // Set Expression
        duplicateSegment.setExpression(expression: newExpression != nil ? newExpression! : self.expression!)
        
        // Set segment index
        duplicateSegment.setIndex(index: self.index)
        
        // Set soundIntensity
        duplicateSegment.setSoundIntensity(intensity: self.soundIntensity)
        
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
        
        return duplicateSegment
    }
    
    // creates new sentence expression object
    func createSentenceExpression(onCompletionHandler: @escaping (_ sentence: Expression?) -> Void) {
        if let expression = self.expression {
            let range = self.sentence.timeRange
            Utils.trimExpression(expression: expression, keeping: range, permanent: true) { expression in
                onCompletionHandler(expression)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    func suggestsNewParagraph(includingFirstSegment: Bool = false) -> Bool {
//        if self.isSilence() && avgPauseDuration != Utils.UNKNOWN {
        if self.isSilence() {
            let duration = self.timeMapping.source.duration.seconds
            let isFirstSegment = self.timeMapping.source.start == CMTime.zero
            if duration > NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER && (includingFirstSegment || !isFirstSegment) {
                return true
            }
        }

        return false
    }
    
    func suggestsNewSentence(includingFirstSegment: Bool = false) -> Bool {
//        if self.isSilence() && avgPauseDuration != Utils.UNKNOWN {
        if self.isSilence() {
            let duration = self.timeMapping.source.duration.seconds
            let isFirstSegment = self.timeMapping.source.start == CMTime.zero
            if duration > NEW_SENTENCE_PAUSE_DURATION_MULTIPLIER && (includingFirstSegment || !isFirstSegment) {
                return true
            }
        }
        
        return false
    }
    
    func suggestsNewComma(includingFirstSegment: Bool = false) -> Bool {
        if self.isSilence() && avgPauseDuration != Utils.UNKNOWN {
            let duration = self.timeMapping.source.duration.seconds
            let isFirstSegment = self.timeMapping.source.start == CMTime.zero
            if duration > COMMA_PAUSE_DURATION_MULTIPLIER && (includingFirstSegment || !isFirstSegment) {
                return true
            }
        }
        
        return false
    }
}
