//
//  StorageManager.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/31/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit
import CloudKit

class StorageManager: NSObject {
    // MARK: - Notifications
    
    static let onFetchedStoredState = Notification.Name(Notifications.onFetchedStoredState.rawValue)
    
    // MARK: - App Modules
    
    var speechRecognition: SpeechRecognitionEngine!
    
    // MARK: - Initialization and Deinitialization
    
    override init() {
        print("===== Storage Manager: Initialization =====")
    }
    
    // MARK: - Methods
    
    func fetch() {
        print("===== Storage Manager: Fetch =====")
        NotificationCenter.default.post(
            name: StorageManager.onFetchedStoredState,
            object: nil,
            userInfo: [
                "userSettings": self.fetchUserSettings() as Any,
                "entries" : self.fetchEntries() as Any,
                "voiceCommandStream": self.fetchVoiceCommandStream() as Any,
                "appTelemetry": self.fetchAppTelemetry() as Any,
                "clips": self.fetchClips() as Any
            ]
        )
    }
    
    func save(state: StateManager) {
        print("===== Storage Manager: Save =====")
        DispatchQueue.global(qos: .utility).async {
            self.saveToCloud(
                speaker: state.speaker,
                entries: state.entries,
                playbackRate: state._playbackRate,
                echoRate: state._echoRate,
                appOpens: state.appOpens,
                audioDeviceUse: state.audioDeviceUse,
                entryViews: state.entryViews,
                entryPlays: state.entryPlays,
                entryTextExports: state.entryTextExports,
                entryAudioExports: state.entryAudioExports,
                activeEntryWordCounts: state.activeEntryWordCounts,
                deletedEntryWordCounts: state.activeEntryWordCounts,
                voiceCommands: state.voiceCommands,
                voiceCommandStream: self.speechRecognition.voiceCommandStream
            )
            self.saveEntries(entries: state.entries)
            self.saveUserSettings(
                speaker: state.speaker,
                withOnDeviceRecognition: state.withOnDeviceRecognition,
                withTemporalSuggestions: state.withTemporalSuggestions,
                withPunctuationSuggestions: state.withPunctuationSuggestions,
                withFormattingSuggestions: state.withFormattingSuggestions,
                withTextStrictlyAsWords: state.withTextStrictlyAsWords,
                withCapitalization: state.withCapitalization,
                withSkipPunctuation: state.withSkipPunctuation,
                withOmitSilences: state.withOmitSilences,
                withPassiveEcho: state.withPassiveEcho,
                playbackRate: state._playbackRate,
                echoRate: state._echoRate,
                fontSize: state.font.pointSize
            )
            self.saveAppTelemetry(
                appOpens: state.appOpens,
                audioDeviceUse: state.audioDeviceUse,
                entryViews: state.entryViews,
                entryPlays: state.entryPlays,
                entryTextExports: state.entryTextExports,
                entryAudioExports: state.entryAudioExports,
                activeEntryWordCounts: state.activeEntryWordCounts,
                deletedEntryWordCounts: state.activeEntryWordCounts,
                voiceCommands: state.voiceCommands
            )
            self.saveVoiceCommandStream(voiceCommandStream: self.speechRecognition.voiceCommandStream)
            self.saveClips(clips: state.clips)
        }
    }
    
    // MARK: - Fetching
    
    func fetchEntries() -> [Entry]? {
        print("===== Storage Manager: Fetch Entries =====")
        let defaults = UserDefaults.standard
        if let savedObj = defaults.object(forKey: "entries") as? Data {
            if let entries = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [Entry] {
                print("\tSuccessfully fetched \(entries.count) entries!")
                return entries
            } else {
                print("\t[Error] There was a problem converting entries Data object to array of Entries.")
            }
        } else {
            print("\t[Error] There was a problem retrieving entries Data object.")
        }
        
        return nil
    }
    
    func fetchClips() -> [String: Set<String>]? {
        print("===== Storage Manager: Fetch Clips =====")
        let defaults = UserDefaults.standard
        if let savedObj = defaults.object(forKey: "clips") as? Data {
            if let clips = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [String: Set<String>] {
                print("\tSuccessfully fetched \(clips.count) clips!")
                return clips
            } else {
                print("\t[Error] There was a problem converting entries Data object to clips dictionary.")
            }
        } else {
            print("\t[Error] There was a problem retrieving entries clips dictionary.")
        }
        
        return nil
    }
    
