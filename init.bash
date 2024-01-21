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
  echo "Error fetching '$1':"
  echo "$2"
  echo "Exiting."
  exit 1
}

remote_base=https://raw.githubusercontent.com/jetzig-framework/jetzig/main/src/init

objects=(
  'build.zig'
  'build.zig.zon'
  'src/main.zig'
  'src/app/views/index.zig'
  'src/app/views/index.zmpl'
  'src/app/views/quotes.zig'
  'src/app/views/quotes/get.zmpl'
  'src/app/config/quotes.json'
  'public/jetzig.png'
  '.gitignore'
)

for object in "${objects[@]}"
do
  printf "Creating output: ${object} "
  url="${remote_base}/${object}"
  mkdir -p "$(dirname "${project_path}/${object}")"
  set +e
  output=$(curl -s --fail --output "${project_path}/${object}" "${url}" 2>&1)
  set -e
  if (($?))
  then
    do_exit "${url}" "${output}"
  else
    echo "✅"
  fi
done

sed -i.bak -e "s,%%project_name%%,${project},g" "${project_path}/build.zig"
rm "${project_path}/build.zig.bak"
sed -i.bak -e "s,%%project_name%%,${project},g" "${project_path}/build.zig.zon"
rm "${project_path}/build.zig.zon.bak"

echo
echo "Finished creating new project in: ${project_path}"
echo
echo "Run your new project:"
echo
echo "  cd '${project_path}'"
echo '  zig build run'
echo
echo "Welcome to Jetzig. ✈️🦎 "
echo
