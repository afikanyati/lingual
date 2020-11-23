//
//  SoundIntensityDatum.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/27/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

class SoundIntensityDatum: NSObject, NSCoding {
    var date: Date
    var power: Double

    override var description: String {
        return "SoundIntensityDatum (\n\tdate: \(date)\n\tpower:\(power)\n)"
    }
    
    init(
        date: Date,
        power: Double
    ) {
        self.date = date
        self.power = power
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.date, forKey: "date")
        coder.encode(self.power, forKey: "power")
    }

    required init?(coder: NSCoder) {
        self.date = coder.decodeObject(forKey: "date") as! Date
        self.power = coder.decodeObject(forKey: "power") as! Double
    }
   
    func setDate(value: Date) {
        date = value
    }

    func setDecibels(value: Double) {
        power = value
    }
}
