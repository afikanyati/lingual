//
//  ExpressionTrack.swift
//  diction-processor
//
//  Created by Afika Nyati on 6/20/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import UIKit
import AVFoundation

class ExpressionTrack: AVMutableCompositionTrack {
    var _segments: [ExpressionSegment]?
    
    override public var segments : [AVCompositionTrackSegment]? {
        get {
            return _segments
        }
        set {
            if let newSegments = newValue as? [ExpressionSegment] {
                _segments = newSegments
            } else {
                print("Incorrect segments type for ExpressionTrack")
            }
        }
    }
}
