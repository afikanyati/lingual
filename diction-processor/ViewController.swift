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

class ViewController: UIViewController, SegueProtocol {
    // MARK: - Notifications
    static let onDidLoad = Notification.Name(Notifications.onViewControllerDidLoad.rawValue)
    static let onWillDisappear = Notification.Name(Notifications.onViewControllerWillDisappear.rawValue)
    
    // MARK: - Outlets and Views
    
    // Wake Phrase
    @IBOutlet weak var wakePhraseLabel: UILabel?
    @IBOutlet weak var wakePhraseSubtitleLabel: UILabel?
    
    // Indicators
    @IBOutlet weak var soundIntensityIndicator: UIView?
    @IBOutlet weak var soundIntensityIndicatorHeight: NSLayoutConstraint?
    @IBOutlet weak var soundIntensityIndicatorPositionBottom: NSLayoutConstraint?
    @IBOutlet weak var pitchLabel: UILabel?
    
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
    
    // MARK: - ViewController References
    weak var noteTableViewController: NoteTableViewController?
    weak var detailViewController: DetailViewController?
    
    // MARK: - Lifecycle Methods
    
    public override func viewWillAppear(_ animated: Bool) {
        print("===== View Controller: View Will Appear =====")
        super.viewWillAppear(animated)
        
        self.configureNotificationObservers()
    }
    
