do # Require
	mongodb = require 'mongodb'
	MongoClient = mongodb.MongoClient
	_ = require 'prelude-ls-extended'
	async = require 'async'
	request = require 'request'
	idkfile = try require './idkfile' catch => {}

do # Globals
	db = collection = config = null
	defaultQueueSettings = {priority: 0, limit: 0, rateLimit: 0, rateInterval: 0, attempts: 1, backoff: 0, delay: 0, duration: 60*60, url: null, method: 'POST'}
	jobValidation = {data: 'obj', type: 'str', priority: 'int', attempts: '+int', backoff: '', delay: 'int', duration: '+int', url: '', method: 'str', batchId: '_id'}

class Job
	(@model={}) ->
		@data = @model.data
		@queue = queues[@model.type]

	option: -> | @model[it]? => that | otherwise @queue.options[it]
	update: (data, next) !-> @model import data; collection.update {_id: @model._id}, {$set: data}, next

	setState: (state, next=!->) !->
		# Apparently everytime we setState we want to decrement the processingCount
		@queue.processingCount -= 1

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
					# For eval
					attempt = updateData.failedAttempts; doc = @model
					if backoffType is 'String'
						try eval backoff
						catch e
							# If eval fails, mark the request as killed
							# TODO: log why it died e.message
							backoffValue = 0
							state = 'killed'
					else backoffValue = backoff
					updateData.delayTil = Date.now! + backoffValue * 1000

		if state is 'killed' => state = 'failed'

		err <~! @update updateData import {state}
		<~! (next) !~>
			if @model.batchId and state in <[failed successful]>
				@checkBatchFinish next
			else next!
		next err

	checkBatchFinish: (next=!->) !->
		err, count <~! collection.find {batchId: @model.batchId, state: {$nin: <[failed successful]>}} .count
		if count is 0
			err, batch <~! db.collection 'batch' .findOne {_id: @model.batchId}
			if batch.onComplete => createJob batch.onComplete, next
			else next!
		else next!
	success: (res, job) !->
		console.log 'done success: ', res
		<~! (next) !~>
			updateData = {}
			if @model.progress? => updateData.progress = 100
			if res? => updateData.result = res
			if not _.Obj.empty updateData => @update updateData, next else next!
		err <~! @setState 'successful'
		<~! (next) !~>
			if job => createJob job, next else next!
		@queue.processPendingJobs!
	error: (res) !->
		@log "Error: #{res}"; console.log 'done error: ', res
		err <~! @setState 'failed'
		@queue.processPendingJobs!
	retry: (res) !->
		@log 'Retry'; console.log 'done retry: ', res
		@setState 'pending'
	kill: (res) !->
		@log 'Killed'; console.log 'done kill: ', res
		@setState 'killed'
	log: (message, next=!->) !-> collection.update {_id: @model._id}, {$push: {logs: {t:Date.now!, m:message}}}, next
	progress: (progress, next=!->) !-> @update {progress}, next

	# This is only here to expose createJob to idkfile
	create: createJob
Job.create = (model, next) !->
	model.type ?= 'default'
	model.state = 'pending'
	delay = model.delay or queues[model.type]?options?delay or 0
	if delay > 0
		model.state = 'delayed'
		model.delayTil = Date.now! + delay * 1000
	duration = model.duration or queues[model.type]?options?duration or 0
	model.resetAt = Date.now! + duration * 1000
	console.log model
	err, docs <-! collection.insert model
	console.log 'inserted new job to:', model.type
	job = new Job docs.0
	next err, job

class Queue
	(@type, options={}) ->
		@updateConfig options
		@processingCount = 0
		# To get things started if there's jobs waiting when we start the server
		@processPendingJobs!

	updateConfig: (options) !-> @options = ({} import config.queues.default) import options
	processPendingJobs: !->
		console.log 'processingCount:', @type, @processingCount

		# If we're at queue limit, get out of here
		return if @options.limit > 0 and @processingCount >= @options.limit
		@processingCount += 1

		# Rate limiting
		# TODO: This isn't atomic, should be part of the find & modify
		<~! (next) !~>
			if @options.rateLimit > 0 and @options.rateInterval > 0
				err, count <~! collection.find {lastProcessed: {$gte: Date.now! - @options.rateInterval * 1000}} .count
				if count < @options.rateLimit => next! else return @processingCount -= 1
			else next!

		# Get pending job
		err, doc <~! collection.findAndModify {type: @type, state: 'pending'}, [['priority', 'desc']], {$set: {state: 'processing', lastProcessed: Date.now!}}, {new: true}
		job = (if doc => new Job doc else null)

		# We didn't find anything, get out of here
		return @processingCount -= 1 if not job

		# Process the job we found
		@process job

		# Loop, looking for more jobs
		@processPendingJobs!

	process: (job) !->
		if idkfile[job.option 'type'] => return that job

		console.log 'pushing job to:', job.option 'url'
		err, res, body <-! request {url: (job.option 'url'), method: (job.option 'method'), json: job.model}
		console.log 'Done!'
		return job.error err if err
		if res.statusCode is 200 => job.success body
		else if res.statusCode is 202 => job.retry!
		else if res.statusCode is 403 => job.kill!
		else job.error res.statusCode + (if body => ": #body" else '')




