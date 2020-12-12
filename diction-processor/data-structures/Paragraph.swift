//
//  Paragraph.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/9/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

class Paragraph: NSObject, NSCoding {
    var number: Int
    var text: String
    var timeRange: CMTimeRange
    var entryRange: Range<Int>
    
    init(
        number: Int,
        text: String,
        timeRange: CMTimeRange,
        entryRange: Range<Int>
    ) {
        self.number = number
        self.text = text
        self.timeRange = timeRange
        self.entryRange = entryRange
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.number, forKey: "number")
        coder.encode(self.text, forKey: "text")
        let timeRange: [String: [String: Int]] = [
            "start": [
                "value": Int(self.timeRange.start.value),
                "timescale": Int(self.timeRange.start.timescale)
            ],
            "end": [
                "value": Int(self.timeRange.end.value),
                "timescale": Int(self.timeRange.end.timescale)
            ]
        ]
        coder.encode(timeRange, forKey: "timeRange")
        let entryDictRange: [String:Int] = [
            "startIndex": self.entryRange.startIndex,
            "endIndex": self.entryRange.endIndex
        ]
        coder.encode(entryDictRange, forKey: "entryRange")
    }
    
    required init?(coder: NSCoder) {
        self.number = Int(truncatingIfNeeded: coder.decodeInt64(forKey: "number"))
        self.text = coder.decodeObject(forKey: "text") as! String
        let timeRange = coder.decodeObject(forKey: "timeRange") as! [String: [String: Int]]
        self.timeRange = CMTimeRangeFromTimeToTime(
            start: CMTimeMake(
                value: Int64(timeRange["start"]!["value"]!),
                timescale: Int32(timeRange["start"]!["timescale"]!)
            ),
            end: CMTimeMake(
                value: Int64(timeRange["end"]!["value"]!),
                timescale: Int32(timeRange["end"]!["timescale"]!)
            )
        )
        let entryDictRange = coder.decodeObject(forKey: "entryRange") as! [String:Int]
        self.entryRange = entryDictRange["startIndex"]!..<entryDictRange["endIndex"]!
    }
    
   func setNumber(value: Int) {
        self.number = value
    }
    
    func setTimeRange(value: CMTimeRange) {
        self.timeRange = value
    }
    
    func setEntryRange(value: Range<Int>) {
        self.entryRange = value
    }
    
    func setText(value: String) {
        self.text = value
    }
    
    static func ==(_ firstParagraph: Paragraph, _ secondParagraph: Paragraph) -> Bool {
        return firstParagraph.number == secondParagraph.number &&
            firstParagraph.text == secondParagraph.text &&
            firstParagraph.timeRange == secondParagraph.timeRange &&
            firstParagraph.entryRange == secondParagraph.entryRange
    }
    
    override var description: String {
        return "Paragraph (\n\t\ttext: \(text)\n\t\tnumber: \(number)\n\t\tentryRange: \(entryRange)\n\t\ttimeRange: (\n\t\t\tstart: \(timeRange.start.seconds),\n\t\t\tend: \(timeRange.end.seconds),\n\t\t\tduration: \(timeRange.duration.seconds)\n\t\t)\n\t)"
    }
}
