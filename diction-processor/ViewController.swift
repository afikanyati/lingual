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

// MARK: - ViewController

public let viewController = ViewController.shared
public final class ViewController: UIViewController {
    static let shared = ViewController()
    
    // MARK: - Outlets and Views
    
    // Wake Phrase
    @IBOutlet weak var wakePhraseLabel: UILabel?
    @IBOutlet weak var wakePhraseSubtitleLabel: UILabel?
    
    // Indicators
    @IBOutlet weak var soundIntensityIndicator: UIView?
    @IBOutlet weak var soundIntensityIndicatorHeight: NSLayoutConstraint?
    @IBOutlet weak var soundIntensityIndicatorPositionBottom: NSLayoutConstraint?
    @IBOutlet weak var pitchLabel: UILabel?
    
    // MARK: - App Preferences
    /// Stores a reference to the minimum power value accepted for sound intensity datum
    var minPower: Float = -160.0
    /// Specifies whether speech recognition should use on-device compute or cloud compute
    var withOnDeviceRecognition = Utils.DEFAULT_USE_ON_DEVICE_RECOGNITION
    /// Specifies whether note will present visual indications of temporal silences on screen
    var withTemporalSuggestions = false
    /// Specifies whether note will present punctuation suggestions based on duration of silences
    var withPunctuationSuggestions = true
    /// Specifies whether note will present emphasis suggestions based on fluctuating sound intensity of speaker
    var withFormattingSuggestions = true
    /// Specifies whether note will only present written language as words (versus numerals or punctuation symbols)
    var withTextStrictlyAsWords = false
    /// Specifies whether note text will contain capitalized words
    var withCapitalization = true
    /// Specifies whether segments corresponding to punctuation should be skipped
    var withSkipPunctuation = true
    /// Specifies whether segments corresponding to silences should be skipped
    var withOmitSilences = true
    /// Specifies whether passive echo should execute when headphones are connected
    var withPassiveEcho = true
    
    // MARK: - Telemetry
    var numAppSessions = 0
    
    // MARK: - General Properties
    var appActivated = false
    let wakePhrases = [
        "rise and shine",
        "rison shine",
        "razon shine"
    ]
    var listeningPermissionsGranted = false
    var isListeningForWakePhrase = false
    var isListeningForVolume = false
    var notificationQueue = Queue<NotificationItem>()
    /// Specifies whether view has been instructed to clear out contents of notification queue
    private(set) var isExhaustingNotificationQueue = false
    /// Stores the current playback volume of note playback
    public var playbackVolume: Float {
        return AVAudioSession.sharedInstance().outputVolume
    }
    var appNotificationTimer: Timer?
//    var volumeListeningRateTimer: Timer?
//    var stopListeningForVolumeTimer: Timer?
    
    // MARK: - General Audio Properties
    @objc dynamic var session = AVAudioSession.sharedInstance()
    
    // MARK: - Speech Recognition Properties
    var audioEngine = AVAudioEngine()
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    var request: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    /// Stores the type of recognition last executed e.g. speech or voice command
    private(set) var lastRecognitionTask: RecognitionTask?
    /// Indicates whether we have to execute listening for speech handler in isListeningForSpeech method
    private var executedListeningForCommandsStartHandler = true
    /// Indicates whether we have processed a voice command early
    private(set) var earlyVoiceCommandDetection = false
    /// Stores the number of words that occur before a voice command in it's buffer
    private(set) var numWordsBeforeVoiceCommand: Int = 0
    
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
    /// Specifies whether note is currently listening for voice commands
    private(set) var isListeningForCommands = false
    /// Specifies whether note has paused listening for commands (active, but paused vs. inactive)
    private(set) var pausedListeningForCommands = false
    private var soundIntensityStream = [SoundIntensityDatum]()
    private var pitchStream = [PitchDatum]()
    /// Stores a UI handler to be executed when new sound intensity data is received
    private(set) var soundIntensityHandler: ((_ power: Double?) -> Void)?
    /// Stores a UI handler to be executed when new pitch data is received
    private(set) var pitchHandler: ((_ pitchDatum: PitchDatum?) -> Void)?
    
    // MARK: - Audio Playback Properties
    /// Stores the current playback rate of note playback
    private(set) var playbackRate: Float = 1
    
    // MARK: - Speech Synthesis Properties
    let speechSynthesizer = AVSpeechSynthesizer()
    var synthesizerVoice : AVSpeechSynthesisVoice?
    /// Stores a queue of synthesizer tasks to be executed serially
    var synthesizerQueue = Queue<SynthesizerItem>()
    /// Specifies whether view has been instructed to clear out contents of synthesizer queue
    private(set) var isExhaustingSynthesizerQueue = false
    /// Stores flag that indicates if we've prematurely ended echo utterance
    private(set) var interruptedEcho = false
    /// Stores the rate of the speech synthesis speech
    private(set) var echoRate: Float = 0.53
    private var updateEchoRate: Float?
    /// Stores a temporary handler to be executed when echo is complete (executes on-demand)
    private(set) var tempOnEchoFinish: (() -> Void)?
    
    var detailView: DetailViewController!
    var noteTableView: NoteTableViewController!
    
    // MARK: - ViewController Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        self.detailView = storyboard?.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController
        self.noteTableView = storyboard?.instantiateViewController(withIdentifier: "NoteTableViewController") as? NoteTableViewController
        
        // Set up Audio Session
        self.configureAudioSession()
        
        // Set up notification observers
        self.configureNotificationObservers()
        
        // Set up ui handlers
        self.configureUIHandlers()

        // App Visits
        self.configureAppVisits()
        
        // Permissions
        if !self.listeningPermissionsGranted {
            self.requestPermissions()
        }

        // Prepare UI
        self.setActiveUI(as: false)
        self.wakePhraseLabel?.text = "\"\(self.wakePhrases[0].capitalizeFirstLetter())\""
        
        self.prepareGeneralView()
        
        
        if !self.isListeningForWakePhrase {
            // Start listening for wake word
            self.configureListeningForWakePhrase()
        }
        
        // Assign delegates
        self.speechSynthesizer.delegate = self
        
        // add volume observer
        self.session.addObserver(
            self,
            forKeyPath: #keyPath(AVAudioSession.outputVolume),
            options: [.old, .new],
            context: nil
        )
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // remove volume observer
        self.session.removeObserver(
            self,
            forKeyPath: #keyPath(AVAudioSession.outputVolume),
            context: nil
        )
        
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Inactive
    func activateApp() {
        self.appActivated = true
        self.setActiveUI(as: true)
        
        // clear pitch and volume streams
        self.pitchStream = [PitchDatum]()
        self.soundIntensityStream = [SoundIntensityDatum]()

        // start listening for voice commands
        self.startListeningForVoiceCommands()
        
        // push to table view
        navigationController?.pushViewController(noteTableView, animated: true)
    }
    
    // MARK: - Setup
    
