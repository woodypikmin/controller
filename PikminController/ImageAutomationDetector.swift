
import UIKit
import CoreGraphics

final class ImageAutomationDetector {
    static func componentCenters(
        mask: [Bool],
        width w: Int,
        height h: Int
    ) -> [(CGRect, Int)] {
        FruitDetector.connectedComponents(
            width: w,
            height: h,
            mask: mask
        )
    }

    static func detectExpeditionButton(
        in image: UIImage
    ) -> CGPoint? {
        guard let (w, h, data) =
            FruitDetector.rawPixels(image)
        else {
            return nil
        }

        var mask = [Bool](
            repeating: false,
            count: w * h
        )

        let x0 = Int(Double(w) * 0.18)
        let x1 = Int(Double(w) * 0.82)

        let y0 = Int(Double(h) * 0.55)
        let y1 = Int(Double(h) * 0.84)

        for y in y0..<y1 {
            for x in x0..<x1 {
                let p = FruitDetector.pixel(
                    data,
                    width: w,
                    x: x,
                    y: y
                )

                let v = FruitDetector.hsv(p)

                // OpenCV H 70...105 -> approx 140...210 degrees.
                if v.h >= 135 &&
                    v.h <= 215 &&
                    v.s > 0.25 &&
                    v.v > 0.31 {
                    mask[y * w + x] = true
                }
            }
        }

        let components = componentCenters(
            mask: mask,
            width: w,
            height: h
        )

        let candidates = components.compactMap {
            rect,
            count -> (Double, CGPoint)? in

            if count <
                Int(
                    Double(w * h)
                    * 0.00035
                ) {
                return nil
            }

            if rect.width <
                Double(w) * 0.12 {
                return nil
            }

            return (
                Double(count),
                CGPoint(
                    x: rect.midX,
                    y: rect.midY
                )
            )
        }
        .sorted {
            $0.0 > $1.0
        }

        return candidates.first?.1
    }

    static func detectPinkFilter(
        in image: UIImage
    ) -> CGPoint? {
        guard let (w, h, data) =
            FruitDetector.rawPixels(image)
        else {
            return nil
        }

        let y0 = Int(Double(h) * 0.35)
        let y1 = Int(Double(h) * 0.50)

        var mask = [Bool](
            repeating: false,
            count: w * h
        )

        for y in y0..<y1 {
            for x in 0..<w {
                let p = FruitDetector.pixel(
                    data,
                    width: w,
                    x: x,
                    y: y
                )

                let r = Int(p.r)
                let g = Int(p.g)
                let b = Int(p.b)

                if r > 215 &&
                    b > 165 &&
                    g > 105 &&
                    g < 235 &&
                    r - g > 22 &&
                    b - g > 5 {
                    mask[y * w + x] = true
                }
            }
        }

        let components = componentCenters(
            mask: mask,
            width: w,
            height: h
        )

        let candidates = components.compactMap {
            rect,
            count -> (Double, CGPoint)? in

            if count <
                Int(
                    Double(w * h)
                    * 0.00020
                ) {
                return nil
            }

            return (
                Double(count),
                CGPoint(
                    x: rect.midX,
                    y: rect.midY
                )
            )
        }
        .sorted {
            $0.0 > $1.0
        }

        return candidates.first?.1
    }

    static func detectActiveGO(
        in image: UIImage
    ) -> CGPoint? {
        guard let (w, h, data) =
            FruitDetector.rawPixels(image)
        else {
            return nil
        }

        let x0 = Int(Double(w) * 0.60)
        let y0 = Int(Double(h) * 0.76)

        var mask = [Bool](
            repeating: false,
            count: w * h
        )

        for y in y0..<h {
            for x in x0..<w {
                let p = FruitDetector.pixel(
                    data,
                    width: w,
                    x: x,
                    y: y
                )

                let v = FruitDetector.hsv(p)

                let warmHue =
                    v.h < 60 ||
                    v.h > 336

                if warmHue &&
                    v.s > 0.27 &&
                    v.v > 0.56 {
                    mask[y * w + x] = true
                }
            }
        }

        let components = componentCenters(
            mask: mask,
            width: w,
            height: h
        )

        let candidates = components.compactMap {
            rect,
            count -> (Double, CGPoint)? in

            if count <
                Int(
                    Double(w * h)
                    * 0.0010
                ) {
                return nil
            }

            if rect.width <
                Double(w) * 0.07 ||
                rect.height <
                Double(h) * 0.04 {
                return nil
            }

            return (
                Double(count),
                CGPoint(
                    x: rect.midX,
                    y: rect.midY
                )
            )
        }
        .sorted {
            $0.0 > $1.0
        }

        return candidates.first?.1
    }

