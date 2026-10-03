import Flutter
import PDFKit
import UniformTypeIdentifiers
import UIKit
import Vision

final class PdfTimetableImporter: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
    private let channel: FlutterMethodChannel
    private var pendingResult: FlutterResult?

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "top.celechron/pdf_timetable", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "pickAndRead" else {
                result(FlutterMethodNotImplemented)
                return
            }
            self?.pick(result: result)
        }
    }

    private func pick(result: @escaping FlutterResult) {
        guard pendingResult == nil else {
            result(FlutterError(code: "busy", message: "已有 PDF 正在读取", details: nil))
            return
        }
        pendingResult = result
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?.present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingResult?(nil)
        pendingResult = nil
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let result = pendingResult else { return }
        pendingResult = nil
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else {
            result(FlutterError(code: "invalid_pdf", message: "无法读取所选 PDF 文件", details: nil))
            return
        }
        guard !document.isLocked else {
            result(FlutterError(code: "encrypted_pdf", message: "PDF 已加密或需要密码", details: nil))
            return
        }
        guard document.pageCount > 0 else {
            result(FlutterError(code: "empty_pdf", message: "PDF 中没有可读取的页面", details: nil))
            return
        }
        do {
            var pages = [[String: Any]]()
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                var spans = Self.pdfSpans(page: page)
                var source = "pdf"
                if spans.reduce(0, { $0 + $1.text.count }) < 80 {
                    spans = try Self.ocrSpans(page: page)
                    source = "vision"
                }
                pages.append(["index": index, "rotation": page.rotation, "source": source,
                              "spans": spans.map { ["text": $0.text, "x": $0.x, "y": $0.y,
                                                    "width": $0.width, "height": $0.height] }])
            }
            result(["pages": pages])
        } catch {
            result(FlutterError(code: "pdf_read_failed", message: "读取 PDF 文字失败", details: nil))
        }
    }

    private struct Span {
        let text: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    private static func pdfSpans(page: PDFPage) -> [Span] {
        guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        let bounds = page.bounds(for: .cropBox)
        return selection.selectionsByLine().compactMap { line in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let rect = line.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            return Span(text: text, x: Double((rect.minX - bounds.minX) / bounds.width),
                        y: Double(1 - (rect.maxY - bounds.minY) / bounds.height),
                        width: Double(rect.width / bounds.width), height: Double(rect.height / bounds.height))
        }
    }

    private static func ocrSpans(page: PDFPage) throws -> [Span] {
        let image = page.thumbnail(of: CGSize(width: 2200, height: 1600), for: .cropBox)
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { item in
            guard let text = item.topCandidates(1).first?.string else { return nil }
            let box = item.boundingBox
            return Span(text: text, x: Double(box.minX), y: Double(1 - box.maxY),
                        width: Double(box.width), height: Double(box.height))
        }
    }
}
