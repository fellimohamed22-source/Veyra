#!/bin/sh
set -e

# FirebasePushProvider (see backend/src/main/java/com/veyra/provider/FirebasePushProvider.java)
# reads its service account credentials from a real file on disk
# (FileInputStream), not directly from an environment variable -- so the
# raw JSON content, however it arrives (a platform secret exposed as an
# env var here), has to be written out to an actual file before the JVM
# starts, and FIREBASE_CREDENTIALS_PATH pointed at it.
if [ -n "$FIREBASE_ADMIN_SDK_JSON" ]; then
  echo "$FIREBASE_ADMIN_SDK_JSON" > /app/firebase-credentials.json
  export FIREBASE_CREDENTIALS_PATH=/app/firebase-credentials.json
  export FIREBASE_ENABLED=true
fi

exec java -jar /app/app.jar
