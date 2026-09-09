
import UIKit
import CoreGraphics
import Vision

enum CardState: String {
    case available = "AVAILABLE"
    case busy = "BUSY"
    case complete = "COMPLETE"
    case blocked = "BLOCKED"
}

struct OCRItem {
    let text: String
    let rect: CGRect
}

struct StatusCard: Identifiable {
    let id = UUID()
    let state: CardState
    let rect: CGRect
}

struct FruitCandidate: Identifiable {
    let id = UUID()
    var rect: CGRect
    var center: CGPoint
    var fill: Double
    var state: CardState
    var labelText: String = ""
}

struct DetectionResult {
    var fruits: [FruitCandidate]
    var cards: [StatusCard]
    var ocr: [OCRItem]
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

    struct LineBand {
        let state: CardState
        let column: Int
        let y0: Int
        let y1: Int

        var centerY: Double {
            Double(y0 + y1) / 2.0
        }
    }

    // ---------------------------------------------------------
    // Pixel helpers
    // ---------------------------------------------------------

    static func rawPixels(
        _ image: UIImage
    ) -> (Int, Int, [UInt8])? {
        guard let cg = image.cgImage else {
            return nil
        }

        let w = cg.width
        let h = cg.height
        let bytesPerRow = w * 4

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
        let i = (
            y * width + x
        ) * 4

        return Pixel(
            r: data[i],
            g: data[i + 1],
            b: data[i + 2]
        )
    }

    static func hsv(
        _ p: Pixel
    ) -> HSV {
        let r =
            Double(p.r) / 255.0

        let g =
            Double(p.g) / 255.0

        let b =
            Double(p.b) / 255.0

        let mx =
            max(
                r,
                g,
                b
            )

        let mn =
            min(
                r,
                g,
                b
            )

        let d =
            mx - mn

        var h = 0.0

        if d != 0 {
            if mx == r {
                h =
                    60.0 *
                    (
                        (
                            (g - b) / d
                        )
                        .truncatingRemainder(
                            dividingBy: 6.0
                        )
                    )
            }
            else if mx == g {
                h =
                    60.0 *
                    (
                        (b - r) / d
                        + 2.0
                    )
            }
            else {
                h =
                    60.0 *
                    (
                        (r - g) / d
                        + 4.0
                    )
            }
        }

        if h < 0 {
            h += 360.0
        }

        let s =
            mx == 0
            ? 0
            : d / mx

        return HSV(
            h: h,
            s: s,
            v: mx
        )
    }

    // ---------------------------------------------------------
    // Full-screen OCR once
    // ---------------------------------------------------------

