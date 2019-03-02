require 'appoptics_apm'
require 'get_process_mem'
require 'ruby-prof'
require 'memory_profiler'

class MemProf
  @@max = 0
  def self.print_usage(n, before, after)
    asterix = ''
    if after > @@max
      asterix = '*'
      @@max = after
    end
    puts "#{n.to_s.rjust(3)}) MEMORY USAGE(MB) - before: #{before.round(1).to_s.rjust(6)}, after: #{after.round(1).to_s.rjust(6)} #{asterix}"
  end

  def self.print_usage_before_and_after(n)
    before = GetProcessMem.new.mb
    yield
    after = GetProcessMem.new.mb
    print_usage(n, before, after)
  end
end

num = 1_000_000
# num = 10000
times = ARGV.first.to_i

# export RUBY_PROF_MEASURE_MODE=allocations
# result = RubyProf.profile do
# report = MemoryProfiler.report do
  (1..times).each do |n|
    MemProf.print_usage_before_and_after(n) do
      num.times do
        a = []
        a << AppOpticsAPM::Context.getSampleMetricsDecisions
        a << AppOpticsAPM::Context.getSampleMetricsDecisions(0)
        a << AppOpticsAPM::Context.getSampleMetricsDecisions(1, 1000)
        a << AppOpticsAPM::Context.getSampleMetricsDecisions(1, 10000000, '2BE176BC800FE533EB7910F59C44F173BBF6ED7E07EFAAC4BEBB329CA801')
        a << AppOpticsAPM::Context.getSampleMetricsDecisions(1, 10000000, '2BE176BC800FE533EB7910F59C44F173BBF6ED7E07EFAAC4BEBB329CA801', 'the_service')
      end
    end
  end
# end

# report.pretty_print(to_file: "profile.txt")
# printer = RubyProf::FlatPrinter.new(result)
# printer.print(STDOUT)
