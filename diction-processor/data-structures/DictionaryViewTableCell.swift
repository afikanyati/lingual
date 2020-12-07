//
//  DictionaryViewTableCell.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/6/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

// Reference: https://programmingwithswift.com/create-a-custom-uitableviewcell-with-swift/
class DictionaryViewTableCell: UITableViewCell {
    @IBOutlet weak var header: UILabel!
    @IBOutlet weak var body: UILabel!
    @IBOutlet weak var supportingText: UILabel!
    @IBOutlet weak var bodyBottomConstraint: NSLayoutConstraint!
}
