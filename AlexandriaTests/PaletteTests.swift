import AppKit
import SwiftUI
import XCTest
@testable import Alexandria

/// PaletteStore's pixel pipeline (extract/backgroundColor/textCandidates) is
/// private, but its public entry point `palette(for:)` sources images through
/// CoverCache, which decodes file:// URLs straight from disk — no network. So
/// these tests drive the real extraction with programmatic PNGs written to a
/// temp directory (unique names per run, so the process-wide caches never
/// serve a stale palette across runs).
@MainActor
final class PaletteTests: XCTestCase {
    // MARK: Fixtures

    /// Renders a 200x200 sRGB PNG via the given draw closure and writes it to
    /// a uniquely-named temp file, returning its URL.
    private func writePNG(_ name: String, draw: (CGContext, CGRect) -> Void) throws -> URL {
        let side = 200
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        draw(context, CGRect(x: 0, y: 0, width: side, height: side))
        let image = try XCTUnwrap(context.makeImage())
        let data = try XCTUnwrap(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alexandria-palette-\(name)-\(UUID().uuidString).png")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private func components(_ color: Color) throws -> (r: Double, g: Double, b: Double) {
        let rgb = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }

    /// WCAG relative luminance, mirroring the extraction's own math.
    private func relativeLuminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func linear(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    // MARK: Extraction

    func testSolidCoverBackgroundMatchesFillColor() async throws {
        let url = try writePNG("solid-red") { context, rect in
            context.setFillColor(srgb(0.8, 0.15, 0.1))
            context.fill(rect)
        }
        let extracted = await PaletteStore.shared.palette(for: url)
        let palette = try XCTUnwrap(extracted)
        let bg = try components(palette.background)
        XCTAssertEqual(bg.r, 0.8, accuracy: 0.05)
        XCTAssertEqual(bg.g, 0.15, accuracy: 0.05)
        XCTAssertEqual(bg.b, 0.1, accuracy: 0.05)
        XCTAssertTrue(palette.isDark)
        // No second color clears the contrast bar on a solid cover, so text
        // falls back to plain white against the dark background.
        let text = try components(palette.primaryText)
        XCTAssertEqual(text.r, 1.0, accuracy: 0.02)
        XCTAssertEqual(text.g, 1.0, accuracy: 0.02)
        XCTAssertEqual(text.b, 1.0, accuracy: 0.02)
    }

    func testTwoToneCoverBackgroundMatchesEdgeColor() async throws {
        // Left third blue (the sampled edge), rest white.
        let url = try writePNG("two-tone") { context, rect in
            context.setFillColor(srgb(1, 1, 1))
            context.fill(rect)
            context.setFillColor(srgb(0.1, 0.2, 0.85))
            context.fill(CGRect(x: 0, y: 0, width: rect.width / 3, height: rect.height))
        }
        let extracted = await PaletteStore.shared.palette(for: url)
        let palette = try XCTUnwrap(extracted)
        let bg = try components(palette.background)
        XCTAssertEqual(bg.r, 0.1, accuracy: 0.05)
        XCTAssertEqual(bg.g, 0.2, accuracy: 0.05)
        XCTAssertEqual(bg.b, 0.85, accuracy: 0.05)
        XCTAssertTrue(palette.isDark)
    }

    /// Regression: a mid-luminance background (bright brick red, ~0.17) sits
    /// just above the point where dark ink out-contrasts light ink, so a
    /// near-black cover color used to win `primaryText` on raw contrast alone
    /// — dark-on-dark the moment that red was dimmed or washed. Text must land
    /// on the same side of the background as the black/white floor.
    func testTextIsLighterThanAMidLuminanceBackground() async throws {
        let background = (r: 0.78, g: 0.27, b: 0.20)
        let url = try writePNG("mid-luminance-bg") { context, rect in
            context.setFillColor(srgb(background.r, background.g, background.b))
            context.fill(rect)
            // Right half: a near-black block that beats every light color on
            // raw contrast, and a light one that should win anyway.
            context.setFillColor(srgb(0.13, 0.10, 0.09))
            context.fill(CGRect(x: 110, y: 20, width: 80, height: 70))
            context.setFillColor(srgb(0.95, 0.85, 0.35))
            context.fill(CGRect(x: 110, y: 110, width: 80, height: 70))
        }
        let extracted = await PaletteStore.shared.palette(for: url)
        let palette = try XCTUnwrap(extracted)
        let bg = try components(palette.background)
        XCTAssertEqual(bg.r, background.r, accuracy: 0.06)

        let text = try components(palette.primaryText)
        XCTAssertGreaterThan(
            relativeLuminance(text), relativeLuminance(bg),
            "primaryText must be lighter than a background that wants light ink"
        )
        XCTAssertGreaterThanOrEqual(
            ArtworkPalette.contrastRatio(palette.primaryText, palette.background), 3.0
        )
    }

    func testIsDarkForBlackVersusWhiteCovers() async throws {
        let blackURL = try writePNG("solid-black") { context, rect in
            context.setFillColor(srgb(0, 0, 0))
            context.fill(rect)
        }
        let blackExtracted = await PaletteStore.shared.palette(for: blackURL)
        let black = try XCTUnwrap(blackExtracted)
        XCTAssertTrue(black.isDark)

        let whiteURL = try writePNG("solid-white") { context, rect in
            context.setFillColor(srgb(1, 1, 1))
            context.fill(rect)
        }
        let whiteExtracted = await PaletteStore.shared.palette(for: whiteURL)
        let white = try XCTUnwrap(whiteExtracted)
        XCTAssertFalse(white.isDark)
    }

    // MARK: Neutral fallback

    func testUnloadableCoverYieldsNilSoConsumersFallBackToNeutral() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("alexandria-palette-missing-\(UUID().uuidString).png")
        let palette = await PaletteStore.shared.palette(for: missing)
        XCTAssertNil(palette)

        let nilURL = await PaletteStore.shared.palette(for: nil)
        XCTAssertNil(nilURL)
    }

    func testNeutralPaletteMatchesSemanticStyling() {
        XCTAssertEqual(ArtworkPalette.neutral.background, .clear)
        XCTAssertFalse(ArtworkPalette.neutral.isDark)
    }

    // MARK: Contrast helper

    func testContrastRatioBounds() {
        XCTAssertEqual(ArtworkPalette.contrastRatio(.black, .white), 21, accuracy: 0.01)
        XCTAssertEqual(ArtworkPalette.contrastRatio(.white, .black), 21, accuracy: 0.01)
        XCTAssertEqual(ArtworkPalette.contrastRatio(.white, .white), 1, accuracy: 0.01)
    }
}
