# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

require 'uri'
require 'cgi'

if AppOpticsAPM.loaded
  module AppOpticsAPM
    ##
    # AppOpticsAPM::Rack
    #
    # The AppOpticsAPM::Rack middleware used to sample a subset of incoming
    # requests for instrumentation and reporting.  Tracing context can
    # be received here (via the X-Trace HTTP header) or initiated here
    # based on configured tracing mode.
    #
    # After the rack layer passes on to the following layers (Rails, Sinatra,
    # Padrino, Grape), then the instrumentation downstream will
    # automatically detect whether this is a sampled request or not
    # and act accordingly. (to instrument or not)
    #
    class Rack
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call(env)
        # if we are already propagating, sampling, etc. don't start again
        # TODO this is too broad
        incoming = AppOpticsAPM::Context.isValid
        return @app.call(env) if AppOpticsAPM.tracing? && AppOpticsAPM.layer == :rack

        AppOpticsAPM.transaction_name = nil

        url = env['PATH_INFO']
        xtrace = AppOpticsAPM::XTrace.valid?(env['HTTP_X_TRACE']) ? (env['HTTP_X_TRACE']) : nil
        filter = AppOpticsAPM::TransactionSettings.new(url, xtrace)
        result = [500, {}, nil]

        propagate_xtrace(env, filter, xtrace) do
          sample(env, filter) do
            metrics(env, filter) do
              result = @app.call(env)
            end
          end
        end

        AppOpticsAPM::Context.clear unless incoming
        result
        # No metrics and traces when in never mode.
        # In the case of nested Ruby apps such as Grape inside of Rails
        # or Grape inside of Grape, each app has it's own instance
        # of rack middleware. We avoid tracing rack more than once and
        # instead start instrumenting from the first rack pass.
        # if (AppOpticsAPM.tracing? && AppOpticsAPM.layer == :rack) ||
        #   AppOpticsAPM::Util.asset?(env['PATH_INFO'])
        #
        #   return call_app(env)
        # end
        #
        # # create a non-sampling context for never requests
        # if AppOpticsAPM.tracing_disabled? || AppOpticsAPM::Util.tracing_disabled?(env['PATH_INFO'])
        #
        #   return tracing_disabled_call(env)
        # end
        #
        # # don't send metrics if we already have a context
        # return sampling_call(env) if AppOpticsAPM::Context.isValid
        #
        # # else we also send metrics
        # metrics_sampling_call(env)
      rescue Exception => e
        AppOpticsAPM::Context.clear unless incoming
        raise e
      end

      def self.noop?
        false
      end

      private

      def extract_xtrace(env)
        # xtrace = env.is_a?(Hash) ? env['HTTP_X_TRACE'] : nil
        xtrace = env['HTTP_X_TRACE']
        AppOpticsAPM::XTrace.valid?(xtrace) ? xtrace : nil
      end

      def collect(env, filter)
        req = ::Rack::Request.new(env)
        report_kvs = {}

        begin
          report_kvs[:'HTTP-Host']      = req.host
          report_kvs[:Port]             = req.port
          report_kvs[:Proto]            = req.scheme
          report_kvs[:Method]           = req.request_method
          report_kvs[:AJAX]             = true if req.xhr?
          report_kvs[:ClientIP]         = req.ip

          if AppOpticsAPM::Config[:rack][:log_args]
            report_kvs[:'Query-String'] = ::CGI.unescape(req.query_string) unless req.query_string.empty?
          end

          report_kvs[:URL] = AppOpticsAPM::Config[:rack][:log_args] ? ::CGI.unescape(req.fullpath) : ::CGI.unescape(req.path)
          report_kvs[:Backtrace] = AppOpticsAPM::API.backtrace if AppOpticsAPM::Config[:rack][:collect_backtraces]
          report_kvs[:SampleRate]        = filter.rate
          report_kvs[:SampleSource]      = filter.source

          # Report any request queue'ing headers.  Report as 'Request-Start' or the summed Queue-Time
          report_kvs[:'Request-Start']     = env['HTTP_X_REQUEST_START']    if env.key?('HTTP_X_REQUEST_START')
          report_kvs[:'Request-Start']     = env['HTTP_X_QUEUE_START']      if env.key?('HTTP_X_QUEUE_START')
          report_kvs[:'Queue-Time']        = env['HTTP_X_QUEUE_TIME']       if env.key?('HTTP_X_QUEUE_TIME')

          report_kvs[:'Forwarded-For']     = env['HTTP_X_FORWARDED_FOR']    if env.key?('HTTP_X_FORWARDED_FOR')
          report_kvs[:'Forwarded-Host']    = env['HTTP_X_FORWARDED_HOST']   if env.key?('HTTP_X_FORWARDED_HOST')
          report_kvs[:'Forwarded-Proto']   = env['HTTP_X_FORWARDED_PROTO']  if env.key?('HTTP_X_FORWARDED_PROTO')
          report_kvs[:'Forwarded-Port']    = env['HTTP_X_FORWARDED_PORT']   if env.key?('HTTP_X_FORWARDED_PORT')

          report_kvs[:'Ruby.AppOptics.Version'] = AppOpticsAPM::Version::STRING
          report_kvs[:ProcessID]         = Process.pid
          report_kvs[:ThreadID]          = Thread.current.to_s[/0x\w*/]
        rescue StandardError => e
          # Discard any potential exceptions. Debug log and report whatever we can.
          AppOpticsAPM.logger.debug "[appoptics_apm/debug] Rack KV collection error: #{e.inspect}"
        end
        report_kvs
      end

      # def start_metrics(env)
      #   return yield unless @filter.do_metrics
      #
      #   start = Time.now
      #   AppOpticsAPM.transaction_name = nil
      #   req = ::Rack::Request.new(env)
      #   req_url = req.url   # saving it here because rails3.2 overrides it when there is a 500 error
      #   # status = 500
      #
      #   status, _headers, _response = yield(env)
      #   confirmed_transaction_name = send_metrics(env, req, req_url, start, status)
      # end

      def propagate_xtrace(env, filter, xtrace)
        return yield unless filter.do_propagate

        if xtrace
          xtrace_local = xtrace
          AppOpticsAPM::XTrace.unset_sampled(xtrace_local) unless filter.do_sample
          AppOpticsAPM::Context.fromString(xtrace_local)
          env['HTTP_X_TRACE'] = xtrace_local

          status, headers, response = yield

          headers['X-Trace'] ||= xtrace # && headers.is_a?(Hash)
        else
          AppOpticsAPM::Context.set(AppOpticsAPM::Metadata.makeRandom(filter.do_sample))
          env['HTTP_X_TRACE'] = AppOpticsAPM::Context.toString

          status, headers, response = yield
          headers ||= {}
          headers['X-Trace'] ||= AppOpticsAPM::Context.toString if AppOpticsAPM::Context.isValid
        end

        [status, headers, response]
      end

      # In this case we have an existing context from a recursive rack call
      # don't need to handle headers, they will be handled
      # by the upstream metrics_sampling_call
      # def sampling_call(env)
      #   report_kvs = collect(env)
      #
      #   AppOpticsAPM::API.trace(:rack, report_kvs) do
      #     @app.call(env)
      #   end
      # end

      # def metrics_sampling_call(env, metrics)
      def sample(env, filter)
        return yield unless filter.do_sample

        report_kvs = collect(env, filter)

        # Check for and validate X-Trace request header to pick up tracing context
        # xtrace = env.is_a?(Hash) ? env['HTTP_X_TRACE'] : nil
        # xtrace = env['HTTP_X_TRACE']
        # xtrace = AppOpticsAPM::XTrace.valid?(xtrace) ? xtrace : nil

        # TODO JRUBY
        # Under JRuby, JAppOpticsAPM may have already started a trace.  Make note of this
        # if so and don't clear context on log_end (see appoptics_apm/api/logging.rb)
        # AppOpticsAPM.has_incoming_context = AppOpticsAPM.tracing?
        # AppOpticsAPM.has_xtrace_header = xtrace
        # AppOpticsAPM.is_continued_trace = AppOpticsAPM.has_incoming_context || AppOpticsAPM.has_xtrace_header
        AppOpticsAPM::API.log_entry(:rack, report_kvs)
        # AppOpticsAPM::SDK.start_trace(:rack, xtrace, report_kvs) do

        status, headers, response = yield
        # report_kvs.clear
        # report_kvs[:TransactionName] = AppOpticsAPM.transaction_name
        # report_kvs[:Status] = status
        # end
        xtrace =
          AppOpticsAPM::API.log_exit(:rack,
                                     :Status => status,
                                     :TransactionName => AppOpticsAPM.transaction_name)

        headers['X-Trace'] = xtrace if headers.is_a?(Hash) # headers can be nil here

        # TODO revisit this JRUBY condition
        # headers['X-Trace'] = xtrace if headers.is_a?(Hash) unless defined?(JRUBY_VERSION) && AppOpticsAPM.is_continued_trace?
        # headers['X-Trace'] = xtrace #if headers.is_a?(Hash)

        [status, headers, response]
      rescue Exception => e
        # it is ok to rescue Exception here because we are reraising it (we just need a chance to log_end)
        AppOpticsAPM::API.log_exception(:rack, e)
        # confirmed_transaction_name ||= metrics.send(env, req, req_url, start, status)
        xtrace =
          AppOpticsAPM::API.log_exit(:rack,
                                     :Status => status,
                                       :TransactionName => AppOpticsAPM.transaction_name)

        headers['X-Trace'] = xtrace if headers.is_a?(Hash) # headers can be nil here
        # TODO revisit this JRUBY condition
        # headers['X-Trace'] = xtrace if headers.is_a?(Hash) unless defined?(JRUBY_VERSION) && AppOpticsAPM.is_continued_trace?
        # headers['X-Trace'] = xtrace #if headers.is_a?(Hash)

        raise
      end

      def metrics(env, filter)
        status, headers, response = 500, {}, nil

        TransactionMetrics.start_metrics(env, filter) do
          status, headers, response = yield
        end

        [status, headers, response]
      end

      # def send_metrics(env, req, req_url, start, status)
      #   status = status.to_i
      #   error = status.between?(500,599) ? 1 : 0
      #   duration =(1000 * 1000 * (Time.now - start)).round(0)
      #   method = req.request_method
      #   AppOpticsAPM::Span.createHttpSpan(transaction_name(env), req_url, domain(req), duration, status, method, error) || ''
      # end
      #
      # def domain(req)
      #   if AppOpticsAPM::Config['transaction_name']['prepend_domain']
      #     [80, 443].include?(req.port) ? req.host : "#{req.host}:#{req.port}"
      #   end
      # end
      #
      # def transaction_name(env)
      #   if AppOpticsAPM.transaction_name
      #     AppOpticsAPM.transaction_name
      #   elsif env['appoptics_apm.controller'] && env['appoptics_apm.action']
      #     [env['appoptics_apm.controller'], env['appoptics_apm.action']].join('.')
      #   end
      # end

    end
  end
else
  module AppOpticsAPM
    class Rack
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      end

      def self.noop?
        true
      end
    end
  end
end
