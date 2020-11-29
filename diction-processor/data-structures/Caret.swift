//
//  Caret.swift
//  diction-processor
//
//  Created by Afika Nyati on 11/25/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

// Reference: https://stackoverflow.com/questions/29027741/optional-dynamic-properties-in-swift
class Caret: NSObject {
    let index: Int
    let trackType: NoteTrackType
    init(
        index: Int,
        trackType: NoteTrackType
    ) {
        self.index = index
        self.trackType = trackType
    }
    
    public override var description: String {
        return "Caret {\n\tindex: \(self.index) \n\ttrackType: \(self.trackType)\n}"
    }
    
    static func ==(_ firstCaret: Caret, _ secondCaret: Caret) -> Bool {
        return firstCaret.index == secondCaret.index &&
            firstCaret.trackType == secondCaret.trackType
    }
    
    func duplicate() -> Caret {
        return Caret(index: self.index, trackType: self.trackType)
    }
}