    public override func viewDidLoad() {
        print("===== View Controller: View Did Load =====")
        super.viewDidLoad()

        // Prepare UI
        self.wakePhraseLabel?.text = "\"\(self.speechRecognition.wakePhrases[0].capitalizeFirstLetter())\""
        
        self.prepareGeneralView()
        
        // Notify observers of loading
        NotificationCenter.default.post(
            name: ViewController.onDidLoad,
            object: nil,
            userInfo: [:]
        )
        
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
            self.speechRecognition.activateListeningIndicator(
                withRecording: false,
                withStopListeningButton: true,
                withBackToNotesButton: false
            )
        }
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        print("===== View Controller: View Will Disappear =====")
        super.viewWillDisappear(animated)
    
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        // Notify observers of disappearing
        NotificationCenter.default.post(
            name: ViewController.onWillDisappear,
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
        case .moveFromSleepToNoteTable:
            print(">>>>> Segue from ViewController to NoteTableViewController >>>>>")
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
        case .moveFromSleepToDetail:
            print (">>>>> Segue from ViewControlller to DetailViewController >>>>>")
            if let detailViewController = segue.destination as? DetailViewController {
                detailViewController.state = self.state
                detailViewController.speechRecognition = self.speechRecognition
                detailViewController.speechSynthesis = self.speechSynthesis
                detailViewController.pitchRecognition = self.pitchRecognition
                detailViewController.notifications = self.notifications
                detailViewController.speechPlayer = self.speechPlayer
                detailViewController.selectionCursor = self.selectionCursor
                detailViewController.noteManager = self.noteManager
                detailViewController.uiManager = self.uiManager
            }
            self.speechRecognition.activateListeningIndicator(
                withRecording: self.speechRecognition.isListeningForSpeech,
                withStopListeningButton: !self.speechRecognition.isListeningForSpeech,
                withBackToNotesButton: true
            )
        case .moveFromNoteTableToDetail:
            print (">>>>> [Invalid Segue within ViewController] from NoteTableViewControlller to DetailViewController >>>>>")
        case .moveFromNoteTableToSleep:
            print (">>>>> [Invalid Segue within ViewController] from NoteTableViewControlller to ViewController >>>>>")
        case .moveFromDetailToNoteTable:
            print (">>>>> [Invalid Segue within ViewController] from DetailViewControlller to NoteTableViewController >>>>>")
        case .noIdentifier:
            print (">>>>> [Error] No Segue Identifier in ViewController >>>>>")
        }
    }
    
    // MARK: - Segues
    
    @IBAction func unwindToSleep(segue: UIStoryboardSegue) {
        
    }
    
    // MARK: - Setup
    
    func prepareGeneralView() {
        self.soundIntensityIndicator?.backgroundColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
        self.pitchLabel?.textColor = UIColor(hex: Utils.LINGUAL_RED) ?? UIColor.red
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        
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
        notificationCenter.addObserver(
            self,
            selector: #selector(onWakePhraseDetected(notification:)),
            name: SpeechRecognitionEngine.onWakePhraseDetected,
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
        
        // Note
        notificationCenter.addObserver(
            self,
            selector: #selector(onNoteComplete(notification:)),
            name: Note.onNoteComplete,
            object: nil
        )
        
        // NoteManager
        notificationCenter.addObserver(
            self,
            selector: #selector(onSetNote(notification:)),
            name: NoteManager.onSetNote,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onNoteAudioExported(notification:)),
            name: NoteManager.onNoteAudioExported,
            object: nil
        )
    }
    
    @objc func onNoteTableViewDidLoad(notification: Notification) {
        print("===== View Controller: On Note Table View Did Load =====")
        self.noteTableViewController = storyboard?.instantiateViewController(withIdentifier: "NoteTableViewController") as? NoteTableViewController
    }
    
    @objc func onDetailViewDidLoad(notification: Notification) {
        print("===== View Controller: On Detail View Did Load =====")
        self.detailViewController = storyboard?.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController
    }
    
    @objc func onNoteTableViewWillDisappear(notification: Notification) {
        print("===== View Controller: On View Will Disappear =====")
        self.noteTableViewController = nil
    }
    
    @objc func onDetailViewWillDisappear(notification: Notification) {
        print("===== View Controller: On Detail View Will Disappear =====")
        self.detailViewController = nil
    }
    
    @objc func onSetNote(notification: Notification) {
        print("===== View Controller: On Set Note =====")
        DispatchQueue.main.async { [weak self] in
            let index = notification.userInfo!["currentNoteIndex"] as? Int
            if let _ = index {
                Utils.onSetNote(
                    notification: notification,
                    vc: self!,
                    identifier: Segues.moveFromSleepToDetail.rawValue
                )
            }
        }
    }
    
    @objc func onPitchUpdate(notification: Notification) {
        // print("===== View Controller: On Pitch Update =====")
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
        // print("===== View Controller: On Power Update =====")
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
        print("===== View Controller: On Started Listening For Wake Phrase =====")
        Utils.onStartedListeningForWakePhrase(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStartedListeningForCommands(notification: Notification) {
        print("===== View Controller: On Started Listening For Commands =====")
        Utils.onStartedListeningForCommands(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStartedListeningForSpeech(notification: Notification) {
        print("===== View Controller: On Started Listening For Speech =====")
        Utils.onStartedListeningForSpeech(
            notification: notification,
            note: self.noteManager.currentNote,
            speechRecognition: self.speechRecognition,
            selectionCursor: self.selectionCursor
        )
    }
    
    @objc func onPausedListening(notification: Notification) {
        print("===== View Controller: On Paused Listening =====")
        Utils.onPausedListening(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStoppedListening(notification: Notification) {
        print("===== View Controller: On Stopped Listening =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onStoppedListening(
                notification: notification,
                speechRecognition: self!.speechRecognition,
                soundIntensityIndicatorHeight: self!.soundIntensityIndicatorHeight,
                pitchLabel: self!.pitchLabel
            )
        }
    }
    
    @objc func onWakePhraseDetected(notification: Notification) {
        print("===== View Controller: On Wake Phrase Detected =====")
        DispatchQueue.main.async { [weak self] in
            self?.performSegue(withIdentifier: Segues.moveFromSleepToNoteTable.rawValue, sender: nil)
        }
    }
    
    @objc func onStartTimedNotification(notification: Notification) {
        print("===== View Controller: On Start Timed Notification =====")
        Utils.onStartTimedNotification(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStopNotification(notification: Notification) {
        print("===== View Controller: On Stop Timed Notification =====")
        Utils.onStopNotification(
            notification: notification,
            note: self.noteManager.currentNote,
            speechRecognition: self.speechRecognition,
            selectionCursor: self.selectionCursor
        )
    }
    
    @objc func onStartIndefiniteNotification(notification: Notification) {
        print("===== View Controller: On Start Indefinite Notification =====")
        Utils.onStartIndefiniteNotification(
            notification: notification,
            state: self.state,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onNoteComplete(notification: Notification) {
        print("===== View Controller: On Note Complete =====")
        Utils.onNoteComplete(
            notification: notification,
            speechRecognition: self.speechRecognition,
            soundIntensityIndicatorHeight: self.soundIntensityIndicatorHeight
        )
    }
    
    @objc func onSpeechStartPlaying(notification: Notification) {
        print("===== View Controller: On Start Start Playing =====")
//        DispatchQueue.main.async { [weak self] in
        DispatchQueue.main.async {
            Utils.onSpeechStartPlaying(notification: notification)
        }
    }
    
    @objc func onSpeechBoundaryCrossed(notification: Notification) {
        print("===== View Controller: On Speech Boundary Crossed =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechBoundaryCrossed(
                notification: notification,
                speechPlayer: self!.speechPlayer,
                pitchLabel: self!.pitchLabel
            )
        }
    }
    
    @objc func onSpeechSecondElapsed(notification: Notification) {
        print("===== View Controller: On Speech Second Elapsed =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechSecondElapsed(
                notification: notification,
                speechRecognition: self!.speechRecognition,
                speechPlayer: self!.speechPlayer,
                noteManager: self!.noteManager
            )
        }
    }
    
    @objc func onSpeechStopPlaying(notification: Notification) {
        print("===== View Controller: On Speech Stop Playing =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechStopPlaying(
                notification: notification,
                speechRecognition: self!.speechRecognition,
                noteManager: self!.noteManager
            )
        }
    }
    
    // Reference: https://stackoverflow.com/questions/50128462/how-to-save-document-to-files-app-in-swift
    @objc func onNoteAudioExported(notification: Notification) {
        print("===== View Controller: On Note Audio Exported =====")
        DispatchQueue.main.async {
            Utils.onNoteAudioExported(
                notification: notification,
                vc: self
            )
        }
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
//                    self?.navigationBar.topItem?.title = "\(Utils.formattedTime(time: Float(self!.note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.note.getDuration(filteredDuration: true).seconds)))"
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
//                    self?.navigationBar.topItem?.title = ""
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
//                    self?.navigationBar.topItem?.title = "\(Utils.formattedTime(time: Float(self!.note.player.currentTime().seconds)))/\(Utils.formattedTime(time: Float(self!.note.getDuration(filteredDuration: true).seconds)))"
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
//                    self?.navigationBar.topItem?.title = ""
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
