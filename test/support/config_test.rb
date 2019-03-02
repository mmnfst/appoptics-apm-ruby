# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

require 'minitest_helper'
require 'mocha/minitest'

class ConfigTest
  describe "AppOpticsAPM::Config" do

    @@default_config_path = File.join(Dir.pwd, 'appoptics_apm_config.rb')
    @@test_config_path = File.join(File.dirname(__FILE__), 'appoptics_apm_config.rb')
    @@template = File.join(File.dirname(File.dirname(File.dirname(__FILE__))),
                           'lib/rails/generators/appoptics_apm/templates/appoptics_apm_initializer.rb')
    @@rails_config_path = File.join(Dir.pwd, 'config', 'initializers', 'appoptics_apm.rb')
    FileUtils.mkdir_p(File.join(Dir.pwd, 'config', 'initializers'))

    before do
      @loaded = AppOpticsAPM.loaded

      @config_mode = AppOpticsAPM::Config[:tracing_mode]
      @config_rate = AppOpticsAPM::Config[:sample_rate]
      @config_verbose = AppOpticsAPM::Config[:verbose]
      @config_key = AppOpticsAPM::Config[:service_key]
      @config_alias = AppOpticsAPM::Config[:hostname_alias]
      @config_level = AppOpticsAPM::Config[:debug_level]
      @config_regexp = AppOpticsAPM::Config[:dnt_regexp]

      @log_level = AppOpticsAPM.logger.level

      @env_config = ENV['APPOPTICS_APM_CONFIG_RUBY']
      @env_key = ENV['APPOPTICS_SERVICE_KEY']
      @env_alias = ENV['APPOPTICS_HOSTNAME_ALIAS']
      @env_debug = ENV['APPOPTICS_DEBUG_LEVEL']
      @env_verbose = ENV['APPOPTICS_GEM_VERBOSE']

      ENV.delete('APPOPTICS_APM_CONFIG_RUBY')
      ENV.delete('APPOPTICS_SERVICE_KEY')
      ENV.delete('APPOPTICS_HOSTNAME_ALIAS')
      ENV.delete('APPOPTICS_DEBUG_LEVEL')
      ENV.delete('APPOPTICS_GEM_VERBOSE')

      AppOpticsAPM::Config[:service_key] = nil
      AppOpticsAPM::Config[:hostname_alias] = nil
      AppOpticsAPM::Config[:debug_level] = nil
      AppOpticsAPM::Config[:verbose] = nil
    end

    after do
      ENV.delete('APPOPTICS_APM_CONFIG_RUBY')
      ENV.delete('APPOPTICS_SERVICE_KEY')
      ENV.delete('APPOPTICS_HOSTNAME_ALIAS')
      ENV.delete('APPOPTICS_DEBUG_LEVEL')
      ENV.delete('APPOPTICS_GEM_VERBOSE')

      ENV['APPOPTICS_APM_CONFIG_RUBY'] = @env_config  if @env_config
      ENV['APPOPTICS_SERVICE_KEY']     = @env_key     if @env_key
      ENV['APPOPTICS_HOSTNAME_ALIAS']  = @env_alias   if @env_alias
      ENV['APPOPTICS_DEBUG_LEVEL']     = @env_debug   if @env_debug
      ENV['APPOPTICS_GEM_VERBOSE']     = @env_verbose if @env_verbose

      FileUtils.rm(@@default_config_path, :force => true)
      FileUtils.rm(@@rails_config_path, :force => true)
      FileUtils.rm(@@test_config_path, :force => true)

      AppOpticsAPM.logger.level = @log_level

      AppOpticsAPM::Config[:tracing_mode] = @config_mode
      AppOpticsAPM::Config[:sample_rate] = @config_rate
      AppOpticsAPM::Config[:verbose] = @config_verbose
      AppOpticsAPM::Config[:service_key] = @config_key
      AppOpticsAPM::Config[:hostname_alias] = @config_alias
      AppOpticsAPM::Config[:debug_level] = @config_level
      AppOpticsAPM::Config[:dnt_regexp] = @config_regexp

      AppOpticsAPM.loaded = @loaded
    end

    it 'should read the settings from the config file' do
      File.open(@@default_config_path, 'w') do |f|
        f.puts "AppOpticsAPM::Config[:service_key] = '11111111-1111-1111-1111-111111111111:the_service_name'"
        f.puts "AppOpticsAPM::Config[:hostname_alias] = 'my_service'"
        f.puts "AppOpticsAPM::Config[:debug_level] = 6"
        f.puts "AppOpticsAPM::Config[:verbose] = true"
      end
      ENV['APPOPTICS_APM_CONFIG_RUBY'] = @@default_config_path
      AppOpticsAPM::Config.load_config_file

      ENV['APPOPTICS_SERVICE_KEY'].must_be_nil
      AppOpticsAPM::Config[:service_key].must_equal '11111111-1111-1111-1111-111111111111:the_service_name'

      ENV['APPOPTICS_HOSTNAME_ALIAS'].must_be_nil
      AppOpticsAPM::Config[:hostname_alias].must_equal 'my_service'

      # logging happens in 2 places, oboe and ruby, we translate
      ENV['APPOPTICS_DEBUG_LEVEL'].must_be_nil
      AppOpticsAPM::Config[:debug_level].must_equal 6
      AppOpticsAPM.logger.level.must_equal Logger::DEBUG

      ENV['APPOPTICS_GEM_VERBOSE'].must_be_nil
      AppOpticsAPM::Config[:verbose].must_equal true
    end

    it 'should NOT override env vars with config file settings' do
       ENV['APPOPTICS_SERVICE_KEY'] = '22222222-2222-2222-2222-222222222222:the_service_name'
       ENV['APPOPTICS_HOSTNAME_ALIAS'] = 'my_other_service'
       ENV['APPOPTICS_DEBUG_LEVEL'] = '2'
       ENV['APPOPTICS_GEM_VERBOSE'] = 'TRUE'

       File.open(@@default_config_path, 'w') do |f|
         f.puts "AppOpticsAPM::Config[:service_key] = '11111111-1111-1111-1111-111111111111:the_service_name'"
         f.puts "AppOpticsAPM::Config[:hostname_alias] = 'my_service'"
         f.puts "AppOpticsAPM::Config[:debug_level] = 6"
         f.puts "AppOpticsAPM::Config[:verbose] = false"
       end
       ENV['APPOPTICS_APM_CONFIG_RUBY'] = @@default_config_path
       AppOpticsAPM::Config.load_config_file

       ENV['APPOPTICS_SERVICE_KEY'].must_equal '22222222-2222-2222-2222-222222222222:the_service_name'
       ENV['APPOPTICS_HOSTNAME_ALIAS'].must_equal 'my_other_service'
       ENV['APPOPTICS_DEBUG_LEVEL'].must_equal '2'
       AppOpticsAPM.logger.level.must_equal Logger::WARN
       ENV['APPOPTICS_GEM_VERBOSE'].must_equal 'TRUE'
       AppOpticsAPM::Config[:verbose].must_equal true
    end

    it 'tests the env service key' do
      AppOpticsAPM.logger.level = Logger::ERROR

      ENV['APPOPTICS_SERVICE_KEY'] = nil
      AppOpticsAPM::Reporter.valid_service_key?.must_equal false

      ENV['APPOPTICS_SERVICE_KEY'] = '22222222-2222-2222-2222-222222222222:service'
      AppOpticsAPM::Reporter.valid_service_key?.must_equal false

      ENV['APPOPTICS_SERVICE_KEY'] = '1234567890123456789012345678901234567890123456789012345678901234'
      AppOpticsAPM::Reporter.valid_service_key?.must_equal false

      ENV['APPOPTICS_SERVICE_KEY'] = '1234567890123456789012345678901234567890123456789012345678901234:'
      AppOpticsAPM::Reporter.valid_service_key?.must_equal false

      ENV['APPOPTICS_SERVICE_KEY'] = '1234567890123456789012345678901234567890123456789012345678901234:service'
      AppOpticsAPM::Reporter.valid_service_key?.must_equal true
    end

    it 'tests the config service_key when there is no env' do
      AppOpticsAPM.logger.level = Logger::ERROR
      ENV['APPOPTICS_SERVICE_KEY'] = nil

      AppOpticsAPM::Config[:service_key] = nil
      AppOpticsAPM::Reporter.valid_service_key?.must_equal false

      AppOpticsAPM::Config[:service_key] = '22222222-2222-2222-2222-222222222222:service'
      AppOpticsAPM::Reporter.valid_service_key?.must_equal false

      AppOpticsAPM::Config[:service_key] = '1234567890123456789012345678901234567890123456789012345678901234'
      AppOpticsAPM::Reporter.valid_service_key?.must_equal false

      AppOpticsAPM::Config[:service_key] = '1234567890123456789012345678901234567890123456789012345678901234:'
      AppOpticsAPM::Reporter.valid_service_key?.must_equal false

      AppOpticsAPM::Config[:service_key] = '1234567890123456789012345678901234567890123456789012345678901234:service'
      AppOpticsAPM::Reporter.valid_service_key?.must_equal true

      ENV['APPOPTICS_SERVICE_KEY'] = 'blabla'
      AppOpticsAPM::Config[:service_key] = '1234567890123456789012345678901234567890123456789012345678901234:service'
      AppOpticsAPM::Reporter.valid_service_key?.must_equal false
    end

    it 'should use default when there is a wrong debug level setting' do
      File.open(@@default_config_path, 'w') do |f|
        f.puts "AppOpticsAPM::Config[:debug_level] = 7"
      end
      ENV['APPOPTICS_APM_CONFIG_RUBY'] = @@default_config_path
      AppOpticsAPM::Config.load_config_file

      ENV['APPOPTICS_DEBUG_LEVEL'].must_be_nil
      AppOpticsAPM::Config[:debug_level].must_equal 3
      AppOpticsAPM.logger.level.must_equal Logger::INFO
    end

    it 'should accept -1 (disable logging)' do
      File.open(@@default_config_path, 'w') do |f|
        f.puts "AppOpticsAPM::Config[:debug_level] = -1"
      end
      ENV['APPOPTICS_APM_CONFIG_RUBY'] = @@default_config_path
      AppOpticsAPM::Config.load_config_file

      ENV['APPOPTICS_DEBUG_LEVEL'].must_be_nil
      AppOpticsAPM::Config[:debug_level].must_equal -1
      AppOpticsAPM.logger.level.must_equal 6
    end

    it "should accept 'true'/'TRUE'/'True'/... as true for VERBOSE" do
      File.open(@@default_config_path, 'w') do |f|
        f.puts "AppOpticsAPM::Config[:verbose] = false"
      end
      ENV['APPOPTICS_APM_CONFIG_RUBY'] = @@default_config_path
      ENV['APPOPTICS_GEM_VERBOSE'] = 'FALSE'
      AppOpticsAPM::Config.load_config_file
      AppOpticsAPM::Config[:verbose].wont_equal true

      ENV['APPOPTICS_GEM_VERBOSE'] = 'TRUE'
      AppOpticsAPM::Config.load_config_file
      AppOpticsAPM::Config[:verbose].must_equal true

      ENV['APPOPTICS_GEM_VERBOSE'] = 'verbose'
      AppOpticsAPM::Config.load_config_file
      AppOpticsAPM::Config[:verbose].wont_equal true

      ENV['APPOPTICS_GEM_VERBOSE'] = 'True'
      AppOpticsAPM::Config.load_config_file
      AppOpticsAPM::Config[:verbose].must_equal true
    end

    it 'should have the correct instrumentation defaults' do
      # Reset AppOpticsAPM::Config to defaults
      AppOpticsAPM::Config.initialize

      AppOpticsAPM::Config[:debug_level] = 3
      AppOpticsAPM::Config[:verbose].must_equal false
      AppOpticsAPM::Config[:tracing_mode].must_equal :always
      AppOpticsAPM::Config[:sanitize_sql].must_equal true
      AppOpticsAPM::Config[:sanitize_sql_regexp].must_equal '(\'[^\']*\'|\d*\.\d+|\d+|NULL)'
      AppOpticsAPM::Config[:sanitize_sql_opts].must_equal Regexp::IGNORECASE

      AppOpticsAPM::Config[:dnt_regexp].must_equal '\\.(jpg|jpeg|gif|png|ico|css|zip|tgz|gz|rar|bz2|pdf|txt|tar|wav|bmp|rtf|js|flv|swf|otf|eot|ttf|woff|woff2|svg|less)(\\?.+){0,1}$'
      AppOpticsAPM::Config[:dnt_compiled].inspect.must_equal '/\\.(jpg|jpeg|gif|png|ico|css|zip|tgz|gz|rar|bz2|pdf|txt|tar|wav|bmp|rtf|js|flv|swf|otf|eot|ttf|woff|woff2|svg|less)(\\?.+){0,1}$/i'
      AppOpticsAPM::Config[:dnt_opts].must_equal Regexp::IGNORECASE

      AppOpticsAPM::Config[:transaction_settings].is_a?(Hash).must_equal true
      AppOpticsAPM::Config[:transaction_settings].must_equal({ url: [] })

      AppOpticsAPM::Config[:blacklist].is_a?(Array).must_equal true
      AppOpticsAPM::Config[:report_rescued_errors].must_equal false

      AppOpticsAPM::Config[:bunnyconsumer][:controller].must_equal :app_id
      AppOpticsAPM::Config[:bunnyconsumer][:action].must_equal :type

      # Verify the number of individual instrumentations
      instrumentation = AppOpticsAPM::Config.instrumentation
      instrumentation.count.must_equal 33

      AppOpticsAPM::Config[:action_controller][:enabled].must_equal true
      AppOpticsAPM::Config[:action_controller_api][:enabled].must_equal true
      AppOpticsAPM::Config[:action_view][:enabled].must_equal true
      AppOpticsAPM::Config[:active_record][:enabled].must_equal true
      AppOpticsAPM::Config[:bunnyclient][:enabled].must_equal true
      AppOpticsAPM::Config[:bunnyconsumer][:enabled].must_equal true
      AppOpticsAPM::Config[:cassandra][:enabled].must_equal true
      AppOpticsAPM::Config[:curb][:enabled].must_equal true
      AppOpticsAPM::Config[:dalli][:enabled].must_equal true
      AppOpticsAPM::Config[:delayed_jobclient][:enabled].must_equal true
      AppOpticsAPM::Config[:delayed_jobworker][:enabled].must_equal true
      AppOpticsAPM::Config[:em_http_request][:enabled].must_equal false
      AppOpticsAPM::Config[:excon][:enabled].must_equal true
      AppOpticsAPM::Config[:faraday][:enabled].must_equal true
      AppOpticsAPM::Config[:grpc_client][:enabled].must_equal true
      AppOpticsAPM::Config[:grpc_server][:enabled].must_equal true
      AppOpticsAPM::Config[:grape][:enabled].must_equal true
      AppOpticsAPM::Config[:httpclient][:enabled].must_equal true
      AppOpticsAPM::Config[:memcached][:enabled].must_equal true
      AppOpticsAPM::Config[:mongo][:enabled].must_equal true
      AppOpticsAPM::Config[:moped][:enabled].must_equal true
      AppOpticsAPM::Config[:nethttp][:enabled].must_equal true
      AppOpticsAPM::Config[:padrino][:enabled].must_equal true
      AppOpticsAPM::Config[:rack][:enabled].must_equal true
      AppOpticsAPM::Config[:redis][:enabled].must_equal true
      AppOpticsAPM::Config[:resqueclient][:enabled].must_equal true
      AppOpticsAPM::Config[:resqueworker][:enabled].must_equal true
      AppOpticsAPM::Config[:rest_client][:enabled].must_equal true
      AppOpticsAPM::Config[:sequel][:enabled].must_equal true
      AppOpticsAPM::Config[:sidekiqclient][:enabled].must_equal true
      AppOpticsAPM::Config[:sidekiqworker][:enabled].must_equal true
      AppOpticsAPM::Config[:sinatra][:enabled].must_equal true
      AppOpticsAPM::Config[:typhoeus][:enabled].must_equal true

      AppOpticsAPM::Config[:bunnyconsumer][:log_args].must_equal true
      AppOpticsAPM::Config[:curb][:log_args].must_equal true
      # AppOpticsAPM::Config[:em_http_request][:log_args].must_equal true
      AppOpticsAPM::Config[:excon][:log_args].must_equal true
      # AppOpticsAPM::Config[:faraday][:log_args].must_equal true
      AppOpticsAPM::Config[:httpclient][:log_args].must_equal true
      AppOpticsAPM::Config[:mongo][:log_args].must_equal true
      AppOpticsAPM::Config[:nethttp][:log_args].must_equal true
      AppOpticsAPM::Config[:rack][:log_args].must_equal true
      AppOpticsAPM::Config[:resqueclient][:log_args].must_equal true
      AppOpticsAPM::Config[:resqueworker][:log_args].must_equal true
      # AppOpticsAPM::Config[:rest_client][:log_args].must_equal true
      AppOpticsAPM::Config[:sidekiqclient][:log_args].must_equal true
      AppOpticsAPM::Config[:sidekiqworker][:log_args].must_equal true
      AppOpticsAPM::Config[:typhoeus][:log_args].must_equal true

      AppOpticsAPM::Config[:action_controller][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:action_controller_api][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:action_view][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:active_record][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:bunnyclient][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:bunnyconsumer][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:cassandra][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:curb][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:dalli][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:delayed_jobclient][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:delayed_jobworker][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:em_http_request][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:excon][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:faraday][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:grape][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:grpc_client][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:grpc_server][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:httpclient][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:memcached][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:mongo][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:moped][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:nethttp][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:padrino][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:rack][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:redis][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:resqueclient][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:resqueworker][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:rest_client][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:sequel][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:sidekiqclient][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:sidekiqworker][:collect_backtraces].must_equal false
      AppOpticsAPM::Config[:sinatra][:collect_backtraces].must_equal true
      AppOpticsAPM::Config[:typhoeus][:collect_backtraces].must_equal false
    end

    def test_deprecated_config_accessors
      AppOpticsAPM::Config.initialize

      http_clients = AppOpticsAPM::Config.http_clients

      AppOpticsAPM::Config[:include_remote_url_params] = false
      http_clients.each do |i|
        AppOpticsAPM::Config[i][:log_args].must_equal false
      end

      AppOpticsAPM::Config[:include_remote_url_params] = true
      http_clients.each do |i|
        AppOpticsAPM::Config[i][:log_args].must_equal true
      end

      AppOpticsAPM::Config[:include_url_query_params] = false
      AppOpticsAPM::Config[:rack][:log_args].must_equal false

      AppOpticsAPM::Config[:include_url_query_params] = true
      AppOpticsAPM::Config[:rack][:log_args].must_equal true
    end

    def test_should_correct_negative_sample_rate
      AppOpticsAPM::Config[:sample_rate] = -3
      AppOpticsAPM::Config.initialize

      AppOpticsAPM::Config[:sample_rate].must_equal 0
      AppOpticsAPM::Config.sample_rate.must_equal 0
    end

    def test_should_correct_large_sample_rate
      AppOpticsAPM::Config[:sample_rate] = 1_000_000_000
      AppOpticsAPM::Config.initialize

      AppOpticsAPM::Config[:sample_rate].must_equal 1_000_000
      AppOpticsAPM::Config.sample_rate.must_equal 1_000_000
    end

    def test_should_correct_non_numeric_sample_rate
      AppOpticsAPM::Config[:sample_rate] = "summertime"
      AppOpticsAPM::Config.initialize

      AppOpticsAPM::Config[:sample_rate].must_equal 0
      AppOpticsAPM::Config.sample_rate.must_equal 0
    end


    ############################################
    ### Tests for DNT (do not trace) configs ###
    ############################################
    describe "asset_filtering" do
      it 'use :dnt_regexp' do
        AppOpticsAPM::Config[:dnt_regexp] = '\\.gif|\\.js|\\.css|\\.gz(\\?.+){0,1}$'
        AppOpticsAPM::Config[:dnt_opts] = Regexp::IGNORECASE
        AppOpticsAPM::Config.dnt_compile

        AppOpticsAPM::Config[:dnt_compiled].inspect.must_equal '/\\.gif|\\.js|\\.css|\\.gz(\\?.+){0,1}$/i'
      end

      it 'no regex leads to no :dnt_compiled' do
        AppOpticsAPM::Config[:dnt_regexp] = ''
        AppOpticsAPM::Config[:dnt_opts] = Regexp::IGNORECASE
        AppOpticsAPM::Config.dnt_compile

        AppOpticsAPM::Config[:dnt_compiled].must_be_nil
      end
    end

    ###############################################
    ### Tests for :transaction_settings configs ###
    ###############################################
    # more tests in transaction_settings_test.rb

    describe "transaction_settings" do
      before do
        @config_map = AppOpticsAPM::Util.deep_dup(AppOpticsAPM::Config[:transaction_settings])
        @config_url_enabled = AppOpticsAPM::Config[:url_enabled_regexps]
        @config_url_disabled = AppOpticsAPM::Config[:url_disabled_regexps]
      end

      after do
        AppOpticsAPM::Config[:transaction_settings] = AppOpticsAPM::Util.deep_dup(@config_map)
        AppOpticsAPM::Config[:url_enabled_regexps] = @config_url_enabled
        AppOpticsAPM::Config[:url_disabled_regexps] = @config_url_disabled
      end

      it 'the default leads to no :url_never_regexps' do
        AppOpticsAPM::Config[:url_disabled_regexps].must_be_nil
      end

      it " creates no url regexps if :transaction_settings doesn't have a :url key" do
        AppOpticsAPM::Config[:url_enabled_regexps] = Regexp.new(/.*lobster.*/)
        AppOpticsAPM::Config[:url_disabled_regexps] = Regexp.new(/.*lobster.*/)
        AppOpticsAPM::Config[:transaction_settings] = 'LA VIE EST BELLE'

        AppOpticsAPM::Config[:url_enabled_regexps].must_be_nil
        AppOpticsAPM::Config[:url_disabled_regexps].must_be_nil
      end
    end

    #########################################
    ### Tests for loading the config file ###
    #########################################

    it 'should not load a file if no path and no default file are found' do
      AppOpticsAPM::Config.expects(:load).times(0)
      AppOpticsAPM::Config.load_config_file
    end

    it 'should load configs from default file' do
      FileUtils.cp(@@template, @@default_config_path)

      AppOpticsAPM::Config.expects(:load).with(@@default_config_path).times(1)
      AppOpticsAPM::Config.load_config_file
    end

    it 'should load config file from env var' do
      ENV['APPOPTICS_APM_CONFIG_RUBY'] = @@test_config_path
      FileUtils.cp(@@template, @@test_config_path)

      AppOpticsAPM::Config.expects(:load).with(@@test_config_path).times(1)
      AppOpticsAPM::Config.load_config_file
    end

    it 'should find the file if the path points to a directory' do
      ENV['APPOPTICS_APM_CONFIG_RUBY'] = File.dirname(@@test_config_path)
      FileUtils.cp(@@template, @@test_config_path)

      AppOpticsAPM::Config.expects(:load).with(@@test_config_path).times(1)
      AppOpticsAPM::Config.load_config_file
    end

    it 'should load the rails default config file' do
      # even though rails will load it as well, but we don't have a reliable way to detect a rails app
      FileUtils.cp(@@template, @@rails_config_path)

      AppOpticsAPM::Config.expects(:load).with(@@rails_config_path).times(1)
      AppOpticsAPM::Config.load_config_file
    end

    it 'should print a message if env var does not point to a file' do
      ENV['APPOPTICS_APM_CONFIG_RUBY'] = 'non_existing_file'

      AppOpticsAPM.logger.expects(:warn).once
      AppOpticsAPM::Config.load_config_file
    end

    it 'should print a message if multiple config files are configured' do
      FileUtils.cp(@@template, @@default_config_path)
      FileUtils.cp(@@template, @@test_config_path)
      ENV['APPOPTICS_APM_CONFIG_RUBY'] = @@test_config_path

      AppOpticsAPM.logger.expects(:warn).once
      AppOpticsAPM::Config.expects(:load).with(@@test_config_path).times(1)
      AppOpticsAPM::Config.load_config_file
    end
  end
end
