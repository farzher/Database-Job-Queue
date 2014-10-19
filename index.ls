do # Require
	mongodb = require 'mongodb'
	MongoClient = mongodb.MongoClient
	db = collection = config = null
	_ = require 'prelude-ls-extended'
	async = require 'async'
	request = require 'request'

class Job
	(@model={}) ->
		@data = @model.data
		@queue = queues[@model.type]

	option: -> | @model[it]? => that | otherwise @queue.options[it]
	update: (data, next) !-> @model import data; collection.update {_id: @model._id}, {$set: data}, next

	setState: (state, next=!->) !->
		updateData = {}
		if state is 'failed'
			updateData.failedAttempts = (@option 'failedAttempts' or 0) + 1
			state = 'pending' if updateData.failedAttempts < @option 'attempts'

			# If we're trying to set it back to pending, first check backoff, maybe we need to delay it instead
			if state is 'pending' and (@option 'backoff') > 0
				state = 'delayed'
				updateData.delayTil = Date.now! + (@option 'backoff') * 1000

		if state is 'killed' => state = 'failed'

		err <~! @update updateData import {state}
		next err

	done: (err=null) !->
		@queue.processingCount -= 1

		if not err?
			err <~! @setState 'successful'
			@queue.processPendingJobs!
		else
			err <~! @setState 'failed'
			@queue.processPendingJobs!
	retry: (next=!->) !-> @setState 'pending', next
	kill: (next=!->) !-> @setState 'killed', next
	log: (message, next=!->) !-> collection.update {_id: @model._id}, {$push: {logs: message}}, next
Job.create = (model, next) !->
	model.state = 'pending'
	delay = model.delay or queues[model.type]?options?delay or 0
	if delay > 0
		model.state = 'delayed'
		model.delayTil = Date.now! + delay * 1000
	duration = model.duration or queues[model.type]?options?duration or 0
	model.resetAt = Date.now! + duration * 1000
	err, docs <-! collection.insert model
	console.log 'inserted new job:', model
	job = new Job docs.0
	next err, job
Job.getPending = (type, next) !->
	err, doc <-! collection.findAndModify {type: type, state: 'pending'}, [['priority', 'asc']], {$set: {state: 'processing'}}, {new: true}
	next err, (if doc => new Job doc else null)

class Queue
	(@type, @_options={}) ->
		@options = ({} import defaultOptions) import @_options
		@processingCount = 0
		# To get things started if there's jobs waiting when we start the server
		@processPendingJobs!

	processPendingJobs: !->
		console.log 'processingCount:', @processingCount

		# If we're over our limit, get out of here
		if @options.limit >= 0
			return if @processingCount >= @options.limit
		@processingCount += 1

		# Get pending job
		err, job <~! Job.getPending @type
		console.log 'found job:', job?

		# We didn't find anything, get out of here
		return @processingCount -= 1 if not job

		# Process the job we found
		@process job

		# Loop, looking for more jobs
		@processPendingJobs!

	process: (job) !->
		console.log 'pushing job to:', @options.endpoint
		err, res, body <-! request.post @options.endpoint, {json: job.model}
		return job.done err if err
		if res.statusCode is 200 => job.done null, body
		else if res.statusCode is 202 => job.retry!
		else if res.statusCode is 403 => job.kill!
		else
			message = res.statusCode + (if body => ": #body" else '')
			job.done message








do # Init
	# TODO: use an actual command line library
	args =
		connect: 'mongodb://farzher:testing@kahana.mongohq.com:10017/queue'
		port: 1337
		promoteInterval: 5000
		endpoint: 'http://httpbin.org/code/500'
	queues = {}
	defaultOptions = {priority: 0, limit: 1, attempts: 1, backoff: 0, delay: 0, duration: 60*60, endpoint: args.endpoint}

	# DB
	err, db <-! MongoClient.connect args.connect
	console.log 'Connected'
	db := db; collection := db.collection 'jobs'

	# Get config, or create it if doesn't exist
	err, dbConfig <-! db.collection 'config' .findOne
	config := dbConfig
	if not config?
		config := {queues: default: {}}
		err, docs <-! db.collection 'config' .insert config

	# Push config into queues
	for k, v of config.queues => queues[k] = new Queue k, v

	# Ensure index
	<-! collection.ensureIndex {type: 1}
	<-! collection.ensureIndex {state: 1}
	<-! collection.ensureIndex {priority: 1}
	<-! collection.ensureIndex {delayTil: 1}
	<-! collection.ensureIndex {resetAt: 1}

	# Promote delayed jobs, reset hanging jobs
	setInterval _, args.promoteInterval <| !->
		err, delayedDocs <-! collection.find {state: 'delayed', delayTil: {$lte: Date.now!}}, {_id: true, type: true} .toArray
		err, hangingDocs <-! collection.find {state: 'processing', resetAt: {$lte: Date.now!}}, {_id: true, type: true} .toArray
		docs = delayedDocs ++ hangingDocs
		return if _.empty docs
		_ids = _.map (._id), docs
		err <-! collection.update {_id: $in: _ids}, {$set: {state: 'pending'}}, {multi: true}
		for type in _.unique _.map (.type), docs => queues[type]?processPendingJobs!

do # Init JSON API
	# Used to create a job, and check to process it instantly
	createJob = (obj, next=!->) !->
		err, job <-! Job.create obj
		if job.model.state is 'pending' => job.queue.processPendingJobs!
		next err
	# Used to create jobs in a batch
	createBatch = (arr, next=!->) !-> async.each arr, (!-> Job.create ...), next

	express = require 'express'
	app = express!
	bodyParser = require 'body-parser'
	app.use bodyParser.json!
	router = express.Router!
	router.post '/job', (req, res) !->
		obj = req.body
		if _.isArray obj
			return (res.status 500; res.send 'Array is empty') if _.empty obj
			err <-! createBatch obj
			if not err => for type in _.unique _.map (.type), obj => queues[type]?processPendingJobs!
			res.status (if err => 500 else 200); res.send err
		else
			err <-! createJob obj
			res.status (if err => 500 else 200); res.send err
	app.use '/', router
	app.listen args.port
