#! /usr/bin/env ruby

require 'rubygems' # should only do this if we require it
require 'optparse'
require 'socket'
require 'xmpp4r'
require 'xmpp4r/framework/bot'
include Jabber

require 'muc_helpers'

$options = { :myjid => 'mucg@localhost', :mypass => 'test', :whoto => 'fish@muc.localhost' }

# next we create a normal client
puts "making client"
x = Thread.new {
    loop do
        sleep 10
        puts "fish"
    end
}

$client = make_message_client($options)

x.join
