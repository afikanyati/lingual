//
//  SpeechRecognition.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/31/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Foundation
import Speech

class SpeechRecognitionEngine: NSObject, SFSpeechRecognitionTaskDelegate {
    // MARK: - Notifications
    
    static let onStartedListeningForWakePhrase = Notification.Name(Notifications.onStartedListeningForWakePhrase.rawValue)
    static let onStoppedListeningForWakePhrase = Notification.Name(Notifications.onStoppedListeningForWakePhrase.rawValue)
    static let onStartedListeningForCommands = Notification.Name(Notifications.onStartedListeningForCommands.rawValue)
    static let onPausedListeningForCommands = Notification.Name(Notifications.onPausedListeningForCommands.rawValue)
    static let onStoppedListeningForCommands = Notification.Name(Notifications.onStoppedListeningForCommands.rawValue)
    static let onStartedListeningForSpeech = Notification.Name(Notifications.onStartedListeningForSpeech.rawValue)
    static let onPausedListeningForSpeech = Notification.Name(Notifications.onPausedListeningForSpeech.rawValue)
    static let onStoppedListeningForSpeech = Notification.Name(Notifications.onStoppedListeningForSpeech.rawValue)
    static let onRequestPrepareAudioFile = Notification.Name(Notifications.onRequestPrepareAudioFile.rawValue)
    static let onPowerUpdate = Notification.Name(Notifications.onPowerUpdate.rawValue)
    static let onSpeechUpdate = Notification.Name(Notifications.onSpeechUpdate.rawValue)
    static let onWakePhraseDetected = Notification.Name(Notifications.onWakePhraseDetected.rawValue)
    static let onIncorrectWakePhrase = Notification.Name(Notifications.onIncorrectWakePhrase.rawValue)
    static let onBufferItem = Notification.Name(Notifications.onBufferItem.rawValue)
    
    // MARK: - App Modules
    
    var state: StateManager
    var notifications: NotificationEngine
    var speechPlayer: SpeechPlayerEngine
    var speechSynthesis: SpeechSynthesisEngine
    var uiManager: UIManager
    @objc dynamic weak var selectionCursor: SelectionCursor!
    weak var entryManager: EntryManager!
    
    // MARK: - Speech Recognition Properties
    
    let wakePhrases = [
        "rise and shine",
        "rison shine",
        "razon shine"
    ]
    let recordBus = 0
    private(set) var audioEngine = AVAudioEngine()
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private(set) var request: SFSpeechAudioBufferRecognitionRequest?
    private(set) var recognitionTask: SFSpeechRecognitionTask?
    /// Stores the type of recognition last executed e.g. speech or voice command
    private(set) var lastRecognitionTask: RecognitionTask?
    /// Indicates whether we have processed a valid voice command early
    private(set) var earlyValidVoiceCommandDetection = false
    /// Indicates whether we have processed an invalid voice command early
    private(set) var earlyInvalidVoiceCommandDetection = false
    /// Indicates whether we have rejected broadcast speech and should reject again in didFinish
    private(set) var earlyBroadcastSpeechRejection = false
    private(set) var isActive = true
    private(set) var isListeningForWakePhrase = false
    private(set) var isListeningForVolume = false
    /// Specifies whether entry is currently listening for voice commands
    private(set) var isListeningForCommands = false
    /// Specifies whether entry has paused listening for commands (active, but paused vs. inactive)
    private(set) var pausedListeningForCommands = false
    /// Specifies whether entry is currently listening for speech
    private(set) var isListeningForSpeech = false
    /// Specifies whether entry has paused listening for speech (active, but paused vs. inactive)
    private(set) var pausedListeningForSpeech = false
    /// Specifies whether entry has been paused listening for speech by user
    private(set) var userInitiatedPausedListeningForSpeech = false
    /// Indicates whether we have to execute listening for speech handler in isListeningForSpeech method
    private(set) var executedListeningStartHandler = true
    private(set) var soundIntensityStream = [SoundIntensityDatum]()
    private(set) var session = AVAudioSession.sharedInstance()
    //    var volumeListeningRateTimer: Timer?
    //    var stopListeningForVolumeTimer: Timer?
    
    /// Stores a list of voice commands executed
    private(set) var voiceCommandStream = [VoiceCommandDatum]()
    
    private(set) var listeningTimer: Timer?
    private(set) var sentenceSuggestionTimer: Timer?
    private(set) var paragraphSuggestionTimer: Timer?
    private(set) var speechRecognizedTimer: Timer?
    private(set) var lastSpeechRecognizerHypothesizeDate: Date?
    private(set) var lastStartListeningDate: Date?
    /// Stores the timestamp when we last started listening
    private(set) var lastStartedListeningTimestamp: TimeInterval?
    /// Stores a queue of speech recognized tasks to be executed serially
    public var speechRecognizedQueue = Queue<Bool>()
    
    @objc dynamic private var speeechRecognizerAuthorized = false
    @objc dynamic private var sessionAuthorized = false
    @objc dynamic var listeningPermissionsGranted: Bool {
        return self.speeechRecognizerAuthorized && self.sessionAuthorized
    }
    // Allows you to place observer on computed properties: https://stackoverflow.com/questions/36555492/kvo-on-swifts-computed-properties
    @objc class var keyPathsForValuesAffectingListeningPermissionsGranted: Set<String> {
        return [ "speeechRecognizerAuthorized", "sessionAuthorized" ]
    }
    
    // Handlers
    private(set) var stopListeningHandler: (() -> Void)?
    private(set) var pauseListeningHandler: (() -> Void)?
    
    // MARK: - Initialization and Deinitialization

    init(
        state: StateManager,
        notifications: NotificationEngine,
        speechPlayer: SpeechPlayerEngine,
        speechSynthesis: SpeechSynthesisEngine,
        uiManager: UIManager
    ) {
        print("===== Speech Recognition Engine: Initialization =====")
        self.state = state
        self.speechPlayer = speechPlayer
        self.speechSynthesis = speechSynthesis
        self.notifications = notifications
        self.uiManager = uiManager
        
        super.init()
        
        self.configureAudioSession()
        self.configureNotificationObservers()
        
        // Permissions
        if !self.listeningPermissionsGranted {
            print("===== Speech Recognition Engine Initializer - Requesting permissions =====")
            self.requestPermissions()
        }
        
        if let speechRecognizer = self.speechRecognizer, !self.isListeningForWakePhrase && self.state.withOnDeviceRecognition && self.listeningPermissionsGranted && speechRecognizer.supportsOnDeviceRecognition {
            print("===== Speech Recognition Engine: Initializer - Configure listening for wake phrase =====")
            // Start listening for wake word
            self.configureListeningForWakePhrase()
        }
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)

        // remove volume observer
        self.session.removeObserver(
            self,
            forKeyPath: #keyPath(AVAudioSession.outputVolume),
            context: nil
        )
        
        self.speechRecognizer?.removeObserver(
            self,
            forKeyPath: "supportsOnDeviceRecognition",
            context: nil
        )
        
        // remove observer from selectionCursor property
        self.removeObserver(
            self,
            forKeyPath: "selectionCursor",
            context: nil
        )
        
        // remove observer from listeningPermissionsGranted property
        self.removeObserver(
            self,
            forKeyPath: "listeningPermissionsGranted",
            context: nil
        )
        
        if let selectionCursor = self.selectionCursor {
            // remove observer from hasSelection
            selectionCursor.removeObserver(
                self,
                forKeyPath: "hasSelection",
                context: nil
            )
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
    
    // MARK: - Validation
    
    func checkRep() {
        var result = true
        
        // only isListeningForSpeech or isListeningForCommands or isListeningForWakePhrase should be active

        // make sure paused listening for speech only occurs if listening for speech
        result = result && ((self.isListeningForSpeech && !self.pausedListeningForSpeech) || (self.isListeningForSpeech && self.pausedListeningForSpeech) || (!self.isListeningForSpeech && !self.pausedListeningForSpeech))
//        print("make sure paused listening for speech  only occurs if listening for speech: ", (self.isListeningForSpeech && !self.pausedListeningForSpeech), (self.isListeningForSpeech && self.pausedListeningForSpeech), (!self.isListeningForSpeech && !self.pausedListeningForSpeech))
//        print("current result: ", result)
        
        // make sure paused listening for commands only occurs if listening for commands
        result = result && ((self.isListeningForCommands && !self.pausedListeningForCommands) || (self.isListeningForCommands && self.pausedListeningForCommands) || (!self.isListeningForCommands && !self.pausedListeningForCommands))
//        print("make sure paused listening for speech  only occurs if listening for commands: ", (self.isListeningForCommands && !self.pausedListeningForCommands), (self.isListeningForCommands && self.pausedListeningForCommands), (!self.isListeningForCommands && !self.pausedListeningForCommands))
//        print("current result: ", result)
        
        // can't be listening for wake phrase and anything else
        result = result && ((self.isListeningForWakePhrase && !self.isListeningForSpeech && !self.isListeningForCommands && !self.isListeningForVolume) || !self.isListeningForWakePhrase)
//        print("can't be listening for wake phrase and anything else: ", (self.isListeningForWakePhrase && !self.isListeningForSpeech && !self.isListeningForCommands && !self.isListeningForVolume), !self.isListeningForWakePhrase)
//        print("current result: ", result)
        
        // should not have a listening timer if we're not listening for speech
        result = result && ((self.listeningTimer != nil && (self.isListeningForSpeech || self.pausedListeningForSpeech)) || self.listeningTimer == nil)
//        print("should not have a listening timer if we're not listening for speech: ", (self.listeningTimer != nil && self.isListeningForSpeech), self.listeningTimer == nil)
//        print("current result: ", result)
        
        // ***** IF WE ARE LISTENING TO SPEECH, MAKE SURE WE HAVE A ENTRY AS WELL

        if !result {
            fatalError("===== [Error] Speech Recognition Engine Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        print("===== Speech Recognition Engine: Configure Notification Observers =====")
        let notificationCenter = NotificationCenter.default
        
        notificationCenter.addObserver(
            self,
            selector: #selector(self.appMovedToBackground),
            name: UIApplication.didEnterBackgroundNotification,
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
            selector: #selector(self.audioSessionRouteChange),
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
        
        // add volume observer
        self.session.addObserver(
            self,
            forKeyPath: #keyPath(AVAudioSession.outputVolume),
            options: [.old, .new],
            context: nil
        )
        
        // add speech recognizer observer
        self.speechRecognizer!.addObserver(
            self,
            forKeyPath: "supportsOnDeviceRecognition",
            options: [.old, .new],
            context: nil
        )
        
        // EntryManager
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryDeleted(notification:)),
            name: EntryManager.onEntryDeleted,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onExecuteEntryAction(notification:)),
            name: EntryManager.onExecuteEntryAction,
            object: nil
        )
        
        // SpeechPlayer
        notificationCenter.addObserver(
            self,
            selector: #selector(onSpeechStoppedPlaying(notification:)),
            name: SpeechPlayerEngine.onStoppedPlaying,
            object: nil
        )
        
        // StorageManager
        notificationCenter.addObserver(
            self,
            selector: #selector(onFetchedStoredState(notification:)),
            name: StorageManager.onFetchedStoredState,
            object: nil
        )
        
        // add observer to selectionCursor property
        self.addObserver(
            self,
            forKeyPath: "selectionCursor",
            options: [.old, .new],
            context: nil
        )
        
        // add observer to listeningPermissionsGranted property
        self.addObserver(
            self,
            forKeyPath: "listeningPermissionsGranted",
            options: [.old, .new],
            context: nil
        )
        
        // SelectionCursor
        if let selectionCursor = self.selectionCursor {
            selectionCursor.addObserver(
                self,
                forKeyPath: "hasSelection",
                options: [.old, .new],
                context: nil
            )
        }
    }
    
    @objc func appMovedToBackground() {
        print("===== Speech Recognition Engine: App Moved to Background =====")
        if !self.state.appActivated {
            print("\tStop listening for wake phrase...")
            self.stopListeningForWakePhrase()
        }
        
        // keep recording outside of app if entry started
        if !self.isListeningForSpeech {
            print("\tStop listening for voice commands...")
            self.state.setAppActive(as: false)
            if self.isListeningForCommands {
                self.pauseListeningForVoiceCommands()
            }
        }
        
        self.notifications.stopNotification()
    }

    @objc func appMovedToForeground() {
        print("===== Speech Recognition Engine: App Moved to Foreground =====")
        if !self.state.appActivated && self.isListeningForCommands {
            print("\tInitiate listening for voice commands...")
            self.startListeningForVoiceCommands()
        } else if !self.state.appActivated && !self.isListeningForWakePhrase && self.listeningPermissionsGranted {
            print("\tInitiate listening for wake phrase...")
            self.configureListeningForWakePhrase()
        } else {
            print("\tNo action taken.")
        }
    }
    
    @objc func appWillTerminate() {
        print("===== Speech Recognition Engine: App Will Terminate =====")
        if self.isListeningForSpeech {
            print("\tCurrently listening for speech. Stop listening before terminating application...")
            self.stopListeningForSpeech()
        } else if self.isListeningForCommands {
            print("\tCurrently listening for commands. Stop listening before terminating application...")
            self.stopListeningForVoiceCommands()
        } else if self.isListeningForWakePhrase {
            print("\tCurrently listening for wake phrase. Stop listening before terminating application...")
            self.stopListeningForWakePhrase()
        }
    }
    
    @objc func audioSessionRouteChange(notification: Notification) {
        print("===== Speech Recognition Engine: Audio Session Route Change =====")
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
        }
        print("\tReason: ", reason)

        // Switch over the route change reason.
        switch reason {
        case .newDeviceAvailable: // New device found.
            // Reset listening for wake word
            if !self.state.appActivated && self.isListeningForWakePhrase {
                self.stopListeningForWakePhrase() {
                    self.configureListeningForWakePhrase()
                }
            } else if self.isListeningForSpeech {
                self.stopListeningForSpeech() {
                    self.startListeningForSpeech()
                }
            } else if self.isListeningForCommands {
                self.stopListeningForVoiceCommands() {
                    self.startListeningForVoiceCommands()
                }
            } else {
                // Re-initiate Audio Engine to mend broken graph
                self.audioEngine = AVAudioEngine()
            }
        case .oldDeviceUnavailable: // Old device removed.
            // Reset listening for wake word
            if !self.state.appActivated {
                self.stopListeningForWakePhrase() {
                    self.configureListeningForWakePhrase()
                }
            } else if self.isListeningForSpeech && !self.selectionCursor.hasSelection {
                self.speechPlayer.stop(withFeedback: false) {
                    self.startListeningForSpeech()
                }
            }  else if self.isListeningForCommands {
                self.stopListeningForVoiceCommands() {
                    self.startListeningForVoiceCommands()
                }
            } else {
                // Re-initiate Audio Engine to mend broken graph
                self.audioEngine = AVAudioEngine()
            }
        default:
            break
        }
    }
    
