//
//  Sentence.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/27/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

struct Sentence {
    var number: Int
    var text: String
//    var total: Int
    var timeRange: CMTimeRange
    var description: String {
//        return "Sentence {\n\tnumber: \(number)\n\ttotal:\(total)\n\ttimeRange: (start: \(timeRange.start.seconds), end: \(timeRange.end.seconds))\n}"
        return "Sentence {\n\ttext: \(text)\n\tnumber: \(number)\n\ttimeRange: (start: \(timeRange.start.seconds), end: \(timeRange.end.seconds), duration: \(timeRange.duration.seconds)\n}"
    }
    
    mutating func setNumber(value: Int) {
        number = value
    }
    
//    mutating func setTotal(value: Int) {
//        total = value
//    }
    
    mutating func setTimeRange(value: CMTimeRange) {
        timeRange = value
    }
    
    mutating func setText(value: String) {
        text = value
    }
    
    static func ==(_ firstSentence: Sentence, _ secondSentence: Sentence) -> Bool {
        return firstSentence.number == secondSentence.number &&
//            firstSentence.total == secondSentence.total &&
            firstSentence.timeRange == secondSentence.timeRange
    }
}
