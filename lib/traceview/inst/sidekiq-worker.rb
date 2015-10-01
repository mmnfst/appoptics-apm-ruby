module TraceView
  class SidekiqWorker
    def collect_kvs(args)
      begin
        # Attempt to collect up pertinent info.  If we hit something unexpected,
        # keep calm and instrument on.

        report_kvs = {}
        _, msg, queue = args

        report_kvs['Backtrace'] = TV::API.backtrace if TV::Config[:sidekiqworker][:collect_backtraces]

        # Background Job Spec KVs
        report_kvs[:Spec] = :job
        report_kvs[:JobName] = msg['class']
        report_kvs[:JobID] = msg['jid']
        report_kvs[:Source] = msg['queue']
        report_kvs[:Args] = msg['args'].to_s[0..1024] if TraceView::Config[:sidekiqworker][:log_args]

        # Webserver Spec KVs
        report_kvs['HTTP-Host'] = Socket.gethostname
        report_kvs[:Controller] = "Sidekiq_#{queue}"
        report_kvs[:Action] = msg['class']
        report_kvs[:URL] = "/sidekiq/#{queue}/#{msg['class'].to_s}"
      rescue => e
        TraceView.logger.warn "[traceview/sidekiq] Non-fatal error capturing KVs: #{e.message}"
      end
      report_kvs
    end

    def call(*args)
      # args: 0: worker, 1: msg, 2: queue
      result = nil
      report_kvs = collect_kvs(args)

      # Continue the trace from the enqueue side?
      incoming_context = nil
      if TraceView::XTrace.valid?(args[1]['X-Trace'])
        incoming_context = args[1]['X-Trace']
        report_kvs[:Async] = true
      end

      result = TraceView::API.start_trace('sidekiq-worker', incoming_context, report_kvs) do
        yield
      end

      result[0]
    end
  end
end

if defined?(::Sidekiq) && RUBY_VERSION >= '2.0' && TraceView::Config[:sidekiqworker][:enabled]
  ::TraceView.logger.info '[traceview/loading] Instrumenting sidekiq' if TraceView::Config[:verbose]

  ::Sidekiq.configure_server do |config|
    config.server_middleware do |chain|
      ::TraceView.logger.info '[traceview/loading] Adding Sidekiq worker middleware' if TraceView::Config[:verbose]
      chain.add ::TraceView::SidekiqWorker
    end
  end
end