    @objc func handleInterruption(notification: Notification) {
        print("===== Speech Recognition Engine: Handle Interruption =====")
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
        print("===== Speech Recognition Engine: Handle Secondary Audio =====")
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
    
    @objc func onEntryDeleted(notification: Notification) {
        print("===== Speech Recognition Engine: On Deleted Entry =====")
    }
    
    @objc func onExecuteEntryAction(notification: Notification) {
        print("===== Speech Recognition Engine: On Execute Entry Action =====")
        if let type = notification.userInfo!["type"] as? String {
            switch (type) {
            default:
                break
            }
        }
    }
    
    @objc func onSpeechStoppedPlaying(notification: Notification) {
        print("===== Speech Recognition Engine: On Speech Stopped Playing =====")
    }
    
    @objc func onFetchedStoredState(notification: Notification) {
        print("===== Speech Recognition Engine: Fetch Stored State =====")
        // Voice Command Stream
        self.voiceCommandStream = notification.userInfo!["voiceCommandStream"] as? [VoiceCommandDatum] ?? [VoiceCommandDatum]()
    }
    
    // MARK: - Configure
    
    func requestPermissions(handler: (() -> Void)? = nil) {
        print("===== Speech Recognition Engine: Request Permissions =====")
        SFSpeechRecognizer.requestAuthorization {
            [unowned self] (authStatus) in
            print("\tQuerying SFSpeechRecognizer.requestAuthorization:")
            switch authStatus {
            case .authorized:
                print("\t- Speech recognition permission granted.")
                self.setSpeechRecognizerAuthorized(as: true)
            case .denied:
                print("\t- Speech recognition permission denied.")
            case .restricted:
                print("\t- Speech recognition not available on device.")
            case .notDetermined:
                print("\t- Speech recognition not determined.")
            @unknown default:
                print("\t- Unknown permission state received: \(authStatus).")
            }
        }
        
        self.session.requestRecordPermission() {
            allowed in
            print("\tQuerying session.requestRecordPermission:")
            if allowed {
                print("\t- Permission to record audio granted.")
                self.setSessionAuthorized(as: true)
                handler?()
            } else {
                print("\t- Permission to record audio denied.")
                // Consider hiding your playback button
            }
        }
    }
    
    func configureListeningForWakePhrase() {
        print("===== Speech Recognition: Configure Listening For Wake Phrase =====")
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if authStatus != .authorized {
            let dialogActions = [
                DialogAction(
                    title: "Grant Permission",
                    voiceCommand: "grant permission",
                    feedbackVisualMessage: "Permission Granted!",
                    feedbackAudioMessage: "permission granted",
                    style: .default,
                    handler: { [unowned self] action in
                    self.requestPermissions()
                }),
                DialogAction(
                    title: "Cancel",
                    voiceCommand: "cancel",
                    feedbackVisualMessage: "Canceled!",
                    feedbackAudioMessage: "Command canceled.",
                    style: .cancel,
                    handler: nil
                )
            ]
            
            let dialogItem = DialogItem(
                title: "Speech Recognition Permission Denied",
                message: "App requires permission to continue. Say 'grant permission' to continue, or 'cancel' to dismiss.",
                preferredStyle: .alert,
                actions: dialogActions
            )
            self.uiManager.presentDialog(dialogItem: dialogItem)
        } else {
            // pitch engine used to determine if user is male or female
            self.startListeningForWakePhrase()
        }
    }
    
    // MARK: - Methods
    
    @objc func handleToggleListening(_ sender: Any) {
        print("===== Speech Recognition Engine: Handle Toggle Listening =====")
        
        hapticEngine.success()
        
        // Toggle Speech Recogntion
        self.isActive = !self.isActive
        
        if self.isListeningForCommands || (!self.state.appActivated && self.isListeningForWakePhrase) {
            // Stop Listening
            if self.state.appActivated {
                self.stopListeningForVoiceCommands() {[weak self] in
                    DispatchQueue.main.async {
                        var buttons: [UIBarButtonItem] = []
                        
                        if let _ = Utils.getNavigationController()?.visibleViewController as? DetailViewController  {
                            let backToEntriesButton = self!.getBackToEntriesButton()
                            buttons.append(backToEntriesButton)
                        }
                        let stopListeningButton = self!.getStopListeningButton(withStopIndicator: true)
                        buttons.append(stopListeningButton)
                        Utils.getNavigationController()?.visibleViewController?.navigationItem.leftBarButtonItems = buttons
                    }
                }
            } else {
                self.stopListeningForWakePhrase() {[weak self] in
                    DispatchQueue.main.async {
                        var buttons: [UIBarButtonItem] = []
                        
                        if let _ = Utils.getNavigationController()?.visibleViewController as? DetailViewController  {
                            let backToEntriesButton = self!.getBackToEntriesButton()
                            buttons.append(backToEntriesButton)
                        }
                        let stopListeningButton = self!.getStopListeningButton(withStopIndicator: true)
                        buttons.append(stopListeningButton)
                        Utils.getNavigationController()?.visibleViewController?.navigationItem.leftBarButtonItems = buttons
                    }
                }
            }
        } else {
            // Start Listening
            if self.state.appActivated {
                // Listening For Commands
                self.startListeningForVoiceCommands()
                // Because it's missing in the actual handleListening method for voice commands
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                    soundEngine.startListening()
                }
            } else {
                self.startListeningForWakePhrase()
            }
        }
        
        checkRep()
    }
    
    @objc func handleBackToEntries(_ sender: Any) {
        print("===== Speech Recognition Engine: Handle Back To Entries =====")
        DispatchQueue.main.async {
            Utils.getNavigationController()?.visibleViewController?.performSegue(withIdentifier: Segues.moveFromDetailToEntryTable.rawValue, sender: nil)
        }
    }
    
    func activateListeningIndicator(withRecording: Bool = false, withStopListeningButton: Bool = false, withBackToEntriesButton: Bool = false) {
        print("===== Speech Recognition Engine: Activate Listening Indicator =====")
        print("\tWith Recording: ", withRecording)
        print("\tWith Stop Listening Button: ", withStopListeningButton)
        print("\tWith Back To Entries Button: ", withBackToEntriesButton)
        DispatchQueue.main.async {
            var buttons: [UIBarButtonItem] = []
            
            if withBackToEntriesButton {
                let backToEntriesButton = self.getBackToEntriesButton()
                buttons.append(backToEntriesButton)
            }
            
            let spinner = UIActivityIndicatorView(style: .medium)
            if withRecording {
                spinner.color = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
            } else {
                spinner.color = UIColor.systemGray
            }

            spinner.startAnimating()

            let spinnerButton = UIBarButtonItem(customView: spinner)
            buttons.append(spinnerButton)
            
            if withStopListeningButton {
                let stopListeningButton = self.getStopListeningButton()
                buttons.append(stopListeningButton)
            }
            
            Utils.getNavigationController()?.visibleViewController?.navigationItem.leftBarButtonItems = buttons
        }
        
        checkRep()
    }
    
    func deactivateListeningIndicator() {
        print("===== Speech Recognition Engine: Deactivate Listening Indicator =====")
        DispatchQueue.main.async {
            Utils.getNavigationController()?.visibleViewController?.navigationItem.leftBarButtonItems = nil
        }
        
        checkRep()
    }
    
