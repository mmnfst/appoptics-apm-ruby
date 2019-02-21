# Copyright (c) 2017 SolarWinds, LLC.
# All rights reserved.

require 'benchmark/ips'
require_relative '../minitest_helper'


# compare logging when testing for loaded versus tracing?
ENV['APPOPTICS_GEM_VERBOSE'] = 'false'

n = 1_000

Benchmark.ips do |x|
  x.config(:time => 10, :warmup => 2)

  # x.report('tracing_f') do
  #   AppOpticsAPM.loaded = false
  #   AppOpticsAPM::Config[:tracing_mode] = 'never'
  #   AppOpticsAPM::Context.fromString('2B7435A9FE510AE4533414D425DADF4E180D2B4E3649E60702469DB05F00')
  #   n.times do
  #     AppOpticsAPM.tracing?
  #   end
  # end
  # x.report('tracing_n') do
  #   AppOpticsAPM.loaded = true
  #   AppOpticsAPM::Config[:tracing_mode] = 'never'
  #   AppOpticsAPM::Context.fromString('2B7435A9FE510AE4533414D425DADF4E180D2B4E3649E60702469DB05F00')
  #   n.times do
  #     AppOpticsAPM.tracing?
  #   end
  # end

  # x.report('tracing_tf') do
  #   AppOpticsAPM.loaded = true
  #   AppOpticsAPM::Config[:tracing_mode] = 'always'
  #   AppOpticsAPM::Context.fromString('2B7435A9FE510AE4533414D425DADF4E180D2B4E3649E60702469DB05F00')
  #   n.times do
  #     AppOpticsAPM.tracing?
  #   end
  # end
  # x.report('tracing_tt') do
  #   AppOpticsAPM.loaded = true
  #   AppOpticsAPM::Config[:tracing_mode] = 'always'
  #   AppOpticsAPM::Context.fromString('2B7435A9FE510AE4533414D425DADF4E180D2B4E3649E60702469DB05F01')
  #   n.times do
  #     AppOpticsAPM.tracing?
  #   end
  # end


  AppOpticsAPM::Config[:transaction_settings] =
    { url:
        [
          # { type: :url,
          #   extensions: %w[.png .gif .css .js .gz],
          #   tracing: :disabled
          # },
          { regexp: '^.*\/long_job\/.*$',
            opts: Regexp::IGNORECASE,
            tracing: :disabled
          },
          { regexp: '^.*\/heartbreak\/.*$',
            opts: Regexp::IGNORECASE,
            tracing: :disabled
          },
          { regexp: '^.*\/something_else\/.*$',
            opts: Regexp::IGNORECASE,
            tracing: :disabled
          }
        ]
  }

  # regexps = AppOpticsAPM::Config[:transaction_settings].map { |v| Regexp.new(v[:regexp]) }
  # compiled = Regexp.union(regexps)
  #
  # x.report('3 singles non matching') do
  #   path = 'what.is.this/oh/it/is/something_else?what=then'
  #   n.times do
  #     regexps.each { |r| r =~ path }
  #   end
  # end
  #
  # x.report('combi non matching') do
  #   path = 'what.is.this/oh/it/is/something_else?what=then'
  #   n.times do
  #     compiled =~ path
  #   end
  # end

  # x.report('3 singles matching') do
  #   path = 'what.is.this/oh/it/is/something_else/what_then'
  #   n.times do
  #     regexps.each { |r| r =~ path }
  #   end
  # end
  #
  # x.report('combi matching') do
  #   path = 'what.is.this/oh/it/is/something_else/what_then'
  #   n.times do
  #     compiled =~ path
  #   end
  # end

  # compare old vs new sample decision
  x.report('old sample') do
    n.times do
      AppOpticsAPM::Context.sampleRequest('','')
    end
  end

  x.report('new sample') do
    n.times do
      AppOpticsAPM::Context.getSampleMetricsDecisions
    end
  end
  x.compare!
end


