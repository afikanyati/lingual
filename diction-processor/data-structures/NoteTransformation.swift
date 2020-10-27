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
    
    func encode(with coder: NSCoder) {
        coder.encode(self.type, forKey: "type")
        coder.encode(self.uids, forKey: "uids")
        coder.encode(self.text, forKey: "text")
        coder.encode(self.value, forKey: "value")
        coder.encode(self.textRange, forKey: "textRange")
        coder.encode(self.noteRange, forKey: "noteRange")
    }
    
    required init?(coder: NSCoder) {
        self.type = coder.decodeObject(forKey: "type") as! TransformationType
        self.uids = coder.decodeObject(forKey: "uids") as! [String: Int]
        self.text = coder.decodeObject(forKey: "text") as! String
        self.value = coder.decodeObject(forKey: "value") as! Float?
        self.textRange = coder.decodeObject(forKey: "textRange") as! NSRange
        self.noteRange = coder.decodeObject(forKey: "noteRange") as! ClosedRange<Int>
    }
    
    override var description: String {
        return "\tTransformation (\n\ttype: \(type) \n\tuids: \(uids) \n\ttext: \(text) \n\tvalue: \(String(describing: value)) \n\ttextRange: \(textRange) \n\tnoteRange: \(noteRange)\n)"
    }
}
