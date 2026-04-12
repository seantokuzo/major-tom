#!/usr/bin/env bash
#
# generate-icon.sh — Render a placeholder AppIcon.icns for Ground Control.
#
# Uses a small Swift program to draw the `antenna.radiowaves.left.and.right`
# SF Symbol onto a gradient background at the six sizes macOS expects in an
# iconset, then runs `iconutil -c icns` to produce the final .icns file.
#
# Output: macos/GroundControl/Assets/AppIcon.icns
#
# This is intentionally a placeholder — swap it for real art whenever you
# have proper branding. The build-app.sh script will happily pick up any
# AppIcon.icns that sits at that path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${MACOS_DIR}/GroundControl/Assets"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
OUTPUT_ICNS="${ASSETS_DIR}/AppIcon.icns"

mkdir -p "${ASSETS_DIR}" "${ICONSET_DIR}"

echo "==> rendering icon PNGs via swift"

# Write the renderer to a temp .swift file and compile/run it. Inline `swift`
# would work but a scratch file gives us proper error reporting and keeps the
# program readable.
RENDERER="$(mktemp -t gc-icon-renderer-XXXXXX).swift"
trap 'rm -f "${RENDERER}"' EXIT

cat > "${RENDERER}" <<'SWIFT_EOF'
import AppKit
import Foundation

// Sizes macOS expects for a .iconset → .icns conversion.
// Each logical size is rendered at @1x and @2x for retina.
let sizes: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: renderer <output-iconset-dir>\n".data(using: .utf8)!)
    exit(1)
}
let outputDir = CommandLine.arguments[1]

/// Render a single icon size as PNG and write to `url`.
///
/// Draws into an explicit `NSBitmapImageRep` at the exact pixel dimensions
/// we want, instead of relying on `NSImage.lockFocus()` (which honours the
/// current backing scale factor and can surprise you at small sizes).
func renderIcon(pixelSize: Int, to url: URL) throws {
    // 1. Pixel-exact bitmap backing.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed to allocate bitmap rep"])
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    // 2. Push a graphics context bound to the rep.
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "failed to create graphics context"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let size = NSSize(width: pixelSize, height: pixelSize)
    let rect = NSRect(origin: .zero, size: size)

    // 3. Rounded-rect background with a space-y gradient (deep indigo → cyan).
    let cornerRadius = CGFloat(pixelSize) * 0.225
    let clip = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    clip.addClip()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.32, alpha: 1.0),  // deep indigo
        NSColor(calibratedRed: 0.23, green: 0.52, blue: 0.86, alpha: 1.0),  // mid blue
        NSColor(calibratedRed: 0.36, green: 0.82, blue: 0.98, alpha: 1.0),  // cyan
    ])!
    gradient.draw(in: rect, angle: 270)

    // 4. Antenna SF Symbol, tinted white and centered.
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: CGFloat(pixelSize) * 0.6, weight: .semibold)
    guard let symbol = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right",
                               accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) else {
        throw NSError(domain: "icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "SF Symbol not found"])
    }

    let symbolSize = symbol.size
    let origin = NSPoint(
        x: (size.width - symbolSize.width) / 2,
        y: (size.height - symbolSize.height) / 2
    )
    NSColor.white.set()
    symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)

    // 5. Encode the rep directly to PNG.
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 4, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try png.write(to: url)
}

let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

for (pt, scale) in sizes {
    let pixels = pt * scale
    let suffix = scale == 1 ? "" : "@\(scale)x"
    let filename = "icon_\(pt)x\(pt)\(suffix).png"
    let fileURL = outputURL.appendingPathComponent(filename)
    do {
        try renderIcon(pixelSize: pixels, to: fileURL)
        print("  rendered \(filename)")
    } catch {
        FileHandle.standardError.write("error rendering \(filename): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
SWIFT_EOF

swift "${RENDERER}" "${ICONSET_DIR}"

echo "==> iconutil -c icns"
iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"

echo ""
echo "wrote: ${OUTPUT_ICNS}"
echo "preview: qlmanage -p '${OUTPUT_ICNS}'"
