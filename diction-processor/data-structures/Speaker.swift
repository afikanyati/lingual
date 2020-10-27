//
//  Speaker.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/24/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import AVFoundation

class Speaker: NSObject, NSCoding {
    var name: String
    var avatarURL: URL
    var pitch: Pitch?
    var gender: Gender {
        if let pitch = pitch, pitch.note.octave >= 4 {
            return .female
        }
        
        return .male
    }
    
    init(
        name: String,
        avatarURL: URL,
        pitch: Pitch? = nil
    ) {
        self.name = name
        self.avatarURL = avatarURL
        if let pitch = pitch {
            self.pitch = pitch
        }
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.name, forKey: "name")
        coder.encode(self.avatarURL, forKey: "avatarURL")
        coder.encode(self.pitch, forKey: "pitch")
    }

    required init?(coder: NSCoder) {
        self.name = coder.decodeObject(forKey: "name") as! String
        self.avatarURL = coder.decodeObject(forKey: "avatarURL") as! URL
        self.pitch = coder.decodeObject(forKey: "pitch") as! Pitch?
    }
    
    static func ==(_ firstSpeaker: Speaker, _ secondSpeaker: Speaker) -> Bool {
        return firstSpeaker.name == secondSpeaker.name &&
        firstSpeaker.avatarURL == secondSpeaker.avatarURL &&
        firstSpeaker.gender == secondSpeaker.gender &&
        firstSpeaker.pitch?.frequency == secondSpeaker.pitch?.frequency
    }
    
    func setSpeakerPitch(to pitch: Pitch) {
        self.pitch = pitch
    }
}
