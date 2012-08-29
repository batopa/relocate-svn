#!/bin/bash

handleError() {
	MYSELF="$0"               # equals to my script name
	LASTLINE="$1"            # argument 1: last line of error occurence
	LASTERR="$2"             # argument 2: error code of last command
	echo "${MYSELF}: line ${LASTLINE}: exit status of last command: ${LASTERR}"
	exit 1
}

trap 'handleError ${LINENO} ${$?}' ERR

die() {
	echo -e >&2 "$@\n"
	echo "Digit relocate_svn.sh -h for more usage info"
	exit 1
}

help() {
cat << EOF
USAGE: ./relocate.sh [options] <path_to_old_repository_working_copy> <url_to_new_repository>

DESCRIPTION
	This script run the svn relocate.
	If needed it permits to force the working copy UUID change

MANDATORY
	path_to_old_repository_working_copy: local svn working copy directory
	url_to_new_repository: url to new svn repository

OPTIONS:
	-h 		Show this message
	-e 		Optional: list of excluded dirs separated by comma i.e dir1,dir2,..
			Useful when the operation requires an UUID update and some subdirs contain others svn

EXAMPLE:
	$ cd local-svn-folder
	$ ./relocate.sh -e dir1,dir2,dir3 . http://www.example.com/svn-repo/trunk

	in this case the possible UUID change will not be done in local-sv-folder/dir1, local-sv-folder/dir2, local-sv-folder/dir3
EOF
exit 1
}

changeUUID() {
	cmd="find $1 -name entries -exec sed -i 's/$OLD_UUID/$NEW_UUID/g' {} \;"
	if [ $VERBOSE ]; then
		echo "$cmd"
	fi
	eval $cmd
}

VERBOSE=false

# get named options
while getopts "hve:b:" OPTION
do
	case $OPTION in
		h)
			help
			;;
		e)
			EXCLUDE_DIR=$OPTARG
			shift $((OPTIND-1))
			;;
		b)
			BACKUP_DIR=$OPTARG
			shift $((OPTIND-1))
			;;
		v)
			VERBOSE=true
			shift $((OPTIND-1))
			;;
		?)
			help
			;;
	esac
done

# check other args 
if [ "$#" == 1 ] && [ "$1" == "help" ]; then
	help
fi

if [ "$#" -lt 2 ]; then
	die "2 positional arguments are required, $# provided"
fi

if [ ! -d $1 ]; then
	die "$1 has to be a valid directory"
fi

SRC=$1
NEW_REPO=$2

# string to array
if [ ! -z "$EXCLUDE_DIR" ]; then
	IFS=","
	EXCLUDE_DIR_ARR=()
	for dir in $EXCLUDE_DIR
	do
		EXCLUDE_DIR_ARR+=($dir)
	done
fi

echo -e "\nFetching data..."
OLD_REPO=$(svn info | grep URL | sed 's/URL: //')
OLD_UUID=$(svn info | grep 'Repository UUID: ' | sed 's/Repository UUID: //')
NEW_UUID=$(svn info $NEW_REPO | grep 'Repository UUID: ' | sed 's/Repository UUID: //')

echo "Old repository: $OLD_REPO"
echo "Old repository UUID: $OLD_UUID"
echo "New repository: $NEW_REPO"
echo -e "New repository UUID: $NEW_UUID \n"

cd "$SRC"
echo "Proceeding the svn working copy located in '`pwd`' will be relocated to a different repository URL."
if [ "$OLD_UUID" != "$NEW_UUID" ]; then
	echo "WARNING: since the UUIDs don't match, the working copy's UUID should be updated to new repository UUID."
	echo "If you haven't any idea of what is a svn UUID you should be abort the action because the working copy could be corrupted."
fi

echo "Do you want to proceed? [y/n]"
read -p "> " ANSWER

if [ "$ANSWER" != "y" ]; then
	die "Aborting action... bye"
fi

echo "OK, let's go!"
echo "Operating path: $(pwd)";

if [ "$OLD_UUID" != "$NEW_UUID" ]; then

	# if there is at least an exclude dir scan dir by dir
	if [ ! -z "$EXCLUDE_DIR" ]; then

		# update UUID in $SRC/.svn
		changeUUID ".svn"
		echo "UUID in .svn dir updated";

		#enable for loops over items with spaces in their name
		IFS=$'\n'

		# update UUID in .svn inside subdir except for EXCLUDE_DIR passed
		for dir in `ls "$SRC/"`
		do
			if [ -d "$SRC/$dir" ]; then
				if [[ ${EXCLUDE_DIR_ARR[*]} =~ "$dir" ]]; then
					echo "$dir: skipped"
				else
					changeUUID "$dir"
					echo "$dir: UUID updated"
				fi
			fi
		done

	# no exclude dir... massive UUID change
	else
		changeUUID "."
		echo "`pwd`: UUID updated"
	fi

	echo "All UUID changed... proceed"

elif [ "$OLD_REPO" == "$NEW_REPO" ]; then

	echo -e "The repository URL and the UUIDs are identical.\nNo relocate action to do.\nBye"
	exit 1

fi

# relocate
echo "Relocate svn repository"
svn switch --relocate "$OLD_REPO" "$NEW_REPO" --ignore-externals
svn up
echo "--------------------------------------------------"
svn info
echo "done"
