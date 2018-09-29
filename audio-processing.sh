#!/bin/bash

# Debug Mode & Exit on error
#set -xe

# Log the current date, time & user
if [  $USER = root  ]; then
  echo "$(date -u): Script started automatically by CRON."
else
  echo "$(date -u): Script started manually by $USER."
fi

# Presets & dependencies
INPUT_DIRECTORY=/usr/share/pCleaner-Input/
OUTPUT_DIRECTORY=/usr/share/pCleaner-Output/
FX=/etc/opt/pCleaner-settings
FILE_DB=/var/log/pCleaner-DB

# Check dependecies & install if needed
# then create an UPPERCASE variable for their installed path
# Example: SOX=/usr/local/bin/sox
for DEPENDENCY in \
brew \
sox \
faad \
; do
  if [ -z $(command -v "$DEPENDENCY") ]; then
    echo ""$DEPENDENCY" is not installed; we will install it now.";
    brew install "$DEPENDENCY";
  else
    export $(echo "$DEPENDENCY"  | tr '[:lower:]' '[:upper:]')=$(command -v "$DEPENDENCY")
  fi
done

# Check if preset files & directories exist; if not then make them
for PRESET in \
"$INPUT_DIRECTORY" \
"$OUTPUT_DIRECTORY" \
"$FILE_DB" \
; do
  if [ -e "$PRESET" ]; then
    true
  else
    echo "Presetting: $PRESET"
    # Check if $PRESET has a trailing forward-slash, if so assume it's a directory
    # otherwise assume it's a file
    if egrep "^.*\/$" <<< "$PRESET"; then
      mkdir -p "$PRESET"
    else
      touch "$PRESET"
    fi
  fi
done

if [ ! -f "$FX" ]; then
  echo "Generating the audio settings file: $FX"
  rsync -a $(dirname $(find $(pwd -P) -type f -name "$0" -print -quit))/pCleaner-settings $(dirname "$FX")/
fi

#if [ ! -f "$FILE_DB" ]; then
#  touch "$FILE_DB"
#fi

# Checks if any new files have been downloaded
# If so, sends them through the audio engine
# then loop until the list is finished

LIST_NEW_FILES () {
  find "$INPUT_DIRECTORY" \
    -type f \
    -a ! -name "*.tmp" \
    -a ! -name ".DS_Store"
}

MD5_CHECK () {
  if fgrep --silent $(md5 -q "$INFILE") "$FILE_DB"; then
    continue
  fi
}

LIST_NEW_FILES | while IFS=$'\n' read -r "INFILE"; do 
  MD5_CHECK

  # Check the format of the file, if it is M4A then it will need to be converted due ot a limitation with sox
  # If the file is M4A, it will be converted to WAV using faad and then restart the script
  INFILE_NAME=$(basename "$INFILE")
  INFILE_FORMAT="${INFILE##*.}"

  if [ "$INFILE_FORMAT" = m4a ]; then
    echo "Unsupported format: m4a. File will be converted."
    "$FAAD" -q "$INFILE"
    rsync --remove-source-files "$INFILE" "$INFILE"tmp
    exec "$0"
  fi

  OUTFILE_PATH=$(dirname "$INFILE")
  OUTFILE_NAME="${INFILE_NAME%.*}"

  # Automatic handling of output formats from a space delimited list
  OUTFILE_FORMAT_LIST='mp3'
  for OUTFILE_FORMAT in $OUTFILE_FORMAT_LIST; do
    OUTFILE="$OUTFILE_PATH/$OUTFILE_NAME.$OUTFILE_FORMAT"

    rsync "$INFILE" "$INFILE".tmp

    # This is where the magic happens
    source ~/pCleaner-settings
  
    "$SOX" -V \
    -t "$INFILE_FORMAT" "$INFILE".tmp \
    --comment "$G" \
    "$OUTFILE" \
    highpass "$HP" \
    lowpass "$LP" \
    mcompand "$AD $K:$T,$R $X1G $F" \
      "$X1" "$AD $K:$T,$R $X1G $F" \
      "$X2" "$AD $K:$T,$R $X2G $F" \
      "$X3" "$AD $K:$T,$R $X3G $F" \
    gain -n "$O"
  
  done

  # Prevent future runs against the same file
  echo "$(date -u): $(md5 -q $OUTFILE) - $OUTFILE" >> "$FILE_DB"

  if [ -e ./feed-processing.sh ]; then
    ./feed-processing.sh
  fi

done
