import AppKit
import SwiftUI

/// A color scheme derived from a piece of cover art: an edge-sampled
/// background, two text colors guaranteed readable against it, and the most
/// saturated "pop" color for accents. Extraction follows the iTunes 11
/// algorithm as reverse-engineered by Panic (blog.panic.com/itunes-11-and-colors).
///
/// All colors are fixed sRGB values (they do not adapt to light/dark mode);
/// consumers should branch on `isDark` when they need to pair the palette
/// with system materials.
struct ArtworkPalette: Equatable, Sendable {
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let isDark: Bool
}

extension ArtworkPalette {
    /// Semantic fallback so consumers can style non-optionally: standard
    /// semantic text colors, the app accent, and no tinted background. Use it
    /// whenever extraction hasn't finished (or failed) — the UI then looks
    /// exactly like plain system styling.
    static let neutral = ArtworkPalette(
        background: .clear,
        primaryText: .primary,
        secondaryText: .secondary,
        accent: .accentColor,
        isDark: false
    )

    /// WCAG contrast ratio (1...21) between two colors, resolved in sRGB.
    /// For consumers choosing between a palette tint and the semantic accent;
    /// unresolvable (dynamic/semantic) colors report maximal contrast so the
    /// palette check simply passes.
    static func contrastRatio(_ a: Color, _ b: Color) -> Double {
        func luminance(_ color: Color) -> Double? {
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
            func linear(_ c: Double) -> Double {
                c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.redComponent)
                 + 0.7152 * linear(rgb.greenComponent)
                 + 0.0722 * linear(rgb.blueComponent)
        }
        guard let la = luminance(a), let lb = luminance(b) else { return 21 }
        return (Swift.max(la, lb) + 0.05) / (Swift.min(la, lb) + 0.05)
    }
}

/// Process-wide cache of artwork palettes. Mirrors `CoverCache`'s shape:
/// requests for the same URL share one in-flight task, results are cached
/// (capped at ~200 entries, oldest evicted first), and the pixel crunching
/// itself runs off the main actor. Artwork is sourced from
/// `CoverCache.shared` — never fetched independently.
@MainActor
final class PaletteStore {
    static let shared = PaletteStore()

    private var cache: [URL: ArtworkPalette] = [:]
    /// Insertion order for simple FIFO eviction once `cache` passes the cap.
    private var order: [URL] = []
    /// In-flight extractions keyed by URL, so a burst of requests shares one task.
    private var inFlight: [URL: Task<ArtworkPalette?, Never>] = [:]

    private static let capacity = 200

    private init() {}

    /// Synchronous cache-only lookup — never decodes or extracts.
    func cached(for url: URL?) -> ArtworkPalette? {
        guard let url else { return nil }
        return cache[url]
    }

    /// Palette for a cover URL: cache hit, else extract from the cached cover
    /// image off the main actor. Returns nil when the cover itself can't be
    /// loaded — consumers fall back to `.neutral` / semantic styling.
    func palette(for url: URL?) async -> ArtworkPalette? {
        guard let url else { return nil }
        // `.neutral` is the negative-cache sentinel (extraction never produces
        // it): the failure is remembered, but callers still see nil.
        if let hit = cache[url] { return hit == .neutral ? nil : hit }

        if let existing = inFlight[url] {
            return await existing.value
        }
        let task = Task { () -> ArtworkPalette? in
            guard let image = await CoverCache.shared.image(for: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return nil }
            return await Task.detached(priority: .utility) {
                Self.extract(from: cgImage)
            }.value
        }
        inFlight[url] = task
        let palette = await task.value
        inFlight[url] = nil
        // Cache failures too, so covers that can't produce a palette aren't
        // re-decoded on every appearance.
        store(palette ?? .neutral, for: url)
        return palette
    }

    private func store(_ palette: ArtworkPalette, for url: URL) {
        if cache[url] == nil { order.append(url) }
        cache[url] = palette
        while order.count > Self.capacity {
            cache[order.removeFirst()] = nil
        }
    }

    // MARK: - Extraction (runs off the main actor)

