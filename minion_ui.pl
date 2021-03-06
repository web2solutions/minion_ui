#!/usr/bin/env perl

use Mojolicious::Lite;

use Mojo::JSON qw(encode_json decode_json);

plugin Minion => {Pg => "postgresql://$ENV{DBI_USER}:$ENV{DBI_PASS}\@127.0.0.1/jobs"};

get '/' => sub {
    my $c = shift;

    $c->render(template => 'slash');
};

get '/v1/minion/stats' => sub {
    my $c = shift;

    my $stats = $c->app->minion->stats;

    my $ret = { 
        inactive_workers => $stats->{inactive_workers},
        active_workers => $stats->{active_workers},
        active_jobs => int($stats->{active_jobs}),
        failed_jobs => int($stats->{failed_jobs}),
        finished_jobs => int($stats->{finished_jobs}),
        epoch => time,
    };

    $c->render(json => $ret);
};

get '/v1/workers/stats' => sub {
    my $c = shift;

    my $stats = $c->app->minion->backend->list_workers(@_);

    # $c->app->log->debug($c->dumper($stats));

    my $ret = [];

    foreach my $worker (@{ $stats }) {
        push(@{ $ret }, { 
            id => $worker->{id},
            host => $worker->{host},
            pid => $worker->{pid},
        });
    }

    $c->render(json => $ret);
};

get '/v1/jobs/stats' => sub {
    my $c = shift;

    my $stats = $c->app->minion->backend->list_jobs(@_);

    # $c->app->log->debug($c->dumper($stats));

    my $ret = [];

    foreach my $job (@{ $stats }) {
        push(@{ $ret }, { 
            args => encode_json($job->{args}),
            id => $job->{id},
            priority => $job->{priority},
            state => $job->{state},
            task => $job->{task},
            queue => $job->{queue},
        });

        last if 30 <= @{ $ret };
    }

    $c->render(json => $ret);
};

get '/v1/job/enqueue' => sub {
    my $c = shift;

    my $task = $c->param("task");
    my $queue = $c->param("queue");
    my $priority = $c->param("priority");
    my $delay = $c->param("delay");
    my $args = decode_json($c->param("args") || "[]");

    my $options = {};

    $options->{priority} = $priority if $priority;
    $options->{delay} = $delay if $delay;
    $options->{queue} = $queue if $queue;

    my $job_id = $c->app->minion->enqueue($task, $args, $options);

    $c->render(json => {job_id => $job_id});
};

app->start;

__DATA__

@@ slash.html.ep

<!DOCTYPE html>
<html>
<head>
    <title></title>
    <link rel="stylesheet" href="http://kendo.cdn.telerik.com/2015.3.930/styles/kendo.common.core.min.css" />
    <link rel="stylesheet" href="http://kendo.cdn.telerik.com/2015.3.930/styles/kendo.common-nova.core.min.css" />
    <link rel="stylesheet" href="http://kendo.cdn.telerik.com/2015.3.930/styles/kendo.mobile.all.min.css" />
    <link rel="stylesheet" href="/epoch.min.css" />
    <link rel="stylesheet" href="/style.css" />

    <script src="http://kendo.cdn.telerik.com/2015.3.930/js/jquery.min.js"></script>
    <script src="http://kendo.cdn.telerik.com/2015.3.930/js/kendo.ui.core.min.js"></script>

    <script src="/d3.min.js"></script>
    <script src="/epoch.min.js"></script>
</head>
<body>

