
import UIKit
import CoreGraphics
import Vision

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
    var cardText: String = ""
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
        let colorful = hsv.s > 0.34 && hsv.v > 0.26
        let purple = hsv.h >= 240 && hsv.h <= 330 && hsv.s > 0.10 && hsv.v > 0.12
        let red = (hsv.h <= 25 || hsv.h >= 335) && hsv.s > 0.22 && hsv.v > 0.20

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

    static func fruitCandidates(in image: UIImage) -> [FruitCandidate] {
        guard let (w,h,data) = rawPixels(image) else { return [] }

        let y0 = Int(Double(h) * 0.18)
        let y1 = Int(Double(h) * 0.96)

        var mask = [Bool](repeating: false, count: w * h)

        for y in y0..<y1 {
            for x in 0..<w {
                let hv = hsv(pixel(data, width: w, x: x, y: y))
                if isFruitColor(hv) {
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

            // Keep this permissive enough for orange/red apple/plum.
            if fill < 0.50 { continue }

            fruits.append(
                FruitCandidate(
                    rect: rect,
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    fill: fill,
                    state: .available
                )
            )
        }

        fruits.sort {
            if abs($0.center.y - $1.center.y) > 15 {
                return $0.center.y < $1.center.y
            }
            return $0.center.x < $1.center.x
        }

        // Deduplicate nearby fragments.
        var dedup: [FruitCandidate] = []

        for fruit in fruits {
            let tooClose = dedup.contains {
                abs($0.center.x - fruit.center.x) < Double(w) * 0.045 &&
                abs($0.center.y - fruit.center.y) < Double(h) * 0.035
            }

            if !tooClose {
                dedup.append(fruit)
            }
        }

        return dedup
    }

    static func classify(
        image: UIImage,
        fruits: [FruitCandidate]
    ) async -> [FruitCandidate] {
        guard let cg = image.cgImage else { return fruits }

        let imageW = CGFloat(cg.width)
        let imageH = CGFloat(cg.height)

        var out: [FruitCandidate] = []

        for var fruit in fruits {
            let cardRect = fullCardRect(
                imageWidth: imageW,
                imageHeight: imageH,
                fruitCenter: fruit.center
            )

            let text = await recognizeText(
                image: cg,
                pixelRect: cardRect
            )

            fruit.cardText = text

            if isCompleteText(text) {
                fruit.state = .complete
            } else if isBusyText(text) {
                fruit.state = .busy
            } else {
                fruit.state = .available
            }

            out.append(fruit)
        }

        return out
    }

    static func detect(in image: UIImage) async -> [FruitCandidate] {
        let candidates = fruitCandidates(in: image)
        return await classify(image: image, fruits: candidates)
    }

    static func fullCardRect(
        imageWidth w: CGFloat,
        imageHeight h: CGFloat,
        fruitCenter: CGPoint
    ) -> CGRect {
        let columnWidth = w / 3
        let col = min(
            2,
            max(
                0,
                Int(fruitCenter.x / columnWidth)
            )
        )

        // Whole card lane, deliberately larger than Stage 2.0.
        // This includes the time header / 完成 text above the fruit.
        let x0 = CGFloat(col) * columnWidth + w * 0.015
        let x1 = CGFloat(col + 1) * columnWidth - w * 0.015

        let y0 = max(
            0,
            fruitCenter.y - h * 0.165
        )

        let y1 = min(
            h,
            fruitCenter.y + h * 0.105
        )

        return CGRect(
            x: x0,
            y: y0,
            width: max(1, x1 - x0),
            height: max(1, y1 - y0)
        )
    }

    static func recognizeText(
        image: CGImage,
        pixelRect: CGRect
    ) async -> String {
        guard let crop = image.cropping(to: pixelRect.integral) else {
            return ""
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil else {
                    continuation.resume(returning: "")
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []

                let lines = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }

                continuation.resume(
                    returning: lines.joined(separator: " ")
                )
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.025

            let supported = try? request.supportedRecognitionLanguages()

            var preferred: [String] = []

            if supported?.contains("zh-Hant") == true {
                preferred.append("zh-Hant")
            }

            if supported?.contains("zh-Hans") == true {
                preferred.append("zh-Hans")
            }

            if supported?.contains("en-US") == true {
                preferred.append("en-US")
            }

            if !preferred.isEmpty {
                request.recognitionLanguages = preferred
            }

            let handler = VNImageRequestHandler(
                cgImage: crop,
                orientation: .up,
                options: [:]
            )

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "o", with: "0")
    }

    static func isCompleteText(_ text: String) -> Bool {
        let t = normalized(text)

        return t.contains("完成") ||
               t.contains("領取") ||
               t.contains("领取")
    }

    static func isBusyText(_ text: String) -> Bool {
        let t = normalized(text)

        // The user's UI uses strings such as:
        // 176日..., 107日..., X小時, X分
        let units = ["日", "天", "小時", "小时", "分", "秒"]

        for unit in units {
            if t.contains(unit) {
                // Require at least one digit somewhere in the card text.
                if t.range(of: #"\d"#, options: .regularExpression) != nil {
                    return true
                }
            }
        }

        // English fallback if UI language changes.
        let lower = t.lowercased()

        if lower.range(
            of: #"\d+(day|days|hour|hours|min|mins|minute|minutes|sec|secs|second|seconds)"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        return false
    }

    static func annotated(
        image: UIImage,
        fruits: [FruitCandidate]
    ) -> UIImage {
        guard let cg = image.cgImage else { return image }

        let cgW = CGFloat(cg.width)
        let cgH = CGFloat(cg.height)

        let renderer = UIGraphicsImageRenderer(size: image.size)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))

            let sx = image.size.width / cgW
            let sy = image.size.height / cgH

            for fruit in fruits {
                let fruitRect = CGRect(
                    x: fruit.rect.origin.x * sx,
                    y: fruit.rect.origin.y * sy,
                    width: fruit.rect.width * sx,
                    height: fruit.rect.height * sy
                )

                let cardPixel = fullCardRect(
                    imageWidth: cgW,
                    imageHeight: cgH,
                    fruitCenter: fruit.center
                )

                let cardRect = CGRect(
                    x: cardPixel.origin.x * sx,
                    y: cardPixel.origin.y * sy,
                    width: cardPixel.width * sx,
                    height: cardPixel.height * sy
                )

                let color: UIColor

                switch fruit.state {
                case .available:
                    color = .green
                case .busy:
                    color = .red
                case .complete:
                    color = .blue
                }

                color.setStroke()

                let cardPath = UIBezierPath(rect: cardRect)
                cardPath.lineWidth = 4
                cardPath.stroke()

                if fruit.state == .available {
                    let fruitPath = UIBezierPath(
                        rect: fruitRect.insetBy(dx: -3, dy: -3)
                    )
                    fruitPath.lineWidth = 3
                    fruitPath.stroke()
                }
            }
        }
    }
}
