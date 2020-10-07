//
//  Utils.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/3/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Foundation
import AVFoundation
import MediaPlayer

class Utils {
    static let UNKNOWN: Double = -1
    static let SILENCE_SKIP_THRESHOLD = 0.1
    static let CURSOR_WIDTH = 2
    static let EMPTY_NSRANGE = NSRange(location: 0, length: 0)
    static var TALKING_POWER_DELTA: Double {
        if AVAudioSession.isHeadphonesConnected {
            // With headphones, in a relatively empty, small room, near the window, using AirPods Pro mic
            // the background noise read an average of -75dB
            // when talking, the avg. power was -33dB
            // ∆ = 42dB
            // We use 30dB to give some wiggle room
            return 30
        }
        
        // Without headphones, in a relatively empty, small room, near the window, using iPhone SE mic, 30 cm away
        // the background noise read an average of -41dB
        // when talking, the avg. power was -25dB
        // ∆ = 16dB
        // We use 10dB to give some wiggle room
        return 10
    }
    static var VOLUME_POWER_DELTA: Double {
        if AVAudioSession.isHeadphonesConnected {
            return 20
        }

        return 5
    }
    static var EMPHASIS_POWER_DELTA: Double {
        if AVAudioSession.isHeadphonesConnected {
            // With headphones, in a relatively empty, small room, near the window, using AirPods Pro mic
            // the background noise read an average of -69.7dB
            // when talking, the avg. power was -38.9dB
            // when emphasizing, the power was -22.1dB
            // ∆ = 16.8dB
            // We use 16dB to give some wiggle room
            return 30
        }
        
        // Without headphones, in a relatively empty, small room, near the window, using iPhone SE mic, 30 cm away
        // the background noise read an average of -35dB
        // when talking, the avg. power was -28.9dB
        // when emphasizing, the power was -23.5dB
        // ∆ = 5.4dB
        // We use 5dB to give some wiggle room
        return 10
    }
    static var DISCRETE_VOLUME_DELTA: Float = 0.2
    static var DISCRETE_ECHO_RATE_DELTA: Float = 0.05
    static var DISCRETE_PLAYBACK_DELTA: Float = 0.2
    static var DEFAULT_CURSOR_BLINK_RATE: TimeInterval = 0.53
    static var DEFAULT_CURSOR_BLINK_TRANSITION_DURATION: TimeInterval = 0.1
    static var DEFAULT_VIEW_TRANSITION_DURATION: TimeInterval = 0.3
    static let DEFAULT_FIG_COUNT = 2
    static let TEMPORAL_DELTA = 0.01
    static let DEFAULT_SEGMENT_DURATION: Double = 100000 // Must be high enough such that no user will record a note of this duration
    static let TRANSCRIPTION_LATENCY_DURATION: Double = 0.3
    static let SOUND_INTENSITY_SIG_FIG_COUNT: Int = 4
    static let MAXIMUM_VOLUME: Float = 1
    static let MINIMUM_VOLUME: Float = 0.1
    static let MAXIMUM_ECHO_RATE: Float = AVSpeechUtteranceMaximumSpeechRate
    static let MINIMUM_ECHO_RATE: Float = AVSpeechUtteranceMinimumSpeechRate
    static let MAXIMUM_PLAYBACK_RATE: Float = 3
    static let MINIMUM_PLAYBACK_RATE: Float = 0.2
    static let COMMAND_BAR_MAXIMUM_HEIGHT: CGFloat = 410
    static let COMMAND_BAR_MINIMUM_HEIGHT: CGFloat = 260
    static let COMMAND_BAR_BUTTON_HEIGHT: CGFloat = 40
    static let COMMAND_BAR_BUTTON_PADDING: CGFloat = 10
    static let INCREASE_RATE_COMMAND_BUTTON_STANDARD_Y_POSITION: CGFloat = 10
    static let DECREASE_RATE_COMMAND_BUTTON_STANDARD_Y_POSITION: CGFloat = 60
    static let DELETE_COMMAND_BUTTON_STANDARD_Y_POSITION: CGFloat = 110
    static let REPLACE_COMMAND_BUTTON_STANDARD_Y_POSITION: CGFloat = 160
    static let COPY_COMMAND_BUTTON_STANDARD_Y_POSITION: CGFloat = 210
    static let CUT_COMMAND_BUTTON_STANDARD_Y_POSITION: CGFloat = 260
    static let PASTE_COMMAND_BUTTON_STANDARD_Y_POSITION: CGFloat = 310
    static let EXPORT_COMMAND_BUTTON_STANDARD_Y_POSITION: CGFloat = 360
    static var SKIP_PLAYBACK_DURATION: Double = 10
    static var MENU_BAR_HEIGHT: CGFloat = 70
    static var COMMAND_BAR_HEIGHT: CGFloat = 60
    static var COMMAND_BAR_BACKGROUND_COLOR: String = "#7771C2FF"
    static var SCROLL_VIEW_HEIGHT: CGFloat = 60
    
    static let pitchToFrequencyMap: [String : Double] = [
        "C0": 16,
        "D0": 18,
        "E0": 21,
        "F0": 22,
        "G0": 25,
        "A1": 28,
        "B1": 31,
        "C1": 33,
        "D1": 37,
        "E1": 41,
        "F1": 44,
        "G1": 49,
        "A2": 55,
        "B2": 62,
        "C2": 65,
        "D2": 73,
        "E2": 82,
        "F2": 87,
        "G2": 98,
        "A3": 110,
        "B3": 123,
        "C3": 131,
        "D3": 147,
        "E3": 165,
        "F3": 175,
        "G3": 196,
        "A4": 220,
        "B4": 247,
        "C4": 262,
        "D4": 294,
        "E4": 330,
        "F4": 349,
        "G4": 392,
        "A5": 440,
        "B5": 494,
        "C5": 523,
        "D5": 587,
        "E5": 659,
        "F5": 698,
        "G5": 784,
        "A6": 880,
        "B6": 988,
        "C6": 1047,
        "D6": 1175,
        "E6": 1319,
        "F6": 1397,
        "G6": 1568,
        "A7": 1760,
        "B7": 1976,
        "C7": 2093,
        "D7": 2349,
        "E7": 2637,
        "F7": 2794,
        "G7": 3136,
        "A8": 3520,
        "B8": 3951,
        "C8": 4186,
        "D8": 4699,
        "E8": 5274,
        "F8": 5588,
        "G8": 6272
    ]

