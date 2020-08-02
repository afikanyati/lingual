//
//  Double+Rounded.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/8/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

extension Double {
    /// Rounds the double to decimal places value
    func rounded(toPlaces places:Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
