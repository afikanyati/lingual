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
    var UITimer: Timer?
    var savedMessageTimer: Timer?
    var onExpressionListenUpdate: (() -> Void)?
    var onExpressionEchoFinish: (() -> Void)?
    var onExpressionEchoUpdate: ((_ range: NSRange) -> Void)?
    var onExpressionComplete: (() -> Void)?
    
    // MARK: - General Audio Properties
    var recordingSession = AVAudioSession.sharedInstance()
    lazy var expression: Expression = {
        return Expression(
            vc: self,
            speaker: Speaker(name: "Afika Nyati", avatarURL: URL(string: AVATAR_URL)!, playbackVoice: AVSpeechSynthesisVoice.speechVoices()[0], gender: .male),
            minDb: minDb,
            withDeviceRecognition: useOnDeviceRecognition,
            withSpaceSuggestions: false,
            withPunctuationSuggestions: true,
            withFormattingSuggestions: true,
            withTextStrictlyAsWords: false,
            onListenUpdate: onExpressionListenUpdate,
            onEchoFinish: onExpressionEchoFinish,
            onEchoUpdate: onExpressionEchoUpdate,
            onExpressionComplete: onExpressionComplete
        )
    }()
    
    // MARK: - Speech Recognition Properties
    let audioEngine = AVAudioEngine()
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
        pitchEngine.levelThreshold = minDb
        return pitchEngine
    }()
    
    // MARK: - Speech Synthesis Properties
    let speechSynthesizer = AVSpeechSynthesizer()
    var synthesizerVoice : AVSpeechSynthesisVoice?
    
    // MARK: - Pitch Recognition Properties
    let minDb: Float = -160.0
    
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
    }
    
    // MARK: - Inactive
    func activateApp() {
        appActivated = true
        setActiveUI(as: true)
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
        recordingSession = AVAudioSession.sharedInstance()
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .spokenAudio, options: .allowBluetooth)
        } catch {
            print("===== There was an error requesting permissions to record audio or setting session category =====")
        }
    }
    
    @objc func handleRouteChange(notification: Notification) {
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
//                     self.stopSpeechRecognition()
//                     self.hello()
//                     self.configureListeningForWakePhrase()
                }
            }
        case .oldDeviceUnavailable: // Old device removed.
            print("===== Old Audio Device Removed =====")
            // Reset listening for wake word
            DispatchQueue.main.async {
                if !self.appActivated {
//                    self.stopSpeechRecognition()
//                    self.hello()
//                    self.configureListeningForWakePhrase()
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
    
    func hello() {
        if AVAudioSession.isHeadphonesConnected {
            for input in self.recordingSession.availableInputs! {
                if AVAudioSession.isHeadphonePortType(portType: input.portType) {
                    self.configureNotificationObservers()
                    do {
                        try self.recordingSession.setPreferredInput(input)
                    } catch {
                        print("===== Unable to change preferred input =====")
                    }
                    break
                }
            }
        } else {
            for input in self.recordingSession.availableInputs! {
                if !AVAudioSession.isHeadphonePortType(portType: input.portType) {
                    self.configureNotificationObservers()
                    do {
                        try self.recordingSession.setPreferredInput(input)
                    } catch {
                        print("===== Unable to change preferred input =====")
                    }
                    break
                }
            }
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
                    self?.playTextToSpeechButton.setTitle("Play Echo", for: .normal)
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
        
        self.onExpressionComplete = {[weak self] in
            DispatchQueue.main.async {
                self?.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Reset", style: .plain, target: self, action: #selector(self?.resetSession))
                self?.navigationItem.title = "Saved!"
                self?.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.red]
                
                self?
                    .savedMessageTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { timer in
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
        self.expression = Expression(
            vc: self,
            speaker: Speaker(name: "Afika Nyati", avatarURL: URL(string: AVATAR_URL)!, playbackVoice: AVSpeechSynthesisVoice.speechVoices()[0], gender: .male),
            minDb: minDb,
            withDeviceRecognition: useOnDeviceRecognition,
            withSpaceSuggestions: false,
            withPunctuationSuggestions: true,
            withFormattingSuggestions: true,
            withTextStrictlyAsWords: false,
            onListenUpdate: onExpressionListenUpdate,
            onEchoFinish: onExpressionEchoFinish,
            onEchoUpdate: onExpressionEchoUpdate,
            onExpressionComplete: onExpressionComplete
        )
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
        
        recordingSession.requestRecordPermission() {
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
            selector: #selector(handleRouteChange),
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
            
            if !self.expression.isListening {
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
        } else if expression.isListening {
            self.expression.stopListeningForSpeech() {[weak self] in
                DispatchQueue.main.async {
                    self?.stopRecordingUITimer()
                    self?.soundIntensityIndicatorHeight.constant = 0
                }
            }
        }
    }
    
    // MARK: - View Actions

    @IBAction func recordButtonTapped(_ sender: Any) {
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if recordingSession.recordPermission != .granted || authStatus != .authorized {
            let alertController = UIAlertController(title: "Speech Recognition Permission Denied", message: "Please grant permission for application to initiate speech transcription.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Grant Permission", style: .default) { [unowned self] action in
                self.requestPermissions()
            })
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alertController, animated: true)
            return
        }
        
        if authStatus == .authorized && recordingSession.recordPermission == .granted {
            if !expression.isListening {
                print("===== Start Recording =====")
                recordingButton.setTitle("Stop Expression", for: .normal)
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                navigationItem.leftBarButtonItem = UIBarButtonItem(customView: spinner)
                self.savedMessageTimer?.invalidate()
                expression.startListeningForSpeech(soundIntensityHandler: { intensity in
                    if let intensity = intensity {
                        DispatchQueue.main.async {
                            let height = CGFloat(intensity) * self.view.safeAreaLayoutGuide.layoutFrame.height
                            let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                            self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                        }
                    }
                }, onStartHandler: {
                    self.startRecordingUITimer(recording: true)
                })
            } else {
                print("===== Stop Recording =====")
                recordingButton.setTitle("Start Expression", for: .normal)
                navigationItem.leftBarButtonItem = nil
                setAudioButtonsVisibility(visible: true)
                expression.stopListeningForSpeech() {[weak self] in
                    DispatchQueue.main.async {
                        self?.stopRecordingUITimer()
                        self?.soundIntensityIndicatorHeight.constant = 0
                    }
                }
            }
        }
    }

    @IBAction func playButtonTapped(_ sender: Any) {
        if expression.isPlayingExpression {
            expression.pause() { [weak self] in
                self?.playAudioButton.setTitle("Play Audio", for: .normal)
            }
        } else {
            playTextToSpeechButton.setTitle("Play Echo", for: .normal)
            expression.play(
                onStartHandler: { [weak self] in
                    // print("Successfully executed playback on start handler")
                    DispatchQueue.main.async {
                        self?.playAudioButton.setTitle("Pause Audio", for: .normal)
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
                    if let segment = self?.expression.getSegment(type: .current), segment.getText().count > 0, let range = self?.expression.getSegmentTextRange(of: segment) {
                        self?.updateUIText(range: range)
                    }
                }, onFinishHandler: { [weak self] in
                    // print("Successfully executed playback on finish handler")
                    DispatchQueue.main.async {
                        self?.updateUIText()
                        self?.playAudioButton.setTitle("Play Audio", for: .normal)
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
            expression.continueEcho() { [weak self] in
                DispatchQueue.main.async {
                    self?.playTextToSpeechButton.setTitle("Pause Echo", for: .normal)
                }
            }
            
        } else if expression.isPlayingEcho {
            print("==== Speech synthesizer paused =====")
            expression.pauseEcho() { [weak self] in
                DispatchQueue.main.async {
                    self?.playTextToSpeechButton.setTitle("Play Echo", for: .normal)
                }
            }
        } else {
            playAudioButton.setTitle("Play Audio", for: .normal)
            expression.startEcho() { [weak self] in
                DispatchQueue.main.async {
                    self?.navigationItem.title = ""
                    self?.playTextToSpeechButton.setTitle("Pause Echo", for: .normal)
                }
            }
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
            self.UITimer?.invalidate()
        }
    }
    
    // MARK: - Wake Phrase Methods
    
    func startListeningForWakePhrase() {
        print("===== Starting Listening for Wake Phrase =====")
        
        // must be placed before we start listening for wake phrase
        // if pitch engine begins first, we are for some reason unable to do speech recognition
        pitchEngine.start()
        
        if recognitionTask != nil {
            recognitionTask?.finish()
            recognitionTask = nil
        }

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: recordBus)
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request!.shouldReportPartialResults = true
        request!.requiresOnDeviceRecognition = false
        
        node.installTap(onBus: recordBus, bufferSize: 1024, format: recordingFormat) { [unowned self] (buffer, _) in
            self.request!.append(buffer)
            
            DispatchQueue.main.async {
                let soundIntensity = Utils.computeNormalizedSoundIntensity(buffer: buffer, minDb: self.minDb)
                if let soundIntensity = soundIntensity {
                    let soundIntensityHeight = CGFloat(min((CGFloat(soundIntensity) * self.view.safeAreaLayoutGuide.layoutFrame.height), self.view.safeAreaLayoutGuide.layoutFrame.height))
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
        
        do {
            // it’s generally preferable to defer this call until your app begins audio playback
            try recordingSession.setActive(true)
        } catch {
            print("===== Unable to activate audio session =====")
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
        soundIntensityIndicatorHeight.constant = 0
        
        let node = audioEngine.inputNode
        node.removeTap(onBus: self.recordBus)

        audioEngine.stop()
        audioEngine.reset()
        
        // When this is not in the main thread, the recognition task doesn't end correctly
        // which prevents us from receiving the final transcription.
        DispatchQueue.main.async {
            self.recognitionTask!.finish() // don't wrap in if statement because it is sometimes not .running
            self.request!.endAudio() // don't add a request = nil because it results in request not being there sometimes.
            self.pitchEngine.stop()
            onStopHandler?()
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
                print("text: ", text)
                if text.contains(self.wakePhrase) { // wake word/phrase needs to be two words to get pitch data
                    self.stopListeningForWakePhrase()
                    let greetingMessage = self.numAppSessions <= 1 ? "Hey there, it's a pleasure to meet you!" : "Hello again!"
                    
                    let utterance = AVSpeechUtterance(string: greetingMessage) // Nice to hear you again. Let's make things happen.
                    self.synthesizerVoice = Utils.getSynthesizerVoice(withGender: .female, vc: self)
                    if let voice = self.synthesizerVoice {
                        utterance.voice = voice
                    }
                    utterance.rate = (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) / 2 + AVSpeechUtteranceMinimumSpeechRate
                    utterance.volume = 1
                    self.speechSynthesizer.speak(utterance)
                    print("===== Wake Phrase Detected =====")
                    self.activateApp()
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
                    print("===== Restart Listening and continue to look for wake phrase =====")
                    self.stopListeningForWakePhrase() {[weak self] in
                        self?.configureListeningForWakePhrase()
                    }
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
            playTextToSpeechButton.setTitle("Play Echo", for: .normal)
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
        // print("Pitch { \n\tpitch: \(pitch.note.string) \n\tfrequency: \(pitch.frequency) \n}")

        if !self.appActivated && pitch.note.octave >= 4 {
            // is female
            expression.setGender(as: .female)
        } else if !self.appActivated {
            // is male
            expression.setGender(as: .male)
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
