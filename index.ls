do # Require
  mongodb = require 'mongodb'
  MongoClient = mongodb.MongoClient
  _ = require 'prelude-ls-extended'
  async = require 'async'
  request = require 'request'
  fs = require 'fs'
  Path = require 'path'
  Url = require 'url'

do # Globals
  db = collection = dbConfig = null
  queues = {}
  defaultQueueConfig = {priority:0, limit:0, rateLimit:0, rateInterval:0, attempts:1, backoff:0, delay:0, duration:60*60, url:null, method:'POST', onSuccessDelete:false}
  jobValidation = {data:'obj', type:'str', priority:'int', attempts:'+int', backoff:'', delay:'int', url:'str', method:'str', batchId:'_id', parentId:'_id', isOnBatchComplete:'bool', onSuccessDelete:'bool', onComplete:'obj'}

class Job
  (@model={}) ->
    @data = @model.data
    @queue = queues[@model.type]

  option:-> | @model[it]? => that | otherwise @queue.options[it]
  update:(data, next) !-> @model import data; collection.update {_id:@model._id}, {$set:data}, next

  setState:(state, next=!->) !->
    # If we're changing the state, we're finishing processing a job
    # Hanging job failure, then the job finishing can trigger this twice for 1 job
    if @model.state isnt state => @queue.processingCount -= 1

    updateData = {}
    if state is 'failed'
      updateData.failedAttempts = (@model.failedAttempts or 0) + 1
      if (@option 'attempts') <= 0 or updateData.failedAttempts < @option 'attempts'
        state = 'pending'
        # First check backoff, maybe we need to delay it instead
        backoff = @option 'backoff'
        backoffType = typeof! backoff
        if (backoffType is 'Number' and backoff > 0) or (backoffType is 'String')
          state = 'delayed'
          if backoffType is 'String'
            try
              # For eval
              attempt = updateData.failedAttempts; doc = @model
              backoffValue = Number eval backoff
            catch e
              # If eval fails, mark the request as killed
              # TODO: log why it died e.message
              backoffValue = 0
              state = 'killed'
          else backoffValue = backoff
          updateData.delayTil = Date.now! + backoffValue * 1000

    # Not sure why this code was here before? Setting it to killed sounds fine
    # if state is 'killed' => state = 'failed'

    err <~! @update (updateData import {state})

    # insert onComplete job if exists
    <~! (next) !~>
      if @model.onComplete and state in <[killed failed success]>
        createJob (@model.onComplete import {batchId:@model.batchId, parentId:@model._id}), next
      else next!

    # check batch finish
    <~! (next) !~>
      if @model.batchId and not @model.isOnBatchComplete and state in <[killed failed success]>
        @checkBatchFinish next
      else next!

    if state is 'success' and @option 'onSuccessDelete' => @delete!

    next err

  checkBatchFinish:(next=!->) !->
    err, count <~! collection.find {batchId:@model.batchId, state:{$nin:<[killed failed success]>}, isOnBatchComplete:{$ne:true}} .count
    if count is 0
      err <-! collection.update {batchId:@model.batchId, +isOnBatchComplete}, {$set:{delayTil:Date.now!}}, {multi:true}
      promoteJobs!
      next!
    else next!
  success:(result, job) !->
    console.log 'done success: ', result
    <~! (next) !~>
      updateData = {}
      if @model.progress? => updateData.progress = 100
      if result? => updateData.result = result
      if not _.Obj.empty updateData => @update updateData, next else next!
    <~! (next) !~>
      if job => createJob (job import {batchId:@model.batchId, parentId:@model._id}), next else next!
    err <~! @setState 'success'
    @queue.processPendingJobs!
  error:(msg, o={+process}) !->
    m = 'Error'; if msg => m += ": #msg"
    @log m; console.log 'done', m
    err <~! @setState 'failed'
    if o.process => @queue.processPendingJobs!
  systemError:(msg, o) !-> @error "SYSTEM ERROR: #msg", o
  retry:(msg) !->
    m = 'Retry'; if msg => m += ": #msg"
    @log m; console.log 'done', m
    @setState 'pending'
  kill:(msg) !->
    m = 'Killed'; if msg => m += ": #msg"
    @log m; console.log 'done', m
    @setState 'killed'
  delete:!->
    err <~! collection.remove {_id:@model._id}
    if err => @log 'Delete Failed'
  log:(message, next=!->) !-> collection.update {_id:@model._id}, {$push:{logs:{t:Date.now!, m:message}}}, next
  progress:(progress, next=!->) !-> @update {progress}, next

  # This is only here to expose createJob to config file
  create:createJob
  getBatchJobs:(next) !->
    err, docs <~! (collection.find {batchId:@model.batchId, isOnBatchComplete:{$ne:true}})toArray
    if err => return @systemError err
    jobs = for data in docs => new Job data
    next jobs
  getParentJob:(next) !->
    err, docs <~! (collection.find {_id:@parentId})toArray
    if err => return @systemError err
    job = new Job docs.0
    next job

