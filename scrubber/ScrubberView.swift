import UIKit
import AVFoundation
import SwiftUI

// ScrubberView Features:
// 1. Two-way binding between video playback and scrubber movement.
// 2. Dynamic scrubber strip made of colored rectangles for visual guidance.
// 3. Central cursor indicating current playback position with a white background and black border.
// 4. User interaction with the scrubber to seek through the video.
// 5. Automatic scrubber movement in sync witha video playback.
// 6. Pan gesture recognition for manual scrubbing with pause/resume functionality.
// 7. Continuous update of scrubber position based on video playback time.
// 8. Utilizes UIScrollViewDelegate to handle scroll events and user interactions.
// 9. Scrubber Strip Position and Width Binding: The width of the scrubber strip is fixed, but its position relative to the cursor changes based on the video playback time. Initially, the strip is positioned so that it covers half the screen width to the right of the cursor, indicating the start of the video. As the video plays, the strip moves left, and by the end of the video, it covers half the screen width to the left of the cursor. This behavior visually represents the video's progress and prevents scrolling beyond the video's start and end points.
// 10. Segment Representation: Each 80px wide segment of the scrubber strip represents 1 second of video playback time, with timestamps and a border on the left side for clear demarcation.

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
            setupPlayerObserver()
            configureScrubberForVideoDuration()
        }
    }
    private let scrollView = UIScrollView()
    private let cursorView = UIView()
    private var isUserInteracting = false
    private var observer: Any?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        cursorView.frame = CGRect(x: (bounds.width - 2) / 2, y: 0, width: 2, height: bounds.height) // Center-aligned cursor
        
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
    
    private func setupViews() {
        // Configure scrollView
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delegate = self
        addSubview(scrollView)
        
        // Configure cursorView
        cursorView.backgroundColor = .white // Cursor color
        cursorView.layer.borderWidth = 1
        cursorView.layer.borderColor = UIColor.black.cgColor
        addSubview(cursorView)
        
        // Add pan gesture recognizer to the scrollView
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        scrollView.addGestureRecognizer(panGesture)
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
    }

    private func updateScrubberPositionBasedOnPlayback() {
        guard let player = player, let duration = player.currentItem?.duration.seconds, duration > 0 else { return }
        
        let currentTime = player.currentTime().seconds
        let progress = currentTime / duration
        
        // Adjust contentOffsetX calculation here
        let contentOffsetX = calculateContentOffsetX(progress: progress)
        scrollView.setContentOffset(CGPoint(x: contentOffsetX, y: 0), animated: true)
    }

    private func calculateContentOffsetX(progress: Double) -> CGFloat {
        let stripContentWidth = scrollView.contentSize.width
        let appWidth = scrollView.bounds.width
        // To move the strip in the opposite direction, calculate the offset from the end
        let contentOffsetX = CGFloat(progress * stripContentWidth) - appWidth / 2

        return contentOffsetX
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard let player = player, let item = player.currentItem else { return }

        switch gesture.state {
        case .began:
            player.pause()
            isUserInteracting = true
        case .changed:
            let translation = gesture.translation(in: scrollView).x
            let percentage = translation / scrollView.contentSize.width
            let seekTime = item.duration.seconds * Double(percentage)
            let time = CMTime(seconds: seekTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            gesture.setTranslation(.zero, in: scrollView)
        case .ended, .cancelled:
            player.play()
            isUserInteracting = false
        default:
            break
        }
    }
    
    deinit {
        if let observer = observer {
            player?.removeTimeObserver(observer)
        }
    }
}
