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
