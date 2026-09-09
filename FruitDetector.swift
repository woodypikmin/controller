
import UIKit
import CoreGraphics
import Vision

enum CardState: String {
    case available = "AVAILABLE"
    case busy = "BUSY"
    case complete = "COMPLETE"
    case blocked = "BLOCKED"
}

struct FruitCandidate: Identifiable {
    let id = UUID()

    var rect: CGRect
    var center: CGPoint
    var fill: Double

    var state: CardState

    var cardText: String = ""
    var frameRect: CGRect? = nil

    var pinkFrameRows: Int = 0
    var mintFrameRows: Int = 0
    var pikminLeftScore: Double = 0
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

    struct FrameEvidence {
        let pinkRows: Int
        let mintRows: Int
        let rect: CGRect?

        var strongestRows: Int {
            max(pinkRows, mintRows)
        }

        var isStrongFrame: Bool {
            strongestRows >= 30
        }

        var isWeakFrame: Bool {
            strongestRows >= 12
        }
    }

    // ------------------------------------------------------------
    // Basic pixel helpers
    // ------------------------------------------------------------

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

        if h < 0 {
            h += 360
        }

        let s = mx == 0 ? 0 : d / mx

        return HSV(
            h: h,
            s: s,
            v: mx
        )
    }

    static func rawPixels(
        _ image: UIImage
    ) -> (Int, Int, [UInt8])? {
        guard let cg = image.cgImage else {
            return nil
        }

        let w = cg.width
        let h = cg.height

        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel

        var data = [UInt8](
            repeating: 0,
            count: h * bytesPerRow
        )

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

        ctx.draw(
            cg,
            in: CGRect(
                x: 0,
                y: 0,
                width: w,
                height: h
            )
        )

        return (
            w,
            h,
            data
        )
    }

    static func pixel(
        _ data: [UInt8],
        width: Int,
        x: Int,
        y: Int
    ) -> Pixel {
        let index = (
            y * width + x
        ) * 4

        return Pixel(
            r: data[index],
            g: data[index + 1],
            b: data[index + 2]
        )
    }

    // ------------------------------------------------------------
    // Fruit detection
    // ------------------------------------------------------------

    static func isFruitColor(
        _ hsv: HSV
    ) -> Bool {
        let colorful =
            hsv.s > 0.34 &&
            hsv.v > 0.26

        let purple =
            hsv.h >= 240 &&
            hsv.h <= 330 &&
            hsv.s > 0.10 &&
            hsv.v > 0.12

        let red =
            (
                hsv.h <= 25 ||
                hsv.h >= 335
            ) &&
            hsv.s > 0.22 &&
            hsv.v > 0.20

        return (
            colorful ||
            purple ||
            red
        )
    }

    static func connectedComponents(
        width: Int,
        height: Int,
        mask: [Bool]
    ) -> [(CGRect, Int)] {
        var visited = [Bool](
            repeating: false,
            count: mask.count
        )

        var result: [(CGRect, Int)] = []

        let dirs = [
            (1, 0),
            (-1, 0),
            (0, 1),
            (0, -1)
        ]

        for y in 0..<height {
            for x in 0..<width {
                let idx =
                    y * width + x

                if visited[idx] ||
                    !mask[idx] {
                    continue
                }

                var queue = [(x, y)]
                visited[idx] = true

                var qi = 0

                var minX = x
                var maxX = x
                var minY = y
                var maxY = y

                var count = 0

                while qi < queue.count {
                    let (
                        cx,
                        cy
                    ) = queue[qi]

                    qi += 1
                    count += 1

                    minX = min(
                        minX,
                        cx
                    )

                    maxX = max(
                        maxX,
                        cx
                    )

                    minY = min(
                        minY,
                        cy
                    )

                    maxY = max(
                        maxY,
                        cy
                    )

                    for (
                        dx,
                        dy
                    ) in dirs {
                        let nx =
                            cx + dx

                        let ny =
                            cy + dy

                        if nx < 0 ||
                            ny < 0 ||
                            nx >= width ||
                            ny >= height {
                            continue
                        }

                        let ni =
                            ny * width + nx

                        if visited[ni] ||
                            !mask[ni] {
                            continue
                        }

                        visited[ni] = true

                        queue.append(
                            (
                                nx,
                                ny
                            )
                        )
                    }
                }

                result.append(
                    (
                        CGRect(
                            x: minX,
                            y: minY,
                            width:
                                maxX - minX + 1,
                            height:
                                maxY - minY + 1
                        ),
                        count
                    )
                )
            }
        }

        return result
    }

    static func fruitCandidates(
        in image: UIImage
    ) -> [FruitCandidate] {
        guard let (
            w,
            h,
            data
        ) = rawPixels(
            image
        ) else {
            return []
        }

        let y0 =
            Int(
                Double(h) * 0.18
            )

        let y1 =
            Int(
                Double(h) * 0.96
            )

        var mask = [Bool](
            repeating: false,
            count: w * h
        )

        for y in y0..<y1 {
            for x in 0..<w {
                let value = hsv(
                    pixel(
                        data,
                        width: w,
                        x: x,
                        y: y
                    )
                )

                if isFruitColor(
                    value
                ) {
                    mask[
                        y * w + x
                    ] = true
                }
            }
        }

        let components =
            connectedComponents(
                width: w,
                height: h,
                mask: mask
            )

        var fruits: [
            FruitCandidate
        ] = []

        for (
            rect,
            count
        ) in components {
            let bw =
                rect.width

            let bh =
                rect.height

            if bw <
                Double(w) * 0.045 ||
                bw >
                Double(w) * 0.18 {
                continue
            }

            if bh <
                Double(h) * 0.020 ||
                bh >
                Double(h) * 0.105 {
                continue
            }

            let fill =
                Double(count) /
                max(
                    1,
                    bw * bh
                )

            // More permissive than old Stage 2.
            // Red apple, orange and plum are allowed through.
            if fill < 0.50 {
                continue
            }

            fruits.append(
                FruitCandidate(
                    rect: rect,
                    center: CGPoint(
                        x: rect.midX,
                        y: rect.midY
                    ),
                    fill: fill,
                    state: .available
                )
            )
        }

        fruits.sort {
            if abs(
                $0.center.y -
                $1.center.y
            ) > 15 {
                return (
                    $0.center.y <
                    $1.center.y
                )
            }

            return (
                $0.center.x <
                $1.center.x
            )
        }

        // Remove nearby fragments.
        var dedup: [
            FruitCandidate
        ] = []

        for fruit in fruits {
            let duplicate =
                dedup.contains {
                    abs(
                        $0.center.x -
                        fruit.center.x
                    ) <
                    Double(w) * 0.045
                    &&
                    abs(
                        $0.center.y -
                        fruit.center.y
                    ) <
                    Double(h) * 0.035
                }

            if !duplicate {
                dedup.append(
                    fruit
                )
            }
        }

        return dedup
    }

    // ------------------------------------------------------------
    // STATUS FRAME detection
    // ------------------------------------------------------------

    static func isPalePinkFrame(
        _ p: Pixel
    ) -> Bool {
        let r = Int(p.r)
        let g = Int(p.g)
        let b = Int(p.b)

        return (
            r > 220 &&
            g > 205 &&
            b > 205 &&
            r - g > 5 &&
            r - b > 3
        )
    }

    static func isPaleMintFrame(
        _ p: Pixel
    ) -> Bool {
        let r = Int(p.r)
        let g = Int(p.g)
        let b = Int(p.b)

        return (
            r > 190 &&
            g > 205 &&
            b > 195 &&
            g - r > 6 &&
            g - b > 2
        )
    }

    static func frameEvidence(
        data: [UInt8],
        width w: Int,
        height h: Int,
        fruit: FruitCandidate
    ) -> FrameEvidence {
        let columnWidth =
            Double(w) / 3.0

        let col =
            min(
                2,
                max(
                    0,
                    Int(
                        fruit.center.x /
                        columnWidth
                    )
                )
            )

        // Status cards align with one of the three list columns.
        let expectedLeft =
            Double(col) *
            columnWidth +
            Double(w) * 0.030

        let expectedRight =
            Double(col + 1) *
            columnWidth -
            Double(w) * 0.030

        let strip =
            max(
                4,
                Int(
                    Double(w) * 0.012
                )
            )

        let searchY0 =
            max(
                0,
                Int(
                    fruit.center.y -
                    Double(h) * 0.20
                )
            )

        let searchY1 =
            min(
                h - 1,
                Int(
                    fruit.center.y +
                    Double(h) * 0.16
                )
            )

        let left0 =
            max(
                0,
                Int(expectedLeft) -
                strip
            )

        let left1 =
            min(
                w - 1,
                Int(expectedLeft) +
                strip
            )

        let right0 =
            max(
                0,
                Int(expectedRight) -
                strip
            )

        let right1 =
            min(
                w - 1,
                Int(expectedRight) +
                strip
            )

        var pinkRows = 0
        var mintRows = 0

        var statusMinY: Int?
        var statusMaxY: Int?

        for y in searchY0...searchY1 {
            var pinkCount = 0
            var mintCount = 0

            for x in left0...left1 {
                let p = pixel(
                    data,
                    width: w,
                    x: x,
                    y: y
                )

                if isPalePinkFrame(
                    p
                ) {
                    pinkCount += 1
                }

                if isPaleMintFrame(
                    p
                ) {
                    mintCount += 1
                }
            }

            for x in right0...right1 {
                let p = pixel(
                    data,
                    width: w,
                    x: x,
                    y: y
                )

                if isPalePinkFrame(
                    p
                ) {
                    pinkCount += 1
                }

                if isPaleMintFrame(
                    p
                ) {
                    mintCount += 1
                }
            }

            if pinkCount >= 2 {
                pinkRows += 1

                statusMinY =
                    min(
                        statusMinY ?? y,
                        y
                    )

                statusMaxY =
                    max(
                        statusMaxY ?? y,
                        y
                    )
            }

            if mintCount >= 2 {
                mintRows += 1

                statusMinY =
                    min(
                        statusMinY ?? y,
                        y
                    )

                statusMaxY =
                    max(
                        statusMaxY ?? y,
                        y
                    )
            }
        }

        var rect: CGRect?

        if let minY = statusMinY,
           let maxY = statusMaxY {
            let x0 =
                Double(col) *
                columnWidth +
                Double(w) * 0.015

            let x1 =
                Double(col + 1) *
                columnWidth -
                Double(w) * 0.015

            let padY =
                Double(h) * 0.012

            rect = CGRect(
                x: x0,
                y: max(
                    0,
                    Double(minY) -
                    padY
                ),
                width:
                    x1 - x0,
                height:
                    min(
                        Double(h),
                        Double(maxY) +
                        padY
                    )
                    -
                    max(
                        0,
                        Double(minY) -
                        padY
                    )
            )
        }

        return FrameEvidence(
            pinkRows: pinkRows,
            mintRows: mintRows,
            rect: rect
        )
    }

    // ------------------------------------------------------------
    // Pikmin-left fallback
    // ------------------------------------------------------------

    static func pikminLeftScore(
        data: [UInt8],
        width w: Int,
        height h: Int,
        fruit: FruitCandidate
    ) -> Double {
        // Important:
        // Search OUTSIDE the fruit bounding box, on its LEFT.
        // Normal decor flower icons in the user's screenshots are usually
        // on the RIGHT side of an available fruit.
        let x1 =
            max(
                0,
                Int(
                    fruit.rect.minX -
                    Double(w) * 0.008
                )
            )

        let x0 =
            max(
                0,
                Int(
                    fruit.rect.minX -
                    Double(w) * 0.105
                )
            )

        let y0 =
            max(
                0,
                Int(
                    fruit.center.y -
                    Double(h) * 0.050
                )
            )

        let y1 =
            min(
                h - 1,
                Int(
                    fruit.center.y +
                    Double(h) * 0.060
                )
            )

        if x1 <= x0 ||
            y1 <= y0 {
            return 0
        }

        var colored = 0
        var total = 0

        for y in y0...y1 {
            for x in x0...x1 {
                let v = hsv(
                    pixel(
                        data,
                        width: w,
                        x: x,
                        y: y
                    )
                )

                if v.s > 0.42 &&
                    v.v > 0.22 {
                    colored += 1
                }

                total += 1
            }
        }

        if total == 0 {
            return 0
        }

        return (
            Double(colored) /
            Double(total)
        )
    }

    // ------------------------------------------------------------
    // OCR ONLY INSIDE A STATUS FRAME
    // ------------------------------------------------------------

    static func recognizeText(
        image: CGImage,
        pixelRect: CGRect
    ) async -> String {
        let bounded =
            pixelRect
                .intersection(
                    CGRect(
                        x: 0,
                        y: 0,
                        width: image.width,
                        height: image.height
                    )
                )
                .integral

        guard bounded.width > 1,
              bounded.height > 1,
              let crop =
                image.cropping(
                    to: bounded
                )
        else {
            return ""
        }

        return await withCheckedContinuation {
            continuation in

            let request =
                VNRecognizeTextRequest {
                    request,
                    error in

                    guard error == nil else {
                        continuation.resume(
                            returning: ""
                        )
                        return
                    }

                    let observations =
                        request.results
                        as?
                        [
                            VNRecognizedTextObservation
                        ]
                        ?? []

                    let lines =
                        observations.compactMap {
                            $0
                                .topCandidates(1)
                                .first?
                                .string
                        }

                    continuation.resume(
                        returning:
                            lines.joined(
                                separator: " "
                            )
                    )
                }

            request.recognitionLevel =
                .accurate

            request.usesLanguageCorrection =
                false

            request.minimumTextHeight =
                0.025

            if let supported =
                try?
                request.supportedRecognitionLanguages() {
                var languages: [
                    String
                ] = []

                if supported.contains(
                    "zh-Hant"
                ) {
                    languages.append(
                        "zh-Hant"
                    )
                }

                if supported.contains(
                    "zh-Hans"
                ) {
                    languages.append(
                        "zh-Hans"
                    )
                }

                if supported.contains(
                    "en-US"
                ) {
                    languages.append(
                        "en-US"
                    )
                }

                if !languages.isEmpty {
                    request.recognitionLanguages =
                        languages
                }
            }

            let handler =
                VNImageRequestHandler(
                    cgImage: crop,
                    orientation: .up,
                    options: [:]
                )

            DispatchQueue
                .global(
                    qos: .userInitiated
                )
                .async {
                    do {
                        try handler.perform(
                            [
                                request
                            ]
                        )
                    } catch {
                        continuation.resume(
                            returning: ""
                        )
                    }
                }
        }
    }

    static func normalized(
        _ text: String
    ) -> String {
        text
            .replacingOccurrences(
                of: " ",
                with: ""
            )
            .replacingOccurrences(
                of: "\n",
                with: ""
            )
            .replacingOccurrences(
                of: "O",
                with: "0"
            )
            .replacingOccurrences(
                of: "o",
                with: "0"
            )
    }

    static func isCompleteText(
        _ text: String
    ) -> Bool {
        let t =
            normalized(
                text
            )

        return (
            t.contains(
                "完成"
            )
            ||
            t.contains(
                "領取"
            )
            ||
            t.contains(
                "领取"
            )
        )
    }

    static func isBusyText(
        _ text: String
    ) -> Bool {
        let t =
            normalized(
                text
            )

        let units = [
            "日",
            "天",
            "小時",
            "小时",
            "分",
            "秒"
        ]

        let hasDigit =
            t.range(
                of: #"\d"#,
                options:
                    .regularExpression
            )
            != nil

        if !hasDigit {
            return false
        }

        return units.contains {
            t.contains(
                $0
            )
        }
    }

    // ------------------------------------------------------------
    // Final card classification
    // ------------------------------------------------------------

    static func detect(
        in image: UIImage
    ) async -> [FruitCandidate] {
        guard let (
            w,
            h,
            data
        ) = rawPixels(
            image
        ),
        let cg = image.cgImage
        else {
            return []
        }

        var fruits =
            fruitCandidates(
                in: image
            )

        for index in fruits.indices {
            let evidence =
                frameEvidence(
                    data: data,
                    width: w,
                    height: h,
                    fruit: fruits[index]
                )

            let pairScore =
                pikminLeftScore(
                    data: data,
                    width: w,
                    height: h,
                    fruit: fruits[index]
                )

            fruits[index]
                .pinkFrameRows =
                evidence.pinkRows

            fruits[index]
                .mintFrameRows =
                evidence.mintRows

            fruits[index]
                .pikminLeftScore =
                pairScore

            fruits[index]
                .frameRect =
                evidence.rect

            // ----------------------------------------------------
            // CRITICAL RULE:
            //
            // NO FRAME = NEVER use time OCR.
            //
            // This prevents "fruit expiration time" under normal items
            // from being mistaken for transport time.
            // ----------------------------------------------------

            if evidence.isStrongFrame {
                var headerText = ""

                if let frame =
                    evidence.rect {
                    let topY =
                        max(
                            0,
                            frame.minY -
                            Double(h) * 0.010
                        )

                    let bottomY =
                        min(
                            fruits[index]
                                .rect
                                .minY
                            -
                            Double(h) * 0.010,
                            frame.minY +
                            Double(h) * 0.095
                        )

                    let headerRect =
                        CGRect(
                            x:
                                frame.minX,
                            y:
                                topY,
                            width:
                                frame.width,
                            height:
                                max(
                                    20,
                                    bottomY -
                                    topY
                                )
                        )

                    headerText =
                        await recognizeText(
                            image: cg,
                            pixelRect:
                                headerRect
                        )
                }

                fruits[index]
                    .cardText =
                    headerText

                // OCR is used only INSIDE a confirmed status frame.
                if isCompleteText(
                    headerText
                ) {
                    fruits[index]
                        .state =
                        .complete
                }
                else if isBusyText(
                    headerText
                ) {
                    fruits[index]
                        .state =
                        .busy
                }
                // Border color fallback.
                else if evidence
                    .mintRows >=
                    evidence
                        .pinkRows + 10 {
                    fruits[index]
                        .state =
                        .complete
                }
                else if evidence
                    .pinkRows >=
                    evidence
                        .mintRows + 10 {
                    fruits[index]
                        .state =
                        .busy
                }
                else {
                    // We know it is a framed status card,
                    // but cannot safely classify it.
                    // NEVER tap.
                    fruits[index]
                        .state =
                        .blocked
                }
            }
            else {
                // Weak clipped frame + Pikmin to left = conservative skip.
                if evidence.isWeakFrame &&
                    pairScore >= 0.025 {
                    fruits[index]
                        .state =
                        .blocked
                }
                // No detectable frame, but a strong Pikmin-like object
                // immediately left of the fruit: skip as a safety fallback.
                else if pairScore >= 0.055 {
                    fruits[index]
                        .state =
                        .blocked
                }
                else {
                    fruits[index]
                        .state =
                        .available
                }
            }
        }

        return fruits
    }

    // ------------------------------------------------------------
    // Debug annotation
    // ------------------------------------------------------------

    static func annotated(
        image: UIImage,
        fruits: [FruitCandidate]
    ) -> UIImage {
        guard let cg =
            image.cgImage
        else {
            return image
        }

        let cgW =
            CGFloat(
                cg.width
            )

        let cgH =
            CGFloat(
                cg.height
            )

        let renderer =
            UIGraphicsImageRenderer(
                size:
                    image.size
            )

        return renderer.image {
            _ in

            image.draw(
                in:
                    CGRect(
                        origin:
                            .zero,
                        size:
                            image.size
                    )
            )

            let sx =
                image.size.width /
                cgW

            let sy =
                image.size.height /
                cgH

            for fruit in fruits {
                let fruitRect =
                    CGRect(
                        x:
                            fruit.rect
                                .origin.x
                            * sx,
                        y:
                            fruit.rect
                                .origin.y
                            * sy,
                        width:
                            fruit.rect
                                .width
                            * sx,
                        height:
                            fruit.rect
                                .height
                            * sy
                    )

                let color:
                    UIColor

                switch fruit.state {
                case .available:
                    color =
                        .green

                case .busy:
                    color =
                        .red

                case .complete:
                    color =
                        .blue

                case .blocked:
                    color =
                        .purple
                }

                color.setStroke()

                if fruit.state ==
                    .available {
                    let path =
                        UIBezierPath(
                            rect:
                                fruitRect
                                .insetBy(
                                    dx: -4,
                                    dy: -4
                                )
                        )

                    path.lineWidth =
                        4

                    path.stroke()
                }
                else if let frame =
                    fruit.frameRect {
                    let viewFrame =
                        CGRect(
                            x:
                                frame.minX
                                * sx,
                            y:
                                frame.minY
                                * sy,
                            width:
                                frame.width
                                * sx,
                            height:
                                frame.height
                                * sy
                        )

                    let path =
                        UIBezierPath(
                            rect:
                                viewFrame
                        )

                    path.lineWidth =
                        4

                    path.stroke()
                }
                else {
                    let path =
                        UIBezierPath(
                            rect:
                                fruitRect
                                .insetBy(
                                    dx: -5,
                                    dy: -5
                                )
                        )

                    path.lineWidth =
                        4

                    path.stroke()
                }
            }
        }
    }
}
