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
    var uid: String?
    var device: String
    var cloudKitRecordID: String?
    var name: String?
    var avatarURL: URL?
    var pitch: Pitch?
    var register: VocalRegister {
        if let pitch = pitch, pitch.note.octave >= 4 {
            return .female
        }
        
        return .male
    }
    
    init(device: String) {
        self.device = device
    }
    
    func encode(with coder: NSCoder) {
        if let uid = self.uid {
            coder.encode(uid, forKey: "uid")
        }
        coder.encode(self.device, forKey: "device")
        if let cloudKitRecordID = self.cloudKitRecordID {
            coder.encode(cloudKitRecordID, forKey: "cloudKitRecordID")
        }
        if let name = self.name {
            coder.encode(name, forKey: "name")
        }
        if let avatarURL = self.avatarURL {
            coder.encode(avatarURL.absoluteString, forKey: "avatarURL")
        }
        if let pitch = self.pitch {
            coder.encode(pitch.frequency, forKey: "pitchFrequency")
        }
    }

    required init?(coder: NSCoder) {
        if coder.containsValue(forKey: "uid") {
            self.uid = coder.decodeObject(forKey: "uid") as? String
        } else {
            self.uid = nil
        }
        self.device = coder.decodeObject(forKey: "device") as! String
        if coder.containsValue(forKey: "cloudKitRecordID") {
            self.cloudKitRecordID = coder.decodeObject(forKey: "cloudKitRecordID") as? String
        } else {
            self.cloudKitRecordID = nil
        }
        if coder.containsValue(forKey: "name") {
            self.name = coder.decodeObject(forKey: "name") as? String
        } else {
            self.name = nil
        }
        if coder.containsValue(forKey: "avatarURL"),
           let avatarURL = coder.decodeObject(forKey: "avatarURL") as? String
        {
            self.avatarURL = URL(string: avatarURL)
        } else {
            self.avatarURL = nil
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
            firstSpeaker.cloudKitRecordID == secondSpeaker.cloudKitRecordID &&
            firstSpeaker.name == secondSpeaker.name &&
            firstSpeaker.avatarURL == secondSpeaker.avatarURL &&
            firstSpeaker.pitch == secondSpeaker.pitch
    }
    
    func setUID(to uid: String) {
        self.uid = uid
    }
    
    func setCloudKitRecordID(to id: String) {
        self.cloudKitRecordID = id
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
        return "Speaker (\n\tuid: \(String(describing: self.uid)) \n\tdevice: \(self.device) \n\tcloudKitRecordID: \(String(describing: self.cloudKitRecordID)) \n\tname: \(String(describing: self.name)) \n\tavatarURL: \(String(describing: self.avatarURL?.absoluteString)) \n\tpitch: \(String(describing: self.pitch?.note.string)) \n\tregister: \(self.register)\n)"
    }
}
