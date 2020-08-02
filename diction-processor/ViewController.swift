//
//  ViewController.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/9/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Speech
import AVFoundation
import NaturalLanguage

let DEFAULT_USE_ON_DEVICE_RECOGNITION = true
let MALE_LOWEST_VOICED_SPEECH_FREQUENCY: Double = 82
let FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY: Double = 1047
let MIN_SEED_INTENSITY_POINTS = 15
let AVATAR_URL = "https://firebasestorage.googleapis.com/v0/b/afika-nyati-website.appspot.com/o/resume%2Fafika.jpg?alt=media&token=f1d32c1d-07b4-48b0-abf9-2200290645c5"

// MARK: - ViewController

class ViewController: UIViewController, SFSpeechRecognitionTaskDelegate, PitchEngineDelegate {
    
    // MARK: - Outlets
    @IBOutlet weak var wakeWordLabel: UILabel!
    @IBOutlet weak var wakeWordSubtitleLabel: UILabel!
    @IBOutlet weak var transcriptionText: UITextView!
    @IBOutlet weak var playAudioButton: UIButton!
    @IBOutlet weak var playTextToSpeechButton: UIButton!
    @IBOutlet weak var recordingButton: UIButton!
    @IBOutlet weak var soundIntensityIndicatorHeight: NSLayoutConstraint!
    
    // MARK: - General Properties
    var appActivated = false
    var useOnDeviceRecognition = DEFAULT_USE_ON_DEVICE_RECOGNITION
    var numAppSessions = 0
    let wakePhrase = "rise and shine"
    var isListeningForVolume = false
    var UITimer: Timer?
    var savedMessageTimer: Timer?
    var volumeListeningRateTimer: Timer?
    var stopListeningForVolumeTimer: Timer?
    var onExpressionListenUpdate: (() -> Void)?
    var onExpressionEchoFinish: (() -> Void)?
    var onExpressionEchoUpdate: ((_ range: NSRange) -> Void)?
    var onExpressionListenStop: (() -> Void)?
    var onExpressionComplete: (() -> Void)?
    static let PLAY_EXPRESSION_LABEL = "Play Expression"
    static let PAUSE_EXPRESSION_LABEL = "Pause Expression"
    static let PLAY_ECHO_LABEL = "Play Echo"
    static let PAUSE_ECHO_LABEL = "Pause Echo"
    static let START_EXPRESSION_LABEL = "Start Expression"
    static let STOP_EXPRESSION_LABEL = "Stop Expression"
    
    // MARK: - General Audio Properties
    @objc dynamic var session = AVAudioSession.sharedInstance()
    lazy var expression: Expression = {
        return self.createNewExpression()
    }()
    var tempExpression: Expression?
    
    // MARK: - Speech Recognition Properties
    var audioEngine = AVAudioEngine()
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    var request: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    
    // MARK: - Recording Properties
    let recordBus = 0
    lazy var pitchEngine: PitchEngine = { [weak self] in
        let config = Config(
            bufferSize: 1024,
            estimationStrategy: .yin
        )
        let pitchEngine = PitchEngine(config: config, delegate: self)
        pitchEngine.levelThreshold = minPower
        return pitchEngine
    }()
    private var soundIntensityStream = [SoundIntensityDatum]()
    private var pitchStream = [PitchDatum]()
    
    // MARK: - Speech Synthesis Properties
    let speechSynthesizer = AVSpeechSynthesizer()
    var synthesizerVoice : AVSpeechSynthesisVoice?
    
    // MARK: - Pitch Recognition Properties
    let minPower: Float = -160.0
    
    // MARK: - ViewController Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure app
        requestPermissions()
        
        // Set up Audio Session
        configureAudioSession()
        
        // Set up notification observers
        configureNotificationObservers()
        
        // Set up expression handlers
        configureExpressionHandlers()

        // App Visits
        configureAppVisits()

        // Prepare UI
        setActiveUI(as: false)
        wakeWordLabel.text = "\"\(wakePhrase.capitalizeFirstLetter())\""
        
        // Start listening for wake word
        configureListeningForWakePhrase()
        
