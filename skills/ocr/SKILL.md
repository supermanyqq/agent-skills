---
name: ocr
description: "使用 macOS Vision 框架对图片进行 OCR 文字识别、场景分类和对象检测。当后端模型不支持多模态（如 DeepSeek）时，通过此技能将图片转为结构化文字描述，再传给模型理解。适用于需要让模型「看到」截图、文档、UI 界面、照片等场景。"
---

# OCR 图片分析

## 核心定位

利用 macOS 本地 Vision 框架，在客户端完成图片分析——**不消耗 API token，不需联网**。将图片内容转为结构化文字描述后，作为上下文传给后端 LLM，从而绕过 DeepSeek 等纯文本模型对图片的不支持。

## 适用场景

- 后端使用 DeepSeek 或其他不支持多模态的模型
- 需要分析截图中的代码、报错信息、UI 界面
- 需要提取文档照片中的文字
- 需要获取图片的基本描述（场景分类、包含的对象）

## 使用方式

```
/swift scripts/ocr.swift <图片路径> [选项]
```

### 选项

| 选项 | 说明 |
|------|------|
| `--fast` | 快速模式，牺牲精度换取速度 |
| `--plain` | **推荐**：纯文本分段输出，格式适合传给 LLM 消费 |
| `--quiet` | 仅输出识别文字，无任何装饰 |
| `--clipboard` | 从剪贴板读取图片（不需要提供路径） |
| `--no-classify` | 跳过场景分类 |
| `--no-detect` | 跳过人脸/人体/条码检测 |
| `--lang <语言>` | 设置主要识别语言（默认 zh-Hans） |

### 示例

```bash
# 分析截图，输出 LLM 友好格式
swift scripts/ocr.swift screenshot.png --plain

# 从剪贴板读取
swift scripts/ocr.swift --clipboard --plain

# 英文文档
swift scripts/ocr.swift document.jpg --lang en --plain
```

## 工作流程

1. 用户提供图片路径（或使用 `--clipboard` 从剪贴板读取）
2. Swift 脚本调用 macOS Vision 框架进行本地分析：
   - **OCR 文字识别**：提取图片中所有文字
   - **场景分类**：识别图片类型（截图、文档、室内场景等）
   - **对象检测**：人脸、人体、条码/二维码
3. 输出结构化文字描述（`--plain` 模式下分为 `【场景分类】`、`【识别文字】`、`【检测对象】` 三段）
4. 将输出文字作为上下文传给后端 LLM

## 输出格式

`--plain` 模式（推荐）示例：
```
【图片信息】1920×1080

【场景分类】
  computer_screen（85%）
  user_interface（72%）

【识别文字】
  Error: connection refused
  at line 42 in server.ts
  ...

【检测对象】
  条码: QR: https://example.com
```

## 局限性

- **无法生成自然语言描述**：Vision 框架不是多模态 LLM，不能像 GPT-4o 那样说「这是一个蓝色按钮在页面右上角」。但场景分类可以提供粗略的图片类型标签
- **无法理解图表语义**：流程图、架构图中的箭头关系和层级结构无法提取，只能提取图中的文字
- **编译延迟**：Swift 脚本每次执行需要 JIT 编译，首次约 2-3 秒
- **不支持 GIF/动图**：仅支持静态图片（PNG、JPEG、TIFF、BMP 等）
