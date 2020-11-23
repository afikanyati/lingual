//
//  StorageManager.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/31/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

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
                "notes" : self.fetchNotes() as Any,
                "voiceCommandStream": self.fetchVoiceCommandStream() as Any,
                "appOpens": self.fetchAppOpens() as Any
            ]
        )
    }
    
    func save(state: StateManager) {
        print("===== Storage Manager: Save =====")
        DispatchQueue.global(qos: .utility).async {
            self.saveNotes(notes: state.notes)
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
            self.saveAppOpens(opens: state.appOpens)
            if let speechRecognition = self.speechRecognition {
                self.saveVoiceCommandStream(voiceCommandStream: speechRecognition.voiceCommandStream)
            }
            self.saveClips(clips: state.clips)
        }
    }
    
    // MARK: - Fetching
    
    func fetchNotes() -> [Note]? {
        print("===== Storage Manager: Fetch Notes =====")
        let defaults = UserDefaults.standard
        if let savedObj = defaults.object(forKey: "notes") as? Data {
            if let notes = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [Note] {
                print("\tSuccessfully fetched \(notes.count) notes!")
                return notes
            } else {
                print("\t[Error] There was a problem converting notes Data object to array of Notes.")
            }
        } else {
            print("\t[Error] There was a problem retrieving notes Data object.")
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
                print("\t[Error] There was a problem converting notes Data object to clips dictionary.")
            }
        } else {
            print("\t[Error] There was a problem retrieving notes clips dictionary.")
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
    
    func fetchAppOpens() -> [TimeInterval]? {
        print("===== Storage Manager: Fetch App Opens =====")
        let defaults = UserDefaults.standard
        
        if let savedObj = defaults.object(forKey: "appOpens") as? Data {
            if let appOpens = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedObj) as? [TimeInterval] {
                print("\tSuccessfully fetched \(appOpens.count) app opens!")
                return appOpens
            } else {
                print("\t[Error] There was a problem fetching appOpens.")
            }
        } else {
            print("\t[Error] There was a problem retrieving appOpens Data object.")
        }
        return nil
    }
    
    // MARK: - Saving
    
    func saveNotes(notes: [Note]) {
        print("===== Storage Manager: Save Notes =====")
        
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: notes, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "notes")
            print("\tSuccessfully saved \(notes.count) notes!")
        } else {
            print("\t[Error] There was a problem converting notes to Data object.")
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
    
    func saveAppOpens(opens: [TimeInterval]) {
        print("===== Storage Manager: Save App Opens =====")

        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: opens, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "appOpens")
            print("\tSuccessfully saved \(opens.count) app opens!")
        } else {
            print("\t[Error] There was a problem converting app opens to Data object.")
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
}
