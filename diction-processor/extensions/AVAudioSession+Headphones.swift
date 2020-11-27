//
//  AVAudioSession+Headphones.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/3/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

extension AVAudioSession {

    static var isHeadphonesConnected: Bool {
        return sharedInstance().isHeadphonesConnected
    }
    
    static var bluetoothAudioConnected: Bool {
        return sharedInstance().bluetoothAudioConnected
    }
    
    static func isHeadphonePortType(portType: AVAudioSession.Port) -> Bool {
        return portType == AVAudioSession.Port.headphones
        || portType == AVAudioSession.Port.bluetoothA2DP
        || portType == AVAudioSession.Port.bluetoothHFP
        || portType == AVAudioSession.Port.bluetoothLE
    }

    var isHeadphonesConnected: Bool {
        return !currentRoute.outputs.filter { $0.isHeadphones }.isEmpty
    }
    
    // Reference: https://stackoverflow.com/questions/28928876/how-to-detect-if-a-bluetooth-headset-plugged-or-not-ios-8
    var bluetoothAudioConnected: Bool {
        let outputs = currentRoute.outputs
        for output in outputs {
            if output.portType == AVAudioSession.Port.bluetoothA2DP ||
                output.portType == AVAudioSession.Port.bluetoothHFP ||
                output.portType == AVAudioSession.Port.bluetoothLE
            {
                return true
            }
        }
        return false
    }
}

extension AVAudioSessionPortDescription {
    var isHeadphones: Bool {
        return portType == AVAudioSession.Port.headphones
            || portType == AVAudioSession.Port.bluetoothA2DP
            || portType == AVAudioSession.Port.bluetoothHFP
            || portType == AVAudioSession.Port.bluetoothLE
    }
}
