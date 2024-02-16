import UIKit
import AVFoundation
import SwiftUI

// ScrubberView Features:
// 1. Two-way binding between video playback and scrubber movement: The scrubber's position updates in real-time as the video plays, and manually scrubbing updates the video playback position accordingly.
// 2. Dynamic scrubber strip composed of colored rectangles for visual guidance, with each segment representing a specific duration of video playback time for easy reference.
// 3. Central cursor indicating the current playback position with a distinct visual style (white background and black border) for clear visibility.
// 4. User interaction with the scrubber allows seeking through the video: Dragging the scrubber pauses video playback and updates the playback time based on the scrubber's position. Releasing the scrubber resumes playback from the new position, respecting the original play state (playing or paused).
// 5. Pan gesture recognition for manual scrubbing with intelligent play/pause functionality: Initiating a pan gesture on the scrubber temporarily alters the playback state for the duration of the interaction, with the video resuming its original state (playing or paused) once the gesture ends.
// 6. Continuous update of scrubber position in sync with video playback, providing real-time feedback on the current video time.
// 7. Utilizes UIScrollView for the scrubber strip, facilitating smooth scrolling interactions and visual feedback during manual scrubbing.
// 8. Scrubber Strip Position and Width Binding: The scrubber's visual representation dynamically adjusts based on video playback, with the strip's movement directly linked to the video's current time, ensuring accurate scrubbing feedback.
// 9. Segment Representation: Visual segments within the scrubber strip indicate video playback time, with each segment sized to represent a fixed duration and labeled with timestamps for easy navigation.


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
            configureScrubberForVideoDuration()
        }
    }
    private let scrollView = UIScrollView()
    private let cursorView = UIView()
    private var isUserInteracting = false
    private var observer: Any?
    private var wasPlayingBeforeGesture = false // Track the play state before the gesture
    private var playerRateObserver: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupViews() {
        // Configure scrollView
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delegate = self // Make sure ScrubberView is the delegate of scrollView
        addSubview(scrollView)

        // Configure cursorView
        cursorView.backgroundColor = .white // Cursor color
        cursorView.layer.borderWidth = 1
        cursorView.layer.borderColor = UIColor.black.cgColor
        addSubview(cursorView)
        
        // Add tap gesture recognizer to toggle play/pause
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        scrollView.addGestureRecognizer(tapGesture)
    }
    
    private func configureScrubberForVideoDuration() {
        // This method needs to be called after the player is set to adjust the scrubber based on the video's duration
        guard let duration = player?.currentItem?.asset.duration.seconds, duration > 0 else { return }
        let numberOfSegments = Int(ceil(duration))
        setupScrubberStrip()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = self.bounds
        cursorView.frame = CGRect(x: (bounds.width - 2) / 2, y: 0, width: 3, height: bounds.height) // Center-aligned cursor
        
        // Ensure the scrubber is configured whenever the layout is updated
        configureScrubberForVideoDuration()
    }
    
    private func setupScrubberStrip() {
        // Clear existing subviews in the scrollView
        scrollView.subviews.forEach({ $0.removeFromSuperview() })

        let fullSegmentWidth: CGFloat = 80.0 // Width for whole second segments
        let videoDuration = player?.currentItem?.asset.duration.seconds ?? 0
        let numberOfFullSegments = Int(videoDuration) // Full second segments
        let fractionalPart = videoDuration - Double(numberOfFullSegments) // Fractional second
        let fractionalSegmentWidth = fullSegmentWidth * CGFloat(fractionalPart) // Width for the fractional second segment

        var totalWidth: CGFloat = 0

        // Create segments for full seconds
        for i in 0..<numberOfFullSegments {
            let segmentView = createSegmentView(index: i, width: fullSegmentWidth)
            scrollView.addSubview(segmentView)
            totalWidth += segmentView.frame.width
        }

        // Add fractional segment if needed
        if fractionalPart > 0 {
            let segmentView = createSegmentView(index: numberOfFullSegments, width: fractionalSegmentWidth)
            scrollView.addSubview(segmentView)
            totalWidth += segmentView.frame.width
        }

        // Adjust scrollView contentSize to fit all segments
        scrollView.contentSize = CGSize(width: totalWidth, height: scrollView.frame.height)
    }
    
    private func createSegmentView(index: Int, width: CGFloat) -> UIView {
        let segmentView = UIView(frame: CGRect(x: CGFloat(index) * 80, y: 0, width: width, height: scrollView.frame.height))
        segmentView.backgroundColor = index % 2 == 0 ? .blue : .purple
        segmentView.layer.borderWidth = 1.0
        segmentView.layer.borderColor = UIColor.black.cgColor
        
        let timestampLabel = UILabel(frame: CGRect(x: 4, y: (segmentView.frame.height - 20) / 2, width: width - 8, height: 20))
        timestampLabel.text = "\(index)"
        timestampLabel.textColor = .white
        segmentView.addSubview(timestampLabel)
        
        return segmentView
    }
    
    private func setupPlayerObserver() {
        guard let player = player else { return }

        // Remove any existing observer to avoid duplicates
        if let observer = observer {
            player.removeTimeObserver(observer)
            self.observer = nil
        }

        // Add a periodic time observer to the player
        observer = player.addPeriodicTimeObserver(forInterval: CMTimeMakeWithSeconds(0.1, preferredTimescale: Int32(NSEC_PER_SEC)), queue: DispatchQueue.main) { [weak self] _ in
            guard let self = self, !self.isUserInteracting else { return }
            self.updateScrubberPositionBasedOnPlayback()
        }

        // Observe the player's rate property to update the visual indicator
        playerRateObserver = player.observe(\.rate, options: [.new, .old]) { [weak self] (player, change) in
            DispatchQueue.main.async {
                self?.updateVisualIndicator(isPlaying: player.rate > 0)
            }
        }
        
        // Add periodic time observer for playback position update
        observer = player.addPeriodicTimeObserver(forInterval: CMTimeMakeWithSeconds(0.1, preferredTimescale: Int32(NSEC_PER_SEC)), queue: DispatchQueue.main) { [weak self] _ in
            guard let strongSelf = self, !strongSelf.isUserInteracting else { return }
            
            // Calculate the new content offset based on the player's current time
            if let duration = strongSelf.player?.currentItem?.duration.seconds, duration > 0 {
                let currentTime = strongSelf.player?.currentTime().seconds ?? 0
                let progress = currentTime / duration
                let contentOffsetX = strongSelf.calculateContentOffsetX(progress: progress)
                strongSelf.scrollView.setContentOffset(CGPoint(x: contentOffsetX, y: 0), animated: false)
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
        let contentOffsetX = scrollView.contentOffset.x
        let totalContentWidth = scrollView.contentSize.width
        let progress = contentOffsetX / totalContentWidth
        let newTimeInSeconds = Double(progress) * duration
        
        let newTime = CMTimeMakeWithSeconds(newTimeInSeconds, preferredTimescale: Int32(NSEC_PER_SEC))
        player?.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
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
            let progress = currentTime / duration

            // Calculate the new content offset without interrupting the user's scroll
            let contentOffsetX = calculateContentOffsetX(progress: progress)

            // Use DispatchQueue to ensure the UI update is performed on the main thread.
            DispatchQueue.main.async {
                // Animate the content offset change to smooth out the update when the user is not interacting.
                UIView.animate(withDuration: 0.1, animations: {
                    self.scrollView.setContentOffset(CGPoint(x: contentOffsetX, y: 0), animated: false)
                })
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

        if player.rate > 0 {
            player.pause()
            updateVisualIndicator(isPlaying: false)
        } else {
            player.play()
            updateVisualIndicator(isPlaying: true)
        }
    }
    
    private func updateVisualIndicator(isPlaying: Bool) {
        // Change cursorView color based on play state
        cursorView.backgroundColor = isPlaying ? .green : .red
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard let player = player, let duration = player.currentItem?.duration else { return }

        switch gesture.state {
        case .began:
            // Check if the video was playing before starting the gesture
            wasPlayingBeforeGesture = player.rate > 0
            player.pause()
            isUserInteracting = true
        case .changed:
            let translation = gesture.translation(in: scrollView)
            let currentOffset = scrollView.contentOffset.x
            scrollView.setContentOffset(CGPoint(x: currentOffset - translation.x, y: 0), animated: false)
            gesture.setTranslation(.zero, in: scrollView) // Reset translation to zero

            // Calculate the new time based on the scrollView's content offset
            let totalVideoDuration = duration.seconds
            let percentageOfVideo = (scrollView.contentOffset.x + scrollView.bounds.width / 2) / scrollView.contentSize.width
            let newTimeInSeconds = Double(percentageOfVideo) * totalVideoDuration
            
            // Seek to the new time without interrupting the user interaction
            let newTime = CMTimeMakeWithSeconds(newTimeInSeconds, preferredTimescale: Int32(NSEC_PER_SEC))
            player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
        case .ended, .cancelled:
            // Resume playing only if the video was playing before the gesture began
            if wasPlayingBeforeGesture {
                player.play()
            }
            isUserInteracting = false
        default:
            break
        }
    }
    
    deinit {
        if let observer = observer {
            player?.removeTimeObserver(observer)
        }
        playerRateObserver?.invalidate()
    }
}
