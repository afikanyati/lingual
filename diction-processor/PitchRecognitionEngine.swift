//
//  PitchRecognitionEnginer.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/31/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

class PitchRecognitionEngine: NSObject, PitchEngineDelegate {
    // MARK: - Notifications
    
    static let onPitchUpdate = Notification.Name(Notifications.onPitchUpdate.rawValue)
    
    // MARK: - App Modules
    
    var state: StateManager
    var speechRecognition: SpeechRecognitionEngine
    var noteManager: NoteManager!
    
    private(set) var pitchStream = [PitchDatum]()

    lazy var pitchEngine: PitchEngine = { [weak self] in
        let config = Config(
            bufferSize: 1024,
            estimationStrategy: .yin
        )
        let pitchEngine = PitchEngine(config: config, delegate: self)
        pitchEngine.levelThreshold = Utils.DEFAULT_MIN_POWER
        return pitchEngine
    }()
    
    // MARK: - Initialization and Deinitialization
    
    init(
        state: StateManager,
        speechRecognition: SpeechRecognitionEngine
    ) {
        print("===== Pitch Recognition Engine: Initialization =====")
        self.state = state
        self.speechRecognition = speechRecognition
        
        super.init()
        
        self.configureNotificationObservers()
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
        // Observe SpeechRecognitionEngine
        notificationCenter.addObserver(
            self,
            selector: #selector(onStartedListening(notification:)),
            name: SpeechRecognitionEngine.onStartedListeningForWakePhrase,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStoppedListening(notification:)),
            name: SpeechRecognitionEngine.onStoppedListeningForWakePhrase,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStartedListening(notification:)),
            name: SpeechRecognitionEngine.onStartedListeningForCommands,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStoppedListening(notification:)),
            name: SpeechRecognitionEngine.onStoppedListeningForCommands,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStartedListening(notification:)),
            name: SpeechRecognitionEngine.onStartedListeningForSpeech,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStoppedListening(notification:)),
            name: SpeechRecognitionEngine.onStoppedListeningForSpeech,
            object: nil
        )

        // Observe SpeechRecognitionEngine
        notificationCenter.addObserver(
            self,
            selector: #selector(onBufferItem(notification:)),
            name: SpeechRecognitionEngine.onBufferItem,
            object: nil
        )
    }
    
    @objc func onStartedListening(notification: Notification) {
        print("===== Pitch Recognition Engine: On Start Listening =====")
        if !self.pitchEngine.active {
            self.pitchEngine.start()
        }
    }
    
    @objc func onStoppedListening(notification: Notification) {
        print("===== Pitch Recognition Engine: On Stopped Listening =====")
        self.pitchEngine.stop()
    }
    
    @objc func onBufferItem(notification: Notification) {
        // print("===== Pitch Recognition Engine: On Buffer Item =====")
        // Pitch
        var userInfo = [String : PitchDatum]()
        if let pitch = self.pitchStream.last {
            userInfo["pitch"] = pitch
        }
        NotificationCenter.default.post(
            name: PitchRecognitionEngine.onPitchUpdate,
            object: nil,
            userInfo: userInfo
        )
    }
    
    // MARK: - Getters

    func getPitch() -> Double {
        let numPitches: Double = Double(self.pitchStream.count)
        
        if numPitches == 0 {
            return Utils.UNKNOWN
        }
        var pitchSum: Double = 0

        for datum in self.pitchStream {
            if let pitch = datum.pitch {
                pitchSum += pitch.frequency
            }
        }
        
        return pitchSum / numPitches
    }
    
    func getRecordingPitch(timestamp: Double) -> PitchDatum {
        var pitch: PitchDatum
        var i = 0
        var datumTimestamp = self.pitchStream[i].date - self.noteManager.currentNote!.recordStartDate! - Utils.TRANSCRIPTION_LATENCY_DURATION
        repeat {
            datumTimestamp = self.pitchStream[i].date - self.noteManager.currentNote!.recordStartDate! - Utils.TRANSCRIPTION_LATENCY_DURATION
            pitch = self.pitchStream[i]
            i += 1
        } while datumTimestamp < timestamp && i < self.pitchStream.count
        
        return pitch
    }
    
    // MARK: - Pitch Engine Delegate
    
    public func pitchEngine(_ pitchEngine: PitchEngine, didReceivePitch pitch: Pitch) {
        // TODO: Timing
        if pitch.frequency >= Utils.MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= Utils.FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.speechRecognition.getBackgroundNoise() != Double.infinity && self.speechRecognition.soundIntensityStream.count > Utils.MIN_SEED_INTENSITY_POINTS && Utils.validSpeechPower(soundIntensityStream: self.speechRecognition.soundIntensityStream, backgroundNoise: self.speechRecognition.getBackgroundNoise()) {
            // Add to pitch stream
            let pitchDatum = PitchDatum(date: Date(), pitch: pitch)
            self.pitchStream.append(pitchDatum)
            
            // Set speaker pitch
            if !self.state.appActivated {
                do {
                    if self.state.speaker.pitch == nil {
                        print("===== Pitch Recognition Engine: Base vocal frequency detected =====")
                        // when uncommented, it stops system from hearing wake phrase
//                        let rate: Float = 0.53
//                        let volume = AVAudioSession.sharedInstance().outputVolume
//                        let voice = Utils.getSynthesizerVoice(
//                            withGender: pitch.note.octave >= 4 ? .female : .male,
//                            vc: self
//                        )
//                        let synthesizerItem = SynthesizerItem(
//                            synthesizer: self.speechSynthesizer,
//                            text: "Base vocal frequency detected",
//                            voice: voice,
//                            rate: rate,
//                            volume: volume
//                        )
//
//                        Utils.runSpeechSynthesizer(item: synthesizerItem)
                    }

                    let avgPitch = try Pitch(frequency: self.getPitch())
                    self.state.setSpeakerPitch(to: avgPitch)
                } catch {
                    print("===== Pitch Recognition Engine: [Error] There was a problem calculating average pitch =====")
                }
            }
        }
        
        if pitch.frequency >= Utils.MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= Utils.FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.speechRecognition.soundIntensityStream.count > Utils.MIN_SEED_INTENSITY_POINTS && Utils.validSpeechPower(soundIntensityStream: self.speechRecognition.soundIntensityStream, backgroundNoise: self.speechRecognition.getBackgroundNoise()) {
            let pitchDatum = PitchDatum(date: Date(), pitch: pitch)
            self.pitchStream.append(pitchDatum)
            
            if self.state.speaker.pitch == nil {
                let numPitches: Double = Double(self.pitchStream.count)

                var pitchSum: Double = 0

                for datum in self.pitchStream {
                    if let pitch = datum.pitch {
                        pitchSum += pitch.frequency
                    }
                }
                
                do {
                    let avgPitch = try Pitch(frequency: pitchSum / numPitches)
                    self.state.setSpeakerPitch(to: avgPitch)
                } catch {
                    print("===== Pitch Recognition Engine: [Error] There was a problem setting speaker pitch =====")
                }
            }
        }
        
//        if let lastSoundIntensity = self.soundIntensityStream.last, pitch.frequency >= Utils.MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= Utils.FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.getBackgroundNoise() != Double.infinity && self.soundIntensityStream.count > 0 && lastSoundIntensity.power > self.getBackgroundNoise() + Utils.VOLUME_POWER_DELTA {
//            // print("power: ", lastSoundIntensity.power, self.getBackgroundNoise(), Utils.VOLUME_POWER_DELTA)
//            if self.isListeningForVolume && self.volumeListeningRateTimer == nil {
//
//                Utils.setMainVolume(to: Float(Utils.normalizePitch(incidentPitch: pitch, basePitch: self.note.speaker.pitch!)))
//                // MAKE SURE TO ALSO CHANGE VOLUME OF SOUND EFFECTS
//                self.volumeListeningRateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) {[weak self] timer in
//                    self?.volumeListeningRateTimer = nil
//                    // 0.2 interval seems good
//                }
//            }
//        }
    }

    public func pitchEngine(_ pitchEngine: PitchEngine, didReceiveError error: Error) {
//        print("===== Pitch Recognition Engine: Did Receive Error =====")
//        print("\tError: \(error.localizedDescription)")
    }

    public func pitchEngineWentBelowLevelThreshold(_ pitchEngine: PitchEngine) {
//         print("===== Pitch Recognition Engine: Pitch Engine Below Level Threshold =====")
    }
}
