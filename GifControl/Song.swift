//
//  Song.swift
//  MusicVoice
//
//  Created by Bryan Wang on 9/9/20.
//  Copyright © 2020 Bryan Wang. All rights reserved.
//

import Foundation

struct Song {
    var id: String
    var name: String
    var artistName: String
    var artworkURL: String
 
    init(id: String, name: String, artistName: String, artworkURL: String) {
        self.id = id
        self.name = name
        self.artworkURL = artworkURL
        self.artistName = artistName
    }
}
