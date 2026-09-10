import SwiftUI
import AppKit

/// 權限未完成時的引導區塊（顯示在 menu bar 面板上方）
struct OnboardingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("需要以下權限才能完整運作：")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !PermissionManager.microphoneGranted() {
                HStack {
                    Label("麥克風", systemImage: "mic.badge.xmark")
                        .font(.callout)
                    Spacer()
                    Button("授權") {
                        Task { _ = await PermissionManager.requestMicrophone() }
                    }
                }
            }

            if !PermissionManager.accessibilityGranted() {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Label("輔助功能（自動貼上）", systemImage: "accessibility.badge.xmark")
                            .font(.callout)
                        Spacer()
                        Button("開啟設定") { PermissionManager.openAccessibilitySettings() }
                    }
                    Text("到「系統設定 > 隱私與安全性 > 輔助功能」勾選 SpeakDraft")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
