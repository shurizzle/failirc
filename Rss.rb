require 'failirc/client/module'
require 'sqlite3'
require 'uri'
require 'net/http'
require 'time'
require 'date'

$DEBUG = true

module IRC

class Client

module Modules

class Rss < Module
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
        nil
    end

    def self.parse(link)
        url = self.get_final_link(link)
        xml = REXML::Document.new(Net::HTTP.get(URI.parse(url)))

        data = {
            :title      => xml.root.elements['channel/title'].text,
            :home_url   => xml.root.elements['channel/link'].text,
            :items      => []
        }

        xml.elements.each('//item') {|item|
            data[:items] << {
                :title          => item.elements['title'].text,
                :link           => item.elements['link'].text
            }

            if item.elements['dc:date']
                data[:items].last[:date] = DateTime.parse(item.elements['dc:date'].text).to_time
            elsif item.elements['pubDate']
                data[:items].last[:date] = DateTime.parse(item.elements['pubDate'].text).to_time
            else
                data[:items].last[:date] = Time.now
            end
        }

        data
    end

    class Database
        class PollPool < Hash
            def initialize(db)
                @db = db
                @index = 0
                super()
            end

            def poll
                return if self.keys.size == 0

                poll_execute(self[self.keys[@index]])
                @index += 1
                @index = 0 if self.keys.size == @index
            end

        private
            def poll_execute(url)
                xml = Rss.parse(url)
                id_feed = @db.execute(%{SELECT id_feed
    FROM rss_feeds
    WHERE url = ?;}, url).first['id_feed']
                id_articles = []
                xml[:items].each {|item|
                    @db.execute(%{INSERT OR IGNORE
    INTO rss_articles
    VALUES(NULL, ?, ?, ?, ?);}, [id_feed, item[:title], item[:link], item[:date].to_i])
                    id_articles << @db.last_insert_row_id
                }
                id_followers = @db.execute(%{SELECT id_follower
    FROM rss_followers_feeds
    WHERE id_feed = ?;}, [id_feed]).map {|i| i['id_follower']}
                id_articles.each {|id_article|
                    id_followers.each {|id_follower|
                        @db.execute(%{INSERT OR IGNORE
    INTO rss_followers_articles
    VALUES(?, ?, 0);}, [id_follower, id_article])
                    }
                }
            rescue Exception => e
                puts e
                puts e.backtrace
                false
            end
        end

        def initialize(db, poll_time = nil, query_time = nil)
            @db = SQLite3::Database.new(db)
            @db.results_as_hash = true
            db_init

            @users = {}
            @db.execute(%{SELECT *
    FROM rss_followers;}).each {|u|
                @users[u['server']] ||= {}
                @users[u['server']][u['user']] = {
                    :id     => u['id_follower'].to_i,
                    :notify => [false, true][u['notify'].to_i],
                    :last   => Time.now
                }
            }
            @feeds = PollPool.new(@db)
            @db.execute(%{SELECT name, url
    FROM rss_feeds;}).each {|f|
                @feeds[f['name']] = f['url']
            }
            @last_poll = Time.now
            @poll_time = poll_time || 300
            @query_time = query_time || 300
        end

        def poll
            return if Time.now < (@last_poll + @poll_time)
            @last_poll = Time.now
            @feeds.poll
        end

        def user_add(server, name, notify = true)
            @db.execute(%{INSERT OR IGNORE
    INTO rss_followers
    VALUES(NULL, ?, ?, ?);}, [server, name, {true=>1,false=>0}[notify]])
            @users[server] ||= {}
            @users[server][name] = {
                :id     => @db.last_insert_row_id,
                :last   => Time.now,
                :notify => notify
            }
            true
        rescue
            false
        end

        def user_del(server, name)
            @db.execute(%{DELETE
    FROM rss_followers
    WHERE id_follower = ?;}, @users[server][name][:id])
            @users[server].delete(name)
            @users.delete(server) if @users[server].empty?
            true
        rescue
            false
        end

        def query?(server, name)
            return false if Time.now < (@users[server][name][:last] + @query_time)
            @users[server][name][:last] = Time.now
            true
        rescue
            false
        end

        def notify?(server, name)
            @users[server][name][:notify]
        rescue
            false
        end

        def have_unread?(server, name)
            @db.execute(%{SELECT COUNT(*) AS unread
    FROM rss_followers_articles
    WHERE id_follower = ?}, @users[server][name][:id]).first['unread'].to_i > 0 ?
                true : false
        rescue
            false
        end
        
        def feed_add(url, name = nil)
            return @db.execute(%{SELECT id_feed
    FROM rss_feeds
    WHERE url = ?}, url).first['id_feed'].to_i if @feeds.values.include?(url)

            xml = Rss.parse(url)
            name ||= xml[:name]

            @db.execute(%{INSERT OR IGNORE
    INTO rss_feeds
    VALUES(NULL, ?, ?);}, [name, url])
            @feeds[name] = url

            id_feed = @db.last_insert_row_id

            xml[:items].each {|item|
                @db.execute(%{INSERT OR IGNORE
    INTO rss_articles
    VALUES(NULL, ?, ?, ?, ?)}, [id_feed, item[:title], item[:link], item[:date].to_i])
            }

            id_feed
        rescue
            false
        end

        def feed_del(name)
            return true if !@feeds[name]
            id_feed = feed_add(@feed[name])

            @db.execute(%{DELETE
    FROM rss_feeds
    WHERE id_feed = ?;}, [id_feed])
            true
        rescue
            false
        end

        def assoc_user_feed(server, name, id_feed)
            return false if !id_feed.is_a?(Integer)
            @db.execute(%{INSERT OR IGNORE
    INTO rss_followers_feeds
    VALUES(?, ?);}, [@users[server][name][:id], id_feed])
            true
        rescue
            false
        end

        def unassoc_user_feed(server, name, id_feed)
            return false if !id_feed.is_a?(Integer)
            @db.execute(%{SELECT id_article
    FROM rss_articles
    WHERE id_feed = ?;}, [id_feed]).map {|x| x['id_article'] }.each {|id_article|
                @db.execute(%{DELETE
    FROM rss_followers_articles
    WHERE id_follower = ? AND
        id_article = ?;}, [@users[server][name][:id], id_article])
            }
            @db.execute(%{DELETE
    FROM rss_followers_feeds
    WHERE id_follower = ? AND
        id_feed = ?;}, [@users[server][name][:id], id_feed])
            true
        rescue
            false
        end

        def user_next_unread(server, name)
            unread = @db.execute(%{SELECT rss_feeds.name, rss_articles.*
    FROM (rss_articles
    INNER JOIN rss_followers_articles
        ON rss_articles.id_article = rss_followers_articles.id_article)
    INNER JOIN rss_feeds
        ON rss_articles.id_feed = rss_feeds.id_feed
    WHERE rss_followers_articles.id_follower = ? AND
        rss_followers_articles.read = 0
    LIMIT 1;}, @users[server][name][:id]).first
            @db.execute(%{UPDATE rss_followers_articles
    SET read = 1
    WHERE id_article = ? AND
        id_follower = ?;}, [unread['id_article'], @users[server][name][:id]])
            unread
        rescue
            nil
        end

        def user_following(server, name)
            @db.execute(%{SELECT rss_feeds.*
    FROM rss_feeds
    INNER JOIN rss_followers_feeds
        ON rss_followers_feeds.id_feed = rss_feeds.id_feed
    WHERE rss_followers_feeds.id_follower = ?;}, @users[server][name][:id])
        rescue
            []
        end

        def feeds
            @feeds.dup
        end

    private
        
        def db_init
            @db.execute(<<-QUERY
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS rss_feeds (
    id_feed     INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name        TEXT UNIQUE,
    url         TEXT UNIQUE
);

CREATE TABLE IF NOT EXISTS rss_articles (
    id_article  INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    id_feed     INTEGER NOT NULL REFERENCES rss_feeds(id_feed) ON DELETE CASCADE ON UPDATE CASCADE,
    title       TEXT NOT NULL,
    link        TEXT UNIQUE NOT NULL,
    date        INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS rss_followers (
    id_follower INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    server      TEXT,
    user        TEXT,
    notify      INTEGER DEFAULT 1
);

CREATE UNIQUE INDEX follower ON rss_followers(server, user);

CREATE TABLE IF NOT EXISTS rss_followers_articles (
    id_follower INTEGER NOT NULL REFERENCES rss_followers(id_follower) ON DELETE CASCADE ON UPDATE CASCADE,
    id_article  INTEGER NOT NULL REFERENCES rss_articles(id_article) ON DELETE CASCADE ON UPDATE CASCADE,
    read        INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(id_follower, id_article)
);

CREATE TABLE IF NOT EXISTS rss_followers_feeds (
    id_follower INTEGER NOT NULL REFERENCES rss_followers(id_follower) ON DELETE CASCADE ON UPDATE CASCADE,
    id_feed     INTEGER NOT NULL REFERENCES rss_feeds(id_feed) ON DELETE CASCADE ON UPDATE CASCADE,
    PRIMARY KEY(id_follower, id_feed)
);
QUERY
            )
        end
    end

    def description
        "Rss-#{Rss.version}"
    end

    def initialize(client)
        @db = Database.new(client.config.elements['config/modules/module[@name="Rss"]/database'].text,
            begin client.config.elements['config/modules/module[@name="Rss"]/pollTime']; rescue; end,
            begin client.config.elements['config/modules/module[@name="Rss"]/queryTime']; rescue; end)

        @events = {
            :pre    => self.method(:poll),

            :custom => {
                :message        => self.method(:dispatch)
            }
        }
        super(client)
    end

    def dispatch(server, chain, from, to, message)
        return if chain != :input

        case message
            when /^-rss\s+on\s*$/i
                @db.user_add(server.name, from.nick)
            when /^-rss\s+off\s*$/i
                @db.user_del(server.name, from.nick)
            when /^-rss\s+next\s*$/i
                show_next(server, from)
            when /^-rss\s+list\s*$/i
                list_rss(server, from)
            when /^-rss\s+following\s*$/i
                list_following(server, from)
            when /^-rss\s+follow\s+.+?\s*$/i
                follow(server, from, message)
            when /^-rss\s+unfollow\s+.+?\s*$/i
                unfollow(server, from, message)
#            when /^-rss\s+(\S+\s+)?\d+/i
#                show_articles(server, from, message)
            when /^-rss\s+add\s+https?:\/\//i
                add_rss(server, from, message)
        end
        activity(server, from, message)
    end

    def poll(*args)
        @db.poll
    end

    def follow(server, from, message)
        name = message.gsub(/^-rss\s+follow\s+/i, '').strip
        id_feed = @db.feed_add(@db.feeds[name])
        if @db.assoc_user_feed(server.name, from.nick, id_feed)
            server.client.fire :message, server, :output, server.client, from, "\x0303Following feed\x03"
        else
            server.client.fire :message, server, :output, server.client, from, "\x0305An error has occurred\x03"
        end
    rescue
        server.client.fire :message, server, :output, server.client, from, "\x0305An error has occurred\x03"
    end

    def unfollow(server, from, message)
        name = message.gsub(/^-rss\s+unfollow\s+/i, '').strip
        id_feed = @db.feed_add(@db.feeds[name])
        if @db.unassoc_user_feed(server.name, from.nick, id_feed)
            server.client.fire :message, server, :output, server.client, from, "\x0303Feed unfollowed\x03"
        else
            server.client.fire :message, server, :output, server.client, from, "\x0305An error has occurred\x03"
        end
    rescue
        server.client.fire :message, server, :output, server.client, from, "\x0305An error has occurred\x03"
    end

    def list_rss(server, from)
        server.client.fire :message, server, :output, server.client, from,
            "[ \x0305" + @db.feeds.keys.join("\x03, \x0305") + "\x03 ]"
    end

    def list_following(server, from)
        server.client.fire :message, server, :output, server.client, from,
            "[ \x0305" + @db.user_following(server.name, from.nick).map {|x| x['name'] }.join("\x03, \x0305") + "\x03 ]"
    end

    def show_next(server, from)
        n = @db.user_next_unread(server.name, from.nick)
        if n
            send_article(server.client, server, from, n)
        else
            server.client.fire :message, server, :output, server.client, from, "\x0305No news\x03"
        end
    end

    def activity(server, from, message)
        if @db.notify?(server.name, from.nick) and
            @db.query?(server.name, from.nick) and
            @db.have_unread?(server.name, from.nick)
            server.client.fire :message, server, :output, server.client, from, "You have many news to read"
        end
    rescue
        nil
    end

    def add_rss(server, user, message)
        message = message.strip.gsub(/^-rss\s+add\s+/, '')
        url = URI.extract(message).first
        name = message.gsub(/^#{Regexp.escape(url)}/, '').strip
        name = name.empty? ? nil : name
        if (feed = @db.feed_add(url, name))
            @db.users_add(server.name, user.nick)
            @db.assoc_user_feed(server.name, user.nick, feed)
            server.client.fire :message, server, :output, server.client, user, "\x0303Rss added\x03"
        else
            server.client.fire :message, server, :output, server.client, user, "\x0305Rss is not valid\x03"
        end
    end

private

    def send_article(client, server, to, article)
        client.fire :message, server, :output, client, to, "[\x0305%s\x03] \xE2\x86\x92 \x0302%s\x03 @ %s" %
            [article['name'], article['title'], article['link']]
    end
end

end

end

end
