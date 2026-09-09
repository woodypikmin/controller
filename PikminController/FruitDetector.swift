
import UIKit
import CoreGraphics

enum CardState: String {
    case available = "AVAILABLE"
    case busy = "BUSY"
    case complete = "COMPLETE"
}

struct FruitCandidate: Identifiable {
    let id = UUID()
    var rect: CGRect
    var center: CGPoint
    var fill: Double
    var state: CardState
}

final class FruitDetector {
    struct Pixel {
        let r: UInt8
        let g: UInt8
        let b: UInt8
    }

    struct HSV {
        let h: Double
        let s: Double
        let v: Double
    }

    static func hsv(_ p: Pixel) -> HSV {
        let r = Double(p.r) / 255
        let g = Double(p.g) / 255
        let b = Double(p.b) / 255

        let mx = max(r, g, b)
        let mn = min(r, g, b)
        let d = mx - mn

        var h = 0.0

        if d != 0 {
            if mx == r {
                h = 60 * (((g - b) / d).truncatingRemainder(dividingBy: 6))
            } else if mx == g {
                h = 60 * (((b - r) / d) + 2)
            } else {
                h = 60 * (((r - g) / d) + 4)
            }
        }

        if h < 0 { h += 360 }

        let s = mx == 0 ? 0 : d / mx
        return HSV(h: h, s: s, v: mx)
    }

