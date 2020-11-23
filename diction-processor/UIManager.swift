//
//  UIManager.swift
//  diction-processor
//
//  Created by Afika Nyati on 11/8/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import Foundation

class UIManager: NSObject {
    // MARK: - Notifications
    
    static let onReceiveDialogInput = Notification.Name(Notifications.onReceivedDialogInput.rawValue)
    
    // MARK: - App Modules
    
    var state: StateManager!
    var notifications: NotificationEngine
    
    // MARK: - General Properties
    
    private(set) var dialogIsModal = true
    private(set) var dialogIsVisible = false
    private(set) var dialogActionDictionary: [String : Int]? = nil
    private(set) var dialogActions: [DialogAction]? = nil
    
    // MARK: - Initialization and Deinitialization
    
    init(notifications: NotificationEngine) {
        print("===== State Manager : Initialization =====")
        self.notifications = notifications
        
        super.init()

        self.configureNotificationObservers()
    }
    
    deinit {
        // remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Validation
    
    func checkRep() {
        var result = true
        
        // invarant #1
        result = result && true
        
        if !result {
            fatalError("===== [Error] State Manager Representation Invariants were broken =====")
        }
    }
    
    // MARK: - Notifications
    
    func configureNotificationObservers() {
        print("===== UIManager: Configure Notification Observers =====")
        let notificationCenter = NotificationCenter.default
    
        notificationCenter.addObserver(
            self,
            selector: #selector(onProcessedVoiceCommand(notification:)),
            name: VoiceCommandEngine.onProcessedVoiceCommand,
            object: nil
        )
    }
    
    @objc func onProcessedVoiceCommand(notification: Notification) {
        print("===== UIManager: On Processed Voice Command =====")
        let command = notification.userInfo!["command"] as! String
        let utterance = notification.userInfo!["utterance"] as! String
        var handler: (() -> Void)?
        if notification.userInfo!["handler"] != nil {
            handler = notification.userInfo!["handler"] as? () -> Void
        }
        
        if let _ = self.dialogActions, self.dialogIsVisible {
            let (foundAction, action) = self.modalContainsCommand(command: command)
            
            if let action = action, foundAction {
                
                // Dismiss Dialog
                self.dismissDialog()
                
                
                Timer.scheduledTimer(withTimeInterval: Utils.DEFAULT_NOTIFICATION_DELAY, repeats: false) { timer in
                    // Play Sound
                    soundEngine.voiceCommandAccept()
                }
                
                if action.feedbackVisualMessage != nil || action.feedbackAudioMessage != nil {
                    self.notifications.executeFeedback(
                        visualMessage: action.feedbackVisualMessage,
                        audioMessage: action.feedbackAudioMessage,
                        discardPrior: true,
                        withHaptics: true
                    )
                }
                
                action.handler?(nil)
                handler?()
            }
            
            if let validOptions = self.getValidOptionsString(), !foundAction && self.dialogIsModal {
                print("\t[Error] Invalid Command. Remind user of valid commands.")
                self.notifications.executeError(
                    text: "'\(utterance)' is not a valid command. Please choose from: \(validOptions)",
                    voiceCommand: true,
                    discardPrior: true
                )
            }
        }
    }
    
    // MARK: - Methods
    
    // The actionVoiceCommands dictionary connects
    // voice commands to the dialog actions
    func presentDialog(
        dialogItem: DialogItem
    ) {
        print("===== UIManager: Present Dialog =====")
        // Play Sound
        soundEngine.presentDialog()
        
        // Present Feedback
        self.notifications.executeFeedback(
            visualMessage: dialogItem.title,
            audioMessage: dialogItem.message,
            withHaptics: true
        )
        
        let dialog = UIAlertController(
            title: dialogItem.title,
            message: dialogItem.message,
            preferredStyle: dialogItem.preferredStyle
        )
        
        for act in dialogItem.actions {
            let alertAction = UIAlertAction(
                title: act.title,
                style: act.style,
                handler: {action in
                    self.dismissDialog()
                    act.handler?(action)
                }
            )
            
            dialog.addAction(alertAction)
        }

        DispatchQueue.main.async { [weak self] in
            let vc = Utils.getNavigationController()?.visibleViewController
            if let vc = vc {
                self?.dialogIsVisible = true
                self?.dialogActions = dialogItem.actions
                vc.present(dialog, animated: true, completion: nil)
                self?.checkRep()
            }
        }
    }
    
    func dismissDialog() {
        print("===== UIManager: Dismiss Dialog =====")
        DispatchQueue.main.async { [weak self] in
            let vc = Utils.getNavigationController()?.visibleViewController
            if let vc = vc {
                vc.dismiss(animated: true)
                self?.dialogIsVisible = false
                self?.dialogActions = nil
            } else {
                self?.dialogIsVisible = false
                self?.dialogActions = nil
            }
        }
    }
    
    func modalContainsCommand(command: String) -> (Bool, DialogAction?) {
        print("===== UIManager: Modal Contains Command =====")
        print("\tLooking for action with voice command: '\(command)'")
        
        guard let dialogActions = self.dialogActions else {
            return (false, nil)
        }
        
        for action in dialogActions {
            print("\tTesting action with voice command: '\(action.voiceCommand)'")

            if voiceCommandEngine.voiceCommandMapping[action.voiceCommand] == voiceCommandEngine.voiceCommandMapping[command] {
                print("\tFound voice command!")
                return (true, action)
            }
        }
            
        print("\tVoice command not found.")
        return (false, nil)
    }
    
    // MARK: - Setters
    
    func setDialogIsVisible(to isVisible: Bool) {
        print("===== State Manager: Set Dialog Is Visible =====")
        print("Set to: ", isVisible)
        self.dialogIsVisible = isVisible
        checkRep()
    }
    
    // MARK: - Helpers
    
    func getValidOptionsString() -> String? {
        print("===== UIManager: Get Valid Options String =====")
        guard let dialogActions = self.dialogActions else {
            return nil
        }
        
        var validOptions = ""
        for (index, action) in dialogActions.enumerated() {
            if index + 1 == dialogActions.count {
                // last command
                validOptions += "or '\(action.voiceCommand)'."
            } else {
                validOptions += "'\(action.voiceCommand)', "
            }
        }
        
        return validOptions
    }
}
