require "intacct/version"
require 'net/http'
require 'nokogiri'
require 'hooks'
require "intacct/base"
require "intacct/error"
require "intacct/customer"
require "intacct/vendor"
require "intacct/invoice"
require "intacct/bill"
require "intacct/new_base"
require "intacct/new_bill"
require "intacct/new_customer"
require "intacct/new_vendor"
require "intacct/api"
require "intacct/response"

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
                :service_url    , :customer_fields

  def setup
    yield self
  end
end
