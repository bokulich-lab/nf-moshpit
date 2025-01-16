#!/bin/bash

# Function to display usage information
usage() {
  echo "Usage: $0 -i <input_file> -d <output_directory> -p <prefix> [-s]"
  echo "  -i <input_file>       : Path to the input file"
  echo "  -d <output_directory> : Directory to store output files"
  echo "  -p <prefix>           : Prefix for output filenames"
  echo "  -s                    : Skip existing file check (overwrites files)"
  exit 1
}

# Function to log messages
log() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') : $message"
}

# Initialize variables for options
input_file=""
output_dir=""
prefix=""
skip_check=false

# Parse named arguments
while getopts "i:d:p:s" opt; do
  case $opt in
    i) input_file="$OPTARG" ;;
    d) output_dir="$OPTARG" ;;
    p) prefix="$OPTARG" ;;
    s) skip_check=true ;;
    *) usage ;;
  esac
done

# Check if all required arguments are provided
if [ -z "$input_file" ] || [ -z "$output_dir" ] || [ -z "$prefix" ]; then
  usage
fi

# Log the start of the script
log "Starting script with input file '$input_file', output directory '$output_dir', prefix '$prefix', skipping check: '$skip_check'."

# Create the output directory if it doesn't exist
mkdir -p "$output_dir"
log "Ensured that the output directory '$output_dir' exists."

# Read and process entries under "order" from the input file
awk '/order:/{flag=1;next}/^origin:/{flag=0}flag' "$input_file" | \
while IFS= read -r line; do
  # Remove leading dashes and whitespace
  name_uuid=$(echo "$line" | sed -e 's/^[ \t-]*//')
  
  # Splitting `name_uuid` into `key` and `UUID`
  key=$(echo "$name_uuid" | awk -F: '{print $1}' | xargs)
  uuid=$(echo "$name_uuid" | awk -F: '{print $2}' | xargs)

  if [[ -n $key && -n $uuid ]]; then
    # Construct the filename for the output and empty files
    file_name="${prefix}${key}"

    # Check if the file already exists unless skip_check is true
    if { [ -e "$output_dir/$file_name" ] || [ -e "./$file_name" ]; } && [ "$skip_check" = false ]; then
      log "Error: File '$file_name' already exists in the output directory or the current directory."
      exit 1
    fi

    # Write the content to the file in the output directory
    {
      echo "data: $uuid"
      echo "origin: $file_name"
    } > "$output_dir/$file_name"
    log "Created or overwritten file '$output_dir/$file_name' with UUID and origin."

    # Create or overwrite an empty file in the current working directory
    touch "./$file_name"
    log "Created or overwritten empty file './$file_name' in the current directory."
  fi
done

log "Script completed successfully."
