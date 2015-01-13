_ = require 'prelude-ls-extended'
request = require 'request'

exports import
	default: (job) !->
		switch job.data.type
		| 'getSitesFromKeywords'
			jobs = for keyword in job.data.keywords
				{data: {type: 'makeGoogleRequest', keyword}}
			job.success null, {onComplete: {data: {type: 'googleDone'}}, jobs}
		| 'makeGoogleRequest'
			keyword = job.data.keyword
			# make google request to get sites from this keyword
			# There's a 25% chance this fails
			if _.chance 0.9 => return job.error 'Could not load google results, bad proxy'

			sites = ["#{keyword}site1.com", "#{keyword}site2.net", "#{keyword}site3.org"]
			job.success sites
		| 'googleDone'
			jobs <- job.getBatchJobs
			allSites = []
			_.each (-> allSites ++= it.model.result), jobs
			allSites = _.unique allSites
			job.success allSites



		| 'log' => job.success job.data.m
		| 'progress'
			console.log 'progress time'
			<- _.flip-set-timeout 1000
			console.log 'progress percent'
			job.progress 10

			<- _.flip-set-timeout 1000
			job.progress 50

			<- _.flip-set-timeout 1000
			job.progress 75

			<- _.flip-set-timeout 1000
			job.success!


		| 'campaign'
			queries = job.data.queries
			if not queries => return job.kill 'Invalid queries'

			console.log 'Inserting your request into the database'
			if _.chance 0.2 => return job.error 'Things randomly crashed'

			jobs = for q in queries => {data: {type: 'prospect', q, campaign_id: job.model._id}}

			job.success null, {onComplete: {data: {'type': 'log', 'm': "Campaign #{job.model._id} complete"}}, jobs}

		| 'prospect'
			console.log "Making proxy request to google.com?q=#{job.data.q}"
			if _.chance 0.2 => return job.error 'No working proxy available'

			# Scrape domains
			domains = [(_.rand 1000), (_.rand 1000)]

			# Insert opps to mysql
			if _.chance 0.2 => return job.error 'Inserting opps to mysql failed'

			jobs = []
			for domain in domains
				jobs.push {type: 'mx1', data: {domain, (job.data)campaign_id}}
				jobs.push {type: 'mx2', data: {domain, (job.data)campaign_id}}
				jobs.push {type: 'cf', data: {domain, (job.data)campaign_id}}

			job.success domains, {(job.model)batchId, jobs}

	mx1: (job) !->
		if _.chance 0.1 => return job.error 'Getting metrics failed'
		metric = _.rand 10

		job.success metric

	mx2: (job) !->
		if _.chance 0.1 => return job.error 'Getting metrics failed'
		metric = _.rand 10

		job.success metric

	cf: (job) !->
		if _.chance 0.1 => return job.error 'Finding contacts failed'

		contacts = [(_.rand 1000), (_.rand 1000)]

		job.success contacts
