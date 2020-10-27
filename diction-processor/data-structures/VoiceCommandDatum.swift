//
//  VoiceCommandDatum.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/17/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

class VoiceCommandDatum: CustomStringConvertible, NSCoding {
    var date: Date
    var utteredSpeech: String
    var isValid: Bool
    var type: String?
    init(
        date: Date,
        utteredSpeech: String,
        isValid: Bool,
        type: String? = nil
    ) {
        self.date = date
        self.utteredSpeech = utteredSpeech
        self.isValid = isValid
        if let type = type {
            self.type = type
        }
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.date, forKey: "date")
        coder.encode(self.utteredSpeech, forKey: "utteredSpeech")
        coder.encode(self.isValid, forKey: "isValid")
        coder.encode(self.type, forKey: "type")
    }

    required init?(coder: NSCoder) {
        self.date = coder.decodeObject(forKey: "date") as! Date
        self.utteredSpeech = coder.decodeObject(forKey: "utteredSpeech") as! String
        self.isValid = coder.decodeObject(forKey: "isValid") as! Bool
        self.type = coder.decodeObject(forKey: "type") as! String?
    }

    var description: String {
        return "VoiceCommandDatum (\n\tdate: \(date) \n\tutteredSpeech:\(utteredSpeech) \n\tisValid:\(isValid) \n\ttype:\(String(describing: type))\n)"
    }
}