Job.create = (model, next) !->
  model.type ?= 'default'
  model.state = 'pending'
  delay = model.delay or queues[model.type]?options?delay or 0
  if delay > 0
    model.state = 'delayed'
    model.delayTil = Date.now! + delay * 1000
  else if delay < 0
    model.state = 'delayed'

  # Remove void values before inserting
  for k, v of model => if v is void => delete model[k]

  console.log model
  err, r <-! collection.insertOne model
  console.log 'inserted new job to:', model.type
  job = new Job r.ops.0
  next err, job

class Queue
  (@type, options={}) ->
    @updateConfig options
    @processingCount = 0
    # To get things started if there's jobs waiting when we start the server
    @processPendingJobs!

  updateConfig:(options) !-> @options = ({} import dbConfig.queues.default) import options
  processPendingJobs:!->
    # Not sure if this is necessary
    if @processingCount < 0 => @processingCount = 0
    console.log 'processingCount:', @type, @processingCount

    # If we're at queue limit, get out of here
    return if @options.limit > 0 and @processingCount >= @options.limit
    @processingCount += 1

    # Rate limiting
    # TODO: This isn't atomic, should be part of the find & modify
    <~! (next) !~>
      if @options.rateLimit > 0 and @options.rateInterval > 0
        err, count <~! collection.find {lastProcessed:{$gte:Date.now! - @options.rateInterval * 1000}} .count
        if count < @options.rateLimit => next! else return @processingCount -= 1
      else next!

    # Get pending job while refreshing its resetAt time. Duration cannot be a job level setting because of this
    resetAt = Date.now! + (@options.duration or 0) * 1000
    err, r <~! collection.findOneAndUpdate {type:@type, state:'pending'}, {$set:{state:'processing', lastProcessed:Date.now!, resetAt}}, {sort:[['priority', 'desc']], -returnOriginal}
    doc = r.value
    job = (if doc => new Job doc else null)

    # We didn't find anything, get out of here
    return @processingCount -= 1 if not job

    # Process the job we found
    @process job

    # Loop, looking for more jobs
    @processPendingJobs!

  process:(job) !->
    url = job.option 'url'
    type = job.option 'type'

    if url
      console.log 'pushing job to:', url
      err, res, body <-! request {url, method:(job.option 'method'), json:job.model}
      console.log 'url done!'
      return job.kill err if err
      msg = "#{res.statusCode}#{if body => ": #body" else ""}"
      if res.statusCode is 200 => job.success body
      else if res.statusCode is 202 => job.retry msg
      else if res.statusCode is 403 => job.kill msg
      else job.systemError msg
    else if configObject.process[type]
      console.log 'config process found:', type
      that job
    else console.log 'no process defined for this job:', job




# Get dbConfig, or create it if doesn't exist
reloadDbConfig = !->
  err, _dbConfig <-! ((db.collection 'config')find!limit 1)next
  dbConfig := _dbConfig
  if not dbConfig?
    dbConfig := {queues:{default:defaultQueueConfig}}
    err, r <-! db.collection 'config' .insertOne dbConfig

  # Push dbConfig into queues, or update existing queues
  for k, v of dbConfig.queues => if queues[k]? => that.updateConfig v else queues[k] = new Queue k, v

# Used to create a job, or batch of jobs, and check to process it instantly
createJob = (obj, next=!->) !->
  validateJobErr = !->
    return "Job must be an object" if typeof! it isnt 'Object'
    for k, v of it
      if v is void => delete it[k]; continue
      validation = jobValidation[k]
      return "Unknown job key `#k`" if not validation?

      # If it's supposed to be an _id but you're giving a string, try to turn it into an _id
      if validation is '_id' and typeof! v is 'String' => it[k] = v = mongodb.ObjectID v

      switch validation
      | 'bool' => return "Key `#k` must be an bool" if typeof! v isnt 'Boolean'
      | 'int' => return "Key `#k` must be an int" if v isnt parseInt v
      | '+int' => return "Key `#k` must be a positive int" if v isnt parseInt v or v <= 0
      | 'str' => return "Key `#k` must be a str" if typeof! v isnt 'String'
      | 'obj' => return "Key `#k` must be an obj" if typeof! v isnt 'Object'
      | '_id' => return "Key `#k` must be an ObjectId" if typeof! v isnt 'Object'

  isArray = _.isArray obj
  if isArray or obj.jobs?
    jobs = if isArray => obj else obj.jobs
    batchId = obj.batchId
    onComplete = obj.onComplete
    if onComplete?
      if not _.isArray onComplete => onComplete = [onComplete]
      for job in onComplete
        job.delay = -1
        job.isOnBatchComplete = true
        jobs.push job

    return next 'Jobs must be an array' if typeof! jobs isnt 'Array'
    return next 'Array of jobs is empty' if _.empty jobs
    for job in jobs when validateJobErr job => console.log 'validateJobErr', that; return next that
    # If there is no batchId assigned, then create one
    <-! (next) !->
      if not batchId
        err, r <-! db.collection 'batches' .insertOne {}
        batchId := r.insertedId
        next!
      else next!
    err <-! async.each jobs, (model, next) !-> Job.create (model import {batchId, obj.parentId}), next
    for type in _.unique _.map (.type), jobs => queues[type]?processPendingJobs!
    next err
  else
    if validateJobErr obj => console.log 'validateJobErr', that; return next that
    err, job <-! Job.create obj
    if job.model.state is 'pending' => job.queue?processPendingJobs!
    next err

