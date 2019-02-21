# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

module AppOpticsAPM
  ##
  # Provides utility methods for use while in the business
  # of instrumenting code
  module Util
    class << self
      def contextual_name(cls)
        # Attempt to infer a contextual name if not indicated
        #
        # For example:
        # ::ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter.to_s.split(/::/).last
        # => "AbstractMysqlAdapter"
        #
        cls.to_s.split(/::/).last
      rescue
        cls
      end

      ##
      # method_alias
      #
      # Centralized utility method to alias a method on an arbitrary
      # class or module.
      #
      def method_alias(cls, method, name = nil)
        name ||= contextual_name(cls)

        if cls.method_defined?(method.to_sym) || cls.private_method_defined?(method.to_sym)

          # Strip '!' or '?' from method if present
          safe_method_name = method.to_s.chop if method.to_s =~ /\?$|\!$/
          safe_method_name ||= method

          without_appoptics = "#{safe_method_name}_without_appoptics"
          with_appoptics    = "#{safe_method_name}_with_appoptics"

          # Only alias if we haven't done so already
          unless cls.method_defined?(without_appoptics.to_sym) ||
            cls.private_method_defined?(without_appoptics.to_sym)

            cls.class_eval do
              alias_method without_appoptics, method.to_s
              alias_method method.to_s, with_appoptics
            end
          end
        else
          AppOpticsAPM.logger.warn "[appoptics_apm/loading] Couldn't properly instrument #{name}.#{method}.  Partial traces may occur."
        end
      end

      ##
      # class_method_alias
      #
      # Centralized utility method to alias a class method on an arbitrary
      # class or module
      #
      def class_method_alias(cls, method, name = nil)
        name ||= contextual_name(cls)

        if cls.singleton_methods.include? method.to_sym

          # Strip '!' or '?' from method if present
          safe_method_name = method.to_s.chop if method.to_s =~ /\?$|\!$/
          safe_method_name ||= method

          without_appoptics = "#{safe_method_name}_without_appoptics"
          with_appoptics    = "#{safe_method_name}_with_appoptics"

          # Only alias if we haven't done so already
          unless cls.singleton_methods.include? without_appoptics.to_sym
            cls.singleton_class.send(:alias_method, without_appoptics, method.to_s)
            cls.singleton_class.send(:alias_method, method.to_s, with_appoptics)
          end
        else
          AppOpticsAPM.logger.warn "[appoptics_apm/loading] Couldn't properly instrument #{name}.  Partial traces may occur."
        end
      end

      ##
      # send_extend
      #
      # Centralized utility method to send an extend call for an
      # arbitrary class
      def send_extend(target_cls, cls)
        target_cls.send(:extend, cls) if defined?(target_cls)
      end

      ##
      # send_include
      #
      # Centralized utility method to send a include call for an
      # arbitrary class
      def send_include(target_cls, cls)
        target_cls.send(:include, cls) if defined?(target_cls)
      end

      ##
      # prettify
      #
      # Even to my surprise, 'prettify' is a real word:
      # transitive v. To make pretty or prettier, especially in a superficial or insubstantial way.
      #   from The American Heritage Dictionary of the English Language, 4th Edition
      #
      # This method makes things 'purty' for reporting.
      def prettify(x)
        if (x.to_s =~ /^#</) == 0
          x.class.to_s
        else
          x.to_s
        end
      end

      ##
      # upcase
      #
      # Occasionally, we want to send some values in all caps.  This is true
      # for things like HTTP scheme or method.  This takes anything and does
      # it's best to safely convert it to a string (if needed) and convert it
      # to all uppercase.
      def upcase(o)
        if o.is_a?(String) || o.respond_to?(:to_s)
          o.to_s.upcase
        else
          AppOpticsAPM.logger.debug "[appoptics_apm/debug] AppOpticsAPM::Util.upcase: could not convert #{o.class}"
          'UNKNOWN'
        end
      end

      ##
      # to_query
      #
      # Used to convert a hash into a URL # query.
      #
      def to_query(h)
        return '' unless h.is_a?(Hash)

        result = []

        h.each { |k, v| result.push(k.to_s + '=' + v.to_s) }
        result.sort.join('&')
      end

      ##
      # sanitize_sql
      #
      # Used to remove query literals from SQL.  Used by all
      # DB adapter instrumentation.
      #
      # The regular expression passed to String.gsub is configurable
      # via AppOpticsAPM::Config[:sanitize_sql_regexp] and
      # AppOpticsAPM::Config[:sanitize_sql_opts].
      #
      def sanitize_sql(sql)
        return sql unless AppOpticsAPM::Config[:sanitize_sql]

        regexp = Regexp.new(AppOpticsAPM::Config[:sanitize_sql_regexp], AppOpticsAPM::Config[:sanitize_sql_opts])
        sql.gsub(/\\\'/,'').gsub(regexp, '?')
      end

      ##
      # deep_dup
      #
      # deep duplicate of array or hash
      #
      def deep_dup(obj)
        if obj.is_a? Array
          new_obj = []
          obj.each do |v|
            new_obj << deep_dup(v)
          end
        elsif obj.is_a? Hash
          new_obj = {}
          obj.each_pair do |key, value|
            new_obj[key] = deep_dup(value)
          end
        end
      end

      ##
      # legacy_build_init_report
      #
      # Internal: Build a hash of KVs that reports on the status of the
      # running environment.  This is used on stack boot in __Init reporting
      # and for AppOpticsAPM.support_report.
      #
      # This legacy version of build_init_report is used for apps without Bundler.
      #
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
      #
      # @deprecated Please use {#build_init_report} instead
      def legacy_build_init_report
        AppOpticsAPM.logger.warn '[appoptics_apm/warn] Oboe::API will be deprecated in a future version.'
        platform_info = {}

        begin
          # Report the framework in use
          if defined?(::RailsLts::VERSION)
            platform_info['Ruby.RailsLts.Version']  = "RailsLts-#{::RailsLts::VERSION}"
          elsif defined?(::Rails.version)
            platform_info['Ruby.Rails.Version']     = "Rails-#{::Rails.version}"
          end
          platform_info['Ruby.Grape.Version']       = "Grape-#{::Grape::VERSION}" if defined?(::Grape::VERSION)
          platform_info['Ruby.Cramp.Version']       = "Cramp-#{::Cramp::VERSION}" if defined?(::Cramp::VERSION)

          if defined?(::Padrino::VERSION)
            platform_info['Ruby.Padrino.Version']   = "Padrino-#{::Padrino::VERSION}"
          elsif defined?(::Sinatra::VERSION)
            platform_info['Ruby.Sinatra.Version']   = "Sinatra-#{::Sinatra::VERSION}"
          end

          # Report the instrumented libraries
          platform_info['Ruby.Cassandra.Version']  = "Cassandra-#{::Cassandra.VERSION}"    if defined?(::Cassandra.VERSION)
          platform_info['Ruby.Curb.Version']       = "Curb-#{::Curl::VERSION}"             if defined?(::Curl::VERSION)
          platform_info['Ruby.Dalli.Version']      = "Dalli-#{::Dalli::VERSION}"           if defined?(::Dalli::VERSION)
          platform_info['Ruby.Excon.Version']      = "Excon-#{::Excon::VERSION}"           if defined?(::Excon::VERSION)
          platform_info['Ruby.Faraday.Version']    = "Faraday-#{::Faraday::VERSION}"       if defined?(::Faraday::VERSION)
          platform_info['Ruby.HTTPClient.Version'] = "HTTPClient-#{::HTTPClient::VERSION}" if defined?(::HTTPClient::VERSION)
          platform_info['Ruby.Memcached.Version']  = "Memcached-#{::Memcached::VERSION}"   if defined?(::Memcached::VERSION)
          platform_info['Ruby.Moped.Version']      = "Moped-#{::Moped::VERSION}"           if defined?(::Moped::VERSION)
          platform_info['Ruby.Redis.Version']      = "Redis-#{::Redis::VERSION}"           if defined?(::Redis::VERSION)
          platform_info['Ruby.Resque.Version']     = "Resque-#{::Resque::VERSION}"         if defined?(::Resque::VERSION)
          platform_info['Ruby.RestClient.Version'] = "RestClient-#{::RestClient::VERSION}" if defined?(::RestClient::VERSION)
          platform_info['Ruby.Sidekiq.Version']    = "Sidekiq-#{::Sidekiq::VERSION}"       if defined?(::Sidekiq::VERSION)
          platform_info['Ruby.Typhoeus.Version']   = "Typhoeus-#{::Typhoeus::VERSION}"     if defined?(::Typhoeus::VERSION)

          if Gem.loaded_specs.key?('delayed_job')
            # Oddly, DelayedJob doesn't have an embedded version number so we get it from the loaded
            # gem specs.
            version = Gem.loaded_specs['delayed_job'].version.to_s
            platform_info['Ruby.DelayedJob.Version']       = "DelayedJob-#{version}"
          end

          # Special case since the Mongo 1.x driver doesn't embed the version number in the gem directly
          if ::Gem.loaded_specs.key?('mongo')
            platform_info['Ruby.Mongo.Version']     = "Mongo-#{::Gem.loaded_specs['mongo'].version}"
          end

          # Report the DB adapter in use
          platform_info['Ruby.Mysql.Version']   = Mysql::GemVersion::VERSION   if defined?(Mysql::GemVersion::VERSION)
          platform_info['Ruby.PG.Version']      = PG::VERSION                  if defined?(PG::VERSION)
          platform_info['Ruby.Mysql2.Version']  = Mysql2::VERSION              if defined?(Mysql2::VERSION)
          platform_info['Ruby.Sequel.Version']  = ::Sequel::VERSION            if defined?(::Sequel::VERSION)
        rescue StandardError, ScriptError => e
          # Also rescue ScriptError (aka SyntaxError) in case one of the expected
          # version defines don't exist

          platform_info['Error'] = "Error in legacy_build_init_report: #{e.message}"

          AppOpticsAPM.logger.warn "[appoptics_apm/warn] Error in legacy_build_init_report: #{e.message}"
          AppOpticsAPM.logger.debug e.backtrace
        end
        platform_info
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize

      ##
      #  build_init_report
      #
      # Internal: Build a hash of KVs that reports on the status of the
      # running environment.  This is used on stack boot in __Init reporting
      # and for AppOpticsAPM.support_report.
      #
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
      def build_init_report
        platform_info = { '__Init' => 1 }

        begin
          platform_info['Force']                        = true
          platform_info['Ruby.Platform.Version']        = RUBY_PLATFORM
          platform_info['Ruby.Version']                 = RUBY_VERSION
          platform_info['Ruby.AppOptics.Version']    = AppOpticsAPM::Version::STRING

          clib_version_file = File.join(Gem::Specification.find_by_name('appoptics_apm').gem_dir, 'ext', 'oboe_metal', 'src', 'VERSION')
          platform_info['Ruby.clib.Version']            = File.read(clib_version_file).chomp
          platform_info['RubyHeroku.AppOpticsAPM.Version'] = AppOpticsAPMHeroku::Version::STRING if defined?(AppOpticsAPMHeroku)
          platform_info['Ruby.TraceMode.Version']       = AppOpticsAPM::Config[:tracing_mode]

          # Collect up the loaded gems
          if defined?(Gem) && Gem.respond_to?(:loaded_specs)
            Gem.loaded_specs.each_pair { |k, v|
              platform_info["Ruby.#{k}.Version"] = v.version.to_s
            }
          else
            platform_info.merge!(legacy_build_init_report)
          end

          # Report the server in use (if possible)
          if defined?(::Unicorn::Const::UNICORN_VERSION)
            platform_info['Ruby.AppContainer.Version'] = "Unicorn-#{::Unicorn::Const::UNICORN_VERSION}"
          elsif defined?(::Puma::Const::PUMA_VERSION)
            platform_info['Ruby.AppContainer.Version'] = "Puma-#{::Puma::Const::PUMA_VERSION} (#{::Puma::Const::CODE_NAME})"
          elsif defined?(::PhusionPassenger::PACKAGE_NAME)
            platform_info['Ruby.AppContainer.Version'] = "#{::PhusionPassenger::PACKAGE_NAME}-#{::PhusionPassenger::VERSION_STRING}"
          elsif defined?(::Thin::VERSION::STRING)
            platform_info['Ruby.AppContainer.Version'] = "Thin-#{::Thin::VERSION::STRING} (#{::Thin::VERSION::CODENAME})"
          elsif defined?(::Mongrel::Const::MONGREL_VERSION)
            platform_info['Ruby.AppContainer.Version'] = "Mongrel-#{::Mongrel::Const::MONGREL_VERSION}"
          elsif defined?(::Mongrel2::VERSION)
            platform_info['Ruby.AppContainer.Version'] = "Mongrel2-#{::Mongrel2::VERSION}"
          elsif defined?(::Trinidad::VERSION)
            platform_info['Ruby.AppContainer.Version'] = "Trinidad-#{::Trinidad::VERSION}"
          elsif defined?(::WEBrick::VERSION)
            platform_info['Ruby.AppContainer.Version'] = "WEBrick-#{::WEBrick::VERSION}"
          else
            platform_info['Ruby.AppContainer.Version'] = File.basename($PROGRAM_NAME)
          end

        rescue StandardError, ScriptError => e
          # Also rescue ScriptError (aka SyntaxError) in case one of the expected
          # version defines don't exist

          platform_info['Error'] = "Error in build_report: #{e.message}"

          AppOpticsAPM.logger.warn "[appoptics_apm/warn] Error in build_init_report: #{e.message}"
          AppOpticsAPM.logger.debug e.backtrace
        end
        platform_info
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
    end
  end
end
