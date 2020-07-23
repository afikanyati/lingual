//
//  SoundEffects.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/17/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//
// Reference: https://www.hackingwithswift.com/example-code/media/how-to-play-sounds-using-avaudioplayer
// Reference: https://stackoverflow.com/questions/32036146/how-to-play-a-sound-using-swift

import Foundation
import AVFoundation

public let soundEngine = SoundEffectEngine.shared
public final class SoundEffectEngine: NSObject {
    
    static let shared = SoundEffectEngine()
    
    var commitBufferPlayer: AVAudioPlayer? = nil
    var correctWakePhrasePlayer: AVAudioPlayer? = nil
    var errorPlayer: AVAudioPlayer? = nil
    var incorrectWakePhrasePlayer: AVAudioPlayer? = nil
    var playPlayer: AVAudioPlayer? = nil
    var processingPlayer: AVAudioPlayer? = nil
    var repeatPlayer: AVAudioPlayer? = nil
    var saveExpressionPlayer: AVAudioPlayer? = nil
    var startListeningPlayer: AVAudioPlayer? = nil
    var stopListeningPlayer: AVAudioPlayer? = nil
    var voiceCommandAcceptPlayer: AVAudioPlayer? = nil
    var voiceCommandDenyPlayer: AVAudioPlayer? = nil
    
    private override init() {
        // Commit Buffer
        let commitBufferPath = Bundle.main.path(forResource: "commit-buffer", ofType: "wav")!
        let commitBufferURL = URL(fileURLWithPath: commitBufferPath)

        do {
            commitBufferPlayer = try AVAudioPlayer(contentsOf: commitBufferURL)
        } catch {
            print("===== [Error] There was a problem importing 'Commit Buffer' sound =====")
        }
        
        // Correct Wake Phrase
        let correctWakePhrasePath = Bundle.main.path(forResource: "correct-wake-phrase", ofType: "wav")!
        let correctWakePhraseURL = URL(fileURLWithPath: correctWakePhrasePath)

        do {
            correctWakePhrasePlayer = try AVAudioPlayer(contentsOf: correctWakePhraseURL)
        } catch {
            print("===== [Error] There was a problem importing 'Correct Wake Phrase' sound =====")
        }
        
        // Error
        let errorPath = Bundle.main.path(forResource: "error", ofType: "wav")!
        let errorURL = URL(fileURLWithPath: errorPath)

        do {
            errorPlayer = try AVAudioPlayer(contentsOf: errorURL)
        } catch {
            print("===== [Error] There was a problem importing 'Error' sound =====")
        }
        
        // Incorrect Wake Phrase
        let incorrectWakePhrasePath = Bundle.main.path(forResource: "incorrect-wake-phrase", ofType: "wav")!
        let incorrectWakePhraseURL = URL(fileURLWithPath: incorrectWakePhrasePath)

        do {
            incorrectWakePhrasePlayer = try AVAudioPlayer(contentsOf: incorrectWakePhraseURL)
        } catch {
            print("===== [Error] There was a problem importing 'Incorrect Wake Phrase' sound =====")
        }
        
        // Play
        let playPath = Bundle.main.path(forResource: "play", ofType: "wav")!
        let playURL = URL(fileURLWithPath: playPath)

        do {
            playPlayer = try AVAudioPlayer(contentsOf: playURL)
        } catch {
            print("===== [Error] There was a problem importing 'Play' sound =====")
        }
        
        // Processing
        let processingPath = Bundle.main.path(forResource: "processing", ofType: "wav")!
        let processingURL = URL(fileURLWithPath: processingPath)

        do {
            processingPlayer = try AVAudioPlayer(contentsOf: processingURL)
        } catch {
            print("===== [Error] There was a problem importing 'Processing' sound =====")
        }
        
        // Repeat
        let repeatPath = Bundle.main.path(forResource: "repeat", ofType: "wav")!
        let repeatURL = URL(fileURLWithPath: repeatPath)

        do {
            repeatPlayer = try AVAudioPlayer(contentsOf: repeatURL)
        } catch {
            print("===== [Error] There was a problem importing 'Repeat' sound =====")
        }
        
        // Save Expression
        let saveExpressionPath = Bundle.main.path(forResource: "save-expression", ofType: "wav")!
        let saveExpressionURL = URL(fileURLWithPath: saveExpressionPath)

        do {
            saveExpressionPlayer = try AVAudioPlayer(contentsOf: saveExpressionURL)
        } catch {
            print("===== [Error] There was a problem importing 'Save Expression' sound =====")
        }
        
        // Start Listening
        let startListeningPath = Bundle.main.path(forResource: "start-listening", ofType: "wav")!
        let startListeningURL = URL(fileURLWithPath: startListeningPath)

        do {
            startListeningPlayer = try AVAudioPlayer(contentsOf: startListeningURL)
        } catch {
            print("===== [Error] There was a problem importing 'Start Listening' sound =====")
        }
        
        // Stop Listening
        let stopListeningPath = Bundle.main.path(forResource: "stop-listening", ofType: "wav")!
        let stopListeningURL = URL(fileURLWithPath: stopListeningPath)

        do {
            stopListeningPlayer = try AVAudioPlayer(contentsOf: stopListeningURL)
        } catch {
            print("===== [Error] There was a problem importing 'Stop Listening' sound =====")
        }
        
        // Voice Command Accept
        let voiceCommandAcceptPath = Bundle.main.path(forResource: "voice-command-accept", ofType: "wav")!
        let voiceCommandAcceptURL = URL(fileURLWithPath: voiceCommandAcceptPath)

        do {
            voiceCommandAcceptPlayer = try AVAudioPlayer(contentsOf: voiceCommandAcceptURL)
        } catch {
            print("===== [Error] There was a problem importing 'Voice Command Accept' sound =====")
        }
        
        // Voice Command Deny
        let voiceCommandDenyPath = Bundle.main.path(forResource: "voice-command-deny", ofType: "wav")!
        let voiceCommandDenyURL = URL(fileURLWithPath: voiceCommandDenyPath)

        do {
            voiceCommandDenyPlayer = try AVAudioPlayer(contentsOf: voiceCommandDenyURL)
        } catch {
            print("===== [Error] There was a problem importing 'Voice Command Deny' sound =====")
        }
    }
    
    func commitBuffer() { commitBufferPlayer?.play() }
    func correctWakePhrase() { correctWakePhrasePlayer?.play() }
    func error() { errorPlayer?.play() }
    func incorrectWakePhrase() { incorrectWakePhrasePlayer?.play() }
    func play() { playPlayer?.play() }
    func processing() { processingPlayer?.play() }
    func repeatSegment() { repeatPlayer?.play() }
    func saveExpression() { saveExpressionPlayer?.play() }
    func startListening() { startListeningPlayer?.play() }
    func stopListening() { stopListeningPlayer?.play() }
    func voiceCommandAccept() { voiceCommandAcceptPlayer?.play() }
    func voiceCommandDeny() { voiceCommandDenyPlayer?.play() }
}
