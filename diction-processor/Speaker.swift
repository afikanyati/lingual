//
//  Speaker.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/24/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import AVFoundation

struct Speaker {
    var name: String
    var avatarURL: URL
    var playbackVoice: AVSpeechSynthesisVoice? {
        return Utils.getSynthesizerVoice(withGender: gender, vc: vc)
    }
    var pitch: Pitch?
    var gender: Gender {
        if let pitch = pitch, pitch.note.octave >= 4 {
            return .female
        }
        
        return .male
    }
    var vc: ViewController
    
    static func ==(_ firstSpeaker: Speaker, _ secondSpeaker: Speaker) -> Bool {
        return firstSpeaker.name == secondSpeaker.name &&
        firstSpeaker.avatarURL == secondSpeaker.avatarURL &&
        firstSpeaker.playbackVoice == secondSpeaker.playbackVoice &&
        firstSpeaker.gender == secondSpeaker.gender &&
        firstSpeaker.pitch?.frequency == secondSpeaker.pitch?.frequency
    }
}
