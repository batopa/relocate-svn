relocate-svn
============

Bash script to relocate svn repository to new one. Tested with subversion client 1.6.17

If new repository has different UUID offers the possibility to force checkout or update working copy UUID with the new one and then proceed with relocate command

	USAGE:

	$ ./relocate_svn.sh [options] path_to_old_repository_working_copy url_to_new_repository

	MANDATORY
		path_to_old_repository_working_copy: local svn working copy directory
		url_to_new_repository: url to new svn repository

	OPTIONS:
		-h 		Show help
		-v 		verbose mode
		-b 		backup directory before relocate svn
		-e 		Optional: list of excluded dirs separated by comma i.e dir1,dir2,..
				Useful when the operation requires an UUID update and some subdirs contain others svn

	EXAMPLE:
		$ cd local-svn-folder
		$ ./relocate_svn.sh -e dir1,dir2,dir3 . http://www.example.com/svn-repo/trunk

		in this case the possible UUID change will not be done in:
		* local-sv-folder/dir1
		* local-sv-folder/dir2
		* local-sv-folder/dir3
