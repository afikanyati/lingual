//
//  UIView+Border.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/6/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import UIKit

// Reference: https://stackoverflow.com/questions/7666863/uiview-bottom-border
enum viewBorder: String {
    case left = "borderLeft"
    case right = "borderRight"
    case top = "borderTop"
    case bottom = "borderBottom"
}

extension UIView {
    func addBorder(vBorder: viewBorder, color: UIColor, width: CGFloat) {
        let border = CALayer()
        border.backgroundColor = color.cgColor
        border.name = vBorder.rawValue
        switch vBorder {
            case .left:
                border.frame = CGRect(x: 0, y: 0, width: width, height: self.frame.size.height)
            case .right:
                border.frame = CGRect(x: self.frame.size.width - width, y: 0, width: width, height: self.frame.size.height)
            case .top:
                border.frame = CGRect(x: 0, y: 0, width: self.frame.size.width, height: width)
            case .bottom:
                border.frame = CGRect(x: 0, y: self.frame.size.height - width, width: self.frame.size.width, height: width)
        }
        self.layer.addSublayer(border)
    }

    func removeBorder(border: viewBorder) {
        var layerForRemove: CALayer?
        for layer in self.layer.sublayers! {
            if layer.name == border.rawValue {
                layerForRemove = layer
            }
        }
        if let layer = layerForRemove {
            layer.removeFromSuperlayer()
        }
    }
}
