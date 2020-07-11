//
//  Demonstratives.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/11/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
// Determiners: https://dictionary.cambridge.org/grammar/british-grammar/determiners-the-my-some-this
// Demonstratives: https://www.ef.com/wwen/english-resources/english-grammar/demonstratives/
// Possessive Pronouns: https://teachergabriellemos.files.wordpress.com/2018/07/english-pronouns-small.png

class Determiners {
    private static let demonstratives: Set = ["this", "that", "these", "those", "here", "there"]
    private static let possessivePronouns: Set = ["mine", "yours", "his", "hers", "its", "ours", "theirs"]
    
    public static func isDemonstrative(_ value: String) -> Bool {
        let lowercaseValue = value.lowercased()
        return demonstratives.contains(lowercaseValue)
    }
    
    public static func isPossessivePronoun(_ value: String) -> Bool {
        let lowercaseValue = value.lowercased()
        return possessivePronouns.contains(lowercaseValue)
    }
}

