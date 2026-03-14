require "intacct/version"
require 'net/http'
require 'nokogiri'
require 'hooks'
require 'logger'
require "intacct/base"
require "intacct/error"
require "intacct/customer"
require "intacct/vendor"
require "intacct/invoice"
require "intacct/bill"

warn "[DEPRECATION] Intacct gem (v0.0.3): Object#blank?/present? will be removed in v0.1.0. " \
     "Require 'active_support/core_ext/object/blank' instead." unless defined?(ActiveSupport)

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  def present?
    !blank?
  end
end

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
    yield self
  end

  def logger
    @logger ||= ::Logger.new($stdout).tap { |l| l.level = ::Logger::WARN }
  end

  def logger=(log)
    @logger = log
  end
end
