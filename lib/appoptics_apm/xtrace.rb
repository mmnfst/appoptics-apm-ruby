# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

module AppOpticsAPM
  ##
  # Methods to act on, manipulate or investigate an X-Trace
  # value
  module XTrace
    class << self
      ##
      #  AppOpticsAPM::XTrace.valid?
      #
      #  Perform basic validation on a potential X-Trace ID
      #
      def valid?(xtrace)
        # Shouldn't be nil
        return false unless xtrace

        # The X-Trace ID shouldn't be an initialized empty ID
        return false if (xtrace =~ /^2b0000000/i) == 0

        # Valid X-Trace IDs have a length of 60 bytes and start with '2b'
        return false unless xtrace.length == 60 && (xtrace =~ /^2b/i) == 0

        true
      rescue StandardError => e
        AppOpticsAPM.logger.debug "[appoptics_apm/xtrace] #{e.message}"
        AppOpticsAPM.logger.debug e.backtrace
        false
      end

      def sampled?(xtrace)
        valid?(xtrace) && xtrace[59].to_i & 1 == 1
      end

      def set_sampled(xtrace)
        xtrace[59] = (xtrace[59].hex | 1).to_s(16).upcase
      end

      def unset_sampled(xtrace)
        xtrace[59] = (~(~xtrace[59].hex | 1)).to_s(16).upcase
      end

      ##
      # AppOpticsAPM::XTrace.task_id
      #
      # Extract and return the task_id portion of an X-Trace ID
      #
      def task_id(xtrace)
        return nil unless AppOpticsAPM::XTrace.valid?(xtrace)

        xtrace[2..41]
      rescue StandardError => e
        AppOpticsAPM.logger.debug "[appoptics_apm/xtrace] #{e.message}"
        AppOpticsAPM.logger.debug e.backtrace
        return nil
      end

      ##
      # AppOpticsAPM::XTrace.edge_id
      #
      # Extract and return the edge_id portion of an X-Trace ID
      #
      def edge_id(xtrace)
        return nil unless AppOpticsAPM::XTrace.valid?(xtrace)

        xtrace[42..57]
      rescue StandardError => e
        AppOpticsAPM.logger.debug "[appoptics_apm/xtrace] #{e.message}"
        AppOpticsAPM.logger.debug e.backtrace
        return nil
      end

      ##
      # continue_service_context
      #
      # In the case of service calls such as external HTTP requests, we
      # pass along X-Trace headers so that request context can be maintained
      # across servers and applications.
      #
      # Remote requests can return a X-Trace header in which case we want
      # to pickup on and continue the context in most cases.
      #
      # start is the context just before the outgoing request
      #
      # finish is the context returned to us (as an HTTP response header
      # if that be the case)
      #
      def continue_service_context(start, finish)
        if AppOpticsAPM::XTrace.valid?(finish) && AppOpticsAPM.tracing?

          # Assure that we received back a valid X-Trace with the same task_id
          # and the sampling bit is set, otherwise it is a response from a non-sampling service
          if AppOpticsAPM::XTrace.task_id(start) == AppOpticsAPM::XTrace.task_id(finish) && AppOpticsAPM::XTrace.sampled?(finish)
            AppOpticsAPM::Context.fromString(finish)
          else
            AppOpticsAPM.logger.debug "[XTrace] Sampling flag unset or mismatched start and finish ids:\n#{start}\n#{finish}"
          end
        end
      end
    end
  end
end
