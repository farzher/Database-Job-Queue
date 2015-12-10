``
function syntaxHighlight(json) {
    if (typeof json != 'string') {
         json = JSON.stringify(json, undefined, 2);
    }
    json = json.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return json.replace(/("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g, function (match) {
        var cls = 'number';
        if (/^"/.test(match)) {
            if (/:$/.test(match)) {
                cls = 'key';
            } else {
                cls = 'string';
            }
        } else if (/true|false/.test(match)) {
            cls = 'boolean';
        } else if (/null/.test(match)) {
            cls = 'null';
        }
        return '<span class="' + cls + '">' + match + '</span>';
    });
}
``




init_isotope = (ele) !->
  # $(ele).isotope do
  #   # layoutMode: 'vertical'
  #   itemSelector: 'pre'
  #   masonry:
  #     columnWidth: 1

controller = !->
  @filter = eval "(#{m.route.param 'filter'})"

  @reload = !~>
    @info = m.request.post '/info', {data:@filter}
    @jobs = m.request.post '/view', {data:@filter} .then !->
      for job in it
        job.timestamp = (moment job.timestamp)fromNow!
        if job.logs => for log in job.logs
          log.t = (moment log.t)fromNow!
      return it
  @reload!
  @interval = setInterval @reload, 1000
  @onunload = !~> clearInterval @interval

  @changeWhere = (_where) !~>
    @filter.where import _where
    m.route "/#{JSON.stringify @filter}"
    return false

view = (c) ->
  a do
    m 'div' {init:init_isotope} a do
      m 'pre.info' a do
        for let state, count of c.info!counts
          m 'p' m 'a' {class:{active:state is c.filter.where.state}, href:'#', onclick:-> c.changeWhere {state:state}} "#state: #count"
        m 'p' m 'a' {class:{active:void is c.filter.where.state}, href:'#', onclick:-> c.changeWhere {state:void}} "Any"
      m 'pre.info' a do
        for let queue in c.info!queues
          m 'p' m 'a' {class:{active:queue is c.filter.where.type}, href:'#', onclick:-> c.changeWhere {type:queue}} "#queue"
        m 'p' m 'a' {class:{active:void is c.filter.where.type}, href:'#', onclick:-> c.changeWhere {type:void}} "Any"
      m 'br' {style:'clear:both'}

      for job in c.jobs!
        m 'pre.job' m.trust syntaxHighlight JSON.stringify job, void, 1

m.route (document.getElementById 'app'), '/{where:{state:"pending"}}', {'/:filter':{controller, view}}