    // MARK: - Factory Methods
    public static func trimNote(note: Note, keeping: CMTimeRange, permanent: Bool = false, onFinishHandler: @escaping (_ note: Note?) -> Void) {
        print("===== Trim Note Factory Method =====")
        note.duplicate() { note in
            if let duplicateNote = note {
                duplicateNote.trim(keeping: keeping, permanent: permanent) {
                    onFinishHandler(duplicateNote)
                }
            }
        }
    }
    
    // MARK: - General Utilities
    
    // Cannot export to outputURL's that already exist
    // Reference: https://stackoverflow.com/questions/20203548/avassetexportsession-not-exporting-time-range
    // Deleting: https://stackoverflow.com/questions/42041405/delete-a-file-using-swift-in-ios
    public static func exportNote(note: Note, filename: String, fileType: String, timeRange: CMTimeRange, onFinishHandler: (() -> Void)? = nil) {
        print("===== Export Note =====")
        
        do {
            let fileManager = FileManager.default
            let filePath = Utils.getFileURL(of: "\(filename)\(fileType)").absoluteString
            // Check if file exists
            if fileManager.fileExists(atPath: filePath) {
                // Delete file
                print("\tFile exists at specified file path. Delete it...")
                try fileManager.removeItem(atPath: filePath)
                print("\tSuccessfully deleting existing file at file path...")
            } else {
                print("\tFile location is available to write a new file...")
            }

        } catch let error as NSError {
            print("\t[Error] There was a problem while checking for and deleting existing file")
            fatalError("\tMessage: \(error)")
        }

        if !AVAssetExportSession.exportPresets(compatibleWith: note).contains(AVAssetExportPresetAppleM4A) {
            fatalError("\t[Error] Expected export preset value not compatible with note")
        }
        
        // Normalize Segments
        if note.omitSilences {
            print("\tRemove silences and voice command segments...")
        } else {
            print("\tRemove voice command segments...")
        }
        let normalizedExportSegments = Utils.cleanseSegments(
            segments: note.noteSegments,
            omitSilences: note.omitSilences,
            omitVoiceCommands: true,
            omitDeleted: true
        )
        
        // Create normalized segment index map
        var normalizedSegmentIndexMap: [String: Int] = [:]
        for segment in normalizedExportSegments {
            normalizedSegmentIndexMap[segment.getUID()] = segment.getIndex()
        }
        
        // Normalize Transformations
        var normalizedTransformations = [NoteTransformation]()
        if note.transformations.count > 0 {
            if note.omitSilences {
                print("\tRecompute transformation without silences and voice command segments")
            } else {
                print("\tRecompute transformation without voice command segments...")
            }

            normalizedTransformations = Utils.cleanseTransformations(
                transformations: note.transformations,
                segments: normalizedExportSegments,
                segmentIndexMap: normalizedSegmentIndexMap,
                omitSilences: note.omitSilences,
                omitVoiceCommands: true,
                omitDeleted: true
            )
        }
        
        print("\tGenerate mutable composition for exporting...")
        let mutableComposition = AVMutableComposition()
        mutableComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
        do {
            try mutableComposition.tracks[0].validateSegments(normalizedExportSegments)
            mutableComposition.tracks[0].segments = normalizedExportSegments
            
            // Apply transformations
            if normalizedTransformations.count > 0 {
                print("\tApply transformations to composition...")
            }
            for transformation in normalizedTransformations {
                // we can keep moving in until we catch a non silence
                let lowerSegment = normalizedExportSegments[transformation.noteRange.lowerBound]
                let upperSegment = normalizedExportSegments[transformation.noteRange.upperBound]
                // playback rate
                if transformation.type == .playbackRate {
                    let timeRange = CMTimeRangeFromTimeToTime(
                        start: lowerSegment.timeMapping.target.start,
                        end: upperSegment.timeMapping.target.end
                    )
                    let duration = CMTimeMake(
                        value: Int64(Note.defaultSegmentTimescale * (timeRange.duration.seconds * Double( 1 / transformation.value!))),
                        timescale: Int32(Note.defaultSegmentTimescale)
                    )
                    print("\tTransformation (\n\ttype: playbackRate \n\tuids: \(transformation.uids) \n\ttext: \(transformation.text) \n\tvalue: \(transformation.value!) \n\ttextRange: \(transformation.textRange) \n\tnoteRange: \(transformation.noteRange) \n\ttimeRange: \(timeRange) \n\tduration: \(duration)\n)")
                    mutableComposition.scaleTimeRange(timeRange, toDuration: duration)
                }
            }
        } catch {
            fatalError("===== There was a problem validating normalized export segments =====")
        }

        guard let exporter = AVAssetExportSession(asset: mutableComposition, presetName: AVAssetExportPresetAppleM4A) else {
            fatalError("\t[Error] There was an problem instantiating exporter")
        }
        
        if !exporter.supportedFileTypes.contains(.m4a) {
            print()
            fatalError("\t[Error] Expected export file type not compatible with exporter")
        }

        let url = Utils.getFileURL(of: "\(filename).m4a")
        exporter.outputURL = url
        exporter.outputFileType = .m4a
        exporter.timeRange = timeRange
        exporter.shouldOptimizeForNetworkUse = true

        // Export audio
        exporter.exportAsynchronously() {
            DispatchQueue.global(qos: .userInitiated).async {
                if exporter.status == AVAssetExportSession.Status.completed {
                    print("===== Note successfully exported: \(filename).m4a =====")
                    onFinishHandler?()
                } else {
                    print("===== [Error] Unable to export note =====")
                    if let error = exporter.error {
                        print("\tMessage: \(error.localizedDescription)")
                    }
                    fatalError()
                }
            }
        }
    }
    
