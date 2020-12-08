//
//  PlayerViewController.swift
//  BroadcastSample
//
//  Created by Yugo Sugiyama on 2020/10/18.
//

// WWDC2018 Measuring and Optimizing HLS Performance
// https://developer.apple.com/videos/play/wwdc2018/502/

import UIKit
import AVFoundation
import MediaPlayer

final class PlayerViewController: UIViewController {

    @IBOutlet private weak var playerView: UIView!
    @IBOutlet private weak var backButton: UIButton!
    @IBOutlet private weak var forwardButton: UIButton!
    @IBOutlet private weak var muteButton: UIButton!

    @IBOutlet private weak var durationSlider: UISlider!
    @IBOutlet private weak var volumeSlider: UISlider!

    @IBOutlet private weak var mpVolumeContainerView: UIView!
    @IBOutlet private weak var timeControlStatusLabel: UILabel!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var rateLabel: UILabel!
    @IBOutlet private weak var currentTimeLabel: UILabel!
    @IBOutlet private weak var isMutedLabel: UILabel!

    @IBOutlet private weak var playbackLikelyToKeepUpLabel: UILabel!
    @IBOutlet private weak var durationLabel: UILabel!
    @IBOutlet private weak var loadedTimeRangesLabel: UILabel!
    @IBOutlet private weak var preferredForwardBufferDurationLabel: UILabel!
    @IBOutlet private weak var preferredMaximumResolutionLabel: UILabel!
    @IBOutlet private weak var preferredPeakBitRateLabel: UILabel!
    @IBOutlet private weak var presentationSizeLabel: UILabel!

