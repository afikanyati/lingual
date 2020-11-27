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
    
    var note: Note
    var selectionAnchorCaret: Caret?
    var selectionFocusCaret: Caret?
    var selectionCachedAnchorCaret: Caret?
    var message: String
    
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