    func fetchUserSettings() -> [String : Any] {
        print("===== Storage Manager: Fetch User Settings =====")
        let defaults = UserDefaults.standard
        
        var userSettings: [String : Any] = [:]
        
        // speaker
        if let savedObj = defaults.object(forKey: "speaker") as? Data {
            if let speaker = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Speaker {
                print("\tSuccessfully fetched speaker: \(speaker)")
                userSettings["speaker"] = speaker
            } else {
                print("\t[Error] There was a problem fetching speaker.")
            }
        } else {
            print("\t[Error] There was a problem retrieving speaker Data object.")
        }
        
        // withOnDeviceRecognition
        if let savedObj = defaults.object(forKey: "withOnDeviceRecognition") as? Data {
            if let withOnDeviceRecognition = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Bool {
                print("\tSuccessfully fetched withOnDeviceRecognition: \(withOnDeviceRecognition)")
                userSettings["withOnDeviceRecognition"] = withOnDeviceRecognition
            } else {
                print("\t[Error] There was a problem fetching withOnDeviceRecognition.")
            }
        } else {
            print("\t[Error] There was a problem retrieving withOnDeviceRecognition Data object.")
        }
        
        // withTemporalSuggestions
        if let savedObj = defaults.object(forKey: "withTemporalSuggestions") as? Data {
            if let withTemporalSuggestions = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Bool {
                print("\tSuccessfully fetched withTemporalSuggestions: \(withTemporalSuggestions)")
                userSettings["withTemporalSuggestions"] = withTemporalSuggestions
            } else {
                print("\t[Error] There was a problem fetching withTemporalSuggestions.")
            }
        } else {
            print("\t[Error] There was a problem retrieving withTemporalSuggestions Data object.")
        }
        
        // withPunctuationSuggestions
        if let savedObj = defaults.object(forKey: "withPunctuationSuggestions") as? Data {
            if let withPunctuationSuggestions = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Bool {
                print("\tSuccessfully fetched withPunctuationSuggestions: \(withPunctuationSuggestions)")
                userSettings["withPunctuationSuggestions"] = withPunctuationSuggestions
            } else {
                print("\t[Error] There was a problem fetching withPunctuationSuggestions.")
            }
        } else {
            print("\t[Error] There was a problem retrieving withPunctuationSuggestions Data object.")
        }
        
        // withFormattingSuggestions
        if let savedObj = defaults.object(forKey: "withFormattingSuggestions") as? Data {
            if let withFormattingSuggestions = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Bool {
                print("\tSuccessfully fetched withFormattingSuggestions: \(withFormattingSuggestions)")
                userSettings["withFormattingSuggestions"] = withFormattingSuggestions
            } else {
                print("\t[Error] There was a problem fetching withFormattingSuggestions.")
            }
        } else {
            print("\t[Error] There was a problem retrieving withFormattingSuggestions Data object.")
        }
        
        // withTextStrictlyAsWords
        if let savedObj = defaults.object(forKey: "withTextStrictlyAsWords") as? Data {
            if let withTextStrictlyAsWords = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Bool {
                print("\tSuccessfully fetched withTextStrictlyAsWords: \(withTextStrictlyAsWords)")
                userSettings["withTextStrictlyAsWords"] = withTextStrictlyAsWords
            } else {
                print("\t[Error] There was a problem fetching withTextStrictlyAsWords.")
            }
        } else {
            print("\t[Error] There was a problem retrieving withTextStrictlyAsWords Data object.")
        }
        
        // withCapitalization
        if let savedObj = defaults.object(forKey: "withCapitalization") as? Data {
            if let withCapitalization = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Bool {
                print("\tSuccessfully fetched withCapitalization: \(withCapitalization)")
                userSettings["withCapitalization"] = withCapitalization
            } else {
                print("\t[Error] There was a problem fetching withCapitalization.")
            }
        } else {
            print("\t[Error] There was a problem retrieving withCapitalization Data object.")
        }
        
        // withSkipPunctuation
        if let savedObj = defaults.object(forKey: "withSkipPunctuation") as? Data {
            if let withSkipPunctuation = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Bool {
                print("\tSuccessfully fetched withSkipPunctuation: \(withSkipPunctuation)")
                userSettings["withSkipPunctuation"] = withSkipPunctuation
            } else {
                print("\t[Error] There was a problem fetching withSkipPunctuation.")
            }
        } else {
            print("\t[Error] There was a problem retrieving withSkipPunctuation Data object.")
        }
        
        // withOmitSilences
        if let savedObj = defaults.object(forKey: "withOmitSilences") as? Data {
            if let withOmitSilences = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Bool {
                print("\tSuccessfully fetched withOmitSilences: \(withOmitSilences)")
                userSettings["withOmitSilences"] = withOmitSilences
            } else {
                print("\t[Error] There was a problem fetching withOmitSilences.")
            }
        } else {
            print("\t[Error] There was a problem retrieving withOmitSilences Data object.")
        }
        
        // withPassiveEcho
        if let savedObj = defaults.object(forKey: "withPassiveEcho") as? Data {
            if let withPassiveEcho = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Bool {
                print("\tSuccessfully fetched withPassiveEcho: \(withPassiveEcho)")
                userSettings["withPassiveEcho"] = withPassiveEcho
            } else {
                print("\t[Error] There was a problem fetching withPassiveEcho.")
            }
        } else {
            print("\t[Error] There was a problem retrieving withPassiveEcho Data object.")
        }
        
        // playbackRate
        if let savedObj = defaults.object(forKey: "playbackRate") as? Data {
            if let playbackRate = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Float {
                print("\tSuccessfully fetched playbackRate: \(playbackRate)")
                userSettings["playbackRate"] = playbackRate
            } else {
                print("\t[Error] There was a problem fetching playbackRate.")
            }
        } else {
            print("\t[Error] There was a problem retrieving playbackRate Data object.")
        }
        
        // echoRate
        if let savedObj = defaults.object(forKey: "echoRate") as? Data {
            if let echoRate = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? Float {
                print("\tSuccessfully fetched echoRate: \(echoRate)")
                userSettings["echoRate"] = echoRate
            } else {
                print("\t[Error] There was a problem fetching echoRate.")
            }
        } else {
            print("\t[Error] There was a problem retrieving echoRate Data object.")
        }
        
        // font
        if let savedObj = defaults.object(forKey: "fontSize") as? Data {
            if let fontSize = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? CGFloat {
                print("\tSuccessfully fetched font size: \(fontSize)")
                userSettings["fontSize"] = fontSize
            } else {
                print("\t[Error] There was a problem fetching font size.")
            }
        } else {
            print("\t[Error] There was a problem retrieving font size Data object.")
        }
        
        return userSettings
    }
    
