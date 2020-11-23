//
//  DialogAction.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/9/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

struct DialogAction {
    var title: String
    var voiceCommand: String
    var feedbackVisualMessage: String? = nil
    var feedbackAudioMessage: String? = nil
    var style: UIAlertAction.Style
    var handler: ((UIAlertAction?) -> Void)?
}