<div data-role="view" id="tabstrip-dashboard" data-title="Dashboard" data-layout="mobile-tabstrip" data-model="model.dashboard" data-show="model.dashboard.show" data-init="model.dashboard.init">
    <script type="text/x-kendo-template" id="dashboard-template">
        <center>
        <table>
            <tr><td>Finished Jobs</td><td>Failed Jobs</td><td>Active Jobs</td><td>Active Workers</td><td>Inactive Workers</td></tr>
            <tr><td>${finished_jobs}</td><td>${failed_jobs}</td><td>${active_jobs}</td><td>${active_workers}</td><td>${inactive_workers}</td></tr>
        </table>
        </center>
    </script>

    <div id="dashboard-header">
    </div>

    <h3><b>Inactive and Active Workers</b></h3>
    <div id="minionWorker" class="epoch" style="height: 200px; margin-top: 15px;" class="epoch"></div>

    <div class='legend' style="margin-left: 20px;">
    <div class='legend-scale'>
      <ul class='legend-labels'>
        <li><span style='background:#ff7f0e;'></span>Inactive</li>
        <li><span style='background:#1f77b4;'></span>Active</li>
      </ul>
    </div>
    </div>

    <h3 style="margin-top: 20px;"><b>Active Jobs</b></h3>
    <div id="minionActiveJobs" class="epoch" style="height: 200px; margin-top: 15px;" class="epoch"></div>

    <div class='legend' style="margin-left: 20px;">
    <div class='legend-scale'>
      <ul class='legend-labels'>
        <li><span style='background:#1f77b4;'></span>Active</li>
      </ul>
    </div>
    </div>

    <h3><b>Finished and Failed Jobs</b></h3>
    <div id="minionOtherJobs" class="epoch" style="height: 200px; margin-top: 15px;" class="epoch"></div>

    <div class='legend' style="margin-left: 20px;">
    <div class='legend-scale'>
      <ul class='legend-labels'>
        <li><span style='background:#ff7f0e;'></span>Finished</li>
        <li><span style='background:#1f77b4;'></span>Failed</li>
      </ul>
    </div>
    </div>

    <center><p><h1>Workers</h1></p></center>

    <ul id="listview-workers">
        <script type="text/x-kendo-template" id="listview-workers-template">
            # if (data.text) { #
                #: data.text #
            # } else { #
                [#: id #] #: host # [#:pid#]
            # } #
        </script>
    </ul>
</div>

<div data-role="view" id="tabstrip-jobs" data-title="Jobs" data-layout="mobile-tabstrip" data-model="model.jobs" data-init="model.jobs.init">
    <ul id="listview-jobs">
        <script type="text/x-kendo-template" id="listview-jobs-template">
            <a data-role="button" class="km-primary km-button-right km-icon-button"><span class="km-icon km-refresh"></span></a>
            # if (data.text) { #
                #: data.text #
            # } else { #
                #: task #: [#: queue #]: [#: id #]<br>
                State: #: state #<br>
                Args: <code>#: args #</code>
            # } #
        </script>
    </ul>
</div>

<div data-role="view" id="tabstrip-actions" data-title="Actions" data-layout="mobile-tabstrip" data-use-native-scrolling="true" data-model="model.actions" data-show="model.actions.show">
     <form>
        <ul data-role="listview" data-style="inset">
            <li>
                <label class="km-required km-label-above"><span>Task name</span>
                    <input value="" type="text" name="task" required>
                </label>
            </li>
            <li>
                <label class="km-label-above">Queue Name
                    <input type="text" value="" name="queue">
                </label>
            </li>
            <li>
                <label class="km-label-above">Priority
                    <input value="" type="text" name="priority">
                </label>
            </li>
            <li>
                <label class="km-label-above">Delay
                    <input value="" type="text" name="delay">
                </label>
            </li>
            <li>
                <fieldset>
                    <legend>Arguments</legend>
                    <textarea style="height: 50px;" placeholder="JSON goes here" name="args" class="k-valid"></textarea>
                </fieldset>
            </li>          
        </ul>
    </form>

    <center><a data-role="button" data-bind="events:{ click: submit }" data-animated="true" data-icon="action" class="km-primary" style="margin-top: 20px;">Submit</a></center>
</div>

<div data-role="modalview" id="modalview-job-enqueue" style="width: 60%;" data-model="model.actions">
    <div data-role="header">
        <div data-role="navbar">
            <span>Results</span>
            <a data-bind="events:{ click: close }" data-role="button" data-align="right">Close</a>
        </div>
    </div>
    
    <script type="text/x-kendo-template" id="enqueue-template">
        <center>
        <h1>#: task #</h1>

        Enqueued into #: queue # as job id #: job_id #
        </center>
    </script>

    <div id="enqueue-results"></div>
</div>

<div data-role="layout" data-id="mobile-tabstrip">
    <header data-role="header">
        <div data-role="navbar">
            <span data-role="view-title"></span>
        </div>
    </header>

    <p>TabStrip</p>

    <div data-role="footer">
        <div data-role="tabstrip">
            <a href="#tabstrip-dashboard" data-icon="globe">Dashboard</a>
            <a href="#tabstrip-jobs" data-icon="history">Jobs</a>
            <a href="#tabstrip-actions" data-icon="action">Actions</a>
        </div>
    </div>
</div>

<script>
    var model = kendo.observable({
        jobs: {
            init: function(e) {
                var model = e.view.model;
                var id = model.listview.id;
                var template = model.listview.template;

                $(id).kendoMobileListView({
                    dataSource: model.dataSource,
                    pullToRefresh: true,            
                    template: $(template).text(),
                    click: function (e) {
                        var params = $.param({
                            task: e.dataItem.task,
                            priority: e.dataItem.priority,
                            queue: e.dataItem.queue,
                            args: e.dataItem.args,
                        });
                        app.navigate("#tabstrip-actions?" + params, "slide");
                    },
                });
            },

            listview: {
                id: "#listview-jobs",
                template: "#listview-jobs-template",
            },

            dataSource: new kendo.data.DataSource({
                transport: {
                    read: {
                        url: "<%= url_for('/v1/jobs/stats')->to_abs %>",
                    }
                }
            })
        },

        actions: {
            show: function(e) {
                console.log(e.view.params);

                if (e.view.params.task) {
                    var element = app.view().element;

                    var form = $(element).find("form");

                    $(element).find("input[name='task']").val(e.view.params.task);
                    $(element).find("input[name='queue']").val(e.view.params.queue);
                    $(element).find("input[name='priority']").val(e.view.params.priority);
                    $(element).find("textarea[name='args']").val(e.view.params.args);
                }
            },
            submit: function(e) {
                var element = app.view().element;

                var form = $(element).find("form");

                var validator = $(form).kendoValidator({
                    errorTemplate: '',
                }).data("kendoValidator");

                $(element).find("form").find("span").css("color", "");
                if (!validator.validate()) {
                    $(element).find("form").find("span").css("color", "red");
                    return;
                }

                app.showLoading();

                var formData = $(form).serialize();
                console.log(formData);

                $.getJSON("<%= url_for("/v1/job/enqueue") %>?" + formData, function(result) {
                    var template = kendo.template($('#enqueue-template').text());
                    var html = template({
                        task: $(element).find("input[name='task']").val(),
                        queue: $(element).find("input[name='queue']").val() || "default",
                        job_id: result.job_id
                    });
                    $('#enqueue-results').html(html);

                    app.hideLoading();

                    $('#modalview-job-enqueue').data("kendoMobileModalView").open();
                });
            },
            close: function(e) {
                $('#modalview-job-enqueue').data("kendoMobileModalView").close();
            },
        },

        dashboard: {
            workerGraph: null,
            minionActiveJobs: null,
            minionOtherJobs: null,

            init: function(e) {
                $(function() {
                    var inAjax = false;
                    var whence = (new Date()).getTime() - 4000; // start immediately

                    var workerData = {
                        workerGraph: null,
                        minionActiveJobs: null,
                        workerOtherJobs: null,
                    };

                    updWorkerData();

                    function updWorkerData() {
                        var n = (new Date()).getTime() - whence;

                        if ("Dashboard" === app.view().title && !inAjax && n >= 3000) {
                            whence = (new Date()).getTime();

                            $.ajax({
                                url: "<%= url_for("/v1/minion/stats") %>",
                                dataType: 'json',
                                async: true,
                                success: function(result) {
                                    var template = kendo.template($('#dashboard-template').text());
                                    var html = template(result) 
                                    $('#dashboard-header').html(html);

                                    if (null != app.view().model.workerGraph) {
                                        var data = [
                                            { time: result.epoch, y: result.active_workers },
                                            { time: result.epoch, y: result.inactive_workers },
                                        ];

                                        workerData.workerGraph = data;

                                        app.view().model.workerGraph.push(data);
                                    }

                                    if (null != app.view().model.minionActiveJobs) {
                                        var data = [
                                            { time: result.epoch, y: result.active_jobs }
                                        ];

                                        workerData.minionActiveJobs = data;

                                        app.view().model.minionActiveJobs.push(data);
                                    }

                                    if (null != app.view().model.minionOtherJobs) {
                                        var data = [
                                            { time: result.epoch, y: result.failed_jobs },
                                            { time: result.epoch, y: result.finished_jobs },
                                        ];

                                        workerData.minionOtherJobs = data;

                                        app.view().model.minionOtherJobs.push(data);
                                    }

                                    inAjax = false;
                                },
                                error: function() {
                                    inAjax = false;
                                }
                            });
                        }
                        else if ("Dashboard" === app.view().title) {
                            var m = app.view().model;

                            if (m.workerGraph && workerData.workerGraph) {
                                m.workerGraph.push(workerData.workerGraph);
                            }

                            if (m.minionActiveJobs && workerData.minionActiveJobs) {
                                m.minionActiveJobs.push(workerData.minionActiveJobs);
                            }

                            if (m.minionOtherJobs && workerData.minionOtherJobs) {
                                m.minionOtherJobs.push(workerData.minionOtherJobs);
                            }
                        }

                        setTimeout(updWorkerData, 300);
                    }
                });
            },

            show: function(e) {
                var model = e.view.model;

                $.getJSON("<%= url_for("/v1/minion/stats") %>", function(result) {
                    var template = kendo.template($('#dashboard-template').text());
                    var html = template(result) 
                    $('#dashboard-header').html(html);

                    model.workerGraph = $('#minionWorker').epoch({
                        type: 'time.line',
                        axes: ['left', 'bottom', 'right'],
                        data: [
                            {
                                label: "Active",
                                values: [ { time: result.epoch, y: result.active_workers } ]
                            },
                            {
                                label: "Inactive",
                                values: [ { time: result.epoch, y: result.inactive_workers } ]
                            } 
                        ]
                    });

                    model.minionActiveJobs = $('#minionActiveJobs').epoch({
                        type: 'time.line',
                        axes: ['left', 'bottom', 'right'],
                        data: [
                            {
                                label: "Active",
                                values: [ { time: result.epoch, y: result.active_jobs } ]
                            }
                        ]
                    });

                    model.minionOtherJobs = $('#minionOtherJobs').epoch({
                        type: 'time.area',
                        axes: ['left', 'bottom', 'right'],
                        data: [
                            {
                                label: "Failed",
                                values: [ { time: result.epoch, y: result.failed_jobs } ]
                            },
                            {
                                label: "Finished",
                                values: [ { time: result.epoch, y: result.finished_jobs } ]
                            },
                        ]
                    });
                });

                var m = model.workers;
                var id = m.listview.id;
                var template = m.listview.template;

                $(id).kendoMobileListView({
                    dataSource: m.dataSource,
                    template: $(template).text(),
                });
            },

            workers: {
                listview: {
                    id: "#listview-workers",
                    template: "#listview-workers-template",
                },

                dataSource: new kendo.data.DataSource({
                    transport: {
                        read: {
                            url: "<%= url_for('/v1/workers/stats')->to_abs %>",
                        }
                    },
                    schema: {
                        data: function(response) {
                            var ret = [];

                            $.each(response, function(idx, value) {
                                ret.push({
                                    id: value.id,
                                    host: value.host,
                                    pid: value.pid,
                                });
                            });

                            if (0 === ret.length) {
                                return [{ text: "No workers" }];
                            }

                            return ret;
                        }
                    }
                }),
            },
        },
    });

    var app = new kendo.mobile.Application(document.body, { 
        skin: "nova",
    });
</script>
</body>
</html>
