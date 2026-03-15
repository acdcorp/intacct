require 'spec_helper'
require 'support/intacct_helpers'

describe Intacct do
  before { setup_credentials }

  describe ".ping" do
    it "returns true on a successful response" do
      stub_intacct(SUCCESS_XML)
      expect(Intacct.ping).to eq(true)
    end

    it "returns false on an auth failure response" do
      stub_intacct(FAILURE_XML)
      expect(Intacct.ping).to eq(false)
    end

    it "returns false when an exception is raised" do
      stub_request(:post, INTACCT_URL).to_raise(Net::OpenTimeout)
      expect(Intacct.ping).to eq(false)
    end
  end
end
