import CoreGraphics
import Foundation

// Run from the repository root: swift scripts/generate-menu-icon.swift
// Coordinates match the 20 × 20 SVG; the PDF has an 18 pt intrinsic size.
let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = repository.appendingPathComponent("Takku/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf")
var page = CGRect(x: 0, y: 0, width: 18, height: 18)
guard let context = CGContext(output as CFURL, mediaBox: &page, nil) else {
    fatalError("Could not create menu icon PDF")
}
context.beginPDFPage(nil)
context.translateBy(x: 0, y: 18)
context.scaleBy(x: 0.9, y: -0.9)
context.setStrokeColor(CGColor(gray: 0, alpha: 1))
context.setLineWidth(1.65)
context.setLineCap(.round)
context.setLineJoin(.round)
context.addPath(CGPath(roundedRect: CGRect(x: 3.5, y: 4, width: 13, height: 14.5), cornerWidth: 2, cornerHeight: 2, transform: nil))
context.strokePath()
for x: CGFloat in [7, 13] {
    context.move(to: CGPoint(x: x, y: 1.5))
    context.addLine(to: CGPoint(x: x, y: 5.5))
    context.strokePath()
}
// A single open handwritten mark: no separate line to crowd the small glyph.
context.move(to: CGPoint(x: 6.5, y: 10))
context.addLine(to: CGPoint(x: 13.5, y: 8.5))
context.addLine(to: CGPoint(x: 8, y: 13))
context.addLine(to: CGPoint(x: 13.5, y: 11.5))
context.strokePath()
context.endPDFPage()
context.closePDF()

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 20 20">
  <g fill="none" stroke="black" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">
    <rect x="3.5" y="4" width="13" height="14.5" rx="2"/>
    <path d="M7 1.5v4M13 1.5v4M6.5 10l7-1.5L8 13l5.5-1.5"/>
  </g>
</svg>

"""
try svg.write(to: repository.appendingPathComponent("docs/assets/menu-icon.svg"), atomically: true, encoding: .utf8)
