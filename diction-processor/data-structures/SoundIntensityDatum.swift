//
//  SoundIntensityDatum.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/27/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

struct SoundIntensityDatum: CustomStringConvertible {
    var date: Date
    var power: Double

    var description: String {
        return "SoundIntensityDatum (\n\tdate: \(date)\n\tpower:\(power)\n)"
    }
   
    mutating func setDate(value: Date) {
        date = value
    }

    mutating func setDecibels(value: Double) {
        power = value
    }
}
