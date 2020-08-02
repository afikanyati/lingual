//
//  MPVolumeView+volumeSlider.swift
//  diction-processor
//
//  Created by Afika Nyati on 7/28/20.
//  Copyright © 2020 Afika Nyati. All rights reserved.
//

import Foundation
import MediaPlayer

// Resource: https://stackoverflow.com/questions/33168497/ios-9-how-to-change-volume-programmatically-without-showing-system-sound-bar-po/50740234#50740234
extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        let volumeView = MPVolumeView()
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.01) {
            slider?.value = volume
        }
    }
}
