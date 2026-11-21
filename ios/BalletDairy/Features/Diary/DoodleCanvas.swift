import PencilKit
import SwiftUI

enum DoodleTool: String, CaseIterable, Identifiable {
    case ink, rose, lilac, eraser
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .ink: Theme.ink
        case .rose: Theme.ribbon
        case .lilac: Color(hex: 0x8F86C2)
        case .eraser: Theme.paperDeep
        }
    }
    var pkTool: PKTool {
        switch self {
        case .eraser: return PKEraserTool(.vector)
        case .ink: return PKInkingTool(.pen, color: UIColor(hex: 0x3A2E35), width: 2.4)
        case .rose: return PKInkingTool(.pen, color: UIColor(hex: 0xC5667D), width: 2.4)
        case .lilac: return PKInkingTool(.marker, color: UIColor(hex: 0xCEC4E6), width: 10)
        }
    }
}

/// A PencilKit sketch area for doodling poses, notes from class, little stick figures.
struct DoodleCanvas: UIViewRepresentable {
    @Binding var data: Data?
    var tool: DoodleTool
    var isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.drawingPolicy = .anyInput
        v.isScrollEnabled = false
        v.delegate = context.coordinator
        if let data, let d = try? PKDrawing(data: data) { v.drawing = d }
        v.tool = tool.pkTool
        v.isUserInteractionEnabled = isEditable
        return v
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        v.tool = tool.pkTool
        v.isUserInteractionEnabled = isEditable
        // external change (e.g. switching day) → reload
        if context.coordinator.lastWritten != data {
            context.coordinator.isLoading = true
            v.drawing = (data.flatMap { try? PKDrawing(data: $0) }) ?? PKDrawing()
            context.coordinator.lastWritten = data
            context.coordinator.isLoading = false
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DoodleCanvas
        var lastWritten: Data?
        var isLoading = false
        init(_ p: DoodleCanvas) { parent = p; lastWritten = p.data }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isLoading else { return }
            let d = canvasView.drawing.strokes.isEmpty ? nil : canvasView.drawing.dataRepresentation()
            lastWritten = d
            parent.data = d
        }
    }
}
