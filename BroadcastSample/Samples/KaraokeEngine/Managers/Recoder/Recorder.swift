//
//  Recorder.swift
//  BroadcastSample
//
//  Created by Yugo Sugiyama on 2020/11/08.
//

import Foundation
import AVFoundation

enum RecordingState: String {
    case recording
    case stopped
    case paused
    case resuming

    var isRecording: Bool {
        switch self {
        case .recording: return true
        default: return false
        }
    }

    var isStopped: Bool {
        switch self {
        case .stopped: return true
        default: return false
        }
    }

    var isResuming: Bool {
        switch self {
        case .resuming: return true
        default: return false
        }
    }

    var isPaused: Bool {
        switch self {
        case .paused: return true
        default: return false
        }
    }
}

enum InterruptionType: String {
    case interrupting
    case notInterrupted

    static func parse(from type: AVAudioSession.InterruptionType) -> InterruptionType {
        switch type {
        case .began: return .interrupting
        case .ended: return .notInterrupted
        @unknown default: return .notInterrupted
        }
    }
}

// Ref: https://arvindhsukumar.medium.com/using-avaudioengine-to-record-compress-and-stream-audio-on-ios-48dfee09fde4
final class Recorder {
    private let engine = AVAudioEngine()
    private let mixerNode = AVAudioMixerNode()
    private let delayNode = AVAudioUnitDelay()
    private let distortionNode = AVAudioUnitDistortion()
    private let eqNode = AVAudioUnitEQ()
    private let reverbNode = AVAudioUnitReverb()
    private let muteNode = AVAudioMixerNode()

    private var observers: [NSKeyValueObservation] = []
    var didRecordingStateChanged: ((RecordingState) -> Void)?
    private(set) var recordingState: RecordingState = .stopped {
        didSet { didRecordingStateChanged?(recordingState) }
    }
    var didInterruptionTypeChanged: ((InterruptionType) -> Void)?
    private(set) var interruptionType: InterruptionType = .notInterrupted {
        didSet { didInterruptionTypeChanged?(interruptionType) }
    }
    private var isConfigChangePending = false
    private var converter: AVAudioConverter?
    private var compressedBuffer: AVAudioCompressedBuffer?

    init() {
        mixerNode.volume = 0
        setupNotifications()
    }

    func start(path: URL, shouldCompressd: Bool = false) {
        guard recordingState.isStopped else { return }
        guard let audioFile = try? AVAudioFile(forWriting: path, settings: mixerNode.outputFormat(forBus: 0).settings) else { return }
        setupAudioSession()
        let format = mixerNode.outputFormat(forBus: 0)
        if shouldCompressd {
            var outDesc = AudioStreamBasicDescription()
            outDesc.mSampleRate = format.sampleRate
            outDesc.mChannelsPerFrame = 1
            outDesc.mFormatID = kAudioFormatFLAC
            let framePerPacket: UInt32 = 1152
            outDesc.mFramesPerPacket = framePerPacket
            outDesc.mBitsPerChannel = 24
            outDesc.mBytesPerPacket = 0

            let convertFormat = AVAudioFormat(streamDescription: &outDesc)!
            converter = AVAudioConverter(from: format, to: convertFormat)

            let packetSize: UInt32 = 8
            let bufferSize = framePerPacket * packetSize
            mixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { (buffer, when) in
              do {
                guard let converter = self.converter else { return }
                self.compressedBuffer = AVAudioCompressedBuffer(format: convertFormat, packetCapacity: packetSize, maximumPacketSize: converter.maximumOutputPacketSize)
                let inputBlock: AVAudioConverterInputBlock = { (inNumPackets, outStatus) -> AVAudioBuffer? in
                    outStatus.pointee = AVAudioConverterInputStatus.haveData
                    return buffer
                }
                var outError: NSError?
                self.converter?.convert(to: self.compressedBuffer!, error: &outError, withInputFrom: inputBlock)

                if let audioBuffer = self.compressedBuffer?.audioBufferList.pointee.mBuffers,
                   let mData = audioBuffer.mData {
                    let length = Int(audioBuffer.mDataByteSize)
                    let data = Data(bytes: mData, count: length)
                }
                // audioFileにバッファを書き込む
                try audioFile.write(from: buffer)
              } catch let error {
                print("audioFile.writeFromBuffer error:", error)
              }
            }
        } else {
            let bufferSize: AUAudioFrameCount = 4096
            // inputNodeの出力バス(インデックス0)にタップをインストール
            // installTapOnBusの引数formatにnilを指定するとタップをインストールしたノードの出力バスのフォーマットを使用する
            // (この例だとフォーマットに inputNode.outputFormatForBus(0) を指定するのと同じ)
            // tapBlockはメインスレッドで実行されるとは限らないので注意
            mixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { (buffer, when) in
              do {
                // audioFileにバッファを書き込む
                try audioFile.write(from: buffer)
              } catch let error {
                print("audioFile.writeFromBuffer error:", error)
              }
            }
        }

        try? engine.start()
        recordingState = .recording
    }

