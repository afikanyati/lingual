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
    var processingPlayer: AVQueuePlayer? = nil
    var processingLooper: AVPlayerLooper? = nil
    var repeatPlayer: AVAudioPlayer? = nil
    var saveNotePlayer: AVAudioPlayer? = nil
    var startListeningPlayer: AVAudioPlayer? = nil
    var stopListeningPlayer: AVAudioPlayer? = nil
    var voiceCommandAcceptPlayer: AVAudioPlayer? = nil
    var voiceCommandDenyPlayer: AVAudioPlayer? = nil
    var deletePlayer: AVAudioPlayer? = nil
    
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
        let asset = AVAsset(url: processingURL)
        let item = AVPlayerItem(asset: asset)
        processingPlayer = AVQueuePlayer(playerItem: item)
        processingLooper = AVPlayerLooper(player: processingPlayer!, templateItem: item)
        
        // Repeat
        let repeatPath = Bundle.main.path(forResource: "repeat", ofType: "wav")!
        let repeatURL = URL(fileURLWithPath: repeatPath)

        do {
            repeatPlayer = try AVAudioPlayer(contentsOf: repeatURL)
        } catch {
            print("===== [Error] There was a problem importing 'Repeat' sound =====")
        }
        
        // Save Note
        let saveNotePath = Bundle.main.path(forResource: "save", ofType: "wav")!
        let saveNoteURL = URL(fileURLWithPath: saveNotePath)

        do {
            saveNotePlayer = try AVAudioPlayer(contentsOf: saveNoteURL)
        } catch {
            print("===== [Error] There was a problem importing 'Save Note' sound =====")
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
        
        // Delete
        let deletePath = Bundle.main.path(forResource: "delete", ofType: "wav")!
        let deleteURL = URL(fileURLWithPath: deletePath)

        do {
            deletePlayer = try AVAudioPlayer(contentsOf: deleteURL)
        } catch {
            print("===== [Error] There was a problem importing 'Delete' sound =====")
        }
    }
    
    func commitBuffer() { commitBufferPlayer?.play() }
    func correctWakePhrase() { correctWakePhrasePlayer?.play() }
    func error() { errorPlayer?.play() }
    func incorrectWakePhrase() { incorrectWakePhrasePlayer?.play() }
    func play() { playPlayer?.play() }
    func startProcessing() { processingPlayer?.play() }
    func stopProcessing() { processingPlayer?.stop() }
    func repeatSegment() { repeatPlayer?.play() }
    func saveNote() { saveNotePlayer?.play() }
    func startListening() { startListeningPlayer?.play() }
    func stopListening() { stopListeningPlayer?.play() }
    func voiceCommandAccept() { voiceCommandAcceptPlayer?.play() }
    func voiceCommandDeny() { voiceCommandDenyPlayer?.play() }
    func delete() { deletePlayer?.play() }
}
