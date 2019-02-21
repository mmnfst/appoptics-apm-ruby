# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

module AppOpticsAPM
  ##
  # The current version of the gem.  Used mainly by
  # appoptics_apm.gemspec during gem build process
  module Version
    MAJOR = 4
    MINOR = 5
    PATCH = 1

    STRING = [MAJOR, MINOR, PATCH].compact.join('.')
  end
end
