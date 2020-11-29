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
    
    // EntryTableViewController
    case onEntryTableViewControllerDidLoad
    case onEntryTableViewControllerWillDisappear
    
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
    case onRequestPrepareAudioFile
    case onPitchUpdate
    case onPowerUpdate
    case onSpeechUpdate
    case onWakePhraseDetected
    case onIncorrectWakePhrase
    case onBufferItem
    
    // VoiceCommand
    case onProcessedVoiceCommand
    
    // Entry
    case onRequestToUpdateView
    case onEntryListenUpdate
    case onEntryListenStop
    case onEntryComplete
    case onEntryCommittedBuffer
    
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
    
    // EntryManager
    case onCreatedEntry
    case onEntryDeleted
    case onSetEntry
    case onExecuteEntryAction
    case onEntryAudioExported
    
    // StorageManager
    case onFetchedStoredState
    
    // SelectionCursor
    case onClipboardChange
    
    // State Manager
    case onFetchedEntries
    case onUndoManagerChange
    
    // UI Manager
    case onReceivedDialogInput
}