    public static func runPlayer(
        note: Note,
        startTime: CMTime,
        volume: Float,
        onStartHandler: (() -> Void)? = nil
    ) -> AVPlayer? {
        print("===== Run Player =====")
        if note.player.currentItem == nil, let snapshot = note.copy() as? AVAsset {
            print("\tInitiating AVPlayer...")
            let assetKeys = [
                   "playable",
                   "duration",
                   "hasProtectedContent"
               ]
            let playerItem = AVPlayerItem(asset: snapshot, automaticallyLoadedAssetKeys: assetKeys)

            playerItem.addObserver(
                note,
                forKeyPath: #keyPath(AVPlayerItem.status),
                options: [.old, .new],
                context: nil
            )
            
            let player = AVPlayer(playerItem: playerItem)

            // Set Volume
            Utils.setPlayerVolume(player: player, volume: volume)

            return player
        } else if note.player.status != .readyToPlay {
            // just wait for item to be ready
            print("\tWaiting for AVPlayerItem to be ready...\n")
        } else if note.player.currentItem != nil {
            print("\tImmediately Playing Item\n")
            let timeScale = CMTimeScale(NSEC_PER_SEC)
            let time = CMTime(seconds: 1, preferredTimescale: timeScale)

            note.timerObserverToken = note.player.addPeriodicTimeObserver(forInterval: time, queue: .main) {time in
                note.handlePeriodicTimeObserver()
            }
            
            if !selectionCursor.isLoopingSelection {
                // if we have a selection, animating through each word removes it
                var boundaryTimes = [NSValue]()
                for segment in note.noteSegments {
                    boundaryTimes.append(NSValue(time: segment.timeMapping.target.start))
                }

                note.boundaryObserverToken = note.player.addBoundaryTimeObserver(forTimes: boundaryTimes, queue: .main) {
                    note.handleBoundaryTimeObserver()
                }
            }
            
            note.completionObserverToken = note.player.addBoundaryTimeObserver(forTimes: [NSValue(time: note.stopPlaybackAt!)], queue: .main) {
                note.handleCompletionObserver()
            }
            
            if startTime == note.startTime {
                print("\tPlaying from start of recording: \(note.startTime.seconds)")
                // Check to see if there is a silence at the start we need to skip
                note.handleBoundaryTimeObserver(start: true)
            } else {
                print("\tPlaying from \(startTime.seconds) seconds ...")
                note.player.seek(to: startTime)
            }
            
            note.player.play()
            
            let firstPlayableSegment = note.getSegment(
                forTrackTime: CMTimeMake(
                    value: Int64(Note.defaultSegmentTimescale * (startTime.seconds + Utils.TEMPORAL_DELTA)),
                    timescale: Int32(Note.defaultSegmentTimescale)
                )
            )
            let rate = firstPlayableSegment?.getRate() ?? note.vc!.playbackRate
            let rateWasSet = Utils.setPlayerRate(player: note.player, rate: rate)
            if rateWasSet {
                print("\tPlayer rate was successfully set: ", rate)
            } else {
                print("\t[Error] There was a problem setting player rate. Player had not been started yet.")
            }

            onStartHandler?()
            
            return note.player
        }
        
        return nil
    }
    
    public static func setPlayerRate(player: AVPlayer, rate: Float) -> Bool {
        print("===== Set Player Rate =====")

        // Player must be playing to set rate
        // Reference: https://stackoverflow.com/questions/36378642/avplayeritems-canplayslowforward-property-never-called
        if !player.isPlaying {
            return false
        }
        
        // Set Rate
        if rate > 1.0 {
            // Play fast forward
            print("\tWill play note in fast forward at rate: \(rate)")
            player.rate = rate
        } else if rate > 0.0 && rate < 1.0 {
            // Play slow forward
            print("\tWill play note in slow forward at rate: \(rate)")
            player.rate = rate
        } else if rate < 0.0 && rate > -1.0 {
            // Play slow reverse
            print("\tWill play note in slow reverse at rate: \(rate)")
            player.rate = rate
        } else if rate < -1.0 {
            // Play fast reverse
            print("\tWill play note in fast reverse at rate: \(rate)")
            player.rate = rate
        } else {
            // Play as normal if rate = 1.0
            // Stop if rate = 0.0
            print("\tWill play note at rate: \(rate)")
            player.rate = rate
        }
        
        return true
    }
    
    public static func setPlayerVolume(player: AVPlayer, volume: Float) {
        // print("===== Set Player Volume =====")
        
        // Set volume
        // print("\tWill play note at volume: \(volume)")
        player.volume = volume
    }
    
    public static func runSpeechSynthesizer(item: SynthesizerItem) {
        print("===== Play Speech Synthesizer =====")

        let utterance = AVSpeechUtterance(string: item.text)
        utterance.rate = item.rate
        utterance.volume = item.volume

        if let voice = item.voice {
            utterance.voice = voice
            item.synthesizer.speak(utterance)
        } else {
            item.synthesizer.speak(utterance)
        }
    }
    
    public static func runError(note: Note, handler: (() -> Void)?) {
        if !AVAudioSession.isHeadphonesConnected {
            note.stopListeningForVoiceCommands(pause: true) {
                handler?()
            }
        } else {
            handler?()
        }
    }
    
