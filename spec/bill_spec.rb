require 'spec_helper'
require 'support/intacct_helpers'

describe Intacct::Bill do
  before { setup_credentials }

  describe "#get_list" do
    it "sends a get_list request with object=bill" do
      req = stub_intacct(SUCCESS_XML)
      instance = described_class.new
      instance.get_list(5) {}
      expect(req).to have_been_requested
      expect(instance.sent_xml).to include('object="bill"')
      expect(instance.sent_xml).to include('maxitems="5"')
    end
  end

  describe ".list" do
    it "returns a QueryResult" do
      stub_intacct(SUCCESS_XML)
      result = described_class.list(limit: 1) {}
      expect(result).to be_a(Intacct::QueryResult)
    end
  end
end
