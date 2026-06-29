#!/usr/bin/env swift

import Vision
import AppKit
import Foundation

// MARK: - OCR + 场景分析脚本，使用 Apple Vision 框架
// 识别文字、场景分类、人脸/人体/条码检测，输出结构化文本供 LLM 消费

// MARK: - 配置

struct Config {
    var imageURL: URL? = nil
    var useClipboard = false
    var useFast = false
    var plainMode = false       // 纯文本输出，适合 LLM
    var quietMode = false       // 仅输出识别文字
    var noClassify = false      // 跳过场景分类
    var noDetect = false        // 跳过对象检测
    var lang = "zh-Hans"        // 主要识别语言
}

// MARK: - Vision 分析器

struct AnalysisResult {
    var classifications: [String] = []
    var recognizedTexts: [RecognizedItem] = []
    var faceCount = 0
    var humanCount = 0
    var barcodes: [String] = []
    var imageSize: (width: Int, height: Int) = (0, 0)

    var hasAnyContent: Bool {
        !classifications.isEmpty || !recognizedTexts.isEmpty ||
        faceCount > 0 || humanCount > 0 || !barcodes.isEmpty
    }
}

struct RecognizedItem {
    let text: String
    let confidence: Int
    let boundingBox: CGRect
}

func analyzeImage(cgImage: CGImage, config: Config) -> AnalysisResult {
    var result = AnalysisResult()
    result.imageSize = (width: cgImage.width, height: cgImage.height)

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    var requests: [VNRequest] = []

    // 1. 文字识别 (OCR)
    let textRequest = VNRecognizeTextRequest { request, error in
        guard error == nil,
              let observations = request.results as? [VNRecognizedTextObservation] else { return }

        let items: [RecognizedItem] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedItem(
                text: candidate.string,
                confidence: Int(candidate.confidence * 100),
                boundingBox: observation.boundingBox
            )
        }

        // 按位置从上到下、从左到右排序
        result.recognizedTexts = items.sorted { a, b in
            let ya = a.boundingBox.origin.y + a.boundingBox.height
            let yb = b.boundingBox.origin.y + b.boundingBox.height
            if abs(ya - yb) < 0.02 {
                return a.boundingBox.origin.x < b.boundingBox.origin.x
            }
            return ya > yb
        }
    }
    textRequest.recognitionLevel = config.useFast ? .fast : .accurate
    textRequest.usesLanguageCorrection = true
    textRequest.recognitionLanguages = [config.lang, "zh-Hant", "en", "ja", "ko"]
    requests.append(textRequest)

    // 2. 场景分类
    if !config.noClassify {
        let classifyRequest = VNClassifyImageRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNClassificationObservation] else { return }
            result.classifications = observations
                .filter { $0.confidence > 0.2 }
                .prefix(5)
                .map { "\($0.identifier)（\(Int($0.confidence * 100))%）" }
        }
        requests.append(classifyRequest)
    }

    // 3. 人脸检测
    if !config.noDetect {
        let faceRequest = VNDetectFaceRectanglesRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNFaceObservation] else { return }
            result.faceCount = observations.count
        }
        requests.append(faceRequest)
    }

    // 4. 人体检测 (macOS 13+)
    if !config.noDetect {
        if #available(macOS 13.0, *) {
            let humanRequest = VNDetectHumanRectanglesRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNHumanObservation] else { return }
                result.humanCount = observations.count
            }
            requests.append(humanRequest)
        }
    }

    // 5. 条码 / 二维码检测
    if !config.noDetect {
        let barcodeRequest = VNDetectBarcodesRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNBarcodeObservation] else { return }
            result.barcodes = observations.compactMap { observation in
                guard let payload = observation.payloadStringValue else { return nil }
                let type = observation.symbology.rawValue
                return "\(type): \(payload)"
            }
        }
        requests.append(barcodeRequest)
    }

    do {
        try handler.perform(requests)
    } catch {
        fputs("错误: Vision 分析失败 — \(error.localizedDescription)\n", stderr)
    }

    return result
}

// MARK: - 输出格式化

