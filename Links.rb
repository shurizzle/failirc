require 'failirc/client/module'
require 'uri'
require 'net/http'
require 'sqlite3'
require 'htmlentities'
$KCODE = 'u'

class String
    def extract_urls
        URI.extract(self).select {|x|
            x.match(%r{^\w+://})
        }
    end
end

module IRC

class Client

module Modules

class Links < Module
    @@version = '0.0.1'

    def self.version
        @@version
    end

    def self.get_final_link(link, limit = 10)
        return nil if limit == 0

        res = Net::HTTP.get_response(URI.parse(link))
        case res
            when Net::HTTPSuccess       then return link
            when Net::HTTPRedirection   then return get_final_link(res['location'], limit - 1)
            else return nil
        end
    rescue Exception => e
        self.debug e
        self.debug e.backtrace
        nil
    end

    class FakeException < Exception
    end

    class LinkDb
        def initialize(path)
            raise 'Insert a database' if !path

            @db = SQLite3::Database.new(path)
            @db.results_as_hash = true

            db_init
        end

        def insert(link, user, channel, server, message)
            @db.execute('INSERT OR IGNORE INTO links VALUES(?, ?, ?, ?, ?, ?)', [link, Time.now.to_i, user, channel, server, message]) rescue false
        end

        def get_all(channel)
            @db.execute('SELECT * FROM links WHERE channel = ? AND server = ?;', [channel.to_s, channel.server.to_s])
        end

        def get_last(chan, n)
            @db.execute("SELECT * FROM links WHERE channel = ? AND server = ? ORDER BY date DESC LIMIT #{n}",
                    [chan.to_s, chan.server.to_s]).reverse
        end

        def get_range(chan, range)
            @db.execute("SELECT * FROM links WHERE channel = ? AND server = ? LIMIT #{range.end - range.begin} OFFSET #{range.begin}",
                    [chan.to_s, chan.server.to_s])
        end

        def close
            @db.close
        end

    private

        def db_init
            @db.execute(<<QUERY
CREATE TABLE IF NOT EXISTS links (
    link    TEXT UNIQUE,
    date    INTEGER,
    user    VARCHAR(50),
    channel VARCHAR(50),
    server  TEXT,
    message TEXT
);
QUERY
            ) rescue nil
        end
    end

    class Linkers
        def initialize(path)
            raise 'Insert a database' if !path

            @db = SQLite3::Database.new(path)
            @db.results_as_hash = true

            db_init
        end

        def insert(cmd, link)
            @db.execute("INSERT INTO linkers VALUES(?, ?);", [cmd, link]) rescue \
                db.execute("UPDATE linkers SET link = ? WHERE cmd = ?", [link, cmd])
        end

        alias []= insert

        def get(cmd)
            @db.execute("SELECT * FROM linkers WHERE cmd = ?", [cmd])[0]['link'] rescue nil
        end

        alias [] get

        def close
            @db.close
        end

    private

        def db_init
            @db.execute(<<QUERY
CREATE TABLE IF NOT EXISTS linkers (
    cmd     TEXT UNIQUE,
    link    TEXT
);
QUERY
            )
        end
    end

    def description
        "Links-#{Links.version}"
    end

    def initialize(client)
        begin
            db = client.config.elements['config/modules/module[@name="Links"]/database'].text
            @links = LinkDb.new(db)
            @linkers = Linkers.new(db)
        rescue Exception => e
            puts e
        end
        @html = HTMLEntities.new
        @events = {
            :custom => {
                :message        => self.method(:dispatch),
                :topic_change   => self.method(:links_from_topic)
            }
        }

        super(client)
    end

    def dispatch(server, chain, from, to, message)
        return if chain != :input

        if message =~ /^~/
            link(*[server, to, message.match(/^~(.+?)\s+(.+?)\s*$/)[1..2]].flatten)
        elsif message =~ /^-linker/
            new_linker(*message.gsub(/^-linker\s+/, '').split(/\s+/, 2))
        elsif message =~ /^-links/
            p from.nick.class
            show_links(server, to, from.nick, message.gsub(/^-links\s+/, '').split(/\s+/).first)
        else
            handle_links(server, from, to, message)
        end
    end

    def new_linker(cmd, link)
        @linkers[cmd] = link
    end

    def link(server, to, cmd, what)
        server.client.fire :message, server, :output, server.client, to, @linkers[cmd].gsub('<', URI.escape(what))
    rescue Exception => e
        self.debug e
        self.debug e.backtrace
    end

    def show_links(server, chan, to, which)
        which = (which =~ /^[\d\.]+$/ ?
            begin
                eval(which)
            rescue
                nil
            end
            : nil)
        which = which.to_i if which.is_a?(Float)

        (case which
            when Range then @links.get_range(chan, which)
            when Fixnum then @links.get_last(chan, which)
            else @links.get_last(chan, 10)
        end).each {|x|
            server.client.fire :message, server, :output, server.client, to, "[#{Time.at(x['date'].to_i).strftime('%d-%m-%Y %H:%M:%S')}] <#{x['user']}> {#{x['link']}} #{x['message']}"
        }
    end

    def handle_links(server, from, to, message)
        (message.extract_urls.map {|x| Links.get_final_link(x) }.delete_if {|x| x == nil }).each {|x|
            begin
                @links.insert(x, from.to_s, to.to_s, server.to_s, message)
                begin
                    title = @html.decode(Net::HTTP::get(URI.parse(x)).match(/<title>(.+?)<\/title>/m)[1].strip.gsub(/\n/, ''))
                rescue
                    raise FakeException
                end
                server.client.fire :message, server, :output, server.client, to, "Title: #{title} (at #{URI.parse(x).host})"
            rescue FakeException
            end
        }
    end

    def links_from_topic(server, old, topic)
        (topic.text.extract_urls.map {|x| Links.get_final_link(x) }.delete_if {|x| x == nil }).each {|x|
            @links.insert(x, topic.setBy.to_s, topic.channel.to_s, server.to_s, topic.text)
        }
    end
end

end

end

end
