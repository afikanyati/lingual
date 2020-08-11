//
//  HapticEngine.swift
//  diction-processor
//
//  Created by Afika Nyati on 8/5/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

// Reference: https://www.hackingwithswift.com/example-code/uikit/how-to-generate-haptic-feedback-with-uifeedbackgenerator

public let hapticEngine = HapticEngine.shared
public final class HapticEngine: NSObject {
    
    static let shared = HapticEngine()
    
    var notificationFeedbackGenerator: UINotificationFeedbackGenerator? = nil
    var lightImpactFeedbackGenerator: UIImpactFeedbackGenerator? = nil
    var mediumImpactFeedbackGenerator: UIImpactFeedbackGenerator? = nil
    var heavyImpactFeedbackGenerator: UIImpactFeedbackGenerator? = nil
    var selectionFeedbackGenerator: UISelectionFeedbackGenerator? = nil
    
    private override init() {
        // lets you generate feedback based on three system events: error, success, and warning
        notificationFeedbackGenerator = UINotificationFeedbackGenerator()
        
        // lets you generate light, medium, and heavy effects that Apple says provide a "physical metaphor that complements the visual experience."
        lightImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        mediumImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        heavyImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)
        
        // generates feedback that should be triggered when the user is changing their selection on screen, e.g. moving through a picker wheel.
        selectionFeedbackGenerator = UISelectionFeedbackGenerator()
    }
    
    func error() {
        notificationFeedbackGenerator!.prepare()
        notificationFeedbackGenerator!.notificationOccurred(.error)
    }
    
    func success() {
        notificationFeedbackGenerator!.prepare()
        notificationFeedbackGenerator!.notificationOccurred(.success)
    }
    
    func warning() {
        notificationFeedbackGenerator!.prepare()
        notificationFeedbackGenerator!.notificationOccurred(.warning)
    }
    
    func lightImpact() {
        lightImpactFeedbackGenerator!.prepare()
        lightImpactFeedbackGenerator!.impactOccurred()
    }
    
    func mediumImpact() {
        lightImpactFeedbackGenerator!.prepare()
        lightImpactFeedbackGenerator!.impactOccurred()
    }
    
    func heavyImpact() {
        lightImpactFeedbackGenerator!.prepare()
        lightImpactFeedbackGenerator!.impactOccurred()
    }
    
    func selection() {
        selectionFeedbackGenerator!.prepare()
        selectionFeedbackGenerator!.selectionChanged()
    }
}
