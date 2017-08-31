#!/usr/bin/env bash

# AWS Constants
AWS_ECS_CONTAINER_NAME_KEY="com.amazonaws.ecs.container-name"

# AWS Docker Image
AWS_DOCKER_IMAGE="garland/aws-cli-docker"

# FreeSWITCH Constants. These should match the valus in Dockerrun.aws.json
FREESWITCH_CONTAINER_NAME="freeswitch"
S3_PATH_KEY="org.somleng.freeswitch.recordings.s3-path"
CONTAINER_PATH_KEY="org.somleng.freeswitch.recordings.container-path"

# Local Constants
MOUNTED_CONTAINER_PATH="/data/freeswitch-mounted"
SCRATCH_SPACE="/data/scratch_space"

freeswitch_container_id=$(docker ps -aqf "label=${AWS_ECS_CONTAINER_NAME_KEY}=${FREESWITCH_CONTAINER_NAME}")

if [[ -n "$freeswitch_container_id" ]]; then
  echo "Found FreeSWITCH Container: ${freeswitch_container_id}"

  s3_path=$(docker inspect --format "{{ index .Config.Labels \"${S3_PATH_KEY}\"}}" $freeswitch_container_id)

  echo "S3 Path is: ${s3_path} set from ${S3_PATH_KEY} in Dockerun.aws.json"

  if [ "$1" = '--all' ]; then
    # sync all volumes
    echo "--all flag passed. Syncing all volumes"

    # get a list of volume names and put into $docker_volumes
    _x=$(docker volume ls --format "{{.Name}}")
    readarray -t docker_volumes <<<"$_x"

    # mount each volume as read only
    printf -v docker_volumes_command -- "-v %s:${MOUNTED_CONTAINER_PATH}/%s:ro " "${docker_volumes[@]}"

    # flatten the files and sync them to s3
    docker run --rm $docker_volumes_command $AWS_DOCKER_IMAGE /bin/sh -c "mkdir -p $SCRATCH_SPACE && find $MOUNTED_CONTAINER_PATH -type f -exec cp {} $SCRATCH_SPACE \; && aws s3 sync ${SCRATCH_SPACE} ${s3_path} --sse"
  else
    # Sync only current volume

    # get the container path for the FreeSWITCH container
    mounted_container_path=$(docker inspect --format "{{ index .Config.Labels \"${CONTAINER_PATH_KEY}\"}}" $freeswitch_container_id)

    echo "Syncing FreeSWITCH volume at ${mounted_container_path} set from ${CONTAINER_PATH_KEY} in Dockerrun.aws.json"

    # mount the volume as read only and sync it with s3
    docker run --rm --volumes-from $freeswitch_container_id:ro $AWS_DOCKER_IMAGE aws s3 sync $mounted_container_path $s3_path --sse
  fi
fi