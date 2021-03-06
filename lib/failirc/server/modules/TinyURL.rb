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

require 'net/http'
require 'uri'
require 'timeout'

require 'failirc/extensions'
require 'failirc/module'

require 'failirc/server/modules/Base'

module IRC

class Server

module Modules

class TinyURL < Module
    def initialize (server)
        @events = {
            :custom => {
                :message => Event::Callback.new(self.method(:tinyurl), -100),
            }
        }

        super(server)
    end

    def rehash
        if tmp = @server.config.elements['config/modules/module[@name="TinyURL"]/length']
            @length = tmp.text.to_i
        else
            @length = 42
        end

        if tmp = @server.config.elements['config/modules/module[@name="TinyURL"]/timeout']
            @timeout = tmp.text.to_i
        else
            @timeout = 5
        end
    end

    def tinyurl (chain, fromRef, toRef, message, level=nil)
        from = fromRef.value
        to   = toRef.value

        case chain
        
        when :input
            URI.extract(message).each {|uri|
                if uri.length <= @length
                    next
                end

                if tiny = tinyurlify(uri) rescue nil
                    message.gsub!(/#{Regexp.escape(uri)}/, tiny)
                end
            }
        
        when :output
            if Base::Utils::checkFlag(to, :tinyurl_preview)
                message.gsub!('http://tinyurl.com', 'http://preview.tinyurl.com')
            end

        end
    end

    def tinyurlify (url)
        begin
            content = timeout @timeout do
                Net::HTTP.post_form(URI.parse('http://tinyurl.com/create.php'), { 'url' => url }).body
            end
            
            match = content.match('<blockquote><b>(http://tinyurl.com/\w+)</b>')

            if match
                return match[1]
            end
        rescue Timeout::Error
            return nil
        end
    end
end

end

end

end