    func stop() {
        if engine.isRunning {
            mixerNode.removeTap(onBus: 0)
            engine.stop()
            recordingState = .stopped
        }
    }

    func pause() {
        if recordingState.isRecording || recordingState.isResuming {
            engine.pause()
            recordingState = .paused
        }
    }

    func resume() {
        if recordingState.isPaused {
            try? engine.start()
            recordingState = .resuming
        }
    }

    func changeEffect(effect: AudioEffect = .none) {
        engine.reset()
        makeConnection(effect: effect)
    }

    func switchMuted(isMuted: Bool) {
        muteNode.volume = isMuted ? 0 : 1
    }

    private func setupEngine(effect: AudioEffect = .none) {
        makeConnection(effect: effect)
        engine.prepare()
    }

    private func makeConnection(effect: AudioEffect = .none) {
        engine.attach(mixerNode)
        engine.attach(muteNode)
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        engine.connect(inputNode, to: muteNode, format: inputFormat)
        switch effect {
        case .none:
            engine.connect(muteNode, to: mixerNode, format: inputFormat)
        case .delay:
            engine.attach(delayNode)
            delayNode.delayTime = 1
            engine.connect(muteNode, to: delayNode, format: inputFormat)
            engine.connect(delayNode, to: mixerNode, format: inputFormat)
        case .distortion(let preset):
            engine.attach(distortionNode)
            if let preset = preset {
                distortionNode.loadFactoryPreset(preset)
            }
            engine.connect(muteNode, to: distortionNode, format: inputFormat)
            engine.connect(distortionNode, to: mixerNode, format: inputFormat)
        case .eq:
            engine.attach(eqNode)
            engine.connect(muteNode, to: eqNode, format: inputFormat)
            engine.connect(eqNode, to: mixerNode, format: inputFormat)
        case .reverb(let preset):
            engine.attach(reverbNode)
            if let preset = preset {
                reverbNode.loadFactoryPreset(preset)
            }
            engine.connect(muteNode, to: reverbNode, format: inputFormat)
            engine.connect(reverbNode, to: mixerNode, format: inputFormat)
        }
        let mainMixerNode = engine.mainMixerNode
        let mixerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false)
        engine.connect(mixerNode, to: mainMixerNode, format: mixerFormat)
    }

    private func handleConfigurationChange() {
        if isConfigChangePending {
            makeConnection()
        }
        isConfigChangePending = false
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] (notification) in
            guard let self = self else { return }
            let interruptionTypeValue: UInt = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            let avInterruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeValue) ?? .began
            self.interruptionType = InterruptionType.parse(from: avInterruptionType)
            switch avInterruptionType {
            case .began:
                self.pause()
            case .ended:
                try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                self.handleConfigurationChange()
                // すぐにresumeしても、うまくplayできないバグがあるので、delayさせる
                // (Xcode12.1 - iOS12.1環境)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.resume()
                }
            @unknown default: fatalError()
            }
        }

        NotificationCenter.default.addObserver(forName: Notification.Name.AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] notification in
            guard let self = self else { return }
            self.isConfigChangePending = true
            if self.interruptionType == .notInterrupted {
                self.handleConfigurationChange()
            }
        }

        NotificationCenter.default.addObserver(
          forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            self.engine.reset()
            self.setupEngine()
        }
    }

    private func setupAudioSession() {
        do {
            // Audio Sessionを再生&録音モードに変更
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch let error {
            print("Failed to setup", error)
        }
    }
}
