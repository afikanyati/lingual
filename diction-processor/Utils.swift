//
//  computeSoundIntensityHeight.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/3/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Foundation
import AVFoundation

class Utils {
    static let UNKNOWN: Double = -1
    
    // MARK: - Factory Methods
    public static func trimExpression(expression: Expression, keeping: CMTimeRange, permanent: Bool = false, onCompletionHandler: @escaping (_ expression: Expression?) -> Void) {
        print("===== Trim Expression Factory Method =====")
        expression.duplicate() { expression in
            if let duplicateExpression = expression {
                duplicateExpression.trimExpression(keeping: keeping, permanent: permanent) {
                    onCompletionHandler(duplicateExpression)
                }
            }
        }
    }
    
    // MARK: - General Utilities
    
    // Cannot export to outputURL's that already exist
    // Reference: https://stackoverflow.com/questions/20203548/avassetexportsession-not-exporting-time-range
    // Deleting: https://stackoverflow.com/questions/42041405/delete-a-file-using-swift-in-ios
    public static func exportExpression(expression: Expression, filename: String, fileType: String, timeRange: CMTimeRange, onCompletionHandler: @escaping () -> Void) {
        print("===== Export Expression =====")
        
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

        if !AVAssetExportSession.exportPresets(compatibleWith: expression).contains(AVAssetExportPresetAppleM4A) {
            fatalError("\t[Error] Expected export preset value not compatible with expression")
        }

        guard let exporter = AVAssetExportSession(asset: expression, presetName: AVAssetExportPresetAppleM4A) else {
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
            DispatchQueue.main.async {
                if exporter.status == AVAssetExportSession.Status.completed {
                    print("===== Expression successfully exported: \(filename).m4a =====")
                    onCompletionHandler()
                } else {
                    print("===== [Error] Unable to export expression =====")
                    if let error = exporter.error {
                        print("\tMessage: \(error.localizedDescription)")
                    }
                    fatalError()
                }
            }
        }
    }
    
    public static func runPlayer(expression: Expression, startTime: CMTime, rate: Float, volume: Float, onStartHandler: (() -> Void)? = nil) -> AVPlayer? {
        print("===== Run Player =====")
        if expression.player.currentItem == nil, let snapshot = expression.copy() as? AVAsset {
            print("\tInitiating AVPlayer...")
            let assetKeys = [
                   "playable",
                   "duration",
                   "hasProtectedContent"
               ]
            let playerItem = AVPlayerItem(asset: snapshot, automaticallyLoadedAssetKeys: assetKeys)

            playerItem.addObserver(
                expression,
                forKeyPath: #keyPath(AVPlayerItem.status),
                options: [.old, .new],
                context: nil
            )

            let player = AVPlayer(playerItem: playerItem)
            
            // Set Volume
            Utils.setPlayerVolume(player: player, volume: volume)
            
            return player
        } else if expression.player.status != .readyToPlay {
            // just wait for item to be ready
            print("\tWaiting for AVPlayerItem to be ready...\n")
        } else {
            print("\tImmediately Playing Item\n")
            expression.player.play()
            let rateWasSet = Utils.setPlayerRate(player: expression.player, rate: rate)
            if rateWasSet {
                print("\tPlayer rate was successfully set...")
            } else {
                print("\t[Error] There was a problem setting player rate. Player had not been started yet.")
            }
            expression.player.seek(to: startTime)
            onStartHandler?()
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
            print("\tWill play expression in fast forward at rate: \(rate)...")
            player.rate = rate
        } else if rate > 0.0 && rate < 1.0 {
            // Play slow forward
            print("\tWill play expression in slow forward at rate: \(rate)...")
            player.rate = rate
        } else if rate < 0.0 && rate > -1.0 {
            // Play slow reverse
            print("\tWill play expression in slow reverse at rate: \(rate)...")
            player.rate = rate
        } else if rate < -1.0 {
            // Play fast reverse
            print("\tWill play expression in fast reverse at rate: \(rate)...")
            player.rate = rate
        } else {
            // Play as normal if rate = 1.0
            // Stop if rate = 0.0
            print("\tWill play expression at rate: \(rate)...")
            player.rate = rate
        }
        
        return true
    }
    
    public static func setPlayerVolume(player: AVPlayer, volume: Float) {
        print("===== Set Player Volume =====")
        
        // Set volume
        print("\tWill play expression at volume: \(volume)...")
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

    public static func computeNormalizedSoundIntensity(buffer: AVAudioPCMBuffer, minDb: Float) -> Double? {
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
        
        // Scale the decibels into a value suitable for your vuMeter.
        let meterLevel = normalizedPower(power: avgPower, minDb: minDb)
        
        return meterLevel
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

    private static func normalizedPower(power: Double, minDb: Float) -> Double {
        guard power.isFinite else { return 0.0 }
        
        if power < Double(minDb) {
            return 0.0
        } else if power >= 1.0 {
            return 1.0
        } else {
            return (abs(Double(minDb)) - abs(power)) / abs(Double(minDb))
        }
    }
    
    private static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
}