        session.addObserver(
            self, forKeyPath: #keyPath(AVAudioSession.outputVolume),
            options: [.old, .new],
            context: nil
        )
    }
    
    // MARK: - Inactive
    func activateApp() {
        appActivated = true
        setActiveUI(as: true)
        
        // clear pitch and volume streams
        self.pitchStream = [PitchDatum]()
        self.soundIntensityStream = [SoundIntensityDatum]()

        // start listening for voice commands
        expression.startListeningForVoiceCommands(
            soundIntensityHandler: { power in
                if let power = power {
                    DispatchQueue.main.async {
                        let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                        let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                        self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                    }
                }
            }
        )
    }
    
    // MARK: - Setup
    
    func configureListeningForWakePhrase() {
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if authStatus != .authorized {
            let alertController = UIAlertController(title: "Speech Recognition Permission Denied", message: "Please grant permission for application to initiate speech transcription.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Grant Permission", style: .default) { [unowned self] action in
                self.requestPermissions()
            })
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alertController, animated: true)
        } else {
            // pitch engine used to determine if user is male or female
            startListeningForWakePhrase()
            print("===== Listening for Wake Phrase =====")
        }
    }
    
    func configureAudioSession() {
        session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker, .duckOthers])
            try session.setActive(true)
        } catch let error as NSError {
            print("===== There was an error requesting permissions to record audio or setting session category: \(error.localizedDescription) =====")
        } catch {
            print("===== There was an error requesting permissions to record audio or setting session category =====")
        }
    }
    
    @objc func handleAudioSessionRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
        }

        // Switch over the route change reason.
        switch reason {
        case .newDeviceAvailable: // New device found.
            print("===== New Audio Device Found =====")
            // Reset listening for wake word
            DispatchQueue.main.async {
                if !self.appActivated {
                    self.stopListeningForWakePhrase() {[weak self] in
                        self?.configureListeningForWakePhrase()
                    }
                } else {
                    // Re-initiate Audio Engine to mend broken graph
                    self.audioEngine = AVAudioEngine()
                }
            }
        case .oldDeviceUnavailable: // Old device removed.
            print("===== Old Audio Device Removed =====")
            // Reset listening for wake word
            DispatchQueue.main.async {
                if !self.appActivated {
                    self.stopListeningForWakePhrase() {[weak self] in
                        self?.configureListeningForWakePhrase()
                    }
                } else {
                    // Re-initiate Audio Engine to mend broken graph
                    self.audioEngine = AVAudioEngine()
                }
            }
        default: ()
        }
    }
    
    @objc func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
        }

        // Switch over the interruption type.
        switch type {
        case .began:
            print("===== Audio Session Interruption Begun =====")
        case .ended:
           // An interruption ended. Resume playback, if appropriate.
            print("===== Audio Session Interruption Ended =====")
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // Interruption ended. Playback should resume.
                print("TODO: Resume Playback")
            } else {
                // Interruption ended. Playback should not resume.
                print("TODO: Do not resume Playback")
            }

        default: ()
        }
    }
    
    @objc func handleSecondaryAudio(notification: Notification) {
        // Determine hint type
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
            let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue) else {
                return
        }
        
        if type == .begin {
            // Other app audio started playing - mute secondary audio.
            print("===== Other app audio started playing - mute secondary audio =====")
        } else {
            // Other app audio stopped playing - restart secondary audio.
            print("==== Other app audio stopped playing - restart secondary audio. =====")
        }
    }
    
    func configureAppVisits() {
        let defaults = UserDefaults.standard
        
        if let savedAppSessions = defaults.object(forKey: "numAppSessions") as? Data {
            let jsonDecoder = JSONDecoder()
            do {
                numAppSessions = try jsonDecoder.decode(Int.self, from: savedAppSessions)
                incrementAppSessions()
            } catch {
                print("====== Error loading app session count =====")
            }
        } else if numAppSessions == 0 {
            incrementAppSessions()
        }
    }
    
    func incrementAppSessions() {
        let defaults = UserDefaults.standard
        numAppSessions += 1
        
        // Save App Sessions
        let jsonEncoder = JSONEncoder()
        if let updatedAppSessions = try? jsonEncoder.encode(numAppSessions) {
            defaults.set(updatedAppSessions, forKey: "numAppSessions")
        }
    }
    
    func configureExpressionHandlers() {
        self.onExpressionListenUpdate = {[weak self] in
            DispatchQueue.main.async {
                self?.updateUIText()
            }
        }
        
        self.onExpressionEchoFinish = {[weak self] in
            DispatchQueue.main.async {
                self?.updateUIText()
                if (!self!.playTextToSpeechButton.isHidden) {
                    self?.playTextToSpeechButton.setTitle(ViewController.PLAY_ECHO_LABEL, for: .normal)
                }
                
                if !self!.appActivated {
                    self?.appActivated = true
                }
            }
        }
        
        self.onExpressionEchoUpdate = {[weak self] range in
            DispatchQueue.main.async {
                self?.updateUIText(range: range)
            }
        }
        
        self.onExpressionListenStop = {[weak self] in
            DispatchQueue.main.async {
                self?.updateUIText()
                self?.recordingButton.setTitle(ViewController.START_EXPRESSION_LABEL, for: .normal)
                self?.setAudioButtonsVisibility(visible: true)
                self?.stopRecordingUITimer()
                self?.soundIntensityIndicatorHeight.constant = 0
            }
        }
        
        self.onExpressionComplete = {[weak self] in
            DispatchQueue.main.async {
                self?.stopRecordingUITimer()
                self?.soundIntensityIndicatorHeight.constant = 0

                self?.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Reset", style: .plain, target: self, action: #selector(self?.resetSession))
                self?.navigationItem.title = "Saved!"
                self?.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.red]
                
                self?.savedMessageTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { timer in
                    self?.navigationItem.title = ""
                    self?.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
                }
            }
        }
    }
    
    @objc func resetSession() {
        print("===== Reset Session =====")
        setAudioButtonsVisibility(visible: false)
        self.transcriptionText.attributedText = NSMutableAttributedString(string: "")
        self.navigationItem.rightBarButtonItem = nil
        self.savedMessageTimer?.invalidate()
        
        if expression.isPlayingEcho {
            expression.stopEcho(handler: onExpressionEchoFinish)
        }
        
        if expression.isPlayingExpression {
            expression.stop()
        }
        
        if expression.isListeningForCommands || expression.isListeningForSpeech {
            expression.stopListeningForSpeech() {
                self.expression = self.createNewExpression()
                self.expression.startListeningForVoiceCommands(
                    soundIntensityHandler: { power in
                        if let power = power {
                            DispatchQueue.main.async {
                                let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                                let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                                self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                            }
                        }
                    }
                )
            }
        } else {
            self.expression = self.createNewExpression()
        }
    }
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization {
            [unowned self] (authStatus) in
            DispatchQueue.main.async {
                self.recordingButton.isEnabled = false
                switch authStatus {
                case .authorized:
                    self.recordingButton.isEnabled = true
                    print("===== Speech recognition permission granted =====")
                case .denied:
                    print("===== Speech recognition permission denied =====")
                case .restricted:
                    print("===== Speech recognition not available on device =====")
                case .notDetermined:
                    print("===== Speech recognition not determined =====")
                @unknown default:
                    print("===== Unknown permission state received: \(authStatus) =====")
                }
            }
        }
        
        session.requestRecordPermission() {
            allowed in
            DispatchQueue.main.async {
                if allowed {
                    print("===== Permission to record audio granted =====")
                } else {
                    print("===== Permission to record audio denied =====")
                    // Consider hiding your playback button
                }
            }
        }
    }
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
        notificationCenter.addObserver(
            self,
            selector: #selector(appGainsFocus),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(appLosesFocus),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(appMovedToBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(appMovedToForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleSecondaryAudio),
            name: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: nil
        )
    }
    
    func createNewExpression() -> Expression {
        Expression(
            vc: self,
            filename: "expression-\(UUID().uuidString)",
            speaker: Speaker(name: "Afika Nyati", avatarURL: URL(string: AVATAR_URL)!, vc: self),
            minPower: minPower,
            withOnDeviceRecognition: useOnDeviceRecognition,
            withTemporalSuggestions: false,
            withPunctuationSuggestions: true,
            withFormattingSuggestions: true,
            withTextStrictlyAsWords: false,
            onListenUpdate: onExpressionListenUpdate,
            onListenStop: onExpressionListenStop,
            onEchoUpdate: onExpressionEchoUpdate,
            onEchoFinish: onExpressionEchoFinish,
            onExpressionComplete: onExpressionComplete
        )
    }
    
    @objc func appGainsFocus() {
        print("===== App Gains Focus =====")
    }
    
    @objc func appLosesFocus() {
        print("===== App Lost Focus =====")
        // Will occur when open control center
    }
    
    @objc func appMovedToBackground() {
        print("===== App Moved to Background =====")
        DispatchQueue.main.async {
            if !self.appActivated {
                self.stopListeningForWakePhrase()
            }
            
            // keep recording outside of app if expression started
            if !self.expression.isListeningForSpeech {
                self.appActivated = false
                self.setActiveUI(as: false)
            }
        }
    }
    
    @objc func appMovedToForeground() {
        print("===== App Moved to Foreground =====")
        DispatchQueue.main.async {
            if !self.appActivated {
                self.configureListeningForWakePhrase()
            }
        }
    }
    
    @objc func appWillTerminate() {
        print("===== App Will Terminate =====")
        if !self.appActivated {
            self.stopListeningForWakePhrase()
        } else if expression.isListeningForSpeech {
            self.expression.stopListeningForSpeech() {[weak self] in
                self?.onExpressionListenStop!()
            }
        }
    }
    
    // MARK: - View Actions

    @IBAction func recordButtonTapped(_ sender: Any) {
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if session.recordPermission != .granted || authStatus != .authorized {
            let alertController = UIAlertController(title: "Speech Recognition Permission Denied", message: "Please grant permission for application to initiate speech transcription.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Grant Permission", style: .default) { [unowned self] action in
                self.requestPermissions()
            })
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alertController, animated: true)
            return
        }
        
        if authStatus == .authorized && session.recordPermission == .granted {
            if !expression.isListeningForSpeech {
                print("===== Start Recording =====")
                recordingButton.setTitle(ViewController.STOP_EXPRESSION_LABEL, for: .normal)
                self.savedMessageTimer?.invalidate()
                expression.startListeningForSpeech(soundIntensityHandler: { power in
                    if let power = power {
                        DispatchQueue.main.async {
                            let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                            let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                            self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                        }
                    }
                }, onStartHandler: {
                    self.startRecordingUITimer(recording: true)
                })
            } else {
                print("===== Stop Recording =====")
                expression.stopListeningForSpeech() {[weak self] in
                    self?.onExpressionListenStop!()
                    self?.expression.startListeningForVoiceCommands(
                        soundIntensityHandler: { power in
                            if let power = power {
                                DispatchQueue.main.async {
                                    let height = CGFloat(Utils.normalizedPower(power: power, minPower: self!.minPower)) * self!.view.safeAreaLayoutGuide.layoutFrame.height
                                    let soundIntensityHeight: CGFloat = CGFloat(min(height, self!.view.safeAreaLayoutGuide.layoutFrame.height))
                                    self?.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    @IBAction func playButtonTapped(_ sender: Any) {
        if expression.isPlayingExpression {
            expression.pause() { [weak self] in
                DispatchQueue.main.async {
                    self?.playAudioButton.setTitle(ViewController.PLAY_EXPRESSION_LABEL, for: .normal)
                }
            }
        } else {
            expression.play(
                onStartHandler: { [weak self] in
                    // print("Successfully executed playback on start handler")
                    DispatchQueue.main.async {
                        self?.playAudioButton.setTitle(ViewController.PAUSE_EXPRESSION_LABEL, for: .normal)
                    }
                },
                secondElapseHandler: { [weak self] in
                    // print("Successfully executed playback second elapsed handler")
                    DispatchQueue.main.async {
                        self?.navigationItem.title = Utils.formattedTime(time: Float((self!.expression.player.currentTime().seconds)))
                    }
                },
                segmentBoundaryHandler: { [weak self] in
                    // print("Successfully executed playback on segment boundary handler")
                    DispatchQueue.main.async {
                        if let segment = self?.expression.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let range = self?.expression.getSegmentTextRange(of: segment) {
                            self?.updateUIText(range: range)
                        }
                    }
                }, onFinishHandler: { [weak self] in
                    // print("Successfully executed playback on finish handler")
                    DispatchQueue.main.async {
                        self?.updateUIText()
                        self?.playAudioButton.setTitle(ViewController.PLAY_EXPRESSION_LABEL, for: .normal)
                        self!.expression.player.replaceCurrentItem(with: nil)
                        self?.navigationItem.title = ""
                    }
                }
            )
        }
    }
    
    @IBAction func speechToTextButtonTapped(_ sender: Any) {
        if expression.echoIsPaused {
            print("==== Speech synthesizer continue speaking =====")
            expression.startEcho(onStartHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.playTextToSpeechButton.setTitle(ViewController.PAUSE_ECHO_LABEL, for: .normal)
                }
            })
        } else if expression.isPlayingEcho {
            print("==== Speech synthesizer paused =====")
            expression.pauseEcho() { [weak self] in
                DispatchQueue.main.async {
                    self?.playTextToSpeechButton.setTitle(ViewController.PLAY_ECHO_LABEL, for: .normal)
                }
            }
        } else {
            playAudioButton.setTitle(ViewController.PLAY_EXPRESSION_LABEL, for: .normal)
            expression.startEcho(onStartHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.navigationItem.title = ""
                    self?.playTextToSpeechButton.setTitle(ViewController.PAUSE_ECHO_LABEL, for: .normal)
                }
            })
        }
    }
    
    // MARK: - View Methods
    
    func setAudioButtonsVisibility(visible: Bool) {
        playAudioButton.isHidden = !visible
        playAudioButton.isEnabled = visible
        playTextToSpeechButton.isHidden = !visible
        playTextToSpeechButton.isEnabled = visible
    }
    
    func setActiveUI(as visible: Bool) {
        transcriptionText.isHidden = !visible
        recordingButton.isHidden = !visible
        recordingButton.isEnabled = visible
        wakeWordSubtitleLabel.isHidden = visible
        wakeWordLabel.isHidden = visible
        
        if !visible {
            playAudioButton.isHidden = true
            playAudioButton.isEnabled = false
            playTextToSpeechButton.isHidden = true
            playTextToSpeechButton.isEnabled = false
        }
    }
    
    func updateUIText(range: NSRange? = nil) {
        let text = expression.getExpressionText()
        
        if text.count == 0 {
            return
        }
        
        if let range = range {
            let mutableAttributedString = NSMutableAttributedString(string: text)
            mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.white, range: range)
            mutableAttributedString.addAttribute(.backgroundColor, value: UIColor.red, range: range)
            transcriptionText.attributedText = mutableAttributedString
            transcriptionText.font = UIFont.systemFont(ofSize: 18.0)
        } else {
            let mutableAttributedString = NSMutableAttributedString(string: text)
            transcriptionText.attributedText = mutableAttributedString
            transcriptionText.font = UIFont.systemFont(ofSize: 18.0)
        }
    }
    
    /**
        Presents timer to view.

        - Parameter recording: Whether the timer should be set to be a recording.
    */
    func startRecordingUITimer(recording: Bool) {
        DispatchQueue.main.async {
            if recording {
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.red]
            }
            
            self.navigationItem.title = Utils.formattedTime(time: self.expression.getDurationListening())
            self.UITimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                self.navigationItem.title = Utils.formattedTime(time: self.expression.getDurationListening())
            }
        }
    }
    
    /**
        Removes timer from view.
    */
    func stopRecordingUITimer() {
        DispatchQueue.main.async {
            self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
            self.navigationItem.title = ""
            self.UITimer!.invalidate()
        }
    }
    
    // MARK: - Wake Phrase Methods
    
    func startListeningForWakePhrase() {
        print("===== Starting Listening for Wake Phrase =====")
        
        // Play Sound
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
            soundEngine.startListening()
        }
        
        // must be placed before we start listening for wake phrase
        // if pitch engine begins first, we are for some reason unable to do speech recognition
        pitchEngine.start()
        
        if recognitionTask != nil {
            recognitionTask?.finish()
            recognitionTask = nil
        }

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: recordBus)
        print("===== Sample Rates ===== \n\tSoftware Format: \(recordingFormat.sampleRate)\n\tHardware Format: \(AVAudioSession.sharedInstance().sampleRate)")

        request = SFSpeechAudioBufferRecognitionRequest()
        request!.shouldReportPartialResults = true
        request!.requiresOnDeviceRecognition = false
        
        node.installTap(onBus: recordBus, bufferSize: 1024, format: recordingFormat) { [unowned self] (buffer, _) in
            self.request!.append(buffer)
            
            DispatchQueue.main.async {
                let power = Utils.computeSoundIntensity(buffer: buffer)
                if let power = power {
                    let soundIntensityDatum = SoundIntensityDatum(date: Date(), power: power)
                    self.soundIntensityStream.append(soundIntensityDatum)
                    let soundIntensityHeight = CGFloat(min((CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height), self.view.safeAreaLayoutGuide.layoutFrame.height))
                    self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch let error {
            print("[Error] There was a problem starting speech recognition: \(error.localizedDescription)")
        }
        
        guard let myRecognizer = SFSpeechRecognizer() else {
            print("===== Speech Recognizer is not supported for current locale =====")
            return
        }
        
        if useOnDeviceRecognition && myRecognizer.supportsOnDeviceRecognition {
            print("===== Using On-Device Recognition =====")
            request!.requiresOnDeviceRecognition = true
        }
        
        if !myRecognizer.isAvailable {
            print("===== Speech Recognizer is not available =====")
            return
        }
        
        speechRecognizer?.defaultTaskHint = .dictation
        recognitionTask = speechRecognizer?.recognitionTask(with: request!, delegate: self)
    }
    
    func stopListeningForWakePhrase(onStopHandler: (() -> Void)? = nil) {
        print("===== Stopping Listening for Wake Phrase =====")
        
        let node = audioEngine.inputNode
        node.removeTap(onBus: self.recordBus)

        audioEngine.stop()
        // We instantiate new audio engine in case headphones have been added or removed
        // Removing an audio node will create a broken graph: https://developer.apple.com/documentation/avfoundation/avaudioengine
        audioEngine = AVAudioEngine()
        
        // When this is not in the main thread, the recognition task doesn't end correctly
        // which prevents us from receiving the final transcription.
        DispatchQueue.main.async {
            self.soundIntensityIndicatorHeight.constant = 0
            self.recognitionTask!.finish() // don't wrap in if statement because it is sometimes not .running
            self.request!.endAudio() // don't add a request = nil because it results in request not being there sometimes.
            self.pitchEngine.stop()
            onStopHandler?()
        }
    }
    
    // MARK: - Volume Adjuster Methods
    
    func startListeningForVolume() {
        print("===== Starting Listening for Volume =====")
        print("volume: ", AVAudioSession.sharedInstance().outputVolume)
        // set listening flag to true
        
        
        // Play Sound
        soundEngine.startListening()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
            soundEngine.startProcessing()
        }
        
        // clear pitch and sound intensity streams
        self.pitchStream = [PitchDatum]()
        self.soundIntensityStream = [SoundIntensityDatum]()
        
        // must be placed before we start listening for wake phrase
        // if pitch engine begins first, we are for some reason unable to do speech recognition
        pitchEngine.start()

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: recordBus)
        
        node.installTap(onBus: recordBus, bufferSize: 1024, format: recordingFormat) { [unowned self] (buffer, _) in
            DispatchQueue.main.async {
                if !self.isListeningForVolume {
                    self.isListeningForVolume = true
                    self.stopListeningForVolumeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { timer in
                        self.stopListeningForVolume() {
                            self.expression.startListeningForVoiceCommands(
                                soundIntensityHandler: { power in
                                    if let power = power {
                                        DispatchQueue.main.async {
                                            let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                                            let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                                            self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                                        }
                                    }
                                }
                            )
                        }
                    }
                }

                let power = Utils.computeSoundIntensity(buffer: buffer)
                if let power = power {
                    let soundIntensityDatum = SoundIntensityDatum(date: Date(), power: power)
                    self.soundIntensityStream.append(soundIntensityDatum)
                    let soundIntensityHeight = CGFloat(min((CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height), self.view.safeAreaLayoutGuide.layoutFrame.height))
                    self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                    
                    if soundIntensityDatum.power > self.getBackgroundNoise() + Utils.TALKING_POWER_DELTA && self.isListeningForVolume && self.stopListeningForVolumeTimer != nil {
                        // continue if power still coming through
                        self.stopListeningForVolumeTimer?.invalidate()
                        self.stopListeningForVolumeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { timer in
                            if self.stopListeningForVolumeTimer != nil {
                                self.stopListeningForVolume() {
                                    self.expression.startListeningForVoiceCommands(
                                        soundIntensityHandler: { power in
                                            if let power = power {
                                                DispatchQueue.main.async {
                                                    let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                                                    let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                                                    self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch let error {
            print("[Error] There was a problem starting speech recognition: \(error.localizedDescription)")
        }
    }
    
    func stopListeningForVolume(onStopHandler: (() -> Void)? = nil) {
        print("===== Stopping Listening for Volume =====")

        // Play Sound
        soundEngine.stopProcessing()
        soundEngine.stopListening()
    
        
        
        let node = audioEngine.inputNode
        node.removeTap(onBus: self.recordBus)

        audioEngine.stop()
        // We instantiate new audio engine in case headphones have been added or removed
        // Removing an audio node will create a broken graph: https://developer.apple.com/documentation/avfoundation/avaudioengine
        audioEngine = AVAudioEngine()

        DispatchQueue.main.async {
            self.soundIntensityIndicatorHeight.constant = 0
            self.isListeningForVolume = false
            self.stopListeningForVolumeTimer = nil
            self.pitchEngine.stop()
            print("volume: ", AVAudioSession.sharedInstance().outputVolume)
            onStopHandler?()
        }
    }
    
    // MARK: - Getters
    
    func getBackgroundNoise() -> Double {
        var numDatum: Double = 0
        
        var backgroundNoiseSum: Double = 0

        for datum in self.soundIntensityStream {
            if datum.power != -Double.infinity {
                backgroundNoiseSum += datum.power
                numDatum += 1
            }
        }
        
        if numDatum == 0 {
            return Double.infinity
        }
        
        return backgroundNoiseSum / numDatum
    }
    
    func getPitch() -> Double {
        let numPitches: Double = Double(self.pitchStream.count)
        
        if numPitches == 0 {
            return Utils.UNKNOWN
        }
        var pitchSum: Double = 0

        for datum in self.pitchStream {
            pitchSum += datum.pitch.frequency
        }
        
        return pitchSum / numPitches
    }
    
    // MARK: - Key-Value Observer
    
    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(AVAudioSession.outputVolume) {
            print("Output Volume Changed!!!JSK!!!!! ")

            var outputVolume: Float
            if let volume = change?[.oldKey] as? Float {
                outputVolume = volume
                print("\told volume: ", outputVolume)
            } else {
                outputVolume = -1
                print("\told volume: ", outputVolume)
            }
            // Get the status change from the change dictionary
            if let volume = change?[.newKey] as? Float {
                outputVolume = volume
                print("\tnew volume: ", outputVolume, session.outputVolume)
            } else {
                outputVolume = -1
                print("\tnew volume: ", outputVolume, session.outputVolume)
            }
        }
    }
    
    // MARK: - Speech Recognizer Task Delegates
    
    func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {
        print("===== System is no longer accepting new speech input =====")
    }
    
    func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {
        print("===== Application cancelled looking for wake phrase ===== ")
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
         print("===== Application successfully finished looking for wake phrase ===== ")
        if !self.appActivated && !DEFAULT_USE_ON_DEVICE_RECOGNITION {
            print("===== Restart Listening and continue to look for wake phrase =====")
            self.stopListeningForWakePhrase() {[weak self] in
                self?.configureListeningForWakePhrase()
            }
        }
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        // print("===== New or updated transcription segments received =====")
        
        DispatchQueue.main.async {
            if !self.appActivated && !self.speechSynthesizer.isSpeaking {
                var text = ""
                for segment in transcription.segments {
                    text += " \(segment.substring)"
                }
                
                text = text.lowercased()
                if text.contains(self.wakePhrase) { // wake word/phrase needs to be two words to get pitch data
                    self.stopListeningForWakePhrase()
                    // Play Sound
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        soundEngine.correctWakePhrase()
                    }
                    
                    print("===== Wake Phrase Detected =====")
                    self.activateApp()
                } else if !text.contains("rise") && !text.contains("rise and") {
                    // Play Sound
                    soundEngine.incorrectWakePhrase()
                }
                
                return
            }
        }
    }
    
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition result: SFSpeechRecognitionResult) {
        DispatchQueue.main.async {
            if !self.appActivated {
                var text = ""
                for segment in result.bestTranscription.segments {
                    text += " \(segment.substring)"
                }
                
                text = text.lowercased()
                if text.contains(self.wakePhrase) {
                    self.stopListeningForWakePhrase()
                } else if !self.speechSynthesizer.isSpeaking && DEFAULT_USE_ON_DEVICE_RECOGNITION {
                    // Should not go here when we've said wake phrase but the if-statement doesn't return true.
                    // Happens when there's another equally viable option for what sounds like the wake phrase.
                    // or put alternatively, the hypothesized transcript is the wake phrase while the final transcript is a homophone.
//                    print("===== Restart Listening and continue to look for wake phrase =====")
//                    self.stopListeningForWakePhrase() {[weak self] in
//                        self?.configureListeningForWakePhrase()
//                    }
                }

                return
            }
        }
    }
    
    func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        print("===== System has detected first incident of speech input =====")
    }
    
    // MARK: - Speech Synthesizer Delegates
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("===== Speech synthesis was cancelled =====")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("===== Paused speech synthesis successfully instructed to continue =====")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully completed =====")
        updateUIText()
        if (!playTextToSpeechButton.isHidden) {
            playTextToSpeechButton.setTitle(ViewController.PLAY_ECHO_LABEL, for: .normal)
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully paused =====")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully started =====")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        if appActivated {
            updateUIText(range: characterRange)
        }
    }
    
    // MARK: - Pitch Recognition Delegates
    func pitchEngine(_ pitchEngine: PitchEngine, didReceivePitch pitch: Pitch) {
        // TODO: Timing
        
        if let lastSoundIntensity = self.soundIntensityStream.last, pitch.frequency >= MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.getBackgroundNoise() != Double.infinity && self.soundIntensityStream.count > MIN_SEED_INTENSITY_POINTS && lastSoundIntensity.power > self.getBackgroundNoise() + Utils.TALKING_POWER_DELTA {
            // Add to pitch stream
            let pitchDatum = PitchDatum(date: Date(), pitch: pitch)
            self.pitchStream.append(pitchDatum)
            
            // Set speaker pitch
            if !self.appActivated {
                do {
                    
                    if expression.speaker.pitch == nil {
                        print("===== Base vocal frequency detected =====")
                        // when uncommented, it stops system from hearing wake phrase
//                        let rate: Float = 0.5
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
                    expression.setSpeakerPitch(to: avgPitch)
                } catch {
                    fatalError("===== [Error] There was a problem calculating average pitch =====")
                }
            }
        }
        
        if let lastSoundIntensity = self.soundIntensityStream.last, pitch.frequency >= MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.getBackgroundNoise() != Double.infinity && self.soundIntensityStream.count > 0 && lastSoundIntensity.power > self.getBackgroundNoise() + Utils.VOLUME_POWER_DELTA {
            // print("power: ", lastSoundIntensity.power, self.getBackgroundNoise(), Utils.VOLUME_POWER_DELTA)
            if self.isListeningForVolume && self.volumeListeningRateTimer == nil {
                
                Utils.setMainVolume(to: Float(Utils.normalizePitch(incidentPitch: pitch, basePitch: self.expression.speaker.pitch!)))
                // MAKE SURE TO ALSO CHANGE VOLUME OF SOUND EFFECTS
                self.volumeListeningRateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { timer in
                    self.volumeListeningRateTimer = nil
                    // 0.2 interval seems good
                }
            }
        }
    }

    func pitchEngine(_ pitchEngine: PitchEngine, didReceiveError error: Error) {
        //print("===== Pitch Error: \(error.localizedDescription)")
    }

    public func pitchEngineWentBelowLevelThreshold(_ pitchEngine: PitchEngine) {
        // print("===== Pitch Engine below level threshold =====")
    }
}

// List of tests:

// Useful Resources:
// Viewing App Storage on Device: https://stackoverflow.com/questions/15219511/theres-a-way-to-access-the-document-folder-in-iphone-ipad-real-device-no-simu
// Debugging EXC_BAD_ACCESS: https://code.tutsplus.com/tutorials/what-is-exc_bad_access-and-how-to-debug-it--cms-24544

// ====== Before Wake Phrase =====
// +++++ On-server recognition
// +++++ With and without headphones
// TODO: set useOnDeviceRecognition = false
//
// 1) No words
// Instructions: Open app and wait a minute without saying a word.
// Expected result: Console should continue listening for wake phrase
//
// 2) Some words
// Instructions: Open app and say words, but not the wake phrase
// Expected result: Console should continue listening for wake phrase
//
// 3) No words before a minute. Wake phrase after a minute
// Instructions: Only run if test #1 and #2 pass. Open app. Say wake phrase after a minute.
// Expected result: App should activate.
//
// 4) Some words before a minute. Wake phrase after a minute
// Instructions: Only run if test #1 and #2 pass. Open app and say words, but not the wake phrase. Say wake phrase after a minute.
// Expected result: App should activate.
//
// +++++ On-device recognition
// +++++ With and without headphoness
// TODO: set useOnDeviceRecognition = true
//
// 5) No words
// Instructions: Open app and wait a minute without saying a word.
// Expected result: Console should continue listening for wake phrase
//
// 6) Some words
// Instructions: Open app and say words, but not the wake phrase
// Expected result: Console should continue listening for wake phrase
//
// 7) No words before a minute. Wake phrase after a minute
// Instructions: Only run if test #1 and #2 pass. Open app. Say wake phrase after a minute.
// Expected result: App should activate.
//
// 8) Some words before a minute. Wake phrase after a minute
// Instructions: Only run if test #1 and #2 pass. Open app and say words, but not the wake phrase. Say wake phrase after a minute.
// Expected result: App should activate.
//
// ===== After Wake Phrase =====
// 9) Move to Background / Move to Foreground resets Wake Phrase
// Instructions: Open app. Say wake phrase. Go to Home screen and return to app.
// Expected Result: App should be inactive and listening for wake phrase
//
// +++++ On-server recognition
// +++++ With and without headphoness
// TODO: set useOnDeviceRecognition = true
//
// 10) No words for a minute
// Instructions: Open app. Say wake phrase. Start expression. Wait a minute without saying a word. Say words after a minute.
// Expected Result: No words should be transcribed before a minute. Words shold be transcribed after a minute. Session should be fluid.
//
// 11) Some words in a minute. More words after.
// Instructions: Open app. Say wake phrase. Start expression. Say some words before a minute. Say more words after a minute.
// Expected Result: Some words should be transcribed before a minute. More words should be stranscribed after a minute. Session should be fluid. The timestamps should be accurate for each word.
//
// +++++ On-device recognition
// +++++ With and without headphoness
// TODO: set useOnDeviceRecognition = true
//
// 12) No words for a minute
// Instructions: Open app. Say wake phrase. Start expression. Wait a minute without saying a word. Say words after a minute.
// Expected Result: No words should be transcribed before a minute. Words shold be transcribed after a minute. Session should be fluid.
//
// 13) Some words in a minute. More words after.
// Instructions: Open app. Say wake phrase. Start expression. Say some words before a minute. Say more words after a minute.
// Expected Result: Some words should be transcribed before a minute. More words should be stranscribed after a minute. Session should be fluid. The timestamps should be accurate for each word.
//
// 14) Spaced out audio while using on-device recognition
// Instructions: Speak out an expression with at least five seconds of silence between each word
// Expected result: On playback, the silences should be removed and the focus word on screen should be aligned with the word being uttered.
//
// 15) Test Punctuation Suggestion: Ignore Adjective
// Instructions: Utter the following: "This is a beautiful". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Utter "home".
// Expected Result: There should not be a new paragraph created between 'beautiful' and 'home'.
//
// 16) Test Punctuation Suggestion: End on Adjective
// Instructions: Utter the following: "This is beautiful". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. "you are the best".
// Expected Result: There should be a new paragraph created between "This is beautiful" and "you are the best". "You" should be capitalized and there should be no leading space on second sentence
// Warning: Sometimes the transcript returns back a starting time for "you" that happens well before it is uttered. There is no control of this unfortunately
//
// 17) Test Punctuation Suggestion: End on Negative Adjective
// Instructions: Utter the following: "This is not beautiful". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. "you are the word".
// Expected Result: There should be a new paragraph created between "This is not beautiful" and "you are the worst". "You" should be capitalized and there should be no leading space on second sentence
// Warning: Sometimes the transcript returns back a starting time for "you" that happens well before it is uttered. There is no control of this unfortunately
//
// 18) Test Punctuation Suggestion: End on Negative Quantifier Adjective
// Instructions: Utter the following: "This is so beautiful". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. "Can I have it?". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds.
// Expected Result: There should be a new paragraph created between "This is not beautiful" and "Can I have it?". "Can" should be capitalized and there should be a question mark at the end of the sentence.
// Warning: Sometimes the transcript returns back a starting time for "can" that happens well before it is uttered. There is no control of this unfortunately
//
// 19) Test Punctuation and Temporal Suggestions Active
// Instructions: In createNewExpression() method, set 'withTemporalSuggestions' and 'withPunctuationSuggestions' to true. And open application
// Expected Result:  You should see a 'Conflicting View Modes' error dialog telling you it's selected punctuation suggestions.
//
// 20) Test Change Audio Inputs
// Instructions: Start the app without earphones connected. While on the Wake Phrase Screen, connect earphones. Utter wake phrase.
// Expected Result: The wake phrase should be registered without error
//
// 21) Test Play Sentence
//
// ===== Code Needed =====
// expression.playSentence(number: 1)
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Utter the following: "This is the first sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the second sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the third sentence".
// Expected Result: System should play back: "This is the second sentence".
//
// 22) Test Trim Expression: Permanent
//
// ===== Code Needed =====
//expression.trimExpression(keeping: expression.getSentenceDetails(number: 1)!.timeRange, permanent: true) {
//    self.expression.play(
//        onStartHandler: { [weak self] in
//            // print("Successfully executed playback on start handler")
//            DispatchQueue.main.async {
//                self?.playAudioButton.setTitle(PAUSE_EXPRESSION_LABEL, for: .normal)
//            }
//        },
//        secondElapseHandler: { [weak self] in
//            // print("Successfully executed playback secondT elapsed handler")
//            DispatchQueue.main.async {
//                self?.navigationItem.title = Utils.formattedTime(time: Float((self!.expression.player.currentTime().seconds)))
//            }
//        },
//        segmentBoundaryHandler: { [weak self] in
//            // print("Successfully executed playback on segment boundary handler")
//            if let segment = self?.expression.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let range = self?.expression.getSegmentTextRange(of: segment) {
//                self?.updateUIText(range: range)
//            }
//        }, onFinishHandler: { [weak self] in
//            // print("Successfully executed playback on finish handler")
//            DispatchQueue.main.async {
//                self?.updateUIText()
//                self?.playAudioButton.setTitle(PLAY_EXPRESSION_LABEL, for: .normal)
//                self!.expression.player.replaceCurrentItem(with: nil)
//                self?.navigationItem.title = ""
//            }
//        }
//    )
//}
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Utter the following: "This is the first sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the second sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the third sentence".
// Expected Result: System should play back: "This is the second sentence".
//
// 23) Test Trim Expression: Not Permanent
//
// ===== Code Needed =====
//expression.trimExpression(keeping: expression.getSentenceDetails(number: 1)!.timeRange, permanent: false) {
//    self.expression.play(
//        onStartHandler: { [weak self] in
//            // print("Successfully executed playback on start handler")
//            DispatchQueue.main.async {
//                self?.playAudioButton.setTitle(PAUSE_EXPRESSION_LABEL, for: .normal)
//            }
//        },
//        secondElapseHandler: { [weak self] in
//            // print("Successfully executed playback secondT elapsed handler")
//            DispatchQueue.main.async {
//                self?.navigationItem.title = Utils.formattedTime(time: Float((self!.expression.player.currentTime().seconds)))
//            }
//        },
//        segmentBoundaryHandler: { [weak self] in
//            // print("Successfully executed playback on segment boundary handler")
//            if let segment = self?.expression.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let range = self?.expression.getSegmentTextRange(of: segment) {
//                self?.updateUIText(range: range)
//            }
//        }, onFinishHandler: { [weak self] in
//            // print("Successfully executed playback on finish handler")
//            DispatchQueue.main.async {
//                self?.updateUIText()
//                self?.playAudioButton.setTitle(PLAY_EXPRESSION_LABEL, for: .normal)
//                self!.expression.player.replaceCurrentItem(with: nil)
//                self?.navigationItem.title = ""
//            }
//        }
//    )
//}
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Utter the following: "This is the first sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the second sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the third sentence".
// Expected Result: System should play back: "This is the second sentence".
//
// 24) Test Extract Sentence
//
// ===== Code Needed =====
//expression.extractSentence(number: 1) { sentence in
//    self.tempExpression = sentence
//    print(sentence?.getExpressionText() ?? "NIL")
//    sentence?.play(onFinishHandler: {
//        print("Finished sentence!")
//    })
//}
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Utter the following: "This is the first sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the second sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the third sentence".
// Expected Result: System should play back: "This is the second sentence".
//
// 25) Duplicate Expression
//
// ===== Code Needed =====
//expression.duplicate() {expression in
//    self.tempExpression = expression
//    self.tempExpression?.play() {
//        print("Finished Sentence!")
//    }
//}
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Record any expression.
// Expected Result: System should play back your expression.
//
// 26) Voice Commands
//
// Instructions: Open app and utter wake phrase. Start expression by uttering "Start Expression". Speak an expression. End expression by uttering "Stop Expression". Play expression by uttering "Play Expression".
// Expected Result: Your expression should playback *** without *** 'Stop Expression' in it.
//
//
