//
//  Controller.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/24/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import AVFoundation

let AVATAR_URL = "https://firebasestorage.googleapis.com/v0/b/afika-nyati-website.appspot.com/o/resume%2Fafika.jpg?alt=media&token=f1d32c1d-07b4-48b0-abf9-2200290645c5"

class EntryTableViewController: UITableViewController, SegueProtocol {
    // MARK: - Notifications
    static let onDidLoad = Notification.Name(Notifications.onEntryTableViewControllerDidLoad.rawValue)
    static let onWillDisappear = Notification.Name(Notifications.onEntryTableViewControllerWillDisappear.rawValue)
    
    // MARK: - Outlets and Views
    
    // Indicators
    @IBOutlet weak var soundIntensityIndicator: UIView?
    @IBOutlet weak var soundIntensityIndicatorHeight: NSLayoutConstraint?
    @IBOutlet weak var soundIntensityIndicatorPositionBottom: NSLayoutConstraint?
    @IBOutlet weak var pitchLabel: UILabel?
    
    // MARK: - App State
    var state: StateManager!
    var speechRecognition: SpeechRecognitionEngine!
    var speechSynthesis: SpeechSynthesisEngine!
    var pitchRecognition: PitchRecognitionEngine!
    var notifications: NotificationEngine!
    var speechPlayer: SpeechPlayerEngine!
    var selectionCursor: SelectionCursor!
    var entryManager: EntryManager!
    var uiManager: UIManager!
    var voiceCommandEngine: VoiceCommandEngine!
    override var undoManager: UndoManager {
        return self.entryManager.undoManager
    }
    
    // MARK: - ViewController References
    weak var viewController: ViewController?
    weak var detailViewController: DetailViewController?
    
    // MARK: - Lifecycle Methods
    
