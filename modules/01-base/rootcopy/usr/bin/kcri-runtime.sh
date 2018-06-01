#!/bin/bash
# Copyright 2018 Malaccamax.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Knight cmd line wrapper.

## Basic utility
readonly kDebugLog=/tmp/kcri-runtime.log
LIVE=/run/initramfs/memory

# debug prints debug message to stdout.
debug() {
    echo "$(date --utc +%FT%T.%3NZ) stdout F $*" >> "${kDebugLog}"
}

# warn prints warning messages to stderr.
warn() {
    echo "WARNING: $*" >&2
}

# error prints error messages to stderr.
error() {
    echo "ERROR: $*" >&2
    exit 1
}

get_bundle_storage_dir()
{
   local TGT

   TGT=$LIVE/data/slax/modules

   mkdir -p $TGT 2>/dev/null
   touch $TGT/.empty 2>/dev/null && rm $TGT/.empty 2>/dev/null
   if [ $? -ne 0 ]; then
      TGT=$LIVE/modules
      mkdir -p $TGT
   fi

   echo $TGT
}

print_branches()
{
   local SI BUNDLE LOOP CWD

   SI="/sys/fs/aufs/$(cat /proc/mounts | grep 'aufs / aufs' | egrep -o 'si=([^,) ]+)' | tr = _)"
   CWD="$(pwd)"
   cd "$SI"
   ls -v1 | grep -v xi_path | egrep 'br[0-9]+' | xargs cat | grep memory/bundles | rev | cut -b 4- | rev | while read BUNDLE; do
      if mountpoint -q "$BUNDLE"; then
         LOOP=$(cat /proc/mounts | fgrep " $BUNDLE squashfs" | cut -d " " -f 1)
         echo -n "$BUNDLE"
         echo -ne "\t"
         losetup $LOOP | sed -r "s:.*[(]|[)].*::g"
      fi
   done | tac
   cd "$CWD"
}

runscriptlet()
{
	local SB HANDLER TEMPSCRIPT
	local SB=$1
	local HANDLER=$2
	if [ -f ${SB}/run/install ];then 
		debug "/run/install not exists."
	fi
	if ! grep -q ${HANDLER} ${SB}/run/install;then
		debug "/run/install has not ${HANDLER}."
	fi

	TEMPSCRIPT=$(mktemp /tmp/kcri.XXXXXXXXX)
cat > ${TEMPSCRIPT} <<EOF
. ${SB}/run/desc || :
. ${SB}/run/install
${HANDLER}
EOF
	#We use bash as default
	bash ${TEMPSCRIPT}
	RESULT=$?
	rm -f ${TEMPSCRIPT}
	if [ ${RESULT} != 0 ];then
		error "can't runscriptlet $1 $2"
	fi

}

## CRI interfaces

readonly kContainerStateCreated="created"
readonly kContainerStatePaused="paused"
readonly kContainerStateRunning="running"
readonly kContainerStateStopped="stopped"

function containerAttach() {
    debug "containerAttach()"
}

F1=/tmp/kcri-$$-in.tmp
F2=/tmp/kcri-$$-out.tmp
trap "rm -f $F1 $F2" EXIT

# Create a new container.
# @param podId, ID of the PodSandbox in which the container should be created.
# @param containerName, Name of the container. Same as the container name in the PodSpec.
# @param attempt, Attempt number of creating the container. Default: 0.
# @param image, Image to use. ImageId or ImageDigest.
# @param command, Command to execute (i.e., entrypoint for docker)
# @param args, Args for the Command (i.e., command for docker)
# @param workDir, Current working directory of the command.
# @param env, List of environment variable to set in the container.
# @param podName, Pod name of the sandbox. Same as the pod name in the PodSpec.
# @param uid, Pod UID of the sandbox. Same as the pod UID in the PodSpec.
# @param namespace, Pod namespace of the sandbox. Same as the pod namespace in the PodSpec.
# @param podAttempt, Attempt number of creating the sandbox. Default: 0.
# @param hostname, Hostname of the sandbox.

