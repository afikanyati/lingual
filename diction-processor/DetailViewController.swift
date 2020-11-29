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
    @IBOutlet weak var startNoteButton: UIView?
    @IBOutlet weak var editNoteButton: UIView?
    @IBOutlet weak var resumeNoteButton: UIView?
    @IBOutlet weak var stopListeningNoteButton: UIView?
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
    @IBOutlet weak var walkNextElementButton: UIView?
    @IBOutlet weak var walkPreviousElementButton: UIView?
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
    var noteManager: NoteManager!
    var uiManager: UIManager!
    override var undoManager: UndoManager {
        return self.noteManager.undoManager
    }
    
    // MARK: - ViewController References
    weak var viewController: ViewController?
    weak var noteTableViewController: NoteTableViewController?
    
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
        case .moveFromDetailToNoteTable:
            print(">>>>> Segue from DetailViewController to NoteTableViewController >>>>>")
            if let noteTableViewController = segue.destination as? NoteTableViewController {
                noteTableViewController.state = self.state
                noteTableViewController.speechRecognition = self.speechRecognition
                noteTableViewController.speechSynthesis = self.speechSynthesis
                noteTableViewController.pitchRecognition = self.pitchRecognition
                noteTableViewController.notifications = self.notifications
                noteTableViewController.speechPlayer = self.speechPlayer
                noteTableViewController.selectionCursor = self.selectionCursor
                noteTableViewController.noteManager = self.noteManager
                noteTableViewController.uiManager = self.uiManager
            }
            self.speechRecognition.activateListeningIndicator(
                withRecording: self.speechRecognition.isListeningForSpeech,
                withStopListeningButton: !self.speechRecognition.isListeningForSpeech
            )
            
            // Remove textView and cursor from selectionCursor
            self.selectionCursor.setTextView()
            self.selectionCursor.setCursorView()
        case .moveFromSleepToNoteTable:
            print (">>>>> [Invalid Segue within DetailViewController] from ViewControlller to NoteTableViewController >>>>>")
        case .moveFromSleepToDetail:
            print (">>>>> [Invalid Segue within DetailViewController] from ViewControlller to DetailViewController >>>>>")
        case .moveFromNoteTableToDetail:
            print (">>>>> [Invalid Segue within DetailViewController] from NoteTableViewControlller to DetailViewController >>>>>")
        case .moveFromNoteTableToSleep:
            print (">>>>> [Invalid Segue within DetailViewController] from NoteTableViewControlller to ViewController >>>>>")
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
        
        // Observe NoteTableView
        notificationCenter.addObserver(
            self,
            selector: #selector(onNoteTableViewDidLoad(notification:)),
            name: NoteTableViewController.onDidLoad,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onNoteTableViewWillDisappear(notification:)),
            name: NoteTableViewController.onWillDisappear,
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
        
        // Observe Note
        notificationCenter.addObserver(
            self,
            selector: #selector(onNoteListenUpdate(notification:)),
            name: Note.onNoteListenUpdate,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onNoteListenStop(notification:)),
            name: Note.onNoteListenStop,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(onNoteComplete(notification:)),
            name: Note.onNoteComplete,
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
        
        // NoteManager
        notificationCenter.addObserver(
            self,
            selector: #selector(onExecuteNoteAction(notification:)),
            name: NoteManager.onExecuteNoteAction,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onNoteAudioExported(notification:)),
            name: NoteManager.onNoteAudioExported,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onNoteDeleted(notification:)),
            name: NoteManager.onNoteDeleted,
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
            name: NoteManager.onUndoManagerChange,
            object: nil
        )
    }
    
    @objc func onViewDidLoad(notification: Notification) {
        print("===== Detail View Controller: On View Did Load =====")
        self.viewController = storyboard?.instantiateViewController(withIdentifier: "ViewController") as? ViewController
    }
    
    @objc func onNoteTableViewDidLoad(notification: Notification) {
        print("===== Detail View Controller: On Note Table View Did Load =====")
        self.noteTableViewController = storyboard?.instantiateViewController(withIdentifier: "NoteTableViewController") as? NoteTableViewController
    }
    
    @objc func onViewWillDisappear(notification: Notification) {
        print("===== Detail View Controller: On View Will Disappear =====")
        self.viewController = nil
    }
    
    @objc func onNoteTableViewWillDisappear(notification: Notification) {
        print("===== Detail View Controller: On Note Table View Will Disappear =====")
        self.noteTableViewController = nil
    }
    
    @objc func appMovedToBackground() {
        print("===== Detail View Controller: App Moved to Background =====")
        DispatchQueue.main.async { [weak self] in
            // keep recording outside of app if note started
            if !self!.speechRecognition.isListeningForSpeech {
                self?.performSegue(withIdentifier: Segues.moveFromDetailToNoteTable.rawValue, sender: nil)
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
            if let note = self?.noteManager.currentNote {
                self?.updateUIText(text: note.getText(), highlightRange: highlightRange, transformations: note.transformations)
            }
            
            self?.refreshView()
        }
    }
    
    @objc func onEchoFinish(notification: Notification) {
        print("===== Detail View Controller: On Echo Finish =====")
        
        DispatchQueue.main.async { [weak self] in
            if let note = self?.noteManager.currentNote {
                self?.updateUIText(text: note.getText(), transformations: note.transformations)
            }

            self?.refreshView()
        }
    }
    
    @objc func onRequestToUpdateView(notification: Notification) {
        print("===== Detail View Controller: On Request To Update View =====")
        
        DispatchQueue.main.async { [weak self] in
            if let note = self?.noteManager.currentNote {
                self?.updateUIText(text: note.getText(), transformations: note.transformations)
            }

            self?.refreshView()
        }
    }
    
    @objc func onStartedListeningForWakePhrase(notification: Notification) {
        print("===== View Controller: On Started Listening For Wake Phrase =====")
        Utils.onStartedListeningForWakePhrase(
            withBackToNotesButton: true,
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStartedListeningForCommands(notification: Notification) {
        print("===== View Controller: On Started Listening For Commands =====")
        Utils.onStartedListeningForCommands(
            withBackToNotesButton: true,
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
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [self!.getDeleteNoteButton()]
            } else {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [] // remove delete button when listening for speech
            }
            if let _ = self?.selectionCursor.clipboard {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems?.insert(self!.getPasteClipboardButton(), at: 0)
            }
        }
        
        Utils.onStartedListeningForSpeech(
            withBackToNotesButton: true,
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
            withBackToNotesButton: true,
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
            withBackToNotesButton: true,
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
            withBackToNotesButton: true,
            notification: notification,
            speechRecognition: self.speechRecognition,
            soundIntensityIndicatorHeight: self.soundIntensityIndicatorHeight,
            pitchLabel: self.pitchLabel
        ) { [weak self] in
            self?.refreshView()
        }
    }
    
    @objc func onNoteListenUpdate(notification: Notification) {
        print("===== Detail View Controller: On Note Listen Update =====")
        DispatchQueue.main.async { [weak self] in
            let text = notification.userInfo!["text"] as! String
            print("Text:\n'\(text)'")
            let highlightRange = notification.userInfo!["highlightRange"] as! NSRange?
            let bufferRange = notification.userInfo!["bufferRange"] as! NSRange?
            let transformations = notification.userInfo!["transformations"] as! [NoteTransformation]
            self?.updateUIText(text: text, highlightRange: highlightRange, bufferRange: bufferRange, transformations: transformations)
            self?.refreshView()
        }
    }
    
    @objc func onNoteListenStop(notification: Notification) {
        print("===== Detail View Controller: On Note Listen Stop =====")
        DispatchQueue.main.async { [weak self] in
            if let noteManager = self?.noteManager, let note = noteManager.currentNote {
                let text = notification.userInfo!["text"] as! String
                self?.updateUIText(text: text, transformations: note.transformations)
            }
        }
        
        Utils.onNoteStop(
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
            note: self.noteManager.currentNote,
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
    
    @objc func onNoteComplete(notification: Notification) {
        print("===== Detail View Controller: On Note Complete =====")
        DispatchQueue.main.async { [weak self] in
            let navigationController = Utils.getNavigationController()
            if !self!.speechRecognition.isListeningForSpeech {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [self!.getDeleteNoteButton()]
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
        
        Utils.onNoteComplete(
            notification: notification,
            speechRecognition: self.speechRecognition,
            soundIntensityIndicatorHeight: self.soundIntensityIndicatorHeight
        ) { [weak self] in
            if let noteManager = self?.noteManager, let note = noteManager.currentNote {
                self?.updateUIText(text: note.getText(), transformations: note.transformations)
            }
            self?.refreshView()
        }
    }
    
    @objc func onSpeechStartPlaying(notification: Notification) {
        print("===== Detail View Controller: On Speech Start Playing =====")
        print("\tFirst segment: ", (notification.userInfo!["previous"] as? NoteSegment)?.getText() ?? "nil")
//        DispatchQueue.main.async { [weak self] in
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechStartPlaying(notification: notification) {
                if let note = self?.noteManager.currentNote, let segment = notification.userInfo!["next"] as? NoteSegment, segment.getText().count > 0 && segment.isActive(), let range = note.getSegmentTextRange(of: segment) {
                    self?.updateUIText(text: note.getText(), highlightRange: range, transformations: note.transformations)
                }
            }
        }
        
        if !self.speechRecognition.isListeningForSpeech {
            self.onRequestToUpdateView(notification: notification)
        }
    }
    
    @objc func onSpeechBoundaryCrossed(notification: Notification) {
        print("===== Detail View Controller: On Speech Boundary Crossed =====")
        print("\tWord: '\((notification.userInfo!["previous"] as? NoteSegment)?.getText() ?? "nil")'")
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechBoundaryCrossed(
                notification: notification,
                speechPlayer: self!.speechPlayer,
                pitchLabel: self!.pitchLabel
            ) {
                if let note = self?.noteManager.currentNote, let segment = notification.userInfo!["previous"] as? NoteSegment, segment.getText().count > 0 && segment.isActive(), let range = note.getSegmentTextRange(of: segment) {
                    self?.updateUIText(text: note.getText(), highlightRange: range, transformations: note.transformations)
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
                    noteManager: self!.noteManager
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
                noteManager: self!.noteManager
            ) { [weak self] in
                if let note = self?.noteManager.currentNote, !self!.selectionCursor.hasSelection {
                    self?.updateUIText(text: note.getText(), transformations: note.transformations)
                }
            }
            
            self?.refreshView()
        }
    }
    
    @objc func onExecuteNoteAction(notification: Notification) {
        print("===== Detail View Controller: On Execute Note Action =====")
        let type = notification.userInfo!["type"] as? String
        if let type = type {
            switch (type) {
            case "cancel update selection":
                DispatchQueue.main.async { [weak self] in
                    print("\tHide cursor...")
                    self?.setCursorVisibility(as: false)
                }
            case "exit mode":
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
    @objc func onNoteAudioExported(notification: Notification) {
        print("===== Detail View Controller: On Note Audio Exported =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onNoteAudioExported(
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
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [self!.getDeleteNoteButton()]
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
            if let note = self?.noteManager.currentNote, self!.speechRecognition.isListeningForCommands && note.noteSegments.count == 0 {
                print("===== Detail View Controller: On Speech Update =====")
                print("\tNote is empty, so clear buffer hint text from text view...")
                self?.updateUIText(text: "")
            }
        }
    }
    
    @objc func onNoteDeleted(notification: Notification) {
        print("===== Detail View Controller: On Deleted Note =====")

        DispatchQueue.main.async { [weak self] in
            self?.textView?.attributedText = NSMutableAttributedString(string: "")
            let navigationController = Utils.getNavigationController()
            navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = nil
            self?.refreshView()
            self?.setCursorVisibility(as: false)
            self?.performSegue(withIdentifier: Segues.moveFromDetailToNoteTable.rawValue, sender: nil)
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
            if let noteManager = self?.noteManager, let note = noteManager.currentNote {
                print("\tUpdate Text View: ", note.getText())
                self?.updateUIText(text: note.getText(), transformations: note.transformations)
            }
        }
    }

    // MARK: - Configuration Methods
    
    func prepareNavbar() {
        DispatchQueue.main.async { [weak self] in
            let navigationController = Utils.getNavigationController()
            if !self!.speechRecognition.isListeningForSpeech {
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [self!.getDeleteNoteButton()]
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
            if let noteManager = self?.noteManager, let note = noteManager.currentNote {
                self?.updateUIText(text: note.getText(), transformations: note.transformations)
            }
        }
    }
    
    func getDeleteNoteButton() -> UIBarButtonItem {
        let button  = CenteredButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: Utils.NAVBAR_BUTTON_LENGTH, height: Utils.NAVBAR_BUTTON_LENGTH)
        button.addTarget(self, action: #selector(self.handleDeleteNote), for: .touchDown)
        button.setImage(UIImage(systemName: "trash"), for: .normal)
        button.setTitle("Delete", for: .normal)
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
                } else if let note = self?.noteManager.currentNote, let textPosition = self?.textView?.endOfDocument, let caretViewRect = self?.selectionCursor.caretViewPositionRequiresUpdate(textPosition: textPosition), note.noteSegments.count > 0 {
                    print("\tNote already has speech. Move cursor to end of document.")
                    self?.cursorView?.frame = caretViewRect
                }
                
                // Set UIView background color
                self?.cursorView?.backgroundColor = UIColor.systemBlue
                
                // Create corner radius
                self?.cursorView?.layer.cornerRadius = CGFloat(Utils.CURSOR_WIDTH / 2)
                
                // Add above UIView object as the main view's subview.
                self?.view.addSubview(self!.cursorView!)
            } else if let _ = self?.cursorView, visible && self?.cursorView?.alpha == 0 {
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
    
    func updateUIText(text: String, highlightRange: NSRange? = nil, bufferRange: NSRange? = nil, transformations: [NoteTransformation]? = nil) {
        // Cache selection
        if let selectionTextRange = self.selectionCursor.selectionTextRange, self.selectionCursor.hasSelection {
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
        self.textView?.attributedText = mutableAttributedString
        // Set font
        self.textView?.font = self.state.font
        
        if let cachedTextViewSelectedRange = self.cachedTextViewSelectedRange {
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

        // Start Note Button
        if let note = self.noteManager.currentNote,
           !self.speechRecognition.isListeningForSpeech &&
            note.noteSegments.count == 0 &&
            self.speechRecognition.listeningPermissionsGranted {
            self.showButton(self.startNoteButton)
        } else {
            self.hideButton(self.startNoteButton)
        }
        
        // Resume Note Button
        if let _ = self.noteManager.currentNote,
           self.speechRecognition.isListeningForSpeech &&
            self.speechRecognition.userInitiatedPausedListeningForSpeech {
            self.showButton(self.resumeNoteButton)
        } else {
            self.hideButton(self.resumeNoteButton)
        }
        
        // Edit Note Button
        if let note = self.noteManager.currentNote,
           !self.speechRecognition.isListeningForSpeech &&
            note.noteSegments.count > 0 &&
            self.speechRecognition.listeningPermissionsGranted {
            self.showButton(self.editNoteButton)
        } else {
            self.hideButton(self.editNoteButton)
        }
        
        // Stop Listening Note Button
        if self.speechRecognition.isListeningForSpeech && !self.noteManager.isExportingNote {
            self.showButton(self.stopListeningNoteButton)
        } else {
            self.hideButton(self.stopListeningNoteButton)
        }
        
        // Play Note Button
        if let note = self.noteManager.currentNote,
        (
            !self.speechPlayer.isPlayingNote ||
            (
                self.speechPlayer.isPlayingNote &&
                note.speechPlayer.pausedPlayingNote
            ) || (
                self.speechPlayer.isPlayingNote &&
                    self.selectionCursor.hasSelection
            )
        ) && note.noteSegments.count > 0 &&
        !(
            self.selectionCursor.hasSelection &&
            (
                self.noteManager.isWalkingNote ||
                self.noteManager.isRunningNote
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
                    buttonLabel.text = "Play Note"
                }
            }
        } else {
            self.hideButton(self.playButton)
        }
        
        // Stop Playing Note Button
        if let note = self.noteManager.currentNote,
           self.speechPlayer.isPlayingNote && note.noteSegments.count > 0 &&
            !(
                AVAudioSession.isHeadphonesConnected &&
                self.selectionCursor.hasSelection
            ) &&
            !(
                AVAudioSession.isHeadphonesConnected &&
                self.noteManager.isWalkingNote
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
                    buttonLabel.text = "Stop Note"
                }
            }
        } else {
            self.hideButton(self.stopPlayingButton)
        }
        
        // Play Echo Button
        if let note = self.noteManager.currentNote,
        (
            !(
                self.speechSynthesis.isPlayingEcho ||
                self.speechSynthesis.isPlayingPassiveEcho
            ) ||
            (
                self.speechSynthesis.isPlayingEcho &&
                self.speechSynthesis.pausedEcho
            )
        ) && note.noteSegments.count > 0 &&
        !(
            self.selectionCursor.hasSelection &&
            (
                self.noteManager.isWalkingNote ||
                self.noteManager.isRunningNote
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
                    buttonLabel.text = "Echo Note"
                }
            }
        } else {
            self.hideButton(self.echoButton)
        }

        // Stop Echo Button
        if let note = self.noteManager.currentNote,
        (
            self.speechSynthesis.isPlayingEcho ||
            self.speechSynthesis.isPlayingPassiveEcho
        ) && note.noteSegments.count > 0 &&
        !(
            self.selectionCursor.hasSelection &&
            (
                self.noteManager.isWalkingNote ||
                self.noteManager.isRunningNote
            )
        ) {
            self.showButton(self.stopEchoButton)
        } else {
            self.hideButton(self.stopEchoButton)
        }
        
        // Export Note Button
        if let note = self.noteManager.currentNote,
           note.noteSegments.count > 0 &&
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
                    buttonLabel.text = "Export Note"
                }
            }
        } else {
            self.hideButton(self.exportButton)
        }
        
        // Walk Element Button
        if let note = self.noteManager.currentNote, note.noteSegments.count > 0 && !self.noteManager.isWalkingNote {
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
                    buttonLabel.text = "Walk Note"
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
        
        // Run Note Button
        if let note = self.noteManager.currentNote,
           note.noteSegments.count > 0 &&
            !self.selectionCursor.isUpdatingSelection &&
            !self.noteManager.isRunningNote
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
                    buttonLabel.text = "Run Note"
                }
            }
        } else {
            self.hideButton(self.runButton)
        }
        
        // Pause Note Button
        if let note = self.noteManager.currentNote, note.noteSegments.count > 0 &&
            (
                (
                    note.speechRecognition.isListeningForSpeech &&
                    !note.speechRecognition.pausedListeningForSpeech
                ) ||
                (
                    note.speechPlayer.isPlayingNote &&
                    !note.speechPlayer.pausedPlayingNote
                )
            ) && !self.selectionCursor.hasSelection &&
            !note.noteManager.isWalkingNote &&
            !note.noteManager.isRunningNote
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
                    buttonLabel.text = "Pause Note"
                }
            }
        } else {
            self.hideButton(self.pauseButton)
        }
        
        // Playback Rate Button
        if let note = self.noteManager.currentNote, note.noteSegments.count > 0 {
            numActiveButtons += 1
            self.showButton(self.playbackRateButton)
        } else {
            self.hideButton(self.playbackRateButton)
        }
        
        // Echo Rate Button
        if let note = self.noteManager.currentNote, note.noteSegments.count > 0 {
            numActiveButtons += 1
            self.showButton(self.echoRateButton)
        } else {
            self.hideButton(self.echoRateButton)
        }
        
        // ===== Conditional Buttons =====
        
        // Move Here Button
