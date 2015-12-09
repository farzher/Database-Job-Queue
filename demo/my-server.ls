_ = require 'prelude-ls-extended'
request = require 'request'
express = require 'express'
app = express!
bodyParser = require 'body-parser'
app.use bodyParser.json!

router = express.Router!
router.all '/create-campaign', (req, res) !->
  queries = ['pokemon', 'fish', 'nuts']
  job = {data:{type:'campaign', queries}}
  err, response, body <-! request.post 'http://localhost:5672/job', {json:job}
  res.send body

router.all '/send-email', (req, res) !->
  data = req.body.data
  console.log req.body

  # err, response, body <-! request.post 'http://localhost:5672/job', {json:{parentId:req.body._id, batchId:req.body.batchId, data:{idk:'hello (:'}}}
  # console.log 'posted job', err, body

  <-! (|> setTimeout _, 2000)
  err, response, body <-! request.post 'http://localhost:5672/job/update', {json:{_id:req.body._id, progress:50}}
  <-! (|> setTimeout _, 2000)

  response = """
    Sending email to: #{data.to}
    Subject: #{data.subject}
    Message: #{data.message}
  """
  res.send response

app.use '/', router
app.listen 8080
