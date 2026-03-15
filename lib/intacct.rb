require "intacct/version"
require 'ostruct'
require 'net/http'
require 'nokogiri'
require 'hooks'
require 'logger'
require 'active_support/core_ext/object/blank'
require "intacct/base"
require "intacct/error"
require "intacct/query_result"
require "intacct/customer"
require "intacct/vendor"
require "intacct/invoice"
require "intacct/bill"
require "intacct/resource_config"

module Intacct
  extend self

  attr_accessor :xml_sender_id  , :xml_password    ,
                :app_user_id    , :app_company_id  ,
                :app_password   , :invoice_prefix  ,
                :bill_prefix    , :vendor_prefix   ,
                :customer_prefix, :system_name     ,
                :service_url    , :customer_fields ,
                :http_open_timeout, :http_read_timeout

  def setup
    config = ResourceConfig.new
    yield config
    config.apply!
    config
  end

  def logger
    @logger ||= ::Logger.new($stdout).tap { |l| l.level = ::Logger::WARN }
  end

  def logger=(log)
    @logger = log
  end

  def ping
    Base.ping
  end
end
