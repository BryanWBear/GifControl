//
//  Melcepstrum.swift
//  Dancer
//
//  Created by Bryan Wang on 5/30/20.
//  Copyright © 2020 Bryan Wang. All rights reserved.
//

import Foundation
import Accelerate

class Melcepstrum {
    let nMels: Int
    let nFFT: Int
    var melFilters: [Float] = []

    init(nFFT: Int = 512, sampleRate: Int = 44100, nMels: Int = 40) {
        self.nMels = nMels
        self.nFFT = nFFT
        self.melFilters = mel(sampleRate: sampleRate, nFFT: nFFT, nMels: nMels)
    }

    //https://stackoverflow.com/questions/58995021/how-to-get-a-floating-point-number-interval-of-fixed-length-and-bounds-in-swift
    // linspace in Swift is off by one from Python version, that is, use python_in - 1 for 3rd parameter.
    private func linspace<T>(from start: T, through end: T, in samples: Int) -> StrideThrough<T>
        where T : FloatingPoint, T == T.Stride {
        return Swift.stride(from: start, through: end, by: (end - start) / T(samples))
    }

    func mel(sampleRate: Int, nFFT: Int, nMels: Int, slaney: Bool = true) -> [Float] {
        let melNyquist = (2595 * log10(1 + (Double(sampleRate) / 2.0) / 700))
        let melPoints = Array(linspace(from: 0, through: melNyquist, in: nMels + 1))
        var hzPoints = melPoints.map { (mel) -> Double in
            700 * (pow(10, mel / 2595) - 1)
        }
        
        // linspace unreliable sometimes? need to fix this.
        if (hzPoints.count < nMels + 2) {
            hzPoints.append(Double(sampleRate) / 2.0)
        }
        let freqFFT = Array(linspace(from: 0, through: Float(sampleRate / 2), in: nFFT / 2))
        var filterBank: [[Float]] {
            var a = [[Float]](repeating: [Float](repeating: 0, count: nFFT / 2 + 1), count: nMels)
            // could do away with the matrix completely, or convert to sparse format.
            for filterIndex in 1..<(nMels + 1) {
                for (freqIndex, freq) in freqFFT.enumerated() {
                    // lots of Float casting due to swift type checking.
                    let leftSlope: Float = Float(1 / (hzPoints[filterIndex] - hzPoints[filterIndex - 1]))
                    let leftLine: Float = (Float(freq) - Float(hzPoints[filterIndex - 1])) * leftSlope
                    let rightSlope: Float = Float(1 / (hzPoints[filterIndex + 1] - hzPoints[filterIndex]))
                    let rightLine: Float = (Float(hzPoints[filterIndex + 1]) - Float(freq)) * rightSlope
                    a[filterIndex - 1][freqIndex] = max(0, min(leftLine, rightLine))
                    if slaney {
                        let normFactor: Float = Float(2 / (hzPoints[filterIndex + 1] - hzPoints[filterIndex - 1]))
                        a[filterIndex - 1][freqIndex] *= normFactor
                    }
                }
            }
            return a
        }
        let flatFilterBank = filterBank.reduce([], +)
        return flatFilterBank
    }
    
    func onePowerToDb(power : Float, amin: Float = 1e-10) -> Float {
        if (power < amin) {
            return 10.0 * log10(amin)
        }
        return 10.0 * log10(power)
    }

    func powerToDb(spectrum : [Float], topdB : Float = 80.0) -> [Float]{
        var logSpec = spectrum.map { (power) -> Float in
            onePowerToDb(power: power)
        }
        
        let maxVal = logSpec.max()!
        logSpec = logSpec.map { (db) -> Float in
            if (db < maxVal - topdB) {
                return maxVal - topdB
            }
            return db
        }
        return logSpec
    }
    
    func applyFilter(powerSpectrum: UnsafeMutablePointer<Float>, scaleForMFCC: Bool = true) -> [Float] {
        var outputMels = [Float](repeating: 0.0, count: self.nMels)
        
        // use cblas_sgemv? or dgemv
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, Int32(self.nMels), 1, Int32(self.nFFT / 2 + 1), 1.0,
                    &self.melFilters, Int32(self.nFFT / 2 + 1), powerSpectrum, 1, 0.0, &outputMels, 1)
        
//        print("raw mels: ", outputMels)
                
        if scaleForMFCC {
            return powerToDb(spectrum: outputMels)
        }
        return outputMels
    }
}

