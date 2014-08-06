### Job Queue Experiments
This project is unfinished, do not use it.

## Features
* Delayed jobs
* Optional retries with backoff
* Job priority
* RESTful JSON API (creating jobs, searching jobs)
* Process jobs in node or use push queue webhooks to process jobs from another server
* Rate limit jobs (only process 5 at a time, or only process 5 per minute)
* Job monitoring (logging, progress, when finished you can check the result, or reason failed)
* Batches (do something when all jobs in a batch are finished)
* When being processed, a job can either: succeed, fail, die (ignore remaining attempts), or retry (don't count current attempt as failed)
* TODO: cleanup hanging processing jobs

## Redis Version
* Incredibly fast
* Job data is deleted after completion

## Mongo Version
* Advanced job search API
* Job data is kept, keep all your job history here and query it whenever

## MySQL Version
* Lol, I'm kidding.
