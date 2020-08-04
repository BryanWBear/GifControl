//
//  ModelProcessor.swift
//  Dancer
//
//  Created by Bryan Wang on 6/3/20.
//  Copyright © 2020 Bryan Wang. All rights reserved.
//

import Foundation
import Accelerate
import AVFoundation

class ModelProcessor {
    private var buffer: TPCircularBuffer
    var stft: CircularShortTimeFourierTransform
    private let nMels: Int
    private let dummyWindow: UnsafeMutablePointer<Float>
    private let inputSamples: UnsafeMutablePointer<Float>
    
    // this should be moved to a config file.
    private let nWindows: Int = 101
    private let inputSize: Int
    private let model: TorchModule
    public var currentPrediction = 0
    public var savedSamples: [Float] = []
    
    init(model: TorchModule, stft: CircularShortTimeFourierTransform, nMels: Int) {
        // create the circular buffer
        buffer = TPCircularBuffer()
        if !TPCircularBufferInit(&buffer, Int32(40*200*32*2)) {
            fatalError("Unable to allocate circular buffer.")
        }
        
        self.stft = stft
        self.nMels = nMels
        self.inputSize = nMels * self.nWindows
        self.model = model
        
        // preload buffer with samples so that we can start processing immediately.
        var preload = [Float](repeating: 0, count: self.inputSize)
        
        dummyWindow = UnsafeMutablePointer<Float>.allocate(capacity: self.inputSize)
        vDSP_vclr(dummyWindow, 1, vDSP_Length(self.inputSize))
        
        inputSamples = UnsafeMutablePointer<Float>.allocate(capacity: self.inputSize)
        vDSP_vclr(inputSamples, 1, vDSP_Length(self.inputSize))
        
        withUnsafePointer(to: &preload[0]) {
            up in
            if !TPCircularBufferProduceBytes(&buffer, up, Int32(self.inputSize * MemoryLayout<Float>.stride)) {
                fatalError("Insufficient space on buffer.")
            }
        }
    }
    
    deinit {
        // release the circular buffer
        TPCircularBufferCleanup(&buffer)
    }
    
    func processFourierData() -> Bool {
        // get the power information
        guard var power = self.stft.extractPower() else {
            return false
        }
        
//        print(power)
        self.savedSamples = self.savedSamples + power
                
        // append data to local circular buffer
        withUnsafePointer(to: &power[0]) {
            up in
            if !TPCircularBufferProduceBytes(&buffer, up, Int32(self.nMels * MemoryLayout<Float>.stride)) {
                fatalError("Insufficient space on buffer.")
            }
        }
        
        return true
    }
    
    func processNewValue() -> Int {
        // append all new fourier data
        var count = 0
        while processFourierData() { count += 1 }
        print("total number of samples: ", count)
        
        // let UnsafeMutablePointer<Float>: samples
        var availableBytes: Int32 = 0
        let samples: UnsafeMutablePointer<Float32>
        guard let p = TPCircularBufferTail(&buffer, &availableBytes) else {
            return 0
        }
        samples = p.bindMemory(to: Float32.self, capacity: Int(availableBytes) / MemoryLayout<Float32>.stride)
        
        print("available bytes: ", Int(availableBytes) / MemoryLayout<Float32>.stride)
        // not enough available bytes
        if Int(availableBytes) < (self.inputSize * MemoryLayout<Float>.stride) {
            print("not enough bytes on the buffer")
            return 0
        }

        
        // truncate samples; there should be a better way of doing this.
        vDSP_vadd(samples, 1, dummyWindow, 1, inputSamples, 1, UInt(self.inputSize))
        
//        self.savedSamples = self.savedSamples + Array(UnsafeBufferPointer(start:inputSamples, count: self.inputSize))
        
        // mark circular buffer as consumed at END of excution
        defer {
            print("consumed some bytes")
            // mark as consumed, one time per-time length
            // setting this to n so that we consume the same number of samples as we put on the buffer every cycle.
            // seems like the number changes depending on minor changes to the code.
            TPCircularBufferConsume(&buffer, Int32(4 * self.nMels * MemoryLayout<Float>.stride))
        }
        
        
        let preds = model.predict(image: UnsafeMutableRawPointer(inputSamples))!.map { $0.floatValue }
//        print("preds:", preds)
        
        // argmax, may need to do some guards here.
        currentPrediction = preds.indices.max(by: { preds[$0] < preds[$1] }) ?? -1
        
        print(currentPrediction)
        print("maxValue = ", preds.max() ?? -1)
        
        
        // set arbitrary threshold instead of doing a softmax, for speed purposes
        if (preds.max() ?? -1 > 10) {
            return currentPrediction
        }
        return 0
    }
}
