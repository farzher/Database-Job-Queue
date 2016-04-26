``function syntaxHighlight(e){return"string"!=typeof e&&(e=JSON.stringify(e,void 0,2)),e=e.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;"),e.replace(/("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g,function(e){var t="number";return/^"/.test(e)?t=/:$/.test(e)?"key":"string":/true|false/.test(e)?t="boolean":/null/.test(e)&&(t="null"),'<span class="'+t+'">'+e+"</span>"})}``

Vue.config.debug = true

Vue.directive 'tip', do
  bind:!->
    $ele = $ @el
    $ele.attr 'title', @expression
    $ele.tooltip {container:'body', trigger:'hover'}
  update:(v)!->
    $ele = $ @el
    $ele.attr 'title', v
    $ele.tooltip 'dispose'
    $ele.tooltip {container:'body', trigger:'hover'}

window.app = new Vue do
  el:'#app'
  data:
    dbConfig:{}
    dbConfigRaw:''
    createJobRaw:''
    info:{counts:{}, queues:[]}
    jobs:[]
    filter:{where:{state:void, type:void}}
  ready:!->
    # @reload!
    setInterval @refresh, 2000
    # ($ '.tip')tooltip!
  computed:
    isDbConfigDirty:!->
      newConfig = try JSON.parse @dbConfigRaw
      if not newConfig => return true
      return (JSON.stringify newConfig) isnt JSON.stringify @dbConfig
  methods:
    syntaxHighlight:-> syntaxHighlight (if typeof! it is 'Object' => JSON.stringify it, void, 1 else it)

    changeWhere:(_where)!->
      app.filter.where import _where
      Page "/#{JSON.stringify app.filter}"

    # Lightweight reload
    refresh:!->
      (Request.post '/info', app.filter)end (err, res)!-> app.info = res.body
      (Request.post '/job/get', app.filter)end (err, res)!->
        for job in res.body
          job.timestamp = (Moment job.timestamp)fromNow!
          if job.logs => for log in job.logs
            log.t = (Moment log.t)fromNow!
        app.jobs = res.body
    reload:!->
      (Request.post '/get-db-config')end (err, res)!->
        delete res.body._id
        app.dbConfig = res.body
        app.revertDbConfig!
      @refresh!

    revertDbConfig:!->
      app.dbConfigRaw = JSON.stringify app.dbConfig, null, 2
    saveDbConfig:!->
      newConfig = try JSON.parse app.dbConfigRaw
      if not newConfig => alert 'Invalid JSON'; return
      app.dbConfig = newConfig
      app.revertDbConfig!
      (Request.post '/save-db-config', app.dbConfig)end!

    createJob:!->
      job = try JSON.parse app.createJobRaw
      if not job => alert 'Invalid JSON'; return
      (Request.post '/job/create', job)end!
      ($ '#createjob-modal')modal 'hide'

    # make ajax request for href
    ajax:(e, o={})!->
      $ele = $ e.currentTarget
      if $ele.hasClass 'disabled' => return
      href = e.currentTarget.href
      (Request.get href)end (err, res)!->
        if o.reload => app.reload!



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