    static func recognizeAllText(
        image: UIImage
    ) async -> [OCRItem] {
        guard let cg =
            image.cgImage
        else {
            return []
        }

        let w =
            CGFloat(
                cg.width
            )

        let h =
            CGFloat(
                cg.height
            )

        return await withCheckedContinuation {
            continuation in

            let request =
                VNRecognizeTextRequest {
                    request,
                    error in

                    guard error == nil else {
                        continuation.resume(
                            returning: []
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

                    var items: [
                        OCRItem
                    ] = []

                    for observation in observations {
                        guard let text =
                            observation
                            .topCandidates(1)
                            .first?
                            .string
                        else {
                            continue
                        }

                        let box =
                            observation
                            .boundingBox

                        let rect =
                            CGRect(
                                x:
                                    box.minX
                                    * w,
                                y:
                                    (
                                        1.0 -
                                        box.maxY
                                    )
                                    * h,
                                width:
                                    box.width
                                    * w,
                                height:
                                    box.height
                                    * h
                            )

                        items.append(
                            OCRItem(
                                text: text,
                                rect: rect
                            )
                        )
                    }

                    continuation.resume(
                        returning: items
                    )
                }

            request.recognitionLevel =
                .accurate

            request.usesLanguageCorrection =
                false

            request.minimumTextHeight =
                0.012

            if let supported =
                try?
                request
                .supportedRecognitionLanguages() {
                var langs: [
                    String
                ] = []

                if supported.contains(
                    "zh-Hant"
                ) {
                    langs.append(
                        "zh-Hant"
                    )
                }

                if supported.contains(
                    "zh-Hans"
                ) {
                    langs.append(
                        "zh-Hans"
                    )
                }

                if supported.contains(
                    "en-US"
                ) {
                    langs.append(
                        "en-US"
                    )
                }

                if !langs.isEmpty {
                    request
                        .recognitionLanguages =
                        langs
                }
            }

            let handler =
                VNImageRequestHandler(
                    cgImage: cg,
                    orientation: .up,
                    options: [:]
                )

            DispatchQueue
                .global(
                    qos:
                        .userInitiated
                )
                .async {
                    do {
                        try handler.perform(
                            [
                                request
                            ]
                        )
                    }
                    catch {
                        continuation.resume(
                            returning: []
                        )
                    }
                }
        }
    }

    // ---------------------------------------------------------
    // STATUS CARD DETECTION
    //
    // Critical Stage 2.3 change:
    // Detect the HORIZONTAL TOP/BOTTOM border of each rounded card,
    // then pair the two borders into ONE card.
    //
    // No more long vertical rectangles spanning multiple cards.
    // ---------------------------------------------------------

    static func isBusyBorderPixel(
        _ p: Pixel
    ) -> Bool {
        let r =
            Int(p.r)

        let g =
            Int(p.g)

        let b =
            Int(p.b)

        let mx =
            max(
                r,
                g,
                b
            )

        let mn =
            min(
                r,
                g,
                b
            )

        // Pikmin busy card border:
        // extremely pale pink.
        return (
            r > 230 &&
            g > 220 &&
            b > 220 &&
            r - g >= 3 &&
            r - b >= 2 &&
            mx - mn < 35
        )
    }

    static func isCompleteBorderPixel(
        _ p: Pixel
    ) -> Bool {
        let r =
            Int(p.r)

        let g =
            Int(p.g)

        let b =
            Int(p.b)

        let mx =
            max(
                r,
                g,
                b
            )

        let mn =
            min(
                r,
                g,
                b
            )

        // Completed card border:
        // extremely pale mint/green.
        return (
            g > 220 &&
            r > 200 &&
            b > 200 &&
            g - r >= 4 &&
            g - b >= 2 &&
            mx - mn < 40
        )
    }

    static func horizontalBorderBands(
        data: [UInt8],
        width w: Int,
        height h: Int
    ) -> [LineBand] {
        let columnWidth =
            Double(w) / 3.0

        var rawHits:
            [
                (
                    CardState,
                    Int,
                    Int
                )
            ] = []

        let startY =
            Int(
                Double(h) * 0.18
            )

        let endY =
            Int(
                Double(h) * 0.96
            )

        for y in startY..<endY {
            for col in 0..<3 {
                let x0 =
                    max(
                        0,
                        Int(
                            Double(col)
                            * columnWidth
                            +
                            Double(w)
                            * 0.030
                        )
                    )

                let x1 =
                    min(
                        w - 1,
                        Int(
                            Double(col + 1)
                            * columnWidth
                            -
                            Double(w)
                            * 0.030
                        )
                    )

                if x1 <= x0 {
                    continue
                }

                var busyCount =
                    0

                var completeCount =
                    0

                let total =
                    x1 - x0 + 1

                for x in x0...x1 {
                    let p =
                        pixel(
                            data,
                            width: w,
                            x: x,
                            y: y
                        )

                    if isBusyBorderPixel(
                        p
                    ) {
                        busyCount += 1
                    }

                    if isCompleteBorderPixel(
                        p
                    ) {
                        completeCount += 1
                    }
                }

                let busyFraction =
                    Double(
                        busyCount
                    )
                    /
                    Double(
                        total
                    )

                let completeFraction =
                    Double(
                        completeCount
                    )
                    /
                    Double(
                        total
                    )

                if busyFraction >= 0.55 {
                    rawHits.append(
                        (
                            .busy,
                            col,
                            y
                        )
                    )
                }

                if completeFraction >= 0.55 {
                    rawHits.append(
                        (
                            .complete,
                            col,
                            y
                        )
                    )
                }
            }
        }

        var bands: [
            LineBand
        ] = []

        for state in [
            CardState.busy,
            CardState.complete
        ] {
            for col in 0..<3 {
                let ys =
                    rawHits
                    .filter {
                        $0.0 == state &&
                        $0.1 == col
                    }
                    .map {
                        $0.2
                    }
                    .sorted()

                if ys.isEmpty {
                    continue
                }

                var start =
                    ys[0]

                var previous =
                    ys[0]

                for y in ys.dropFirst() {
                    if y <=
                        previous + 1 {
                        previous = y
                    }
                    else {
                        bands.append(
                            LineBand(
                                state: state,
                                column: col,
                                y0: start,
                                y1: previous
                            )
                        )

                        start = y
                        previous = y
                    }
                }

                bands.append(
                    LineBand(
                        state: state,
                        column: col,
                        y0: start,
                        y1: previous
                    )
                )
            }
        }

        return bands
    }

    static func detectStatusCards(
        data: [UInt8],
        width w: Int,
        height h: Int
    ) -> [StatusCard] {
        let bands =
            horizontalBorderBands(
                data: data,
                width: w,
                height: h
            )

        let columnWidth =
            Double(w) / 3.0

        var cards: [
            StatusCard
        ] = []

        for state in [
            CardState.busy,
            CardState.complete
        ] {
            for col in 0..<3 {
                let local =
                    bands
                    .filter {
                        $0.state == state &&
                        $0.column == col
                    }
                    .sorted {
                        $0.centerY <
                        $1.centerY
                    }

                var used =
                    Set<Int>()

                for i in 0..<local.count {
                    if used.contains(
                        i
                    ) {
                        continue
                    }

                    let top =
                        local[i]

                    var bestIndex:
                        Int?

                    for j in
                        (i + 1)..<local.count {
                        if used.contains(
                            j
                        ) {
                            continue
                        }

                        let bottom =
                            local[j]

                        let distance =
                            bottom.centerY -
                            top.centerY

                        // Real status-card height is very stable.
                        // On the supplied screenshots ~13.7% screen height.
                        if distance >=
                            Double(h) * 0.105
                            &&
                            distance <=
                            Double(h) * 0.175 {
                            bestIndex = j
                            break
                        }

                        if distance >
                            Double(h) * 0.175 {
                            break
                        }
                    }

                    guard let j =
                        bestIndex
                    else {
                        continue
                    }

                    used.insert(
                        i
                    )

                    used.insert(
                        j
                    )

                    let bottom =
                        local[j]

                    let x0 =
                        Double(col)
                        * columnWidth
                        +
                        Double(w)
                        * 0.024

                    let x1 =
                        Double(col + 1)
                        * columnWidth
                        -
                        Double(w)
                        * 0.024

                    let y0 =
                        Double(
                            top.y0
                        )

                    let y1 =
                        Double(
                            bottom.y1
                        )

                    cards.append(
                        StatusCard(
                            state: state,
                            rect: CGRect(
                                x: x0,
                                y: y0,
                                width:
                                    x1 - x0,
                                height:
                                    y1 - y0
                            )
                        )
                    )
                }
            }
        }

        return cards
    }

    // ---------------------------------------------------------
    // Fruit detection only for NON-STATUS areas
    // ---------------------------------------------------------

    static func isFruitColor(
        _ value: HSV
    ) -> Bool {
        let colorful =
            value.s > 0.30 &&
            value.v > 0.24

        let purple =
            value.h >= 235 &&
            value.h <= 335 &&
            value.s > 0.09 &&
            value.v > 0.11

        let red =
            (
                value.h <= 28 ||
                value.h >= 332
            )
            &&
            value.s > 0.20 &&
            value.v > 0.18

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

        var result:
            [
                (
                    CGRect,
                    Int
                )
            ] = []

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

                var queue =
                    [
                        (
                            x,
                            y
                        )
                    ]

                visited[idx] =
                    true

                var qi = 0

                var minX = x
                var maxX = x
                var minY = y
                var maxY = y

                var count = 0

                while qi <
                    queue.count {
                    let (
                        cx,
                        cy
                    ) =
                        queue[qi]

                    qi += 1
                    count += 1

                    minX =
                        min(
                            minX,
                            cx
                        )

                    maxX =
                        max(
                            maxX,
                            cx
                        )

                    minY =
                        min(
                            minY,
                            cy
                        )

                    maxY =
                        max(
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

                        visited[ni] =
                            true

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

    static func nearbyLabel(
        for fruit: CGRect,
        imageWidth w: Int,
        imageHeight h: Int,
        ocr: [OCRItem]
    ) -> String {
        let center =
            CGPoint(
                x:
                    fruit.midX,
                y:
                    fruit.midY
            )

        let colWidth =
            Double(w) / 3.0

        let col =
            min(
                2,
                max(
                    0,
                    Int(
                        center.x /
                        colWidth
                    )
                )
            )

        let x0 =
            Double(col)
            * colWidth

        let x1 =
            Double(col + 1)
            * colWidth

        let y0 =
            fruit.maxY

        let y1 =
            min(
                Double(h),
                fruit.maxY
                +
                Double(h)
                * 0.095
            )

        let items =
            ocr.filter {
                $0.rect.midX >= x0 &&
                $0.rect.midX <= x1 &&
                $0.rect.midY >= y0 &&
                $0.rect.midY <= y1
            }

        return items
            .map {
                $0.text
            }
            .joined(
                separator: " "
            )
    }

    static func fruitCandidates(
        image: UIImage,
        data: [UInt8],
        width w: Int,
        height h: Int,
        cards: [StatusCard],
        ocr: [OCRItem]
    ) -> [FruitCandidate] {
        let startY =
            Int(
                Double(h) * 0.18
            )

        let endY =
            Int(
                Double(h) * 0.94
            )

        var mask = [Bool](
            repeating: false,
            count: w * h
        )

        for y in startY..<endY {
            for x in 0..<w {
                let value =
                    hsv(
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

        let columnWidth =
            Double(w) / 3.0

        var result: [
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
                Double(w)
                * 0.040
                ||
                bw >
                Double(w)
                * 0.185 {
                continue
            }

            if bh <
                Double(h)
                * 0.018
                ||
                bh >
                Double(h)
                * 0.110 {
                continue
            }

            let aspect =
                bw /
                max(
                    1,
                    bh
                )

            if aspect < 0.52 ||
                aspect > 1.95 {
                continue
            }

            let fill =
                Double(count)
                /
                max(
                    1,
                    bw * bh
                )

            if fill < 0.44 {
                continue
            }

            let center =
                CGPoint(
                    x:
                        rect.midX,
                    y:
                        rect.midY
                )

            // If it belongs to BUSY/COMPLETE card,
            // it is not an available candidate.
            if cards.contains(
                where: {
                    $0.rect.insetBy(
                        dx: -8,
                        dy: -8
                    )
                    .contains(
                        center
                    )
                }
            ) {
                continue
            }

            let col =
                min(
                    2,
                    max(
                        0,
                        Int(
                            center.x /
                            columnWidth
                        )
                    )
                )

            let expectedCenter =
                (
                    Double(col)
                    +
                    0.5
                )
                *
                columnWidth

            // Plain AVAILABLE fruit is centered in its column.
            // This also helps exclude small decor icons on the right.
            if abs(
                center.x -
                expectedCenter
            )
            >
            columnWidth * 0.28 {
                continue
            }

            let label =
                nearbyLabel(
                    for: rect,
                    imageWidth: w,
                    imageHeight: h,
                    ocr: ocr
                )

            // Seedlings are never fruit.
            if label.contains(
                "花苗"
            ) {
                continue
            }

            result.append(
                FruitCandidate(
                    rect: rect,
                    center: center,
                    fill: fill,
                    state: .available,
                    labelText: label
                )
            )
        }

        result.sort {
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

        var dedup:
            [
                FruitCandidate
            ] = []

        for fruit in result {
            let duplicate =
                dedup.contains {
                    abs(
                        $0.center.x -
                        fruit.center.x
                    )
                    <
                    Double(w)
                    * 0.045
                    &&
                    abs(
                        $0.center.y -
                        fruit.center.y
                    )
                    <
                    Double(h)
                    * 0.035
                }

            if !duplicate {
                dedup.append(
                    fruit
                )
            }
        }

        return dedup
    }

    // ---------------------------------------------------------
    // Main detection
    // ---------------------------------------------------------

    static func detect(
        in image: UIImage
    ) async -> DetectionResult {
        guard let (
            w,
            h,
            data
        ) =
            rawPixels(
                image
            )
        else {
            return DetectionResult(
                fruits: [],
                cards: [],
                ocr: []
            )
        }

        let ocr =
            await recognizeAllText(
                image: image
            )

        let cards =
            detectStatusCards(
                data: data,
                width: w,
                height: h
            )

        let fruits =
            fruitCandidates(
                image: image,
                data: data,
                width: w,
                height: h,
                cards: cards,
                ocr: ocr
            )

        return DetectionResult(
            fruits: fruits,
            cards: cards,
            ocr: ocr
        )
    }

    // ---------------------------------------------------------
    // Debug annotation
    // ---------------------------------------------------------

    static func annotated(
        image: UIImage,
        result: DetectionResult
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

        let sx =
            image.size.width /
            cgW

        let sy =
            image.size.height /
            cgH

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

            // First draw full BUSY/COMPLETE cards.
            for card in
                result.cards {
                let color:
                    UIColor =
                    card.state ==
                        .busy
                    ? .red
                    : .blue

                color.setStroke()

                let rect =
                    CGRect(
                        x:
                            card.rect.minX
                            * sx,
                        y:
                            card.rect.minY
                            * sy,
                        width:
                            card.rect.width
                            * sx,
                        height:
                            card.rect.height
                            * sy
                    )

                let path =
                    UIBezierPath(
                        rect: rect
                    )

                path.lineWidth =
                    4

                path.stroke()
            }

            // Only genuine plain fruit is GREEN.
            for fruit in
                result.fruits {
                UIColor.green
                    .setStroke()

                let rect =
                    CGRect(
                        x:
                            fruit.rect.minX
                            * sx,
                        y:
                            fruit.rect.minY
                            * sy,
                        width:
                            fruit.rect.width
                            * sx,
                        height:
                            fruit.rect.height
                            * sy
                    )
                    .insetBy(
                        dx: -4,
                        dy: -4
                    )

                let path =
                    UIBezierPath(
                        rect: rect
                    )

                path.lineWidth =
                    4

                path.stroke()
            }
        }
    }
}
