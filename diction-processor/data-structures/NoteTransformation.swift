//
//  NoteTransformation.swift
//  diction-processor
//
//  Created by Afika Nyati on 9/16/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

class NoteTransformation: NSObject, NSCoding {
    var type: TransformationType
    var uids: [String: Int]
    var text: String
    var value: Float?
    var textRange: NSRange
    var noteRange: ClosedRange<Int>
    
    init(
        type: TransformationType,
        uids: [String: Int],
        text: String,
        value: Float? = nil,
        textRange: NSRange,
        noteRange: ClosedRange<Int>
    ) {
        self.type = type
        self.uids = uids
        self.text = text
        self.textRange = textRange
        self.noteRange = noteRange
        if let value = value {
            self.value = value
        }
    }
    
    // Reference: https://stackoverflow.com/questions/36154590/how-to-encode-int-as-an-optional-using-nscoding
    func encode(with coder: NSCoder) {
        coder.encode(self.type.rawValue, forKey: "type")
        coder.encode(self.uids, forKey: "uids")
        coder.encode(self.text, forKey: "text")
        if let value = self.value {
            coder.encode(value, forKey: "value")
        }
        let textRange: [String:Int] = [
            "location": self.textRange.location,
            "length": self.textRange.length
        ]
        coder.encode(textRange, forKey: "textRange") // Can't handle NSRange objects
        let noteRange: [String:Int] = [
            "lowerBound": self.noteRange.lowerBound,
            "upperBound": self.noteRange.upperBound
        ]
        coder.encode(noteRange, forKey: "noteRange") // Can't handle ClosedRange objects
    }
    
    required init?(coder: NSCoder) {
        self.type = TransformationType.fromRawValue(rawValue: Int(truncatingIfNeeded: coder.decodeInt64(forKey: "type")))!
        self.uids = coder.decodeObject(forKey: "uids") as! [String: Int]
        self.text = coder.decodeObject(forKey: "text") as! String
        if coder.containsValue(forKey: "value") {
            self.value = coder.decodeFloat(forKey: "value")
        } else {
            self.value = nil
        }
        let textRange = coder.decodeObject(forKey: "textRange") as! [String:Int]
        self.textRange = NSRange(location: textRange["location"]!, length: textRange["length"]!)
        let noteRange = coder.decodeObject(forKey: "noteRange") as! [String:Int]
        self.noteRange = noteRange["lowerBound"]!...noteRange["upperBound"]!
    }
    
    override var description: String {
        return "\tTransformation (\n\ttype: \(type) \n\tuids: \(uids) \n\ttext: \(text) \n\tvalue: \(String(describing: value)) \n\ttextRange: \(textRange) \n\tnoteRange: \(noteRange)\n)"
    }
}
