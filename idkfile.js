// Generated by LiveScript 1.2.0
var _, request;
_ = require('prelude-ls-extended');
request = require('request');
exports['default'] = function(job){
  var jobs, res$, i$, ref$, len$, keyword, sites, queries, q, domains, domain;
  switch (job.data.type) {
  case 'getSitesFromKeywords':
    res$ = [];
    for (i$ = 0, len$ = (ref$ = job.data.keywords).length; i$ < len$; ++i$) {
      keyword = ref$[i$];
      res$.push({
        data: {
          type: 'makeGoogleRequest',
          keyword: keyword
        }
      });
    }
    jobs = res$;
    job.success(null, {
      onComplete: {
        data: {
          type: 'googleDone'
        }
      },
      jobs: jobs
    });
    break;
  case 'makeGoogleRequest':
    keyword = job.data.keyword;
    if (_.chance(0.9)) {
      return job.error('Could not load google results, bad proxy');
    }
    sites = [keyword + "site1.com", keyword + "site2.net", keyword + "site3.org"];
    job.success(sites);
    break;
  case 'googleDone':
    job.getBatchJobs(function(jobs){
      var allSites;
      allSites = [];
      _.each(function(it){
        return allSites = allSites.concat(it.model.result);
      }, jobs);
      allSites = _.unique(allSites);
      return job.success(allSites);
    });
    break;
  case 'log':
    job.success(job.data.m);
    break;
  case 'progress':
    console.log('progress time');
    _.flipSetTimeout(1000, function(){
      console.log('progress percent');
      job.progress(10);
      return _.flipSetTimeout(1000, function(){
        job.progress(50);
        return _.flipSetTimeout(1000, function(){
          job.progress(75);
          return _.flipSetTimeout(1000, function(){
            return job.success();
          });
        });
      });
    });
    break;
  case 'campaign':
    queries = job.data.queries;
    if (!queries) {
      return job.kill('Invalid queries');
    }
    console.log('Inserting your request into the database');
    if (_.chance(0.2)) {
      return job.error('Things randomly crashed');
    }
    res$ = [];
    for (i$ = 0, len$ = queries.length; i$ < len$; ++i$) {
      q = queries[i$];
      res$.push({
        data: {
          type: 'prospect',
          q: q,
          campaign_id: job.model._id
        }
      });
    }
    jobs = res$;
    job.success(null, {
      onComplete: {
        data: {
          'type': 'log',
          'm': "Campaign " + job.model._id + " complete"
        }
      },
      jobs: jobs
    });
    break;
  case 'prospect':
    console.log("Making proxy request to google.com?q=" + job.data.q);
    if (_.chance(0.2)) {
      return job.error('No working proxy available');
    }
    domains = [_.rand(1000), _.rand(1000)];
    if (_.chance(0.2)) {
      return job.error('Inserting opps to mysql failed');
    }
    jobs = [];
    for (i$ = 0, len$ = domains.length; i$ < len$; ++i$) {
      domain = domains[i$];
      jobs.push({
        type: 'mx1',
        data: {
          domain: domain,
          campaign_id: job.data.campaign_id
        }
      });
      jobs.push({
        type: 'mx2',
        data: {
          domain: domain,
          campaign_id: job.data.campaign_id
        }
      });
      jobs.push({
        type: 'cf',
        data: {
          domain: domain,
          campaign_id: job.data.campaign_id
        }
      });
    }
    job.success(domains, {
      batchId: job.model.batchId,
      jobs: jobs
    });
  }
};
exports.mx1 = function(job){
  var metric;
  if (_.chance(0.1)) {
    return job.error('Getting metrics failed');
  }
  metric = _.rand(10);
  job.success(metric);
};
exports.mx2 = function(job){
  var metric;
  if (_.chance(0.1)) {
    return job.error('Getting metrics failed');
  }
  metric = _.rand(10);
  job.success(metric);
};
exports.cf = function(job){
  var contacts;
  if (_.chance(0.1)) {
    return job.error('Finding contacts failed');
  }
  contacts = [_.rand(1000), _.rand(1000)];
  job.success(contacts);
};