if [ ! -f "android/key.properties" ]; then
  echo "WARNING: android/key.properties not found. AppBundle will be signed with the debug key."
  echo "Create android/key.properties and the keystore (see SIGNING.md) to sign with a release key."
fi

flutter build appbundle --release --dart-define=BUNDLE_BUILT=true