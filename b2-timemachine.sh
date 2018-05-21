#!/bin/bash

#
#   Backblaze B2 Timemachine
#
#   Restores a folder from Backblaze B2 storage at specified timestamp.
#
#   `b2-restore.sh <rclone-b2-remote:Bucket/folder> --rollback=<timestamp>`
#   Format of timestamp: 2018-05-11 10:00:00
#
#   [--restore-to=<destination-folder>]
#   Specify restore folder. Defaults to current directory.
#
#   [--parallel=<number-of-processes>]
#   Defines number of rclone copyto processes allowed to run concurrently. Defaults to 10.
#

rclone_remote=$1
rclone_folder=$(basename $rclone_remote)
restore_to=${PWD}

COLOR_BLACK="\033[30m"
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_MAGENTA="\033[35m"
COLOR_CYAN="\033[36m"
COLOR_LIGHT_GRAY="\033[37m"
COLOR_DARK_GRAY="\033[38m"
COLOR_NORMAL="\033[39m"

# Loop through arguments and separate regular arguments from flags (--flag)
for var in "$@"; do

  # If starts with "--" then assign it to a flag array
  if [[ $var == --* ]]; then
    count=1+${#flags[*]}
    flags[$count]=$var
    # Else assign to an arguments array
  else
    count=1+${#arguments[*]}
    arguments[$count]=$var
  fi

done

# Loop through flags and assign to variable. A flag "--email=austin@anchor.host" becomes $email
for i in "${!flags[@]}"; do

  # replace "-" with "_" and remove leading "--"
  flag_name=`echo ${flags[$i]} | cut -c 3-`

  # detected flag contains data
  if [[ $flag_name == *"="* ]]; then
    flag_value=`echo $flag_name | perl -n -e '/.+?=(.+)/&& print $1'` # extract value
    flag_name=`echo $flag_name | perl -n -e '/(.+?)=.+/&& print $1'` # extract name
    flag_name=${flag_name/-/_}
    declare "$flag_name"="$flag_value" # assigns to $flag_flagname
  else
    # assigns to $flag_flagname boolen
    flag_name=${flag_name//-/_}
    declare "$flag_name"=true
  fi

done

if [[ "$parallel" == "" ]]; then

	# Number of concurrent Rclone copyto processes
	parallel=10

fi

run_command() {

  # Require rclone folder>
  if [[ ${rclone_folder} == "" ]]; then
    echo -e "${COLOR_RED}Error:${COLOR_NORMAL} Please specify a folder (ex: B2:Bucket/Folder)."
    exit 1
  fi

  # Require rollback days
  if [[ $rollback == "" ]]; then
    echo -e "${COLOR_RED}Error:${COLOR_NORMAL} Please specify --rollback=<timestamp>."
    exit 1
  fi

	# Calculate seconds between current datetime and rollback datetime
	current_timestamp_in_seconds=$(date +%s)
	rollback_timestamp_in_seconds=$(date -j -f '%Y-%m-%d %H:%M:%S' "$rollback" +%s)
	rollback_seconds=$(( $current_timestamp_in_seconds - $rollback_timestamp_in_seconds ))

  # Sync files as of rollback date
  rclone sync $rclone_remote $restore_to/$rclone_folder --transfers 32 --min-age ${rollback_seconds}s --fast-list -v

	# Calculate seconds between current datetime and rollback datetime
	current_timestamp_in_seconds=$(date +%s)
	rollback_timestamp_in_seconds=$(date -j -f '%Y-%m-%d %H:%M:%S' "$rollback" +%s)
	rollback_seconds=$(( $current_timestamp_in_seconds - $rollback_timestamp_in_seconds ))

  # Pull down list of B2 versions up until the rollback date from Rclone in json format. Append json to include the real file name.
  rclone lsjson $rclone_remote --b2-versions --include="*-v????-??-??-??????-???.*" --min-age ${rollback_seconds}s --fast-list --recursive | json -e 'this["RealName"] = this["Name"].replace(/-v\d{4}-\d{2}-\d{2}-\d{6}-\d{3}/i, "");this["RealPath"] = this["Path"].substring(0, this["Path"].lastIndexOf("/")) + "/" + this["RealName"];' > $restore_to/${rclone_folder}-b2-versions.json

  # Start a new js file to process file versions
  echo "files=" > $restore_to/$rclone_folder-process.js
  cat $restore_to/${rclone_folder}-b2-versions.json >> $restore_to/${rclone_folder}-process.js
  cat >> $restore_to/${rclone_folder}-process.js <<EOL
// Remove directories
files = files.filter(item => item.IsDir == false);

// Collect unique file names
unique = [...new Set(files.map(item => item.RealName))];

// Remove all versions except most recent per unique file name
unique.forEach(item => {
  grouped_files = files.filter(i => i.RealName == item);
  if(grouped_files.length > 1) {
    grouped_dates = [];
	grouped_files.forEach(version => grouped_dates.push(version.Name));
	grouped_dates.sort();
    // Mutiple versions found. Remove all except newest
    grouped_files.forEach(version => {
		if (version.Name == grouped_dates[grouped_dates.length - 1]) {
			// console.log("Keep " + version.Name);
        } else {
          index = files.findIndex(x => x.Name == version.Name);
          //console.log("Remove " + version.Name + " index " + index);
          files.splice(index, 1);
        }
    });
	grouped_dates = [];
  }
});

// Return filtered versions
console.log(JSON.stringify(files));
EOL

  # Filter out directories and all versions keeping only the most recent.
  filtered_versions=$(node $restore_to/${rclone_folder}-process.js | json)

  # Converts json to tab seperated data for bash to read
  files=$(echo $filtered_versions | json -Ma Path Name RealPath RealName -d '\t')
  rclone_copyto_source=()
  rclone_copyto_destination=()

  # Loops through each file and seperates into bash variables for processing
  while IFS=$'\t' read path name realpath realname; do
    to_check="$restore_to/${rclone_folder}/$realpath"

    if [[ ! -f $to_check ]]; then
      echo -e "Restoring version '${COLOR_GREEN}${name}${COLOR_NORMAL}' to '$realpath'"
      rclone_copyto_source+=("$rclone_remote/$path")
      rclone_copyto_destination+=("$restore_to/${rclone_folder}/$realpath")
    fi
  done <<< "$files"

}
run_command


rclone_copyto() {
  rclone copyto "$1" "$2" --b2-versions --fast-list
}

echo "Processing ${#rclone_copyto_source[@]} files using Rclone copyto"
parallel_sets=$((${#rclone_copyto_source[@]} / $parallel))
for parallel_set in `seq 0 $parallel_sets`; do

  set_needed=$(( $parallel_set * $parallel ))

  if [[ "$set_needed" -lt "${#rclone_copyto_source[@]}" ]]; then

    current_parallel=$(($parallel_set * $parallel))
		#echo "current: $current_parallel"
    last_parallel=$(($current_parallel + $parallel - 1))
		#echo "last: $last_parallel"

    for i in `seq $current_parallel $last_parallel`; do
      if [[ "$i" -lt "${#rclone_copyto_source[@]}" ]]; then
				echo -ne "#$(( $i + 1 )) "
        rclone_copyto "${rclone_copyto_source[$i]}" "${rclone_copyto_destination[$i]}" &
      fi
    done

    wait

  fi

done
