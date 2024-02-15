//
//  ContentView.swift
//  scrubber
//
//  Created by Richard Verheyen on 11/2/2024.
//

import SwiftUI
import AVKit
import Foundation


struct ContentView: View {
    private var player: AVPlayer?
    
    init() {
        // Attempt to load the video from the app bundle
        if let videoURL = Bundle.main.url(forResource: "sample4", withExtension: "mp4") {
            self.player = AVPlayer(url: videoURL)
        } else {
            print("Video file not found.")
            self.player = nil
        }
    }
    
    var body: some View {
        VStack {
            if let player = player {
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                ScrubberRepresentable(player: player)
                    .frame(height: 50) // Adjust the frame as necessary
            } else {
                Text("Video file not found.")
            }
        }
    }
}
struct VideoPlayerView: View {
    let videoURL: URL
    @State private var currentTime: CGFloat = 0.0
    private var player: AVPlayer

    init(videoURL: URL) {
        self.videoURL = videoURL
        self.player = AVPlayer(url: videoURL)
    }

    var body: some View {
        VStack(spacing: 0) { // Remove the default spacing between VStack elements
            VideoPlayer(player: player)
                .edgesIgnoringSafeArea(.all)
        }
    }
}

#Preview {
    ContentView()
}
