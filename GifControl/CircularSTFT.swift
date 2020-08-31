//
//  CircularSTFT.swift
//  FinalDancer
//
//  Created by Bryan Wang on 6/3/20.
//  Copyright © 2020 Bryan Wang. All rights reserved.
//

//
//  CircularShortTimeFourierTransform.swift
//  SongDetector
//
//  Created by Nathan Perkins on 9/4/15.
//  Copyright © 2015 Gardner Lab. All rights reserved.
//

import Foundation
import Accelerate

enum WindowType
{
    case none
    case hamming
    case hanning
    case blackman
    
    func createWindow(_ pointer: UnsafeMutablePointer<Float>, len: Int) {
        switch self {
        case .none:
            var one: Float = 1.0
            vDSP_vfill(&one, pointer, 1, vDSP_Length(len))
        case .hamming: vDSP_hamm_window(pointer, vDSP_Length(len), 0)
        case .hanning: vDSP_hann_window(pointer, vDSP_Length(len), 0)
        case .blackman: vDSP_blkman_window(pointer, vDSP_Length(len), 0)
        }
    }
}

func isPowerOfTwo(_ n: Int) -> Bool {
    return (n > 0) && (n & (n - 1) == 0)
}

class CircularShortTimeFourierTransform
{
    private var buffer: TPCircularBuffer
    
    let lengthFft: Int // power of 2
    let lengthWindow: Int
    let nMels: Int
    
    let hop: Int // hop amount
    
    var melFilters: Melcepstrum
    
    private let fftSize: vDSP_Length
    private let fftSetup: FFTSetup
    
    var windowType = WindowType.hanning {
        didSet {
            resetWindow()
        }
    }
    
    // store actual window
    private let window: UnsafeMutablePointer<Float>
    
    // store windowed values
    private let samplesWindowed: UnsafeMutablePointer<Float>
    
    // reusable memory
    private var complexBufferA: DSPSplitComplex
    private var complexBufferT: DSPSplitComplex
    private let forwardDCTSetup: vDSP.DCT?
    
    init(windowLength lengthWindow: Int = 1024, hop: Int = 0, fftSizeOf theLengthFft: Int? = nil, buffer: Int = 409600, sampleRate: Int = 44100, nMels: Int = 32) {
        // length of the fourier transform (must be a power of 2)
        self.lengthWindow = lengthWindow
        self.nMels = nMels
        
        self.hop = hop
        
        // sanity check
        if hop >= lengthWindow {
            fatalError("Invalid overlap value.")
        }
        
        
        // calculate fft
        if let v = theLengthFft {
            guard isPowerOfTwo(v) else {
                fatalError("The FFT size must be a power of 2.")
            }
            
            guard lengthWindow <= v else {
                fatalError("The FFT size must be greater than or equal to the window length.")
            }
            
            lengthFft = v
            fftSize = vDSP_Length(ceil(log2(CDouble(v))))
        }
        else {
            // automatically calculate
            fftSize = vDSP_Length(ceil(log2(CDouble(lengthWindow))))
            lengthFft = 1 << Int(fftSize)
        }
        
        self.melFilters = Melcepstrum(nFFT: lengthWindow, sampleRate: sampleRate, nMels: nMels)
        
        // maybe use lazy instantion?
        
        // setup fft
        fftSetup = vDSP_create_fftsetup(fftSize, FFTRadix(kFFTRadix2))!
        
        // setup window
        window = UnsafeMutablePointer<Float>.allocate(capacity: lengthWindow)
        windowType.createWindow(window, len: lengthWindow)
        
        // setup windowed samples
        samplesWindowed = UnsafeMutablePointer<Float>.allocate(capacity: lengthFft)
        vDSP_vclr(samplesWindowed, 1, vDSP_Length(lengthFft))
        
        // half length (for buffer allocation)
        let halfLength = lengthFft / 2
        
        // setup complex buffers
        complexBufferA = DSPSplitComplex(realp: UnsafeMutablePointer<Float>.allocate(capacity: halfLength), imagp: UnsafeMutablePointer<Float>.allocate(capacity: halfLength))
        // to get desired alignment..
        let alignment: Int = 0x10
        let ptrReal = UnsafeMutableRawPointer.allocate(byteCount: halfLength * MemoryLayout<Float>.stride, alignment: alignment)
        let ptrImag = UnsafeMutableRawPointer.allocate(byteCount: halfLength * MemoryLayout<Float>.stride, alignment: alignment)
        
        complexBufferT = DSPSplitComplex(realp: ptrReal.bindMemory(to: Float.self, capacity: halfLength), imagp: ptrImag.bindMemory(to: Float.self, capacity: halfLength))
        
        // create the circular buffer
        self.buffer = TPCircularBuffer()
        if !TPCircularBufferInit(&self.buffer, Int32(buffer)) {
            fatalError("Unable to allocate circular buffer.")
        }
        
        // preload buffer as a test
//        var preload = [Float](repeating: 1, count: 20000)
        
        self.forwardDCTSetup = vDSP.DCT(count: self.nMels, transformType: vDSP.DCTTransformType.II)!
        
//        withUnsafePointer(to: &preload[0]) {
//            up in
//            if !TPCircularBufferProduceBytes(&self.buffer, up, Int32(20000 * MemoryLayout<Float>.stride)) {
//                fatalError("Insufficient space on buffer.")
//            }
//        }
    }
    
