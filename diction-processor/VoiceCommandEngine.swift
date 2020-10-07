//
//  VoiceCommandEngine.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/24/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

public let voiceCommandEngine = VoiceCommandEngine.shared
public final class VoiceCommandEngine: NSObject {
    static let shared = VoiceCommandEngine()
    private let voiceCommands: Set = [
        "play note",
        "play not",
        "play notes",
        "pause note",
        "pause not",
        "pause notes",
        "new note",
        "start note",
        "start a note",
        "start not",
        "start notes",
        "stock note",
        "starting out",
        "stop note",
        "stop not",
        "stop notes",
        "resume note",
        "resume not",
        "resume notes",
        "continue note",
        "echo note",
        "echo notes",
        "ecko note",
        "ecko notes",
        "play ecko",
        "play echo",
        "start echo",
        "start ecko",
        "pause echo",
        "pause ecko",
        "stop echo",
        "stop ecko",
        "play last sentence",
        "play lost sentence",
        "play previous sentence",
        "echo last sentence",
        "echo lost sentence",
        "echo previous sentence",
        "ecko last sentence",
        "ecko lost sentence",
        "ecko previous sentence",
        "activate punctuation",
        "turn on punctuation",
        "deactivate punctuation",
        "turn off punctuation",
        "activate silences",
        "turn on silences",
        "deactivate silences",
        "turn off silences",
        "activate temporal suggestions",
        "turn on temporal suggestions",
        "deactivate temporal suggestions",
        "turn off temporal suggestions",
        "activate punctuation suggestions",
        "turn on punctuation suggestions",
        "deactivate punctuation suggestions",
        "turn off punctuation suggestions",
        "activate formatting suggestions",
        "turn on formatting suggestions",
        "deactivate formatting suggestions",
        "turn off formatting suggestions",
        "activate passive echo",
        "turn on passive echo",
        "deactivate passive echo",
        "turn off passive echo",
        "turn volume up",
        "turn volume down",
        "increase volume",
        "decrease volume",
        "adjust volume up",
        "adjust volume down",
        "volume up",
        "volume down",
        "just volume up",
        "i just volume up",
        "just volume down",
        "i just volume down",
        "adjust volume",
        "i just volume",
        "just volume",
        "change volume",
        "volume",
        "turn echo rate up",
        "turn echo rate down",
        "increase echo rate",
        "decrease echo rate",
        "adjust echo rate up",
        "adjust echo rate down",
        "echo rate up",
        "echo rate down",
        "just echo rate up",
        "i just echo rate up",
        "just echo rate down",
        "i just echo rate down",
        "turn playback rate up",
        "turn playback rate down",
        "increase playback rate",
        "decrease playback rate",
        "adjust playback rate up",
        "adjust playback rate down",
        "playback rate up",
        "playback rate down",
        "just playback rate up",
        "i just playback rate up",
        "just playback rate down",
        "i just playback rate down",
    ]
    
