### Job Queue Experiment
This project is unfinished, do not use it
It's similar to something like RabbitMQ, but a lot more *powerful*
This is for *LOW BANDWIDTH & IMPORTANT jobs*
This is *not for sending emails*
This *is for* dealing with complex multi-stage jobs with *high failure* chance
*Logging* is supported well, so you can tell exactly what happened if things go wrong
You can attach *arbitrary information* to jobs, like a user_id, to keep track of who's doing what without cluttering your main database

## Example Usage
TODO

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
* [x] Job monitoring (logging, progress, when finished you can check the result, or reason failed)
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
		parentId: job._id
		progress: 0
		logs: [{t: timestamp, m: 'message'}]
		result: where you can store job output
		state: pending,processing,failed,success,delayed,killed
		onSuccessDelete: false
		onComplete: job

	batches
		(currently only used to generate a batch id)

	config
		queues: {default: defaultQueueConfig}
