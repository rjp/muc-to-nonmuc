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
            puts "+ #{msg.from} #{msg.body}"
			bot.roster.groups.each { |group|
			    bot.roster.find_by_group(group).each { |item|
                    if [:from, :both].include?(item.subscription) then
                        if bot.cache[item.jid] > 0 then
                            puts "#{item.jid} is online, sending"
                            bot.cl.send(Message.new(item.jid, "<#{msg.from}> #{msg.body}"))
                        end
                    end
			    }
			}
        elsif msg.type == :chat then
            puts "+ #{msg.from} #{msg.body}"
        end
    end

    p = Presence.new.set_to(o[:whoto] + "/mucg").set_from(o[:myjid])
    x = MUC::XMUC.new
    p.add(x) 
    bot.cl.send(p)

    return bot
end
