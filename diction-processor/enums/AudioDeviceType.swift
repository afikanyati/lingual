//
//  AudioDeviceType.swift
//  diction-processor
//
//  Created by Afika Nyati on 11/23/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

enum AudioDeviceType: Int {
    case bluetoothHeadphones
    case wiredHeadphones
    case speakers
    
    // Reference: https://stackoverflow.com/questions/26077358/access-an-enum-value-by-its-hashvalue
    static func fromRawValue(rawValue: Int) -> AudioDeviceType? {
        switch (rawValue) {
        case 0:
            return .bluetoothHeadphones
        case 1:
            return .wiredHeadphones
        case 2:
            return .speakers
        default:
            return nil
        }
   }
}
