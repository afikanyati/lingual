//
//  TransformationType.swift
//  diction-processor
//
//  Created by Afika Nyati on 9/16/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

enum TransformationType: Int {
    case playbackRate
    
    // Reference: https://stackoverflow.com/questions/26077358/access-an-enum-value-by-its-hashvalue
    static func fromRawValue(rawValue: Int) -> TransformationType? {
        if rawValue == 0 {
            return .playbackRate
        }
        
        return nil
   }
}
