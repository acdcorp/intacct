require 'spec_helper'

describe Intacct::Bill do
  include Helpers

  before { default_setup }

  # Bill wraps a composite object: { payment: payment_obj, vendor: vendor_obj, customer: customer_obj }
  let(:composite) { OpenStruct.new(payment: payment, vendor: vendor, customer: customer) }
  let(:intacct_bill) { Intacct::Bill.new(composite) }

  def build_xml(b)
    b.send(:content_xml) unless b.instance_variable_get(:@content_xml) ||
                                 b.instance_variable_get(:@content_xml_block)
    Nokogiri::XML::Builder.new do |xml|
      xml.create_bill {
        b.send(:build_content_xml, xml)
        b.run_hook :custom_bill_fields, xml, b
        b.run_hook :bill_item_fields, xml, b
      }
    end.doc.root
  end

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

  # ─── content_xml (hash path) ────────────────────────────────────────────────

  describe '#content_xml without block' do
    subject(:h) { Intacct::Bill.new(composite).content_xml }

    it 'returns a Hash' do
      expect(h).to be_a(Hash)
    end

    it 'includes vendorid' do
      expect(h[:vendorid]).to eq vendor.intacct_system_id
    end

    it 'includes datecreated hash' do
      expect(h[:datecreated]).to be_a(Hash)
      expect(h[:datecreated][:year]).to eq payment.created_at.strftime("%Y")
      expect(h[:datecreated][:month]).to eq payment.created_at.strftime("%m")
      expect(h[:datecreated][:day]).to eq payment.created_at.strftime("%d")
    end

    it 'includes dateposted hash' do
      expect(h[:dateposted]).to be_a(Hash)
      expect(h[:dateposted][:year]).to eq payment.created_at.strftime("%Y")
    end

    it 'includes datedue hash' do
      expect(h[:datedue]).to be_a(Hash)
      expect(h[:datedue][:year]).to eq payment.paid_at.strftime("%Y")
      expect(h[:datedue][:month]).to eq payment.paid_at.strftime("%m")
      expect(h[:datedue][:day]).to eq payment.paid_at.strftime("%d")
    end

    it 'stores the result in @content_xml' do
      b = Intacct::Bill.new(composite)
      b.content_xml
      expect(b.instance_variable_get(:@content_xml)).to be_a(Hash)
    end
  end

  describe '#content_xml with block' do
    it 'returns self for chaining' do
      b = Intacct::Bill.new(composite)
      result = b.content_xml { |xml| xml.vendorid 'X' }
      expect(result).to be b
    end

    it 'stores the block in @content_xml_block' do
      b = Intacct::Bill.new(composite)
      b.content_xml { |xml| xml.vendorid 'X' }
      expect(b.instance_variable_get(:@content_xml_block)).to be_a(Proc)
    end

    it 'does not set @content_xml' do
      b = Intacct::Bill.new(composite)
      b.content_xml { |xml| xml.vendorid 'X' }
      expect(b.instance_variable_get(:@content_xml)).to be_nil
    end
  end

  # ─── XML output — hash path ──────────────────────────────────────────────────

  describe 'XML output via hash_to_xml (default path)' do
    let(:b) { Intacct::Bill.new(composite) }

    it 'renders vendorid' do
      root = build_xml(b)
      expect(root.at('vendorid').text).to eq vendor.intacct_system_id.to_s
    end

    it 'renders datecreated with nested year/month/day' do
      root = build_xml(b)
      expect(root.at('datecreated year').text).to eq payment.created_at.strftime("%Y")
      expect(root.at('datecreated month').text).to eq payment.created_at.strftime("%m")
      expect(root.at('datecreated day').text).to eq payment.created_at.strftime("%d")
    end

    it 'renders dateposted with nested year/month/day' do
      root = build_xml(b)
      expect(root.at('dateposted year').text).to eq payment.created_at.strftime("%Y")
    end

    it 'renders datedue with nested year/month/day' do
      root = build_xml(b)
      expect(root.at('datedue year').text).to eq payment.paid_at.strftime("%Y")
      expect(root.at('datedue month').text).to eq payment.paid_at.strftime("%m")
      expect(root.at('datedue day').text).to eq payment.paid_at.strftime("%d")
    end
  end

  # ─── XML output — block path ─────────────────────────────────────────────────

  describe 'XML output via custom block' do
    it 'renders only what the block produces' do
      b = Intacct::Bill.new(composite)
      b.content_xml do |xml|
        xml.vendorid 'BLOCK-VENDOR'
      end
      root = build_xml(b)
      expect(root.at('vendorid').text).to eq 'BLOCK-VENDOR'
      expect(root.at('datecreated')).to be_nil
    end
  end

  # ─── #validate_fields! ───────────────────────────────────────────────────────

  describe '#validate_fields!' do
    context 'intacct_object_id — always-on check' do
      it 'passes when payment has id (prefix + id fallback)' do
        expect { intacct_bill.send(:validate_fields!, :create) }.not_to raise_error
      end

      it 'passes when payment defines intacct_object_id directly (no id needed)' do
        payment.intacct_object_id = 'EXPLICIT-42'
        payment.id = nil
        expect { intacct_bill.send(:validate_fields!, :create) }.not_to raise_error
      end

      it 'raises when neither id nor intacct_object_id resolves to a value' do
        payment.id = nil
        payment.intacct_object_id = nil
        expect { intacct_bill.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Bill requires id or intacct_object_id/)
      end
    end

    context 'gem default [:created_at, :paid_at]' do
      it 'passes when created_at and paid_at are present' do
        expect { intacct_bill.send(:validate_fields!, :create) }.not_to raise_error
        expect { intacct_bill.send(:validate_fields!, :update) }.not_to raise_error
      end

      it 'raises Intacct::Error when created_at is blank on create' do
        payment.created_at = nil
        expect { intacct_bill.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Bill#created_at is required for create/)
      end

      it 'raises Intacct::Error when paid_at is blank on create' do
        payment.paid_at = nil
        expect { intacct_bill.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Bill#paid_at is required for create/)
      end

      it 'raises Intacct::Error when paid_at is blank on update' do
        payment.paid_at = nil
        expect { intacct_bill.send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /Bill#paid_at is required for update/)
      end
    end

    context 'intacct_bill_required_fields overridden globally' do
      before { Intacct.intacct_bill_required_fields = [:id, :created_at, :paid_at, :intacct_key] }
      after  { Intacct.intacct_bill_required_fields = nil }

      it 'applies the override to both create and update' do
        payment.intacct_key = nil
        expect { intacct_bill.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Bill#intacct_key is required for create/)
        payment.intacct_key = nil
        expect { intacct_bill.send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /Bill#intacct_key is required for update/)
      end
    end

    context 'only intacct_bill_create_required_fields set' do
      before { Intacct.intacct_bill_create_required_fields = [:id, :created_at, :paid_at, :intacct_key] }
      after  { Intacct.intacct_bill_create_required_fields = nil }

      it 'validates intacct_key on create' do
        payment.intacct_key = nil
        expect { intacct_bill.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /intacct_key/)
      end

      it 'also applies to update when intacct_bill_update_required_fields is not set' do
        payment.intacct_key = nil
        expect { intacct_bill.send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /intacct_key/)
      end
    end

    context 'both create and update required fields set' do
      before do
        Intacct.intacct_bill_create_required_fields = [:id, :created_at, :paid_at, :intacct_key]
        Intacct.intacct_bill_update_required_fields = [:id, :created_at, :paid_at]
      end
      after do
        Intacct.intacct_bill_create_required_fields = nil
        Intacct.intacct_bill_update_required_fields = nil
      end

      it 'uses create fields for create' do
        payment.intacct_key = nil
        expect { intacct_bill.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /intacct_key/)
      end

      it 'uses update fields for update — intacct_key not required' do
        payment.intacct_key = nil
        expect { intacct_bill.send(:validate_fields!, :update) }.not_to raise_error
      end
    end

    context 'only intacct_bill_update_required_fields set' do
      before { Intacct.intacct_bill_update_required_fields = [:id, :created_at, :paid_at, :intacct_key] }
      after  { Intacct.intacct_bill_update_required_fields = nil }

      it 'uses update fields for update' do
        payment.intacct_key = nil
        expect { intacct_bill.send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /intacct_key/)
      end

      it 'falls back to gem default for create — intacct_key not required' do
        payment.intacct_key = nil
        expect { intacct_bill.send(:validate_fields!, :create) }.not_to raise_error
      end
    end
  end

  # ─── custom_bill_fields hook ─────────────────────────────────────────────────

  describe 'custom_bill_fields hook' do
    let(:b) { Intacct::Bill.new(composite) }

    it 'appends nodes after the default body' do
      b.custom_bill_fields { |xml, _| xml.extra 'bonus' }
      root = build_xml(b)
      expect(root.at('vendorid')).not_to be_nil
      expect(root.at('extra').text).to eq 'bonus'
    end

    it 'appends nodes after a custom block body' do
      b.content_xml { |xml| xml.vendorid 'Block' }
      b.custom_bill_fields { |xml, _| xml.extra 'bonus' }
      root = build_xml(b)
      expect(root.at('vendorid').text).to eq 'Block'
      expect(root.at('extra').text).to eq 'bonus'
    end

    it 'produces no extra nodes when no hook is registered' do
      expect(build_xml(b).at('extra')).to be_nil
    end
  end

  # ─── bill_item_fields hook ───────────────────────────────────────────────────

  describe 'bill_item_fields hook' do
    let(:b) { Intacct::Bill.new(composite) }

    it 'appends item nodes after bill body' do
      b.bill_item_fields { |xml, _| xml.lineitem 'item1' }
      root = build_xml(b)
      expect(root.at('lineitem').text).to eq 'item1'
    end

    it 'produces no item nodes when hook is not registered' do
      expect(build_xml(b).at('lineitem')).to be_nil
    end
  end
end