    let voiceCommandMapping: [String : String] = [
        "play note": "play note",
        "play not": "play note",
        "play notes": "play note",
        "pause note": "pause note",
        "pause not": "pause note",
        "pause notes": "pause note",
        "new note": "start note",
        "start note": "start note",
        "start a note": "start note",
        "start not": "start note",
        "start notes": "start note",
        "stock note": "start note",
        "starting out": "start note",
        "stop note": "stop note",
        "stop not": "stop note",
        "stop notes": "stop note",
        "resume note": "resume note",
        "resume not": "resume note",
        "resume notes": "resume note",
        "continue note": "resume note",
        "echo note": "echo note",
        "echo notes": "echo note",
        "ecko note": "echo note",
        "ecko notes": "echo note",
        "play ecko": "play echo",
        "play echo": "play echo",
        "start echo": "start echo",
        "start ecko": "start echo",
        "pause echo": "pause echo",
        "pause ecko": "pause echo",
        "stop echo": "stop echo",
        "stop ecko": "stop echo",
        "play last sentence": "play previous sentence",
        "play lost sentence": "play previous sentence",
        "play previous sentence": "play previous sentence",
        "ecko last sentence": "echo previous sentence",
        "ecko lost sentence": "echo previous sentence",
        "ecko previous sentence": "echo previous sentence",
        "echo last sentence": "echo previous sentence",
        "echo lost sentence": "echo previous sentence",
        "echo previous sentence": "echo previous sentence",
        "activate punctuation": "activate punctuation",
        "turn on punctuation": "activate punctuation",
        "deactivate punctuation": "deactivate punctuation",
        "turn off punctuation": "deactivate punctuation",
        "activate silences": "activate silences",
        "turn on silences": "activate silences",
        "deactivate silences": "deactivate silences",
        "turn off silences": "deactivate silences",
        "activate temporal suggestions": "activate temporal suggestions",
        "turn on temporal suggestions": "activate temporal suggestions",
        "deactivate temporal suggestions": "deactivate temporal suggestions",
        "turn off temporal suggestions": "deactivate temporal suggestions",
        "activate punctuation suggestions": "activate punctuation suggestions",
        "turn on punctuation suggestions": "activate punctuation suggestions",
        "deactivate punctuation suggestions": "deactivate punctuation suggestions",
        "turn off punctuation suggestions": "deactivate punctuation suggestions",
        "activate formatting suggestions": "activate formatting suggestions",
        "turn on formatting suggestions": "activate formatting suggestions",
        "deactivate formatting suggestions": "deactivate formatting suggestions",
        "turn off formatting suggestions": "deactivate formatting suggestions",
        "activate passive echo": "activate passive echo",
        "turn on passive echo": "activate passive echo",
        "deactivate passive echo": "deactivate passive echo",
        "turn off passive echo": "deactivate passive echo",
        "turn volume up": "increase volume",
        "turn volume down": "decrease volume",
        "increase volume": "increase volume",
        "decrease volume": "decrease volume",
        "adjust volume up": "increase volume",
        "adjust volume down": "decrease volume",
        "volume up": "increase volume",
        "volume down": "decrease volume",
        "just volume up": "increase volume",
        "i just volume up": "increase volume",
        "just volume down": "decrease volume",
        "i just volume down": "decrease volume",
        "adjust volume": "adjust volume",
        "i just volume": "adjust volume",
        "just volume": "adjust volume",
        "change volume": "adjust volume",
        "volume": "adjust volume",
        "turn echo rate up": "increase echo rate",
        "turn echo rate down": "decrease echo rate",
        "increase echo rate": "increase echo rate",
        "decrease echo rate": "decrease echo rate",
        "adjust echo rate up": "increase echo rate",
        "adjust echo rate down": "decrease echo rate",
        "echo rate up": "increase echo rate",
        "echo rate down": "decrease echo rate",
        "just echo rate up": "increase echo rate",
        "i just echo rate up": "increase echo rate",
        "just echo rate down": "decrease echo rate",
        "i just echo rate down": "decrease echo rate",
        "turn playback rate up": "increase playback rate",
        "turn playback rate down": "decrease playback rate",
        "increase playback rate": "increase playback rate",
        "decrease playback rate": "decrease playback rate",
        "adjust playback rate up": "increase playback rate",
        "adjust playback rate down": "decrease playback rate",
        "playback rate up": "increase playback rate",
        "playback rate down": "decrease playback rate",
        "just playback rate up": "increase playback rate",
        "i just playback rate up": "increase playback rate",
        "just playback rate down": "decrease playback rate",
        "i just playback rate down": "decrease playback rate",
    ]
    
