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

module IRC

class Modes < ThreadSafeHash
    def initialize (string=nil)
        super()

        self[:extended] = ThreadSafeHash.new

        if string
            string.each_char {|char|
                @modes[char.to_sym] = true
            }
        end
    end

    def to_s
        modes  = []
        values = []

        each_key {|mode|
            if mode
                mode = mode.to_s

                if mode.length == 1
                    modes.push mode

                    if self[mode.to_sym] != true
                        values.push self[mode.to_sym]
                    end
                end
            end
        }

        return "+#{modes.join} #{values.join ' '}"
    end
end

end
