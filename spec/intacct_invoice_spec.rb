require 'spec_helper'

describe Intacct::Invoice do
  include Helpers

  before { default_setup }

  # Invoice wraps a composite object: { invoice: invoice_obj, vendor: vendor_obj, customer: customer_obj }
  let(:composite) { OpenStruct.new(invoice: invoice, vendor: vendor, customer: customer) }
  let(:intacct_invoice) { Intacct::Invoice.new(composite) }

  # ─── Intacct::Invoice.prefix ────────────────────────────────────────────────

  describe '.prefix' do
    it 'returns the configured invoice_prefix' do
      expect(Intacct::Invoice.prefix).to eq 'AUTO-'
    end

    it 'allows client domain model to build intacct_object_id without coupling to Intacct internals' do
      invoice.intacct_object_id = "#{Intacct::Invoice.prefix}#{invoice.id}"
      expect(intacct_invoice.intacct_object_id).to eq "AUTO-#{invoice.id}"
    end
  end

  # ─── #intacct_object_id ──────────────────────────────────────────────────────

  describe '#intacct_object_id' do
    it 'defaults to invoice_prefix + invoice.id' do
      expect(intacct_invoice.intacct_object_id).to eq "AUTO-#{invoice.id}"
    end

    it 'uses object.invoice.intacct_object_id when present' do
      invoice.intacct_object_id = 'EXPLICIT-INV-42'
      expect(intacct_invoice.intacct_object_id).to eq 'EXPLICIT-INV-42'
    end

    it 'falls back to prefix + id when intacct_object_id is nil' do
      invoice.intacct_object_id = nil
      expect(intacct_invoice.intacct_object_id).to eq "AUTO-#{invoice.id}"
    end
  end
end
