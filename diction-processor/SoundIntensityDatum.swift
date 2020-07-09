//
//  SoundIntensityDatum.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/27/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

struct SoundIntensityDatum {
    var date: Date
    var intensity: Float

    var description: String {
        return "SoundIntensityDatum {\n\tdate: \(date)\n\tintensity:\(intensity)\n}"
    }
   
   mutating func setDate(value: Date) {
       date = value
   }
   
   mutating func setIntensity(value: Float) {
       intensity = value
   }
}
