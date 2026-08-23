import Cocoa

extension UsageDetailsView {
    func drawAPIIntegrationGuide(in page: NSRect) {
        apiIntegrationPageRects.removeAll()
        let tabs = APIIntegrationGuidePage.allCases
        let tabGap: CGFloat = 8
        let tabWidth = (page.width - tabGap * CGFloat(tabs.count - 1)) / CGFloat(tabs.count)
        let tabsRect = NSRect(x: page.minX, y: page.minY + 76, width: page.width, height: 34)
        for (index, guidePage) in tabs.enumerated() {
            let rect = NSRect(
                x: tabsRect.minX + CGFloat(index) * (tabWidth + tabGap),
                y: tabsRect.minY,
                width: tabWidth,
                height: tabsRect.height
            )
            apiIntegrationPageRects[guidePage] = rect
            drawSelectablePill(guidePage.title, rect: rect, selected: guidePage == selectedAPIIntegrationPage)
        }

        switch selectedAPIIntegrationPage {
        case .overview:
            drawAPIIntegrationOverview(in: page, top: tabsRect.maxY + 18)
        case .codex:
            drawCodexAccountIntegration(in: page, top: tabsRect.maxY + 18)
        case .external:
            drawExternalAPIImport(in: page, top: tabsRect.maxY + 18)
        }
    }

