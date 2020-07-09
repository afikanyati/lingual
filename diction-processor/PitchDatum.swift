//
//  PitchDatum.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/5/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

struct PitchDatum {
    var date: Date
    var pitch: Pitch

    var description: String {
        return "PitchDatum {\n\tdate: \(date)\n\tpitch:\(pitch)\n}"
    }
   
   mutating func setDate(value: Date) {
       date = value
   }
   
   mutating func setPitch(value: Pitch) {
       pitch = value
   }
}
