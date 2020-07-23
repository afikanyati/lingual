//
//  SynthesizerItem.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/22/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

struct SynthesizerItem {
    var synthesizer: AVSpeechSynthesizer
    var text: String
    var voice: AVSpeechSynthesisVoice?
    var rate: Float
    var volume: Float
}
