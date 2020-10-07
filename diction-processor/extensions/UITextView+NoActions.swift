//
//  UITextView+NoActions.swift
//  diction-processor
//
//  Created by Afika Nyati on 10/5/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

// Reference: https://stackoverflow.com/questions/44329280/how-to-remove-lookup-share-from-textview-in-swift-3
// Reference: https://stackoverflow.com/questions/1426731/how-disable-copy-cut-select-select-all-in-uitextview
class NoSelectTextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false
    }
}