    func fetchVoiceCommandStream() -> [VoiceCommandDatum]? {
        print("===== Storage Manager: Fetch Voice Command Stream =====")
        let defaults = UserDefaults.standard
        
        if let savedObj = defaults.object(forKey: "voiceCommandStream") as? Data {
            if let voiceCommandStream = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [VoiceCommandDatum] {
                print("\tSuccessfully fetched \(voiceCommandStream.count) voice commands!")
                return voiceCommandStream
            } else {
                print("\t[Error] There was a problem fetching voiceCommandStream.")
            }
        } else {
            print("\t[Error] There was a problem retrieving voiceCommandStream Data object.")
        }
        return nil
    }
    
    func fetchAppTelemetry() -> [String : Any] {
        print("===== Storage Manager: Fetch App Telemetry =====")
        let defaults = UserDefaults.standard
        
        var appTelemetry: [String : Any] = [:]
        
        // App Opens
        if let savedObj = defaults.object(forKey: "appOpens") as? Data {
            if let appOpens = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [TimeInterval] {
                print("\tSuccessfully fetched \(appOpens.count) app opens!")
                appTelemetry["appOpens"] = appOpens
            } else {
                print("\t[Error] There was a problem fetching appOpens.")
            }
        } else {
            print("\t[Error] There was a problem retrieving appOpens Data object.")
        }
        
        // Audio Device Use
        if let savedObj = defaults.object(forKey: "audioDeviceUse") as? Data {
            if let audioDeviceUse = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [AudioDeviceDatum] {
                print("\tSuccessfully fetched \(audioDeviceUse.count) audio device datum!")
                appTelemetry["audioDeviceUse"] = audioDeviceUse
            } else {
                print("\t[Error] There was a problem fetching audioDeviceUse.")
            }
        } else {
            print("\t[Error] There was a problem retrieving audioDeviceUse Data object.")
        }
        
        // Entry Views
        if let savedObj = defaults.object(forKey: "entryViews") as? Data {
            if let entryViews = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [TimeInterval] {
                print("\tSuccessfully fetched \(entryViews.count) entryViews!")
                appTelemetry["entryViews"] = entryViews
            } else {
                print("\t[Error] There was a problem fetching entryViews.")
            }
        } else {
            print("\t[Error] There was a problem retrieving entryViews Data object.")
        }
        
        // Entry Plays
        if let savedObj = defaults.object(forKey: "entryViews") as? Data {
            if let entryPlays = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [TimeInterval] {
                print("\tSuccessfully fetched \(entryPlays.count) entryPlays!")
                appTelemetry["entryPlays"] = entryPlays
            } else {
                print("\t[Error] There was a problem fetching entryPlays.")
            }
        } else {
            print("\t[Error] There was a problem retrieving entryPlays Data object.")
        }
        
        // Entry Text Exports
        if let savedObj = defaults.object(forKey: "entryTextExports") as? Data {
            if let entryTextExports = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [TimeInterval] {
                print("\tSuccessfully fetched \(entryTextExports.count) entryTextExports!")
                appTelemetry["entryTextExports"] = entryTextExports
            } else {
                print("\t[Error] There was a problem fetching entryTextExports.")
            }
        } else {
            print("\t[Error] There was a problem retrieving entryTextExports Data object.")
        }
        
        // Entry Audio Exports
        if let savedObj = defaults.object(forKey: "entryAudioExports") as? Data {
            if let entryAudioExports = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [TimeInterval] {
                print("\tSuccessfully fetched \(entryAudioExports.count) entryAudioExports!")
                appTelemetry["entryAudioExports"] = entryAudioExports
            } else {
                print("\t[Error] There was a problem fetching entryAudioExports.")
            }
        } else {
            print("\t[Error] There was a problem retrieving entryAudioExports Data object.")
        }
        
        // Active Entry Word Counts
        if let savedObj = defaults.object(forKey: "activeEntryWordCounts") as? Data {
            if let activeEntryWordCounts = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [Int] {
                print("\tSuccessfully fetched \(activeEntryWordCounts.count) activeEntryWordCounts!")
                appTelemetry["activeEntryWordCounts"] = activeEntryWordCounts
            } else {
                print("\t[Error] There was a problem fetching activeEntryWordCounts.")
            }
        } else {
            print("\t[Error] There was a problem retrieving activeEntryWordCounts Data object.")
        }
        
        // Deleted Entry Word Counts
        if let savedObj = defaults.object(forKey: "deletedEntryWordCounts") as? Data {
            if let deletedEntryWordCounts = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [Int] {
                print("\tSuccessfully fetched \(deletedEntryWordCounts.count) deletedEntryWordCounts!")
                appTelemetry["deletedEntryWordCounts"] = deletedEntryWordCounts
            } else {
                print("\t[Error] There was a problem fetching deletedEntryWordCounts.")
            }
        } else {
            print("\t[Error] There was a problem retrieving deletedEntryWordCounts Data object.")
        }
        
        // Voice Commands
        if let savedObj = defaults.object(forKey: "voiceCommands") as? Data {
            if let voiceCommands = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [TimeInterval] {
                print("\tSuccessfully fetched \(voiceCommands.count) voiceCommands!")
                appTelemetry["voiceCommands"] = voiceCommands
            } else {
                print("\t[Error] There was a problem fetching voiceCommands.")
            }
        } else {
            print("\t[Error] There was a problem retrieving voiceCommands Data object.")
        }
        
        return appTelemetry
    }
    
