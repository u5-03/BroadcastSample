//
//  AudioPlayer.swift
//  BroadcastSample
//
//  Created by Yugo Sugiyama on 2020/11/08.
//

import Foundation
import AVFoundation

enum AudioResourceType {
    case audioFilePath(URL: URL)
}

enum AudioPlayingState: String {
    case playing, stopped, paused, resuming
}

final class AudioPlayer {

    private let engine = AVAudioEngine()
    private let audioPlayerNode = AVAudioPlayerNode()
    private let delayNode = AVAudioUnitDelay()
    private let distortionNode = AVAudioUnitDistortion()
    private let eqNode = AVAudioUnitEQ()
    private let reverbNode = AVAudioUnitReverb()

    var didAudioPlayingStateChanged: ((AudioPlayingState) -> Void)?
    private var audioPlayingState: AudioPlayingState = .stopped {
        didSet { didAudioPlayingStateChanged?(audioPlayingState) }
    }
    private var observers: [NSKeyValueObservation] = []

    init() {
    }

    func play(resourceType: AudioResourceType, effect: AudioEffect = .none) {
        engine.reset()
        audioPlayerNode.stop()
        setupAudioSession()
        switch resourceType {
        case .audioFilePath(let URL):
            do {
                let audioFile = try AVAudioFile(forReading: URL)
                let audioFormat = audioFile.processingFormat
                let audioFrameCount = UInt32(audioFile.length)
                guard let audioFileBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: audioFrameCount) else { return }
                try audioFile.read(into: audioFileBuffer, frameCount: audioFrameCount)
                let mainMixer = engine.mainMixerNode
                engine.attach(audioPlayerNode)
                switch effect {
                case .none:
                    engine.connect(audioPlayerNode, to: mainMixer, format: audioFileBuffer.format)
                case .delay:
                    engine.attach(delayNode)
                    delayNode.delayTime = 1
                    engine.connect(audioPlayerNode, to: delayNode, format: audioFileBuffer.format)
                    engine.connect(delayNode, to: mainMixer, format: audioFileBuffer.format)
                case .distortion(let preset):
                    engine.attach(distortionNode)
                    if let preset = preset {
                        distortionNode.loadFactoryPreset(preset)
                    }
                    engine.connect(audioPlayerNode, to: distortionNode, format: audioFileBuffer.format)
                    engine.connect(distortionNode, to: mainMixer, format: audioFileBuffer.format)
                case .eq:
                    engine.attach(eqNode)
                    engine.connect(audioPlayerNode, to: eqNode, format: audioFileBuffer.format)
                    engine.connect(eqNode, to: mainMixer, format: audioFileBuffer.format)
                case .reverb(let preset):
                    engine.attach(reverbNode)
                    if let preset = preset {
                        reverbNode.loadFactoryPreset(preset)
                    }
                    engine.connect(audioPlayerNode, to: reverbNode, format: audioFileBuffer.format)
                    engine.connect(reverbNode, to: mainMixer, format: audioFileBuffer.format)
                }

                engine.prepare()
                try engine.start()
                audioPlayerNode.play()
                audioPlayerNode.scheduleBuffer(audioFileBuffer, at: nil, options: .loops, completionHandler: nil)
                audioPlayingState = .playing
            } catch let error {
                print(error)
            }
        }
    }

    func resume() {
        if engine.isRunning, !audioPlayerNode.isPlaying {
            setupAudioSession()
            audioPlayerNode.play()
            audioPlayingState = .resuming
        }
    }

    func pause() {
        if audioPlayerNode.isPlaying {
            audioPlayerNode.pause()
            audioPlayingState = .paused
        }
    }

    func stop() {
        if audioPlayerNode.isPlaying {
            audioPlayerNode.stop()
            audioPlayingState = .stopped
        }
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
            // サイレントモードでも音を鳴らす
            try audioSession.setCategory(.playback)
        } catch {
            print("Audio session setting error..")
        }
    }
}
