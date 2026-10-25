import AudioToolbox
import XCTest
@testable import Alexandria

/// Sound Enhancement: presets, where settings are remembered, and what the
/// unit chain actually does to quiet audio.
final class SoundEnhancementTests: XCTestCase {
    // MARK: Presets → parameters

    func testOriginalRunsNothing() {
        XCTAssertNil(SoundParameters.parameters(for: .original))
    }

    func testVoiceBoostSkipsVoiceIsolation() throws {
        let p = try XCTUnwrap(SoundParameters.parameters(for: .preset(.voiceBoost)))
        XCTAssertNil(p.isolationPercent)
        XCTAssertEqual(p.hissShelfDB, 0)
        XCTAssertEqual(p.makeupGainDB, 8)
    }

    func testRestoreIsolatesVoiceAndTamesHiss() throws {
        let p = try XCTUnwrap(SoundParameters.parameters(for: .preset(.restore)))
        XCTAssertEqual(try XCTUnwrap(p.isolationPercent), 85, accuracy: 0.01)
        XCTAssertLessThan(p.hissShelfDB, 0)
    }

    func testSlidersOverrideThePresetAndStayInRange() throws {
        var profile = SoundProfile.preset(.restore)
        profile.volumeDB = 40
        profile.clarityDB = -5
        profile.noiseReduction = 0.5
        let p = try XCTUnwrap(SoundParameters.parameters(for: profile))
        XCTAssertEqual(p.makeupGainDB, 12)
        XCTAssertEqual(p.presenceGainDB, 0)
        XCTAssertEqual(try XCTUnwrap(p.isolationPercent), 50, accuracy: 0.01)
        profile.noiseReduction = 0
        XCTAssertNil(try XCTUnwrap(SoundParameters.parameters(for: profile)).isolationPercent)
    }

    // MARK: Where it's remembered

    private func preferences() -> SoundPreferences {
        let suite = "SoundEnhancementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return SoundPreferences(defaults: defaults)
    }

    func testABookFallsBackToItsSeriesThenTheDefault() {
        let prefs = preferences()
        XCTAssertEqual(prefs.profile(itemID: "gunslinger", series: "The Dark Tower"), .original)

        prefs.fallback = .preset(.voiceBoost)
        XCTAssertEqual(prefs.profile(itemID: "gunslinger", series: "The Dark Tower").preset, .voiceBoost)

        prefs.set(.preset(.restore), itemID: "gunslinger", series: "The Dark Tower")
        prefs.shareWithSeries(true, itemID: "gunslinger", series: "The Dark Tower")
        XCTAssertEqual(prefs.profile(itemID: "drawing-of-the-three", series: "The Dark Tower").preset, .restore)
        XCTAssertEqual(prefs.scope(itemID: "drawing-of-the-three", series: "The Dark Tower"), .series)
        XCTAssertEqual(prefs.profile(itemID: "carrie", series: nil).preset, .voiceBoost, "other books untouched")
    }

    func testABooksOwnSettingWinsOverItsSeries() {
        let prefs = preferences()
        prefs.set(.preset(.restore), itemID: "gunslinger", series: "The Dark Tower")
        prefs.shareWithSeries(true, itemID: "gunslinger", series: "The Dark Tower")
        prefs.set(.preset(.voiceBoost), itemID: "wizard", series: nil)   // a book-only setting
        XCTAssertEqual(prefs.profile(itemID: "wizard", series: "The Dark Tower").preset, .voiceBoost)
    }

    func testChangingAFollowingBookChangesTheSeries() {
        let prefs = preferences()
        prefs.set(.preset(.voiceBoost), itemID: "gunslinger", series: "The Dark Tower")
        prefs.shareWithSeries(true, itemID: "gunslinger", series: "The Dark Tower")
        prefs.set(.preset(.restore), itemID: "waste-lands", series: "The Dark Tower")
        XCTAssertEqual(prefs.profile(itemID: "gunslinger", series: "The Dark Tower").preset, .restore)
    }

    func testUnsharingKeepsTheSoundOnThisBookOnly() {
        let prefs = preferences()
        prefs.set(.preset(.restore), itemID: "gunslinger", series: "The Dark Tower")
        prefs.shareWithSeries(true, itemID: "gunslinger", series: "The Dark Tower")
        prefs.shareWithSeries(false, itemID: "gunslinger", series: "The Dark Tower")
        XCTAssertEqual(prefs.profile(itemID: "gunslinger", series: "The Dark Tower").preset, .restore)
        XCTAssertEqual(prefs.profile(itemID: "drawing-of-the-three", series: "The Dark Tower"), .original)
    }

    // MARK: The chain on real audio

    private let rate = 44_100.0
    private let frames = 1024

    /// Renders `seconds` of a quiet 220 Hz tone with faint noise through the
    /// chain, two channels, and returns the output's last second.
    private func render(_ profile: SoundProfile, bypass: Bool = false, seconds: Double = 3) throws -> [Float] {
        let format = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
            mBitsPerChannel: 32, mReserved: 0)
        let chain = try XCTUnwrap(EnhancementChain(format: format, maxFrames: UInt32(frames)))
        let parameters = SoundParameters.parameters(for: profile)
        let snapshot = SoundSettings.Snapshot(parameters: parameters, bypass: bypass, version: 1, resetGeneration: 0)

        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { list.unsafeMutablePointer.deallocate() }
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { left.deallocate(); right.deallocate() }

        var generator = SystemRandomNumberGenerator()
        var output: [Float] = []
        let blocks = Int(seconds * rate) / frames
        for block in 0..<blocks {
            for i in 0..<frames {
                let t = Double(block * frames + i) / rate
                let sample = Float(0.018 * sin(2 * .pi * 220 * t)) + Float.random(in: -0.002...0.002, using: &generator)
                left[i] = sample
                right[i] = sample
            }
            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: left)
            list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: right)
            chain.process(list.unsafeMutablePointer, frames: UInt32(frames), settings: snapshot)
            if Double(block + 1) * Double(frames) > (seconds - 1) * rate {
                output.append(contentsOf: UnsafeBufferPointer(start: left, count: frames))
            }
        }
        return output
    }

    private func rmsDB(_ samples: [Float]) -> Double {
        let mean = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
        return 10 * log10(max(mean, 1e-12))
    }

    func testVoiceBoostMakesQuietAudioLouderWithoutClipping() throws {
        let original = try render(.original)
        let boosted = try render(.preset(.voiceBoost))
        XCTAssertGreaterThan(rmsDB(boosted) - rmsDB(original), 6, "at least 6 dB louder")
        XCTAssertLessThanOrEqual(boosted.map(abs).max() ?? 0, 1.0, "the limiter keeps it from clipping")
    }

    func testOriginalAndCompareLeaveAudioUntouched() throws {
        let original = try render(.original)
        let compared = try render(.preset(.restore), bypass: true)
        XCTAssertEqual(rmsDB(compared), rmsDB(original), accuracy: 0.5)
    }

    func testRestoreRendersThroughVoiceIsolation() throws {
        let restored = try render(.preset(.restore))
        XCTAssertFalse(restored.contains { $0.isNaN || $0.isInfinite })
        XCTAssertLessThanOrEqual(restored.map(abs).max() ?? 0, 1.0)
    }
}