    deinit {
        // half length (for buffer allocation)
        let halfLength = lengthFft / 2
        
        // free the complex buffer
        complexBufferA.realp.deinitialize(count: halfLength)
        complexBufferA.realp.deallocate()
        complexBufferA.imagp.deinitialize(count: halfLength)
        complexBufferA.imagp.deallocate()
        complexBufferT.realp.deinitialize(count: halfLength)
        complexBufferT.realp.deallocate()
        complexBufferT.imagp.deinitialize(count: halfLength)
        complexBufferT.imagp.deallocate()
        
        // free the FFT setup
        vDSP_destroy_fftsetup(fftSetup)
        
        // free the memory used to store the samples
        samplesWindowed.deinitialize(count: lengthFft)
        samplesWindowed.deallocate()
        
        // free the window
        window.deinitialize(count: lengthWindow)
        window.deallocate()
        
        // release the circular buffer
        TPCircularBufferCleanup(&self.buffer)
    }
    
    
    func resetWindow() {
        windowType.createWindow(window, len: lengthWindow)
    }
    
    
    func appendData(_ data: UnsafeMutablePointer<Float>, withSamples numSamples: Int) {
        if !TPCircularBufferProduceBytes(&self.buffer, data, Int32(numSamples * MemoryLayout<Float>.stride)) {
            fatalError("Insufficient space on buffer.")
        }
    }
    
    
    func extractPower() -> [Float]? {
        // get buffer read point and available bytes
        var availableBytes: Int32 = 0
        let tail = TPCircularBufferTail(&buffer, &availableBytes)
        
        // not enough available bytes
        if Int(availableBytes) < (lengthWindow * MemoryLayout<Float>.stride) {
            return nil
        }
        
        // make samples
        let samples = tail!.bindMemory(to: Float.self, capacity: Int(availableBytes) / MemoryLayout<Float>.stride)
                
        // mark circular buffer as consumed at END of excution
        defer {
            // mark as consumed
            TPCircularBufferConsume(&buffer, Int32(hop * MemoryLayout<Float>.stride))
        }
        
        // get half length
        let halfLength = lengthFft / 2
        
        var output = [Float](repeating: 0.0, count: halfLength)
        
//        print("raw samples: ", Array(UnsafeBufferPointer(start:samples, count: lengthFft)))
        
        // window the samples
        vDSP_vmul(samples, 1, window, 1, samplesWindowed, 1, UInt(lengthWindow))
        
//        print("windowed samples: ", Array(UnsafeBufferPointer(start:samplesWindowed, count: lengthFft)))

    
        // pack samples into complex values (use stride 2 to fill just reals
        samplesWindowed.withMemoryRebound(to: DSPComplex.self, capacity: halfLength) {
            vDSP_ctoz($0, 2, &complexBufferA, 1, UInt(halfLength))
        }
        
        // perform FFT
        // TODO: potentially use vDSP_fftm_zrip
        vDSP_fft_zript(fftSetup, &complexBufferA, 1, &complexBufferT, fftSize, FFTDirection(FFT_FORWARD))
        
        // clear imagp, represents frequency at midpoint of symmetry, due to packing of array
        complexBufferA.imagp[0] = 0
        
        output.withUnsafeMutableBufferPointer() {
            guard let ba = $0.baseAddress else { return }
            
            // convert to magnitudes
            vDSP_zvabs(&complexBufferA, 1, ba, 1, UInt(halfLength))
            
            // scaling unit
            var scale: Float = 2.0
            vDSP_vsdiv(ba, 1, &scale, ba, 1, UInt(halfLength))
            
            // square output
            vDSP_vsq(ba, 1, ba, 1, UInt(halfLength))
        }
        
        // add back Nyquist frequency for filter bank
        output.append(output[0])
//        print("fft output: ", output)
                        
        let mel = self.melFilters.applyFilter(powerSpectrum: &output)
        
//        print("mels : ", mel)
        
        let dct = self.forwardDCTSetup!.transform(mel)
        
//        print("dct: ", dct)
//        print("dct count: ", dct.count)
//        return dct
        return (0..<self.nMels).map { (i) -> Float in
            if (i == 0) {
                return dct[i] / sqrt(Float(self.nMels))
            }
            return dct[i] * sqrt(2.0 / Float(self.nMels))
        }
        
//        var normalized = [Float](repeating: 0, count: self.nMels)
//        var mn: Float = 0.0
//        var sddev: Float = 0.0
//
//        vDSP_normalize(unnormalized, 1, &normalized, 1, &mn, &sddev, vDSP_Length(unnormalized.count))
//
//        print(normalized)
//        // for debug
////        return output
//        return normalized
    }
}

