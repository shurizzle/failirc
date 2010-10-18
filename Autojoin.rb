require 'failirc/client/module'

module IRC

class Client

module Modules

class Autojoin < Module
    @@version = '0.0.1'

    def self.version
        @@version
    end

    def description
        "Autojoin-#{Autojoin.version}"
    end

    def initialize(client)
        @events = {
            :custom => {
                :connected  => self.method(:autojoin)
            }
        }

        @chans = {}
        client.config.elements.each('config/servers/server') {|server|
            host = server.attributes['host']
            @chans[host] = []
            client.config.elements.each("config/servers/server[@host=\"#{host}\"]/channels/channel") {|chan|
                @chans[host] << chan.text
            }
        }

        super(client)
    end

    def autojoin(server)
        return if !@chans[server.name]

        @chans[server.name].each {|chan|
            server.client.fire :join, server, chan
        }
    end
end

end

end

end
