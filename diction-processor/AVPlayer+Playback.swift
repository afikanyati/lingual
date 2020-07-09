//
//  AVPlayer+Playback.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/3/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import AVFoundation

extension AVPlayer {
    var isPlaying: Bool {
        return rate != 0 && error == nil
    }
    
    func stop() {
        pause()
        if let item = currentItem {
            seek(to: item.duration)
        }
    }
}
