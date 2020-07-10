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
    
    public static func formattedTime(time: Float) -> String {
        var secs = Int(ceil(time))
        var hours = 0
        var mins = 0

        if secs > TimeConstant.secsPerHour {
            hours = secs / TimeConstant.secsPerHour
            secs -= hours * TimeConstant.secsPerHour
        }

        if secs > TimeConstant.secsPerMin {
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
            } else if voice.name == "Allison (Enhanced)" && (gender == .female || gender == nil) && voice.quality == .enhanced {
                // US
                // Female = Allison
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
