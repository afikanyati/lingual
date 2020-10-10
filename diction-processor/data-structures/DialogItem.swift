//
//  DialogItem.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/9/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

struct DialogItem {
    var title: String
    var message: String
    var preferredStyle: UIAlertController.Style
    var actions: [DialogAction]
}
