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

# 簽章：預設 ad-hoc（不需金鑰圈互動，絕不會卡住）。
# 若想用固定自簽名身份（TCC 權限跨 rebuild 保留），需先解決金鑰 ACL：
#   security set-key-partition-list -S apple-tool:,apple: -s -k <你的登入密碼>
# 然後執行 SPEAKDRAFT_SIGN=1 ./build.sh
if [ "${SPEAKDRAFT_SIGN:-0}" = "1" ] && security find-identity -p codesigning 2>/dev/null | grep -q "SpeakDraft Dev Self-Signed"; then
    codesign --force -s "SpeakDraft Dev Self-Signed" "$APP"
else
    codesign --force -s - "$APP"
fi

echo "✔ 建置完成：$APP"
echo "  執行：open $APP"
