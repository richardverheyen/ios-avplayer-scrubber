import UIKit
import AVFoundation
import SwiftUI

struct ScrubberRepresentable: UIViewRepresentable {
    var player: AVPlayer
    func makeUIView(context: Context) -> ScrubberView {
        let scrubberView = ScrubberView()
        scrubberView.player = player
        return scrubberView
    }
    
    func updateUIView(_ uiView: ScrubberView, context: Context) {
        // Implement any update logic
    }
}

class ScrubberView: UIView, UIScrollViewDelegate {
    var player: AVPlayer? {
        didSet {
            playerRateObserver?.invalidate() // Invalidate the old observer
            setupPlayerObserver()
        }
    }
    private let scrollView = UIScrollView()
    private let cursorView = UIView()
    private let tooltipLabel = UILabel()
    private var isUserInteracting = false
    private var observer: Any?
    private var wasPlayingBeforeGesture = false // Track the play state before the gesture
    private var playerRateObserver: NSKeyValueObservation?
    private var zoomFactor: CGFloat = 1.0 // Add this line

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Configure scrollView
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delegate = self // Make sure ScrubberView is the delegate of scrollView
        addSubview(scrollView)

        // Configure cursorView
        cursorView.backgroundColor = .red // Cursor color
        cursorView.layer.borderWidth = 1
        cursorView.layer.borderColor = UIColor.black.cgColor
        addSubview(cursorView)
        
        tooltipLabel.backgroundColor = .black // Customize as needed
        tooltipLabel.textColor = .white
        tooltipLabel.textAlignment = .center
        tooltipLabel.layer.cornerRadius = 5
        tooltipLabel.layer.masksToBounds = true
        tooltipLabel.text = "00:00"
        addSubview(tooltipLabel)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        scrollView.addGestureRecognizer(tapGesture)
        
        // Add this line to set up the pinch gesture
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        scrollView.addGestureRecognizer(pinchGesture)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Add this method to handle pinch gestures
    @objc private func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            let scale = gesture.scale
            zoomFactor *= scale
            gesture.scale = 1.0
            setupScrubberStrip()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = self.bounds
        scrollView.contentInset = UIEdgeInsets(top: 0, left: self.bounds.width / 2, bottom: 0, right: self.bounds.width / 2)
        cursorView.frame = CGRect(x: (bounds.width - 2) / 2, y: 0, width: 3, height: bounds.height) // Center-aligned cursor
        
        let tooltipHeight: CGFloat = 20
        let tooltipWidth: CGFloat = 50
        tooltipLabel.frame = CGRect(x: (bounds.width - tooltipWidth) / 2, y: -tooltipHeight - 5, width: tooltipWidth, height: tooltipHeight)
        
