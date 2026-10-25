import Accelerate
import AVFoundation
import MediaToolbox
import os

/// Live spectrum of what's actually playing, for the toolbar visualizer.
///
/// An MTAudioProcessingTap on each player item hands every decoded buffer to
/// `process`, on the real-time audio thread. There it's mixed to mono,
/// windowed, FFT'd (vDSP) and folded into a handful of log-spaced bands,
/// which land in a lock-protected array the UI samples at display rate. The
/// audio thread never allocates: buffers are sized once in `prepare`.
final class AudioLevelMeter: @unchecked Sendable {
    static let bandCount = 5
    private static let fftSize = 1024            // 2^10
    private static let log2n = vDSP_Length(10)

    private var lock = os_unfair_lock()
    private var bands = [Float](repeating: 0, count: AudioLevelMeter.bandCount)

    // Audio-thread scratch, allocated once.
    private let fftSetup: FFTSetup
    private var window = [Float](repeating: 0, count: AudioLevelMeter.fftSize)
    private var mono = [Float](repeating: 0, count: AudioLevelMeter.fftSize)
    private var real = [Float](repeating: 0, count: AudioLevelMeter.fftSize / 2)
    private var imag = [Float](repeating: 0, count: AudioLevelMeter.fftSize / 2)
    private var magnitudes = [Float](repeating: 0, count: AudioLevelMeter.fftSize / 2)
    private var scratchBands = [Float](repeating: 0, count: AudioLevelMeter.bandCount)
    /// Band edges in Hz: log-spaced across the voice/music range.
    private static let bandEdges: [Double] = [60, 250, 600, 1500, 4000, 12000]
    private var sampleRate: Double = 44_100
    private var isFloat = true

    init() {
        fftSetup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    /// Latest band levels, 0...1 — what the visualizer draws.
    func levels() -> [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return bands
    }

    /// Paused or unloaded: the bars settle to nothing.
    func reset() {
        os_unfair_lock_lock(&lock)
        for i in bands.indices { bands[i] = 0 }
        os_unfair_lock_unlock(&lock)
    }

    // MARK: Tap

    /// Attaches a tap to `item`'s audio so its playback feeds this meter.
    /// Asynchronous: the audio track has to load first. Failure just leaves
    /// the item untapped — the bars stay still, playback is unaffected.
    func attach(to item: AVPlayerItem) {
        Task {
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: Unmanaged.passRetained(self).toOpaque(),
                init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
                finalize: { tap in
                    Unmanaged<AudioLevelMeter>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
                },
                prepare: { tap, _, format in
                    let meter = Unmanaged<AudioLevelMeter>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    meter.sampleRate = format.pointee.mSampleRate
                    meter.isFloat = format.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
                },
                unprepare: nil,
                process: { tap, frameCount, _, bufferList, framesOut, flagsOut in
                    guard MTAudioProcessingTapGetSourceAudio(tap, frameCount, bufferList, flagsOut, nil, framesOut) == noErr
                    else { return }
                    let meter = Unmanaged<AudioLevelMeter>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    meter.analyze(bufferList, frames: Int(framesOut.pointee))
                }
            )
            var tap: MTAudioProcessingTap?
            guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                             kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
                  let tap else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            await MainActor.run { item.audioMix = mix }
        }
    }

    // MARK: Analysis (audio thread)

    private func analyze(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard isFloat, frames > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let n = min(frames, Self.fftSize)

        // Mono mix of the first n frames (non-interleaved float channels).
        vDSP_vclr(&mono, 1, vDSP_Length(Self.fftSize))
        var channels: Float = 0
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            vDSP_vadd(mono, 1, data, vDSP_Stride(buffer.mNumberChannels), &mono, 1, vDSP_Length(n))
            channels += 1
        }
        guard channels > 0 else { return }
        var scale = 1 / channels
        vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(n))
        vDSP_vmul(mono, 1, window, 1, &mono, 1, vDSP_Length(Self.fftSize))

        // Real FFT → magnitudes per bin.
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                mono.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.fftSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(Self.fftSize / 2))
            }
        }

        // Fold into log-spaced bands across the voice/music range, to 0...1
        // on a -60…0 dB scale.
        let binHz = sampleRate / Double(Self.fftSize)
        for band in 0..<Self.bandCount {
            let lo = max(1, Int(Self.bandEdges[band] / binHz))
            let hi = max(lo + 1, min(Self.fftSize / 2, Int(Self.bandEdges[band + 1] / binHz)))
            var peak: Float = 0
            magnitudes.withUnsafeBufferPointer {
                vDSP_maxv($0.baseAddress! + lo, 1, &peak, vDSP_Length(hi - lo))
            }
            let db = 20 * log10(max(peak / Float(Self.fftSize / 4), 1e-6))
            scratchBands[band] = min(1, max(0, (db + 60) / 60))
        }
        os_unfair_lock_lock(&lock)
        for band in 0..<Self.bandCount { bands[band] = scratchBands[band] }
        os_unfair_lock_unlock(&lock)
    }
}
