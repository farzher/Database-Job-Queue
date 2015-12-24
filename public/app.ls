Vue = require 'vue'
Vue.config.debug = true
Request = require 'superagent'
_ = require 'prelude-ls-extended'
a = _.a
Moment = require 'moment'
Page = require 'page'
# $ = require 'jquery'
require './app.css'

``function syntaxHighlight(e){return"string"!=typeof e&&(e=JSON.stringify(e,void 0,2)),e=e.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;"),e.replace(/("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g,function(e){var t="number";return/^"/.test(e)?t=/:$/.test(e)?"key":"string":/true|false/.test(e)?t="boolean":/null/.test(e)&&(t="null"),'<span class="'+t+'">'+e+"</span>"})}``



window.app = new Vue do
  el:'#app'
  data:
    info:{counts:{}, queues:[]}
    jobs:[]
    filter:{where:{state:void, type:void}}
  ready:!->
    @reload!; setInterval @reload, 2000
  methods:
    syntaxHighlight:-> syntaxHighlight (if typeof! it is 'Object' => JSON.stringify it, void, 1 else it)
    changeWhere:(_where)!->
      @filter.where import _where
      Page "/#{JSON.stringify @filter}"
    reload:!->
      (Request.post '/info', @filter)end (err, res)!-> app.info = res.body
      (Request.post '/view', @filter)end (err, res)!->
        for job in res.body
          job.timestamp = (Moment job.timestamp)fromNow!
          if job.logs => for log in job.logs
            log.t = (Moment log.t)fromNow!
        app.jobs = res.body

Page.base '/#'
Page '/:filter', !->
  try
    filter = JSON.parse it.params.filter
    return Page.redirect '/{"where":{}}' if not filter.where
    app.filter = filter
    app.reload!
  catch => Page.redirect '/{"where":{}}'
Page '*', !-> console.log it; Page.redirect '/{"where":{}}'
Page!
