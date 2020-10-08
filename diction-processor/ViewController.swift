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

class ViewController: UIViewController {
    
    // MARK: - Outlets and Views
    
    // ===== Menu Bar =====
    @IBOutlet weak var startNoteButton: UIView!
    @IBOutlet weak var editNoteButton: UIView!
    @IBOutlet weak var resumeNoteButton: UIView!
    @IBOutlet weak var stopListeningNoteButton: UIView!
    @IBOutlet weak var playNoteButton: UIView!
    @IBOutlet weak var stopPlayingNoteButton: UIView!
    @IBOutlet weak var playEchoButton: UIView!
    @IBOutlet weak var stopEchoButton: UIView!
    @IBOutlet weak var exportNoteButton: UIView!
    @IBOutlet weak var walkNoteButton: UIView!
    
    // ===== Command Bar =====
    
    // Resting Buttons
    @IBOutlet weak var runNoteButton: UIView!
    @IBOutlet weak var pauseNoteButton: UIView!
    
    // Conditional Buttons
    @IBOutlet weak var moveHereButton: UIView!
    @IBOutlet weak var previewClipboardButton: UIView!
    @IBOutlet weak var lastCommitButton: UIView!
    @IBOutlet weak var pauseEchoButton: UIView!
    @IBOutlet weak var skipBackwardButton: UIView!
    @IBOutlet weak var skipForwardButton: UIView!
    @IBOutlet weak var playbackRateButton: UIView!
    @IBOutlet weak var echoRateButton: UIView!
    
    // Selection Buttons
    @IBOutlet weak var increaseRateButton: UIView!
    @IBOutlet weak var decreaseRateButton: UIView!
    @IBOutlet weak var deleteSelectionButton: UIView!
    @IBOutlet weak var replaceSelectionButton: UIView!
    @IBOutlet weak var copySelectionButton: UIView!
    @IBOutlet weak var cutSelectionButton: UIView!
    @IBOutlet weak var exportSelectionButton: UIView!
    
    // Wake Phrase
    @IBOutlet weak var wakePhraseLabel: UILabel!
    @IBOutlet weak var wakePhraseSubtitleLabel: UILabel!
    
    // Text View
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var textViewPositionTop: NSLayoutConstraint!
    @IBOutlet weak var textViewPositionBottom: NSLayoutConstraint!
    
    // Indicators
    @IBOutlet weak var soundIntensityIndicatorHeight: NSLayoutConstraint!
    @IBOutlet weak var soundIntensityIndicatorPositionBottom: NSLayoutConstraint!
    @IBOutlet weak var pitchLabel: UILabel!
    @IBOutlet weak var transformationLabel: UILabel!
    
    // Scroll View
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewPositionTop: NSLayoutConstraint!

    // Command Bar
    @IBOutlet weak var commandBar: UIStackView!
    @IBOutlet weak var commandBarPositionTop: NSLayoutConstraint!
    
    // Menu Bar
    @IBOutlet weak var menuBar: UIStackView!
    @IBOutlet weak var menuBarPositionBottom: NSLayoutConstraint!
    
    // Slider
    @IBOutlet weak var sliderView: UIView!
    @IBOutlet weak var sliderViewPositionTop: NSLayoutConstraint!
    @IBOutlet weak var slider: UISlider!
    @IBOutlet weak var exitSliderButton: UIView!
    
    // Cursor
    var cursorView: UIView?
    
    // MARK: - General Properties
    var appActivated = false
    var useOnDeviceRecognition = DEFAULT_USE_ON_DEVICE_RECOGNITION
    var numAppSessions = 0
    let wakePhrases = [
        "rise and shine",
        "rison shine",
        "razon shine"
    ]
    let font = UIFont.systemFont(ofSize: 18.0)
    var listeningPermissionsGranted = false
    var isListeningForWakePhrase = false
    var isListeningForVolume = false
    var sliderIsVisible = false
    var sliderType: SliderType?
    var notificationQueue = Queue<NotificationItem>()
    /// Specifies whether view has been instructed to clear out contents of notification queue
    private(set) var isExhaustingNotificationQueue = false
    /// Stores the current playback volume of note playback
    public var playbackVolume: Float {
        return AVAudioSession.sharedInstance().outputVolume
    }
    var UITimer: Timer?
    var cursorBlinkTimer: Timer?
    var appNotificationTimer: Timer?
    var volumeListeningRateTimer: Timer?
    var stopListeningForVolumeTimer: Timer?
    var onNoteListenUpdate: ((_ text: String, _ bufferRange: NSRange?) -> Void)?
    var onNoteListenStop: (() -> Void)?
    var onNoteComplete: (() -> Void)?
    
    // MARK: - General Audio Properties
    @objc dynamic var session = AVAudioSession.sharedInstance()
    lazy var note: Note = {
        return self.createNewNote()
    }()
    var tempNote: Note?
    
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
    public var synthesizerQueue = Queue<SynthesizerItem>()
    /// Specifies whether view has been instructed to clear out contents of synthesizer queue
    private(set) var isExhaustingSynthesizerQueue = false
    /// Stores flag that indicates if we've prematurely ended echo utterance
    private(set) var interruptedEcho = false
    /// Stores the rate of the speech synthesis speech
    private(set) var echoRate: Float = 0.53
    private var updateEchoRate: Float?
    /// Stores a temporary handler to be executed when echo is complete (executes on-demand)
    private(set) var tempOnEchoFinish: (() -> Void)?
    
    // MARK: - Pitch Recognition Properties
    let minPower: Float = -160.0
    
    // MARK: - ViewController Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up Audio Session
        self.configureAudioSession()
        
        // Set up notification observers
        self.configureNotificationObservers()
        
        // Set up note handlers
        self.configureNoteHandlers()
        
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
        self.wakePhraseLabel.text = "\"\(self.wakePhrases[0].capitalizeFirstLetter())\""
        self.prepareMenuBar()
        self.prepareScrollView()
        self.prepareCommandBar()
        self.prepareSlider()
        self.adjustCommandBar()
        self.adjustMenuBar()
        self.transformationLabel.isHidden = true
        
        // Start listening for wake word
        self.configureListeningForWakePhrase()
        
        // Set textContainer font size
        self.textView.font = self.font
        
        // Assign delegates
        self.speechSynthesizer.delegate = self
        
        // add volume observer
        self.session.addObserver(
            self,
            forKeyPath: #keyPath(AVAudioSession.outputVolume),
            options: [.old, .new],
            context: nil
        )
        
        // add observer to hasSelection
        selectionCursor.addObserver(
            self,
            forKeyPath: "hasSelection",
            options: [.old, .new],
            context: nil
        )
        
        // add observer to clipboard
        selectionCursor.addObserver(
            self,
            forKeyPath: "clipboard",
            options: [.old, .new],
            context: nil
        )
        
        self.textView.addObserver(
            self,
            forKeyPath: "selectedTextRange",
            options: [.old, .new],
            context: nil
        )
        
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        self.textView.addGestureRecognizer(singleTap)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // remove volume observer
        self.session.removeObserver(
            self,
            forKeyPath: #keyPath(AVAudioSession.outputVolume),
            context: nil
        )
        
        // remove observer from hasSelection
        selectionCursor.removeObserver(
            self,
            forKeyPath: "hasSelection",
            context: nil
        )
        
        self.note.removeObserver(
            self,
            forKeyPath: "isListeningForSpeech",
            context: nil
        )
        
        self.note.removeObserver(
            self,
            forKeyPath: "pausedListeningForSpeech",
            context: nil
        )
        
        // remove observer from clipboard
        selectionCursor.removeObserver(
            self,
            forKeyPath: "clipboard",
            context: nil
        )
        
        self.textView.removeObserver(
            self,
            forKeyPath: "selectedTextRange",
            context: nil
        )
        
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Inactive
    func activateApp() {
        self.appActivated = true
        self.setActiveUI(as: true)
        
        self.adjustCommandBar()
        self.adjustMenuBar()
        
        // clear pitch and volume streams
        self.pitchStream = [PitchDatum]()
        self.soundIntensityStream = [SoundIntensityDatum]()

        // start listening for voice commands
        note.startListeningForVoiceCommands(
            soundIntensityHandler: self.soundIntensityHandler!,
            pitchHandler: self.pitchHandler!
        )
    }
    
    // MARK: - Setup
    
