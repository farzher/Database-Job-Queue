redis = require 'redis'
_ = require 'prelude-ls-extended'
client = redis.createClient 16365, 'pub-redis-16365.us-east-1-3.1.ec2.garantiadata.com'

# Things break if we don't ensure these aren't strings
redisInts = <[attempts failedAttempts priority backoff delay insertedAt]>

getTimestamp = -> Math.floor Date.now! / 1000

class Task
	(@id, @redisOptions={}) ->
		@data = @redisOptions.data
		@type = @redisOptions.type
		@process = q.processes[@type]
		@options = ({} import @process.options) import @redisOptions

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
			m.hset (q.key "task:#{@id}"), 'failedAttempts', @redisOptions.failedAttempts
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
		err, @id <~ client.incr (q.key 'taskIncrementId')
		return next err if err

		m = client.multi!
		m.hmset (q.key "task:#{@id}"), @toRedisHash!
		m.zadd (q.key "type:#{@type}"), @options.priority, @id
		err, res <~ m.exec!
		return next err if err

		err <~ @setState 'pending'
		next err; return if err

		# After it's saved, pickup a task to process (probably this one)
		@process.pickupPendingTasks!

	execute: ->
		err <~ @setState 'processing'
		@process.execute @

	# After we're done, we look for new tasks to process
	done: (err=null) ->
		@process.processingCount -= 1

		if not err
			err <~ @setState 'successful'
			@process.pickupPendingTasks!
		else
			err <~ @setState 'failed'
			@process.pickupPendingTasks!


class Process
	(@type, @options=null, @cb=null) ->
		@processingCount = 0
		@pickupPendingTasks!

	# TODO: Pickup is not atomic
	pickupPendingTasks: ->
		# If we're over our limit, get out of here
		if @options.limit > 0
			return if @processingCount >= @options.limit
		@processingCount += 1

		# Get pending task
		m = client.multi!
		m.zrange (q.key "state:pending:type:#{@type}"), 0, 0
		m.zremrangebyrank (q.key "state:pending:type:#{@type}"), 0, 0
		err, res <~ m.exec!
		id = res.0.0

		# We didn't find anything, get out of here
		return @processingCount -= 1 if not id

		# Get details for task
		err, task <~ q.getTask id
		task.state = 'pending'

		# Process the task we found
		task.execute!

		# Loop, looking for more tasks
		@pickupPendingTasks!

	execute: (task) ->
		@cb task

q = exports import
	namespace: 'q'
	key: -> "#{q.namespace}:#it"
	processes: {}

	# Used to define a function for processing tasks
	process: (type, options=null, cb=null) ->
		if not cb? => cb = options
		if not _.isType 'Object', options => options = {}
		options = {priority: 0, limit: 1, attempts: 1, backoff: 0, delay: 0} import options

		q.processes[type] = new Process type, options, cb

	# Used to create a task, and check to process it instantly
	create: (type, data={}, redisOptions={}, next=->) ->
		task = new Task null, (redisOptions import {type, data})
		task.save next
		return task

	# Called once to enable JSON api and dashboard
	listen: (port) ->
		express = require 'express'
		app = express!
		bodyParser = require 'body-parser'
		app.use bodyParser.json!
		router = express.Router!
		router.post '/task', (req, res) ->
			obj = req.body
			err <- q.create obj.type, obj.data, obj.options
			res.status (if err => 500 else 200)
			res.send!
		app.use '/', router
		app.listen port
		return {app, router}

	getTask: (id, next) ->
		err, res <- client.hgetall (q.key "task:#id")
		return next err if err
		return next 404 if not res

		res.data = try JSON.parse res.data catch => {}
		for name in redisInts => res[name] = parseInt res[name] if res[name]?

		next null, (new Task id, res)

# Initialize the database
client.setnx (q.key 'taskIncrementId'), 0

# Promote delayed jobs
setInterval ->
	timestamp = getTimestamp!
	m = client.multi!
	m.zrangebyscore (q.key 'state:delayed'), 0, timestamp
	m.zremrangebyscore (q.key 'state:delayed'), 0, timestamp
	err, res <~ m.exec!
	ids = res.0
	for id in ids
		err, task <- q.getTask id
		task.state = 'delayed'
		err <- task.setState 'pending'
		# TODO: this only needs to be called once for each process type
		task.process.pickupPendingTasks!
, 5000
