//
//  NSRange+Range.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/15/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

// Reference: https://stackoverflow.com/questions/45493826/how-to-convert-rangestring-index-to-nsrange
public extension NSRange {
    private init(string: String, lowerBound: String.Index, upperBound: String.Index) {
        let utf16 = string.utf16

        let lowerBound = lowerBound.samePosition(in: utf16)
        let location = utf16.distance(from: utf16.startIndex, to: lowerBound!)
        let length = utf16.distance(from: lowerBound!, to: upperBound.samePosition(in: utf16)!)

        self.init(location: location, length: length)
    }

    init(range: Range<String.Index>, in string: String) {
        self.init(string: string, lowerBound: range.lowerBound, upperBound: range.upperBound)
    }

    init(range: ClosedRange<String.Index>, in string: String) {
        self.init(string: string, lowerBound: range.lowerBound, upperBound: range.upperBound)
    }
}
