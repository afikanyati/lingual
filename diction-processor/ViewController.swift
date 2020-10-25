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
    @IBOutlet weak var playButton: UIView!
    @IBOutlet weak var stopPlayingButton: UIView!
    @IBOutlet weak var echoButton: UIView!
    @IBOutlet weak var stopEchoButton: UIView!
    @IBOutlet weak var exportButton: UIView!
    @IBOutlet weak var walkButton: UIView!
    
    // ===== Command Bar =====
    
    // Resting Buttons
    @IBOutlet weak var runButton: UIView!
    @IBOutlet weak var pauseButton: UIView!
    
    // Conditional Buttons
    @IBOutlet weak var moveHereButton: UIView!
    @IBOutlet weak var inspectClipboardButton: UIView!
    @IBOutlet weak var playCommitButton: UIView!
    @IBOutlet weak var pauseEchoButton: UIView!
    @IBOutlet weak var skipBackwardButton: UIView!
    @IBOutlet weak var skipForwardButton: UIView!
    @IBOutlet weak var playbackRateButton: UIView!
    @IBOutlet weak var echoRateButton: UIView!
    
    // Selection Buttons
    @IBOutlet weak var increaseRateButton: UIView!
    @IBOutlet weak var decreaseRateButton: UIView!
    @IBOutlet weak var deleteSelectionButton: UIView!
    @IBOutlet weak var updateSelectionButton: UIView!
    @IBOutlet weak var cancelUpdateSelectionButton: UIView!
    @IBOutlet weak var copySelectionButton: UIView!
    @IBOutlet weak var cutSelectionButton: UIView!
    
    // Wake Phrase
    @IBOutlet weak var wakePhraseLabel: UILabel!
    @IBOutlet weak var wakePhraseSubtitleLabel: UILabel!
    
    // Text View
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var textViewPositionTop: NSLayoutConstraint!
    @IBOutlet weak var textViewPositionBottom: NSLayoutConstraint!
    
    // Indicators
    @IBOutlet weak var soundIntensityIndicator: UIView!
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
    
    // Walk
    @IBOutlet weak var walkNextElementButton: UIView!
    @IBOutlet weak var walkPreviousElementButton: UIView!
    @IBOutlet weak var exitWalkRunButton: UIView!
    
    // Run
    @IBOutlet weak var haltRunButton: UIView!

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
    var onNoteListenUpdate: ((_ text: String, _ bufferRange: NSRange?, _ highlightRange: NSRange?) -> Void)?
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
    
    // MARK: - Cached Properties
    var cachedTextViewSelectedRange: NSRange?
    
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
        self.prepareGeneralView()
        self.prepareCommandBar()
        self.prepareSlider()
        self.prepareTextView()
        self.adjustCommandBar()
        self.adjustMenuBar()
        self.transformationLabel.isHidden = true
        
        // Start listening for wake word
        self.configureListeningForWakePhrase()
        
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
        
        // add observer to isUpdatingSelection
        selectionCursor.addObserver(
            self,
            forKeyPath: "isUpdatingSelection",
            options: [.old, .new],
            context: nil
        )
        
        // add observer to isPromptingForUpdateAcceptance
        selectionCursor.addObserver(
            self,
            forKeyPath: "isPromptingForUpdateAcceptance",
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
        
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(self.handleSingleTap))
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
        
        // remove observer from isUpdatingSelection
        selectionCursor.removeObserver(
            self,
            forKeyPath: "isUpdatingSelection",
            context: nil
        )
        
        // remove observer from isPromptingForUpdateAcceptance
        selectionCursor.removeObserver(
            self,
            forKeyPath: "isPromptingForUpdateAcceptance",
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
        
        self.note.removeObserver(
            self,
            forKeyPath: "isWalkingNote",
            context: nil
        )
        
        self.note.removeObserver(
            self,
            forKeyPath: "isRunningNote",
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
            let dialogActions = [
                DialogAction(title: "Grant Permission", style: .default, handler: { [unowned self] action in
                    self.requestPermissions(handler: {
                        self.configureListeningForWakePhrase()
                    })
                }),
                DialogAction(title: "Cancel", style: .cancel, handler: nil)
            ]
            
            let dialogItem = DialogItem(
                title: "Speech Recognition Permission Denied",
                message: "Please grant permission for application to initiate speech transcription.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            Utils.presentDialog(dialogItem: dialogItem, vc: self)
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
    
    func prepareGeneralView() {
        self.soundIntensityIndicator.backgroundColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
        self.pitchLabel.textColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
        self.transformationLabel.textColor = UIColor(hex: Utils.LINGUAL_ORANGE) ?? UIColor.orange
    }
    
    func prepareCommandBar() {
        self.commandBar.backgroundColor = UIColor(hex: Utils.LINGUAL_PURPLE) ?? UIColor.purple
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
    
    // Reference: https://stackoverflow.com/questions/3231896/how-to-set-margins-padding-in-uitextview
    func prepareTextView() {
        // Set textContainer font size
        self.textView.font = self.font
        self.textView.textContainerInset = UIEdgeInsets(
            top: Utils.TEXT_VIEW_PADDING_TOP,
            left: Utils.TEXT_VIEW_PADDING_LEFT,
            bottom: Utils.TEXT_VIEW_PADDING_BOTTOM,
            right: Utils.TEXT_VIEW_PADDING_RIGHT
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
    
    func getDeleteNoteButton() -> UIBarButtonItem {
        let button  = UIButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 40.0)
        button.addTarget(self, action: #selector(self.resetSession), for: .touchUpInside)
        button.setImage(UIImage(systemName: "trash"), for: .normal)
        button.tintColor = UIColor.systemGray
        
        let barButton = UIBarButtonItem(customView: button)
        
        return barButton
    }
    
    func getPasteClipboardButton() -> UIBarButtonItem {
        let button  = UIButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 40.0)
        button.addTarget(self, action: #selector(self.pasteClipboard), for: .touchUpInside)
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
        self.onNoteListenUpdate = {[weak self] text, highlightRange, bufferRange in
            DispatchQueue.main.async {
                self?.updateUIText(text: text, highlightRange: highlightRange, bufferRange: bufferRange, transformations: self!.note.transformations)
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
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                soundEngine.saveNote()
            }

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
//        hapticEngine.mediumImpact()
        hapticEngine.success()

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
        
        note.addObserver(
            self,
            forKeyPath: "isWalkingNote",
            options: [.old, .new],
            context: nil
        )
        
        note.addObserver(
            self,
            forKeyPath: "isRunningNote",
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
            self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red]
            
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
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red]
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
        // Cache selection
        if let selectionTextRange = selectionCursor.selectionTextRange, selectionCursor.hasSelection {
            self.cachedTextViewSelectedRange = selectionTextRange
        }

        let mutableAttributedString = NSMutableAttributedString(string: text)

        if let bufferRange = bufferRange, bufferRange.length > 0 && text.count > 0 {
            // If passage is in buffer, we make gray text
            mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.systemGray, range: bufferRange)
        } else if let highlightRange = highlightRange, highlightRange.length > 0 && text.count > 0 {
            // If words in note are being echoed, we highlight them
            mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.white, range: highlightRange)
            mutableAttributedString.addAttribute(.backgroundColor, value: UIColor(hex: Utils.LINGUAL_PURPLE) ?? UIColor.purple, range: highlightRange)
        }
        
        // Emphasize all transformations text
        if let transformations = transformations {
            for transformation in transformations {
                mutableAttributedString.addAttribute(.foregroundColor, value: UIColor(hex: Utils.LINGUAL_ORANGE) ?? UIColor.orange, range: transformation.textRange)
            }
        }
        
        // Add all accumulated attributes to text object
        self.textView.attributedText = mutableAttributedString
        // Set font
        self.textView.font = self.font
        
        if let cachedTextViewSelectedRange = self.cachedTextViewSelectedRange {
            print("\t[updateUIText] Adding back cached selection text...")
            selectionCursor.manualSelection(range: cachedTextViewSelectedRange)
            self.cachedTextViewSelectedRange = nil
        }
        
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
                self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red]
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
        if (!self.note.isPlayingNote || (self.note.isPlayingNote && self.note.pausedPlayingNote) || (self.note.isPlayingNote && (self.note.isWalkingNote || self.note.isRunningNote))) && self.note.noteSegments.count > 0 && !(selectionCursor.hasSelection && !self.note.isWalkingNote && !self.note.isRunningNote) {
            self.showButton(self.playButton)
            
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.playButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Play Selection"
                }
            } else {
                let buttonLabel = self.playButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Play Note"
                }
            }
        } else {
            self.hideButton(self.playButton)
        }
        
        // Stop Playing Note Button
        if self.note.isPlayingNote && self.note.noteSegments.count > 0 && !(AVAudioSession.isHeadphonesConnected && selectionCursor.hasSelection) && !(AVAudioSession.isHeadphonesConnected && self.note.isWalkingNote) {
            self.showButton(self.stopPlayingButton)
            
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.stopPlayingButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Stop Selection"
                }
            } else {
                let buttonLabel = self.stopPlayingButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Stop Note"
                }
            }
        } else {
            self.hideButton(self.stopPlayingButton)
        }
        
        // Play Echo Button
        if (!(self.note.isPlayingEcho || self.note.isPlayingPassiveEcho) || (self.note.isPlayingEcho && self.note.pausedEcho) || (self.note.isPlayingEcho && (self.note.isWalkingNote || self.note.isRunningNote))) && self.note.noteSegments.count > 0 && !(selectionCursor.hasSelection && !self.note.isWalkingNote && !self.note.isRunningNote) {
            self.showButton(self.echoButton)
            
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.echoButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Echo Selection"
                }
            } else {
                let buttonLabel = self.echoButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Echo Note"
                }
            }
        } else {
            self.hideButton(self.echoButton)
        }

        // Stop Echo Button
        if (self.note.isPlayingEcho || self.note.isPlayingPassiveEcho) && self.note.noteSegments.count > 0 && !(selectionCursor.hasSelection && !self.note.isWalkingNote && !self.note.isRunningNote) {
            self.showButton(self.stopEchoButton)
        } else {
            self.hideButton(self.stopEchoButton)
        }
        
        // Export Note Button
        if self.note.noteSegments.count > 0 && !self.note.isListeningForSpeech {
            self.showButton(self.exportButton)
            
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.exportButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Export Selection"
                }
            } else {
                let buttonLabel = self.exportButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Export Note"
                }
            }
        } else {
            self.hideButton(self.exportButton)
        }
        
        // Walk Element Button
        if self.note.noteSegments.count > 0 {
            self.showButton(self.walkButton)
            
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.walkButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Walk Selection"
                }
            } else {
                let buttonLabel = self.walkButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Walk Note"
                }
            }
        } else {
            self.hideButton(self.walkButton)
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
        if self.note.noteSegments.count > 0 && !selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.runButton)
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.runButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Run Selection"
                }
            } else {
                let buttonLabel = self.runButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Run Note"
                }
            }
        } else {
            self.hideButton(self.runButton)
        }
        
        // Pause Note Button
        if self.note.noteSegments.count > 0 &&
            (
                (self.note.isListeningForSpeech && !self.note.pausedListeningForSpeech) ||
                (self.note.isPlayingNote && !self.note.pausedPlayingNote)
            ) && !selectionCursor.hasSelection && !self.note.isWalkingNote && !self.note.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.pauseButton)
            // Change text
            if selectionCursor.hasSelection {
                let buttonLabel = self.pauseButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Pause Selection"
                }
            } else {
                let buttonLabel = self.pauseButton.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel.first as? UILabel {
                    buttonLabel.text = "Pause Note"
                }
            }
        } else {
            self.hideButton(self.pauseButton)
        }
        
        // Playback Rate Button
        if self.note.noteSegments.count > 0 {
            numActiveButtons += 1
            self.showButton(self.playbackRateButton)
        } else {
            self.hideButton(self.playbackRateButton)
        }
        
        // Echo Rate Button
        if self.note.noteSegments.count > 0 {
            numActiveButtons += 1
            self.showButton(self.echoRateButton)
        } else {
            self.hideButton(self.echoRateButton)
        }
        
        // ===== Conditional Buttons =====
        
        // Move Here Button
        if self.note.isListeningForSpeech && (self.note.pausedPlayingNote || self.note.isPlayingNote || self.note.isPlayingEcho || self.note.pausedEcho) {
            numActiveButtons += 1
            self.showButton(self.moveHereButton)
        } else {
            self.hideButton(self.moveHereButton)
        }
        
        // Inspect Clipboard Button
        if let _ = selectionCursor.clipboard, self.note.isListeningForSpeech {
            numActiveButtons += 1
            self.showButton(self.inspectClipboardButton)
        } else {
            self.hideButton(self.inspectClipboardButton)
        }
        
        // Play Commit Button
        if self.note.committedBufferRanges.count > 0 && self.note.isListeningForSpeech {
            numActiveButtons += 1
            self.showButton(self.playCommitButton)
        } else {
            self.hideButton(self.playCommitButton)
        }
        
        // Pause Echo Button
        if self.note.isPlayingEcho && !self.note.pausedEcho && !selectionCursor.hasSelection && !self.note.isWalkingNote && !self.note.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.pauseEchoButton)
        } else {
            self.hideButton(self.pauseEchoButton)
        }
        
        // Skip Backward Button
        if self.note.isPlayingNote && !selectionCursor.hasSelection && !self.note.isWalkingNote && !self.note.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.skipBackwardButton)
        } else {
            self.hideButton(self.skipBackwardButton)
        }
        
        // Skip Forward Button
        if self.note.isPlayingNote && !selectionCursor.hasSelection && !self.note.isWalkingNote && !self.note.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.skipForwardButton)
        } else {
            self.hideButton(self.skipForwardButton)
        }
        
        // Previous Walk Element Button
        if self.note.isWalkingNote {
            numActiveButtons += 1
            self.showButton(self.walkPreviousElementButton)
        } else {
            self.hideButton(self.walkPreviousElementButton)
        }
        
        // Next Walk Element Button
        if self.note.isWalkingNote {
            numActiveButtons += 1
            self.showButton(self.walkNextElementButton)
        } else {
            self.hideButton(self.walkNextElementButton)
        }
        
        // Exit Walk Run Button
        if self.note.isWalkingNote || self.note.isRunningNote  {
            numActiveButtons += 1
            self.showButton(self.exitWalkRunButton)
        } else {
            self.hideButton(self.exitWalkRunButton)
        }
        
        // Halt Run Button
        if self.note.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.haltRunButton)
        } else {
            self.hideButton(self.haltRunButton)
        }
        
        // ===== Selection Buttons ======

        // Increase Rate Button
        if let firstSelectionSegment = selectionCursor.selectionSegments?.first, selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection && firstSelectionSegment.getRate() + Utils.DISCRETE_PLAYBACK_DELTA <= Utils.MAXIMUM_PLAYBACK_RATE  {
            numActiveButtons += 1
            self.showButton(self.increaseRateButton)
        } else {
            self.hideButton(self.increaseRateButton)
        }
        
        // Decrease Rate Button
        if let firstSelectionSegment = selectionCursor.selectionSegments?.first, selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection && firstSelectionSegment.getRate() - Utils.DISCRETE_PLAYBACK_DELTA >= Utils.MINIMUM_PLAYBACK_RATE {
            numActiveButtons += 1
            self.showButton(self.decreaseRateButton)
        } else {
            self.hideButton(self.decreaseRateButton)
        }
        
        // Delete Button
        if selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.deleteSelectionButton)
        } else {
            self.hideButton(self.deleteSelectionButton)
        }
        
        // Update Button
        if selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.updateSelectionButton)
        } else {
            self.hideButton(self.updateSelectionButton)
        }
        
        // Cancel Update Button
        if selectionCursor.hasSelection && selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.cancelUpdateSelectionButton)
        } else {
            self.hideButton(self.cancelUpdateSelectionButton)
        }
        
        // Copy Button
        if selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.copySelectionButton)
        } else {
            self.hideButton(self.copySelectionButton)
        }
        
        // Cut Button
        if selectionCursor.hasSelection && !selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.cutSelectionButton)
        } else {
            self.hideButton(self.cutSelectionButton)
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
            self.request!.contextualStrings = ["rise and shine"]
            
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
            Timer.scheduledTimer(withTimeInterval: Utils.LISTENING_LAUNCH_DELAY, repeats: false) { [weak self] timer in
                if let speechRecognizer = self?.speechRecognizer, self!.useOnDeviceRecognition && speechRecognizer.supportsOnDeviceRecognition {
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
                    Utils.presentDialog(dialogItem: dialogItem, vc: self!)
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
        self.playbackRate = rate

        if self.note.isPlayingNote {
            self.note.player.rate = self.playbackRate
        }
    }

    // sets relative to wpm of current note
    func setPlaybackRate(wpm: Float) {
        print("===== Set Playback Rate: \(wpm)wpm =====")
        self.playbackRate = wpm / Float(self.note.avgSpeakingRate).rounded(toPlaces: Utils.DEFAULT_FIG_COUNT)

        if self.note.isPlayingNote {
            self.note.player.rate = self.playbackRate
        }
    }
    
    // Implementing real-time rate change: https://stackoverflow.com/questions/25499803/how-to-change-speech-rate-during-speaking-using-avspeechsynthesizer-in-ios-7
    func setEchoRate(to rate: Float) {
        print("===== Set Echo Rate: \(rate) =====")
        self.echoRate = rate
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
            if let hasSelection = change?[.newKey] as? Bool, hasSelection && self.note.isListeningForSpeech {
                print("====== Go from no selection to selection while recording ======")
                // ====== Go from no selection to selection while recording ======
                //
                
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] timer in
                    // Determine if we present adjust rate buttons
                    self!.adjustCommandBar()
                    self!.adjustMenuBar()
                    self!.setCursorVisibility(as: false)
                }
                // Determine if we present transformation information
                self.handleTransformationsView()
                // We show command bar when successfully paused listening for speech
                // stop listening for speech, start listening for commands
                if !self.note.pausedListeningForSpeech {
                    self.note.stopListeningForSpeech(pause: true) {
                        self.note.startListeningForVoiceCommands(
                            soundIntensityHandler: self.soundIntensityHandler!,
                            pitchHandler: self.pitchHandler!
                        )
                    }
                } else if !self.note.isListeningForCommands {
                    self.note.startListeningForVoiceCommands(
                        soundIntensityHandler: self.soundIntensityHandler!,
                        pitchHandler: self.pitchHandler!
                    )
                }
            } else if let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && self.note.isListeningForSpeech && self.note.pausedListeningForSpeech && self.note.isListeningForCommands && !self.note.isPlayingNote && !self.note.isPlayingEcho && !self.note.isPlayingPassiveEcho {
                print("====== Go from selection to no selection while recording ======")
                // ====== Go from selection to no selection while recording ======
                //
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] timer in
                    // Determine if we present adjust rate buttons
                    self!.adjustCommandBar()
                    self!.adjustMenuBar()
                    self!.setCursorVisibility(as: true)
                }
                // Determine if we present transformation information
                self.handleTransformationsView()
                // start listening for speech again
                if self.note.pausedListeningForSpeech {
                    self.note.startListeningForSpeech(
                        soundIntensityHandler: self.soundIntensityHandler!,
                        pitchHandler: self.pitchHandler!
                    )
                }
                
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] timer in
                    // Update UI Text in case we have new transformations
                    self!.updateUIText(text: self!.note.getText(), transformations: self!.note.transformations)
                }
            } else if let hasSelection = change?[.newKey] as? Bool, hasSelection && !self.note.isListeningForSpeech && self.note.isListeningForCommands {
                print("====== Go from no selection to selection while not recording ======")
                // ====== Go from no selection to selection while not recording ======
                //
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] timer in
                    // Determine if we present adjust rate buttons
                    self!.adjustCommandBar()
                    self!.adjustMenuBar()
                }
                // Determine if we present transformation information
                self.handleTransformationsView()
            } else if let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && !self.note.isListeningForSpeech && self.note.isListeningForCommands {
                print("====== Go from selection to no selection while not recording ======")
                // ====== Go from selection to no selection while not recording ======
                //
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] timer in
                    // Determine if we present adjust rate buttons
                    self!.adjustCommandBar()
                    self!.adjustMenuBar()
                }
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
        } else if keyPath == "isUpdatingSelection" {
            // Determine if we adjust command bar
            self.adjustCommandBar()
            self.adjustMenuBar()
        } else if keyPath == "isPromptingForUpdateAcceptance" {
            // Determine if we adjust command bar
            self.adjustCommandBar()
            self.adjustMenuBar()
        } else if keyPath == "isWalkingNote" {
            // Determine if we adjust command bar
            self.adjustCommandBar()
            self.adjustMenuBar()
        } else if keyPath == "isRunningNote" {
            // Determine if we adjust command bar
            self.adjustCommandBar()
            self.adjustMenuBar()
        }
    }
    
    // MARK: - Touch Events
    
    @objc func handleSingleTap(touch: UITapGestureRecognizer) {
        print("===== Touch Interaction: Single Tap =====")
        if self.appActivated && self.note.isListeningForSpeech {
            print("\tDetermine text position near touch point...")
            let touchPoint = touch.location(in: self.textView)
            let textPosition = self.textView.closestPosition(to: touchPoint)
            
            if self.textView.selectedTextRange != nil && selectionCursor.hasSelection && (self.note.isWalkingNote || self.note.isRunningNote) {
                // Remove Selection in view and model
                print("\tPrior selection detected. Remove Selection in view and model...")
                self.note.exitWalk(withFeedback: false)
            } else if self.textView.selectedTextRange != nil && selectionCursor.hasSelection {
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
        print("===== Screen Button: Slider Value Changed =====")
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
        print("===== Screen Button: Handle Toggle Listening =====")
        
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
    
    @IBAction func startNote(_ sender: Any? = nil) {
        self.handleStartNote()
    }

    func handleStartNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Start Note =====")
        } else {
            print("===== Voice Command: Handle Start Note =====")
        }
        
        if self.note.isListeningForSpeech {
            Utils.executeError(note: self.note, text: "Note already started.", voiceCommand: voiceCommand)
        }
        
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if session.recordPermission != .granted || authStatus != .authorized {
            let dialogActions = [
                DialogAction(title: "Grant Permission", style: .default, handler: { [unowned self] action in
                    self.requestPermissions(handler: {
                        self.configureListeningForWakePhrase()
                    })
                }),
                DialogAction(title: "Cancel", style: .cancel, handler: nil)
            ]
            
            let dialogItem = DialogItem(
                title: "Speech Recognition Permission Denied",
                message: "Please grant permission for application to initiate speech transcription.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            Utils.presentDialog(dialogItem: dialogItem, vc: self)
            
            return
        }
        
        if authStatus == .authorized && session.recordPermission == .granted {
            if !note.isListeningForSpeech && !note.isExporting {
                if !self.note.isListeningForCommands {
                    // User switched off listening with the button
                    // Change button to normal again
                }
                
                if voiceCommand {
                    // Play Sound
                    soundEngine.voiceCommandAccept()
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
                if self.note.isListeningForSpeech {
                    Utils.executeError(note: self.note, text: "Note already started.", voiceCommand: voiceCommand)
                } else {
                    Utils.executeError(note: self.note, text: "Wait until note export completion.", voiceCommand: voiceCommand)
                }
                print("\t[Error] There was a problem starting note. System does not have record permissions.")
            }
        } else {
            Utils.executeError(note: self.note, text: "Unable to start note.", voiceCommand: voiceCommand)
            print("\t[Error] There was a problem starting note. System does not have record permissions.")
        }
    }
    
    @IBAction func resumeNote(_ sender: Any? = nil) {
        self.handleResumeNote()
    }
    
    func handleResumeNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Resume Note =====")
        } else {
            print("===== Voice Command: Handle Resume Note =====")
        }
        
        if self.note.isListeningForSpeech && self.note.pausedListeningForSpeech && self.note.isListeningForCommands {
            if voiceCommand {
                // Play Sound
                soundEngine.voiceCommandAccept()
            }

            note.startListeningForSpeech(
                soundIntensityHandler: self.soundIntensityHandler!,
                pitchHandler: self.pitchHandler!,
                onStartHandler: {
                    DispatchQueue.main.async {
                        self.startRecordingUITimer(recording: true)
                        self.adjustCommandBar()
                        self.adjustMenuBar()
                        handler?()
                    }
                }
            )
        } else {
            Utils.executeError(note: self.note, text: "No ongoing note.", handler: handler)
            return
        }
    }
    
    @IBAction func editNote(_ sender: Any? = nil) {
        self.handleEditNote()
    }

    func handleEditNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Edit Note =====")
        } else {
            print("===== Voice Command: Handle Edit Note =====")
        }
        
        if self.note.noteSegments.count == 0 {
            Utils.executeError(note: self.note, text: "No existing note.", voiceCommand: voiceCommand, handler: handler)
        }
        
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if session.recordPermission != .granted || authStatus != .authorized {
            let dialogActions = [
                DialogAction(title: "Grant Permission", style: .default, handler: { [unowned self] action in
                    self.requestPermissions(handler: {
                        self.configureListeningForWakePhrase()
                    })
                }),
                DialogAction(title: "Cancel", style: .cancel, handler: nil)
            ]
            
            let dialogItem = DialogItem(
                title: "Speech Recognition Permission Denied",
                message: "Please grant permission for application to initiate speech transcription.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            Utils.presentDialog(dialogItem: dialogItem, vc: self)
            
            handler?()
            return
        }
        
        if authStatus == .authorized && session.recordPermission == .granted {
            if !note.isListeningForSpeech && !note.isExporting {
                if voiceCommand {
                    // Play Sound
                    soundEngine.voiceCommandAccept()
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
                            handler?()
                        }
                    }
                )
            } else {
                Utils.executeError(note: self.note, text: "Unable to start note.", voiceCommand: voiceCommand, handler: handler)
                print("\t[Error] There was a problem starting note. System does not have record permissions.")
            }
        }
    }
    
    @IBAction func stopListeningNote(_ sender: Any? = nil) {
        self.handleStopListeningNote()
    }
    
    func handleStopListeningNote(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Stop Listening Note =====")
        } else {
            print("===== Voice Command: Stop Listening Note =====")
        }
        
        if note.isListeningForSpeech && !note.isExporting {
            print("\tStopping Note...")
            if voiceCommand {
                // No sound here
                // We omit sound for stopping note
            }

            note.stopListeningForSpeech() {[weak self] in
                self?.onNoteListenStop!()
                self?.adjustCommandBar()
                self?.adjustMenuBar()
                handler?()
            }
        } else {
            if !self.note.isListeningForSpeech {
                Utils.executeError(note: self.note, text: "No ongoing note.", voiceCommand: voiceCommand, handler: handler)
            } else {
                Utils.executeError(note: self.note, text: "Wait until note export completion.", voiceCommand: voiceCommand, handler: handler)
            }
            print("\t[Error] There was a problem stopping note. We're not listening for speech or are exporting note.")
        }
    }
    
    @IBAction func play(_ sender: Any? = nil) {
        self.handlePlay()
    }
    
    // Should never be called when headphones on while we have a selection
    // Will be looping selection and have isPlayingNote set to true
    // Which should hide playButton
    func handlePlay(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Play \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Play \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let playSegments: (_ segments: [NoteSegment]) -> Void = { segments in
            self.note.play(
                segments: segments,
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
                        if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
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
                        if !self!.note.isListeningForSpeech {
                            self?.navigationItem.title = ""
                        }
                        
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                        
                        if self!.note.pausedWalkingNote {
                            self?.note.walk() {
                                handler?()
                            }
                        } else if self!.note.pausedRunningNote {
                            self?.note.run() {
                                handler?()
                            }
                        } else {
                            handler?()
                        }
                    }
                }
            )
        }
        
        let executePlay = {
            if self.note.pausedWalkingNote || self.note.pausedRunningNote {
                playSegments(Array(self.note.noteSegments[self.note.walkingRange!]))
            } else if let selectionSegments = selectionCursor.selectionSegments, selectionCursor.hasSelection {
                playSegments(selectionSegments)
            } else {
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
                            if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
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
                            if !self!.note.isListeningForSpeech {
                                self?.navigationItem.title = ""
                            }
                            
                            self?.adjustCommandBar()
                            self?.adjustMenuBar()
                            
                            if self!.note.pausedWalkingNote {
                                self?.note.walk() {
                                    handler?()
                                }
                            } else if self!.note.pausedRunningNote {
                                self?.note.run() {
                                    handler?()
                                }
                            } else {
                                handler?()
                            }
                        }
                    }
                )
            }
        }
        
        if self.note.isWalkingNote || self.note.isRunningNote {
            self.note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                if self.note.isPlayingNote {
                    self.note.stop() {
                        executePlay()
                    }
                } else {
                    executePlay()
                }
            }
        } else if self.note.isPlayingNote {
            self.note.stop() {
                executePlay()
            }
        } else {
            executePlay()
        }
    }
    
    @IBAction func stopPlaying(_ sender: Any? = nil) {
        self.handleStopPlaying()
    }

    func handleStopPlaying(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Playing \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Playing \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Stop Note
        self.note.stop() { [weak self] in
            DispatchQueue.main.async {
                self?.adjustCommandBar()
                self?.adjustMenuBar()
                if self!.note.pausedWalkingNote {
                    self?.note.walk() {
                        handler?()
                    }
                } else if self!.note.pausedRunningNote {
                    self?.note.run() {
                        handler?()
                    }
                } else {
                    handler?()
                }
            }
        }
    }
    
    @IBAction func echo(_ sender: Any? = nil) {
        self.handleEcho()
    }
    
    func handleEcho(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("==== Screen Button: Handle Echo \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("==== Voice Command: Handle Echo \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let executeEcho = {
            print("\tSpeech synthesizer \(self.note.pausedEcho ? "continue" : "starts") speaking...")
            var segments: [NoteSegment]
            if self.note.pausedWalkingNote || self.note.pausedRunningNote {
                segments = Array(self.note.noteSegments[self.note.walkingRange!])
            } else if selectionCursor.hasSelection {
                segments = selectionCursor.selectionSegments!
            } else {
                segments = self.note.noteSegments
            }
            self.note.startEcho(
                segments: segments,
                onStartHandler: { [weak self] in
                    DispatchQueue.main.async {
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                    }
                },
                onFinishHandler: { [weak self] in
                    DispatchQueue.main.async {
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                        if self!.note.pausedWalkingNote {
                            self?.note.walk() {
                                handler?()
                            }
                        } else if self!.note.pausedRunningNote {
                            self?.note.run() {
                                handler?()
                            }
                        } else {
                            handler?()
                        }
                    }
                }
            )
        }
        
        if self.note.isWalkingNote || self.note.isRunningNote {
            self.note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                if self.note.isPlayingEcho {
                    self.note.stopEcho() {
                        executeEcho()
                    }
                } else {
                    executeEcho()
                }
            }
        } else if self.note.isPlayingEcho {
            self.note.stopEcho() {
                executeEcho()
            }
        } else {
            executeEcho()
        }
    }
    
    @IBAction func stopEcho(_ sender: Any? = nil) {
        self.handleStopEcho()
    }
    
    func handleStopEcho(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Stop Echo =====")
        } else {
            print("===== Voice Command: Handle Stop Echo =====")
        }
        
        if !note.isPlayingEcho && !note.isPlayingPassiveEcho {
            Utils.executeError(note: self.note, text: "Note not being echoed.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if self.note.isPlayingEcho || self.note.isPlayingPassiveEcho {
            self.note.stopEcho() { [weak self] in
                DispatchQueue.main.async {
                    self?.adjustCommandBar()
                    self?.adjustMenuBar()
                    if self!.note.pausedWalkingNote {
                        self?.note.walk() {
                            handler?()
                        }
                    } else if self!.note.pausedRunningNote {
                        self?.note.run() {
                            handler?()
                        }
                    } else {
                        handler?()
                    }
                }
            }
        }
    }
    
    @IBAction func walk(_ sender: Any? = nil) {
        self.handleWalk()
    }
    
    func handleWalk(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Walk \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Walk \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if let selectionSegments = selectionCursor.selectionSegments, selectionCursor.hasSelection {
            // Walk Selection
            note.walk(segments: selectionSegments, onStartHandler: handler)
        } else {
            // Walk Note
            note.walk(onStartHandler: handler)
        }
    }
    
    @IBAction func export(_ sender: Any? = nil) {
        self.handleExport()
    }
    
    func handleExport(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Export \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Export \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if selectionCursor.hasSelection {
            // Export Selection
        } else {
            // Export Note
        }
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
    
    // MARK: - Resting Command Bar Methods
    
    @IBAction func moveHere(_ sender: Any? = nil) {
        self.handleMoveHere()
    }
    
    func handleMoveHere(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Move Here =====")
        } else {
            print("===== Voice Command: Handle Move Here =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
    
    @IBAction func run(_ sender: Any? = nil) {
        self.handleRun()
    }
    
    func handleRun(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Run \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Run \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if let selectionSegments = selectionCursor.selectionSegments, selectionCursor.hasSelection {
            // Run Selection
            note.run(segments: selectionSegments, onStartHandler: handler)
        } else {
            // Run Note
            note.run(onStartHandler: handler)
        }
    }
    
    @IBAction func pause(_ sender: Any? = nil) {
        self.handlePause()
    }
    
    func handlePause(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Pause \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        } else {
            print("===== Voice Command: Handle Pause \(selectionCursor.hasSelection ? "Selection" : "Note") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        if self.note.isPlayingNote {
            print("\tPausing Playing Note...")
            self.note.pause() {
                DispatchQueue.main.async {
                    self.adjustCommandBar()
                    self.adjustMenuBar()
                    handler?()
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
                        handler?()
                    }
                }
            }
        } else {
            print("\tUnhandled Branch")
        }
    }
    
    @IBAction func playCommit(_ sender: Any? = nil) {
        self.handlePlayCommit()
    }
    
    func handlePlayCommit(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Play Commit =====")
        } else {
            print("===== Voice Command: Handle Play Commit =====")
        }
        
        if note.committedBufferRanges.count == 0 {
            Utils.executeError(note: self.note, text: "No previous commits.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let executePlay = {
            let commit = self.note.getLastCommit()
            print("\tLast Commit: ", self.note.getText(segments: commit))
            guard let lastCommit = commit else {
                Utils.executeError(note: self.note, text: "Unable to find last commit.", handler: handler)
                return
            }
            let fromTime = lastCommit.first!.timeMapping.target.start
            let toTime = lastCommit.last!.timeMapping.target.end
            
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
                        if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && segment.isActive(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
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
                        if !self!.note.isListeningForSpeech {
                            self?.navigationItem.title = ""
                        }
                        
                        self?.adjustCommandBar()
                        self?.adjustMenuBar()
                        if self!.note.pausedWalkingNote {
                            self?.note.walk() {
                                handler?()
                            }
                        } else if self!.note.pausedRunningNote {
                            self?.note.run() {
                                handler?()
                            }
                        } else {
                            handler?()
                        }
                    }
                }
            )
        }
        
        if self.note.isWalkingNote || self.note.isRunningNote {
            self.note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                if self.note.isPlayingNote {
                    self.note.stop() {
                        executePlay()
                    }
                } else {
                    executePlay()
                }
            }
        } else if self.note.isPlayingNote {
            self.note.stop() {
                executePlay()
            }
        } else {
            executePlay()
        }
    }
    
    @IBAction func pauseEcho(_ sender: Any? = nil) {
        self.handlePauseEcho()
    }
    
    func handlePauseEcho(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Pause Echo =====")
        } else {
            print("===== Voice Command: Handle Pause Echo =====")
        }
        
        if !self.note.isPlayingEcho {
            Utils.executeError(note: self.note, text: "Note not being echoed.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        self.note.pauseEcho() {
            self.adjustCommandBar()
            self.adjustMenuBar()
            
            if self.note.pausedListeningForCommands && !AVAudioSession.isHeadphonesConnected {
                // when headphones are off we don't listen for voice commands while echoing
                // but on completion we turn it back on
                self.note.startListeningForVoiceCommands(
                    soundIntensityHandler: self.soundIntensityHandler!,
                    pitchHandler: self.pitchHandler!,
                    onStartHandler: {
                        DispatchQueue.main.async {
                            self.adjustCommandBar()
                            self.adjustMenuBar()
                            handler?()
                        }
                    }
                )
            } else if self.note.pausedListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
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
                            handler?()
                        }
                    }
                )
            }
        }
    }
    
    @IBAction func inspectClipboard(_ sender: Any? = nil) {
        self.handleInspectClipboard()
    }
    
    func handleInspectClipboard(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Inspect Clipboard:  \(selectionCursor.clipboardText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Inspect Clipboard:  \(selectionCursor.clipboardText ?? "nil") =====")
        }
        
        if let clipboardSelection = selectionCursor.clipboard, clipboardSelection.count > 0 {
            if voiceCommand {
                // Play Sound
                soundEngine.voiceCommandAccept()
            }

            let executePlay = {
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
                            if !self!.note.isListeningForSpeech {
                                self?.navigationItem.title = ""
                            }
                            
                            self?.adjustCommandBar()
                            self?.adjustMenuBar()
                            if self!.note.pausedWalkingNote {
                                self?.note.walk() {
                                    handler?()
                                }
                            } else if self!.note.pausedRunningNote {
                                self?.note.run() {
                                    handler?()
                                }
                            } else {
                                handler?()
                            }
                        }
                    }
                )
            }
            
            if self.note.isWalkingNote || self.note.isRunningNote {
                self.note.exitWalk(pause: true, clearSelection: false, withFeedback: false) {
                    if self.note.isPlayingNote {
                        self.note.stop() {
                            executePlay()
                        }
                    } else {
                        executePlay()
                    }
                }
            } else if self.note.isPlayingNote {
                self.note.stop() {
                    executePlay()
                }
            } else {
                executePlay()
            }
        } else {
            // havent recorded anything
            Utils.executeError(note: self.note, text:  "Clipboard is empty.", handler: handler)
            return
        }
    }
    
    @IBAction func skipBackward(_ sender: Any? = nil) {
        self.handleSkipBackward()
    }
    
    func handleSkipBackward(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Skip Backward =====")
        } else {
            print("===== Voice Command: Handle Skip Backward =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let currentSegment = self.note.getSegment(type: .current)
        
        if let currentSegment = currentSegment, self.note.isPlayingNote, CMTimeMake(
            value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Note.defaultSegmentTimescale)
        ) > CMTime.zero {
            let time = CMTimeMake(
                value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
                timescale: Int32(Note.defaultSegmentTimescale)
            )
            self.note.skip(to: time)
        } else if let currentSegment = currentSegment, self.note.isPlayingNote, CMTimeMake(
            value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds - Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Note.defaultSegmentTimescale)
        ) <= CMTime.zero {
            // Will skip past end of track
            Utils.executeError(note: self.note, text: "Skipping would exceed duration", handler: handler)
        }
        
        handler?()
    }
    
    @IBAction func skipForward(_ sender: Any? = nil) {
        self.handleSkipForward()
    }
    
    func handleSkipForward(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Skip Forward =====")
        } else {
            print("===== Voice Command: Handle Skip Forward =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        let currentSegment = self.note.getSegment(type: .current)
        
        if let currentSegment = currentSegment, let currentItem = self.note.player.currentItem, self.note.isPlayingNote, CMTimeMake(
            value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Note.defaultSegmentTimescale)
        ) < currentItem.duration {
            let time = CMTimeMake(
                value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
                timescale: Int32(Note.defaultSegmentTimescale)
            )
            self.note.skip(to: time)
        } else if let currentSegment = currentSegment, let currentItem = self.note.player.currentItem, self.note.isPlayingNote, CMTimeMake(
            value: Int64(Note.defaultSegmentTimescale * (currentSegment.timeMapping.target.start.seconds + Utils.SKIP_PLAYBACK_DURATION)),
            timescale: Int32(Note.defaultSegmentTimescale)
        ) >= currentItem.duration {
            // Will skip past end of track
            Utils.executeError(note: self.note, text: "Skipping would exceed duration", handler: handler)
        }
        
        handler?()
    }
    
    @IBAction func playbackRate(_ sender: Any? = nil) {
        self.handlePlaybackRate()
    }
    
    func handlePlaybackRate(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Playback Rate =====")
        } else {
            print("===== Voice Command: Handle Playback Rate =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
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
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
    
    @IBAction func echoRate(_ sender: Any? = nil) {
        self.handleEchoRate()
    }
    
    func handleEchoRate(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Echo Rate =====")
        } else {
            print("===== Voice Command: Handle Echo Rate =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
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
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
    
    @IBAction func exitSlider(_ sender: Any? = nil) {
        self.handleExitSlider()
    }
    
    func handleExitSlider(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Exit Slider =====")
        } else {
            print("===== Voice Command: Handle Exit Slider =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Present Feedback
        if self.sliderType == .playback {
            Utils.executeFeedback(
                visualMessage: "Playback Rate: \(self.playbackRate)x",
                audioMessage: "Set playback rate to \(self.playbackRate)x.",
                note: self.note,
                withHaptics: true
            )
        } else {
            Utils.executeFeedback(
                visualMessage: "Echo rate: \(self.echoRate)x",
                audioMessage: "Set echo rate to \(self.echoRate)x.",
                note: self.note,
                withHaptics: true
            )
        }
        
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
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
    }
    
    @IBAction func walkNextElement(_ sender: Any? = nil) {
        self.handleWalkNextElement()
    }
    
    func handleWalkNextElement(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Walk Next Element =====")
        } else {
            print("===== Voice Command: Handle Walk Next Element =====")
        }
        
        if !self.note.isWalkingNote {
            Utils.executeError(note: self.note, text: "Not walking note or selection.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        self.note.walkToNextSegment(handler: handler)

        handler?()
    }
    
    @IBAction func walkPreviousElement(_ sender: Any? = nil) {
        self.handleWalkPreviousElement()
    }
    
    func handleWalkPreviousElement(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Walk Previous Element =====")
        } else {
            print("===== Voice Command: Handle Walk Previous Element =====")
        }
        
        if !self.note.isWalkingNote {
            Utils.executeError(note: self.note, text: "Not walking note or selection.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        self.note.walkToPreviousSegment(handler: handler)
        
        handler?()
    }
    
    @IBAction func haltRun(_ sender: Any? = nil) {
        self.handleHaltRun()
    }
    
    func handleHaltRun(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Halt Run =====")
        } else {
            print("===== Voice Command: Handle Halt Run =====")
        }
        
        if !self.note.isRunningNote {
            Utils.executeError(note: self.note, text: "Not running note or selection.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        self.note.haltRun(handler: handler)
        
        handler?()
    }
    
    @IBAction func exitWalkRun(_ sender: Any? = nil) {
        self.handleExitWalkRun()
    }
    
    func handleExitWalkRun(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Exit Walk or Run =====")
        } else {
            print("===== Voice Command: Handle Exit Walk or Run =====")
        }
        
        if !self.note.isWalkingNote && !self.note.isRunningNote {
            Utils.executeError(note: self.note, text: "Not walking or running note or selection.", handler: handler)
            return
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        self.note.exitWalk(handler: handler)
    }

    // MARK: - Selection Methods

    @IBAction func increaseRateSelection(_ sender: Any? = nil) {
        self.handleIncreaseRateSelection()
    }

    func handleIncreaseRateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Increase Rate Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Increase Rate Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.adjustRateSelection(direction: .up)
        // Determine if we present adjust rate buttons
        self.adjustCommandBar()
        // Update transformation view
        self.handleTransformationsView()
        
        handler?()
    }
    
    @IBAction func decreaseRateSelection(_ sender: Any? = nil) {
        self.handleDecreaseRateSelection()
    }
    
    func handleDecreaseRateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Decrease Rate Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Decrease Rate Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.adjustRateSelection(direction: .down)
        // Determine if we present adjust rate buttons
        self.adjustCommandBar()
        // Update transformation view
        self.handleTransformationsView()
        
        handler?()
    }
    
    @IBAction func deleteSelection(_ sender: Any? = nil) {
        self.handleDeleteSelection()
    }

    func handleDeleteSelection(voiceCommand: Bool = false, isCommit: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Delete \(isCommit ? "Commit" : "Selection"): \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Delete \(isCommit ? "Commit" : "Selection"): \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.deleteSelection(isCommit: isCommit, handler: handler)
    }
    
    @IBAction func updateSelection(_ sender: Any? = nil) {
        self.handleUpdateSelection()
    }
    
    func handleUpdateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Update Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Update Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Turn on ambient track
        if !soundEngine.isPlayingModalAmbience {
            soundEngine.startModalAmbience()
        }
        
        // Execute update selection
        selectionCursor.initiateUpdateSelection()

        // Determine if we present adjust rate buttons
        self.adjustCommandBar()
        
        handler?()
    }
    
    @IBAction func cancelUpdateSelection(_ sender: Any? = nil) {
        self.handleCancelUpdateSelection()
    }
    
    func handleCancelUpdateSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Cancel Update Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Cancel Update Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        // Turn off ambient track
        soundEngine.stopModalAmbience()
        
        // Clear buffer segments
        print("\tClearing note buffer...")
        self.note.clearBuffer()
        
        // Cancel Update Selection
        selectionCursor.cancelUpdateSelection()
        
        // Determine if we present adjust rate buttons
        self.adjustCommandBar()

        handler?()
    }
    
    @IBAction func copySelection(_ sender: Any? = nil) {
        self.handleCopySelection()
    }

    func handleCopySelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Copy Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Copy Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.copySelection()
        
        handler?()
    }
    
    @IBAction func cutSelection(_ sender: Any? = nil) {
        self.handleCutSelection()
    }
    
    func handleCutSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Cut Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Cut Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.cutSelection()
        
        handler?()
    }
    
    // Reference: https://stackoverflow.com/questions/43251708/passing-arguments-to-selector-in-swift
    @objc func pasteClipboard(_ sender: Any? = nil) {
        self.handlePasteClipboard()
    }
    
    func handlePasteClipboard(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Paste Selection: \(selectionCursor.clipboardText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Paste Selection: \(selectionCursor.clipboardText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.pasteSelection()

        handler?()
    }
    
    @IBAction func exportSelection(_ sender: Any? = nil) {
        self.handleExportSelection()
    }

    func handleExportSelection(voiceCommand: Bool = false, handler: (() -> Void)? = nil) {
        if !voiceCommand {
            print("===== Screen Button: Handle Export Selection: \(selectionCursor.selectionText ?? "nil") =====")
        } else {
            print("===== Voice Command: Handle Export Selection: \(selectionCursor.selectionText ?? "nil") =====")
        }
        
        if voiceCommand {
            // Play Sound
            soundEngine.voiceCommandAccept()
        }
        
        selectionCursor.exportSelection()
        
        // Give haptic feedback
//        hapticEngine.mediumImpact()
        hapticEngine.success()
        
        handler?()
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
                            note: self.note,
                            discardPrior: true,
                            withHaptics: true
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
//                            note: self.note,
//                            withHaptics: true
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
        
        if !self.note.isPlayingPassiveEcho {
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
        } else if self.appActivated && self.note.pausedListeningForSpeech && !self.speechSynthesizer.isSpeaking && !AVAudioSession.isHeadphonesConnected && !self.note.isRunningNote && !self.note.isWalkingNote {
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
        if self.appActivated && (self.note.isPlayingEcho || self.note.isPlayingPassiveEcho) && utterance.speechString == self.note.getText(segments: Array(self.note.noteSegments[self.note.lastEchoSegmentRange!])) {
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
            
            self.updateUIText(text: self.note.getText(), highlightRange: textRange, transformations: self.note.transformations)
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
        if pitch.frequency >= MALE_LOWEST_VOICED_SPEECH_FREQUENCY && pitch.frequency <= FEMALE_HIGHEST_VOICED_SPEECH_FREQUENCY && self.getBackgroundNoise() != Double.infinity && self.soundIntensityStream.count > MIN_SEED_INTENSITY_POINTS && Utils.validSpeechPower(soundIntensityStream: self.soundIntensityStream, backgroundNoise: self.getBackgroundNoise()) {
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
                    print("===== [Error] There was a problem calculating average pitch =====")
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
