//
//  DictionaryViewController.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/4/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import AVFoundation

// MARK: - DictionaryViewController

class DictionaryViewController: UITableViewController, SegueProtocol {
    // MARK: - Notifications
    static let onDidLoad = Notification.Name(Notifications.onDictionaryViewControllerDidLoad.rawValue)
    static let onWillDisappear = Notification.Name(Notifications.onDictionaryViewControllerWillDisappear.rawValue)
    
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
    var entryListManager: EntryListManager!
    var uiManager: UIManager!
    var voiceCommandEngine: VoiceCommandEngine!
    
    // MARK: - ViewController References
    weak var entryTableViewController: EntryTableViewController?
    weak var detailViewController: DetailViewController?
    
    // MARK: - Data
    
    var sections: [DictionarySection] = [
        DictionarySection(
            title: ["Parts of Speech"],
            details: "The building blocks of voice commands on Lingual.",
            isAccordion: false,
            lines: [
                DictionaryLine(
                    title: "Object",
                    body: "The entity of interest e.g. \"selection\""
                ),
                DictionaryLine(
                    title: "Action",
                    body: "The interaction you desire to perform on the object e.g. \"shift\""
                ),
                DictionaryLine(
                    title: "Direction",
                    body: "An optional modifier that resolves spatial ambiguity in spatial commands. e.g. \"right\""
                )
            ]
        ),
        DictionarySection(
            title: ["Application Modes"],
            details: "An exhaustive list of all the possible states Lingual can enter.",
            isAccordion: false,
            lines: [
                DictionaryLine(
                    title: "Selection Mode",
                    body: "Entered upon speech selection while editing an entry. Sonically this is represented by a looping audio section."
                ),
                DictionaryLine(
                    title: "Playback Mode",
                    body: "Entered upon playback of captured speech. In this mode, captured speech is presented back in its natural spoken form."
                ),
                DictionaryLine(
                    title: "Echo Mode",
                    body: "Entered upon echoing of captured speech. In this mode, captured speech is presented back as computer-synthesized speech."
                ),
                DictionaryLine(
                    title: "Dialog Mode",
                    body: "Entered upon the activation of the dialog, such as when deleting an entry. Prompts for a response chosen from a restricted set of voice commands."
                ),
                DictionaryLine(
                    title: "Walk Mode",
                    body: "Entered upon the completion of the walk voice command. Selects a single word and loops its natural spoken form followed by the computer-synthesized form, allowing for cross-comparison. Shifting between words is user-controlled."
                ),
                DictionaryLine(
                    title: "Run Mode",
                    body: "Entered upon the completion of the run voice command. Advances automatically through a passage playing its natural spoken form followed by the computer-synthesized form, allowing for cross-comparison."
                )
            ]
        ),
        DictionarySection(
            title: ["Vocabulary"],
            details: "An exhaustive list of all objects and their actions.",
            isAccordion: false
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.ENTRY.value().uppercased()],
            details: "An audiovisual record of speech.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PLAY.value().uppercased()],
                    description: "Initiate playback of a selected entry.",
                    example: "Play entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PAUSE.value().uppercased(), "FREEZE"],
                    description: "Pause listening for new entry speech.",
                    example: "Pause entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.CREATE.value().uppercased(), "NEW"],
                    description: "Add a new entry.",
                    example: "Create entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.START.value().uppercased()],
                    description: "Initiate listening for new entry speech.",
                    example: "Start entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.STOP.value().uppercased(), VoiceCommandEngine.Token.END.value().uppercased(), VoiceCommandEngine.Token.FINISH.value().uppercased()],
                    description: "Terminate listening for new entry speech.",
                    example: "Stop entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.RESUME.value().uppercased(), VoiceCommandEngine.Token.CONTINUE.value().uppercased()],
                    description: "Return to listening for new entry speech after pause.",
                    example: "Resume entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DELETE.value().uppercased()],
                    description: "Remove selected entry.",
                    example: "Delete entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ECHO.value().uppercased()],
                    description: "Initiate echo of a selected entry.",
                    example: "Echo entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.RUN.value().uppercased()],
                    description: "Initiate running a selected entry.",
                    example: "Run entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.WALK.value().uppercased()],
                    description: "Initiate walking a selected entry.",
                    example: "Walk entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EDIT.value().uppercased()],
                    description: "Initiate listening for entry speech in an existing entry.",
                    example: "Edit entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXPORT.value().uppercased()],
                    description: "Initiate audio or text export for selected entry.",
                    example: "Export entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ENTER.value().uppercased(), "OPEN", "VIEW"],
                    description: "(From the entry list) Navigate into a selected entry.",
                    example: "Enter entry"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXIT.value().uppercased(), "LEAVE", "CLOSE"],
                    description: "(From the entry detail) Navigate out of a selected entry back to the entry list.",
                    example: "Exit entry"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.ENTRY_LIST.value().uppercased(), VoiceCommandEngine.Token.LIST.value().uppercased()],
            details: "A list of entries.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.RUN.value().uppercased()],
                    description: "Initiate running the entry list.",
                    example: "Run list"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.WALK.value().uppercased()],
                    description: "Initiate walking the entry list.",
                    example: "Walk list"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ENTER.value().uppercased()],
                    description: "(From an entry) Navigate out of a selected entry back to the entry list.",
                    example: "Enter entry list"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.ECHO.value().uppercased()],
            details: "The system’s interpreted understanding of entry speech, delivered aurally as computer-synthesized audio.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PLAY.value().uppercased(), VoiceCommandEngine.Token.START.value().uppercased()],
                    description: "Initiate echo of a selected entry.",
                    example: "Play echo"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PAUSE.value().uppercased(), "FREEZE"],
                    description: "Pause ongoing echo.",
                    example: "Pause echo"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.STOP.value().uppercased(), VoiceCommandEngine.Token.END.value().uppercased(), VoiceCommandEngine.Token.FINISH.value().uppercased()],
                    description: "Terminate ongoing echo.",
                    example: "Stop echo"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.RESUME.value().uppercased(), VoiceCommandEngine.Token.CONTINUE.value().uppercased()],
                    description: "Return to echo after pause.",
                    example: "Resume echo"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.INCREASE.value().uppercased()],
                    description: "Accelerates the rate at which echo and system speech is delivered.",
                    example: "Increase echo"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DECREASE.value().uppercased()],
                    description: "Decelerates the rate at which echo and system speech is delivered.",
                    example: "Decrease echo"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ADJUST.value().uppercased()],
                    description: "Modifies (up or down) the rate at which echo is delivered. Requires a Direction: <UP>, <DOWN>",
                    example: "Adjust echo up"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.PLAYBACK.value().uppercased()],
            details: "A natural recording of entry speech, delivered aurally as it was heard at capture time.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PAUSE.value().uppercased(), "FREEZE"],
                    description: "Pause ongoing playback.",
                    example: "Pause playback"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.RESUME.value().uppercased(), VoiceCommandEngine.Token.CONTINUE.value().uppercased()],
                    description: "Return to playback after pause.",
                    example: "Resume playback"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.STOP.value().uppercased(), VoiceCommandEngine.Token.END.value().uppercased(), VoiceCommandEngine.Token.FINISH.value().uppercased()],
                    description: "Terminate ongoing playback.",
                    example: "Stop playback"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.INCREASE.value().uppercased()],
                    description: "Accelerates the rate at which playback is delivered.",
                    example: "Increase playback"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DECREASE.value().uppercased()],
                    description: "Decelerates the rate at which playback is delivered.",
                    example: "Decrease playback"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ADJUST.value().uppercased()],
                    description: "Modifies (up or down) the rate at which playback is delivered. Requires a Direction: <UP>, <DOWN>",
                    example: "Adjust playback down"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SKIP.value().uppercased()],
                    description: "Seeks 10 seconds ahead or behind current location during active playback. Requires a Direction: <BACKWARD>, <FORWARD>",
                    example: "Skip forward"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.SELECTION.value().uppercased()],
            details: "A user-defined segment of speech in an entry.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DELETE.value().uppercased()],
                    description: "Removes a selection.",
                    example: "Delete selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.UPDATE.value().uppercased()],
                    description: "Initiates update sequence to replace arbitrarily selected speech.",
                    example: "Update selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.COPY.value().uppercased()],
                    description: "Copies arbitrarily selected speech to clipboard.",
                    example: "Copy selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.CUT.value().uppercased()],
                    description: "Copies arbitrarily selected speech to clipboard and removes it from entry.",
                    example: "Cut selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXPORT.value().uppercased()],
                    description: "Initiate audio or text export for arbitrary selection.",
                    example: "Export selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.RUN.value().uppercased()],
                    description: "Initiate running arbitrary selection.",
                    example: "Run selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.WALK.value().uppercased()],
                    description: "Initiate walking arbitrary selection.",
                    example: "Walk selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ENTER.value().uppercased(), VoiceCommandEngine.Token.START.value().uppercased(), "MAKE", "BEGIN"],
                    description: "Enter selection mode by selecting word nearest to speech cursor.",
                    example: "Make selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.REMOVE.value().uppercased(), "CLEAR", VoiceCommandEngine.Token.END.value().uppercased(), VoiceCommandEngine.Token.STOP.value().uppercased(), VoiceCommandEngine.Token.FINISH.value().uppercased(), VoiceCommandEngine.Token.EXIT.value().uppercased()],
                    description: "Exits selection mode.",
                    example: "Remove selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXPAND.value().uppercased()],
                    description: "Extends selection by integrating neighboring words.",
                    example: "Expand selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.REDUCE.value().uppercased()],
                    description: "Shrinks selection by releasing boundary words.",
                    example: "Reduce selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PLAY.value().uppercased()],
                    description: "Initiate playback of arbitrary selection.",
                    example: "Play selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ECHO.value().uppercased()],
                    description: "Initiate echo of arbitrary selection.",
                    example: "Echo selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SHIFT.value().uppercased(), "MOVE"],
                    description: "Advances arbitrary selection behind or ahead of current selection. Requires a Direction: <LEFT | BACKWARD | DOWN | PREVIOUS>, <RIGHT | FORWARD | UP | NEXT>",
                    example: "Shift left"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PASTE.value().uppercased()],
                    description: "Inserts selection stored in clipboard at location of cursor.",
                    example: "Paste selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.INCREASE.value().uppercased()],
                    description: "Accelerates the rate of arbitrary selection playback (in addition to the playback rate)",
                    example: "Increase selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DECREASE.value().uppercased()],
                    description: "Decelerates the rate of arbitrary selection playback (in addition to the playback rate)",
                    example: "Decrease selection"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ADJUST.value().uppercased()],
                    description: "Modifies (up or down) the rate of arbitrary selection playback. Requires a Direction: <UP>, <DOWN>",
                    example: "Adust selection down"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.WORD.value().uppercased()],
            details: "A word selection in an entry.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SELECT.value().uppercased(), VoiceCommandEngine.Token.ENTER.value().uppercased()],
                    description: "Enter selection mode by selecting word nearest to speech cursor.",
                    example: "Select word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DELETE.value().uppercased()],
                    description: "Removes word.",
                    example: "Delete word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.UPDATE.value().uppercased()],
                    description: "Initiates update sequence to replace word.",
                    example: "Update word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.COPY.value().uppercased()],
                    description: "Copies word to clipboard.",
                    example: "Copy word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.CUT.value().uppercased()],
                    description: "Copies word to clipboard and removes it from entry.",
                    example: "Cut word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXPORT.value().uppercased()],
                    description: "Initiate audio or text export for word.",
                    example: "Export word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PLAY.value().uppercased()],
                    description: "Initiate playback of word.",
                    example: "Play word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ECHO.value().uppercased()],
                    description: "Initiate echo of word.",
                    example: "Echo word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SHIFT.value().uppercased(), "MOVE"],
                    description: "Advances to word behind or ahead of current word. Requires a Direction: <LEFT | BACKWARD | DOWN | PREVIOUS>, <RIGHT | FORWARD | UP | NEXT>",
                    example: "Next word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.INCREASE.value().uppercased()],
                    description: "Accelerates the rate of word playback (in addition to the playback rate)",
                    example: "Increase word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DECREASE.value().uppercased()],
                    description: "Decelerates the rate of word playback (in addition to the playback rate)",
                    example: "Decrease word"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ADJUST.value().uppercased()],
                    description: "Modifies (up or down) the rate of word playback. Requires a Direction: <UP>, <DOWN>",
                    example: "Adjust word down"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.SENTENCE.value().uppercased()],
            details: "A sentence selection in an entry.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SELECT.value().uppercased(), VoiceCommandEngine.Token.ENTER.value().uppercased()],
                    description: "Enter selection mode by selecting sentence nearest to speech cursor.",
                    example: "Select sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DELETE.value().uppercased()],
                    description: "Removes sentence.",
                    example: "Delete sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.UPDATE.value().uppercased()],
                    description: "Initiates update sequence to replace sentence.",
                    example: "Update sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.COPY.value().uppercased()],
                    description: "Copies sentence to clipboard.",
                    example: "Copy sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.CUT.value().uppercased()],
                    description: "Copies sentence to clipboard and removes it from entry.",
                    example: "Cut sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXPORT.value().uppercased()],
                    description: "Initiate audio or text export for sentence.",
                    example: "Export sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.RUN.value().uppercased()],
                    description: "Initiate running sentence.",
                    example: "Run sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.WALK.value().uppercased()],
                    description: "Initiate walking sentence.",
                    example: "Walk sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PLAY.value().uppercased()],
                    description: "Initiate playback of sentence.",
                    example: "Play sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ECHO.value().uppercased()],
                    description: "Initiate echo of sentence.",
                    example: "Echo sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SHIFT.value().uppercased(), "MOVE"],
                    description: "Advances to sentence behind or ahead of current word. Requires a Direction: <LEFT | BACKWARD | DOWN | PREVIOUS>, <RIGHT | FORWARD | UP | NEXT>",
                    example: "Next sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.INCREASE.value().uppercased()],
                    description: "Accelerates the rate of sentence playback (in addition to the playback rate)",
                    example: "Increase sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DECREASE.value().uppercased()],
                    description: "Decelerates the rate of sentence playback (in addition to the playback rate)",
                    example: "Decrease sentence"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ADJUST.value().uppercased()],
                    description: "Modifies (up or down) the rate of sentence playback. Requires a Direction: <UP>, <DOWN>",
                    example: "Adjust sentence down"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.PARAGRAPH.value().uppercased(), "PASSAGE", "SECTION"],
            details: "A paragraph selection in an entry.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SELECT.value().uppercased(), VoiceCommandEngine.Token.ENTER.value().uppercased()],
                    description: "Enter selection mode by selecting paragraph nearest to speech cursor.",
                    example: "Select paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DELETE.value().uppercased()],
                    description: "Removes paragraph.",
                    example: "Delete paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.UPDATE.value().uppercased()],
                    description: "Initiates update sequence to replace paragraph.",
                    example: "Update paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.COPY.value().uppercased()],
                    description: "Copies paragraph to clipboard.",
                    example: "Copy paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.CUT.value().uppercased()],
                    description: "Copies paragraph to clipboard and removes it from entry.",
                    example: "Cut paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXPORT.value().uppercased()],
                    description: "Initiate audio or text export for paragraph.",
                    example: "Export paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.RUN.value().uppercased()],
                    description: "Initiate running paragraph.",
                    example: "Run paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.WALK.value().uppercased()],
                    description: "Initiate walking paragraph.",
                    example: "Walk paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PLAY.value().uppercased()],
                    description: "Initiate playback of paragraph.",
                    example: "Play paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ECHO.value().uppercased()],
                    description: "Initiate echo of paragraph.",
                    example: "Echo paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SHIFT.value().uppercased(), "MOVE"],
                    description: "Advances to paragraph behind or ahead of current word. Requires a Direction: <LEFT | BACKWARD | DOWN | PREVIOUS>, <RIGHT | FORWARD | UP | NEXT>",
                    example: "Next paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.INCREASE.value().uppercased()],
                    description: "Accelerates the rate of paragraph playback (in addition to the playback rate)",
                    example: "Increase paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DECREASE.value().uppercased()],
                    description: "Decelerates the rate of paragraph playback (in addition to the playback rate)",
                    example: "Decrease paragraph"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ADJUST.value().uppercased()],
                    description: "Modifies (up or down) the rate of paragraph playback. Requires a Direction: <UP>, <DOWN>",
                    example: "Adjust paragraph down"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.SELECTION_UPDATE.value().uppercased()],
            details: "A staged update to a selection, created during the selection update action.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ACCEPT.value().uppercased()],
                    description: "Commits selection update in the place of current selection.",
                    example: "Accept"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.REDO.value().uppercased()],
                    description: "Discards selection update and initiates listening for new selection update.",
                    example: "Redo"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.COMMIT.value().uppercased()],
            details: "The last passage of speech that the system captured while listening for new speech.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PLAY.value().uppercased()],
                    description: "Initiate playback of last commit.",
                    example: "Play commit"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ECHO.value().uppercased()],
                    description: "Initiate echo of last commit.",
                    example: "Echo commit"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SELECT.value().uppercased()],
                    description: "Enter selection mode by selecting last commit.",
                    example: "Select commit"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ROLLBACK.value().uppercased(), VoiceCommandEngine.Token.DELETE.value().uppercased(), "REVERSE"],
                    description: "Discards last committed speech.",
                    example: "Delete commit"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.WALK.value().uppercased()],
                    description: "Initiate walking last commit.",
                    example: "Walk commit"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.RUN.value().uppercased()],
                    description: "Initiate running last commit.",
                    example: "Run commit"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.VOLUME.value().uppercased()],
            details: "The loudness of device sound.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.INCREASE.value().uppercased()],
                    description: "Raises the loudness of device sound.",
                    example: "Increase volume"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DECREASE.value().uppercased()],
                    description: "Lowers the loudness of device sound.",
                    example: "Decrease volume"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ADJUST.value().uppercased()],
                    description: "Adjusts (up or down) the loudness of device sound. Requires a Direction: <UP>, <DOWN>",
                    example: "Adjust volume up"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.PLAYBACK_RATE.value().uppercased()],
            details: "The rate at which playback is delivered.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.INCREASE.value().uppercased()],
                    description: "Accelerates the rate at which playback is delivered.",
                    example: "Increase playback rate"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DECREASE.value().uppercased()],
                    description: "Decelerates the rate at which playback is delivered.",
                    example: "Decrease playback rate"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ADJUST.value().uppercased()],
                    description: "Modifies (up or down) the rate at which playback is delivered. Requires a Direction: <UP>, <DOWN>",
                    example: "Adjust playback rate up"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.ECHO_RATE.value().uppercased()],
            details: "The rate at which echo and system speech is delivered.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.INCREASE.value().uppercased()],
                    description: "Accelerates the rate at which echo and system speech is delivered.",
                    example: "Increase echo rate"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.DECREASE.value().uppercased()],
                    description: "Decelerates the rate at which echo and system speech is delivered.",
                    example: "Decrease echo rate"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ADJUST.value().uppercased()],
                    description: "Modifies (up or down) the rate at which echo is delivered. Requires a Direction: <UP>, <DOWN>",
                    example: "Adjust echo rate down"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.SELECTION_RATE.value().uppercased()],
            details: "The rate at which a selection is played back (in addition to the playback rate).",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                   tokens: [VoiceCommandEngine.Token.INCREASE.value().uppercased()],
                   description: "Accelerates the rate of selection playback (in addition to the playback rate).",
                   example: "Increase selection rate"
               ),
               DictionaryAction(
                   tokens: [VoiceCommandEngine.Token.DECREASE.value().uppercased()],
                   description: "Decelerates the rate of selection playback (in addition to the playback rate).",
                   example: "Decrease selection rate"
               ),
               DictionaryAction(
                   tokens: [VoiceCommandEngine.Token.ADJUST.value().uppercased()],
                   description: "Modifies (up or down) the rate of selection playback. Requires a Direction: <UP>, <DOWN>",
                   example: "Adjust selection rate down"
               )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.RUN.value().uppercased()],
            details: "A mode that advances automatically through a passage playing it’s natural spoken form followed by the computer-synthesized form, allowing for cross-comparison.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PAUSE.value().uppercased(), "FREEZE"],
                    description: "Exits out of ongoing run into walk mode.",
                    example: "Pause run"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.STOP.value().uppercased(), VoiceCommandEngine.Token.REMOVE.value().uppercased(), VoiceCommandEngine.Token.END.value().uppercased(), VoiceCommandEngine.Token.FINISH.value().uppercased(), VoiceCommandEngine.Token.EXIT.value().uppercased()],
                    description: "Terminates ongoing run.",
                    example: "Exit run"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.WALK.value().uppercased()],
            details: "A mode that selects a single word and loops it’s natural spoken form followed by the computer-synthesized form, allowing for cross-comparison. Shifting between words is user-controlled.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SHIFT.value().uppercased(), "MOVE"],
                    description: "Adjusts selection to the word behind or ahead of current selection. Requires a Direction: <LEFT | BACKWARD | DOWN | PREVIOUS>, <RIGHT | FORWARD | UP | NEXT>",
                    example: "Shift right"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXIT.value().uppercased(), "LEAVE"],
                    description: "Terminates ongoing walk.",
                    example: "Exit walk"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.ANCHOR.value().uppercased(), VoiceCommandEngine.Token.BEGINNING.value().uppercased(), VoiceCommandEngine.Token.START.value().uppercased()],
            details: "(During selection mode) The beginning of the selection.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SHIFT.value().uppercased(), "MOVE"],
                    description: "Extends of shrinks selection by releasing or integrating first word/first word’s neighbor. Requires a Direction: <LEFT | BACKWARD | DOWN| PREVIOUS | OUTWARD>, <RIGHT | FORWARD | UP | NEXT | INWARD>",
                    example: "Shift start left"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.FOCUS.value().uppercased(), VoiceCommandEngine.Token.END.value().uppercased(), VoiceCommandEngine.Token.FINISH.value().uppercased()],
            details: "(During selection mode) The end of the selection.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.SHIFT.value().uppercased(), "MOVE"],
                    description: "Extends of shrinks selection by releasing or integrating last word/last word’s neighbor. Requires a Direction: <LEFT | BACKWARD | DOWN| PREVIOUS | INWARD>, <RIGHT | FORWARD | UP | NEXT | OUTWARD>",
                    example: "Shift end right"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.CLIPBOARD.value().uppercased()],
            details: "Stores selected speech that has been copied or cut.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.INSPECT.value().uppercased(), "PREVIEW", "CHECK"],
                    description: "Playback speech stored in clipboard.",
                    example: "Preview clipboard"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.PASTE.value().uppercased(), "FREEZE"],
                    description: "Inserts clipboard speech at location of cursor.",
                    example: "Paste clipboard"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.AUDIO.value().uppercased()],
            details: "An audio representation of entry speech.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXPORT.value().uppercased()],
                    description: "(During export process) Represents audio export format.",
                    example: "Export audio"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.TEXT.value().uppercased()],
            details: "A textual representation of entry speech.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXPORT.value().uppercased()],
                    description: "(During export process) Represents text export format.",
                    example: "Export text"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.DICTIONARY.value().uppercased()],
            details: "A reference for Lingual voice commands.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.ENTER.value().uppercased(), "OPEN", "VIEW"],
                    description: "Navigate to the dictionary",
                    example: "Export text"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.EXIT.value().uppercased(), "LEAVE", "CLOSE"],
                    description: "Navigate out of the dictionary back to entry list.",
                    example: "Export text"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.CHANGE.value().uppercased()],
            details: "The last modification made while listening for new entry speech.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.UNDO.value().uppercased()],
                    description: "Discards last committed speech.",
                    example: "Undo"
                ),
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.REDO.value().uppercased()],
                    description: "Reapplies last undone change.",
                    example: "Redo"
                )
            ]
        ),
        DictionarySection(
            title: [VoiceCommandEngine.Token.DIALOG.value().uppercased()],
            details: "A mode that prompts for a response chosen from a restricted set of voice commands.",
            isAccordion: false,
            isExpanded: false,
            actions: [
                DictionaryAction(
                    tokens: [VoiceCommandEngine.Token.CANCEL.value().uppercased()],
                    description: "Closes active dialog.",
                    example: "Cancel"
                )
            ]
        ),
        DictionarySection(
            title: ["Special Cases"],
            details: "Notable features of Lingual's voice command grammar.",
            isAccordion: false,
            lines: [
                DictionaryLine(
                    title: "Orderless",
                    body: "Tokens can be uttered in any order. e.g. \"PLAY ENTRY\" vs \"ENTRY PLAY\""
                ),
                DictionaryLine(
                    title: "Supports padded statements",
                    body: "Padded voice commands are permitted, allowing you to include “filler” words between tokens. e.g. \"Please <START> an <ENTRY>\""
                ),
                DictionaryLine(
                    title: "Object Omission",
                    body: "When in an “object mode”, such as when we have selected speech, omitting the object is permitted. e.g. \"SHIFT WALK RIGHT\" -> \"SHIFT RIGHT\""
                ),
                DictionaryLine(
                    title: "Action Omission",
                    body: "If an object has only one action with a direction, including a direction and omitting the action token is permitted. e.g. \"SHIFT WALK RIGHT\" -> \"WALK RIGHT\""
                ),
                DictionaryLine(
                    title: "Action Omission",
                    body: "If an object has a single action, omitting the action token is permitted. One must still include any required direction. e.g. \"EXPORT AUDIO\" -> \"AUDIO\""
                ),
                DictionaryLine(
                    title: "Combining Special Cases",
                    body: "Object Omission and Action Omission can be used simultaneously. e.g. \"SHIFT WALK RIGHT\" -> \"RIGHT\""
                ),
                DictionaryLine(
                    title: "Undo/Redo",
                    body: "The <CHANGE> token can be omitted when calling undo or redo."
                )
            ]
        ),
    ]
    
    // MARK: - Lifecycle Methods
    
    override func viewWillAppear(_ animated: Bool) {
        print("===== Dictionary View Controller: View Will Appear =====")
        super.viewWillAppear(animated)
        
        // Set automatic dimensions for row height
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = UITableView.automaticDimension
        
        // reload table
        self.reloadTable()
        
        DispatchQueue.main.async { [weak self] in
            if let indexPath = self?.tableView.indexPathForSelectedRow {
                self!.tableView.deselectRow(at: indexPath, animated: true)
            }
        }
        
        self.configureNotificationObservers()
        
        if AVAudioSession.isHeadphonesConnected && !self.speechRecognition.isListeningForSpeech {
            // Begin Nature Sounds
            soundEngine.startNatureAmbience()
        }
        
        let navigationController = Utils.getNavigationController()
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.navigationItem.largeTitleDisplayMode = .always
        self.navigationItem.title = "Dictionary"
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
        print("===== Dictionary View Controller: View Did Load =====")
        super.viewDidLoad()
        
        let navigationController = Utils.getNavigationController()
        DispatchQueue.main.async {
            // add table view buttons
            navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = []
        }
        
        // Register the custom header view.
        self.tableView.register(DictionaryViewTableHeader.self, forHeaderFooterViewReuseIdentifier: "DictionaryViewTableHeader")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        print("===== View Controller: View Will Disappear =====")
        super.viewWillDisappear(animated)
    
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
        
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
            name: SpeechRecognitionEngine.onStoppedListeningForCommands,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(onStoppedListening(notification:)),
            name: SpeechRecognitionEngine.onStoppedListeningForSpeech,
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
            selector: #selector(onEntryAudioExported(notification:)),
            name: EntryManager.onEntryAudioExported,
            object: nil
        )
    }
    
    @objc func onEntryTableViewDidLoad(notification: Notification) {
        print("===== Dictionary View Controller: On Entry Table View Did Load =====")
        self.entryTableViewController = storyboard?.instantiateViewController(withIdentifier: "EntryTableViewController") as? EntryTableViewController
    }
    
    @objc func onDetailViewDidLoad(notification: Notification) {
        print("===== Dictionary View Controller: On Detail View Did Load =====")
        self.detailViewController = storyboard?.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController
    }
    
    @objc func onEntryTableViewWillDisappear(notification: Notification) {
        print("===== Dictionary View Controller: On View Will Disappear =====")
        self.entryTableViewController = nil
    }
    
    @objc func onDetailViewWillDisappear(notification: Notification) {
        print("===== Dictionary View Controller: On Detail View Will Disappear =====")
        self.detailViewController = nil
    }
    
    @objc func appMovedToBackground() {
        print("===== Dictionary View Controller: App Moved to Background =====")
        DispatchQueue.main.async { [weak self] in
            if self == nil {
                return
            }
            // keep recording outside of app if entry started
            if self != nil && !self!.speechRecognition.isListeningForSpeech {
                self?.performSegue(withIdentifier: Segues.moveFromDictionaryToEntryTable.rawValue, sender: nil)
            }
        }
    }
    
    @objc func audioSessionRouteChange(notification: Notification) {
        print("===== Dictionary View Controller: Audio Session Route Change =====")
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
        }
        print("\tReason: ", reason)

        // Switch over the route change reason.
        switch reason {
        case .newDeviceAvailable: // New device found.
            if AVAudioSession.isHeadphonesConnected && !self.speechRecognition.isListeningForSpeech {
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
        print("===== Dictionary View Controller: Handle Interruption =====")
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
        print("===== Dictionary View Controller: Handle Secondary Audio =====")
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
        // print("===== View Controller: On Pitch Update =====")
        DispatchQueue.main.async { [weak self] in
            if self == nil {
                return
            }
            
            let pitchDatum = notification.userInfo!["pitch"] as? PitchDatum
            
            if let pitch = pitchDatum?.pitch,
               self?.pitchLabel == nil &&
                !self!.speechPlayer.isPlayingEntry &&
                !self!.notifications.isPresentingVisualNotification
            {
                let navigationController = Utils.getNavigationController()
                navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = [
                    Utils.getPitchLabel(
                        pitchText: pitch.note.string,
                        font: UIFont.systemFont(ofSize: Utils.DEFAULT_FONT_SIZE, weight: .bold)
                    )
                ]
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
    
    @objc func onStartedListeningForCommands(notification: Notification) {
        print("===== Dictionary View Controller: On Started Listening For Commands =====")
        Utils.onStartedListeningForCommands(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStartedListeningForSpeech(notification: Notification) {
        print("===== Dictionary View Controller: On Started Listening For Speech =====")
        Utils.onStartedListeningForSpeech(
            notification: notification,
            entry: self.entryManager.currentEntry,
            speechRecognition: self.speechRecognition,
            selectionCursor: self.selectionCursor
        )
    }
    
    @objc func onPausedListening(notification: Notification) {
        print("===== Dictionary View Controller: On Paused Listening =====")
        Utils.onPausedListening(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStoppedListening(notification: Notification) {
        print("===== Dictionary View Controller: On Stopped Listening =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onStoppedListening(
                notification: notification,
                speechRecognition: self!.speechRecognition,
                soundIntensityIndicatorHeight: self!.soundIntensityIndicatorHeight,
                pitchLabel: self!.pitchLabel
            )
        }
    }
    
    @objc func onEntryListenStop(notification: Notification) {
        print("===== Dictionary View Controller: On Entry Listen Stop =====")
        Utils.onEntryStop(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
    }
    
    @objc func onStartTimedNotification(notification: Notification) {
        print("===== Dictionary View Controller: On Start Timed Notification =====")
        Utils.onStartTimedNotification(
            notification: notification,
            speechRecognition: self.speechRecognition
        )
        
        // Remove pitch label while presenting notification
        DispatchQueue.main.async {
            let navigationController = Utils.getNavigationController()
            navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = []
        }
    }
    
    @objc func onStopNotification(notification: Notification) {
        print("===== Dictionary View Controller: On Stop Timed Notification =====")
        Utils.onStopNotification(
            notification: notification,
            entry: self.entryManager.currentEntry,
            speechRecognition: self.speechRecognition,
            selectionCursor: self.selectionCursor
        )
    }
    
    @objc func onStartIndefiniteNotification(notification: Notification) {
        print("===== Dictionary View Controller: On Start Indefinite Notification =====")
        Utils.onStartIndefiniteNotification(
            notification: notification,
            state: self.state,
            speechRecognition: self.speechRecognition
        )
        
        // Remove pitch label while presenting notification
        DispatchQueue.main.async {
            let navigationController = Utils.getNavigationController()
            navigationController?.visibleViewController?.navigationItem.rightBarButtonItems = []
        }
    }
    
    @objc func onEntryComplete(notification: Notification) {
        print("===== Dictionary View Controller: On Entry Complete =====")
        Utils.onEntryComplete(
            notification: notification,
            speechRecognition: self.speechRecognition,
            soundIntensityIndicatorHeight: self.soundIntensityIndicatorHeight
        )
    }
    
    @objc func onSpeechStartPlaying(notification: Notification) {
        print("===== Dictionary View Controller: On Start Start Playing =====")
//        DispatchQueue.main.async { [weak self] in
        DispatchQueue.main.async {
            Utils.onSpeechStartPlaying(notification: notification)
        }
    }
    
    @objc func onSpeechBoundaryCrossed(notification: Notification) {
        print("===== Dictionary View Controller: On Speech Boundary Crossed =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechBoundaryCrossed(
                notification: notification,
                speechPlayer: self!.speechPlayer,
                pitchLabel: self!.pitchLabel
            )
        }
    }
    
    @objc func onSpeechSecondElapsed(notification: Notification) {
        print("===== Dictionary View Controller: On Speech Second Elapsed =====")
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
        print("===== Dictionary View Controller: On Speech Stop Playing =====")
        DispatchQueue.main.async { [weak self] in
            Utils.onSpeechStopPlaying(
                notification: notification,
                speechRecognition: self!.speechRecognition,
                entryManager: self!.entryManager
            )
        }
    }
    
    // Reference: https://stackoverflow.com/questions/50128462/how-to-save-document-to-files-app-in-swift
    @objc func onEntryAudioExported(notification: Notification) {
        print("===== Dictionary View Controller: On Entry Audio Exported =====")
        DispatchQueue.main.async {
            Utils.onEntryAudioExported(
                notification: notification,
                vc: self
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
        case .moveFromDictionaryToEntryTable:
            print(">>>>> Segue from DictionaryViewController to EntryTableViewController >>>>>")
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
            self.notifications.executeFeedback(
                visualMessage: "Entry List",
                audioMessage: "Navigated to entry list.",
                discardPrior: true,
                withHaptics: true
            )
        case .moveFromEntryTableToDetail:
            print (">>>>> [Invalid Segue within ViewController] from EntryTableViewControlller to DetailViewController >>>>>")
        case .moveFromDetailToEntryTable:
            print (">>>>> [Invalid Segue within ViewController] from DetailViewControlller to EntryTableViewController >>>>>")
        case .moveFromEntryTableToDictionary:
            print (">>>>> [Invalid Segue within DictionaryViewController] from EntryTableViewControlller to DictionaryViewController >>>>>")
        case .noIdentifier:
            print (">>>>> [Error] No Segue Identifier in ViewController >>>>>")
        }
    }
    
    // MARK: - Segues
    
    @IBAction func unwindToDictionary(segue: UIStoryboardSegue) {
        
    }
    
    // MARK: - Table View
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        
        if let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "DictionaryViewTableHeader") as? DictionaryViewTableHeader {
            view.title.text = self.sections[section].getTitle()
            view.details.text = self.sections[section].details
            view.button.tag = section
            
            if self.sections[section].isAccordion {
                view.button.addTarget(self, action: #selector(self.toggleAccordion), for: .touchUpInside)
            }
            
            if self.sections[section].actions == nil && self.sections[section].lines == nil {
                view.contentView.backgroundColor = UIColor.white
            } else {
                view.contentView.backgroundColor = UIColor.systemGray6
//                view.contentView.addBorder(vBorder: .bottom, color: UIColor.systemGray3, width: 1)
            }
            return view
        }

        return DictionaryViewTableHeader()
    }
    
    @objc func toggleAccordion(button: UIButton) {
        let sectionIndex = button.tag
        var indexPaths = [IndexPath]()
        let section = self.sections[sectionIndex]
        if let lines = section.lines {
            for row in lines.indices {
                let indexPath = IndexPath(row: row, section: sectionIndex)
                indexPaths.append(indexPath)
            }
        } else if let actions = section.actions {
            for row in actions.indices {
                let indexPath = IndexPath(row: row, section: sectionIndex)
                indexPaths.append(indexPath)
            }
        }
        
        let isExpanded = self.sections[sectionIndex].isExpanded
        self.sections[sectionIndex].isExpanded = !isExpanded
        
        if isExpanded {
            tableView.deleteRows(at: indexPaths, with: .fade)
        } else {
            tableView.insertRows(at: indexPaths, with: .fade)
        }
    }
    
    override func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        return 110
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if let actions = self.sections[section].actions, self.sections[section].isExpanded || !self.sections[section].isAccordion  {
            return actions.count
        } else if let lines = self.sections[section].lines, self.sections[section].isExpanded || !self.sections[section].isAccordion {
            return lines.count
        } else {
            return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Get reusable cell
        
        if let cell = tableView.dequeueReusableCell(withIdentifier: "DictionaryViewTableCell") as? DictionaryViewTableCell {
            let section = self.sections[indexPath.section]
            if let lines = section.lines {
                cell.header.text = lines[indexPath.row].title
                cell.body.text = lines[indexPath.row].body
                cell.supportingText.text = ""
                cell.bodyBottomConstraint.constant = 15
            } else if let actions = section.actions {
                cell.header.text = actions[indexPath.row].getName()
                cell.body.text = actions[indexPath.row].description
                cell.supportingText.text = "\"\(actions[indexPath.row].example)\""
                cell.bodyBottomConstraint.constant = 40
            }
            
            return cell
        }
        return DictionaryViewTableCell()
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Give haptic feedback
        if self.sections[indexPath.section].isAccordion {
            hapticEngine.success()
        }
    }
    
    // Reference: https://stackoverflow.com/questions/42717173/uitableviewcell-auto-height-based-on-amount-of-uilabel-text/42717313
    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 120
    }
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    // MARK: - Methods
    
    func reloadTable() {
        print("===== Dictionary View Controller: Reload Table =====")
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
        }
    }
}
