//
//  DictionaryAction.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/6/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

struct DictionaryAction {
    var tokens: [String]
    var description: String
    var example: String
    
    func getName() -> String {
        return tokens[1..<tokens.count].reduce(tokens[0], { result, string in
            return "\(result) | \(string)"
        }).trimTrailingPunctuation()
    }
}
