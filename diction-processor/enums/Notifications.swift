//
//  Notifications.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/30/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

enum Notifications: String {
    // ViewController
    case onViewControllerDidLoad
    case onViewControllerWillDisappear
    
    // NoteTableViewController
    case onNoteTableViewControllerDidLoad
    case onNoteTableViewControllerWillDisappear
    
    // DetailViewController
    case onDetailViewControllerDidLoad
    case onDetailViewControllerWillDisappear
    case onChangedPlayerRate
    case onChangedEchoRate
    
    // SpeechRecognitionEngine
    case onStartedListeningForWakePhrase
    case onStoppedListeningForWakePhrase
    case onStartedListeningForCommands
    case onPausedListeningForCommands
    case onStoppedListeningForCommands
    case onStartedListeningForSpeech
    case onPausedListeningForSpeech
    case onStoppedListeningForSpeech
    case onPitchUpdate
    case onPowerUpdate
    case onSpeechUpdate
    case onWakePhraseDetected
    case onIncorrectWakePhrase
    case onBufferItem
    
    // VoiceCommand
    case onProcessedVoiceCommand
    
    // Note
    case onRequestToUpdateView
    case onNoteListenUpdate
    case onNoteListenStop
    case onNoteComplete
    case onNoteCommittedBuffer
    
    // Notification
    case onStartTimedNotification
    case onStartIndefiniteNotification
    case onStopNotification
    
    // SpeechPlayer
    case onStartedPlaying
    case onBoundaryCrossed
    case onSecondElapsed
    case onStoppedPlaying
    
    // SpeechSynthesis
    case onEchoStart
    case onEchoUpdate
    case onEchoFinish
    
    // NoteManager
    case onCreatedNote
    case onNoteDeleted
    case onSetNote
    case onExecuteNoteAction
    case onNoteAudioExported
    
    // StorageManager
    case onFetchedStoredState
    
    // SelectionCursor
    case onClipboardChange
    
    // State Manager
    case onFetchedNotes
    
    // UI Manager
    case onReceivedDialogInput
}