# Promote delayed jobs, reset hanging jobs, recheck rate limited queues
promoteJobs = !->
  processed = []
  # Recheck rate limited queues
  for , queue of queues when queue.options.rateLimit > 0 and queue.options.rateInterval > 0
    processed.push queue.type
    queue.processPendingJobs!

  # Mark deplayed jobs as pending to start them
  err, delayedDocs <-! (collection.find {state:'delayed', delayTil:{$lte:Date.now!}}, {_id:true, type:true})toArray
  _ids = _.map (._id), delayedDocs
  err <-! collection.updateMany {_id:{$in:_ids}}, {$set:{state:'pending'}}

  # Throw errors on hanging jobs
  # We recheck processing each failed job 1 by 1 in systemError because the processPendingJobs
  # doesn't always pick them up because of async
  err, hangingDocs <-! (collection.find {state:'processing', resetAt:{$lte:Date.now!}})toArray
  for model in hangingDocs
    job = new Job model
    job.systemError 'Hanging job detected. Job is processing for too long'

  # Start processing these new deplayed and hanging jobs
  docs = delayedDocs ++ hangingDocs
  return if _.empty docs
  for type in _.unique _.reject (in processed), _.map (.type), docs => queues[type]?processPendingJobs!

do # Init
  # Get config file path from first command line argument
  configFile = process.argv.2

  # If file doesn't exist throw error
  exists = fs.existsSync configFile
  if not exists => throw 'Config file must exist'

  # Require the config file as a module, if that fails throw the error
  configFileAbsPath = Path.join process.cwd!, configFile
  configObject = try require configFileAbsPath catch e => throw e

  # Config validation / default config settings
  if not configObject.connect => throw 'connect string is required in config file'
  configObject.port ?= 5672
  configObject.promoteInterval ?= 5000
  configObject.process ?= {}

  # DB
  err, _db <-! MongoClient.connect configObject.connect
  console.log 'Connected'
  db := _db; collection := db.collection 'jobs'

  reloadDbConfig!

  # Ensure index
  <-! collection.createIndexes [{key:{type:1}}, {key:{state:1}}, {key:{priority:1}}, {key:{delayTil:1}}, {key:{resetAt:1}}, {key:{batchId:1}}, {key:{parentId:1}}]

  if configObject.promoteInterval > 0
    setInterval promoteJobs, configObject.promoteInterval
    promoteJobs!

  do # Init JSON API
    express = require 'express'
    app = express!
    bodyParser = require 'body-parser'
    app.use bodyParser.json!
    app.use express.static "#{process.cwd!}/public"
    app.use (req, res, next) !-> res.setHeader 'Access-Control-Allow-Origin', '*'; next!
    router = express.Router!
    router.all '/job', (req, res) !-> createJob req.body, (err) !-> res.status (if err => 500 else 200); res.send err
    router.all '/job/update', (req, res) !->
      err, model <-! ((collection.find {_id:mongodb.ObjectID req.body._id})limit 1)next
      job = new Job model
      if req.body.progress => job.progress that
      res.send ''
    router.all '/info', (req, res) !->
      _where = req.body.where or {}
      err, pending <-! (collection.find _where import {state:'pending'})count
      err, processing <-! (collection.find _where import {state:'processing'})count
      err, delayed <-! (collection.find _where import {state:'delayed'})count
      err, success <-! (collection.find _where import {state:'success'})count
      err, failed <-! (collection.find _where import {state:'failed'})count
      err, killed <-! (collection.find _where import {state:'killed'})count
      res.send do
        counts:{pending, processing, delayed, success, failed, killed}
        queues:_.keys queues
    router.all '/view', (req, res) !->
      err, docs <-! (collection.find req.body.where, {limit:100, fields:{+type, +state, +url, +data, +logs, +progress, +result}, sort:[['_id', 'desc']]} import req.body)toArray
      for doc in docs
        doc.timestamp = doc._id.getTimestamp!getTime!
        delete doc._id
      res.send docs
    router.all '/reload-db-config', (req, res) !-> reloadDbConfig!; res.send ''
    app.use '/', router
    app.listen configObject.port
