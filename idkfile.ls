_ = require 'prelude-ls-extended'
request = require 'request'

exports import
	default: !->
		switch it.data.type
		| 'mxDone'
			# did it pass metrics filter?
			if _.chance 0.9
				err, response <-! request 'http://localhost:5672/job', {json: {type: 'cf', data: {(it.data)domainId}}}
				it.done err
			else
				err, response <-! request 'http://localhost:5672/job', {json: {data: {type: 'done', (it.data)domainId}}}
				it.done err
		| 'done'
			console.log 'Your entire campaign has finished for domainId:', it.data.domainId

	campaign: !->
		console.log 'Inserting stuff into the database and doing things'
		if _.chance 0.2 => return it.error 'Things randomly crashed'

		domainId = it.data.domainId
		if not domainId => return it.error 'Invalid domainId'

		it.success null, do
			jobs:
				{type: 'mx1', data: {domainId}}
				{type: 'mx2', data: {domainId}}
			onComplete: {data: {type: 'mxDone', domainId}}

	mx1: !->
		if _.chance 0.1 => return it.done 'Getting metrics failed'
		metric = _.rand 10
		# Store the metric in the database
		if _.chance 0.1 => return it.done 'Saving metrics failed'

		it.done!

	mx2: !->
		if _.chance 0.1 => return it.done 'Getting metrics failed'
		metric = _.rand 10
		# Store the metric in the database
		if _.chance 0.1 => return it.done 'Saving metrics failed'

		it.done!

	cf: !->
		if _.chance 0.1 => return it.done 'Finding contacts failed'

		err, response <-! request 'http://localhost:5672/job', {json: {data: {type: 'done', (it.data)domainId}}}
		it.done err
