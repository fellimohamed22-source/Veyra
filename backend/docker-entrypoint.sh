#!/bin/sh
set -e

# FirebasePushProvider (see backend/src/main/java/com/veyra/provider/FirebasePushProvider.java)
# reads its service account credentials from a real file on disk
# (FileInputStream), not directly from an environment variable -- so the
# raw JSON content, however it arrives (a platform secret exposed as an
# env var here), has to be written out to an actual file before the JVM
# starts, and FIREBASE_CREDENTIALS_PATH pointed at it.
#
# Deliberately printf, not echo: a Firebase service-account JSON's
# private_key field contains literal backslash-n escape sequences
# (standard JSON encoding of embedded newlines within the PEM key,
# e.g. "-----BEGIN PRIVATE KEY-----\nMII...\n-----END..."). POSIX sh's
# echo builtin (dash on Debian-based images, which is what this
# eclipse-temurin base image uses) interprets backslash escapes by
# default, unlike bash -- so `echo "$FIREBASE_ADMIN_SDK_JSON"` would
# silently turn each literal \n into a real newline character INSIDE
# the JSON string, corrupting it (a raw, unescaped newline inside a
# JSON string literal is invalid JSON). printf '%s' never interprets
# escapes within its argument, only within a literal format string,
# which is fixed here to '%s\n' -- the one real trailing newline it
# adds is harmless, standard practice for text files.
if [ -n "$FIREBASE_ADMIN_SDK_JSON" ]; then
  printf '%s\n' "$FIREBASE_ADMIN_SDK_JSON" > /app/firebase-credentials.json
  export FIREBASE_CREDENTIALS_PATH=/app/firebase-credentials.json
  export FIREBASE_ENABLED=true
fi

exec java -jar /app/app.jar
