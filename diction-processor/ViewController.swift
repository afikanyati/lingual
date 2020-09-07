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
    @IBOutlet weak var wakePhraseLabel: UILabel!
    @IBOutlet weak var wakePhraseSubtitleLabel: UILabel!
    @IBOutlet weak var transcriptionText: UITextView!
    @IBOutlet weak var playAudioButton: UIButton!
    @IBOutlet weak var playTextToSpeechButton: UIButton!
    @IBOutlet weak var recordingButton: UIButton!
    @IBOutlet weak var soundIntensityIndicatorHeight: NSLayoutConstraint!
    @IBOutlet weak var pitchLabel: UILabel!
    @IBOutlet weak var commandBar: UIView!
    @IBOutlet weak var commandBarPositionLeft: NSLayoutConstraint!
    var cursorView: UIView?
    
    // MARK: - General Properties
    var appActivated = false
    var useOnDeviceRecognition = DEFAULT_USE_ON_DEVICE_RECOGNITION
    var numAppSessions = 0
    let wakePhrase = "rise and shine"
    let font = UIFont.systemFont(ofSize: 18.0)
    var isListeningForVolume = false
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
    var onNoteListenUpdate: ((_ bufferRange: NSRange?) -> Void)?
    var onNoteListenStop: (() -> Void)?
    var onNoteComplete: (() -> Void)?
    static let PLAY_NOTE_LABEL = "Play Note"
    static let PAUSE_NOTE_LABEL = "Pause Note"
    static let PLAY_ECHO_LABEL = "Play Echo"
    static let PAUSE_ECHO_LABEL = "Pause Echo"
    static let START_NOTE_LABEL = "Start Note"
    static let STOP_NOTE_LABEL = "Stop Note"
    
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
    
    // MARK: - Speech Synthesis Properties
    let speechSynthesizer = AVSpeechSynthesizer()
    var synthesizerVoice : AVSpeechSynthesisVoice?
    /// Stores a queue of synthesizer tasks to be executed serially
    public var synthesizerQueue = Queue<SynthesizerItem>()
    /// Specifies whether view has been instructed to clear out contents of synthesizer queue
    private(set) var isExhaustingSynthesizerQueue = false
    /// Stores the rate of the speech synthesis speech
    private(set) var echoRate: Float = 0.53
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

        // App Visits
        self.configureAppVisits()

        // Prepare UI
        self.setActiveUI(as: false)
        self.wakePhraseLabel.text = "\"\(wakePhrase.capitalizeFirstLetter())\""
        self.prepareCommandBar()
        self.setCommandBarVisibility(as: false)
        
        // Start listening for wake word
        self.configureListeningForWakePhrase()
        
        // Set textContainer font size
        self.transcriptionText.font = self.font
        
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
        
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        self.transcriptionText.addGestureRecognizer(singleTap)
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
        note.startListeningForVoiceCommands(
            soundIntensityHandler: { power in
                if let power = power {
                    DispatchQueue.main.async {
                        let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                        let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                        self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                    }
                }
            },
            pitchHandler: { pitchDatum in
                if let pitchDatum = pitchDatum, !self.note.isPlayingNote {
                    DispatchQueue.main.async {
                        let pitch = pitchDatum.pitch.note.string
                        self.pitchLabel.text = pitch
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
            try session.setActive(true)
        } catch let error as NSError {
            print("===== There was an error requesting permissions to record audio or setting session category: \(error.localizedDescription) =====")
        } catch {
            print("===== There was an error requesting permissions to record audio or setting session category =====")
        }
    }
    
    func prepareCommandBar() {
        self.commandBar.layer.shadowPath =
              UIBezierPath(roundedRect: self.commandBar.bounds,
              cornerRadius: self.commandBar.layer.cornerRadius).cgPath
        self.commandBar.layer.shadowColor = UIColor.black.cgColor
        self.commandBar.layer.shadowOpacity = 0.5
        self.commandBar.layer.shadowOffset = CGSize(width: 5, height: 5)
        self.commandBar.layer.shadowRadius = 5
        self.commandBar.layer.masksToBounds = false
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
        self.onNoteListenUpdate = {[weak self] bufferRange in
            DispatchQueue.main.async {
                self?.updateUIText(bufferRange: bufferRange)
            }
        }
        
        self.onNoteListenStop = {[weak self] in
            DispatchQueue.main.async {
                self?.updateUIText()
                self?.stopRecordingUITimer()

                if !self!.note.isListeningForSpeech {
                    self?.setAudioButtonsVisibility(visible: true)
                    self?.recordingButton.setTitle(ViewController.START_NOTE_LABEL, for: .normal)
                    self?.soundIntensityIndicatorHeight.constant = 0
                }
            }
        }
        
        self.onNoteComplete = {[weak self] in
            // Play sound
            soundEngine.saveNote()

            DispatchQueue.main.async {
                self?.stopRecordingUITimer()
                self?.scheduleNotification(text: "Saved!", type: .success) // we must have stopped recording ui timer before calling this
                self?.exhaustNotificationQueue()
                self?.soundIntensityIndicatorHeight.constant = 0
                self?.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Reset", style: .plain, target: self, action: #selector(self?.resetSession))
            }
        }
    }
    
    @objc func resetSession() {
        print("===== Reset Session =====")
        // Play sound
        soundEngine.delete()
        
        // Give haptic feedback
        hapticEngine.selection()

        clearTimedNotification()
        
        if note.isPlayingEcho {
            note.stopEcho()
        }
        
        if note.isPlayingNote {
            note.stop()
        }
        
        // Remove previous observer
        self.note.removeObserver(
            self,
            forKeyPath: "isListeningForSpeech",
            context: nil
        )
        
        if note.isListeningForSpeech {
            note.stopListeningForSpeech() {
                self.note = self.createNewNote()
                self.note.startListeningForVoiceCommands(
                    soundIntensityHandler: { power in
                        if let power = power {
                            DispatchQueue.main.async {
                                let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                                let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                                self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                            }
                        }
                    },
                    pitchHandler: { pitchDatum in
                        if let pitchDatum = pitchDatum, !self.note.isPlayingNote {
                            DispatchQueue.main.async {
                                let pitch = pitchDatum.pitch.note.string
                                self.pitchLabel.text = pitch
                            }
                        }
                    }
                )
            }
        } else if note.isListeningForCommands {
            note.stopListeningForVoiceCommands() {
                self.note = self.createNewNote()
                self.note.startListeningForVoiceCommands(
                    soundIntensityHandler: { power in
                        if let power = power {
                            DispatchQueue.main.async {
                                let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                                let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                                self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                            }
                        }
                    },
                    pitchHandler: { pitchDatum in
                        if let pitchDatum = pitchDatum, !self.note.isPlayingNote {
                            DispatchQueue.main.async {
                                let pitch = pitchDatum.pitch.note.string
                                self.pitchLabel.text = pitch
                            }
                        }
                    }
                )
            }
        } else {
            self.note = self.createNewNote()
        }
        
        DispatchQueue.main.async {
            self.transcriptionText.attributedText = NSMutableAttributedString(string: "")
            self.navigationItem.rightBarButtonItem = nil
            self.setAudioButtonsVisibility(visible: false)
        }
    }
    
    func requestPermissions(handler: (() -> Void)?) {
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
        // manage cursor view
        if visible && self.transcriptionText.attributedText.length == 0 {
            // compute x and y positions
            let textContainerPadding = transcriptionText.textContainer.lineFragmentPadding
            let xPos = transcriptionText.frame.minX + textContainerPadding
            let yPos = transcriptionText.frame.minY + textContainerPadding + ((self.font.lineHeight - self.font.pointSize) / 2)
            let width = Utils.CURSOR_WIDTH
            

            // Create a CGRect object which is used to render a rectangle.
            let cursor: CGRect = CGRect(
                x: xPos,
                y: yPos,
                width: CGFloat(width),
                height: CGFloat(self.font.lineHeight)
            )
            
            // Create a UIView object which use above CGRect object.
            self.cursorView = UIView(frame: cursor)
            
            // Set UIView background color
            self.cursorView!.backgroundColor = UIColor.systemBlue
            
            // Create corner radius
            self.cursorView!.layer.cornerRadius = CGFloat(width / 2)
            
            // Add above UIView object as the main view's subview.
            self.view.addSubview(self.cursorView!)
        } else if visible && self.transcriptionText.attributedText.length > 0 {
            // keep cursor where it last was
        } else if let cursorView = self.cursorView, !visible {
            // remove cursor
            cursorView.removeFromSuperview()
            self.cursorView = nil
        }
        
        // manage cursor model
        if visible {
            selectionCursor.setTextView(textView: self.transcriptionText)
            selectionCursor.setCursorView(cursorView: self.cursorView!)
            selectionCursor.setNote(note: self.note)
            
            if self.cursorBlinkTimer != nil {
                // Stopped cursor blinking that's already running
                // To avoid two instances of blinking timers
                self.cursorBlinkTimer?.invalidate()
            }
            
            // start cursor blink
            self.cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_CURSOR_BLINK_RATE, repeats: true) { timer in
                if let cursorView = self.cursorView, cursorView.alpha == 1 {
                    UIView.animate(withDuration: Utils.DEFAULT_CURSOR_BLINK_TRANSITION_DURATION) {
                        self.cursorView!.alpha = 0
                    }
                } else if let cursorView = self.cursorView, cursorView.alpha == 0 {
                    UIView.animate(withDuration: Utils.DEFAULT_CURSOR_BLINK_TRANSITION_DURATION) {
                        self.cursorView!.alpha = 1
                    }
                }
            }
        } else {
            selectionCursor.reset()
            
            // stop cursor blink
            if self.cursorBlinkTimer != nil {
                self.cursorBlinkTimer?.invalidate()
                self.cursorBlinkTimer = nil
            }
        }
    }
    
    func setCommandBarVisibility(as visible: Bool) {
        if visible {
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.commandBar.alpha = 1
                    self.commandBarPositionLeft.constant = 10
                }
            )
        } else {
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.commandBar.alpha = 0
                    self.commandBarPositionLeft.constant = -10
                }
            )
        }
    }
    
    func createNewNote() -> Note {
        // create new note
        let note = Note(
            vc: self,
            filename: "note-\(UUID().uuidString)",
            speaker: Speaker(name: "Afika Nyati", avatarURL: URL(string: AVATAR_URL)!, vc: self),
            minPower: minPower,
            withOnDeviceRecognition: useOnDeviceRecognition,
            withTemporalSuggestions: false,
            withPunctuationSuggestions: true,
            withFormattingSuggestions: true,
            withTextStrictlyAsWords: false,
            onListenUpdate: onNoteListenUpdate,
            onListenStop: onNoteListenStop,
            onComplete: onNoteComplete,
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
    
    func runTimedNotification(item: NotificationItem) {
        // Stop UI Timer if we receive app notification while recording
        if self.note.isListeningForSpeech && self.UITimer != nil {
            self.stopRecordingUITimer()
        }
        
        self.navigationItem.title = item.text
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.red]
        self.appNotificationTimer = Timer.scheduledTimer(withTimeInterval: item.duration!, repeats: false) {[weak self] timer in
            // Restart UI Timer is we received app notification while receiving
            if self!.isExhaustingNotificationQueue {
                self?.navigationItem.title = ""
                self?.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]

                self!.exhaustNotificationQueue()
            } else if self!.note.isListeningForSpeech {
                self?.navigationItem.title = ""
                self?.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]

                DispatchQueue.main.async {
                    self!.startRecordingUITimer(recording: true)
                }
            } else {
                self?.navigationItem.title = ""
                self?.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
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
        self.navigationItem.title = ""
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
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
        
        self.navigationItem.title = item.text
        if self.note.isListeningForSpeech {
            self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.red]
        } else {
            self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
        }
    }
    
    func removeIndefiniteNotification() {
        if self.note.isListeningForSpeech {
            self.navigationItem.title = ""
            self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]

            DispatchQueue.main.async {
                self.startRecordingUITimer(recording: true)
            }
        } else {
            self.navigationItem.title = ""
            self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
        }
    }
    
    func exhaustSynthesizerQueue() {
        let item = self.synthesizerQueue.dequeue()
        self.isExhaustingSynthesizerQueue = !self.synthesizerQueue.isEmpty

        if let item = item {
            Utils.runSpeechSynthesizer(item: item)
        }
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
    
    // MARK: - View Actions

    @IBAction func recordButtonTapped(_ sender: Any) {
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
                print("===== Start Recording =====")
                recordingButton.setTitle(ViewController.STOP_NOTE_LABEL, for: .normal)
                note.startListeningForSpeech(
                    soundIntensityHandler: { power in
                        if let power = power {
                            DispatchQueue.main.async {
                                let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                                let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                                self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                            }
                        }
                    },
                    pitchHandler: { pitchDatum in
                        if let pitchDatum = pitchDatum, !self.note.isPlayingNote {
                            DispatchQueue.main.async {
                                let pitch = pitchDatum.pitch.note.string
                                self.pitchLabel.text = pitch
                            }
                        }
                    },
                    onStartHandler: {
                        DispatchQueue.main.async {
                            self.startRecordingUITimer(recording: true)
                        }
                    }
                )
                
                // Give haptic feedback
                hapticEngine.selection()
            } else if note.isListeningForSpeech && !note.isExporting {
                print("===== Stop Recording =====")
                note.stopListeningForSpeech() {[weak self] in
                    self?.onNoteListenStop!()
                }
                
                // Give haptic feedback
                hapticEngine.selection()
            }
        }
    }

    @IBAction func playButtonTapped(_ sender: Any) {
        if note.isPlayingNote {
            note.pause() { [weak self] in
                DispatchQueue.main.async {
                    self?.playAudioButton.setTitle(ViewController.PLAY_NOTE_LABEL, for: .normal)
                }
            }
            
            // Give haptic feedback
            hapticEngine.selection()
        } else {
            note.play(
                onStartHandler: { [weak self] in
                    // print("Successfully executed playback on start handler")
                    DispatchQueue.main.async {
                        self?.playAudioButton.setTitle(ViewController.PAUSE_NOTE_LABEL, for: .normal)
                    }
                },
                secondElapseHandler: { [weak self] in
                    // print("Successfully executed playback second elapsed handler")
                    DispatchQueue.main.async {
                        if !self!.note.isListeningForSpeech {
                            self?.navigationItem.title = "\(Utils.formattedTime(time: Float(self!.note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.note.duration.seconds)))"
                        }
                    }
                },
                segmentBoundaryHandler: { [weak self] in
                    // print("Successfully executed playback on segment boundary handler")
                    DispatchQueue.main.async {
                        if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
                            // update text
                            self?.updateUIText(highlightRange: highlightRange)
                        }
                        
                        if let segment = self?.note.getSegment(type: .current), let pitch = segment.getPitch() {
                            // update pitch
                            self?.pitchLabel.text = pitch.note.string
                        }
                    }
                }, onFinishHandler: { [weak self] in
                    // print("Successfully executed playback on finish handler")
                    DispatchQueue.main.async {
                        self?.updateUIText()
                        self!.note.player.replaceCurrentItem(with: nil)
                        if !self!.note.isListeningForSpeech {
                            self?.navigationItem.title = ""
                            self?.playAudioButton.setTitle(ViewController.PLAY_NOTE_LABEL, for: .normal)
                        }
                    }
                }
            )
            
            // Give haptic feedback
            hapticEngine.selection()
        }
    }
    
    @IBAction func speechToTextButtonTapped(_ sender: Any) {
        if note.echoIsPaused {
            print("==== Speech synthesizer continue speaking =====")
            note.startEcho(onStartHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.playTextToSpeechButton.setTitle(ViewController.PAUSE_ECHO_LABEL, for: .normal)
                }
            })
            
            // Give haptic feedback
            hapticEngine.selection()
        } else if note.isPlayingEcho {
            print("==== Speech synthesizer paused =====")
            note.pauseEcho() { [weak self] in
                DispatchQueue.main.async {
                    self?.playTextToSpeechButton.setTitle(ViewController.PLAY_ECHO_LABEL, for: .normal)
                }
            }
            
            // Give haptic feedback
            hapticEngine.selection()
        } else {
            playAudioButton.setTitle(ViewController.PLAY_NOTE_LABEL, for: .normal)
            note.startEcho(onStartHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.navigationItem.title = ""
                    self?.playTextToSpeechButton.setTitle(ViewController.PAUSE_ECHO_LABEL, for: .normal)
                }
            })
            
            // Give haptic feedback
            hapticEngine.selection()
        }
    }
    
    // MARK: - View Methods
    
    func setAudioButtonsVisibility(visible: Bool) {
        self.playAudioButton.isHidden = !visible
        self.playAudioButton.isEnabled = visible
        self.playTextToSpeechButton.isHidden = !visible
        self.playTextToSpeechButton.isEnabled = visible
    }
    
    func setActiveUI(as visible: Bool) {
        transcriptionText.isHidden = !visible
        recordingButton.isHidden = !visible
        recordingButton.isEnabled = visible
        pitchLabel.isHidden = !visible
        wakePhraseSubtitleLabel.isHidden = visible
        wakePhraseLabel.isHidden = visible
        
        if !visible {
            playAudioButton.isHidden = true
            playAudioButton.isEnabled = false
            playTextToSpeechButton.isHidden = true
            playTextToSpeechButton.isEnabled = false
        }
    }
    
    func updateUIText(highlightRange: NSRange? = nil, bufferRange: NSRange? = nil) {
        let text = note.getText()
        
        if text.count == 0 {
            return
        }
        
        if let highlightRange = highlightRange {
            let mutableAttributedString = NSMutableAttributedString(string: text)
            mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.white, range: highlightRange)
            mutableAttributedString.addAttribute(.backgroundColor, value: UIColor.red, range: highlightRange)
            transcriptionText.attributedText = mutableAttributedString
            transcriptionText.font = self.font
        } else if let bufferRange = bufferRange {
            let mutableAttributedString = NSMutableAttributedString(string: text)
            mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.systemGray, range: bufferRange)
            transcriptionText.attributedText = mutableAttributedString
            transcriptionText.font = self.font
        } else {
            let mutableAttributedString = NSMutableAttributedString(string: text)
            transcriptionText.attributedText = mutableAttributedString
            transcriptionText.font = self.font
        }
        
        // Notify of text change
        selectionCursor.textViewDidChange(self.transcriptionText)
    }
    
    /**
        Presents timer to view.

        - Parameter recording: Whether the timer should be set to be a recording.
    */
    func startRecordingUITimer(recording: Bool) {
        if recording {
            self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.red]
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
    
    func activateListeningIndicator() {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: spinner)
    }
    
    func deactivateListeningIndicator() {
        self.navigationItem.leftBarButtonItem = nil
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
                    let soundIntensityDatum = SoundIntensityDatum(date: Date(), power: power)
                    self.soundIntensityStream.append(soundIntensityDatum)
                    let soundIntensityHeight = CGFloat(min((CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height), self.view.safeAreaLayoutGuide.layoutFrame.height))
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
                                soundIntensityHandler: { power in
                                    if let power = power {
                                        DispatchQueue.main.async {
                                            let height = CGFloat(Utils.normalizedPower(power: power, minPower: self!.minPower)) * self!.view.safeAreaLayoutGuide.layoutFrame.height
                                            let soundIntensityHeight: CGFloat = CGFloat(min(height, self!.view.safeAreaLayoutGuide.layoutFrame.height))
                                            self?.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                                        }
                                    }
                                },
                                pitchHandler: { pitchDatum in
                                    if let pitchDatum = pitchDatum, !self!.note.isPlayingNote {
                                        DispatchQueue.main.async {
                                            let pitch = pitchDatum.pitch.note.string
                                            self?.pitchLabel.text = pitch
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
                        self.stopListeningForVolumeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) {[weak self] timer in
                            if self?.stopListeningForVolumeTimer != nil {
                                self?.stopListeningForVolume() {
                                    self?.note.startListeningForVoiceCommands(
                                        soundIntensityHandler: { power in
                                            if let power = power {
                                                DispatchQueue.main.async {
                                                    let height = CGFloat(Utils.normalizedPower(power: power, minPower: self!.minPower)) * self!.view.safeAreaLayoutGuide.layoutFrame.height
                                                    let soundIntensityHeight: CGFloat = CGFloat(min(height, self!.view.safeAreaLayoutGuide.layoutFrame.height))
                                                    self?.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                                                }
                                            }
                                        },
                                        pitchHandler: { pitchDatum in
                                            if let pitchDatum = pitchDatum, !self!.note.isPlayingNote {
                                                DispatchQueue.main.async {
                                                    let pitch = pitchDatum.pitch.note.string
                                                    self?.pitchLabel.text = pitch
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
        } else if keyPath == "isListeningForSpeech" {
            if let isListeningForSpeech = change?[.newKey] as? Bool {
                self.setCursorVisibility(as: isListeningForSpeech)
            }
        } else if keyPath == "hasSelection" {
            if let hasSelection = change?[.newKey] as? Bool {
                self.setCommandBarVisibility(as: hasSelection)
            }
        }
    }
    
    // MARK: - Touch Events
    
    @objc func handleSingleTap(touch: UITapGestureRecognizer) {
        if self.appActivated && self.note.isListeningForSpeech {
            let touchPoint = touch.location(in: self.transcriptionText)
            let textPosition = self.transcriptionText.closestPosition(to: touchPoint)
            
            if self.transcriptionText.selectedRange != Utils.EMPTY_NSRANGE {
                self.transcriptionText.selectedRange = NSRange(location: 0, length: 0)
            }
            
            if let textPosition = textPosition {
                print("===== Touch Interaction: Single Tap =====")
                selectionCursor.moveCursor(textPosition: textPosition, cache: true)
            }
        }
    }

    @IBAction func handleDeleteSelection(_ sender: Any) {
        print("handleDeleteSelection")
    }
    
    @IBAction func handleReplaceSelection(_ sender: Any) {
        print("handleReplaceSelection")
    }
    
    @IBAction func handleCopySelection(_ sender: Any) {
        print("handleCopySelection")
    }
    
    @IBAction func handleCutSelection(_ sender: Any) {
        print("handleCutSelection")
    }
    
    @IBAction func handlePasteSelection(_ sender: Any) {
        print("handlePasteSelection")
    }
    
    @IBAction func handleExportSelection(_ sender: Any) {
        print("handleExportSelection")
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
                if text.contains(self.wakePhrase) { // wake word/phrase needs to be two words to get pitch data
                    self.stopListeningForWakePhrase()
                    // Play Sound
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
                        soundEngine.correctWakePhrase()
                    }
                    
                    // Give haptic feedback
                    hapticEngine.success()
                    
                    print("===== Wake Phrase Detected =====")
                    self.activateApp()
                } else if !text.contains("rise") && !text.contains("rise and") {
                    // Play Sound
                    soundEngine.incorrectWakePhrase()
                    
                    // Give haptic feedback
                    hapticEngine.error()
                    
                    // Give visual feedback
                    if text.count > 0 {
                        self.scheduleNotification(
                            text: "\"\(transcription.segments.count > 3 ? "\(transcription.segments.first!.substring.lowercased())...\(transcription.segments.last!.substring.lowercased())" : text)\"",
                            duration: 3
                        )
                        self.exhaustNotificationQueue()
                        
                        // Give audio feedback
                        if AVAudioSession.isHeadphonesConnected {
                            // we don't run when !AVAudioSession.isHeadphonesConnected && note.isListeningForSpeech
                            // because we will be note.isListeningForVoiceCommands
                            // which will catch the words and process them
                            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {[weak self] timer in
                                let voice = Utils.getSynthesizerVoice(withGender: .female, vc: self)

                                let synthesizerItem = SynthesizerItem(
                                    synthesizer: self!.speechSynthesizer,
                                    text: text,
                                    voice: voice,
                                    rate: self!.echoRate,
                                    volume: self!.playbackVolume
                                )
                                self?.synthesizerQueue.enqueue(synthesizerItem)
                                self?.exhaustSynthesizerQueue()
                            }
                        }
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
        self.updateUIText()
        if !self.playTextToSpeechButton.isHidden {
            self.playTextToSpeechButton.setTitle(ViewController.PLAY_ECHO_LABEL, for: .normal)
        }
        
        if self.isExhaustingSynthesizerQueue {
            self.exhaustSynthesizerQueue()
        } else if self.note.isPlayingEcho {
            // turn off isPlayingEcho
            self.note.isPlayingEcho = false
        }
        
        self.tempOnEchoFinish?()
        self.tempOnEchoFinish = nil
        
        if self.appActivated && self.note.pausedListeningForCommands && !AVAudioSession.isHeadphonesConnected {
            // when headphones are off we don't listen for voice commands while echoing
            // but on completion we turn it back on
            self.note.startListeningForVoiceCommands(
                soundIntensityHandler: { power in
                    if let power = power {
                        DispatchQueue.main.async {
                            let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                            let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                            self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                        }
                    }
                },
                pitchHandler: { pitchDatum in
                    if let pitchDatum = pitchDatum, !self.note.isPlayingNote {
                        DispatchQueue.main.async {
                            let pitch = pitchDatum.pitch.note.string
                            self.pitchLabel.text = pitch
                        }
                    }
                }
            )
        }

        if self.appActivated && self.note.pausedListeningForSpeech && !AVAudioSession.isHeadphonesConnected {
            // when headphones are off we don't listen for speech while echoing
            // but on completion we turn it back on
            self.note.startListeningForSpeech(
                soundIntensityHandler: { power in
                    if let power = power {
                        DispatchQueue.main.async {
                            let height = CGFloat(Utils.normalizedPower(power: power, minPower: self.minPower)) * self.view.safeAreaLayoutGuide.layoutFrame.height
                            let soundIntensityHeight: CGFloat = CGFloat(min(height, self.view.safeAreaLayoutGuide.layoutFrame.height))
                            self.soundIntensityIndicatorHeight.constant = soundIntensityHeight
                        }
                    }
                },
                pitchHandler: { pitchDatum in
                    if let pitchDatum = pitchDatum, !self.note.isPlayingNote {
                        DispatchQueue.main.async {
                            let pitch = pitchDatum.pitch.note.string
                            self.pitchLabel.text = pitch
                        }
                    }
                }
            )
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully paused =====")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("===== Speech synthesis utterance successfully started =====")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        if appActivated && self.note.isPlayingEcho && utterance.speechString == self.note.getText(segments: Array(self.note.noteSegments[self.note.lastEchoSegmentRange!])).trimTrailingPunctuation() {
            var textRange = characterRange
            // normalize range to include contribution from text before echoed passage
            var lowestEchoSegment: NoteSegment?
            for segment in self.note.noteSegments[self.note.lastEchoSegmentRange!] {
                if !segment.isSilence() && !segment.isVoiceCommandWord() {
                    lowestEchoSegment = segment
                    break
                }
            }

            if let lowestEchoSegment = lowestEchoSegment, let lowestEchoSegmentRange = self.note.getSegmentTextRange(of: lowestEchoSegment), self.note.isListeningForSpeech {
                textRange = NSRange(location: lowestEchoSegmentRange.location + characterRange.location, length: characterRange.length)
            }
            
            self.updateUIText(highlightRange: textRange)
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
//                if !self!.note.isListeningForSpeech {
//                    self?.navigationItem.title = "\(Utils.formattedTime(time: Float(self!.note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.note.duration.seconds)))"
//                }
//            }
//        },
//        segmentBoundaryHandler: { [weak self] in
//            // print("Successfully executed playback on segment boundary handler")
//            DispatchQueue.main.async {
//                if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
//                    // update text
//                    self?.updateUIText(highlightRange: highlightRange)
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
//                self?.updateUIText()
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
//                if !self!.note.isListeningForSpeech {
//                    self?.navigationItem.title = "\(Utils.formattedTime(time: Float(self!.note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.note.duration.seconds)))"
//                }
//            }
//        },
//        segmentBoundaryHandler: { [weak self] in
//            // print("Successfully executed playback on segment boundary handler")
//            DispatchQueue.main.async {
//                if let segment = self?.note.getSegment(type: .current), segment.getText().count > 0 && !segment.isVoiceCommandWord(), let highlightRange = self?.note.getSegmentTextRange(of: segment) {
//                    // update text
//                    self?.updateUIText(highlightRange: highlightRange)
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
//                self?.updateUIText()
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
