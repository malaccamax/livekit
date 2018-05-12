#!/bin/bash
set -e

for _FILE in ${PROGRAM}/functions/*.sh;do
	if [ -e "${_FILE}" ];then
		. "${_FILE}"
	fi
done
