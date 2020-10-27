//
//  Sentence.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/27/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

class Sentence: CustomStringConvertible, NSCoding {
    var number: Int
    var text: String
    var timeRange: CMTimeRange
    var noteRange: Range<Int>
    
    init(
        number: Int,
        text: String,
        timeRange: CMTimeRange,
        noteRange: Range<Int>
    ) {
        self.number = number
        self.text = text
        self.timeRange = timeRange
        self.noteRange = noteRange
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.number, forKey: "number")
        coder.encode(self.text, forKey: "text")
        coder.encode(self.timeRange, forKey: "timeRange")
        coder.encode(self.noteRange, forKey: "noteRange")
    }
    
    required init?(coder: NSCoder) {
        self.number = Int(truncatingIfNeeded: coder.decodeInt64(forKey: "number"))
        self.text = coder.decodeObject(forKey: "text") as! String
        self.timeRange = coder.decodeObject(forKey: "timeRange") as! CMTimeRange
        self.noteRange = coder.decodeObject(forKey: "noteRange") as! Range<Int>
    }
    
   func setNumber(value: Int) {
        self.number = value
    }
    
    func setTimeRange(value: CMTimeRange) {
        self.timeRange = value
    }
    
    func setNoteRange(value: Range<Int>) {
        self.noteRange = value
    }
    
    func setText(value: String) {
        self.text = value
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
