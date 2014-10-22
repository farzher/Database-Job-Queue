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
		# Apparently everytime we setState we want to decrement the processingCount
		@queue.processingCount -= 1

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
	model.type ?= 'default'
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

class Queue
	(@type, options={}) ->
		@updateConfig options
		@processingCount = 0
		# To get things started if there's jobs waiting when we start the server
		@processPendingJobs!

	updateConfig: (options) !-> @options = ({} import config.queues.default) import options
	processPendingJobs: !->
		console.log 'processingCount:', @type, @processingCount

		# This runs even if we're over our queue's limit! In that case it's based on the job's overwritten limit
		query = {type: @type, state: 'pending', $or: [{limit: {$gt: @processingCount}}, {limit: {$lt: 0}}]}
		# If we're not over our queue's limit, also include any jobs with null limit
		if @options.limit < 0 or @processingCount < @options.limit => query.$or.push {limit: null}
		@processingCount += 1

		# Get pending job
		err, doc <~! collection.findAndModify query, [['priority', 'desc']], {$set: {state: 'processing'}}, {new: true}
		job = (if doc => new Job doc else null)
		console.log 'found job:', job?

		# We didn't find anything, get out of here
		return @processingCount -= 1 if not job

		# Process the job we found
		@process job

		# Loop, looking for more jobs
		@processPendingJobs!

	process: (job) !->
		console.log 'pushing job to:', job.option 'url'
		err, res, body <-! request {url: (job.option 'url'), method: (job.option 'method'), json: job.model}
		console.log 'Done!'
		return job.done err if err
		if res.statusCode is 200 => job.done null, body
		else if res.statusCode is 202 => job.retry!
		else if res.statusCode is 403 => job.kill!
		else
			message = res.statusCode + (if body => ": #body" else '')
			job.done message




# Get config, or create it if doesn't exist
updateConfig = !->
	err, _config <-! db.collection 'config' .findOne
	config := _config
	if not config?
		config := {queues: default: {priority: 0, limit: 1, attempts: 1, backoff: 0, delay: 0, duration: 60*60, url: null, method: 'POST'}}
		err, docs <-! db.collection 'config' .insert config

	# Push config into queues, or update existing queues
	for k, v of config.queues => if queues[k]? => that.updateConfig v else queues[k] = new Queue k, v

# Used to create a job, and check to process it instantly
createJob = (obj, next=!->) !->
	err, job <-! Job.create obj
	if job.model.state is 'pending' => job.queue?processPendingJobs!
	next err

# Used to create jobs in a batch
createBatch = (arr, next=!->) !-> async.each arr, (!-> Job.create ...), next

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
	<-! collection.ensureIndex {limit: 1}

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
	express = require 'express'
	app = express!
	bodyParser = require 'body-parser'
	app.use bodyParser.json!
	router = express.Router!
	router.all '/job', (req, res) !->
		obj = req.body
		if _.isArray obj
			return (res.status 500; res.send 'Array is empty') if _.empty obj
			err <-! createBatch obj
			if not err => for type in _.unique _.map (.type), obj => queues[type]?processPendingJobs!
			res.status (if err => 500 else 200); res.send err
		else
			err <-! createJob obj
			res.status (if err => 500 else 200); res.send err
	router.all '/update-config', (req, res) !-> updateConfig!; res.send ''
	app.use '/', router
	app.listen args.port
