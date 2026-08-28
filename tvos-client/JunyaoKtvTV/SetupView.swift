import SwiftUI

struct SetupView: View {
    @Binding var serverAddress: String
    let onSave: () -> Void
    @State private var inputAddress: String = ""
    @State private var testing = false
    @State private var testResult: String? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Same background as login page
            WebColors.bg.ignoresSafeArea()
            RadialGradient(colors: [WebColors.ac.opacity(0.16), .clear],
                           center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 500)
                .ignoresSafeArea()
            RadialGradient(colors: [WebColors.ac2.opacity(0.12), .clear],
                           center: UnitPoint(x: 0.9, y: 1.0), startRadius: 0, endRadius: 450)
                .ignoresSafeArea()

            VStack {
                Spacer()
                // Setup card (same style as login .box)
                VStack(spacing: 0) {
                    Text("墨墨爱K歌")
                        .font(.system(size: 48, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(LinearGradient(colors: [WebColors.ac2, WebColors.ac, WebColors.pink],
                                                        startPoint: .leading, endPoint: .trailing))
                        .padding(.bottom, 12)

                    Text("请输入 KTV 服务器地址")
                        .font(.system(size: 24, weight: .bold))
                        .tracking(1)
                        .foregroundColor(Color(hex: 0xb8b8d8))
                        .padding(.bottom, 40)

                    // Server address input
                    TextField("例如: 192.168.3.16:8083", text: $inputAddress)
                        .focused($isFocused)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(Color(hex: 0xf4f4ff))
                        .padding(.horizontal, 26).padding(.vertical, 24)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(isFocused ? WebColors.ac : Color.white.opacity(0.1), lineWidth: 2))
                        .padding(.bottom, 24)
                        .onSubmit { save() }

                    // Test result
                    if let result = testResult {
                        Text(result)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(result.contains("成功") ? .green : WebColors.pink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 20)
                    }

                    // Connect button (same style as login button)
                    Button(action: save) {
                        Text(testing ? "连接中..." : "连接")
                            .font(.system(size: 30, weight: .heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(LinearGradient(colors: [WebColors.ac, WebColors.ac2],
                                                       startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 1, y: 1)))
                            .foregroundColor(WebColors.bg)
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                    .disabled(testing || inputAddress.isEmpty)
                    .opacity(testing || inputAddress.isEmpty ? 0.5 : 1.0)

                    // Tip
                    VStack(spacing: 8) {
                        Text("服务器运行在飞牛 NAS Docker 中")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(hex: 0x9a9ac0))
                        Text("默认端口 8083，格式: IP:端口")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(hex: 0x9a9ac0))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .overlay(Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1), alignment: .top)
                    .padding(.top, 26)
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 64)
                .frame(width: 680)
                .background(Color(hex: 0x10102a).opacity(0.78))
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
                Spacer()
            }
        }
        .onAppear {
            inputAddress = serverAddress
            isFocused = true
        }
    }

    private func save() {
        let addr = inputAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addr.isEmpty else { return }
        testing = true
        testResult = nil

        // Test connection
        let urlStr = addr.hasPrefix("http") ? addr : "http://\(addr)"
        guard let url = URL(string: "\(urlStr)/api/stats") else {
            testResult = "地址格式错误"
            testing = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                testing = false
                if let _ = data, error == nil {
                    testResult = "连接成功！"
                    serverAddress = addr
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onSave()
                    }
                } else {
                    testResult = "连接失败，请检查地址"
                }
            }
        }.resume()
    }
}