    private func drawAPIIntegrationOverview(in page: NSRect, top: CGFloat) {
        let copy = apiGuideCopy
        drawText(copy.overviewTitle, rect: NSRect(x: page.minX, y: top, width: page.width, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawMultilineText(copy.overviewHint, rect: NSRect(x: page.minX, y: top + 24, width: page.width, height: 34), font: .systemFont(ofSize: 11.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.56))

        let cardGap: CGFloat = 12
        let cardHeight: CGFloat = 138
        let cardWidth = (page.width - cardGap) / 2
        let codexRect = NSRect(x: page.minX, y: top + 70, width: cardWidth, height: cardHeight)
        let externalRect = NSRect(x: codexRect.maxX + cardGap, y: codexRect.minY, width: cardWidth, height: cardHeight)
        drawIntegrationCard(
            rect: codexRect,
            icon: "checkmark.shield",
            accent: accentTeal,
            title: copy.codexCardTitle,
            body: copy.codexCardBody,
            footer: copy.codexCardFooter
        )
        drawIntegrationCard(
            rect: externalRect,
            icon: "arrow.down.doc",
            accent: accentBlue,
            title: copy.externalCardTitle,
            body: copy.externalCardBody,
            footer: copy.externalCardFooter
        )

        let flowRect = NSRect(x: page.minX, y: codexRect.maxY + 16, width: page.width, height: 134)
        drawPanel(flowRect)
        drawText(copy.flowTitle, rect: NSRect(x: flowRect.minX + 16, y: flowRect.minY + 14, width: flowRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: .white.withAlphaComponent(0.86))
        let steps = [copy.flowOne, copy.flowTwo, copy.flowThree]
        let columnGap: CGFloat = 10
        let columnWidth = (flowRect.width - 32 - columnGap * 2) / 3
        for (index, step) in steps.enumerated() {
            let x = flowRect.minX + 16 + CGFloat(index) * (columnWidth + columnGap)
            let badge = NSRect(x: x, y: flowRect.minY + 48, width: 24, height: 24)
            accentBlue.withAlphaComponent(0.24).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 12, yRadius: 12).fill()
            drawCentered("\(index + 1)", rect: badge, font: .systemFont(ofSize: 11, weight: .bold), color: .white)
            drawMultilineText(step, rect: NSRect(x: x, y: flowRect.minY + 80, width: columnWidth, height: 38), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.60))
        }

        drawPrivacyNote(copy.privacyNote, in: NSRect(x: page.minX, y: flowRect.maxY + 16, width: page.width, height: 42))
    }

    private func drawCodexAccountIntegration(in page: NSRect, top: CGFloat) {
        let copy = apiGuideCopy
        drawText(copy.codexTitle, rect: NSRect(x: page.minX, y: top, width: page.width, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawMultilineText(copy.codexHint, rect: NSRect(x: page.minX, y: top + 24, width: page.width, height: 34), font: .systemFont(ofSize: 11.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.56))

        let steps = [
            ("1", copy.codexStepOneTitle, copy.codexStepOneBody),
            ("2", copy.codexStepTwoTitle, copy.codexStepTwoBody),
            ("3", copy.codexStepThreeTitle, copy.codexStepThreeBody)
        ]
        let stepHeight: CGFloat = 72
        for (index, step) in steps.enumerated() {
            let rect = NSRect(x: page.minX, y: top + 70 + CGFloat(index) * (stepHeight + 10), width: page.width, height: stepHeight)
            drawPanel(rect)
            let badge = NSRect(x: rect.minX + 16, y: rect.minY + 20, width: 30, height: 30)
            accentTeal.withAlphaComponent(0.20).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 15, yRadius: 15).fill()
            drawCentered(step.0, rect: badge, font: .systemFont(ofSize: 12, weight: .bold), color: accentTeal)
            drawText(step.1, rect: NSRect(x: badge.maxX + 14, y: rect.minY + 14, width: rect.width - 76, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: .white)
            drawMultilineText(step.2, rect: NSRect(x: badge.maxX + 14, y: rect.minY + 36, width: rect.width - 76, height: 24), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.56))
        }

        let verificationRect = NSRect(x: page.minX, y: top + 316, width: page.width, height: 102)
        drawPanel(verificationRect)
        drawSymbolIcon("waveform.path.ecg", in: NSRect(x: verificationRect.minX + 16, y: verificationRect.minY + 18, width: 20, height: 20), color: accentAmber, pointSize: 14)
        drawText(copy.codexVerifyTitle, rect: NSRect(x: verificationRect.minX + 48, y: verificationRect.minY + 14, width: verificationRect.width - 64, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: .white)
        drawMultilineText(copy.codexVerifyBody, rect: NSRect(x: verificationRect.minX + 48, y: verificationRect.minY + 36, width: verificationRect.width - 64, height: 44), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
    }

    private func drawExternalAPIImport(in page: NSRect, top: CGFloat) {
        let copy = apiGuideCopy
        drawText(copy.externalTitle, rect: NSRect(x: page.minX, y: top, width: page.width, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawMultilineText(copy.externalHint, rect: NSRect(x: page.minX, y: top + 24, width: page.width, height: 34), font: .systemFont(ofSize: 11.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.56))

        let pathRect = NSRect(x: page.minX, y: top + 70, width: page.width, height: 52)
        drawPanel(pathRect)
        drawText(copy.externalPathLabel, rect: NSRect(x: pathRect.minX + 14, y: pathRect.minY + 10, width: 120, height: 16), font: .systemFont(ofSize: 10.5, weight: .bold), color: NSColor.white.withAlphaComponent(0.54))
        drawTruncatedText(AppSettings.externalAPICostURL.path, rect: NSRect(x: pathRect.minX + 14, y: pathRect.minY + 28, width: pathRect.width - 28, height: 15), font: .monospacedSystemFont(ofSize: 10.5, weight: .medium), color: accentTeal.withAlphaComponent(0.92))

        let codeRect = NSRect(x: page.minX, y: pathRect.maxY + 12, width: page.width, height: 218)
        inputSurfaceColor.setFill()
        NSBezierPath(roundedRect: codeRect, xRadius: 9, yRadius: 9).fill()
        borderColor.setStroke()
        NSBezierPath(roundedRect: codeRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9).stroke()
        drawText("api-usage.json", rect: NSRect(x: codeRect.minX + 14, y: codeRect.minY + 12, width: codeRect.width - 28, height: 15), font: .monospacedSystemFont(ofSize: 10.5, weight: .bold), color: NSColor.white.withAlphaComponent(0.50))
        drawMultilineText(apiUsageJSONExample, rect: NSRect(x: codeRect.minX + 14, y: codeRect.minY + 36, width: codeRect.width - 28, height: codeRect.height - 46), font: .monospacedSystemFont(ofSize: 10, weight: .regular), color: NSColor.white.withAlphaComponent(0.82))

        drawPrivacyNote(copy.externalFootnote, in: NSRect(x: page.minX, y: codeRect.maxY + 14, width: page.width, height: 48))
    }

    private func drawIntegrationCard(rect: NSRect, icon: String, accent: NSColor, title: String, body: String, footer: String) {
        drawPanel(rect)
        drawSymbolIcon(icon, in: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: 20, height: 20), color: accent, pointSize: 14)
        drawText(title, rect: NSRect(x: rect.minX + 46, y: rect.minY + 15, width: rect.width - 62, height: 20), font: .systemFont(ofSize: 12, weight: .bold), color: .white)
        drawMultilineText(body, rect: NSRect(x: rect.minX + 16, y: rect.minY + 48, width: rect.width - 32, height: 48), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
        drawText(footer, rect: NSRect(x: rect.minX + 16, y: rect.maxY - 26, width: rect.width - 32, height: 15), font: .systemFont(ofSize: 10, weight: .bold), color: accent.withAlphaComponent(0.90))
    }

    private func drawPrivacyNote(_ text: String, in rect: NSRect) {
        accentAmber.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        drawSymbolIcon("lock.fill", in: NSRect(x: rect.minX + 12, y: rect.minY + 13, width: 16, height: 16), color: accentAmber.withAlphaComponent(0.88), pointSize: 11)
        drawMultilineText(text, rect: NSRect(x: rect.minX + 36, y: rect.minY + 9, width: rect.width - 48, height: rect.height - 14), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.66))
    }

    private var apiUsageJSONExample: String {
        """
        {
          \"updated_at\": \"2026-08-24T10:30:00Z\",
          \"usage\": { \"input\": 1200, \"cached_input\": 100,
                     \"output\": 800, \"total\": 2000 },
          \"by_day\": [{ \"day\": \"2026-08-24\", \"requests\": 1,
                       \"input\": 1200, \"output\": 800, \"total\": 2000 }],
          \"models\": [{ \"name\": \"gpt-5.6\", \"requests\": 1,
                        \"input\": 1200, \"output\": 800, \"total\": 2000 }]
        }
        """
    }

    private var apiGuideCopy: APIGuideCopy {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return APIGuideCopy(
                overviewTitle: "先选数据路径，再看结果",
                overviewHint: "AI Token Meter 不代理你的请求。它只读取当前 Mac 上已有的登录态或汇总文件，再把可用的 Token 用量展示到 API 分区。",
                codexCardTitle: "Codex 官方数据",
                codexCardBody: "复用已有 Codex 登录态，读取实时额度、Profile 总量和重置机会。",
                codexCardFooter: "无需粘贴 API Key",
                externalCardTitle: "外部 API 用量",
                externalCardBody: "让你的脚本把各厂商用量汇总成一个本地 JSON 文件，应用自动读取。",
                externalCardFooter: "本地文件，按需更新",
                flowTitle: "推荐接入顺序",
                flowOne: "确认已有 Codex 登录或外部用量采集脚本。",
                flowTwo: "在这里选择对应路径，并打开 Profile 总量开关。",
                flowThree: "刷新后在“API”来源下核对模型、Token 和成本。",
                privacyNote: "隐私边界：不会上传 API Key、原始请求、提示词或会话日志；外部 JSON 只在本机以只读方式解析。",
                codexTitle: "接入 Codex 官方额度与总量",
                codexHint: "应用使用当前 Codex Desktop/CLI 的本地登录态发起只读 HTTPS 请求。默认 `~/.codex` 已可用；多账号或自定义 CODEX_HOME 才需要改路径。",
                codexStepOneTitle: "保留已有登录态",
                codexStepOneBody: "先在 Codex 完成登录。不要把 API Key 或 access token 粘贴到 AI Token Meter。",
                codexStepTwoTitle: "选择正确的 CODEX_HOME",
                codexStepTwoBody: "到“数据来源”页选择包含 auth.json 的根目录；不选则使用默认 ~/.codex。",
                codexStepThreeTitle: "打开 Profile API 总量并刷新",
                codexStepThreeBody: "它补充官方累计量与每日桶。网络或登录态失效时会保留本地日志的兜底，不会写入认证文件。",
                codexVerifyTitle: "验证方式",
                codexVerifyBody: "刷新后在“诊断”页检查 auth.json、Live quota 和 Profile API totals。显示不可用通常表示登录态、网络或服务端暂不可读，并不代表本地扫描失败。",
                externalTitle: "导入 Codex 之外的 API 调用",
                externalHint: "在你的采集脚本结束时，原子写入一个汇总 JSON。不要写入 prompt、响应内容或密钥；应用只需要 Token、日期、模型和可选请求数。",
                externalPathLabel: "当前读取路径",
                externalFootnote: "支持 input / cached_input / output / total，以及 input_tokens、prompt_tokens、completion_tokens 等同义字段。若模型无公开价格，仍展示 Token，但成本会明确保持未定价。"
            )
        case .japanese:
            return APIGuideCopy(
                overviewTitle: "データ経路を選んでから結果を確認",
                overviewHint: "AI Token Meter はリクエストを中継しません。この Mac 上の既存ログイン情報または集計ファイルを読み取り、API 使用量として表示します。",
                codexCardTitle: "Codex 公式データ", codexCardBody: "既存の Codex ログインで、ライブ制限、Profile 合計、リセット機会を読み取ります。", codexCardFooter: "API Key は不要",
                externalCardTitle: "外部 API 使用量", externalCardBody: "集計スクリプトからローカル JSON を書き出すと、アプリが読み取ります。", externalCardFooter: "ローカルファイルのみ",
                flowTitle: "推奨する順序", flowOne: "Codex ログインまたは使用量収集スクリプトを確認。", flowTwo: "ここで経路を選択し、Profile 合計を有効化。", flowThree: "更新後に API ソースでモデル、Token、コストを確認。",
                privacyNote: "プライバシー: API Key、プロンプト、会話ログはアップロードしません。外部 JSON はローカルで読み取り専用です。",
                codexTitle: "Codex 公式制限と合計を接続", codexHint: "現在の Codex のローカルログイン情報で、読み取り専用 HTTPS リクエストを行います。標準の ~/.codex はそのまま使えます。",
                codexStepOneTitle: "既存のログインを利用", codexStepOneBody: "まず Codex にログインしてください。API Key や access token を貼り付けないでください。",
                codexStepTwoTitle: "正しい CODEX_HOME を選択", codexStepTwoBody: "データソースで auth.json を含むルートを選びます。未選択なら ~/.codex を使用します。",
                codexStepThreeTitle: "Profile API 合計を有効化して更新", codexStepThreeBody: "公式合計と日別バケットを補います。失敗時はローカルログの表示を維持します。",
                codexVerifyTitle: "確認方法", codexVerifyBody: "更新後に診断ページで auth.json、Live quota、Profile API totals を確認します。利用不可はログイン、ネットワーク、またはサーバーの状態を示すことがあります。",
                externalTitle: "Codex 外の API 呼び出しを取り込む", externalHint: "収集スクリプトの最後に集計 JSON を原子的に書き出します。prompt、応答本文、キーは入れず、Token、日付、モデル、任意のリクエスト数のみ記録します。",
                externalPathLabel: "現在の読み取り先", externalFootnote: "input / cached_input / output / total と同義フィールドに対応します。公開価格がないモデルは Token のみ表示し、コストは未価格のままです。"
            )
        default:
            return APIGuideCopy(
                overviewTitle: "Choose a data path, then verify the result",
                overviewHint: "AI Token Meter never proxies requests. It reads existing sign-in state or a local aggregate file on this Mac, then shows usable tokens in the API partition.",
                codexCardTitle: "Codex official data", codexCardBody: "Reuse the existing Codex sign-in for live quota, Profile totals, and reset credits.", codexCardFooter: "No API key to paste",
                externalCardTitle: "External API usage", externalCardBody: "Have your collection script write one local JSON aggregate that the app can read.", externalCardFooter: "Local file, updated on demand",
                flowTitle: "Recommended sequence", flowOne: "Confirm an existing Codex sign-in or external usage collector.", flowTwo: "Select the matching path here and enable Profile totals.", flowThree: "Refresh, then check models, tokens, and cost under the API source.",
                privacyNote: "Privacy boundary: API keys, raw requests, prompts, and session logs are never uploaded. External JSON is parsed locally and read-only.",
                codexTitle: "Connect Codex quota and account totals", codexHint: "The app uses the current Codex Desktop/CLI sign-in to make read-only HTTPS requests. The default ~/.codex works without configuration; only custom CODEX_HOME roots need selection.",
                codexStepOneTitle: "Keep the existing sign-in", codexStepOneBody: "Sign in through Codex first. Do not paste an API key or access token into AI Token Meter.",
                codexStepTwoTitle: "Choose the right CODEX_HOME", codexStepTwoBody: "In Data Sources, select the root containing auth.json. Otherwise the default ~/.codex is used.",
                codexStepThreeTitle: "Enable Profile API totals and refresh", codexStepThreeBody: "This adds official lifetime and daily buckets. If sign-in or network access fails, local-log fallback remains and no auth file is changed.",
                codexVerifyTitle: "How to verify", codexVerifyBody: "After refreshing, use Diagnostics to check auth.json, Live quota, and Profile API totals. Unavailable can indicate sign-in, network, or server state; it does not prove local scans failed.",
                externalTitle: "Import API calls made outside Codex", externalHint: "At the end of your collector, atomically write one aggregate JSON file. Exclude prompts, response bodies, and keys; the app only needs tokens, dates, models, and optional request counts.",
                externalPathLabel: "Current read path", externalFootnote: "input / cached_input / output / total and aliases such as input_tokens, prompt_tokens, and completion_tokens are supported. Models without public prices still show tokens but stay explicitly unpriced."
            )
        }
    }
}

private struct APIGuideCopy {
    let overviewTitle: String
    let overviewHint: String
    let codexCardTitle: String
    let codexCardBody: String
    let codexCardFooter: String
    let externalCardTitle: String
    let externalCardBody: String
    let externalCardFooter: String
    let flowTitle: String
    let flowOne: String
    let flowTwo: String
    let flowThree: String
    let privacyNote: String
    let codexTitle: String
    let codexHint: String
    let codexStepOneTitle: String
    let codexStepOneBody: String
    let codexStepTwoTitle: String
    let codexStepTwoBody: String
    let codexStepThreeTitle: String
    let codexStepThreeBody: String
    let codexVerifyTitle: String
    let codexVerifyBody: String
    let externalTitle: String
    let externalHint: String
    let externalPathLabel: String
    let externalFootnote: String
}