    func configureListeningForWakePhrase() {
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if authStatus != .authorized {
            let dialogActions = [
                DialogAction(title: "Grant Permission", style: .default, handler: { [unowned self] action in
                    self.requestPermissions() {
                        self.configureListeningForWakePhrase()
                    }
                }),
                DialogAction(title: "Cancel", style: .cancel, handler: nil)
            ]
            
            let dialogItem = DialogItem(
                title: "Speech Recognition Permission Denied",
                message: "Please grant permission for application to initiate speech transcription.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            Utils.presentDialog(dialogItem: dialogItem)
        } else {
            // pitch engine used to determine if user is male or female
            startListeningForWakePhrase()
            print("===== Listening for Wake Phrase =====")
        }
    }
    
    func configureAudioSession() {
        session = AVAudioSession.sharedInstance()

        do {
            // .voiceChat mode does not default to speakers
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try session.setPreferredSampleRate(44_100)
            try session.setActive(true)
        } catch let error as NSError {
            print("===== There was an error requesting permissions to record audio or setting session category: \(error.localizedDescription) =====")
        } catch {
            print("===== There was an error requesting permissions to record audio or setting session category =====")
        }
    }
    
    func prepareGeneralView() {
        self.soundIntensityIndicator?.backgroundColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
        self.pitchLabel?.textColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
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

    func configureUIHandlers() {
        self.soundIntensityHandler = { [weak self] power in
            if let power = power {
                DispatchQueue.main.async {
                    var screenHeight = self!.view.safeAreaLayoutGuide.layoutFrame.height
                    if let _ = self?.detailView.note {
                        screenHeight -= Utils.COMMAND_BAR_HEIGHT
                    }
                    if let _ = self?.detailView.note {
                        screenHeight -= Utils.MENU_BAR_HEIGHT
                    }
                    let height = CGFloat(Utils.normalizedPower(power: power, minPower: self!.minPower)) * screenHeight
                    let soundIntensityHeight: CGFloat = CGFloat(min(height, screenHeight))
                    self?.soundIntensityIndicatorHeight?.constant = soundIntensityHeight
                }
            }
        }
        self.pitchHandler = { [weak self] pitchDatum in
            if let pitchDatum = pitchDatum, let note = self?.detailView.note, !note.isPlayingNote {
                DispatchQueue.main.async {
                    let pitch = pitchDatum.pitch?.note.string
                    self?.pitchLabel?.text = pitch
                }
            }
        }
    }
    
    func requestPermissions(handler: (() -> Void)? = nil) {
        SFSpeechRecognizer.requestAuthorization {
            [unowned self] (authStatus) in
            DispatchQueue.main.async {
                self.listeningPermissionsGranted = false
                switch authStatus {
                case .authorized:
                    self.listeningPermissionsGranted = true
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
                    handler?()
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
            selector: #selector(self.appGainsFocus),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(self.appLosesFocus),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(self.appMovedToBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(self.appMovedToForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(self.appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(self.handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(self.handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(self.handleSecondaryAudio),
            name: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: nil
        )
    }
    
    func getStopListeningButton(withStopIndicator: Bool = false) -> UIBarButtonItem {
        let button  = UIButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: 30.0, height: 30.0)
        button.addTarget(self, action: #selector(self.handleToggleListening), for: .touchUpInside)
        
        if withStopIndicator {
            button.backgroundColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
            button.layer.cornerRadius = 0.5 * button.bounds.size.width
            button.setImage(UIImage(systemName: "mic.slash"), for: .normal)
            button.tintColor = UIColor.white
        } else {
            button.setImage(UIImage(systemName: "mic.slash"), for: .normal)
            button.tintColor = UIColor.systemGray
        }
        
        let barButton = UIBarButtonItem(customView: button)
        
        return barButton
    }

    func scheduleNotification(text: String, type: NotificationType? = nil, duration: TimeInterval? = 5) {
        let notificationItem = NotificationItem(
            text: text,
            type: type,
            duration: duration
        )
        self.notificationQueue.enqueue(notificationItem)
    }
    
    func exhaustNotificationQueue() {
        let item = self.notificationQueue.dequeue()
        self.isExhaustingNotificationQueue = !self.notificationQueue.isEmpty
        
        if let item = item {
            self.runTimedNotification(item: item)
        }
    }
    
    func emptyNotificationQueue() {
        self.notificationQueue.empty()
    }
    
    func runTimedNotification(item: NotificationItem) {
        DispatchQueue.main.async { [weak self] in
            // Stop UI Timer if we receive app notification while recording
            if let note = self?.detailView?.note, note.isListeningForSpeech && self?.detailView.UITimer != nil {
                self?.detailView.stopRecordingUITimer()
            }
            
            // Stop any prior notification that hasn't completed yet
            if self?.appNotificationTimer != nil {
                self?.appNotificationTimer?.invalidate()
                self?.appNotificationTimer = nil
            }

            self?.navigationItem.title = item.text
//            self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red]
            
            self?.appNotificationTimer = Timer.scheduledTimer(withTimeInterval: item.duration!, repeats: false) {[weak self] timer in
                self?.navigationItem.title = ""
                self?.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
                
                // Restart UI Timer is we received app notification while receiving
                if self!.isExhaustingNotificationQueue {
                    self!.exhaustNotificationQueue()
                } else if let note = self?.detailView?.note, note.isListeningForSpeech {
                    self?.clearTimedNotification()
                    self?.detailView.startRecordingUITimer(recording: true)
                }
            }
        }
        
        // Give haptic feedback
        if let type = item.type {
            switch (type) {
            case .error:
                hapticEngine.error()
            case .warning:
                hapticEngine.warning()
            default:
                hapticEngine.success()
            }
        }
    }
    
    func clearTimedNotification() {
        self.appNotificationTimer?.invalidate()
        self.appNotificationTimer = nil
        
        // Clear out UI artifacts
        DispatchQueue.main.async {
            self.navigationItem.title = ""
            self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
        }
    }
    
    func presentIndefiniteNotification(item: NotificationItem) {
        // Remove any timed notification
        if self.appNotificationTimer != nil {
            clearTimedNotification()
        }
        
        // Stop UI Timer if recording
        if let note = detailView.note, note.isListeningForSpeech && detailView.UITimer != nil {
            detailView.stopRecordingUITimer()
        }
        
        DispatchQueue.main.async {
            self.navigationItem.title = item.text
            if let note = self.detailView.note, note.isListeningForSpeech || !self.appActivated {
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red]
            } else {
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
            }
        }
    }
    
    func removeIndefiniteNotification() {
        DispatchQueue.main.async {
            if let note = self.detailView.note, note.isListeningForSpeech {
                self.navigationItem.title = ""
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
                self.detailView.startRecordingUITimer(recording: true)
            } else {
                self.navigationItem.title = ""
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
            }
        }
    }
    
    func exhaustSynthesizerQueue() {
        let item = self.synthesizerQueue.dequeue()
        self.isExhaustingSynthesizerQueue = !self.synthesizerQueue.isEmpty

        if let item = item {
            Utils.runSpeechSynthesizer(item: item)
        }
    }
    
    func emptySynthesizerQueue() {
        if self.speechSynthesizer.isSpeaking {
            self.speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        self.synthesizerQueue.empty()
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
            
            // keep recording outside of app if note started
            if let note = self.detailView.note, !note.isListeningForSpeech {
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
        } else if let note = self.detailView.note, note.isListeningForSpeech {
            note.stopListeningForSpeech() {
                self.detailView.onNoteListenStop!()
            }
        }
    }
    
    // MARK: - View Methods
    
    func setActiveUI(as visible: Bool) {
        self.pitchLabel?.isHidden = !visible
        self.wakePhraseSubtitleLabel?.isHidden = visible
        self.wakePhraseLabel?.isHidden = visible
        
        if let _ = detailView.note, !visible {
            detailView.setCursorVisibility(as: false)
        }
    }
    
    func activateListeningIndicator(withRecording: Bool = false, withStopListeningButton: Bool = false) {
        let spinner = UIActivityIndicatorView(style: .medium)
        if withRecording {
            spinner.color = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
        }
        spinner.startAnimating()

        let spinnerButton = UIBarButtonItem(customView: spinner)
        var buttons = [spinnerButton]
        if withStopListeningButton {
            let stopListeningButton = self.getStopListeningButton()
            buttons.append(stopListeningButton)
        }
        
        self.navigationItem.leftBarButtonItems = buttons
    }
    
    func deactivateListeningIndicator() {
        self.navigationItem.leftBarButtonItem = nil
    }
    
    // MARK: - Listening Methods
    
    func startListeningForWakePhrase() {
        print("===== Starting Listening for Wake Phrase =====")
        
        // Play Sound
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
            soundEngine.startListening()
        }
        
        // Give haptic feedback
//        hapticEngine.heavyImpact()
        hapticEngine.success()
        
        // Visually indicate app is listening
        DispatchQueue.main.async {
            self.activateListeningIndicator(withStopListeningButton: true)
        }
        
        // Update Wake Phrase Flage
        self.isListeningForWakePhrase = true
        
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

            // Handle sound intensity and pitch information
            DispatchQueue.main.async {
                // Sound Intensity
                let power = Utils.computeSoundIntensity(buffer: buffer)
                if let power = power {
                    var screenHeight = self.view.safeAreaLayoutGuide.layoutFrame.height
                    if let _ = detailView.note {
                        screenHeight -= Utils.COMMAND_BAR_HEIGHT
                    }
                    if let _ = detailView.note {
                        screenHeight -= Utils.MENU_BAR_HEIGHT
                    }
                    let soundIntensityDatum = SoundIntensityDatum(date: Date(), power: power)
                    self.soundIntensityStream.append(soundIntensityDatum)
                    let soundIntensityHeight = CGFloat(min((CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * screenHeight), screenHeight))
                    self.soundIntensityIndicatorHeight?.constant = soundIntensityHeight
                }
                // Pitch
                if let lastPitchDatum = self.pitchStream.last, let pitch = lastPitchDatum.pitch, let note = detailView.note, !note.isPlayingNote {
                    self.pitchLabel?.text = pitch.note.string
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch let error {
            print("[Error] There was a problem starting speech recognition: \(error.localizedDescription)")
        }
        
        let handleRecognizer = {
            print("\tUsing On-Device Recognition")
            self.request!.requiresOnDeviceRecognition = true
            self.request!.contextualStrings = ["rise and shine"]
            
            if let speechRecognizer = self.speechRecognizer, !speechRecognizer.isAvailable {
                print("\tSpeech Recognizer is not available")
                return
            }
            
            self.speechRecognizer?.defaultTaskHint = .dictation
            self.recognitionTask = self.speechRecognizer?.recognitionTask(with: self.request!, delegate: self)
        }
        
        if let speechRecognizer = self.speechRecognizer, self.withOnDeviceRecognition && speechRecognizer.supportsOnDeviceRecognition {
            handleRecognizer()
        } else {
            // check again after two seconds
            Timer.scheduledTimer(withTimeInterval: Utils.LISTENING_LAUNCH_DELAY, repeats: false) { [weak self] timer in
                if let speechRecognizer = self?.speechRecognizer, self!.withOnDeviceRecognition && speechRecognizer.supportsOnDeviceRecognition {
                    handleRecognizer()
                } else {
                    let dialogActions = [
                        DialogAction(title: "Close", style: .cancel, handler: nil)
                    ]
                    
                    let dialogItem = DialogItem(
                        title: "Unable to initiate Voice Recognition",
                        message: "Lingual relies on on-device recognition to deliver a the best user experience. Your device does not support it.",
                        preferredStyle: .alert,
                        actions: dialogActions
                    )
                    Utils.presentDialog(dialogItem: dialogItem)
                }
            }
        }
    }
    
    func stopListeningForWakePhrase(onStopHandler: (() -> Void)? = nil) {
        print("===== Stopping Listening for Wake Phrase =====")
        
        // Update Wake Phrase Flage
        self.isListeningForWakePhrase = false
        
        let node = audioEngine.inputNode
        node.removeTap(onBus: self.recordBus)
        
        // Give haptic feedback
//        hapticEngine.heavyImpact()
        hapticEngine.success()

        audioEngine.stop()
        // We instantiate new audio engine in case headphones have been added or removed
        // Removing an audio node will create a broken graph: https://developer.apple.com/documentation/avfoundation/avaudioengine
        audioEngine = AVAudioEngine()
        
        // When this is not in the main thread, the recognition task doesn't end correctly
        // which prevents us from receiving the final transcription.
        DispatchQueue.main.async {
            self.soundIntensityIndicatorHeight?.constant = 0
            self.pitchLabel?.text = ""
            self.recognitionTask!.finish() // don't wrap in if statement because it is sometimes not .running
            self.request!.endAudio() // don't add a request = nil because it results in request not being there sometimes.
            self.pitchEngine.stop()
            // Remove is listening indicator
            self.deactivateListeningIndicator()
            onStopHandler?()
        }
    }
    
    func startListeningForVoiceCommands(
        onStartHandler: (() -> Void)? = nil
    ) {
        print("===== Starting Listening For Voice Commands =====")

        // Make sure we're not listening for voice commands or speech already
        if let note = detailView.note, note.isListeningForSpeech {
            note.stopListeningForSpeech() {
                self.startListeningForVoiceCommands(
                    onStartHandler: onStartHandler
                )
            }
            
            return
        }
        
        if !self.isListeningForCommands || self.pausedListeningForCommands {
            // A transcription can be in progress before call to startSpeechRecognition if
            // Apple servers ended dictation session
            // It cannot be if after a continguous clause was completed while on-device recognition
            if !self.isListeningForCommands {
                self.isListeningForCommands = true
            }
            
            self.setLastRecognitionTask(task: RecognitionTask.VOICE_COMMAND)
        }

        if self.pausedListeningForCommands {
            self.pausedListeningForCommands = false
        }
        
        // flag to run start handler
        self.executedListeningForCommandsStartHandler = false

        // Visually indicate app is listening
        DispatchQueue.main.async {
            self.activateListeningIndicator(
                withRecording: false,
                withStopListeningButton: true
            )
        }
        
        // Activate Pitch Recognition
        pitchEngine.start()
        
        // Set sound intensity handler
        if let soundIntensityHandler = soundIntensityHandler {
            self.soundIntensityHandler = soundIntensityHandler
        }
        
        // Set pitch handler
        if let pitchHandler = pitchHandler {
            self.pitchHandler = pitchHandler
        }
        
        // Make sure any previous recognition tasks are finished
        if recognitionTask != nil {
            recognitionTask?.finish()
            recognitionTask = nil
        }

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: self.recordBus)
        print("===== Recording Info ===== \n\tSoftware Format: \(recordingFormat.sampleRate)\n\tHardware Format: \(AVAudioSession.sharedInstance().sampleRate)")
        
        // Set up values for speech recognition
        request = SFSpeechAudioBufferRecognitionRequest()
        request!.shouldReportPartialResults = true
        request!.requiresOnDeviceRecognition = false // Set to false by default, but conditionally changed below

        // Tap into microphone bus to receive and process audio input buffers
        node.installTap(onBus: self.recordBus, bufferSize: 1024, format: recordingFormat) { [unowned self] (buffer, _) in
            // Capture buffer
            self.request!.append(buffer)

            DispatchQueue.main.async {
                if !self.executedListeningForCommandsStartHandler {
                    self.executedListeningForCommandsStartHandler = true
                    onStartHandler?()
                }
            }
            
            // Handle sound intensity and pitch information
            DispatchQueue.main.async {
                // Sound Intensity
                let power = Utils.computeSoundIntensity(buffer: buffer)
                if let power = power {
                    let datum = SoundIntensityDatum(date: Date(), power: power)
                    self.soundIntensityStream.append(datum)
                    self.soundIntensityHandler?(power)
                    if let _ = detailView.note {
                        detailView.soundIntensityHandler?(power)
                    }
                }
                
                // Pitch
                if let note = detailView.note, let lastPitchDatum = note.pitchStream.last, note.isListeningForSpeech && !note.isPlayingNote {
                    self.pitchHandler?(lastPitchDatum)
                } else if let note = detailView.note, let lastPitchDatum = self.pitchStream.last, !note.isListeningForSpeech {
                    self.pitchHandler?(lastPitchDatum)
                    
                    if let _ = detailView.note {
                        detailView.pitchHandler?(lastPitchDatum)
                    }
                }
            }
        }
        
        // Prepare and start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("\t[Error] There was a problem starting speech recognition")
        }
        
        let handleRecognizer = {
            print("\tUsing On-Device Recognition")
            self.request!.requiresOnDeviceRecognition = true
            
            print("\tLoad contextual strings")
            self.request!.contextualStrings = [
                
            ]
            
            if let speechRecognizer = self.speechRecognizer, !speechRecognizer.isAvailable {
                print("\tSpeech Recognizer is not available")
                return
            }
            
            // Let speech recognizer know we're performing dictation or voice commands
            self.speechRecognizer?.defaultTaskHint = .search
            self.recognitionTask = self.speechRecognizer?.recognitionTask(with: self.request!, delegate: self)
        }

        if let speechRecognizer = self.speechRecognizer, self.withOnDeviceRecognition && speechRecognizer.supportsOnDeviceRecognition {
            handleRecognizer()
        } else {
            // check again after a second
            Timer.scheduledTimer(withTimeInterval: Utils.LISTENING_LAUNCH_DELAY, repeats: false) { timer in
                if let speechRecognizer = self.speechRecognizer, self.withOnDeviceRecognition && speechRecognizer.supportsOnDeviceRecognition {
                    handleRecognizer()
                    
                } else {
                    // Present error
                    let dialogActions = [
                        DialogAction(title: "Close", style: .cancel, handler: nil)
                    ]
                    
                    let dialogItem = DialogItem(
                        title: "Unable to initiate Voice Recognition",
                        message: "Lingual relies on on-device recognition to deliver a the best user experience. Your device does not support it.",
                        preferredStyle: .alert,
                        actions: dialogActions
                    )
                    Utils.presentDialog(dialogItem: dialogItem)
                }
            }
        }
    }
    
    func stopListeningForVoiceCommands(pause: Bool = false, onStopHandler: (() -> Void)? = nil) {
        print("===== Stopping Listening For Voice Commands =====")
        
        guard self.isListeningForCommands else {
            print("\t[Error] There was a problem stopping listening for commands. Listening not active.")
            return
        }

        if isListeningForCommands && !pause {
            if self.isListeningForCommands {
                self.isListeningForCommands = false
            }
            if self.pausedListeningForCommands {
                self.pausedListeningForCommands = false
            }
        } else if pause {
            if !self.pausedListeningForCommands {
                self.pausedListeningForCommands = true
            }
        }
        
        let node = audioEngine.inputNode
        node.removeTap(onBus: self.recordBus)
        
        if pause {
            audioEngine.pause()
        } else {
            audioEngine.stop()
        }

        // When this is not in the main thread, the recognition task doesn't end correctly
        // which prevents us from receiving the final transcription.
        DispatchQueue.main.async {
            self.recognitionTask?.finish() // don't wrap in if statement because it is sometimes not .running
            self.request!.endAudio() // don't add a request = nil because it results in request not being there sometimes.
            self.pitchEngine.stop()
            self.activateListeningIndicator(
                withRecording: false,
                withStopListeningButton: true
            )
            onStopHandler?() // Needs to be outside DispatchQueue.main.async so it doesn't accidentally wrap two DispatchQueue.main.async if handler has one
        }
    }
    
    // MARK: - Volume Adjuster Methods
    
//    func startListeningForVolume() {
//        print("===== Starting Listening for Volume =====")
//        print("volume: ", AVAudioSession.sharedInstance().outputVolume)
//        // set listening flag to true
//
//
//        // Play Sound
//        soundEngine.startListening()
//        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
//            soundEngine.startProcessing()
//        }
//
//        // clear pitch and sound intensity streams
//        self.pitchStream = [PitchDatum]()
//        self.soundIntensityStream = [SoundIntensityDatum]()
//
//        // must be placed before we start listening for wake phrase
//        // if pitch engine begins first, we are for some reason unable to do speech recognition
//        pitchEngine.start()
//
//        let node = audioEngine.inputNode
//        let recordingFormat = node.outputFormat(forBus: recordBus)
//
//        node.installTap(onBus: recordBus, bufferSize: 1024, format: recordingFormat) { [unowned self] (buffer, _) in
//            DispatchQueue.main.async {
//                if !self.isListeningForVolume {
//                    self.isListeningForVolume = true
//                    self.stopListeningForVolumeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) {[weak self] timer in
//                        self?.stopListeningForVolume() {
//                            self?.note.startListeningForVoiceCommands(
//                                soundIntensityHandler: self!.soundIntensityHandler!,
//                                pitchHandler: self!.pitchHandler!
//                            )
//                        }
//                    }
//                }
//
//                let power = Utils.computeSoundIntensity(buffer: buffer)
//                if let power = power {
//                    var screenHeight = self.view.safeAreaLayoutGuide.layoutFrame.height
//                    if self.commandBar.alpha == 1 {
//                        screenHeight -= Utils.COMMAND_BAR_HEIGHT
//                    }
//                    if self.scrollView.alpha == 1 {
//                        screenHeight -= Utils.MENU_BAR_HEIGHT
//                    }
//                    let soundIntensityDatum = SoundIntensityDatum(date: Date(), power: power)
//                    self.soundIntensityStream.append(soundIntensityDatum)
//                    let soundIntensityHeight = CGFloat(min((CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * screenHeight), screenHeight))
//                    self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
//
//                    if soundIntensityDatum.power > self.getBackgroundNoise() + Utils.TALKING_POWER_DELTA && self.isListeningForVolume && self.stopListeningForVolumeTimer != nil {
//                        // continue if power still coming through
//                        self.stopListeningForVolumeTimer?.invalidate()
//                        self.stopListeningForVolumeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) {[weak self] timer in
//                            if self?.stopListeningForVolumeTimer != nil {
//                                self?.stopListeningForVolume() {
//                                    self?.note.startListeningForVoiceCommands(
//                                        soundIntensityHandler: self!.soundIntensityHandler!,
//                                        pitchHandler: self!.pitchHandler!
//                                    )
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//        }
//
//        audioEngine.prepare()
//        do {
//            try audioEngine.start()
//        } catch let error {
//            print("[Error] There was a problem starting speech recognition: \(error.localizedDescription)")
//        }
//    }
//
//    func stopListeningForVolume(onStopHandler: (() -> Void)? = nil) {
//        print("===== Stopping Listening for Volume =====")
//
//        // Play Sound
//        soundEngine.stopProcessing()
//        soundEngine.stopListening()
//
//
//
//        let node = audioEngine.inputNode
//        node.removeTap(onBus: self.recordBus)
//
//        audioEngine.stop()
//        // We instantiate new audio engine in case headphones have been added or removed
//        // Removing an audio node will create a broken graph: https://developer.apple.com/documentation/avfoundation/avaudioengine
//        audioEngine = AVAudioEngine()
//
//        DispatchQueue.main.async {
//            self.soundIntensityIndicatorHeight.constant = 0
//            self.isListeningForVolume = false
//            self.stopListeningForVolumeTimer = nil
//            self.pitchEngine.stop()
//            print("volume: ", AVAudioSession.sharedInstance().outputVolume)
//            onStopHandler?()
//        }
//    }
    
    // MARK: - Navigation Bar Methods
    
    @objc func handleToggleListening(_ sender: Any) {
        print("===== Screen Button: Handle Toggle Listening =====")
        
        if self.isListeningForCommands || (!self.appActivated && self.isListeningForWakePhrase) {
            // Stop Listening For Commands
            if self.appActivated {
                self.stopListeningForVoiceCommands() {
                    let stopListeningButton = self.getStopListeningButton(withStopIndicator: true)
                    self.navigationItem.leftBarButtonItems = [stopListeningButton]
                }
            } else {
                self.stopListeningForWakePhrase() {[weak self] in
                    let stopListeningButton = self!.getStopListeningButton(withStopIndicator: true)
                    self?.navigationItem.leftBarButtonItems = [stopListeningButton]
                }
            }
        } else {
            if self.appActivated {
                // Listening For Commands
                self.startListeningForVoiceCommands()
            } else {
                self.startListeningForWakePhrase()
            }
        }
    }
    
    // MARK: - Manage Saved Content
    func fetchNotes() -> [Note]? {
        print("===== Fetch Notes =====")
        let defaults = UserDefaults.standard
        if let savedNotes = defaults.object(forKey: "notes") as? Data {
            if let decodedNotes = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(savedNotes) as? [Note] {
                print("\tSuccessfully fetched \(decodedNotes.count) notes!")
                return decodedNotes
            } else {
                print("\t[Error] There was a problem converting notes Data object to array of Notes.")
            }
        } else {
            print("\t[Error] There was a problem retrieiving notes Data object.")
        }
        
        return nil
    }
    
    func saveNotes(notes: [Note]) {
        print("===== Save Notes =====")
        if let savedData = try? NSKeyedArchiver.archivedData(withRootObject: notes, requiringSecureCoding: false) {
            let defaults = UserDefaults.standard
            defaults.set(savedData, forKey: "notes")
            print("\tSuccessfully saved \(notes.count) notes!")
        } else {
            print("\t[Error] There was a problem converting notes to Data object.")
        }
    }
    
    // MARK: - Setters
       
    func setPlaybackRate(to rate: Float) {
        print("===== Set Playback Rate: \(rate) =====")
        self.playbackRate = rate

        if let note = detailView.note, note.isPlayingNote {
            note.player.rate = self.playbackRate
        }
    }

    // sets relative to wpm of current note
    func setPlaybackRate(wpm: Float) {
        print("===== Set Playback Rate: \(wpm)wpm =====")
        guard let note = detailView.note else {
            print("\t[Error] There was a problem setting playback rate. Unable to locate note.")
            return
        }
        self.playbackRate = wpm / Float(note.avgSpeakingRate).rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)

        if note.isPlayingNote {
            note.player.rate = self.playbackRate
        }
    }
    
    // Implementing real-time rate change: https://stackoverflow.com/questions/25499803/how-to-change-speech-rate-during-speaking-using-avspeechsynthesizer-in-ios-7
    func setEchoRate(to rate: Float, stageUpdate: Bool = false) {
        print("===== Set Echo Rate: \(rate) =====")
        if stageUpdate {
            self.updateEchoRate = rate
        } else {
            self.echoRate = rate
        }
    }
    
    // Audio variable
    func setWithSkipPunctuation(to skip: Bool) {
        self.withSkipPunctuation = skip
        
        if self.withSkipPunctuation {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Skip Punctuation",
                audioMessage: "skip punctuation activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Include Punctuation",
                audioMessage: "skip punctuation deactivated",
                withHaptics: true
            )
        }
    }
    
    // Audio variable
    func setWithOmitSilences(to skip: Bool) {
        self.withOmitSilences = skip
        
        if self.withOmitSilences {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Activate Silences",
                audioMessage: "silences activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Deactivate Silences",
                audioMessage: "silences deactivated",
                withHaptics: true
            )
        }
    }
    