    func getStopListeningButton(withStopIndicator: Bool = false) -> UIBarButtonItem {
        let button  = UIButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: Utils.NAVBAR_BUTTON_LENGTH, height: Utils.NAVBAR_BUTTON_LENGTH)
        button.addTarget(self, action: #selector(self.handleToggleListening), for: .touchDown)
        
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
    
    func getBackToEntriesButton() -> UIBarButtonItem {
        let button  = UIButton(type: .custom)
        
        button.frame = CGRect(x: 0.0, y: 0.0, width: Utils.NAVBAR_BUTTON_LENGTH, height: Utils.NAVBAR_BUTTON_LENGTH)
        button.addTarget(self, action: #selector(self.handleBackToEntries), for: .touchDown)
        
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = UIColor.systemGray
        
        let barButton = UIBarButtonItem(customView: button)
        
        return barButton
    }
    
    func startListeningForWakePhrase() {
        print("===== Speech Recognition Engine: Starting Listening for Wake Phrase =====")
        
        // If we're waiting for another session to wrap up, stage this one.
        if let stopListeningHandler = self.stopListeningHandler {
            print("\t[NOTE] Encountered existing 'stopListeningHandler'. Stage method to execute after handler.")
            let oldHandler = stopListeningHandler
            self.stopListeningHandler = {
                oldHandler()
                self.startListeningForWakePhrase()
            }
            
            return
        } else if let pauseListeningHandler = self.pauseListeningHandler {
            print("\t[NOTE] Encountered existing 'pauseListeningHandler'. Stage method to execute after handler.")
            let oldHandler = pauseListeningHandler
            self.pauseListeningHandler = {
                oldHandler()
                self.startListeningForWakePhrase()
            }
            
            return
        }
        
        self.setLastRecognitionTask(task: RecognitionTask.WAKE_PHRASE)
        
        // Update Wake Phrase Flage
        self.isListeningForWakePhrase = self.handleStartListening(
            type: .WAKE_PHRASE,
            contextualStrings: ["rise and shine"]
        ) {
            self.notifications.executeFeedback(
                visualMessage: "Listening for Wake Phrase...",
                audioMessage: "Say 'rise and shine' to wake from sleep.",
                discardPrior: true,
                withHaptics: true,
                delay: 5
            )
        }
        
        checkRep()
    }
    
    func stopListeningForWakePhrase(onStopHandler: (() -> Void)? = nil) {
        print("===== Speech Recognition Engine: Stopping Listening for Wake Phrase =====")
        
        // If we're waiting for another session to wrap up, stage this one.
        if let stopListeningHandler = self.stopListeningHandler {
            print("\t[NOTE] Encountered existing 'stopListeningHandler'. Stage method to execute after handler.")
            let oldHandler = stopListeningHandler
            self.stopListeningHandler = {
                oldHandler()
                self.stopListeningForWakePhrase(onStopHandler: onStopHandler)
            }
            
            return
        } else if let pauseListeningHandler = self.pauseListeningHandler {
            print("\t[NOTE] Encountered existing 'pauseListeningHandler'. Stage method to execute after handler.")
            let oldHandler = pauseListeningHandler
            self.pauseListeningHandler = {
                oldHandler()
                self.stopListeningForWakePhrase(onStopHandler: onStopHandler)
            }
            
            return
        }
        
        self.handleStopListening(type: .WAKE_PHRASE, onStopHandler: onStopHandler)
        
        // Update Wake Phrase Flage
        self.isListeningForWakePhrase = false
    }
    
    func startListeningForVoiceCommands(
        onStartHandler: (() -> Void)? = nil
    ) {
        print("===== Speech Recognition Engine: Starting Listening For Voice Commands =====")
        
        // If we're waiting for another session to wrap up, stage this one.
        if let stopListeningHandler = self.stopListeningHandler {
            print("\t[NOTE] Encountered existing 'stopListeningHandler'. Stage method to execute after handler.")
            let oldHandler = stopListeningHandler
            self.stopListeningHandler = {
                oldHandler()
                self.startListeningForVoiceCommands(onStartHandler: onStartHandler)
            }
            
            return
        } else if let pauseListeningHandler = self.pauseListeningHandler {
            print("\t[NOTE] Encountered existing 'pauseListeningHandler'. Stage method to execute after handler.")
            let oldHandler = pauseListeningHandler
            self.pauseListeningHandler = {
                oldHandler()
                self.startListeningForVoiceCommands(onStartHandler: onStartHandler)
            }
            
            return
        }

        // Make sure we're not listening for voice commands or speech already
        if self.isListeningForSpeech && !self.pausedListeningForSpeech {
            self.pauseListeningForSpeech() {
                self.startListeningForVoiceCommands(
                    onStartHandler: onStartHandler
                )
            }
            
            return
        } else if self.isListeningForCommands && !self.pausedListeningForCommands {
            print("\tAlready listening for commands.")
            return
        }
        
        if !self.isListeningForCommands || self.pausedListeningForCommands {
            self.setLastRecognitionTask(task: RecognitionTask.VOICE_COMMAND)
            
            self.isListeningForCommands = self.handleStartListening(
                type: .VOICE_COMMAND,
                onStartHandler: onStartHandler
            )
            
            checkRep()
        }
    }
    
    func pauseListeningForVoiceCommands(onPauseHandler: (() -> Void)? = nil) {
        print("===== Speech Recognition Engine: Pause Listening For Voice Commands =====")
        
        // If we're waiting for another session to wrap up, stage this one.
        if let stopListeningHandler = self.stopListeningHandler {
            print("\t[NOTE] Encountered existing 'stopListeningHandler'. Stage method to execute after handler.")
            let oldHandler = stopListeningHandler
            self.stopListeningHandler = {
                oldHandler()
                self.pauseListeningForVoiceCommands(onPauseHandler: onPauseHandler)
            }
            
            return
        } else if let pauseListeningHandler = self.pauseListeningHandler {
            print("\t[NOTE] Encountered existing 'pauseListeningHandler'. Stage method to execute after handler.")
            let oldHandler = pauseListeningHandler
            self.pauseListeningHandler = {
                oldHandler()
                self.pauseListeningForVoiceCommands(onPauseHandler: onPauseHandler)
            }
            
            return
        }
        
        if !self.pausedListeningForCommands {
            self.pausedListeningForCommands = true
        }
        
        self.handlePauseListening(type: .VOICE_COMMAND, onPauseHandler: onPauseHandler)
    }
    
    func stopListeningForVoiceCommands(onStopHandler: (() -> Void)? = nil) {
        print("===== Speech Recognition Engine: Stopping Listening For Voice Commands =====")
        
        // If we're waiting for another session to wrap up, stage this one.
        if let stopListeningHandler = self.stopListeningHandler {
            print("\t[NOTE] Encountered existing 'stopListeningHandler'. Stage method to execute after handler.")
            let oldHandler = stopListeningHandler
            self.stopListeningHandler = {
                oldHandler()
                self.stopListeningForVoiceCommands(onStopHandler: onStopHandler)
            }
            
            return
        } else if let pauseListeningHandler = self.pauseListeningHandler {
            print("\t[NOTE] Encountered existing 'pauseListeningHandler'. Stage method to execute after handler.")
            let oldHandler = pauseListeningHandler
            self.pauseListeningHandler = {
                oldHandler()
                self.stopListeningForVoiceCommands(onStopHandler: onStopHandler)
            }
            
            return
        }
        
        self.handleStopListening(type: .VOICE_COMMAND, onStopHandler: onStopHandler)
        
        if self.isListeningForCommands {
            self.isListeningForCommands = false
        }
    }
    
    func startListeningForSpeech(onStartHandler: (() -> Void)? = nil) {
        print("===== Speech Recognition Engine: Start Listening for Speech =====")
        
        // If we're waiting for another session to wrap up, stage this one.
        if let stopListeningHandler = self.stopListeningHandler {
            print("\t[NOTE] Encountered existing 'stopListeningHandler'. Stage method to execute after handler.")
            let oldHandler = stopListeningHandler
            self.stopListeningHandler = {
                oldHandler()
                self.startListeningForSpeech(onStartHandler: onStartHandler)
            }
            
            return
        } else if let pauseListeningHandler = self.pauseListeningHandler {
            print("\t[NOTE] Encountered existing 'pauseListeningHandler'. Stage method to execute after handler.")
            let oldHandler = pauseListeningHandler
            self.pauseListeningHandler = {
                oldHandler()
                self.startListeningForSpeech(onStartHandler: onStartHandler)
            }
            
            return
        }

        // Make sure we're not listening for voice commands or speech already
        if self.isListeningForCommands {
            self.stopListeningForVoiceCommands() {
                self.startListeningForSpeech(
                    onStartHandler: onStartHandler
                )
            }
            
            return
        } else if self.isListeningForSpeech && !self.pausedListeningForSpeech {
            self.notifications.executeError(
                text: "Already listening for speech.",
                handler: onStartHandler
            )
            return
        }
        
        if (!self.isListeningForSpeech || self.pausedListeningForSpeech) {
            if self.userInitiatedPausedListeningForSpeech {
                self.userInitiatedPausedListeningForSpeech = false
            }

            if self.pausedListeningForCommands {
                self.pausedListeningForCommands = false
            }

            self.setLastRecognitionTask(task: RecognitionTask.SPEECH)
            
            self.isListeningForSpeech = self.handleStartListening(
                type: .SPEECH,
                contextualStrings: VoiceCommandEngine.voiceCommands,
                onStartHandler: onStartHandler
            )
            
            checkRep()
        }
    }
    
    func pauseListeningForSpeech(
        userInitiated: Bool = false,
        preventListeningForCommands: Bool = false,
        onPauseHandler: (() -> Void)? = nil
    ) {
        print("===== Speech Recognition Engine: Pause Listening For Speech =====")
        
        // If we're waiting for another session to wrap up, stage this one.
        if let stopListeningHandler = self.stopListeningHandler {
            print("\t[NOTE] Encountered existing 'stopListeningHandler'. Stage method to execute after handler.")
            let oldHandler = stopListeningHandler
            self.stopListeningHandler = {
                oldHandler()
                self.pauseListeningForSpeech(
                    userInitiated: userInitiated,
                    preventListeningForCommands: preventListeningForCommands,
                    onPauseHandler: onPauseHandler
                )
            }
            
            return
        } else if let pauseListeningHandler = self.pauseListeningHandler {
            print("\t[NOTE] Encountered existing 'pauseListeningHandler'. Stage method to execute after handler.")
            let oldHandler = pauseListeningHandler
            self.pauseListeningHandler = {
                oldHandler()
                self.pauseListeningForSpeech(
                    userInitiated: userInitiated,
                    preventListeningForCommands: preventListeningForCommands,
                    onPauseHandler: onPauseHandler
                )
            }
            
            return
        }
        
        if !self.pausedListeningForSpeech {
            self.pausedListeningForSpeech = true
        }
        
        if userInitiated && !self.userInitiatedPausedListeningForSpeech {
            self.userInitiatedPausedListeningForSpeech = true
        }
        
        self.handlePauseListening(
            type: .SPEECH,
            preventListeningForCommands: preventListeningForCommands,
            onPauseHandler: onPauseHandler
        )
    }
    
    // make sure onStophandler is not also wrapped in DispatchQueue.main.async
    func stopListeningForSpeech(onStopHandler: (() -> Void)? = nil) {
        print("===== Speech Recognition Engine: Stop Listening For Speech =====")
        
        // If we're waiting for another session to wrap up, stage this one.
        if let stopListeningHandler = self.stopListeningHandler {
            print("\t[NOTE] Encountered existing 'stopListeningHandler'. Stage method to execute after handler.")
            let oldHandler = stopListeningHandler
            self.stopListeningHandler = {
                oldHandler()
                self.stopListeningForSpeech(onStopHandler: onStopHandler)
            }
            
            return
        } else if let pauseListeningHandler = self.pauseListeningHandler {
            print("\t[NOTE] Encountered existing 'pauseListeningHandler'. Stage method to execute after handler.")
            let oldHandler = pauseListeningHandler
            self.pauseListeningHandler = {
                oldHandler()
                self.stopListeningForSpeech(onStopHandler: onStopHandler)
            }
            
            return
        }
        
        self.listeningTimer?.invalidate()
        self.listeningTimer = nil

        self.handleStopListening(type: .SPEECH, onStopHandler: onStopHandler)
        
        if self.isListeningForSpeech {
            self.isListeningForSpeech = false
        }
    }
    
//        func startListeningForVolume() {
//            print("===== Starting Listening for Volume =====")
//            print("volume: ", AVAudioSession.sharedInstance().outputVolume)
//            // set listening flag to true
//
//
//            // Play Sound
//            soundEngine.startListening()
//            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
//                soundEngine.startProcessing()
//            }
//
//            // clear pitch and sound intensity streams
//            self.pitchStream = [PitchDatum]()
//            self.soundIntensityStream = [SoundIntensityDatum]()
//
//            // must be placed before we start listening for wake phrase
//            // if pitch engine begins first, we are for some reason unable to do speech recognition
//            pitchEngine.start()
//
//            let node = audioEngine.inputNode
//            let recordingFormat = node.outputFormat(forBus: recordBus)
//
//            node.installTap(onBus: recordBus, bufferSize: 1024, format: recordingFormat) { [unowned self] (buffer, _) in
//                if !self.isListeningForVolume {
//                    self.isListeningForVolume = true
//                    self.stopListeningForVolumeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) {[weak self] timer in
//                        self?.stopListeningForVolume() {
//                            self?.entry.startListeningForVoiceCommands(
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
//                                    self?.entry.startListeningForVoiceCommands(
//                                        soundIntensityHandler: self!.soundIntensityHandler!,
//                                        pitchHandler: self!.pitchHandler!
//                                    )
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//
//            audioEngine.prepare()
//            do {
//                try audioEngine.start()
//            } catch let error {
//                print("[Error] There was a problem starting speech recognition: \(error.localizedDescription)")
//            }
//        }
    
//        func stopListeningForVolume(onStopHandler: (() -> Void)? = nil) {
//            print("===== Stopping Listening for Volume =====")
//
//            // Play Sound
//            soundEngine.stopProcessing()
//            soundEngine.stopListening()
//
//
//
//            let node = audioEngine.inputNode
//            node.removeTap(onBus: self.recordBus)
//
//            audioEngine.stop()
//            // We instantiate new audio engine in case headphones have been added or removed
//            // Removing an audio node will create a broken graph: https://developer.apple.com/documentation/avfoundation/avaudioengine
//            audioEngine = AVAudioEngine()
//
//            self.soundIntensityIndicatorHeight.constant = 0
//            self.isListeningForVolume = false
//            self.stopListeningForVolumeTimer = nil
//            NotificationCenter.default.post(
//                name: SpeechRecognitionEngine.onStoppedListening,
//                object: nil,
//                userInfo: [:]
//            )
//            print("volume: ", AVAudioSession.sharedInstance().outputVolume)
//            onStopHandler?()
//        }
    
    // MARK: - Setters
    
    func setLastRecognitionTask(task: RecognitionTask) {
        print("===== Speech Recognition Engine: Set Last Recognition Task =====")
        self.lastRecognitionTask = task
        
        checkRep()
    }
    
    func setListeningTimer(timer: Timer? = nil) {
        print("===== Speech Recognition Engine: Set Listening Timer =====")
        self.listeningTimer?.invalidate()
        self.listeningTimer = timer
        
        checkRep()
    }
    
    func setSpeechRecognizerAuthorized(as value: Bool) {
        print("===== Speech Recognition Engine: Set Speech Recognizer Authorized =====")
        self.speeechRecognizerAuthorized = value
    }
    
    func setSessionAuthorized(as value: Bool) {
        print("===== Speech Recognition Engine: Set Session Authorized =====")
        self.sessionAuthorized = value
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
    
    func getDurationListening() -> Float {
        // print("===== Get Duration Listening =====")
        if let entry = self.entryManager.currentEntry, self.pausedListeningForSpeech {
            return Float(entry.endTime.seconds)
        } else if let entry = self.entryManager.currentEntry, entry.currentClipUID != nil && entry.recordStartDate != nil && entry.entrySegments.count > 0 {
            return Float(Date().timeIntervalSince(entry.recordStartDate!))
        } else if let entry = self.entryManager.currentEntry, entry.recordStartDate != nil {
            return Float(Date().timeIntervalSince(entry.recordStartDate!))
        }
        
        return 0
    }
    
    func getRecordingSoundIntensityDatum(timestamp: Double) -> SoundIntensityDatum {
        var datum: SoundIntensityDatum
        var i = 0
        var datumTimestamp = self.soundIntensityStream[i].date - self.entryManager.currentEntry!.recordStartDate! - Utils.TRANSCRIPTION_LATENCY_DURATION
        repeat {
            datumTimestamp = self.soundIntensityStream[i].date - self.entryManager.currentEntry!.recordStartDate! - Utils.TRANSCRIPTION_LATENCY_DURATION
            datum = self.soundIntensityStream[i]
            i += 1
        } while datumTimestamp < timestamp && i < self.soundIntensityStream.count
        
        return datum
    }
    
    // MARK: - Key-Value Observer
    
    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?)
    {
        print("===== Speech Recognition Engine: Observe Value =====")
        if keyPath == #keyPath(AVAudioSession.outputVolume) {
            print("\tKeyPath: AVAudioSession.outputVolume")

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
                print("\tNew Volume: ", outputVolume)
            } else {
                outputVolume = -1
                print("\tNew Volume: ", outputVolume)
            }
        } else if keyPath == "hasSelection" {
            if let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, newHasSelection && !oldHasSelection && self.isListeningForSpeech {
                print("\tKeyPath: hasSelection")
                print("\tSelection established.")
                // We show command bar when successfully paused listening for speech
                // stop listening for speech, start listening for commands
                if  self.isListeningForSpeech {
                    print("\tPause speech and start listening for commands.")
                    self.pauseListeningForSpeech()
                }
//                } else if !self.isListeningForSpeech && !self.isListeningForCommands {
//                    self.startListeningForVoiceCommands()
//                }
            } else if let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && self.isListeningForSpeech && self.isListeningForCommands && !self.speechPlayer.isPlayingEntry && !self.speechSynthesis.isPlayingEcho && !self.speechSynthesis.isPlayingPassiveEcho {
                print("\tKeyPath: hasSelection")
                print("\tSelection removed.")
                // start listening for speech again
                if self.pausedListeningForSpeech && !self.selectionCursor.isUpdatingSelection {
                    print("\tResume listening for commands.")
                    self.startListeningForSpeech()
                }
                
                if self.state.withPunctuationSuggestions {
                    print("\tInvalidate punctuation suggestion timers...")
                    self.sentenceSuggestionTimer?.invalidate()
                    self.paragraphSuggestionTimer?.invalidate()
                }
            }
        } else if keyPath == "selectionCursor" {
            print("\tKeyPath: selectionCursor")
            if let selectionCursor = change?[.newKey] as? SelectionCursor {
                selectionCursor.addObserver(
                    self,
                    forKeyPath: "hasSelection",
                    options: [.old, .new],
                    context: nil
                )
            }
        } else if keyPath == "listeningPermissionsGranted" {
            print("\tKeyPath: listeningPermissionsGranted")
            let withOnDeviceRecognition = self.state.withOnDeviceRecognition
            let supportsOnDeviceRecognition = self.speechRecognizer!.supportsOnDeviceRecognition
            let listeningPermissionsGranted = self.listeningPermissionsGranted
            if let _ = self.speechRecognizer, !self.isListeningForWakePhrase && withOnDeviceRecognition && listeningPermissionsGranted && supportsOnDeviceRecognition {
                print("\tReceived listeningPermissionsGranted and all systems ready =====")
                self.configureListeningForWakePhrase()
            } else {
                print("\tReceived listeningPermissionsGranted but not all systems ready:")
                print("\tspeechRecognizer: ", self.speechRecognizer != nil ? "available" : "unavailable")
                print("\twithOnDeviceRecognition: ", withOnDeviceRecognition)
                print("\tspeechRecognizer.supportsOnDeviceRecognition: ", supportsOnDeviceRecognition)
                print("\tlisteningPermissionsGranted: ", listeningPermissionsGranted)
            }
        } else if let speechRecognizer = self.speechRecognizer, keyPath == "supportsOnDeviceRecognition" && speechRecognizer.supportsOnDeviceRecognition {
            print("\tKeyPath: supportsOnDeviceRecognition")
            let withOnDeviceRecognition = self.state.withOnDeviceRecognition
            let supportsOnDeviceRecognition = self.speechRecognizer!.supportsOnDeviceRecognition
            let listeningPermissionsGranted = self.listeningPermissionsGranted
            if let _ = self.speechRecognizer, !self.isListeningForWakePhrase && withOnDeviceRecognition && listeningPermissionsGranted && supportsOnDeviceRecognition {
                print("\tReceived supportsOnDeviceRecognition and all systems ready =====")
                self.configureListeningForWakePhrase()
            } else {
                print("\tReceived supportsOnDeviceRecognition but not all systems ready:")
                print("\tspeechRecognizer: ", self.speechRecognizer != nil ? "available" : "unavailable")
                print("\twithOnDeviceRecognition: ", withOnDeviceRecognition)
                print("\tspeechRecognizer.supportsOnDeviceRecognition: ", supportsOnDeviceRecognition)
                print("\tlisteningPermissionsGranted: ", listeningPermissionsGranted)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    func exhaustSpeechRecognizedQueue() {
        print("===== Speech Recognition Engine - Exhaust Speech Recognized Queue =====")
        let _ = self.speechRecognizedQueue.dequeue()
        soundEngine.speechRegistered()
        self.speechRecognizedTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: false) { timer in
            if !self.speechRecognizedQueue.isEmpty {
                self.exhaustSpeechRecognizedQueue()
            } else {
                self.speechRecognizedTimer = nil
            }
        }
    }
    
    func handleStartListening(
        type: RecognitionTask,
        contextualStrings: [String]? = nil,
        onStartHandler: (() -> Void)? = nil
    ) -> Bool {
        if (self.speechSynthesis.isPlayingEcho && !self.speechSynthesis.pausedEcho) || self.speechSynthesis.isPlayingPassiveEcho {
            // Stop active echo
            self.speechSynthesis.stopEcho(withFeedback: false)
        }
        
        if self.speechPlayer.isPlayingEntry && !self.speechPlayer.pausedPlayingEntry && !self.selectionCursor.hasSelection {
            // stop active playback
            self.speechPlayer.stop(withFeedback: false)
        }
        
        if (type == .SPEECH && !self.pausedListeningForSpeech) ||
            (type == .WAKE_PHRASE && self.state.playedStartupSound) {
            // Play Sound
            // We delay so that it can be heard
            let delay: TimeInterval = type == .WAKE_PHRASE ? 1.5 : 1
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { timer in
                soundEngine.startListening()
            }
        }
        
        // remove paused commands flag
        // must be placed after soundEngine call
        // to prevent always executing startListening sound effect
        // remove paused listening flag
        //
        // Listening for Commands should not be able to override this
        if self.pausedListeningForSpeech && type == .SPEECH {
            self.pausedListeningForSpeech = false
        }
        
        if self.pausedListeningForCommands {
            self.pausedListeningForCommands = false
        }
        
        // Give haptic feedback
        // hapticEngine.heavyImpact()
        hapticEngine.success()
        
        // flag to run start handler
        self.executedListeningStartHandler = false
        
        let executeListening: () -> Bool = {
            if self.audioEngine.isRunning {
                print("\tStopped running audio engine...")
                self.audioEngine.stop()
            }
            
            // We must call this before we begin the SFSpeechAudioBufferRecognitionRequest
            // so that the recording we create aligns in time with the speech recognition
            // transcript
            if type == .SPEECH {
                NotificationCenter.default.post(
                    name: SpeechRecognitionEngine.onRequestPrepareAudioFile,
                    object: nil,
                    userInfo: [:]
                )
            }
            
            let node = self.audioEngine.inputNode
            let recordingFormat = node.outputFormat(forBus: self.recordBus)
            print("===== Recording Info ===== \n\tSoftware Format: \(recordingFormat.sampleRate)\n\tHardware Format: \(AVAudioSession.sharedInstance().sampleRate) \n\tInput Latency: \(self.session.inputLatency.rounded(toPlaces: 5)) \n\tOutput Latency: \(self.session.outputLatency.rounded(toPlaces: 5)) \n\tIOBufferDuration: \(self.session.ioBufferDuration.rounded(toPlaces: 5))")
            
    //        let recordSettings: [String : AnyObject] = [
    //            AVSampleRateKey : NSNumber(value: Float(16000)),
    //            AVFormatIDKey : NSNumber(value: Int32(kAudioFormatMPEG4AAC)),
    //            AVNumberOfChannelsKey : NSNumber(value: 1),
    //            AVEncoderAudioQualityKey : NSNumber(value: Int32(AVAudioQuality.low.rawValue))
    //        ]
            
            // Set up values for speech recognition
            // It's best to reset this everytime we want to listen for new speech
            // This way we can trash faulty tasks
            self.request = SFSpeechAudioBufferRecognitionRequest()
            self.request!.shouldReportPartialResults = true
            self.request!.requiresOnDeviceRecognition = false // Set to false by default, but conditionally changed below
            
            // Tap into microphone bus to receive and process audio input buffers
            node.installTap(onBus: self.recordBus, bufferSize: 1024, format: recordingFormat) { [unowned self] (buffer, _) in
                // Capture buffer
                self.request!.append(buffer)

                if !self.executedListeningStartHandler {
                    print("\tExecute start listening handler and notification...")
                    self.executedListeningStartHandler = true
                    
                    switch (type) {
                    case .SPEECH:
                        print("\tBroadcast 'onStartedListeningForSpeech' notification...")
                        // Capture last started listening timestamp
                        self.lastStartedListeningTimestamp = Date().timeIntervalSince1970
                        NotificationCenter.default.post(
                            name: SpeechRecognitionEngine.onStartedListeningForSpeech,
                            object: nil,
                            userInfo: [:]
                        )
                    case .VOICE_COMMAND:
                        print("\tBroadcast 'onStartedListeningForCommands' notification...")
                        NotificationCenter.default.post(
                            name: SpeechRecognitionEngine.onStartedListeningForCommands,
                            object: nil,
                            userInfo: [:]
                        )
                    case .WAKE_PHRASE:
                        print("\tBroadcast 'onStartedListeningForWakePhrase' notification...")
                        NotificationCenter.default.post(
                            name: SpeechRecognitionEngine.onStartedListeningForWakePhrase,
                            object: nil,
                            userInfo: [:]
                        )
                    }

                    onStartHandler?()
                }
                
                // Handle sound intensity and pitch information
                // Sound Intensity
                let power = Utils.computeSoundIntensity(buffer: buffer)
                if let power = power {
                    let soundIntensityDatum = SoundIntensityDatum(date: Date(), power: power)
                    self.soundIntensityStream.append(soundIntensityDatum)
                    NotificationCenter.default.post(
                        name: SpeechRecognitionEngine.onPowerUpdate,
                        object: nil,
                        userInfo: [ "power" : soundIntensityDatum]
                    )
                }
                
                // Broadcast buffer item
                NotificationCenter.default.post(
                    name: SpeechRecognitionEngine.onBufferItem,
                    object: nil,
                    userInfo: [ "buffer" : buffer ]
                )
            }
            
            // Prepare and start audio engine
            self.audioEngine.prepare()
            do {
                try self.audioEngine.start()
            } catch let error {
                print("[Error] There was a problem starting speech recognition: \(error.localizedDescription)")
            }
            
            let handleRecognizer: () -> Bool = {
                print("\tUsing On-Device Recognition")
                self.request!.requiresOnDeviceRecognition = true
                
                if let contextualStrings = contextualStrings {
                    print("\tLoad contextual strings")
                    self.request!.contextualStrings = contextualStrings
                }
                
                if let speechRecognizer = self.speechRecognizer, !speechRecognizer.isAvailable {
                    print("\tSpeech Recognizer is not available")
                    return false
                }
                
                // Let speech recognizer know we're performing dictation or voice commands
                self.speechRecognizer?.defaultTaskHint = .dictation
                
                // It's best to reset this everytime we want to listen for new speech
                // This way we can trash faulty tasks
                self.recognitionTask = self.speechRecognizer?.recognitionTask(with: self.request!, delegate: self)
                
                self.lastStartListeningDate = Date()
                
                return true
            }
            
            let withOnDeviceRecognition = self.state.withOnDeviceRecognition
            let supportsOnDeviceRecognition = self.speechRecognizer!.supportsOnDeviceRecognition
            let listeningPermissionsGranted = self.listeningPermissionsGranted
            if let _ = self.speechRecognizer, withOnDeviceRecognition && supportsOnDeviceRecognition && listeningPermissionsGranted {
                print("\tAll systems were ready to initiate listening...")
                return handleRecognizer()
            } else {
                print("\tNot all systems were ready to initiate listening:")
                print("\tspeechRecognizer: ", self.speechRecognizer != nil ? "available" : "unavailable")
                print("\twithOnDeviceRecognition: ", withOnDeviceRecognition)
                print("\tspeechRecognizer.supportsOnDeviceRecognition: ", supportsOnDeviceRecognition)
                print("\tlisteningPermissionsGranted: ", listeningPermissionsGranted)
                return false
            }
            
    //        // Present error
    //        let dialogActions = [
    //            DialogAction(title: "Close", style: .cancel, handler: nil)
    //        ]
    //
    //        let dialogItem = DialogItem(
    //            title: "Unable to initiate Voice Recognition",
    //            message: "Lingual relies on on-device recognition to deliver a the best user experience. Your device does not support it.",
    //            preferredStyle: .alert,
    //            actions: dialogActions
    //        )
    //        Utils.presentDialog(dialogItem: dialogItem)
        }
        
        // Make sure any previous recognition tasks are finished
        // If self.lastSpeechRecognizerHypothesizeDate is not nil, we haven't received final transcript
        // from it yet
        if let recognitionTask = self.recognitionTask, recognitionTask.state == .running || self.lastSpeechRecognizerHypothesizeDate != nil {
            print("\tFound existing recognition task. End it")
            DispatchQueue.main.async {
                // When this is not in the main thread, the recognition task doesn't end correctly
                // which prevents us from receiving the final transcription.
                recognitionTask.finish() // don't wrap in if statement because it is sometimes not .running
                self.request!.endAudio() // don't add a request = nil because it results in request not being there sometimes.
                
                let isListening = executeListening()
                
                switch (type) {
                case .WAKE_PHRASE:
                    self.isListeningForWakePhrase = isListening
                case .VOICE_COMMAND:
                    self.isListeningForCommands = isListening
                case .SPEECH:
                    self.isListeningForSpeech = isListening
                }
            }
            
            switch (type) {
            case .WAKE_PHRASE:
                return self.isListeningForWakePhrase
            case .VOICE_COMMAND:
                return self.isListeningForCommands
            case .SPEECH:
                return self.isListeningForSpeech
            }
        } else {
            return executeListening()
        }
    }
    
    func handlePauseListening(type: RecognitionTask, preventListeningForCommands: Bool = false, onPauseHandler: (() -> Void)? = nil) {
        let node = self.audioEngine.inputNode
        node.removeTap(onBus: self.recordBus)
        
        let executePause = {
            self.audioEngine.stop() // Things get message when we use self.audioEngine.pause(). Affects ability to listen again afterwards
            // When this is not in the main thread, the recognition task doesn't end correctly
            // which prevents us from receiving the final transcription.
            self.recognitionTask?.finish() // don't wrap in if statement because it is sometimes not .running
            self.request?.endAudio() // don't add a request = nil because it results in request not being there sometimes.
            
            // We instantiate new audio engine in case headphones have been added or removed
            // Removing an audio node will create a broken graph: https://developer.apple.com/documentation/avfoundation/avaudioengine
            self.audioEngine = AVAudioEngine()
        }
        
        let handleBroadcast = {
            switch (type) {
            case .SPEECH:
                NotificationCenter.default.post(
                    name: SpeechRecognitionEngine.onPausedListeningForSpeech,
                    object: nil,
                    userInfo: [:]
                )
            case .VOICE_COMMAND:
                NotificationCenter.default.post(
                    name: SpeechRecognitionEngine.onPausedListeningForCommands,
                    object: nil,
                    userInfo: [:]
                )
            case .WAKE_PHRASE:
                break
            }
        }

        if type == .SPEECH || type == .VOICE_COMMAND {
            if !preventListeningForCommands && type == .SPEECH {
                let pauseListeningHandler = { [weak self] in
                    let _ = self?.startListeningForVoiceCommands(
                        onStartHandler: {
                            onPauseHandler?()
                            handleBroadcast()
                            self?.checkRep()
                        }
                    )
                }
                
                self.pauseListeningHandler = pauseListeningHandler
            } else {
                let pauseListeningHandler = {
                    onPauseHandler?()
                    handleBroadcast()
                    self.checkRep()
                }
                
                self.pauseListeningHandler = pauseListeningHandler
            }
        } else {
            let pauseListeningHandler = {
                onPauseHandler?()
                handleBroadcast()
                self.checkRep()
            }
            
            self.pauseListeningHandler = pauseListeningHandler
        }
        
        executePause()
    }
    
    func handleStopListening(type: RecognitionTask, onStopHandler: (() -> Void)? = nil) {
        if (type == .SPEECH && !self.isListeningForSpeech) ||
            (type == .VOICE_COMMAND && !self.isListeningForCommands) ||
            (type == .WAKE_PHRASE && !self.isListeningForWakePhrase) {
            self.notifications.executeError(
                text: "Not currently listening.",
                handler: onStopHandler
            )
            return
        }
        
        // Give haptic feedback
//        hapticEngine.heavyImpact()
        hapticEngine.success()
        
        // Listening for Commands should not be able to override this
        if self.pausedListeningForSpeech && type == .SPEECH {
            self.pausedListeningForSpeech = false
        }
        
        if self.pausedListeningForCommands {
            self.pausedListeningForCommands = false
        }
        
        // Play Sound
//        if type == .SPEECH {
//            soundEngine.stopListening()
//        }
        
        let node = self.audioEngine.inputNode
        node.removeTap(onBus: self.recordBus)
        
        // End punctuation suggestion timers
        if let sentenceSuggestionTimer = self.sentenceSuggestionTimer, self.state.withPunctuationSuggestions {
            sentenceSuggestionTimer.invalidate()
            self.sentenceSuggestionTimer = nil
        }
        
        if let paragraphSuggestionTimer = self.paragraphSuggestionTimer, self.state.withPunctuationSuggestions {
            paragraphSuggestionTimer.invalidate()
            self.paragraphSuggestionTimer = nil
        }
        
        self.lastSpeechRecognizerHypothesizeDate = nil
        self.lastStartListeningDate = nil
        
        let stopListeningHandler = { [weak self] in
            onStopHandler?()
            switch (type) {
            case .SPEECH:
                NotificationCenter.default.post(
                    name: SpeechRecognitionEngine.onStoppedListeningForSpeech,
                    object: nil,
                    userInfo: [:]
                )
            case .VOICE_COMMAND:
                NotificationCenter.default.post(
                    name: SpeechRecognitionEngine.onStoppedListeningForCommands,
                    object: nil,
                    userInfo: [:]
                )
            case .WAKE_PHRASE:
                
                NotificationCenter.default.post(
                    name: SpeechRecognitionEngine.onStoppedListeningForWakePhrase,
                    object: nil,
                    userInfo: [:]
                )
            }
            self?.checkRep()
        }
        
        self.stopListeningHandler = stopListeningHandler
        
        // When this is not in the main thread, the recognition task doesn't end correctly
        // which prevents us from receiving the final transcription.
        self.audioEngine.stop()
        self.recognitionTask?.finish()
        self.request?.endAudio() // don't add a request = nil because it results in request not being there sometimes.
        
        // We instantiate new audio engine in case headphones have been added or removed
        // Removing an audio node will create a broken graph: https://developer.apple.com/documentation/avfoundation/avaudioengine
        self.audioEngine = AVAudioEngine()
    }
    
    func isValidVoiceCommand(query: String) -> (Bool, InvalidVoiceCommandType?, String?, Int?) {
        print("===== Speech Recognition Engine: Is Valid Voice Command =====")
        print("\tVoice Command: ", query)
        if let (type, numWordsBeforeVoiceCommand) = voiceCommandEngine.includesCommand(passage: query) {
            if let lastVoiceCommand = self.voiceCommandStream.last, self.isListeningForSpeech && lastVoiceCommand.type == type && Date() < lastVoiceCommand.date.addingTimeInterval(Utils.MINIMUM_REST_BETWEEN_VOICE_COMMANDS) {
                // Likely too close to last voice command that was the same voice command
                print("\t[Invalid] Likely too close to last voice command that was the same voice command")
                return (false, .CLOSE_TO_LAST_VOICE_COMMAND, type, numWordsBeforeVoiceCommand)
            } else if self.uiManager.dialogIsVisible && self.uiManager.dialogIsModal && !self.uiManager.modalContainsCommand(command: query).0 {
                // Attempting to make foreign command while modal dialog is visible
                print("\t[Invalid] Attempting to make foreign command while modal dialog is visible")
                return (false, .FOREIGN_COMMAND_WHILE_MODAL_VISIBLE, type, numWordsBeforeVoiceCommand)
            } else if !self.selectionCursor.hasSelection && voiceCommandEngine.isSelectionVoiceCommand(command: type) {
                // Attempting to use selection voice command without selection
                print("\t[Invalid] Attempting to use selection voice command without selection")
                return (false, .SELECTION_COMMAND_WITHOUT_SELECTION, type, numWordsBeforeVoiceCommand)
            } else if self.entryManager.currentEntry == nil && type != "start entry" && (voiceCommandEngine.isEntryVoiceCommand(command: type) || voiceCommandEngine.isEntryManagerCommand(command: type)) {
                // Attempt to make entry command when no entry set
                print("\t[Invalid] Attempt to make entry command when no entry set")
                return (false, .ENTRY_COMMAND_WITHOUT_ENTRY_SET, type, numWordsBeforeVoiceCommand)
            } else if !self.uiManager.dialogIsVisible && voiceCommandEngine.isUIManagerCommand(command: type) && (type != "cancel" && self.selectionCursor.isUpdatingSelection) {
                // User said ui manager vocie command when wasn't visible
                print("\t[Invalid] User said ui manager voice command when wasn't visible")
                return (false, .UI_MANAGER_COMMAND_WITHOUT_DIALOG_VISIBLE, type, numWordsBeforeVoiceCommand)
            } else if type == "stop" && !self.speechPlayer.isPlayingEntry && !self.speechSynthesis.isPlayingEcho && !self.entryManager.isRunningEntry {
                // User said stop when no stoppable mode was active
                print("\t[Invalid] User said stop when no stoppable mode was active")
                return (false, .STOP_COMMAND_WITHOUT_SUITABLE_MODE, type, numWordsBeforeVoiceCommand)
            } else if type == "delete" && self.isListeningForSpeech && !self.selectionCursor.hasSelection {
                // Attemping to delete entry while listening for speech without selection
                print("\t[Invalid] Attemping to delete entry while listening for speech without selection")
                return (false, .DELETE_ENTRY_WHILE_LISTENING_FOR_SPEECH, type, numWordsBeforeVoiceCommand)
            } else {
                print("\t[Valid] Voice command is valid")
                return (true, nil, type, numWordsBeforeVoiceCommand)
            }
        } else {
            if let lastVoiceCommand = self.voiceCommandStream.last, self.isListeningForSpeech && Date() < lastVoiceCommand.date.addingTimeInterval(Utils.MINIMUM_REST_BETWEEN_VOICE_COMMANDS) {
                print("\t[Invalid] Voice command does not exist and too close to last voice command that was the same voice command.")
                return (false, .CLOSE_TO_LAST_VOICE_COMMAND, nil, nil)
            }
            print("\t[Invalid] Voice command does not exist.")
            // Is an invalid voice command
            return (false, .VOICE_COMMAND_NOT_FOUND, nil, nil)
        }
    }
    
    func getTranscriptText(segments: [SFTranscriptionSegment]) -> String {
        var text = ""
        for segment in segments {
            text += " \(segment.substring)"
        }
        
        return text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func searchForWakePhrase(
        transcription: SFTranscription,
        earlyDetection: Bool = false
    ) {
        print("===== Speech Recognition Engine: Search For Wake Phrase =====")
        // Get transcription text
        let text = self.getTranscriptText(segments: transcription.segments).lowercased()

        // Process for wake phrase
        if text.contains(self.wakePhrases[0]) ||
            text.contains(self.wakePhrases[1]) ||
            text.contains(self.wakePhrases[2]) {
            // Set early detection flag on
            self.earlyValidVoiceCommandDetection = earlyDetection
            // Wake Phrase Detected
            self.handleWakePhraseDetected()
        } else if !text.contains("rise") &&
            !text.contains("rise and") &&
            !text.contains("rison") &&
            !text.contains("razon") &&
            !self.earlyInvalidVoiceCommandDetection { // we don't want to repeat error twice
            // Set early detection flag on
            self.earlyInvalidVoiceCommandDetection = earlyDetection
            self.handleWakePhraseError(text: text, transcription: transcription)
        }

        return
    }
    
    func handleWakePhraseDetected() {
        print("===== Speech Recognition Engine: Handle Wake Phrase Detected =====")
        self.stopListeningForWakePhrase() {
            // Play Sound
            // We delay so that it can be heard
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                soundEngine.correctWakePhrase()
            }
            
            if self.state.withPunctuationSuggestions {
                print("\tInvalidate punctuation suggestion timers...")
                self.sentenceSuggestionTimer?.invalidate()
                self.paragraphSuggestionTimer?.invalidate()
            }
            
            self.earlyValidVoiceCommandDetection = false
            
            // Give haptic feedback
            hapticEngine.success()
            
            // start listening for voice commands
            self.startListeningForVoiceCommands()
            
            NotificationCenter.default.post(
                name: SpeechRecognitionEngine.onWakePhraseDetected,
                object: nil,
                userInfo: [:]
            )
        }
    }
    
    func handleWakePhraseError(text: String, transcription: SFTranscription) {
        print("===== Speech Recognition Engine: Handle Wake Phrase Error =====")
        // Play Sound
        soundEngine.incorrectWakePhrase()
        
        // Give haptic feedback
        hapticEngine.error()
        
        NotificationCenter.default.post(
            name: SpeechRecognitionEngine.onIncorrectWakePhrase,
            object: nil,
            userInfo: [
                "utterance": text,
                "transcription": transcription
            ]
        )
    }
    
    func handleDetectValidVoiceCommand(
        voiceCommandType: String,
        transcription: SFTranscription,
        earlyDetection: Bool = false,
        handled: Bool = false
    ) {
        print("===== Speech Recognition Engine: Handle Detect Valid Voice Command =====")
        print("\tCommand Recognized!: \(voiceCommandType)")

        // Remove voice command text previous added to text view if voice command detected
        if let entry = self.entryManager.currentEntry, !self.isListeningForSpeech && entry.entrySegments.count == 0 {
            // Don't clear text if we're mid-entry
            entry.handleOnSpeechUpdate(text: "")
        }
        
        // clear any previous notifications
        self.notifications.stopNotification()
        
        // Set early detection flag on
        self.earlyValidVoiceCommandDetection = earlyDetection
        
        // Capture valid voice command if we are composing a entry
        if let _ = self.entryManager.currentEntry, self.isListeningForSpeech {
            let date = Date()
            let voiceCommandDatum = VoiceCommandDatum(
                date: date,
                utteredSpeech: transcription.formattedString,
                isValid: true,
                type: voiceCommandType
            )
            self.voiceCommandStream.append(voiceCommandDatum)
            
            // Increment State Aggregate Count
            self.state.incrementVoiceCommandCount(timeInterval: date.timeIntervalSince1970)
        }
        
        if !handled {
            // Process Voice Command
            if voiceCommandType == "stop entry" && AVAudioSession.isHeadphonesConnected {
                voiceCommandEngine.process(
                    command: voiceCommandType,
                    utterance: transcription.formattedString
                ) {
                    if let entry = self.entryManager.currentEntry, self.isListeningForSpeech {
                        entry.handleOnSpeechUpdate(text: entry.getText())
                    } else {
                        NotificationCenter.default.post(
                            name: Entry.onRequestToUpdateView,
                            object: nil,
                            userInfo: [:]
                        )
                    }
                }
            } else {
                // we want to cache hasSelection so that the process(query:) handler
                // uses the value that we had when the method was called
                let hasSelection = self.selectionCursor.hasSelection
                let isUpdatingSelection = self.selectionCursor.isUpdatingSelection
                voiceCommandEngine.process(
                    command: voiceCommandType,
                    utterance: transcription.formattedString
                ) { [weak self] in
                    if voiceCommandType != "pause entry" &&
                        voiceCommandType != "create entry" &&
                        voiceCommandType != "open selection" &&
                        voiceCommandType != "select commit" &&
                        voiceCommandType != "walk commit" &&
                        voiceCommandType != "run commit" &&
                        voiceCommandType != "walk selection" &&
                        voiceCommandType != "run selection" &&
                        voiceCommandType != "pause run" &&
                        voiceCommandType != "next element" &&
                        voiceCommandType != "remove selection" &&
                        voiceCommandType != "delete selection" &&
                        voiceCommandType != "previous element" &&
                        voiceCommandType != "exit mode" &&
                        voiceCommandType != "walk entry" &&
                        voiceCommandType != "run entry" &&
                        !isUpdatingSelection &&
                        !hasSelection &&
                        !voiceCommandEngine.isUIManagerCommand(command: voiceCommandType) &&
                        self!.pausedListeningForSpeech
                    {
                        // Start listening for speech again if paused
                        // It won't be paused if the processed voice command was 'stop entry'
                        if !self!.selectionCursor.hasSelection {
                            self?.startListeningForSpeech() { [weak self] in
                                if let entry = self!.entryManager.currentEntry, self!.isListeningForSpeech {
                                    entry.handleOnSpeechUpdate(text: entry.getText())
                                } else {
                                    NotificationCenter.default.post(
                                        name: Entry.onRequestToUpdateView,
                                        object: nil,
                                        userInfo: [:]
                                    )
                                }
                            }
                        }
                    } else {
                        if let entry = self?.entryManager.currentEntry,
                           self!.isListeningForSpeech &&
                            !self!.selectionCursor.isUpdatingSelection
                        {
                            entry.handleOnSpeechUpdate(text: entry.getText())
                        } else {
                            NotificationCenter.default.post(
                                name: Entry.onRequestToUpdateView,
                                object: nil,
                                userInfo: [:]
                            )
                        }
                    }
                }
            }
        }
    }
    
    func handleInvalidVoiceCommand(
        transcription: SFTranscription,
        earlyDetection: Bool = false
    ) {
        print("===== Speech Recognition Engine: Handle Invalid Voice Command =====")
        // Play Sound
        soundEngine.voiceCommandDeny()
        
        // Set early detection flag on
        self.earlyInvalidVoiceCommandDetection = earlyDetection

        // Get invalid voice command text
        let text = self.getTranscriptText(segments: transcription.segments)
        
        let (foundAction, _) = self.uiManager.modalContainsCommand(command: text)
        if let validOptions = self.uiManager.getValidOptionsString(), !foundAction && self.uiManager.dialogIsModal {
            print("\t[Error] Invalid Command. Remind user of valid commands.")
            self.notifications.executeError(
                text: "'\(text)' is not a valid command. Please choose from: \(validOptions)",
                voiceCommand: true,
                discardPrior: true
            )
        } else if text.count > 0 {
            // Process visual only if not empty
            print("\tExecute feedback: ", text)
            self.notifications.executeFeedback(
                visualMessage: "\"\(transcription.segments.count > 3 ? "\(transcription.segments.first!.substring.lowercased())...\(transcription.segments.last!.substring.lowercased())" : text.lowercased())\"",
                audioMessage: transcription.formattedString,
                discardPrior: true,
                withHaptics: true
            )
        }
        
        // Capture invalid voice command if we are composing a entry
        if let _ = self.entryManager.currentEntry, self.isListeningForSpeech {
            let date = Date()
            let voiceCommandDatum = VoiceCommandDatum(
                date: date,
                utteredSpeech: transcription.formattedString,
                isValid: false
            )
            
            self.voiceCommandStream.append(voiceCommandDatum)
            
            // Increment State Aggregate Count
            self.state.incrementVoiceCommandCount(timeInterval: date.timeIntervalSince1970)
        }
    }
    
    func broadcastSpeechUpdates(
        transcription: SFTranscription,
        isVoiceCommand: Bool,
        voiceCommandType: String? = nil,
        numWordsBeforeVoiceCommand: Int? = nil,
        isFinalTranscription: Bool
    ) {
        print("===== Speech Recognition Engine: Broadcast Speech Updates =====")
        print("\tTranscription: ", transcription.formattedString)
        print("\tIs Voice Command: ", isVoiceCommand)
        print("\tNum Words Before Voice Command: ", numWordsBeforeVoiceCommand ?? "nil")
        print("\tIs Final Transcription: ", isFinalTranscription)

        var userInfo: [String : Any] = [
            "transcription": transcription,
            "isVoiceCommand": isVoiceCommand,
            "isFinalTranscription": isFinalTranscription
        ]
        if let voiceCommandType = voiceCommandType {
            userInfo["voiceCommandType"] = voiceCommandType
        }
        if let numWordsBeforeVoiceCommand = numWordsBeforeVoiceCommand {
            userInfo["numWordsBeforeVoiceCommand"] = numWordsBeforeVoiceCommand
        }
        NotificationCenter.default.post(
            name: SpeechRecognitionEngine.onSpeechUpdate,
            object: nil,
            userInfo: userInfo
        )
    }
    
    // MARK: - Speech Recognition Delegate
    
    public func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {
        print("===== Speech Recognition Engine: Application is no longer accepting new speech input =====")
        
        // Play sound
        soundEngine.error()
        
        // Give haptic feedback
        hapticEngine.error()
    }
    
    public func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {
        print("===== Speech Recognition Engine: Application cancelled listening ===== ")
        
        // Play sound
        soundEngine.error()
        
        // Give haptic feedback
        hapticEngine.error()
    }
    
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        print("===== Speech Recognition Engine: didFinishSuccessfully =====")
        if let pauseListeningHandler = self.pauseListeningHandler {
            print("\tExecute paused listening handler...")
            self.pauseListeningHandler = nil
            pauseListeningHandler()
        } else if let stopListeningHandler = self.stopListeningHandler {
            print("\tExecute stop listening handler...")
            self.stopListeningHandler = nil
            stopListeningHandler()
        }
    }
    
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        print("===== Speech Recognition Engine: didHypothesizeTranscription ==== ")
        print("\tTranscription: ", transcription.formattedString)
        if self.isListeningForSpeech {
            print("\tSpeech Type: Listening For Speech")
        } else if self.isListeningForCommands {
            print("\tSpeech Type: Listening For Commands")
        } else if self.isListeningForWakePhrase {
            print("\tSpeech Type: Listening For Wake Phrase")
        } else {
            print("\t[Error] Unknown listening state.")
        }
        
        // Sometimes we don't receive a final transcript
        // In these cases our flags remain set affecting subsequent listening
        // We manually reset them in such a scenario after Utils.DEFAULT_RESET_LISTENING_FLAG_DELAY seconds
        //
        // self.lastSpeechRecognizerHypothesizeDate will continue to be reset so this reset will only occur if we've been silent for
        // Utils.DEFAULT_RESET_LISTENING_FLAG_DELAY seconds
        //
        // If we don't do this we commit segments that haven't been replaced with true duratio values
        // which affects timing of every other segment
        if let lastSpeechRecognizerHypothesizeDate = self.lastSpeechRecognizerHypothesizeDate, Utils.DEFAULT_RESET_LISTENING_FLAG_DELAY + lastSpeechRecognizerHypothesizeDate.timeIntervalSinceNow < 0 {
            print("\tReset speech recognition flags and clear entry buffer because final transcript didn't arrive...")
            self.earlyValidVoiceCommandDetection = false
            self.earlyInvalidVoiceCommandDetection = false
            self.earlyBroadcastSpeechRejection = false
            self.entryManager.currentEntry?.clearBuffer()
        }
        
        // Capture durrent date
        self.lastSpeechRecognizerHypothesizeDate = Date()
        
        // Handle Speech Recognized Sound
        if AVAudioSession.isHeadphonesConnected {
            self.speechRecognizedQueue.enqueue(true)
            
            if self.speechRecognizedTimer == nil {
                self.exhaustSpeechRecognizedQueue()
            }
        }
        
        // MARK: - Wake Phrase
        if !self.state.appActivated {
            print("\tSearching for wake phrase...")
            self.searchForWakePhrase(
                transcription: transcription,
                earlyDetection: true
            )
        // MARK: - Listening for Commands
        } else if self.isListeningForCommands && Utils.validSpeechPower(soundIntensityStream: self.soundIntensityStream, backgroundNoise: self.getBackgroundNoise()) {
            print("\tListening for Commands...")
            // Analyze for voice commands
            let (isValidVoiceCommand, invalidType, voiceCommandType, _) = self.isValidVoiceCommand(query: transcription.formattedString.lowercased())

            // Add voice command text to the text view if entry is empty
            if let entry = self.entryManager.currentEntry, !self.isListeningForSpeech && entry.entrySegments.count == 0 {
                entry.handleOnSpeechUpdate(text: transcription.formattedString)
            }
            
            if let voiceCommandType = voiceCommandType, isValidVoiceCommand {
                print("Handle detect valid voice command...")
                self.handleDetectValidVoiceCommand(
                    voiceCommandType: voiceCommandType,
                    transcription: transcription,
                    earlyDetection: true
                )
            } else if let lastStartListeningDate = self.lastStartListeningDate, !isValidVoiceCommand && invalidType != .CLOSE_TO_LAST_VOICE_COMMAND && Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow < 0 {
                print("Handle invalid voice command...")
                self.handleInvalidVoiceCommand(
                    transcription: transcription,
                    earlyDetection: true
                )
            }
        // MARK: - Listening for Speech
        } else if self.isListeningForSpeech &&
                !self.pausedListeningForSpeech &&
                Utils.validSpeechPower(soundIntensityStream: self.soundIntensityStream, backgroundNoise: self.getBackgroundNoise())
        {
            print("\tListening for Speech...")
            if self.isListeningForSpeech && self.state.withPunctuationSuggestions {
                // Initiate Punctuation Suggestion Timers
                self.sentenceSuggestionTimer?.invalidate()
                self.paragraphSuggestionTimer?.invalidate()
            }
            
            // Analyze for voice commands
            let (isValidVoiceCommand, invalidType, voiceCommandType, numWordsBeforeVoiceCommand) = self.isValidVoiceCommand(query: transcription.formattedString.lowercased())
            
            // We place this before the voice command detection infrastructure
            // to make sure that we've processed voice commands into entry
            // before acting on them.
            //
            // e.g. "open selection" requires voice command words be tagged
            // for it to grab the right word to select
            if let lastStartedListeningTimestamp = self.lastStartedListeningTimestamp,
               let lastStartListeningDate = self.lastStartListeningDate,
               invalidType != .CLOSE_TO_LAST_VOICE_COMMAND &&
               Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow < 0 &&
                Date().timeIntervalSince1970 - lastStartedListeningTimestamp >  Utils.DEFAULT_START_LISTENING_DELAY
            { // Apple-related bug
                print("\tBroadcast speech updates...")
                self.broadcastSpeechUpdates(
                    transcription: transcription,
                    isVoiceCommand: isValidVoiceCommand,
                    voiceCommandType: voiceCommandType,
                    numWordsBeforeVoiceCommand: numWordsBeforeVoiceCommand,
                    isFinalTranscription: false
                )
            } else {
                self.earlyBroadcastSpeechRejection = true
                print("\t[Error] Speech not broadcast:")
                print("\tInvalid Type: ", invalidType ?? "nil")
                print("\tLast Start Listening Timestamp: ", self.lastStartedListeningTimestamp ?? "nil")
                if let lastStartedListeningTimestamp = self.lastStartedListeningTimestamp {
                    print(
                        "\tNow - Last Started Listening Timestamp >  Default Start Listening Delay ",
                        Date().timeIntervalSince1970 - lastStartedListeningTimestamp >  Utils.DEFAULT_START_LISTENING_DELAY,
                        lastStartedListeningTimestamp,
                        Date().timeIntervalSince1970 - lastStartedListeningTimestamp,
                        Utils.DEFAULT_START_LISTENING_DELAY
                    )
                }
                if let lastStartListeningDate = self.lastStartListeningDate {
                    print(
                        "\tLast Start Listening Date + Default Start Listening Delay < 0: ",
                        Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow < 0,
                        Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow
                    )
                }
            }

            // We encountered a voice command while listening for speech
            // Add to voice command stream
            if let voiceCommandType = voiceCommandType, isValidVoiceCommand {
                print("Handle detect valid voice command...")
                self.handleDetectValidVoiceCommand(
                    voiceCommandType: voiceCommandType,
                    transcription: transcription,
                    earlyDetection: true
                )
            } else {
                print("\t[Error] Did not handle valid voice command:")
                print("\tIs Valid Voice Command: ", isValidVoiceCommand)
                print("\tEarly Valid Voice Command Detection: ", self.earlyValidVoiceCommandDetection)
            }
        }
    }
    
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition result: SFSpeechRecognitionResult) {
        print("===== Speech Recognition Engine: didFinishRecognition ====")
        print("\tTranscription: ", result.bestTranscription.formattedString)
        
        // MARK: - Wake Phrase
        if !self.state.appActivated && !self.earlyValidVoiceCommandDetection {
            print("\tSearching for wake phrase...")
            self.searchForWakePhrase(transcription: result.bestTranscription)
        // MARK: - Edge Case and Voice Commands
        } else if (
            self.isListeningForCommands
        ) || (
            self.isListeningForSpeech &&
            self.pausedListeningForSpeech &&
            !self.isListeningForCommands &&
            self.entryManager.currentEntry?.entryBuffer.count ?? 0 > 0 &&
            self.entryManager.currentEntry?.recordStartDate == nil
        ) {
            print("\tHandling speech edge case and voice command speech")
            // sometimes the voice commands that initiate the entry will be sent to be committed erroneously
            // we catch them by identifying that self.recordStartDate == nil, for which they would be if
            // they were processed before entry properly started

            // Clear buffer
            if let entry = self.entryManager.currentEntry, entry.entrySegments.count == 0 {
                // clear buffer
                entry.clearBuffer()
                // clear screen
                entry.handleOnSpeechUpdate(text: "")
            }
            
            // Analyze for voice commands
            let (isValidVoiceCommand, invalidType, voiceCommandType, _) = self.isValidVoiceCommand(query: result.bestTranscription.formattedString.lowercased())
            
            if let voiceCommandType = voiceCommandType,
               isValidVoiceCommand &&
                !self.earlyValidVoiceCommandDetection {
                print("Handle detect valid voice command...")
                self.handleDetectValidVoiceCommand(
                    voiceCommandType: voiceCommandType,
                    transcription: result.bestTranscription
                )
            } else if let lastStartListeningDate = self.lastStartListeningDate,
                !self.earlyInvalidVoiceCommandDetection &&
                !isValidVoiceCommand &&
                invalidType != .CLOSE_TO_LAST_VOICE_COMMAND &&
                Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow < 0 {
                print("Handle invalid voice command...")
                // We don't want to repeat an error twice, hence why we only let those that weren't caught early through
                self.handleInvalidVoiceCommand(transcription: result.bestTranscription)
            }
        // MARK: - Listening for Speech (Unhandled or handled by didHypothesizeTranscription)
        } else if
            (
                self.isListeningForSpeech ||
                (self.voiceCommandStream.last != nil && self.voiceCommandStream.last!.type == "stop entry")
            ) &&
            !self.isListeningForCommands
        {
            print("\tListening for speech (handled and unhandled by didHypothesizeTranscription)...")
            // Analyze for voice commands
            let (isValidVoiceCommand, invalidType, voiceCommandType, numWordsBeforeVoiceCommand) = self.isValidVoiceCommand(query: result.bestTranscription.formattedString.lowercased())
            
            // We place this before the voice command detection infrastructure
            // to make sure that we've processed voice commands into entry
            // before acting on them.
            //
            // e.g. "open selection" requires voice command words be tagged
            // for it to grab the right word to select
            if let lastStartListeningDate = self.lastStartListeningDate,
               let lastStartedListeningTimestamp = self.lastStartedListeningTimestamp,
               !self.earlyBroadcastSpeechRejection &&
                Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow < 0 &&
                 Date().timeIntervalSince1970 - lastStartedListeningTimestamp >  Utils.DEFAULT_START_LISTENING_DELAY
            { // Apple-related bug
                print("\tBroadcast speech updates...")
                self.broadcastSpeechUpdates(
                    transcription: result.bestTranscription,
                    isVoiceCommand: isValidVoiceCommand,
                    voiceCommandType: voiceCommandType,
                    numWordsBeforeVoiceCommand: numWordsBeforeVoiceCommand,
                    isFinalTranscription: true
                )
            } else {
                print("\t[Error] Speech not broadcast:")
                print("\tLast Start Listening Timestamp: ", self.lastStartedListeningTimestamp ?? "nil")
                if let lastStartedListeningTimestamp = self.lastStartedListeningTimestamp {
                    print(
                        "\tNow - Last Started Listening Timestamp >  Default Start Listening Delay ",
                        Date().timeIntervalSince1970 - lastStartedListeningTimestamp >  Utils.DEFAULT_START_LISTENING_DELAY,
                        lastStartedListeningTimestamp,
                        Date().timeIntervalSince1970 - lastStartedListeningTimestamp,
                        Utils.DEFAULT_START_LISTENING_DELAY
                    )
                }
                if let lastStartListeningDate = self.lastStartListeningDate {
                    print(
                        "\tLast Start Listening Date + Default Start Listening Delay < 0: ",
                        Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow < 0,
                        Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow
                    )
                }
                print("\tEarly Broadcast Speech Rejection: ", self.earlyBroadcastSpeechRejection)
            }

            if let voiceCommandType = voiceCommandType,
               isValidVoiceCommand &&
                !self.earlyValidVoiceCommandDetection {
                print("Handle detect valid voice command...")
                self.handleDetectValidVoiceCommand(
                    voiceCommandType: voiceCommandType,
                    transcription: result.bestTranscription
                )
            } else {
                print("\t[Error] Did not handle valid voice command:")
                print("\tIs Valid Voice Command: ", isValidVoiceCommand)
                print("\tEarly Valid Voice Command Detection: ", self.earlyValidVoiceCommandDetection)
            }
            
            if let lastSpeechRecognizerHypothesizeDate = self.lastSpeechRecognizerHypothesizeDate,
               let lastStartListeningDate = self.lastStartListeningDate,
                let lastStartedListeningTimestamp = self.lastStartedListeningTimestamp,
                AVAudioSession.isHeadphonesConnected &&
               self.isListeningForSpeech &&
                self.state.withPunctuationSuggestions &&
                !self.selectionCursor.hasSelection &&
                !self.earlyBroadcastSpeechRejection &&
                invalidType != .CLOSE_TO_LAST_VOICE_COMMAND &&
                 Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow < 0 &&
                  Date().timeIntervalSince1970 - lastStartedListeningTimestamp >  Utils.DEFAULT_START_LISTENING_DELAY
            {
                print("\tSetting punctuation suggestion timers...")
                // Initiate Punctuation Suggestion Timers
                print("\tSentence Suggestion Timer: \(Utils.NEW_SENTENCE_PAUSE_DURATION) s \(lastSpeechRecognizerHypothesizeDate.timeIntervalSinceNow) s")
                self.sentenceSuggestionTimer = Timer.scheduledTimer(withTimeInterval: max(0, Utils.NEW_SENTENCE_PAUSE_DURATION + lastSpeechRecognizerHypothesizeDate.timeIntervalSinceNow), repeats: false) { timer in
                    soundEngine.sentenceSuggestion()
                }
                print("\tParagraph Suggestion Timer: \(Utils.NEW_PARAGRAPH_PAUSE_DURATION) s \(lastSpeechRecognizerHypothesizeDate.timeIntervalSinceNow) s")
                self.paragraphSuggestionTimer = Timer.scheduledTimer(withTimeInterval: max(0, Utils.NEW_PARAGRAPH_PAUSE_DURATION + lastSpeechRecognizerHypothesizeDate.timeIntervalSinceNow), repeats: false) { timer in
                    soundEngine.paragraphSuggestion()
                }
            }
            // MARK: - Listening for Commands (Handled by didHypothesizeTranscription, but updating it)
        } else if self.isListeningForCommands {
            print("\tListening for commmands (handled by didHypothesizeTranscription)...")
            // Analyze for voice commands
            let (isValidVoiceCommand, invalidType, voiceCommandType, numWordsBeforeVoiceCommand) = self.isValidVoiceCommand(query: result.bestTranscription.formattedString.lowercased())
            
            // We place this before the voice command detection infrastructure
            // to make sure that we've processed voice commands into entry
            // before acting on them.
            //
            // e.g. "open selection" requires voice command words be tagged
            // for it to grab the right word to select
            if let lastStartListeningDate = self.lastStartListeningDate,
               let lastStartedListeningTimestamp = self.lastStartedListeningTimestamp,
               !self.earlyBroadcastSpeechRejection &&
                Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow < 0 &&
                 Date().timeIntervalSince1970 - lastStartedListeningTimestamp >  Utils.DEFAULT_START_LISTENING_DELAY
            { // Apple-related bug
                print("\tBroadcast speech updates...")
                self.broadcastSpeechUpdates(
                    transcription: result.bestTranscription,
                    isVoiceCommand: isValidVoiceCommand,
                    voiceCommandType: voiceCommandType,
                    numWordsBeforeVoiceCommand: numWordsBeforeVoiceCommand,
                    isFinalTranscription: true
                )
            } else {
                print("\t[Error] Speech not broadcast:")
                print("\tLast Start Listening Timestamp: ", self.lastStartedListeningTimestamp ?? "nil")
                if let lastStartedListeningTimestamp = self.lastStartedListeningTimestamp {
                    print(
                        "\tNow - Last Started Listening Timestamp >  Default Start Listening Delay ",
                        Date().timeIntervalSince1970 - lastStartedListeningTimestamp >  Utils.DEFAULT_START_LISTENING_DELAY,
                        lastStartedListeningTimestamp,
                        Date().timeIntervalSince1970 - lastStartedListeningTimestamp,
                        Utils.DEFAULT_START_LISTENING_DELAY
                    )
                }
                if let lastStartListeningDate = self.lastStartListeningDate {
                    print(
                        "\tLast Start Listening Date + Default Start Listening Delay < 0: ",
                        Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow < 0,
                        Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow
                    )
                }
                print("\tEarly Broadcast Speech Rejection: ", self.earlyBroadcastSpeechRejection)
            }

            if let voiceCommandType = voiceCommandType, isValidVoiceCommand && !self.earlyValidVoiceCommandDetection {
                print("Handle detect valid voice command...")
                self.handleDetectValidVoiceCommand(
                    voiceCommandType: voiceCommandType,
                    transcription: result.bestTranscription
                )
            } else if let lastStartListeningDate = self.lastStartListeningDate, !self.earlyInvalidVoiceCommandDetection && !isValidVoiceCommand && invalidType != .CLOSE_TO_LAST_VOICE_COMMAND && Utils.DEFAULT_START_LISTENING_DELAY + lastStartListeningDate.timeIntervalSinceNow < 0 {
                print("Handle invalid voice command...")
                // We don't want to repeat an error twice, hence why we only let those that weren't caught early through
                self.handleInvalidVoiceCommand(transcription: result.bestTranscription)
            }
        // MARK: - Catch All
        } else {
            print("\tCatch all...")
            // execute listen update handler
            if let entry = self.entryManager.currentEntry, !self.isListeningForSpeech && entry.entrySegments.count == 0 {
                // We are not yet starting a entry and have no entrySegments. We should remove text on screen
                entry.handleOnSpeechUpdate(text: "")
            }
        }
        
        // Turns off early voice commmand detection flag
        self.earlyValidVoiceCommandDetection = false
        self.earlyInvalidVoiceCommandDetection = false
        self.earlyBroadcastSpeechRejection = false
        self.lastSpeechRecognizerHypothesizeDate = nil
    }
    
    public func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        print("===== Speech Recognition Engine: System has detected first incident of speech input =====")
    }
}

