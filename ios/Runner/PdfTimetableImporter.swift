import Flutter
import PDFKit
import UniformTypeIdentifiers
import UIKit
import Vision

final class PdfTimetableImporter: NSObject, UIDocumentPickerDelegate {
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
            guard let self else {
                result(FlutterError(code: "importer_unavailable", message: "课表读取器未就绪，请重试", details: nil))
                return
            }
            self.pick(result: result)
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
        let presenter = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
        guard let presenter else {
            pendingResult = nil
            result(FlutterError(code: "picker_unavailable", message: "无法打开文件选择器", details: nil))
            return
        }
        presenter.present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingResult?(nil)
        pendingResult = nil
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let result = pendingResult else { return }
        guard let url = urls.first else {
            pendingResult = nil
            result(FlutterError(code: "invalid_pdf", message: "未取得 PDF 文件，请重新选择", details: nil))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let payload = Self.readDocument(at: url)
            DispatchQueue.main.async {
                self.pendingResult = nil
                result(payload)
            }
        }
    }

    private static func readDocument(at url: URL) -> Any {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else {
            return FlutterError(code: "invalid_pdf", message: "无法读取所选 PDF 文件", details: nil)
        }
        guard !document.isLocked else {
            return FlutterError(code: "encrypted_pdf", message: "PDF 已加密或需要密码", details: nil)
        }
        guard document.pageCount > 0 else {
            return FlutterError(code: "empty_pdf", message: "PDF 中没有可读取的页面", details: nil)
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
            return ["pages": pages]
        } catch {
            return FlutterError(code: "pdf_read_failed", message: "读取 PDF 文字失败", details: nil)
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
        guard let text = page.string else { return [] }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0, page.rotation == 0 || page.rotation == 90 else { return [] }
        let rotated = page.rotation == 90
        let displayWidth = rotated ? bounds.height : bounds.width
        let displayHeight = rotated ? bounds.width : bounds.height
        let characters = text as NSString
        var lines = [[(String, CGRect)]]()
        for index in 0..<characters.length {
            let glyph = page.characterBounds(at: index)
            guard !glyph.isNull, glyph.width > 0, glyph.height > 0 else { continue }
            let rect = rotated
                ? CGRect(x: glyph.minX, y: glyph.minY + bounds.width, width: glyph.width, height: glyph.height)
                : glyph
            let value = characters.substring(with: NSRange(location: index, length: 1))
            if let previous = lines.last?.last?.1,
               abs(previous.midY - rect.midY) < 2.5,
               rect.minX >= previous.maxX - 2,
               rect.minX - previous.maxX < 25 {
                lines[lines.count - 1].append((value, rect))
            } else {
                lines.append([(value, rect)])
            }
        }
        var spans = [Span]()
        let weekdayLabels = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
        for label in weekdayLabels {
            let range = characters.range(of: label)
            guard range.location != NSNotFound else { continue }
            let glyphs = (range.location..<NSMaxRange(range)).map { index -> (String, CGRect) in
                let glyph = page.characterBounds(at: index)
                let rect = rotated
                    ? CGRect(x: glyph.minX, y: glyph.minY + bounds.width, width: glyph.width, height: glyph.height)
                    : glyph
                return (characters.substring(with: NSRange(location: index, length: 1)), rect)
            }
            spans.append(makeSpan(label, glyphs: glyphs, bounds: bounds,
                                  width: displayWidth, height: displayHeight))
        }
        for line in lines {
            let lineText = line.map(\.0).joined()
            if weekdayLabels.contains(where: lineText.contains) { continue }
            let value = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                spans.append(makeSpan(value, glyphs: line, bounds: bounds,
                                      width: displayWidth, height: displayHeight))
            }
        }
        return spans
    }

    private static func makeSpan(
        _ text: String,
        glyphs: [(String, CGRect)],
        bounds: CGRect,
        width: CGFloat,
        height: CGFloat
    ) -> Span {
        let first = glyphs[0].1
        let rect = glyphs.dropFirst().reduce(first) { $0.union($1.1) }
        return Span(text: text, x: Double((rect.minX - bounds.minX) / width),
                    y: Double(1 - (rect.maxY - bounds.minY) / height),
                    width: Double(rect.width / width), height: Double(rect.height / height))
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
