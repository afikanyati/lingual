//
//  DetailViewController.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/24/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Speech
import AVFoundation
import NaturalLanguage

class DetailViewController: UIViewController, SegueProtocol {
    // MARK: - Notifications
    static let onDidLoad = Notification.Name(Notifications.onDetailViewControllerDidLoad.rawValue)
    static let onWillDisappear = Notification.Name(Notifications.onDetailViewControllerWillDisappear.rawValue)
    static let onChangedPlayerRate = Notification.Name(Notifications.onChangedPlayerRate.rawValue)
    static let onChangedEchoRate = Notification.Name(Notifications.onChangedEchoRate.rawValue)

    // MARK: - Outlets and Views
    
    // ===== Menu Bar =====
    @IBOutlet weak var startEntryButton: UIView?
    @IBOutlet weak var editEntryButton: UIView?
    @IBOutlet weak var resumeEntryButton: UIView?
    @IBOutlet weak var stopListeningEntryButton: UIView?
    @IBOutlet weak var playButton: UIView?
    @IBOutlet weak var stopPlayingButton: UIView?
    @IBOutlet weak var echoButton: UIView?
    @IBOutlet weak var stopEchoButton: UIView?
    @IBOutlet weak var exportButton: UIView?
    @IBOutlet weak var walkButton: UIView?
    
    // ===== Command Bar =====
    
    // Resting Buttons
    @IBOutlet weak var runButton: UIView?
    @IBOutlet weak var pauseButton: UIView?
    
    // Conditional Buttons
    @IBOutlet weak var moveHereButton: UIView?
    @IBOutlet weak var inspectClipboardButton: UIView?
    @IBOutlet weak var playCommitButton: UIView?
    @IBOutlet weak var pauseEchoButton: UIView?
    @IBOutlet weak var skipBackwardButton: UIView?
    @IBOutlet weak var skipForwardButton: UIView?
    @IBOutlet weak var playbackRateButton: UIView?
    @IBOutlet weak var echoRateButton: UIView?
    
    // Selection Buttons
    @IBOutlet weak var increaseRateButton: UIView?
    @IBOutlet weak var decreaseRateButton: UIView?
    @IBOutlet weak var deleteSelectionButton: UIView?
    @IBOutlet weak var updateSelectionButton: UIView?
    @IBOutlet weak var cancelUpdateSelectionButton: UIView?
    @IBOutlet weak var copySelectionButton: UIView?
    @IBOutlet weak var cutSelectionButton: UIView?
    
    // Text View
    @IBOutlet weak var textView: UITextView?
    @IBOutlet weak var textViewPositionTop: NSLayoutConstraint?
    @IBOutlet weak var textViewPositionBottom: NSLayoutConstraint?
    
    // Indicators
    @IBOutlet weak var soundIntensityIndicator: UIView?
    @IBOutlet weak var soundIntensityIndicatorHeight: NSLayoutConstraint?
    @IBOutlet weak var soundIntensityIndicatorPositionBottom: NSLayoutConstraint?
    @IBOutlet weak var pitchLabel: UILabel?
    @IBOutlet weak var transformationLabel: UILabel?
    
    // Scroll View
    @IBOutlet weak var scrollView: UIScrollView?
    @IBOutlet weak var scrollViewPositionTop: NSLayoutConstraint?

    // Command Bar
    @IBOutlet weak var commandBar: UIStackView?
    @IBOutlet weak var commandBarPositionTop: NSLayoutConstraint?
    
    // Menu Bar
    @IBOutlet weak var menuBar: UIStackView?
    @IBOutlet weak var menuBarPositionBottom: NSLayoutConstraint?
    
    // Slider
    @IBOutlet weak var sliderView: UIView?
    @IBOutlet weak var sliderViewPositionTop: NSLayoutConstraint?
    @IBOutlet weak var slider: UISlider?
    @IBOutlet weak var exitSliderButton: UIView?
    
    // Walk
    @IBOutlet weak var walkNextWordButton: UIView?
    @IBOutlet weak var walkPreviousWordButton: UIView?
    @IBOutlet weak var exitWalkRunButton: UIView?
    
    // Run
    @IBOutlet weak var pauseRunButton: UIView?
    
    // Undo/Redo
    @IBOutlet weak var undoButton: UIView?
    @IBOutlet weak var redoButton: UIView?
    
    // Cursor
    var cursorView: UIView?
    
    // MARK: - App Modules
    var state: StateManager!
    var speechRecognition: SpeechRecognitionEngine!
    var speechSynthesis: SpeechSynthesisEngine!
    var pitchRecognition: PitchRecognitionEngine!
    var notifications: NotificationEngine!
    var speechPlayer: SpeechPlayerEngine!
    var selectionCursor: SelectionCursor!
    var entryManager: EntryManager!
    var entryListManager: EntryListManager!
    var uiManager: UIManager!
    var voiceCommandEngine: VoiceCommandEngine!
    
    // MARK: - ViewController References
    weak var viewController: ViewController?
    weak var entryTableViewController: EntryTableViewController?
    weak var dictionaryViewController: DictionaryViewController?
    
    // MARK: - General Properties
    var sliderIsVisible = false
    var sliderType: SliderType?
    var cursorBlinkTimer: Timer?

    // MARK: - Cached Properties
    var cachedTextViewSelectedRange: NSRange?
    
    // MARK: - Lifecycle Methods
    
    override func viewWillAppear(_ animated: Bool) {
        print("===== Detail View Controller: View Will Appear =====")
        super.viewWillAppear(animated)
        
        self.prepareNavbar()
        self.configureNotificationObservers()
        
        // Prevent large title
        let navigationController = Utils.getNavigationController()
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationController?.navigationItem.largeTitleDisplayMode = .never
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Asssign as "Shake to undo" handler
        becomeFirstResponder()
    }
    
    // For shake to undo.
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override func viewDidLoad() {
        print("===== Detail View Controller: View Did Load =====")
        super.viewDidLoad()
        
        // Prepare UI
        self.prepareMenuBar()
        self.prepareCommandBar()
        self.prepareSlider()
        self.prepareTextView()
        self.prepareGeneralView()
        self.transformationLabel?.isHidden = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshView()
        }
    
        // Show cursor
        self.setCursorVisibility(as: self.speechRecognition.isListeningForSpeech)
        
        // add observer to hasSelection
        self.selectionCursor.addObserver(
            self,
            forKeyPath: "hasSelection",
            options: [.old, .new],
            context: nil
        )
        
        self.textView?.addObserver(
            self,
            forKeyPath: "selectedTextRange",
            options: [.old, .new],
            context: nil
        )
        
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(self.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        self.textView?.addGestureRecognizer(singleTap)
        
        // Notify observers of loading
        NotificationCenter.default.post(
            name: DetailViewController.onDidLoad,
            object: nil,
            userInfo: [:]
        )
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        print("===== Detail View Controller: View Will Disappear =====")
        super.viewWillDisappear(animated)

        // remove observer from hasSelection
        self.selectionCursor.removeObserver(
            self,
            forKeyPath: "hasSelection",
            context: nil
        )
        
        self.textView?.removeObserver(
            self,
            forKeyPath: "selectedTextRange",
            context: nil
        )
        
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        // Notify observers of disappearing
        NotificationCenter.default.post(
            name: DetailViewController.onWillDisappear,
            object: nil,
            userInfo: [:]
        )
    }
    
    // MARK: - Segues
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let identifier = segueIdentifierCase(for: segue) else {
            assertionFailure(">>>>> [Error] Could not map Segue Identifier - \(String(describing: segue.identifier)) - to Segue Case >>>>>")
            return
        }

