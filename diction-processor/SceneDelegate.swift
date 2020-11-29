//
//  SceneDelegate.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/9/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let _ = (scene as? UIWindowScene) else { return }
        let mainViewController = self.window!.rootViewController!.children.first! as! ViewController
        let storageManager = StorageManager()
        let notifications = NotificationEngine()
        let uiManager = UIManager(notifications: notifications)
        let state = StateManager(
            storageManager: storageManager,
            notifications: notifications,
            uiManager: uiManager
        )
        uiManager.state = state
        let speechPlayer = SpeechPlayerEngine(
            state: state,
            notifications: notifications
        )
        let speechSynthesis = SpeechSynthesisEngine(
            state: state,
            speechPlayer: speechPlayer,
            notifications: notifications
        )
        speechPlayer.speechSynthesis = speechSynthesis
        uiManager.speechSynthesis = speechSynthesis
        let speechRecognition = SpeechRecognitionEngine(
            state: state,
            notifications: notifications,
            speechPlayer: speechPlayer,
            speechSynthesis: speechSynthesis,
            uiManager: uiManager
        )
        notifications.speechSynthesis = speechSynthesis
        notifications.speechRecognition = speechRecognition
        speechSynthesis.speechRecognition = speechRecognition
        speechPlayer.speechRecognition = speechRecognition
        storageManager.speechRecognition = speechRecognition
        let selectionCursor = SelectionCursor(
            state: state,
            speechPlayer: speechPlayer,
            speechSynthesis: speechSynthesis,
            speechRecognition: speechRecognition,
            notifications: notifications,
            uiManager: uiManager
        )
        speechRecognition.selectionCursor = selectionCursor
        speechPlayer.selectionCursor = selectionCursor
        speechSynthesis.selectionCursor = selectionCursor
        let pitchRecognition = PitchRecognitionEngine(
            state: state,
            speechRecognition: speechRecognition
        )
        let noteManager = NoteManager(
            state: state,
            speechRecognition: speechRecognition,
            notifications: notifications,
            speechPlayer: speechPlayer,
            speechSynthesis: speechSynthesis,
            selectionCursor: selectionCursor,
            uiManager: uiManager,
            pitchRecognition: pitchRecognition
        )
        pitchRecognition.noteManager = noteManager
        speechPlayer.noteManager = noteManager
        speechSynthesis.noteManager = noteManager
        speechRecognition.noteManager = noteManager
        selectionCursor.noteManager = noteManager
        mainViewController.state = state
        mainViewController.notifications = notifications
        mainViewController.speechRecognition = speechRecognition
        mainViewController.speechSynthesis = speechSynthesis
        mainViewController.pitchRecognition = pitchRecognition
        mainViewController.speechPlayer = speechPlayer
        mainViewController.selectionCursor = selectionCursor
        mainViewController.noteManager = noteManager
        mainViewController.uiManager = uiManager
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not neccessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.

        // Save changes in the application's managed object context when the application transitions to the background.
        (UIApplication.shared.delegate as? AppDelegate)?.saveContext()
    }


}

