# failirc, a fail IRC library.
#
# Copyleft meh. [http://meh.doesntexist.org | meh.ffff@gmail.com]
#
# This file is part of failirc.
#
# failirc is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# failirc is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with failirc. If not, see <http://www.gnu.org/licenses/>.

require 'failirc/extensions'

class Object

def debug (argument, separator='')
    output = ''

    if argument.is_a?(Exception)
        output << "\n#{self.class}: #{argument.class}: #{argument.message}\n"
        output << argument.backtrace.collect {|stack|
            "#{self.class}: #{stack}"
        }.join("\n")
        output << "\n\n"
    elsif argument.is_a?(String)
        output << "#{self.class}: #{argument}\n"
    else
        output << "#{self.class}: #{argument.inspect}\n"
    end

    if separator
        output << separator
    end

    begin
        if @verbose || (@server && @server.verbose) || (@client && @client.verbose) || ($server && $server.verbose) || ($client && $client.verbose)
            puts output
        end
    rescue
    end

    (dispatcher rescue ($server || server).dispatcher rescue ($client || client).dispatcher).execute :log, output rescue nil
end

end
