//
//  CMTimeMapping+subscript.swift
//  diction-processor
//
//  Created by Afika Nyati on 8/6/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

extension CMTimeMapping {
    subscript(_ mappingType: TimeNormalizerType) -> CMTimeRange {
        get {
            if mappingType == .target {
                return self.target
            }
            
            return self.source
        }
    }
}
