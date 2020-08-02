//
//  Date+Subtract.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/3/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

extension Date {
    static func - (lhs: Date, rhs: Date) -> TimeInterval {
        return lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate
    }
}
