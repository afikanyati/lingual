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
        "play expression",
        "pause expression",
        "start expression",
        "stop expression",
        "echo expression",
        "ecko expression",
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
        "deactivate passive echo"
    ]
    
    func includesCommand(passage: String) -> String? {
        print("===== Voice Command Engine: Includes Command =====")
        let bagOfWords = passage.lowercased().components(separatedBy: " ")
        
        // Check for two word commands
        if bagOfWords.count > 2 {
            for i in 0..<bagOfWords.count - 1 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1])"
                if voiceCommands.contains(phrase) {
                    print("\tFound Expression: \(phrase)")
                    return phrase
                }
            }
        } else if bagOfWords.count == 2 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1])"
            if voiceCommands.contains(phrase) {
                print("\tFound Expression: \(phrase)")
                return phrase
            }
        }
        
        // Check for three word commands
        if bagOfWords.count > 3 {
            for i in 0..<bagOfWords.count - 2 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1]) \(bagOfWords[i+2])"
                if voiceCommands.contains(phrase) {
                    print("\tFound Expression: \(phrase)")
                    return phrase
                }
            }
        } else if bagOfWords.count == 3 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1]) \(bagOfWords[2])"
            if voiceCommands.contains(phrase) {
                print("\tFound Expression: \(phrase)")
                return phrase
            }
        }
        
        return nil
    }
    
    func process(expression: Expression, query: String, handler: (() -> Void)? = nil) {
        print("===== Processing Voice Command =====")
        let query = query.lowercased()
        print("\tQuery: \(query)")
        
        switch (query) {
        case "play expression":
            // Play Sound
            soundEngine.voiceCommandAccept()

            playExpression(expression: expression, handler: handler)
            break
        case "pause expression":
            // Play Sound
            soundEngine.voiceCommandAccept()

            pauseExpression(expression: expression, handler: handler)
            break
        case "start expression":
            if !expression.isListeningForSpeech {
                // no need to play sound
                // we will piggyback off of start expression sound

                expression.stopListeningForVoiceCommands() {
                    self.startListeningForSpeech(expression: expression, handler: handler)
                }
            } else {
                // Play Sound
                soundEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let rate: Float = 0.5
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: expression.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: expression.speechSynthesizer,
                        text: "An expression has already been started.",
                        voice: voice,
                        rate: rate,
                        volume: expression.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
            
            break
        case "stop expression":
            if let _ = expression.tempVoiceCommandHandler {
                // Play Sound
                soundEngine.voiceCommandAccept()

                // we've always stopped expression before getting here
                stopListeningForSpeech(expression: expression, handler: handler)
            } else {
                // Play Sound
                soundEngine.error()
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                    let rate: Float = 0.5
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: expression.vc)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: expression.speechSynthesizer,
                        text: "An expression has not been started.",
                        voice: voice,
                        rate: rate,
                        volume: expression.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
            break
        case "echo expression", "ecko expression", "play echo", "play ecko", "start echo", "start ecko":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            startEcho(expression: expression, handler: handler)
            break
        case "pause echo", "pause ecko":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            pauseEcho(expression: expression, handler: handler)
            break
        case "stop echo", "stop ecko":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            stopEcho(expression: expression, handler: handler)
            break
        case "activate punctuation":
            // Play Sound
            soundEngine.voiceCommandAccept()

            activateSkipPunctuation(expression: expression, handler: handler)
            break
        case "deactivate punctuation":
            // Play Sound
            soundEngine.voiceCommandAccept()

            deactivatePassiveEcho(expression: expression, handler: handler)
            break
        case "activate silences":
            // Play Sound
            soundEngine.voiceCommandAccept()

            activateSilence(expression: expression, handler: handler)
            break
        case "deactivate silences":
            // Play Sound
            soundEngine.voiceCommandAccept()

            deactivateSilence(expression: expression, handler: handler)
            break
        case "activate temporal suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            activateTemporalSuggestions(expression: expression, handler: handler)
            break
        case "deactivate temporal suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            deactivateTemporalSuggestions(expression: expression, handler: handler)
            break
        case "activate punctuation suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            activatePunctuationSuggestions(expression: expression, handler: handler)
            break
        case "deactivate punctuation suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            deactivatePunctuationSuggestions(expression: expression, handler: handler)
            break
        case "activate formatting suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            activateFormattingSuggestions(expression: expression, handler: handler)
            break
        case "deactivate formatting suggestions":
            // Play Sound
            soundEngine.voiceCommandAccept()

            deactivateFormattingSuggestions(expression: expression, handler: handler)
            break
        case "activate passive echo":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            activatePassiveEcho(expression: expression, handler: handler)
        case "deactivate passive echo":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            deactivatePassiveEcho(expression: expression, handler: handler)
        default:
            soundEngine.voiceCommandDeny()
        }
    }

    func playExpression(expression: Expression, rate: Float? = nil, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Play Expression")
        if let rate = rate {
            setPlaybackRate(expression: expression, to: rate)
        }
        
        if !expression.isPlayingExpression {
            expression.play(
                onStartHandler: {
                    DispatchQueue.main.async {
                        expression.vc!.playAudioButton.setTitle(ViewController.PAUSE_EXPRESSION_LABEL, for: .normal)
                    }
                },
                secondElapseHandler: {
                    DispatchQueue.main.async {
                        expression.vc!.navigationItem.title = Utils.formattedTime(time: Float((expression.vc!.expression.player.currentTime().seconds)))
                    }
                },
                segmentBoundaryHandler: {
                    DispatchQueue.main.async {
                        if let segment = expression.vc!.expression.getSegment(type: .current), segment.getText().count > 0, let range = expression.vc!.expression.getSegmentTextRange(of: segment) {
                            expression.vc!.updateUIText(range: range)
                        }
                    }
                }, onFinishHandler: {
                    DispatchQueue.main.async {
                        expression.vc!.updateUIText()
                        expression.vc!.playAudioButton.setTitle(ViewController.PLAY_EXPRESSION_LABEL, for: .normal)
                        expression.vc!.expression.player.replaceCurrentItem(with: nil)
                        expression.vc!.navigationItem.title = ""
                    }
                }
            )
        }
        
        handler?()
    }
    
    func pauseExpression(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Pause Expression")
        if expression.isPlayingExpression {
            expression.pause() {
                DispatchQueue.main.async {
                    expression.vc!.playAudioButton.setTitle(ViewController.PLAY_EXPRESSION_LABEL, for: .normal)
                }
            }
        }
        
        handler?()
    }
    
    func startListeningForSpeech(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Start Listening For Speech")
        expression.vc!.recordingButton.setTitle("Stop Expression", for: .normal)
        expression.vc!.savedMessageTimer?.invalidate()
        expression.startListeningForSpeech(soundIntensityHandler: { intensity in
            if let intensity = intensity {
                DispatchQueue.main.async {
                    let height = CGFloat(intensity) * expression.vc!.view.safeAreaLayoutGuide.layoutFrame.height
                    let soundIntensityHeight: CGFloat = CGFloat(min(height, expression.vc!.view.safeAreaLayoutGuide.layoutFrame.height))
                    expression.vc!.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                }
            }
        }, onStartHandler: {
            expression.vc!.startRecordingUITimer(recording: true)
            handler?()
        })
    }
    
    func stopListeningForSpeech(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Stop Listening For Speech")
        expression.stopListeningForSpeech() {
            expression.startListeningForVoiceCommands(
                soundIntensityHandler: { intensity in
                    if let intensity = intensity {
                        DispatchQueue.main.async {
                            let height = CGFloat(intensity) * expression.vc!.view.safeAreaLayoutGuide.layoutFrame.height
                            let soundIntensityHeight: CGFloat = CGFloat(min(height, expression.vc!.view.safeAreaLayoutGuide.layoutFrame.height))
                            expression.vc!.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                        }
                    }
                },
                onStartHandler: handler
            )
        }
    }
    
    func startEcho(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Start Echo")
        expression.startEcho(onStartHandler: handler)
    }
    
    func pauseEcho(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Pause Echo")
        expression.pauseEcho(handler: handler)
    }
    
    func stopEcho(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Stop Echo")
        expression.stopEcho(handler: handler)
    }
    
    func trimExpression(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Trim Expression")
        // expression.trimExpression(keeping: <#T##CMTimeRange#>)
    }
    
    func activateSkipPunctuation(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Skip Punctuation")
        expression.setSkipPunctuation(to: true)
        handler?()
    }
    
    func deactivateSkipPunctuation(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Skip Punctuation")
        expression.setSkipPunctuation(to: false)
        handler?()
    }
    
    func activateSilence(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Silence")
        expression.setSkipSilence(to: true)
        handler?()
    }
    
    func deactivateSilence(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Silence")
        expression.setSkipSilence(to: false)
        handler?()
    }
    
    func activateTemporalSuggestions(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Temporal Suggestions")
        expression.setWithTemporalSuggestions(to: true)
        handler?()
    }
    
    func deactivateTemporalSuggestions(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Temporal Suggestions")
        expression.setWithTemporalSuggestions(to: false)
        handler?()
    }
    
    func activatePunctuationSuggestions(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Punctuation Suggestions")
        expression.setWithPunctuationSuggestions(to: true)
        handler?()
    }
    
    func deactivatePunctuationSuggestions(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Punctuation Suggestions")
        expression.setWithPunctuationSuggestions(to: false)
        handler?()
    }
    
    func activateFormattingSuggestions(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Formatting Suggestions")
        expression.setWithFormattingSuggestions(to: true)
        handler?()
    }
    
    func deactivateFormattingSuggestions(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Formatting Suggestions")
        expression.setWithFormattingSuggestions(to: false)
        handler?()
    }
    
    func activatePassiveEcho(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Activate Passive Echo")
        expression.setWithPassiveEcho(to: true)
        handler?()
    }
    
    func deactivatePassiveEcho(expression: Expression, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Deactivate Passive Echo")
        expression.setWithPassiveEcho(to: false)
        handler?()
    }
    
    func setPlaybackRate(expression: Expression, to rate: Float, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Set Playback Rate")
        expression.setPlaybackRate(to: rate)
        handler?()
    }
    
    func setPlaybackVolume(expression: Expression, to volume: Float, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Set Playback Volume")
        expression.setPlaybackVolume(to: volume)
        handler?()
    }
}