    public static func executeFeedback(visualMessage: String? = nil, audioMessage: String? = nil, note: Note, discardPrior: Bool = false) {
        // Give visual feedback
        if let visualMessage = visualMessage {
            note.vc!.scheduleNotification(
                text: visualMessage,
                duration: 3
            )
            note.vc!.exhaustNotificationQueue()
        }
        
        // Give audio feedback
        if AVAudioSession.isHeadphonesConnected, let audioMessage = audioMessage {
            // we don't run when !AVAudioSession.isHeadphonesConnected
            // because we will will catch the words and process them
            let voice = Utils.getSynthesizerVoice(withGender: .female, vc: note.vc)

            let synthesizerItem = SynthesizerItem(
                synthesizer: note.vc!.speechSynthesizer,
                text: audioMessage,
                voice: voice,
                rate: note.vc!.echoRate,
                volume: note.vc!.playbackVolume
            )

            if discardPrior {
                note.vc!.emptySynthesizerQueue()
            }

            note.vc!.synthesizerQueue.enqueue(synthesizerItem)
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                note.vc!.exhaustSynthesizerQueue()
            }
        }
    }
    
    public static func setMainVolume(to volume: Float, note: Note) {
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Set Playback Volume",
            audioMessage: "set volume to \(volume)",
            note: note
        )

        MPVolumeView.setVolume(volume)
        print("volume: ", AVAudioSession.sharedInstance().outputVolume, volume)
    }
    
    // Use only if you don't have access to a Pitch object that has approximate frequency
    public static func pitchToFrequency(pitch: String) -> Double {
        let musicLetters: Set = ["A", "B", "C", "D", "E", "F", "G"]

        // remove sharp
        var naturalizedPitch = pitch
        if naturalizedPitch.count > 2 {
            naturalizedPitch = pitch.replacingOccurrences(of: "#", with: "").capitalized
        }
        
        if !musicLetters.contains(naturalizedPitch[0]) {
            print("pitch is not musical letter: ", naturalizedPitch[0])
            return Utils.UNKNOWN
        }
        
        if Int(naturalizedPitch[1])! < 0 || Int(naturalizedPitch[1])! > 8 {
            print("pitch is not regular octave: ", naturalizedPitch[1])
            return Utils.UNKNOWN
        }

        return pitchToFrequencyMap[naturalizedPitch] ?? Utils.UNKNOWN
    }
    
    public static func frequencyToPitch(frequency: Double) -> String {
        var pitch: String
        switch (frequency) {
        case 0...pitchToFrequencyMap["D0"]! - 1:
            pitch = "C0"
        case pitchToFrequencyMap["D0"]!...pitchToFrequencyMap["E0"]! - 1:
            pitch = "D0"
        case pitchToFrequencyMap["E0"]!...pitchToFrequencyMap["F0"]! - 1:
            pitch = "E0"
        case pitchToFrequencyMap["F0"]!...pitchToFrequencyMap["G0"]! - 1:
            pitch = "F0"
        case pitchToFrequencyMap["G0"]!...pitchToFrequencyMap["A1"]! - 1:
            pitch = "G0"
        case pitchToFrequencyMap["A1"]!...pitchToFrequencyMap["B1"]! - 1:
            pitch = "A1"
        case pitchToFrequencyMap["B1"]!...pitchToFrequencyMap["C1"]! - 1:
            pitch = "B1"
        case pitchToFrequencyMap["C1"]!...pitchToFrequencyMap["D1"]! - 1:
            pitch = "C1"
        case pitchToFrequencyMap["D1"]!...pitchToFrequencyMap["E1"]! - 1:
            pitch = "D1"
        case pitchToFrequencyMap["E1"]!...pitchToFrequencyMap["F1"]! - 1:
            pitch = "E1"
        case pitchToFrequencyMap["F1"]!...pitchToFrequencyMap["G1"]! - 1:
            pitch = "F1"
        case pitchToFrequencyMap["G1"]!...pitchToFrequencyMap["A2"]! - 1:
            pitch = "G1"
        case pitchToFrequencyMap["A2"]!...pitchToFrequencyMap["B2"]! - 1:
            pitch = "A2"
        case pitchToFrequencyMap["B2"]!...pitchToFrequencyMap["C2"]! - 1:
            pitch = "B2"
        case pitchToFrequencyMap["C2"]!...pitchToFrequencyMap["D2"]! - 1:
            return "C2"
        case pitchToFrequencyMap["D2"]!...pitchToFrequencyMap["E2"]! - 1:
            pitch = "D2"
        case pitchToFrequencyMap["E2"]!...pitchToFrequencyMap["F2"]! - 1:
            pitch = "E2"
        case pitchToFrequencyMap["F2"]!...pitchToFrequencyMap["G2"]! - 1:
            pitch = "F2"
        case pitchToFrequencyMap["G2"]!...pitchToFrequencyMap["A3"]! - 1:
            pitch = "G2"
        case pitchToFrequencyMap["A3"]!...pitchToFrequencyMap["B3"]! - 1:
            pitch = "A3"
        case pitchToFrequencyMap["B3"]!...pitchToFrequencyMap["C3"]! - 1:
            pitch = "B3"
        case pitchToFrequencyMap["C3"]!...pitchToFrequencyMap["D3"]! - 1:
            pitch = "C3"
        case pitchToFrequencyMap["D3"]!...pitchToFrequencyMap["E3"]! - 1:
            pitch = "D3"
        case pitchToFrequencyMap["E3"]!...pitchToFrequencyMap["F3"]! - 1:
            pitch = "E3"
        case pitchToFrequencyMap["F3"]!...pitchToFrequencyMap["G3"]! - 1:
            pitch = "F3"
        case pitchToFrequencyMap["G3"]!...pitchToFrequencyMap["A4"]! - 1:
            pitch = "G3"
        case pitchToFrequencyMap["A4"]!...pitchToFrequencyMap["B4"]! - 1:
            pitch = "A4"
        case pitchToFrequencyMap["B4"]!...pitchToFrequencyMap["C4"]! - 1:
            pitch = "B4"
        case pitchToFrequencyMap["C4"]!...pitchToFrequencyMap["D4"]! - 1:
            pitch = "C4"
        case pitchToFrequencyMap["D4"]!...pitchToFrequencyMap["E4"]! - 1:
            pitch = "D4"
        case pitchToFrequencyMap["E4"]!...pitchToFrequencyMap["F4"]! - 1:
            pitch = "E4"
        case pitchToFrequencyMap["F4"]!...pitchToFrequencyMap["G4"]! - 1:
            pitch = "F4"
        case pitchToFrequencyMap["G4"]!...pitchToFrequencyMap["A5"]! - 1:
            pitch = "G4"
        case pitchToFrequencyMap["A5"]!...pitchToFrequencyMap["B5"]! - 1:
            pitch = "A5"
        case pitchToFrequencyMap["B5"]!...pitchToFrequencyMap["C5"]! - 1:
            pitch = "B5"
        case pitchToFrequencyMap["C5"]!...pitchToFrequencyMap["D5"]! - 1:
            pitch = "C5"
        case pitchToFrequencyMap["D5"]!...pitchToFrequencyMap["E5"]! - 1:
            pitch = "D5"
        case pitchToFrequencyMap["E5"]!...pitchToFrequencyMap["F5"]! - 1:
            pitch = "E5"
        case pitchToFrequencyMap["F5"]!...pitchToFrequencyMap["G5"]! - 1:
            pitch = "F5"
        case pitchToFrequencyMap["G5"]!...pitchToFrequencyMap["A6"]! - 1:
            pitch = "G5"
        case pitchToFrequencyMap["A6"]!...pitchToFrequencyMap["B6"]! - 1:
            pitch = "A6"
        case pitchToFrequencyMap["B6"]!...pitchToFrequencyMap["C6"]! - 1:
            pitch = "B6"
        case pitchToFrequencyMap["C6"]!...pitchToFrequencyMap["D6"]! - 1:
            pitch = "C6"
        case pitchToFrequencyMap["D6"]!...pitchToFrequencyMap["E6"]! - 1:
            pitch = "D6"
        case pitchToFrequencyMap["E6"]!...pitchToFrequencyMap["F6"]! - 1:
            pitch = "E6"
        case pitchToFrequencyMap["F6"]!...pitchToFrequencyMap["G6"]! - 1:
            pitch = "F6"
        case pitchToFrequencyMap["G6"]!...pitchToFrequencyMap["A7"]! - 1:
            pitch = "G6"
        case pitchToFrequencyMap["A7"]!...pitchToFrequencyMap["B7"]! - 1:
            pitch = "A7"
        case pitchToFrequencyMap["B7"]!...pitchToFrequencyMap["C7"]! - 1:
            pitch = "B7"
        case pitchToFrequencyMap["C7"]!...pitchToFrequencyMap["D7"]! - 1:
            pitch = "C7"
        case pitchToFrequencyMap["D7"]!...pitchToFrequencyMap["E7"]! - 1:
            pitch = "D7"
        case pitchToFrequencyMap["E7"]!...pitchToFrequencyMap["F7"]! - 1:
            pitch = "E7"
        case pitchToFrequencyMap["F7"]!...pitchToFrequencyMap["G7"]! - 1:
            pitch = "F7"
        case pitchToFrequencyMap["G7"]!...pitchToFrequencyMap["A8"]! - 1:
            pitch = "G7"
        case pitchToFrequencyMap["A8"]!...pitchToFrequencyMap["B8"]! - 1:
            pitch = "A8"
        case pitchToFrequencyMap["B8"]!...pitchToFrequencyMap["C8"]! - 1:
            pitch = "B8"
        case pitchToFrequencyMap["C8"]!...pitchToFrequencyMap["D8"]! - 1:
            pitch = "C8"
        case pitchToFrequencyMap["D8"]!...pitchToFrequencyMap["E8"]! - 1:
            pitch = "D8"
        case pitchToFrequencyMap["E8"]!...pitchToFrequencyMap["F8"]! - 1:
            pitch = "E8"
        case pitchToFrequencyMap["F8"]!...pitchToFrequencyMap["G8"]! - 1:
            pitch = "F8"
        case pitchToFrequencyMap["G8"]!...Double.infinity:
            pitch = "G8"
        default:
            pitch =  ""
        }
        
        return pitch
    }
    
    public static func getHigherPitch(pitch: Pitch, offsets: Int) -> String {
        let letters = "ABCDEFG"
        let letter = pitch.note.letter.rawValue
        let octave = pitch.note.octave
        
        let letterStringIndex = letters.firstIndex(of: letter.first!)!
        let letterIndex = letters.distance(to: letterStringIndex)
        let newLetterIndex = (letterIndex + offsets) % letters.count
        let newOctaveNumber = octave + Int(floor(Float(letterIndex + offsets) / Float(letters.count)))
        let normalizedOctaveNumber = min(newOctaveNumber, 8)
        let newPitch: String = letters[newLetterIndex] + String(normalizedOctaveNumber)
        return newPitch
    }
    
    public static func getLowerPitch(pitch: Pitch, offsets: Int) -> Pitch {
        let letters = "ABCDEFG"
        let letter = pitch.note.letter.rawValue
        let octave = pitch.note.octave
        
        let letterStringIndex = letters.firstIndex(of: letter.first!)!
        let letterIndex = letters.distance(to: letterStringIndex)
        let newLetterIndex = (letterIndex - offsets) % letters.count
        let normalizedLetterIndex = newLetterIndex > 0 ? newLetterIndex : letters.count - newLetterIndex
        let newOctaveNumber = octave + Int(floor(Float(letterIndex - offsets) / Float(letters.count)))
        let normalizedOctaveNumber = max(newOctaveNumber, 0)
        let newPitch: String = letters[normalizedLetterIndex] + String(normalizedOctaveNumber)
        do {
            let pitch = try Pitch(frequency: pitchToFrequencyMap[newPitch]!)
            return pitch
        } catch {
            fatalError("===== [Error] There was a problem getting lower pitch =====")
        }
    }
    
    public static func normalizePitch(incidentPitch: Pitch, basePitch: Pitch) -> Double {
        var index: Double
        switch (incidentPitch.frequency) {
        case 0...pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: basePitch.note.string))]! - 1:
            index = 1
            break
        case pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: basePitch.note.string))]!...pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 1)))]! - 1:
            index = 2
            break
        case pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 1)))]!...pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 2)))]! - 1:
            index = 3
            break
        case pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 2)))]!...pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 3)))]! - 1:
            index = 4
            break
        case pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 3)))]!...pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 4)))]! - 1:
            index = 5
            break
        case pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 4)))]!...pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 5)))]! - 1:
            index = 6
            break
        case pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 5)))]!...pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 6)))]! - 1:
            index = 7
            break
        case pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 6)))]!...pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 7)))]! - 1:
            index = 8
            break
        case pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 7)))]!...pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 8)))]! - 1:
            index = 9
            break
        case pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 8)))]!...pitchToFrequencyMap[Utils.frequencyToPitch(frequency: Utils.pitchToFrequency(pitch: Utils.getHigherPitch(pitch: basePitch, offsets: 9)))]! - 1:
            index = 10
            break
        default:
            index = 10
        }

        return index / Double(10)
    }

    public static func computeSoundIntensity(buffer: AVAudioPCMBuffer) -> Double? {
        // gives you an array of pointers to each sample’s data
        guard let channelData = buffer.floatChannelData else { return nil }

        let channelDataValue = channelData.pointee
        
        // Converting from an array of UnsafeMutablePointer<Float> to an array of Float makes later calculations easier.
        let channelDataValueArray = stride(from: 0,
                                           to: Int(buffer.frameLength),
                                           by: buffer.stride).map{ channelDataValue[$0] }
        // Compute average power using root mean square
        let rmsNumerator = channelDataValueArray.map{ $0 * $0 }.reduce(0, +)
        let rms = sqrt(Double(rmsNumerator) / Double(buffer.frameLength))
        
        // Convert the RMS to decibels
        // This should be a value between -160 and 0, but if rms is negative, this value would be NaN.
        let avgPower = 20 * log10(rms)

        return avgPower
    }
    
    public static func getFileURL(of filename: String) -> URL {
        return getDocumentsDirectory().appendingPathComponent(filename)
    }
    
    // Reference: https://stackoverflow.com/questions/32657533/temporary-file-path-using-swift
    // Reference: https://medium.com/@victor.pavlychko/managing-temporary-files-in-swift-b076e1444c76
    // Reference: https://iswift.org/cookbook/get-temporary-directory-path
    // Reference: https://stackoverflow.com/questions/11897825/ios-temporary-folder-location
    //
    // Good pattern: https://stackoverflow.com/questions/50765879/swift-how-to-access-a-csv-file-in-temporary-directory-nstemporarydirectory
    // Creating TemporaryFile class: https://oleb.net/blog/2018/03/temp-file-helper/
    public static func getTempFileURL(of filename: String) -> URL {
        // return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
    
    public static func formattedTime(time: Float) -> String {
        var secs = Int(ceil(time))
        var hours = 0
        var mins = 0

        if secs > TimeConstant.secsPerHour {
            hours = secs / TimeConstant.secsPerHour
            secs -= hours * TimeConstant.secsPerHour
        }

        if secs >= TimeConstant.secsPerMin {
            mins = secs / TimeConstant.secsPerMin
            secs -= mins * TimeConstant.secsPerMin
        }

        var formattedString = ""
        if hours > 0 {
            formattedString = "\(String(format: "%02d", hours)):"
        }
        formattedString += "\(String(format: "%02d", mins)):\(String(format: "%02d", secs))"
        return formattedString
    }
    
    public static func getDateString(date: TimeInterval) -> String? {
        guard date > 0 else {
            return nil
        }
        // Prepare date formatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter.string(from: Date(timeIntervalSince1970: date))
    }
    
    public static func getSynthesizerVoice(withGender gender: Gender? = nil, vc: UIViewController? = nil) -> AVSpeechSynthesisVoice? {
        var synthesizerVoice: AVSpeechSynthesisVoice?
        voicesLoop: for voice in AVSpeechSynthesisVoice.speechVoices() {
            if (Locale.current.regionCode == "AU") && (gender == .male || gender == nil) && (voice.name == "Lee (Enhanced)" && voice.quality == .enhanced) {
                // AU
                // Male = Lee
                synthesizerVoice = voice
                break
            } else if (Locale.current.regionCode == "AU") && (gender == .female || gender == nil) && (voice.name == "Karen (Enhanced)" && voice.quality == .enhanced) {
                // AU
                // Female = Karen
                synthesizerVoice = voice
                break
            } else if (Locale.current.regionCode == "UK") && (gender == .male || gender == nil) && (voice.name == "Oliver (Enhanced)" && voice.quality == .enhanced) {
                // UK
                // Male = Oliver
                synthesizerVoice = voice
                break
            } else if (Locale.current.regionCode == "UK") && (gender == .female || gender == nil) && (voice.name == "Kate (Enhanced)" && voice.quality == .enhanced) {
                // UK
                // Female = Kate
                synthesizerVoice = voice
                break
            } else if voice.name == "Tom (Enhanced)" && (gender == .male || gender == nil) && voice.quality == .enhanced {
                // US
                // Male = Tom
                synthesizerVoice = voice
                break
            } else if voice.name == "Ava (Enhanced)" && (gender == .female || gender == nil) && voice.quality == .enhanced {
                // US
                // Female = Ava
                synthesizerVoice = voice
                break
            }
        }
        
        if let synthesizerVoice = synthesizerVoice {
            return synthesizerVoice
        } else if let vc = vc {
            var voiceName = "Tom"
            voicesLoop: for voice in AVSpeechSynthesisVoice.speechVoices() {
                if (Locale.current.regionCode == "AU") && (gender == .male || gender == nil) && (voice.name == "Lee (Enhanced)" && voice.quality == .enhanced) {
                    // AU
                    // Male = Lee
                    voiceName = "Lee"
                } else if (Locale.current.regionCode == "AU") && (gender == .female || gender == nil) && (voice.name == "Karen (Enhanced)" && voice.quality == .enhanced) {
                    // AU
                    // Female = Karen
                    voiceName = "Karen"
                } else if (Locale.current.regionCode == "UK") && (gender == .male || gender == nil) && (voice.name == "Oliver (Enhanced)" && voice.quality == .enhanced) {
                    // UK
                    // Male = Oliver
                    voiceName = "Oliver"
                } else if (Locale.current.regionCode == "UK") && (gender == .female || gender == nil) && (voice.name == "Kate (Enhanced)" && voice.quality == .enhanced) {
                    // UK
                    // Female = Kate
                    voiceName = "Kate"
                } else if voice.name == "Tom (Enhanced)" && (gender == .male || gender == nil) && voice.quality == .enhanced {
                    // US
                    // Male = Tom
                    voiceName = "Tom"
                } else if voice.name == "Allison (Enhanced)" && (gender == .female || gender == nil) && voice.quality == .enhanced {
                    // US
                    // Female = Allison
                    voiceName = "Allison"
                }
            }
            let alertController = UIAlertController(title: "Better Echo Voices Available", message: "Please install \(voiceName) (Enhanced) voice to allow for enhanced dictation. Go to Accessibility > Spoken Content> Voices and select \(voiceName) (Enhanced)", preferredStyle: .alert)
            let voicesURL = "App-prefs:ACCESSIBILITY"
            // let appURL = UIApplication.openSettingsURLString
            let settingsAction = UIAlertAction(title: "Settings", style: .default) { (_) -> Void in
                guard let settingsUrl = URL(string: voicesURL) else { return }

                if UIApplication.shared.canOpenURL(settingsUrl) {
                    if #available(iOS 10.0, *) {
                        UIApplication.shared.open(settingsUrl, options: [UIApplication.OpenExternalURLOptionsKey.universalLinksOnly : false], completionHandler: { (success) in
                            print("Settings opened: \(success)") // Prints true
                        })
                    } else {
                        // Fallback on earlier versions
                    }
                }
            }
            alertController.addAction(settingsAction)
            let cancelAction = UIAlertAction(title: "Cancel", style: .default, handler: nil)
            alertController.addAction(cancelAction)

            DispatchQueue.main.async {
                vc.present(alertController, animated: true, completion: nil)
            }
        }
        
        return synthesizerVoice
    }
    
    // Reference: https://www.quora.com/Natural-Language-Processing-Whats-the-best-way-to-detect-if-a-piece-of-text-is-interrogative
    // Helping Verbs 1: https://www.grammar-monster.com/glossary/helping_verb.htm#:~:text=A%20helping%20verb%20(also%20known,%2C%20had%2C%20having%2C%20will%20have
    // Helping Verbs 2: https://grammar.yourdictionary.com/parts-of-speech/verbs/helping-verbs.html
    // Reference: https://stackoverflow.com/questions/3573872/how-to-find-out-if-a-sentence-is-a-question-interrogative
    // Reference: https://stackoverflow.com/questions/4083060/determine-if-a-sentence-is-an-inquiry
    // Paper: https://pdfs.semanticscholar.org/72ea/54243949e475bc4e656cd517dbe51f487bc3.pdf
    // Paper: https://www.aclweb.org/anthology/C10-1130.pdf
    public static func isQuestion(sentence: String) -> Bool {
        if sentence.count == 0 {
            return false
        }
        
        let elements: [String] = ["?"]
        let starters: [String] = ["which", "won't", "can't", "isn't", "aren't", "is", "do", "does", "will", "can", "is", "did", "has", "had", "are", "were", "can", "could", "may", "might", "would", "shall", "should", "must", "am", "was", "have", "who", "what", "when", "where", "why", "how"]
        let temp = sentence.lowercased()

        let splitted: [String] = temp.components(separatedBy: " ")

        if starters.contains(String(splitted[0])) {
            return true;
        } else {
            return splitted.contains(anyOf: elements)
        }
    }
    
    public static func isFirstPersonSingularPronoun(_ str: String) -> Bool {
        return (str.count == 1 && str.contains("I")) || str.contains("I'")
    }

    // Scale the decibels into a value suitable for your vuMeter.
    public static func normalizedPower(power: Double, minPower: Float) -> Double {
        guard power.isFinite else { return 0.0 }
        
        if power < Double(minPower) {
            return 0.0
        } else if power >= 1.0 {
            return 1.0
        } else {
            return (abs(Double(minPower)) - abs(power)) / abs(Double(minPower))
        }
    }
    
    // normalizes by changing target times not source times
    public static func cleanseSegments(
        segments: [NoteSegment],
        omitSilences: Bool,
        omitVoiceCommands: Bool,
        omitDeleted: Bool
    ) -> [NoteSegment] {
        print("===== Cleanse Segments =====")
        var cleansedSegments = [NoteSegment]()
        
        if omitSilences {
            print("\tFilter out silences...")
        }
        if omitVoiceCommands {
            print("\tFilter out voice command words...")
        }

        for segment in segments {
            // Filter out silences
            if omitSilences && segment.isSilence() && segment.timeMapping.target.duration.seconds > Utils.SILENCE_SKIP_THRESHOLD {
                continue
            }
            
            // Filter out voice command segments
            if omitVoiceCommands && segment.isVoiceCommandWord() {
                continue
            }
            
            if omitDeleted && segment.isDeleted() {
                continue
            }
            
            // add segment to array
            let duplicateSegment = segment.duplicate()
            cleansedSegments.append(duplicateSegment)
        }
        
        // normalize segments array
        print("\tShift segments to close up gaps in time caused by removes segments...")
        var lastEnd = CMTime.zero
        var normalizedCleansedSegments = [NoteSegment]()
        var silenceIndices = [Int]()
        for (index, segment) in cleansedSegments.enumerated() {
            if segment.timeMapping.target.start.seconds > lastEnd.seconds {
                let shiftedSegment = NoteSegment(
                    note: segment.note,
                    word: segment.getText(),
                    trackURL: segment.sourceURL!,
                    trackID: segment.sourceTrackID,
                    phoneticallySimilarWords: segment.getPhoneticallySimilarWords(),
                    sourceTimeRange: segment.timeMapping.source,
                    targetTimeRange: CMTimeRangeMake(
                        start: lastEnd,
                        duration: segment.timeMapping.target.duration
                    ),
                    tokenType: segment.getTokenType(),
                    lexicalClass: segment.getLexicalClass(),
                    nameType: segment.getNameType(),
                    lemma: segment.getLemma(),
                    sentimentScore: segment.getSentiment(),
                    voiceCommandWord: segment.isVoiceCommandWord(), // should be false if we've removed all voice commands
                    deleted: segment.isDeleted()
                )

                // Sound Intensity
                if segment.getPower() != Double.infinity {
                    // Import sound intensity
                    let power = segment.getPower()
                    shiftedSegment.setPower(power: power)
                }
                
                // Pitch
                if let pitch = segment.getPitch() {
                    // Import pitch
                    shiftedSegment.setPitch(pitch: pitch)
                }
                
                // Rate
                shiftedSegment.setRate(rate: segment.getRate())
                
                // Date Created and Modified
                shiftedSegment.dateCreated = segment.dateCreated
                shiftedSegment.dateModified = segment.dateModified
                
                // UID
                shiftedSegment.setUID(uid: segment.getUID())

                // Add to segments array
                normalizedCleansedSegments.append(shiftedSegment)
                
                // Save silence index
                if (!omitSilences && !shiftedSegment.isDeleted() && shiftedSegment.isSilence()) || (omitSilences && !shiftedSegment.isDeleted() && shiftedSegment.isSilence() && shiftedSegment.timeMapping.target.duration.seconds <= Utils.SILENCE_SKIP_THRESHOLD) {
                    silenceIndices.append(index)
                }
                
                // Update last end value
                lastEnd = CMTimeAdd(lastEnd, segment.timeMapping.target.duration)
            } else {
                // Save silence index
                if (!omitSilences && !segment.isDeleted() && segment.isSilence()) || (omitSilences && !segment.isDeleted() && segment.isSilence() && segment.timeMapping.target.duration.seconds <= Utils.SILENCE_SKIP_THRESHOLD) {
                    silenceIndices.append(index)
                }

                // Add to segments array
                normalizedCleansedSegments.append(segment)
                
                // Update last end value
                lastEnd = segment.timeMapping.target.end
            }
        }
        
        var avgPauseDuration: Double?
        if silenceIndices.count > 0 {
            avgPauseDuration = silenceIndices.reduce(0, { result, i in
                return result + normalizedCleansedSegments[i].timeMapping.target.duration.seconds
            }) / Double(silenceIndices.count)
            avgPauseDuration = avgPauseDuration!.rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)
        }
        
        var speakingRate: Double?
        if normalizedCleansedSegments.count > 0 {
            speakingRate = normalizedCleansedSegments.reduce(0, { result, item in
                if !item.isPunctuation() && !item.isSilence() && !item.isVoiceCommandWord() && !item.isDeleted() {
                    return result + 1
                }
                
                return result
            }) / Double(normalizedCleansedSegments.first!.getNote()!.getDuration(filteredDuration: true).seconds / Double(TimeConstant.secsPerMin))
            speakingRate = speakingRate!.rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)
        }
        
        // Update Index, Background Noise, AvgPauseDuration, SpeakingRate
        var fullyNormalizedCleansedSegments = [NoteSegment]()
        for (index, segment) in normalizedCleansedSegments.enumerated() {
            // Set segment index
            segment.setIndex(index: index)
            
            // Set backgroundNoise
            segment.setBackgroundNoise(noise: normalizedCleansedSegments.first!.getNote()!.getBackgroundNoise())

            // Set avgPauseDuration
            if let avgPauseDuration = avgPauseDuration {
                segment.setAvgPauseDuration(duration: avgPauseDuration)
            }
            
            // Set speakingRate
            if let speakingRate = speakingRate {
                segment.setSpeakingRate(rate: speakingRate)
            }
            
            fullyNormalizedCleansedSegments.append(segment)
        }
        
        return fullyNormalizedCleansedSegments
    }
    
    public static func cleanseTransformations(
        transformations: [NoteTransformation],
        segments: [NoteSegment],
        segmentIndexMap: [String: Int],
        omitSilences: Bool,
        omitVoiceCommands: Bool,
        omitDeleted: Bool
    ) -> [NoteTransformation] {
        print("===== Cleanse Transformations =====")

        var cleansedTransformations = [NoteTransformation]()
        for transformation in transformations {
            print("\tTransformation -------")
            print(transformation)
            
            // skip if segments have been removed
            print("\tCheck to see if transformation should still exist...")
            var allSegmentsRemoved = true
            for segmentUID in transformation.uids.keys {
                allSegmentsRemoved = allSegmentsRemoved && !(segmentIndexMap[segmentUID] != nil)
                if !allSegmentsRemoved {
                    // We found one cunter-example where we found a transformation segment in the segment-index map
                    // no need to check the others
                    break
                }
            }
            
            if allSegmentsRemoved {
                // Has the effect of removing transformation
                print("\tAll transformation segments have been removed. Discarding transformation...")
                continue
            } else {
                print("\tSegments argument includes segments in original transformation. Transformation should exist. Continue cleansing...")
            }
            
            // check for deleted transformation segments
            // remove silences if instructed to by method argument
            // remove voice commands if instructed to by method argument
            print("\tChecking for deleted transformation segments...")
            if omitSilences {
                print("\tRemoving silences...")
            }
            if omitVoiceCommands {
                print("\tRemove voice command segments...")
            }
            var transformationUIDs: [String:Int] = [:]
            for segmentUID in transformation.uids.keys {
                if let segmentIndex = segmentIndexMap[segmentUID],
                    ((omitSilences && !segments[segmentIndex].isSilence()) || (omitSilences && segments[segmentIndex].isSilence() && segments[segmentIndex].timeMapping.target.duration.seconds <= Utils.SILENCE_SKIP_THRESHOLD) || !omitSilences && segments[segmentIndex].isSilence()) &&
                    ((omitVoiceCommands && !segments[segmentIndex].isVoiceCommandWord()) || !omitVoiceCommands && segments[segmentIndex].isVoiceCommandWord()) &&
                    ((omitDeleted && !segments[segmentIndex].isDeleted()) || !omitDeleted && segments[segmentIndex].isDeleted()) {
                    transformationUIDs[segmentUID] = segmentIndex
                }
            }

            let sortedUIDIndexPairs = transformationUIDs.sorted { $0.1 < $1.1 }
            print("\tExisting transformation segments: ", sortedUIDIndexPairs)
            
            // Determine transformation ranges
            print("\tDetermine and factor in transformation slicing or shifting due to addition or removal of segments...")
            
            var startIndex: Int?
            var lastIndex: Int?
            var transformationRanges = [ClosedRange<Int>]()
            print("\tLocating first transformation range...")
            for uidIndexPair in sortedUIDIndexPairs {
                if startIndex == nil {
                    // first segment
                    startIndex = uidIndexPair.value
                    lastIndex = uidIndexPair.value
                    print("\tNew transformation range lower bound index: ", startIndex!)
                } else if startIndex != nil && lastIndex != nil && uidIndexPair.value > lastIndex! + 1 {
                    // create transformation range
                    transformationRanges.append(startIndex!...lastIndex!)
                    print("\tNew transformation range: ", startIndex!...lastIndex!)
                    
                    // reinitialize start index
                    startIndex = uidIndexPair.value
                    lastIndex = uidIndexPair.value
                    print("\tNew transformation range lower bound index: ", startIndex!)
                } else {
                    // increment last index
                    lastIndex = uidIndexPair.value
                }
            }
            
            // create last segment
            if startIndex != nil && lastIndex != nil {
                // create transformation range
                transformationRanges.append(startIndex!...lastIndex!)
                print("\tNew transformation range: ", startIndex!...lastIndex!)
            }
            
            for range in transformationRanges {
                print("\tCreate new cleansed transformation...")
                let lowerSegment = segments[range.lowerBound]
                let upperSegment = segments[range.upperBound]

                // Compute text
                let text = lowerSegment.note!.getText(
                    from: lowerSegment.timeMapping.target.start,
                    until: upperSegment.timeMapping.target.end,
                    segments: segments
                )
                print("\tCompute cleansed transformation text: ", text)

                // Compute value
                let value = transformation.value
                if let value = value {
                    print("\tCompute cleansed transformation value: ", value)
                }
                
                // Compute text range
                let lowerRange = lowerSegment.note!.getSegmentTextRange(of: lowerSegment)
                let upperRange = upperSegment.note!.getSegmentTextRange(of: upperSegment)
                let lowerLocation = lowerRange!.location
                let upperLocation = upperRange!.location
                let upperLength = upperRange!.length
                let textRange = NSRange(location: lowerLocation, length: (upperLocation - lowerLocation) + upperLength)
                print("\tCompute cleansed transformation textRange: ", textRange)
                
                // Compute range
                let noteRange = range
                print("\tCompute cleansed transformation noteRange: ", noteRange)
                
                // Collect segment uids
                var uids: [String: Int] = [:]
                for segment in segments[noteRange] {
                    uids[segment.getUID()] = segment.getIndex()
                }
                print("\tCompute cleansed transformation segmentIndexMap: ", uids)
                
                let cleansedTransformation = NoteTransformation(
                    type: transformation.type,
                    uids: uids,
                    text: text,
                    value: value,
                    textRange: textRange,
                    noteRange: noteRange
                )
                print("\tInstantiate cleansed transformation: ", cleansedTransformation)
                
                cleansedTransformations.append(cleansedTransformation)
                print("Add cleansed transformation to array...")
            }
        }
        
        return cleansedTransformations
    }
    
    public static func initializeCursor(textView: UITextView, cursorView: UIView, font: UIFont) {
        // compute x and y positions
        let textContainerPadding = textView.textContainer.lineFragmentPadding
        let xPos = textView.frame.minX + textContainerPadding
        let yPos = textView.frame.minY + textContainerPadding + ((font.lineHeight - font.pointSize) / 2)
        let width = Utils.CURSOR_WIDTH

        // Create a CGRect object which is used to render a rectangle.
        let frame: CGRect = CGRect(
            x: xPos,
            y: yPos,
            width: CGFloat(width),
            height: CGFloat(font.lineHeight)
        )
        
        cursorView.frame = frame
    }
    
    // MARK: - Helper Functions
    
    private static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
}
