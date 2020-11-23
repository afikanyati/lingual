//
//  InvalidVoiceCommandType.swift
//  diction-processor
//
//  Created by Afika Nyati on 11/17/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

enum InvalidVoiceCommandType {
    case CLOSE_TO_LAST_VOICE_COMMAND
    case FOREIGN_COMMAND_WHILE_MODAL_VISIBLE
    case SELECTION_COMMAND_WITHOUT_SELECTION
    case NOTE_COMMAND_WITHOUT_NOTE_SET
    case UI_MANAGER_COMMAND_WITHOUT_DIALOG_VISIBLE
    case STOP_COMMAND_WITHOUT_SUITABLE_MODE
    case DELETE_NOTE_WHILE_LISTENING_FOR_SPEECH
    case VOICE_COMMAND_NOT_FOUND
}
