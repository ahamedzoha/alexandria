import AudioToolbox
import Foundation
import os

// MARK: - Profile

/// How a book should sound: a preset, fine-tuned by three sliders. Saved per
/// book or per series (see AppState.soundProfile(for:)).
struct SoundProfile: Codable, Sendable, Equatable {
    enum Preset: String, Codable, CaseIterable, Identifiable, Sendable {
        case original, voiceBoost, restore

        var id: String { rawValue }

        var title: String {
            switch self {
            case .original: "Original"
            case .voiceBoost: "Voice Boost"
            case .restore: "Restore"
            }
        }

        var summary: String {
            switch self {
            case .original: "As recorded."
            case .voiceBoost: "Louder, steadier and clearer narration."
            case .restore: "Voice Boost, plus removing tape hiss and room noise."
            }
        }
    }

    var preset: Preset
    /// Gain after compression, in dB (0…12).
    var volumeDB: Double
    /// Presence boost around 3 kHz, in dB (0…8).
    var clarityDB: Double
    /// How much of the voice-isolated signal replaces the original (0…1).
    /// Restore only.
    var noiseReduction: Double

    static let original = SoundProfile(preset: .original, volumeDB: 0, clarityDB: 0, noiseReduction: 0)

    /// A preset at its default settings.
    static func preset(_ preset: Preset) -> SoundProfile {
        switch preset {
        case .original: .original
        case .voiceBoost: SoundProfile(preset: .voiceBoost, volumeDB: 8, clarityDB: 3, noiseReduction: 0)
        case .restore: SoundProfile(preset: .restore, volumeDB: 8, clarityDB: 4, noiseReduction: 0.85)
        }
    }

    var isEnhanced: Bool { preset != .original }

    static let volumeRange: ClosedRange<Double> = 0...12
    static let clarityRange: ClosedRange<Double> = 0...8
}

// MARK: - Parameters

/// What each audio unit gets for a profile. Pure, so the mapping is testable
/// without audio.
struct SoundParameters: Equatable, Sendable {
    /// AUSoundIsolation wet/dry, percent; nil leaves the unit out.
    var isolationPercent: Float?
    var highPassHz: Float
    var mudGainDB: Float
    var presenceGainDB: Float
    /// High shelf at 9 kHz that takes the edge off residual hiss; 0 = flat.
    var hissShelfDB: Float
    var compressorThresholdDB: Float
    var compressorHeadroomDB: Float
    var attackSeconds: Float
    var releaseSeconds: Float
    var expansionThresholdDB: Float
    var expansionRatio: Float
    var makeupGainDB: Float

    /// nil for Original: nothing runs.
    static func parameters(for profile: SoundProfile) -> SoundParameters? {
        guard profile.isEnhanced else { return nil }
        let restore = profile.preset == .restore
        return SoundParameters(
            isolationPercent: restore && profile.noiseReduction > 0
                ? Float(min(max(profile.noiseReduction, 0), 1) * 100) : nil,
            highPassHz: 80,
            mudGainDB: -2,
            presenceGainDB: Float(SoundProfile.clarityRange.clamp(profile.clarityDB)),
            hissShelfDB: restore ? -3 : 0,
            compressorThresholdDB: -28,
            compressorHeadroomDB: 6,
            attackSeconds: 0.005,
            releaseSeconds: 0.15,
            expansionThresholdDB: -55,
            expansionRatio: 2,
            makeupGainDB: Float(SoundProfile.volumeRange.clamp(profile.volumeDB))
        )
    }
}

private extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

// MARK: - Shared settings

/// The profile every playback tap reads. The UI writes it (main thread);
/// taps read a small snapshot once per buffer on the audio thread, so the
/// lock is held for a struct copy and nothing else.
final class SoundSettings: @unchecked Sendable {
    static let shared = SoundSettings()

    struct Snapshot: Sendable {
        var parameters: SoundParameters?
        var bypass: Bool
        var version: Int
        var resetGeneration: Int
    }

    private var lock = os_unfair_lock()
    private var state = Snapshot(parameters: nil, bypass: false, version: 0, resetGeneration: 0)

