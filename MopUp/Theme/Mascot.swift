import SwiftUI

/// Mop Up's mascot: a soapy bucket with a mop, in the rubber-hose cartoon style
/// of the BrewDock mug (thick ink outlines, pastel fills, big eyes, white glove).
/// Drawn on a pastel disc so it reads in dark mode too.
struct Mascot: View {
    enum Mood { case happy, working, proud, sleepy }

    var mood: Mood = .happy
    var size: CGFloat = 72
    var disc: Color = AppColors.periwinkle

    private static let ink = Color(hex: 0x232428)
    private static let bucket = Color(hex: 0xC2E6D6)      // mint
    private static let bucketShade = Color(hex: 0xA3D4BF)
    private static let water = Color(hex: 0xA9D8F0)
    private static let suds = Color(hex: 0xFFFFFF)
    private static let wood = Color(hex: 0xE8B97E)
    private static let mopHead = Color(hex: 0xF6E2A4)     // butter
    private static let sclera = Color(hex: 0xFBF6E9)
    private static let blush = Color(hex: 0xF6C3B4)       // peach
    private static let sweat = Color(hex: 0x8FCBEB)

    var body: some View {
        Canvas { context, canvasSize in
            // Draw in a 100×100 space
            let scale = min(canvasSize.width, canvasSize.height) / 100
            context.scaleBy(x: scale, y: scale)
            draw(in: &context)
        }
        .frame(width: size, height: size)
        .background(disc, in: Circle())
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext) {
        let ink = Self.ink
        let outline = StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)

