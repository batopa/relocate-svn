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
USAGE: ./relocate_svn.sh [options] <path_to_working_copy> <new_repository_url>

DESCRIPTION
	This script run the svn relocate.
	If needed it permits to force checkout or the working copy UUID change

MANDATORY
	path_to_working_copy: local svn working copy directory, points to old svn repository
	new_repository_url: url to new svn repository

OPTIONS:
	-h 		Show this message
	-v 		verbose mode
	-b 		backup directory before relocate svn
	-e 		Optional: list of excluded dirs separated by comma i.e dir1,dir2,..
			Useful when the operation requires an UUID update and some subdirs contain others svn

EXAMPLE:
	$ cd local-svn-folder
	$ ./relocate_svn.sh -e dir1,dir2,dir3 . http://www.example.com/svn-repo/trunk

	in this case the possible UUID change will not be done in local-sv-folder/dir1, local-sv-folder/dir2, local-sv-folder/dir3
EOF
exit 1
}

changeUUID() {
	cmd="find $1 -name entries -exec sed -i 's/$OLD_UUID/$NEW_UUID/g' {} \;"
	if [[ $VERBOSE == true ]]; then
		echo "$cmd"
	fi
	eval $cmd
}

removeSVN() {
	cmd="rm -rf `find $1 -type d -name .svn`"
	if [[ $VERBOSE == true ]]; then
		echo "$cmd"
	fi
	eval $cmd
}

VERBOSE=false
BACKUP=false

# get named options
while getopts "hvbe:" OPTION
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
			BACKUP=true
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

# change directory to $SRC
cd "$SRC"
SRC=`pwd`

# backup
if [ $BACKUP == true ]; then
	BACKUP_DIR=~/tmp
	DIRNAME=${PWD##*/}
	BACKUP_FILE="$DIRNAME-"`date +"%s"`".tar.gz"
	echo -e "\nBACKUP option selected...\n"
	echo "A backup file named $BACKUP_FILE will be saved into $BACKUP_DIR"
	if [ ! -d $BACKUP_DIR ]; then
		mkdir $BACKUP_DIR
		echo "$BACKUP_DIR directory created"
	fi

	TAR_OPTIONS="cfz"
	if [ $VERBOSE == true ]; then
		TAR_OPTIONS=$TAR_OPTIONS"v"
		echo "tar $TAR_OPTIONS $BACKUP_DIR/$BACKUP_FILE ../$DIRNAME"
	fi
	tar $TAR_OPTIONS $BACKUP_DIR"/"$BACKUP_FILE "../$DIRNAME"
	echo "Backup done in $BACKUP_DIR/$BACKUP_FILE"

	echo "Continue? [y/n]"
	read -p "> " ANSWER

	if [ "$ANSWER" != "y" ]; then
		die "Aborting action... bye"
	fi
fi

echo -e "\nFetching data..."
OLD_REPO=$(svn info | grep URL | sed 's/URL: //')
OLD_UUID=$(svn info | grep 'Repository UUID: ' | sed 's/Repository UUID: //')
NEW_UUID=$(svn info $NEW_REPO | grep 'Repository UUID: ' | sed 's/Repository UUID: //')

if [ -z "$NEW_UUID" ]; then
	die "New repository UUID not found, check svn url ...bye"
fi

echo "Old repository: $OLD_REPO"
echo "Old repository UUID: $OLD_UUID"
echo "New repository: $NEW_REPO"
echo -e "New repository UUID: $NEW_UUID \n"

echo "Proceeding the svn working copy located in '`pwd`' will be relocated to a different repository URL."

# can be false or 'removeSVN' or 'changeUUID'
MISMATCH_UUID_OPERATION=

if [ "$OLD_UUID" != "$NEW_UUID" ]; then
	echo -e "\n-------------------------------------------------------------------------------"
	echo "WARNING: working copy UUID doesn't match new repository UUID!"
	echo -e "This means that the new repository isn't an identical copy of old repository.\nTrying to relocate could be result a bit difficult."
	echo -e "-------------------------------------------------------------------------------\n"
	echo -e "You can proceed in two ways:\n"
	echo "1. Force check out on top of existing files. It will remove all .svn dir then perform a 'svn checkout --force' operation and revert to new repository HEAD (recommended)"
	echo "2. Trying to override old UUID with new UUID then relocate svn"
	echo -e "\nWhat do you choose? [1/2/any other key to abort]"
	read -p "> " ANSWER

	if ! [[ "$ANSWER" =~ ^[0-9]+$ ]] || [[ "$ANSWER" -ne 1 && "$ANSWER" -ne 2 ]]; then
		die "Aborting action... bye"
	elif [ "$ANSWER" -eq 1 ]; then
		echo "Force checkout option selected"
		MISMATCH_UUID_OPERATION=removeSVN
	elif [ "$ANSWER" -eq 2 ]; then
		echo "Changhe UUID and relocate selected"
		MISMATCH_UUID_OPERATION=changeUUID
	fi
else
	echo "Do you want to proceed? [y/n]"
	read -p "> " ANSWER

	if [ "$ANSWER" != "y" ]; then
		die "Aborting action... bye"
	fi
fi

echo -e "\nOK, let's go!"
echo "Operating path: $PWD";

if [ "$OLD_UUID" != "$NEW_UUID" ]; then

	# if there is at least an exclude dir scan dir by dir
	if [ ! -z "$EXCLUDE_DIR" ]; then

		if [ $MISMATCH_UUID_OPERATION == "removeSVN" ]; then
			# remove .svn
			rm -rf .svn
			echo ".svn dir removed";
		else
			# update UUID in $SRC/.svn
			changeUUID ".svn"
			echo "UUID in .svn dir updated";
		fi

		#enable for loops over items with spaces in their name
		IFS=$'\n'

		# update UUID in .svn inside subdir except for EXCLUDE_DIR passed
		for dir in `pwd | ls`
		do
			if [ -d "$SRC/$dir" ]; then
				if [[ ${EXCLUDE_DIR_ARR[*]} =~ "$dir" ]]; then
					echo "$dir: skipped"
				else
					if [ $MISMATCH_UUID_OPERATION == "removeSVN" ]; then
						removeSVN "$dir"
						echo "$dir: .svn removed"
					else
						changeUUID "$dir"
						echo "$dir: UUID updated"
					fi
				fi
			fi
		done

	# no exclude dir... massive UUID change
	else
		if [ $MISMATCH_UUID_OPERATION == "removeSVN" ]; then
			removeSVN "."
			echo "`pwd`: all .svn updated"
		else
			changeUUID "."
			echo "`pwd`: UUID updated"
		fi
	fi

	echo -e "\nProceed\n"

elif [ "$OLD_REPO" == "$NEW_REPO" ]; then

	echo -e "The repository URL and the UUIDs are identical.\nNo relocate action to do.\nBye"
	exit 1

fi

if [ $MISMATCH_UUID_OPERATION == "removeSVN" ]; then
	# force checkout and revert
	echo "Force checkout"
	svn co --force "$NEW_REPO" "."
	svn revert -R .
else
	# relocate
	echo "Relocate svn repository"
	svn switch --relocate "$OLD_REPO" "$NEW_REPO" --ignore-externals
fi

svn up
echo "--------------------------------------------------"
svn info "$SRC"
echo "done"
