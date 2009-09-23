require 'rubygems' # should only do this if we require it
require 'optparse'
require 'socket'
require 'xmpp4r'
require 'xmpp4r/framework/bot'
require 'xmpp4r/delay/x/delay'
require 'xmpp4r/muc/helper/mucclient'
require 'xmpp4r/muc/iq/mucadminitem'
require 'xmpp4r/muc/x/muc'
include Jabber

$filters = Hash.new { |h,k| h[k] = Array.new }

def filter(message, filters)
    denied = 0; allowed = 0; global_allow = 0; global_denied = 0
    filters.each { |dir, regexp|
        if message =~ Regexp.new(regexp) then
            puts "+ #{message} =~ /#{regexp}/"
            case dir
                when 'allow'
                    if regexp == '.*' then
                        global_allow = 1
                    else
                        allowed = 1
                    end
                when 'deny'
                    if regexp == '.*' then
                        global_denied = 1
                    else
                        denied = 1
                    end
            end
        end
    }
    puts "after filters, allowed=#{allowed}, global_allow=#{global_allow}, denied=#{denied}"
    if (allowed == 1 and denied == 0) or (global_allow == 1 and denied == 0) then
        return true
    end

    return false
end

def make_message_client(o)
    subscription_callback = lambda { |item,pres|
      name = pres.from
      if item != nil && item.iname != nil
        name = "#{item.iname} (#{pres.from})"
      end
      case pres.type
        when :subscribe then puts("Subscription request from #{name}")
        when :subscribed then puts("Subscribed to #{name}")
        when :unsubscribe then puts("Unsubscription request from #{name}")
        when :unsubscribed then puts("Unsubscribed from #{name}")
        else raise "The Roster Helper is buggy!!! subscription callback with type=#{pres.type}"
      end
    }

    bot = Jabber::Framework::Bot.new(o[:myjid], o[:mypass])
    class << bot
      attr_accessor :cache

      def accept_subscription_from?(jid)
        if jid == o[:whoto] then
            true
        else
            false
        end
      end
    end

    bot.cache = Hash.new(0)
    bot.set_presence(nil, "Waiting for socket tickling...")

    bot.roster.add_presence_callback { |olditem, item|
        puts "old=#{olditem.inspect}"
        puts "new=#{item.inspect}"
        if item.nil? then
            bot.cache[olditem.jid] = 1
        else
            bot.cache[olditem.jid] = 0
        end
    }

    bot.roster.add_update_callback { |olditem,item|
        p olditem
        p item
      if [:from, :none].include?(item.subscription) && item.ask != :subscribe && item.jid == o[:whoto]
        if $options[:debug] > 0 then
            puts("Subscribing to #{item.jid}")
        end
        item.subscribe
      end
    }

    bot.roster.add_subscription_callback(0, nil, &subscription_callback)

    bot.roster.groups.each { |group|
        bot.roster.find_by_group(group).each { |item|
            if [:from, :none].include?(item.subscription) && item.ask != :subscribe && item.jid == $options[:whoto] then
                if $options[:debug] > 0 then
                    puts "subscribing to #{item.jid}"
                end
                item.subscribe
            end
        }
    }

    bot.cl.add_message_callback do |msg|
        if msg.type == :groupchat then
            puts "G+ #{msg.from} #{msg.body}"
            bot.roster.groups.each { |group|
                bot.roster.find_by_group(group).each { |item|
                    if [:from, :both].include?(item.subscription) then
                        if bot.cache[item.jid] > 0 then
                            puts "#{item.jid} is online, sending"
                            p $filters
                            if filter(msg.body, $filters[item.jid.strip.to_s].to_a) then
                                puts "sending to #{item.jid}"
                                msg = Message.new(item.jid, "<#{msg.from.resource}> #{msg.body}")
                                msg.type = :chat
                                bot.cl.send(msg)
                            else
                                puts "blocked send to #{item.jid}"
                            end
                        end
                    end
                }
            }
        elsif msg.type == :chat then
            puts "C+ #{msg.from} #{msg.body}"
            if msg.body =~ /^filter(!?) (.+)/ then
                key = ($1 == '!' ?  msg.from.to_s : msg.from.strip.to_s)
                filter = $2
                p [key, filter]
                if filter =~ /^(deny|allow)=(.+)/i then
                    puts "k=#{key} f=#{msg.from.to_s} r=#{filter}"
                    # valid filter setting
                    $filters[key].push [$1, $2]
                end
                p $filters[key]
            end
        end
    end

    p = Presence.new.set_to(o[:whoto] + "/mucg").set_from(o[:myjid])
    x = MUC::XMUC.new
    p.add(x)
    bot.cl.send(p)

    return bot
end
