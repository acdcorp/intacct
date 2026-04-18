require 'spec_helper'

describe Intacct::Bill do
  include Helpers

  before { default_setup }

  # Bill wraps a composite object: { payment: payment_obj, vendor: vendor_obj, customer: customer_obj }
  let(:composite) { OpenStruct.new(payment: payment, vendor: vendor, customer: customer) }
  let(:intacct_bill) { Intacct::Bill.new(composite) }

  # ─── Intacct::Bill.prefix ───────────────────────────────────────────────────

  describe '.prefix' do
    it 'returns the configured bill_prefix' do
      expect(Intacct::Bill.prefix).to eq 'AUTO-'
    end

    it 'allows client domain model to build intacct_object_id without coupling to Intacct internals' do
      payment.intacct_object_id = "#{Intacct::Bill.prefix}#{payment.id}"
      expect(intacct_bill.intacct_object_id).to eq "AUTO-#{payment.id}"
    end
  end

  # ─── #intacct_object_id ──────────────────────────────────────────────────────

  describe '#intacct_object_id' do
    it 'defaults to bill_prefix + payment.id' do
      expect(intacct_bill.intacct_object_id).to eq "AUTO-#{payment.id}"
    end

    it 'uses object.payment.intacct_object_id when present' do
      payment.intacct_object_id = 'EXPLICIT-BILL-42'
      expect(intacct_bill.intacct_object_id).to eq 'EXPLICIT-BILL-42'
    end

    it 'falls back to prefix + id when intacct_object_id is nil' do
      payment.intacct_object_id = nil
      expect(intacct_bill.intacct_object_id).to eq "AUTO-#{payment.id}"
    end
  end
end
