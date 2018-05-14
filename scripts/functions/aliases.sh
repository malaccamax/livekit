#!/bin/sh

Find_files ()
{
	(ls "${@}" | grep -qs .) > /dev/null 2>&1
}

In_list ()
{
	NEEDLES="${1}"
	shift

	for ITEM in ${@}
	do
		for NEEDLE in ${NEEDLES}
		do
			if [ "${NEEDLE}" = "${ITEM}" ]
			then
				return 0
			fi
		done
	done

	return 1
}

Truncate ()
{
	for FILE in ${@}
	do
		: > ${FILE}
	done
}