containerCreate() {
    local podId=$1
    local containerName=$2
    local attempt=$3
    local image=$4
    local command=$5
    local args=$6
    local workDir=$7
    local env=$8
    local podName=$9
    local uid=$10
    local namespace=$11
    local podAttempt=$12
    local hostname=$13
    debug "containerCreate() $*"
    local SB TGT BAS

    SB="$(readlink -f "${image}")"
    BAS="$(basename "$SB")"

    # check if file exists
    if [ ! -r "$SB" ]; then
        error "file not found $SB"
    fi

    # copy the module to storage dir so it can be activated from there
    TGT="$(get_bundle_storage_dir)"

    if [ -r $TGT/$BAS ]; then
        error "File exists: $TGT/$BAS"
    fi

    cp -n "$SB" "$TGT/$BAS"

    if [ $? -ne 0 ]; then
        die "Error copying file to $TGT/$BAS. Not enough space?"
    fi

    SB="$TGT/$BAS"

    # check if this particular file is already activated
    if print_branches | cut -f 2 | fgrep -q "$SB"; then
        exit
    fi

    # mount remount,add
    TGT="$LIVE/bundles/$BAS"
    mkdir -p "$TGT"

	runscriptlet "${TGT}" pre_install

    mount -n -o loop,ro "$SB" "$TGT"
    if [ $? -ne 0 ]; then
        error "Error mounting $SB to $TGT, perhaps corrupted download"
    fi

    # add current branch to aufs union
    mount -t aufs -o remount,add:1:"$TGT" aufs /
    if [ $? -ne 0 ]; then
        umount "$TGT"
        rmdir "$TGT"
        error "Error attaching bundle filesystem to Slax"
    fi

	runscriptlet "${TGT}" post_install
    echo "Slax Bundle activated: $BAS"
}

containerExec() {
    debug "containerExec()"
}

containerExecSync() {
    debug "containerExecSync()"
}

# @return [(containerId, containerName, restartAttempt, imageRef, state, podSandboxId) ...]
containerList() {
    debug "containerList"
    local SI BUNDLE LOOP CWD DEST
    SI="/sys/fs/aufs/$(cat /proc/mounts | grep 'aufs / aufs' | egrep -o 'si=([^,) ]+)' | tr = _)"
    CWD="$(pwd)"
    cd "$SI"
    ls -v1 | grep -v xi_path | egrep 'br[0-9]+' | xargs cat | grep memory/bundles | rev | cut -b 4- | rev | while read BUNDLE; do
        if mountpoint -q "$BUNDLE"; then
            LOOP=$(cat /proc/mounts | fgrep " $BUNDLE squashfs" | cut -d " " -f 1)
            DEST=$(losetup $LOOP | sed -r "s:.*[(]|[)].*::g")
            if echo ${DEST} | egrep -q "/modules/";then 
				id=$(echo -n "${BUNDLE}" | sha256sum - | awk '{print $1}')
				basename ${DEST} | sed 's/\.sb//' | awk -F'-' '{print $1,$2,$3}' | read num name version
                ref=${name}:${version:-lastest}
                attempt=12
				if systemctl status ${name}.service | grep -q 'Active:.*(running)';then
					state='running'
				else
					state='pending'
				fi
				podid=$(echo -n "${BUNDLE}" | sha256sum - | awk '{print $1}')
				echo -e "${id}\t${name}\t${attempt}\t${ref}\t${state}\t${podid}"
            fi
        fi
    done | tac
    cd "$CWD"
}

# @param podId
# @return portForward service url.
#    POST / HTTP/1.1\r\n
#    Host: localhost:8000\r\n
#    User-Agent: Go-http-client/1.1\r\n
#    Content-Length: 0\r\n
#    Connection: Upgrade\r\n
#    Upgrade: SPDY/3.1\r\n
#    X-Stream-Protocol-Version: portforward.k8s.io\r\n
#    \r\n
containerPortForward() {
    local podId=$1
    debug "containerPortForward() ${podId}"

    echo "http://127.0.0.1:8090"
}