        // Ensure the scrubber is configured whenever the layout is updated
        setupScrubberStrip()
    }
    
    private func setupScrubberStrip() {
        // Clear existing subviews in the scrollView
        scrollView.subviews.forEach({ $0.removeFromSuperview() })

        let baseSegmentWidth: CGFloat = 80.0 // Base width for whole second segments
        let videoDuration = player?.currentItem?.asset.duration.seconds ?? 0
        
        // Calculate the segment duration based on the zoom factor
        let segmentDuration = max(1, Int(round(1 / zoomFactor)))
        let numberOfFullSegments = Int(videoDuration) / segmentDuration
        let fractionalPart = videoDuration - Double(numberOfFullSegments * segmentDuration)

        var totalWidth: CGFloat = 0

        // Create segments for full durations
        for i in 0..<numberOfFullSegments {
            let segmentStartTime = i * segmentDuration
            let segmentWidth = baseSegmentWidth * zoomFactor * CGFloat(segmentDuration)
            let segmentView = createSegmentView(startTime: segmentStartTime, width: segmentWidth)
            segmentView.frame.origin.x = totalWidth
            scrollView.addSubview(segmentView)
            totalWidth += segmentView.frame.width
        }

        // Add fractional segment if needed
        if fractionalPart > 0 {
            let segmentStartTime = numberOfFullSegments * segmentDuration
            let segmentWidth = baseSegmentWidth * zoomFactor * CGFloat(fractionalPart)
            let segmentView = createSegmentView(startTime: segmentStartTime, width: segmentWidth)
            segmentView.frame.origin.x = totalWidth
            scrollView.addSubview(segmentView)
            totalWidth += segmentView.frame.width
        }

        // Adjust scrollView contentSize to fit all segments
        scrollView.contentSize = CGSize(width: totalWidth, height: scrollView.frame.height)
        
        // Center the zoomed position
        let currentTime = player?.currentTime().seconds ?? 0
        let progress = currentTime / videoDuration
        let contentOffsetX = CGFloat(progress * totalWidth) - scrollView.bounds.width / 2
        scrollView.setContentOffset(CGPoint(x: contentOffsetX, y: 0), animated: false)
    }
    
    private func createSegmentView(startTime: Int, width: CGFloat) -> UIView {
        let segmentView = UIView(frame: CGRect(x: CGFloat(startTime) * width / CGFloat(max(1, Int(round(1 / zoomFactor)))), y: 0, width: width, height: scrollView.frame.height))
        segmentView.backgroundColor = .clear
        segmentView.layer.borderWidth = 1.0
        segmentView.layer.borderColor = UIColor.white.cgColor
        
        let timestampLabel = UILabel(frame: CGRect(x: 4, y: 0, width: width - 8, height: 20))
        timestampLabel.text = formatDuration(seconds: startTime)
        timestampLabel.textColor = .white
        segmentView.addSubview(timestampLabel)
        
        return segmentView
    }
    
    private func formatDuration(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes > 0 {
            return String(format: "%dm %ds", minutes, remainingSeconds)
        } else {
            return String(format: "%ds", remainingSeconds)
        }
    }
    
    private func setupPlayerObserver() {
        guard let player = player else { return }

        player.seek(to: CMTimeMakeWithSeconds(0, preferredTimescale: Int32(NSEC_PER_SEC)), toleranceBefore: .zero, toleranceAfter: .zero)
        
        // Remove any existing observer to avoid duplicates
        if let observer = observer {
            player.removeTimeObserver(observer)
            self.observer = nil
        }

        // Add a periodic time observer to the player
        observer = player.addPeriodicTimeObserver(forInterval: CMTimeMakeWithSeconds(0.0333, preferredTimescale: Int32(NSEC_PER_SEC)), queue: DispatchQueue.main) { [weak self] _ in
            guard let self = self, !self.isUserInteracting else { return }
            self.updateScrubberPositionBasedOnPlayback()
        }

        // Observe the player's rate property to update the visual indicator
        playerRateObserver = player.observe(\.rate, options: [.new, .old]) { [weak self] (player, change) in
            DispatchQueue.main.async {
                self?.updateVisualIndicator(isPlaying: player.rate > 0)
            }
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // User interaction begins
        wasPlayingBeforeGesture = player?.rate ?? 0 > 0
        player?.pause()
        isUserInteracting = true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let duration = player?.currentItem?.duration.seconds, duration > 0, isUserInteracting else { return }
        
        // This block is only entered if the user is actively dragging the scrollView.
        let contentOffsetX = scrollView.contentOffset.x + self.bounds.width / 2
        let totalContentWidth = scrollView.contentSize.width
        let progress = contentOffsetX / totalContentWidth
        let newTimeInSeconds = Double(progress) * duration
        
        tooltipLabel.text = formatTime(seconds: newTimeInSeconds)
        
        let newTime = CMTimeMakeWithSeconds(newTimeInSeconds, preferredTimescale: Int32(NSEC_PER_SEC))
        player?.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    private func formatTime(seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        formatter.unitsStyle = .positional
        return formatter.string(from: seconds) ?? "00:00"
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // User interaction ends without deceleration
        if !decelerate {
            handlePlaybackResumption()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // User interaction ends with deceleration
        handlePlaybackResumption()
    }

    private func handlePlaybackResumption() {
        if wasPlayingBeforeGesture {
            player?.play()
        }
        isUserInteracting = false
    }

    private func updateScrubberPositionBasedOnPlayback() {
        guard let player = player, let duration = player.currentItem?.duration.seconds, duration > 0 else { return }

        // Only update the scrubber's position if the user is not currently interacting with it.
        if !isUserInteracting {
            let currentTime = player.currentTime().seconds
            tooltipLabel.text = formatTime(seconds: currentTime)
            let progress = currentTime / duration

            // Calculate the new content offset without interrupting the user's scroll
            let contentOffsetX = calculateContentOffsetX(progress: progress)

            // Use DispatchQueue to ensure the UI update is performed on the main thread.
            DispatchQueue.main.async {
                self.scrollView.setContentOffset(CGPoint(x: contentOffsetX, y: 0), animated: false)
            }
        }
    }

    private func calculateContentOffsetX(progress: Double) -> CGFloat {
        let stripContentWidth = scrollView.contentSize.width
        let appWidth = scrollView.bounds.width
        // To move the strip in the opposite direction, calculate the offset from the end
        let contentOffsetX = CGFloat(progress * stripContentWidth) - appWidth / 2

        return contentOffsetX
    }
    
    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        guard let player = player else { return }
        
        let duration = player.currentItem?.duration.seconds
        let currentTime = player.currentTime().seconds
        
        if player.rate > 0 {
            player.pause()
            updateVisualIndicator(isPlaying: false)
        } else {
            if duration != nil && currentTime >= duration! {
                player.seek(to: CMTimeMakeWithSeconds(0, preferredTimescale: Int32(NSEC_PER_SEC)), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.play()
            updateVisualIndicator(isPlaying: true)
        }
    }
    
    private func updateVisualIndicator(isPlaying: Bool) {
        // Change cursorView color based on play state
        cursorView.backgroundColor = isPlaying ? .green : .red
    }
    
    deinit {
        if let observer = observer {
            player?.removeTimeObserver(observer)
        }
        playerRateObserver?.invalidate()
    }
}
