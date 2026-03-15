require 'spec_helper'
require 'support/intacct_helpers'

describe Intacct::Customer do
  before { setup_credentials }

  describe "#get" do
    it "sends a get request with the customer id" do
      req = stub_intacct(SUCCESS_XML)
      stub = OpenStruct.new(intacct_system_id: "C123")
      instance = described_class.new(stub)
      instance.get([:customerid, :name])
      expect(req).to have_been_requested
      expect(instance.sent_xml).to include('object="customer"')
      expect(instance.sent_xml).to include('key="C123"')
      expect(instance.sent_xml).to include('<field>customerid</field>')
      expect(instance.sent_xml).to include('<field>name</field>')
    end
  end

  describe ".find" do
    it "returns a QueryResult" do
      stub_intacct(SUCCESS_XML)
      result = described_class.find(id: "C123", fields: [:customerid, :name])
      expect(result).to be_a(Intacct::QueryResult)
    end
  end
end