    /// iTunes-11-style palette extraction (per Panic's write-up):
    /// 1. Downsample to ~64x64 for speed.
    /// 2. Background = dominant color along the left edge, skipping past any
    ///    solid border, preferring a colored candidate over near-black/white.
    /// 3. Text/accent = frequent, saturated, mutually distinct colors that
    ///    clear a 3.0:1 WCAG contrast ratio against that background; accent is
    ///    the most saturated survivor, primary text the highest-contrast one.
    private nonisolated static func extract(from cgImage: CGImage) -> ArtworkPalette? {
        guard let bitmap = Bitmap(downsampling: cgImage) else { return nil }

        let background = backgroundColor(of: bitmap)
        let candidates = textCandidates(in: bitmap, against: background)

        // Fall back to plain black/white text when nothing clears the bar.
        let fallback: RGB = background.relativeLuminance < 0.5 ? .white : .black
        let primary = candidates.max { $0.contrastRatio(against: background) < $1.contrastRatio(against: background) } ?? fallback
        let accent = candidates.max { $0.saturation < $1.saturation } ?? fallback
        // Secondary text: primary at 70% opacity, pre-blended over the background.
        let secondary = primary.blended(toward: background, amount: 0.3)

        return ArtworkPalette(
            background: background.color,
            primaryText: primary.color,
            secondaryText: secondary.color,
            accent: accent.color,
            isDark: background.relativeLuminance < 0.5
        )
    }

    /// Step 2 — background. Sample color frequency down the left edge. A
    /// column that is >90% one color is treated as a solid border and skipped
    /// (up to a quarter of the width) so thin frames don't win. Among the edge
    /// colors, near-black/white only wins if no colored candidate occurs at
    /// least 30% as often — album art usually reads better on its tint than
    /// on its matting.
    private nonisolated static func backgroundColor(of bitmap: Bitmap) -> RGB {
        // Skip past a solid border, if any.
        var x = 0
        if let first = bitmap.dominantBin(inColumn: 0), first.count * 10 > bitmap.height * 9 {
            let limit = max(1, bitmap.width / 4)
            var next = 1
            while next < limit,
                  let column = bitmap.dominantBin(inColumn: next),
                  column.bin == first.bin,
                  column.count * 10 > bitmap.height * 9 {
                next += 1
            }
            x = next
        }

        // Frequency histogram over the (post-border) edge column and its neighbor.
        var histogram = Histogram()
        for column in [x, min(x + 1, bitmap.width - 1)] {
            for y in 0..<bitmap.height {
                histogram.add(bitmap.pixel(x: column, y: y))
            }
        }
        let ranked = histogram.binsByCount()
        guard let top = ranked.first else { return .black }

        let topColor = histogram.averageColor(inBin: top.bin)
        if topColor.isNearBlackOrWhite,
           let colored = ranked.first(where: { !histogram.averageColor(inBin: $0.bin).isNearBlackOrWhite }),
           colored.count * 10 >= top.count * 3 {
            return histogram.averageColor(inBin: colored.bin)
        }
        return topColor
    }

    /// Step 3 — text/accent candidates from a full-image frequency histogram.
    /// A candidate must appear more than once, pass a saturation floor
    /// (washed-out colors are rejected unless the background is neutral, where
    /// grays are legitimate text), clear 3.0:1 contrast against the
    /// background, and be distinct from candidates already accepted.
    private nonisolated static func textCandidates(in bitmap: Bitmap, against background: RGB) -> [RGB] {
        var histogram = Histogram()
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                histogram.add(bitmap.pixel(x: x, y: y))
            }
        }

        let backgroundIsNeutral = background.saturation < 0.15 || background.isNearBlackOrWhite
        var accepted: [RGB] = []
        for entry in histogram.binsByCount() {
            if entry.count <= 1 { break }  // ignore colors appearing once
            let color = histogram.averageColor(inBin: entry.bin)
            if color.saturation < 0.15 && !backgroundIsNeutral { continue }
            if color.contrastRatio(against: background) < 3.0 { continue }
            if accepted.contains(where: { $0.distance(to: color) < 0.25 }) { continue }
            accepted.append(color)
            if accepted.count >= 8 { break }
        }
        return accepted
    }
}

// MARK: - Pixel plumbing

