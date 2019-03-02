# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

require 'minitest_helper'
require 'appoptics_apm/inst/rack'
require 'mocha/minitest'

describe "Rack: " do

  def restart_rack
    @rack = AppOpticsAPM::Rack.new(@app)
  end

  before do
    @tracing_mode = AppOpticsAPM::Config.tracing_mode
    @dnt = AppOpticsAPM::Config.dnt_compiled
    @transactions = AppOpticsAPM::Util.deep_dup(AppOpticsAPM::Config[:transaction_settings])

    @app = mock('app')
    def @app.call(_)
      [200, {}, "response"]
    end
    @rack = AppOpticsAPM::Rack.new(@app)
  end

  after do
    AppOpticsAPM::Config.tracing_mode = @tracing_mode
    AppOpticsAPM::Config.dnt_compiled = @dnt
    AppOpticsAPM::Config[:transaction_settings] = AppOpticsAPM::Util.deep_dup(@transactions)
  end

  # the following is a common situation for grape, which,
  # when instrumented, calls AppOpticsAPM::Rack#call 3 times
  describe 'A - when we are tracing and the layer is rack' do
    it 'calls @app.call' do
      @rack.app.expects(:call)

      AppOpticsAPM::API.start_trace(:rack) do
        @rack.call({})
        assert AppOpticsAPM::Context.isValid
      end

      refute AppOpticsAPM::Context.isValid
    end

    it "does not call createHttpSpan" do
      AppOpticsAPM::API.start_trace(:rack) do
        AppOpticsAPM::API.expects(:log_start).never
        AppOpticsAPM::Span.expects(:createHttpSpan).never

        _, header, _ = @rack.call({})
        assert AppOpticsAPM::Context.isValid

        refute header['X-Trace']
      end
      refute AppOpticsAPM::Context.isValid
    end

    it "does not return an xtrace header" do
      header = nil

      AppOpticsAPM::API.start_trace(:rack) do
        _, header, _ = @rack.call({})
        assert AppOpticsAPM::Context.isValid
      end

      refute header['X-Trace']
      refute AppOpticsAPM::Context.isValid
    end
  end

  describe 'B - asset?' do
    it 'ignores dnt if there is no :dnt_compiled' do
      AppOpticsAPM::API.expects(:log_start).twice
      AppOpticsAPM::Span.expects(:createHttpSpan).twice

      AppOpticsAPM::Config.dnt_compiled = nil

      _, headers_1, _ = @rack.call({})
      _, headers_2, _ = @rack.call({ 'PATH_INFO' => '/blablabla/test' })

      AppOpticsAPM::XTrace.valid?(headers_1['X-Trace'])
      AppOpticsAPM::XTrace.valid?(headers_2['X-Trace'])
      refute AppOpticsAPM::Context.isValid
    end

    it 'does not send metrics/traces when dnt matches' do
      AppOpticsAPM::API.expects(:log_start).never
      AppOpticsAPM::Span.expects(:createHttpSpan).never

      AppOpticsAPM::Config.dnt_compiled = Regexp.new('.*test$')
      restart_rack

      _, headers, _ = @rack.call({ 'PATH_INFO' => '/blablabla/test' })

      refute headers['X-Trace']
      refute AppOpticsAPM::Context.isValid
    end

    it 'sends metrics/traces when dnt does not match' do
      AppOpticsAPM::API.expects(:log_start).once
      AppOpticsAPM::Span.expects(:createHttpSpan).once

      AppOpticsAPM::Config.dnt_compiled = Regexp.new('.*rainbow$')
      restart_rack

      _, headers, _ = @rack.call({ 'PATH_INFO' => '/blablabla/test' })

      AppOpticsAPM::XTrace.valid?(headers['X-Trace'])
      refute AppOpticsAPM::Context.isValid
    end
  end

  describe 'C - when tracing_mode is :never' do
    it 'does not send metrics or traces for :never' do
      AppOpticsAPM::API.expects(:log_start).never
      AppOpticsAPM::Span.expects(:createHttpSpan).never

      AppOpticsAPM::Config.tracing_mode = :never
      _, headers, _ = @rack.call({})

      assert AppOpticsAPM::XTrace.valid?(headers['X-Trace'])
      refute AppOpticsAPM::XTrace.sampled?(headers['X-Trace'])
      refute AppOpticsAPM::Context.isValid
    end
 end

  describe 'D - tracing disabled for path' do
    it 'sends metrics and traces when not disabled' do
      AppOpticsAPM::API.expects(:log_start).once
      AppOpticsAPM::Span.expects(:createHttpSpan).once

      AppOpticsAPM::Config.tracing_mode = :always
      AppOpticsApm::Config[:transaction_settings] = { url: [{ regexp: /that/ }] }

      @rack.call({ 'PATH_INFO' => '/this_one/test' })
    end

    it 'sets a sampled x-trace header when not disabled' do
      AppOpticsAPM::Config.tracing_mode = :always
      AppOpticsApm::Config[:transaction_settings] = { url: [{ regexp: /that/ }] }

      _, headers, _ = @rack.call({ 'PATH_INFO' => '/this_one/test' })

      assert AppOpticsAPM::XTrace.valid?(headers['X-Trace'])
      assert AppOpticsAPM::XTrace.sampled?(headers['X-Trace'])
      refute AppOpticsAPM::Context.isValid
    end

    it 'does not send metrics and traces when disabled' do
      @app.expects(:call).returns([200, {}, ''])
      AppOpticsAPM::API.expects(:log_start).never
      AppOpticsAPM::Span.expects(:createHttpSpan).never

      AppOpticsAPM::Config.tracing_mode = :always
      AppOpticsApm::Config[:transaction_settings] = { url: [{ regexp: /this_one/ }] }

      @rack.call({ 'PATH_INFO' => '/this_one/test' })
    end

    it 'returns an unsampled x-trace header when disabled' do
      AppOpticsAPM::Config.tracing_mode = :always
      AppOpticsApm::Config[:transaction_settings] = { url: [{ regexp: /this_one/ }] }

      _, headers, _ = @rack.call({ 'PATH_INFO' => '/this_one/test' })

      assert AppOpticsAPM::XTrace.valid?(headers['X-Trace'])
      refute AppOpticsAPM::XTrace.sampled?(headers['X-Trace'])
      refute AppOpticsAPM::Context.isValid
    end
  end

  describe 'E - when there is a context not from rack' do

    it 'should log a an entry and exit' do
      AppOpticsAPM::API.start_trace(:other) do
        AppOpticsAPM::API.expects(:log_start)
        AppOpticsAPM::API.expects(:log_exit)
        AppOpticsAPM::Span.expects(:createHttpSpan).never

        @rack.call({})
      end
    end

    it 'should log exit even when there is an exception' do
      AppOpticsAPM::API.expects(:log_exit)

      assert_raises StandardError do
        AppOpticsAPM::API.start_trace(:other) do
          def @app.call(_); raise StandardError; end
          @rack.call({})
          assert AppOpticsAPM::Context.isValid
        end
      end
    end

    it "should call the app's call method" do
      @rack.app.expects(:call)

      AppOpticsAPM::API.start_trace(:other) do
        @rack.call({})
        assert AppOpticsAPM::Context.isValid
      end

      refute AppOpticsAPM::Context.isValid
    end

  end

  describe 'F - when there is no context' do

    it 'should start/end a trace and send metrics' do
      AppOpticsAPM::API.expects(:log_start)
      AppOpticsAPM::API.expects(:log_exit)
      AppOpticsAPM::Span.expects(:createHttpSpan)

      @rack.call({})
    end

    it 'should return an x-trace header' do
      _, headers, _ = @rack.call({})

      assert AppOpticsAPM::XTrace.valid?(headers['X-Trace'])
      assert AppOpticsAPM::XTrace.sampled?(headers['X-Trace'])
      refute AppOpticsAPM::Context.isValid
    end

    it 'should start/end a trace and send metrics when there is an exception' do
      def @app.call(_); raise StandardError; end

      AppOpticsAPM::API.expects(:log_start)
      AppOpticsAPM::API.expects(:log_exit)
      AppOpticsAPM::Span.expects(:createHttpSpan)

      assert_raises StandardError do
        @rack.call({})
      end
    end

    it "should clear the context if there is an exception" do
      def @app.call(_); raise StandardError; end
      begin
        @rack.call({})
      rescue
      end

      refute AppOpticsAPM::Context.isValid
    end

    it "should call the app's call method" do
      @rack.app.expects(:call)

      @rack.call({})

      refute AppOpticsAPM::Context.isValid
    end

  end

  describe 'G - when there is a non-sampling context' do
    it 'returns a non sampling header' do
      AppOpticsAPM::Context.fromString('2B7435A9FE510AE4533414D425DADF4E180D2B4E3649E60702469DB05F00')
      _, headers, _ = @rack.call({})

      assert AppOpticsAPM::XTrace.valid?(headers['X-Trace'])
      refute AppOpticsAPM::XTrace.sampled?(headers['X-Trace'])
      assert AppOpticsAPM::Context.isValid
    end

    it 'does not trace or send metrics' do
      AppOpticsAPM::Context.fromString('2B7435A9FE510AE4533414D425DADF4E180D2B4E3649E60702469DB05F00')

      AppOpticsAPM::API.expects(:log_start).never
      AppOpticsAPM::Span.expects(:createHttpSpan).never

      @rack.call({})
    end
  end
end