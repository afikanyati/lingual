//
//  String+Substring.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/3/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

extension String {
    var length: Int {
        return count
    }

    subscript (i: Int) -> String {
        return self[i ..< i + 1]
    }

    func substring(fromIndex: Int) -> String {
        return self[min(fromIndex, length) ..< length]
    }

    /// not including toIndex
    func substring(toIndex: Int) -> String {
        return self[0 ..< max(0, toIndex)]
    }

    subscript (r: Range<Int>) -> String {
        let range = Range(uncheckedBounds: (lower: max(0, min(length, r.lowerBound)),
                                            upper: min(length, max(0, r.upperBound))))
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(start, offsetBy: range.upperBound - range.lowerBound)
        return String(self[start ..< end])
    }
    
    func capitalizeFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }
    
    func replace(_ target: String, with: String) -> String
    {
        return self.replacingOccurrences(of: target, with: with, options: NSString.CompareOptions.literal, range: nil)
    }
    
    func trimTrailingPunctuation() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: .punctuationCharacters)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