        // Mop: a wooden handle leaning out of the bucket, strings tucked inside
        var handle = Path()
        handle.move(to: CGPoint(x: 58, y: 40))
        handle.addLine(to: CGPoint(x: 80, y: 9))
        context.stroke(handle, with: .color(ink), style: StrokeStyle(lineWidth: 7.5, lineCap: .round))
        context.stroke(handle, with: .color(Self.wood), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        // Mop strings poking over the rim
        for (x, lean, top) in [(53.0, -4.0, 29.0), (57.0, -1.5, 26.0), (61.0, 1.0, 25.0),
                               (65.0, 3.5, 27.0), (69.0, 6.0, 30.0)] {
            var string = Path()
            string.move(to: CGPoint(x: x, y: 39))
            string.addQuadCurve(to: CGPoint(x: x + lean, y: top), control: CGPoint(x: x + lean * 1.8, y: 34))
            context.stroke(string, with: .color(ink), style: StrokeStyle(lineWidth: 6.4, lineCap: .round))
            context.stroke(string, with: .color(Self.mopHead), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }

        // Bucket body, tapered
        var body = Path()
        body.move(to: CGPoint(x: 24, y: 38))
        body.addLine(to: CGPoint(x: 76, y: 38))
        body.addLine(to: CGPoint(x: 70, y: 82))
        body.addQuadCurve(to: CGPoint(x: 63, y: 89), control: CGPoint(x: 69.5, y: 89))
        body.addLine(to: CGPoint(x: 37, y: 89))
        body.addQuadCurve(to: CGPoint(x: 30, y: 82), control: CGPoint(x: 30.5, y: 89))
        body.closeSubpath()
        context.fill(body, with: .color(Self.bucket))
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(Path(CGRect(x: 62, y: 34, width: 20, height: 60)), with: .color(Self.bucketShade))
            // A band near the bottom, like a real pail
            layer.fill(Path(CGRect(x: 20, y: 80, width: 60, height: 2.4)), with: .color(ink.opacity(0.18)))
        }
        context.stroke(body, with: .color(ink), style: outline)

        // Rim with soapy water
        let rim = Path(ellipseIn: CGRect(x: 23, y: 33, width: 54, height: 11))
        context.fill(rim, with: .color(Self.water))
        context.stroke(rim, with: .color(ink), style: outline)

        // Suds piled up on the left of the rim
        for bubble in [CGRect(x: 22, y: 27, width: 13, height: 13),
                       CGRect(x: 31, y: 23, width: 15, height: 15),
                       CGRect(x: 42, y: 28, width: 11, height: 11),
                       CGRect(x: 17, y: 20, width: 7, height: 7)] {
            let suds = Path(ellipseIn: bubble)
            context.fill(suds, with: .color(Self.suds))
            context.stroke(suds, with: .color(ink), lineWidth: 2.1)
            // Shine
            context.fill(Path(ellipseIn: CGRect(x: bubble.minX + bubble.width * 0.25,
                                                y: bubble.minY + bubble.height * 0.22,
                                                width: bubble.width * 0.22, height: bubble.height * 0.22)),
                         with: .color(Self.water))
        }

        // Cheeks
        for x in [31.0, 60.0] {
            context.fill(Path(ellipseIn: CGRect(x: x, y: 70, width: 9, height: 4.5)), with: .color(Self.blush))
        }

        // Eyes
        for x in [35.0, 52.0] {
            let eyeRect = CGRect(x: x, y: 51, width: 12, height: 15)
            switch mood {
            case .happy:
                let eye = Path(ellipseIn: eyeRect)
                context.fill(eye, with: .color(Self.sclera))
                context.stroke(eye, with: .color(ink), lineWidth: 2.2)
                context.fill(Path(ellipseIn: CGRect(x: x + 4, y: 55.5, width: 7, height: 9)), with: .color(ink))
                context.fill(Path(ellipseIn: CGRect(x: x + 5.3, y: 56.6, width: 2.6, height: 2.6)), with: .color(.white))
            case .working:
                // Focused: eyes looking down at the work
                let eye = Path(ellipseIn: eyeRect)
                context.fill(eye, with: .color(Self.sclera))
                context.stroke(eye, with: .color(ink), lineWidth: 2.2)
                context.fill(Path(ellipseIn: CGRect(x: x + 2.5, y: 58, width: 7, height: 7.5)), with: .color(ink))
                // Heavy lid across the top
                var lid = Path()
                lid.move(to: CGPoint(x: x, y: 56))
                lid.addLine(to: CGPoint(x: x + 12, y: 56))
                context.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            case .proud:
                // Closed, smiling eyes: ^ ^
                var arc = Path()
                arc.move(to: CGPoint(x: x + 1, y: 61))
                arc.addQuadCurve(to: CGPoint(x: x + 11, y: 61), control: CGPoint(x: x + 6, y: 52))
                context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            case .sleepy:
                var lid = Path()
                lid.move(to: CGPoint(x: x + 1, y: 59))
                lid.addQuadCurve(to: CGPoint(x: x + 11, y: 59), control: CGPoint(x: x + 6, y: 64))
                context.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
            if mood != .proud {
                var brow = Path()
                brow.move(to: CGPoint(x: x + 2, y: 48))
                brow.addQuadCurve(to: CGPoint(x: x + 10, y: 48), control: CGPoint(x: x + 6, y: 44.5))
                context.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }

        // Mouth
        var mouth = Path()
        switch mood {
        case .working:
            mouth.move(to: CGPoint(x: 45, y: 76))
            mouth.addQuadCurve(to: CGPoint(x: 53, y: 76), control: CGPoint(x: 49, y: 78))
            context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        case .proud:
            mouth.move(to: CGPoint(x: 42.5, y: 74))
            mouth.addQuadCurve(to: CGPoint(x: 55.5, y: 74), control: CGPoint(x: 49, y: 83))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(ink))
            context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        default:
            mouth.move(to: CGPoint(x: 44, y: 75))
            mouth.addQuadCurve(to: CGPoint(x: 54, y: 75), control: CGPoint(x: 49, y: 80.5))
            context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }

        // Sweat drop while working
        if mood == .working {
            var drop = Path()
            drop.move(to: CGPoint(x: 72, y: 47))
            drop.addQuadCurve(to: CGPoint(x: 72, y: 57), control: CGPoint(x: 66, y: 55))
            drop.addQuadCurve(to: CGPoint(x: 72, y: 47), control: CGPoint(x: 78, y: 55))
            context.fill(drop, with: .color(Self.sweat))
            context.stroke(drop, with: .color(ink), lineWidth: 1.8)
        }

        // Sparkles when the job's done
        if mood == .proud {
            for (cx, cy, r) in [(86.0, 30.0, 6.0), (14.0, 56.0, 4.5), (88.0, 66.0, 4.0)] {
                var star = Path()
                star.move(to: CGPoint(x: cx, y: cy - r))
                star.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx, y: cy))
                star.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx, y: cy))
                star.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx, y: cy))
                star.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx, y: cy))
                context.fill(star, with: .color(.white))
                context.stroke(star, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
        }

        // Waving rubber-hose arm with a white glove (not while working)
        guard mood != .working else { return }
        var arm = Path()
        arm.move(to: CGPoint(x: 29, y: 64))
        arm.addCurve(to: CGPoint(x: 14, y: 49),
                     control1: CGPoint(x: 19, y: 67),
                     control2: CGPoint(x: 12, y: 58))
        context.stroke(arm, with: .color(ink), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
        let glove = Path(ellipseIn: CGRect(x: 7.5, y: 38, width: 13, height: 12.5))
        context.fill(glove, with: .color(.white))
        context.stroke(glove, with: .color(ink), lineWidth: 2.2)
        let thumb = Path(ellipseIn: CGRect(x: 17, y: 42, width: 6, height: 5.5))
        context.fill(thumb, with: .color(.white))
        context.stroke(thumb, with: .color(ink), lineWidth: 2)
        for dx in [11.5, 14.5] {
            var crease = Path()
            crease.move(to: CGPoint(x: dx, y: 40.5))
            crease.addLine(to: CGPoint(x: dx, y: 44))
            context.stroke(crease, with: .color(ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }
}