    static func rawPixels(_ image: UIImage) -> (Int, Int, [UInt8])? {
        guard let cg = image.cgImage else { return nil }

        let w = cg.width
        let h = cg.height
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel

        var data = [UInt8](repeating: 0, count: h * bytesPerRow)

        guard let ctx = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, data)
    }

    static func pixel(_ data: [UInt8], width: Int, x: Int, y: Int) -> Pixel {
        let i = (y * width + x) * 4
        return Pixel(r: data[i], g: data[i+1], b: data[i+2])
    }

    static func isFruitColor(_ hsv: HSV) -> Bool {
        let sat = hsv.s
        let val = hsv.v

        let colorful = sat > 0.34 && val > 0.26
        let purple = hsv.h >= 240 && hsv.h <= 330 && sat > 0.10 && val > 0.12
        let red = (hsv.h <= 25 || hsv.h >= 335) && sat > 0.22 && val > 0.20

        return colorful || purple || red
    }

    static func connectedComponents(
        width: Int,
        height: Int,
        mask: [Bool]
    ) -> [(CGRect, Int)] {
        var visited = [Bool](repeating: false, count: mask.count)
        var result: [(CGRect, Int)] = []

        let dirs = [(1,0),(-1,0),(0,1),(0,-1)]

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x

                if visited[idx] || !mask[idx] { continue }

                var queue = [(x,y)]
                visited[idx] = true
                var qi = 0

                var minX = x
                var maxX = x
                var minY = y
                var maxY = y
                var count = 0

                while qi < queue.count {
                    let (cx, cy) = queue[qi]
                    qi += 1
                    count += 1

                    minX = min(minX, cx)
                    maxX = max(maxX, cx)
                    minY = min(minY, cy)
                    maxY = max(maxY, cy)

                    for (dx,dy) in dirs {
                        let nx = cx + dx
                        let ny = cy + dy

                        if nx < 0 || ny < 0 || nx >= width || ny >= height {
                            continue
                        }

                        let ni = ny * width + nx
                        if visited[ni] || !mask[ni] { continue }

                        visited[ni] = true
                        queue.append((nx,ny))
                    }
                }

                result.append((
                    CGRect(
                        x: minX,
                        y: minY,
                        width: maxX - minX + 1,
                        height: maxY - minY + 1
                    ),
                    count
                ))
            }
        }

        return result
    }

    static func detect(in image: UIImage) -> [FruitCandidate] {
        guard let (w,h,data) = rawPixels(image) else { return [] }

        let y0 = Int(Double(h) * 0.18)
        let y1 = Int(Double(h) * 0.96)

        var mask = [Bool](repeating: false, count: w * h)

        for y in y0..<y1 {
            for x in 0..<w {
                let hsvValue = hsv(pixel(data, width: w, x: x, y: y))
                if isFruitColor(hsvValue) {
                    mask[y * w + x] = true
                }
            }
        }

        let comps = connectedComponents(width: w, height: h, mask: mask)
        var fruits: [FruitCandidate] = []

        for (rect, count) in comps {
            let bw = rect.width
            let bh = rect.height

            if bw < Double(w) * 0.045 || bw > Double(w) * 0.18 { continue }
            if bh < Double(h) * 0.020 || bh > Double(h) * 0.105 { continue }

            let fill = Double(count) / max(1, bw * bh)

            if fill < 0.55 { continue }

            let center = CGPoint(
                x: rect.midX,
                y: rect.midY
            )

            let state = classifyCard(
                data: data,
                width: w,
                height: h,
                fruitCenter: center
            )

            fruits.append(
                FruitCandidate(
                    rect: rect,
                    center: center,
                    fill: fill,
                    state: state
                )
            )
        }

        fruits.sort {
            if abs($0.center.y - $1.center.y) > 15 {
                return $0.center.y < $1.center.y
            }
            return $0.center.x < $1.center.x
        }

        return fruits
    }

    static func classifyCard(
        data: [UInt8],
        width w: Int,
        height h: Int,
        fruitCenter: CGPoint
    ) -> CardState {
        let col = min(
            2,
            max(
                0,
                Int(fruitCenter.x / (Double(w) / 3))
            )
        )

        let x0 = max(0, Int(Double(col) * Double(w) / 3 + Double(w) * 0.02))
        let x1 = min(w-1, Int(Double(col+1) * Double(w) / 3 - Double(w) * 0.02))

        let y0 = max(0, Int(fruitCenter.y - Double(h) * 0.11))
        let y1 = min(h-1, Int(fruitCenter.y + Double(h) * 0.09))

        var strongGreen = 0
        var paleMint = 0
        var palePink = 0
        var strongRed = 0

        for y in y0...y1 {
            for x in x0...x1 {
                let p = pixel(data, width: w, x: x, y: y)
                let v = hsv(p)

                if v.h >= 130 && v.h <= 205 && v.s > 0.28 && v.v > 0.32 {
                    strongGreen += 1
                }

                if v.h >= 130 && v.h <= 205 && v.s >= 0.015 && v.s <= 0.30 && v.v > 0.70 {
                    paleMint += 1
                }

                if (v.h <= 20 || v.h >= 335) &&
                    v.s >= 0.01 && v.s <= 0.24 && v.v > 0.78 {
                    palePink += 1
                }

                if (v.h <= 20 || v.h >= 335) &&
                    v.s > 0.45 && v.v > 0.42 {
                    strongRed += 1
                }
            }
        }

        // Complete card has very characteristic green text/card chrome.
        if strongGreen > 900 || paleMint > 6500 {
            return .complete
        }

        // Busy card has pale pink rounded border plus usually red progress.
        if palePink > 6000 || strongRed > 1400 {
            return .busy
        }

        return .available
    }

    static func annotated(
        image: UIImage,
        fruits: [FruitCandidate]
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)

        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))

            let cgW = CGFloat(image.cgImage?.width ?? Int(image.size.width))
            let cgH = CGFloat(image.cgImage?.height ?? Int(image.size.height))

            let sx = image.size.width / cgW
            let sy = image.size.height / cgH

            for fruit in fruits {
                let r = CGRect(
                    x: fruit.rect.origin.x * sx,
                    y: fruit.rect.origin.y * sy,
                    width: fruit.rect.width * sx,
                    height: fruit.rect.height * sy
                )

                let color: UIColor
                switch fruit.state {
                case .available: color = .green
                case .busy: color = .red
                case .complete: color = .blue
                }

                color.setStroke()

                let path = UIBezierPath(rect: r.insetBy(dx: -4, dy: -4))
                path.lineWidth = 4
                path.stroke()
            }
        }
    }
}
