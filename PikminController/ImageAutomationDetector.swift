
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

        let x1 = Int(Double(w) * 0.20)
        let y0 = Int(Double(h) * 0.76)

        var mask = [Bool](
            repeating: false,
            count: w * h
        )

        for y in y0..<h {
            for x in 0..<x1 {
                let p = FruitDetector.pixel(
                    data,
                    width: w,
                    x: x,
                    y: y
                )

                let v = FruitDetector.hsv(p)

                // Same green range used by the proven Python V7,
                // expressed in normal 0...360 hue.
                if v.h > 70 &&
                    v.h < 200 &&
                    v.s > 0.14 &&
                    v.v > 0.14 {
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

            let minArea =
                Double(w * h) * 0.0007

            if Double(count) < minArea {
                return nil
            }

            if rect.width <
                Double(w) * 0.045 ||
                rect.width >
                Double(w) * 0.18 {
                return nil
            }

            if rect.height <
                Double(h) * 0.025 ||
                rect.height >
                Double(h) * 0.12 {
                return nil
            }

            let aspect =
                rect.width /
                max(
                    1,
                    rect.height
                )

            if aspect < 0.55 ||
                aspect > 1.8 {
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
}
