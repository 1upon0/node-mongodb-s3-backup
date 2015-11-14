# Forked from https://github.com/theycallmeswift/node-mongodb-s3-backup

fs = require('fs')
async = require('async')
exec = require('child_process').exec
spawn = require('child_process').spawn
path = require('path')
glob = require('glob')
crypto = require('crypto')
###*
# log
#
# Logs a message to the console with a tag.
#
# @param message  the message to log
# @param tag      (optional) the tag to log with.
###

log = (message, tag) ->
  util = require('util')
  color = require('cli-color')
  tag = tag || 'info'
  tags =
    error: color.red.bold
    warn: color.yellow
    info: color.cyanBright
  currentTag = tags[tag] || (str) ->
    str
  util.log((currentTag('[' + tag + '] ') + message).replace(/(\n|\r|\r\n)$/, ''))
  return

###*
# getArchiveName
#
# Returns the archive name in database_YYYY_MM_DD.tar.gz format.
#
# @param databaseName   The name of the database
###

getArchiveName = (databaseName) ->
  date = new Date
  datestring = [
    databaseName
     new Date().toISOString()[...-5].replace(/[^T0-9]/g,'-')
  ]
  datestring.join('_') + '.tar.gz'

### removeRF
#
# Remove a file or directory. (Recursive, forced)
#
# @param target       path to the file or directory
# @param callback     callback(error)
###

removeRF = (target, callback) ->
  callback = callback or ->
  fs.exists(target, (exists) ->
    if !exists
      return callback(null)
    log('Removing ' + target, 'info')
    exec('rm -rf ' + target, callback)
    return
  )
  return

### mkdir
#
# Creates a directory.
#
# @param target       path to the new directory
# @param callback     callback(error)
###

mkdir = (target, callback) ->
  callback = callback or ->
  fs.exists(target, (exists) ->
    if !exists
      log('Creating folder ' + target, 'info')
      exec('mkdir ' + target, ()->callback())
    return
  )
  return

###*
# mongoDump
#
# Calls mongodump on a specified database.
#
# @param options    MongoDB connection options [host, port, username, password, db]
# @param directory  Directory to dump the database to
# @param callback   callback(err)
###

mongoDump = (options, directory, callback) ->
  callback = callback or ->
  mongoOptions = [
    '-h'
    options.host + ':' + options.port
    '-o'
    directory
  ]
  if options.db
    mongoOptions.push '-d'
    mongoOptions.push options.db
  if options.username and options.password
    mongoOptions.push '-u'
    mongoOptions.push options.username
    mongoOptions.push '-p'
    mongoOptions.push options.password
  log('Starting mongodump of ' + options.backupName, 'info')
  mongodump = spawn('mongodump', mongoOptions)
  mongodump.stdout.on('data', (data) ->
    log data
    return
  )
  mongodump.stderr.on('data', (data) ->
    log data, 'error'
    return
  )
  mongodump.on('exit', (code) ->
    if code == 0
      log 'mongodump executed successfully', 'info'
      callback(null)
    else
      callback(new Error('Mongodump exited with code ' + code))
    return
  )
  return

###*
# compressDirectory
#
# Compressed the directory so we can upload it to S3.
#
# @param directory  current working directory
# @param input     path to input file or directory
# @param output     path to output archive
# @param callback   callback(err)
###

compressDirectory = (cwd, input, output, callback) ->
  tar = undefined
  tarOptions = undefined
  callback = callback or ->
  tarOptions = [
    '--force-local'
    '-zcf'
    output
    input
  ]
  log('Starting compression of ' + input + ' into ' + output, 'info')
  tar = spawn('tar', tarOptions, cwd: cwd)
  tar.stderr.on('data', (data) ->
    log(data, 'error')
  )
  tar.on('exit', (code) ->
    if code == 0
      log('Successfully compressed', 'info')
      callback null
    else
      callback new Error('Tar exited with code ' + code)
  )
  return

