#!/bin/bash

printf 'Enter project name (default: "jetzig-demo"): '
read -a project
if [ -z "${project}" ]
then
  project="jetzig-demo"
fi

pwd="$(pwd)"
printf "Enter project parent directory (default: \"${pwd}\"): "
read -a dir
if [ -z "${dir}" ]
then
  dir="${pwd}"
fi


set -eu

project_path="${dir}/${project}"
echo
echo "Initializing new project in: ${project_path}"

mkdir -p "${project_path}"

do_exit () {
  echo "Error fetching $1 - exiting."
  exit 1
}

remote_base=https://raw.githubusercontent.com/jetzig-framework/jetzig/main/src/init

objects=(
  build.zig
  build.zig.zon
  src/main.zig
  src/app/views/index.zig
)

for object in "${objects[$@]}"
do
  echo "Creating output: ${object}"
  url="${remote_base}/${object}"
  curl -qs --fail --output "${project_path}/${object}" "${url}" || do_exit "${url}"
done

echo "Project initialization complete. Welcome to Jetzig. ✈️🦎 "