    // Audio variable
    func setWithPassiveEcho(to value: Bool) {
        self.withPassiveEcho = value
        
        if self.withPassiveEcho {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Activate Passive Echo",
                audioMessage: "passive echo activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Deactivate Passive Echo",
                audioMessage: "passive echo deactivated",
                withHaptics: true
            )
        }
    }
    
    // Visual variable
    func setWithTemporalSuggestions(to value: Bool) {
        self.withTemporalSuggestions = value
        
        // We can only have one suggestion type on at a time
        // Deactivate punctuation suggestions if active
        if value && self.withPunctuationSuggestions {
            self.withTemporalSuggestions = false
        }
        
        // Make sure new setting is reflecting visually
        // TODO => UPDATE NOTE DETAIL
        
        if self.withTemporalSuggestions {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Activate Temporal Suggestions",
                audioMessage: "temporal suggestions activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Deactivate Temporal Suggestions",
                audioMessage: "temporal suggestions deactivated",
                withHaptics: true
            )
        }
    }
    
    // Visual variable
    func setWithPunctuationSuggestions(to value: Bool) {
        self.withPunctuationSuggestions = value
        
        // We can only have one suggestion type on at a time
        // Deactivate space suggestions if active
        if value && self.withTemporalSuggestions {
            self.withTemporalSuggestions = false
        }
        
        // Make sure new setting is reflecting visually
        // TODO => UPDATE NOTE DETAIL
        
        if self.withPunctuationSuggestions {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Activate Punctuation Suggestions",
                audioMessage: "punctuation suggestions activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Deactivate Punctuation Suggestions",
                audioMessage: "punctuation suggestions deactivated",
                withHaptics: true
            )
        }
    }
    
    // Visual variable
    func setWithFormattingSuggestions(to value: Bool) {
        self.withFormattingSuggestions = value
        
        // Make sure new setting is reflecting visually
        // TODO => UPDATE NOTE DETAIL
        
        if self.withFormattingSuggestions {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Activate Formatting Suggestions",
                audioMessage: "formatting suggestions activated",
                withHaptics: true
            )
        } else {
            // Present Feedback
            Utils.executeFeedback(
                visualMessage: "Deactivate Formatting Suggestions",
                audioMessage: "formatting suggestions deactivated",
                withHaptics: true
            )
        }
    }
    
    // Visual variable
    func setWithTextStrictlyAsWords(to value: Bool) {
        self.withTextStrictlyAsWords = value
        
        // Make sure new setting is reflecting visually
        // TODO => UPDATE NOTE DETAIL
    }
    
    // Visual variable
    func setWithCapitalization(to value: Bool) {
        self.withCapitalization = value
        
        // Make sure new setting is reflecting visually
        // TODO => UPDATE NOTE DETAIL
    }
    
    func setEchoHandler(handler: (() -> Void)? = nil) {
        self.tempOnEchoFinish = handler
    }
    
    func setLastRecognitionTask(task: RecognitionTask) {
        self.lastRecognitionTask = task
    }
    
    func setPausedListeningForCommands(paused: Bool) {
        self.pausedListeningForCommands = paused
    }
    
    // MARK: - Getters
    
    func getBackgroundNoise() -> Double {
        if self.soundIntensityStream.count == 0 {
            return Double.infinity
        }
        
        let soundIntensityStream = Utils.cleanseSoundIntensityStream(soundIntensityStream: self.soundIntensityStream)
        
        // Determine sound intensity with greatest frequency
        var counts = [Int: Int]()
        soundIntensityStream.forEach {
            if $0.power != Double.infinity && $0.power != Double.nan && $0.power != -Double.infinity {
                counts[Int($0.power)] = (counts[Int($0.power)] ?? 0) + 1
            }
        }
        
        if let (value, _) = counts.max(by: {$0.1 < $1.1}) {
            return Double(value)
        }
        
        return Double.infinity
    }
    
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

    
    // MARK: - Key-Value Observer
    
    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?)
    {
        if keyPath == #keyPath(AVAudioSession.outputVolume) {
            print(" ===== Modify Output  Volume =====")

            var outputVolume: Float
            if let volume = change?[.oldKey] as? Float {
                outputVolume = volume
                print("\tOld Volume: ", outputVolume)
            } else {
                outputVolume = -1
                print("\tOld Volume: ", outputVolume)
            }
            // Get the status change from the change dictionary
            if let volume = change?[.newKey] as? Float {
                outputVolume = volume
                print("\tNew Volume: ", outputVolume, session.outputVolume)
            } else {
                outputVolume = -1
                print("\tNew Volume: ", outputVolume, session.outputVolume)
            }
        }
    }
}
    