    func snapshot() -> Snapshot {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return state
    }

    func apply(_ profile: SoundProfile) {
        let parameters = SoundParameters.parameters(for: profile)
        os_unfair_lock_lock(&lock)
        if state.parameters != parameters {
            state.parameters = parameters
            state.version &+= 1
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Hold-to-compare: plays the original while true.
    func setBypass(_ bypass: Bool) {
        os_unfair_lock_lock(&lock)
        state.bypass = bypass
        os_unfair_lock_unlock(&lock)
    }

    /// A seek or a new item: the units' memory (compressor envelope, the
    /// isolation model's look-ahead) belongs to audio that's no longer next.
    func requestReset() {
        os_unfair_lock_lock(&lock)
        state.resetGeneration &+= 1
        os_unfair_lock_unlock(&lock)
    }
}

// MARK: - Chain

/// Apple's built-in effect units, rendered in place over one tap's buffers:
/// voice isolation (Restore) → EQ (rumble cut, de-mud, presence, hiss
/// shelf) → dynamics (compression, gentle expansion, makeup gain) → peak
/// limiter. Created in the tap's `prepare`, used only on the audio thread.
final class EnhancementChain {
    private var isolation: AudioUnit?
    private var eq: AudioUnit?
    private var dynamics: AudioUnit?
    private var limiter: AudioUnit?

    /// The buffers being processed; each unit's input callback reads them.
    fileprivate var source: UnsafeMutablePointer<AudioBufferList>?
    private var timeStamp = AudioTimeStamp()
    private var appliedVersion = -1
    private var resetGeneration = 0
    private var wasActive = false
    private var isolationActive = false

    private static let eqBands: UInt32 = 4

    /// nil when the stream isn't deinterleaved float or a unit won't take
    /// it: playback then just stays as recorded.
    init?(format: AudioStreamBasicDescription, maxFrames: UInt32) {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0,
              format.mBitsPerChannel == 32 else { return nil }
        timeStamp.mFlags = .sampleTimeValid
        guard let eq = makeUnit(kAudioUnitSubType_NBandEQ, format: format, maxFrames: maxFrames, configure: { unit in
                  var bands = Self.eqBands
                  AudioUnitSetProperty(unit, kAUNBandEQProperty_NumberOfBands, kAudioUnitScope_Global, 0,
                                       &bands, UInt32(MemoryLayout<UInt32>.size))
              }),
              let dynamics = makeUnit(kAudioUnitSubType_DynamicsProcessor, format: format, maxFrames: maxFrames),
              let limiter = makeUnit(kAudioUnitSubType_PeakLimiter, format: format, maxFrames: maxFrames)
        else {
            dispose()
            return nil
        }
        self.eq = eq
        self.dynamics = dynamics
        self.limiter = limiter
        // Optional: without it, Restore falls back to EQ and expansion.
        isolation = makeUnit(kAudioUnitSubType_AUSoundIsolation, format: format, maxFrames: maxFrames) { unit in
            AudioUnitSetParameter(unit, kAUSoundIsolationParam_SoundToIsolate, kAudioUnitScope_Global, 0,
                                  AudioUnitParameterValue(kAUSoundIsolationSoundType_HighQualityVoice), 0)
        }
    }

    deinit { dispose() }

    private func dispose() {
        for unit in [isolation, eq, dynamics, limiter].compactMap({ $0 }) {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        isolation = nil; eq = nil; dynamics = nil; limiter = nil
    }

    private func makeUnit(_ subtype: OSType, format: AudioStreamBasicDescription, maxFrames: UInt32,
                          configure: (AudioUnit) -> Void = { _ in }) -> AudioUnit? {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: subtype,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { return nil }
        var instance: AudioUnit?
        guard AudioComponentInstanceNew(component, &instance) == noErr, let unit = instance else { return nil }
        var streamFormat = format
        let formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var frames = maxFrames
        var callback = AURenderCallbackStruct(inputProc: chainInput,
                                              inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        guard AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                   &streamFormat, formatSize) == noErr,
              AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0,
                                   &streamFormat, formatSize) == noErr,
              AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                                   &frames, UInt32(MemoryLayout<UInt32>.size)) == noErr,
              AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                                   &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr
        else {
            AudioComponentInstanceDispose(unit)
            return nil
        }
        configure(unit)
        guard AudioUnitInitialize(unit) == noErr else {
            AudioComponentInstanceDispose(unit)
            return nil
        }
        return unit
    }

    // MARK: Rendering (audio thread)

    /// Processes `list` in place according to the shared settings. Original
    /// (or Compare held) leaves it untouched.
    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: UInt32,
                 settings: SoundSettings.Snapshot) {
        guard let parameters = settings.parameters, !settings.bypass,
              let eq, let dynamics, let limiter else {
            wasActive = false
            return
        }
        if !wasActive || settings.resetGeneration != resetGeneration {
            resetGeneration = settings.resetGeneration
            for unit in [isolation, eq, dynamics, limiter].compactMap({ $0 }) {
                AudioUnitReset(unit, kAudioUnitScope_Global, 0)
            }
            isolationActive = false
        }
        wasActive = true
        if settings.version != appliedVersion {
            appliedVersion = settings.version
            apply(parameters)
        }

        source = list
        if let isolation, parameters.isolationPercent != nil {
            if !isolationActive {
                AudioUnitReset(isolation, kAudioUnitScope_Global, 0)
                isolationActive = true
            }
            render(isolation, list, frames)
        } else {
            isolationActive = false
        }
        render(eq, list, frames)
        render(dynamics, list, frames)
        render(limiter, list, frames)
        source = nil
        timeStamp.mSampleTime += Double(frames)
    }

