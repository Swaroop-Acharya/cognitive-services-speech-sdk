#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Get some helpers
. "$SCRIPT_DIR/../functions.sh"

set -x -e -o pipefail
USAGE="Usage: $0 version-name version-code drop-dir"
VERSION_NAME="${1?$USAGE}"
# TODO is version code relevant for Android libraries?
VERSION_CODE="${2?$USAGE}"
DROP_DIR="${3?$USAGE}"

# Make absolute
DROP_DIR="$(readlink -f "$DROP_DIR")"

AAR_TEMPLATE_DIR="$SCRIPT_DIR/aartemplate"
[[ $AAR_TEMPLATE_DIR ]]

AAR_DIR="$SCRIPT_DIR/aar"

# Used for timestamping all published files
NOW=$(date -Iseconds)

for micpermission in false true; do
  # Note: the only difference for the nomic package ($micpermission false) is
  #       the removal of the RECORD_AUDIO permission from the manifest.
  for flavor in Debug Release; do

    # Debug only with microphone permissions
    $micpermission || [[ $flavor == Release ]] || continue

    # Note: we don't intend to publish the debug version for now; subject to change.

    FLAVORED_VERSION_NAME="$VERSION_NAME"
    AAR_DIR="$SCRIPT_DIR/aar"

    $micpermission || AAR_DIR+=-nomic

    [[ $flavor == Debug ]] && {
      FLAVORED_VERSION_NAME+=-debug
      AAR_DIR+=-debug
    }

    # Clean output
    [[ -d $AAR_DIR ]] && rm -rf "$AAR_DIR"

    # Copy template directory
    cp --verbose --recursive "$AAR_TEMPLATE_DIR" "$AAR_DIR"

    # Patch version code and name
    perl -l -p -i.bak -e '
      BEGIN {
        $versionName = shift;
        $versionCode = shift;
        $micpermission = shift ne "false";
      }
      $micpermission or
        not m/uses-permission\s+android:name="android.permission.RECORD_AUDIO"/ or
        $_ = "";
      s/(?<=\bandroid:versionCode=")[^"]*/$versionCode/;
      s/(?<=\bandroid:versionName=")[^"]*/$versionName/;
    ' "$FLAVORED_VERSION_NAME" "$VERSION_CODE" "$micpermission" "$AAR_DIR/AndroidManifest.xml"
    diff -u "$AAR_DIR/AndroidManifest.xml"{.bak,} || true
    rm "$AAR_DIR/AndroidManifest.xml.bak"

    # Copy the ARM32 jar
    cp --verbose --preserve "$DROP_DIR"/Android-arm32/$flavor/public/lib/com.microsoft.cognitiveservices.speech.jar "$AAR_DIR/classes.jar"

    # Copy native libraries
    mkdir -p "$AAR_DIR"/jni{,/armeabi-v7a,/arm64-v8a,/x86,/x86_64}

    # Note: KWS currently not shipping in the AAR.

    cp --verbose --preserve \
      "$DROP_DIR"/Android-arm32/$flavor/public/lib/libMicrosoft.CognitiveServices.Speech.{core,java.bindings,extension.codec,extension.kws}.so \
      "$AAR_DIR"/jni/armeabi-v7a

    cp --verbose --preserve \
      "$DROP_DIR"/Android-arm64/$flavor/public/lib/libMicrosoft.CognitiveServices.Speech.{core,java.bindings,extension.codec,extension.kws}.so \
      "$AAR_DIR"/jni/arm64-v8a

    cp --verbose --preserve \
      "$DROP_DIR"/Android-x86/$flavor/public/lib/libMicrosoft.CognitiveServices.Speech.{core,java.bindings,extension.codec,extension.kws}.so \
      "$AAR_DIR"/jni/x86

    cp --verbose --preserve \
      "$DROP_DIR"/Android-x64/$flavor/public/lib/libMicrosoft.CognitiveServices.Speech.{core,java.bindings,extension.codec,extension.kws}.so \
      "$AAR_DIR"/jni/x86_64

    cp --verbose "$SCRIPT_DIR/../../"{REDIST.txt,license.md,ThirdPartyNotices.md} "$AAR_DIR"

    # Timestamp
    find "$AAR_DIR" -print0 | xargs -0 touch --date=$NOW
  done
done
