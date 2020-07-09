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
    
    static func isHeadphonePortType(portType: AVAudioSession.Port) -> Bool {
        return portType == AVAudioSession.Port.headphones
        || portType == AVAudioSession.Port.bluetoothA2DP
        || portType == AVAudioSession.Port.bluetoothHFP
        || portType == AVAudioSession.Port.bluetoothLE
    }

    var isHeadphonesConnected: Bool {
        return !currentRoute.outputs.filter { $0.isHeadphones }.isEmpty
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
