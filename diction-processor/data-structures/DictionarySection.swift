//
//  DictionaryEntry.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/6/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

struct DictionarySection {
    var title: [String]
    var details: String
    var isAccordion: Bool
    var isExpanded: Bool = true
    var actions: [DictionaryAction]?
    var lines: [DictionaryLine]?
    
    func getTitle() -> String {
        return title[1..<title.count].reduce(title[0], { result, string in
            return "\(result) | \(string)"
        }).trimTrailingPunctuation()
    }
}