containerRemove() {
	local containerId=$1
	local BUNDLES SB MATCH LOOP LOOPFILE
	for BUNDLE in $(ls ${LIVE}/bundles -v1); do
		if echo $(echo -n ${LIVE}/bundles/${BUNDLE} | sha256sum - | awk '{print $1}') | grep -q ${containerId};then
			SB=${BUNDLE}
			break
		fi
	done

	if [ -z ${SB} ];then
		error "can't found containerId:${containerId}"
	fi

	BUNDLES=$LIVE/bundles

	rmdir "$BUNDLES/$SB" 2>/dev/null    # this fails unless the dir is

	if [ ! -d "$BUNDLES/$SB" ]; then
		# we don't have real filename match, lets try to add .sb extension
		if [ ! -d "$BUNDLES/$SB.sb" ]; then
			# no, still no match. Lets use some guesswork
			SB=$(print_branches | cut -f 2 | egrep -o "/[0-9]+-$SB.sb\$" | tail -n 1 | xargs -r basename)
		else
			SB="$SB.sb"
		fi
	fi

	if [ "$SB" = "" -o ! -d "$BUNDLES/$SB" ]; then
		error "can't find active bundle $1"
	fi

	runscriptlet "${SB}" pre_remove

	echo "Attempting to deactivate bundle $SB..."
	mount -t aufs -o remount,verbose,del:"$BUNDLES/$SB" aufs / 2>/dev/null
	if [ $? -ne 0 ]; then
		error "Unable to deactivate Bundle - still in use. See dmesg for more."
	fi

	runscriptlet "${SB}" post_remove

   # remember what loop device was the bundle mounted to, it may be needed later
   LOOP="$(cat /proc/mounts | fgrep " $BUNDLES/$SB " | cut -d " " -f 1)"
   LOOPFILE="$(losetup "$LOOP" | cut -d " " -f 3 | sed -r 's:^.|.$::g')"

   umount "$BUNDLES/$SB" 2>/dev/null
   if [ $? -ne 0 ]; then
	   error "Unable to umount bundle loop-mount $BUNDLES/$SB"
   fi
   rmdir "$BUNDLES/$SB"

   # free the loop device manually since umount fails to do that if the bundle was activated on boot
   losetup -d "$LOOP" 2>/dev/null

   # remove the .sb file, but keep it if deactivate was issued on full sb real path
   if [ "$(realpath "$1")" != "$(realpath "$LOOPFILE")" ]; then
	   rm -f "$LOOPFILE" 2>/dev/null
   fi

   echo "Bundle deactivated: $SB"
   debug "containerRemove() ${containerId}"
}

containerReopenLog() {
    debug "containerReopenLog()"
}

containerStart() {
    local containerId=$1
    debug "containerStart() ${containerid}"
	local SB SERVICE
	for bundle in $(ls ${LIVE}/bundles -v1); do
		if echo $(echo -n ${LIVE}/bundles/${bundle} | sha256sum - | awk '{print $1}') | grep -q ${containerId};then
			SB=${bundle}
			break
		fi
	done
    
    if [ -z ${SB} ] || [ ! -d "${LIVE}/bundles/$SB" ]; then
        error "can't found containerId:${containerId}"
    fi

    if [ ! -f "${LIVE}/bundles/${SB}/run/desc" ]; then
        error "can't found desc for containerId:${containerId}"
    fi

    SERVICE=$(cat "${LIVE}/bundles/${SB}/run/desc" | grep -e '^|service=' | awk -F'=' '{print $2}') 
    if [ -z ${SERVICE} ];then
        error "can't found service for containerId:${containerId}"
    fi

    systemctl start ${SERVICE} || error "cann't start service for containerId:${containerId}"
}

# Return statistics of a specific container.
# @param containerId
# @return (containerId, containerName, attempt, cpuTimestamp, cpuUsageCoreNanoSeconds,
#          memoryTimestamp, memoryWorkingSetBytes, fsTimestamp, fsId, fsUsedBytes, fsInodesUsed)
# * containerId, ID of the container.
# * containerName, Name of the container. Same as the container name in the PodSpec.
# * attempt, Attempt number of creating the container. Default: 0.
# * cpuTimestamp, Timestamp in nanoseconds at which the information were collected. Must be > 0.
# * cpuUsageCoreNanoSeconds, Cumulative CPU usage (sum across all cores) since object creation.
# * memoryTimestamp, Timestamp in nanoseconds at which the information were collected. Must be > 0.
# * memoryWorkingSetBytes, The amount of working set memory in bytes.
# * fsTimestamp, Timestamp in nanoseconds at which the information were collected. Must be > 0.
# * fsId, The unique identifier of the filesystem.
# * fsUsedBytes, UsedBytes represents the bytes used for images on the filesystem.
# * fsInodesUsed, InodesUsed represents the inodes used by the images.
containerStats() {
    local containerId=$1
    debug "containerStats() ${containerId}"
    for bundle in $(ls ${LIVE}/bundles -v1); do
		if echo $(echo -n ${LIVE}/bundles/${bundle} | sha256sum - | awk '{print $1}') | grep -q ${containerId};then
			SB=${bundle}
			break
		fi
	done
    
    if [ -z ${SB} ] || [ ! -d "${LIVE}/bundles/$SB" ]; then
        error "can't found containerId:${containerId}"
    fi

    if [ -f "${LIVE}/bundles/${SB}/run/desc" ]; then
        name=$(cat "${LIVE}/bundles/${SB}/run/desc" | grep -e '^|name=' | awk -F'=' '{print $2}')
    else
        name=${SB}
    fi
    
    echo "${containerId}\t${name}\t0\t10\t100\t21\t200000\t300\t/var/lib/docker\t4000\t5000"
}

