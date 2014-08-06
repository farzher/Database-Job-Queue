q = require '../redis/index'
async = require 'async'
_ = require 'prelude-ls-extended'

q.queue 'test', {limit: 1, attempts: 3}, (job) ->
	sendMail = (data, cb) -> setTimeout (-> cb (if data.subject is 'fail' => 'asked to fail')), 1000

	data = job.data
	console.log 'attempting to send email now'
	err <- sendMail {data.subject, data.message}
	console.log 'sendMail finished with err', err
	job.done err

# q.create 'test', {subject: 'hey 1', message: 'sup'}, {priority: -1}
# q.create 'test', {subject: 'hey 2', message: 'sup'}, {priority: -2, attempts: 1}
q.listen 1337
return
















# Example of processing a batch of requests
q.queue 'mx', (data, job) ->
	job.log 'whatever'
	job.done!


# Example of processing an entire batch as 1 request
q.queue 'mx', (data, job) ->
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
		job.done!

# type, optional options, (process function | push url)
q.queue 'email', {limit: 1, attempts: 1, backoff: 0}, (data, job) ->
	if iDontWantToSendNow => return job.delay 60

	job.log 'attempting to send email now'
	success <- sendEmail {data.subject, data.message}
	if not success => job.done 'failed to send email'

	job.done!

# Push queue example, this acts like ironmq
q.queue 'email', 'http://mysite.com/webhook'

# JSON API
q.listen 1337
# POST / job object or array of jobs
# GET / dashboard ui
# GET /:id job w/ meta data
# GET /type/:type
# GET /type/:type/state/:state states are pending, processing, successful, failed, delayed
# these are options for filtering GET requests ?from=0&limit=0

# TODO: add exponental backoff type
# job JSON
	# type: 'email'
	# data:
	# 	subject: 'hey'
	# 	message: 'what up bro'
	# priority: 0
	# attempts: 3
	# backoff: 60
	# delay: 10 #-1 will never get picked up, batch jobs are put as -1 delay
	# insertAt: timestamp
	# parentId: jobId #onfinished, if this exists, add job id to parentId's finishedChildIds, if all are finished, mark parent as pending
	# childIds: [job ids]
	# finishedChildIds: [job ids]
	# progress: 0

# DB structure
	# q:jobIncrementId = 0
	# q:job:1 = {}
	# q:state:pending,processing,etc = [job ids]
	# q:type:email = [job ids]






# How should I handle batches?
	# insert batch
	# processing the batch will async execute everything in a long running function, with some retries in loops

	# insert all requests in 1 call
	# how do I know when the batch is done?

	# insert batch
	# processing the batch will insert all the individual requests
	# ?how do I know when the batch is done
