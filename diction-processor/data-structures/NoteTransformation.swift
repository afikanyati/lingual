//
//  NoteTransformation.swift
//  diction-processor
//
//  Created by Afika Nyati on 9/16/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

struct NoteTransformation {
    var type: TransformationType
    var uids: [String: Int]
    var text: String
    var value: Float?
    var textRange: NSRange
    var noteRange: ClosedRange<Int>
    
    var description: String {
        return "\tTransformation (\n\ttype: \(type) \n\tuids: \(uids) \n\ttext: \(text) \n\tvalue: \(String(describing: value)) \n\ttextRange: \(textRange) \n\tnoteRange: \(noteRange)\n)"
    }
}