compressFiles = (cwd, files, output, callback) ->
  tar = undefined
  tarOptions = undefined
  callback = callback or ->
  tarOptions = [
    '--no-recursion'
    '--force-local'
    '-zcf'
    output
    '-T'
    '-'
  ]
  log('Starting compression of '+files.length+' files into ' + output, 'info')
  tar = spawn('tar', tarOptions, cwd: cwd)
  for file in files
    if file[0]=='-'
      tar.stdin.write('--add-file=')
    tar.stdin.write(file+'\n')
  tar.stdin.end();
  tar.stderr.on('data', (data) ->
    log(data, 'error')
  )
  tar.on('exit', (code) ->
    if code == 0
      log('Successfully compressed', 'info')
      callback null
    else
      callback new Error('Tar exited with code ' + code)
  )
  return

###*
# sendToS3
#
# Sends a file or directory to S3.
#
# @param options   s3 options [key, secret, bucket]
# @param directory directory containing file or directory to upload
# @param target    file or directory to upload
# @param callback  callback(err)
###

sendToS3 = (options, directory, target, callback) ->
  knox = require('knox')
  sourceFile = path.join(directory, target)
  s3client = undefined
  destination = options.destination or '/'
  if(destination[0]!='/')
    destination='/'+destination;
  if(destination[-1..]!='/')
    destination=destination+'/';
  headers = {}
  callback = callback or ->
  s3client = knox.createClient(options)
  if options.encrypt
    headers = 'x-amz-server-side-encryption': 'AES256'
  destinationFile = destination + target
  log 'Attemping to upload ' + sourceFile + ' to the ' + options.bucket + ' s3 bucket into ' + destinationFile
  s3client.putFile(sourceFile, destinationFile, headers, (err, res) ->
    if err
      return callback(err)
    res.setEncoding 'utf8'
    res.on('data', (chunk) ->
      if res.statusCode != 200
        log(chunk, 'error')
      else
        log(chunk)
    )
    res.on('end', (chunk) ->
      if res.statusCode != 200
        return callback(new Error('Expected a 200 response from S3, got ' + res.statusCode))
      log 'Successfully uploaded to s3'
      callback()
    )
  )
  return

###*
# sync
#
# Performs a mongodump on a specified database, gzips the data,
# and uploads it to s3.
#
# @param mongodbConfig   mongodb config [host, port, username, password, db]
# @param s3Config        s3 config [key, secret, bucket]
# @param callback        callback(err)
###

sync = (mongodbConfig, filesConfig, s3Config, callback) ->
  if !mongodbConfig.db
    mongodbConfig.backupName = 'all'
    log 'No database to be backed up is specified. Using backup name: ' + mongodbConfig.backupName
  else
    mongodbConfig.backupName = mongodbConfig.db
  tmpDir = path.join(require('os').tmpDir(), 's3_backup_'+crypto.randomBytes(8).toString('hex'))
  if(tmpDir[1...3]==':\\' &&  require('os').type().indexOf('Windows')!=-1)
    tmpDir=tmpDir[0...3]+'\\'+tmpDir[3..]
  console.log(tmpDir);
  dbArchiveName = getArchiveName('db_'+mongodbConfig.backupName)
  filesArchiveName = getArchiveName('files')
  files = []
  callback = callback or ->

  async.series([
    (cb)->mkdir(tmpDir,(err)->cb(err))
    async.apply(mongoDump, mongodbConfig, tmpDir+'/dump')
    async.apply(compressDirectory, tmpDir, 'dump', dbArchiveName)
    (cb)->
      if(!filesConfig.paths)
        log("No other files given for backup","info")
        return cb()
      async.map(filesConfig.paths,glob,(err,filesList)->
        if(err)
          return cb(err);
        files=[].concat(filesList...)
        if(!files.length)
          log("No files matched!","warning");
        cb();
      );
    (cb)->
      if(!files.length)
        return cb()
      compressFiles('./',files, tmpDir+'/'+filesArchiveName,cb)
    (cb)->
      try
        async.parallel([
          (cb)->sendToS3(s3Config, tmpDir, dbArchiveName, (err)->cb(err))
          (cb)->
            if(!files.length)
              return cb()
            sendToS3(s3Config, tmpDir, filesArchiveName, (err)->cb(err))
        ],(err)->cb(err)
        )
      catch e
        cb(e)
  ], (err) ->
    if err
      log(err, 'error')
    else
      log 'Successfully done'
    # cleanup folders
    removeRF(tmpDir,(moreErr)->callback(err || moreErr))
  )

module.exports ={
  sync: sync
  log: log
}