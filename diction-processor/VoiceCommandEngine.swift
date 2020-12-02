//
//  VoiceCommandEngine.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/24/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

public class VoiceCommandEngine: NSObject {
    // MARK: - Notifications
    
    static let onProcessedVoiceCommand = Notification.Name(Notifications.onProcessedVoiceCommand.rawValue)
    
    // MARK: - App Modules
    
    var speechPlayer: SpeechPlayerEngine
    var selectionCursor: SelectionCursor
    weak var entryManager: EntryManager!
    var uiManager: UIManager
    var speechSynthesis: SpeechSynthesisEngine
    var speechRecognition: SpeechRecognitionEngine
    
    // MARK: - Initialization and Deinitialization
    
    init(
        speechPlayer: SpeechPlayerEngine,
        selectionCursor: SelectionCursor,
        uiManager: UIManager,
        speechSynthesis: SpeechSynthesisEngine,
        speechRecognition: SpeechRecognitionEngine
    ) {
        print("===== Voice Command Engine : Initialization =====")
        self.speechPlayer = speechPlayer
        self.selectionCursor = selectionCursor
        self.uiManager = uiManager
        self.speechSynthesis = speechSynthesis
        self.speechRecognition = speechRecognition
        
        super.init()
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Methods

    func isCommand(query: String) -> (VoiceCommand, [Int])? {
        var actionTokens = [Token]()
        var entityTokens = [Token]()
        var actionEntityTokens = [Token]()
        var spatialRelationTokens = [Token]()

        // Infer entity based on mode of operation
        // Inferred entities can be overrided by another entity when explicitly provided
        //
        // Keep in mind heirarchy of methods
        if self.speechPlayer.isPlayingEntry &&
            !self.selectionCursor.hasSelection && // We could still end playback while in selection, but we don't infer it
            !self.entryManager.isWalkingEntry &&
            !self.entryManager.isRunningEntry
        {
            entityTokens.append(.PLAYBACK)
        } else if self.speechSynthesis.isPlayingEcho &&
            !self.selectionCursor.hasSelection && // We could still end playback while in selection, but we don't infer it
            !self.entryManager.isWalkingEntry &&
            !self.entryManager.isRunningEntry
        {
            actionEntityTokens.append(.ECHO)
        } else if self.selectionCursor.isPromptingForUpdateAcceptance {
            entityTokens.append(.SELECTION_UPDATE)
        } else if self.entryManager.isRunningEntry {
            actionEntityTokens.append(.RUN)
        } else if self.entryManager.isWalkingEntry {
            actionEntityTokens.append(.WALK)
        } else if self.selectionCursor.hasSelection {
            entityTokens.append(.SELECTION)
            entityTokens.append(.SELECTION_RATE)
        } else if self.uiManager.dialogIsVisible {
            // Get other entity tokens from UI Manager
            if let voiceCommandSets = self.uiManager.getActionVoiceCommandSets() {
                // Loop through voice commands
                for set in voiceCommandSets {
                    // Loop through tokens
                    for token in set {
                        if EntityToken.contains(token) && !entityTokens.contains(token) {
                            // Add token to entity list if its an entity
                            entityTokens.append(token)
                        } else if ActionEntityToken.contains(token) && !actionEntityTokens.contains(token) {
                            // Add token to entity list if its an entity
                            actionEntityTokens.append(token)
                        }
                    }
                }
            }
        }
//        } else if let _ = Utils.getNavigationController()?.visibleViewController as? DetailViewController,
//            !self.uiManager.dialogIsVisible &&
//            !self.selectionCursor.hasSelection &&
//            !self.entryManager.isWalkingEntry &&
//            !self.entryManager.isRunningEntry &&
//            !self.speechSynthesis.isPlayingEcho &&
//            !self.speechPlayer.isPlayingEntry &&
//            !self.speechRecognition.isListeningForSpeech
//        {
//            entityTokens.append(.ENTRY)
//        }
        // isUpdatingSelection -> .SELECTION_UPDATE

        // Compute all permutations of two words to find valid tokens
        let bagOfWords = query.lowercased().components(separatedBy: " ")
        
        print("\tBag of Words: ", bagOfWords)
        
        var filteredBagOfWords = [String]()
        // Filter out words that aren't in token library
        for word in bagOfWords {
            if let _ = TokenMap[word] {
                filteredBagOfWords.append(word)
            }
        }
        
        print("\tFiltered Bag of Words: ", bagOfWords)
        
        let possibleTokens = Utils.permute(
            list: filteredBagOfWords,
            maxWordJoins: 2,
            separator: " "
        )
        
        print("\tPossible Tokens: ", possibleTokens)
        print("\tCount: ", possibleTokens.count)

        var tokenMappings = [Token : String]()
        // Find valid tokens and classify them
        //
        // We also cache token mappings to refer to to extract token indices at the end of method
        // Reference: https://stackoverflow.com/questions/44074794/string-to-enum-mapping-in-swift/44074929
        for possibleToken in bagOfWords {
            if let validToken = TokenMap[possibleToken],
            ActionToken.contains(validToken) &&
            !actionTokens.contains(validToken)
            {
                actionTokens.append(validToken)
                tokenMappings[validToken] = possibleToken
            } else if let validToken = TokenMap[possibleToken],
                EntityToken.contains(validToken) &&
                !entityTokens.contains(validToken)
            {
                entityTokens.append(validToken)
                tokenMappings[validToken] = possibleToken
            } else if let validToken = TokenMap[possibleToken],
                ActionEntityToken.contains(validToken) &&
                !actionEntityTokens.contains(validToken)
            {
                actionEntityTokens.append(validToken)
                tokenMappings[validToken] = possibleToken
            } else if let validToken = TokenMap[possibleToken],
                SpatialRelationToken.contains(validToken) &&
                !spatialRelationTokens.contains(validToken)
            {
                spatialRelationTokens.append(validToken)
                tokenMappings[validToken] = possibleToken
            }
        }
        
        print("\tToken Mappings: ", tokenMappings)

        // Determine if action can be inferred
        // - entity only has one action
        if  actionTokens.count == 0 &&
            entityTokens.count > 0
        {
            for token in entityTokens {
                if let permissibleEntityActions: Set<Token> = PossibleEntityActions[token],
                   let loneAction = permissibleEntityActions.first,
                    permissibleEntityActions.count == 1 && (
                        PossibleEntitySpatialRelations[loneAction] == nil ||
                        PossibleEntitySpatialRelations[loneAction]!.count == 1
                    ) && !actionTokens.contains(loneAction)
                {
                    // If entity only has one action (and one or no spatial relation), we can infer action
                    actionTokens.append(loneAction)
                } else if let permissibleEntityActions: Set<Token> = PossibleEntityActions[token],
                    spatialRelationTokens.count == 1 {
                    // If entity and spatial relation are specified and they are valid, we can infer action
                    for action in permissibleEntityActions {
                        if let possibleEntitySpatialRelations = PossibleEntitySpatialRelations[action],
                           possibleEntitySpatialRelations.contains(spatialRelationTokens[0]) &&
                            !actionTokens.contains(action)
                        {
                            actionTokens.append(action)
                        }
                    }
                }
            }
        } else if actionTokens.count == 0 &&
            actionEntityTokens.count > 0
        {
            for token in actionEntityTokens {
                if let permissibleEntityActions: Set<Token> = PossibleEntityActions[token],
                   let loneAction = permissibleEntityActions.first,
                    permissibleEntityActions.count == 1 && (
                        PossibleEntitySpatialRelations[loneAction] == nil ||
                        PossibleEntitySpatialRelations[loneAction]!.count == 1
                    ) && !actionTokens.contains(loneAction)
                {
                    // If entity only has one action (and one or no spatial relation), we can infer action
                    actionTokens.append(loneAction)
                } else if let permissibleEntityActions: Set<Token> = PossibleEntityActions[token],
                      spatialRelationTokens.count == 1 {
                    // If entity and spatial relation are specified and they are valid, we can infer action
                      for action in permissibleEntityActions {
                          if let possibleEntitySpatialRelations = PossibleEntitySpatialRelations[action],
                             possibleEntitySpatialRelations.contains(spatialRelationTokens[0]) &&
                            !actionTokens.contains(action)
                          {
                              actionTokens.append(action)
                          }
                      }
                  }
            }
        }
        
        // Determine if entity can be inferred
        if actionTokens.contains(.UNDO) || actionTokens.contains(.REDO) {
            entityTokens.append(.CHANGE)
        }

        // Verify we have suitable number of types of tokens to continue
        //
        // If we have an action-entity and no entity, we must have an action and the action-entity functions as an entity
        // If we have an entity and action,
        guard (entityTokens.count == 0 && actionEntityTokens.count > 0 && actionTokens.count > 0) ||
            (entityTokens.count > 0 && actionEntityTokens.count > 0 && actionTokens.count == 0) ||
            (entityTokens.count > 0 && actionTokens.count > 0)
        else {
            return nil
        }
        
        print("\tEntity Tokens: ", entityTokens)
        print("\tAction Entity Tokens: ", actionEntityTokens)
        print("\tAction Tokens: ", actionTokens)
        print("\tSpatial Tokens: ", spatialRelationTokens)

        var viableVoiceCommandSets = [Set<Token>]()

        // Confirm entity action alignment exists
        //
        // Determine if viable action needs a spatial relation and that it exists
        for entity in entityTokens {
            // Check for permissible actions
            if let possibleEntityActions = PossibleEntityActions[entity] {
                let actionTokenSet = Set(actionTokens)
                // Find out if we have provided enough information to match an action with an entity
                let viableEntityActions = possibleEntityActions.intersection(actionTokenSet)
                for action in viableEntityActions {
                    if PossibleEntitySpatialRelations[action] == nil {
                        // No need for spatial relation
                        let voiceCommandSet = Set([entity, action])
                        if let _ = VoiceCommandMap[voiceCommandSet],
                           !viableVoiceCommandSets.contains(voiceCommandSet)
                        {
                            // Voice Command Exists
                            // Add to list of viable voice commands
                            viableVoiceCommandSets.append(voiceCommandSet)
                        }
                    } else if let spatialRelations = PossibleEntitySpatialRelations[action] {
                        // Find out if we have provided enough information to match an spatial relation with an entity and action
                        let viableSpatialRelations = spatialRelations.intersection(spatialRelationTokens)
                        for spatialRelation in viableSpatialRelations {
                            let voiceCommandSet = Set([entity, action, spatialRelation])
                            if let _ = VoiceCommandMap[voiceCommandSet],
                               !viableVoiceCommandSets.contains(voiceCommandSet)
                            {
                                // Voice Command Exists
                                // Add to list of viable voice commands
                                viableVoiceCommandSets.append(voiceCommandSet)
                            }
                        }
                    }
                }
                
                let actionEntityTokenSet = Set(actionEntityTokens)
                // Find out if we have provided enough information to match an action-entity with an entity
                let viableEntityActionEntities = possibleEntityActions.intersection(actionEntityTokenSet)
                for action in viableEntityActionEntities {
                    if PossibleEntitySpatialRelations[action] == nil {
                        // No need for spatial relation
                        let voiceCommandSet = Set([entity, action])
                        if let _ = VoiceCommandMap[voiceCommandSet],
                           !viableVoiceCommandSets.contains(voiceCommandSet)
                        {
                            // Voice Command Exists
                            // Add to list of viable voice commands
                            viableVoiceCommandSets.append(voiceCommandSet)
                        }
                    } else if let spatialRelations = PossibleEntitySpatialRelations[action] {
                        // Find out if we have provided enough information to match an spatial relation with an entity and action
                        let viableSpatialRelations = spatialRelations.intersection(spatialRelationTokens)
                        for spatialRelation in viableSpatialRelations {
                            let voiceCommandSet = Set([entity, action, spatialRelation])
                            if let _ = VoiceCommandMap[voiceCommandSet],
                               !viableVoiceCommandSets.contains(voiceCommandSet)
                            {
                                // Voice Command Exists
                                // Add to list of viable voice commands
                                viableVoiceCommandSets.append(voiceCommandSet)
                            }
                        }
                    }
                }
            }
        }

        for entity in actionEntityTokens {
            // Check for permissible actions
            if let possibleEntityActions = PossibleEntityActions[entity] {
                let actionTokenSet = Set(actionTokens)
                // Find out if we have provided enough information to match an action with an entity
                let viableEntityActions = possibleEntityActions.intersection(actionTokenSet)
                for action in viableEntityActions {
                    if PossibleEntitySpatialRelations[action] == nil {
                        // No need for spatial relation
                        let voiceCommandSet = Set([entity, action])
                        if let _ = VoiceCommandMap[voiceCommandSet],
                           !viableVoiceCommandSets.contains(voiceCommandSet)
                        {
                            // Voice Command Exists
                            // Add to list of viable voice commands
                            viableVoiceCommandSets.append(voiceCommandSet)
                        }
                    } else if let spatialRelations = PossibleEntitySpatialRelations[action] {
                        // Find out if we have provided enough information to match an spatial relation with an entity and action
                        let viableSpatialRelations = spatialRelations.intersection(spatialRelationTokens)
                        for spatialRelation in viableSpatialRelations {
                            let voiceCommandSet = Set([entity, action, spatialRelation])
                            if let _ = VoiceCommandMap[voiceCommandSet],
                               !viableVoiceCommandSets.contains(voiceCommandSet)
                            {
                                // Voice Command Exists
                                // Add to list of viable voice commands
                                viableVoiceCommandSets.append(voiceCommandSet)
                            }
                        }
                    }
                }
            }
        }
        
        print("\tViable Commands: ", viableVoiceCommandSets)

        guard viableVoiceCommandSets.count > 0 else {
            return nil
        }

        // Check all combinations of tokens for all posible valid voice commands
        // Q1: What if there are more than one?
        // A1:Prioritize based on mode

        var voiceCommand: VoiceCommand?
        var voiceCommandSet: Set<Token>?
        if self.speechPlayer.isPlayingEntry &&
            !self.selectionCursor.hasSelection && // We could still end playback while in selection, but we don't infer it
            !self.entryManager.isWalkingEntry &&
            !self.entryManager.isRunningEntry
        {
            // Play Mode
            for commandSet in viableVoiceCommandSets {
                if commandSet.contains(.PLAYBACK) {
                    voiceCommand = VoiceCommandMap[commandSet]
                    voiceCommandSet = commandSet
                    break
                }
            }
        } else if self.speechSynthesis.isPlayingEcho &&
            !self.selectionCursor.hasSelection && // We could still end playback while in selection, but we don't infer it
            !self.entryManager.isWalkingEntry &&
            !self.entryManager.isRunningEntry
        {
            // Echo Mode
            for commandSet in viableVoiceCommandSets {
                if commandSet.contains(.ECHO) {
                    voiceCommand = VoiceCommandMap[commandSet]
                    voiceCommandSet = commandSet
                    break
                }
            }
        } else if self.selectionCursor.isPromptingForUpdateAcceptance {
            // Updating Selection Mode
            for commandSet in viableVoiceCommandSets {
                if commandSet.contains(.SELECTION_UPDATE) {
                    voiceCommand = VoiceCommandMap[commandSet]
                    voiceCommandSet = commandSet
                    break
                }
            }
        } else if self.entryManager.isRunningEntry {
            // Run Mode
            for commandSet in viableVoiceCommandSets {
                if commandSet.contains(.RUN) {
                    voiceCommand = VoiceCommandMap[commandSet]
                    voiceCommandSet = commandSet
                    break
                }
            }
        } else if self.entryManager.isWalkingEntry {
            // Walk Mode
            for commandSet in viableVoiceCommandSets {
                if commandSet.contains(.WALK) {
                    voiceCommand = VoiceCommandMap[commandSet]
                    voiceCommandSet = commandSet
                    break
                }
            }
        } else if self.selectionCursor.hasSelection {
            // Selection Mode
            for commandSet in viableVoiceCommandSets {
                if commandSet.contains(.SELECTION) || commandSet.contains(.SELECTION_RATE) {
                    voiceCommand = VoiceCommandMap[commandSet]
                    voiceCommandSet = commandSet
                    break
                }
            }
        } else if self.uiManager.dialogIsVisible {
            // Dialog Mode
            // Choose first voice command
            if let firstVoiceCommandSet = viableVoiceCommandSets.first,
               let firstVoiceCommand = VoiceCommandMap[firstVoiceCommandSet]
            {
                voiceCommand = firstVoiceCommand
                voiceCommandSet = firstVoiceCommandSet
            }
        } else {
            // Other
            // Choose first voice command
            if let firstVoiceCommandSet = viableVoiceCommandSets.first,
               let firstVoiceCommand = VoiceCommandMap[firstVoiceCommandSet]
            {
                voiceCommand = firstVoiceCommand
                voiceCommandSet = firstVoiceCommandSet
            }
        }

        guard let command = voiceCommand,
           let commandSet = voiceCommandSet else
        {
            return nil
        }
        
        print("\tFinal Command: ", command, commandSet)

        var voiceCommandIndices = [Int]()
        // Get voice command token indices
        for token in commandSet {
            // Some tokens might be compound tokens
            // Split them up
            let tokens = token.value().components(separatedBy: " ")
            for t in tokens {
                // Get original token text
                if  let mappedToken = TokenMap[t],
                    let tokenText = tokenMappings[mappedToken],
                   let index = bagOfWords.firstIndex(of: tokenText)
                {
                    // Determine index in bag of words
                    voiceCommandIndices.append(index)
                } else if let index = bagOfWords.firstIndex(of: t),
                    !voiceCommandIndices.contains(index)
                {
                    // Sometimes not all words in a compound token have their own token
                    // e.g. rate
                    voiceCommandIndices.append(index)
                }
            }
        }
        
        print("\tRETURN: ", command, voiceCommandIndices)

        return (command, voiceCommandIndices)
    }
    
    func isSelectionVoiceCommand(command: VoiceCommand) -> Bool {
        if (
            command == .DELETE_SELECTION ||
            command == .PLAY_SELECTION ||
            command == .ECHO_SELECTION ||
            command == .UPDATE_SELECTION ||
            command == .COPY_SELECTION ||
            command == .CUT_SELECTION ||
            command == .INCREASE_SELECTION_RATE ||
            command == .DECREASE_SELECTION_RATE ||
            command == .RUN_SELECTION ||
            command == .WALK_SELECTION ||
            command == .ACCEPT_SELECTION_UPDATE ||
            command == .REDO_SELECTION_UPDATE ||
            command == .PAUSE_RUN ||
            command == .SHIFT_NEXT_WALK_ELEMENT ||
            command == .SHIFT_PREVIOUS_WALK_ELEMENT ||
            command == .REMOVE_SELECTION ||
            command == .EXIT_RUN ||
            command == .EXIT_WALK ||
            command == .SHIFT_ANCHOR_RIGHT ||
            command == .SHIFT_ANCHOR_LEFT ||
            command == .SHIFT_FOCUS_RIGHT ||
            command == .SHIFT_FOCUS_LEFT ||
            command == .SHIFT_SELECTION_FORWARD ||
            command == .SHIFT_SELECTION_BACKWARD ||
            command == .EXPAND_SELECTION ||
            command == .REDUCE_SELECTION
        ) {
            return true
        }
        
        return false
    }
    
    func isEntryVoiceCommand(command: VoiceCommand) -> Bool {
        if (
            // Entry Manager
            command == .PLAY_ENTRY ||
            command == .PAUSE_ENTRY ||
            command == .START_ENTRY ||
            command == .CREATE_ENTRY ||
            command == .STOP_ENTRY ||
            command == .RESUME_ENTRY ||
            command == .ECHO_ENTRY ||
            command == .PAUSE_ECHO ||
            command == .STOP_ECHO ||
            command == .PLAY_PREVIOUS_SENTENCE ||
            command == .ECHO_PREVIOUS_SENTENCE ||
            command == .DELETE_SELECTION ||
            command == .UPDATE_SELECTION ||
            command == .COPY_SELECTION ||
            command == .CUT_SELECTION ||
            command == .INCREASE_SELECTION_RATE ||
            command == .DECREASE_SELECTION_RATE ||
            command == .EXPORT_ENTRY ||
            command == .EXPORT_SELECTION ||
            command == .PAUSE_PLAYBACK ||
            command == .RESUME_PLAYBACK ||
            command == .RESUME_ECHO ||
            command == .EDIT_ENTRY ||
            command == .PLAY_COMMIT ||
            command == .ECHO_COMMIT ||
            command == .SELECT_COMMIT ||
            command == .WALK_COMMIT ||
            command == .RUN_COMMIT ||
            command == .ROLLBACK_COMMIT ||
            command == .SKIP_PLAYBACK_BACKWARD ||
            command == .SKIP_PLAYBACK_FORWARD ||
            command == .STOP_PLAYBACK ||
            command == .OPEN_SELECTION ||
            command == .REMOVE_SELECTION ||
            command == .SHIFT_ANCHOR_LEFT ||
            command == .SHIFT_ANCHOR_RIGHT ||
            command == .SHIFT_FOCUS_LEFT ||
            command == .SHIFT_FOCUS_RIGHT ||
            command == .SHIFT_SELECTION_FORWARD ||
            command == .SHIFT_SELECTION_BACKWARD ||
            command == .PASTE_CLIPBOARD ||
            command == .EXPAND_SELECTION ||
            command == .REDUCE_SELECTION ||
            command == .DELETE_ENTRY ||
            command == .PLAY_SELECTION ||
            command == .ECHO_SELECTION ||
            command == .RUN_SELECTION ||
            command == .WALK_SELECTION ||
            command == .WALK_ENTRY ||
            command == .RUN_ENTRY ||
            command == .SHIFT_NEXT_WALK_ELEMENT ||
            command == .SHIFT_PREVIOUS_WALK_ELEMENT ||
            command == .PAUSE_RUN ||
            command == .EXIT_RUN ||
            command == .EXIT_WALK ||
            command == .CANCEL_SELECTION_UPDATE ||
            command == .REDO_CHANGE ||
            command == .UNDO_CHANGE ||
            // UI Manager
            command == .ACCEPT_SELECTION_UPDATE ||
            command == .EXPORT_AUDIO ||
            command == .EXPORT_TEXT
            // General
//            command == .SHIFT_HERE
        ) {
            return true
        }
        
        return false
    }
    
    func isEntryManagerCommand(command: VoiceCommand) -> Bool {
        if (
            command == .PLAY_ENTRY ||
            command == .PAUSE_ENTRY ||
            command == .START_ENTRY ||
            command == .CREATE_ENTRY ||
            command == .STOP_ENTRY ||
            command == .RESUME_ENTRY ||
            command == .ECHO_ENTRY ||
            command == .PAUSE_ECHO ||
            command == .STOP_ECHO ||
            command == .PLAY_PREVIOUS_SENTENCE ||
            command == .ECHO_PREVIOUS_SENTENCE ||
            command == .DELETE_SELECTION ||
            command == .UPDATE_SELECTION ||
            command == .COPY_SELECTION ||
            command == .CUT_SELECTION ||
            command == .INCREASE_SELECTION_RATE ||
            command == .DECREASE_SELECTION_RATE ||
            command == .EXPORT_ENTRY ||
            command == .EXPORT_SELECTION ||
            command == .PAUSE_PLAYBACK ||
            command == .RESUME_PLAYBACK ||
            command == .RESUME_ECHO ||
            command == .EDIT_ENTRY ||
            command == .PLAY_COMMIT ||
            command == .ECHO_COMMIT ||
            command == .SELECT_COMMIT ||
            command == .WALK_COMMIT ||
            command == .RUN_COMMIT ||
            command == .ROLLBACK_COMMIT ||
            command == .SKIP_PLAYBACK_BACKWARD ||
            command == .SKIP_PLAYBACK_FORWARD ||
            command == .STOP_PLAYBACK ||
            command == .OPEN_SELECTION ||
            command == .REMOVE_SELECTION ||
            command == .SHIFT_ANCHOR_LEFT ||
            command == .SHIFT_ANCHOR_RIGHT ||
            command == .SHIFT_FOCUS_LEFT ||
            command == .SHIFT_FOCUS_RIGHT ||
            command == .SHIFT_SELECTION_FORWARD ||
            command == .SHIFT_SELECTION_BACKWARD ||
            command == .PASTE_CLIPBOARD ||
            command == .EXPAND_SELECTION ||
            command == .REDUCE_SELECTION ||
            command == .DELETE_ENTRY ||
            command == .PLAY_SELECTION ||
            command == .ECHO_SELECTION ||
            command == .RUN_SELECTION ||
            command == .WALK_SELECTION ||
            command == .WALK_ENTRY ||
            command == .RUN_ENTRY ||
            command == .SHIFT_NEXT_WALK_ELEMENT ||
            command == .SHIFT_PREVIOUS_WALK_ELEMENT ||
            command == .PAUSE_RUN ||
            command == .EXIT_RUN ||
            command == .EXIT_WALK ||
            command == .CANCEL_SELECTION_UPDATE ||
            command == .REDO_CHANGE ||
            command == .UNDO_CHANGE
        ) {
            return true
        }
        
        return false
    }
    
    func isStateCommand(command: VoiceCommand) -> Bool {
        if (
            command == .ACTIVATE_PUNCTUATION ||
            command == .DEACTIVATE_PUNCTUATION ||
            command == .ACTIVATE_SILENCES ||
            command == .DEACTIVATE_SILENCES ||
            command == .ACTIVATE_TEMPORAL_SUGGESTIONS ||
            command == .DEACTIVATE_TEMPORAL_SUGGESTIONS ||
            command == .ACTIVATE_PUNCTUATION_SUGGESTIONS ||
            command == .DEACTIVATE_PUNCTUATION_SUGGESTIONS ||
            command == .ACTIVATE_FORMATTING_SUGGESTIONS ||
            command == .DEACTIVATE_FORMATTING_SUGGESTIONS ||
            command == .ACTIVATE_PASSIVE_ECHO ||
            command == .DEACTIVATE_PASSIVE_ECHO ||
            command == .INCREASE_VOLUME ||
            command == .DECREASE_VOLUME
        ) {
            return true
        }
        
        return false
    }
    
    func isSpeechPlayerCommand(command: VoiceCommand) -> Bool {
        if (
            command == .INCREASE_PLAYBACK_RATE ||
            command == .DECREASE_PLAYBACK_RATE
        ) {
            return true
        }
        
        return false
    }
    
    func isSpeechSynthesisCommand(command: VoiceCommand) -> Bool {
        if (
            command == .INCREASE_ECHO_RATE ||
            command == .DECREASE_ECHO_RATE
        ) {
            return true
        }
        
        return false
    }
    
    func isSelectionCursorCommand(command: VoiceCommand) -> Bool {
        if (
            command == .INSPECT_CLIPBOARD
        ) {
            return true
        }
        
        return false
    }
    
    func isUIManagerCommand(command: VoiceCommand) -> Bool {
        if (
            command == .ACCEPT_SELECTION_UPDATE ||
            command == .REDO_SELECTION_UPDATE ||
            command == .GRANT_PERMISSION ||
            command == .CANCEL_DIALOG ||
            command == .CONTINUE_DIALOG ||
            command == .EXPORT_AUDIO ||
            command == .EXPORT_TEXT
        ) {
            return true
        }
        
        return false
    }

    // command: should be a query after undergoing mapping by voiceCommandMapping
    func process(
        command: VoiceCommand,
        utterance: String,
        handler: (() -> Void)? = nil
    ) {
        print("===== Voice Command Engine: Process =====")
        let utterance = utterance.lowercased()
        print("\tVoice Command: \(command)")
        print("\tUtterance: \"\(utterance)\"")

        if self.isEntryManagerCommand(command: command) ||
            self.isStateCommand(command: command) ||
            self.isSpeechPlayerCommand(command: command) ||
            self.isSpeechSynthesisCommand(command: command) ||
            self.isSelectionCursorCommand(command: command) ||
            self.isUIManagerCommand(command: command)
        {
            print("\tBroadcast processed voice command...")
            // Broadcast Voice Command
            var userInfo: [String: Any] = [
                "command" : command,
                "utterance": utterance
            ]
            if let handler = handler {
                userInfo["handler"] = handler
            }

            NotificationCenter.default.post(
                name: VoiceCommandEngine.onProcessedVoiceCommand,
                object: nil,
                userInfo: userInfo
            )
        } else {
            print("\t[Error] Unable to process voice command!")
        }
    }
    
    public enum Token: String {
        // ACTIONS
        case START = "start"
        case PLAY = "play"
        case PAUSE = "pause"
        case CREATE = "create"
        case STOP = "stop"
        case RESUME = "resume"
        case DELETE = "delete"
        case ACTIVATE = "activate"
        case DEACTIVATE = "deactivate"
        case INCREASE = "increase"
        case DECREASE = "decrease"
        case ADJUST = "adjust"
        case UPDATE = "update"
        case COPY = "copy"
        case CUT = "cut"
        case EXPORT = "export"
        case EDIT = "edit"
        case INSPECT = "inspect"
        case SKIP = "skip"
        case ACCEPT = "accept"
        case OPEN = "open"
        case REMOVE = "remove"
        case UNDO = "undo"
        case REDO = "redo"
        case EXIT = "exit"
        case SELECT = "select"
        case ROLLBACK = "rollback"
        case SHIFT = "shift"
        case EXPAND = "expand"
        case REDUCE = "reduce"
        case GRANT = "grant"
        case CANCEL = "cancel"
        case CONTINUE = "continue"
        case PASTE = "paste"
        case SHOW = "show"
        
        // ENTITIES
        case ENTRY = "entry"
        case SENTENCE = "sentence"
        case PUNCTUATION = "punctuation"
        case SILENCES = "silences"
        case TEMPORAL_SUGGESTIONS = "temporal suggestions"
        case PUNCTUATION_SUGGESTIONS = "punctuation suggestions"
        case FORMATTING_SUGGESTIONS = "formatting suggestions"
        case PASSIVE_ECHO = "passive echo"
        case VOLUME = "volume"
        case ECHO_RATE = "echo rate"
        case PLAYBACK_RATE = "playback rate"
        case PLAYBACK = "playback"
        case SELECTION = "selection"
        case SELECTION_RATE = "selection rate"
        case COMMIT = "commit"
        case CLIPBOARD = "clipboard"
        case SELECTION_UPDATE = "selection update"
        case ANCHOR = "anchor"
        case FOCUS = "focus"
        case PERMISSION = "permission"
        case AUDIO = "audio"
        case TEXT = "text"
        case BEGINNING = "beginning"
        case CHANGE = "change"
        case DIALOG = "dialog"
    //        case HELP = "help"
            
        // ACTION ENTITIES
        case ECHO = "echo"
        case RUN = "run"
        case WALK = "walk"
        case END = "end"
        case FINISH = "finish"
        
        // SPATIAL RELATIONS
        case PREVIOUS = "previous"
        case NEXT = "next"
        case HERE = "here"
        case LEFT = "left"
        case RIGHT = "right"
        case INWARD = "inward"
        case OUTWARD = "outward"
        case UP = "up"
        case DOWN = "down"
        case ON = "on"
        case OFF = "off"
        
        func value() -> String {
            return self.rawValue
        }
    }
    
    public enum VoiceCommand: String, CaseIterable {
        // Entry
        case PLAY_ENTRY = "play entry"
        case PAUSE_ENTRY = "pause entry"
        case CREATE_ENTRY = "create entry"
        case START_ENTRY = "start entry"
        case STOP_ENTRY = "stop entry"
        case RESUME_ENTRY = "resume entry"
        case DELETE_ENTRY = "delete entry"
        case ECHO_ENTRY = "echo entry"
        case RUN_ENTRY = "run entry"
        case WALK_ENTRY = "walk entry"
        case EDIT_ENTRY = "edit entry"
        case EXPORT_ENTRY = "export entry"
        // Echo
        case PLAY_ECHO = "play echo"
        case START_ECHO = "start echo"
        case PAUSE_ECHO = "pause echo"
        case STOP_ECHO = "stop echo"
        case RESUME_ECHO = "resume echo"
        // Playback
        case PAUSE_PLAYBACK = "pause playback"
        case RESUME_PLAYBACK = "resume playback"
        case STOP_PLAYBACK = "stop playback"
        case SKIP_PLAYBACK_BACKWARD = "skip playback backward"
        case SKIP_PLAYBACK_FORWARD = "skip playback forward"
        // Sentence
        case PLAY_PREVIOUS_SENTENCE = "play previous sentence"
        case ECHO_PREVIOUS_SENTENCE = "echo previous sentence"
        // Punctuation
        case ACTIVATE_PUNCTUATION = "activate punctuation"
        case DEACTIVATE_PUNCTUATION = "deactivate punctuation"
        // Silences
        case ACTIVATE_SILENCES = "activate silences"
        case DEACTIVATE_SILENCES = "deactivate silences"
        // Temporal Suggestions
        case ACTIVATE_TEMPORAL_SUGGESTIONS = "activate temporal suggestions"
        case DEACTIVATE_TEMPORAL_SUGGESTIONS = "deactivate temporal suggestions"
        // Punctuation Suggestions
        case ACTIVATE_PUNCTUATION_SUGGESTIONS = "activate punctuation suggestions"
        case DEACTIVATE_PUNCTUATION_SUGGESTIONS = "deactivate punctuation suggestions"
        // Formatting Suggestions
        case ACTIVATE_FORMATTING_SUGGESTIONS = "activate formatting suggestions"
        case DEACTIVATE_FORMATTING_SUGGESTIONS = "deactivate formatting suggestions"
        // Passive Echo
        case ACTIVATE_PASSIVE_ECHO = "activate passive echo"
        case DEACTIVATE_PASSIVE_ECHO = "deactivate passive echo"
        // Volume
        case INCREASE_VOLUME = "increase volume"
        case DECREASE_VOLUME = "decrease volume"
    //        case ADJUST_VOLUME = "adjust volume"
        // Echo Rate
        case INCREASE_ECHO_RATE = "increase echo rate"
        case DECREASE_ECHO_RATE = "decrease echo rate"
        // Playback Rate
        case INCREASE_PLAYBACK_RATE = "increase playback rate"
        case DECREASE_PLAYBACK_RATE = "decrease playback rate"
        // Selection
        case DELETE_SELECTION = "delete selection"
        case UPDATE_SELECTION = "update selection"
        case COPY_SELECTION = "copy selection"
        case CUT_SELECTION = "cut selection"
        case EXPORT_SELECTION = "export selection"
        case RUN_SELECTION = "run selection"
        case WALK_SELECTION = "walk selection"
        case OPEN_SELECTION = "open selection"
        case REMOVE_SELECTION = "remove selection"
        case EXPAND_SELECTION = "expand selection"
        case REDUCE_SELECTION = "reduce selection"
        case PLAY_SELECTION = "play selection"
        case ECHO_SELECTION = "echo selection"
        case PAUSE_RUN = "pause run"
        case EXIT_RUN = "exit run"
        case EXIT_WALK = "exit walk"
        case SHIFT_ANCHOR_RIGHT = "shift anchor right"
        case SHIFT_ANCHOR_LEFT = "shift anchor left"
        case SHIFT_FOCUS_RIGHT = "shift focus right"
        case SHIFT_FOCUS_LEFT = "shift focus left"
        case SHIFT_SELECTION_FORWARD = "shift selection forward"
        case SHIFT_SELECTION_BACKWARD = "shift selection backward"
        case SHIFT_NEXT_WALK_ELEMENT = "shift next walk element"
        case SHIFT_PREVIOUS_WALK_ELEMENT = "shift previous walk element"
        // Selection Update
        case ACCEPT_SELECTION_UPDATE = "accept selection update"
        case REDO_SELECTION_UPDATE = "redo selection update"
        case CANCEL_SELECTION_UPDATE = "cancel selection update"
        // Selection Rate
        case INCREASE_SELECTION_RATE = "increase selection rate"
        case DECREASE_SELECTION_RATE = "decrease selection rate"
        // Cursor
    //        case SHIFT_HERE = "shift here"
        // Commmit
        case PLAY_COMMIT = "play commit"
        case ECHO_COMMIT = "echo commit"
        case SELECT_COMMIT = "select commit"
        case ROLLBACK_COMMIT = "rollback commit"
        case WALK_COMMIT = "walk commit"
        case RUN_COMMIT = "run commit"
        // Clipboard
        case INSPECT_CLIPBOARD = "inspect clipboard"
        case PASTE_CLIPBOARD = "paste clipboard"
        // Output
        case EXPORT_AUDIO = "export audio"
        case EXPORT_TEXT = "export text"
        // General
        case UNDO_CHANGE = "undo change"
        case REDO_CHANGE = "redo change"
    //        case SHOW_HELP = "show help"
        case GRANT_PERMISSION = "grant permission"
        case CANCEL_DIALOG = "cancel dialog"
        case CONTINUE_DIALOG = "continue dialog"
        
        func value() -> String {
            return self.rawValue
        }
        
        // Reference: https://stackoverflow.com/questions/32952248/how-to-get-all-enum-values-as-an-array
        init?(id : Int) {
            switch id {
            // Entry
            case 1: self = .PLAY_ENTRY
            case 2: self = .PAUSE_ENTRY
            case 3: self = .CREATE_ENTRY
            case 4: self = .START_ENTRY
            case 5: self = .STOP_ENTRY
            case 6: self = .RESUME_ENTRY
            case 7: self = .DELETE_ENTRY
            case 8: self = .ECHO_ENTRY
            case 9: self = .RUN_ENTRY
            case 10: self = .WALK_ENTRY
            case 11: self = .EDIT_ENTRY
            case 12: self = .EXPORT_ENTRY
            // Echo
            case 13: self = .PLAY_ECHO
            case 14: self = .START_ECHO
            case 15: self = .PAUSE_ECHO
            case 16: self = .STOP_ECHO
            case 17: self = .RESUME_ECHO
            // Playback
            case 18: self = .PAUSE_PLAYBACK
            case 19: self = .RESUME_PLAYBACK
            case 20: self = .STOP_PLAYBACK
            case 21: self = .SKIP_PLAYBACK_BACKWARD
            case 22: self = .SKIP_PLAYBACK_FORWARD
            // Sentence
            case 23: self = .PLAY_PREVIOUS_SENTENCE
            case 24: self = .ECHO_PREVIOUS_SENTENCE
            // Punctuation
            case 25: self = .ACTIVATE_PUNCTUATION
            case 26: self = .DEACTIVATE_PUNCTUATION
            // Silences
            case 27: self = .ACTIVATE_SILENCES
            case 28: self = .DEACTIVATE_SILENCES
            // Temporal Suggestions
            case 29: self = .ACTIVATE_TEMPORAL_SUGGESTIONS
            case 30: self = .DEACTIVATE_TEMPORAL_SUGGESTIONS
            // Punctuation Suggestions
            case 31: self = .ACTIVATE_PUNCTUATION_SUGGESTIONS
            case 32: self = .DEACTIVATE_PUNCTUATION_SUGGESTIONS
            // Formatting Suggestions
            case 33: self = .ACTIVATE_FORMATTING_SUGGESTIONS
            case 34: self = .DEACTIVATE_FORMATTING_SUGGESTIONS
            // Passive Echo
            case 35: self = .ACTIVATE_PASSIVE_ECHO
            case 36: self = .DEACTIVATE_PASSIVE_ECHO
            // Volume
            case 37: self = .INCREASE_VOLUME
            case 38: self = .DECREASE_VOLUME
    //        case ADJUST_VOLUME = "adjust volume"
            // Echo Rate
            case 39: self = .INCREASE_ECHO_RATE
            case 40: self = .DECREASE_ECHO_RATE
            // Playback Rate
            case 41: self = .INCREASE_PLAYBACK_RATE
            case 42: self = .DECREASE_PLAYBACK_RATE
            // Selection
            case 43: self = .DELETE_SELECTION
            case 44: self = .UPDATE_SELECTION
            case 45: self = .COPY_SELECTION
            case 46: self = .CUT_SELECTION
            case 47: self = .EXPORT_SELECTION
            case 48: self = .RUN_SELECTION
            case 49: self = .WALK_SELECTION
            case 50: self = .OPEN_SELECTION
            case 51: self = .REMOVE_SELECTION
            case 52: self = .EXPAND_SELECTION
            case 53: self = .REDUCE_SELECTION
            case 54: self = .PLAY_SELECTION
            case 55: self = .ECHO_SELECTION
            case 56: self = .PAUSE_RUN
            case 57: self = .EXIT_RUN
            case 58: self = .EXIT_WALK
            case 59: self = .SHIFT_ANCHOR_RIGHT
            case 60: self = .SHIFT_ANCHOR_LEFT
            case 61: self = .SHIFT_FOCUS_RIGHT
            case 62: self = .SHIFT_FOCUS_LEFT
            case 63: self = .SHIFT_SELECTION_FORWARD
            case 64: self = .SHIFT_SELECTION_BACKWARD
            case 65: self = .SHIFT_NEXT_WALK_ELEMENT
            case 66: self = .SHIFT_PREVIOUS_WALK_ELEMENT
            // Selection Update
            case 67: self = .ACCEPT_SELECTION_UPDATE
            case 68: self = .REDO_SELECTION_UPDATE
            case 69: self = .CANCEL_SELECTION_UPDATE
            // Selection Rate
            case 70: self = .INCREASE_SELECTION_RATE
            case 71: self = .DECREASE_SELECTION_RATE
            // Cursor
    //        case SHIFT_HERE = "shift here"
            // Commmit
            case 72: self = .PLAY_COMMIT
            case 73: self = .ECHO_COMMIT
            case 74: self = .SELECT_COMMIT
            case 75: self = .ROLLBACK_COMMIT
            case 76: self = .WALK_COMMIT
            case 77: self = .RUN_COMMIT
            // Clipboard
            case 78: self = .INSPECT_CLIPBOARD
            case 79: self = .PASTE_CLIPBOARD
            // Output
            case 80: self = .EXPORT_AUDIO
            case 81: self = .EXPORT_TEXT
            // General
            case 82: self = .UNDO_CHANGE
            case 83: self = .REDO_CHANGE
    //        case SHOW_HELP = "show help"
            case 84: self = .GRANT_PERMISSION
            case 85: self = .CANCEL_DIALOG
            case 86: self = .CONTINUE_DIALOG
            default: return nil
            }
        }
    }
    
    let TokenMap: [String : Token] = [
        // ACTION
        Token.START.value() : .START,
        "starts" : .START,
        "stock" : .START,
        "scott" : .START,
        Token.PLAY.value() : .PLAY,
        Token.PAUSE.value() : .PAUSE,
        "freeze" : .PAUSE,
        "halt" : .PAUSE,
        "holt" : .PAUSE,
        Token.CREATE.value() : .CREATE,
        "new" : .CREATE,
        Token.STOP.value() : .STOP,
        Token.RESUME.value() : .RESUME,
        Token.DELETE.value() : .DELETE,
        Token.ACTIVATE.value() : .ACTIVATE,
        Token.DEACTIVATE.value() : .DEACTIVATE,
        Token.INCREASE.value() : .INCREASE,
        Token.DECREASE.value() : .DECREASE,
        Token.ADJUST.value() : .ADJUST,
        "i just" : .ADJUST,
        "just" : .ADJUST,
        "turn": .ADJUST,
        Token.UPDATE.value() : .UPDATE,
        Token.COPY.value() : .COPY,
        Token.CUT.value() : .CUT,
        Token.EXPORT.value() : .EXPORT,
        "exports" : .EXPORT,
        Token.EDIT.value() : .EDIT,
        Token.INSPECT.value() : .INSPECT,
        "preview" : .INSPECT,
        "check" : .INSPECT,
        Token.SKIP.value() : .SKIP,
        Token.ACCEPT.value() : .ACCEPT,
        "except" : .ACCEPT,
        Token.OPEN.value() : .OPEN,
        "add" : .OPEN,
        "wake" : .OPEN,
        "make" : .OPEN,
        "makes" : .OPEN,
        "begin": .OPEN,
        Token.REMOVE.value() : .REMOVE,
        "clear" : .REMOVE,
        "unselect" : .REMOVE,
        Token.UNDO.value() : .UNDO,
        Token.REDO.value() : .REDO,
        Token.EXIT.value() : .EXIT,
        Token.SELECT.value() : .SELECT,
        Token.ROLLBACK.value() : .ROLLBACK,
        "reverse" : .ROLLBACK,
        Token.SHIFT.value() : .SHIFT,
        "move" : .SHIFT,
        "place" : .SHIFT,
        "drop" : .SHIFT,
        Token.EXPAND.value() : .EXPAND,
        Token.REDUCE.value() : .REDUCE,
        Token.GRANT.value() : .GRANT,
        "give" : .GRANT,
        "allow": .GRANT,
        Token.CANCEL.value() : .CANCEL,
        Token.CONTINUE.value() : .CONTINUE,
        Token.PASTE.value() : .PASTE,
        Token.SHOW.value() : .SHOW,
        
        // ENTITY
        Token.ENTRY.value() : .ENTRY,
        "entering" : .ENTRY,
        Token.SENTENCE.value() : .SENTENCE,
        Token.PUNCTUATION.value() : .PUNCTUATION,
        Token.SILENCES.value() : .SILENCES,
        Token.TEMPORAL_SUGGESTIONS.value() : .TEMPORAL_SUGGESTIONS,
        Token.PUNCTUATION_SUGGESTIONS.value() : .PUNCTUATION_SUGGESTIONS,
        Token.FORMATTING_SUGGESTIONS.value() : .FORMATTING_SUGGESTIONS,
        Token.PASSIVE_ECHO.value() : .PASSIVE_ECHO,
        Token.VOLUME.value() : .VOLUME,
        Token.ECHO_RATE.value() : .ECHO_RATE,
        Token.PLAYBACK_RATE.value() : .PLAYBACK_RATE,
        Token.PLAYBACK.value() : .PLAYBACK,
        Token.SELECTION.value() : .SELECTION,
        Token.SELECTION_RATE.value() : .SELECTION_RATE,
        Token.COMMIT.value() : .COMMIT,
        "comment" : .COMMIT,
        Token.CLIPBOARD.value() : .CLIPBOARD,
        Token.SELECTION_UPDATE.value() : .SELECTION_UPDATE,
        Token.ANCHOR.value() : .ANCHOR,
        Token.FOCUS.value() : .FOCUS,
        Token.PERMISSION.value() : .PERMISSION,
        Token.AUDIO.value() : .AUDIO,
        Token.TEXT.value() : .TEXT,
        Token.BEGINNING.value() : .BEGINNING,
        Token.CHANGE.value() : .CHANGE,
        Token.DIALOG.value() : .DIALOG,
    //        Token.HELP.value() : .HELP,

        // ACTION-ENTITY
        Token.ECHO.value() : .ECHO,
        "ecko": .ECHO,
        Token.RUN.value() : .RUN,
        Token.WALK.value() : .WALK,
        Token.END.value() : .END,
        "ending" : .END,

        // SPATIAL RELATIONS
        Token.PREVIOUS.value() : .PREVIOUS,
        "last" : .PREVIOUS,
        "lost" : .PREVIOUS,
        "backward": .PREVIOUS,
        "backwards": .PREVIOUS,
        Token.NEXT.value() : .NEXT,
        "right" : .NEXT,
        "forward": .NEXT,
        "forwards": .NEXT,
    //    Token.HERE.value() : .HERE,
        Token.LEFT.value() : .LEFT,
        Token.INWARD.value() : .INWARD,
        "inwards" : .INWARD,
        "in" : .INWARD,
        Token.OUTWARD.value() : .OUTWARD,
        "outwards" : .OUTWARD,
        "out" : .OUTWARD,
        Token.UP.value() : .UP,
        Token.DOWN.value() : .DOWN,
        Token.ON.value() : .ON,
        Token.OFF.value() : .OFF
    ]
    
    let VoiceCommandMap: [Set<Token>: VoiceCommand] = [
        // Entry
        Set([.PLAY, .ENTRY]) : .PLAY_ENTRY,
        Set([.PAUSE, .ENTRY]) : .PAUSE_ENTRY,
        Set([.CREATE, .ENTRY]) : .CREATE_ENTRY,
        Set([.START, .ENTRY]) : .START_ENTRY,
        Set([.STOP, .ENTRY]) : .STOP_ENTRY,
        Set([.END, .ENTRY]) : .STOP_ENTRY,
        Set([.FINISH, .ENTRY]) : .STOP_ENTRY,
        Set([.RESUME, .ENTRY]) : .RESUME_ENTRY,
        Set([.CONTINUE, .ENTRY]) : .RESUME_ENTRY,
        Set([.DELETE, .ENTRY]) : .DELETE_ENTRY,
        Set([.ECHO, .ENTRY]) : .ECHO_ENTRY,
        Set([.RUN, .ENTRY]) : .RUN_ENTRY,
        Set([.WALK, .ENTRY]) : .WALK_ENTRY,
        Set([.EDIT, .ENTRY]) : .EDIT_ENTRY,
        Set([.EXPORT, .ENTRY]) : .EXPORT_ENTRY,
        // Echo
        Set([.PLAY, .ECHO]) : .PLAY_ECHO,
        Set([.START, .ECHO]) : .START_ECHO,
        Set([.PAUSE, .ECHO]) : .PAUSE_ECHO,
        Set([.STOP, .ECHO]) : .STOP_ECHO,
        Set([.END, .ECHO]) : .STOP_ECHO,
        Set([.FINISH, .ECHO]) : .STOP_ECHO,
        Set([.RESUME, .ECHO]) : .RESUME_ECHO,
        Set([.CONTINUE, .ECHO]) : .RESUME_ECHO,
        // Playback
        Set([.PAUSE, .PLAYBACK]) : .PAUSE_PLAYBACK,
        Set([.RESUME, .PLAYBACK]) : .RESUME_PLAYBACK,
        Set([.CONTINUE, .PLAYBACK]) : .RESUME_PLAYBACK,
        Set([.STOP, .PLAYBACK]) : .STOP_PLAYBACK,
        Set([.END, .PLAYBACK]) : .STOP_PLAYBACK,
        Set([.FINISH, .PLAYBACK]) : .STOP_PLAYBACK,
        Set([.SKIP, .PLAYBACK, .NEXT]) : .SKIP_PLAYBACK_BACKWARD,
        Set([.SKIP, .PLAYBACK, .PREVIOUS]) : .SKIP_PLAYBACK_FORWARD,
        // Sentence
        Set([.PLAY, .PREVIOUS, .SENTENCE]) : .PLAY_PREVIOUS_SENTENCE,
        Set([.ECHO, .PREVIOUS, .SENTENCE]) : .ECHO_PREVIOUS_SENTENCE,
        // Punctuation
        Set([.ACTIVATE, .PUNCTUATION]) : .ACTIVATE_PUNCTUATION,
        Set([.ADJUST, .ON, .PUNCTUATION]) : .ACTIVATE_PUNCTUATION,
        Set([.DEACTIVATE, .PUNCTUATION]) : .DEACTIVATE_PUNCTUATION,
        Set([.ADJUST, .OFF, .PUNCTUATION]) : .DEACTIVATE_PUNCTUATION,
        // Silences
        Set([.ACTIVATE, .SILENCES]) : .ACTIVATE_SILENCES,
        Set([.ADJUST, .ON, .SILENCES]) : .ACTIVATE_SILENCES,
        Set([.DEACTIVATE, .SILENCES]) : .DEACTIVATE_SILENCES,
        Set([.ADJUST, .OFF, .SILENCES]) : .DEACTIVATE_SILENCES,
        // Temporal Suggestions
        Set([.ACTIVATE, .TEMPORAL_SUGGESTIONS]) : .ACTIVATE_TEMPORAL_SUGGESTIONS,
        Set([.ADJUST, .ON, .TEMPORAL_SUGGESTIONS]) : .ACTIVATE_TEMPORAL_SUGGESTIONS,
        Set([.DEACTIVATE, .TEMPORAL_SUGGESTIONS]) : .DEACTIVATE_TEMPORAL_SUGGESTIONS,
        Set([.ADJUST, .OFF, .TEMPORAL_SUGGESTIONS]) : .DEACTIVATE_TEMPORAL_SUGGESTIONS,
        // Punctuation Suggestions
        Set([.ACTIVATE, .PUNCTUATION_SUGGESTIONS]) : .ACTIVATE_PUNCTUATION_SUGGESTIONS,
        Set([.ADJUST, .ON, .PUNCTUATION_SUGGESTIONS]) : .ACTIVATE_PUNCTUATION_SUGGESTIONS,
        Set([.DEACTIVATE, .PUNCTUATION_SUGGESTIONS]) : .DEACTIVATE_PUNCTUATION_SUGGESTIONS,
        Set([.ADJUST, .OFF, .PUNCTUATION_SUGGESTIONS]) : .DEACTIVATE_PUNCTUATION_SUGGESTIONS,
        // Formatting Suggestions
        Set([.ACTIVATE, .FORMATTING_SUGGESTIONS]) : .ACTIVATE_FORMATTING_SUGGESTIONS,
        Set([.ADJUST, .ON, .FORMATTING_SUGGESTIONS]) : .ACTIVATE_FORMATTING_SUGGESTIONS,
        Set([.DEACTIVATE, .FORMATTING_SUGGESTIONS]) : .DEACTIVATE_FORMATTING_SUGGESTIONS,
        Set([.ADJUST, .OFF, .FORMATTING_SUGGESTIONS]) : .DEACTIVATE_FORMATTING_SUGGESTIONS,
        // Passive Echo
        Set([.ACTIVATE, .PASSIVE_ECHO]) : .ACTIVATE_PASSIVE_ECHO,
        Set([.ADJUST, .ON, .PASSIVE_ECHO]) : .ACTIVATE_PASSIVE_ECHO,
        Set([.DEACTIVATE, .PASSIVE_ECHO]) : .DEACTIVATE_PASSIVE_ECHO,
        Set([.ADJUST, .OFF, .PASSIVE_ECHO]) : .DEACTIVATE_PASSIVE_ECHO,
        // Volume
        Set([.INCREASE, .VOLUME]) : .INCREASE_VOLUME,
        Set([.ADJUST, .UP, .VOLUME]) : .INCREASE_VOLUME,
        Set([.DECREASE, .VOLUME]) : .DECREASE_VOLUME,
        Set([.ADJUST, .DOWN, .VOLUME]) : .DECREASE_VOLUME,
    //        Set([.ADJUST, .VOLUME]) : .ADJUST_VOLUME,
        // Echo Rate
        Set([.INCREASE, .ECHO_RATE]) : .INCREASE_ECHO_RATE,
        Set([.DECREASE, .ECHO_RATE]) : .DECREASE_ECHO_RATE,
        // Playback Rate
        Set([.INCREASE, .PLAYBACK_RATE]) : .INCREASE_PLAYBACK_RATE,
        Set([.DECREASE, .PLAYBACK_RATE]) : .DECREASE_PLAYBACK_RATE,
        // Selection
        Set([.DELETE, .SELECTION]) : .DELETE_SELECTION,
        Set([.UPDATE, .SELECTION]) : .UPDATE_SELECTION,
        Set([.COPY, .SELECTION]) : .COPY_SELECTION,
        Set([.CUT, .SELECTION]) : .CUT_SELECTION,
        Set([.EXPORT, .SELECTION]) : .EXPORT_SELECTION,
        Set([.RUN, .SELECTION]) : .RUN_SELECTION,
        Set([.WALK, .SELECTION]) : .WALK_SELECTION,
        Set([.OPEN, .SELECTION]) : .OPEN_SELECTION,
        Set([.START, .SELECTION]) : .OPEN_SELECTION,
        Set([.REMOVE, .SELECTION]) : .REMOVE_SELECTION,
        Set([.END, .SELECTION]) : .REMOVE_SELECTION,
        Set([.STOP, .SELECTION]) : .REMOVE_SELECTION,
        Set([.FINISH, .SELECTION]) : .REMOVE_SELECTION,
        Set([.EXPAND, .SELECTION]) : .EXPAND_SELECTION,
        Set([.REDUCE, .SELECTION]) : .REDUCE_SELECTION,
        Set([.PLAY, .SELECTION]) : .PLAY_SELECTION,
        Set([.ECHO, .SELECTION]) : .ECHO_SELECTION,
        Set([.PAUSE, .RUN]) : .PAUSE_RUN,
        Set([.STOP, .RUN]) : .PAUSE_RUN,
        Set([.EXIT, .RUN]) : .EXIT_RUN,
        Set([.EXIT, .WALK]) : .EXIT_WALK,
        // Shift Anchor Right
        Set([.SHIFT, .ANCHOR, .RIGHT]) : .SHIFT_ANCHOR_RIGHT,
        Set([.SHIFT, .ANCHOR, .NEXT]) : .SHIFT_ANCHOR_RIGHT,
        Set([.SHIFT, .ANCHOR, .INWARD]) : .SHIFT_ANCHOR_RIGHT,
        Set([.SHIFT, .START, .RIGHT]) : .SHIFT_ANCHOR_RIGHT,
        Set([.SHIFT, .START, .NEXT]) : .SHIFT_ANCHOR_RIGHT,
        Set([.SHIFT, .START, .INWARD]) : .SHIFT_ANCHOR_RIGHT,
        Set([.SHIFT, .BEGINNING, .RIGHT]) : .SHIFT_ANCHOR_RIGHT,
        Set([.SHIFT, .BEGINNING, .NEXT]) : .SHIFT_ANCHOR_RIGHT,
        Set([.SHIFT, .BEGINNING, .INWARD]) : .SHIFT_ANCHOR_RIGHT,
        // Shift Anchor Left
        Set([.SHIFT, .ANCHOR, .LEFT]) : .SHIFT_ANCHOR_LEFT,
        Set([.SHIFT, .ANCHOR, .PREVIOUS]) : .SHIFT_ANCHOR_LEFT,
        Set([.SHIFT, .ANCHOR, .OUTWARD]) : .SHIFT_ANCHOR_LEFT,
        Set([.SHIFT, .START, .LEFT]) : .SHIFT_ANCHOR_LEFT,
        Set([.SHIFT, .START, .PREVIOUS]) : .SHIFT_ANCHOR_LEFT,
        Set([.SHIFT, .START, .OUTWARD]) : .SHIFT_ANCHOR_LEFT,
        Set([.SHIFT, .BEGINNING, .LEFT]) : .SHIFT_ANCHOR_LEFT,
        Set([.SHIFT, .BEGINNING, .PREVIOUS]) : .SHIFT_ANCHOR_LEFT,
        Set([.SHIFT, .BEGINNING, .OUTWARD]) : .SHIFT_ANCHOR_LEFT,
        // Shift Focus Right
        Set([.SHIFT, .FOCUS, .RIGHT]) : .SHIFT_FOCUS_RIGHT,
        Set([.SHIFT, .FOCUS, .NEXT]) : .SHIFT_FOCUS_RIGHT,
        Set([.SHIFT, .FOCUS, .OUTWARD]) : .SHIFT_FOCUS_RIGHT,
        Set([.SHIFT, .END, .RIGHT]) : .SHIFT_FOCUS_RIGHT,
        Set([.SHIFT, .END, .NEXT]) : .SHIFT_FOCUS_RIGHT,
        Set([.SHIFT, .END, .OUTWARD]) : .SHIFT_FOCUS_RIGHT,
        Set([.SHIFT, .FINISH, .RIGHT]) : .SHIFT_FOCUS_RIGHT,
        Set([.SHIFT, .FINISH, .NEXT]) : .SHIFT_FOCUS_RIGHT,
        Set([.SHIFT, .FINISH, .OUTWARD]) : .SHIFT_FOCUS_RIGHT,
        // Shift Focus Left
        Set([.SHIFT, .FOCUS, .LEFT]) : .SHIFT_FOCUS_LEFT,
        Set([.SHIFT, .FOCUS, .PREVIOUS]) : .SHIFT_FOCUS_LEFT,
        Set([.SHIFT, .FOCUS, .INWARD]) : .SHIFT_FOCUS_LEFT,
        Set([.SHIFT, .END, .LEFT]) : .SHIFT_FOCUS_LEFT,
        Set([.SHIFT, .END, .PREVIOUS]) : .SHIFT_FOCUS_LEFT,
        Set([.SHIFT, .END, .INWARD]) : .SHIFT_FOCUS_LEFT,
        Set([.SHIFT, .FINISH, .LEFT]) : .SHIFT_FOCUS_LEFT,
        Set([.SHIFT, .FINISH, .PREVIOUS]) : .SHIFT_FOCUS_LEFT,
        Set([.SHIFT, .FINISH, .INWARD]) : .SHIFT_FOCUS_LEFT,
        // Shift Selection
        Set([.SHIFT, .SELECTION, .NEXT]) : .SHIFT_SELECTION_FORWARD,
        Set([.SHIFT, .SELECTION, .RIGHT]) : .SHIFT_SELECTION_FORWARD,
        Set([.SHIFT, .SELECTION, .PREVIOUS]) : .SHIFT_SELECTION_BACKWARD,
        Set([.SHIFT, .SELECTION, .LEFT]) : .SHIFT_SELECTION_BACKWARD,
        // Shift Next Walk Element
        Set([.SHIFT, .WALK, .NEXT]) : .SHIFT_NEXT_WALK_ELEMENT,
        Set([.SHIFT, .WALK, .RIGHT]) : .SHIFT_NEXT_WALK_ELEMENT,
        // Shift Previous Walk Element
        Set([.SHIFT, .WALK, .PREVIOUS]) : .SHIFT_PREVIOUS_WALK_ELEMENT,
        Set([.SHIFT, .WALK, .LEFT]) : .SHIFT_PREVIOUS_WALK_ELEMENT,
        // Selection Update
        Set([.ACCEPT, .SELECTION_UPDATE]) : .ACCEPT_SELECTION_UPDATE,
        Set([.REDO, .SELECTION_UPDATE]) : .REDO_SELECTION_UPDATE,
        Set([.CANCEL, .SELECTION_UPDATE]) : .CANCEL_SELECTION_UPDATE,
        // Selection Rate
        Set([.INCREASE, .SELECTION_RATE]) : .INCREASE_SELECTION_RATE,
        Set([.DECREASE, .SELECTION_RATE]) : .DECREASE_SELECTION_RATE,
        // Cursor
    //        Set([.SHIFT, .HERE]) : .SHIFT_HERE,
        // Commit
        Set([.PLAY, .COMMIT]) : .PLAY_COMMIT,
        Set([.ECHO, .COMMIT]) : .ECHO_COMMIT,
        Set([.SELECT, .COMMIT]) : .SELECT_COMMIT,
        Set([.ROLLBACK, .COMMIT]) : .ROLLBACK_COMMIT,
        Set([.DELETE, .COMMIT]) : .ROLLBACK_COMMIT,
        Set([.WALK, .COMMIT]) : .WALK_COMMIT,
        Set([.RUN, .COMMIT]) : .RUN_COMMIT,
        // Clipboard
        Set([.INSPECT, .CLIPBOARD]) : .INSPECT_CLIPBOARD,
        Set([.PASTE, .CLIPBOARD]) : .PASTE_CLIPBOARD,
        Set([.PASTE, .SELECTION]) : .PASTE_CLIPBOARD,
        // Output
        Set([.EXPORT, .AUDIO]) : .EXPORT_AUDIO,
        Set([.EXPORT, .TEXT]) : .EXPORT_TEXT,
        // General
        Set([.UNDO, .CHANGE]) : .UNDO_CHANGE,
        Set([.REDO, .CHANGE]) : .REDO_CHANGE,
    //        Set([.SHOW, .HELP]) : .SHOW_HELP,
        Set([.GRANT, .PERMISSION]) : .GRANT_PERMISSION,
        Set([.CANCEL, .DIALOG]) : .CANCEL_DIALOG,
        Set([.CONTINUE, .DIALOG]) : .CONTINUE_DIALOG
    ]
    
    let ActionToken: Set<Token> = [
        .PLAY,
        .PAUSE,
        .CREATE,
        .STOP,
        .RESUME,
        .DELETE,
        .ACTIVATE,
        .DEACTIVATE,
        .INCREASE,
        .DECREASE,
        .ADJUST,
        .UPDATE,
        .COPY,
        .CUT,
        .EXPORT,
        .EDIT,
        .INSPECT,
        .SKIP,
        .ACCEPT,
        .OPEN,
        .REMOVE,
        .UNDO,
        .REDO,
        .EXIT,
        .SELECT,
        .ROLLBACK,
        .SHIFT,
        .EXPAND,
        .REDUCE,
        .GRANT,
        .CANCEL,
        .CONTINUE,
        .PASTE,
        .SHOW
    ]
    
    let ActionEntityToken: Set<Token> = [
        .ECHO,
        .RUN,
        .WALK,
        .START,
        .END,
        .FINISH
    ]
    
    let EntityToken: Set<Token> = [
        .ENTRY,
        .SENTENCE,
        .PUNCTUATION,
        .SILENCES,
        .TEMPORAL_SUGGESTIONS,
        .PUNCTUATION_SUGGESTIONS,
        .FORMATTING_SUGGESTIONS,
        .PASSIVE_ECHO,
        .VOLUME,
        .ECHO_RATE,
        .PLAYBACK_RATE,
        .PLAYBACK,
        .SELECTION,
        .SELECTION_RATE,
        .COMMIT,
        .CLIPBOARD,
        .SELECTION_UPDATE,
        .ANCHOR,
        .FOCUS,
        .PERMISSION,
        .AUDIO,
        .TEXT,
        .CHANGE,
        .DIALOG
    //        .HELP
    ]
    
    let SpatialRelationToken: Set<Token> = [
        .PREVIOUS,
        .NEXT,
        .HERE,
        .LEFT,
        .RIGHT,
        .INWARD,
        .OUTWARD,
        .UP,
        .DOWN,
        .ON,
        .OFF
    ]
    
    let PossibleEntityActions: [Token : Set<Token>] = [
        .ENTRY: Set([
            .PLAY,
            .PAUSE,
            .CREATE,
            .START,
            .STOP,
            .END,
            .FINISH,
            .RESUME,
            .DELETE,
            .ECHO,
            .RUN,
            .WALK,
            .EDIT,
            .EXPORT,
            .CONTINUE
        ]),
        .ECHO: Set([
            .PLAY,
            .START,
            .PAUSE,
            .STOP,
            .END,
            .FINISH,
            .RESUME,
            .CONTINUE
        ]),
        .PLAYBACK: Set([
            .PAUSE,
            .RESUME,
            .STOP,
            .END,
            .FINISH,
            .SKIP,
            .CONTINUE
        ]),
        .SENTENCE: Set([
            .PLAY,
            .ECHO
        ]),
        .PUNCTUATION: Set([
            .ACTIVATE,
            .DEACTIVATE
        ]),
        .SILENCES: Set([
            .ACTIVATE,
            .DEACTIVATE
        ]),
        .TEMPORAL_SUGGESTIONS: Set([
            .ACTIVATE,
            .DEACTIVATE,
            .ADJUST
        ]),
        .PUNCTUATION_SUGGESTIONS: Set([
            .ACTIVATE,
            .DEACTIVATE,
            .ADJUST
        ]),
        .FORMATTING_SUGGESTIONS: Set([
            .ACTIVATE,
            .DEACTIVATE,
            .ADJUST
        ]),
        .PASSIVE_ECHO: Set([
            .ACTIVATE,
            .DEACTIVATE,
            .ADJUST
        ]),
        .VOLUME: Set([
            .INCREASE,
            .DECREASE,
            .ADJUST
        ]),
        .ECHO_RATE: Set([
            .INCREASE,
            .DECREASE
        ]),
        .PLAYBACK_RATE: Set([
            .INCREASE,
            .DECREASE
        ]),
        .SELECTION: Set([
            .DELETE,
            .UPDATE,
            .COPY,
            .CUT,
            .EXPORT,
            .RUN,
            .WALK,
            .OPEN,
            .START,
            .REMOVE,
            .END,
            .STOP,
            .FINISH,
            .EXPAND,
            .REDUCE,
            .PLAY,
            .ECHO,
            .SHIFT,
            .PASTE
        ]),
        .SELECTION_UPDATE: Set([
            .ACCEPT,
            .REDO
        ]),
        .RUN: Set([
            .PAUSE,
            .RUN,
            .EXIT,
            .STOP
        ]),
        .WALK: Set([
            .SHIFT,
            .EXIT
        ]),
        .ANCHOR: Set([
            .SHIFT
        ]),
        .START: Set([
            .SHIFT
        ]),
        .BEGINNING: Set([
            .SHIFT
        ]),
        .FOCUS: Set([
            .SHIFT
        ]),
        .END: Set([
            .SHIFT
        ]),
        .FINISH: Set([
            .SHIFT
        ]),
        .SELECTION_RATE: Set([
            .INCREASE,
            .DECREASE
        ]),
        .COMMIT: Set([
            .PLAY,
            .ECHO,
            .SELECT,
            .ROLLBACK,
            .DELETE,
            .WALK,
            .RUN,
            .PASTE
        ]),
        .CLIPBOARD: Set([
            .INSPECT,
            .PASTE
        ]),
        .AUDIO: Set([
            .EXPORT
        ]),
        .TEXT: Set([
            .EXPORT
        ]),
        .PERMISSION: Set([
            .GRANT
        ]),
        .CHANGE: Set([
            .UNDO,
            .REDO
        ]),
        .DIALOG: Set([
            .CANCEL,
            .CONTINUE
        ])
    ]
    
    let PossibleEntitySpatialRelations: [Token: Set<Token>] = [
        .SKIP: Set([.NEXT, .PREVIOUS]),
        .SENTENCE: Set([.PREVIOUS]),
        .SHIFT: Set([.NEXT, .PREVIOUS, .RIGHT, .LEFT, .OUTWARD, .INWARD, .UP, .DOWN]),
        .ADJUST: Set([.UP, .DOWN, .ON, .OFF])
    ]
    
    // MARK: - Getters
    
    public static func getContextualStrings() -> [String] {
        var contextualStrings = [String]()
        for command in VoiceCommand.allCases {
            contextualStrings.append(command.value())
        }
        
        return contextualStrings
    }
}
