q = require '../index'
async = require 'async'
_ = require 'prelude-ls-extended'

q.process 'test', {limit: 1, attempts: 3}, (task) ->
	sendMail = (data, cb) -> setTimeout (-> cb (if data.subject is 'fail' => 'asked to fail')), 1000

	data = task.data
	console.log 'attempting to send email now'
	err <- sendMail {data.subject, data.message}
	console.log 'sendMail finished with err', err
	task.done err

# q.create 'test', {subject: 'hey 1', message: 'sup'}, {priority: -1}
# q.create 'test', {subject: 'hey 2', message: 'sup'}, {priority: -2, attempts: 1}
q.listen 1337
return
















# Example of processing a batch of requests
q.process 'mx', (data, task) ->
	task.log 'whatever'
	task.done!


# Example of processing an entire batch as 1 request
q.process 'mx', (data, task) ->
	results = {}
	for domain_id in data.domain_ids => results[domain_id] = {}

	functions = []

	# Single requests like Twitter
	for domain_id in data.domain_ids
		let domain_id
			functions.push (cb) ->
				# TODO: make actual request to get data
				results[domain_id].twitter = 999
				cb!

	# Batched requests like majestic and moz
	for domain_ids in _.batch 10, data.domain_ids
		let domain_ids
			functions.push (cb) ->
				# TODO: make actual request to get data
				for domain_id in domain_ids
					results[domain_id].moz = 888
				cb!

	async.parallel functions, (err, res) ->
		# TODO: update database metrics
		console.log results
		task.done!

# type, optional options, (process function | push url)
q.process 'email', {limit: 1, attempts: 1, backoff: 0}, (data, task) ->
	if iDontWantToSendNow => return task.delay 60

	task.log 'attempting to send email now'
	success <- sendEmail {data.subject, data.message}
	if not success => task.done 'failed to send email'

	task.done!

# Push queue example, this acts like ironmq
q.process 'email', 'http://mysite.com/webhook'

# JSON API
q.listen 1337
# POST / task object or array of jobs
# GET / dashboard ui
# GET /:id task w/ meta data
# GET /type/:type
# GET /type/:type/state/:state states are pending, processing, successful, failed, delayed
# these are options for filtering GET requests ?from=0&limit=0

# TODO: add exponental backoff type
# task JSON
	# type: 'email'
	# data:
	# 	subject: 'hey'
	# 	message: 'what up bro'
	# priority: 0
	# attempts: 3
	# backoff: 60
	# delay: 10 #-1 will never get picked up, batch jobs are put as -1 delay
	# insertAt: timestamp
	# parentId: jobId #onfinished, if this exists, add task id to parentId's finishedChildIds, if all are finished, mark parent as pending
	# childIds: [task ids]
	# finishedChildIds: [task ids]
	# progress: 0

# DB structure
	# q:jobIncrementId = 0
	# q:task:1 = {}
	# q:state:pending,processing,etc = [task ids]
	# q:type:email = [task ids]






# How should I handle batches?
	# insert batch
	# processing the batch will async execute everything in a long running function, with some retries in loops

	# insert all requests in 1 call
	# how do I know when the batch is done?

	# insert batch
	# processing the batch will insert all the individual requests
	# ?how do I know when the batch is done