    private func render(_ unit: AudioUnit, _ list: UnsafeMutablePointer<AudioBufferList>, _ frames: UInt32) {
        var flags = AudioUnitRenderActionFlags()
        if AudioUnitRender(unit, &flags, &timeStamp, 0, frames, list) != noErr {
            // A unit that fails leaves the previous stage's audio in place.
            return
        }
    }

    private func apply(_ p: SoundParameters) {
        let global = kAudioUnitScope_Global
        if let isolation, let percent = p.isolationPercent {
            AudioUnitSetParameter(isolation, kAUSoundIsolationParam_WetDryMixPercent, global, 0, percent, 0)
        }
        if let eq {
            let bands: [(type: Int, hz: Float, gain: Float, octaves: Float)] = [
                (kAUNBandEQFilterType_2ndOrderButterworthHighPass, p.highPassHz, 0, 1),
                (kAUNBandEQFilterType_Parametric, 250, p.mudGainDB, 1.2),
                (kAUNBandEQFilterType_Parametric, 3000, p.presenceGainDB, 1.4),
                (kAUNBandEQFilterType_HighShelf, 9000, p.hissShelfDB, 1),
            ]
            for (i, band) in bands.enumerated() {
                let id = AudioUnitParameterID(i)
                AudioUnitSetParameter(eq, kAUNBandEQParam_FilterType + id, global, 0, Float(band.type), 0)
                AudioUnitSetParameter(eq, kAUNBandEQParam_Frequency + id, global, 0, band.hz, 0)
                AudioUnitSetParameter(eq, kAUNBandEQParam_Gain + id, global, 0, band.gain, 0)
                AudioUnitSetParameter(eq, kAUNBandEQParam_Bandwidth + id, global, 0, band.octaves, 0)
                AudioUnitSetParameter(eq, kAUNBandEQParam_BypassBand + id, global, 0, 0, 0)
            }
        }
        if let dynamics {
            AudioUnitSetParameter(dynamics, kDynamicsProcessorParam_Threshold, global, 0, p.compressorThresholdDB, 0)
            AudioUnitSetParameter(dynamics, kDynamicsProcessorParam_HeadRoom, global, 0, p.compressorHeadroomDB, 0)
            AudioUnitSetParameter(dynamics, kDynamicsProcessorParam_AttackTime, global, 0, p.attackSeconds, 0)
            AudioUnitSetParameter(dynamics, kDynamicsProcessorParam_ReleaseTime, global, 0, p.releaseSeconds, 0)
            AudioUnitSetParameter(dynamics, kDynamicsProcessorParam_ExpansionThreshold, global, 0,
                                  p.expansionThresholdDB, 0)
            AudioUnitSetParameter(dynamics, kDynamicsProcessorParam_ExpansionRatio, global, 0, p.expansionRatio, 0)
            AudioUnitSetParameter(dynamics, kDynamicsProcessorParam_OverallGain, global, 0, p.makeupGainDB, 0)
        }
        if let limiter {
            AudioUnitSetParameter(limiter, kLimiterParam_AttackTime, global, 0, 0.002, 0)
            AudioUnitSetParameter(limiter, kLimiterParam_DecayTime, global, 0, 0.024, 0)
            AudioUnitSetParameter(limiter, kLimiterParam_PreGain, global, 0, 0, 0)
        }
    }
}

