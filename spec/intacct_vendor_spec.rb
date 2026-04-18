require 'spec_helper'

describe Intacct::Vendor do
  include Helpers

  before { default_setup }

  # Builds XML through build_content_xml + hook without hitting the Intacct API.
  def build_xml(v)
    v.send(:content_xml) unless v.instance_variable_get(:@content_xml) ||
                                 v.instance_variable_get(:@content_xml_block)
    Nokogiri::XML::Builder.new do |xml|
      xml.create_vendor {
        xml.vendorid v.intacct_object_id
        v.send(:build_content_xml, xml)
        v.run_hook :custom_vendor_fields, xml
      }
    end.doc.root
  end

  # ─── intacct_object_id ──────────────────────────────────────────────────────

  describe '#intacct_object_id' do
    it 'defaults to vendor_prefix + id' do
      expect(Intacct::Vendor.new(vendor).intacct_object_id).to eq "A#{vendor.id}"
    end

    it 'uses intacct_object_id from the object when present' do
      vendor.intacct_object_id = 'OVERRIDE-99'
      expect(Intacct::Vendor.new(vendor).intacct_object_id).to eq 'OVERRIDE-99'
    end
  end

  # ─── content_xml (hash path) ────────────────────────────────────────────────

  describe '#content_xml without block' do
    subject(:h) { Intacct::Vendor.new(vendor).content_xml }

    it 'returns a Hash' do
      expect(h).to be_a(Hash)
    end

    it 'includes top-level vendor fields' do
      expect(h[:name]).to eq vendor.name
      expect(h[:vendtype]).to eq 'Appraiser'
      expect(h[:billingtype]).to eq 'balanceforward'
      expect(h[:status]).to eq 'active'
    end

    it 'nests contact fields under contactinfo > contact' do
      contact = h.dig(:contactinfo, :contact)
      expect(contact[:contactname]).to eq vendor.contactname
      expect(contact[:email1]).to eq vendor.email
      expect(contact[:firstname]).to eq vendor.first_name
      expect(contact[:lastname]).to eq vendor.last_name
    end

    it 'includes mailaddress under contact when billing_address is present' do
      addr = h.dig(:contactinfo, :contact, :mailaddress)
      expect(addr[:address1]).to eq vendor.billing_address.address1
      expect(addr[:city]).to eq vendor.billing_address.city
      expect(addr[:zip]).to eq vendor.billing_address.zipcode
    end

    it 'omits mailaddress when billing_address is absent' do
      vendor.billing_address = nil
      contact = Intacct::Vendor.new(vendor).content_xml.dig(:contactinfo, :contact)
      expect(contact).not_to have_key(:mailaddress)
    end

    context 'with ACH routing number present' do
      it 'includes paymethod, paymentnotify, achenabled' do
        expect(h[:paymethod]).to eq 'ACH'
        expect(h[:paymentnotify]).to eq 'true'
        expect(h[:achenabled]).to eq 'true'
      end

      it 'converts routing and account numbers to integers' do
        expect(h[:achbankroutingnumber]).to eq vendor.ach_routing_number.to_i
        expect(h[:achaccountnumber]).to eq vendor.ach_account_number.to_i
      end

      it 'capitalizes account type and appends Account' do
        expect(h[:achaccounttype]).to eq 'Savings Account'
      end

      it 'uses CCD for business classification' do
        expect(h[:achremittancetype]).to eq 'CCD'
      end

      it 'uses PPD for personal classification' do
        vendor.ach_account_classification = 'personal'
        expect(Intacct::Vendor.new(vendor).content_xml[:achremittancetype]).to eq 'PPD'
      end
    end

    context 'without ACH routing number' do
      before { vendor.ach_routing_number = nil }

      it 'omits all ACH fields' do
        %i[paymethod paymentnotify achenabled achbankroutingnumber
           achaccountnumber achaccounttype achremittancetype].each do |key|
          expect(Intacct::Vendor.new(vendor).content_xml).not_to have_key(key)
        end
      end
    end

    it 'stores the result in @content_xml' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml
      expect(v.instance_variable_get(:@content_xml)).to be_a(Hash)
    end
  end

  # ─── content_xml (block path) ───────────────────────────────────────────────

  describe '#content_xml with block' do
    it 'returns self for chaining' do
      v = Intacct::Vendor.new(vendor)
      result = v.content_xml { |xml| xml.name 'X' }
      expect(result).to be v
    end

    it 'stores the block in @content_xml_block' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml { |xml| xml.name 'X' }
      expect(v.instance_variable_get(:@content_xml_block)).to be_a(Proc)
    end

    it 'does not set @content_xml' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml { |xml| xml.name 'X' }
      expect(v.instance_variable_get(:@content_xml)).to be_nil
    end
  end

  # ─── XML output — hash path ──────────────────────────────────────────────────

  describe 'XML output via hash_to_xml (default path)' do
    let(:root) { build_xml(Intacct::Vendor.new(vendor)) }

    it 'renders vendorid, name, vendtype, billingtype, status' do
      expect(root.at('vendorid').text).to eq "A#{vendor.id}"
      expect(root.at('name').text).to eq vendor.name
      expect(root.at('vendtype').text).to eq 'Appraiser'
      expect(root.at('billingtype').text).to eq 'balanceforward'
      expect(root.at('status').text).to eq 'active'
    end

    it 'renders contactinfo > contact structure' do
      expect(root.at('contactinfo > contact > contactname').text).to eq vendor.contactname
      expect(root.at('contactinfo > contact > email1').text).to eq vendor.email
    end

    it 'renders mailaddress nested inside contact' do
      expect(root.at('contactinfo > contact > mailaddress > city').text).to eq vendor.billing_address.city
    end

    it 'renders ACH block' do
      expect(root.at('paymethod').text).to eq 'ACH'
      expect(root.at('achaccounttype').text).to eq 'Savings Account'
      expect(root.at('achremittancetype').text).to eq 'CCD'
    end

    it 'reflects top-level hash mutations' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml[:vendtype] = 'Inspector'
      expect(build_xml(v).at('vendtype').text).to eq 'Inspector'
    end

    it 'reflects nested hash mutations' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml.dig(:contactinfo, :contact)[:email1] = 'changed@example.com'
      expect(build_xml(v).at('email1').text).to eq 'changed@example.com'
    end
  end

  # ─── XML output — block path ─────────────────────────────────────────────────

  describe 'XML output via custom block' do
    it 'renders only what the block produces' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml do |xml|
        xml.name 'Block Name'
        xml.vendtype 'Block Type'
        xml.contactinfo { xml.contact { xml.contactname 'Block Contact' } }
      end
      root = build_xml(v)
      expect(root.at('name').text).to eq 'Block Name'
      expect(root.at('vendtype').text).to eq 'Block Type'
      expect(root.at('contactinfo > contact > contactname').text).to eq 'Block Contact'
      expect(root.at('billingtype')).to be_nil
      expect(root.at('paymethod')).to be_nil
    end
  end

  # ─── custom_vendor_fields hook ───────────────────────────────────────────────

  describe 'custom_vendor_fields hook' do
    it 'appends nodes after the default body' do
      v = Intacct::Vendor.new(vendor)
      v.custom_vendor_fields { |xml| xml.extra 'bonus' }
      root = build_xml(v)
      expect(root.at('name').text).to eq vendor.name
      expect(root.at('extra').text).to eq 'bonus'
    end

    it 'appends nodes after a custom block body' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml { |xml| xml.name 'Block' }
      v.custom_vendor_fields { |xml| xml.extra 'bonus' }
      root = build_xml(v)
      expect(root.at('name').text).to eq 'Block'
      expect(root.at('extra').text).to eq 'bonus'
    end

    it 'produces no extra nodes when no hook is registered' do
      expect(build_xml(Intacct::Vendor.new(vendor)).at('extra')).to be_nil
    end
  end

  # ─── validate_fields! ────────────────────────────────────────────────────────

  describe '#validate_fields!' do
    context 'gem default [:id, :name]' do
      it 'passes when id and name are present' do
        v = Intacct::Vendor.new(vendor)
        expect { v.send(:validate_fields!, :create) }.not_to raise_error
        expect { v.send(:validate_fields!, :update) }.not_to raise_error
      end

      it 'raises Intacct::Error when name is blank on create' do
        vendor.name = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Vendor#name is required for create/)
      end

      it 'raises Intacct::Error when id is blank on update' do
        vendor.id = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /Vendor#id is required for update/)
      end
    end

    context 'intacct_vendor_required_fields overridden globally' do
      before { Intacct.intacct_vendor_required_fields = [:id, :name, :email] }
      after  { Intacct.intacct_vendor_required_fields = [:id, :name] }

      it 'applies the override to both create and update' do
        vendor.email = nil
        v = Intacct::Vendor.new(vendor)
        expect { v.send(:validate_fields!, :create) }.to raise_error(Intacct::Error, /email/)
        expect { v.send(:validate_fields!, :update) }.to raise_error(Intacct::Error, /email/)
      end
    end

    context 'only intacct_vendor_create_required_fields set' do
      before { Intacct.intacct_vendor_create_required_fields = [:id, :name, :email] }
      after  { Intacct.intacct_vendor_create_required_fields = nil }

      it 'validates email on create' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /email/)
      end

      it 'also applies to update when intacct_vendor_update_required_fields is not set' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /email/)
      end
    end

    context 'both create and update required fields set' do
      before do
        Intacct.intacct_vendor_create_required_fields = [:id, :name, :email]
        Intacct.intacct_vendor_update_required_fields = [:id, :name]
      end
      after do
        Intacct.intacct_vendor_create_required_fields = nil
        Intacct.intacct_vendor_update_required_fields = nil
      end

      it 'uses create fields for create' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /email/)
      end

      it 'uses update fields for update — email not required' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :update) }
          .not_to raise_error
      end
    end

    context 'only intacct_vendor_update_required_fields set' do
      before { Intacct.intacct_vendor_update_required_fields = [:id, :name, :email] }
      after  { Intacct.intacct_vendor_update_required_fields = nil }

      it 'uses update fields for update' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /email/)
      end

      it 'falls back to gem default for create — email not required' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .not_to raise_error
      end
    end
  end
end
