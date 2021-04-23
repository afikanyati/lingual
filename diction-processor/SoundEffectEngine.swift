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
    
    // Players
    var commitBufferPlayer: AVAudioPlayer? = nil
    var errorPlayer: AVAudioPlayer? = nil
    var playPlayer: AVAudioPlayer? = nil
    var processingPlayer: AVQueuePlayer? = nil
    var processingLooper: AVPlayerLooper? = nil
    var modalAmbiencePlayer: AVQueuePlayer? = nil
    var modalAmbienceLooper: AVPlayerLooper? = nil
    var naturePlayer: AVQueuePlayer? = nil
    var natureLooper: AVPlayerLooper? = nil
    var repeatPlayer: AVAudioPlayer? = nil
    var saveEntryPlayer: AVAudioPlayer? = nil
    var startListeningPlayer: AVAudioPlayer? = nil
    var stopListeningPlayer: AVAudioPlayer? = nil
    var voiceCommandAcceptPlayer: AVAudioPlayer? = nil
    var voiceCommandDenyPlayer: AVAudioPlayer? = nil
    var deletePlayer: AVAudioPlayer? = nil
    var dialogPlayer: AVAudioPlayer? = nil
    var startupPlayer: AVAudioPlayer? = nil
    var tapPlayer: AVAudioPlayer? = nil
    var speechRegisteredPlayer: AVAudioPlayer? = nil
    var paragraphSuggestionPlayer: AVAudioPlayer? = nil
    var sentenceSuggestionPlayer: AVAudioPlayer? = nil
    
    // Flags
    var isProcessing = false
    var isPlayingModalAmbience = false
    var isPlayingNatureAmbience = false
    var pan: Float = 0 // A value of –1.0 is full left, 0.0 is center, and 1.0 is full right.
    var players = [AVAudioPlayer?]()
    
    private override init() {
        // Commit Buffer
        let commitBufferPath = Bundle.main.path(forResource: "commit-buffer", ofType: "wav")!
        let commitBufferURL = URL(fileURLWithPath: commitBufferPath)

        do {
            self.commitBufferPlayer = try AVAudioPlayer(contentsOf: commitBufferURL)
            self.players.append(self.commitBufferPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Commit Buffer' sound =====")
        }
        
        // Error
        let errorPath = Bundle.main.path(forResource: "error", ofType: "wav")!
        let errorURL = URL(fileURLWithPath: errorPath)

        do {
            self.errorPlayer = try AVAudioPlayer(contentsOf: errorURL)
            self.players.append(self.errorPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Error' sound =====")
        }
        
        // Play
        let playPath = Bundle.main.path(forResource: "play", ofType: "wav")!
        let playURL = URL(fileURLWithPath: playPath)

        do {
            self.playPlayer = try AVAudioPlayer(contentsOf: playURL)
            self.players.append(self.playPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Play' sound =====")
        }
        
        // Processing
        let processingPath = Bundle.main.path(forResource: "processing", ofType: "wav")!
        let processingURL = URL(fileURLWithPath: processingPath)
        let processingAsset = AVAsset(url: processingURL)
        let processingItem = AVPlayerItem(asset: processingAsset)
        processingPlayer = AVQueuePlayer(playerItem: processingItem)
        processingPlayer?.volume = 0.02
        processingLooper = AVPlayerLooper(player: processingPlayer!, templateItem: processingItem)
        
        // Modal Ambience
        let modalAmbiencePath = Bundle.main.path(forResource: "modal-ambience", ofType: "wav")!
        let modalAmbienceURL = URL(fileURLWithPath: modalAmbiencePath)
        let modalAmbienceAsset = AVAsset(url: modalAmbienceURL)
        let modalAmbienceItem = AVPlayerItem(asset: modalAmbienceAsset)
        modalAmbiencePlayer = AVQueuePlayer(playerItem: modalAmbienceItem)
        modalAmbiencePlayer?.volume = 0.02
        modalAmbienceLooper = AVPlayerLooper(player: modalAmbiencePlayer!, templateItem: modalAmbienceItem)
        
        // Repeat
        let repeatPath = Bundle.main.path(forResource: "repeat", ofType: "wav")!
        let repeatURL = URL(fileURLWithPath: repeatPath)

        do {
            self.repeatPlayer = try AVAudioPlayer(contentsOf: repeatURL)
            self.players.append(self.repeatPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Repeat' sound =====")
        }
        
        // Save Entry
        let saveEntryPath = Bundle.main.path(forResource: "save", ofType: "wav")!
        let saveEntryURL = URL(fileURLWithPath: saveEntryPath)

        do {
            self.saveEntryPlayer = try AVAudioPlayer(contentsOf: saveEntryURL)
            self.players.append(self.saveEntryPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Save Entry' sound =====")
        }
        
        // Start Listening
        let startListeningPath = Bundle.main.path(forResource: "start-listening", ofType: "wav")!
        let startListeningURL = URL(fileURLWithPath: startListeningPath)

        do {
            self.startListeningPlayer = try AVAudioPlayer(contentsOf: startListeningURL)
            self.players.append(self.startListeningPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Start Listening' sound =====")
        }
        
        // Stop Listening
        let stopListeningPath = Bundle.main.path(forResource: "stop-listening", ofType: "wav")!
        let stopListeningURL = URL(fileURLWithPath: stopListeningPath)

        do {
            self.stopListeningPlayer = try AVAudioPlayer(contentsOf: stopListeningURL)
            self.players.append(self.stopListeningPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Stop Listening' sound =====")
        }
        
        // Voice Command Accept
        let voiceCommandAcceptPath = Bundle.main.path(forResource: "voice-command-accept", ofType: "wav")!
        let voiceCommandAcceptURL = URL(fileURLWithPath: voiceCommandAcceptPath)

        do {
            self.voiceCommandAcceptPlayer = try AVAudioPlayer(contentsOf: voiceCommandAcceptURL)
            self.players.append(self.voiceCommandAcceptPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Voice Command Accept' sound =====")
        }
        
        // Voice Command Deny
        let voiceCommandDenyPath = Bundle.main.path(forResource: "voice-command-deny", ofType: "wav")!
        let voiceCommandDenyURL = URL(fileURLWithPath: voiceCommandDenyPath)

        do {
            self.voiceCommandDenyPlayer = try AVAudioPlayer(contentsOf: voiceCommandDenyURL)
            self.players.append(self.voiceCommandDenyPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Voice Command Deny' sound =====")
        }
        
        // Delete
        let deletePath = Bundle.main.path(forResource: "delete", ofType: "wav")!
        let deleteURL = URL(fileURLWithPath: deletePath)

        do {
            self.deletePlayer = try AVAudioPlayer(contentsOf: deleteURL)
            self.players.append(self.deletePlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Delete' sound =====")
        }
        
        // Present Dialog
        let dialogPath = Bundle.main.path(forResource: "dialog", ofType: "wav")!
        let dialogURL = URL(fileURLWithPath: dialogPath)

        do {
            self.dialogPlayer = try AVAudioPlayer(contentsOf: dialogURL)
            self.players.append(self.dialogPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Dialog' sound =====")
        }
        
        // Paragraph Suggestion
        let paragraphSuggestionPath = Bundle.main.path(forResource: "paragraph-suggestion", ofType: "wav")!
        let paragraphSuggestionURL = URL(fileURLWithPath: paragraphSuggestionPath)

        do {
            self.paragraphSuggestionPlayer = try AVAudioPlayer(contentsOf: paragraphSuggestionURL)
            self.players.append(self.paragraphSuggestionPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Paragraph Suggestion' sound =====")
        }
        
        // Sentence Suggestion
        let sentenceSuggestionPath = Bundle.main.path(forResource: "sentence-suggestion", ofType: "wav")!
        let sentenceSuggestionURL = URL(fileURLWithPath: sentenceSuggestionPath)

        do {
            self.sentenceSuggestionPlayer = try AVAudioPlayer(contentsOf: sentenceSuggestionURL)
            self.players.append(self.sentenceSuggestionPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Sentence Suggestion' sound =====")
        }
        
        // Startup
        let startupPath = Bundle.main.path(forResource: "startup", ofType: "wav")!
        let startupURL = URL(fileURLWithPath: startupPath)

        do {
            self.startupPlayer = try AVAudioPlayer(contentsOf: startupURL)
            self.startupPlayer?.volume = 0.07
            self.players.append(self.startupPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Startup' sound =====")
        }
        
        // Nature
        let natureAmbiencePath = Bundle.main.path(forResource: "nature-ambience", ofType: "mp3")!
        let natureAmbienceURL = URL(fileURLWithPath: natureAmbiencePath)
        let natureAmbienceAsset = AVAsset(url: natureAmbienceURL)
        let natureAmbienceItem = AVPlayerItem(asset: natureAmbienceAsset)
        naturePlayer = AVQueuePlayer(playerItem: natureAmbienceItem)
        naturePlayer?.volume = 0.01
        natureLooper = AVPlayerLooper(player: naturePlayer!, templateItem: natureAmbienceItem)
        
        // Speech Registered
        let speechRegisteredPath = Bundle.main.path(forResource: "speech-registered", ofType: "wav")!
        let speechRegisteredURL = URL(fileURLWithPath: speechRegisteredPath)

        do {
            self.speechRegisteredPlayer = try AVAudioPlayer(contentsOf: speechRegisteredURL)
            self.speechRegisteredPlayer?.volume = 0.05
            self.players.append(self.speechRegisteredPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Speech Registered' sound =====")
        }
        
        // Tap
        let tapPath = Bundle.main.path(forResource: "speech-registered", ofType: "wav")!
        let tapURL = URL(fileURLWithPath: tapPath)

        do {
            self.tapPlayer = try AVAudioPlayer(contentsOf: tapURL)
            self.tapPlayer?.volume = 0.2
            self.players.append(self.tapPlayer)
        } catch {
            print("===== [Error] There was a problem importing 'Tap' sound =====")
        }
    }
    
    func commitBuffer() {
        commitBufferPlayer?.prepareToPlay()
        commitBufferPlayer?.play()
    }
    func error() {
        errorPlayer?.prepareToPlay()
        errorPlayer?.play()
    }
    func play() {
        playPlayer?.prepareToPlay()
        playPlayer?.play()
    }
    func startProcessing() {
        processingPlayer?.play()
        self.isProcessing = true
    }
    func stopProcessing() {
        processingPlayer?.stop()
        self.isProcessing = false
    }
    func startModalAmbience() {
        modalAmbiencePlayer?.play()
        self.isPlayingModalAmbience = true
    }
    func stopModalAmbience() {
        modalAmbiencePlayer?.stop()
        self.isPlayingModalAmbience = false
    }
    func repeatSegment() {
        repeatPlayer?.prepareToPlay()
        repeatPlayer?.play()
    }
    func saveEntry() {
        saveEntryPlayer?.prepareToPlay()
        saveEntryPlayer?.play()
    }
    func startListening() {
        startListeningPlayer?.prepareToPlay()
        startListeningPlayer?.play()
    }
    func stopListening() {
        stopListeningPlayer?.prepareToPlay()
        stopListeningPlayer?.play()
    }
    func voiceCommandAccept() {
        voiceCommandAcceptPlayer?.prepareToPlay()
        voiceCommandAcceptPlayer?.play()
    }
    func voiceCommandDeny() {
        voiceCommandDenyPlayer?.prepareToPlay()
        voiceCommandDenyPlayer?.play()
    }
    func delete() {
        deletePlayer?.prepareToPlay()
        deletePlayer?.play()
    }
    func presentDialog() {
        dialogPlayer?.prepareToPlay()
        dialogPlayer?.play()
    }
    func startup() {
        startupPlayer?.prepareToPlay()
        startupPlayer?.play()
    }
    func paragraphSuggestion() {
        paragraphSuggestionPlayer?.prepareToPlay()
        paragraphSuggestionPlayer?.play()
    }
    func sentenceSuggestion() {
        sentenceSuggestionPlayer?.prepareToPlay()
        sentenceSuggestionPlayer?.play()
    }
    func startNatureAmbience() {
        naturePlayer?.play()
        self.isPlayingNatureAmbience = true
    }
    func stopNatureAmbience() {
        naturePlayer?.stop()
        self.isPlayingNatureAmbience = false
    }
    func speechRegistered() {
        speechRegisteredPlayer?.prepareToPlay()
        speechRegisteredPlayer?.play()
    }
    func tap() {
        tapPlayer?.prepareToPlay()
        tapPlayer?.play()
    }
    
    // Reference: https://stackoverflow.com/questions/39088804/is-there-a-way-to-play-a-sound-note-in-only-one-ear-of-headphone-in-swift-2-0-us
    func panLeft() {
        for player in self.players {
            player?.pan = -1.0
        }
    }
    
    // Reference: https://stackoverflow.com/questions/39088804/is-there-a-way-to-play-a-sound-note-in-only-one-ear-of-headphone-in-swift-2-0-us
    func panRight() {
        for player in self.players {
            player?.pan = 1.0
        }
    }
    
    // Reference: https://stackoverflow.com/questions/39088804/is-there-a-way-to-play-a-sound-note-in-only-one-ear-of-headphone-in-swift-2-0-us
    func panCenter() {
        for player in self.players {
            player?.pan = 0
        }
    }
}
