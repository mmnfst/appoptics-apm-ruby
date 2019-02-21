# Copyright (c) 2018 SolarWinds, LLC.
# All rights reserved.
#


module AppOpticsAPM
  ##
  # This module helps with setting up the filters and applying them
  #
  class TransactionSettings

    attr_reader :do_metrics, :do_propagate, :do_sample, :rate, :source

    def initialize(url, xtrace = '')
      @do_metrics = false
      @do_sample = false
      @do_propagate = true

      if asset?(url)
        @do_propagate = false
        return
      end

      if AppOpticsAPM::Context.isValid
        @do_sample = AppOpticsAPM.tracing?
        return
      end

      if AppOpticsAPM.tracing_disabled? && !tracing_enabled?(url) ||
         tracing_disabled?(url)
        return
      end

      if AppOpticsAPM::Context.isValid
        @do_sample = AppOpticsAPM.tracing?
        return
      end

      args = [xtrace || '']
      args << AppOpticsAPM::Config[:sample_rate] if AppOpticsAPM::Config[:sample_rate]&. >= 0
      metrics, sample, @rate, @source = AppOpticsAPM::Context.getDecisions(*args)

      @do_metrics = metrics > 0
      @do_sample = sample > 0
    end

    private
    ##
    # tracing_enabled?
    #
    # Given a path, this method determines whether it matches any of the
    # regexps to exclude it from metrics and traces
    #
    def tracing_enabled?(url)
      return false unless AppOpticsAPM::Config[:url_enabled_regexps].is_a? Array
      # once we only support Ruby >= 2.4.0 use `match?` instead of `=~`
      return AppOpticsAPM::Config[:url_enabled_regexps].any? { |regex| regex =~ url }
    rescue => e
      AppOpticsAPM.logger.warn "[AppOpticsAPM/filter] Could not apply :enabled filter to path. #{e.inspect}"
      true
    end

    ##
    # tracing_disabled?
    #
    # Given a path, this method determines whether it matches any of the
    # regexps to exclude it from metrics and traces
    #
    def tracing_disabled?(url)
      return false unless AppOpticsAPM::Config[:url_disabled_regexps].is_a? Array
      # once we only support Ruby >= 2.4.0 use `match?` instead of `=~`
      return AppOpticsAPM::Config[:url_disabled_regexps].any? { |regex| regex =~ url }
    rescue => e
      AppOpticsAPM.logger.warn "[AppOpticsAPM/filter] Could not apply :disabled filter to path. #{e.inspect}"
      false
    end

    ##
    # asset?
    #
    # Given a path, this method determines whether it is a static asset
    #
    def asset?(path)
      return false unless AppOpticsAPM::Config[:dnt_compiled]
      # once we only support Ruby >= 2.4.0 use `match?` instead of `=~`
      return AppOpticsAPM::Config[:dnt_compiled] =~ path
    rescue => e
      AppOpticsAPM.logger.warn "[AppOpticsAPM/filter] Could not apply do-not-trace filter to path. #{e.inspect}"
      false
    end

    public

    class << self

      def compile_url_settings(settings)
        if !settings.is_a?(Array) || settings.empty?
          reset_url_regexps
          return
        end

        # `tracing: disabled` is the default
        disabled = settings.select { |v| !v.has_key?(:tracing) || v[:tracing] == :disabled }
        enabled = settings.select { |v| v[:tracing] == :enabled }

        AppOpticsAPM::Config[:url_enabled_regexps] = compile_regexp(enabled)
        AppOpticsAPM::Config[:url_disabled_regexps] = compile_regexp(disabled)
      end

      def compile_regexp(settings)
        regexp_regexp     = compile_url_settings_regexp(settings)
        extensions_regexp = compile_url_settings_extensions(settings)

        regexps = [regexp_regexp, extensions_regexp].flatten.compact

        regexps.empty? ? nil : regexps
      end

      def compile_url_settings_regexp(value)
        regexps = value.select do |v|
          v.key?(:regexp) &&
            !(v[:regexp].is_a?(String) && v[:regexp].empty?) &&
            !(v[:regexp].is_a?(Regexp) && v[:regexp].inspect == '//')
        end

        regexps.map! do |v|
          begin
            v[:regexp].is_a?(String) ? Regexp.new(v[:regexp], v[:opts]) : Regexp.new(v[:regexp])
          rescue
            AppOpticsAPM.logger.warn "[appoptics_apm/config] Problem compiling transaction_settings item #{v}, will ignore."
            nil
          end
        end
        regexps.keep_if { |v| !v.nil?}
        regexps.empty? ? nil : regexps
      end

      def compile_url_settings_extensions(value)
        extensions = value.select do |v|
          v.key?(:extensions) &&
            v[:extensions].is_a?(Array) &&
            !v[:extensions].empty?
        end
        extensions = extensions.map { |v| v[:extensions] }.flatten
        extensions.keep_if { |v| v.is_a?(String)}

        extensions.empty? ? nil : Regexp.new("(#{Regexp.union(extensions).source})(\\?.+){0,1}$")
      end

      def reset_url_regexps
        AppOpticsAPM::Config[:url_enabled_regexps] = nil
        AppOpticsAPM::Config[:url_disabled_regexps] = nil
      end
    end
  end
end