//        if let _ = self.noteManager.currentNote, self.speechRecognition.isListeningForSpeech && (self.speechPlayer.pausedPlayingNote || self.speechPlayer.isPlayingNote || self.speechSynthesis.isPlayingEcho || self.speechSynthesis.pausedEcho) {
//            numActiveButtons += 1
//            self.showButton(self.moveHereButton)
//        } else {
//            self.hideButton(self.moveHereButton)
//        }
        self.hideButton(self.moveHereButton)
        
        // Inspect Clipboard Button
        if let _ = self.noteManager.currentNote, let _ = self.selectionCursor.clipboard, self.speechRecognition.isListeningForSpeech {
            numActiveButtons += 1
            self.showButton(self.inspectClipboardButton)
        } else {
            self.hideButton(self.inspectClipboardButton)
        }
        
        // Play Commit Button
        if let note = self.noteManager.currentNote, note.committedBufferRanges.count > 0 && self.speechRecognition.isListeningForSpeech {
            numActiveButtons += 1
            self.showButton(self.playCommitButton)
        } else {
            self.hideButton(self.playCommitButton)
        }
        
        // Pause Echo Button
        if let _ = self.noteManager.currentNote,
           self.speechSynthesis.isPlayingEcho &&
            !self.speechSynthesis.pausedEcho &&
            !self.selectionCursor.hasSelection &&
            !self.noteManager.isWalkingNote &&
            !self.noteManager.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.pauseEchoButton)
        } else {
            self.hideButton(self.pauseEchoButton)
        }
        
        // Skip Backward Button
        if let _ = self.noteManager.currentNote,
           self.speechPlayer.isPlayingNote &&
            !self.selectionCursor.hasSelection &&
            !self.noteManager.isWalkingNote &&
            !self.noteManager.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.skipBackwardButton)
        } else {
            self.hideButton(self.skipBackwardButton)
        }
        
        // Skip Forward Button
        if let _ = self.noteManager.currentNote,
           self.speechPlayer.isPlayingNote &&
            !self.selectionCursor.hasSelection &&
            !self.noteManager.isWalkingNote &&
            !self.noteManager.isRunningNote {
            numActiveButtons += 1
            self.showButton(self.skipForwardButton)
        } else {
            self.hideButton(self.skipForwardButton)
        }
        
        // Previous Walk Element Button
        if let note = self.noteManager.currentNote,
           let walkingRange = self.noteManager.walkingRange,
           let firstWalkingSegmentIndex = Utils.getSegmentIndex(
                segment: Array(note.noteSegments[walkingRange])[0],
                segments: Array(note.noteSegments[walkingRange]),
                type: .next,
                isWord: true
           ),
           self.noteManager.isWalkingNote &&
            self.noteManager.walkingIndex != firstWalkingSegmentIndex
        {
            numActiveButtons += 1
            self.showButton(self.walkPreviousElementButton)
        } else {
            self.hideButton(self.walkPreviousElementButton)
        }

        // Next Walk Element Button
        if let note = self.noteManager.currentNote,
           let walkingRange = self.noteManager.walkingRange,
           let lastWalkingSegmentIndex = Utils.getNoteNthLastSegmentIndex(
                segments: Array(note.noteSegments[walkingRange]),
                selectionCursor: self.selectionCursor,
                n: 0
           ).1,
           self.noteManager.isWalkingNote &&
            self.noteManager.walkingIndex < lastWalkingSegmentIndex
        {
            numActiveButtons += 1
            self.showButton(self.walkNextElementButton)
        } else {
            self.hideButton(self.walkNextElementButton)
        }
        
        // Exit Walk Run Button
        if let _ = self.noteManager.currentNote, self.noteManager.isWalkingNote || self.noteManager.isRunningNote  {
            numActiveButtons += 1
            self.showButton(self.exitWalkRunButton)
        } else {
            self.hideButton(self.exitWalkRunButton)
        }
        
        // Pause Run Button
        if let _ = self.noteManager.currentNote, self.noteManager.isRunningNote {
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
    
    @objc func handleDeleteNote() {
        self.noteManager.deleteNote()
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
            if let _ = self.noteManager.currentNote, let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, newHasSelection && !oldHasSelection && self.speechRecognition.isListeningForSpeech {
                print("====== Detail View Controller: Go from no selection to selection while recording ======")
                // ====== Go from no selection to selection while recording ======
                //
                DispatchQueue.main.async { [weak self] in
                    self?.refreshView()
                    self?.setCursorVisibility(as: false)
                }
            } else if let note = self.noteManager.currentNote, let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && self.speechRecognition.isListeningForSpeech && self.speechRecognition.pausedListeningForSpeech && self.speechRecognition.isListeningForCommands && !self.speechPlayer.isPlayingNote && !self.speechSynthesis.isPlayingEcho && !self.speechSynthesis.isPlayingPassiveEcho {
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
                            note: note,
                            speechRecognition: self!.speechRecognition,
                            selectionCursor: self!.selectionCursor
                        )
                        self?.speechRecognition.setListeningTimer(timer: timer)
                    }
                }
                
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] timer in
                    DispatchQueue.main.async {
                        self?.updateUIText(text: note.getText(), transformations: note.transformations)
                    }
                }
            } else if let _ = self.noteManager.currentNote, let hasSelection = change?[.newKey] as? Bool, hasSelection && !self.speechRecognition.isListeningForSpeech && self.speechRecognition.isListeningForCommands {
                print("====== Detail View Controller: Go from no selection to selection while not recording ======")
                // ====== Go from no selection to selection while not recording ======
                //
                DispatchQueue.main.async { [weak self] in
                    self?.refreshView()
                }
            } else if let _ = self.noteManager.currentNote, let newHasSelection = change?[.newKey] as? Bool, let oldHasSelection = change?[.oldKey] as? Bool, !newHasSelection && oldHasSelection && !self.speechRecognition.isListeningForSpeech && self.speechRecognition.isListeningForCommands {
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
        if let note = self.noteManager.currentNote, self.state.appActivated && self.speechRecognition.isListeningForSpeech {
            print("\tComposing Note => Move Cursor to Touch Location")
            print("\tDetermine text position near touch point...")
            let touchPoint = touch.location(in: self.textView)
            let textPosition = self.textView?.closestPosition(to: touchPoint)
            
            if self.textView?.selectedTextRange != nil && self.selectionCursor.hasSelection && (self.noteManager.isWalkingNote || self.noteManager.isRunningNote) {
                // Remove Selection in view and model
                print("\tPrior selection detected. Remove Selection in view and model...")
                note.exitWalk(clearSelection: true, withFeedback: false)
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
        } else if let note = self.noteManager.currentNote, self.state.appActivated && !self.speechRecognition.isListeningForSpeech {
            print("\tConsuming Note => Playback to Note")
            print("\tDetermine text position near touch point...")
            let touchPoint = touch.location(in: self.textView)
            let textPosition = self.textView?.closestPosition(to: touchPoint)
            
            if let textPosition = textPosition {
                print("\tGet note segment at touch point...")
                let (index, _) = Utils.getIndexAtTextPosition(
                    textPosition: textPosition,
                    textView: self.textView!,
                    note: note,
                    segments: note.noteSegments
                )
                
                if let index = index {
                    let segment = note.noteSegments[index]
                    print("\tFound Segment: ", segment.getText())
                    print("\tPlay note and Seek to segment...")
                    let wasPlayingNote = self.speechPlayer.isPlayingNote && !self.speechPlayer.pausedPlayingNote
                    self.noteManager.stopPlayingNote(withFeedback: false) {
                        if wasPlayingNote {
                            print("\tDon't pause note because it was playing before touch tap...")
                            self.noteManager.playNote(from: segment.timeMapping.target.start)
                        } else {
                            print("\tPause note because it wasn't playing before touch tap...")
                            self.noteManager.playNote(
                                from: segment.timeMapping.target.start,
                                onStartHandler: {
                                    // Pause Note
                                    self.noteManager.pauseNote(withFeedback: false)
                                    
                                    // Highlight word
                                    DispatchQueue.main.async { [weak self] in
                                        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { timer in
                                            if segment.getText().count > 0 && segment.isActive(), let range = note.getSegmentTextRange(of: segment) {
                                                print("\tHighlight word '\(segment.getText())' on screen...")
                                                self?.updateUIText(text: note.getText(), highlightRange: range, transformations: note.transformations)
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
    
    @IBAction func startNote(_ sender: Any? = nil) {
        if let _ = self.noteManager.currentNote {
            self.noteManager.startNote()
        } else {
            let _ = self.noteManager.createNote(withListening: true)
        }
    }
    
    @IBAction func resumeNote(_ sender: Any? = nil) {
        self.noteManager.resumeNote()
    }
    
    @IBAction func editNote(_ sender: Any? = nil) {
        self.noteManager.editNote()
    }
    
    @IBAction func stopListeningNote(_ sender: Any? = nil) {
        self.noteManager.stopNote()
    }
    
    @IBAction func play(_ sender: Any? = nil) {
        self.noteManager.playNote()
    }
    
    @IBAction func stopPlaying(_ sender: Any? = nil) {
        self.noteManager.stopPlayingNote()
    }
    
    @IBAction func echo(_ sender: Any? = nil) {
        self.noteManager.echoNote()
    }
    
    @IBAction func stopEcho(_ sender: Any? = nil) {
        self.noteManager.stopEcho()
    }
    
    @IBAction func walk(_ sender: Any? = nil) {
        self.noteManager.walkNote()
    }
    
    @IBAction func export(_ sender: Any? = nil) {
        self.noteManager.exportNote()
    }
    
    // MARK: - Resting Command Bar Methods
    
    @IBAction func moveHere(_ sender: Any? = nil) {
        selectionCursor.moveHere()
    }
    
    @IBAction func run(_ sender: Any? = nil) {
        self.noteManager.runNote()
    }
    
    @IBAction func pause(_ sender: Any? = nil) {
        self.noteManager.pauseNote()
    }
    
    @IBAction func playCommit(_ sender: Any? = nil) {
        self.noteManager.playCommit()
    }
    
    @IBAction func pauseEcho(_ sender: Any? = nil) {
        self.noteManager.pauseEcho()
    }
    
    @IBAction func inspectClipboard(_ sender: Any? = nil) {
        self.selectionCursor.inspectClipboard()
    }
    
    @IBAction func skipBackward(_ sender: Any? = nil) {
        self.noteManager.skipBackward()
    }
    
    @IBAction func skipForward(_ sender: Any? = nil) {
        self.noteManager.skipForward()
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
        
        // Present Feedback
        if self.sliderType == .playback {
            self.notifications.executeFeedback(
                visualMessage: "Playback Rate: \(self.speechPlayer.playbackRate)x",
                audioMessage: "Set playback rate to \(self.speechPlayer.playbackRate)x.",
                withHaptics: true
            )
        } else {
            self.notifications.executeFeedback(
                visualMessage: "Echo rate: \(self.speechSynthesis.echoRate)x",
                audioMessage: "Set echo rate to \(self.speechSynthesis.echoRate)x.",
                withHaptics: true
            )
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
    
    @IBAction func walkNextElement(_ sender: Any? = nil) {
        self.noteManager.walkNextElement()
    }
    
    @IBAction func walkPreviousElement(_ sender: Any? = nil) {
        self.noteManager.walkPreviousElement()
    }
    
    @IBAction func pauseRun(_ sender: Any? = nil) {
        self.noteManager.pauseRun()
    }
    
    @IBAction func exitWalkRun(_ sender: Any? = nil) {
        self.noteManager.exitWalkRun()
    }

    // MARK: - Selection Methods

    @IBAction func increaseRateSelection(_ sender: Any? = nil) {
        self.noteManager.increaseRateSelection()
    }
    
    @IBAction func decreaseRateSelection(_ sender: Any? = nil) {
        self.noteManager.decreaseRateSelection()
    }
    
    @IBAction func deleteSelection(_ sender: Any? = nil) {
        self.noteManager.deleteSelection()
    }
    
    @IBAction func updateSelection(_ sender: Any? = nil) {
        self.noteManager.updateSelection()
    }
    
    @IBAction func cancelUpdateSelection(_ sender: Any? = nil) {
        self.noteManager.cancelUpdateSelection()
    }
    
    @IBAction func copySelection(_ sender: Any? = nil) {
        self.noteManager.copySelection()
    }
    
    @IBAction func cutSelection(_ sender: Any? = nil) {
        self.noteManager.cutSelection()
    }
    
    // Reference: https://stackoverflow.com/questions/43251708/passing-arguments-to-selector-in-swift
    @objc func pasteClipboard(_ sender: Any? = nil) {
        self.noteManager.pasteClipboard()
    }
    
    // MARK: - UndoManager Methods
    
    @IBAction func undoTapped() {
        print("===== Detail View Controller: Undo Manager =====")
        self.noteManager.undo()
    }
    
    @IBAction func redoTapped() {
        print("===== Detail View Controller: Redo Manager =====")
        self.noteManager.redo()
    }
    
    // MARK: - Helper Methods
    
    func refreshView() {
        print("===== Detail View Controller: Refresh View =====")
        self.adjustCommandBar()
        self.adjustMenuBar()
        self.handleTransformationsView()
    }
}
