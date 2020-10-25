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
        "create note",
        "new note",
        "start note",
        "start a note",
        "start not",
        "start notes",
        "starting it",
        "stagnant",
        "stock note",
        "scott note",
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
//        "adjust volume",
//        "i just volume",
//        "just volume",
//        "change volume",
//        "volume",
        "turn echo rate up",
        "turn echo rate down",
        "increase echo rate",
        "increase ecko rate",
        "increase echo route",
        "increase ecko route",
        "increase accurate",
        "decrease echo rate",
        "decrease ecko rate",
        "decrease echo route",
        "decrease ecko route",
        "decrease accurate",
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
        "delete",
        "delete selection",
        "update",
        "update selection",
        "copy",
        "copy selection",
        "cut",
        "cut selection",
        "increase rate",
        "increase selection rate",
        "decrease rate",
        "decrease selection rate",
        "export",
        "export selection",
        "move here",
        "place cursor",
        "run",
        "run selection",
        "walk",
        "walk selection",
        "run note",
        "run notes",
        "run not",
        "walk note",
        "walk notes",
        "walk not",
        "pause playback",
        "resume playback",
        "continue playback",
        "resume echo",
        "resume ecko",
        "continue echo",
        "continue ecko",
        "edit note",
        "play commit",
        "play comment",
        "echo commit",
        "echo comment",
        "ecko commit",
        "ecko comment",
        "walk commit",
        "walk comment",
        "run commit",
        "run comment",
        "preview clipboard",
        "check clipbord",
        "inspect clipboard",
        "play clipboard",
        "skip backward",
        "skip back",
        "skip forward",
        "skip ahead",
        "stop playback",
        "export note",
        "export notes",
        "export not",
        "accept",
        "except",
        "redo",
        "cancel",
        "start selection",
        "begin selection",
        "open selection",
        "make selection",
        "makes selection",
        "wake selection",
        "add selection",
        "next",
        "forward",
        "right",
        "up",
        "previous",
        "last",
        "backward",
        "left",
        "down",
        "freeze",
        "freeze run",
        "stop",
        "stop run",
        "halt",
        "holt",
        "halt run",
        "holt run",
        "pause",
        "pause run",
        "remove selection",
        "clear selection",
        "undo",
        "exit",
        "exit run",
        "exit walk",
        "select commit",
        "select comment",
        "delete commit",
        "delete comment",
        "reverse commit",
        "reverse comment",
        "rollback commit",
        "shift start in",
        "shift start out",
        "shift starts in",
        "shift starts out",
        "shift start right",
        "shift start left",
        "shift starts right",
        "shift starts left",
        "shift beginning in",
        "shift beginning out",
        "shift beginning right",
        "shift beginning left",
        "shift anchor in",
        "shift anchor out",
        "shift anchor right",
        "shift anchor left",
        "shift end in",
        "shift end out",
        "shift end left",
        "shift end right",
        "shift ending in",
        "shift ending out",
        "shift ending left",
        "shift ending right",
        "shift finish in",
        "shift finish out",
        "shift finish left",
        "shift finish right",
        "shift focus in",
        "shift focus out",
        "shift focus left",
        "shift focus right",
        "shift right",
        "shift forward",
        "shift up",
        "shift left",
        "shift backward",
        "shift down",
        "move start in",
        "move start out",
        "move starts in",
        "move starts out",
        "move start right",
        "move start left",
        "move starts right",
        "move starts left",
        "move beginning in",
        "move beginning out",
        "move beginning right",
        "move beginning left",
        "move anchor in",
        "move anchor out",
        "move anchor right",
        "move anchor left",
        "move end in",
        "move end out",
        "move end left",
        "move end right",
        "move ending in",
        "move ending out",
        "move ending left",
        "move ending right",
        "move finish in",
        "move finish out",
        "move finish left",
        "move finish right",
        "move focus in",
        "move focus out",
        "move focus left",
        "move focus right",
        "move right",
        "move forward",
        "move up",
        "move left",
        "move backward",
        "move down",
        "expand",
        "expand selection",
        "reduce",
        "reduce selection",
        "paste selection",
        "paste clipboard",
        "help",
        "play",
        "echo"
    ] // Make sure to add in contextual strings as well
    
    let voiceCommandMapping: [String : String] = [
        "play note": "play note",
        "play not": "play note",
        "play notes": "play note",
        "pause note": "pause note",
        "pause not": "pause note",
        "pause notes": "pause note",
        "new note": "start note",
        "create note": "start note",
        "start note": "start note",
        "stagnant": "start note",
        "starting it": "start note",
        "start a note": "start note",
        "start not": "start note",
        "start notes": "start note",
        "stock note": "start note",
        "scott note": "start note",
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
//        "adjust volume": "adjust volume",
//        "i just volume": "adjust volume",
//        "just volume": "adjust volume",
//        "change volume": "adjust volume",
//        "volume": "adjust volume",
        "turn echo rate up": "increase echo rate",
        "adjust echo rate up": "increase echo rate",
        "increase echo rate": "increase echo rate",
        "increase ecko rate": "increase echo rate",
        "increase echo route": "increase echo rate",
        "increase ecko route": "increase echo rate",
        "increase accurate": "increase echo rate",
        "turn echo rate down": "decrease echo rate",
        "decrease echo rate": "decrease echo rate",
        "decrease ecko rate": "decrease echo rate",
        "decrease echo route": "decrease echo rate",
        "decrease ecko route": "decrease echo rate",
        "decrease accurate": "decrease echo rate",
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
        "delete": "delete selection",
        "delete selection": "delete selection",
        "update": "update selection",
        "update selection": "update selection",
        "copy": "copy selection",
        "copy selection": "copy selection",
        "cut": "cut selection",
        "cut selection": "cut selection",
        "increase rate": "increase selection rate",
        "increase selection rate": "increase selection rate",
        "decrease rate": "decrease selection rate",
        "decrease selection rate": "increase selection rate",
        "export": "export selection",
        "export selection": "export selection",
        "place cursor": "move here",
        "move here": "move here",
        "run": "run selection",
        "run selection": "run selection",
        "walk": "walk selection",
        "walk selection": "walk selection",
        "run note": "run note",
        "run not": "run note",
        "run notes": "run note",
        "walk note": "walk note",
        "walk not": "walk note",
        "walk notes": "walk note",
        "pause playback": "pause playback",
        "resume playback": "resume playback",
        "continue playback": "resume playback",
        "resume echo": "resume echo",
        "resume ecko": "resume echo",
        "continue echo": "resume echo",
        "continue ecko": "resume echo",
        "edit note": "edit note",
        "play commit": "play commit",
        "play comment": "play commit",
        "echo commit": "echo commit",
        "echo comment": "echo commit",
        "ecko commit": "echo commit",
        "ecko comment": "echo commit",
        "preview clipboard": "inspect clipboard",
        "check clipboard": "inspect clipboard",
        "inspect clipboard": "inspect clipboard",
        "play clipboard": "inspect clipboard",
        "skip backward": "skip backward",
        "skip back": "skip backward",
        "skip forward": "skip forward",
        "skip ahead": "skip forward",
        "stop playback": "stop playback",
        "export note": "export note",
        "export not": "export note",
        "export notes": "export note",
        "accept": "accept update selection",
        "except": "accept update selection",
        "cancel": "cancel update selection",
        "start selection": "open selection",
        "begin selection": "open selection",
        "open selection": "open selection",
        "make selection": "open selection",
        "makes selection": "open selection",
        "wake selection": "open selection",
        "add selection": "open selection",
        "next": "next element",
        "forward": "next element",
        "right": "next element",
        "up": "next element",
        "previous": "previous element",
        "last": "previous element",
        "backward": "previous element",
        "left": "previous element",
        "down": "previous element",
        "freeze": "halt run",
        "freeze run": "halt run",
        "stop": "stop",
        "stop run": "halt run",
        "halt": "halt run",
        "holt": "halt run",
        "halt run": "halt run",
        "holt run": "halt run",
        "pause": "pause",
        "pause run": "halt run",
        "remove selection": "remove selection",
        "clear selection": "remove selection",
        "undo": "undo",
        "redo": "redo",
        "exit": "exit mode",
        "exit run": "exit mode",
        "exit walk": "exit mode",
        "select commit": "select commit",
        "select comment": "select commit",
        "delete commit": "rollback commit",
        "delete comment": "rollback commit",
        "reverse commit": "rollback commit",
        "reverse comment": "rollback commit",
        "rollback commit": "rollback commit",
        "walk commit": "walk commit",
        "walk comment": "walk commit",
        "run commit": "run commit",
        "run comment": "run commit",
        "shift start in": "shift anchor right",
        "shift start out": "shift anchor left",
        "shift starts in": "shift anchor right",
        "shift starts out": "shift anchor left",
        "shift start right": "shift anchor right",
        "shift start left": "shift anchor left",
        "shift starts right": "shift anchor right",
        "shift starts left": "shift anchor left",
        "shift beginning in": "shift anchor right",
        "shift beginning out": "shift anchor left",
        "shift beginning right": "shift anchor right",
        "shift beginning left": "shift anchor left",
        "shift anchor in": "shift anchor right",
        "shift anchor out": "shift anchor left",
        "shift anchor right": "shift anchor right",
        "shift anchor left": "shift anchor left",
        "shift end in": "shift focus left",
        "shift end out": "shift focus right",
        "shift end left": "shift focus left",
        "shift end right": "shift focus right",
        "shift ending in": "shift focus left",
        "shift ending out": "shift focus right",
        "shift ending left": "shift focus left",
        "shift ending right": "shift focus right",
        "shift finish in": "shift focus left",
        "shift finish out": "shift focus right",
        "shift finish left": "shift focus left",
        "shift finish right": "shift focus right",
        "shift focus in": "shift focus left",
        "shift focus out": "shift focus right",
        "shift focus left": "shift focus left",
        "shift focus right": "shift focus right",
        "shift right": "shift forward",
        "shift forward": "shift forward",
        "shift up": "shift forward",
        "shift left": "shift backward",
        "shift backward": "shift backward",
        "shift down": "shift backward",
        "move start in": "shift anchor right",
        "move start out": "shift anchor left",
        "move starts in": "shift anchor right",
        "move starts out": "shift anchor left",
        "move start right": "shift anchor right",
        "move start left": "shift anchor left",
        "move starts right": "shift anchor right",
        "move starts left": "shift anchor left",
        "move beginning in": "shift anchor right",
        "move beginning out": "shift anchor left",
        "move beginning right": "shift anchor right",
        "move beginning left": "shift anchor left",
        "move anchor in": "shift anchor right",
        "move anchor out": "shift anchor left",
        "move anchor right": "shift anchor right",
        "move anchor left": "shift anchor left",
        "move end in": "shift focus left",
        "move end out": "shift focus right",
        "move end left": "shift focus left",
        "move end right": "shift focus right",
        "move ending in": "shift focus left",
        "move ending out": "shift focus right",
        "move ending left": "shift focus left",
        "move ending right": "shift focus right",
        "move finish in": "shift focus left",
        "move finish out": "shift focus right",
        "move finish left": "shift focus left",
        "move finish right": "shift focus right",
        "move focus in": "shift focus left",
        "move focus out": "shift focus right",
        "move focus left": "shift focus left",
        "move focus right": "shift focus right",
        "move right": "shift forward",
        "move forward": "shift forward",
        "move up": "shift forward",
        "move left": "shift backward",
        "move backward": "shift backward",
        "move down": "shift backward",
        "expand": "expand selection",
        "expand selection": "expand selection",
        "reduce": "reduce selection",
        "reduce selection": "reduce selection",
        "paste selection": "paste clipboard",
        "paste clipboard": "paste clipboard",
        "help": "prompt for assistance",
        "play": "play selection",
        "echo": "echo selection",
    ]
    
    func includesCommand(passage: String) -> (String, Int)? {
        let bagOfWords = passage.lowercased().components(separatedBy: " ")
        
        // Check for one word commands
        if bagOfWords.count > 1 {
            for i in 0..<bagOfWords.count - 1 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return (self.voiceCommandMapping[phrase] ?? phrase, i)
                }
            }
        } else if bagOfWords.count == 1 {
            let phrase = bagOfWords[0]
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return (self.voiceCommandMapping[phrase] ?? phrase, 0)
            }
        }
        
        // Check for two word commands
        if bagOfWords.count > 2 {
            for i in 0..<bagOfWords.count - 1 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return (self.voiceCommandMapping[phrase] ?? phrase, i)
                }
            }
        } else if bagOfWords.count == 2 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return (self.voiceCommandMapping[phrase] ?? phrase, 0)
            }
        }
        
        // Check for three word commands
        if bagOfWords.count > 3 {
            for i in 0..<bagOfWords.count - 2 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1]) \(bagOfWords[i+2])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return (self.voiceCommandMapping[phrase] ?? phrase, i)
                }
            }
        } else if bagOfWords.count == 3 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1]) \(bagOfWords[2])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return (self.voiceCommandMapping[phrase] ?? phrase, 0)
            }
        }
        
        // Check for four word commands
        if bagOfWords.count > 4 {
            for i in 0..<bagOfWords.count - 3 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1]) \(bagOfWords[i+2]) \(bagOfWords[i+3])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return (self.voiceCommandMapping[phrase] ?? phrase, i)
                }
            }
        } else if bagOfWords.count == 4 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1]) \(bagOfWords[2]) \(bagOfWords[3])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return (self.voiceCommandMapping[phrase] ?? phrase, 0)
            }
        }
        
        // Check for five word commands
        if bagOfWords.count > 5 {
            for i in 0..<bagOfWords.count - 4 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1]) \(bagOfWords[i+2]) \(bagOfWords[i+3]) \(bagOfWords[i+4])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return (self.voiceCommandMapping[phrase] ?? phrase, i)
                }
            }
        } else if bagOfWords.count == 5 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1]) \(bagOfWords[2]) \(bagOfWords[3]) \(bagOfWords[4])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\tFound voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return (self.voiceCommandMapping[phrase] ?? phrase, 0)
            }
        }
        
        return nil
    }
    
    func isSelectionVoiceCommand(command: String) -> Bool {
        if (
            command == "delete selection" ||
            command == "update selection" ||
            command == "copy selection" ||
            command == "cut selection" ||
            command == "increase selection rate" ||
            command == "decrease selection rate" ||
            command == "run selection" ||
            command == "walk selection" ||
            command == "accept update selection" ||
            command == "cancel update selection" ||
            command == "redo" ||
            command == "stop run" ||
            command == "freeze run" ||
            command == "halt run" ||
            command == "pause run" ||
            command == "next element" ||
            command == "previous element" ||
            command == "remove selection" ||
            command == "exit mode" ||
            command == "shift anchor right" ||
            command == "shift anchor left" ||
            command == "shift focus left" ||
            command == "shift focus right" ||
            command == "shift forward" ||
            command == "shift backward" ||
            command == "expand selection" ||
            command == "reduce selection" ||
            command == "play" ||
            command == "echo"
        ) {
            return true
        }
        
        return false
    }
    
    func process(note: Note, query: String, handler: (() -> Void)? = nil) {
        print("===== Processing Voice Command =====")
        let query = query.lowercased()
        print("\tQuery: \"\(self.voiceCommandMapping[query] ?? query)\"")
        
        switch (self.voiceCommandMapping[query]) {
        case "play note":
            note.vc!.handlePlay(voiceCommand: true, handler: handler)
        case "pause note":
            note.vc!.handlePause(voiceCommand: true, handler: handler)
        case "start note":
            note.vc!.handleStartNote(voiceCommand: true, handler: handler)
        case "stop note":
            if note.isPlayingNote {
                note.vc!.handleStopPlaying(voiceCommand: true, handler: handler)
            } else {
                note.vc!.handleStopListeningNote(voiceCommand: true, handler: handler)
            }
        case "resume note":
            note.vc!.handleResumeNote(voiceCommand: true, handler: handler)
        case "echo note":
            note.vc!.handleEcho(voiceCommand: true, handler: handler)
        case "pause echo":
            note.vc!.handlePauseEcho(voiceCommand: true, handler: handler)
        case "stop echo":
            note.vc!.handleStopEcho(voiceCommand: true, handler: handler)
        case "play previous sentence":
            self.handlePlayPreviousSentence(note: note, handler: handler)
        case "echo previous sentence":
            self.handleEchoPreviousSentence(note: note, handler: handler)
        case "activate punctuation":
            print("\tVoice Command: Activate Skip Punctuation")
            
            // Play Sound
            soundEngine.voiceCommandAccept()

            note.setSkipPunctuation(to: false)
            handler?()
        case "deactivate punctuation":
            print("\tVoice Command: Deactivate Skip Punctuation")
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.setSkipPunctuation(to: true)
            handler?()
        case "activate silences":
            print("\tVoice Command: Activate Silence")
            
            // Play Sound
            soundEngine.voiceCommandAccept()

            note.setOmitSilences(to: false)
            handler?()
        case "deactivate silences":
            print("\tVoice Command: Deactivate Silence")
            
            // Play Sound
            soundEngine.voiceCommandAccept()

            note.setOmitSilences(to: true)
            handler?()
        case "activate temporal suggestions":
            print("\tVoice Command: Activate Temporal Suggestions")

            // Play Sound
            soundEngine.voiceCommandAccept()

            note.setWithTemporalSuggestions(to: true)
            handler?()
        case "deactivate temporal suggestions":
            print("\tVoice Command: Deactivate Temporal Suggestions")

            // Play Sound
            soundEngine.voiceCommandAccept()

            note.setWithTemporalSuggestions(to: false)
            handler?()
        case "activate punctuation suggestions":
            print("\tVoice Command: Activate Punctuation Suggestions")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
        
            note.setWithPunctuationSuggestions(to: true)
            handler?()
        case "deactivate punctuation suggestions":
            print("\tVoice Command: Deactivate Punctuation Suggestions")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
        
            note.setWithPunctuationSuggestions(to: false)
            handler?()
        case "activate formatting suggestions":
            print("\tVoice Command: Activate Formatting Suggestions")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.setWithFormattingSuggestions(to: true)
            handler?()
        case "deactivate formatting suggestions":
            print("\tVoice Command: Deactivate Formatting Suggestions")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.setWithFormattingSuggestions(to: false)
            handler?()
        case "activate passive echo":
            print("\tVoice Command: Activate Passive Echo")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.setWithPassiveEcho(to: true)
            handler?()
        case "deactivate passive echo":
            print("\tVoice Command: Deactivate Passive Echo")
            
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.setWithPassiveEcho(to: false)
            handler?()
        case "increase volume":
            print("\tVoice Command: Increase Volume")
            self.handleIncreaseVolume(note: note, handler: handler)
        case "decrease volume":
            print("\tVoice Command: Decrease Volume")
            self.handleDecreaseVolume(note: note, handler: handler)
//        case "adjust volume":
//            startListeningForVolume(note: note)
        case "increase echo rate":
            print("\tVoice Command: Increase Echo Rate")
            self.handleIncreaseEchoRate(note: note, handler: handler)
        case "decrease echo rate":
            print("\tVoice Command: Decrease Echo Rate")
            self.handleDecreaseEchoRate(note: note, handler: handler)
        case "increase playback rate":
            print("\tVoice Command: Increase Playback Rate")
            self.handleIncreasePlaybackRate(note: note, handler: handler)
        case "decrease playback rate":
            print("\tVoice Command: Decrease Playback Rate")
            self.handleDecreasePlaybackRate(note: note, handler: handler)
        case "accept update selection":
            print("\tVoice Command: Accept Update Selection")
            self.handleAcceptUpdateSelection(note: note, handler: handler)
        case "redo":
            if selectionCursor.hasSelection && selectionCursor.isUpdatingSelection && selectionCursor.isPromptingForUpdateAcceptance {
                print("\tVoice Command: Redo Update Selection")
                self.handleRedoUpdateSelection(note: note, handler: handler)
            } else {
                // Normal Redo
            }
        case "cancel update selection":
            self.handleCancelUpdateSelection(note: note, handler: handler)
        case "delete selection":
            note.vc!.handleDeleteSelection(voiceCommand: true, handler: handler)
        case "update selection":
            note.vc!.handleUpdateSelection(voiceCommand: true, handler: handler)
        case "copy selection":
            note.vc!.handleCopySelection(voiceCommand: true, handler: handler)
        case "cut selection":
            note.vc!.handleCutSelection(voiceCommand: true, handler: handler)
        case "increase selection rate":
            note.vc!.handleIncreaseRateSelection(voiceCommand: true, handler: handler)
        case "decrease selection rate":
            note.vc!.handleDecreaseRateSelection(voiceCommand: true, handler: handler)
        case "export note", "export selection":
            note.vc!.handleExport(voiceCommand: true, handler: handler)
        case "pause playback":
            note.vc!.handlePause(voiceCommand: true, handler: handler)
        case "resume playback":
            self.handleResumePlayback(note: note, handler: handler)
        case "resume echo":
            note.vc!.handleEcho(voiceCommand: true, handler: handler)
        case "edit note":
            note.vc!.handleEditNote(voiceCommand: true, handler: handler)
        case "play commit":
            note.vc!.handlePlayCommit(voiceCommand: true, handler: handler)
        case "echo commit":
            self.handleEchoCommit(note: note, handler: handler)
        case "select commit":
            self.handleSelectCommit(note: note, handler: handler)
        case "walk commit":
            self.handleWalkCommit(note: note, handler: handler)
        case "run commit":
            self.handleRunCommit(note: note, handler: handler)
        case "rollback commit":
            self.handleRollbackCommit(note: note, handler: handler)
        case "inspect clipboard":
            note.vc!.handleInspectClipboard(voiceCommand: true, handler: handler)
        case "skip backward":
            note.vc!.handleSkipBackward(voiceCommand: true, handler: handler)
        case "skip forward":
            note.vc!.handleSkipForward(voiceCommand: true, handler: handler)
        case "stop playback":
            note.vc!.handleStopPlaying(voiceCommand: true, handler: handler)
        case "open selection":
            self.handleOpenSelection(note: note, handler: handler)
        case "remove selection":
            self.handleRemoveSelection(note: note, handler: handler)
        case "shift anchor left":
            self.handleShiftAnchor(direction: .left, note: note, handler: handler)
        case "shift anchor right":
            self.handleShiftAnchor(direction: .right, note: note, handler: handler)
        case "shift focus left":
            self.handleShiftFocus(direction: .left, note: note, handler: handler)
        case "shift focus right":
            self.handleShiftFocus(direction: .right, note: note, handler: handler)
        case "shift forward":
            self.handleShift(direction: .right, note: note, handler: handler)
        case "shift backward":
            self.handleShift(direction: .left, note: note, handler: handler)
        case "expand selection":
            self.handleExpandSelection(note: note, handler: handler)
        case "reduce selection":
            self.handleReduceSelection(note: note, handler: handler)
        case "run selection":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            let selection = selectionCursor.selectionSegments
            note.run(segments: selection, onStartHandler: handler)
        case "walk selection":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            let selection = selectionCursor.selectionSegments
            note.walk(segments: selection, onStartHandler: handler)
        case "run note":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.run(onStartHandler: handler)
        case "walk note":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.walk(onStartHandler: handler)
        case "next element":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.walkToNextSegment(handler: handler)
        case "previous element":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.walkToPreviousSegment(handler: handler)
        case "halt run":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.haltRun(handler: handler)
        case "exit mode":
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            note.exitWalk(handler: handler)
        case "pause":
            if note.isPlayingNote {
                note.vc!.handlePause(voiceCommand: true, handler: handler)
            } else if note.isPlayingEcho {
                note.vc!.handlePauseEcho(voiceCommand: true, handler: handler)
            } else if note.isRunningNote {
                // Play Sound
                soundEngine.voiceCommandAccept()

                note.haltRun(handler: handler)
            }
        case "stop":
            if note.isPlayingNote {
                note.vc!.handleStopPlaying(voiceCommand: true, handler: handler)
            } else if note.isPlayingEcho {
                note.vc!.handleStopEcho(voiceCommand: true, handler: handler)
            } else if note.isRunningNote {
                // Play Sound
                soundEngine.voiceCommandAccept()
                
                note.haltRun(handler: handler)
            }
        case "paste clipboard":
            note.vc!.handlePasteClipboard(voiceCommand: true, handler: handler)
        case "move here":
            // Play Sound
            soundEngine.voiceCommandAccept()
        case "undo":
            // Play Sound
            soundEngine.voiceCommandAccept()
        case "prompt for assistance":
            // Play Sound
            soundEngine.voiceCommandAccept()
        default:
            // Play Sound
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
    
    func handlePlayPreviousSentence(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Play Previous Sentence")
        if note.noteSegments.count == 0 {
            Utils.executeError(note: note, text: "Note is empty.", voiceCommand: true, handler: handler)
            return
        }

        let executePlay = {
            let previousSentenceIndex = max(note.numSentences - 1, 0)
            
            if note.numSentences == 1 {
                Utils.executeError(note: note, text: "No previous sentence exists.", voiceCommand: true, handler: handler)
                return
            }
            
            // Play Sound
            soundEngine.voiceCommandAccept()

            note.playSentence(
                number: previousSentenceIndex,
                onStartHandler: {
                    DispatchQueue.main.async {
                        if !note.isListeningForSpeech {
                            note.vc!.adjustCommandBar()
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
                        if let segment = note.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let range = note.getSegmentTextRange(of: segment) {
                            // update text
                            note.vc!.updateUIText(text: note.getText(), highlightRange: range, transformations: note.transformations)
                        }
                        
                        if let segment = note.previousBoundarySegment, let pitch = segment.getPitch() {
                            // update pitch
                            note.vc!.pitchLabel.text = pitch.note.string
                        }
                    }
                }, onFinishHandler: {
                    DispatchQueue.main.async {
                        if !selectionCursor.hasSelection {
                            note.vc!.updateUIText(text: note.getText(), transformations: note.transformations)
                        }
                        note.player.replaceCurrentItem(with: nil)
                        if !note.isListeningForSpeech {
                            note.vc!.navigationItem.title = ""
                        }
                        
                        note.vc!.adjustCommandBar()
                        note.vc!.adjustMenuBar()
                        if note.pausedWalkingNote {
                            note.walk() {
                                handler?()
                            }
                        } else if note.pausedRunningNote {
                            note.run() {
                                handler?()
                            }
                        } else {
                            handler?()
                        }
                    }
                }
            )
        }
        
        if note.isWalkingNote || note.isRunningNote {
            note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                if note.isPlayingNote {
                    note.stop() {
                        executePlay()
                    }
                } else {
                    executePlay()
                }
            }
        } else if note.isPlayingNote {
            note.stop() {
                executePlay()
            }
        } else {
            executePlay()
        }
    }
    
    func handleEchoPreviousSentence(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Echo Previous Sentence")
        if note.noteSegments.count == 0 {
            Utils.executeError(note: note, text: "Note is empty.", voiceCommand: true, handler: handler)
            return
        }

        let previousSentenceIndex = max(note.numSentences - 1, 0)
        
        if note.numSentences == 1 {
            Utils.executeError(note: note, text: "No previous sentence exists.", voiceCommand: true, handler: handler)
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()

        note.echoSentence(number: previousSentenceIndex, onStartHandler: handler)
    }
    
    func setPlaybackRate(note: Note, to rate: Float, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Set Playback Rate")
        
        note.vc!.setPlaybackRate(to: rate)
        handler?()
    }
    
    func setEchoRate(note: Note, to rate: Float, handler: (() -> Void)? = nil) {
        note.vc!.setEchoRate(to: rate)
        handler?()
    }
    
    func setPlaybackVolume(note: Note, to volume: Float, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Set Playback Volume")
        
        Utils.setMainVolume(to: volume, note: note)
        handler?()
    }
    
    func handleIncreaseVolume(note: Note, handler: (() -> Void)? = nil) {
        let currentVolume = note.vc!.playbackVolume
        let newVolume = min(currentVolume + Utils.DISCRETE_VOLUME_DELTA, Utils.MAXIMUM_VOLUME).rounded(toPlaces: 2)
        if currentVolume < Utils.MAXIMUM_VOLUME {
            // Play Sound
            soundEngine.voiceCommandAccept()

            setPlaybackVolume(
                note: note,
                to: newVolume
            ) {
                Utils.executeFeedback(
                    visualMessage: "New volume: \(newVolume)",
                    audioMessage: "Volume increased to \(newVolume)",
                    note: note,
                    withHaptics: true
                )
                
                handler?()
            }
        } else {
            Utils.executeError(note: note, text: "Volume already at maximum.", voiceCommand: true, handler: handler)
        }
    }
    
    func handleDecreaseVolume(note: Note, handler: (() -> Void)? = nil) {
        let currentVolume = note.vc!.playbackVolume
        let newVolume = max(currentVolume - Utils.DISCRETE_VOLUME_DELTA, Utils.MINIMUM_VOLUME).rounded(toPlaces: 2)
        if currentVolume > Utils.MINIMUM_VOLUME {
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            setPlaybackVolume(
                note: note,
                to: newVolume
            ) {
                Utils.executeFeedback(
                    visualMessage: "New volume: \(newVolume)",
                    audioMessage: "Volume decreased to \(newVolume)",
                    note: note,
                    withHaptics: true
                )
                
                handler?()
            }
        } else {
            Utils.executeError(note: note, text: "Volume already at minimum.", voiceCommand: true, handler: handler)
        }
    }
    
    func handleIncreaseEchoRate(note: Note, handler: (() -> Void)? = nil) {
        let currentEchoRate = note.vc!.echoRate
        let newEchoRate = min(currentEchoRate + Utils.DISCRETE_ECHO_RATE_DELTA, Utils.MAXIMUM_ECHO_RATE).rounded(toPlaces: 2)
        if currentEchoRate < Utils.MAXIMUM_ECHO_RATE {
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            setEchoRate(
                note: note,
                to: newEchoRate
            ) {
                Utils.executeFeedback(
                    visualMessage: "Echo Rate: \(newEchoRate)",
                    audioMessage: "Echo Rate increased to \(newEchoRate)",
                    note: note,
                    withHaptics: true
                )
        
                handler?()
            }
        } else {
            Utils.executeError(note: note, text: "Echo Rate already at fastest.", voiceCommand: true, handler: handler)
        }
    }
    
    func handleDecreaseEchoRate(note: Note, handler: (() -> Void)? = nil) {
        let currentEchoRate = note.vc!.echoRate
        let newEchoRate = max(currentEchoRate - Utils.DISCRETE_ECHO_RATE_DELTA, Utils.MINIMUM_ECHO_RATE).rounded(toPlaces: 2)
        if currentEchoRate > Utils.MINIMUM_ECHO_RATE {
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            setEchoRate(
                note: note,
                to: newEchoRate
            ) {
                Utils.executeFeedback(
                    visualMessage: "Echo Rate: \(newEchoRate)",
                    audioMessage: "Echo Rate decreased to \(newEchoRate)",
                    note: note,
                    withHaptics: true
                )
        
                handler?()
            }
        } else {
            Utils.executeError(note: note, text: "Echo Rate already at slowest.", voiceCommand: true, handler: handler)
        }
    }
    
    func handleIncreasePlaybackRate(note: Note, handler: (() -> Void)? = nil) {
        let currentPlaybackRate = note.vc!.playbackRate
        let newPlaybackRate = min(currentPlaybackRate + Utils.DISCRETE_PLAYBACK_DELTA, Utils.MAXIMUM_PLAYBACK_RATE).rounded(toPlaces: 2)
        if currentPlaybackRate < Utils.MAXIMUM_PLAYBACK_RATE {
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            setPlaybackRate(
                note: note,
                to: newPlaybackRate
            ) {
                Utils.executeFeedback(
                    visualMessage: "Playback Rate: \(newPlaybackRate)",
                    audioMessage: "Playback Rate increased to \(newPlaybackRate)x",
                    note: note,
                    withHaptics: true
                )

                handler?()
            }
        } else {
            Utils.executeError(note: note, text: "Playback Rate already at fastest.", voiceCommand: true, handler: handler)
        }
    }
    
    func handleDecreasePlaybackRate(note: Note, handler: (() -> Void)? = nil) {
        let currentPlaybackRate = note.vc!.playbackRate
        let newPlaybackRate = max(currentPlaybackRate - Utils.DISCRETE_PLAYBACK_DELTA, Utils.MINIMUM_PLAYBACK_RATE).rounded(toPlaces: 2)
        if currentPlaybackRate > Utils.MINIMUM_PLAYBACK_RATE {
            // Play Sound
            soundEngine.voiceCommandAccept()
            
            setPlaybackRate(
                note: note,
                to: newPlaybackRate
            ) {
                Utils.executeFeedback(
                    visualMessage: "Playback Rate: \(newPlaybackRate)",
                    audioMessage: "Playback Rate decreased to \(newPlaybackRate)x",
                    note: note,
                    withHaptics: true
                )

                handler?()
            }
        } else {
            Utils.executeError(note: note, text: "Playback Rate already at slowest.", voiceCommand: true, handler: handler)
        }
    }
    
    func handleResumePlayback(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Resume Playback")
        
        if note.pausedListeningForSpeech {
            Utils.executeError(note: note, text: "Note not paused.", voiceCommand: true, handler: handler)
            return
        }
        
        note.vc!.handleStartNote(voiceCommand: true, handler: handler)
    }
    
    func handleEchoCommit(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Echo Commit")

        if note.committedBufferRanges.count == 0 {
            Utils.executeError(note: note, text: "No previous commits.", voiceCommand: true, handler: handler)
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let executeEcho = {
            let commit = note.getLastCommit()
            print("\tLast Commit: ", note.getText(segments: commit))
            guard let lastCommit = commit else {
                Utils.executeError(note: note, text: "Unable to find last commit.", handler: handler)
                return
            }

            note.startEcho(
                segments: Array(lastCommit),
                onStartHandler: {
                    DispatchQueue.main.async {
                        note.vc!.adjustCommandBar()
                        note.vc!.adjustMenuBar()
                    }
                },
                onFinishHandler: {
                    DispatchQueue.main.async {
                        note.vc!.adjustCommandBar()
                        note.vc!.adjustMenuBar()
                        if note.pausedWalkingNote {
                            note.walk() {
                                handler?()
                            }
                        } else if note.pausedRunningNote {
                            note.run() {
                                handler?()
                            }
                        } else {
                            handler?()
                        }
                    }
                }
            )
        }
        
        if note.isWalkingNote || note.isRunningNote {
            note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                if note.isPlayingEcho {
                    note.stopEcho() {
                        executeEcho()
                    }
                } else {
                    executeEcho()
                }
            }
        } else if note.isPlayingEcho {
            note.stopEcho() {
                executeEcho()
            }
        } else {
            executeEcho()
        }
    }
    
    func handleSelectCommit(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Select Commit")

        if note.committedBufferRanges.count == 0 {
            Utils.executeError(note: note, text: "No previous commits.", voiceCommand: true, handler: handler)
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        let commit = note.getLastCommit()
        print("\tLast Commit: ", note.getText(segments: commit))
        guard let lastCommit = commit else {
            Utils.executeError(note: note, text: "Unable to find last commit.", handler: handler)
            return
        }
        var newFocus: NoteSegment? = lastCommit.last
        var newAnchor: NoteSegment?  = lastCommit.first
        
        if let anchor = newAnchor, !anchor.isActive() {
            print("\tSearching for valid anchor...")
            newAnchor = note.getSegment(segment: anchor, segments: Array(lastCommit), type: .next, isWord: true)
        }
        
        if let focus = newFocus, !focus.isActive() {
            print("\tSearching for valid focus...")
            newFocus = note.getSegment(segment: focus, segments: Array(lastCommit), type: .previous, isWord: true)
        }
        
        if let anchor = newAnchor, let focus = newFocus {
            // Select Previous Commit
            print("\tSetting selection...")
            selectionCursor.setSelection(anchor: anchor, focus: focus)
        }
        
        handler?()
    }
    
    func handleRollbackCommit(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Rollback Commit")

        if note.committedBufferRanges.count == 0 {
            Utils.executeError(note: note, text: "No previous commits.", voiceCommand: true, handler: handler)
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        // Select Previous Commit
        self.handleSelectCommit(note: note)
        
        // Delete current selection
        note.vc!.handleDeleteSelection(voiceCommand: true, isCommit: true, handler: handler)
    }
    
    func handleWalkCommit(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Walk Commit")

        if note.committedBufferRanges.count == 0 {
            Utils.executeError(note: note, text: "No previous commits.", voiceCommand: true, handler: handler)
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        // Select Previous Commit
        self.handleSelectCommit(note: note)
        
        // Walk current selection
        note.vc!.handleWalk(voiceCommand: true, handler: handler)
    }
    
    func handleRunCommit(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Walk Commit")

        if note.committedBufferRanges.count == 0 {
            Utils.executeError(note: note, text: "No previous commits.", voiceCommand: true, handler: handler)
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        // Select Previous Commit
        self.handleSelectCommit(note: note)
        
        // Run current selection
        note.vc!.handleRun(voiceCommand: true, handler: handler)
    }
    
    func handleOpenSelection(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Open Selection")
        
        if note.noteSegments.count == 0 {
            Utils.executeError(note: note, text: "Note is empty.", voiceCommand: true, handler: handler)
            return
        }
        
        let currentAnchor = selectionCursor.anchor
        var newSelection = currentAnchor
        if let segment = newSelection, selectionCursor.isAtEndOfTextView {
            // set last word as selection
            if segment.isPunctuation() ||
                segment.isSilence() ||
                segment.isVoiceCommandWord() ||
                segment.isDeleted() ||
                !segment.isCommitted() {
                newSelection = note.getSegment(segment: segment, segments: note.noteSegments, type: .previous, isWord: true, isCommitted: true)
            }
        } else if let segment = newSelection {
            // set word after anchor as selection
            if segment.isPunctuation() ||
                segment.isSilence() ||
                segment.isVoiceCommandWord() ||
                segment.isDeleted() ||
                !segment.isCommitted() {
                newSelection = note.getSegment(segment: segment, segments: note.noteSegments, type: .next, isWord: true, isCommitted: true)
            }
        }
        
        if let newSelection = newSelection {
            // Play Sound
            soundEngine.voiceCommandAccept()

            selectionCursor.setSelection(anchor: newSelection, focus: newSelection)
            
            Utils.executeFeedback(
                visualMessage: "Selection Opened!",
                note: note,
                withHaptics: true
            )
            
            handler?()
        } else {
            print("\t[Error] There was a problem opening selection. Unable to locate suitable segment.")
            Utils.executeError(note: note, text: "Unable to locate suitable segment.", handler: handler)
        }
    }
    
    func handleRemoveSelection(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Remove Selection")

        if !selectionCursor.hasSelection {
            Utils.executeError(note: note, text: "No selection exists.", voiceCommand: true, handler: handler)
            return
        }
        
        // Play Sound
        soundEngine.voiceCommandAccept()
        
        selectionCursor.clearSelection(withFeedback: true) {
            DispatchQueue.main.async {
                note.vc!.adjustCommandBar()
                note.vc!.adjustMenuBar()
            }
        }
        
        handler?()
    }
    
    func handleAcceptUpdateSelection(note: Note, handler: (() -> Void)? = nil) {
        if selectionCursor.hasSelection && selectionCursor.isUpdatingSelection && selectionCursor.isPromptingForUpdateAcceptance {
            // Play Sound
            soundEngine.voiceCommandAccept()

            // Dismiss Dialog
            Utils.dismissDialog(vc: note.vc!)
            
            // Turn off ambient track
            soundEngine.stopModalAmbience()

            // Clear buffer segments
            print("\tClearing note buffer...")
            note.clearBuffer()
            
            // Accept Update
            print("\tAccepting Update Selection...")
            selectionCursor.acceptUpdateSelection(handler: handler)
        } else if !selectionCursor.hasSelection {
            Utils.executeError(note: note, text: "No existing selection.", voiceCommand: true, handler: handler)
        } else if !selectionCursor.isUpdatingSelection {
            Utils.executeError(note: note, text: "Say \"update\" to replace selection.", voiceCommand: true, handler: handler)
        } else if !selectionCursor.isPromptingForUpdateAcceptance {
            Utils.executeError(note: note, text: "No update yet.", voiceCommand: true, handler: handler)
        }
    }
    
    func handleRedoUpdateSelection(note: Note, handler: (() -> Void)? = nil) {
        if selectionCursor.hasSelection && selectionCursor.isUpdatingSelection && selectionCursor.isPromptingForUpdateAcceptance {
            // Play Sound
            soundEngine.voiceCommandAccept()

            // Dismiss Dialog
            Utils.dismissDialog(vc: note.vc!)
            
            // Turn off ambient track
            soundEngine.stopModalAmbience()

            // Clear buffer segments
            print("\tClearing note buffer...")
            note.clearBuffer()
            
            // Redo Update Selection
            print("\tRedoing Update Selection...")
            selectionCursor.initiateUpdateSelection(handler: handler)
        } else if !selectionCursor.hasSelection {
            Utils.executeError(note: note, text: "No existing selection.", voiceCommand: true, handler: handler)
        } else if !selectionCursor.isUpdatingSelection {
            Utils.executeError(note: note, text: "Say \"update\" to replace selection.", voiceCommand: true, handler: handler)
        } else if !selectionCursor.isPromptingForUpdateAcceptance {
            Utils.executeError(note: note, text: "No update yet.", voiceCommand: true, handler: handler)
        }
    }
    
    func handleCancelUpdateSelection(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Cancel Update Selection")
        
        if selectionCursor.hasSelection && selectionCursor.isUpdatingSelection {
            // Play Sound
            soundEngine.voiceCommandAccept()

            // Dismiss Dialog
            Utils.dismissDialog(vc: note.vc!)
            
            // Turn off ambient track
            soundEngine.stopModalAmbience()

            // Clear buffer segments
            print("\tClearing note buffer...")
            note.clearBuffer()
            
            // Cancel Update Selection
            print("\tCanceling Update Selection...")
            selectionCursor.cancelUpdateSelection(handler: handler)
        } else if !selectionCursor.hasSelection {
            Utils.executeError(note: note, text: "No existing selection.", voiceCommand: true, handler: handler)
        } else if !selectionCursor.isUpdatingSelection {
            Utils.executeError(note: note, text: "Update mode not active.", voiceCommand: true, handler: handler)
        }
    }
    
    func handleShiftAnchor(direction: DirectionType, note: Note, withFeedback: Bool = true, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Shift Anchor \(direction == .left ? "Left" : "Right")")

        if !selectionCursor.hasSelection {
            Utils.executeError(note: note, text: "No existing selection.", voiceCommand: true, handler: handler)
            return
        }
        
        var newAnchor: NoteSegment?
        if let currentAnchor = selectionCursor.anchor, direction == .left {
            newAnchor = note.getSegment(segment: currentAnchor, segments: note.noteSegments, type: .previous, isWord: true)
        } else if let currentAnchor = selectionCursor.anchor, let currentFocus = selectionCursor.focus, direction == .right && currentAnchor.getUID() != currentFocus.getUID() {
            newAnchor = note.getSegment(segment: currentAnchor, segments: note.noteSegments, type: .next, isWord: true)
        }
        
        if let newAnchor = newAnchor {
            if withFeedback {
                // Play Sound
                soundEngine.voiceCommandAccept()
            }

            selectionCursor.setAnchor(segment: newAnchor)
            
            if withFeedback {
                Utils.executeFeedback(
                    visualMessage: "Selection Updated!",
                    note: note,
                    withHaptics: true
                )
            }
            print("\tShifted anchor \(direction == .left ? "left" : "right")")
            handler?()
        } else if let currentAnchor = selectionCursor.anchor, let currentFocus = selectionCursor.focus, currentAnchor.getUID() == currentFocus.getUID() {
            print("\tUnable to shift anchor right because we're selecting a single segment")
        } else {
            print("\t[Error] There was a problem updating selection anchor. Unable to locate suitable segment.")
            Utils.executeError(note: note, text: "Unable to update selection.", handler: handler)
        }
    }
    
    func handleShiftFocus(direction: DirectionType, note: Note, withFeedback: Bool = true, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Shift Focus \(direction == .left ? "Left" : "Right")")

        if !selectionCursor.hasSelection {
            Utils.executeError(note: note, text: "No existing selection.", voiceCommand: true, handler: handler)
            return
        }
        
        
        var newFocus: NoteSegment?
        if let currentFocus = selectionCursor.focus, let currentAnchor = selectionCursor.anchor, direction == .left && currentAnchor.getUID() != currentFocus.getUID() {
            newFocus = note.getSegment(segment: currentFocus, segments: note.noteSegments, type: .previous, isWord: true)
        } else if let currentFocus = selectionCursor.focus, direction == .right {
            newFocus = note.getSegment(segment: currentFocus, segments: note.noteSegments, type: .next, isWord: true)
        }
        
        if let newFocus = newFocus {
            if withFeedback {
                // Play Sound
                soundEngine.voiceCommandAccept()
            }

            selectionCursor.setFocus(segment: newFocus)
            
            if withFeedback {
                Utils.executeFeedback(
                    visualMessage: "Selection Updated!",
                    note: note,
                    withHaptics: true
                )
            }
            print("\tShifted focus \(direction == .left ? "left" : "right")")
            handler?()
        } else if let currentAnchor = selectionCursor.anchor, let currentFocus = selectionCursor.focus, currentAnchor.getUID() == currentFocus.getUID() {
            print("\tUnable to shift focus left because we're selecting a single segment")
        } else {
            print("\t[Error] There was a problem updating selection focus. Unable to locate suitable segment.")
            Utils.executeError(note: note, text: "Unable to update selection.", handler: handler)
        }
    }
    
    func handleShift(direction: DirectionType, note: Note, withFeedback: Bool = true, handler: (() -> Void)? = nil) {
        self.handleShiftAnchor(direction: direction, note: note, withFeedback: false)
        self.handleShiftFocus(direction: direction, note: note, handler: handler)
    }
    
    func handleExpandSelection(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Expand Selection")
        self.handleShiftAnchor(direction: .left, note: note, withFeedback: false)
        self.handleShiftFocus(direction: .right, note: note, handler: handler)
    }
    
    func handleReduceSelection(note: Note, handler: (() -> Void)? = nil) {
        print("\tVoice Command: Reduce Selection")
        self.handleShiftAnchor(direction: .right, note: note, withFeedback: false)
        self.handleShiftFocus(direction: .left, note: note, handler: handler)
    }
    
//    func trimNote(note: Note, handler: (() -> Void)? = nil) {
//        print("\tVoice Command: Trim Note")
//
//        // note.trim(keeping: <#T##CMTimeRange#>)
//    }
    
//    func startListeningForVolume(note: Note) {
//        if note.isListeningForSpeech {
//            note.stopListeningForSpeech() {
//                note.vc!.startListeningForVolume()
//            }
//        } else if note.isListeningForCommands {
//            note.stopListeningForVoiceCommands() {
//                note.vc!.startListeningForVolume()
//            }
//        }
//    }
}
