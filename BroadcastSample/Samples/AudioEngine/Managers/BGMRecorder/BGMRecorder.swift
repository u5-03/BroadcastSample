//
//  BGMRecorder.swift
//  BroadcastSample
//
//  Created by 杉山優悟 on 2020/12/12.
//

import Foundation
import AVFoundation

final class BGMRecorder {
    private let engine = AVAudioEngine()
    private let mixerNode = AVAudioMixerNode()
    private let audioPlayerNode = AVAudioPlayerNode()

    init() {}

    func startRecord() {

    }

    func stopRecord() {

    }

    func playBGM() {
        engine.reset()
        prepare()
        audioPlayerNode.play()
//        audioPlayerNode.scheduleBuffer(audioFileBuffer, at: nil, options: .loops, completionHandler: nil)
    }

    func pauseBGM() {
        if audioPlayerNode.isPlaying {
            audioPlayerNode.stop()
        }
    }

    private func prepare() {
        engine.reset()
        audioPlayerNode.stop()
        setupAudioSession()
        let audioFileURL = URL(string: Bundle.main.path(forResource: "nocturne", ofType: "mp3")!)!
        do {
            let audioFile = try AVAudioFile(forReading: audioFileURL)
            let audioFormat = audioFile.processingFormat
            let audioFrameCount = UInt32(audioFile.length)
            guard let audioFileBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: audioFrameCount) else { return }
            try audioFile.read(into: audioFileBuffer, frameCount: audioFrameCount)
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let mainMixerNode = engine.mainMixerNode
            let mixerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false)
            engine.attach(audioPlayerNode)
            engine.attach(mixerNode)
            engine.connect(audioPlayerNode, to: mixerNode, format: audioFormat)
            engine.connect(inputNode, to: mixerNode, format: audioFormat)
            engine.connect(mixerNode, to: mainMixerNode, format: mixerFormat)

            engine.prepare()
            try engine.start()
        } catch let error {
            print(error)
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