    override func viewWillAppear(_ animated: Bool) {
        print("===== Entry Table View Controller: View Will Appear =====")
        super.viewWillAppear(animated)
        
        let state = UIApplication.shared.applicationState
        if state == .background || state == .inactive {
            print("\tApp is in the background. Segue to Sleep.")
            self.performSegue(withIdentifier: Segues.moveFromEntryTableToSleep.rawValue, sender: nil)
        }
        
        DispatchQueue.main.async { [weak self] in
            // reload table
            self?.tableView.reloadData()
            
            if let indexPath = self?.tableView.indexPathForSelectedRow {
                self!.tableView.deselectRow(at: indexPath, animated: true)
            }
        }

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
        print("===== Entry Table View Controller: View Did Load =====")
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Entry")
        
        DispatchQueue.main.async {
            // add table view buttons
            let navigationController = Utils.getNavigationController()
            navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [self.getNewEntryButton()]
        }
        
        // Notify observers of loading
        NotificationCenter.default.post(
            name: EntryTableViewController.onDidLoad,
            object: nil,
            userInfo: [:]
        )
        
        if AVAudioSession.isHeadphonesConnected {
            // Begin Nature Sounds
            soundEngine.startNatureAmbience()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        print("===== Entry Table View Controller: View Will Disappear =====")
        super.viewWillDisappear(animated)
        
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        // Notify observers of disappearing
        NotificationCenter.default.post(
            name: EntryTableViewController.onWillDisappear,
            object: nil,
            userInfo: [:]
        )
        
        // End Nature Sounds
        if soundEngine.isPlayingNatureAmbience {
            soundEngine.stopNatureAmbience()
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
        
        // Audio
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
        
        // Observe DetailView
        notificationCenter.addObserver(
            self,
            selector: #selector(onDetailViewDidLoad(notification:)),
            name: DetailViewController.onDidLoad,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onDetailViewWillDisappear(notification:)),
            name: DetailViewController.onWillDisappear,
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
            selector: #selector(onStoppedListening(notification:)),
            name: SpeechRecognitionEngine.onStoppedListeningForSpeech,
            object: nil
        )
        
        // Observe Notification Manager
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
        
        // State
        notificationCenter.addObserver(
            self,
            selector: #selector(onCreatedEntry(notification:)),
            name: EntryManager.onCreatedEntry,
            object: nil
        )
        
        // Entry
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
            selector: #selector(onSetEntry(notification:)),
            name: EntryManager.onSetEntry,
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
    }
    
    @objc func onDetailViewDidLoad(notification: Notification) {
        print("===== Entry Table View Controller: On Detail View Did Load =====")
        self.detailViewController = storyboard?.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController
    }
    
    @objc func onViewDidLoad(notification: Notification) {
        print("===== Entry Table View Controller: On View Did Load =====")
        self.viewController = storyboard?.instantiateViewController(withIdentifier: "ViewController") as? ViewController
    }
    
    @objc func onViewWillDisappear(notification: Notification) {
        print("===== Entry Table View Controller: On View Will Disappear =====")
        self.viewController = nil
    }
    
    @objc func onDetailViewWillDisappear(notification: Notification) {
        print("===== Entry Table View Controller: On Detail View Will Disappear =====")
        self.detailViewController = nil
    }
    
    @objc func onCreatedEntry(notification: Notification) {
        print("===== Entry Table View Controller: On Created Entry =====")
        DispatchQueue.main.async { [weak self] in
            // reload table
            self?.tableView.reloadData()
        }
    }
    
    @objc func appMovedToBackground() {
        print("===== Entry Table View Controller: App Moved to Background =====")
        DispatchQueue.main.async { [weak self] in
            // keep recording outside of app if entry started
            if !self!.speechRecognition.isListeningForSpeech {
                self?.performSegue(withIdentifier: Segues.moveFromEntryTableToSleep.rawValue, sender: nil)
            }
        }
    }
    
    @objc func audioSessionRouteChange(notification: Notification) {
        print("===== Entry Table View Controller: Audio Session Route Change =====")
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
        }
        print("\tReason: ", reason)

        // Switch over the route change reason.
        switch reason {
        case .newDeviceAvailable: // New device found.
            if AVAudioSession.isHeadphonesConnected {
                // Begin Nature Sounds
                soundEngine.startNatureAmbience()
            }
        case .oldDeviceUnavailable: // Old device removed.
            // End Nature Sounds
            if soundEngine.isPlayingNatureAmbience {
                soundEngine.stopNatureAmbience()
            }
            break
        default:
            break
        }
    }
    
