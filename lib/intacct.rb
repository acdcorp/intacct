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
                :service_url    ,
                :http_open_timeout, :http_read_timeout,
                :dtdversion, :uniq_id,
                :intacct_vendor_create_required_fields,
                :intacct_vendor_update_required_fields,
                :intacct_customer_create_required_fields,
                :intacct_customer_update_required_fields

  def intacct_vendor_required_fields
    @intacct_vendor_required_fields ||= [:id, :name]
  end

  def intacct_vendor_required_fields=(val)
    @intacct_vendor_required_fields = val
  end

  def intacct_customer_required_fields
    @intacct_customer_required_fields ||= [:id, :name]
  end

  def intacct_customer_required_fields=(val)
    @intacct_customer_required_fields = val
  end

  def customer_fields
    @customer_fields ||= [
      :customerid,
      :name,
      :termname,
      :auto_employee,
      :auto_commission_start_date,
      :auto_commission_end_date,
      :auto_commission_rate,
      :property_employee,
      :property_commission_start_date,
      :property_commission_end_date,
      :property_commission_rate,
      :subro_employee,
      :subro_commission_start_date,
      :subro_commission_end_date,
      :subro_commission_rate
    ]
  end

  def customer_fields=(val)
    @customer_fields = val
  end

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