    func configureListeningForWakePhrase() {
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if authStatus != .authorized {
            let alertController = UIAlertController(title: "Speech Recognition Permission Denied", message: "Please grant permission for application to initiate speech transcription.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Grant Permission", style: .default) { [unowned self] action in
                self.requestPermissions(handler: {
                    self.configureListeningForWakePhrase()
                })
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
    
    func prepareMenuBar() {
        self.menuBar.layer.shadowPath =
              UIBezierPath(
                roundedRect: self.menuBar.bounds,
                cornerRadius: self.menuBar.layer.cornerRadius
              ).cgPath
        self.menuBar.layer.shadowColor = UIColor.black.cgColor
        self.menuBar.layer.shadowOpacity = 0.5
        self.menuBar.layer.shadowOffset = CGSize(width: 0, height: -5)
        self.menuBar.layer.shadowRadius = 5
        self.menuBar.layer.masksToBounds = false
    }
    
    func prepareScrollView() {

    }
    
    func prepareCommandBar() {
        self.commandBar.backgroundColor = UIColor(hex: Utils.COMMAND_BAR_BACKGROUND_COLOR)
        self.commandBar.layer.shadowPath =
              UIBezierPath(
                roundedRect: self.commandBar.bounds,
                cornerRadius: self.commandBar.layer.cornerRadius
              ).cgPath
        self.commandBar.layer.shadowColor = UIColor.black.cgColor
        self.commandBar.layer.shadowOpacity = 0.5
        self.commandBar.layer.shadowOffset = CGSize(width: 0, height: 5)
        self.commandBar.layer.shadowRadius = 5
        self.commandBar.layer.masksToBounds = false
    }
    
    func prepareSlider() {
        self.slider.minimumValue = Utils.MINIMUM_PLAYBACK_RATE
        self.slider.maximumValue = Utils.MAXIMUM_PLAYBACK_RATE
        self.slider.isContinuous = true
        self.slider.addTarget(self, action: #selector(self.sliderValueDidChange), for: .valueChanged)
        
        // Hide Slider
        self.setSliderVisibility(as: false)
    }
    
    func getStopListeningButton(withStopIndicator: Bool = false) -> UIBarButtonItem {
        let button  = UIButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 40.0)
        button.addTarget(self, action: #selector(handleToggleListening), for: .touchUpInside)
        
        if withStopIndicator {
            button.backgroundColor = UIColor.red
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
    
    func getDeleteNoteButton() -> UIBarButtonItem {
        let button  = UIButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 40.0)
        button.addTarget(self, action: #selector(resetSession), for: .touchUpInside)
        button.setImage(UIImage(systemName: "trash"), for: .normal)
        button.tintColor = UIColor.systemGray
        
        let barButton = UIBarButtonItem(customView: button)
        
        return barButton
    }
    
    func getPasteClipboardButton() -> UIBarButtonItem {
        let button  = UIButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 40.0)
        button.addTarget(self, action: #selector(self.handlePasteClipboard), for: .touchUpInside)
        button.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
        button.tintColor = UIColor.systemGray
        
        let barButton = UIBarButtonItem(customView: button)

        return barButton
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
    
    func configureNoteHandlers() {
        self.onNoteListenUpdate = {[weak self] text, bufferRange in
            DispatchQueue.main.async {
                self?.updateUIText(text: text, bufferRange: bufferRange, transformations: self!.note.transformations)
                self?.adjustCommandBar()
                self?.adjustMenuBar()
            }
        }
        
        self.onNoteListenStop = {[weak self] in
            DispatchQueue.main.async {
                self?.updateUIText(text: self!.note.getText(), transformations: self!.note.transformations)
                self?.stopRecordingUITimer()
                self?.adjustCommandBar()
                self?.adjustMenuBar()
                self?.soundIntensityIndicatorHeight.constant = 0
            }
        }
        
        self.onNoteComplete = {[weak self] in
            // Play sound
            soundEngine.saveNote()

            DispatchQueue.main.async {
                self?.stopRecordingUITimer()
                self?.soundIntensityIndicatorHeight.constant = 0
                self?.adjustCommandBar()
                self?.adjustMenuBar()
                self?.navigationItem.rightBarButtonItems = [self!.getDeleteNoteButton()]
                if let _ = selectionCursor.clipboard {
                    self?.navigationItem.rightBarButtonItems?.insert(self!.getPasteClipboardButton(), at: 0)
                }
                self?.activateListeningIndicator(withStopListeningButton: true)
            }
        }
    }
    
    func configureUIHandlers() {
        self.soundIntensityHandler = { power in
            if let power = power {
                DispatchQueue.main.async {
                    var screenHeight = self.view.safeAreaLayoutGuide.layoutFrame.height
                    if self.commandBar.alpha == 1 {
                        screenHeight -= Utils.COMMAND_BAR_HEIGHT
                    }
                    if self.scrollView.alpha == 1 {
                        screenHeight -= Utils.MENU_BAR_HEIGHT
                    }
                    let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * screenHeight
                    let soundIntensityHeight: CGFloat = CGFloat(min(height, screenHeight))
                    self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                }
            }
        }
        self.pitchHandler = { pitchDatum in
            if let pitchDatum = pitchDatum, !self.note.isPlayingNote {
                DispatchQueue.main.async {
                    let pitch = pitchDatum.pitch.note.string
                    self.pitchLabel.text = pitch
                }
            }
        }
    }
    
    @objc func resetSession() {
        print("===== Reset Session =====")
        // Play sound
        soundEngine.delete()
        
        // Give haptic feedback
        hapticEngine.mediumImpact()

        // Clear any timed notification
        clearTimedNotification()
        
        if note.isPlayingEcho || note.isPlayingPassiveEcho {
            note.stopEcho(omitFeedback: true)
        }
        
        if note.isPlayingNote {
            note.stop()
        }
        
        // Reset Selection Cursor
        selectionCursor.reset()
        
        // Remove previous observer
        self.note.removeObserver(
            self,
            forKeyPath: "isListeningForSpeech",
            context: nil
        )
        
        self.note.removeObserver(
            self,
            forKeyPath: "pausedListeningForSpeech",
            context: nil
        )
        
        // Stop listening for speech
        // Reset note
        if note.isListeningForSpeech {
            note.stopListeningForSpeech() {
                self.note = self.createNewNote()
                self.note.startListeningForVoiceCommands(
                    soundIntensityHandler: self.soundIntensityHandler!,
                    pitchHandler: self.pitchHandler!
                )
            }
        } else if note.isListeningForCommands {
            note.stopListeningForVoiceCommands() {
                self.note = self.createNewNote()
                self.note.startListeningForVoiceCommands(
                    soundIntensityHandler: self.soundIntensityHandler!,
                    pitchHandler: self.pitchHandler!
                )
            }
        } else {
            self.note = self.createNewNote()
        }
        
        DispatchQueue.main.async {
            self.textView.attributedText = NSMutableAttributedString(string: "")
            self.navigationItem.rightBarButtonItems = nil
            self.adjustCommandBar()
            self.adjustMenuBar()
            self.setCursorVisibility(as: false)
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
    
    func setCursorVisibility(as visible: Bool) {
        print("=====  Set Cursor Visibility: \(visible) =====")
        // manage cursor view
        if self.cursorView == nil && visible && self.textView.attributedText.length == 0 {
            // initial set up for cursor
            self.cursorView = UIView()
            Utils.initializeCursor(
                textView: self.textView,
                cursorView: self.cursorView!,
                font: self.font
            )
            
            // Set UIView background color
            self.cursorView!.backgroundColor = UIColor.systemBlue
            
            // Create corner radius
            self.cursorView!.layer.cornerRadius = CGFloat(Utils.CURSOR_WIDTH / 2)
            
            // Add above UIView object as the main view's subview.
            self.view.addSubview(self.cursorView!)
        } else if let _ = self.cursorView, visible && self.textView.attributedText.length > 0 && self.cursorView!.alpha == 0 {
            // show cursor again
            self.cursorView!.alpha = 1
        } else if let _ = self.cursorView, !visible && self.note.isListeningForSpeech {
            // hide cursor
            self.cursorView!.alpha = 0
        }
        
        // manage cursor model
        if visible {
            selectionCursor.setTextView(textView: self.textView)
            selectionCursor.setCursorView(cursorView: cursorView)
            selectionCursor.setNote(note: self.note)
            selectionCursor.setFont(font: self.font)
            
            if self.cursorBlinkTimer != nil {
                // Stopped cursor blinking that's already running
                // To avoid two instances of blinking timers
                self.cursorBlinkTimer?.invalidate()
            }
            
            // start cursor blink
            self.cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_CURSOR_BLINK_RATE, repeats: true) { [weak self] timer in
                if let cursorView = self?.cursorView, cursorView.alpha == 1 {
                    UIView.animate(withDuration: Utils.DEFAULT_CURSOR_BLINK_TRANSITION_DURATION) {
                        self!.cursorView!.alpha = 0
                    }
                } else if let cursorView = self?.cursorView, cursorView.alpha == 0 {
                    UIView.animate(withDuration: Utils.DEFAULT_CURSOR_BLINK_TRANSITION_DURATION) {
                        self!.cursorView!.alpha = 1
                    }
                }
            }
        } else {
            // stop cursor blink
            if self.cursorBlinkTimer != nil {
                self.cursorBlinkTimer?.invalidate()
                self.cursorBlinkTimer = nil
            }
        }
    }
    
    func removeCursor() {
        print("===== Remove Cursor =====")
        // selectionCursor.reset()

        // remove cursor
        if let cursorView = self.cursorView {
            cursorView.removeFromSuperview()
            self.cursorView = nil
        }
    }
    
    func setMenuBarVisibility(as visible: Bool) {
        if visible {
            // Show Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.menuBar.alpha = 1
                    self.menuBarPositionBottom.constant = 0
                }
            )
            // Reduce TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionBottom.constant = Utils.MENU_BAR_HEIGHT
                }
            )
            
            // Move Sound Intensity Indicator Bottom
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.soundIntensityIndicatorPositionBottom.constant = Utils.MENU_BAR_HEIGHT
                }
            )
        } else {
            // Hide Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.menuBar.alpha = 0
                    self.menuBarPositionBottom.constant = -20
                }
            )
            
            // Incrase TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionBottom.constant = 0
                }
            )
            
