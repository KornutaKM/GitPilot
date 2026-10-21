import XCTest
import SwiftUI
import UIKit
@testable import GitPilotCoreSmoke

/// Native color verification on iOS SDK: pastel treatment must remain readable
/// when contrast, text scaling and VoiceOver are used.
final class PastelDesignTests: XCTestCase {
    private func relativeLuminance(_ color: Color) -> Double {
        let rgba = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(rgba.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        func convert(_ value: CGFloat) -> Double {
            let x = Double(value)
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * convert(red) + 0.7152 * convert(green) + 0.0722 * convert(blue)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let first = relativeLuminance(a)
        let second = relativeLuminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    func testReadableInkOnPastelCanvasAndWhiteCards() {
        XCTAssertGreaterThanOrEqual(contrast(GP.ink, GP.background), 7.0)
        XCTAssertGreaterThanOrEqual(contrast(GP.ink, GP.card), 7.0)
        XCTAssertGreaterThanOrEqual(contrast(GP.secondary, GP.card), 4.5)
    }

    func testInteractiveAccentAndStatusLabelsRemainReadable() {
        XCTAssertGreaterThanOrEqual(contrast(GP.accent, GP.card), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(GP.red, GP.card), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(GP.green, GP.card), 4.5)
    }

    func testSoftPastelSurfacesRemainDistinctAndNotBlack() {
        XCTAssertGreaterThan(relativeLuminance(GP.background), 0.80)
        XCTAssertGreaterThan(relativeLuminance(GP.lavender), 0.65)
        XCTAssertGreaterThan(relativeLuminance(GP.mint), 0.65)
        XCTAssertGreaterThan(relativeLuminance(GP.peach), 0.65)
        XCTAssertGreaterThan(contrast(GP.border, GP.card), 1.05)
    }
}
