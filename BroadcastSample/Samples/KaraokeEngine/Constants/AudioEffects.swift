//
//  AudioEffects.swift
//  BroadcastSample
//
//  Created by Yugo Sugiyama on 2020/11/16.
//

import Foundation
import AVFoundation

enum AudioEffect: CaseIterable {

    case none
    case delay
    case distortion(preset: AVAudioUnitDistortionPreset?)
    case eq
    case reverb(preset: AVAudioUnitReverbPreset?)

    static var allCases: [AudioEffect] {
        return [
            .none,
            .delay,
            .distortion(preset: .speechGoldenPi),
            .eq,
            .reverb(preset: .cathedral)
        ]
    }
}
