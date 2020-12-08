//
//  AudioEngineViewController.swift
//  BroadcastSample
//
//  Created by Yugo Sugiyama on 2020/11/07.
//

import UIKit
import AVFoundation

final class AudioEngineViewController: UIViewController {

    @IBOutlet private weak var recordEffectSegment: UISegmentedControl!
    @IBOutlet weak var isRecordingLabel: UILabel! {
        didSet { isRecordingLabel.text = RecordingState.stopped.rawValue }
    }
    @IBOutlet weak var interruptionTypeLabel: UILabel! {
        didSet { interruptionTypeLabel.text = InterruptionType.notInterrupted.rawValue }
    }
    @IBOutlet weak var audioTypeSegment: UISegmentedControl!
    
    @IBOutlet weak var audioEffectSegment: UISegmentedControl!
    @IBOutlet weak var isPlayingLabel: UILabel! {
        didSet { isPlayingLabel.text = AudioPlayingState.stopped.rawValue }
    }

    // For recorder
    private let recoder = Recorder()
    // For player
    private let audioPlayer = AudioPlayer()

    private let bgmRecorder =  BGMRecorder()

    private var observers: [NSKeyValueObservation] = []
    private var recordAudioPath: URL? {
        let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentDir.appendingPathComponent("/sample.caf")
    }
    private var audioPath: URL? {
        switch audioTypeSegment.selectedSegmentIndex {
        case 0:
            return recordAudioPath
        case 1:
            return URL(string: Bundle.main.path(forResource: "nocturne", ofType: "mp3")!)!
        case 2:
            return URL(string: Bundle.main.path(forResource: "toujyo", ofType: "mp3")!)!
        default: return nil
        }
    }
    private var audioFormat: AVAudioFormat? {
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: true)
    }
    private var audioFile: AVAudioFile? {
        guard let audioFilePath = recordAudioPath,
              let audioFormat = audioFormat else { return nil }

        // オーディオファイル
        return try? AVAudioFile(forWriting: audioFilePath, settings: audioFormat.settings)
    }

    static func instance() -> AudioEngineViewController {
        return UIStoryboard(name: "AudioEngine", bundle: nil).instantiateInitialViewController() as! AudioEngineViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupObserver()
//        setupAudioSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupEngine()
    }

    private func setupObserver() {
        recoder.didRecordingStateChanged = { [unowned self] recordingState in
            self.isRecordingLabel.text = recordingState.rawValue
        }
        recoder.didInterruptionTypeChanged = { [unowned self] interruptionType in
            self.interruptionTypeLabel.text = interruptionType.rawValue
        }
        audioPlayer.didAudioPlayingStateChanged = { [unowned self] audioState in
            self.isPlayingLabel.text = audioState.rawValue
        }
    }

    private func setupEngine() {
    }

    private func playAudio() {
        guard let audioPath = audioPath else {
            print("Audio file path is invalid!")
            return
        }
        let effect = AudioEffect.allCases[audioEffectSegment.selectedSegmentIndex]
        audioPlayer.play(resourceType: .audioFilePath(URL: audioPath), effect: effect)
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

    @IBAction func startRecord(_ sender: Any) {
        guard let recordAudioPath = recordAudioPath else { return }
        let effect = AudioEffect.allCases[recordEffectSegment.selectedSegmentIndex]
        recoder.changeEffect(effect: effect)
        recoder.start(path: recordAudioPath)
    }

    @IBAction func stopRecord(_ sender: Any) {
        recoder.stop()
    }

    @IBAction func pauseRecord(_ sender: Any) {
        recoder.pause()
    }

    @IBAction func resumeRecord(_ sender: Any) {
        recoder.resume()
    }

    @IBAction func muteSegmentValueChanged(_ sender: UISegmentedControl) {
        recoder.switchMuted(isMuted: sender.selectedSegmentIndex == 1)
    }

    @IBAction func startAudio(_ sender: Any) {
        playAudio()
    }

    @IBAction func stopAudio(_ sender: Any) {
        audioPlayer.stop()
    }

    @IBAction func resumeAudio(_ sender: Any) {
        audioPlayer.resume()
    }

    @IBAction func pauseAudio(_ sender: Any) {
        audioPlayer.pause()
    }

    @IBAction func recordWithBGMStart(_ sender: Any) {
    }

    @IBAction func recordWIthBGMStop(_ sender: Any) {

    }

    @IBAction func playBGM(_ sender: Any) {
        bgmRecorder.playBGM()
    }

    @IBAction func stopBGM(_ sender: Any) {
        bgmRecorder.pauseBGM()
    }
}
