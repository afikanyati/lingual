//
//  VoiceCommandDatum.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/17/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

class VoiceCommandDatum: NSObject, NSCoding {
    var date: Date
    var utteredSpeech: String
    var isValid: Bool
    var type: VoiceCommandEngine.VoiceCommand?
    init(
        date: Date,
        utteredSpeech: String,
        isValid: Bool,
        type: VoiceCommandEngine.VoiceCommand? = nil
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
        if let type = self.type {
            coder.encode(type.value(), forKey: "type")
        }
    }

    required init?(coder: NSCoder) {
        self.date = coder.decodeObject(forKey: "date") as! Date
        self.utteredSpeech = coder.decodeObject(forKey: "utteredSpeech") as! String
        self.isValid = coder.decodeBool(forKey: "isValid")
        if coder.containsValue(forKey: "type"),
           let type = coder.decodeObject(forKey: "type") as? String,
           let command = VoiceCommandEngine.VoiceCommand(rawValue: type)
        {
            self.type = command
        } else {
            self.type = nil
        }
    }

    override var description: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        let dateString = dateFormatter.string(from: self.date)
        return "VoiceCommandDatum (\n\tdate: \(dateString) \n\tutteredSpeech:\(self.utteredSpeech) \n\tisValid:\(self.isValid) \n\ttype:\(String(describing: self.type))\n)"
    }
}
