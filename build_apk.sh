if [ ! -f "android/key.properties" ]; then
  echo "WARNING: android/key.properties not found. APK will be signed with the debug key."
  echo "Create android/key.properties and the keystore (see SIGNING.md) to sign with a release key."
fi

flutter build apk --release 