# Return statistics of all containers.
containerStatsList() {
    debug "containerStatsList()"
    for bundle in $(ls ${LIVE}/bundles -v1); do
        containerId=$(echo -n ${LIVE}/bundles/${bundle} | sha256sum - | awk '{print $1}')
        if [ -f "${LIVE}/bundles/${bundle}/run/desc" ]; then
            name=$(cat "${LIVE}/bundles/${bundle}/run/desc" | grep -e '^|name=' | awk -F'=' '{print $2}')
        else
            name=${bundle}
        fi
        echo "${containerId}\t${name}\t0\t$(date +%s%N)\t10\t21\t200000\t300\t${LIVE}\t4000\t5000"
    done
}

# @param containerId e.g. 8add50bb6d013936126ec718af599c2e0c22de29ae2ede6a614b493a71e65a7e
# @return (containerId, containerName, restartAttempt, imageRef, state, containerPath, hostPath, logPath)
containerStatus() {
    debug "containerStatus()"
    for bundle in $(ls ${LIVE}/bundles -v1); do
        containerId=$(echo -n ${LIVE}/bundles/${bundle} | sha256sum - | awk '{print $1}')
        if [ -f "${LIVE}/bundles/${bundle}/run/desc" ]; then
            name=$(cat "${LIVE}/bundles/${bundle}/run/desc" | grep -e '^|name=' | awk -F'=' '{print $2}')
            version=$(cat "${LIVE}/bundles/${bundle}/run/desc" | grep -e '^|version=' | awk -F'=' '{print $2}')
        else
            name=${bundle}
			version=lastest
        fi
        echo "${containerId}\t${name}\t0\t${name}:${version}\trunning\t${LIVE}/bundles/${bundle}\t${LIVE}/bundles\t${kDebugLog}"
    done
}

containerStop() {
    local containerId=$1
    debug "containerStop() ${containerId}"
    local SB SERVICE
	for bundle in $(ls ${LIVE}/bundles -v1); do
		if echo $(echo -n ${LIVE}/bundles/${bundle} | sha256sum - | awk '{print $1}') | grep -q ${containerId};then
			SB=${bundle}
			break
		fi
	done
    
    if [ -z ${SB} ] || [ ! -d "${LIVE}/bundles/$SB" ]; then
        error "can't found containerId:${containerId}"
    fi

    if [ ! -f "${LIVE}/bundles/${SB}/run/desc" ]; then
        error "can't found desc for containerId:${containerId}"
    fi

    SERVICE=$(cat "${LIVE}/bundles/${SB}/run/desc" | grep -e '^|service=' | awk -F'=' '{print $2}') 
    if [ -z ${SERVICE} ];then
        error "can't found service for containerId:${containerId}"
    fi

    systemctl stop ${SERVICE} || error "cann't stop service for containerId:${containerId}"
}

# TODO(Shaohua):
# Update resource limitation policy of a container.
containerUpdateResources() {
    debug "containerUpdateResources()"
}

# @param podCird, CIDR to use for pod IP addresses.
containerUpdateRuntimeConfig() {
    local cird=$1
    debug "containerUpdateRuntimeConfig() ${cird}"
}

# Returns filesystem statistics information.
# * storagePath: Absolute path to image directory.
# * bytesUsed, bytes used of image directory.
# * inodesUsed, total inodes of image directory.
# @return (storagePath, bytesUsed, inodesUsed)
imageFsInfo() {
    debug "imageFsInfo()"

    echo "${LIVE} 1023123 18283"
}

