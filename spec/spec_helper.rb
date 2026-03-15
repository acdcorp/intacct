require 'rubygems'
require 'bundler/setup'
# our gem
require 'intacct'
require 'dotenv'
require "faker"
require "pry"
require 'awesome_print'
require 'helpers'
require 'webmock/rspec'

Dotenv.load

if ENV['INTACCT_INTEGRATION']
  WebMock.allow_net_connect!
else
  WebMock.disable_net_connect!
end

Dir["./spec/steps/**/*steps.rb"].each { |f| require f }

RSpec.configure do |config|
  config.include Helpers
end
