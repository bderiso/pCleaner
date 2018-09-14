#!/bin/bash

# Exit on error
#set -e

# Debug Mode
set -x

# Check dependecies & install if needed
if [ ! -z $(command -v faad) ];
 then echo;
 else echo "faad not installed, we will install it now.";
 brew install faad2;
fi

if [ ! -z $(command -v sox) ];
 then echo;
 else echo "sox not installed, we will install it now.";
 brew install sox;
fi

# Find & variablize the installed path for dependecies
FAAD=$(command -v faad)
SOX=$(command -v sox)

# Setting locations
# Input directory
IN_DIR=~/pCleaner-Input
# Output directory
#OUT_DIR=~/pCleaner-Output
# Audio Settings
FX=~/pCleaner-settings
# Processing History Database
FILE_DB=~/pCleaner-DB

# Check that IN_DIR, OUT_DIR & FX exist; if not then make them
if [ ! -e "$IN_DIR" ]; then
  echo "Creating the input directory: $IN_DIR"
  mkdir -p "$IN_DIR"
fi

if [ ! -e "$FX" ]; then
  echo "Generating the audio settings file: $FX"
  cp ./pCleaner-settings.template "$FX"
fi

# Check if this script is running on MacOS, and if so then clean up the Input Directory 
if [ $(uname -s) = Darwin ]; then
  find "$IN_DIR" -type f -name "/.DS_Store" -delete
fi

# Check if any new files have been downloaded; if zero then exit
## List the directory and makes sure to append '/' to nested directories in the list
## then exclude those directories.
## If no files were listed, then exit with a message
if ls -p $IN_DIR | egrep -v /$ > /dev/null; then : nothing; 
else
  echo "$(date -u): No new files found in $IN_DIR"
  exit 0
fi

# Send files within the input directory through the audio processing 
# then loop until the list is finished
  find "$IN_DIR"/ -type f ! -name "*.tmp" | while IFS=$'\n' read -r INFILE; do

    # Check if the file has been processed before
    if fgrep $(md5 -q "$INFILE") "$FILE_DB"; then
      continue
    fi

    # Check the format of the file, if it is M4A then it will need to be converted due ot a limitation with sox
    # If the file is M4A, it will be converted to WAV using faad and then restart the script
    INFILE_NAME=$(basename "$INFILE")
    INFILE_FORMAT="${INFILE##*.}"

    if [ "$INFILE_FORMAT" = m4a ]; then
      echo "Unsupported format: m4a. File will be converted."
      "$FAAD" -q "$INFILE"
      rsync --remove-source-files "$INFILE" "$IN_DIR"/archive/
      exec "$0"
    fi

    OUTFILE_PATH=$(dirname "$INFILE")
      OUTFILE_NAME="${INFILE_NAME%.*}"
  
    # Automatic handling of output formats from a space delimited list
    OUTFILE_FORMAT_LIST='mp3'
    for OUTFILE_FORMAT in $OUTFILE_FORMAT_LIST; do
      OUTFILE="$OUTFILE_PATH/$OUTFILE_NAME.$OUTFILE_FORMAT"

      echo "$(date -u):"

    cp "$INFILE" "$INFILE".tmp

      # This is where the magic happens
      source ~/pCleaner-settings
    
      "$SOX" -V -t "$INFILE_FORMAT" "$INFILE".tmp --comment "$G" "$OUTFILE" highpass "$HP" lowpass "$LP" mcompand "$AD $K:$T,$R $X1G $F" "$X1" "$AD $K:$T,$R $X1G $F" "$X2" "$AD $K:$T,$R $X2G $F" "$X3" "$AD $K:$T,$R $X3G $F" gain -n "$O"
    
    done

    # Prevent future runs against the same file
    echo $(md5 -q "$OUTFILE") "$OUTFILE" | tee -a "$FILE_DB"

    if [ -e ./feed-processing.sh ]; then
      ./feed-processing.sh
    fi

done
