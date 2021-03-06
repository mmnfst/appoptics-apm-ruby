# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

if defined?(ActionView::Base) && AppOpticsAPM::Config[:action_view][:enabled]

  if Rails::VERSION::MAJOR >= 4

    AppOpticsAPM.logger.info '[appoptics_apm/loading] Instrumenting actionview' if AppOpticsAPM::Config[:verbose]

    ActionView::PartialRenderer.class_eval do
      alias :render_partial_without_appoptics :render_partial
      def render_partial(*args)
        entry_kvs = {}
        begin
          entry_kvs[:Partial] = AppOpticsAPM::Util.prettify(@options[:partial]) if @options.is_a?(Hash)
        rescue => e
          AppOpticsAPM.logger.debug "[appoptics_apm/debug] #{__method__}:#{File.basename(__FILE__)}:#{__LINE__}: #{e.message}" if AppOpticsAPM::Config[:verbose]
        end

        AppOpticsAPM::SDK.trace('partial', entry_kvs) do
          entry_kvs[:Backtrace] = AppOpticsAPM::API.backtrace if AppOpticsAPM::Config[:action_view][:collect_backtraces]
          render_partial_without_appoptics(*args)
        end
      end

      alias :render_collection_without_appoptics :render_collection
      def render_collection(*args)
        entry_kvs = {}
        begin
          entry_kvs[:Partial] = AppOpticsAPM::Util.prettify(@path)
        rescue => e
          AppOpticsAPM.logger.debug "[appoptics_apm/debug] #{__method__}:#{File.basename(__FILE__)}:#{__LINE__}: #{e.message}" if AppOpticsAPM::Config[:verbose]
        end

        AppOpticsAPM::SDK.trace('collection', entry_kvs) do
          entry_kvs[:Backtrace] = AppOpticsAPM::API.backtrace if AppOpticsAPM::Config[:action_view][:collect_backtraces]
          render_collection_without_appoptics(*args)
        end
      end

    end
  end
end

# vim:set expandtab:tabstop=2
