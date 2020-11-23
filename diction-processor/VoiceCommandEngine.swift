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
    static let onProcessedVoiceCommand = Notification.Name(Notifications.onProcessedVoiceCommand.rawValue)
    static let voiceCommands = [
        "play note",
        "pause note",
        "create note",
        "new note",
        "start note",
        "start a note",
        "start not",
        "start notes",
        "starting it",
        "stagnant",
        "starts not",
        "stocks not",
        "stock note",
        "scott's not",
        "scott note",
        "scott not",
        "starting out",
        "stop note",
        "resume note",
        "continue note",
        "echo note",
        "play echo",
        "start echo",
        "pause echo",
        "stop echo",
        "play last sentence",
        "play previous sentence",
        "echo last sentence",
        "echo previous sentence",
        "ecko last sentence",
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
        "turn echo rate up",
        "turn echo rate down",
        "increase echo rate",
        "decrease echo rate",
        "adjust echo rate up",
        "adjust echo rate down",
        "echo rate up",
        "echo rate down",
        "turn playback rate up",
        "turn playback rate down",
        "increase playback rate",
        "decrease playback rate",
        "adjust playback rate up",
        "adjust playback rate down",
        "playback rate up",
        "playback rate down",
        "delete",
        "delete note",
        "delete selection",
        "update",
        "replace",
        "update selection",
        "replace selection",
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
        "exports selection",
        "move here",
        "place cursor",
        "run",
        "run selection",
        "walk",
        "walk selection",
        "run note",
        "walk note",
        "pause playback",
        "resume playback",
        "continue playback",
        "resume echo",
        "continue echo",
        "edit note",
        "play last commit",
        "play last comment",
        "echo last commit",
        "echo last comment",
        "ecko last commit",
        "ecko last comment",
        "walk commit",
        "walk comment",
        "run commit",
        "run comment",
        "play commit",
        "play comment",
        "echo commit",
        "echo comment",
        "ecko commit",
        "ecko comment",
        "preview clipboard",
        "check clipboard",
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
        "exports note",
        "exports notes",
        "exports not",
        "accept",
        "except",
        "redo",
        "cancel",
        "start selection",
        "begin selection",
        "open selection",
        "make selection",
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
        "unselect",
        "undo",
        "redo",
        "exit",
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
        "expand selection",
        "expand",
        "reduce selection",
        "reduce",
        "paste selection",
        "paste clipboard",
        "help",
        "play",
        "echo",
        "unselect",
        "grant permission",
        "cancel",
        "continue",
        "export audio",
        "exports audio",
        "export text",
        "exports text",
        "echo selection",
        "play selection"
    ]

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
        "starts not",
        "stocks not",
        "stock note",
        "scott note",
        "scott not",
        "scott's not",
        "starting out",
        "stop note",
        "stop not",
        "stop notes",
        "resume note",
        "resume not",
        "resume notes",
        "continue note",
        "delete note",
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
        "replace",
        "update selection",
        "replace selection",
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
        "exports selection",
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
        "exports note",
        "exports notes",
        "exports not",
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
        "echo",
        "ekho",
        "unselect",
        "grant permission",
        "cancel",
        "continue",
        "export audio",
        "export text",
        "exports audio",
        "exports text",
        "echo selection",
        "ecko selection",
        "play selection"
    ] // Make sure to add in contextual strings as well
    
    let voiceCommandMapping: [String : String] = [
        "play note": "play note",
        "play not": "play note",
        "play notes": "play note",
        "pause note": "pause note",
        "pause not": "pause note",
        "pause notes": "pause note",
        "new note": "create note",
        "create note": "create note",
        "start note": "start note",
        "stagnant": "start note",
        "starting it": "start note",
        "start a note": "start note",
        "start not": "start note",
        "start notes": "start note",
        "stock note": "start note",
        "scott note": "start note",
        "scott not": "start note",
        "scott's not": "start note",
        "starting out": "start note",
        "starts not": "start note",
        "stocks not": "start note",
        "stop note": "stop note",
        "stop not": "stop note",
        "stop notes": "stop note",
        "resume note": "resume note",
        "resume not": "resume note",
        "resume notes": "resume note",
        "continue note": "resume note",
        "delete note": "delete note",
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
        "delete": "delete",
        "delete selection": "delete selection",
        "update": "update selection",
        "update selection": "update selection",
        "replace": "update selection",
        "replace selection": "update selection",
        "copy": "copy selection",
        "copy selection": "copy selection",
        "cut": "cut selection",
        "cut selection": "cut selection",
        "increase rate": "increase selection rate",
        "increase selection rate": "increase selection rate",
        "decrease rate": "decrease selection rate",
        "decrease selection rate": "increase selection rate",
        "export": "export",
        "export selection": "export selection",
        "exports selection": "export selection",
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
        "exports note": "export note",
        "exports not": "export note",
        "exports notes": "export note",
        "accept": "accept update selection",
        "except": "accept update selection",
        "accept update selection": "accept update selection",
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
        "freeze": "pause run",
        "freeze run": "pause run",
        "stop": "stop",
        "stop run": "pause run",
        "halt": "pause run",
        "holt": "pause run",
        "halt run": "pause run",
        "holt run": "pause run",
        "pause": "pause",
        "pause run": "pause run",
        "remove selection": "remove selection",
        "clear selection": "remove selection",
        "unselect": "remove selection",
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
        "play selection": "play selection",
        "play": "play selection",
        "echo selection": "echo selection",
        "ekho selection": "echo selection",
        "echo": "echo",
        "ekho": "echo",
        "grant permission": "",
        "cancel": "cancel",
        "continue": "continue",
        "export audio": "export audio",
        "exports audio": "export audio",
        "export text": "export text",
        "exports text": "export text"
    ]
    
    func includesCommand(passage: String) -> (String, Int)? {
        let bagOfWords = passage.lowercased().components(separatedBy: " ")
        
        // Check for one word commands
        if bagOfWords.count > 1 {
            for i in 0..<bagOfWords.count - 1 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\t[Success] Found voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return (self.voiceCommandMapping[phrase] ?? phrase, i)
                }
            }
        } else if bagOfWords.count == 1 {
            let phrase = bagOfWords[0]
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\t[Success] Found voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return (self.voiceCommandMapping[phrase] ?? phrase, 0)
            }
        }
        
        // Check for two word commands
        if bagOfWords.count > 2 {
            for i in 0..<bagOfWords.count - 1 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\t[Success] Found voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return (self.voiceCommandMapping[phrase] ?? phrase, i)
                }
            }
        } else if bagOfWords.count == 2 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\t[Success] Found voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return (self.voiceCommandMapping[phrase] ?? phrase, 0)
            }
        }
        
        // Check for three word commands
        if bagOfWords.count > 3 {
            for i in 0..<bagOfWords.count - 2 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1]) \(bagOfWords[i+2])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\t[Success] Found voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return (self.voiceCommandMapping[phrase] ?? phrase, i)
                }
            }
        } else if bagOfWords.count == 3 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1]) \(bagOfWords[2])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\t[Success] Found voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return (self.voiceCommandMapping[phrase] ?? phrase, 0)
            }
        }
        
        // Check for four word commands
        if bagOfWords.count > 4 {
            for i in 0..<bagOfWords.count - 3 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1]) \(bagOfWords[i+2]) \(bagOfWords[i+3])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\t[Success] Found voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return (self.voiceCommandMapping[phrase] ?? phrase, i)
                }
            }
        } else if bagOfWords.count == 4 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1]) \(bagOfWords[2]) \(bagOfWords[3])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\t[Success] Found voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return (self.voiceCommandMapping[phrase] ?? phrase, 0)
            }
        }
        
        // Check for five word commands
        if bagOfWords.count > 5 {
            for i in 0..<bagOfWords.count - 4 {
                let phrase = "\(bagOfWords[i]) \(bagOfWords[i+1]) \(bagOfWords[i+2]) \(bagOfWords[i+3]) \(bagOfWords[i+4])"
                if voiceCommands.contains(phrase) {
                    print("===== Voice Command Engine: Includes Command =====")
                    print("\t[Success] Found voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                    return (self.voiceCommandMapping[phrase] ?? phrase, i)
                }
            }
        } else if bagOfWords.count == 5 {
            let phrase = "\(bagOfWords[0]) \(bagOfWords[1]) \(bagOfWords[2]) \(bagOfWords[3]) \(bagOfWords[4])"
            if voiceCommands.contains(phrase) {
                print("===== Voice Command Engine: Includes Command =====")
                print("\t[Success] Found voice command: \"\(self.voiceCommandMapping[phrase] ?? phrase)\"")
                return (self.voiceCommandMapping[phrase] ?? phrase, 0)
            }
        }
        
        print("\t[No Success] No voice command found.")
        return nil
    }
    
    func isSelectionVoiceCommand(command: String) -> Bool {
        if (
            command == "delete selection" ||
            command == "play selection" ||
            command == "echo selection" ||
            command == "update selection" ||
            command == "copy selection" ||
            command == "cut selection" ||
            command == "increase selection rate" ||
            command == "decrease selection rate" ||
            command == "run selection" ||
            command == "walk selection" ||
            command == "accept update selection" ||
            command == "redo" ||
            command == "stop run" ||
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
            command == "reduce selection"
        ) {
            return true
        }
        
        return false
    }
    
    func isNoteVoiceCommand(command: String) -> Bool {
        if (
            command == "play note" ||
            command == "pause note" ||
            command == "start note" ||
            command == "create note" ||
            command == "stop note" ||
            command == "resume note" ||
            command == "echo note" ||
            command == "pause echo" ||
            command == "stop echo" ||
            command == "play previous sentence" ||
            command == "echo previous sentence" ||
            command == "accept update selection" ||
            command == "delete selection" ||
            command == "update selection" ||
            command == "copy selection" ||
            command == "cut selection" ||
            command == "increase selection rate" ||
            command == "decrease selection rate" ||
            command == "export" ||
            command == "export note" ||
            command == "export selection" ||
            command == "pause playback" ||
            command == "resume playback" ||
            command == "resume echo" ||
            command == "edit note" ||
            command == "play commit" ||
            command == "echo commit" ||
            command == "select commit" ||
            command == "walk commit" ||
            command == "run commit" ||
            command == "rollback commit" ||
            command == "skip backward" ||
            command == "skip forward" ||
            command == "stop playback" ||
            command == "open selection" ||
            command == "remove selection" ||
            command == "shift anchor left" ||
            command == "shift anchor right" ||
            command == "shift focus left" ||
            command == "shift focus right" ||
            command == "shift forward" ||
            command == "shift backward" ||
            command == "expand selection" ||
            command == "reduce selection" ||
            command == "run selection" ||
            command == "walk selection" ||
            command == "run note" ||
            command == "walk note" ||
            command == "next element" ||
            command == "previous element" ||
            command == "pause run" ||
            command == "exit mode" ||
            command == "pause" ||
            command == "stop" ||
            command == "paste clipboard" ||
            command == "move here" ||
            command == "echo" ||
            command == "delete note" ||
            command == "play selection" ||
            command == "echo selection"
        ) {
            return true
        }
        
        return false
    }
    
    func isNoteManagerCommand(command: String) -> Bool {
        if (
            command == "play note" ||
            command == "pause note" ||
            command == "start note" ||
            command == "create note" ||
            command == "stop note" ||
            command == "resume note" ||
            command == "echo note" ||
            command == "pause echo" ||
            command == "stop echo" ||
            command == "delete" ||
            command == "delete selection" ||
            command == "update selection" ||
            command == "copy selection" ||
            command == "cut selection" ||
            command == "increase selection rate" ||
            command == "decrease selection rate" ||
            command == "export" ||
            command == "export note" ||
            command == "export selection" ||
            command == "pause playback" ||
            command == "resume echo" ||
            command == "edit note" ||
            command == "play commit" ||
            command == "skip backward" ||
            command == "skip forward" ||
            command == "stop playback" ||
            command == "pause" ||
            command == "stop" ||
            command == "paste clipboard" ||
            command == "resume playback" ||
            command == "walk commit" ||
            command == "run commit" ||
            command == "rollback commit" ||
            command == "select commit" ||
            command == "open selection" ||
            command == "remove selection" ||
            command == "shift anchor left" ||
            command == "shift anchor right" ||
            command == "shift focus right" ||
            command == "shift focus left" ||
            command == "shift forward" ||
            command == "shift backward" ||
            command == "expand selection" ||
            command == "reduce selection" ||
            command == "echo commit" ||
            command == "echo previous sentence" ||
            command == "play previous sentence" ||
            command == "delete note" ||
            command == "play selection" ||
            command == "echo selection" ||
            command == "echo" ||
            command == "cancel" ||
            command == "walk note" ||
            command == "run selection" ||
            command == "walk selection" ||
            command == "run note" ||
            command == "next element" ||
            command == "previous element" ||
            command == "pause run" ||
            command == "exit mode"
        ) {
            return true
        }
        
        return false
    }
    
    func isStateCommand(command: String) -> Bool {
        if (
            command == "activate punctuation" ||
            command == "deactivate punctuation" ||
            command == "activate silences" ||
            command == "deactivate silences" ||
            command == "activate temporal suggestions" ||
            command == "deactivate temporal suggestions" ||
            command == "activate punctuation suggestions" ||
            command == "deactivate punctuation suggestions" ||
            command == "activate formatting suggestions" ||
            command == "deactivate formatting suggestions" ||
            command == "activate passive echo" ||
            command == "deactivate passive echo" ||
            command == "pause" ||
            command == "stop" ||
            command == "increase volume" ||
            command == "decrease volume"
        ) {
            return true
        }
        
        return false
    }
    
    func isSpeechPlayerCommand(command: String) -> Bool {
        if (
            command == "increase playback rate" ||
            command == "decrease playback rate"
        ) {
            return true
        }
        
        return false
    }
    
    func isSpeechSynthesisCommand(command: String) -> Bool {
        if (
            command == "increase echo rate" ||
            command == "decrease echo rate"
        ) {
            return true
        }
        
        return false
    }
    
    func isSelectionCursorCommand(command: String) -> Bool {
        if (
            command == "inspect clipboard"
        ) {
            return true
        }
        
        return false
    }
    
    func isUIManagerCommand(command: String) -> Bool {
        if (
            command == "accept update selection" ||
            command == "redo" ||
            command == "grant permission" ||
            command == "cancel" ||
            command == "continue" ||
            command == "export audio" ||
            command == "export text"
        ) {
            return true
        }
        
        return false
    }

    // command: should be a query after undergoing mapping by voiceCommandMapping
    func process(
        command: String,
        utterance: String,
        handler: (() -> Void)? = nil
    ) {
        print("===== Voice Command Engine: Process =====")
        let utterance = utterance.lowercased()
        print("\tVoice Command: \(command)")
        print("\tUtterance: \"\(utterance)\"")

        if self.isNoteManagerCommand(command: command) ||
            self.isStateCommand(command: command) ||
            self.isSpeechPlayerCommand(command: command) ||
            self.isSpeechSynthesisCommand(command: command) ||
            self.isSelectionCursorCommand(command: command) ||
            self.isUIManagerCommand(command: command)
        {
            print("\tBroadcast processed voice command...")
            // Broadcast Voice Command
            var userInfo: [String: Any] = [
                "command" : command,
                "utterance": utterance
            ]
            if let handler = handler {
                userInfo["handler"] = handler
            }

            NotificationCenter.default.post(
                name: VoiceCommandEngine.onProcessedVoiceCommand,
                object: nil,
                userInfo: userInfo
            )
        } else {
            print("\t[Error] Unable to process voice command!")
        }

        // Unhandled:
        // - Redo
        // - Move Here
        // - Undo
        // - Prompt fro Assistance
    }
    
//    func trimNote(note: Note, handler: (() -> Void)? = nil) {
//        print("\tVoice Command: Trim Note")
//
//        // note.trim(keeping: <#T##CMTimeRange#>)
//    }
    
//    func startListeningForVolume(note: Note) {
//        if note.isListeningForSpeech {
//            note.stopListeningForSpeech() {
//                viewController.startListeningForVolume()
//            }
//        } else if note.isListeningForCommands {
//            note.stopListeningForVoiceCommands() {
//                viewController.startListeningForVolume()
//            }
//        }
//    }
}
