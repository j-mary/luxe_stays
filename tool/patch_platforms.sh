#!/usr/bin/env bash
# Applied once after `flutter create --platforms=android,ios .`
#
# Two things the generated host projects do not do by default, and that a
# WebView-based app talking to a local mock server needs:
#   1. Android: allow cleartext traffic to localhost (debug only).
#   2. iOS: an ATS exception for localhost, and the custom URL scheme.
#
# Neither weakens production: the Android rule is scoped to the debug manifest
# and to localhost, and the iOS exception names one domain.
set -euo pipefail

echo "Patching Android debug manifest…"
mkdir -p android/app/src/debug
cat > android/app/src/debug/AndroidManifest.xml <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        android:usesCleartextTraffic="true"
        tools:replace="android:usesCleartextTraffic"/>
</manifest>
XML

echo "Patching iOS Info.plist…"
PLIST=ios/Runner/Info.plist
if [ -f "$PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains dict" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:localhost dict" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:localhost:NSExceptionAllowsInsecureHTTPLoads bool true" "$PLIST" 2>/dev/null || true

  # Custom scheme, so the PSP and booking engine can redirect back to the app.
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string luxestays" "$PLIST" 2>/dev/null || true
fi

echo "Done. Android minSdk should be 24+ for webview_flutter and 23+ for"
echo "flutter_secure_storage - check android/app/build.gradle if a build fails."
