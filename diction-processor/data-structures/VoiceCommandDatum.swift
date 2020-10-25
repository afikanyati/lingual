//
//  VoiceCommandDatum.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/17/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

struct VoiceCommandDatum: CustomStringConvertible {
    var date: Date
    var utteredSpeech: String
    var isValid: Bool
    var type: String?

    var description: String {
        return "VoiceCommandDatum (\n\tdate: \(date) \n\tutteredSpeech:\(utteredSpeech) \n\tisValid:\(isValid) \n\ttype:\(String(describing: type))\n)"
    }
}
