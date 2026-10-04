#!/usr/bin/env swift

// Mathematical source for Trigrams brand assets; no application behavior.
import Foundation

struct Point {
    let x: Double
    let y: Double
}

struct SineMark {
    let length: Double
    let amplitude: Double
    let radius: Double
    let emphasis: Double
    let samples = 384

    func center(_ t: Double) -> Point {
        Point(x: (256 - length) / 2 + length * t,
              y: 128 - amplitude * sin(2 * .pi * t))
    }

    func frame(_ t: Double) -> (tangent: Point, normal: Point) {
        let dy = -2 * .pi * amplitude * cos(2 * .pi * t)
        let magnitude = hypot(length, dy)
        return (Point(x: length / magnitude, y: dy / magnitude),
                Point(x: -dy / magnitude, y: length / magnitude))
    }

    func halfWidth(_ t: Double) -> Double {
        radius + emphasis * pow(sin(.pi * t), 2)
    }

    func edge(_ t: Double, side: Double) -> Point {
        let c = center(t)
        let n = frame(t).normal
        let r = halfWidth(t) * side
        return Point(x: c.x + r * n.x, y: c.y + r * n.y)
    }

    var outline: [Point] {
        var points = (0...samples).map { edge(Double($0) / Double(samples), side: 1) }
        let end = center(1)
        let ef = frame(1)
        for step in 1...48 {
            let angle = .pi * Double(step) / 48
            points.append(Point(x: end.x + radius * (cos(angle) * ef.normal.x + sin(angle) * ef.tangent.x),
                                y: end.y + radius * (cos(angle) * ef.normal.y + sin(angle) * ef.tangent.y)))
        }
        points += (0..<samples).reversed().map { edge(Double($0) / Double(samples), side: -1) }
        let start = center(0)
        let sf = frame(0)
        for step in 1...48 {
            let angle = .pi * Double(step) / 48
            points.append(Point(x: start.x - radius * (cos(angle) * sf.normal.x + sin(angle) * sf.tangent.x),
                                y: start.y - radius * (cos(angle) * sf.normal.y + sin(angle) * sf.tangent.y)))
        }
        return points
    }

    var path: String {
        outline.enumerated().map { index, point in
            "\(index == 0 ? "M" : "L")\(number(point.x)) \(number(point.y))"
        }.joined(separator: " ") + " Z"
    }

    var guide: String {
        (0...samples).map { step in
            let point = center(Double(step) / Double(samples))
            return "\(step == 0 ? "M" : "L")\(number(point.x)) \(number(point.y))"
        }.joined(separator: " ")
    }

    func validate() {
        for p in outline {
            precondition(p.x.isFinite && p.y.isFinite)
            precondition((0...256).contains(p.x) && (0...256).contains(p.y))
        }
        for step in 0...samples {
            let t = Double(step) / Double(samples)
            let dy = -2 * .pi * amplitude * cos(2 * .pi * t)
            let ddy = 4 * .pi * .pi * amplitude * sin(2 * .pi * t)
            let curvature = abs(length * ddy) / pow(length * length + dy * dy, 1.5)
            precondition(curvature * halfWidth(t) < 1, "Offset curve must not fold locally.")
        }
    }

    var parameters: [String: Double] {
        ["length": length, "amplitude": amplitude, "radius": radius, "emphasis": emphasis]
    }
}

func number(_ value: Double) -> String {
    String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
}

func svg(path: String, color: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" role="img" aria-label="Trigrams sine mark">
    <path fill="\(color)" d="\(path)"/>
    </svg>
    """ + "\n"
}

let output = CommandLine.arguments.count == 2
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: #filePath).deletingLastPathComponent()
precondition(CommandLine.arguments.count <= 2, "Usage: swift generate-logo.swift [output-directory]")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let main = SineMark(length: 192, amplitude: 64, radius: 9, emphasis: 4)
let small = SineMark(length: 208, amplitude: 56, radius: 11, emphasis: 3)
main.validate()
small.validate()
let geometry: [String: Any] = [
    "viewBox": [0, 0, 256, 256], "path": main.path, "smallPath": small.path,
    "centerline": main.guide, "main": main.parameters, "small": small.parameters,
    "equation": "C(t) = ((256-L)/2 + Lt, 128 - A sin(2πt)); r(t) = r0 + e sin²(πt)",
]
let json = try JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try (json + Data("\n".utf8)).write(to: output.appendingPathComponent("geometry.json"))
for (name, color) in [("trigrams-mark.svg", "#673AB7"), ("trigrams-mark-light.svg", "#673AB7"), ("trigrams-mark-dark.svg", "#81A1C1")] {
    try svg(path: main.path, color: color).write(to: output.appendingPathComponent(name), atomically: true, encoding: .utf8)
}
print("Generated sine geometry and theme marks; \(main.outline.count) outline vertices.")