// Transcription: https://developer.apple.com/documentation/speech/sftranscription
// Segment: https://developer.apple.com/documentation/speech/sftranscriptionsegment

// Behavior
// App should continue to record when the phone is locked.

// ===== SpeechRecognition =====

// ** There are throttling limits **
// Per device per day
// Per app per day (global limitations for all users of your app) - 1000 calls an hour across apps on a single device = 4 calls every 15 seconds => very generous
// Error Code: 203
// https://developer.apple.com/library/archive/qa/qa1951/_index.html
// One minute limitation for a single utterance (from start to end of a recognition task)

// ===== On Device Recognition =====
// There is no continuous learning like you have on the Cloud. This can lead to less accuracy on the device. Moreover, the language support is limited to about 10 languages currently.
// lets you do speech recognition for an unlimited amount of time

// iOS 13 SFSpeechRecognizer is smart enough to recognize punctuations in your speech.
// how many users have iOS 13?

// ===== Pitch Recognition =====
// We use Beethoven to conduct pitch recognition: https://github.com/vadymmarkov/Beethoven
// Theory: https://medium.com/@neurodatalab/pitch-tracking-or-how-to-estimate-the-fundamental-frequency-in-speech-on-the-examples-of-praat-fe0ca50f61fd

// Adult Male Vocal Range: Bass = E2 - F4 , Baritone = G2 - Ab4, Tenor = Bb2 - C5
// Adult Female Vocal Range: Alto = F3 - A5, Soprano = A3 - C6
// Source: https://www.quora.com/What-is-the-average-vocal-range-for-an-adult-male-and-for-an-adult-female#:~:text=Adult%20male%20professional%20singers%20may%20have%20up%20to%20three%20octave,and%20Contraltos%20may%20have%20less.
// Speaking: https://en.wikipedia.org/wiki/Voice_frequency
// Vocal Range: https://en.wikipedia.org/wiki/Vocal_range
// Male: [85, 180]
// Female: [165, 255]
