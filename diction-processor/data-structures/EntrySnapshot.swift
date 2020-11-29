//
//  StateSnapshot.swift
//  diction-processor
//
//  Created by Afika Nyati on 11/22/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

@objc class EntrySnapshot: NSObject {
    // MARK: - Properties
    
    let entry: Entry
    let selectionAnchorCaret: Caret?
    let selectionFocusCaret: Caret?
    let selectionCachedAnchorCaret: Caret?
    let message: String
    
    // MARK: - Initialization
    init(
        entry: Entry,
        selectionAnchorCaret: Caret?,
        selectionFocusCaret: Caret?,
        selectionCachedAnchorCaret: Caret?,
        undo message: String
    ) {
        self.entry = entry
        self.selectionAnchorCaret = selectionAnchorCaret
        self.selectionFocusCaret = selectionFocusCaret
        self.selectionCachedAnchorCaret = selectionCachedAnchorCaret
        self.message = message
    }
    
    public override var description: String {
        return "EntrySnapshot {\n\tentry: \(self.entry) \n\tanchorCaret: \(String(describing: self.selectionAnchorCaret)) \n\tfocusCaret: \(String(describing: self.selectionFocusCaret)) \n\tcachedAnchorCaret: \(String(describing: self.selectionCachedAnchorCaret)) \n\tmessage: \(self.message)\n}"
    }
    
    // MARK: - Types
    
    struct Diff {
        let from: EntrySnapshot
        let to: EntrySnapshot

        fileprivate init(from: EntrySnapshot, to: EntrySnapshot) {
            self.from = from
            self.to = to
        }

        var hasChanges: Bool {
            return from != to
        }
    }

    func diffed(with other: EntrySnapshot) -> Diff {
        return Diff(from: self, to: other)
    }
}

// MARK: - Equatable

extension EntrySnapshot {
    static func ==(_ firstSnapshot: EntrySnapshot, _ secondSnapshot: EntrySnapshot) -> Bool {
        return firstSnapshot.entry == secondSnapshot.entry &&
            firstSnapshot.message == secondSnapshot.message &&
            firstSnapshot.selectionAnchorCaret == secondSnapshot.selectionAnchorCaret &&
            firstSnapshot.selectionFocusCaret == secondSnapshot.selectionFocusCaret &&
            firstSnapshot.selectionCachedAnchorCaret == secondSnapshot.selectionCachedAnchorCaret
    }
}
