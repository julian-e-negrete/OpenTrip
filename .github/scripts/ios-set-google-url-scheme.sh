#!/usr/bin/env bash
# Writes the reversed iOS Google OAuth client ID into Info.plist's URL
# scheme (needed for Google Sign-In to return to the app). No-op when the
# GOOGLE_IOS_CLIENT_ID secret isn't set: the valid placeholder stays and
# only Google sign-in is unavailable — guest mode and email sign-in work.
set -euo pipefail
plist="apps/mobile/ios/Runner/Info.plist"
if [ -z "${GOOGLE_IOS_CLIENT_ID:-}" ]; then
  echo "GOOGLE_IOS_CLIENT_ID not set; leaving the placeholder URL scheme."
  exit 0
fi
# 1234-abc.apps.googleusercontent.com -> com.googleusercontent.apps.1234-abc
reversed=$(echo "$GOOGLE_IOS_CLIENT_ID" | awk -F. '{ for (i = NF; i > 0; i--) printf "%s%s", $i, (i > 1 ? "." : "") }')
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 $reversed" "$plist"
echo "Google Sign-In URL scheme set."
