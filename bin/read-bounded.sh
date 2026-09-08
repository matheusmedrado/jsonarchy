#!/bin/sh
# Bounded file reader for JSONarchy.
#
#   sh read-bounded.sh <path> <max-bytes>
#
# Writes at most <max-bytes> of a regular file to stdout and nothing else.
# Everything that could block or balloon a read is rejected before the file
# is opened: devices, FIFOs, sockets, directories, missing paths, dangling
# symlinks, and files larger than the limit. Symlinks to regular files are
# followed; the checks apply to the target.
#
# Exit codes: 0 ok, 2 usage, 3 not a regular file, 4 too large, 5 unreadable.
set -eu

[ "$#" -eq 2 ] || { echo "usage: read-bounded.sh <path> <max-bytes>" >&2; exit 2; }
path=$1
max=$2
case $max in
  ''|*[!0-9]*) echo "max-bytes must be a non-negative integer" >&2; exit 2 ;;
esac

[ -e "$path" ] || { echo "not found" >&2; exit 3; }
[ -f "$path" ] || { echo "not a regular file" >&2; exit 3; }
[ -r "$path" ] || { echo "not readable" >&2; exit 5; }

size=$(stat -L -c %s -- "$path" 2>/dev/null) || { echo "unreadable" >&2; exit 5; }
[ "$size" -le "$max" ] || { echo "too large: $size bytes, limit $max" >&2; exit 4; }

# head caps the read even if the file grows between the stat and the read.
exec head -c "$max" -- "$path"
