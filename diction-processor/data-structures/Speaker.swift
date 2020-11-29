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
    var uid: String
    var device: String
    var name: String?
    var avatarURL: URL?
    var pitch: Pitch?
    var register: VocalRegister {
        if let pitch = pitch, pitch.note.octave >= 4 {
            return .female
        }
        
        return .male
    }
    
    init(uid: String, device: String) {
        self.uid = uid
        self.device = device
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.uid, forKey: "uid")
        coder.encode(self.device, forKey: "device")
        coder.encode(self.name, forKey: "name")
        coder.encode(self.avatarURL?.absoluteString, forKey: "avatarURL")
        coder.encode(self.pitch?.frequency, forKey: "pitchFrequency")
    }

    required init?(coder: NSCoder) {
        self.uid = coder.decodeObject(forKey: "uid") as! String
        self.device = coder.decodeObject(forKey: "device") as! String
        self.name = coder.decodeObject(forKey: "name") as! String?
        if let avatarURL = coder.decodeObject(forKey: "avatarURL") as? String {
            self.avatarURL = URL(string: avatarURL)
        }
        let frequency = coder.decodeObject(forKey: "pitchFrequency") as? Double
        if let frequency = frequency {
            do {
                self.pitch = try Pitch(frequency: frequency)
            } catch {
                print("\t[Error] There was a problem reproducing Speaker pitch")
            }
        }
    }
    
    static func ==(_ firstSpeaker: Speaker, _ secondSpeaker: Speaker) -> Bool {
        return firstSpeaker.uid == secondSpeaker.uid &&
            firstSpeaker.device == secondSpeaker.device &&
            firstSpeaker.name == secondSpeaker.name &&
            firstSpeaker.avatarURL == secondSpeaker.avatarURL &&
            firstSpeaker.pitch == secondSpeaker.pitch
    }
    
    func setName(to name: String?) {
        self.name = name
    }
    
    func setAvatarURL(to url: URL?) {
        self.avatarURL = url
    }
    
    func setSpeakerPitch(to pitch: Pitch?) {
        self.pitch = pitch
    }
    
    override var description: String {
        return "Speaker (\n\tuid: \(self.uid) \n\tdevice: \(self.device) \n\tname: \(String(describing: self.name)) \n\tavatarURL: \(String(describing: self.avatarURL?.absoluteString)) \n\tpitch: \(String(describing: self.pitch?.note.string)) \n\tregister: \(self.register)\n)"
    }
}