    // MARK: - Saving
    
    func saveEntries(entries: [Entry]) {
        print("===== Storage Manager: Save Entries =====")
        
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: entries, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "entries")
            print("\tSuccessfully saved \(entries.count) entries!")
        } else {
            print("\t[Error] There was a problem converting entries to Data object.")
        }
    }
    
    func saveClips(clips: [String: Set<String>]) {
        print("===== Storage Manager: Save Clips =====")
        
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: clips, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "clips")
            print("\tSuccessfully saved \(clips.count) clips!")
        } else {
            print("\t[Error] There was a problem converting clips to Data object.")
        }
    }
    
    func saveUserSettings(
        speaker: Speaker,
        withOnDeviceRecognition: Bool,
        withTemporalSuggestions: Bool,
        withPunctuationSuggestions: Bool,
        withFormattingSuggestions: Bool,
        withTextStrictlyAsWords: Bool,
        withCapitalization: Bool,
        withSkipPunctuation: Bool,
        withOmitSilences: Bool,
        withPassiveEcho: Bool,
        playbackRate: Float,
        echoRate: Float,
        fontSize: CGFloat
    ) {
        print("===== Storage Manager: Save User Settings =====")
        
        // speaker
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: speaker, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "speaker")
            print("\tSuccessfully saved speaker: \(speaker)")
        } else {
            print("\t[Error] There was a problem converting speaker to Data object.")
        }
        
        // withOnDeviceRecognition
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: withOnDeviceRecognition, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "withOnDeviceRecognition")
            print("\tSuccessfully saved withOnDeviceRecognition: \(withOnDeviceRecognition)")
        } else {
            print("\t[Error] There was a problem converting withOnDeviceRecognition to Data object.")
        }
        
        // withTemporalSuggestions
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: withTemporalSuggestions, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "withTemporalSuggestions")
            print("\tSuccessfully saved withTemporalSuggestions: \(withTemporalSuggestions)")
        } else {
            print("\t[Error] There was a problem converting withTemporalSuggestions to Data object.")
        }
        
        // withPunctuationSuggestions
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: withPunctuationSuggestions, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "withPunctuationSuggestions")
            print("\tSuccessfully saved withOnDeviceRecognition: \(withPunctuationSuggestions)")
        } else {
            print("\t[Error] There was a problem converting withPunctuationSuggestions to Data object.")
        }
        
        // withFormattingSuggestions
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: withFormattingSuggestions, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "withFormattingSuggestions")
            print("\tSuccessfully saved withFormattingSuggestions: \(withFormattingSuggestions)")
        } else {
            print("\t[Error] There was a problem converting withFormattingSuggestions to Data object.")
        }
        
        // withTextStrictlyAsWords
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: withTextStrictlyAsWords, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "withTextStrictlyAsWords")
            print("\tSuccessfully saved withTextStrictlyAsWords: \(withTextStrictlyAsWords)")
        } else {
            print("\t[Error] There was a problem converting withTextStrictlyAsWords to Data object.")
        }
        
        // withCapitalization
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: withCapitalization, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "withCapitalization")
            print("\tSuccessfully saved withCapitalization: \(withCapitalization)")
        } else {
            print("\t[Error] There was a problem converting withCapitalization to Data object.")
        }
        
        // withSkipPunctuation
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: withSkipPunctuation, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "withSkipPunctuation")
            print("\tSuccessfully saved withSkipPunctuation: \(withSkipPunctuation)")
        } else {
            print("\t[Error] There was a problem converting withSkipPunctuation to Data object.")
        }
        
        // withOmitSilences
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: withOmitSilences, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "withOmitSilences")
            print("\tSuccessfully saved withOmitSilences: \(withOmitSilences)")
        } else {
            print("\t[Error] There was a problem converting withOmitSilences to Data object.")
        }
        
        // withPassiveEcho
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: withPassiveEcho, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "withPassiveEcho")
            print("\tSuccessfully saved withPassiveEcho: \(withPassiveEcho)")
        } else {
            print("\t[Error] There was a problem converting withPassiveEcho to Data object.")
        }
        
        // playbackRate
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: playbackRate, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "playbackRate")
            print("\tSuccessfully saved playbackRate: \(playbackRate)")
        } else {
            print("\t[Error] There was a problem converting playbackRate to Data object.")
        }
        
        // echoRate
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: echoRate, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "echoRate")
            print("\tSuccessfully saved echoRate: \(echoRate)")
        } else {
            print("\t[Error] There was a problem converting echoRate to Data object.")
        }
        
        // font size
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: fontSize, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "fontSize")
            print("\tSuccessfully saved fontSize: \(fontSize)")
        } else {
            print("\t[Error] There was a problem converting fontSize to Data object.")
        }
    }
    
    func saveAppTelemetry(
        appOpens: [TimeInterval],
        audioDeviceUse: [AudioDeviceDatum],
        entryViews: [TimeInterval],
        entryPlays: [TimeInterval],
        entryTextExports: [TimeInterval],
        entryAudioExports: [TimeInterval],
        activeEntryWordCounts: [Int],
        deletedEntryWordCounts: [Int],
        voiceCommands: [TimeInterval]
    ) {
        print("===== Storage Manager: Save Telemetry =====")
        
        // App Opens
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: appOpens, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "appOpens")
            print("\tSuccessfully saved \(appOpens.count) appOpens!")
        } else {
            print("\t[Error] There was a problem converting appOpens to Data object.")
        }
        
        // Audio Device Use
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: audioDeviceUse, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "audioDeviceUse")
            print("\tSuccessfully saved \(audioDeviceUse.count) audioDeviceUse!")
        } else {
            print("\t[Error] There was a problem converting audioDeviceUse to Data object.")
        }
        
        // Entry Views
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: entryViews, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "entryViews")
            print("\tSuccessfully saved \(entryViews.count) entryViews!")
        } else {
            print("\t[Error] There was a problem converting entryViews to Data object.")
        }
        
        // Entry Plays
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: entryPlays, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "entryPlays")
            print("\tSuccessfully saved \(entryPlays.count) entryPlays!")
        } else {
            print("\t[Error] There was a problem converting entryPlays to Data object.")
        }
        
        // Entry Text Exports
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: entryTextExports, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "entryTextExports")
            print("\tSuccessfully saved \(entryTextExports.count) entryTextExports!")
        } else {
            print("\t[Error] There was a problem converting entryTextExports to Data object.")
        }
        
        // Entry Audio Exports
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: entryAudioExports, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "entryAudioExports")
            print("\tSuccessfully saved \(entryAudioExports.count) entryAudioExports!")
        } else {
            print("\t[Error] There was a problem converting entryAudioExports to Data object.")
        }
        
        // Active Entry Word Counts
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: activeEntryWordCounts, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "activeEntryWordCounts")
            print("\tSuccessfully saved \(activeEntryWordCounts.count) activeEntryWordCounts!")
        } else {
            print("\t[Error] There was a problem converting activeEntryWordCounts to Data object.")
        }
        
        // Deleted Entry Word Counts
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: deletedEntryWordCounts, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "deletedEntryWordCounts")
            print("\tSuccessfully saved \(deletedEntryWordCounts.count) deletedEntryWordCounts!")
        } else {
            print("\t[Error] There was a problem converting deletedEntryWordCounts to Data object.")
        }
        
        // Voice Commands
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: voiceCommands, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "voiceCommands")
            print("\tSuccessfully saved \(voiceCommands.count) voiceCommands!")
        } else {
            print("\t[Error] There was a problem converting voiceCommands to Data object.")
        }
    }
    
    func saveVoiceCommandStream(voiceCommandStream: [VoiceCommandDatum]) {
        print("===== Storage Manager: Save Voice Command Stream =====")
        
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: voiceCommandStream, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "voiceCommandStream")
            print("\tSuccessfully saved \(voiceCommandStream.count) voice commmands!")
        } else {
            print("\t[Error] There was a problem converting voice commands to Data object.")
        }
    }
    
    // Reference: https://stackoverflow.com/questions/29315598/how-to-get-the-current-user-id-in-cloudkit
    // Reference: https://stackoverflow.com/questions/54332381/cloudkit-public-and-private-database-messaging-platform
    func saveToCloud(
        speaker: Speaker,
        entries: [Entry],
        playbackRate: Float,
        echoRate: Float,
        appOpens: [TimeInterval],
        audioDeviceUse: [AudioDeviceDatum],
        entryViews: [TimeInterval],
        entryPlays: [TimeInterval],
        entryTextExports: [TimeInterval],
        entryAudioExports: [TimeInterval],
        activeEntryWordCounts: [Int],
        deletedEntryWordCounts: [Int],
        voiceCommands: [TimeInterval],
        voiceCommandStream: [VoiceCommandDatum]
    ) {
        print("===== Storage Manager: Save To Cloud =====")
        let handleSave: () -> Void = {
            if let recordName = speaker.cloudKitRecordID {
                print("\tFound existing record. Modify existing user record...")
                let recordID = CKRecord.ID.init(recordName: recordName)
                CKContainer(identifier: Utils.CLOUD_KIT_CONTAINER_IDENTIFIER).publicCloudDatabase.fetch(withRecordID: recordID) { (record, err) in
                    if let err = err {
                        print("\t[Error] There was a problem fetching user record.")
                        print("\tMessage: ", err.localizedDescription)
                        return
                    }
                    guard let record = record else { return }
                    
                    // Save UID
                    if let uid = speaker.uid {
                        record["speakerUID"] = uid as CKRecordValue
                    }
                    // Save Device
                    record["speakerDevice"] = speaker.device as CKRecordValue
                    // Save Clout Kit Record ID
                    if let cloudKitRecordID = speaker.cloudKitRecordID {
                        record["speakerCloudKitRecordID"] = cloudKitRecordID as CKRecordValue
                    }
                    // Save Name
                    if let name = speaker.name {
                        record["speakerName"] = name as CKRecordValue
                    }
                    // Save Avatar URL
                    if let avatarURL = speaker.avatarURL {
                        record["speakerAvatarURL"] = avatarURL.absoluteString as CKRecordValue
                    }
                    // Save Pitch
                    if let pitch = speaker.pitch {
                        record["speakerPitchFrequency"] = pitch.frequency as CKRecordValue
                    }
                    
                    // Save Playback Rates
                    record["playbackRate"] = playbackRate as CKRecordValue
                    record["echoRate"] = echoRate as CKRecordValue
                    
                    // Set App Telemetry
                    if appOpens.count > 0 {
                        let opens = appOpens.map({(interval: TimeInterval) -> String in
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                            let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                            return dateString
                        })
                        record["appOpens"] = opens as CKRecordValue
                    }
                    if audioDeviceUse.count > 0 {
                        let audioUse = audioDeviceUse.map { String(describing: $0) }
                        record["audioDeviceUse"] = audioUse as CKRecordValue
                    }
                    if entryViews.count > 0 {
                        let views = entryViews.map({(interval: TimeInterval) -> String in
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                            let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                            return dateString
                        })
                        record["entryViews"] = views as CKRecordValue
                    }
                    if entryPlays.count > 0 {
                        let plays = entryPlays.map({(interval: TimeInterval) -> String in
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                            let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                            return dateString
                        })
                        record["entryPlays"] = plays as CKRecordValue
                    }
                    if entryTextExports.count > 0 {
                        let textExports = entryTextExports.map({(interval: TimeInterval) -> String in
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                            let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                            return dateString
                        })
                        record["entryTextExports"] = textExports as CKRecordValue
                    }
                    if entryAudioExports.count > 0 {
                        let audioExports = entryAudioExports.map({(interval: TimeInterval) -> String in
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                            let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                            return dateString
                        })
                        record["entryAudioExports"] = audioExports as CKRecordValue
                    }
                    if activeEntryWordCounts.count > 0 {
                        record["activeEntryWordCounts"] = activeEntryWordCounts as CKRecordValue
                        record["activeEntryBackgroundNoise"] = entries.map { $0.avgBackgroundNoise } as CKRecordValue
                    }
                    if deletedEntryWordCounts.count > 0 {
                        record["deletedEntryWordCounts"] = deletedEntryWordCounts as CKRecordValue
                    }
                    if voiceCommands.count > 0 {
                        let commands = voiceCommands.map({(interval: TimeInterval) -> String in
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                            let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                            return dateString
                        })
                        record["voiceCommands"] = commands as CKRecordValue
                    }
                    
                    // Save Voice Command Stream
                    if voiceCommandStream.count > 0 {
                        let stream = voiceCommandStream.map { String(describing: $0) }
                        record["voiceCommandStream"] = stream as CKRecordValue
                    }
                    
                    CKContainer(identifier: Utils.CLOUD_KIT_CONTAINER_IDENTIFIER).publicCloudDatabase.save(record) { record, err in
                        if let err = err {
                            print("\t[Error] There was a problem save user record.")
                            print("\tMessage: ", err.localizedDescription)
                            return
                        } else {
                            print("\tSuccessfully saved user record to CloudKit")
                        }
                    }
                }
            } else {
                print("\tNo existing record. Generate new user record...")
                let userRecord = CKRecord(recordType: "Telemetry")
                
                // Save UID
                if let uid = speaker.uid {
                    userRecord["speakerUID"] = uid as CKRecordValue
                }
                // Save Device
                userRecord["speakerDevice"] = speaker.device as CKRecordValue

                // Save Name
                if let name = speaker.name {
                    userRecord["speakerName"] = name as CKRecordValue
                }
                // Save Avatar URL
                if let avatarURL = speaker.avatarURL {
                    userRecord["speakerAvatarURL"] = avatarURL.absoluteString as CKRecordValue
                }
                // Save Pitch
                if let pitch = speaker.pitch {
                    userRecord["speakerPitchFrequency"] = pitch.frequency as CKRecordValue
                }
                
                // Save Playback Rates
                userRecord["playbackRate"] = playbackRate as CKRecordValue
                userRecord["echoRate"] = echoRate as CKRecordValue
                
                // Set App Telemetry
                if appOpens.count > 0 {
                    let opens = appOpens.map({(interval: TimeInterval) -> String in
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                        let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                        return dateString
                    })
                    userRecord["appOpens"] = opens as CKRecordValue
                }
                if audioDeviceUse.count > 0 {
                    let audioUse = audioDeviceUse.map { String(describing: $0) }
                    userRecord["audioDeviceUse"] = audioUse as CKRecordValue
                }
                if entryViews.count > 0 {
                    let views = entryViews.map({(interval: TimeInterval) -> String in
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                        let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                        return dateString
                    })
                    userRecord["entryViews"] = views as CKRecordValue
                }
                if entryPlays.count > 0 {
                    let plays = entryPlays.map({(interval: TimeInterval) -> String in
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                        let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                        return dateString
                    })
                    userRecord["entryPlays"] = plays as CKRecordValue
                }
                if entryTextExports.count > 0 {
                    let textExports = entryTextExports.map({(interval: TimeInterval) -> String in
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                        let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                        return dateString
                    })
                    userRecord["entryTextExports"] = textExports as CKRecordValue
                }
                if entryAudioExports.count > 0 {
                    let audioExports = entryAudioExports.map({(interval: TimeInterval) -> String in
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                        let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                        return dateString
                    })
                    userRecord["entryAudioExports"] = audioExports as CKRecordValue
                }
                if activeEntryWordCounts.count > 0 {
                    userRecord["activeEntryWordCounts"] = activeEntryWordCounts as CKRecordValue
                    userRecord["activeEntryBackgroundNoise"] = entries.map { $0.avgBackgroundNoise } as CKRecordValue
                }
                if deletedEntryWordCounts.count > 0 {
                    userRecord["deletedEntryWordCounts"] = deletedEntryWordCounts as CKRecordValue
                }
                if voiceCommands.count > 0 {
                    let commands = voiceCommands.map({(interval: TimeInterval) -> String in
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                        let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: interval))
                        return dateString
                    })
                    userRecord["voiceCommands"] = commands as CKRecordValue
                }
                
                // Save Voice Command Stream
                if voiceCommandStream.count > 0 {
                    let stream = voiceCommandStream.map { String(describing: $0) }
                    userRecord["voiceCommandStream"] = stream as CKRecordValue
                }
                
                CKContainer(identifier: Utils.CLOUD_KIT_CONTAINER_IDENTIFIER).publicCloudDatabase.save(userRecord) { record, err in
                    if let err = err {
                        print("\t[Error] There was a problem save user record.")
                        print("\tMessage: ", err.localizedDescription)
                        return
                    }
                    guard let record = record else { return }
                    let id = record.recordID.recordName
                    speaker.setCloudKitRecordID(to: id)
                    record["speakerCloudKitRecordID"] = id as CKRecordValue
                    CKContainer(identifier: Utils.CLOUD_KIT_CONTAINER_IDENTIFIER).publicCloudDatabase.save(record) { record, err in
                        if let err = err {
                            print("\t[Error] There was a problem save user record.")
                            print("\tMessage: ", err.localizedDescription)
                            return
                        } else {
                            print("\tSuccessfully saved user record to CloudKit")
                        }
                    }
                }
            }
        }
        
        if let _ = speaker.uid {
            print("\tSpeaker has existing Cloud Kit ID. Proceed as usual...")
            // We have user's record id
            handleSave()
        } else {
            print("\tSpeaker doesn't have existing Cloud Kit ID. Fetch it...")
            // Get user's record id
            CKContainer(identifier: Utils.CLOUD_KIT_CONTAINER_IDENTIFIER).fetchUserRecordID(completionHandler: { (recordId, error) in
                if let id = recordId?.recordName {
                    print("\tiCloud ID: " + id)
                    // Set id in speaker
                    speaker.setUID(to: id)
                    handleSave()
                } else if let error = error {
                    print("\t[Error] There was a problem fetching User Record ID.")
                    print("\tMessage: ", error.localizedDescription)
                }
            })
        }
    }
}