        switch identifier {
        case .moveFromDetailToEntryTable:
            print(">>>>> Segue from DetailViewController to EntryTableViewController >>>>>")
            if let entryTableViewController = segue.destination as? EntryTableViewController {
                entryTableViewController.state = self.state
                entryTableViewController.speechRecognition = self.speechRecognition
                entryTableViewController.speechSynthesis = self.speechSynthesis
                entryTableViewController.pitchRecognition = self.pitchRecognition
                entryTableViewController.notifications = self.notifications
                entryTableViewController.speechPlayer = self.speechPlayer
                entryTableViewController.selectionCursor = self.selectionCursor
                entryTableViewController.entryManager = self.entryManager
                entryTableViewController.entryListManager = self.entryListManager
                entryTableViewController.uiManager = self.uiManager
                entryTableViewController.voiceCommandEngine = self.voiceCommandEngine
            }
            self.speechRecognition.activateListeningIndicator(
                withRecording: self.speechRecognition.isListeningForSpeech,
                withStopListeningButton: !self.speechRecognition.isListeningForSpeech
            )
            
            // Remove textView and cursor from selectionCursor
            self.selectionCursor.setTextView()
            self.selectionCursor.setCursorView()
            // Unselect current entry
            self.entryManager.setCurrentEntry()
        case .moveFromSleepToEntryTable:
            print (">>>>> [Invalid Segue within DetailViewController] from ViewControlller to EntryTableViewController >>>>>")
        case .moveFromSleepToDetail:
            print (">>>>> [Invalid Segue within DetailViewController] from ViewControlller to DetailViewController >>>>>")
        case .moveFromEntryTableToDetail:
            print (">>>>> [Invalid Segue within DetailViewController] from EntryTableViewControlller to DetailViewController >>>>>")
        case .moveFromEntryTableToSleep:
            print (">>>>> [Invalid Segue within DetailViewController] from EntryTableViewControlller to ViewController >>>>>")
        case .moveFromEntryTableToDictionary:
            print (">>>>> [Invalid Segue within DetailViewController] from EntryTableViewControlller to DictionaryViewController >>>>>")
        case .moveFromDictionaryToEntryTable:
            print (">>>>> [Invalid Segue within DetailViewController] from DictionaryViewControlller to EntryTableViewController >>>>>")
        case .noIdentifier:
            print (">>>>> [Error] No Segue Identifier in ViewController >>>>>")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
        // App
        notificationCenter.addObserver(
            self,
            selector: #selector(self.appMovedToBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // Observe ViewController
        notificationCenter.addObserver(
            self,
            selector: #selector(onViewDidLoad(notification:)),
            name: ViewController.onDidLoad,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onViewWillDisappear(notification:)),
            name: ViewController.onWillDisappear,
            object: nil
        )
        
        // Observe EntryTableView
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryTableViewDidLoad(notification:)),
            name: EntryTableViewController.onDidLoad,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryTableViewWillDisappear(notification:)),
            name: EntryTableViewController.onWillDisappear,
            object: nil
        )
        
        // Observe DictionaryView
        notificationCenter.addObserver(
            self,
            selector: #selector(onDictionaryViewDidLoad(notification:)),
            name: DictionaryViewController.onDidLoad,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onDictionaryViewWillDisappear(notification:)),
            name: DictionaryViewController.onWillDisappear,
            object: nil
        )
        
        // Observe SpeechRecognitionEngine
        notificationCenter.addObserver(
            self,
            selector: #selector(onPitchUpdate(notification:)),
            name: PitchRecognitionEngine.onPitchUpdate,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onPowerUpdate(notification:)),
            name: SpeechRecognitionEngine.onPowerUpdate,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStartedListeningForWakePhrase(notification:)),
            name: SpeechRecognitionEngine.onStartedListeningForWakePhrase,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStartedListeningForCommands(notification:)),
            name: SpeechRecognitionEngine.onStartedListeningForCommands,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStartedListeningForSpeech(notification:)),
            name: SpeechRecognitionEngine.onStartedListeningForSpeech,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onPausedListening(notification:)),
            name: SpeechRecognitionEngine.onPausedListeningForCommands,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onPausedListening(notification:)),
            name: SpeechRecognitionEngine.onPausedListeningForSpeech,
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
            selector: #selector(onStoppedListening(notification:)),
            name: SpeechRecognitionEngine.onStoppedListeningForCommands,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStoppedListeningForSpeech(notification:)),
            name: SpeechRecognitionEngine.onStoppedListeningForSpeech,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onSpeechUpdate(notification:)),
            name: SpeechRecognitionEngine.onSpeechUpdate,
            object: nil
        )
        
        // Observe NotificationEngine
        notificationCenter.addObserver(
            self,
            selector: #selector(onStartTimedNotification(notification:)),
            name: NotificationEngine.onStartTimedNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStartIndefiniteNotification(notification:)),
            name: NotificationEngine.onStartIndefiniteNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStopNotification(notification:)),
            name: NotificationEngine.onStopNotification,
            object: nil
        )
        
        // Speech Player
        notificationCenter.addObserver(
            self,
            selector: #selector(onSpeechStartPlaying(notification:)),
            name: SpeechPlayerEngine.onStartedPlaying,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onSpeechBoundaryCrossed(notification:)),
            name: SpeechPlayerEngine.onBoundaryCrossed,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onSpeechSecondElapsed(notification:)),
            name: SpeechPlayerEngine.onSecondElapsed,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onSpeechStopPlaying(notification:)),
            name: SpeechPlayerEngine.onStoppedPlaying,
            object: nil
        )
        
        // SpeechSynthesisEngine
        notificationCenter.addObserver(
            self,
            selector: #selector(onRequestToUpdateView(notification:)),
            name: SpeechSynthesisEngine.onRequestToUpdateView,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onEchoUpdate(notification:)),
            name: SpeechSynthesisEngine.onEchoUpdate,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onEchoFinish(notification:)),
            name: SpeechSynthesisEngine.onEchoFinish,
            object: nil
        )
        
        // Entry
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryListenUpdate(notification:)),
            name: Entry.onEntryListenUpdate,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryComplete(notification:)),
            name: Entry.onEntryComplete,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryListenStop(notification:)),
            name: Entry.onEntryListenStop,
            object: nil
        )
        
        // EntryManager
        notificationCenter.addObserver(
            self,
            selector: #selector(onExecuteEntryAction(notification:)),
            name: EntryManager.onExecuteEntryAction,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryAudioExported(notification:)),
            name: EntryManager.onEntryAudioExported,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onEntryDeleted(notification:)),
            name: EntryManager.onEntryDeleted,
            object: nil
        )
        
        // SelectionCursor
        notificationCenter.addObserver(
            self,
            selector: #selector(onClipboardChange(notification:)),
            name: SelectionCursor.onClipboardChange,
            object: nil
        )
        
        // StateManager
        notificationCenter.addObserver(
            self,
            selector: #selector(onUndoManagerChange(notification:)),
            name: EntryManager.onUndoManagerChange,
            object: nil
        )
    }
    
    @objc func onViewDidLoad(notification: Notification) {
        print("===== Detail View Controller: On View Did Load =====")
        self.viewController = storyboard?.instantiateViewController(withIdentifier: "ViewController") as? ViewController
    }
    
    @objc func onEntryTableViewDidLoad(notification: Notification) {
        print("===== Detail View Controller: On Entry Table View Did Load =====")
        self.entryTableViewController = storyboard?.instantiateViewController(withIdentifier: "EntryTableViewController") as? EntryTableViewController
    }
    
    @objc func onDictionaryViewDidLoad(notification: Notification) {
        print("===== Detail View Controller: On Dictionary View Did Load =====")
        self.dictionaryViewController = storyboard?.instantiateViewController(withIdentifier: "DictionaryViewController") as? DictionaryViewController
    }
    
    @objc func onViewWillDisappear(notification: Notification) {
        print("===== Detail View Controller: On View Will Disappear =====")
        self.viewController = nil
    }
    
    @objc func onEntryTableViewWillDisappear(notification: Notification) {
        print("===== Detail View Controller: On Entry Table View Will Disappear =====")
        self.entryTableViewController = nil
    }
    
    @objc func onDictionaryViewWillDisappear(notification: Notification) {
        print("===== Detail View Controller: On Dictionary View Will Disappear =====")
        self.dictionaryViewController = nil
    }
    
    @objc func appMovedToBackground() {
        print("===== Detail View Controller: App Moved to Background =====")
        DispatchQueue.main.async { [weak self] in
            // keep recording outside of app if entry started
            if !self!.speechRecognition.isListeningForSpeech {
                self?.performSegue(withIdentifier: Segues.moveFromDetailToEntryTable.rawValue, sender: nil)
            }
            
            self?.setCursorVisibility(as: false)
        }
    }
    
    @objc func onPitchUpdate(notification: Notification) {
        // print("===== Detail View Controller: On Pitch Update =====")
        DispatchQueue.main.async { [weak self] in
            if let speechPlayer = self?.speechPlayer, let pitchLabel = self?.pitchLabel {
                Utils.onPitchUpdate(
                    notification: notification,
                    speechPlayer: speechPlayer,
                    pitchLabel: pitchLabel
                )
            }
        }
    }
    
    @objc func onPowerUpdate(notification: Notification) {
        // print("===== Detail View Controller: On Power Update =====")
        DispatchQueue.main.async { [weak self] in
            if let view = self?.view, let soundIntensityIndicatorHeight = self?.soundIntensityIndicatorHeight {
                Utils.onPowerUpdate(
                    notification: notification,
                    view: view,
                    soundIntensityIndicatorHeight: soundIntensityIndicatorHeight
                )
            }
        }
    }
    
    @objc func onEchoUpdate(notification: Notification) {
        print("===== Detail View Controller: On Echo Update =====")

        DispatchQueue.main.async { [weak self] in
            let highlightRange = notification.userInfo!["highlightRange"] as! NSRange
            if let entry = self?.entryManager.currentEntry {
                self?.updateUIText(text: entry.getText(), highlightRange: highlightRange, transformations: entry.transformations)
            }
            
            self?.refreshView()
        }
    }
    
    @objc func onEchoFinish(notification: Notification) {
        print("===== Detail View Controller: On Echo Finish =====")
        
        DispatchQueue.main.async { [weak self] in
            if let entry = self?.entryManager.currentEntry {
                self?.updateUIText(text: entry.getText(), transformations: entry.transformations)
            }

            self?.refreshView()
        }
    }
    
    @objc func onRequestToUpdateView(notification: Notification) {
        print("===== Detail View Controller: On Request To Update View =====")
        
        DispatchQueue.main.async { [weak self] in
            if let entry = self?.entryManager.currentEntry {
                self?.updateUIText(text: entry.getText(), transformations: entry.transformations)
            }

            self?.refreshView()
        }
    }
    
    @objc func onStartedListeningForWakePhrase(notification: Notification) {
        print("===== View Controller: On Started Listening For Wake Phrase =====")
        Utils.onStartedListeningForWakePhrase(
            withBackToEntriesButton: true,
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStartedListeningForCommands(notification: Notification) {
        print("===== View Controller: On Started Listening For Commands =====")
        Utils.onStartedListeningForCommands(
            withBackToEntriesButton: true,
            notification: notification,
            speechRecognition: self.speechRecognition
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.refreshView()
        }
    }
    
    @objc func onStartedListeningForSpeech(notification: Notification) {
        print("===== Detail View Controller: On Started Listening For Speech =====")
 
        DispatchQueue.main.async { [weak self] in
            let navigationController = Utils.getNavigationController()
            if !self!.speechRecognition.isListeningForSpeech {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [self!.getDeleteEntryButton()]
            } else {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [] // remove delete button when listening for speech
            }
            if let _ = self?.selectionCursor.clipboard {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems?.insert(self!.getPasteClipboardButton(), at: 0)
            }
        }
        
        Utils.onStartedListeningForSpeech(
            withBackToEntriesButton: true,
            delayStartRecording: 3,
            notification: notification,
            speechRecognition: self.speechRecognition,
            selectionCursor: self.selectionCursor
        )
        
        // Show cursor
        self.setCursorVisibility(as: true)
        
        DispatchQueue.main.async { [weak self] in
            self?.refreshView()
        }
    }
    
    @objc func onPausedListening(notification: Notification) {
        print("===== Detail View Controller: On Paused Listening =====")
        Utils.onPausedListening(
            withBackToEntriesButton: true,
            notification: notification,
            speechRecognition: self.speechRecognition
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.refreshView()
        }
    }
    
    @objc func onStoppedListeningForSpeech(notification: Notification) {
        print("===== Detail View Controller: On Stopped Listening For Speech =====")
        Utils.onStoppedListening(
            withBackToEntriesButton: true,
            notification: notification,
            speechRecognition: self.speechRecognition,
            soundIntensityIndicatorHeight: self.soundIntensityIndicatorHeight,
            pitchLabel: self.pitchLabel
        ) { [weak self] in
            // Hide cursor
            self?.setCursorVisibility(as: false)
            self?.removeCursor()
            self?.refreshView()
        }
    }
    
    @objc func onStoppedListening(notification: Notification) {
        print("===== Detail View Controller: On Stopped Listening =====")
        Utils.onStoppedListening(
            withBackToEntriesButton: true,
            notification: notification,
            speechRecognition: self.speechRecognition,
            soundIntensityIndicatorHeight: self.soundIntensityIndicatorHeight,
            pitchLabel: self.pitchLabel
        ) { [weak self] in
            self?.refreshView()
        }
    }
    
    @objc func onEntryListenUpdate(notification: Notification) {
        print("===== Detail View Controller: On Entry Listen Update =====")
        DispatchQueue.main.async { [weak self] in
            let text = notification.userInfo!["text"] as! String
            print("Text:\n'\(text)'")
            let highlightRange = notification.userInfo!["highlightRange"] as! NSRange?
            let bufferRange = notification.userInfo!["bufferRange"] as! NSRange?
            let transformations = notification.userInfo!["transformations"] as! [EntryTransformation]
            self?.updateUIText(text: text, highlightRange: highlightRange, bufferRange: bufferRange, transformations: transformations)
            self?.refreshView()
        }
    }
    
    @objc func onEntryListenStop(notification: Notification) {
        print("===== Detail View Controller: On Entry Listen Stop =====")
        DispatchQueue.main.async { [weak self] in
            if let entryManager = self?.entryManager, let entry = entryManager.currentEntry {
                let text = notification.userInfo!["text"] as! String
                self?.updateUIText(text: text, transformations: entry.transformations)
            }
        }
        
        Utils.onEntryStop(
            notification: notification,
            speechRecognition: self.speechRecognition
        ) { [weak self] in
            self?.refreshView()
            self?.soundIntensityIndicatorHeight?.constant = 0
        }
    }
    
    @objc func onStartTimedNotification(notification: Notification) {
        print("===== Detail View Controller: On Start Timed Notification =====")
        Utils.onStartTimedNotification(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStopNotification(notification: Notification) {
        print("===== Detail View Controller: On Stop Notification =====")
        Utils.onStopNotification(
            notification: notification,
            entry: self.entryManager.currentEntry,
            speechRecognition: self.speechRecognition,
            selectionCursor: self.selectionCursor
        )
    }
    
    @objc func onStartIndefiniteNotification(notification: Notification) {
        print("===== Detail View Controller: On Start Indefinite Notification =====")
        Utils.onStartIndefiniteNotification(
            notification: notification,
            state: self.state,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onEntryComplete(notification: Notification) {
        print("===== Detail View Controller: On Entry Complete =====")
        DispatchQueue.main.async { [weak self] in
            let navigationController = Utils.getNavigationController()
            if !self!.speechRecognition.isListeningForSpeech {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [self!.getDeleteEntryButton()]
            } else {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [] // remove delete button when listening for speech
            }
            if let _ = self?.selectionCursor.clipboard {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems?.insert(self!.getPasteClipboardButton(), at: 0)
            }
            
            // Remove Undo Buttons
            self?.hideButton(self!.undoButton)
            self?.hideButton(self!.redoButton)
        }
        
        Utils.onEntryComplete(
            notification: notification,
            speechRecognition: self.speechRecognition,
            soundIntensityIndicatorHeight: self.soundIntensityIndicatorHeight
        ) { [weak self] in
            if let entryManager = self?.entryManager, let entry = entryManager.currentEntry {
                self?.updateUIText(text: entry.getText(), transformations: entry.transformations)
            }
            self?.refreshView()
        }
    }
    
    @objc func onSpeechStartPlaying(notification: Notification) {
        print("===== Detail View Controller: On Speech Start Playing =====")
        print("\tFirst Segment: ", (notification.userInfo!["next"] as? EntrySegment)?.getText() ?? "nil")
//        DispatchQueue.main.async { [weak self] in
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechStartPlaying(notification: notification) {
                if let entry = self?.entryManager.currentEntry, let segment = notification.userInfo!["next"] as? EntrySegment, segment.getText().count > 0 && segment.isActive(), let range = entry.getSegmentTextRange(of: segment) {
                    self?.updateUIText(text: entry.getText(), highlightRange: range, transformations: entry.transformations)
                }
            }
        }
    }
    
    @objc func onSpeechBoundaryCrossed(notification: Notification) {
        print("===== Detail View Controller: On Speech Boundary Crossed =====")
        print("\tWord: '\((notification.userInfo!["previous"] as? EntrySegment)?.getText() ?? "nil")'")
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechBoundaryCrossed(
                notification: notification,
                speechPlayer: self!.speechPlayer,
                pitchLabel: self!.pitchLabel
            ) {
                if let entry = self?.entryManager.currentEntry,
                   let segment = notification.userInfo!["previous"] as? EntrySegment,
                   segment.getText().count > 0 &&
                    segment.isActive(),
                   let range = entry.getSegmentTextRange(of: segment)
                {
                    self?.updateUIText(text: entry.getText(), highlightRange: range, transformations: entry.transformations)
                }
            }
        }
    }
    
    @objc func onSpeechSecondElapsed(notification: Notification) {
        print("===== Detail View Controller: On Speech Second Elapsed =====")
        print("\tSeconds: ", notification.userInfo!["seconds"] as! Double)
        
        if !self.notifications.isPresentingVisualNotification {
            DispatchQueue.main.async { [weak self] in
                Utils.onSpeechSecondElapsed(
                    notification: notification,
                    speechRecognition: self!.speechRecognition,
                    speechPlayer: self!.speechPlayer,
                    entryManager: self!.entryManager
                )
            }
        }
    }
    
    @objc func onSpeechStopPlaying(notification: Notification) {
        print("===== Detail View Controller: On Speech Stop Playing =====")
        
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechStopPlaying(
                notification: notification,
                speechRecognition: self!.speechRecognition,
                entryManager: self!.entryManager
            ) { [weak self] in
                if let entry = self?.entryManager.currentEntry, !self!.selectionCursor.hasSelection {
                    self?.updateUIText(text: entry.getText(), transformations: entry.transformations)
                }
            }
            
            self?.refreshView()
        }
    }
    
    @objc func onExecuteEntryAction(notification: Notification) {
        print("===== Detail View Controller: On Execute Entry Action =====")
        let type = notification.userInfo!["type"] as? VoiceCommandEngine.VoiceCommand
        if let type = type {
            switch (type) {
            case .CANCEL_SELECTION_UPDATE:
                DispatchQueue.main.async { [weak self] in
                    print("\tHide cursor...")
                    self?.setCursorVisibility(as: false)
                }
            case .EXIT_WALK:
                DispatchQueue.main.async { [weak self] in
                    print("\tRefresh view...")
                    self?.refreshView()
                }
            default:
                break
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.refreshView()
        }
    }
    
    // Reference: https://stackoverflow.com/questions/50128462/how-to-save-document-to-files-app-in-swift
    @objc func onEntryAudioExported(notification: Notification) {
        print("===== Detail View Controller: On Entry Audio Exported =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onEntryAudioExported(
                notification: notification,
                vc: self!
            )
        }
    }
    
    @objc func onClipboardChange(notification: Notification) {
        print("===== Detail View Controller: On Clipboard Change =====")
        DispatchQueue.main.async { [weak self] in
            let navigationController = Utils.getNavigationController()
            self?.adjustCommandBar()
            if !self!.speechRecognition.isListeningForSpeech {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [self!.getDeleteEntryButton()]
            } else {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [] // remove delete button when listening for speech
            }
            if let _ = self?.selectionCursor.clipboard {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems?.insert(self!.getPasteClipboardButton(), at: 0)
            }
        }
    }
    
    @objc func onSpeechUpdate(notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            if let entry = self?.entryManager.currentEntry, self!.speechRecognition.isListeningForCommands && entry.entrySegments.count == 0 {
                print("===== Detail View Controller: On Speech Update =====")
                print("\tEntry is empty, so clear buffer hint text from text view...")
                self?.updateUIText(text: "")
            }
        }
    }
    
    @objc func onEntryDeleted(notification: Notification) {
        print("===== Detail View Controller: On Entry Deleted =====")

        DispatchQueue.main.async { [weak self] in
            self?.textView?.attributedText = NSMutableAttributedString(string: "")
            let navigationController = Utils.getNavigationController()
            navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = nil
            self?.refreshView()
            self?.setCursorVisibility(as: false)
            self?.notifications.executeFeedback(
                visualMessage: "Entry List",
                audioMessage: "Navigated to entry list.",
                discardPrior: true,
                withHaptics: true
            )
            self?.performSegue(withIdentifier: Segues.moveFromDetailToEntryTable.rawValue, sender: nil)
        }
    }
    
    @objc func onUndoManagerChange(notification: Notification) {
        print("===== Detail View Controller: On Undo Manager Change =====")
        let canUndo = notification.userInfo!["canUndo"] as! Bool
        let canRedo = notification.userInfo!["canRedo"] as! Bool
        print("\tCan Undo: ", canUndo)
        print("\tCan Redo: ", canRedo)
        
        // Handle Undo Button
        if let undoButton = self.undoButton, canUndo && undoButton.alpha == 0 {
            // Show
            print("\tShow Undo Button...")
            self.showButton(self.undoButton)
        } else if let undoButton = self.undoButton, !canUndo && undoButton.alpha == 1 {
            // Hide
            print("\tHide Undo Button...")
            self.hideButton(self.undoButton)
        } else {
            // !canUndo && undoButton.alpha == 0 || canRedo && undoButton.alpha == 1
            // Do Nothing
        }
        
        // Handle Redo Button
        if let redoButton = self.redoButton, canRedo && redoButton.alpha == 0 {
            // Show
            print("\tShow Redo Button...")
            self.showButton(self.redoButton)
        } else if let redoButton = self.redoButton, !canRedo && redoButton.alpha == 1 {
            // Hide
            print("\tHide Redo Button...")
            self.hideButton(self.redoButton)
        } else {
            // !canUndo && redoButton.alpha == 0 || canRedo && redoButton.alpha == 1
            // Do Nothing
        }
        
        DispatchQueue.main.async { [weak self] in
            // Add text to text view if exists
            if let entryManager = self?.entryManager, let entry = entryManager.currentEntry {
                print("\tUpdate Text View: ", entry.getText())
                self?.updateUIText(text: entry.getText(), transformations: entry.transformations)
            }
        }
    }

    // MARK: - Configuration Methods
    
    func prepareNavbar() {
        DispatchQueue.main.async { [weak self] in
            let navigationController = Utils.getNavigationController()
            if !self!.speechRecognition.isListeningForSpeech {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [self!.getDeleteEntryButton()]
            } else {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [] // remove delete button when listening for speech
            }
            if let _ = self?.selectionCursor.clipboard {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems?.insert(self!.getPasteClipboardButton(), at: 0)
            }
        }
    }
    
    func prepareGeneralView() {
        self.soundIntensityIndicator?.backgroundColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
        self.pitchLabel?.textColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
        self.transformationLabel?.textColor = UIColor(hex: Utils.LINGUAL_ORANGE) ?? UIColor.orange
        self.hideButton(self.undoButton)
        self.hideButton(self.redoButton)
    }
    
    func prepareMenuBar() {
        guard let menuBar = self.menuBar else { return }
        menuBar.layer.shadowPath =
              UIBezierPath(
                roundedRect: menuBar.bounds,
                cornerRadius: menuBar.layer.cornerRadius
              ).cgPath
        menuBar.layer.shadowColor = UIColor.black.cgColor
        menuBar.layer.shadowOpacity = 0.5
        menuBar.layer.shadowOffset = CGSize(width: 0, height: -5)
        menuBar.layer.shadowRadius = 5
        menuBar.layer.masksToBounds = false
    }
    
    func prepareCommandBar() {
        guard let commandBar = self.commandBar else { return }
        commandBar.backgroundColor = UIColor(hex: Utils.LINGUAL_PURPLE) ?? UIColor.purple
        commandBar.layer.shadowPath =
              UIBezierPath(
                roundedRect: commandBar.bounds,
                cornerRadius: commandBar.layer.cornerRadius
              ).cgPath
        commandBar.layer.shadowColor = UIColor.black.cgColor
        commandBar.layer.shadowOpacity = 0.5
        commandBar.layer.shadowOffset = CGSize(width: 0, height: 5)
        commandBar.layer.shadowRadius = 5
        commandBar.layer.masksToBounds = false
    }
    
    func prepareSlider() {
        self.slider?.minimumValue = Utils.MINIMUM_PLAYBACK_RATE
        self.slider?.maximumValue = Utils.MAXIMUM_PLAYBACK_RATE
        self.slider?.isContinuous = true
        self.slider?.addTarget(self, action: #selector(self.sliderValueDidChange), for: .valueChanged)
        
        // Hide Slider
        self.setSliderVisibility(as: false)
    }
    
    // Reference: https://stackoverflow.com/questions/3231896/how-to-set-margins-padding-in-uitextview
    func prepareTextView() {
        // Set textContainer font size
        DispatchQueue.main.async { [weak self] in
            self?.textView?.font = self!.state.font
            self?.textView?.textContainerInset = UIEdgeInsets(
                top: Utils.TEXT_VIEW_PADDING_TOP,
                left: Utils.TEXT_VIEW_PADDING_LEFT,
                bottom: Utils.TEXT_VIEW_PADDING_BOTTOM,
                right: Utils.TEXT_VIEW_PADDING_RIGHT
            )
            
            // Add text to text view if exists
            if let entryManager = self?.entryManager, let entry = entryManager.currentEntry {
                self?.updateUIText(text: entry.getText(), transformations: entry.transformations)
            }
        }
    }
    
    func getDeleteEntryButton() -> UIBarButtonItem {
        let button  = CenteredButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: Utils.NAVBAR_BUTTON_LENGTH, height: Utils.NAVBAR_BUTTON_LENGTH)
        button.addTarget(self, action: #selector(self.handleDeleteEntry), for: .touchDown)
        button.setImage(UIImage(systemName: "trash"), for: .normal)
        button.setTitle("Delete Entry", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 11)
        button.setTitleColor(UIColor.systemGray5, for: .normal)
        button.tintColor = UIColor.systemGray
        
        let barButton = UIBarButtonItem(customView: button)
        
        return barButton
    }
    
    func getPasteClipboardButton() -> UIBarButtonItem {
        let button  = CenteredButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: Utils.NAVBAR_BUTTON_LENGTH, height: Utils.NAVBAR_BUTTON_LENGTH)
        button.addTarget(self, action: #selector(self.pasteClipboard), for: .touchDown)
        button.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
        button.setTitle("Paste Clipboard", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 11)
        button.setTitleColor(UIColor.systemGray5, for: .normal)
        button.tintColor = UIColor.systemGray
        
        let barButton = UIBarButtonItem(customView: button)

        return barButton
    }
    
    // MARK: - UI Methods

    func setCursorVisibility(as visible: Bool) {
        DispatchQueue.main.async { [weak self] in
            print("===== Set Cursor Visibility: \(visible) =====")
    
            // manage cursor view
            if self?.cursorView == nil && visible {
                print("\tCursor View is empty. Prepare it...")
                // Set dependencies
                if let selectionCursor = self?.selectionCursor, selectionCursor.textView == nil {
                    print("\tSelection Cursor doesn't have textView set. Set it")
                    self?.selectionCursor.setTextView(textView: self!.textView)
                }
                
                // initial set up for cursor
                self?.cursorView = UIView()
                
                if let selectionCursor = self?.selectionCursor, selectionCursor.cursorView == nil {
                    print("\tSelection Cursor doesn't have cursorView set. Set it")
                    self?.selectionCursor.setCursorView(cursorView: self!.cursorView)
                }

                Utils.initializeCursor(
                    textView: self!.textView!,
                    cursorView: self!.cursorView!,
                    font: self!.state.font
                )
                
                // Move cursor to end of document if text already
                if let selectionTextRange = self?.selectionCursor.selectionTextRange, let textView = self?.selectionCursor.textView, let caretViewRect = self?.selectionCursor.caretViewPositionRequiresUpdate(textPosition: selectionTextRange.toTextRange(textInput: textView)!.end) {
                    print("\tSelection Cursor already has cursor position. Move it there.")
                    self?.cursorView?.frame = caretViewRect
                } else if let entry = self?.entryManager.currentEntry, let textPosition = self?.textView?.endOfDocument, let caretViewRect = self?.selectionCursor.caretViewPositionRequiresUpdate(textPosition: textPosition), entry.entrySegments.count > 0 {
                    print("\tEntry already has speech. Move cursor to end of document.")
                    self?.cursorView?.frame = caretViewRect
                }
                
                // Set UIView background color
                self?.cursorView?.backgroundColor = UIColor.systemBlue
                
                // Create corner radius
                self?.cursorView?.layer.cornerRadius = CGFloat(Utils.CURSOR_WIDTH / 2)
                
                // Add above UIView object as the main view's subview.
                self?.view.addSubview(self!.cursorView!)
            } else if let _ = self?.cursorView, visible && self?.cursorView?.alpha == 0 {
                // Move cursor to end of document if text already
                if let selectionTextRange = self?.selectionCursor.selectionTextRange, let textView = self?.selectionCursor.textView, let caretViewRect = self?.selectionCursor.caretViewPositionRequiresUpdate(textPosition: selectionTextRange.toTextRange(textInput: textView)!.end) {
                    print("\tSelection Cursor already has cursor position. Move it there.")
                    self?.cursorView?.frame = caretViewRect
                } else if let entry = self?.entryManager.currentEntry, let textPosition = self?.textView?.endOfDocument, let caretViewRect = self?.selectionCursor.caretViewPositionRequiresUpdate(textPosition: textPosition), entry.entrySegments.count > 0 {
                    print("\tEntry already has speech. Move cursor to end of document.")
                    self?.cursorView?.frame = caretViewRect
                }
                
                // show cursor again
                self?.cursorView!.alpha = 1
            } else if let _ = self?.cursorView, !visible && self!.speechRecognition.isListeningForSpeech {
                // hide cursor
                self?.cursorView!.alpha = 0
            }
            
            // manage cursor model
            if visible {
                print("\tShow cursor...")
                // Set dependencies
                if let selectionCursor = self?.selectionCursor, selectionCursor.textView == nil {
                    print("\tSelection Cursor doesn't have textView set. Set it")
                    self?.selectionCursor.setTextView(textView: self!.textView)
                }
                if let selectionCursor = self?.selectionCursor, selectionCursor.cursorView == nil {
                    print("\tSelection Cursor doesn't have cursorView set. Set it")
                    self?.selectionCursor.setCursorView(cursorView: self!.cursorView)
                }
    
                if self?.cursorBlinkTimer != nil {
                    // Stopped cursor blinking that's already running
                    // To avoid two instances of blinking timers
                    self?.cursorBlinkTimer?.invalidate()
                }
                
                // start cursor blink
                self?.cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_CURSOR_BLINK_RATE, repeats: true) { [weak self] timer in
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
                print("\tStop cursor blinking...")
                // stop cursor blink
                if self?.cursorBlinkTimer != nil {
                    self?.cursorBlinkTimer?.invalidate()
                    self?.cursorBlinkTimer = nil
                }
            }
        }
    }
    
    func removeCursor() {
        print("===== Detail View Controller: Remove Cursor =====")
        // self.selectionCursor.reset()

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
                    self.menuBar?.alpha = 1
                    self.menuBarPositionBottom?.constant = 0
                }
            )
            // Reduce TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionBottom?.constant = Utils.MENU_BAR_HEIGHT
                }
            )
            
            // Move Sound Intensity Indicator Bottom
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.soundIntensityIndicatorPositionBottom?.constant = Utils.MENU_BAR_HEIGHT
                }
            )
        } else {
            // Hide Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.menuBar?.alpha = 0
                    self.menuBarPositionBottom?.constant = -20
                }
            )
            
            // Incrase TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionBottom?.constant = 0
                }
            )
            
            // Move Sound Intensity Indicator Bottom
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.soundIntensityIndicatorPositionBottom?.constant = 0
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
                    self.scrollView?.alpha = 1
                    self.scrollViewPositionTop?.constant = 0
                }
            )
            // Reduce TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionTop?.constant = Utils.SCROLL_VIEW_HEIGHT
                }
            )
            
            // Adjust cursor
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                // Adjust cursor to appropriate position
                if self!.selectionCursor.isVisible && !self!.selectionCursor.hasSelection {
                    self!.selectionCursor.textViewDidChange(self!.textView!)
                }
            }
        } else {
            // Hide Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.scrollView?.alpha = 0
                    self.scrollViewPositionTop?.constant = -20
                }
            )
            
            // Expand TextView Height
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.textViewPositionTop?.constant = 0
                }
            )

            // Adjust cursor
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                // Adjust cursor to appropriate position
                if self!.selectionCursor.isVisible && !self!.selectionCursor.hasSelection {
                    self!.selectionCursor.textViewDidChange(self!.textView!)
                }
            }
        }
    }
    
    func setCommandBarVisibility(as visible: Bool) {
        if visible {
            // Show Slider View
            self.commandBar?.isHidden = false

            // Animate in Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.commandBar?.alpha = 1
                }
            )
        } else {
            // Animate out Command Bar
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.commandBar?.alpha = 0
                }
            )
            
            // Hide Command Bar
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                self!.commandBar?.isHidden = true
            }
        }
    }
    
    func setSliderVisibility(as visible: Bool) {
        if visible {
            // Show Slider View
            self.sliderView?.isHidden = false

            // Animate in Slider View
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.sliderView?.alpha = 1
                }
            )
        } else {
            // Animate out Slider View
            UIView.animate(
                withDuration: Utils.DEFAULT_VIEW_TRANSITION_DURATION,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    self.sliderView?.alpha = 0
                }
            )
            
            // Hide Slider View
            Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_VIEW_TRANSITION_DURATION, repeats: false) { [weak self] timer in
                self!.sliderView?.isHidden = true
            }
        }
    }
    
    func updateUIText(text: String, highlightRange: NSRange? = nil, bufferRange: NSRange? = nil, transformations: [EntryTransformation]? = nil) {
        // Cache selection
        if let selectionTextRange = self.selectionCursor.selectionTextRange, self.selectionCursor.hasSelection {
            self.cachedTextViewSelectedRange = selectionTextRange
        }

        let mutableAttributedString = NSMutableAttributedString(string: text)

        if let bufferRange = bufferRange, bufferRange.length > 0 && text.count > 0 {
            // If passage is in buffer, we make gray text
            mutableAttributedString.addAttribute(.foregroundColor, value: UIColor.systemGray, range: bufferRange)
        } else if let highlightRange = highlightRange, highlightRange.length > 0 && text.count > 0 {
            // If words in entry are being echoed, we highlight them
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
        self.textView?.attributedText = mutableAttributedString
        // Set font
        self.textView?.font = self.state.font
        
        if let cachedTextViewSelectedRange = self.cachedTextViewSelectedRange,
           self.speechRecognition.isListeningForSpeech
        {
            self.selectionCursor.manualSelection(range: cachedTextViewSelectedRange)
            self.cachedTextViewSelectedRange = nil
        }
        
        // Notify of text change
        if self.selectionCursor.isVisible {
            self.selectionCursor.textViewDidChange(self.textView!)
        }
    }

    
    func adjustMenuBar() {
        print("===== Adjust Menu Bar =====")

        // Start Entry Button
        if let entry = self.entryManager.currentEntry,
           !self.speechRecognition.isListeningForSpeech &&
            entry.entrySegments.count == 0 &&
            self.speechRecognition.listeningPermissionsGranted {
            self.showButton(self.startEntryButton)
        } else {
            self.hideButton(self.startEntryButton)
        }
        
        // Resume Entry Button
        if let _ = self.entryManager.currentEntry,
           self.speechRecognition.isListeningForSpeech &&
            self.speechRecognition.userInitiatedPausedListeningForSpeech {
            self.showButton(self.resumeEntryButton)
        } else {
            self.hideButton(self.resumeEntryButton)
        }
        
        // Edit Entry Button
        if let entry = self.entryManager.currentEntry,
           !self.speechRecognition.isListeningForSpeech &&
            entry.entrySegments.count > 0 &&
            self.speechRecognition.listeningPermissionsGranted {
            self.showButton(self.editEntryButton)
        } else {
            self.hideButton(self.editEntryButton)
        }
        
        // Stop Listening Entry Button
        if self.speechRecognition.isListeningForSpeech && !self.entryManager.isExportingEntry {
            self.showButton(self.stopListeningEntryButton)
        } else {
            self.hideButton(self.stopListeningEntryButton)
        }
        
        // Play Entry Button
        if let entry = self.entryManager.currentEntry,
        (
            !self.speechPlayer.isPlayingEntry ||
            (
                self.speechPlayer.isPlayingEntry &&
                entry.speechPlayer.pausedPlayingEntry
            ) || (
                self.speechPlayer.isPlayingEntry &&
                    self.selectionCursor.hasSelection
            )
        ) && entry.entrySegments.count > 0 &&
        !(
            self.selectionCursor.hasSelection &&
            (
                self.entryManager.isWalkingEntry ||
                self.entryManager.isRunningEntry
            )
        ) {
            self.showButton(self.playButton)
            
            // Change text
            if self.selectionCursor.hasSelection {
                let buttonLabel = self.playButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Play Selection"
                }
            } else {
                let buttonLabel = self.playButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Play Entry"
                }
            }
        } else {
            self.hideButton(self.playButton)
        }
        
        // Stop Playing Entry Button
        if let entry = self.entryManager.currentEntry,
           self.speechPlayer.isPlayingEntry && entry.entrySegments.count > 0 &&
            !(
                AVAudioSession.isHeadphonesConnected &&
                self.selectionCursor.hasSelection
            ) &&
            !(
                AVAudioSession.isHeadphonesConnected &&
                self.entryManager.isWalkingEntry
            ) {
            self.showButton(self.stopPlayingButton)
            
            // Change text
            if self.selectionCursor.hasSelection {
                let buttonLabel = self.stopPlayingButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Stop Selection"
                }
            } else {
                let buttonLabel = self.stopPlayingButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Stop Entry"
                }
            }
        } else {
            self.hideButton(self.stopPlayingButton)
        }
        
        // Play Echo Button
        if let entry = self.entryManager.currentEntry,
        (
            !(
                self.speechSynthesis.isPlayingEcho ||
                self.speechSynthesis.isPlayingPassiveEcho
            ) ||
            (
                self.speechSynthesis.isPlayingEcho &&
                self.speechSynthesis.pausedEcho
            )
        ) && entry.entrySegments.count > 0 &&
        !(
            self.selectionCursor.hasSelection &&
            (
                self.entryManager.isWalkingEntry ||
                self.entryManager.isRunningEntry
            )
        ) {
            self.showButton(self.echoButton)
            
            // Change text
            if self.selectionCursor.hasSelection {
                let buttonLabel = self.echoButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Echo Selection"
                }
            } else {
                let buttonLabel = self.echoButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Echo Entry"
                }
            }
        } else {
            self.hideButton(self.echoButton)
        }

        // Stop Echo Button
        if let entry = self.entryManager.currentEntry,
        (
            self.speechSynthesis.isPlayingEcho ||
            self.speechSynthesis.isPlayingPassiveEcho
        ) && entry.entrySegments.count > 0 &&
        !(
            self.selectionCursor.hasSelection &&
            (
                self.entryManager.isWalkingEntry ||
                self.entryManager.isRunningEntry
            )
        ) {
            self.showButton(self.stopEchoButton)
        } else {
            self.hideButton(self.stopEchoButton)
        }
        
        // Export Entry Button
        if let entry = self.entryManager.currentEntry,
           entry.entrySegments.count > 0 &&
            !self.speechRecognition.isListeningForSpeech {
            self.showButton(self.exportButton)
            
            // Change text
            if self.selectionCursor.hasSelection {
                let buttonLabel = self.exportButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Export Selection"
                }
            } else {
                let buttonLabel = self.exportButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Export Entry"
                }
            }
        } else {
            self.hideButton(self.exportButton)
        }
        
        // Walk Element Button
        if let entry = self.entryManager.currentEntry, entry.entrySegments.count > 0 && !self.entryManager.isWalkingEntry {
            self.showButton(self.walkButton)
            
            // Change text
            if self.selectionCursor.hasSelection {
                let buttonLabel = self.walkButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Walk Selection"
                }
            } else {
                let buttonLabel = self.walkButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Walk Entry"
                }
            }
        } else {
            self.hideButton(self.walkButton)
        }
        
        // ===== Manage Visibility of Menu Bar =====
    
        if  self.state.appActivated {
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
        
        // Run Entry Button
        if let entry = self.entryManager.currentEntry,
           entry.entrySegments.count > 0 &&
            !self.selectionCursor.isUpdatingSelection &&
            !self.entryManager.isRunningEntry
        {
            numActiveButtons += 1
            self.showButton(self.runButton)
            // Change text
            if self.selectionCursor.hasSelection {
                let buttonLabel = self.runButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Run Selection"
                }
            } else {
                let buttonLabel = self.runButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Run Entry"
                }
            }
        } else {
            self.hideButton(self.runButton)
        }
        
        // Pause Entry Button
        if let entry = self.entryManager.currentEntry, entry.entrySegments.count > 0 &&
            (
                (
                    entry.speechRecognition.isListeningForSpeech &&
                    !entry.speechRecognition.pausedListeningForSpeech
                ) ||
                (
                    entry.speechPlayer.isPlayingEntry &&
                    !entry.speechPlayer.pausedPlayingEntry
                )
            ) && !self.selectionCursor.hasSelection &&
            !entry.entryManager.isWalkingEntry &&
            !entry.entryManager.isRunningEntry
        {
            numActiveButtons += 1
            self.showButton(self.pauseButton)
            // Change text
            if self.selectionCursor.hasSelection {
                let buttonLabel = self.pauseButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Pause Selection"
                }
            } else {
                let buttonLabel = self.pauseButton?.subviews.filter {$0 is UILabel }
                if let buttonLabel = buttonLabel?.first as? UILabel {
                    buttonLabel.text = "Pause Entry"
                }
            }
        } else {
            self.hideButton(self.pauseButton)
        }
        
        // Playback Rate Button
        if let entry = self.entryManager.currentEntry, entry.entrySegments.count > 0 {
            numActiveButtons += 1
            self.showButton(self.playbackRateButton)
        } else {
            self.hideButton(self.playbackRateButton)
        }
        
        // Echo Rate Button
        if let entry = self.entryManager.currentEntry, entry.entrySegments.count > 0 {
            numActiveButtons += 1
            self.showButton(self.echoRateButton)
        } else {
            self.hideButton(self.echoRateButton)
        }
        
        // ===== Conditional Buttons =====
        
        // Move Here Button
