#!/usr/bin/env bash
# Generates and configures the iOS project of one Flutter app, the iOS twin
# of the android-apk steps (native folders are not versioned).
# Usage: ios-prepare.sh <app dir> <project name> <bundle id> <display name> <client|driver>
# Env: GOOGLE_SERVICE_INFO_PLIST (optional, content of GoogleService-Info.plist)
set -euo pipefail
dir=$1; project=$2; bundle=$3; display=$4; kind=$5
cd "$dir"
flutter create . --platforms=ios --project-name "$project" --org com.veyra

plist=ios/Runner/Info.plist
pb() { /usr/libexec/PlistBuddy -c "$1" "$plist"; }
set_str() { pb "Delete :$1" 2>/dev/null || true; pb "Add :$1 string $2"; }

# Same bundle ids as the Firebase iOS apps (com.veyra.client / com.veyra.driver).
sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = com\.veyra\.[A-Za-z]*;/PRODUCT_BUNDLE_IDENTIFIER = $bundle;/" ios/Runner.xcodeproj/project.pbxproj
grep -q "PRODUCT_BUNDLE_IDENTIFIER = $bundle;" ios/Runner.xcodeproj/project.pbxproj

set_str CFBundleDisplayName "$display"
pb "Delete :CFBundleLocalizations" 2>/dev/null || true
pb "Add :CFBundleLocalizations array"; pb "Add :CFBundleLocalizations:0 string fr"; pb "Add :CFBundleLocalizations:1 string en"
set_str CFBundleDevelopmentRegion fr

# Permission texts (Android declares the same permissions in its manifest).
set_str NSPhotoLibraryUsageDescription "VEYRA utilise vos photos pour votre photo de profil et vos documents."
set_str NSCameraUsageDescription "VEYRA utilise l'appareil photo pour photographier vos documents."
pb "Delete :UIBackgroundModes" 2>/dev/null || true
pb "Add :UIBackgroundModes array"; pb "Add :UIBackgroundModes:0 string remote-notification"
if [ "$kind" = driver ]; then
  set_str NSLocationWhenInUseUsageDescription "VEYRA Chauffeur utilise votre position pour calculer l'approche et la partager avec le client pendant la course."
  set_str NSLocationAlwaysAndWhenInUseUsageDescription "VEYRA Chauffeur partage votre position avec le client pendant la course, même application en arrière-plan."
  pb "Add :UIBackgroundModes:1 string location"
else
  set_str NSLocationWhenInUseUsageDescription "VEYRA utilise votre position pour remplir votre adresse de départ."
fi

# Push notifications and Sign in with Apple (Android: FCM + Firebase providers).
cat > ios/Runner/Runner.entitlements <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyLists-1.0.dtd">
<plist version="1.0">
<dict>
  <key>aps-environment</key><string>development</string>
  <key>com.apple.developer.applesignin</key><array><string>Default</string></array>
</dict>
</plist>
EOF
sed -i '' "s#PRODUCT_BUNDLE_IDENTIFIER = $bundle;#PRODUCT_BUNDLE_IDENTIFIER = $bundle; CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;#" ios/Runner.xcodeproj/project.pbxproj
grep -q 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;' ios/Runner.xcodeproj/project.pbxproj

# Firebase/Stripe need iOS 15 at least.
if grep -q "platform :ios" ios/Podfile; then
  sed -i '' "s/^# *platform :ios.*/platform :ios, '15.0'/; s/^platform :ios.*/platform :ios, '15.0'/" ios/Podfile
else
  printf "platform :ios, '15.0'\n%s" "$(cat ios/Podfile)" > ios/Podfile
fi
sed -i '' "s/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g" ios/Runner.xcodeproj/project.pbxproj

# Approved app icon: each slot gets the branding PNG of the same pixel size.
set=ios/Runner/Assets.xcassets/AppIcon.appiconset
for f in "$set"/*.png; do
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
  [ -f "branding/ios/AppIcon-$w.png" ] && cp "branding/ios/AppIcon-$w.png" "$f"
done
cmp branding/ios/AppIcon-1024.png "$set/Icon-App-1024x1024@1x.png"

# Firebase config (secret); its REVERSED_CLIENT_ID is the URL scheme Google
# sign-in and phone-auth reCAPTCHA return to.
if [ -n "${GOOGLE_SERVICE_INFO_PLIST:-}" ]; then
  printf '%s\n' "$GOOGLE_SERVICE_INFO_PLIST" > ios/Runner/GoogleService-Info.plist
  grep -q "$bundle" ios/Runner/GoogleService-Info.plist
  reversed=$(/usr/libexec/PlistBuddy -c "Print :REVERSED_CLIENT_ID" ios/Runner/GoogleService-Info.plist 2>/dev/null || true)
  if [ -n "$reversed" ]; then
    pb "Add :CFBundleURLTypes array"; pb "Add :CFBundleURLTypes:0 dict"
    pb "Add :CFBundleURLTypes:0:CFBundleURLSchemes array"; pb "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $reversed"
  fi
  # Xcode only bundles files referenced by the project.
  ruby -e '
    require "xcodeproj"
    p = Xcodeproj::Project.open("ios/Runner.xcodeproj")
    t = p.targets.find { |x| x.name == "Runner" }
    g = p.main_group["Runner"]
    ref = g.files.find { |f| f.path == "GoogleService-Info.plist" } || g.new_file("GoogleService-Info.plist")
    t.resources_build_phase.add_file_reference(ref, true)
    p.save'
else
  echo "::warning title=iOS $project::GoogleService-Info.plist absent (secret) : Firebase (connexion Google/Apple/téléphone, notifications) ne fonctionnera pas sur iOS."
fi

# Native Google Maps SDK (same engine as Uber/Bolt): key given to the SDK at
# launch, from the GitHub secret, never stored in the repository.
if [ -n "${GOOGLE_MAPS_MOBILE_KEY:-}" ]; then
  delegate=ios/Runner/AppDelegate.swift
  perl -0pi -e 's/import Flutter\n/import Flutter\nimport GoogleMaps\n/' "$delegate"
  MAPS_KEY="$GOOGLE_MAPS_MOBILE_KEY" perl -0pi -e 's/(didFinishLaunchingWithOptions[^{]*\{\n)/$1    GMSServices.provideAPIKey("$ENV{MAPS_KEY}")\n/' "$delegate"
  grep -q 'GMSServices.provideAPIKey' "$delegate"
fi
