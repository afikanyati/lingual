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
    /// Stores the timescale used to scale the values specified for CMTime objects
    static let DEFAULT_FONT_SIZE: CGFloat = 18.0
    static let DEFAULT_PLAYBACK_RATE: Float = 1
    static let DEFAULT_ECHO_RATE: Float = 0.53
    static let DEFAULT_SEGMENT_TIMESCALE = Double(10000)
    static let DEFAULT_WITH_ON_DEVICE_RECOGNITION = true
    static let DEFAULT_WITH_TEMPORAL_SUGGESTIONS = false
    static let DEFAULT_WITH_PUNCTUATION_SUGGESTIONS = true
    static let DEFAULT_WITH_FORMATTING_SUGGESTIONS = true
    static let DEFAULT_WITH_TEXT_STRICTLY_AS_WORDS = false
    static let DEFAULT_WITH_CAPITALIZATION = true
    static let DEFAULT_WITH_SKIP_PUNCTUATION = true
    static let DEFAULT_WITH_OMIT_SILENCES = true
    static let DEFAULT_WITH_PASSIVE_ECHO = true
    static let MALE_LOWEST_VOICED_SPEECH_FREQUENCY: Double = 82
    static let FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY: Double = 1047
    static let UNKNOWN: Double = -1
    static let SILENCE_SKIP_THRESHOLD = 0.1
    static let CURSOR_WIDTH = 2
    static let CURSOR_TRANSITION_DURATION: TimeInterval = 0.15
    static let TEXT_VIEW_SCROLL_TRANSITION_DURATION: TimeInterval = 0.3
    static let EMPTY_NSRANGE = NSRange(location: 0, length: 0)
    static var TALKING_POWER_DELTA: Double {
        if AVAudioSession.isHeadphonesConnected {
            // With headphones, in a relatively empty, small room, near the window, using AirPods Pro mic
            // the background noise read an average of -75dB
            // when talking, the avg. power was -33dB
            // ∆ = 42dB
            // We use 30dB to give some wiggle room
            return 40
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
    static var WALKING_PERIOD_DURATION: TimeInterval = 3
    static var WALKING_ECHO_DELAY_DURATION: TimeInterval = 1
    static var WALKING_LOOP_BUFFER: TimeInterval = 0.5
    static var WALKING_START_DELAY_DURATION: TimeInterval = 0.5
    static let DEFAULT_FIG_COUNT = 2
    static let TEMPORAL_DELTA = 0.01
    static let DEFAULT_SEGMENT_DURATION: Double = 100000 // Must be high enough such that no user will record a entry of this duration
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
    static var LINGUAL_PURPLE: String = "#7771C2FF"
    static var LINGUAL_RED: String = "#D31900FF"
    static var LINGUAL_ORANGE: String = "#D87736FF"
    static var LINGUAL_DARK_PURPLE: String = "#252533FF"
    static var LINGUAL_GRAY: String = "#A6A9BFFF"
    static var LINGUAL_WHITE: String = "#CACFE5FF"
    static var SCROLL_VIEW_HEIGHT: CGFloat = 60
    static var LISTENING_LAUNCH_DELAY: TimeInterval = 2
    static var SOUND_INTENSITY_LATENCY: Int = 10
    static var PLAYER_END_PLAYBACK_BUFFER: Double = 0.05 // We want to put it just before end. makes sure we don't seek to the exact end which causes the completion observer not to run
    static var MINIMUM_REST_BETWEEN_VOICE_COMMANDS: TimeInterval = 1 // Determined experimentally
    static var TEXT_VIEW_PADDING_TOP: CGFloat = 15
    static var TEXT_VIEW_PADDING_BOTTOM: CGFloat = 160
    static var TEXT_VIEW_PADDING_LEFT: CGFloat = 10
    static var TEXT_VIEW_PADDING_RIGHT: CGFloat = 10
    static var ENTRY_ITEM_PREVIEW_CHAR_COUNT = 50
    static let MIN_SEED_INTENSITY_POINTS = 15
    /// Stores the current playback volume of entry playback
    static var playbackVolume: Float {
        return AVAudioSession.sharedInstance().outputVolume
    }
    static let CURSOR_X_POS_BUFFER = CGFloat(4)
    static let NAVBAR_BUTTON_LENGTH: CGFloat = 30.0
    /// Stores a reference to the minimum power value accepted for sound intensity datum
    static let DEFAULT_MIN_POWER: Float = -160.0
    static let DEFAULT_NOTIFICATION_DELAY: TimeInterval = 0.7
    static let DEFAULT_START_LISTENING_DELAY: TimeInterval = 2
    static let COMMA_PAUSE_DURATION: Double = 2
    static let NEW_SENTENCE_PAUSE_DURATION: Double = 4
    static let NEW_PARAGRAPH_PAUSE_DURATION: Double = 7
    static let DEFAULT_RESET_LISTENING_FLAG_DELAY: TimeInterval = 5 // Final Transcript should show up in five seconds without any sound
    static let PREVIEW_ENTRY_DURATION: Double = 10
    static let CLOUD_KIT_CONTAINER_IDENTIFIER: String = "iCloud.com.afikanyati.lingual"
    static let NAVIGATION_BAR_THRESHOLD_HEIGHT: CGFloat = -20
    static let PREFERRED_INPUT_SAMPLE_RATE: Double = 48000.0
    static let PREFERRED_CONVERTED_SAMPLE_RATE: Double = 12000.0
    static let NEWLINE_CHAR = "\n\n"
    static let PLAYBACK_SCROLL_BUFFER: Int = 500
    static let TEXT_SCRUB_START_DELAY: TimeInterval = 0.2
    static let TEXT_SCRUB_PAUSE_DELAY: TimeInterval = 0.2
    static let RECORD_FILE_BUS: Int = 0
    static let SPEECH_RECOGNITION_BUS: Int = 1
    static let SEED_CONTENT_TITLE: String = "Welcome to Lingual"
    static let SEED_CONTENT_FILENAME: String = "entry-016AAC62-FEFB-4D62-96DE-854FDC07585C"
    static let PLAYBACK_SECOND_DURATION: TimeInterval = 1
    static let INDEX_SEARCH_BUFFER: Int = 7
    static let VALID_VOICE_COMMAND_DELAY: TimeInterval = 0.3 // 0.2 was too fast
    static let DEFAULT_NOTIFICATION_DURATION: TimeInterval = 3
    static let UI_DIALOG_DELAY: TimeInterval = 0.2
    
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
    
    // MARK: - General Utilities
    
    // Cannot export to outputURL's that already exist
    // Reference: https://stackoverflow.com/questions/20203548/avassetexportsession-not-exporting-time-range
    // Deleting: https://stackoverflow.com/questions/42041405/delete-a-file-using-swift-in-ios
    // Accessing Exported Entry: https://stackoverflow.com/questions/60269542/how-to-get-m4a-file-from-recorded-audio-for-api-in-swift
    public static func exportEntry(
        state: StateManager,
        entry: Entry,
        timeRange: CMTimeRange,
        onFinishHandler: ((_ entryURL: String) -> Void)? = nil
    ) {
        print("===== Utils: Export Entry =====")

        if !AVAssetExportSession.exportPresets(compatibleWith: entry).contains(AVAssetExportPresetAppleM4A) {
            fatalError("\t[Error] Expected export preset value not compatible with entry")
        }
        
        // Normalize Segments
        if state.withOmitSilences {
            print("\tRemove silences and voice command segments...")
        } else {
            print("\tRemove voice command segments...")
        }
        let normalizedExportSegments = Utils.cleanseSegments(
            segments: entry.entrySegments,
            omitSilences: state.withOmitSilences,
            omitVoiceCommands: true,
            omitDeleted: true
        )
        
        // Create normalized segment index map
        var normalizedSegmentIndexMap: [String: Int] = [:]
        for segment in normalizedExportSegments {
            normalizedSegmentIndexMap[segment.getUID()] = segment.getIndex()
        }
        
        // Normalize Transformations
        var normalizedTransformations = [EntryTransformation]()
        if entry.transformations.count > 0 {
            if state.withOmitSilences {
                print("\tRecompute transformation without silences and voice command segments")
            } else {
                print("\tRecompute transformation without voice command segments...")
            }

            print("\tNormalized before: ", entry.transformations)
            normalizedTransformations = Utils.cleanseTransformations(
                transformations: entry.transformations,
                segments: normalizedExportSegments,
                segmentIndexMap: normalizedSegmentIndexMap,
                omitSilences: state.withOmitSilences,
                omitVoiceCommands: true,
                omitDeleted: true
            )
            print("\tNormalized after: ", normalizedTransformations)
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
                let lowerSegment = normalizedExportSegments[transformation.entryRange.lowerBound]
                let upperSegment = normalizedExportSegments[transformation.entryRange.upperBound]
                // playback rate
                if transformation.type == .playbackRate {
                    let timeRange = CMTimeRangeFromTimeToTime(
                        start: lowerSegment.timeMapping.target.start,
                        end: upperSegment.timeMapping.target.end
                    )
                    let duration = CMTimeMake(
                        value: Int64(Utils.DEFAULT_SEGMENT_TIMESCALE * (timeRange.duration.seconds * Double( 1 / transformation.value!))),
                        timescale: Int32(Utils.DEFAULT_SEGMENT_TIMESCALE)
                    )
                    print("\tTransformation (\n\ttype: playbackRate \n\tuids: \(transformation.uids) \n\ttext: \(transformation.text) \n\tvalue: \(transformation.value!) \n\ttextRange: \(transformation.textRange) \n\tentryRange: \(transformation.entryRange) \n\ttimeRange: \(timeRange) \n\tduration: \(duration)\n)")
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

        let entryName = entry.getTitle(withDashes: true).string
        var number: Int = 1
        var url = Utils.getFileURL(of: "\(entryName) no. \(number).m4a")
        let fileManager = FileManager.default
        while fileManager.fileExists(atPath: url.path) {
            number += 1
            url = Utils.getFileURL(of: "\(entryName) no. \(number).m4a")
        }
        exporter.outputURL = url
        exporter.outputFileType = .m4a
        exporter.timeRange = timeRange
        exporter.shouldOptimizeForNetworkUse = true

        // Export audio
        exporter.exportAsynchronously() {
            DispatchQueue.global(qos: .userInitiated).async {
                if exporter.status == AVAssetExportSession.Status.completed {
                    print("===== Entry successfully exported: \(entry.filename).m4a =====")
                    onFinishHandler?(url.lastPathComponent)
                } else {
                    print("===== [Error] Unable to export entry =====")
                    if let error = exporter.error {
                        print("\tMessage: \(error.localizedDescription)")
                    }
                    fatalError()
                }
            }
        }
    }
    
    public static func deleteIfExistingFile(atPath path: String) -> Bool {
        do {
            let fileManager = FileManager.default
            // Check if file exists
            if fileManager.fileExists(atPath: path) {
                // Delete file
                print("\tFile exists at specified file path. Delete it...")
                try fileManager.removeItem(atPath: path)
                print("\tSuccessfully deleting existing file at file path...")
            } else {
                print("\tFile location is available to write a new file...")
            }
        } catch let error as NSError {
            print("\t[Error] There was a problem while checking for and deleting existing file")
            print("\tMessage: \(error)")
            
            return false
        }
        
        return true
    }
    
    public static func setMainVolume(to volume: Float) {
        MPVolumeView.setVolume(volume)
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
        return self.getDocumentsDirectory().appendingPathComponent(filename)
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
    
    // Reference: https://stackoverflow.com/questions/19959642/uiactivityviewcontroller-with-alternate-filename
    public static func generateLinkToFile(at fileURL: URL, withName fileName: String) -> URL? {
        let fileManager = FileManager.default               // the default file maneger
        let tempDirectoryURL = fileManager.temporaryDirectory   // get the temp directory
        let linkURL = tempDirectoryURL.appendingPathComponent(fileName) // and append the new file name
        do {                                                // try the operations
            if fileManager.fileExists(atPath: linkURL.path) {   // there is already a hard link with that name
                try fileManager.removeItem(at: linkURL)     // get rid of it
            }
            try fileManager.linkItem(at: fileURL, to: linkURL)  // create the hard link
            return linkURL                                  // and return it
        } catch let error as NSError {                      // something wrong
            print("\(error)")                               // debug print out
            return nil                                      // and signal to caller
        }
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
    
    // Reference: https://stackoverflow.com/questions/57134259/how-to-resolve-keywindow-was-deprecated-in-ios-13-0
    // Reference: https://stackoverflow.com/questions/32201292/access-navigationcontroller-from-a-viewcontroller-that-i-opened-using-modal-in-s
    public static func getSynthesizerVoice(withRegister register: VocalRegister? = nil) -> AVSpeechSynthesisVoice? {
        var synthesizerVoice: AVSpeechSynthesisVoice?
        voicesLoop: for voice in AVSpeechSynthesisVoice.speechVoices() {
            if (Locale.current.regionCode == "AU") && (register == .male || register == nil) && (voice.name == "Lee (Enhanced)" && voice.quality == .enhanced) {
                // AU
                // Male = Lee
                synthesizerVoice = voice
                break
            } else if (Locale.current.regionCode == "AU") && (register == .female || register == nil) && (voice.name == "Karen (Enhanced)" && voice.quality == .enhanced) {
                // AU
                // Female = Karen
                synthesizerVoice = voice
                break
            } else if (Locale.current.regionCode == "UK") && (register == .male || register == nil) && (voice.name == "Oliver (Enhanced)" && voice.quality == .enhanced) {
                // UK
                // Male = Oliver
                synthesizerVoice = voice
                break
            } else if (Locale.current.regionCode == "UK") && (register == .female || register == nil) && (voice.name == "Kate (Enhanced)" && voice.quality == .enhanced) {
                // UK
                // Female = Kate
                synthesizerVoice = voice
                break
            } else if voice.name == "Tom (Enhanced)" && (register == .male || register == nil) && voice.quality == .enhanced {
                // US
                // Male = Tom
                synthesizerVoice = voice
                break
            } else if voice.name == "Ava (Enhanced)" && (register == .female || register == nil) && voice.quality == .enhanced {
                // US
                // Female = Ava
                synthesizerVoice = voice
                break
            }
        }
        
        if let synthesizerVoice = synthesizerVoice {
            return synthesizerVoice
        } else {
            var voiceName = "Tom"
            voicesLoop: for voice in AVSpeechSynthesisVoice.speechVoices() {
                if (Locale.current.regionCode == "AU") && (register == .male || register == nil) && (voice.name == "Lee (Enhanced)" && voice.quality == .enhanced) {
                    // AU
                    // Male = Lee
                    voiceName = "Lee"
                } else if (Locale.current.regionCode == "AU") && (register == .female || register == nil) && (voice.name == "Karen (Enhanced)" && voice.quality == .enhanced) {
                    // AU
                    // Female = Karen
                    voiceName = "Karen"
                } else if (Locale.current.regionCode == "UK") && (register == .male || register == nil) && (voice.name == "Oliver (Enhanced)" && voice.quality == .enhanced) {
                    // UK
                    // Male = Oliver
                    voiceName = "Oliver"
                } else if (Locale.current.regionCode == "UK") && (register == .female || register == nil) && (voice.name == "Kate (Enhanced)" && voice.quality == .enhanced) {
                    // UK
                    // Female = Kate
                    voiceName = "Kate"
                } else if voice.name == "Tom (Enhanced)" && (register == .male || register == nil) && voice.quality == .enhanced {
                    // US
                    // Male = Tom
                    voiceName = "Tom"
                } else if voice.name == "Allison (Enhanced)" && (register == .female || register == nil) && voice.quality == .enhanced {
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
                let vc = Utils.getNavigationController()?.visibleViewController
                if let vc = vc {
                    vc.present(alertController, animated: true, completion: nil)
                }
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
        segments: [EntrySegment],
        omitSilences: Bool = false,
        omitVoiceCommands: Bool = false,
        omitDeleted: Bool = false
    ) -> [EntrySegment] {
        print("===== Cleanse Segments =====")
        var cleansedSegments = [EntrySegment]()
        
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
        var normalizedCleansedSegments = [EntrySegment]()
        var silenceIndices = [Int]()
        for (index, segment) in cleansedSegments.enumerated() {
            if segment.timeMapping.target.start.seconds != lastEnd.seconds {
                let shiftedSegment = EntrySegment(
                    entry: segment.entry,
                    speakerUID: segment.getSpeakerUID(),
                    word: segment.getText(),
                    clipUID: segment.getClipUID(),
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
                    withPunctuationSuggestions: false,
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
            }) / Double(normalizedCleansedSegments.first!.getEntry()!.getDuration().seconds / Double(TimeConstant.secsPerMin))
            speakingRate = speakingRate!.rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)
        }
        
        // Update Index, Background Noise, AvgPauseDuration, SpeakingRate
        var fullyNormalizedCleansedSegments = [EntrySegment]()
        for (index, segment) in normalizedCleansedSegments.enumerated() {
            // Set segment index
            segment.setIndex(index: index)
            
            // Set backgroundNoise
            segment.setBackgroundNoise(noise: normalizedCleansedSegments.first!.getEntry()!.getBackgroundNoise())

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
        transformations: [EntryTransformation],
        segments: [EntrySegment],
        segmentIndexMap: [String: Int],
        omitSilences: Bool,
        omitVoiceCommands: Bool,
        omitDeleted: Bool
    ) -> [EntryTransformation] {
        print("===== Cleanse Transformations =====")

        var cleansedTransformations = [EntryTransformation]()
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
                    (
                        (
                            omitSilences &&
                            !segments[segmentIndex].isSilence()
                        ) ||
                        (
                            omitSilences &&
                            segments[segmentIndex].isSilence() &&
                            segments[segmentIndex].timeMapping.target.duration.seconds <= Utils.SILENCE_SKIP_THRESHOLD
                        ) ||
                        (
                            !omitSilences
                        )
                    ) &&
                    (
                        (
                            omitVoiceCommands &&
                            !segments[segmentIndex].isVoiceCommandWord()
                        ) ||
                        (
                            !omitVoiceCommands
                        )
                    ) &&
                    (
                        (
                            omitDeleted &&
                            !segments[segmentIndex].isDeleted()
                        ) ||
                        (
                            !omitDeleted
                        )
                    )
                {
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
                let text = Entry.getText(
                    segments: segments,
                    from: lowerSegment.timeMapping.target.start,
                    until: upperSegment.timeMapping.target.end
                )
                print("\tCompute cleansed transformation text: ", text)

                // Compute value
                let value = transformation.value
                if let value = value {
                    print("\tCompute cleansed transformation value: ", value)
                }
                
                // Compute text range
                let lowerRange = lowerSegment.entry!.getSegmentTextRange(of: lowerSegment)
                let upperRange = upperSegment.entry!.getSegmentTextRange(of: upperSegment)
                
                if let lowerRange = lowerRange, let upperRange = upperRange {
                    let lowerLocation = lowerRange.location
                    let upperLocation = upperRange.location
                    let upperLength = upperRange.length
                    let textRange = NSRange(location: lowerLocation, length: (upperLocation - lowerLocation) + upperLength)
                    print("\tCompute cleansed transformation textRange: ", textRange)
                    
                    // Compute range
                    let entryRange = range
                    print("\tCompute cleansed transformation entryRange: ", entryRange)
                    
                    // Collect segment uids
                    var uids: [String: Int] = [:]
                    for segment in segments[entryRange] {
                        uids[segment.getUID()] = segment.getIndex()
                    }
                    print("\tCompute cleansed transformation segmentIndexMap: ", uids)
                    
                    let cleansedTransformation = EntryTransformation(
                        type: transformation.type,
                        uids: uids,
                        text: text,
                        value: value,
                        textRange: textRange,
                        entryRange: entryRange
                    )
                    print("\tInstantiate cleansed transformation: ", cleansedTransformation)
                    
                    cleansedTransformations.append(cleansedTransformation)
                    print("Add cleansed transformation to array...")
                } else {
                    print("\t[Error] There was a problem locating lower or upper range.")
                }
            }
        }
        
        return cleansedTransformations
    }
    
    public static func getBeginningOfEntryFrame(textView: UITextView, cursorView: UIView, font: UIFont) -> CGRect {
        // compute x and y positions
        let textContainerPadding: CGFloat = 0
//        let textContainerPadding: CGFloat = textView.textContainer.lineFragmentPadding
        let xPos = textView.frame.minX + textContainerPadding + Utils.TEXT_VIEW_PADDING_RIGHT
        let yPos = textView.frame.minY + textContainerPadding + ((font.lineHeight - font.pointSize) / 2) + Utils.TEXT_VIEW_PADDING_TOP
        let width = Utils.CURSOR_WIDTH

        // Create a CGRect object which is used to render a rectangle.
        let frame: CGRect = CGRect(
            x: xPos,
            y: yPos,
            width: CGFloat(width),
            height: CGFloat(font.lineHeight)
        )
        
        return frame
    }
    
    public static func placeCursorAtBeginningOfEntry(textView: UITextView, cursorView: UIView, font: UIFont) {
        let frame = Utils.getBeginningOfEntryFrame(textView: textView, cursorView: cursorView, font: font)
        cursorView.frame = frame
    }
    
    public static func validSpeechPower(soundIntensityStream: [SoundIntensityDatum], backgroundNoise: Double) -> Bool {
        let lastSoundIntensities = soundIntensityStream[max(0, soundIntensityStream.count - Utils.SOUND_INTENSITY_LATENCY)..<soundIntensityStream.count]
        var largestSoundIntensity: Double?
        for datum in lastSoundIntensities {
            if largestSoundIntensity == nil || datum.power > largestSoundIntensity! {
                largestSoundIntensity = datum.power
            }
        }
        
        if let largestSoundIntensity = largestSoundIntensity, largestSoundIntensity > backgroundNoise + Utils.TALKING_POWER_DELTA {
            return true
        }
        
        return false
    }
    
    public static func startRecordingUITimer(
        timer: Timer?,
        recording: Bool,
        entry: Entry? = nil,
        speechRecognition: SpeechRecognitionEngine,
        selectionCursor: SelectionCursor
    ) -> Timer {
        print("===== Utils: Start Recording UITimer =====")
        print("\tTimer: ", timer != nil ? "Yes" : "No")
        print("\tRecording: ", recording)
        
        let executeRecording = {
            if !speechRecognition.isListeningForSpeech {
                DispatchQueue.main.async {
                    let navigationController = Utils.getNavigationController()
                    let titleView = Utils.getTitleView(
                        text: "",
                        withRecording: recording,
                        asNotification: false,
                        asVoiceCommand: false
                    )
                    navigationController?.navigationBar.topItem?.titleView = titleView
                }
            }
            
            if let anchor = selectionCursor.anchor,
               let focus = selectionCursor.focus,
               selectionCursor.hasSelection &&
                selectionCursor.direction == .forwards
            {
                // we have selection in forwards direction
                // visually present the time range of selection
                DispatchQueue.main.async {
                    let navigationController = Utils.getNavigationController()
                    let titleView = Utils.getTitleView(
                        text: "\(Utils.formattedTime(time: speechRecognition.getDurationListening()))\(" [\(Utils.formattedTime(time: Float(anchor.timeMapping.target.start.seconds))) - \(Utils.formattedTime(time: Float(focus.timeMapping.target.end.seconds)))]")",
                        withRecording: recording,
                        asNotification: false,
                        asVoiceCommand: false
                    )
                    navigationController?.navigationBar.topItem?.titleView = titleView
                }
            } else if let anchor = selectionCursor.anchor,
                let focus = selectionCursor.focus,
                selectionCursor.hasSelection &&
                selectionCursor.direction == .backwards
            {
                // we have selection in backwards direction
                // visually present the time range of selection
                DispatchQueue.main.async {
                    let navigationController = Utils.getNavigationController()
                    let titleView = Utils.getTitleView(
                        text: "\(Utils.formattedTime(time: speechRecognition.getDurationListening()))\(" [\(Utils.formattedTime(time: Float(focus.timeMapping.target.start.seconds))) - \(Utils.formattedTime(time: Float(anchor.timeMapping.target.end.seconds)))]")",
                        withRecording: recording,
                        asNotification: false,
                        asVoiceCommand: false
                    )
                    navigationController?.navigationBar.topItem?.titleView = titleView
                }
            } else {
                // we don't have a selection
                // we might have a cursor placed mid-sentence however
                // present time of cursor
                DispatchQueue.main.async {
                    let navigationController = Utils.getNavigationController()
                    let titleView = Utils.getTitleView(
                        text: "\(Utils.formattedTime(time: speechRecognition.getDurationListening()))\(selectionCursor.cachedAnchor != nil && entry != nil && selectionCursor.cachedAnchor! != Utils.getEntryNthLastSegment(segments: entry!.entrySegments, selectionCursor: selectionCursor, n: 0) ? " [\(Utils.formattedTime(time: Float(selectionCursor.cachedAnchor!.timeMapping.target.end.seconds)))]" : "")",
                        withRecording: recording,
                        asNotification: false,
                        asVoiceCommand: false
                    )
                    navigationController?.navigationBar.topItem?.titleView = titleView
                }
            }
        }

        timer?.invalidate()
        executeRecording()
        
        return Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            executeRecording()
        }
    }
    
    public static func stopRecordingUITimer(timer: Timer?) -> Timer? {
        print("===== Utils: Stop Recording UITimer =====")
        timer?.invalidate()
        
        DispatchQueue.main.async {
            let navigationController = Utils.getNavigationController()
            let titleView = Utils.getTitleView(
                text: "",
                withRecording: false,
                asNotification: false,
                asVoiceCommand: false
            )
            navigationController?.navigationBar.topItem?.titleView = titleView
        }
        
        return nil
    }
    
    public static func onPitchUpdate(
        notification: Notification,
        speechPlayer: SpeechPlayerEngine,
        pitchLabel: UILabel? = nil
    ) {
        // print("===== View Controller: On Pitch Update =====")
        let pitchDatum = notification.userInfo!["pitch"] as? PitchDatum
        if let pitch = pitchDatum?.pitch, !speechPlayer.isPlayingEntry {
            pitchLabel?.text = pitch.note.string
        }
    }
    
    public static func onPowerUpdate(
        notification: Notification,
        view: UIView,
        soundIntensityIndicatorHeight: NSLayoutConstraint? = nil
    ) {
        // print("===== View Controller: On Power Update =====")
        let power = notification.userInfo!["power"] as? SoundIntensityDatum
        if let power = power {
            var screenHeight = view.safeAreaLayoutGuide.layoutFrame.height
            if let _ = Utils.getNavigationController()?.visibleViewController as? DetailViewController {
                screenHeight -= Utils.COMMAND_BAR_HEIGHT
            }
            if let _ = Utils.getNavigationController()?.visibleViewController as? DetailViewController {
                screenHeight -= Utils.MENU_BAR_HEIGHT
            }
            let soundIntensityHeight = CGFloat(min((CGFloat(Utils.normalizedPower(power: power.power, minPower: Utils.DEFAULT_MIN_POWER)) * screenHeight), screenHeight))
            soundIntensityIndicatorHeight?.constant = soundIntensityHeight
        }
    }
    
    public static func onStartedListeningForWakePhrase(
        withBackToEntriesButton: Bool = false,
        notification: Notification,
        speechRecognition: SpeechRecognitionEngine
    ) {
        print("===== Utils: On Started Listening For Wake Phrase =====")
        speechRecognition.activateListeningIndicator(
            withRecording: false,
            withStopListeningButton: true,
            withBackToEntriesButton: withBackToEntriesButton
        )
    }
    
    public static func onStartedListeningForCommands(
        withBackToEntriesButton: Bool = false,
        notification: Notification,
        speechRecognition: SpeechRecognitionEngine
    ) {
        print("===== Utils: On Started Listening For Commands =====")
        speechRecognition.activateListeningIndicator(
            withRecording: false,
            withStopListeningButton: true,
            withBackToEntriesButton: withBackToEntriesButton
        )
    }
    
    public static func onStartedListeningForSpeech(
        withBackToEntriesButton: Bool = false,
        delayStartRecording: TimeInterval = 0,
        notification: Notification,
        entry: Entry? = nil,
        speechRecognition: SpeechRecognitionEngine,
        selectionCursor: SelectionCursor,
        handler: (() -> Void)? = nil
    ) {
        print("===== Utils: On Started Listening For Speech =====")
        speechRecognition.activateListeningIndicator(
            withRecording: true,
            withStopListeningButton: false,
            withBackToEntriesButton: withBackToEntriesButton
        )
        Timer.scheduledTimer(withTimeInterval: delayStartRecording, repeats: false) { timer in
            let timer = Utils.startRecordingUITimer(
                timer: speechRecognition.listeningTimer,
                recording: true,
                entry: entry,
                speechRecognition: speechRecognition,
                selectionCursor: selectionCursor
            )
            speechRecognition.setListeningTimer(timer: timer)
            handler?()
        }
    }
    
    public static func onPausedListening(
        withBackToEntriesButton: Bool = false,
        notification: Notification,
        speechRecognition: SpeechRecognitionEngine
    ) {
        print("===== Utils: On Paused Listening =====")
        speechRecognition.activateListeningIndicator(
            withRecording: false,
            withStopListeningButton: true,
            withBackToEntriesButton: withBackToEntriesButton
        )
    }
    
    public static func onStoppedListening(
        withBackToEntriesButton: Bool = false,
        notification: Notification,
        speechRecognition: SpeechRecognitionEngine,
        soundIntensityIndicatorHeight: NSLayoutConstraint? = nil,
        pitchLabel: UILabel? = nil,
        handler: (() -> Void)? = nil
    ) {
        print("===== Utils: On Stopped Listening =====")
        
        if speechRecognition.isActive {
            speechRecognition.activateListeningIndicator(
                withRecording: false,
                withStopListeningButton: true,
                withBackToEntriesButton: withBackToEntriesButton
            )
            
            let _ = Utils.stopRecordingUITimer(timer: speechRecognition.listeningTimer)
            speechRecognition.setListeningTimer()
        }
        
        DispatchQueue.main.async {
            soundIntensityIndicatorHeight?.constant = 0
            pitchLabel?.text = ""
            handler?()
        }
    }
    
    public static func onStartTimedNotification(
        notification: Notification,
        speechRecognition: SpeechRecognitionEngine
    ) {
        print("===== Utils: On Start Timed Notification =====")
        let item = notification.userInfo!["item"] as! NotificationItem
        
        // Stop UI Timer if we receive app notification while recording
        if speechRecognition.isListeningForSpeech && speechRecognition.listeningTimer != nil {
            let _ = Utils.stopRecordingUITimer(timer: speechRecognition.listeningTimer)
            speechRecognition.setListeningTimer()
        }
        
        DispatchQueue.main.async {
            if let navigationController = Utils.getNavigationController() {
                print("\tSuccessfully retrieved navigationController")
                let titleView = Utils.getTitleView(
                    text: item.text,
                    withRecording: speechRecognition.isListeningForSpeech,
                    asNotification: true,
                    asVoiceCommand: item.isVoiceCommand
                )
                navigationController.navigationBar.topItem?.titleView = titleView
            } else {
                print("\t[Error] There was a problem retrieving the navigationController")
            }
        }
    }
    
    public static func onStopNotification(
        notification: Notification,
        entry: Entry? = nil,
        speechRecognition: SpeechRecognitionEngine,
        selectionCursor: SelectionCursor
    ) {
        print("===== Utils: On Stop Timed Notification =====")
        if speechRecognition.isListeningForSpeech {
            DispatchQueue.main.async {
                let navigationController = Utils.getNavigationController()
                let titleView = Utils.getTitleView(
                    text: "",
                    withRecording: speechRecognition.isListeningForSpeech,
                    asNotification: false,
                    asVoiceCommand: false
                )
                navigationController?.navigationBar.topItem?.titleView = titleView
            }
            let timer = Utils.startRecordingUITimer(
                timer: speechRecognition.listeningTimer,
                recording: true,
                entry: entry,
                speechRecognition: speechRecognition,
                selectionCursor: selectionCursor
            )
            speechRecognition.setListeningTimer(timer: timer)
        } else {
            DispatchQueue.main.async {
                let navigationController = Utils.getNavigationController()
                let titleView = Utils.getTitleView(
                    text: "",
                    withRecording: speechRecognition.isListeningForSpeech,
                    asNotification: false,
                    asVoiceCommand: false
                )
                navigationController?.navigationBar.topItem?.titleView = titleView
            }
        }
    }
    
    public static func onStartIndefiniteNotification(
        notification: Notification,
        state: StateManager,
        speechRecognition: SpeechRecognitionEngine
    ) {
        print("===== Utils: On Start Indefinite Notification =====")
        let item = notification.userInfo!["item"] as! NotificationItem
        
        // Stop UI Timer if recording
        if speechRecognition.isListeningForSpeech && speechRecognition.listeningTimer != nil {
            let _ = Utils.stopRecordingUITimer(timer: speechRecognition.listeningTimer)
            speechRecognition.setListeningTimer()
        }
        
        DispatchQueue.main.async {
            let navigationController = Utils.getNavigationController()
            let titleView = Utils.getTitleView(
                text: item.text,
                withRecording: speechRecognition.isListeningForSpeech || !state.appActivated,
                asNotification: false,
                asVoiceCommand: false
            )
            navigationController?.navigationBar.topItem?.titleView = titleView
        }
    }
    
    public static func onEntryStop(
        notification: Notification,
        speechRecognition: SpeechRecognitionEngine,
        handler: (() -> Void)? = nil
    ) {
        print("===== Utils: On Entry Stop =====")

        let _ = Utils.stopRecordingUITimer(timer: speechRecognition.listeningTimer)
        speechRecognition.setListeningTimer()
        handler?()
    }
    
    public static func onEntryComplete(
        notification: Notification,
        speechRecognition: SpeechRecognitionEngine,
        soundIntensityIndicatorHeight: NSLayoutConstraint? = nil,
        handler: (() -> Void)? = nil
    ) {
        print("===== Utils: On Entry Complete =====")
        // Play sound
        soundEngine.saveEntry()
        
        let _ = Utils.stopRecordingUITimer(timer: speechRecognition.listeningTimer)
        speechRecognition.setListeningTimer()
        
        DispatchQueue.main.async {
            soundIntensityIndicatorHeight?.constant = 0
            handler?()
        }
    }
    
    public static func onSpeechStartPlaying(notification: Notification, handler: (() -> Void)? = nil) {
        print("===== Utils: On Start Start Playing =====")
        handler?()
    }
    
    public static func onSpeechBoundaryCrossed(
        notification: Notification,
        speechPlayer: SpeechPlayerEngine,
        pitchLabel: UILabel? = nil,
        handler: (() -> Void)? = nil
    ) {
        print("===== Utils: On Speech Boundary Crossed =====")
        print("From: '\((notification.userInfo!["previous"] as? EntrySegment)?.getText() ?? "nil")', To: '\((notification.userInfo!["next"] as? EntrySegment)?.getText() ?? "nil")'")
        if let segment = speechPlayer.previousBoundarySegment, let pitch = segment.getPitch() {
            // update pitch
            pitchLabel?.text = pitch.note.string
        }
        handler?()
    }
    
    public static func onSpeechSecondElapsed(
        notification: Notification,
        speechRecognition: SpeechRecognitionEngine,
        speechPlayer: SpeechPlayerEngine,
        entryManager: EntryManager
    ) {
        print("===== Utils: On Speech Second Elapsed =====")
        print("Seconds: ", notification.userInfo!["seconds"] as! Double)
        if !speechRecognition.isListeningForSpeech && !entryManager.isWalkingEntry && !entryManager.isRunningEntry && Float(speechPlayer.player.currentTime().seconds).isNormal && !Float(speechPlayer.player.currentTime().seconds).isNaN {
            let navigationController = Utils.getNavigationController()
            let titleView = Utils.getTitleView(
                text: "\(Utils.formattedTime(time: Float(speechPlayer.effectiveTimeElapsed.seconds)))/\(Utils.formattedTime(time: Float(speechPlayer.effectiveDuration!.seconds)))",
                withRecording: speechRecognition.isListeningForSpeech,
                asNotification: false,
                asVoiceCommand: false
            )
            navigationController?.navigationBar.topItem?.titleView = titleView
        }
    }
    
    public static func onSpeechStopPlaying(
        notification: Notification,
        speechRecognition: SpeechRecognitionEngine,
        entryManager: EntryManager,
        handler: (() -> Void)? = nil
    ) {
        print("===== Utils: On Speech Stop Playing =====")
        let stopHandler = notification.userInfo!["handler"] as? () -> Void
        if !speechRecognition.isListeningForSpeech {
            let navigationController = Utils.getNavigationController()
            let titleView = Utils.getTitleView(
                text: "",
                withRecording: speechRecognition.isListeningForSpeech,
                asNotification: false,
                asVoiceCommand: false
            )
            navigationController?.navigationBar.topItem?.titleView = titleView
        }
        
        if let entry = entryManager.currentEntry, entryManager.pausedWalkingEntry {
            entry.walk() {
                stopHandler?()
            }
        } else if let entry = entryManager.currentEntry, entryManager.pausedRunningEntry {
            entry.run() {
                stopHandler?()
            }
        } else {
            stopHandler?()
        }
        
        handler?()
    }
    
    // Reference: https://stackoverflow.com/questions/50128462/how-to-save-document-to-files-app-in-swift
    public static func onEntryAudioExported(
        notification: Notification,
        vc: UIViewController
    ) {
        print("===== Utils: On Entry Audio Exported =====")
        // Get exported file
        let entryURL = notification.userInfo!["entryURL"] as! String

        // Present to user
        let entryFile = Utils.getFileURL(of: entryURL)
        let activityViewController = UIActivityViewController(
            activityItems: [entryFile],
            applicationActivities: nil
        )
        vc.present(activityViewController, animated: true, completion: nil)
    }
    
    public static func onEntrySet(
        notification: Notification,
        vc: UIViewController,
        identifier: String
    ) {
        print("===== Utils: On Set Entry =====")
        // push to detail view
        vc.performSegue(withIdentifier: identifier, sender: nil)
    }
    
    public static func getEntryNthLastSegment(
        segments: [EntrySegment],
        bufferSegments: [EntrySegment]? = nil,
        selectionCursor: SelectionCursor,
        n: Int
    ) -> EntrySegment? {
        let lastSegmentTuple = Utils.getEntryNthLastSegmentIndex(
            segments: segments,
            bufferSegments: bufferSegments,
            selectionCursor: selectionCursor,
            n: n
        )
        if let trackType = lastSegmentTuple.0, let lastSegmentIndex = lastSegmentTuple.1, trackType == .committed {
            return segments[lastSegmentIndex]
        } else if let trackType = lastSegmentTuple.0, let lastSegmentIndex = lastSegmentTuple.1, trackType == .buffer {
            return bufferSegments![lastSegmentIndex]
        }
        
        return nil
    }
    
    public static func getIndicesInTextRange(
        textRange: UITextRange,
        textView: UITextView,
        entry: Entry,
        segments: [EntrySegment]
    ) -> [Int] {
        // Get index relative to text view at which textPosition begins
        let location = textView.offset(from: textView.beginningOfDocument, to: textRange.start)
        // Get the length of the text range
        let length = textView.offset(from: textRange.start, to: textRange.end)
        // Get entry text
        let entryText = entry.getText()
        // Get index of lower part of text range relative to entry text
        var lowerIndex = entryText.index(entryText.startIndex, offsetBy: Int(location))
        // Get index of upper part of text range relative to entry text
        var upperIndex = entryText.index(entryText.startIndex, offsetBy: Int(location) + length)
        // Computer selection range
        var selectionRangeStringIndex = lowerIndex..<upperIndex
        // Get range text
        var rangeText = String(entryText[selectionRangeStringIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
        // Get all text before range
        var beforeRangeText = String(entryText[entryText.startIndex..<lowerIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
        // Get all text after range
        var afterRangeText = String(entryText[upperIndex..<entryText.endIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
        
        // Determine number of words before range
        var numLowerWords = beforeRangeText.split(separator: " ").count
        // Determine number of spaces before range
        var numLowerSpaces = beforeRangeText.filter { $0 == " " }.count
        
        // We want the start of the range to be at the left of a space
        // Thus the first character of should be a space
        // We slide selection to the left until we meet criteria
        var i = 0
        while numLowerWords > numLowerSpaces && beforeRangeText.count > 0 && beforeRangeText.last != " " {
            i += 1
            lowerIndex = entryText.index(entryText.startIndex, offsetBy: Int(location - i))
            selectionRangeStringIndex = lowerIndex..<upperIndex
            rangeText = String(entryText[selectionRangeStringIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
            beforeRangeText = String(entryText[entryText.startIndex..<lowerIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
            numLowerWords = beforeRangeText.split(separator: " ").count
            numLowerSpaces = beforeRangeText.filter { $0 == " " }.count
        }
        
        
        // Get number of words in range
        var numRangeWords = rangeText.split(separator: " ").count
        // Get number of spaces in range
        var numRangeSpaces = rangeText.filter { $0 == " " }.count
        
//         We want the end of the range to be at the left of a space
//         We slide selection to the right until we meet criteria
        var j = 0
        while numRangeSpaces <= numRangeWords && afterRangeText.count > 0 && afterRangeText.first != " " {
            j += 1
            upperIndex = entryText.index(entryText.startIndex, offsetBy: Int(location + length + j))
            selectionRangeStringIndex = lowerIndex..<upperIndex
            rangeText = String(entryText[selectionRangeStringIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
            afterRangeText = String(entryText[upperIndex..<entryText.endIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
            numRangeWords = rangeText.split(separator: " ").count
            numRangeSpaces = rangeText.filter { $0 == " " }.count
        }
        
        // Find segment indices that correspond
        // to the words in selection
        let selectionRange = NSRange(
            range: selectionRangeStringIndex,
            in: entryText
        )
        
        let numUpperWords = afterRangeText.split(separator: " ").count
        
        var rangeSegments = [Int]()
        let startIndex = max(0, numLowerWords - Utils.INDEX_SEARCH_BUFFER)
        let endIndex = min(segments.count - numUpperWords + Utils.INDEX_SEARCH_BUFFER, segments.count)
        for (index, segment) in segments[startIndex..<endIndex].enumerated() {
            let segmentTextRange = entry.getSegmentTextRange(of: segment)
            
            if let segmentTextRange = segmentTextRange,
               NSIntersectionRange(
                segmentTextRange,
                selectionRange
            ).length > 0 &&
            segment.isActive()
            {
                rangeSegments.append(startIndex + index)
            }
        }

        return rangeSegments
    }
    
    public static func getIndexAtTextPosition(
        textPosition: UITextPosition,
        textView: UITextView,
        entry: Entry,
        segments: [EntrySegment]
    ) -> (Int?, Int?) {
        // Get index relative to text view at which textPosition begins
        let location = textView.offset(from: textView.beginningOfDocument, to: textPosition)
        // Get entry text
        let entryText = entry.getText()
        // Get index relative to entry text at which textPosition begins
        var caretIndex = entryText.index(entryText.startIndex, offsetBy: Int(location))
        // Get all text before caret
        var beforeCaretText = String(entryText[entryText.startIndex..<caretIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
        // Get all text after caret
        var afterCaretText = String(entryText[caretIndex..<entryText.endIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
        // Determine number of words before caret
        var numLowerWords = beforeCaretText.split(separator: " ").count
        
        // We want the caret to be at the left of a space
        // Thus the first character of should be a space
        // We slide caret to the right until we meet criteria
        var rightOffsetFromCaret = 0
        while afterCaretText.count > 0 && beforeCaretText.last != " " && afterCaretText.first != " "  {
            rightOffsetFromCaret += 1
            caretIndex = entryText.index(entryText.startIndex, offsetBy: Int(location + rightOffsetFromCaret))
            beforeCaretText = String(entryText[entryText.startIndex..<caretIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
            afterCaretText = String(entryText[caretIndex..<entryText.endIndex]).replace(Utils.NEWLINE_CHAR, with: " ")
            numLowerWords = beforeCaretText.split(separator: " ").count
        }
        
        // Find segment index that corresponds to
        // the last word in the lower half of the bissection
        // caused by the caret
        var segmentIndex: Int?
        let lowerRange = NSRange(
            range: entryText.startIndex..<caretIndex,
            in: entryText
        )
        
        let startIndex = max(0, numLowerWords - Utils.INDEX_SEARCH_BUFFER)
        for (index, segment) in segments[startIndex..<segments.count].enumerated() {
            let segmentTextRange = entry.getSegmentTextRange(of: segment)
            if let segmentTextRange = segmentTextRange,
               segment.isActive() &&
                segmentTextRange.location < lowerRange.length
            { // changing this affects touch scrubbing, insert passage placement, and cursor placement
                segmentIndex = startIndex + index
            }
            
            if let segmentTextRange = segmentTextRange,
               segmentTextRange.location >= lowerRange.length
            {
                break
            }
        }
        
        return (segmentIndex, rightOffsetFromCaret)
    }
    
    // Assumes playbackSegments are sorted in ascending order of index values
    public static func getSegmentIndex(
        segment: EntrySegment,
        segments: [EntrySegment],
        type: SegmentPosition,
        by count: Int = 1,
        isWord: Bool = false,
        isCommitted: Bool = false
    ) -> Int? {
        var result: Int?
        switch type {
        case .current:
            result = Utils.binarySearchIndex(
                in: segments,
                isLower: { seg in
                    return seg.timeMapping.target.start < segment.timeMapping.target.start
                },
                isHigher: { seg in
                    return seg.timeMapping.target.start > segment.timeMapping.target.start
                }
            )
            
        case .previous:
            var currentSegmentIndex = max(0, (segment.getIndex() - segments[0].getIndex()) - 1)
            if let index = Utils.binarySearchIndex(
                in: segments,
                isLower: { seg in
                    return seg.timeMapping.target.start < segment.timeMapping.target.start
                },
                isHigher: { seg in
                    return seg.timeMapping.target.start > segment.timeMapping.target.start
                }
            ) {
                currentSegmentIndex = max(0, index - 1)
            }
            
            var numProcessedWords = 0
            result = currentSegmentIndex
            if (
                !segments[currentSegmentIndex].isPunctuation() &&
                !segments[currentSegmentIndex].isSilence() &&
                !segments[currentSegmentIndex].isVoiceCommandWord() &&
                !segments[currentSegmentIndex].isDeleted()
            ) {
                numProcessedWords += 1
            }
            
            while (
                (
                    isWord &&
                    (
                        segments[currentSegmentIndex].isPunctuation() ||
                        segments[currentSegmentIndex].isSilence() ||
                        segments[currentSegmentIndex].isVoiceCommandWord() ||
                        segments[currentSegmentIndex].isDeleted()
                    )
                ) ||
                (isCommitted && !segments[currentSegmentIndex].isCommitted())
                ||
                numProcessedWords < count
            ) && currentSegmentIndex - 1 >= 0 {
                currentSegmentIndex -= 1
                result = currentSegmentIndex
                if (
                    !segments[currentSegmentIndex].isPunctuation() &&
                    !segments[currentSegmentIndex].isSilence() &&
                    !segments[currentSegmentIndex].isVoiceCommandWord() &&
                    !segments[currentSegmentIndex].isDeleted()
                ) {
                    numProcessedWords += 1
                }
            }
        case .next:
            var currentSegmentIndex = min((segment.getIndex() - segments[0].getIndex()) + 1, segments.count - 1)
            if let index = Utils.binarySearchIndex(
                in: segments,
                isLower: { seg in
                    return seg.timeMapping.target.end < segment.timeMapping.target.end // switching these to start might break sentence selection
                },
                isHigher: { seg in
                    return seg.timeMapping.target.end > segment.timeMapping.target.end
                }
            ) {
                currentSegmentIndex = min(index + 1, segments.count - 1)
            }
            
            var numProcessedWords = 0
            result = currentSegmentIndex
            if (
                !segments[currentSegmentIndex].isPunctuation() &&
                !segments[currentSegmentIndex].isSilence() &&
                !segments[currentSegmentIndex].isVoiceCommandWord() &&
                !segments[currentSegmentIndex].isDeleted()
            ) {
                numProcessedWords += 1
            }

            while (
                (
                    isWord &&
                    (
                        segments[currentSegmentIndex].isPunctuation() ||
                        segments[currentSegmentIndex].isSilence() ||
                        segments[currentSegmentIndex].isVoiceCommandWord() ||
                        segments[currentSegmentIndex].isDeleted()
                    )
                ) ||
                (isCommitted && !segments[currentSegmentIndex].isCommitted())
                ||
                numProcessedWords < count
            ) && currentSegmentIndex + 1 < segments.count {
                currentSegmentIndex += 1
                result = currentSegmentIndex
                if (
                    !segments[currentSegmentIndex].isPunctuation() &&
                    !segments[currentSegmentIndex].isSilence() &&
                    !segments[currentSegmentIndex].isVoiceCommandWord() &&
                    !segments[currentSegmentIndex].isDeleted()
                ) {
                    numProcessedWords += 1
                }
            }
        }
        
        if let result = result, (isWord && (
            segments[result].isPunctuation() ||
            segments[result].isSilence() ||
            segments[result].isVoiceCommandWord() ||
            segments[result].isDeleted()
        )) ||
        (isCommitted && !segments[result].isCommitted()) {
            return nil
        } else {
            return result
        }
    }
    
    public static func getSegment(
        forTrackTime: CMTime,
        segments: [EntrySegment]? = nil,
        entry: Entry? = nil,
        isPlayingEntry: Bool = false,
        isWord: Bool = false,
        isCommitted: Bool = false
    ) -> EntrySegment? {
        if let segments = segments, isPlayingEntry {
            var segment = Utils.binarySearch(
                in: segments,
                isLower: { segment in
                    return segment.timeMapping.target.end < forTrackTime
                },
                isHigher: { segment in
                    return segment.timeMapping.target.start > forTrackTime
                }
            )
            
            if let s = segment, isWord || isCommitted {
                var currentSegmentIndex = s.getIndex() - segments[0].getIndex()
                while let seg = segment, (
                    (isWord && (
                        seg.isPunctuation() ||
                        seg.isSilence() ||
                        seg.isVoiceCommandWord() ||
                        seg.isDeleted()
                    )) ||
                    (isCommitted && !seg.isCommitted())
                ) && currentSegmentIndex + 1 < segments.count {
                    currentSegmentIndex += 1
                    segment = segments[currentSegmentIndex]
                }
            }
            return segment
        } else if let entry = entry {
            // check committed segments
            var seg = Utils.binarySearch(
                in: entry.entrySegments,
                isLower: { segment in
                    return segment.timeMapping.target.end < forTrackTime
                },
                isHigher: { segment in
                    return segment.timeMapping.target.start > forTrackTime
                }
            )
            
            // Only return if we found it
            if let s = seg, isWord || isCommitted {
                var currentSegmentIndex = s.getIndex() - entry.entrySegments[0].getIndex()
                while let segment = seg, (
                    (isWord && (
                        segment.isPunctuation() ||
                        segment.isSilence() ||
                        segment.isVoiceCommandWord() ||
                        segment.isDeleted()
                    )) ||
                    (isCommitted && !segment.isCommitted())
                ) && currentSegmentIndex + 1 < entry.entrySegments.count {
                    currentSegmentIndex += 1
                    seg = entry.entrySegments[currentSegmentIndex]
                }
                return seg
            }
            
            // check buffer segments
            let committedTrackLastSegment = entry.entrySegments.last
            if let committedTrackLastSegment = committedTrackLastSegment {
                // We subtract because segments in track two do not factor time from track one
                let boundaryTime = CMTimeSubtract(forTrackTime, committedTrackLastSegment.timeMapping.target.end)
                var segment = Utils.binarySearch(
                    in: entry.entryBuffer,
                    isLower: { segment in
                        return segment.timeMapping.target.end < boundaryTime
                    },
                    isHigher: { segment in
                        return segment.timeMapping.target.start > boundaryTime
                    }
                )
                
                if let s = segment, isWord || isCommitted {
                    var currentSegmentIndex = s.getIndex() - entry.entryBuffer[0].getIndex()
                    while let seg = segment, (
                        (isWord && (
                            seg.isPunctuation() ||
                            seg.isSilence() ||
                            seg.isVoiceCommandWord() ||
                            seg.isDeleted()
                        )) ||
                        (isCommitted && !seg.isCommitted())
                    ) && currentSegmentIndex + 1 < entry.entryBuffer.count {
                        currentSegmentIndex += 1
                        segment = entry.entryBuffer[currentSegmentIndex]
                    }
                    return segment
                }
                
                return segment
            }
        }
        
        return nil
    }
    
    public static func getSegments(entry: Entry, from: CMTime = CMTime.zero, until: CMTime) -> [EntrySegment] {
        var segments = [EntrySegment]()
        for segment in entry.entrySegments {
            if segment.timeMapping.target.start >= from && segment.timeMapping.target.end <= until {
                segments.append(segment)
            }
        }
        
        return segments
    }
    
    // Reference: https://www.robnorback.com/blog/setting-title-and-title-color-on-a-uibutton-in-swift-3
    public static func getPitchLabel(pitchText: String, font: UIFont) -> UIBarButtonItem {
        let button  = UIButton(type: .custom)
        button.frame = CGRect(x: 0.0, y: 0.0, width: Utils.NAVBAR_BUTTON_LENGTH, height: Utils.NAVBAR_BUTTON_LENGTH)
        button.setTitle(pitchText, for: .normal)
        button.titleLabel?.font = font
        button.setTitleColor(UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red, for: .normal)
        
        let barButton = UIBarButtonItem(customView: button)
        barButton.isEnabled = false
        
        return barButton
    }
    
    public static func getTitleView(
        text: String,
        withRecording: Bool = false,
        asNotification: Bool = false,
        asVoiceCommand: Bool = false
    ) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = text
        titleLabel.font = UIFont.systemFont(ofSize: Utils.DEFAULT_FONT_SIZE, weight: .semibold)
        if asNotification || asVoiceCommand || withRecording {
            titleLabel.textColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
        } else {
            titleLabel.textColor = UIColor.white
        }
        
        var stackSubviews = [UIView]()
        var imageView: UIImageView?
        if asVoiceCommand {
            imageView = UIImageView(image: UIImage(systemName: "mouth"))
            NSLayoutConstraint.activate([
                imageView!.heightAnchor.constraint(equalToConstant: 20),
                imageView!.widthAnchor.constraint(equalToConstant: 20)
            ])
            imageView!.tintColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
            stackSubviews.append(imageView!)
        } else if asNotification {
            imageView = UIImageView(image: UIImage(systemName: "bell"))
            NSLayoutConstraint.activate([
                imageView!.heightAnchor.constraint(equalToConstant: 20),
                imageView!.widthAnchor.constraint(equalToConstant: 20)
            ])
            imageView!.tintColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
            stackSubviews.append(imageView!)
        }
        
        stackSubviews.append(titleLabel)
        
        let horizontalStack = UIStackView(arrangedSubviews: stackSubviews)
        horizontalStack.spacing = 5
        horizontalStack.alignment = .center
        
        return horizontalStack
    }
    
    // MARK: - Helper Functions
    
    private static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    // Reference: https://learnappmaking.com/binary-search-swift-how-to/
    // Must be ordered segments and conditional
    public static func binarySearch(in segments: [EntrySegment], isLower: (_ segment: EntrySegment) -> Bool, isHigher: (_ segment: EntrySegment) -> Bool) -> EntrySegment? {
        let index = binarySearchIndex(in: segments, isLower: isLower, isHigher: isHigher)
        if let index = index {
            return segments[index]
        }
        return nil
    }
    
    public static func binarySearchIndex(in segments: [EntrySegment], isLower: (_ segment: EntrySegment) -> Bool, isHigher: (_ segment: EntrySegment) -> Bool) -> Int? {
        var left = 0
        var right = segments.count - 1
        
        while left <= right {
            let middle = Int(floor(Double(left + right) / 2.0))
            
            if isLower(segments[middle]) {
                left = middle + 1
            } else if isHigher(segments[middle]) {
                right = middle - 1
            } else {
                return middle
            }
        }
        
        return nil
    }
    
    // Reference: https://stackoverflow.com/questions/22663353/algorithm-to-remove-extreme-outliers-in-array/22663905
    public static func cleanseSoundIntensityStream(soundIntensityStream: [SoundIntensityDatum]) -> [SoundIntensityDatum] {
        // sort stream
        let sortedSoundIntensityStream = soundIntensityStream.sorted {
            $0.power < $1.power
        }
        
        var sum: Double = 0     // stores sum of elements
        var sumSquares: Double = 0; // stores sum of squares
        var length: Double = 0
        for i in 0..<sortedSoundIntensityStream.count {
            if sortedSoundIntensityStream[i].power != Double.infinity && sortedSoundIntensityStream[i].power != Double.nan && sortedSoundIntensityStream[i].power != -Double.infinity  {
                sum += sortedSoundIntensityStream[i].power
                sumSquares += sortedSoundIntensityStream[i].power * sortedSoundIntensityStream[i].power
                length += 1
            }
        }

        let mean = sum / length;
        let variance = sumSquares / length - mean * mean
        let standardDev = sqrt(variance)

        var filteredSoundIntensityStream = [SoundIntensityDatum]() // uses for data which is 3 standard deviations from the mean
        for i in 0..<soundIntensityStream.count {
            if soundIntensityStream[i].power > (mean - 3 * standardDev) && soundIntensityStream[i].power < (mean + 3 * standardDev) {
                filteredSoundIntensityStream.append(soundIntensityStream[i])
            }
        }
        
        return filteredSoundIntensityStream
    }
    
    public static func getNavigationController() -> UINavigationController? {
        let keyWindow = UIApplication.shared.connectedScenes
                .filter({$0.activationState == .foregroundActive})
                .map({$0 as? UIWindowScene})
                .compactMap({$0})
                .first?.windows
                .filter({$0.isKeyWindow}).first
        return keyWindow?.rootViewController as? UINavigationController
    }
    
    // Reference: https://stackoverflow.com/questions/25827033/how-do-i-convert-a-swift-array-to-a-string
    // Reference: https://codeburst.io/swift-map-flatmap-filter-and-reduce-53959ebeb6aa
    public static func stringifySegments(segments: [EntrySegment]) -> String {
        let segments = segments.map({(segment: EntrySegment) -> String in
            if segment.isVoiceCommandWord() {
                return "[Voice Command Word: '\(segment.getText())']"
            } else if segment.isDeleted() {
                return "[Deleted: '\(segment.getText())']"
            } else {
                return "'\(segment.getText())'"
            }
        })
        return "[\(segments.joined(separator: ", "))]"
    }
    
    public static func getEntryNthLastSegmentIndex(
        segments: [EntrySegment],
        bufferSegments: [EntrySegment]? = nil,
        fromBuffer: Bool = false,
        selectionCursor: SelectionCursor,
        n: Int
    ) -> (EntryTrackType?, Int?) {
        var lastSegmentIndex: Int?
        var trackType: EntryTrackType?
        if bufferSegments == nil || bufferSegments!.count == 0 {
            // No buffer segments were supplied
            // Search for nth last segment in committed segments only
            trackType = .committed
            var i = 0
            for (index, segment) in segments.reversed().enumerated() {
                if segment.isActive() && lastSegmentIndex == nil && i == n {
                    lastSegmentIndex = segments.count - index - 1
                    break
                } else if segment.isActive() && lastSegmentIndex == nil {
                    // we've encountered another word, add to number of words encountered accumulator
                    i += 1
                }
            }
        } else if let bufferSegments = bufferSegments, bufferSegments.count > 0 {
            // Buffer segments were supplied
            // Search for nth last segment from segment array that is a composition of committed and buffer segments.
            if let cachedAnchorCaret = selectionCursor.cachedAnchorCaret {
                // Cached Anchor Caret exists

                // Insert buffer at correct location within committed segments
                var entrySegments = segments
                let index = cachedAnchorCaret.index
                entrySegments.insert(contentsOf: bufferSegments, at: index)
                
                var i = 0
                var segmentsIndex: Int?
                if fromBuffer {
                    // Seeking nth last index from buffer segments only
                    let permittedSegments = Array(entrySegments[0..<cachedAnchorCaret.index + bufferSegments.count])
                    for (index, segment) in permittedSegments.reversed().enumerated() {
                        if segment.isActive() && segmentsIndex == nil && i == n {
                            segmentsIndex = permittedSegments.count - index - 1
                            break
                        } else if segment.isActive() && segmentsIndex == nil {
                            // we've encountered another word, add to number of words encountered accumulator
                            i += 1
                        }
                    }
                } else {
                    // Seeking last index from segment array that is a composition of committed and buffer segments.
                    for (index, segment) in entrySegments.reversed().enumerated() {
                        if segment.isActive() && segmentsIndex == nil && i == n {
                            segmentsIndex = entrySegments.count - index - 1
                            break
                        } else if segment.isActive() && segmentsIndex == nil {
                            // we've encountered another word, add to number of words encountered accumulator
                            i += 1
                        }
                    }
                }

                if let segmentsIndex = segmentsIndex,
                    segmentsIndex < cachedAnchorCaret.index &&
                    !fromBuffer
                {
                    // Index is before location where buffer was inserted...
                    trackType = .committed
                    lastSegmentIndex = segmentsIndex
                } else if let segmentsIndex = segmentsIndex,
                 segmentsIndex >= cachedAnchorCaret.index &&
                  segmentsIndex < cachedAnchorCaret.index + bufferSegments.count
                {
                    // Index is in buffer...
                    trackType = .buffer
                    lastSegmentIndex = segmentsIndex - cachedAnchorCaret.index
                } else if let segmentsIndex = segmentsIndex,
                    segmentsIndex >= cachedAnchorCaret.index + bufferSegments.count &&
                    !fromBuffer
                {
                    // Index is after buffer...
                    trackType = .committed
                    lastSegmentIndex = segmentsIndex - bufferSegments.count
                }
            } else {
                // Cached Anchor Caret doesn't exist
                
                // Insert buffer at the end of committed segments
                let entrySegments = segments + bufferSegments
                
                var i = 0
                var segmentsIndex: Int?
                for (index, segment) in entrySegments.reversed().enumerated() {
                    if segment.isActive() && segmentsIndex == nil && i == n {
                        segmentsIndex = entrySegments.count - index - 1
                        break
                    } else if segment.isActive() && segmentsIndex == nil {
                        // we've encountered another word, add to number of words encountered accumulator
                        i += 1
                    }
                }

                if let segmentsIndex = segmentsIndex, segmentsIndex >= segments.count {
                    // Index is in buffer...
                    trackType = .buffer
                    lastSegmentIndex = segmentsIndex - segments.count
                } else if let segmentsIndex = segmentsIndex, !fromBuffer {
                    // Index is committed segment (before buffer)...
                    trackType = .committed
                    lastSegmentIndex = segmentsIndex
                }
            }
        }
        
        return (trackType, lastSegmentIndex)
    }
    
    public static func encodeLingualEntry(entry: Entry, filename: String) -> Bool {
        print("===== Utils: Encode Lingual Entry =====")
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: entry, requiringSecureCoding: false) {
            let url = Utils.getFileURL(of: filename)
            if let _ = try? savedData.write(to: url, options: []) {
                print("\tSuccessfully saved entry as binary file!")
                return true
            } else {
                print("\t[Error] There was a problem saving entry as binary file.")
            }
        } else {
            print("\t[Error] There was a problem creating binary file of entry.")
        }
        
        return false
    }
    
    public static func decodeLingualEntry(name: String) -> Entry? {
        print("===== Utils: Decode Lingual Entry =====")
        let entryPath = Bundle.main.path(forResource: name, ofType: "lingual")!
        let entryURL = URL(fileURLWithPath: entryPath)
        
        if let dataFile = try? Data(contentsOf: entryURL) {
            if let entry = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(dataFile) as? Entry {
                print("\tSuccessfully fetched entry!")
                return entry
            } else {
                print("\t[Error] There was a problem converting entry Data object to Entry class instance.")
            }
        } else {
            print("\t[Error] There was a problem locating entry with name: \(name).")
        }
        
        return nil
    }
    
    // Reference: https://stackoverflow.com/questions/49540035/how-to-store-audio-data-into-documents-directory
    public static func writeToDocumentsDirectory(filename: String) {
        let fileManager = FileManager.default
        
        let fileURL = Utils.getFileURL(of: "\(filename).caf")
        if fileManager.fileExists(atPath: fileURL.path) {
            // do nothing
        } else {
            // Get file from bundle
            let bundlePath = Bundle.main.path(forResource: filename, ofType: "caf")!
            let bundleURL = URL(fileURLWithPath: bundlePath)
            do {
                try fileManager.copyItem(at: bundleURL, to: fileURL)
            } catch {
                print("[Error in Write to Documents Directory] There was a problem copying '\(filename).caf' to Documents Directory.")
            }
        }
    }
    
    // Reference: https://stackoverflow.com/questions/33021064/how-to-generate-all-possible-combinations
    public static func permute(list: [String], minWordJoins: Int = 1, maxWordJoins: Int = 10, separator: String = "") -> Set<String> {
        func permute(fromList: [String], toList: [String], minWordJoins: Int, maxWordJoins: Int, separator: String, set: inout Set<String>) {
            if toList.count >= minWordJoins && toList.count <= maxWordJoins {
                set.insert(toList.joined(separator: separator))
            }
            if !fromList.isEmpty {
                for (index, item) in fromList.enumerated() {
                    var newFrom = fromList
                    newFrom.remove(at: index)
                    permute(fromList: newFrom, toList: toList + [item], minWordJoins: minWordJoins, maxWordJoins: maxWordJoins, separator: separator, set: &set)
                }
            }
        }

        var set = Set<String>()
        permute(fromList: list, toList:[], minWordJoins: minWordJoins, maxWordJoins: maxWordJoins, separator: separator, set: &set)
        return set
    }
}
