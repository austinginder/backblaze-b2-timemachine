# Backblaze B2 Time Machine

## Description
Restores a folder from Backblaze B2 storage at specific point in the past.

## Limitations

- This script is pretty basic. It can't tell if a B2 version is needed. That means restores may include unnecessary previous file versions.
- This is not a real time machine. Will not modify the space-time continuum.

## Getting started
This script uses a few other command line apps in order to work.

- [Node](https://nodejs.org/en/download/) `brew install node`
- [JSON](https://github.com/trentm/json) `npm install -g json`
- [Rclone](https://rclone.org/downloads/) `curl https://rclone.org/install.sh | sudo bash`

Rclone needs configured with a Backblaze B2 account. B2 bucket needs [file versions](https://www.backblaze.com/b2/docs/file_versions.html) enabled.

- Run `rclone config` and add B2 account.
- Download script and assign execute permission `chmod +x b2-timemachine.sh`

## Usage

Example: Restores folder as of May 1st, 2018 at 10am.

`b2-timemachine.sh rclone-b2:Bucket/folder --rollback="2018-05-01 10:00:00"`

## Optional arguments

`--restore-to=<destination-folder>`

Specify restore folder. Defaults to current directory.

`--parallel=<number-of-processes>`

Defines number of rclone copyto processes allowed to run concurrently. Defaults to 10.

## Changelog

### [0.1.0] - 2018-05-21
- Initial release. Bash attempt to solve B2 time machine restore based on official Rclone discussion [#2126](https://github.com/ncw/rclone/issues/2126).

## License
This is free software under the terms of MIT the license (check the LICENSE file included in this package).
