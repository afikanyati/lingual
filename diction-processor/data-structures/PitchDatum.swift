//
//  PitchDatum.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/5/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

class PitchDatum: NSObject, NSCoding {
    var date: Date
    var pitch: Pitch?
    
    func encode(with coder: NSCoder) {
        coder.encode(self.date, forKey: "date")
        coder.encode(self.pitch?.frequency, forKey: "pitchFrequency")
    }
    
    init(
        date: Date,
        pitch: Pitch?
    ) {
        self.date = date
        self.pitch = pitch
    }
    
    required init?(coder: NSCoder) {
        self.date = coder.decodeObject(forKey: "date") as! Date
        let frequency = coder.decodeObject(forKey: "pitchFrequency") as? Double
        if let frequency = frequency {
            do {
                self.pitch = try Pitch(frequency: frequency)
            } catch {
                print("\t[Error] There was a problem reproducing PitchDatum pitch")
            }
        }
    }

    override var description: String {
        return "PitchDatum {\n\tdate: \(date)\n\tpitch:\(String(describing: pitch))\n}"
    }
   
   func setDate(value: Date) {
        self.date = value
   }
   
   func setPitch(value: Pitch) {
        self.pitch = value
   }
}