    @IBOutlet weak var seekableTimeRangeLabel: UILabel!
    private let avPlayer = AVPlayer()
    private let avPlayerLayer = AVPlayerLayer()
    private var avPlayerItem: AVPlayerItem? {
        didSet {
            avPlayer.pause()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.itemDuration = CMTimeGetSeconds(self.avPlayerItem?.asset.duration ?? .zero)
                self.avPlayer.replaceCurrentItem(with: self.avPlayerItem)
                self.updateDurationSlider(time: .zero)
                self.removePlayerObserver()
                self.setupObserver()
                self.setupNotification()
            }
        }
    }
    private let mpVolumeView = MPVolumeView()
    private var observers: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var offsetDefaultTime: Double = 15 {
        didSet {
            backButton.setImage(UIImage(systemName: "gobackward.\(Int(offsetDefaultTime))"), for: .normal)
            forwardButton.setImage(UIImage(systemName: "goforward.\(Int(offsetDefaultTime))"), for: .normal)
        }
    }
    private var itemDuration: Double = 0
    private var isSliderDragging = false

    static func instance() -> PlayerViewController {
        return UIStoryboard(name: "Player", bundle: nil).instantiateInitialViewController() as! PlayerViewController
    }

    deinit {
        removePlayerObserver()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupAudioSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // ここに書かないと、avPlayerLayerのサイズが合わない
        avPlayerLayer.frame = playerView.frame
    }

    private func setupViews() {
        setupPlayer()
        offsetDefaultTime = 15
        switch avPlayer.timeControlStatus {
        case .playing: self.timeControlStatusLabel.text = "Playing"
        case .paused: self.timeControlStatusLabel.text = "Paused"
        case .waitingToPlayAtSpecifiedRate: self.timeControlStatusLabel.text = "WaitingToPlayAtSpecifiedRate"
        @unknown default: fatalError()
        }
        switch avPlayer.status {
        case .readyToPlay: self.statusLabel.text = "Ready to play"
        case .failed: self.statusLabel.text = "Failed"
        case .unknown: self.statusLabel.text = "unknown"
        @unknown default: fatalError()
        }
        rateLabel.text = "\(avPlayer.rate)"
        isMutedLabel.text = avPlayer.isMuted ? "True" : "False"
        guard let avPlayerItem = avPlayerItem else { return }
        playbackLikelyToKeepUpLabel.text = avPlayerItem.isPlaybackLikelyToKeepUp ? "True" : "False"
        preferredForwardBufferDurationLabel.text = "\(avPlayerItem.preferredForwardBufferDuration)"
        preferredMaximumResolutionLabel.text = "\(avPlayerItem.preferredMaximumResolution)"
        preferredPeakBitRateLabel.text = "\(avPlayerItem.preferredPeakBitRate)"
        // setup MPVolumeView
        mpVolumeContainerView.addSubview(mpVolumeView)
        mpVolumeView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mpVolumeView.topAnchor.constraint(equalTo: mpVolumeContainerView.topAnchor),
            mpVolumeView.leadingAnchor.constraint(equalTo: mpVolumeContainerView.leadingAnchor),
            mpVolumeContainerView.trailingAnchor.constraint(equalTo: mpVolumeView.trailingAnchor),
            mpVolumeContainerView.bottomAnchor.constraint(equalTo: mpVolumeView.bottomAnchor)
        ])
    }

    private func setupPlayer() {
        let avAsset = AVAsset(url: URL(string: "http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8")!)
        let avPlayerItem = AVPlayerItem(asset: avAsset)
        self.avPlayerItem = avPlayerItem
        playerView.layer.addSublayer(avPlayerLayer)
        avPlayerLayer.player = avPlayer
        avPlayerLayer.frame = playerView.frame
        avPlayerLayer.videoGravity = .resizeAspect
        avPlayerLayer.needsDisplayOnBoundsChange = true
    }

    private func removePlayerObserver() {
        guard let timeObserver = timeObserver else { return }
        avPlayer.removeTimeObserver(timeObserver)
        NotificationCenter.default.removeObserver(self)
    }

    private func changePosition(time: CMTime) {
        updateDurationSlider(time: time)
        let rate = avPlayer.rate
        avPlayer.rate = 0
        avPlayer.seek(to: time) { [weak self] completed in
            if !completed { return }
            self?.avPlayer.rate = rate
        }
    }

    private func offsetTime(offset: Double) {
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let rhs = CMTime(seconds: offset, preferredTimescale: timeScale)
        let time = CMTimeAdd(avPlayer.currentTime(), rhs)
        changePosition(time: time)
    }

    private func setVolume(volume: Float) {
        avPlayer.volume = volume
        volumeSlider.value = volume
        // Ref: https://qiita.com/pandapanda/items/1c87fa0115a8bcba51a6
        guard let slider = mpVolumeView.subviews.first(where: { $0 is UISlider }) as? UISlider else { return }
        slider.value = volume
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
            // https://gist.github.com/kazz12211/9d58af5c42ecbe35de58d66418412690
            volumeSlider.value = audioSession.outputVolume
            observers.append(audioSession.observe(\.outputVolume, options: .new) { [weak self] (_, value) in
                guard let self = self else { return }
                self.setVolume(volume: value.newValue ?? 0)
            })
            // サイレントモードでも音を鳴らす
            try audioSession.setCategory(.playback)
        } catch {
            print("Audio session setting error..")
        }
    }

    private func setupNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying(notification:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: avPlayer.currentItem)
    }

    private func setupObserver() {
        // AVPlayer
        observers.append(avPlayer.observe(\.timeControlStatus, options: .new, changeHandler: { [unowned self] (avPlayer, _) in
            // valueを使うと、nilになる
            switch avPlayer.timeControlStatus {
            case .playing: self.timeControlStatusLabel.text = "Playing"
            case .paused: self.timeControlStatusLabel.text = "Paused"
            case .waitingToPlayAtSpecifiedRate: self.timeControlStatusLabel.text = "waitingToPlayAtSpecifiedRate"
            @unknown default: fatalError()
            }
        }))
        observers.append(avPlayer.observe(\.status, options: .new, changeHandler: { [unowned self] (avPlayer, _) in
            // valueを使うと、nilになる
            switch avPlayer.status {
            case .readyToPlay: self.statusLabel.text = "Ready to play"
            case .failed: self.statusLabel.text = "Failed"
            case .unknown: self.statusLabel.text = "unknown"
            @unknown default: fatalError()
            }
        }))
        observers.append(avPlayer.observe(\.rate, options: .new, changeHandler: { [unowned self] (avPlayer, _) in
            self.rateLabel.text = "\(avPlayer.rate)"
        }))
        // Ref: https://qiita.com/roba4coding/items/142671f1518361d319a4
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: .init(seconds: 0.1, preferredTimescale: 1_000), queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = ceil(time.seconds * 10000) / 10000
            self.currentTimeLabel.text = "\(seconds)秒"
            if !self.isSliderDragging,
               self.avPlayer.timeControlStatus == .playing {
                self.updateDurationSlider(time: time)
            }
        }
        observers.append(avPlayer.observe(\.isMuted, options: .new, changeHandler: { [unowned self] (avPlayer, _) in
            self.isMutedLabel.text = avPlayer.isMuted ? "True" : "False"
        }))
        // AVPlayerItem
        observers.append(avPlayerItem!.observe(\.isPlaybackLikelyToKeepUp, options: .new, changeHandler: { [unowned self] (_, value) in
            guard let isPlaybackLikelyToKeepUp = value.newValue else { return }
            self.playbackLikelyToKeepUpLabel.text = isPlaybackLikelyToKeepUp ? "True" : "False"
        }))
        observers.append(avPlayerItem!.observe(\.duration, options: .new, changeHandler: { [unowned self] (_, value) in
            guard let time = value.newValue else { return }
            self.durationLabel.text = "\(CMTimeGetSeconds(time))秒"
        }))
        observers.append(avPlayerItem!.observe(\.loadedTimeRanges, options: .new, changeHandler: { [unowned self] (_, value) in
            guard let loadedTimeRanges = value.newValue, let timeRange = loadedTimeRanges.first as? CMTimeRange else { return }
            self.loadedTimeRangesLabel.text = "Start: \(timeRange.start.value), duration: \(timeRange.duration.value)"
        }))
        observers.append(avPlayerItem!.observe(\.preferredForwardBufferDuration, options: .new, changeHandler: { [unowned self] (_, value) in
            guard let preferredForwardBufferDuration = value.newValue else { return }
            self.preferredForwardBufferDurationLabel.text = "\(preferredForwardBufferDuration)"
        }))
        observers.append(avPlayerItem!.observe(\.preferredMaximumResolution, options: .new, changeHandler: { [unowned self] (_, value) in
            guard let preferredMaximumResolution = value.newValue else { return }
            self.preferredMaximumResolutionLabel.text = "\(preferredMaximumResolution)"
        }))
        observers.append(avPlayerItem!.observe(\.preferredPeakBitRate, options: .new, changeHandler: { [unowned self] (_, value) in
            guard let preferredPeakBitRate = value.newValue else { return }
            self.preferredPeakBitRateLabel.text = "\(preferredPeakBitRate)"
        }))
        observers.append(avPlayerItem!.observe(\.presentationSize, options: .new, changeHandler: { [unowned self] (_, value) in
            guard let presentationSize = value.newValue else { return }
            self.presentationSizeLabel.text = "\(presentationSize)"
        }))
        observers.append(avPlayerItem!.observe(\.seekableTimeRanges, options: .new, changeHandler: { [unowned self] (_, value) in
            guard let seekableTimeRanges = value.newValue, let timeRange = seekableTimeRanges.first as? CMTimeRange else { return }
            self.seekableTimeRangeLabel.text = "From: \(timeRange.start.value), duration: \(timeRange.duration.value)"
        }))
    }

    private func updateDurationSlider(time: CMTime) {
        DispatchQueue.main.async {
            if self.itemDuration != 0 {
                self.durationSlider.value = Float(CMTimeGetSeconds(time) / self.itemDuration)
            }
        }
    }

    @IBAction func play(_ sender: Any) {
        avPlayer.play()
    }

    @IBAction func stop(_ sender: Any) {
        avPlayer.pause()
    }

    @IBAction func back(_ sender: Any) {
        offsetTime(offset: -offsetDefaultTime)
    }

    @IBAction func forward(_ sender: Any) {
        offsetTime(offset: offsetDefaultTime)
    }
    
    @IBAction func mute(_ sender: Any) {
        avPlayer.isMuted.toggle()
        if avPlayer.isMuted {
            muteButton.setTitle("Mute OFF", for: .normal)
        } else {
            muteButton.setTitle("Mute ON", for: .normal)
        }
    }
    
    @IBAction func onDurationSliderValueChanged(_ sender: UISlider, forEvent event: UIEvent) {
        guard let touchEvent = event.allTouches?.first else { return }
        switch touchEvent.phase {
        case .began:
            isSliderDragging = true
        case .ended:
            let seconds = Double(sender.value) * itemDuration
            let timeScale = CMTimeScale(NSEC_PER_SEC)
            let time = CMTime(seconds: seconds, preferredTimescale: timeScale)
            changePosition(time: time)
            isSliderDragging = false
        case .cancelled:
            isSliderDragging = false
        default: break
        }
    }

    @IBAction func onVolumeSliderValueChanged(_ sender: UISlider) {
        setVolume(volume: sender.value)
    }

    @objc private func playerDidFinishPlaying(notification: NSNotification) {
        durationLabel.text = "\(CMTimeGetSeconds(avPlayer.currentTime()))秒"
    }

    @IBAction private func onPlaySpeedValueChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            avPlayer.rate = 0.5
        } else if sender.selectedSegmentIndex == 1 {
            avPlayer.rate = 1
        } else if sender.selectedSegmentIndex == 2 {
            avPlayer.rate = 2
        }
    }

    @IBAction private func onSkipSecondValueChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            offsetDefaultTime = 10
        } else if sender.selectedSegmentIndex == 1 {
            offsetDefaultTime = 15
        } else if sender.selectedSegmentIndex == 2 {
            offsetDefaultTime = 30
        }
    }

    @IBAction func onContentModeValueChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0: avPlayerLayer.videoGravity = .resizeAspect
        case 1: avPlayerLayer.videoGravity = .resizeAspectFill
        default: break
        }
    }
    
    @IBAction func onAssetValueChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex > 3 { return }
        let avAsset: AVAsset
        if sender.selectedSegmentIndex == 0 {
            avAsset = AVAsset(url: URL(string: "http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8")!)
        } else if sender.selectedSegmentIndex == 1 {
            avAsset = AVAsset(url: URL(string: "https://bitdash-a.akamaihd.net/content/MI201109210084_1/m3u8s/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.m3u8")!)
        } else if sender.selectedSegmentIndex == 2 {
            avAsset = AVAsset(url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!)
        } else {
            fatalError()
        }
        let avPlayerItem = AVPlayerItem(asset: avAsset)
        self.avPlayerItem = avPlayerItem
    }
}