# Get config, or create it if doesn't exist
updateConfig = !->
	err, _config <-! db.collection 'config' .findOne
	config := _config
	if not config?
		config := {queues: default: defaultQueueSettings}
		err, docs <-! db.collection 'config' .insert config

	# Push config into queues, or update existing queues
	for k, v of config.queues => if queues[k]? => that.updateConfig v else queues[k] = new Queue k, v

# Used to create a job, or batch of jobs, and check to process it instantly
createJob = (obj, next=!->) !->
	validateJobErr = !->
		return "Job must be an object" if typeof! it isnt 'Object'
		for k, v of it
			validation = jobValidation[k]
			return "Unknown job key `#k`" if not validation?
			switch validation
			| 'int' => return "Key `#k` must be an int" if v isnt parseInt v
			| '+int' => return "Key `#k` must be a positive int" if v isnt parseInt v or v <= 0
			| 'str' => return "Key `#k` must be a str" if typeof! v isnt 'String'
			| 'obj' => return "Key `#k` must be an obj" if typeof! v isnt 'Object'
			| '_id' => return "Key `#k` must be an ObjectId" if typeof! v isnt 'Object'

	isArray = _.isArray obj
	if isArray or obj.jobs?
		jobs = if isArray => obj else obj.jobs
		onComplete = if isArray => null else obj.onComplete
		batchId = if isArray => null else obj.batchId
		return next 'Jobs must be an array' if typeof! jobs isnt 'Array'
		return next 'Array of jobs is empty' if _.empty jobs
		for job in jobs when validateJobErr job => return next that
		# If there is no batchId assigned, then create one
		<-! (next) !->
			if not batchId
				err, docs <-! db.collection 'batch' .insert {onComplete}
				batchId := docs.0._id
				next!
			else next!
		err <-! async.each jobs, (model, next) !-> Job.create model import {batchId}, next
		for type in _.unique _.map (.type), jobs => queues[type]?processPendingJobs!
		next err
	else
		if validateJobErr obj => return next that
		err, job <-! Job.create obj
		if job.model.state is 'pending' => job.queue?processPendingJobs!
		next err

do # Init
	# TODO: use an actual command line library
	args =
		connect: process.argv.2 or 'mongodb://farzher:testing@kahana.mongohq.com:10017/queue'
		port: process.argv.3 or 5672
		promoteInterval: 5000
	queues = {}

	# DB
	err, _db <-! MongoClient.connect args.connect
	console.log 'Connected'
	db := _db; collection := db.collection 'jobs'

	updateConfig!

	# Ensure index
	<-! collection.ensureIndex {type: 1}
	<-! collection.ensureIndex {state: 1}
	<-! collection.ensureIndex {priority: 1}
	<-! collection.ensureIndex {delayTil: 1}
	<-! collection.ensureIndex {resetAt: 1}

	# Promote delayed jobs, reset hanging jobs, recheck rate limited queues
	setInterval _, args.promoteInterval <| !->
		processed = []
		for , queue of queues when queue.options.rateLimit > 0 and queue.options.rateInterval > 0
			processed.push queue.type
			queue.processPendingJobs!

		err, delayedDocs <-! collection.find {state: 'delayed', delayTil: {$lte: Date.now!}}, {_id: true, type: true} .toArray
		err, hangingDocs <-! collection.find {state: 'processing', resetAt: {$lte: Date.now!}}, {_id: true, type: true} .toArray
		docs = delayedDocs ++ hangingDocs
		return if _.empty docs
		_ids = _.map (._id), docs
		err <-! collection.update {_id: $in: _ids}, {$set: {state: 'pending'}}, {multi: true}
		for type in _.unique _.reject (in processed), _.map (.type), docs => queues[type]?processPendingJobs!

do # Init JSON API
	express = require 'express'
	app = express!
	bodyParser = require 'body-parser'
	app.use bodyParser.json!
	router = express.Router!
	router.all '/', (req, res) !-> res.send '//TODO: Single page UI that lets you see what jobs are currently running, and edit queue settings'
	router.all '/job', (req, res) !-> createJob req.body, (err) !-> res.status (if err => 500 else 200); res.send err
	router.all '/update-config', (req, res) !-> updateConfig!; res.send ''
	app.use '/', router
	app.listen args.port
