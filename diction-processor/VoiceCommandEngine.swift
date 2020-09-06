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
        "start note",
        "start not",
        "start notes",
        "stock note",
        "starting out",
        "stop note",
        "stop not",
        "stop notes",
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
        "volume"
    ]
    
    let voiceCommandMapping: [String : String] = [
        "play note": "play note",
        "play not": "play note",
        "play notes": "play note",
        "pause note": "pause note",
        "pause not": "pause note",
        "pause notes": "pause note",
        "start note": "start note",
        "start not": "start note",
        "start notes": "start note",
        "stock note": "start note",
        "starting out": "start note",
        "stop note": "stop note",
        "stop not": "stop note",
        "stop notes": "stop note",
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
        "volume": "adjust volume"
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
        
        switch (query) {
        case "play note", "play not", "play notes":
            // Play Sound
            soundEngine.voiceCommandAccept()

            playNote(note: note, handler: handler)
            break
        case "pause note", "pause not", "pause notes":
            // Play Sound
            soundEngine.voiceCommandAccept()

            pauseNote(note: note, handler: handler)
            break
        case "start note", "starting out", "start notes", "start not", "stock note":
            self.startListeningForSpeech(note: note, handler: handler)
            break
        case "stop note", "stop not", "stop notes":
            if note.isListeningForSpeech {
                // Play Sound
                soundEngine.voiceCommandAccept()
                
                stopListeningForSpeech(note: note, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.vc!.speechSynthesizer,
                        text: "No ongoing note.",
                        voice: voice,
                        rate: note.vc!.echoRate,
                        volume: note.vc!.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
            break
        case "echo note", "echo notes", "ecko note", "ecko notes", "play echo", "play ecko", "start echo", "start ecko":
            // Play Sound
            if !note.isPlayingEcho {
                soundEngine.voiceCommandAccept()
                
                startEcho(note: note, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.vc!.speechSynthesizer,
                        text: "Echo already in progress.",
                        voice: voice,
                        rate: note.vc!.echoRate,
                        volume: note.vc!.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
            break
        case "pause echo", "pause ecko":
            if note.isPlayingEcho {
                // Play Sound
                soundEngine.voiceCommandAccept()
                
                pauseEcho(note: note, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.vc!.speechSynthesizer,
                        text: "Note not being echoed.",
                        voice: voice,
                        rate: note.vc!.echoRate,
                        volume: note.vc!.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
            break
        case "stop echo", "stop ecko":
            if note.isPlayingEcho {
                // Play Sound
                soundEngine.voiceCommandAccept()
                
                stopEcho(note: note, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.vc!.speechSynthesizer,
                        text: "Note not being echoed.",
                        voice: voice,
                        rate: note.vc!.echoRate,
                        volume: note.vc!.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
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
        case "turn volume up", "increase volume", "adjust volume up", "volume up", "just volume up", "i just volume up":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            let currentVolume = note.vc!.playbackVolume
            if currentVolume < 1 {
                setPlaybackVolume(
                    note: note,
                    to: min(currentVolume + Utils.DISCRETE_VOLUME_DELTA, 1)
                ) {
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.vc!.speechSynthesizer,
                        text: "Volume increased.",
                        voice: voice,
                        rate: note.vc!.echoRate,
                        volume: note.vc!.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.vc!.speechSynthesizer,
                        text: "Volume already at maximum.",
                        voice: voice,
                        rate: note.vc!.echoRate,
                        volume: note.vc!.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
        case "turn volume down", "decrease volume", "adjust volume down", "volume down", "just volume down", "i just volume down":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            let currentVolume = note.vc!.playbackVolume
            if currentVolume > 0 {
                setPlaybackVolume(
                    note: note,
                    to: max(currentVolume - Utils.DISCRETE_VOLUME_DELTA, 0.1)
                ) {
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.vc!.speechSynthesizer,
                        text: "Volume decreased.",
                        voice: voice,
                        rate: note.vc!.echoRate,
                        volume: note.vc!.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                // Give haptic feedback
                hapticEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.vc!.speechSynthesizer,
                        text: "Volume already at minimum.",
                        voice: voice,
                        rate: note.vc!.echoRate,
                        volume: note.vc!.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
        case "adjust volume", "i just volume", "just volume", "change volume", "volume":
            startListeningForVolume(note: note)
        default:
            soundEngine.voiceCommandDeny()
            
            let queryArray = query.split(separator: " ")

            // Give visual feedback
            note.vc!.scheduleNotification(
                text: "\"\(queryArray.count > 3 ? "\(queryArray.first!.lowercased())...\(queryArray.last!.lowercased())" : query)\"",
                duration: 3
            )
            note.vc!.exhaustNotificationQueue()
        }
    }

    func playNote(note: Note, rate: Float? = nil, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Play Note")

        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Play Note\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        // *** The note playing is the audio feedback ***

        if let rate = rate {
            setPlaybackRate(note: note, to: rate)
        }
        
        if !note.isPlayingNote {
            note.play(
                onStartHandler: {
                    DispatchQueue.main.async {
                        if !note.isListeningForSpeech {
                            note.vc!.playAudioButton.setTitle(ViewController.PAUSE_NOTE_LABEL, for: .normal)
                        }
                    }
                },
                secondElapseHandler: {
                    DispatchQueue.main.async {
                        if !note.isListeningForSpeech {
                            note.vc!.navigationItem.title = "\(Utils.formattedTime(time: Float((note.player.currentTime().seconds))))/\(note.duration.seconds)"
                        }
                    }
                },
                segmentBoundaryHandler: {
                    DispatchQueue.main.async {
                        if let segment = note.vc!.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let range = note.vc!.note.getSegmentTextRange(of: segment) {
                            // update text
                            note.vc!.updateUIText(highlightRange: range)
                        }
                        
                        if let segment = note.vc!.note.getSegment(type: .current), let pitch = segment.getPitch() {
                            // update pitch
                            note.vc!.pitchLabel.text = pitch.note.string
                        }
                    }
                }, onFinishHandler: {
                    DispatchQueue.main.async {
                        note.vc!.updateUIText()
                        note.vc!.note.player.replaceCurrentItem(with: nil)
                        if !note.isListeningForSpeech {
                            note.vc!.navigationItem.title = ""
                            note.vc!.playAudioButton.setTitle(ViewController.PLAY_NOTE_LABEL, for: .normal)
                        }
                        handler?()
                    }
                }
            )
        }
    }
    
    func pauseNote(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Pause Note")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Pause Note\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && note.isPlayingNote {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "note paused",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }
        

        if note.isPlayingNote {
            note.pause() {
                DispatchQueue.main.async {
                    note.vc!.playAudioButton.setTitle(ViewController.PLAY_NOTE_LABEL, for: .normal)
                }
            }
        }
        
        handler?()
    }
    
    func startListeningForSpeech(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Start Listening For Speech")

        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Start Note\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && !note.isListeningForSpeech {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "note started",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        note.vc!.recordingButton.setTitle("Stop Note", for: .normal)
        note.vc!.clearTimedNotification()
        note.startListeningForSpeech(
            soundIntensityHandler: { power in
                if let power = power {
                    DispatchQueue.main.async {
                        let height = CGFloat(Utils.normalizedPower(power: power, minPower: note.minPower)) * note.vc!.view.safeAreaLayoutGuide.layoutFrame.height
                        let soundIntensityHeight: CGFloat = CGFloat(min(height, note.vc!.view.safeAreaLayoutGuide.layoutFrame.height))
                        note.vc!.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                    }
                }
            },
            pitchHandler: { pitchDatum in
                if let pitchDatum = pitchDatum {
                    DispatchQueue.main.async {
                        let pitch = pitchDatum.pitch.note.string
                        note.vc!.pitchLabel.text = pitch
                    }
                }
            },
            onStartHandler: {
                note.vc!.startRecordingUITimer(recording: true)
                handler?()
            }
        )
    }
    
    func stopListeningForSpeech(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Stop Listening For Speech")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Stop Note\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "note stopped",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        note.stopListeningForSpeech() {
            handler?()
        }
    }
    
    func startEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Start Echo")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Start Echo\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        // *** The note playing is the audio feedback ***

        note.startEcho(onStartHandler: handler)
    }
    
    func pauseEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Pause Echo")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Pause Echo\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && note.isPlayingEcho {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "echo paused",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        note.pauseEcho(handler: handler)
    }
    
    func stopEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Stop Echo")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Stop Echo\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && note.isPlayingEcho {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "echo stopped",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        note.stopEcho(handler: handler)
    }
    
    func trimNote(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Trim Note")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Trim Note\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "trimming note",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        // note.trimNote(keeping: <#T##CMTimeRange#>)
    }
    
    func activateSkipPunctuation(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Skip Punctuation")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Skip Punctuation\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && !note.skipPunctuation {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "skip punctuation activated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        note.setSkipPunctuation(to: true)
        handler?()
    }
    
    func deactivateSkipPunctuation(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Skip Punctuation")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Include Punctuation\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && note.skipPunctuation {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "skip punctuation deactivated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        note.setSkipPunctuation(to: false)
        handler?()
    }
    
    func activateSilence(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Silence")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Activate Silences\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && !note.skipSilence {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "silences activated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        note.setSkipSilence(to: true)
        handler?()
    }
    
    func deactivateSilence(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Silence")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Deactivate Silences\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && note.skipSilence {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "silences deactivated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        note.setSkipSilence(to: false)
        handler?()
    }
    
    func activateTemporalSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Temporal Suggestions")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Activate Temporal Suggestions\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && !note.withTemporalSuggestions {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "temporal suggestions activated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        note.setWithTemporalSuggestions(to: true)
        handler?()
    }
    
    func deactivateTemporalSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Temporal Suggestions")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Deactivate Temporal Suggestions\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && note.withTemporalSuggestions {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "temporal suggestions deactivated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        note.setWithTemporalSuggestions(to: false)
        handler?()
    }
    
    func activatePunctuationSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Punctuation Suggestions")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Activate Punctuation Suggestions\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && !note.withPunctuationSuggestions {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "punctuation suggestions activated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }

        
        note.setWithPunctuationSuggestions(to: true)
        handler?()
    }
    
    func deactivatePunctuationSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Punctuation Suggestions")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Deactivate Punctuation Suggestions\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && note.withTemporalSuggestions {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "punctuation suggestions deactivated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }
        
        note.setWithPunctuationSuggestions(to: false)
        handler?()
    }
    
    func activateFormattingSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Formatting Suggestions")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Activate Formatting Suggestions\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && !note.withFormattingSuggestions {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "formatting suggestions activated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }
        
        note.setWithFormattingSuggestions(to: true)
        handler?()
    }
    
    func deactivateFormattingSuggestions(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Formatting Suggestions")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Deactivate Formatting Suggestions\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()

        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && note.withPunctuationSuggestions {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "formatting suggestions deactivated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }
        
        note.setWithFormattingSuggestions(to: false)
        handler?()
    }
    
    func activatePassiveEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Passive Echo")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Activate Passive Echo\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()

        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && !note.withPassiveEcho {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "passive echo activated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }
        
        note.setWithPassiveEcho(to: true)
        handler?()
    }
    
    func deactivatePassiveEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Passive Echo")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Deactivate Passive Echo\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()

        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected && note.withPassiveEcho {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "passive echo deactivated",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }
        
        note.setWithPassiveEcho(to: false)
        handler?()
    }
    
    func setPlaybackRate(note: Note, to rate: Float, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Set Playback Rate")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Set Playback Rate\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "setting playback rate",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }
        
        note.setPlaybackRate(to: rate)
        handler?()
    }
    
    func setPlaybackVolume(note: Note, to volume: Float, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Set Playback Volume")
        
        // Give visual feedback
        note.vc!.scheduleNotification(
            text: "\"Set Playback Volume\"",
            duration: 3
        )
        note.vc!.exhaustNotificationQueue()

        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected {
            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
            // because we will be note.isListeningForVoiceCommands
            // which will catch the words and process them
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

                let synthesizerItem = SynthesizerItem(
                    synthesizer: note.vc!.speechSynthesizer,
                    text: "setting playback volume",
                    voice: voice,
                    rate: note.vc!.echoRate,
                    volume: note.vc!.playbackVolume
                )
                note.vc!.synthesizerQueue.enqueue(synthesizerItem)
                note.vc!.exhaustSynthesizerQueue()
            }
        }
        
        Utils.setMainVolume(to: volume)
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
