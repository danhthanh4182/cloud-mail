#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${ANDROID_JAR:?Set ANDROID_JAR to Android platform android.jar}"
: "${BUILD_TOOLS:?Set BUILD_TOOLS to Android SDK build-tools directory}"
mkdir -p build/classes build/dex build/keys
"$BUILD_TOOLS/aapt" package -f -M AndroidManifest.xml -S res -I "$ANDROID_JAR" -F build/base.apk
if command -v javac >/dev/null; then
  javac -source 8 -target 8 -classpath "$ANDROID_JAR" -d build/classes src/dev/danhthanh/cloudmail/MainActivity.java
else
  : "${ECJ_JAR:?Install a JDK or set ECJ_JAR}"
  java -jar "$ECJ_JAR" -8 -classpath "$ANDROID_JAR" -d build/classes src/dev/danhthanh/cloudmail/MainActivity.java
fi
mapfile -t classes < <(find build/classes -name '*.class')
java -cp "$BUILD_TOOLS/lib/d8.jar" com.android.tools.r8.D8 --min-api 26 --lib "$ANDROID_JAR" --output build/dex "${classes[@]}"
cp build/base.apk build/unsigned.apk
(cd build/dex && zip -q -j ../unsigned.apk classes.dex)
"$BUILD_TOOLS/zipalign" -f -p 4 build/unsigned.apk build/aligned.apk
if [[ ! -f build/keys/debug.keystore ]]; then
 keytool -genkeypair -keystore build/keys/debug.keystore -storepass android -keypass android -alias androiddebugkey -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000 -noprompt
fi
"$BUILD_TOOLS/apksigner" sign --ks build/keys/debug.keystore --ks-pass pass:android --key-pass pass:android --out build/cloud-mail-0.1.0-debug.apk build/aligned.apk
"$BUILD_TOOLS/apksigner" verify --verbose build/cloud-mail-0.1.0-debug.apk
"$BUILD_TOOLS/aapt" dump badging build/cloud-mail-0.1.0-debug.apk
