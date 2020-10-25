//
//  Sentence.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/27/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

struct Sentence: CustomStringConvertible {
    var number: Int
    var text: String
    var timeRange: CMTimeRange
    var noteRange: Range<Int>
    
    mutating func setNumber(value: Int) {
        number = value
    }
    
    mutating func setTimeRange(value: CMTimeRange) {
        timeRange = value
    }
    
    mutating func setNoteRange(value: Range<Int>) {
        noteRange = value
    }
    
    mutating func setText(value: String) {
        text = value
    }
    
    static func ==(_ firstSentence: Sentence, _ secondSentence: Sentence) -> Bool {
        return firstSentence.number == secondSentence.number &&
            firstSentence.text == secondSentence.text &&
            firstSentence.timeRange == secondSentence.timeRange &&
            firstSentence.noteRange == secondSentence.noteRange
    }
    
    var description: String {
        return "Sentence (\n\t\ttext: \(text)\n\t\tnumber: \(number)\n\t\tnoteRange: \(noteRange)\n\t\ttimeRange: (\n\t\t\tstart: \(timeRange.start.seconds),\n\t\t\tend: \(timeRange.end.seconds),\n\t\t\tduration: \(timeRange.duration.seconds)\n\t\t)\n\t)"
    }
}