# @return [(Repository Tag ImageId Size) ...]
imageList() {
    debug "imageList()"
    wget -q -O- "http://localhost/kcri?action=imagelist"
    if [ $? -ne 0 ];then
        echo "nginx latest sha256:577260d221dbb1be2d83447402d0d7c5e15501a89b0e2cc1961f0b24ed56c77c 10418293"
        error "Download error. Check your network connection."
    fi
}

# @param imageName, e.g. nginx:latest
# @return ImageId
imagePull() {
    local imageName=$1
    warn "TODO(Shaohua): Pull image ${imageName}"
    wget -q -O $F2 "http://localhost/kcri?action=imagepull&imagename=${imageName}" 
    if [ $? -ne 0 ];then
        error "Download error. Check your network connection."
    fi

    name=$(cat $F2 | grep -e '^|name=' | awk -F'=' '{print $2}')
    version=$(cat $F2 | grep -e '^|version=' | awk -F'=' '{print $2}')
    priority=$(cat $F2 | grep -e '^|priority=' | awk -F'=' '{print $2}')
    
    url=$(cat $F2 | grep -e '^|url=' | awk -F'=' '{print $2}')
    sha256sum=$(cat $F2 | grep -e '^|sha256sum=' | awk -F'=' '{print $2}')
    
    SB=${priority:-50}-${name}-${version}.sb
    wget -q -O ${F2} ${url} || error "Download error. Check your network connection."

    if [ $(sha256sum ${F2} | awk '{print $1}') != "${sha256sum}" ];then
        mv ${F2} ${LIVE}/data/${SB}
    fi
    echo "sha256:${sha256sum}"
}

# Remove a specific image
# @param imageName, e.g. nginx:latest
imageRemove() {
    local imageName=$1
    debug "imageRemove() ${imageName}"
    echo ${imagename} | awk -F':' | read name version
    echo "Will remove all image named by ${name} to reduce disk usage."
    for sb in $(ls ${LIVE}/data | grep .sb | grep ${name});do
        rm -f ${LIVE}/data/${sb}
    done
}

# @param imageName, e.g. nginx:latest
# @return (Repository Tag ImageId Size)
imageStatus() {
    local imageName=$1
    debug "imageStatus() ${imageName}"
    wget -q -O- "http://localhost/kcri?action=imagestatus&args=${imageName}"
    if [ $? -ne 0 ];then
        echo "nginx latest sha256:577260d221dbb1be2d83447402d0d7c5e15501a89b0e2cc1961f0b24ed56c77c 10418293"
        error "Download error. Check your network connection."
    fi
}

runtimeStatus() {
    debug "runtimeStatus()"
}

# @return [(podId, podName, uid, namespace, attempt, state, createdAt)]
# * podId, ID of the PodSandbox.
# * podName, pod name of the sandbox. Same as the pod name in the PodSpec.
# * uid, pod UID of the sandbox. Same as the pod UID in the PodSpec.
# * namespace, pod namespace of the sandbox. Same as the pod namespace in the PodSpec.
# * attempt, attempt number of creating the sandbox. Default: 0.
# * state, state of the PodSandbox, might be "ready" or "notReady".
# * createdAt, Creation timestamps of the PodSandbox in nanoseconds. Must be > 0. In nanoseconds
sandboxList() {
    debug "sandboxList()"

    echo "nginx1 nginxPod 0 default 0 ready 1526785840198798054"
}

sandboxRemove() {
    local podId=$1
    debug "sandboxRemove() ${podId}"
}

# @param podName, Pod name of the sandbox. Same as the pod name in the PodSpec.
# @param uid, Pod UID of the sandbox. Same as the pod UID in the PodSpec.
# @param namespace, Pod namespace of the sandbox. Same as the pod namespace in the PodSpec.
# @param attempt, Attempt number of creating the sandbox. Default: 0.
# @return, new created pod id.
sandboxRun() {
    local podName=$1
    local uid=$2
    local namespace=$3
    local attempt=$4
    debug "sandboxRun(), ${podName}, ${uid}, ${namespace}, ${attempt}"

    echo "nginxPod1"
}

