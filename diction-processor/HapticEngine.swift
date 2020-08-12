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
        notificationFeedbackGenerator!.prepare()
        
        // lets you generate light, medium, and heavy effects that Apple says provide a "physical metaphor that complements the visual experience."
        lightImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        mediumImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        heavyImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)
        lightImpactFeedbackGenerator!.prepare()
        mediumImpactFeedbackGenerator!.prepare()
        heavyImpactFeedbackGenerator!.prepare()
        
        // generates feedback that should be triggered when the user is changing their selection on screen, e.g. moving through a picker wheel.
        selectionFeedbackGenerator = UISelectionFeedbackGenerator()
        selectionFeedbackGenerator!.prepare()
    }
    
    func error() {
        notificationFeedbackGenerator!.notificationOccurred(.error)
    }
    
    func success() {
        notificationFeedbackGenerator!.notificationOccurred(.success)
    }
    
    func warning() {
        notificationFeedbackGenerator!.notificationOccurred(.warning)
    }
    
    func lightImpact() {
        lightImpactFeedbackGenerator!.impactOccurred()
    }
    
    func mediumImpact() {
        mediumImpactFeedbackGenerator!.impactOccurred()
    }
    
    func heavyImpact() {
        heavyImpactFeedbackGenerator!.impactOccurred()
    }
    
    func selection() {
        selectionFeedbackGenerator!.selectionChanged()
    }
}
