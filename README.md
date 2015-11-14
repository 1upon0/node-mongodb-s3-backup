# Node.js - MongoDB and Files backup to Amazon S3

This is a package that makes backing up your mongo databases and local files to S3 simple.
The binary file is a node cronjob that runs at midnight every day and backs up
the database and files (wildcards/globs supported) specified in the config file.

PS: In cronjob mode, the process runs forever. You can use `nohup s3_backup <path_to_config.json> 2>&1 > /dev/null &` to send the process to background forever and supress output.
You can also use your own scheduler and pass `-n` as the first argument to `s3_backup` to run the backup and exit immediately.

PS: This package has been forked from <https://github.com/theycallmeswift/node-mongodb-s3-backup> to add support for custom files to the backup.

## Installation

    npm install s3_backup -g

## Configuration

To configure the backup, you need to pass the binary a JSON configuration file.
There is a sample configuration file supplied in the package (`config.sample.json`).
The file should have the following format:

    {
      "mongodb": {
        "host": "localhost",
        "port": 27017,
        "username": false,
        "password": false,
        "db": "database_to_backup"
      },
      "files": {
        paths: ["test_dir/**/*","images/*.jpg","onefile.txt"]
      },
      "s3": {
        "key": "your_s3_key",
        "secret": "your_s3_secret",
        "bucket": "s3_bucket_to_upload_to",
        "destination": "/",
        "encrypt": true,
        "region": "ap-southeast-1" //s3_region_to_use
      },
      "cron": {
        "time": "11:59",
      }
    }

All options in the "s3" object will be directly passed to knox, therefore, you can include any of the options listed [in the knox documentation](https://github.com/LearnBoost/knox#client-creation-options "Knox README").

### Crontabs

You may optionally substitute the cron "time" field with an explicit "crontab"
of the standard format `0 0 * * *`.

      "cron": {
        "crontab": "0 0 * * *"
      }

*Note*: The version of cron that we run supports a sixth digit (which is in seconds) if
you need it.

### Timezones

The optional "timezone" allows you to specify timezone-relative time regardless
of local timezone on the host machine.

      "cron": {
        "time": "00:00",
        "timezone": "America/New_York"
      }

You must first `npm install time` to use "timezone" specification.

## Running

To start a long-running process with scheduled cron job:

    s3_backup <path to config file>

To execute a backup immediately and exit:

    s3_backup -n <path to config file>
