#Linux bash script to oaccassionally check File system

trap '
	[ -s "$Report" ] && $Mail -s "$PN report" $Admin < "$Report"
	rm -f "$Report"' 0
trap "exit 2" 1 2 3 13 15

NDirs=5

# Determine the operating system we run on
OS=
DF=
case `uname -s` in
    SunOS)
    	case `uname -r` in
	    4.*)
	    	OS=SUNOS
		DF=df
		DU=du
		;;
	    5.*)
	    	OS=SOLARIS
		DF="df -k"
		DU="du -k"
		;;
	esac;;
    *)
    	echo >&2 "unknown operating system, using default commands"
	DF=df
	DU=du
	OS=`uname -s | tr '[a-z]' '[A-Z]'`
	;;
esac

exec > "$Report" 2>&1

[ $# -lt 1 ] && set -- /

#
# Find full file systems
#

MinPercent=95

echo "
*** File systems at least $MinPercent % full
"

$DF |
    nawk '
	{
	    if ( Header "" == "" ) Header = $0
	    for ( i=1; i<=NF; i++ ) {
	    	if ( $i ~ /^[0-9][0-9]*%$/ ) {
		    Percent=$i; sub (/%$/, "", Percent)
		    if ( Percent + 0 >= '$MinPercent' ) {
		    	if ( headerPrinted == "" ) {
			    print Header; headerPrinted = "true"
			}
		    	print
		    }
		}
	    }
	}
    '

#
# Find the directories consuming most space, grouped by file system
#

echo "
*** Top $NDirs directories, grouped by file system
"

# Determine all file systems
Filesystems=

if [ -r /etc/fstab ]
then					# BSD/SunOS/Linux style
    # Example:
    # /dev/sd0a  /  4.2 rw,quotas 1 1
    exec 3<&0 0</etc/fstab
    while read device mountpoint rest
    do
    	case "$device" in
	    /dev*)	;;		# valid device name
	    *)		continue;;
	esac
	case "$mountpoint" in
	    /*)		;;		# valid mount point
	    *)		continue;
	esac
	Filesystems="$Filesystems $mountpoint"
    done
    exec 0<&3 3<&-
elif [ -r /etc/vfstab ]
then					# SVR4 style (SOLARIS, UnixWare, ...)
    # Example:
    # /dev/dsk/c0t3d0s0 /dev/rdsk/c0t3d0s0 / ufs 1 no -

    exec 3<&0 0</etc/vfstab
    while read mountdev fsckdev mountpoint rest
    do
    	case "$mountdev" in
	    /dev*)	;;		# o.k., valid device name
	    *)		continue;;
	esac
	case "$mountpoint" in
	    /*)		;;		# valid path name
	    *)		continue;;
	esac
	Filesystems="$Filesystems $mountpoint"
    done
    exec 0<&3 3<&-
fi

set -u

#Filesystems=

for FS in $Filesystems
do
    # Build list of files to exclude, i.e. "^/usr|^/var|^/usr/local"
    ExcludeList=
    for dir in $Filesystems
    do
    	[ $dir = $FS ] && continue
	case "$FS" in
	    $dir*)		# do not exclude this substring (i.e. "/")
		continue;;
	esac
	ExcludeList="${ExcludeList:+$ExcludeList|}$dir"
    done
    : ${ExcludeList:="THIS NEVER MATCHES A DIRECTORY"}
    ExcludeList="[ 	]*($ExcludeList)"

    echo "
--- $FS"

    $DU $FS |
    	egrep -v "$ExcludeList" |
	sort -nr |
	awk '$1 > 1000' |	# we are only interested in *large* directories
	head -$NDirs
done

echo "
*** Hidden directories
"
# Find all directories and files starting with a '.' and calculate the size
find "$@" \( -type d -o -type f \) -name '.*' -print |
	xargs $DU -s |
	awk '$1 > 1000'

# Find all files greater than 5 MB
#find "$@" -type f -size +5120 -print | xargs ls -ld
