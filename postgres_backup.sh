#!/usr/bin/env sh

# Usage:
# postgres_backup.sh [man]		//Manual backup, full output
# postgres_backup.sh auto		//Auto backup (separate backup location, only outputs STDERR messages)

# CONFIG
### Example Config File ############
###
### PORT=5432
### DIR=/var/lib/pgsql/backup
### COMPRESSION=zstd
### COMP_LEVEL=14
### THREADS=2
###
####################################
#
# Load config file:
if [ ! -f ${HOME}/.postgres_backup.conf ]; then
	echo "ERROR 10: Configuration file not found"
	exit 10
fi
source ${HOME}/.postgres_backup.conf


## Check if automated, set appropriate directory
if [ "$1" = "auto" ]; then
	AUTO="true"
	DIR=${DIR}/auto
else
	AUTO="false"
	DIR=${DIR}/manual
fi

## Define message commands
msg_show() {
	[ "$AUTO" = "false" ] && printf "$1"
}
msg_check() {
	[ "$AUTO" = "false" ] && printf '%-70s %s' "$1" # | sed s/\ \ /../g
}
get_size() {
	tsize=$(find $1 -prune -printf '%s\n')
	[ $tsize -lt 1024 ] && tsize="$tsize B" || tsize=$(numfmt --to=iec-i --suffix=B --format='%.3f' <<<$tsize | sed -r 's/([A-Z])/ \1/')
	printf "$tsize"
}

## Sanity check
pass="$(tput bold)$(tput setaf 2)OK$(tput sgr0)\n"
fail="$(tput bold)$(tput setaf 1)FAIL$(tput sgr0)\n"

msg_show "=== $(tput bold)Config Sanity Check$(tput sgr0)\n"

msg_check "PostgreSQL server port: $(tput bold)${PORT}$(tput sgr0)"
if [ $PORT -lt 65536 -a $PORT -gt 0 ] 2>/dev/null; then
	msg_show "$pass"
else
	msg_show "$fail"
	echo "ERROR 11: PORT configuration not a valid port number" >&2
	exit 11
fi
msg_check "Backup directory: $(tput bold)${DIR}$(tput sgr0)"
if [ -d "$DIR" ]; then
	msg_show "$pass"
else
	msg_show "$fail"
	echo "ERROR 12: Backup directory does not exist" >&2
	exit 12
fi
msg_check "Compression type: $(tput bold)${COMPRESSION}$(tput sgr0)"
case $COMPRESSION in
	xz)
		msg_show "$pass"
		msg_check "Compression level: $(tput bold)${COMP_LEVEL}$(tput sgr0)"
		if [ $(sed s/e// <<< $COMP_LEVEL) -lt 10 -a $(sed s/e// <<< $COMP_LEVEL) -gt 0 ] 2>/dev/null; then
			msg_show "$pass"
		else
			msg_show "$fail"
			echo "ERROR 14: Compression level not valid" >&2
			exit 14
		fi
		;;
	zstd)
		msg_show "$pass"
		msg_check "Compression level: $(tput bold)${COMP_LEVEL}$(tput sgr0)"
		if [ $COMP_LEVEL -lt 20 -a $COMP_LEVEL -gt 0 ] 2>/dev/null; then
			msg_show "$pass"
		else
			msg_show "$fail"
			echo "ERROR 14: Compression level not valid" >&2
			exit 14
		fi
		;;
	*)
		msg_show "$fail"
		echo "ERROR 13: Compression not configured correctly" >&2
		exit 13
		;;
esac
msg_check "Thread count: $(tput bold)${THREADS}$(tput sgr0)"
if [ $THREADS -eq $THREADS -a $THREADS -gt -1 ] 2>/dev/null; then
	msg_show "$pass"
	[ $THREADS -gt $(nproc) ] 2>/dev/null && msg_show "$(tput setaf 3)$(tput bold)WARN:$(tput sgr0) THREADS is set higher than CPU count!\n"
else
	msg_show "$fail"
	echo "ERROR 15: Thread count is not a valid positive integer" >&2
	exit 15
fi
## End sanity check


## Set date for timestamp
DATE=$(date +%Y%m%d-%H%M)
msg_show "Timestamp set to $(tput bold)${DATE}$(tput sgr0)\n"

## Get list of DBs
list_db=$(psql -p${PORT} -U postgres -t -c 'select datname from pg_database;' | grep -v 'template0\|template1\|postgres' | sed '/^$/d')

## Set compression parameters
case $COMPRESSION in
	xz)
		compress="xz -T${THREADS} -${COMP_LEVEL} -"
		comp_ext="xz"
		;;
	zstd)
		compress="zstd -T${THREADS} -${COMP_LEVEL} -z -"
		comp_ext="zst"
		;;
	*)
		echo "ERROR 13: Compression not configured correctly!" >&2
		exit 13
		;;
esac

msg_show "\nStarting backup procedures...\n\n"

## Backup globals
target="${DIR}/globals_${DATE}.dmp.${comp_ext}"
pg_dumpall -p${PORT} -g | eval $compress > ${DIR}/globals_${DATE}.dmp.${comp_ext}
msg_show "Backed up $(tput setaf 2)$(tput bold)globals$(tput sgr0) as $(tput setaf 3)${target}$(tput sgr0) [$(tput setaf 2)$(get_size $target)$(tput sgr0)] using $(tput bold)${compress}$(tput sgr0)\n"

for db in $list_db; do
	target="${DIR}/${db}_${DATE}.dmp.${comp_ext}"
	pg_dump -O $db | eval $compress > $target
	msg_show "Backed up $(tput setaf 2)$(tput bold)${db}$(tput sgr0) as $(tput setaf 3)${target}$(tput sgr0) [$(tput setaf 2)$(get_size $target)$(tput sgr0)] using $(tput bold)${compress}$(tput sgr0)\n"
done

exit 0

