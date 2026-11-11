#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "==> 1. Compiling MacDisplayPro Universal Binary (Apple Silicon arm64 + Intel x86_64)..."
swift build -c release --arch arm64 --arch x86_64

BIN_PATH="$PROJECT_DIR/.build/apple/Products/Release/MacDisplayPro"
if [ ! -f "$BIN_PATH" ]; then
    BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacDisplayPro"
fi

echo "==> Universal Binary Info:"
file "$BIN_PATH"
lipo -info "$BIN_PATH"

APP_DIR="$PROJECT_DIR/MacDisplayPro.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "==> 2. Generating 1024x1024 @2x Retina AppIcon.icns (Zero-Aliasing Vector Icon)..."
ICONSET_DIR="$PROJECT_DIR/.build/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift -e '
import AppKit
import CoreGraphics

let iconsetPath = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, filename) in sizes {
    let s = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { continue }

    NSGraphicsContext.saveGraphicsState()
    if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        cg.setAllowsAntialiasing(true)
        cg.setShouldAntialias(true)
        cg.interpolationQuality = .high

        // macOS BigSur/Tahoe rounded squircle background with rich indigo-cyan gradient
        let inset = s * 0.08
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let radius = s * 0.225
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.addClip()

        let grad = NSGradient(colors: [
            NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.42, alpha: 1.0),
            NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.88, alpha: 1.0),
            NSColor(calibratedRed: 0.05, green: 0.72, blue: 0.92, alpha: 1.0)
        ])
        grad?.draw(in: rect, angle: -45)

        // Draw crisp vector monitor frame
        let monW = s * 0.56
        let monH = s * 0.38
        let monX = (s - monW) / 2.0
        let monY = s * 0.36
        let monRect = CGRect(x: monX, y: monY, width: monW, height: monH)
        let monPath = NSBezierPath(roundedRect: monRect, xRadius: s * 0.04, yRadius: s * 0.04)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        monPath.lineWidth = max(1.5, s * 0.035)
        monPath.stroke()

        // Stand
        let standPath = NSBezierPath()
        standPath.move(to: CGPoint(x: s * 0.5, y: monY))
        standPath.line(to: CGPoint(x: s * 0.5, y: s * 0.24))
        standPath.move(to: CGPoint(x: s * 0.36, y: s * 0.24))
        standPath.line(to: CGPoint(x: s * 0.64, y: s * 0.24))
        standPath.lineWidth = max(1.5, s * 0.035)
        standPath.lineCapStyle = .round
        standPath.stroke()

        // HiDPI / XDR sun badge inside screen
        let sunR = s * 0.09
        let sunRect = CGRect(x: s * 0.5 - sunR, y: monY + monH * 0.5 - sunR, width: sunR * 2, height: sunR * 2)
        NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.25, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: sunRect).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(filename)"))
    }
}
' "$ICONSET_DIR"

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> 3. Packaging MacDisplayPro.app bundle..."
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/MacDisplayPro"
chmod +x "$APP_DIR/Contents/MacOS/MacDisplayPro"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> 4. Signing MacDisplayPro.app (ad-hoc signature for local execution)..."
codesign --force --deep --sign - "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true

echo "==> 5. Creating portable Universal Binary archive (v2.0.0)..."
ZIP_NAME="MacDisplayPro-v2.0.0-Universal.zip"
rm -f "$PROJECT_DIR/$ZIP_NAME"
ditto -c -k --keepParent "$APP_DIR" "$PROJECT_DIR/$ZIP_NAME"

echo "==> Done! App bundle created at: $APP_DIR"
echo "==> Portable Universal Zip created at: $PROJECT_DIR/$ZIP_NAME"
