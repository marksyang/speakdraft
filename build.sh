#!/bin/bash
# 建置 SpeakDraft.app（release）並組出 app bundle
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/SpeakDraft.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/SpeakDraft" "$APP/Contents/MacOS/SpeakDraft"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>SpeakDraft</string>
	<key>CFBundleDisplayName</key>
	<string>SpeakDraft</string>
	<key>CFBundleIdentifier</key>
	<string>com.markyang.speakdraft</string>
	<key>CFBundleExecutable</key>
	<string>SpeakDraft</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>SpeakDraft 需要麥克風權限以錄製語音並轉成文字。</string>
</dict>
</plist>
PLIST

# 用固定的自簽名身份簽章（TCC 權限可跨 rebuild 保留）；沒裝則 fallback ad-hoc
SIGN_IDENTITY="SpeakDraft Dev Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    codesign --force -s "$SIGN_IDENTITY" "$APP"
else
    echo "⚠️  未找到簽章身份 $SIGN_IDENTITY，改用 ad-hoc（每次 rebuild 需重開權限）"
    codesign --force -s - "$APP"
fi

echo "✔ 建置完成：$APP"
echo "  執行：open $APP"
