require 'failirc/client/module'

module IRC

class Client

module Modules

class Autorejoin < Module
    @@version = '0.0.1'

    def self.version
        @@version
    end

    def description
        "Autorejoin-#{Autorejoin.version}"
    end

    def initialize(client)
        @events = {
            :custom => {
                :kicked => self.method(:rejoin)
            }
        }

        super(client)
    end

    def rejoin(server, from, by, to, reason)
        if to.nick == server.client.nick
            server.client.fire :join, server, from
        end
    end
end

end

end

end
