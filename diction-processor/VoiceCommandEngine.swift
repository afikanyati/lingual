//
//  VoiceCommandEngine.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/24/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

public let voiceCommandEngine = VoiceCommandEngine.shared
public final class VoiceCommandEngine: NSObject {
    static let shared = VoiceCommandEngine()
    private let voiceCommands: Set = [
        "play note",
        "pause note",
        "start note",
        "start notes",
        "starting out",
        "start not",
        "stop note",
        "stop not",
        "echo note",
        "ecko note",
        "play ecko",
        "play echo",
        "start echo",
        "start ecko",
        "pause echo",
        "pause ecko",
        "stop echo",
        "stop ecko",
        "activate punctuation",
        "deactivate punctuation",
        "activate silences",
        "deactivate silences",
        "activate temporal suggestions",
        "deactivate temporal suggestions",
        "activate punctuation suggestions",
        "deactivate punctuation suggestions",
        "activate formatting suggestions",
        "deactivate formatting suggestions",
        "activate passive echo",
        "deactivate passive echo",
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
    
    func includesCommand(passage: String) -> String? {
        let bagOfWords = passage.lowercased().components(separatedBy: " ")
        
        // Check for two word commands
        if bagOfWords.count > 2 {
            for i in 0..<bagOfWords.count - 1 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\tFound voice command: \"\(phrase)\"")
                    return phrase
                }
            }
        } else if bagOfWords.count == 2 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\tFound voice command: \"\(phrase)\"")
                return phrase
            }
        }
        
        // Check for three word commands
        if bagOfWords.count > 3 {
            for i in 0..<bagOfWords.count - 2 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1]) \(bagOfWords[i+2])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\tFound voice command: \"\(phrase)\"")
                    return phrase
                }
            }
        } else if bagOfWords.count == 3 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1]) \(bagOfWords[2])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\tFound voice command: \"\(phrase)\"")
                return phrase
            }
        }
        
        return nil
    }
    
    func process(note: Note, query: String, handler: (() -> Void)? = nil) {
        print("===== Processing Voice Command =====")
        let query = query.lowercased()
        print("\tQuery: \"\(query)\"")
        
        switch (query) {
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
        case "start note", "starting out", "start notes", "start not":
            self.startListeningForSpeech(note: note, handler: handler)
            break
        case "stop note", "stop not":
            // Play Sound
            soundEngine.voiceCommandAccept()
            stopListeningForSpeech(note: note, handler: handler)
            break
        case "echo note", "ecko note", "play echo", "play ecko", "start echo", "start ecko":
            // Play Sound
            if !note.isPlayingEcho {
                soundEngine.voiceCommandAccept()
                
                startEcho(note: note, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let rate: Float = 0.52
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.speechSynthesizer,
                        text: "Echo already in progress.",
                        voice: voice,
                        rate: rate,
                        volume: note.playbackVolume
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
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let rate: Float = 0.52
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.speechSynthesizer,
                        text: "Note not being echoed.",
                        voice: voice,
                        rate: rate,
                        volume: note.playbackVolume
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
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let rate: Float = 0.52
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.speechSynthesizer,
                        text: "Note not being echoed.",
                        voice: voice,
                        rate: rate,
                        volume: note.playbackVolume
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
            
            let currentVolume = note.playbackVolume
            if currentVolume < 1 {
                setPlaybackVolume(to: min(currentVolume + Utils.DISCRETE_VOLUME_DELTA, 1)) {
                    let rate: Float = 0.52
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.speechSynthesizer,
                        text: "Volume increased.",
                        voice: voice,
                        rate: rate,
                        volume: note.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let rate: Float = 0.52
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.speechSynthesizer,
                        text: "Volume already at maximum.",
                        voice: voice,
                        rate: rate,
                        volume: note.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
        case "turn volume down", "decrease volume", "adjust volume down", "volume down", "just volume down", "i just volume down":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            let currentVolume = note.playbackVolume
            if currentVolume > 0 {
                setPlaybackVolume(to: max(currentVolume - Utils.DISCRETE_VOLUME_DELTA, 0.1)) {
                    let rate: Float = 0.52
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.speechSynthesizer,
                        text: "Volume decreased.",
                        voice: voice,
                        rate: rate,
                        volume: note.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let rate: Float = 0.52
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: note.speechSynthesizer,
                        text: "Volume already at minimum.",
                        voice: voice,
                        rate: rate,
                        volume: note.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
        case "adjust volume", "i just volume", "just volume", "change volume", "volume":
            startListeningForVolume(note: note)
        default:
            soundEngine.voiceCommandDeny()
        }
    }

    func playNote(note: Note, rate: Float? = nil, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Play Note")
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
                            note.vc!.updateUIText(range: range)
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
        note.vc!.recordingButton.setTitle("Stop Note", for: .normal)
        note.vc!.clearAppNotification()
        note.startListeningForSpeech(soundIntensityHandler: { power in
            if let power = power {
                DispatchQueue.main.async {
                    let height = CGFloat(Utils.normalizedPower(power: power, minPower: note.minPower)) * note.vc!.view.safeAreaLayoutGuide.layoutFrame.height
                    let soundIntensityHeight: CGFloat = CGFloat(min(height, note.vc!.view.safeAreaLayoutGuide.layoutFrame.height))
                    note.vc!.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                }
            }
        }, onStartHandler: {
            note.vc!.startRecordingUITimer(recording: true)
            handler?()
        })
    }
    
    func stopListeningForSpeech(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Stop Listening For Speech")
        note.stopListeningForSpeech() {
            note.startListeningForVoiceCommands(
                soundIntensityHandler: { power in
                    if let power = power {
                        DispatchQueue.main.async {
                            let height = CGFloat(Utils.normalizedPower(power: power, minPower: note.minPower)) * note.vc!.view.safeAreaLayoutGuide.layoutFrame.height
                            let soundIntensityHeight: CGFloat = CGFloat(min(height, note.vc!.view.safeAreaLayoutGuide.layoutFrame.height))
                            note.vc!.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                        }
                    }
                },
                onStartHandler: handler
            )
        }
    }
    
    func startEcho(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Start Echo")
        note.startEcho(onStartHandler: handler)
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
        // note.trimNote(keeping: <#T##CMTimeRange#>)
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
        note.setSkipSilence(to: true)
        handler?()
    }
    
    func deactivateSilence(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Silence")
        note.setSkipSilence(to: false)
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
        note.setPlaybackRate(to: rate)
        handler?()
    }
    
    func setPlaybackVolume(to volume: Float, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Set Playback Volume")
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
