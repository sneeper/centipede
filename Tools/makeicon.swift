// Generates a 1024×1024 app icon PNG using Core Graphics (no art assets needed).
// Usage: swift Tools/makeicon.swift <output.png>
//
// Headless-safe: draws into an offscreen bitmap context, so it needs no display.

import CoreGraphics
import ImageIO
import Foundation

let pixels = 1024
let S = CGFloat(pixels)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: pixels, height: pixels,
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("could not create context") }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: CGColor) {
    ctx.setFillColor(c)
    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
}

// Rounded "squircle" background with a faint neon border.
let margin: CGFloat = 80
let bgRect = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.addPath(bgPath); ctx.setFillColor(rgb(0.04, 0.04, 0.09)); ctx.fillPath()
ctx.addPath(bgPath); ctx.setStrokeColor(rgb(0.3, 0.95, 0.55, 0.55)); ctx.setLineWidth(10); ctx.strokePath()

// A few mushrooms.
func mushroom(_ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) {
    let r = CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)
    let p = CGPath(roundedRect: r, cornerWidth: s * 0.28, cornerHeight: s * 0.28, transform: nil)
    ctx.addPath(p); ctx.setFillColor(rgb(0.7, 0.45, 0.95)); ctx.fillPath()
}
mushroom(360, 430, 86)
mushroom(640, 400, 86)
mushroom(500, 470, 86)

// The centipede: a wiggling row of discs with an orange head.
let body = rgb(0.5, 0.9, 0.4)
let head = rgb(1.0, 0.55, 0.2)
let segR: CGFloat = 64
for i in 0..<6 {
    let x = 300 + CGFloat(i) * 92
    let y = 600 + CGFloat(sin(Double(i) * 0.9)) * 55
    if i == 5 {
        disc(x, y, segR, head)
        disc(x + 20, y + 18, 12, rgb(0, 0, 0))   // eyes
        disc(x - 20, y + 18, 12, rgb(0, 0, 0))
    } else {
        disc(x, y, segR, body)
    }
}

// The shooter (green triangle) and a bullet above it.
let bx: CGFloat = 512, by: CGFloat = 250
ctx.setFillColor(rgb(0.4, 1.0, 0.4))
ctx.move(to: CGPoint(x: bx, y: by + 70))
ctx.addLine(to: CGPoint(x: bx - 62, y: by - 58))
ctx.addLine(to: CGPoint(x: bx + 62, y: by - 58))
ctx.closePath(); ctx.fillPath()
ctx.setFillColor(rgb(1, 1, 0.25))
ctx.fill(CGRect(x: bx - 6, y: by + 90, width: 12, height: 48))

guard let image = ctx.makeImage() else { fatalError("could not render image") }

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("could not create destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write PNG") }
print("wrote \(outPath)")
