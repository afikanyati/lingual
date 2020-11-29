//
//  StateSnapshot.swift
//  diction-processor
//
//  Created by Afika Nyati on 11/22/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

@objc class NoteSnapshot: NSObject {
    // MARK: - Properties
    
    let note: Note
    let selectionAnchorCaret: Caret?
    let selectionFocusCaret: Caret?
    let selectionCachedAnchorCaret: Caret?
    let message: String
    
    // MARK: - Initialization
    init(
        note: Note,
        selectionAnchorCaret: Caret?,
        selectionFocusCaret: Caret?,
        selectionCachedAnchorCaret: Caret?,
        undo message: String
    ) {
        self.note = note
        self.selectionAnchorCaret = selectionAnchorCaret
        self.selectionFocusCaret = selectionFocusCaret
        self.selectionCachedAnchorCaret = selectionCachedAnchorCaret
        self.message = message
    }
    
    public override var description: String {
        return "NoteSnapshot {\n\tnote: \(self.note) \n\tanchorCaret: \(String(describing: self.selectionAnchorCaret)) \n\tfocusCaret: \(String(describing: self.selectionFocusCaret)) \n\tcachedAnchorCaret: \(String(describing: self.selectionCachedAnchorCaret)) \n\tmessage: \(self.message)\n}"
    }
    
    // MARK: - Types
    
    struct Diff {
        let from: NoteSnapshot
        let to: NoteSnapshot

        fileprivate init(from: NoteSnapshot, to: NoteSnapshot) {
            self.from = from
            self.to = to
        }

        var hasChanges: Bool {
            return from != to
        }
    }

    func diffed(with other: NoteSnapshot) -> Diff {
        return Diff(from: self, to: other)
    }
}

// MARK: - Equatable

extension NoteSnapshot {
    static func ==(_ firstSnapshot: NoteSnapshot, _ secondSnapshot: NoteSnapshot) -> Bool {
        return firstSnapshot.note == secondSnapshot.note &&
            firstSnapshot.message == secondSnapshot.message &&
            firstSnapshot.selectionAnchorCaret == secondSnapshot.selectionAnchorCaret &&
            firstSnapshot.selectionFocusCaret == secondSnapshot.selectionFocusCaret &&
            firstSnapshot.selectionCachedAnchorCaret == secondSnapshot.selectionCachedAnchorCaret
    }
}
