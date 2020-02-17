#!/usr/bin/env bash

function convert_docker_mapping() {
  # Supposed to use for mapping docker-in-docker paths for -v or --mount usage 
  # Usage:
  #  convert_docker_mapping "/source/path:/dest/path,/source2/path:/dest2/path" "/source/path/file_to_bind"
  dir_mappings=${1//,/ }
  target_path=$2
  result=$target_path
  for el in $dir_mappings; do
    src=${el//:*}
    dst=${el//*:}
    if [[ "${target_path}" == "${src}" ]]; then
      result=$dst
      break
    elif [[ ${target_path} == "${src}/"* ]]; then
      result=${target_path/$src/$dst}
      break
    fi
  done
  echo $result
}