            // Move Sound Intensity Indicator Bottom
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.soundIntensityIndicatorPositionBottom.constant = 0
                }
            )
        }
    }
    
    func setScrollViewVisibility(as visible: Bool) {
        if visible {
            // Show Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.scrollView.alpha = 1
                    self.scrollViewPositionTop.constant = 0
                }
            )
            // Reduce TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionTop.constant = Utils.SCROLL_VIEW_HEIGHT
                }
            )
            
            // Adjust cursor
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                // Adjust cursor to appropriate position
                if selectionCursor.isVisible && !selectionCursor.hasSelection {
                    selectionCursor.textViewDidChange(self!.textView)
                }
            }
        } else {
            // Hide Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.scrollView.alpha = 0
                    self.scrollViewPositionTop.constant = -20
                }
            )
            
            // Expand TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionTop.constant = 0
                }
            )

            // Adjust cursor
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                // Adjust cursor to appropriate position
                if selectionCursor.isVisible && !selectionCursor.hasSelection {
                    selectionCursor.textViewDidChange(self!.textView)
                }
            }
        }
    }
    
    func setCommandBarVisibility(as visible: Bool) {
        if visible {
            // Show Slider View
            self.commandBar.isHidden = false

            // Animate in Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.commandBar.alpha = 1
                }
            )
        } else {
            // Animate out Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.commandBar.alpha = 0
                }
            )
            
            // Hide Command Bar
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                self!.commandBar.isHidden = true
            }
        }
    }
    
    func setSliderVisibility(as visible: Bool) {
        if visible {
            // Show Slider View
            self.sliderView.isHidden = false

            // Animate in Slider View
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.sliderView.alpha = 1
                }
            )
        } else {
            // Animate out Slider View
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.sliderView.alpha = 0
                }
            )
            
            // Hide Slider View
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                self!.sliderView.isHidden = true
            }
        }
    }
    
    func createNewNote() -> Note {
        // create new note
        let uid = UUID().uuidString
        let note = Note(
            vc: self,
            uid: uid,
            filename: "note-\(uid)",
            speaker: Speaker(name: "Afika Nyati", avatarURL: URL(string: AVATAR_URL)!, vc: self),
            minPower: minPower,
            withOnDeviceRecognition: self.useOnDeviceRecognition,
            withTemporalSuggestions: false,
            withPunctuationSuggestions: true,
            withFormattingSuggestions: true,
            withTextStrictlyAsWords: false,
            withCapitalization: true,
            onListenUpdate: self.onNoteListenUpdate,
            onListenStop: self.onNoteListenStop,
            onComplete: self.onNoteComplete,
            scheduleTempOnEchoFinishHandler: { [weak self] handler in
                self?.tempOnEchoFinish = handler
            }
        )

        // add observer to new note
        note.addObserver(
            self,
            forKeyPath: "isListeningForSpeech",
            options: [.old, .new],
            context: nil
        )
        note.addObserver(
            self,
            forKeyPath: "pausedListeningForSpeech",
            options: [.old, .new],
            context: nil
        )
        
        return note
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
        DispatchQueue.main.async {
            // Stop UI Timer if we receive app notification while recording
            if self.note.isListeningForSpeech && self.UITimer != nil {
                self.stopRecordingUITimer()
            }
            
            // Stop any prior notification that hasn't completed yet
            if self.appNotificationTimer != nil {
                self.appNotificationTimer?.invalidate()
                self.appNotificationTimer = nil
            }

            self.navigationItem.title = item.text
            self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.red]
            
            self.appNotificationTimer = Timer.scheduledTimer(withTimeInterval: item.duration!, repeats: false) {[weak self] timer in
                self?.navigationItem.title = ""
                self?.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
                
                // Restart UI Timer is we received app notification while receiving
                if self!.isExhaustingNotificationQueue {
                    self!.exhaustNotificationQueue()
                } else if self!.note.isListeningForSpeech {
                    self?.clearTimedNotification()
                    self!.startRecordingUITimer(recording: true)
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
        if self.note.isListeningForSpeech && self.UITimer != nil {
            self.stopRecordingUITimer()
        }
        
        DispatchQueue.main.async {
            self.navigationItem.title = item.text
            if self.note.isListeningForSpeech || !self.appActivated {
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.red]
            } else {
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
            }
        }
    }
    
    func removeIndefiniteNotification() {
        DispatchQueue.main.async {
            if self.note.isListeningForSpeech {
                self.navigationItem.title = ""
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
                self.startRecordingUITimer(recording: true)
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
            if !self.note.isListeningForSpeech {
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
        } else if note.isListeningForSpeech {
            self.note.stopListeningForSpeech() {[weak self] in
                self?.onNoteListenStop!()
            }
        }
    }
    
    // MARK: - View Methods
    
    func setActiveUI(as visible: Bool) {
        textView.isHidden = !visible
        pitchLabel.isHidden = !visible
        wakePhraseSubtitleLabel.isHidden = visible
        wakePhraseLabel.isHidden = visible
        
        if !visible {
            self.setCursorVisibility(as: false)
        }
    }
    
    func updateUIText(text: String, highlightRange: NSRange? = nil, bufferRange: NSRange? = nil, transformations: [NoteTransformation]? = nil) {
        let mutableAttributedString = NSMutableAttributedString(string: text)

        if let bufferRange = bufferRange, bufferRange.length > 0 && text.count > 0 {
            // If passage is in buffer, we make gray text
            mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.systemGray, range: bufferRange)
        } else if let highlightRange = highlightRange, highlightRange.length > 0 && text.count > 0 {
            // If words in note are being echoed, we highlight them
            mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.white, range: highlightRange)
            mutableAttributedString.addAttribute(.backgroundColor, value: UIColor.red, range: highlightRange)
        }
        
        // Emphasize all transformations text
        if let transformations = transformations {
            for transformation in transformations {
                mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: transformation.textRange)
            }
        }
        
        // Add all accumulated attributes to text object
        textView.attributedText = mutableAttributedString
        // Set font
        textView.font = self.font
        
        // Notify of text change
        if selectionCursor.isVisible {
            selectionCursor.textViewDidChange(self.textView)
        }
    }
    
    /**
        Presents timer to view.

        - Parameter recording: Whether the timer should be set to be a recording.
    */
    func startRecordingUITimer(recording: Bool) {
        if self.UITimer != nil {
            self.stopRecordingUITimer()
        }
        
        if recording {
            DispatchQueue.main.async {
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.red]
            }
        }
        
        if selectionCursor.hasSelection && selectionCursor.direction == .forwards {
            // we have selection in forwards direction
            // visually present the time range of selection
            self.navigationItem.title = "\(Utils.formattedTime(time: self.note.getDurationListening()))\(" [\(Utils.formattedTime(time: Float(selectionCursor.anchor!.timeMapping.target.start.seconds))) - \(Utils.formattedTime(time: Float(selectionCursor.focus!.timeMapping.target.end.seconds)))]")"
        } else if selectionCursor.hasSelection && selectionCursor.direction == .backwards {
            // we have selection in backwards direction
            // visually present the time range of selection
            self.navigationItem.title = "\(Utils.formattedTime(time: self.note.getDurationListening()))\(" [\(Utils.formattedTime(time: Float(selectionCursor.focus!.timeMapping.target.start.seconds))) - \(Utils.formattedTime(time: Float(selectionCursor.anchor!.timeMapping.target.end.seconds)))]")"
        } else {
            // we don't have a selection
            // we might have a cursor placed mid-sentence however
            // present time of cursor
            self.navigationItem.title = "\(Utils.formattedTime(time: self.note.getDurationListening()))\(selectionCursor.cachedAnchor != nil ? " [\(Utils.formattedTime(time: Float(selectionCursor.cachedAnchor!.timeMapping.target.end.seconds)))]" : "")"
        }
        
        self.UITimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {[weak self] timer in
            // Terminate timer if no longer recording
            if !self!.note.isListeningForSpeech {
                self!.UITimer?.invalidate()
                self!.UITimer = nil
            }

            if selectionCursor.hasSelection && selectionCursor.direction == .forwards {
                // we have selection in forwards direction
                // visually present the time range of selection
                self?.navigationItem.title = "\(Utils.formattedTime(time: self!.note.getDurationListening()))\(" [\(Utils.formattedTime(time: Float(selectionCursor.anchor!.timeMapping.target.start.seconds))) - \(Utils.formattedTime(time: Float(selectionCursor.focus!.timeMapping.target.end.seconds)))]")"
            } else if selectionCursor.hasSelection && selectionCursor.direction == .backwards {
                // we have selection in backwards direction
                // visually present the time range of selection
                self?.navigationItem.title = "\(Utils.formattedTime(time: self!.note.getDurationListening()))\(" [\(Utils.formattedTime(time: Float(selectionCursor.focus!.timeMapping.target.start.seconds))) - \(Utils.formattedTime(time: Float(selectionCursor.anchor!.timeMapping.target.end.seconds)))]")"
            } else if self!.note.isListeningForSpeech {
                // we don't have a selection
                // we might have a cursor placed mid-sentence however
                // present time of cursor
                self?.navigationItem.title = "\(Utils.formattedTime(time: self!.note.getDurationListening()))\(selectionCursor.cachedAnchor != nil ? " [\(Utils.formattedTime(time: Float(selectionCursor.cachedAnchor!.timeMapping.target.end.seconds)))]" : "")"
            }
        }
    }
    
    /**
        Removes timer from view.
    */
    func stopRecordingUITimer() {
        self.UITimer?.invalidate()
        self.UITimer = nil
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
        self.navigationItem.title = ""
    }
    
    func activateListeningIndicator(withRecording: Bool = false, withStopListeningButton: Bool = false) {
        let spinner = UIActivityIndicatorView(style: .medium)
        if withRecording {
            spinner.color = UIColor.red
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
    
    func adjustMenuBar() {
        print("===== Adjust Menu Bar =====")

        // Start Note Button
        if !self.note.isListeningForSpeech &&
            self.note.noteSegments.count == 0 &&
            self.listeningPermissionsGranted {
            self.showButton(self.startNoteButton)
        } else {
            self.hideButton(self.startNoteButton)
        }
        
        // Resume Note Button
        if self.note.isListeningForSpeech && self.note.userInitiatedPausedListeningForSpeech {
            self.showButton(self.resumeNoteButton)
        } else {
            self.hideButton(self.resumeNoteButton)
        }
        
        // Edit Note Button
        if !self.note.isListeningForSpeech &&
            self.note.noteSegments.count > 0 &&
            self.listeningPermissionsGranted {
            self.showButton(self.editNoteButton)
        } else {
            self.hideButton(self.editNoteButton)
        }
        
        // Stop Listening Note Button
        if self.note.isListeningForSpeech && !self.note.isExporting {
            self.showButton(self.stopListeningNoteButton)
        } else {
            self.hideButton(self.stopListeningNoteButton)
        }
        
        // Play Note Button
        if (!self.note.isPlayingNote || (self.note.isPlayingNote && self.note.pausedPlayingNote)) && self.note.noteSegments.count > 0 {
            self.showButton(self.playNoteButton)
        } else {
            self.hideButton(self.playNoteButton)
        }
        
        // Stop Playing Note Button
        if self.note.isPlayingNote && self.note.noteSegments.count > 0 {
            self.showButton(self.stopPlayingNoteButton)
        } else {
            self.hideButton(self.stopPlayingNoteButton)
        }
        
        // Play Echo Button
        if (!(self.note.isPlayingEcho || self.note.isPlayingPassiveEcho) || (self.note.isPlayingEcho && self.note.pausedEcho)) && self.note.noteSegments.count > 0 {
            self.showButton(self.playEchoButton)
        } else {
            self.hideButton(self.playEchoButton)
        }

        // Stop Echo Button
        if (self.note.isPlayingEcho || self.note.isPlayingPassiveEcho) && self.note.noteSegments.count > 0 {
            self.showButton(self.stopEchoButton)
        } else {
            self.hideButton(self.stopEchoButton)
        }
        
        // Export Note Button
        if self.note.noteSegments.count > 0 && !self.note.isListeningForSpeech {
            self.showButton(self.exportNoteButton)
        } else {
            self.hideButton(self.exportNoteButton)
        }
        
        // Walk Note Button
        if self.note.noteSegments.count > 0 {
            self.showButton(self.walkNoteButton)
        } else {
            self.hideButton(self.walkNoteButton)
        }
        
        // ===== Manage Visibility of Menu Bar =====
    
        if self.appActivated {
            self.setMenuBarVisibility(as: true)
        } else {
            self.setMenuBarVisibility(as: false)
        }
    }
    
    func adjustCommandBar() {
        print("===== Adjust Command Bar =====")
        
        // ===== Number of active buttons =====
        var numActiveButtons = 0
        
        // ===== Resting Command Bar Buttons ======
        
        // Run Note Button
        if self.note.noteSegments.count > 0 && !selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.runNoteButton)
        } else {
            self.hideButton(self.runNoteButton)
        }
        
        // Pause Note Button
        if self.note.noteSegments.count > 0 &&
            (
                (self.note.isListeningForSpeech && !self.note.pausedListeningForSpeech) ||
                (self.note.isPlayingNote && !self.note.pausedPlayingNote)
            ) && !selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.pauseNoteButton)
        } else {
            self.hideButton(self.pauseNoteButton)
        }
        
        // Playback Rate Button
        if self.note.noteSegments.count > 0 && !selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.playbackRateButton)
        } else {
            self.hideButton(self.playbackRateButton)
        }
        
        // Echo Rate Button
        if self.note.noteSegments.count > 0 && !selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.echoRateButton)
        } else {
            self.hideButton(self.echoRateButton)
        }
        
        // ===== Conditional Buttons =====
        
        // Move Here Button
        if !selectionCursor.isAtEndOfTextView && self.note.isListeningForSpeech && !selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.moveHereButton)
        } else {
            self.hideButton(self.moveHereButton)
        }
        
        // Preview Clipboard Button
        if let _ = selectionCursor.clipboard, self.note.isListeningForSpeech {
            numActiveButtons += 1
            self.showButton(self.previewClipboardButton)
        } else {
            self.hideButton(self.previewClipboardButton)
        }
        
        // Last Commit Button
        if self.note.committedBufferRanges.count > 0 && self.note.isListeningForSpeech && !selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.lastCommitButton)
        } else {
            self.hideButton(self.lastCommitButton)
        }
        
        // Pause Echo Button
        if self.note.isPlayingEcho && !self.note.pausedEcho && !selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.pauseEchoButton)
        } else {
            self.hideButton(self.pauseEchoButton)
        }
        
        // Skip Backward Button
        if self.note.isPlayingNote && !selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.skipBackwardButton)
        } else {
            self.hideButton(self.skipBackwardButton)
        }
        
        // Skip Forward Button
        if self.note.isPlayingNote && !selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.skipForwardButton)
        } else {
            self.hideButton(self.skipForwardButton)
        }
        
        // ===== Selection Buttons ======

        // Increase Rate Button
        if let firstSelectionSegment = selectionCursor.selectionSegments?.first, selectionCursor.hasSelection && firstSelectionSegment.getRate() + Utils.DISCRETE_PLAYBACK_DELTA <= Utils.MAXIMUM_PLAYBACK_RATE  {
            numActiveButtons += 1
            self.showButton(self.increaseRateButton)
        } else {
            self.hideButton(self.increaseRateButton)
        }
        
        // Decrease Rate Button
        if let firstSelectionSegment = selectionCursor.selectionSegments?.first, selectionCursor.hasSelection && firstSelectionSegment.getRate() - Utils.DISCRETE_PLAYBACK_DELTA >= Utils.MINIMUM_PLAYBACK_RATE {
            numActiveButtons += 1
            self.showButton(self.decreaseRateButton)
        } else {
            self.hideButton(self.decreaseRateButton)
        }
        
        // Delete Button
        if selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.deleteSelectionButton)
        } else {
            self.hideButton(self.deleteSelectionButton)
        }
        
        // Replace Button
        if selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.replaceSelectionButton)
        } else {
            self.hideButton(self.replaceSelectionButton)
        }
        
        // Copy Button
        if selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.copySelectionButton)
        } else {
            self.hideButton(self.copySelectionButton)
        }
        
        // Cut Button
        if selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.cutSelectionButton)
        } else {
            self.hideButton(self.cutSelectionButton)
        }
        
        // Export Button
        if selectionCursor.hasSelection {
            numActiveButtons += 1
            self.showButton(self.exportSelectionButton)
        } else {
            self.hideButton(self.exportSelectionButton)
        }
        
        // ===== Manage Visibility of CommandBar =====
    
        if numActiveButtons > 0 && self.appActivated {
            self.setScrollViewVisibility(as: true)
        } else {
            self.setScrollViewVisibility(as: false)
        }
    }
    
    func handleTransformationsView() {
        if let selectionTransformations = selectionCursor.selectionTransformations, selectionCursor.hasSelection {
            self.transformationLabel.isHidden = false
            self.transformationLabel.text = "1.0"
            for transformation in selectionTransformations {
                if transformation.type == .playbackRate, let value = transformation.value {
                    self.transformationLabel.text = String(value)
                    break
                }
            }
        } else {
            self.transformationLabel.isHidden = true
        }
    }
    
    // MARK: - Wake Phrase Methods
    
    func startListeningForWakePhrase() {
        print("===== Starting Listening for Wake Phrase =====")
        
        // Play Sound
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
            soundEngine.startListening()
        }
        
        // Give haptic feedback
        hapticEngine.heavyImpact()
        
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
                    if self.commandBar.alpha == 1 {
                        screenHeight -= Utils.COMMAND_BAR_HEIGHT
                    }
                    if self.scrollView.alpha == 1 {
                        screenHeight -= Utils.MENU_BAR_HEIGHT
                    }
                    let soundIntensityDatum = SoundIntensityDatum(date: Date(), power: power)
                    self.soundIntensityStream.append(soundIntensityDatum)
                    let soundIntensityHeight = CGFloat(min((CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * screenHeight), screenHeight))
                    self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                }
                // Pitch
                if let lastPitchDatum = self.pitchStream.last, !self.note.isPlayingNote {
                    self.pitchLabel.text = lastPitchDatum.pitch.note.string
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
            
            if let speechRecognizer = self.speechRecognizer, !speechRecognizer.isAvailable {
                print("\tSpeech Recognizer is not available")
                return
            }
            
            self.speechRecognizer?.defaultTaskHint = .dictation
            self.recognitionTask = self.speechRecognizer?.recognitionTask(with: self.request!, delegate: self)
        }
        
        if let speechRecognizer = self.speechRecognizer, useOnDeviceRecognition && speechRecognizer.supportsOnDeviceRecognition {
            handleRecognizer()
        } else {
            // check again after two seconds
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] timer in
                if let speechRecognizer = self?.speechRecognizer, self!.useOnDeviceRecognition && speechRecognizer.supportsOnDeviceRecognition {
                    handleRecognizer()
                } else {
                    // Present error
                    let alertController = UIAlertController(title: "Unable to initiate Voice Recognition", message: "Lingual relies on on-device recognition to deliver a the best user experience. Your device does not support it.", preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "Close", style: .cancel))
                    DispatchQueue.main.async {
                        self!.present(alertController, animated: true)
                    }
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
        hapticEngine.heavyImpact()

        audioEngine.stop()
        // We instantiate new audio engine in case headphones have been added or removed
        // Removing an audio node will create a broken graph: https://developer.apple.com/documentation/avfoundation/avaudioengine
        audioEngine = AVAudioEngine()
        
        // When this is not in the main thread, the recognition task doesn't end correctly
        // which prevents us from receiving the final transcription.
        DispatchQueue.main.async {
            self.soundIntensityIndicatorHeight.constant = 0
            self.pitchLabel.text = ""
            self.recognitionTask!.finish() // don't wrap in if statement because it is sometimes not .running
            self.request!.endAudio() // don't add a request = nil because it results in request not being there sometimes.
            self.pitchEngine.stop()
            // Remove is listening indicator
            self.deactivateListeningIndicator()
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
                    self.stopListeningForVolumeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) {[weak self] timer in
                        self?.stopListeningForVolume() {
                            self?.note.startListeningForVoiceCommands(
                                soundIntensityHandler: self!.soundIntensityHandler!,
                                pitchHandler: self!.pitchHandler!
                            )
                        }
                    }
                }

                let power = Utils.computeSoundIntensity(buffer: buffer)
                if let power = power {
                    var screenHeight = self.view.safeAreaLayoutGuide.layoutFrame.height
                    if self.commandBar.alpha == 1 {
                        screenHeight -= Utils.COMMAND_BAR_HEIGHT
                    }
                    if self.scrollView.alpha == 1 {
                        screenHeight -= Utils.MENU_BAR_HEIGHT
                    }
                    let soundIntensityDatum = SoundIntensityDatum(date: Date(), power: power)
                    self.soundIntensityStream.append(soundIntensityDatum)
                    let soundIntensityHeight = CGFloat(min((CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * screenHeight), screenHeight))
                    self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                    
                    if soundIntensityDatum.power > self.getBackgroundNoise() + Utils.TALKING_POWER_DELTA && self.isListeningForVolume && self.stopListeningForVolumeTimer != nil {
                        // continue if power still coming through
                        self.stopListeningForVolumeTimer?.invalidate()
                        self.stopListeningForVolumeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) {[weak self] timer in
                            if self?.stopListeningForVolumeTimer != nil {
                                self?.stopListeningForVolume() {
                                    self?.note.startListeningForVoiceCommands(
                                        soundIntensityHandler: self!.soundIntensityHandler!,
                                        pitchHandler: self!.pitchHandler!
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
    
    // MARK: - Setters
       
    func setPlaybackRate(to rate: Float) {
        print("===== Set Playback Rate: \(rate) =====")
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Set Playback Rate",
            audioMessage: "set playback rate to \(self.playbackRate)",
            note: self.note
        )

        self.playbackRate = rate

        if self.note.isPlayingNote {
            self.note.player.rate = self.playbackRate
        }
    }

    // sets relative to wpm of current note
    func setPlaybackRate(wpm: Float) {
        print("===== Set Playback Rate: \(wpm)wpm =====")
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Set Playback Rate",
            audioMessage: "set playback rate to \(self.playbackRate)",
            note: self.note
        )
        
        self.playbackRate = wpm / Float(self.note.avgSpeakingRate).rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)

        if self.note.isPlayingNote {
            self.note.player.rate = self.playbackRate
        }
    }
    
    // Implementing real-time rate change: https://stackoverflow.com/questions/25499803/how-to-change-speech-rate-during-speaking-using-avspeechsynthesizer-in-ios-7
    func setEchoRate(to rate: Float) {
        print("===== Set Echo Rate: \(rate) =====")
        
        // Present Feedback
        Utils.executeFeedback(
            visualMessage: "Set Echo Rate",
            audioMessage: "set echo rate to \(self.echoRate)",
            note: self.note
        )
        
        self.echoRate = rate
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
    
    // MARK: - Helper Functions
    
    func showButton(_ commandButton: UIView) -> Void {
        let button = commandButton.subviews.filter {$0 is UIButton }
        if let button = button.first as? UIButton {
            button.isEnabled = true
        }
        commandButton.isHidden = false
        
        if commandButton.alpha == 0 {
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    commandButton.alpha = 1
                }
            )
        }
    }
    
    func hideButton(_ commandButton: UIView) -> Void {
        if commandButton.alpha == 1 {
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    commandButton.alpha = 0
                }
            )
        }
        
        Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { timer in
            let button = commandButton.subviews.filter {$0 is UIButton }
            if let button = button.first as? UIButton {
                button.isEnabled = false
            }
            commandButton.isHidden = true
        }
    }
    
    // MARK: - Key-Value Observer
    
    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(AVAudioSession.outputVolume) {
            print("Output  Volume Changed!!!JSK!!!!! ")

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
        } else if keyPath == "selectedTextRange" {
            // Determine if we adjust command bar
            self.adjustCommandBar()
        } else if keyPath == "isListeningForSpeech" {
            if let isListeningForSpeech = change?[.newKey] as? Bool, isListeningForSpeech {
                self.setCursorVisibility(as: isListeningForSpeech)
            } else if let isListeningForSpeech = change?[.newKey] as? Bool, !isListeningForSpeech {
                self.removeCursor()
                self.setCursorVisibility(as: false)
            }
        } else if keyPath == "hasSelection" {
            if let hasSelection = change?[.newKey] as? Bool, hasSelection && self.note.isListeningForSpeech && !self.note.pausedListeningForSpeech && !self.note.isListeningForCommands {
                // ====== Go from no selection to selection while recording ======
                //
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] timer in
                    // Determine if we present adjust rate buttons
                    self!.adjustCommandBar()
                }
                // Determine if we present transformation information
                self.handleTransformationsView()
                // We show command bar when successfully paused listening for speech
                // stop listening for speech, start listening for commands
                self.note.stopListeningForSpeech(pause: true) {
                    self.note.startListeningForVoiceCommands(
                        soundIntensityHandler: self.soundIntensityHandler!,
                        pitchHandler: self.pitchHandler!
                    )
                }
            } else if let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && self.note.isListeningForSpeech && self.note.pausedListeningForSpeech && self.note.isListeningForCommands && !self.note.isPlayingNote && !self.note.isPlayingEcho && !self.note.isPlayingPassiveEcho {
                // ====== Go from selection to no selection while recording ======
                //
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] timer in
                    // Determine if we present adjust rate buttons
                    self!.adjustCommandBar()
                }
                // Determine if we present transformation information
                self.handleTransformationsView()
                // start listening for speech again
                self.note.startListeningForSpeech(
                    soundIntensityHandler: self.soundIntensityHandler!,
                    pitchHandler: self.pitchHandler!
                )
                
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] timer in
                    // Update UI Text in case we have new transformations
                    self!.updateUIText(text: self!.note.getText(), transformations: self!.note.transformations)
                }
            } else if let hasSelection = change?[.newKey] as? Bool, hasSelection && !self.note.isListeningForSpeech && self.note.isListeningForCommands {
                // ====== Go from no selection to selection while not recording ======
                //
                // Determine if we present transformation information
                self.handleTransformationsView()
            } else if let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && !self.note.isListeningForSpeech && self.note.isListeningForCommands {
                // ====== Go from selection to no selection while not recording ======
                //
                // Determine if we present transformation information
                self.handleTransformationsView()
            }
        } else if keyPath == "clipboard" {
            if let clipboard = change?[.newKey] as? [NoteSegment]?, let _ = clipboard {
                self.adjustCommandBar()
                self.navigationItem.rightBarButtonItems = [self.getPasteClipboardButton()]
            } else {
                self.adjustCommandBar()
                self.navigationItem.rightBarButtonItems = nil
            }
        }
    }
    
    // MARK: - Touch Events
    
    @objc func handleSingleTap(touch: UITapGestureRecognizer) {
        print("===== Touch Interaction: Single Tap =====")
        if self.appActivated && self.note.isListeningForSpeech {
            print("\tDetermine text position near touch point...")
            let touchPoint = touch.location(in: self.textView)
            let textPosition = self.textView.closestPosition(to: touchPoint)
            
            if self.textView.selectedTextRange != nil && selectionCursor.hasSelection {
                // Remove Selection in view and model
                print("\tPrior selection detected. Remove Selection in view and model...")
                selectionCursor.clearSelection()
            }
            
            if let textPosition = textPosition {
                print("\tMove cursor to new position...")
                selectionCursor.moveCursor(textPosition: textPosition, cache: true)
            }
            
            self.adjustCommandBar()
        } else {
            print("\tAborted because app is not active or not listening for speech.")
        }
    }
    
    // Reference: https://www.appsdeveloperblog.com/create-uislider-in-swift-programmatically/
    // Reference: https://stackoverflow.com/questions/25499803/how-to-change-speech-rate-during-speaking-using-avspeechsynthesizer-in-ios-7
    @objc func sliderValueDidChange(_ sender: UISlider!) {
        print("===== Slider Value Changed =====")
        print("\tNew value: \(sender.value)")
        
        if self.sliderType == .playback {
            // Set new playback rate
            self.playbackRate = sender.value
            
            if self.note.isPlayingNote {
                let _ = Utils.setPlayerRate(player: self.note.player, rate: sender.value)
            }
        } else if self.sliderType == .echo {
            // Set new echo rate
            if self.note.isPlayingEcho || self.note.isPlayingPassiveEcho {
                // Activate update echo rate flag
                self.updateEchoRate = sender.value
            } else {
                // Set immediately
                self.echoRate = sender.value
            }
        }
    }
    
    // MARK: - Navigation Bar Methods
    
    @objc func handleToggleListening(_ sender: Any) {
        print("===== Handle Toggle Listening =====")
        if self.note.isListeningForCommands || (!self.appActivated && self.isListeningForWakePhrase) {
            // Stop Listening For Commands
            if self.appActivated {
                self.note.stopListeningForVoiceCommands() {
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
                self.note.startListeningForVoiceCommands(
                    soundIntensityHandler: self.soundIntensityHandler!,
                    pitchHandler: self.pitchHandler!
                )
            } else {
                self.startListeningForWakePhrase()
            }
        }
    }
    
    // MARK: - Menu Bar Methods

    @IBAction func handleStartNote(_ sender: Any) {
        print("===== Handle Start Note =====")
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if session.recordPermission != .granted || authStatus != .authorized {
            let alertController = UIAlertController(title: "Speech Recognition Permission Denied", message: "Please grant permission for application to initiate speech transcription.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Grant Permission", style: .default) { [unowned self] action in
                self.requestPermissions(handler: {
                    self.configureListeningForWakePhrase()
                })
            })
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alertController, animated: true)
            return
        }
        
        if authStatus == .authorized && session.recordPermission == .granted {
            if !note.isListeningForSpeech && !note.isExporting {
                if !self.note.isListeningForCommands {
                    // User switched off listening with the button
                    // Change button to normal again
                    
                }
                
                print("\tStarting Note...")
                note.startListeningForSpeech(
                    soundIntensityHandler: self.soundIntensityHandler!,
                    pitchHandler: self.pitchHandler!,
                    onStartHandler: {
                        DispatchQueue.main.async {
                            self.startRecordingUITimer(recording: true)
                            self.adjustCommandBar()
                            self.adjustMenuBar()
                        }
                    }
                )
            } else {
                print("\t[Error] There was a problem starting note. System does not have record permissions.")
            }
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleResumeNote(_ sender: Any) {
        print("===== Handle Resume Note =====")
        
        note.startListeningForSpeech(
            soundIntensityHandler: self.soundIntensityHandler!,
            pitchHandler: self.pitchHandler!,
            onStartHandler: {
                DispatchQueue.main.async {
                    self.startRecordingUITimer(recording: true)
                    self.adjustCommandBar()
                    self.adjustMenuBar()
                }
            }
        )
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }

    @IBAction func handleEditNote(_ sender: Any) {
        print("===== Handle Edit Note =====")
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if session.recordPermission != .granted || authStatus != .authorized {
            let alertController = UIAlertController(title: "Speech Recognition Permission Denied", message: "Please grant permission for application to initiate speech transcription.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Grant Permission", style: .default) { [unowned self] action in
                self.requestPermissions(handler: {
                    self.configureListeningForWakePhrase()
                })
            })
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alertController, animated: true)
            return
        }
        
        if authStatus == .authorized && session.recordPermission == .granted {
            if !note.isListeningForSpeech && !note.isExporting {
                print("\tStarting Note...")
                note.startListeningForSpeech(
                    soundIntensityHandler: self.soundIntensityHandler!,
                    pitchHandler: self.pitchHandler!,
                    onStartHandler: {
                        DispatchQueue.main.async {
                            self.startRecordingUITimer(recording: true)
                            self.adjustCommandBar()
                            self.adjustMenuBar()
                        }
                    }
                )
            } else {
                print("\t[Error] There was a problem starting note. System does not have record permissions.")
            }
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleStopListeningNote(_ sender: Any) {
        print("===== Stop Recording =====")
        if note.isListeningForSpeech && !note.isExporting {
            print("\tStopping Note...")
            note.stopListeningForSpeech() {[weak self] in
                self?.onNoteListenStop!()
                self?.adjustCommandBar()
                self?.adjustMenuBar()
            }
        } else {
            print("\t[Error] There was a problem stopping note. We're not listening for speech or are exporting note.")
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handlePlayNote(_ sender: Any) {
        print("===== Handle Play Note =====")
        self.note.play(
            onStartHandler: { [weak self] in
                // print("Successfully executed playback on start handler")
                DispatchQueue.main.async {
                    self?.adjustCommandBar()
                    self?.adjustMenuBar()
                }
            },
            secondElapseHandler: { [weak self] in
                // print("Successfully executed playback second elapsed handler")
                DispatchQueue.main.async {
                    if !self!.note.isListeningForSpeech && self!.note.player.currentTime().seconds != Double.infinity && self!.note.player.currentTime().seconds != Double.nan && self!.note.player.currentTime().seconds != -Double.infinity {
                        self?.navigationItem.title = "\(Utils.formattedTime(time: Float(self!.note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.note.getDuration(filteredDuration: true).seconds)))"
                    }
                }
            },
            segmentBoundaryHandler: { [weak self] in
                // print("Successfully executed playback on segment boundary handler")
                DispatchQueue.main.async {
                    if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
                        // update text
                        self?.updateUIText(text: self!.note.getText(), highlightRange: highlightRange, transformations: self!.note.transformations)
                    }
                    
                    if let segment = self?.note.getSegment(type: .current), let pitch = segment.getPitch() {
                        // update pitch
                        self?.pitchLabel.text = pitch.note.string
                    }
                }
            }, onFinishHandler: { [weak self] in
                // print("Successfully executed playback on finish handler")
                DispatchQueue.main.async {
                    self?.updateUIText(text: self!.note.getText(), transformations: self!.note.transformations)
                    self!.note.player.replaceCurrentItem(with: nil)
                    if !self!.note.isListeningForSpeech {
                        self?.navigationItem.title = ""
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                    }
                }
            }
        )
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }

    @IBAction func handleStopPlayingNote(_ sender: Any) {
        print("===== Handle Play Note =====")
        
        // Stop Note
        self.note.stop() { [weak self] in
            DispatchQueue.main.async {
                self?.adjustCommandBar()
                self?.adjustMenuBar()
            }
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handlePlayEcho(_ sender: Any) {
        print("==== Handle Play Echo =====")
        if self.note.pausedEcho {
            print("\tSpeech synthesizer continue speaking...")
            self.note.startEcho(
                text: self.note.getText(),
                onStartHandler: { [weak self] in
                    DispatchQueue.main.async {
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                    }
                }
            )
        } else {
            print("\tSpeech synthesizer starts speaking...")
            self.note.startEcho(
                text: self.note.getText(),
                onStartHandler: { [weak self] in
                    DispatchQueue.main.async {
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                    }
                }
            )
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleStopEcho(_ sender: Any) {
        if self.note.isPlayingEcho || self.note.isPlayingPassiveEcho {
            print("==== Speech synthesizer paused =====")

            self.note.stopEcho() { [weak self] in
                DispatchQueue.main.async {
                    self?.tempOnEchoFinish?()
                    self?.tempOnEchoFinish = nil
                    self?.adjustCommandBar()
                    self?.adjustMenuBar()
                }
            }
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleWalkNote(_ sender: Any) {
        print("===== Handle Walk Note =====")
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleExportNote(_ sender: Any) {
        print("===== Handle Export Note =====")
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    // MARK: - Resting Command Bar Methods
    @IBAction func handleMoveHere(_ sender: Any) {
        print("===== Handle Move Here =====")
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleRunNote(_ sender: Any) {
        print("===== Handle Run Note =====")
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handlePauseNote(_ sender: Any) {
        print("===== Handle Pause Note =====")
        if self.note.isPlayingNote {
            print("\tPausing Playing Note...")
            self.note.pause() {
                DispatchQueue.main.async {
                    self.adjustCommandBar()
                    self.adjustMenuBar()
                }
            }
        } else if self.note.isListeningForSpeech {
            print("\tPausing Listening Note....")
            self.note.pauseListeningForSpeech() {
                self.note.startListeningForVoiceCommands(
                    soundIntensityHandler: self.soundIntensityHandler!,
                    pitchHandler: self.pitchHandler!
                ) {
                    DispatchQueue.main.async {
                        self.adjustCommandBar()
                        self.adjustMenuBar()
                    }
                }
            }
        } else {
            print("\tUnhandled Branch")
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleLastCommit(_ sender: Any) {
        print("===== Handle Last Commit =====")
        
        let lastBufferRange = self.note.committedBufferRanges[self.note.committedBufferRanges.count - 1]
        let lastBuffer = self.note.noteSegments[lastBufferRange]
        let fromTime = lastBuffer.first!.timeMapping.target.start
        let toTime = lastBuffer.last!.timeMapping.target.end
        
        self.note.play(
            from: fromTime,
            to: toTime,
            onStartHandler: { [weak self] in
                // print("Successfully executed playback on start handler")
                DispatchQueue.main.async {
                    self?.adjustCommandBar()
                    self?.adjustMenuBar()
                }
            },
            secondElapseHandler: { [weak self] in
                // print("Successfully executed playback second elapsed handler")
                DispatchQueue.main.async {
                    if !self!.note.isListeningForSpeech && self!.note.player.currentTime().seconds != Double.infinity && self!.note.player.currentTime().seconds != Double.nan && self!.note.player.currentTime().seconds != -Double.infinity {
                        self?.navigationItem.title = "\(Utils.formattedTime(time: Float(self!.note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.note.getDuration(filteredDuration: true).seconds)))"
                    }
                }
            },
            segmentBoundaryHandler: { [weak self] in
                // print("Successfully executed playback on segment boundary handler")
                DispatchQueue.main.async {
                    if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
                        // update text
                        self?.updateUIText(text: self!.note.getText(), highlightRange: highlightRange, transformations: self!.note.transformations)
                    }
                    
                    if let segment = self?.note.getSegment(type: .current), let pitch = segment.getPitch() {
                        // update pitch
                        self?.pitchLabel.text = pitch.note.string
                    }
                }
            }, onFinishHandler: { [weak self] in
                // print("Successfully executed playback on finish handler")
                DispatchQueue.main.async {
                    self?.updateUIText(text: self!.note.getText(), transformations: self!.note.transformations)
                    self!.note.player.replaceCurrentItem(with: nil)
                    if !self!.note.isListeningForSpeech {
                        self?.navigationItem.title = ""
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                    }
                }
            }
        )
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handlePauseEcho(_ sender: Any) {
        print("===== Handle Pause Echo =====")
        self.note.pauseEcho() {
            self.adjustCommandBar()
            self.adjustMenuBar()
            
            if self.note.pausedListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                // when headphones are off we don't listen for voice commands while echoing
                // but on completion we turn it back on
                self.note.startListeningForVoiceCommands(
                    soundIntensityHandler: self.soundIntensityHandler!,
                    pitchHandler: self.pitchHandler!
                )
            }

            if self.note.pausedListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                // when headphones are off we don't listen for speech while echoing
                // but on completion we turn it back on
                self.note.startListeningForSpeech(
                    soundIntensityHandler: self.soundIntensityHandler!,
                    pitchHandler: self.pitchHandler!,
                    onStartHandler: {
                        DispatchQueue.main.async {
                            self.startRecordingUITimer(recording: true)
                            self.adjustCommandBar()
                            self.adjustMenuBar()
                        }
                    }
                )
            }
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handlePreviewClipboard(_ sender: Any) {
        print("===== Handle Preview Clipboard:  \(selectionCursor.clipboardText ?? "nil") =====")
        
        if let clipboardSelection = selectionCursor.clipboard, clipboardSelection.count > 0 {
            let selectionDuration = CMTimeSubtract(
                clipboardSelection.last!.timeMapping.target.start,
                clipboardSelection.first!.timeMapping.target.end
            )
            self.note.play(
                segments: clipboardSelection,
                onStartHandler: { [weak self] in
                    // print("Successfully executed playback on start handler")
                    DispatchQueue.main.async {
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                    }
                },
                secondElapseHandler: { [weak self] in
                    // print("Successfully executed playback second elapsed handler")
                    DispatchQueue.main.async {
                        if !self!.note.isListeningForSpeech && self!.note.player.currentTime().seconds != Double.infinity && self!.note.player.currentTime().seconds != Double.nan && self!.note.player.currentTime().seconds != -Double.infinity {
                            self?.navigationItem.title = "\(Utils.formattedTime(time: Float(self!.note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(selectionDuration.seconds)))"
                        }
                    }
                }, onFinishHandler: { [weak self] in
                    // print("Successfully executed playback on finish handler")
                    DispatchQueue.main.async {
                        self?.updateUIText(text: self!.note.getText(), transformations: self!.note.transformations)
                        self!.note.player.replaceCurrentItem(with: nil)
                        if !self!.note.isListeningForSpeech {
                            self?.navigationItem.title = ""
                            self?.adjustCommandBar()
                            self?.adjustMenuBar()
                        }
                    }
                }
            )
        } else {
            // havent recorded anything
            // Play Sound
            soundEngine.error()
            
            // Give haptic feedback
            hapticEngine.error()
            
            let errorHandler: () -> Void  = {
                // Delay error message to allow error earcon to complete
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {[weak self] timer in
                    let voice = Utils.getSynthesizerVoice(withGender: .female, vc: self)
                    let synthesizerItem = SynthesizerItem(
                        synthesizer: self!.speechSynthesizer,
                        text: "Clipboard is empty.",
                        voice: voice,
                        rate: self!.echoRate,
                        volume: self!.playbackVolume
                    )
                    
                    Utils.runSpeechSynthesizer(item: synthesizerItem)
                }
            }
            
            if self.note.isListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                self.note.stopListeningForVoiceCommands(pause: true) {
                    Utils.runError(note: self.note, handler: errorHandler)
                }
            } else if self.note.isListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
                self.note.stopListeningForSpeech(pause: true) {
                    Utils.runError(note: self.note, handler: errorHandler)
                }
            } else {
                Utils.runError(note: self.note, handler: errorHandler)
            }
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleSkipBackward(_ sender: Any) {
        print("===== Handle Skip Backward =====")
        let currentSegment = self.note.getSegment(type: .current)
        
        if let currentSegment = currentSegment, self.note.isPlayingNote {
            let time = CMTimeMake(
                value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
                timescale: Int32(Note.defaultSegmentTimescale)
            )
            self.note.skip(to: time)
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleSkipForward(_ sender: Any) {
        print("===== Handle Skip Forward =====")
        let currentSegment = self.note.getSegment(type: .current)
        
        if let currentSegment = currentSegment, self.note.isPlayingNote {
            let time = CMTimeMake(
                value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
                timescale: Int32(Note.defaultSegmentTimescale)
            )
            self.note.skip(to: time)
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handlePlaybackRate(_ sender: Any) {
        print("===== Handle Playback Rate =====")
        
        print("\tAdjusting flag to: true")
        self.sliderIsVisible = true
        self.sliderType = .playback
        
        print("\tSet Slider Min and Max Values...")
        self.slider.minimumValue = Utils.MINIMUM_PLAYBACK_RATE
        self.slider.maximumValue = Utils.MAXIMUM_PLAYBACK_RATE
        self.slider.value = self.playbackRate
        
        print("\tHide Command Bar...")
        self.setCommandBarVisibility(as: false)
        self.adjustCommandBar()
        
        print("\tShow Slider View...")
        Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) {[weak self] timer in
            self!.setSliderVisibility(as: true)
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleEchoRate(_ sender: Any) {
        print("===== Handle Echo Rate =====")
        
        print("\tAdjusting flag to: true")
        self.sliderIsVisible = true
        self.sliderType = .echo
        
        print("\tSet Slider Min and Max Values...")
        self.slider.minimumValue = Utils.MINIMUM_ECHO_RATE
        self.slider.maximumValue = Utils.MAXIMUM_ECHO_RATE
        self.slider.value = self.echoRate
        
        print("\tHide Command Bar...")
        self.setCommandBarVisibility(as: false)
        self.adjustCommandBar()
        
        print("\tShow Slider View...")
        Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
            self!.setSliderVisibility(as: true)
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleExitSlider(_ sender: Any) {
        print("===== Handle Exit Slider =====")
        
        print("\tAdjusting flag to: false")
        self.sliderIsVisible = false
        self.sliderType = nil
        
        print("\tHide Slider View...")
        self.setSliderVisibility(as: false)
        
        print("\tShow Command Bar...")
        Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
            self!.setCommandBarVisibility(as: true)
            self!.adjustCommandBar()
        }
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    // MARK: - Selection Methods

    @IBAction func handleIncreaseRateSelection(_ sender: Any) {
        print("===== Increase Rate Selection: \(selectionCursor.selectionText ?? "nil") =====")
        selectionCursor.adjustRateSelection(direction: .up)
        // Determine if we present adjust rate buttons
        self.adjustCommandBar()
        // Update transformation view
        self.handleTransformationsView()
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleDecreaseRateSelection(_ sender: Any) {
        print("===== Decrease Rate Selection: \(selectionCursor.selectionText ?? "nil") =====")
        selectionCursor.adjustRateSelection(direction: .down)
        // Determine if we present adjust rate buttons
        self.adjustCommandBar()
        // Update transformation view
        self.handleTransformationsView()
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }

    @IBAction func handleDeleteSelection(_ sender: Any) {
        print("===== Handle Delete Selection: \(selectionCursor.selectionText ?? "nil") =====")
        selectionCursor.deleteSelection()
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleReplaceSelection(_ sender: Any) {
        print("===== Handle Replace Selection: \(selectionCursor.selectionText ?? "nil") =====")
        
        // Turn on ambient track
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleCopySelection(_ sender: Any) {
        print("===== Handle Copy Selection: \(selectionCursor.selectionText ?? "nil") =====")
        selectionCursor.copySelection()
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @IBAction func handleCutSelection(_ sender: Any) {
        print("===== Handle Cut Selection: \(selectionCursor.selectionText ?? "nil") =====")
        selectionCursor.cutSelection()
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
    
    @objc func handlePasteClipboard(_ sender: Any) {
        print("===== Handle Paste Selection: \(selectionCursor.clipboardText ?? "nil") =====")
        selectionCursor.pasteSelection()
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }

    @IBAction func handleExportSelection(_ sender: Any) {
        print("===== Handle Export Selection: \(selectionCursor.selectionText ?? "nil") =====")
        selectionCursor.exportSelection()
        
        // Give haptic feedback
        hapticEngine.mediumImpact()
    }
}
    
// MARK: - Speech Recognition Delegate Extension

extension ViewController: SFSpeechRecognitionTaskDelegate {
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
                
                text = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if text.contains(self.wakePhrases[0]) || text.contains(self.wakePhrases[1]) || text.contains(self.wakePhrases[2]) { // wake word/phrase needs to be two words to get pitch data
                    self.stopListeningForWakePhrase() { [weak self] in
                        // Play Sound
                        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
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
                            note: self.note,
                            discardPrior: true
                        )
                    }
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
//                            note: self.note
//                        )
//                    }
                }

                return
            }
        }
    }
    
    func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        print("===== System has detected first incident of speech input =====")
    }
}

// MARK: - Speech Synthesizer Delegate Extension

extension ViewController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("===== Speech synthesis was cancelled =====")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("===== Paused speech synthesis successfully instructed to continue =====")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
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
        
        if !selectionCursor.hasSelection && !self.note.isPlayingPassiveEcho {
            // Avoid updating ui when selection
            // it will remove selection
            self.updateUIText(text: self.note.getText(), transformations: self.note.transformations)
        }
        
        if self.isExhaustingSynthesizerQueue {
            self.exhaustSynthesizerQueue()
        } else if self.note.isPlayingEcho {
            // turn off isPlayingEcho
            self.note.isPlayingEcho = false
            
            // Update View
            self.adjustCommandBar()
            self.adjustMenuBar()
            self.updateUIText(text: self.note.getText(), transformations: self.note.transformations)
        } else if self.note.isPlayingPassiveEcho && utterance.speechString == self.note.getText(segments: Array(self.note.noteSegments[self.note.lastEchoSegmentRange!])).trimTrailingPunctuation() {
            // turn off isPlayingPassiveEcho
            self.note.isPlayingPassiveEcho = false
            
            // Update View
            self.adjustCommandBar()
            self.adjustMenuBar()
            self.updateUIText(text: self.note.getText(), transformations: self.note.transformations)
        }

        self.tempOnEchoFinish?()
        self.tempOnEchoFinish = nil
        
        if self.appActivated && self.note.pausedListeningForCommands && !self.speechSynthesizer.isSpeaking && !AVAudioSession.isHeadphonesConnected {
            // when headphones are off we don't listen for voice commands while echoing
            // but on completion we turn it back on
            self.note.startListeningForVoiceCommands(
                soundIntensityHandler: self.soundIntensityHandler!,
                pitchHandler: self.pitchHandler!
            ) {
                // Call after isPlayingEcho is set to false by tempOnEchoFinish
                self.adjustCommandBar()
                self.adjustMenuBar()
            }
        }

        if self.appActivated && self.note.pausedListeningForSpeech && !self.speechSynthesizer.isSpeaking && !AVAudioSession.isHeadphonesConnected {
            // when headphones are off we don't listen for speech while echoing
            // but on completion we turn it back on
            self.note.startListeningForSpeech(
                soundIntensityHandler: self.soundIntensityHandler!,
                pitchHandler: self.pitchHandler!,
                onStartHandler: {
                    DispatchQueue.main.async {
                        self.startRecordingUITimer(recording: true)
                        // Call after isPlayingEcho is set to false by tempOnEchoFinish
                        self.adjustCommandBar()
                        self.adjustMenuBar()
                    }
                }
            )
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully paused =====")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully started: \(utterance.speechString) =====")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {        
        if self.appActivated && (self.note.isPlayingEcho || self.note.isPlayingPassiveEcho) && utterance.speechString == self.note.getText(segments: Array(self.note.noteSegments[self.note.lastEchoSegmentRange!])).trimTrailingPunctuation() {
            var textRange = characterRange
            // find lowest segment that is a word
            var lowestEchoSegment: NoteSegment?
            for segment in self.note.noteSegments[self.note.lastEchoSegmentRange!] {
                if !segment.isSilence() && !segment.isVoiceCommandWord() && !segment.isDeleted() {
                    lowestEchoSegment = segment
                    break
                }
            }

            if let lowestEchoSegment = lowestEchoSegment, let lowestEchoSegmentRange = self.note.getSegmentTextRange(of: lowestEchoSegment), self.note.isListeningForSpeech {
                textRange = NSRange(location: lowestEchoSegmentRange.location + characterRange.location, length: characterRange.length)
            }
            
            if !selectionCursor.hasSelection {
                // Avoid updating ui when selection
                // it will remove selection
                self.updateUIText(text: self.note.getText(), highlightRange: textRange, transformations: self.note.transformations)
            }
        }
        
        if let updateEchoRate = self.updateEchoRate, self.appActivated {
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
                voice: self.note.speaker.playbackVoice,
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
    func pitchEngine(_ pitchEngine: PitchEngine, didReceivePitch pitch: Pitch) {
        // TODO: Timing
        
        if let lastSoundIntensity = self.soundIntensityStream.last, pitch.frequency >= MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.getBackgroundNoise() != Double.infinity && self.soundIntensityStream.count > MIN_SEED_INTENSITY_POINTS && lastSoundIntensity.power > self.getBackgroundNoise() + Utils.TALKING_POWER_DELTA {
            // Add to pitch stream
            let pitchDatum = PitchDatum(date: Date(), pitch: pitch)
            self.pitchStream.append(pitchDatum)
            
            // Set speaker pitch
            if !self.appActivated {
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
                    note.setSpeakerPitch(to: avgPitch)
                } catch {
                    fatalError("===== [Error] There was a problem calculating average pitch =====")
                }
            }
        }
        
//        if let lastSoundIntensity = self.soundIntensityStream.last, pitch.frequency >= MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.getBackgroundNoise() != Double.infinity && self.soundIntensityStream.count > 0 && lastSoundIntensity.power > self.getBackgroundNoise() + Utils.VOLUME_POWER_DELTA {
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
// Instructions: Open app. Say wake phrase. Start note. Wait a minute without saying a word. Say words after a minute.
// Expected Result: No words should be transcribed before a minute. Words shold be transcribed after a minute. Session should be fluid.
//
// 11) Some words in a minute. More words after.
// Instructions: Open app. Say wake phrase. Start note. Say some words before a minute. Say more words after a minute.
// Expected Result: Some words should be transcribed before a minute. More words should be stranscribed after a minute. Session should be fluid. The timestamps should be accurate for each word.
//
// +++++ On-device recognition
// +++++ With and without headphoness
// TODO: set useOnDeviceRecognition = true
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
//                if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
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
//                self?.playAudioButton.setTitle(ViewController.PLAY_NOTE_LABEL, for: .normal)
//                self!.note.player.replaceCurrentItem(with: nil)
//                if self!.note.isListeningForSpeech {
//                    self?.navigationItem.title = ""
//                }
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
//                if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
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
//                self?.playAudioButton.setTitle(ViewController.PLAY_NOTE_LABEL, for: .normal)
//                self!.note.player.replaceCurrentItem(with: nil)
//                if self!.note.isListeningForSpeech {
//                    self?.navigationItem.title = ""
//                }
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
