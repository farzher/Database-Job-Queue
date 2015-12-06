### Job Queue Experiment
This project is unfinished, do not use it.

## Features
* [x] Delayed jobs
* [x] Optional retries
	* [x] with custom backoff
* [x] Job priority
* [ ] RESTful JSON API
	* [x] creating jobs
	* [ ] searching jobs
	* [x] processing jobs
* [x] Job data is kept, keep all your job history here and query it whenever
* [ ] Processes jobs by
	* [x] node callbacks
	* [x] using webhooks
	* [ ] calling cli commands
	* [ ] or polling
* [ ] Web API lets you configure new queues without having to restart the server
* [x] The default queue can be used for multiple things, by `switch`ing on an arbitrary type
* [x] Rate limit jobs
	* [x] only process 5 at a time
	* [x] only process 5 per minute
* [ ] Job monitoring (logging, progress, when finished you can check the result, or reason failed)
* [x] Batches????? (do something when all jobs in a batch are finished)
* [x] When being processed, a job can either: succeed, fail, die (ignore remaining attempts), or retry (don't count current attempt as failed)
* [x] cleanup hanging processing jobs

## Database
	jobs
		type: 'email'
		data:
			subject: 'hey'
			message: 'what up bro'
		priority: 0
		attempts: 3
		backoff: 60
		delay: 10
		insertAt: timestamp
		resetAt: timestamp
		delayTil: timestamp
		batchId: batch._id
		progress: 0
		logs: [{t: timestamp, m: 'message'}]
		result: where you can store job output
		state: pending,active,fail,success,delay
		onSuccessDelete: false
		onComplete: job
		parentId: job

	batches
		onComplete: job
		isComplete: false

	config
		queues: {default: defaultQueueConfig}
