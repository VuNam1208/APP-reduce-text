import Flutter
import PDFKit
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private let channelName = "document_summary/file_reader"
  private var pendingDocumentResult: FlutterResult?
  private var pendingShareResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let documentChannel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    documentChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "pickTextFile" {
        self?.pickTextFile(result: result)
        return
      }

      if call.method == "saveTextFile" {
        guard let arguments = call.arguments as? [String: Any] else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "Thieu noi dung file can luu.",
              details: nil
            )
          )
          return
        }

        self?.saveTextFile(
          fileName: arguments["fileName"] as? String ?? "summary.txt",
          content: arguments["content"] as? String ?? "",
          result: result
        )
        return
      }

      if call.method == "saveBinaryFile" {
        guard
          let arguments = call.arguments as? [String: Any],
          let bytes = arguments["bytes"] as? FlutterStandardTypedData
        else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "No file data was provided.",
              details: nil
            )
          )
          return
        }

        self?.saveBinaryFile(
          fileName: arguments["fileName"] as? String ?? "summary.pdf",
          data: bytes.data,
          mimeType: arguments["mimeType"] as? String ?? "application/octet-stream",
          result: result
        )
        return
      }

      if call.method == "ocrScannedPdf" {
        guard
          let arguments = call.arguments as? [String: Any],
          let bytes = arguments["bytes"] as? FlutterStandardTypedData
        else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "Khong co du lieu PDF de OCR.",
              details: nil
            )
          )
          return
        }

        self?.ocrScannedPdf(data: bytes.data, result: result)
        return
      }

      if call.method == "ocrImage" {
        guard
          let arguments = call.arguments as? [String: Any],
          let bytes = arguments["bytes"] as? FlutterStandardTypedData
        else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "Khong co du lieu anh de OCR.",
              details: nil
            )
          )
          return
        }

        self?.ocrImage(data: bytes.data, result: result)
        return
      }

      result(FlutterMethodNotImplemented)
    }
  }

  private func pickTextFile(result: @escaping FlutterResult) {
    guard pendingDocumentResult == nil else {
      result(
        FlutterError(
          code: "busy",
          message: "Dang mo trinh chon file.",
          details: nil
        )
      )
      return
    }

    pendingDocumentResult = result

    let picker = UIDocumentPickerViewController(
      documentTypes: [
        "public.text",
        "public.plain-text",
        "public.utf8-plain-text",
        "public.comma-separated-values-text",
        "public.json",
        "public.xml",
        "com.adobe.pdf",
        "org.openxmlformats.wordprocessingml.document",
        "public.jpeg",
        "public.png",
        "public.image",
      ],
      in: .import
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false

    guard let presenter = topViewController() else {
      pendingDocumentResult = nil
      result(
        FlutterError(
          code: "no_presenter",
          message: "Khong the mo trinh chon file.",
          details: nil
        )
      )
      return
    }

    presenter.present(picker, animated: true)
  }

  private func ocrScannedPdf(data: Data, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let document = PDFDocument(data: data) else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "ocr_failed",
              message: "Khong the mo file PDF scan.",
              details: nil
            )
          )
        }
        return
      }

      do {
        var pageTexts: [String] = []
        let pageCount = min(document.pageCount, 30)

        for index in 0..<pageCount {
          guard
            let page = document.page(at: index),
            let image = self.renderPageForOcr(page),
            let cgImage = image.cgImage
          else {
            continue
          }

          let pageText = try self.recognizeText(in: cgImage)
          if !pageText.isEmpty {
            pageTexts.append(pageText)
          }
        }

        DispatchQueue.main.async {
          result(pageTexts.joined(separator: "\n\n"))
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "ocr_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func ocrImage(data: Data, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let image = UIImage(data: data), let cgImage = image.cgImage else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "ocr_failed",
              message: "Khong the doc anh da chon.",
              details: nil
            )
          )
        }
        return
      }

      do {
        let text = try self.recognizeText(in: cgImage)

        DispatchQueue.main.async {
          result(text)
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "ocr_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func renderPageForOcr(_ page: PDFPage) -> UIImage? {
    let bounds = page.bounds(for: .mediaBox)
    let longestSide = max(bounds.width, bounds.height)
    let scale = max(0.5, min(2200 / longestSide, 3.0))
    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)

    return renderer.image { context in
      UIColor.white.set()
      context.fill(CGRect(origin: .zero, size: size))
      context.cgContext.saveGState()
      context.cgContext.translateBy(x: 0, y: size.height)
      context.cgContext.scaleBy(x: scale, y: -scale)
      page.draw(with: .mediaBox, to: context.cgContext)
      context.cgContext.restoreGState()
    }
  }

  private func recognizeText(in image: CGImage) throws -> String {
    var recognizedLines: [String] = []
    var requestError: Error?
    let request = VNRecognizeTextRequest { request, error in
      requestError = error

      guard let observations = request.results as? [VNRecognizedTextObservation] else {
        return
      }

      recognizedLines = observations.compactMap { observation in
        observation.topCandidates(1).first?.string
      }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["vi-VN", "en-US"]

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    if let requestError = requestError {
      throw requestError
    }

    return recognizedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func saveBinaryFile(
    fileName: String,
    data: Data,
    mimeType: String,
    result: @escaping FlutterResult
  ) {
    guard pendingShareResult == nil else {
      result(
        FlutterError(
          code: "busy",
          message: "A save sheet is already open.",
          details: nil
        )
      )
      return
    }

    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "no_presenter",
          message: "Could not open the save sheet.",
          details: nil
        )
      )
      return
    }

    do {
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(ensureFileName(fileName, extensionForMimeType(mimeType)))
      try data.write(to: url, options: .atomic)

      presentShareSheet(url: url, presenter: presenter, result: result)
    } catch {
      result(
        FlutterError(
          code: "write_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func presentShareSheet(
    url: URL,
    presenter: UIViewController,
    result: @escaping FlutterResult
  ) {
    pendingShareResult = result

    let activityController = UIActivityViewController(
      activityItems: [url],
      applicationActivities: nil
    )
    activityController.completionWithItemsHandler = { [weak self] _, completed, _, error in
      guard let shareResult = self?.pendingShareResult else {
        return
      }

      self?.pendingShareResult = nil

      if let error = error {
        shareResult(
          FlutterError(
            code: "write_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
        return
      }

      shareResult(completed)
    }

    if let popover = activityController.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(
        x: presenter.view.bounds.midX,
        y: presenter.view.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }

    presenter.present(activityController, animated: true)
  }

  private func saveTextFile(
    fileName: String,
    content: String,
    result: @escaping FlutterResult
  ) {
    guard pendingShareResult == nil else {
      result(
        FlutterError(
          code: "busy",
          message: "Dang mo trinh luu file.",
          details: nil
        )
      )
      return
    }

    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "no_presenter",
          message: "Khong the mo trinh luu file.",
          details: nil
        )
      )
      return
    }

    do {
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(ensureTextFileName(fileName))
      try content.write(to: url, atomically: true, encoding: .utf8)

      presentShareSheet(url: url, presenter: presenter, result: result)
    } catch {
      result(
        FlutterError(
          code: "write_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pendingDocumentResult else {
      return
    }

    pendingDocumentResult = nil

    guard let url = urls.first else {
      result(nil)
      return
    }

    let hasAccess = url.startAccessingSecurityScopedResource()
    defer {
      if hasAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let data = try Data(contentsOf: url, options: .mappedIfSafe)

      guard data.count <= 20 * 1024 * 1024 else {
        result(
          FlutterError(
            code: "file_too_large",
            message: "File qua lon. Hay chon file duoi 20 MB.",
            details: nil
          )
        )
        return
      }

      let content = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .ascii)
        ?? ""

      result([
        "name": url.lastPathComponent,
        "content": content,
        "bytes": FlutterStandardTypedData(bytes: data),
      ])
    } catch {
      result(
        FlutterError(
          code: "read_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingDocumentResult?(nil)
    pendingDocumentResult = nil
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let keyWindow = scenes
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }

    var controller = keyWindow?.rootViewController

    while let presented = controller?.presentedViewController {
      controller = presented
    }

    return controller
  }

  private func ensureTextFileName(_ fileName: String) -> String {
    ensureFileName(fileName, "txt")
  }

  private func ensureFileName(_ fileName: String, _ fileExtension: String) -> String {
    let trimmedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackName = trimmedName.isEmpty ? "summary.\(fileExtension)" : trimmedName
    let suffix = ".\(fileExtension)"

    if fallbackName.lowercased().hasSuffix(suffix) {
      return fallbackName
    }

    return "\(fallbackName)\(suffix)"
  }

  private func extensionForMimeType(_ mimeType: String) -> String {
    switch mimeType {
    case "application/pdf":
      return "pdf"
    case "text/plain":
      return "txt"
    default:
      return "bin"
    }
  }
}
