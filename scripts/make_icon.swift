// Draws the B-Glass app icon (1024x1024, opaque) with CoreGraphics: swiftc scripts/make_icon.swift -o /tmp/make_icon && /tmp/make_icon <out.png>
import AppKit
import ImageIO

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let g = ctx.cgContext
let cs = CGColorSpaceCreateDeviceRGB()

func color(_ r: CGFloat, _ gr: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r / 255, gr / 255, b / 255, a])! }

// background: deep blue ink
let bg = CGGradient(colorsSpace: cs, colors: [color(10, 58, 122), color(4, 25, 59), color(2, 10, 26)] as CFArray, locations: [0, 0.55, 1])!
g.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// soft cyan glow behind the letter
let glow = CGGradient(colorsSpace: cs, colors: [color(109, 207, 246, 0.55), color(109, 207, 246, 0)] as CFArray, locations: [0, 1])!
g.drawRadialGradient(glow, startCenter: CGPoint(x: 360, y: 700), startRadius: 0, endCenter: CGPoint(x: 360, y: 700), endRadius: 620, options: [])
let glow2 = CGGradient(colorsSpace: cs, colors: [color(1, 82, 164, 0.7), color(1, 82, 164, 0)] as CFArray, locations: [0, 1])!
g.drawRadialGradient(glow2, startCenter: CGPoint(x: 800, y: 180), startRadius: 0, endCenter: CGPoint(x: 800, y: 180), endRadius: 560, options: [])

// a frosted glass plate
let plate = CGRect(x: 150, y: 150, width: 724, height: 724)
let platePath = CGPath(roundedRect: plate, cornerWidth: 190, cornerHeight: 190, transform: nil)
g.saveGState()
g.addPath(platePath)
g.clip()
let glass = CGGradient(colorsSpace: cs, colors: [color(255, 255, 255, 0.26), color(255, 255, 255, 0.06)] as CFArray, locations: [0, 1])!
g.drawLinearGradient(glass, start: CGPoint(x: 150, y: 874), end: CGPoint(x: 874, y: 150), options: [])
g.restoreGState()
g.addPath(platePath)
g.setLineWidth(5)
g.setStrokeColor(color(255, 255, 255, 0.45))
g.strokePath()

// the letter
let font = NSFont.systemFont(ofSize: 560, weight: .heavy)
let para = NSMutableParagraphStyle()
para.alignment = .center
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedRed: 0.43, green: 0.81, blue: 0.96, alpha: 0.9)
shadow.shadowBlurRadius = 46
shadow.shadowOffset = .zero
let text = NSAttributedString(string: "B", attributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: para, .shadow: shadow])
let tsize = text.size()
text.draw(in: CGRect(x: 0, y: (size - tsize.height) / 2 - 8, width: size, height: tsize.height))

// a play triangle, lower right, as a nod to what the app does
g.saveGState()
g.translateBy(x: 690, y: 258)
let tri = CGMutablePath()
tri.move(to: CGPoint(x: 0, y: 0)); tri.addLine(to: CGPoint(x: 0, y: 120)); tri.addLine(to: CGPoint(x: 104, y: 60)); tri.closeSubpath()
g.addPath(tri)
g.setFillColor(color(109, 207, 246))
g.fillPath()
g.restoreGState()

NSGraphicsContext.current = nil
// flatten into an RGB image without an alpha channel (icons must be opaque)
let flat = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flat.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, flat.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote", CommandLine.arguments[1])