// MARK: - Speech Recognition Delegate Extension

extension ViewController: SFSpeechRecognitionTaskDelegate {
    public func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {
        print("===== System is no longer accepting new speech input =====")
    }
    
    public func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {
        print("===== Application cancelled looking for wake phrase ===== ")
    }
    
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
         print("===== Application successfully finished looking for wake phrase ===== ")
        if !self.appActivated && !Utils.DEFAULT_USE_ON_DEVICE_RECOGNITION {
            print("===== Restart Listening and continue to look for wake phrase =====")
            self.stopListeningForWakePhrase() {[weak self] in
                self?.configureListeningForWakePhrase()
            }
        }
    }
    
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        DispatchQueue.main.async {
            if !self.appActivated && !self.speechSynthesizer.isSpeaking {
                var text = ""
                for segment in transcription.segments {
                    text += " \(segment.substring)"
                }
                
                text = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if text.contains(self.wakePhrases[0]) || text.contains(self.wakePhrases[1]) || text.contains(self.wakePhrases[2]) { // wake word/phrase needs to be two words to get pitch data
                    self.stopListeningForWakePhrase() { [weak self] in
                        // Play Sound
                        Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { timer in
                            soundEngine.correctWakePhrase()
                        }
                        
                        // Give haptic feedback
                        hapticEngine.success()
                        
                        print("===== Wake Phrase Detected =====")
                        self?.activateApp()
                        // Remove voice command hint text
                        self?.removeIndefiniteNotification()
                        
                        // Remove any speech synthesizing
                        self?.emptySynthesizerQueue()
                    }
                } else if !text.contains("rise") && !text.contains("rise and") && !text.contains("rison") {
                    // Play Sound
                    soundEngine.incorrectWakePhrase()
                    
                    // Give haptic feedback
                    hapticEngine.error()
                    
                    // Remove voice command hint text
                    self.removeIndefiniteNotification()
                    
                    // Present feedback
                    if text.count > 0 {
                        self.emptySynthesizerQueue()
                        Utils.executeFeedback(
                            visualMessage: "\"\(transcription.segments.count > 3 ? "\(transcription.segments.first!.substring.lowercased())...\(transcription.segments.last!.substring.lowercased())" : text.lowercased())\"",
                            audioMessage: text,
                            discardPrior: true,
                            withHaptics: true
                        )
                    }
                }
                
                return
            } else if self.isListeningForCommands && (
                (self.detailView.note == nil && Utils.validSpeechPower(soundIntensityStream: self.soundIntensityStream, backgroundNoise: self.getBackgroundNoise())) ||
                    (self.detailView.note != nil && Utils.validSpeechPower(soundIntensityStream: self.detailView.note!.soundIntensityStream, backgroundNoise: self.detailView.note!.getBackgroundNoise()))
            ) {
                // Analyze for voice commands
                let (isValidVoiceCommand, voiceCommandType, numWordsBeforeVoiceCommand) = Utils.isValidVoiceCommand(detailView: self.detailView, query: transcription.formattedString)

                // execute listen update handler
                if let note = self.detailView.note, !note.isListeningForSpeech && note.noteSegments.count == 0 {
                    // Don't clear text if we're mid-note
                    // Dont clear text if we have existing note segments
                    note.handleOnListenUpdate(text: transcription.formattedString)
                }
                
                // We don't want to have double error audio
                if let note = self.detailView.note, !isValidVoiceCommand {
//                    // Play Sound
//                    soundEngine.voiceCommandDeny()
//
//                    var text = ""
//                    for segment in transcription.segments {
//                        text += " \(segment.substring)"
//                    }
//
//                    text = text.trimTrailingPunctuation()

//                    if text.count > 0 {
//                        Utils.executeFeedback(
//                            visualMessage: "\"\(transcription.segments.count > 3 ? "\(transcription.segments.first!.substring.lowercased())...\(transcription.segments.last!.substring.lowercased())" : text.lowercased())\"",
//                            vc: self.vc!,
//                            withHaptics: true,
//                            delay: 0
//                        )
//                    }
                    
                    // Capture invalid voice commands
                    let voiceCommandDatum = VoiceCommandDatum(
                        date: Date(),
                        utteredSpeech: transcription.formattedString,
                        isValid: false
                    )
                    note.voiceCommandStream.append(voiceCommandDatum)
                }
                
                if let numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand, let voiceCommandType = voiceCommandType, isValidVoiceCommand {
                    // execute listen update handler
                    if let note = self.detailView.note, !note.isListeningForSpeech && note.noteSegments.count == 0 {
                        // Don't clear text if we're mid-note
                        note.handleOnListenUpdate(text: "")
                    }
                    
                    // Set early detection flag on
                    self.earlyVoiceCommandDetection = true
                    
                    // Set number of words before voice command
                    self.numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand
                    
                    print("\tCommand Recognized!: \(transcription.formattedString)")
                    if let note = self.detailView.note {
                        // Capture Voice Command Datum
                        let voiceCommandDatum = VoiceCommandDatum(
                            date: Date(),
                            utteredSpeech: transcription.formattedString,
                            isValid: true,
                            type: voiceCommandType
                        )
                        note.voiceCommandStream.append(voiceCommandDatum)
                        // prepare voice command handler
                        voiceCommandEngine.process(detailView: self.detailView, note: note, query: transcription.formattedString)
                    } else {
                        // prepare voice command handler
                        voiceCommandEngine.process(detailView: self.detailView, query: transcription.formattedString)
                    }
                }
            }
        }
    }
    
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition result: SFSpeechRecognitionResult) {
        DispatchQueue.main.async {
            if !self.appActivated {
                var text = ""
                for segment in result.bestTranscription.segments {
                    text += " \(segment.substring)"
                }
                
                text = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if text.contains(self.wakePhrases[0]) || text.contains(self.wakePhrases[1]) || text.contains(self.wakePhrases[2]) {
                    self.stopListeningForWakePhrase()
                } else if !self.speechSynthesizer.isSpeaking && self.synthesizerQueue.isEmpty {
//                    // Play Sound
//                    soundEngine.incorrectWakePhrase()
//
//                    // Give haptic feedback
//                    hapticEngine.error()
//
//                    // Remove voice command hint text
//                    self.removeIndefiniteNotification()
//
//                    // Present feedback
//                    if text.count > 0 {
//                        self.emptySynthesizerQueue()
//                        Utils.executeFeedback(
//                            visualMessage: "\"\(result.bestTranscription.segments.count > 3 ? "\(result.bestTranscription.segments.first!.substring.lowercased())...\(result.bestTranscription.segments.last!.substring.lowercased())" : text.lowercased())\"",
//                            audioMessage: text,
//                            note: self.note,
//                            withHaptics: true
//                        )
//                    }
                }

                return
            } else if (self.isListeningForCommands && !self.pausedListeningForCommands && !self.earlyVoiceCommandDetection) || (self.detailView.note?.isListeningForSpeech ?? false && self.detailView.note?.pausedListeningForSpeech ?? false && !self.isListeningForCommands && self.detailView.note?.noteBuffer.count ?? 0 > 0 && self.request!.requiresOnDeviceRecognition && self.detailView.note?.recordStartDate == nil && !self.earlyVoiceCommandDetection) {
                // sometimes the voice commands that initiate the note will be sent to be committed erroneously
                // we catch them by identifying that self.recordStartDate == nil, for which they would be if
                // they were processed before note properly started

                if self.detailView.note?.noteBuffer.count ?? 0 > 0 {
                    // clear buffer
                    self.detailView.note?.clearBuffer()
                }
                
                // Analyze for voice commands
                let (isValidVoiceCommand, voiceCommandType, numWordsBeforeVoiceCommand) = Utils.isValidVoiceCommand(detailView: self.detailView, query: result.bestTranscription.formattedString)
                
                if let note = self.detailView.note, !note.isListeningForSpeech && note.noteSegments.count == 0 {
                    // We are not yet starting a note and have no noteSegments. We should remove text on screen
                    note.handleOnListenUpdate(text: "")
                }
                
                if !isValidVoiceCommand {
                    // Play Sound
                    soundEngine.voiceCommandDeny()

                    var text = ""
                    for segment in result.bestTranscription.segments {
                        text += " \(segment.substring)"
                    }
                    
                    text = text.trimTrailingPunctuation()
                    if text.count > 0 {
                        Utils.executeFeedback(
                            visualMessage: "\"\(result.bestTranscription.segments.count > 3 ? "\(result.bestTranscription.segments.first!.substring.lowercased())...\(result.bestTranscription.segments.last!.substring.lowercased())" : text.lowercased())\"",
                            audioMessage: result.bestTranscription.formattedString,
                            withHaptics: true,
                            delay: 0
                        )
                    }
                    
                    if let note = self.detailView.note {
                        // Capture invalid voice commands
                        let voiceCommandDatum = VoiceCommandDatum(
                            date: Date(),
                            utteredSpeech: result.bestTranscription.formattedString,
                            isValid: false
                        )
                        note.voiceCommandStream.append(voiceCommandDatum)
                    }
                    
                    // Turns off early voice commmand detection flag
                    self.earlyVoiceCommandDetection = false
                }

                if let numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand, let _ = voiceCommandType, isValidVoiceCommand {
                    // execute listen update handler
                    if let note = self.detailView.note, !note.isListeningForSpeech && note.noteSegments.count == 0 {
                        // We are not yet starting a note and have no noteSegments. We should remove text on screen
                        note.handleOnListenUpdate(text: "")
                    }

                    self.numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand
                    
                    print("\tCommand Recognized!: \(result.bestTranscription.formattedString)")
                    
                    if let note = self.detailView.note {
                        // Capture invalid voice commands
                        let voiceCommandDatum = VoiceCommandDatum(
                            date: Date(),
                            utteredSpeech: result.bestTranscription.formattedString,
                            isValid: false
                        )
                        note.voiceCommandStream.append(voiceCommandDatum)
                        voiceCommandEngine.process(detailView: self.detailView, note: note, query: result.bestTranscription.formattedString)
                    } else {
                        voiceCommandEngine.process(detailView: self.detailView, query: result.bestTranscription.formattedString)
                    }
                }
            } else {
                // execute listen update handler
                if let note = self.detailView.note, !note.isListeningForSpeech && note.noteSegments.count == 0 {
                    // We are not yet starting a note and have no noteSegments. We should remove text on screen
                    note.handleOnListenUpdate(text: "")
                }
                
                // Prevents double voice command processing when we are listening for comands
                self.earlyVoiceCommandDetection = false
            }
        }
    }
    
    public func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        print("===== System has detected first incident of speech input =====")
    }
}

