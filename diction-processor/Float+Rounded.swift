//
//  Float+Rounded.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/8/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

extension Float {
    /// Rounds the float to decimal places value
    func rounded(toPlaces places:Int) -> Float {
        let divisor = pow(10.0, Float(places))
        return (self * divisor).rounded() / divisor
    }
}