func formatOutput(_ result: AnalysisResult, config: Config) {
    if config.quietMode {
        // 仅输出识别文字，无任何装饰
        for item in result.recognizedTexts {
            print(item.text)
        }
        return
    }

    let sizeInfo = "\(result.imageSize.width)×\(result.imageSize.height)"

    if config.plainMode {
        // 纯文本格式，适合传给 LLM
        print("【图片信息】\(sizeInfo)")

        if !result.classifications.isEmpty {
            print("\n【场景分类】")
            for c in result.classifications {
                print("  \(c)")
            }
        }

        if !result.recognizedTexts.isEmpty {
            print("\n【识别文字】")
            for item in result.recognizedTexts {
                print("  \(item.text)")
            }
        } else if result.classifications.isEmpty {
            print("\n【识别文字】")
            print("  （未检测到文字）")
        }

        var detections: [String] = []
        if result.faceCount > 0 { detections.append("人脸 ×\(result.faceCount)") }
        if result.humanCount > 0 { detections.append("人体 ×\(result.humanCount)") }
        detections.append(contentsOf: result.barcodes.map { "条码: \($0)" })
        if !detections.isEmpty {
            print("\n【检测对象】")
            for d in detections {
                print("  \(d)")
            }
        }
        return
    }

    // 默认人类友好格式
    print("===== 图片分析 =====")
    print("尺寸: \(sizeInfo)")
    print("")

    if !result.classifications.isEmpty {
        print("┌─ 场景分类 ─────────────")
        for c in result.classifications {
            print("│ \(c)")
        }
        print("")
    }

    if !result.recognizedTexts.isEmpty {
        print("┌─ 识别文字 ─────────────")
        for item in result.recognizedTexts {
            let tag = item.confidence >= 90 ? "✓" : "~"
            print("│ \(tag) [\(item.confidence)%] \(item.text)")
        }
        print("")
    } else {
        print("┌─ 识别文字 ─────────────")
        print("│ （未检测到文字）")
        print("")
    }

    if result.faceCount > 0 || result.humanCount > 0 || !result.barcodes.isEmpty {
        print("┌─ 检测对象 ─────────────")
        if result.faceCount > 0 { print("│ 人脸: \(result.faceCount) 个") }
        if result.humanCount > 0 { print("│ 人体: \(result.humanCount) 个") }
        for barcode in result.barcodes { print("│ 条码: \(barcode)") }
        print("")
    }

    if !result.hasAnyContent {
        print("（未检测到任何可识别的内容）")
    }
}

// MARK: - 图片加载

func loadImage(from path: String) -> NSImage? {
    let url: URL
    if path.hasPrefix("/") {
        url = URL(fileURLWithPath: path)
    } else {
        url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
    }
    return NSImage(contentsOf: url)
}

func loadImageFromClipboard() -> NSImage? {
    let pasteboard = NSPasteboard.general
    // 尝试多种格式
    for type in [NSPasteboard.PasteboardType.tiff, .png] {
        if let data = pasteboard.data(forType: type),
           let image = NSImage(data: data) {
            return image
        }
    }
    return nil
}

func cgImage(from nsImage: NSImage) -> CGImage? {
    return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

// MARK: - 命令行解析

func printUsage() {
    let usage = """
    用法: swift ocr.swift <图片路径> [选项]

    选项:
      --fast         使用快速模式（牺牲精度换取速度）
      --quiet        仅输出识别文字，无格式无置信度
      --plain        纯文本分段输出，适合传给 LLM
      --clipboard    从剪贴板读取图片（不需要提供路径）
      --no-classify  跳过场景分类
      --no-detect    跳过人脸/人体/条码检测
      --lang <语言>   设置主要识别语言（默认 zh-Hans）
      --help         显示此帮助信息

    示例:
      swift ocr.swift screenshot.png
      swift ocr.swift photo.jpg --plain
      swift ocr.swift --clipboard --plain
      swift ocr.swift document.jpg --lang en
    """
    print(usage)
}

func parseArgs(_ args: [String]) -> Config {
    var config = Config()
    var i = 0

    while i < args.count {
        switch args[i] {
        case "--help", "-h":
            printUsage()
            exit(0)
        case "--fast":
            config.useFast = true
        case "--quiet":
            config.quietMode = true
        case "--plain":
            config.plainMode = true
        case "--clipboard":
            config.useClipboard = true
        case "--no-classify":
            config.noClassify = true
        case "--no-detect":
            config.noDetect = true
        case "--lang":
            i += 1
            if i < args.count { config.lang = args[i] }
        default:
            if !args[i].hasPrefix("--") {
                // 尝试作为文件路径
                let url: URL
                if args[i].hasPrefix("/") {
                    url = URL(fileURLWithPath: args[i])
                } else {
                    url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        .appendingPathComponent(args[i])
                }
                if FileManager.default.fileExists(atPath: url.path) {
                    config.imageURL = url
                }
            }
        }
        i += 1
    }

    return config
}

// MARK: - 主入口

let args = Array(CommandLine.arguments.dropFirst())

guard !args.isEmpty else {
    printUsage()
    exit(1)
}

let config = parseArgs(args)

// 加载图片
let nsImage: NSImage?

if config.useClipboard {
    nsImage = loadImageFromClipboard()
    guard nsImage != nil else {
        fputs("错误: 剪贴板中没有图片\n", stderr)
        exit(1)
    }
} else if let url = config.imageURL {
    nsImage = NSImage(contentsOf: url)
    guard nsImage != nil else {
        fputs("错误: 无法加载图片 \(url.path)\n", stderr)
        exit(1)
    }
} else {
    fputs("错误: 请提供图片路径或使用 --clipboard\n", stderr)
    printUsage()
    exit(1)
}

guard let cgImg = cgImage(from: nsImage!) else {
    fputs("错误: 无法将图片转换为 CGImage\n", stderr)
    exit(1)
}

// 分析并输出
let result = analyzeImage(cgImage: cgImg, config: config)
formatOutput(result, config: config)