    @objc func handleInterruption(notification: Notification) {
        print("===== Entry Table View Controller: Handle Interruption =====")
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
        print("===== Entry Table View Controller: Handle Secondary Audio =====")
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
    
    @objc func onPitchUpdate(notification: Notification) {
        // print("===== Entry Table View Controller: On Pitch Update =====")
        DispatchQueue.main.async { [weak self] in
            let pitchDatum = notification.userInfo!["pitch"] as? PitchDatum
            
            if let pitch = pitchDatum?.pitch, self?.pitchLabel == nil && !self!.speechPlayer.isPlayingEntry {
                let navigationController = Utils.getNavigationController()
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [self!.getNewEntryButton(), self!.getPitchLabel(pitchText: pitch.note.string)]
            }
            
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
        // print("===== Entry Table View Controller: On Power Update =====")
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
    
    @objc func onStartedListeningForWakePhrase(notification: Notification) {
        print("===== Entry Table View Controller: On Started Listening For Wake Phrase =====")
        Utils.onStartedListeningForWakePhrase(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStartedListeningForCommands(notification: Notification) {
        print("===== Entry Table View Controller: On Started Listening For Commands =====")
        Utils.onStartedListeningForCommands(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStartedListeningForSpeech(notification: Notification) {
        print("===== Entry Table View Controller: On Started Listening For Speech =====")
        Utils.onStartedListeningForSpeech(
            notification: notification,
            entry: self.entryManager.currentEntry,
            speechRecognition: self.speechRecognition,
            selectionCursor: self.selectionCursor
        )
    }
    
    @objc func onPausedListening(notification: Notification) {
        print("===== Entry Table View Controller: On Paused Listening =====")
        Utils.onPausedListening(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStoppedListening(notification: Notification) {
        print("===== Entry Table View Controller: On Stopped Listening =====")
        Utils.onStoppedListening(
            notification: notification,
            speechRecognition: self.speechRecognition,
            soundIntensityIndicatorHeight: self.soundIntensityIndicatorHeight,
            pitchLabel: self.pitchLabel
        )
    }
    
    @objc func onEntryListenStop(notification: Notification) {
        print("===== Entry Table View Controller: On Entry Listen Stop =====")
        Utils.onEntryStop(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStartTimedNotification(notification: Notification) {
        print("===== Entry Table View Controller: On Start Timed Notification =====")
        Utils.onStartTimedNotification(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStopNotification(notification: Notification) {
        print("===== Entry Table View Controller: On Stop Timed Notification =====")
        Utils.onStopNotification(
            notification: notification,
            entry: self.entryManager.currentEntry,
            speechRecognition: self.speechRecognition,
            selectionCursor: self.selectionCursor
        )
    }
    
    @objc func onStartIndefiniteNotification(notification: Notification) {
        print("===== Entry Table View Controller: On Start Indefinite Notification =====")
        Utils.onStartIndefiniteNotification(
            notification: notification,
            state: self.state,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onEntryComplete(notification: Notification) {
        print("===== Entry Table View Controller: On Entry Complete =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onEntryComplete(
                notification: notification,
                speechRecognition: self!.speechRecognition,
                soundIntensityIndicatorHeight: self!.soundIntensityIndicatorHeight
            )
        }
    }
    
    @objc func onSpeechStartPlaying(notification: Notification) {
        print("===== Entry Table View Controller: On Speech Start Playing =====")
//        DispatchQueue.main.async { [weak self] in
        DispatchQueue.main.async {
            Utils.onSpeechStartPlaying(notification: notification)
        }
    }
    
    @objc func onSpeechBoundaryCrossed(notification: Notification) {
        print("===== Entry Table View Controller: On Speech Boundary Crossed =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechBoundaryCrossed(
                notification: notification,
                speechPlayer: self!.speechPlayer,
                pitchLabel: self!.pitchLabel
            )
        }
    }
    
    @objc func onSpeechSecondElapsed(notification: Notification) {
        print("===== Entry Table View Controller: On Speech Second Elapsed =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechSecondElapsed(
                notification: notification,
                speechRecognition: self!.speechRecognition,
                speechPlayer: self!.speechPlayer,
                entryManager: self!.entryManager
            )
        }
    }
    
    @objc func onSpeechStopPlaying(notification: Notification) {
        print("===== Entry Table View Controller: On Speech Stop Playing =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechStopPlaying(
                notification: notification,
                speechRecognition: self!.speechRecognition,
                entryManager: self!.entryManager
            )
        }
    }
    
    @objc func onSetEntry(notification: Notification) {
        print("===== Entry Table View Controller: On Set Entry =====")
        DispatchQueue.main.async { [weak self] in
            let index = notification.userInfo!["currentEntryIndex"] as? Int
            print("\tEntry Index: ", index ?? "nil")
            if let _ = index {
                Utils.onSetEntry(
                    notification: notification,
                    vc: self!,
                    identifier: Segues.moveFromEntryTableToDetail.rawValue
                )
            }
        }
    }
    
    @objc func onEntryDeleted(notification: Notification) {
        print("===== Entry Table View Controller: On Entry Deleted =====")
        DispatchQueue.main.async { [weak self] in
            // reload table
            self?.tableView.reloadData()
        }
    }
    
    // Reference: https://stackoverflow.com/questions/50128462/how-to-save-document-to-files-app-in-swift
    @objc func onEntryAudioExported(notification: Notification) {
        print("===== Entry Table View Controller: On Entry Audio Exported =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onEntryAudioExported(
                notification: notification,
                vc: self!
            )
        }
    }
    
    // MARK: - Segues
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let identifier = segueIdentifierCase(for: segue) else {
            assertionFailure(">>>>> [Error] Could not map Segue Identifier - \(String(describing: segue.identifier)) - to Segue Case >>>>>")
            return
        }

        switch identifier {
        case .moveFromEntryTableToDetail:
            print(">>>>> Segue from EntryTableViewController to DetailViewController >>>>>")
            if let detailViewController = segue.destination as? DetailViewController {
                detailViewController.state = self.state
                detailViewController.speechRecognition = self.speechRecognition
                detailViewController.speechSynthesis = self.speechSynthesis
                detailViewController.pitchRecognition = self.pitchRecognition
                detailViewController.notifications = self.notifications
                detailViewController.speechPlayer = self.speechPlayer
                detailViewController.selectionCursor = self.selectionCursor
                detailViewController.entryManager = self.entryManager
                detailViewController.uiManager = self.uiManager
                detailViewController.voiceCommandEngine = self.voiceCommandEngine
            }
            self.speechRecognition.activateListeningIndicator(
                withRecording: self.speechRecognition.isListeningForSpeech,
                withStopListeningButton: !self.speechRecognition.isListeningForSpeech,
                withBackToEntriesButton: true
            )
        case .moveFromEntryTableToSleep:
            print(">>>>> Segue from EntryTableViewController to ViewController >>>>>")
            if let viewController = segue.destination as? ViewController {
                viewController.state = self.state
                viewController.speechRecognition = self.speechRecognition
                viewController.speechSynthesis = self.speechSynthesis
                viewController.pitchRecognition = self.pitchRecognition
                viewController.notifications = self.notifications
                viewController.speechPlayer = self.speechPlayer
                viewController.selectionCursor = self.selectionCursor
                viewController.entryManager = self.entryManager
                viewController.uiManager = self.uiManager
                viewController.voiceCommandEngine = self.voiceCommandEngine
            }
            self.speechRecognition.activateListeningIndicator(
                withRecording: false,
                withStopListeningButton: true
            )
        case .moveFromSleepToEntryTable:
            print (">>>>> [Invalid Segue within EntryTableViewController] from ViewControlller to EntryTableViewController >>>>>")
        case .moveFromSleepToDetail:
            print (">>>>> [Invalid Segue within EntryTableViewController] from ViewControlller to DetailViewController >>>>>")
        case .moveFromDetailToEntryTable:
            print (">>>>> [Invalid Segue within EntryTableViewController] from DetailViewControlller to EntryTableViewController >>>>>")
        case .noIdentifier:
            print (">>>>> [Error] No Segue Identifier in ViewController >>>>>")
        }
    }
    
    // MARK: - Segues
    
    @IBAction func unwindToEntryTable(segue: UIStoryboardSegue) {
        
    }
    
    // MARK: - Table View
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.state.activeEntries.count
    }
    
    // Reference: https://stackoverflow.com/questions/25002017/how-to-change-font-of-uibutton-with-swift
    // Reference: https://stackoverflow.com/questions/38845948/how-to-change-each-uitableviewcell-background-color
    // Reference: https://stackoverflow.com/questions/6322798/adding-the-little-arrow-to-the-right-side-of-a-cell-in-an-iphone-tableview-cell
    // Reference: https://stackoverflow.com/questions/3484511/altering-the-background-color-of-cell-accessoryview-and-cell-editingaccessoryvie
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Entry", for: indexPath)
        cell.accessoryType = .disclosureIndicator
        cell.contentView.superview?.backgroundColor = UIColor(hex: Utils.LINGUAL_WHITE) ?? UIColor.white
        cell.textLabel?.attributedText = self.makeEntryAttributedString(entry: self.state.activeEntries[indexPath.row], index: indexPath.row)
        cell.textLabel?.numberOfLines = 2
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Set entry index
        if let entryIndex = self.entryManager.currentIndex, self.speechRecognition.isListeningForSpeech && entryIndex != indexPath.row {
            self.notifications.executeError(
                text: "Error. Another entry is being edited."
            )
        } else {
            self.entryManager.setCurrentEntry(index: indexPath.row)
        }
        
        // Give haptic feedback
        hapticEngine.success()
    }
    
    // Reference: https://www.hackingwithswift.com/example-code/uikit/how-to-swipe-to-delete-uitableviewcells
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            self.entryManager.deleteEntry(index: indexPath.row, withConfirmation: false)
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
        }
    }
    
    func makeEntryAttributedString(entry: Entry, index: Int) -> NSAttributedString {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .headline),
            NSAttributedString.Key.foregroundColor: self.entryManager.currentIndex != nil && self.speechRecognition.isListeningForSpeech && index == self.entryManager.currentIndex! ? UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red : UIColor(hex: Utils.LINGUAL_DARK_PURPLE) ?? UIColor.black
        ]
        var subtitleAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .subheadline)
        ]

        // Reference: http://www.gwtproject.org/javadoc/latest/com/google/gwt/i18n/client/DateTimeFormat.html
        
        let titleString = entry.getTitle(attributes: titleAttributes)
        let entryText = entry.getText()
        let preview = entryText.count > Utils.ENTRY_ITEM_PREVIEW_CHAR_COUNT ? "\(entryText.substring(toIndex: Utils.ENTRY_ITEM_PREVIEW_CHAR_COUNT))..." : entryText
        if preview.count > 0 {
            subtitleAttributes[NSAttributedString.Key.foregroundColor] = self.entryManager.currentIndex != nil && self.speechRecognition.isListeningForSpeech && index == self.entryManager.currentIndex! ? UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red : UIColor.darkGray
            let subtitleString = NSAttributedString(string: "\n\(preview)", attributes: subtitleAttributes)
            titleString.append(subtitleString)
        } else {
            subtitleAttributes[NSAttributedString.Key.foregroundColor] = self.entryManager.currentIndex != nil && self.speechRecognition.isListeningForSpeech && index == self.entryManager.currentIndex! ? UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red : UIColor(hex: Utils.LINGUAL_GRAY) ?? UIColor.systemGray2
            let subtitleString = NSAttributedString(string: "\nBlank entry.", attributes: subtitleAttributes)
            titleString.append(subtitleString)
        }

        return titleString
    }
    
    func getNewEntryButton() -> UIBarButtonItem {
        let button  = CenteredButton(type: .custom)

        button.frame = CGRect(x: 0.0, y: 0.0, width: Utils.NAVBAR_BUTTON_LENGTH, height: Utils.NAVBAR_BUTTON_LENGTH)
        button.addTarget(self, action: #selector(self.createEntry), for: .touchDown)
        button.setImage(UIImage(systemName: "plus"), for: .normal)
        button.setTitle("Create Entry", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 11)
        button.setTitleColor(UIColor.systemGray5, for: .normal)
        button.tintColor = UIColor.systemGray
        
        let barButton = UIBarButtonItem(customView: button)
        
        return barButton
    }
    
    // Reference: https://www.robnorback.com/blog/setting-title-and-title-color-on-a-uibutton-in-swift-3
    func getPitchLabel(pitchText: String) -> UIBarButtonItem {
        let button  = UIButton(type: .custom)
        button.frame = CGRect(x: 0.0, y: 0.0, width: Utils.NAVBAR_BUTTON_LENGTH, height: Utils.NAVBAR_BUTTON_LENGTH)
        button.setTitle(pitchText, for: .normal)
        button.titleLabel?.font = self.state.font
        button.setTitleColor(UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red, for: .normal)
        
        let barButton = UIBarButtonItem(customView: button)
        barButton.isEnabled = false
        
        return barButton
    }
    
    // MARK: - Methods
    
    @objc func createEntry(_ sender: Any? = nil) {
        print("===== Entry Table View Controller: Create Entry =====")
        let entryUID = self.entryManager.createEntry(voiceCommand: false, withListening: false)
        let _ = self.entryManager.getEntry(uid: entryUID)
        
        // Haptic Feedback
        hapticEngine.success()
    }
}
