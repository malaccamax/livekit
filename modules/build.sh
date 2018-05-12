#!/bin/bash
set -e

for _FILE in scripts/functions/*.sh;do
	if [ -e "${_FILE}" ];then
		. "${_FILE}"
	fi
done