/// Each unit pulls its input from the buffers being processed — which may be
/// the very buffers it was asked to render into, so copy only when they differ.
private func chainInput(_ refCon: UnsafeMutableRawPointer,
                        _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                        _ timeStamp: UnsafePointer<AudioTimeStamp>,
                        _ bus: UInt32, _ frames: UInt32,
                        _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let chain = Unmanaged<EnhancementChain>.fromOpaque(refCon).takeUnretainedValue()
    guard let ioData, let source = chain.source else { return kAudioUnitErr_NoConnection }
    let from = UnsafeMutableAudioBufferListPointer(source)
    let to = UnsafeMutableAudioBufferListPointer(ioData)
    for i in 0..<min(from.count, to.count) {
        guard let src = from[i].mData else { continue }
        let bytes = min(from[i].mDataByteSize, frames * 4)
        if to[i].mData == nil {
            to[i].mData = src
        } else if to[i].mData != src {
            memmove(to[i].mData!, src, Int(bytes))
        }
        to[i].mDataByteSize = bytes
    }
    return noErr
}

// MARK: - Preferences

/// Where each book's sound is remembered: on the book, on its whole series,
/// or nowhere (the default from Settings applies). A book's own setting wins
/// over its series'.
struct SoundPreferences {
    enum Scope: Equatable { case book, series, fallback }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private static func key(item id: String) -> String { "sound.item.\(id)" }
    private static func key(series name: String) -> String { "sound.series.\(name)" }
    private static let fallbackKey = "sound.default"

    /// The sound for books with no setting of their own or of their series.
    var fallback: SoundProfile {
        get { read(Self.fallbackKey) ?? .original }
        nonmutating set { write(newValue, Self.fallbackKey) }
    }

    func profile(itemID: String, series: String?) -> SoundProfile {
        if let own = read(Self.key(item: itemID)) { return own }
        if let series, let shared = read(Self.key(series: series)) { return shared }
        return fallback
    }

    func scope(itemID: String, series: String?) -> Scope {
        if read(Self.key(item: itemID)) != nil { return .book }
        if let series, read(Self.key(series: series)) != nil { return .series }
        return .fallback
    }

    /// Saves `profile` where it currently applies: the series when the book
    /// follows its series' setting, otherwise the book.
    func set(_ profile: SoundProfile, itemID: String, series: String?) {
        if scope(itemID: itemID, series: series) == .series, let series {
            write(profile, Self.key(series: series))
        } else {
            write(profile, Self.key(item: itemID))
        }
    }

    /// "Use for all of <series>": on moves the book's sound to the series
    /// (and the book then follows it); off keeps it on this book only.
    func shareWithSeries(_ share: Bool, itemID: String, series: String) {
        let current = profile(itemID: itemID, series: series)
        if share {
            write(current, Self.key(series: series))
            defaults.removeObject(forKey: Self.key(item: itemID))
        } else {
            write(current, Self.key(item: itemID))
            defaults.removeObject(forKey: Self.key(series: series))
        }
    }

    private func read(_ key: String) -> SoundProfile? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SoundProfile.self, from: $0) }
    }

    private func write(_ profile: SoundProfile, _ key: String) {
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: key) }
    }
}
