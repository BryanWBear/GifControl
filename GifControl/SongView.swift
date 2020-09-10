//
//  SongView.swift
//  MusicVoice
//
//  Created by Bryan Wang on 9/9/20.
//  Copyright © 2020 Bryan Wang. All rights reserved.
//

import SwiftUI
import StoreKit
import MediaPlayer
import SDWebImageSwiftUI

struct SongView: View {
    @State private var searchText = ""
    @State private var searchResults = [Song]()
    @Binding var musicPlayer: MPMusicPlayerController
    @Binding var currentSong: Song
    
    var body: some View {
        VStack {
            TextField("Search Songs", text: $searchText, onCommit: {
                // 1
                UIApplication.shared.resignFirstResponder()
                if self.searchText.isEmpty {
                    // 2
                    self.searchResults = []
                } else {
                    // 3
                    SKCloudServiceController.requestAuthorization { (status) in
                        if status == .authorized {
                            // 4
                            self.searchResults = AppleMusicAPI().searchAppleMusic(self.searchText)
                        }
                    }
                }
            })
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal, 16)
            .accentColor(.pink)
            List {
                // 1
                ForEach(searchResults, id:\.id) { song in
                    // 2
                    HStack {
                        // 3
                        WebImage(url: URL(string: song.artworkURL.replacingOccurrences(of: "{w}", with: "80").replacingOccurrences(of: "{h}", with: "80")))
                            .resizable()
                            .frame(width: 40, height: 40)
                            .cornerRadius(5)
                            .shadow(radius: 2)
             
                        // 4
                        VStack(alignment: .leading) {
                            // 1
                            Text(song.name)
                                .font(.headline)
                            // 2
                            Text(song.artistName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        // 5
                        Button(action: {
                            self.currentSong = song
                            self.musicPlayer.setQueue(with: [song.id])
                            self.musicPlayer.play()
                        }) {
                            Image(systemName: "play.fill")
                                .foregroundColor(.pink)
                        }
                    }
                }
            }
            .accentColor(.pink)
        }
    }
}

//struct SongView_Previews: PreviewProvider {
//    static var previews: some View {
//        SongView()
//    }
//}