    func includesCommand(passage: String) -> String? {
        let bagOfWords = passage.lowercased().components(separatedBy: " ")
        
        // Check for two word commands
        if bagOfWords.count > 2 {
            for i in 0..<bagOfWords.count - 1 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return self.voiceCommandMapping[phrase] ?? phrase
                }
            }
        } else if bagOfWords.count == 2 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return self.voiceCommandMapping[phrase] ?? phrase
            }
        }
        
        // Check for three word commands
        if bagOfWords.count > 3 {
            for i in 0..<bagOfWords.count - 2 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1]) \(bagOfWords[i+2])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return self.voiceCommandMapping[phrase] ?? phrase
                }
            }
        } else if bagOfWords.count == 3 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1]) \(bagOfWords[2])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return self.voiceCommandMapping[phrase] ?? phrase
            }
        }
        
        return nil
    }
    
    func process(note: Note, query: String, handler: (() -> Void)? = nil) {
        print("===== Processing Voice Command =====")
        let query = query.lowercased()
        print("\tQuery: \"\(self.voiceCommandMapping[query] ?? query)\"")
        
        switch (self.voiceCommandMapping[query]) {
        case "play note":
            // Play Sound
            soundEngine.voiceCommandAccept()

            playNote(note: note, handler: handler)
            break
        case "pause note":
            // Play Sound
            soundEngine.voiceCommandAccept()

            pauseNote(note: note, handler: handler)
            break
        case "start note":
            self.startListeningForSpeech(note: note, handler: handler)
            break
        case "stop note":
            if note.isListeningForSpeech {
                // Play Sound
                soundEngine.voiceCommandAccept()
                
                stopListeningForSpeech(note: note, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void  = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "No ongoing note.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
            break
        case "resume note":
            if note.isListeningForSpeech && note.pausedListeningForSpeech && note.isListeningForCommands {
                // Play Sound
                soundEngine.voiceCommandAccept()
                
                self.startListeningForSpeech(note: note, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void  = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "No ongoing note.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
            break
        case "echo note":
            if !note.isPlayingEcho && !note.isPlayingPassiveEcho {
                // Play Sound
                soundEngine.voiceCommandAccept()
                
                startEcho(note: note, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void  = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Echo already in progress.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
            break
        case "pause echo":
            if note.isPlayingEcho {
                // Play Sound
                soundEngine.voiceCommandAccept()
                
                pauseEcho(note: note, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void  = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Note not being echoed.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
            break
        case "stop echo":
            if note.isPlayingEcho || note.isPlayingPassiveEcho {
                // Play Sound
                soundEngine.voiceCommandAccept()

                stopEcho(note: note, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void  = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Note not being echoed.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
            break
        case "play previous sentence":
            // Play Sound
            soundEngine.voiceCommandAccept()

            playPreviousSentence(note: note, handler: handler)
            break
        case "echo previous sentence":
            // Play Sound
            soundEngine.voiceCommandAccept()

            echoPreviousSentence(note: note, handler: handler)
            break
        case "activate punctuation":
            // Play Sound
            soundEngine.voiceCommandAccept()

            activateSkipPunctuation(note: note, handler: handler)
            break
        case "deactivate punctuation":
            // Play Sound
            soundEngine.voiceCommandAccept()

            deactivatePassiveEcho(note: note, handler: handler)
            break
        case "activate silences":
            // Play Sound
            soundEngine.voiceCommandAccept()

            activateSilence(note: note, handler: handler)
            break
        case "deactivate silences":
            // Play Sound
            soundEngine.voiceCommandAccept()

            deactivateSilence(note: note, handler: handler)
            break
        case "activate temporal suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            activateTemporalSuggestions(note: note, handler: handler)
            break
        case "deactivate temporal suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            deactivateTemporalSuggestions(note: note, handler: handler)
            break
        case "activate punctuation suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            activatePunctuationSuggestions(note: note, handler: handler)
            break
        case "deactivate punctuation suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            deactivatePunctuationSuggestions(note: note, handler: handler)
            break
        case "activate formatting suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            activateFormattingSuggestions(note: note, handler: handler)
            break
        case "deactivate formatting suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            deactivateFormattingSuggestions(note: note, handler: handler)
            break
        case "activate passive echo":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            activatePassiveEcho(note: note, handler: handler)
        case "deactivate passive echo":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            deactivatePassiveEcho(note: note, handler: handler)
        case "increase volume":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            let currentVolume = note.vc!.playbackVolume
            let newVolume = min(currentVolume + Utils.DISCRETE_VOLUME_DELTA, Utils.MAXIMUM_VOLUME)
            if currentVolume < Utils.MAXIMUM_VOLUME {
                setPlaybackVolume(
                    note: note,
                    to: newVolume
                ) {
                    let errorHandler: () -> Void  = {
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Volume increased to \(newVolume)",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                    
                    if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForVoiceCommands(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForSpeech(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void  = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Volume already at maximum.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
        case "decrease volume":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            let currentVolume = note.vc!.playbackVolume
            let newVolume = max(currentVolume - Utils.DISCRETE_VOLUME_DELTA, Utils.MINIMUM_VOLUME)
            if currentVolume > Utils.MINIMUM_VOLUME {
                setPlaybackVolume(
                    note: note,
                    to: newVolume
                ) {
                    
                    let errorHandler: () -> Void  = {
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Volume decreased to \(newVolume)",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                    
                    if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForVoiceCommands(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForSpeech(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Volume already at minimum.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
        case "adjust volume":
            startListeningForVolume(note: note)
        case "increase echo rate":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            let currentEchoRate = note.vc!.echoRate
            let newEchoRate = min(currentEchoRate + Utils.DISCRETE_ECHO_RATE_DELTA, Utils.MAXIMUM_ECHO_RATE)
            if currentEchoRate < Utils.MAXIMUM_ECHO_RATE {
                setEchoRate(
                    note: note,
                    to: newEchoRate
                ) {
                    let errorHandler: () -> Void  = {
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Echo Rate increased to \(newEchoRate)",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                    
                    if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForVoiceCommands(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForSpeech(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void  = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Echo Rate already at fastest.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
        case "decrease echo rate":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            let currentEchoRate = note.vc!.echoRate
            let newEchoRate = max(currentEchoRate - Utils.DISCRETE_VOLUME_DELTA, Utils.MINIMUM_ECHO_RATE)
            if currentEchoRate > Utils.MINIMUM_ECHO_RATE {
                setEchoRate(
                    note: note,
                    to: newEchoRate
                ) {
                    
                    let errorHandler: () -> Void  = {
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Echo Rate decreased to \(newEchoRate)",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                    
                    if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForVoiceCommands(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForSpeech(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Echo Rate already at slowest.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
        case "increase playback rate":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            let currentPlaybackRate = note.vc!.playbackRate
            let newPlaybackRate = min(currentPlaybackRate + Utils.DISCRETE_PLAYBACK_DELTA, Utils.MAXIMUM_PLAYBACK_RATE)
            if currentPlaybackRate < Utils.MAXIMUM_PLAYBACK_RATE {
                setPlaybackRate(
                    note: note,
                    to: newPlaybackRate
                ) {
                    let errorHandler: () -> Void  = {
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Playback Rate increased to \(newPlaybackRate)",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                    
                    if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForVoiceCommands(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForSpeech(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void  = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Playback Rate already at fastest.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
        case "decrease playback rate":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
           let currentPlaybackRate = note.vc!.playbackRate
            let newPlaybackRate = max(currentPlaybackRate - Utils.DISCRETE_PLAYBACK_DELTA, Utils.MINIMUM_PLAYBACK_RATE)
            if currentPlaybackRate > Utils.MINIMUM_PLAYBACK_RATE {
                setPlaybackRate(
                    note: note,
                    to: newPlaybackRate
                ) {
                    
                    let errorHandler: () -> Void  = {
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Playback Rate decreased to \(newPlaybackRate)",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                    
                    if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForVoiceCommands(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                        note.stopListeningForSpeech(pause: true) {
                            Utils.runError(note: note, handler: errorHandler)
                        }
                    } else {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                let errorHandler: () -> Void = {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                        let synthesizerItem = SynthesizerItem(
                            synthesizer: note.vc!.speechSynthesizer,
                            text: "Playback Rate already at slowest.",
                            voice: voice,
                            rate: note.vc!.echoRate,
                            volume: note.vc!.playbackVolume
                        )
                        
                        note.vc!.emptySynthesizerQueue()
                        note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                        note.vc!.exhaustSynthesizerQueue()
                    }
                }
                
                if note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForVoiceCommands(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else if note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                    note.stopListeningForSpeech(pause: true) {
                        Utils.runError(note: note, handler: errorHandler)
                    }
                } else {
                    Utils.runError(note: note, handler: errorHandler)
                }
            }
        default:
            soundEngine.voiceCommandDeny()
            
            let queryArray = query.split(separator: " ")

            // Give visual feedback
            // Give audio feedback
            Utils.executeFeedback(
                visualMessage: "\"\(queryArray.count > 3 ? "\(queryArray.first!.lowercased())...\(queryArray.last!.lowercased())" : query)\"",
                audioMessage: note.isListeningForCommands ? "\"\(queryArray.count > 3 ? "\(queryArray.first!.lowercased())...\(queryArray.last!.lowercased())" : query)\"" : nil,
                note: note,
                discardPrior: true
            )
        }
    }

    func playNote(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Play Note")
        
        if !note.isPlayingNote {
            note.play(
                onStartHandler: {
                    DispatchQueue.main.async {
                        if !note.isListeningForSpeech {
                            note.vc!.adjustMenuBar()
                        }
                    }
                },
                secondElapseHandler: {
                    DispatchQueue.main.async {
                        if !note.isListeningForSpeech {
                            note.vc!.navigationItem.title = "\(Utils.formattedTime(time: Float(note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(note.getDuration(filteredDuration: false).seconds)))"
                        }
                    }
                },
                segmentBoundaryHandler: {
                    DispatchQueue.main.async {
                        if let segment = note.vc!.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let range = note.vc!.note.getSegmentTextRange(of: segment) {
                            // update text
                            note.vc!.updateUIText(text: note.getText(), highlightRange: range, transformations: note.transformations)
                        }
                        
                        if let segment = note.vc!.note.getSegment(type: .current), let pitch = segment.getPitch() {
                            // update pitch
                            note.vc!.pitchLabel.text = pitch.note.string
                        }
                    }
                }, onFinishHandler: {
                    DispatchQueue.main.async {
                        note.vc!.updateUIText(text: note.getText(), transformations: note.transformations)
                        note.vc!.note.player.replaceCurrentItem(with: nil)
                        if !note.isListeningForSpeech {
                            note.vc!.navigationItem.title = ""
                            note.vc!.adjustMenuBar()
                        }
                        handler?()
                    }
                }
            )
        }
    }
    
    func playPreviousSentence(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Play Previous Sentence")
        let previousSentenceIndex = max(note.numSentences - 1, 0)
        note.playSentence(
            number: previousSentenceIndex,
            onStartHandler: {
                DispatchQueue.main.async {
                    if !note.isListeningForSpeech {
                        note.vc!.adjustMenuBar()
                    }
                }
            },
            secondElapseHandler: {
                DispatchQueue.main.async {
                    if !note.isListeningForSpeech {
                        note.vc!.navigationItem.title = "\(Utils.formattedTime(time: Float(note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(note.getDuration(filteredDuration: false).seconds)))"
                    }
                }
            },
            segmentBoundaryHandler: {
                DispatchQueue.main.async {
                    if let segment = note.vc!.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let range = note.vc!.note.getSegmentTextRange(of: segment) {
                        // update text
                        note.vc!.updateUIText(text: note.getText(), highlightRange: range, transformations: note.transformations)
                    }
                    
                    if let segment = note.vc!.note.getSegment(type: .current), let pitch = segment.getPitch() {
                        // update pitch
                        note.vc!.pitchLabel.text = pitch.note.string
                    }
                }
            }, onFinishHandler: {
                DispatchQueue.main.async {
                    note.vc!.updateUIText(text: note.getText(), transformations: note.transformations)
                    note.vc!.note.player.replaceCurrentItem(with: nil)
                    if !note.isListeningForSpeech {
                        note.vc!.navigationItem.title = ""
                        note.vc!.adjustMenuBar()
                    }
                    handler?()
                }
            }
        )
    }
    
    func echoPreviousSentence(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Play Previous Sentence")
        let previousSentenceIndex = max(note.numSentences - 1, 0)
        note.echoSentence(number: previousSentenceIndex)
    }
    
    func pauseNote(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Pause Note")

        if note.isPlayingNote {
            note.pause() {
                DispatchQueue.main.async {
                    note.vc!.adjustMenuBar()
                }
            }
        } else if note.isListeningForSpeech {
            // stop listening for speech, start listening for commands
            note.stopListeningForSpeech(pause: true) {
                note.startListeningForVoiceCommands(
                    soundIntensityHandler: note.vc!.soundIntensityHandler!,
                    pitchHandler: note.vc!.pitchHandler!
                )
            }
        }
        
        handler?()
    }
    
    func startListeningForSpeech(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Start Listening For Speech")

        note.vc!.adjustMenuBar()
        note.vc!.clearTimedNotification()
        note.startListeningForSpeech(
            soundIntensityHandler: note.vc!.soundIntensityHandler!,
            pitchHandler: note.vc!.pitchHandler!,
            onStartHandler: {
                note.vc!.startRecordingUITimer(recording: true)
                handler?()
            }
        )
    }
    
    func stopListeningForSpeech(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Stop Listening For Speech")

        note.stopListeningForSpeech() {
            handler?()
        }
    }
    
    func startEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Start Echo")

        note.startEcho(
            text: note.getText(),
            onStartHandler: handler
        )
    }
    
    func pauseEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Pause Echo")

        note.pauseEcho(handler: handler)
    }
    
    func stopEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Stop Echo")
        note.stopEcho(handler: handler)
    }
    
    func trimNote(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Trim Note")

        // note.trim(keeping: <#T##CMTimeRange#>)
    }
    
    func activateSkipPunctuation(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Skip Punctuation")

        note.setSkipPunctuation(to: true)
        handler?()
    }
    
    func deactivateSkipPunctuation(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Skip Punctuation")

        note.setSkipPunctuation(to: false)
        handler?()
    }
    
    func activateSilence(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Silence")

        note.setOmitSilences(to: true)
        handler?()
    }
    
    func deactivateSilence(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Silence")

        note.setOmitSilences(to: false)
        handler?()
    }
    
    func activateTemporalSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Temporal Suggestions")

        note.setWithTemporalSuggestions(to: true)
        handler?()
    }
    
    func deactivateTemporalSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Temporal Suggestions")

        note.setWithTemporalSuggestions(to: false)
        handler?()
    }
    
    func activatePunctuationSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Punctuation Suggestions")
    
        note.setWithPunctuationSuggestions(to: true)
        handler?()
    }
    
    func deactivatePunctuationSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Punctuation Suggestions")
        
        note.setWithPunctuationSuggestions(to: false)
        handler?()
    }
    
    func activateFormattingSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Formatting Suggestions")
        
        note.setWithFormattingSuggestions(to: true)
        handler?()
    }
    
    func deactivateFormattingSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Formatting Suggestions")
        
        note.setWithFormattingSuggestions(to: false)
        handler?()
    }
    
    func activatePassiveEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Passive Echo")
        
        note.setWithPassiveEcho(to: true)
        handler?()
    }
    
    func deactivatePassiveEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Passive Echo")
        
        note.setWithPassiveEcho(to: false)
        handler?()
    }
    
    func setPlaybackRate(note: Note, to rate: Float, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Set Playback Rate")
        
        note.vc!.setPlaybackRate(to: rate)
        handler?()
    }
    
    func setEchoRate(note: Note, to rate: Float, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Set Echo Rate")
        
        note.vc!.setEchoRate(to: rate)
        handler?()
    }
    
    func setPlaybackVolume(note: Note, to volume: Float, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Set Playback Volume")
        
        Utils.setMainVolume(to: volume, note: note)
        handler?()
    }
    
    func startListeningForVolume(note: Note) {
        if note.isListeningForSpeech {
            note.stopListeningForSpeech() {
                note.vc!.startListeningForVolume()
            }
        } else if note.isListeningForCommands {
            note.stopListeningForVoiceCommands() {
                note.vc!.startListeningForVolume()
            }
        }
    }
}
