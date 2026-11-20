#!/usr/bin/env bash
# يجهز ملفات أندرويد والويب قبل البناء (يشتغل داخل GitHub Actions)
set -euo pipefail

if [ ! -d android ] || [ ! -d web ]; then
  flutter create --platforms=android,web --org com.lamma --project-name lamma .
fi
rm -rf test

command -v convert >/dev/null || { sudo apt-get update -qq >/dev/null; sudo apt-get install -y -qq imagemagick >/dev/null; }
ICON=assets/brand/icon-1024.png

# ---------- أندرويد ----------
G=$( (ls android/app/build.gradle.kts android/app/build.gradle 2>/dev/null || true) | head -1)
sed -i -E 's/applicationId *=? *"[^"]*"/applicationId = "com.lamma.games"/' "$G"
grep -n "applicationId" "$G"

M=android/app/src/main/AndroidManifest.xml
sed -i 's/android:label="[^"]*"/android:label="لمّة"/' "$M"
grep -q 'screenOrientation' "$M" || sed -i 's/android:name=".MainActivity"/android:name=".MainActivity"\n            android:screenOrientation="portrait"/' "$M"
# الإنترنت (للأونلاين). Flutter يحطه بس بنسخة التطوير، فلازم نضيفه للنسخة الأصلية.
grep -q 'android.permission.INTERNET' "$M" || sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$M"
grep -n "INTERNET" "$M"

KT=$(find android/app/src/main -name MainActivity.kt | head -1)
PKG=$(grep -m1 '^package' "$KT")
cat > "$KT" <<KOT
$PKG

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // الشاشة تبقى شغالة أثناء اللعب
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
KOT

for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  n=${d%%:*}; px=${d##*:}
  mkdir -p android/app/src/main/res/mipmap-$n
  convert "$ICON" -resize ${px}x${px} android/app/src/main/res/mipmap-$n/ic_launcher.png
done

# ---------- الويب ----------
mkdir -p web/icons
convert "$ICON" -resize 192x192 web/icons/Icon-192.png
convert "$ICON" -resize 512x512 web/icons/Icon-512.png
cp web/icons/Icon-192.png web/icons/Icon-maskable-192.png
cp web/icons/Icon-512.png web/icons/Icon-maskable-512.png
convert "$ICON" -resize 64x64 web/favicon.png
convert "$ICON" -resize 180x180 web/icons/apple-touch-icon.png
mkdir -p web/brand
convert "$ICON" -resize 256x256 web/brand/logo.png

python3 tools/patch_web.py
