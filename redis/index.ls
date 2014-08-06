redis = require 'redis'
_ = require 'prelude-ls-extended'
client = redis.createClient 16365, 'pub-redis-16365.us-east-1-3.1.ec2.garantiadata.com'

# Things break if we don't ensure these aren't strings
redisInts = <[attempts failedAttempts priority backoff delay insertedAt]>

getTimestamp = -> Math.floor Date.now! / 1000

class Job
	(@id, @redisOptions={}) ->
		@data = @redisOptions.data
		@type = @redisOptions.type
		@queue = q.queues[@type]
		@options = ({} import @queue.options) import @redisOptions

	toRedisHash: ->
		result = {} import @redisOptions
		result.data = try JSON.stringify @data catch => '{}'
		return result

	setState: (state, next=->) ->
		m = client.multi!

		# If we've askd for delay, and current state is null, insert it delayed instead of pending
		if state is 'pending' and not @state?
			state = 'delayed' if @options.delay > 0

		if state is 'failed'
			@redisOptions.failedAttempts = (@redisOptions.failedAttempts or 0) + 1
			m.hset (q.key "job:#{@id}"), 'failedAttempts', @redisOptions.failedAttempts
			state = 'pending' if @redisOptions.failedAttempts < @options.attempts

			# If we're trying to set it back to pending, first check backoff, maybe we need to delay it instead
			if state is 'pending' and @options.backoff > 0
				state = 'delayed'

		# If it's delayed, score is when it's promoted instead of priority
		score = if state is 'delayed'
			if @redisOptions.failedAttempts? => getTimestamp! + @options.backoff
			else getTimestamp! + @options.delay
		else @options.priority

		if @state?
			m.zrem (q.key "state:#{@state}"), @id
			m.zrem (q.key "state:#{@state}:type:#{@type}"), @id
		m.zadd (q.key "state:#state"), score, @id
		m.zadd (q.key "state:#state:type:#{@type}"), score, @id
		err, res <~ m.exec!
		@state = state
		next err

	save: (next) ->
		@redisOptions.insertedAt = getTimestamp!
		err, @id <~ client.incr (q.key 'jobIncrementId')
		return next err if err

		m = client.multi!
		m.hmset (q.key "job:#{@id}"), @toRedisHash!
		m.zadd (q.key "type:#{@type}"), @options.priority, @id
		err, res <~ m.exec!
		return next err if err

		err <~ @setState 'pending'
		next err; return if err

		# After it's saved, pickup a job to process (probably this one)
		@queue.pickupPendingJobs!

	process: ->
		err <~ @setState 'processing'
		@queue.process @

	# After we're done, we look for new jobs to process
	done: (err=null) ->
		@queue.processingCount -= 1

		if not err
			err <~ @setState 'successful'
			@queue.pickupPendingJobs!
		else
			err <~ @setState 'failed'
			@queue.pickupPendingJobs!


class Queue
	(@type, @options=null, @cb=null) ->
		@processingCount = 0
		@pickupPendingJobs!

	# TODO: Pickup is not atomic
	pickupPendingJobs: ->
		# If we're over our limit, get out of here
		if @options.limit > 0
			return if @processingCount >= @options.limit
		@processingCount += 1

		# Get pending job
		m = client.multi!
		m.zrange (q.key "state:pending:type:#{@type}"), 0, 0
		m.zremrangebyrank (q.key "state:pending:type:#{@type}"), 0, 0
		err, res <~ m.exec!
		id = res.0.0

		# We didn't find anything, get out of here
		return @processingCount -= 1 if not id

		# Get details for job
		err, job <~ q.getJob id
		job.state = 'pending'

		# Process the job we found
		job.process!

		# Loop, looking for more jobs
		@pickupPendingJobs!

	process: (job) ->
		@cb job

q = exports import
	namespace: 'q'
	key: -> "#{q.namespace}:#it"
	queues: {}

	# Used to define a function for processing jobs
	queue: (type, options=null, cb=null) ->
		if not cb? => cb = options
		if not _.isType 'Object', options => options = {}
		options = {priority: 0, limit: 1, attempts: 1, backoff: 0, delay: 0} import options

		q.queues[type] = new Queue type, options, cb

	# Used to create a job, and check to process it instantly
	create: (type, data={}, redisOptions={}, next=->) ->
		job = new Job null, (redisOptions import {type, data})
		job.save next
		return job

	# Called once to enable JSON api and dashboard
	listen: (port) ->
		express = require 'express'
		app = express!
		bodyParser = require 'body-parser'
		app.use bodyParser.json!
		router = express.Router!
		router.post '/job', (req, res) ->
			obj = req.body
			err <- q.create obj.type, obj.data, obj.options
			res.status (if err => 500 else 200)
			res.send!
		app.use '/', router
		app.listen port
		return {app, router}

	getJob: (id, next) ->
		err, res <- client.hgetall (q.key "job:#id")
		return next err if err
		return next 404 if not res

		res.data = try JSON.parse res.data catch => {}
		for name in redisInts => res[name] = parseInt res[name] if res[name]?

		next null, (new Job id, res)

# Initialize the database
client.setnx (q.key 'jobIncrementId'), 0

# Promote delayed jobs
setInterval ->
	timestamp = getTimestamp!
	m = client.multi!
	m.zrangebyscore (q.key 'state:delayed'), 0, timestamp
	m.zremrangebyscore (q.key 'state:delayed'), 0, timestamp
	err, res <~ m.exec!
	ids = res.0
	for id in ids
		err, job <- q.getJob id
		job.state = 'delayed'
		err <- job.setState 'pending'
		# TODO: this only needs to be called once for each queue type
		job.queue.pickupPendingJobs!
, 5000
