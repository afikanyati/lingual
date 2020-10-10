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
    var style: UIAlertAction.Style
    var handler: ((UIAlertAction) -> Void)?
}
