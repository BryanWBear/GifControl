//
//  GifView.swift
//  GifControl
//
//  Created by Bryan Wang on 8/1/20.
//  Copyright © 2020 Bryan Wang. All rights reserved.
//

import SwiftUI
import Gifu

struct GifView: UIViewRepresentable {
    func makeUIView(context: Context) -> GIFImageView {
        let imageView = GIFImageView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        // sizing doesn't work
//        imageView.prepareForAnimation(withGIFNamed: "mushroom") {
//          print("Ready to animate!")
//        }
        return imageView
    }

    func updateUIView(_ uiView: GIFImageView, context: Context) {
        uiView.animate(withGIFNamed: "mushroom")
    }
}

struct GifView_Previews: PreviewProvider {
    static var previews: some View {
        GifView()
    }
}
