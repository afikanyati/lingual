//
//  Dictionary+isEqual.swift
//  diction-processor
//
//  Created by Afika Nyati on 9/12/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

// Resource: https://stackoverflow.com/questions/47632263/comparing-two-string-any-dictionaries-in-swift-4
func isEqual (_ left: Any, _ right: Any) -> Bool {
    if  type(of: left) == type(of: right) &&
        String(describing: left) == String(describing: right) { return true }
    if let left = left as? [AnyHashable: Any], let right = right as? [AnyHashable: Any] { return left == right }
    return false
}

extension Dictionary where Value: Any {
    static func != (left: [Key : Value], right: [Key : Value]) -> Bool { return !(left == right) }
    static func == (left: [Key : Value], right: [Key : Value]) -> Bool {
        if left.count != right.count { return false }
        for element in left {
            guard   let rightValue = right[element.key],
                isEqual(rightValue, element.value) else { return false }
        }
        return true
    }
}
