//
//  MicrophoneDatum.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/15/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

class MicrophoneDatum: NSObject, NSCoding {
    var date: Date
    var softwareSampleRate: Double
    var hardwareSampleRate: Double
    
    init(
        date: Date,
        softwareSampleRate: Double,
        hardwareSampleRate: Double
    ) {
        self.date = date
        self.softwareSampleRate = softwareSampleRate
        self.hardwareSampleRate = hardwareSampleRate
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.date, forKey: "date")
        coder.encode(self.softwareSampleRate, forKey: "softwareSampleRate")
        coder.encode(self.hardwareSampleRate, forKey: "hardwareSampleRate")
    }

    required init?(coder: NSCoder) {
        self.date = coder.decodeObject(forKey: "date") as! Date
        self.softwareSampleRate = coder.decodeDouble(forKey: "softwareSampleRate")
        self.hardwareSampleRate = coder.decodeDouble(forKey: "hardwareSampleRate")
    }
    
    override var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        let dateString = dateFormatter.string(from: self.date)
        return "MicrophoneDatum (\n\tdate: \(dateString) \n\tsoftwareSampleRate: \(self.softwareSampleRate)Hz \n\thardwareSampleRate: \(self.hardwareSampleRate)Hz\n)"
    }
   
    func setDate(value: Date) {
        self.date = value
    }

    func setSoftwareSampleRate(value: Double) {
        self.softwareSampleRate = value
    }
    
    func setHardwareSampleRate(value: Double) {
        self.hardwareSampleRate = value
    }
}
