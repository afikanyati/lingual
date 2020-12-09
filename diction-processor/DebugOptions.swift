//
//  DebugOptions.swift
//  diction-processor
//
//  Created by Afika Nyati on 12/8/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation

// Disabling print statements in release builds
// Reference: http://fusionblender.net/disable-print-statements-production-releases-xcode/
// Reference: https://stackoverflow.com/questions/26913799/remove-println-for-release-version-ios-swift
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    
    #if DEBUG
    
    var idx = items.startIndex
    let endIdx = items.endIndex
    
    repeat {
        Swift.print(items[idx], separator: separator, terminator: idx == (endIdx - 1) ? terminator : separator)
        idx += 1
    }while idx < endIdx
    
    #endif
}
