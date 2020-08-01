//
//  ContentView.swift
//  GifControl
//
//  Created by Bryan Wang on 8/1/20.
//  Copyright © 2020 Bryan Wang. All rights reserved.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var viewModel: ViewModel = ViewModel()

    var body: some View {
        GifView().onAppear {
            do {
                try self.viewModel.startRecording()
            }
            catch {
                print("cannot record")
            }
        }
    }
}

extension ContentView {
    class ViewModel: ObservableObject {
        @Published var currentText = "No Input"
        let audioEngine = AVAudioEngine()
        var savedBuff: [Float] = []
        var count: Int = 0
        let speechSampleRate: Int = 16000
        
        
//        golden advice
//        https://forums.developer.apple.com/thread/73560
        func startRecording() throws {
            let queue = DispatchQueue(label: "ProcessorQueue")
            let stft = CircularShortTimeFourierTransform(windowLength: 512, hop: 160, fftSizeOf: 512, sampleRate: speechSampleRate)
            guard let filePathModel: String = Bundle.main.path(forResource: "traced_model_luckier", ofType: "pt") else {
                return }
            let model = TorchModule(fileAtPath: filePathModel)!
            let modelProcessor = ModelProcessor(model: model, stft: stft, nMels: 40)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setPreferredSampleRate(Double(speechSampleRate))

//          want a 10 ms hop (160 samples for a SR of 16000)
            
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0 )
            guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else{
                print("couldn't initialize AVAudioConverter")
                return
            }
            
            inputNode.installTap(onBus: 0, bufferSize: 160, format: inputFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
                if let tail = buffer.floatChannelData?[0] {
                    print("appending raw samples: ", Int(buffer.frameLength))
                    modelProcessor.stft.appendData(tail, withSamples: Int(buffer.frameLength))
                }
                queue.async {
                    while true {
                        let value = modelProcessor.processNewValue()
                        if (value == 11) {
                            DispatchQueue.main.async{
                                self.currentText = "Go"
                            }
                        }
                        else if (value == 27) {
                            DispatchQueue.main.async{
                                self.currentText = "Stop"
                            }
                        }
                        
                    }
                }
            }

            audioEngine.prepare()
            print("done preparing the engine")

            try audioEngine.start()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