// MARK: - Speech Synthesizer Delegate Extension

extension ViewController: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("===== Speech synthesis was cancelled =====")
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("===== Paused speech synthesis successfully instructed to continue =====")
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully completed =====")
        if self.interruptedEcho {
            // We just modified the echo rate while playing echo
            // this ends echo and creates a new one with new rate
            // from the last word uttered
            //
            // Do nothing
            self.interruptedEcho = false
            return
        }
        
        if let note = detailView.note, !note.isPlayingPassiveEcho {
            // Avoid updating ui when selection
            // it will remove selection
            detailView.updateUIText(text: note.getText(), transformations: note.transformations)
        }
        
        if self.isExhaustingSynthesizerQueue {
            self.exhaustSynthesizerQueue()
        } else if let note = detailView.note, note.isPlayingEcho {
            // turn off isPlayingEcho
            note.isPlayingEcho = false
            
            // Update View
            detailView.adjustCommandBar()
            detailView.adjustMenuBar()
            detailView.updateUIText(text: note.getText(), transformations: note.transformations)
        } else if let note = detailView.note, note.isPlayingPassiveEcho && utterance.speechString == note.getText(segments: Array(note.noteSegments[note.lastEchoSegmentRange!])).trimTrailingPunctuation() {
            // turn off isPlayingPassiveEcho
            note.isPlayingPassiveEcho = false
            
            // Update View
            detailView.adjustCommandBar()
            detailView.adjustMenuBar()
            detailView.updateUIText(text: note.getText(), transformations: note.transformations)
        }

        self.tempOnEchoFinish?()
        self.tempOnEchoFinish = nil
        
        if self.appActivated && self.pausedListeningForCommands && !self.speechSynthesizer.isSpeaking && !AVAudioSession.isHeadphonesConnected {
            // when headphones are off we don't listen for voice commands while echoing
            // but on completion we turn it back on
            self.startListeningForVoiceCommands() {
                // Call after isPlayingEcho is set to false by tempOnEchoFinish
                self.detailView.adjustCommandBar()
                self.detailView.adjustMenuBar()
            }
        } else if let note = detailView.note, self.appActivated && note.pausedListeningForSpeech && !self.speechSynthesizer.isSpeaking && !AVAudioSession.isHeadphonesConnected && !note.isRunningNote && !note.isWalkingNote {
            // when headphones are off we don't listen for speech while echoing
            // but on completion we turn it back on
            note.startListeningForSpeech(
                onStartHandler: {[weak self] in
                    DispatchQueue.main.async {
                        self?.detailView.startRecordingUITimer(recording: true)
                        // Call after isPlayingEcho is set to false by tempOnEchoFinish
                        self?.detailView.adjustCommandBar()
                        self?.detailView.adjustMenuBar()
                    }
                }
            )
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully paused =====")
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully started: \(utterance.speechString) =====")
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        if let note = detailView.note, self.appActivated && (note.isPlayingEcho || note.isPlayingPassiveEcho) && utterance.speechString == note.getText(segments: Array(note.noteSegments[note.lastEchoSegmentRange!])) {
            var textRange = characterRange
            // find lowest segment that is a word
            var lowestEchoSegment: NoteSegment?
            for segment in note.noteSegments[note.lastEchoSegmentRange!] {
                if !segment.isSilence() && !segment.isVoiceCommandWord() && !segment.isDeleted() {
                    lowestEchoSegment = segment
                    break
                }
            }

            if let note = detailView.note, let lowestEchoSegment = lowestEchoSegment, let lowestEchoSegmentRange = note.getSegmentTextRange(of: lowestEchoSegment), note.isListeningForSpeech {
                textRange = NSRange(location: lowestEchoSegmentRange.location + characterRange.location, length: characterRange.length)
            }
            
            detailView.updateUIText(text: note.getText(), highlightRange: textRange, transformations: note.transformations)
        }
        
        if let note = detailView.note, let updateEchoRate = self.updateEchoRate, self.appActivated {
            // Compute unprocessed utterance
            let numProcessedChar = max(0, characterRange.location)
            let unprocessedUtterance = utterance.speechString.substring(fromIndex: numProcessedChar).lowercased()
            
            // Stop speech synthesizer
            self.speechSynthesizer.stopSpeaking(at: .immediate)
            
            // Change rate
            self.echoRate = updateEchoRate
            
            // Run remainder utterance
            let synthesizerItem = SynthesizerItem(
                synthesizer: self.speechSynthesizer,
                text: unprocessedUtterance,
                voice: Utils.getSynthesizerVoice(withGender: note.speaker.gender),
                rate: self.echoRate,
                volume: self.playbackVolume
            )
            Utils.runSpeechSynthesizer(item: synthesizerItem)
            
            self.updateEchoRate = nil
            self.interruptedEcho = true
        }
    }
}
    
