//
//  UITextView+VisibleRange.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/13/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

// Reference: https://stackoverflow.com/questions/6067803/ios-how-to-find-what-is-the-visible-range-of-text-in-uitextview
public extension UITextView {
    var visibleRange: NSRange? {
        if let start = closestPosition(to: contentOffset) {
            if let end = characterRange(at: CGPoint(x: contentOffset.x + bounds.maxX, y: contentOffset.y + bounds.maxY))?.end {
                return NSMakeRange(offset(from: beginningOfDocument, to: start), offset(from: start, to: end))
            }
        }
        return nil
    }
}