# @return (podId, podName, uid, namespace, attempt, state, createdAt, networkIp)
# * podId, ID of the sandbox.
# * podName, Pod name of the sandbox. Same as the pod name in the PodSpec.
# * uid, Pod UID of the sandbox. Same as the pod UID in the PodSpec.
# * namespace, Pod namespace of the sandbox. Same as the pod namespace in the PodSpec.
# * attempt, Attempt number of creating the sandbox. Default: 0.
# * state, State of the sandbox, might be "ready", or "notReady".
# * createdAt, Creation timestamp of the sandbox in nanoseconds. Must be > 0, in nanoseconds.
# * networkIp, IP address of the podSandbox. Network contains network status if network is handled by the runtime.
sandboxStatus() {
    local podId=$1
    debug "sandboxStatus() ${podId}"

    echo "nginx1 nginxPod 0 default 0 ready 1526785840198798054 10.91.0.31"
}

sandboxStop() {
    local podId=$1
    debug "sandboxStop() ${podId}"
}

# No need to implement here.
#function version() {
#    echo "version"
#}

# Print usage message and exit.
printUsage() {
    cat > /dev/stdout << EOF
Usage: $0 cmd [command options] [arguments...]

COMMANDS:
     attach        Attach to a running container
     create        Create a new container
     exec          Run a command in a running container
     images        List images
     inspect       Display the status of one or more containers
     inspecti      Return the status of one ore more images
     inspectp      Display the status of one or more pods
     logs          Fetch the logs of a container
     port-forward  Forward local port to a pod
     ps            List containers
     pull          Pull an image from a registry
     runp          Run a new pod
     rm            Remove one or more containers
     rmi           Remove one or more images
     rmp           Remove one or more pods
     pods          List pods
     start         Start one or more created containers
     info          Display information of the container runtime
     stop          Stop one or more running containers
     stopp         Stop one or more running pods
     update        Update one or more running containers
     stats         List container(s) resource usage statistics
     help, h       Shows a list of commands or help for one command

EOF
    exit 1
}

main() {
    [ $# -ge 1 ] || printUsage

    local cmd=$1

    case "${cmd}" in
    attach | containerAttach)
        containerAttach
        ;;

    create | containerCreate)
        shift 1
        containerCreate $*
        ;;

    exec)
        # FIXME(Shaohua):
        containerExec
        containerExecSync
        ;;
    containerExec)
        containerExec
        ;;
    containerExecSync)
        containerExecSync
        ;;

    images | imageList)
        imageList
        ;;

    inspect | containerStatus)
        shift 1
        containerStatus $*
        ;;

    inspecti | imageStatus)
        shift 1
        imageStatus $*
        ;;

    inspectp | sandboxStatus)
        sandboxStatus
        ;;

    logs | containerReopenLog)
        containerReopenLog
        ;;

    port-forward | containerPortForward)
        shift 1
        containerPortForward $*
        ;;

    ps | containerList)
        containerList
        ;;

    pull | imagePull)
        shift 1
        imagePull $*
        ;;

    runp | sandboxRun)
        shift 1
        sandboxRun $*
        ;;

    rm | containerRemove)
        shift 1
        containerRemove $*
        ;;

    rmi | imageRemove)
        shift 1
        imageRemove $*
        ;;

    rmp | sandboxRemove)
        shift 1
        sandboxRemove $*
        ;;

    pods | sandboxList)
        sandboxList
        ;;

    start | containerStart)
        shift 1
        containerStart $*
        ;;

    info | runtimeStatus)
        runtimeStatus
        ;;

    stop | containerStop)
        shift 1
        containerStop $*
        ;;

    stopp | sandboxStop)
        shift 1
        sandboxStop $*
        ;;

    update | containerUpdateResources)
        shift 1
        containerUpdateResources $*
        ;;

    containerUpdateRuntimeConfig)
        shift 1
        containerUpdateRuntimeConfig $*
        ;;

    stats)
        # FIXME(Shaohua):
        containerStats
        containerStatsList
        ;;
    containerStats)
        shift 1
        containerStats $*
        ;;
    containerStatsList)
        containerStatsList
        ;;

    imageFsInfo)
        imageFsInfo
        ;;

    help|h)
        printUsage
        ;;

    *)
        error "Unsupported cmd: ${cmd}"
        printUsage
        ;;
    esac
}

main $*