//        if let _ = self.entryManager.currentEntry, self.speechRecognition.isListeningForSpeech && (self.speechPlayer.pausedPlayingEntry || self.speechPlayer.isPlayingEntry || self.speechSynthesis.isPlayingEcho || self.speechSynthesis.pausedEcho) {
//            numActiveButtons += 1
//            self.showButton(self.moveHereButton)
//        } else {
//            self.hideButton(self.moveHereButton)
//        }
        self.hideButton(self.moveHereButton)
        
        // Inspect Clipboard Button
        if let _ = self.entryManager.currentEntry, let _ = self.selectionCursor.clipboard, self.speechRecognition.isListeningForSpeech {
            numActiveButtons += 1
            self.showButton(self.inspectClipboardButton)
        } else {
            self.hideButton(self.inspectClipboardButton)
        }
        
        // Play Commit Button
        if let entry = self.entryManager.currentEntry, entry.committedBufferRanges.count > 0 && self.speechRecognition.isListeningForSpeech {
            numActiveButtons += 1
            self.showButton(self.playCommitButton)
        } else {
            self.hideButton(self.playCommitButton)
        }
        
        // Pause Echo Button
        if let _ = self.entryManager.currentEntry,
           self.speechSynthesis.isPlayingEcho &&
            !self.speechSynthesis.pausedEcho &&
            !self.selectionCursor.hasSelection &&
            !self.entryManager.isWalkingEntry &&
            !self.entryManager.isRunningEntry {
            numActiveButtons += 1
            self.showButton(self.pauseEchoButton)
        } else {
            self.hideButton(self.pauseEchoButton)
        }
        
        // Skip Backward Button
        if let _ = self.entryManager.currentEntry,
           self.speechPlayer.isPlayingEntry &&
            !self.selectionCursor.hasSelection &&
            !self.entryManager.isWalkingEntry &&
            !self.entryManager.isRunningEntry {
            numActiveButtons += 1
            self.showButton(self.skipBackwardButton)
        } else {
            self.hideButton(self.skipBackwardButton)
        }
        
        // Skip Forward Button
        if let _ = self.entryManager.currentEntry,
           self.speechPlayer.isPlayingEntry &&
            !self.selectionCursor.hasSelection &&
            !self.entryManager.isWalkingEntry &&
            !self.entryManager.isRunningEntry {
            numActiveButtons += 1
            self.showButton(self.skipForwardButton)
        } else {
            self.hideButton(self.skipForwardButton)
        }
        
        // Previous Walk Element Button
        if let entry = self.entryManager.currentEntry,
           let walkingRange = self.entryManager.walkingRange,
           let firstWalkingSegmentIndex = Utils.getSegmentIndex(
                segment: Array(entry.entrySegments[walkingRange])[0],
                segments: Array(entry.entrySegments[walkingRange]),
                type: .next,
                isWord: true
           ),
           self.entryManager.isWalkingEntry &&
            self.entryManager.walkingIndex != firstWalkingSegmentIndex
        {
            numActiveButtons += 1
            self.showButton(self.walkPreviousWordButton)
        } else {
            self.hideButton(self.walkPreviousWordButton)
        }

        // Next Walk Element Button
        if let entry = self.entryManager.currentEntry,
           let walkingRange = self.entryManager.walkingRange,
           let lastWalkingSegmentIndex = Utils.getEntryNthLastSegmentIndex(
                segments: Array(entry.entrySegments[walkingRange]),
                selectionCursor: self.selectionCursor,
                n: 0
           ).1,
           self.entryManager.isWalkingEntry &&
            self.entryManager.walkingIndex < lastWalkingSegmentIndex
        {
            numActiveButtons += 1
            self.showButton(self.walkNextWordButton)
        } else {
            self.hideButton(self.walkNextWordButton)
        }
        
        // Exit Walk Run Button
        if let _ = self.entryManager.currentEntry, self.entryManager.isWalkingEntry || self.entryManager.isRunningEntry  {
            numActiveButtons += 1
            self.showButton(self.exitWalkRunButton)
        } else {
            self.hideButton(self.exitWalkRunButton)
        }
        
        // Pause Run Button
        if let _ = self.entryManager.currentEntry, self.entryManager.isRunningEntry {
            numActiveButtons += 1
            self.showButton(self.pauseRunButton)
        } else {
            self.hideButton(self.pauseRunButton)
        }
        
        // ===== Selection Buttons ======

        // Increase Rate Button
        if let firstSelectionSegment = self.selectionCursor.selectionSegments?.first,
           self.selectionCursor.hasSelection &&
            !self.selectionCursor.isUpdatingSelection &&
            firstSelectionSegment.getRate() + Utils.DISCRETE_PLAYBACK_DELTA <= Utils.MAXIMUM_PLAYBACK_RATE
        {
            numActiveButtons += 1
            self.showButton(self.increaseRateButton)
        } else {
            self.hideButton(self.increaseRateButton)
        }
        
        // Decrease Rate Button
        if let firstSelectionSegment = self.selectionCursor.selectionSegments?.first,
           self.selectionCursor.hasSelection &&
            !self.selectionCursor.isUpdatingSelection &&
            firstSelectionSegment.getRate() - Utils.DISCRETE_PLAYBACK_DELTA >= Utils.MINIMUM_PLAYBACK_RATE
        {
            numActiveButtons += 1
            self.showButton(self.decreaseRateButton)
        } else {
            self.hideButton(self.decreaseRateButton)
        }
        
        // Delete Button
        if self.selectionCursor.hasSelection && !self.selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.deleteSelectionButton)
        } else {
            self.hideButton(self.deleteSelectionButton)
        }
        
        // Update Button
        if self.selectionCursor.hasSelection && !self.selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.updateSelectionButton)
        } else {
            self.hideButton(self.updateSelectionButton)
        }
        
        // Cancel Update Button
        if self.selectionCursor.hasSelection && self.selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.cancelUpdateSelectionButton)
        } else {
            self.hideButton(self.cancelUpdateSelectionButton)
        }
        
        // Copy Button
        if self.selectionCursor.hasSelection && !self.selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.copySelectionButton)
        } else {
            self.hideButton(self.copySelectionButton)
        }
        
        // Cut Button
        if self.selectionCursor.hasSelection && !self.selectionCursor.isUpdatingSelection {
            numActiveButtons += 1
            self.showButton(self.cutSelectionButton)
        } else {
            self.hideButton(self.cutSelectionButton)
        }
        
        // ===== Manage Visibility of CommandBar =====
    
        if  numActiveButtons > 0 && self.state.appActivated {
            self.setScrollViewVisibility(as: true)
        } else {
            self.setScrollViewVisibility(as: false)
        }
    }
    
    func handleTransformationsView() {
        print("===== Detail View Controller: Handle Transformations View =====")
        if let selectionTransformations = self.selectionCursor.selectionTransformations, self.selectionCursor.hasSelection {
            print("\tSelection has transformations: ", selectionTransformations)
            self.transformationLabel?.isHidden = false
            self.transformationLabel?.text = "1.0"
            for transformation in selectionTransformations {
                if transformation.type == .playbackRate, let value = transformation.value {
                    print("\tFound transformation rate for selection: ", value)
                    self.transformationLabel?.text = String(value)
                    break
                }
            }
        } else {
            self.transformationLabel?.isHidden = true
        }
    }
    
    
    // MARK: - Entry Methods
    
    @objc func handleDeleteEntry() {
        self.entryManager.deleteEntry()
    }
    
    // MARK: - Helper Functions
    
    func showButton(_ commandButton: UIView?) {
        guard let commandButton = commandButton else { return }

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
    
    func hideButton(_ commandButton: UIView?) {
        guard let commandButton = commandButton else { return }

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
    
    public override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "selectedTextRange" {
            // Determine if we adjust command bar
            DispatchQueue.main.async { [weak self] in
                self?.refreshView()
            }
        } else if keyPath == "hasSelection" {
            if let _ = self.entryManager.currentEntry, let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, newHasSelection && !oldHasSelection && self.speechRecognition.isListeningForSpeech {
                print("====== Detail View Controller: Go from no selection to selection while recording ======")
                // ====== Go from no selection to selection while recording ======
                //
                DispatchQueue.main.async { [weak self] in
                    self?.refreshView()
                    self?.setCursorVisibility(as: false)
                }
            } else if let entry = self.entryManager.currentEntry, let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && self.speechRecognition.isListeningForSpeech && self.speechRecognition.pausedListeningForSpeech && self.speechRecognition.isListeningForCommands && !self.speechPlayer.isPlayingEntry && !self.speechSynthesis.isPlayingEcho && !self.speechSynthesis.isPlayingPassiveEcho {
                print("====== Detail View Controller: Go from selection to no selection while recording ======")
                // ====== Go from selection to no selection while recording ======
                //
                DispatchQueue.main.async { [weak self] in
                    self?.refreshView()
                    self?.setCursorVisibility(as: true)
                    if self!.speechRecognition.isListeningForSpeech {
                        // bring back listening timer
                        let timer = Utils.startRecordingUITimer(
                            timer: self!.speechRecognition.listeningTimer,
                            recording: true,
                            entry: entry,
                            speechRecognition: self!.speechRecognition,
                            selectionCursor: self!.selectionCursor
                        )
                        self?.speechRecognition.setListeningTimer(timer: timer)
                    }
                }
                
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] timer in
                    DispatchQueue.main.async {
                        self?.updateUIText(text: entry.getText(), transformations: entry.transformations)
                    }
                }
            } else if let _ = self.entryManager.currentEntry, let hasSelection = change?[.newKey] as? Bool, hasSelection && !self.speechRecognition.isListeningForSpeech && self.speechRecognition.isListeningForCommands {
                print("====== Detail View Controller: Go from no selection to selection while not recording ======")
                // ====== Go from no selection to selection while not recording ======
                //
                DispatchQueue.main.async { [weak self] in
                    self?.refreshView()
                }
            } else if let _ = self.entryManager.currentEntry, let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && !self.speechRecognition.isListeningForSpeech && self.speechRecognition.isListeningForCommands {
                print("====== Detail View Controller: Go from selection to no selection while not recording ======")
                // ====== Go from selection to no selection while not recording ======
                //
                DispatchQueue.main.async { [weak self] in
                    self?.refreshView()
                }
            }
        }
    }
    
    // MARK: - Touch Events
    
    @objc func handleSingleTap(touch: UITapGestureRecognizer) {
        print("===== Touch Interaction: Single Tap =====")
        if let entry = self.entryManager.currentEntry, self.state.appActivated && self.speechRecognition.isListeningForSpeech {
            print("\tComposing Entry => Move Cursor to Touch Location")
            print("\tDetermine text position near touch point...")
            let touchPoint = touch.location(in: self.textView)
            let textPosition = self.textView?.closestPosition(to: touchPoint)
            
            if self.textView?.selectedTextRange != nil && self.selectionCursor.hasSelection && (self.entryManager.isWalkingEntry || self.entryManager.isRunningEntry) {
                // Remove Selection in view and model
                print("\tPrior selection detected. Remove Selection in view and model...")
                entry.exitWalk(clearSelection: true, withFeedback: false)
            } else if self.textView?.selectedTextRange != nil && self.selectionCursor.hasSelection {
                // Remove Selection in view and model
                print("\tPrior selection detected. Remove Selection in view and model...")
                self.selectionCursor.clearSelection()
            }
            
            if let textPosition = textPosition {
                print("\tMove cursor to new position...")
                self.selectionCursor.moveCursor(textPosition: textPosition, cache: true)
            }
            
            // Uncommenting this causes issues with late reveal of command buttons
            // Double tapping a word to select it reveals the buttons in command bar temporarily
//            DispatchQueue.main.async { [weak self] in
//                self?.refreshView()
//            }
        } else if let entry = self.entryManager.currentEntry, self.state.appActivated && !self.speechRecognition.isListeningForSpeech {
            print("\tConsuming Entry => Playback to Entry")
            print("\tDetermine text position near touch point...")
            let touchPoint = touch.location(in: self.textView)
            let textPosition = self.textView?.closestPosition(to: touchPoint)
            
            if let textPosition = textPosition {
                print("\tGet entry segment at touch point...")
                let (index, _) = Utils.getIndexAtTextPosition(
                    textPosition: textPosition,
                    textView: self.textView!,
                    entry: entry,
                    segments: entry.entrySegments
                )
                
                if let index = index {
                    let segment = entry.entrySegments[index]
                    print("\tFound Segment: ", segment.getText())
                    print("\tPlay entry and Seek to segment...")
                    let wasPlayingEntry = self.speechPlayer.isPlayingEntry && !self.speechPlayer.pausedPlayingEntry
                    self.entryManager.stopPlayingEntry(withFeedback: false) {
                        if wasPlayingEntry {
                            print("\tDon't pause entry because it was playing before touch tap...")
                            self.entryManager.playEntry(from: segment.timeMapping.target.start)
                        } else {
                            print("\tPause entry because it wasn't playing before touch tap...")
                            self.entryManager.playEntry(
                                from: segment.timeMapping.target.start,
                                onStartHandler: {
                                    // Pause Entry
                                    self.entryManager.pauseEntry(withFeedback: false)
                                    
                                    // Highlight word
                                    DispatchQueue.main.async { [weak self] in
                                        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { timer in
                                            if segment.getText().count > 0 && segment.isActive(), let range = entry.getSegmentTextRange(of: segment) {
                                                print("\tHighlight word '\(segment.getText())' on screen...")
                                                self?.updateUIText(text: entry.getText(), highlightRange: range, transformations: entry.transformations)
                                            }
                                        }
                                    }
                                    
                                    // Audio Feedback
                                    soundEngine.tap()
                                }
                            )
                        }
                    }
                }
            }
            
        } else {
            print("\tAborted because app is not active or not listening for speech.")
        }
    }
    
    // Reference: https://www.appsdeveloperblog.com/create-uislider-in-swift-programmatically/
    // Reference: https://stackoverflow.com/questions/25499803/how-to-change-speech-rate-during-speaking-using-avspeechsynthesizer-in-ios-7
    @objc func sliderValueDidChange(_ sender: UISlider!) {
        print("===== Screen Button: Slider Value Changed =====")
        print("\tNew value: \(sender.value)")
        
        if  self.sliderType == .playback {
            // Set new playback rate
            self.speechPlayer.setPlaybackRate(to: sender.value)
            
            NotificationCenter.default.post(
                name: DetailViewController.onChangedPlayerRate,
                object: nil,
                userInfo: [ "rate" : sender.value]
            )
        } else if self.sliderType == .echo {
            NotificationCenter.default.post(
                name: DetailViewController.onChangedEchoRate,
                object: nil,
                userInfo: [
                    "rate" : sender.value
                ]
            )
        }
    }
    
    // MARK: - Menu Bar Methods
    
    @IBAction func startEntry(_ sender: Any? = nil) {
        if let _ = self.entryManager.currentEntry {
            self.entryManager.startEntry()
        } else {
            let _ = self.entryManager.createEntry(withListening: true)
        }
    }
    
    @IBAction func resumeEntry(_ sender: Any? = nil) {
        self.entryManager.resumeEntry()
    }
    
    @IBAction func editEntry(_ sender: Any? = nil) {
        self.entryManager.editEntry()
    }
    
    @IBAction func stopListeningEntry(_ sender: Any? = nil) {
        self.entryManager.stopEntry()
    }
    
    @IBAction func play(_ sender: Any? = nil) {
        self.entryManager.playEntry()
    }
    
    @IBAction func stopPlaying(_ sender: Any? = nil) {
        self.entryManager.stopPlayingEntry()
    }
    
    @IBAction func echo(_ sender: Any? = nil) {
        self.entryManager.echoEntry()
    }
    
    @IBAction func stopEcho(_ sender: Any? = nil) {
        self.entryManager.stopEcho()
    }
    
    @IBAction func walk(_ sender: Any? = nil) {
        self.entryManager.walkEntry()
    }
    
    @IBAction func export(_ sender: Any? = nil) {
        self.entryManager.exportEntry()
    }
    
    // MARK: - Resting Command Bar Methods
    
    @IBAction func moveHere(_ sender: Any? = nil) {
        selectionCursor.moveHere()
    }
    
    @IBAction func run(_ sender: Any? = nil) {
        self.entryManager.runEntry()
    }
    
    @IBAction func pause(_ sender: Any? = nil) {
        self.entryManager.pauseEntry()
    }
    
    @IBAction func playCommit(_ sender: Any? = nil) {
        self.entryManager.playCommit()
    }
    
    @IBAction func pauseEcho(_ sender: Any? = nil) {
        self.entryManager.pauseEcho()
    }
    
    @IBAction func inspectClipboard(_ sender: Any? = nil) {
        self.selectionCursor.inspectClipboard()
    }
    
    @IBAction func skipBackward(_ sender: Any? = nil) {
        self.entryManager.skipBackward()
    }
    
    @IBAction func skipForward(_ sender: Any? = nil) {
        self.entryManager.skipForward()
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
        
        print("\tSet Playback Slider Min and Max Values...")
        self.slider?.minimumValue = Utils.MINIMUM_PLAYBACK_RATE
        print("\tMin: ", self.slider?.minimumValue ?? "nil")
        self.slider?.maximumValue = Utils.MAXIMUM_PLAYBACK_RATE
        print("\tMax: ", self.slider?.maximumValue ?? "nil")
        self.slider?.value = self.speechPlayer.playbackRate
        
        DispatchQueue.main.async { [weak self] in
            print("\tHide Command Bar...")
            self?.setCommandBarVisibility(as: false)
            self?.refreshView()
        }
        
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
        
        print("\tSet Echo Slider Min and Max Values...")
        self.slider?.minimumValue = Utils.MINIMUM_ECHO_RATE
        print("\tMin: ", self.slider?.minimumValue ?? "nil")
        self.slider?.maximumValue = Utils.MAXIMUM_ECHO_RATE
        print("\tMax: ", self.slider?.maximumValue ?? "nil")
        self.slider?.value = self.speechSynthesis.echoRate
        
        DispatchQueue.main.async { [weak self] in
            print("\tHide Command Bar...")
            self?.setCommandBarVisibility(as: false)
            self?.refreshView()
        }
        
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
        
        print("\tAdjusting flag to: false")
        self.sliderIsVisible = false
        self.sliderType = nil
        
        DispatchQueue.main.async { [weak self] in
            print("\tHide Slider View...")
            self?.setSliderVisibility(as: false)
        }
        
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
    
    @IBAction func walkNextWord(_ sender: Any? = nil) {
        self.entryManager.walkNextWord()
    }
    
    @IBAction func walkPreviousWord(_ sender: Any? = nil) {
        self.entryManager.walkPreviousWord()
    }
    
    @IBAction func pauseRun(_ sender: Any? = nil) {
        self.entryManager.pauseRun()
    }
    
    @IBAction func exitWalkRun(_ sender: Any? = nil) {
        self.entryManager.exitWalkRun()
    }

    // MARK: - Selection Methods

    @IBAction func increaseRateSelection(_ sender: Any? = nil) {
        self.entryManager.increaseRateSelection()
    }
    
    @IBAction func decreaseRateSelection(_ sender: Any? = nil) {
        self.entryManager.decreaseRateSelection()
    }
    
    @IBAction func deleteSelection(_ sender: Any? = nil) {
        self.entryManager.deleteSelection()
    }
    
    @IBAction func updateSelection(_ sender: Any? = nil) {
        self.entryManager.updateSelection()
    }
    
    @IBAction func cancelUpdateSelection(_ sender: Any? = nil) {
        self.entryManager.cancelUpdateSelection()
    }
    
    @IBAction func copySelection(_ sender: Any? = nil) {
        self.entryManager.copySelection()
    }
    
    @IBAction func cutSelection(_ sender: Any? = nil) {
        self.entryManager.cutSelection()
    }
    
    // Reference: https://stackoverflow.com/questions/43251708/passing-arguments-to-selector-in-swift
    @objc func pasteClipboard(_ sender: Any? = nil) {
        self.entryManager.pasteClipboard()
    }
    
    // MARK: - UndoManager Methods
    
    @IBAction func undoTapped() {
        print("===== Detail View Controller: Undo Manager =====")
        self.entryManager.undo()
    }
    
    @IBAction func redoTapped() {
        print("===== Detail View Controller: Redo Manager =====")
        self.entryManager.redo()
    }
    
    // MARK: - Helper Methods
    
    func refreshView() {
        print("===== Detail View Controller: Refresh View =====")
        self.adjustCommandBar()
        self.adjustMenuBar()
        self.handleTransformationsView()
    }
}