// MARK: - Pitch Recognition Delegate Extension

extension ViewController: PitchEngineDelegate {
    public func pitchEngine(_ pitchEngine: PitchEngine, didReceivePitch pitch: Pitch) {
        // TODO: Timing
        if pitch.frequency >= Utils.MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= Utils.FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.getBackgroundNoise() != Double.infinity && self.soundIntensityStream.count > Utils.MIN_SEED_INTENSITY_POINTS && Utils.validSpeechPower(soundIntensityStream: self.soundIntensityStream, backgroundNoise: self.getBackgroundNoise()) {
            // Add to pitch stream
            let pitchDatum = PitchDatum(date: Date(), pitch: pitch)
            self.pitchStream.append(pitchDatum)
            
            // Set speaker pitch
            if let note = detailView.note, !self.appActivated {
                do {
                    if note.speaker.pitch == nil {
                        print("===== Base vocal frequency detected =====")
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
                    note.speaker.setSpeakerPitch(to: avgPitch)
                } catch {
                    print("===== [Error] There was a problem calculating average pitch =====")
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
// TODO: set withOnDeviceRecognition = false
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
// TODO: set withOnDeviceRecognition = true
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
// TODO: set withOnDeviceRecognition = true
//
// 10) No words for a minute
// Instructions: Open app. Say wake phrase. Start note. Wait a minute without saying a word. Say words after a minute.
// Expected Result: No words should be transcribed before a minute. Words shold be transcribed after a minute. Session should be fluid.
//
// 11) Some words in a minute. More words after.
// Instructions: Open app. Say wake phrase. Start note. Say some words before a minute. Say more words after a minute.
// Expected Result: Some words should be transcribed before a minute. More words should be stranscribed after a minute. Session should be fluid. The timestamps should be accurate for each word.
//
// +++++ On-device recognition
// +++++ With and without headphoness
// TODO: set withOnDeviceRecognition = true
//
// 12) No words for a minute
// Instructions: Open app. Say wake phrase. Start note. Wait a minute without saying a word. Say words after a minute.
// Expected Result: No words should be transcribed before a minute. Words shold be transcribed after a minute. Session should be fluid.
//
// 13) Some words in a minute. More words after.
// Instructions: Open app. Say wake phrase. Start note. Say some words before a minute. Say more words after a minute.
// Expected Result: Some words should be transcribed before a minute. More words should be stranscribed after a minute. Session should be fluid. The timestamps should be accurate for each word.
//
// 14) Spaced out audio while using on-device recognition
// Instructions: Speak out an note with at least five seconds of silence between each word
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
// Instructions: In createNewNote() method, set 'withTemporalSuggestions' and 'withPunctuationSuggestions' to true. And open application
// Expected Result:  You should see a 'Conflicting View Modes' error dialog telling you it's selected punctuation suggestions.
//
// 20) Test Change Audio Inputs
// Instructions: Start the app without earphones connected. While on the Wake Phrase Screen, connect earphones. Utter wake phrase.
// Expected Result: The wake phrase should be registered without error
//
// 21) Test Play Sentence
//
// ===== Code Needed =====
// note.playSentence(number: 1)
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Utter the following: "This is the first sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the second sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the third sentence".
// Expected Result: System should play back: "This is the second sentence".
//
// 22) Test Trim Note: Permanent
//
// ===== Code Needed =====
//note.trim(keeping: note.getSentenceDetails(number: 1)!.timeRange, permanent: true) {
//    self.note.play(
//        onStartHandler: { [weak self] in
//            // print("Successfully executed playback on start handler")
//            DispatchQueue.main.async {
//                self?.playAudioButton.setTitle(PAUSE_NOTE_LABEL, for: .normal)
//            }
//        },
//        secondElapseHandler: { [weak self] in
//            // print("Successfully executed playback secondT elapsed handler")
//            DispatchQueue.main.async {
//                if !self!.note.isListeningForSpeech && self!.note.player.currentTime().seconds != Double.infinity && self!.note.player.currentTime().seconds != Double.nan && self!.note.player.currentTime().seconds != -Double.infinity {
//                    self?.navigationItem.title = "\(Utils.formattedTime(time: Float(self!.note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.note.getDuration(filteredDuration: true).seconds)))"
//                }
//            }
//        },
//        segmentBoundaryHandler: { [weak self] in
//            // print("Successfully executed playback on segment boundary handler")
//            DispatchQueue.main.async {
//                if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
//                    // update text
//                    self?.updateUIText(text: self!.note.getText(), highlightRange: highlightRange, transformations: self!.note.transformations)
//                }
//
//                if let segment = self?.note.getSegment(type: .current), let pitch = segment.getPitch() {
//                    // update pitch
//                    self?.pitchLabel.text = pitch.note.string
//                }
//            }
//        }, onFinishHandler: { [weak self] in
//            // print("Successfully executed playback on finish handler")
//            DispatchQueue.main.async {
//                self?.updateUIText(text: self!.note.getText(), transformations: self!.note.transformations)
//                if !self!.note.isListeningForSpeech {
//                    self?.navigationItem.title = ""
//                }
//
//                self?.adjustCommandBar()
//                self?.adjustMenuBar()
//            }
//        }
//    )
//}
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Utter the following: "This is the first sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the second sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the third sentence".
// Expected Result: System should play back: "This is the second sentence".
//
// 23) Test Trim Note: Not Permanent
//
// ===== Code Needed =====
//note.trim(keeping: note.getSentenceDetails(number: 1)!.timeRange, permanent: false) {
//    self.note.play(
//        onStartHandler: { [weak self] in
//            // print("Successfully executed playback on start handler")
//            DispatchQueue.main.async {
//                self?.playAudioButton.setTitle(PAUSE_NOTE_LABEL, for: .normal)
//            }
//        },
//        secondElapseHandler: { [weak self] in
//            // print("Successfully executed playback secondT elapsed handler")
//            DispatchQueue.main.async {
//                if !self!.note.isListeningForSpeech && self!.note.player.currentTime().seconds != Double.infinity && self!.note.player.currentTime().seconds != Double.nan && self!.note.player.currentTime().seconds != -Double.infinity {
//                    self?.navigationItem.title = "\(Utils.formattedTime(time: Float(self!.note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.note.getDuration(filteredDuration: true).seconds)))"
//                }
//            }
//        },
//        segmentBoundaryHandler: { [weak self] in
//            // print("Successfully executed playback on segment boundary handler")
//            DispatchQueue.main.async {
//                if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
//                    // update text
//                    self?.updateUIText(text: self!.note.getText(), highlightRange: highlightRange, transformations: self!.note.transformations)
//                }
//
//                if let segment = self?.note.getSegment(type: .current), let pitch = segment.getPitch() {
//                    // update pitch
//                    self?.pitchLabel.text = pitch.note.string
//                }
//            }
//        }, onFinishHandler: { [weak self] in
//            // print("Successfully executed playback on finish handler")
//            DispatchQueue.main.async {
//                self?.updateUIText(text: self!.note.getText(), transformations: self!.note.transformations)
//                if !self!.note.isListeningForSpeech {
//                    self?.navigationItem.title = ""
//                }
//
//                self?.adjustCommandBar()
//                self?.adjustMenuBar()
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
//note.extractSentence(number: 1) { sentence in
//    self.tempNote = sentence
//    print(sentence?.getText() ?? "NIL")
//    sentence?.play(onFinishHandler: {
//        print("Finished sentence!")
//    })
//}
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Utter the following: "This is the first sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the second sentence". Wait NEW_PARAGRAPH_PAUSE_DURATION_MULTIPLIER seconds. Then utter: "This is the third sentence".
// Expected Result: System should play back: "This is the second sentence".
//
// 25) Duplicate Note
//
// ===== Code Needed =====
//note.duplicate() { note in
//    self.tempNote = note
//    self.tempNote?.play() {
//        print("Finished Sentence!")
//    }
//}
// =======================
//
// Instructions: Place code in an area where it maybe be executable. Record any note.
// Expected Result: System should play back your note.
//
// 26) Voice Commands
//
// Instructions: Open app and utter wake phrase. Start note by uttering "Start Note". Speak an note. End note by uttering "Stop Note". Play note by uttering "Play Note".
// Expected Result: Your note should playback *** without *** 'Stop Note' in it.
//
// 27) Uttering Voice Command Mid-Note
//
// Instructions: Open app and utter wake phrase. Start note by uttering "Start Note". Speak an note. Mid note utter "Play Note". Let audio play until completion. Continue speaking an note. End note by uttering "Stop Note". Play note by uttering "Play Note".
// Expected Result: Mid-note you should hear yourself utter the note up until that point. After ending note, your note should playback *** without *** 'Stop Note' in it.
//
// 28) Test track collapsing implementation
//
// Instructions: Open app and utter wake phrase. Start note by uttering "Start Note". Utter "this is the first sentence". Then utter "Play Note". Let audio play until completion. Then utter "this is the second sentence". Then utter "Play Note". Let audio play until completion. Then utter "this is the third sentence". Then utter "Play Note". End note by uttering "Stop Note"
// Expected Result: At each stage of "play note", each new utterance should be added to the note playback without voice command playback between each utterance.

// 29) Double Play Note Test
//
// Instructions: Open app and utter wake phrase. Start note by uttering "Start Note". Speak an note. Mid note utter "Play Note". Let audio play until completion. After completion, utter "Play Note" again.
// Expected Result: Note should be played back twice without any voice command utters played back.

// 30) Emphasis Test
//
// Instructions:
// Expected Result:
