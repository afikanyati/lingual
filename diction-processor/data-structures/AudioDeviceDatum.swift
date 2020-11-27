//
//  AudioDeviceDatum.swift
//  diction-processor
//
//  Created by Afika Nyati on 11/23/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

class AudioDeviceDatum: NSObject, NSCoding {
    var date: Date
    var deviceType: AudioDeviceType

    override var description: String {
        return "AudioDeviceDatum (\n\tdate: \(self.date)\n\tdeviceType:\(self.deviceType)\n)"
    }
    
    init(
        date: Date,
        deviceType: AudioDeviceType
    ) {
        self.date = date
        self.deviceType = deviceType
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.date, forKey: "date")
        coder.encode(self.deviceType.rawValue, forKey: "deviceType")
    }

    required init?(coder: NSCoder) {
        self.date = coder.decodeObject(forKey: "date") as! Date
        self.deviceType = AudioDeviceType.fromRawValue(rawValue: Int(truncatingIfNeeded: coder.decodeInt64(forKey: "deviceType")))!
    }
   
    func setDate(value: Date) {
        self.date = value
    }

    func setDeviceType(value: AudioDeviceType) {
        self.deviceType = value
    }
}