/// A cover downsampled into a small RGBX sRGB pixel buffer. 64x64 keeps
/// histogram work around 4k pixels, which is plenty for frequency ranking.
private struct Bitmap {
    let pixels: [UInt8]
    let width: Int
    let height: Int

    init?(downsampling cgImage: CGImage, side: Int = 64) {
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress,
                      width: side,
                      height: side,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }
        self.pixels = pixels
        self.width = side
        self.height = side
    }

    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = (y * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2])
    }

    /// Most frequent quantized color in one column — used for border detection.
    func dominantBin(inColumn x: Int) -> (bin: Int, count: Int)? {
        var counts: [Int: Int] = [:]
        for y in 0..<height {
            counts[Histogram.bin(for: pixel(x: x, y: y)), default: 0] += 1
        }
        return counts.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
}

/// Color-frequency histogram quantized to 4 bits per channel (4096 bins).
/// Each bin also accumulates the true channel sums so the reported color is
/// the average of its members, not the coarse bin center.
private struct Histogram {
    private var counts = [Int](repeating: 0, count: 4096)
    private var sumR = [Int](repeating: 0, count: 4096)
    private var sumG = [Int](repeating: 0, count: 4096)
    private var sumB = [Int](repeating: 0, count: 4096)

    static func bin(for pixel: (r: UInt8, g: UInt8, b: UInt8)) -> Int {
        ((Int(pixel.r) >> 4) << 8) | ((Int(pixel.g) >> 4) << 4) | (Int(pixel.b) >> 4)
    }

    mutating func add(_ pixel: (r: UInt8, g: UInt8, b: UInt8)) {
        let bin = Self.bin(for: pixel)
        counts[bin] += 1
        sumR[bin] += Int(pixel.r)
        sumG[bin] += Int(pixel.g)
        sumB[bin] += Int(pixel.b)
    }

    /// Non-empty bins, most frequent first.
    func binsByCount() -> [(bin: Int, count: Int)] {
        var entries: [(bin: Int, count: Int)] = []
        for bin in 0..<4096 where counts[bin] > 0 {
            entries.append((bin, counts[bin]))
        }
        return entries.sorted { $0.count > $1.count }
    }

    func averageColor(inBin bin: Int) -> RGB {
        let n = Double(counts[bin])
        guard n > 0 else { return .black }
        return RGB(
            r: Double(sumR[bin]) / n / 255,
            g: Double(sumG[bin]) / n / 255,
            b: Double(sumB[bin]) / n / 255
        )
    }
}

/// Working color value (sRGB, 0...1 per channel) with the color math the
/// extraction steps need.
private struct RGB {
    var r: Double
    var g: Double
    var b: Double

    static let black = RGB(r: 0, g: 0, b: 0)
    static let white = RGB(r: 1, g: 1, b: 1)

    var color: Color { Color(red: r, green: g, blue: b) }

    /// HSB saturation.
    var saturation: Double {
        let hi = Swift.max(r, g, b)
        guard hi > 0 else { return 0 }
        return (hi - Swift.min(r, g, b)) / hi
    }

    /// Panic's neutral test: all channels near 1 (white-ish) or near 0 (black-ish).
    var isNearBlackOrWhite: Bool {
        (r > 0.91 && g > 0.91 && b > 0.91) || (r < 0.09 && g < 0.09 && b < 0.09)
    }

    /// WCAG relative luminance (sRGB linearization).
    var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG contrast ratio, 1...21.
    func contrastRatio(against other: RGB) -> Double {
        let a = relativeLuminance + 0.05
        let b = other.relativeLuminance + 0.05
        return Swift.max(a, b) / Swift.min(a, b)
    }

    /// Perception-weighted (deltaE-ish) distance in 0...1 — green differences
    /// matter most, blue least. Used for the mutual-distinctness threshold.
    func distance(to other: RGB) -> Double {
        let dr = r - other.r, dg = g - other.g, db = b - other.b
        return ((2 * dr * dr + 4 * dg * dg + 3 * db * db) / 9).squareRoot()
    }

    /// Linear interpolation toward another color (amount 0 = self, 1 = other).
    func blended(toward other: RGB, amount: Double) -> RGB {
        RGB(
            r: r + (other.r - r) * amount,
            g: g + (other.g - g) * amount,
            b: b + (other.b - b) * amount
        )
    }
}