    static func detectCarryingClose(
        in image: UIImage
    ) -> CGPoint? {
        guard let (w, h, data) =
            FruitDetector.rawPixels(image)
        else {
            return nil
        }

        // This button is extremely stable on the carrying screen.
        // From the user's real screenshots its center is ~
        // x=0.096w, y=0.917h and radius ~0.055w.
        //
        // The carrying button is GREEN.
        // The normal expedition-list close button at the same place
        // is WHITE, so color makes this a very reliable discriminator.

        let expectedX =
            Double(w) * 0.096

        let expectedY =
            Double(h) * 0.917

        let radius =
            Double(w) * 0.055

        let searchDX =
            Int(Double(w) * 0.035)

        let searchDY =
            Int(Double(h) * 0.025)

        let stepX =
            max(
                2,
                Int(Double(w) * 0.006)
            )

        let stepY =
            max(
                2,
                Int(Double(h) * 0.006)
            )

        var bestPoint:
            CGPoint?

        var bestScore =
            -999.0

        var cy =
            Int(expectedY) -
            searchDY

        while cy <=
            Int(expectedY) +
            searchDY {

            var cx =
                Int(expectedX) -
                searchDX

            while cx <=
                Int(expectedX) +
                searchDX {

                var green =
                    0

                var white =
                    0

                var total =
                    0

                let rr =
                    radius * 0.82

                let minX =
                    max(
                        0,
                        Int(
                            Double(cx) -
                            rr
                        )
                    )

                let maxX =
                    min(
                        w - 1,
                        Int(
                            Double(cx) +
                            rr
                        )
                    )

                let minY =
                    max(
                        0,
                        Int(
                            Double(cy) -
                            rr
                        )
                    )

                let maxY =
                    min(
                        h - 1,
                        Int(
                            Double(cy) +
                            rr
                        )
                    )

                for y in minY...maxY {
                    for x in minX...maxX {
                        let dx =
                            Double(x - cx)

                        let dy =
                            Double(y - cy)

                        if dx * dx +
                            dy * dy >
                            rr * rr {
                            continue
                        }

                        let p =
                            FruitDetector.pixel(
                                data,
                                width: w,
                                x: x,
                                y: y
                            )

                        let value =
                            FruitDetector.hsv(
                                p
                            )

                        // Equivalent to the already-proven Python V3:
                        // OpenCV H 35...100 -> normal HSV ~70...200 deg.
                        if value.h > 70 &&
                            value.h < 200 &&
                            value.s > 0.14 &&
                            value.v > 0.14 {
                            green += 1
                        }

                        if value.s < 0.18 &&
                            value.v > 0.84 {
                            white += 1
                        }

                        total += 1
                    }
                }

                if total > 0 {
                    let greenFraction =
                        Double(green) /
                        Double(total)

                    let whiteFraction =
                        Double(white) /
                        Double(total)

                    let score =
                        greenFraction -
                        whiteFraction * 0.50

                    // Carrying screenshot tested around:
                    // green ~= 0.95, white ~= 0.04
                    //
                    // Expedition list X tested around:
                    // green ~= 0.00, white ~= 0.94
                    if greenFraction >
                        0.30 &&
                        whiteFraction <
                        0.45 &&
                        score >
                        bestScore {

                        bestScore =
                            score

                        bestPoint =
                            CGPoint(
                                x:
                                    Double(cx),
                                y:
                                    Double(cy)
                            )
                    }
                }

                cx +=
                    stepX
            }

            cy +=
                stepY
        }

        return bestPoint
    }
}
