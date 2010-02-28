# failirc, a fail IRC server.
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

require 'thread'
require 'socket'
require 'openssl'

require 'rexml/document'
include REXML

require 'failirc'
require 'failirc/server/client'
require 'failirc/utils'

module IRC

require 'failirc/server/errors'
require 'failirc/server/responses'

class Server
    include Utils

    attr_reader :verbose

    def initialize (conf, verbose)
        @verbose = verbose ? true : false

        self.config = conf

        @clients   = []
        @servers   = []
        @listening = []
    end

    def start
        if @started
            return
        end

        if !@config
            raise '@config is missing.'
        end

        @listeningThread = Thread.new {
            begin
                @config.elements.each('config/server/listen') {|listen|
                    server = TCPServer.new(listen.attributes['bind'], listen.attributes['port'])

                    if listen.attributes['ssl'] == 'enable'
                        context = OpenSSL::SSL::SSLContext.new
                        context.key = File.read(listen.attributes['sslKey'])
                        context.cert = File.read(listen.attributes['sslCert'])

                        server = OpenSSL::SSL::SSLServer(server, context)
                    end

                    @listening.push(server)
                }
            rescue Exception => e
                puts e.message
                Thread.stop
            end

            while true
                begin
                    @listening.each {|server|
                        socket, = server.accept_nonblock

                        if socket
                            run(socket)
                        end
                    }
                rescue Errno::EAGAIN, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
                    IO::select(@listening)
                rescue Exception => e
                    self.debug(e)
                end
            end
        }

        @pingThread = Thread.new {
            while true
                sleep 60

                self.do :ping
            end
        }

        @listeningThread.run
        @pingThread.run

        @started = true

        self.loop()
    end

    def loop
        while true
            connections = @clients.concat(@servers)
            connections = IO::select(connections, connections)

            connections.each {|socket|
                handle socket
            }
        end
    end

    def stop
        if @started
            Thread.kill(@listeningThread)
            Thread.kill(@pingThread)

            @listening.each {|socket|
                socket.close
            }

            @clients.each {|socket|
                socket.close
            }

            @servers.each {|socket|
                socket.close
            }
        end

        exit 0
    end

    def rehash
        self.config = @configReference
    end

    def config= (reference)
        @config          = Document.new reference
        @configReference = reference

        if !@config.elements['config'].elements['server'].elements['name']
            @config.elements['config'].elements['server'].add(Element.new('name'))
            @config.elements['config'].elements['server'].elements['name'].text = "Fail IRC"
        end

        if !@config.elements['config'].elements['server'].elements['listen']
            @config.elements['config'].elements['server'].add(Element.new('listen'))
        end

        @config.elements.each("config/server/listen") {|element|
            if !element.attributes['port']
                element.attributes['port'] = '6667'
            end

            if !element.attributes['bind']
                element.attributes['bind'] = '0.0.0.0'
            end

            if !element.attributes['ssl'] || (element.attributes['ssl'] != 'enable' && element.attributes['ssl'] != 'disable')
                element.attributes['ssl'] = 'disable'
            end
        }
    end

    # Executed with each incoming connection
    def run (socket)
        begin
            @clients.push(IRC::Client.new(self, socket))
        rescue Exception => e
            socket.close
            self.debug(e)
        end
    end

    def do (type, *args)
        callback = @@callbacks[type]
        callback(args)
    end

    @@callbacks = {
        :ping => lambda {
            @clients.each {|client|

            }
        }
    }
end

end
