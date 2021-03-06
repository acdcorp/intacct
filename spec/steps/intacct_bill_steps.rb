module IntacctBillSteps
  class << self
    attr_accessor :intacct_key
  end

  step 'I have setup the correct settings' do
    default_setup
    custom_fields_for_auto
  end

  step('I have an payment, customer and vendor') { payment; customer; vendor }

  step 'I create an Intacct Bill object' do
    @intacct_bill = Intacct::Bill.new({
      payment: payment,
      customer: customer,
      vendor: vendor
    })
  end

  step 'I use the #create method' do
    # We need to remove the fake intacct_system_id so it creates a real one
    @intacct_bill.object.payment.intacct_system_id = nil
    @intacct_bill.object.customer.intacct_system_id = nil
    @intacct_bill.object.vendor.intacct_system_id = nil
    @response = @intacct_bill.create
    IntacctBillSteps.intacct_key = @intacct_bill.object.payment.intacct_key

    @intacct_bill2 = Intacct::Bill.new({
      payment: payment,
      customer: customer,
      vendor: vendor
    })
    @intacct_bill2.object.payment.intacct_system_id = nil
    @response2 = @intacct_bill2.create

  end

  step 'I use the #delete method' do
    @intacct_bill.object.payment.intacct_key = IntacctBillSteps.intacct_key
    @response = @intacct_bill.delete
    if @response
      Intacct::Customer.new(@intacct_bill.object.customer).delete
      Intacct::Vendor.new(@intacct_bill.object.vendor).delete
    end
  end

  def custom_fields_for_auto
    Intacct::Bill.class_eval do
      custom_bill_fields do |xml|
        xml.billno intacct_object_id #intact bill id
        xml.ponumber object.payment.claim.claimnumber
        xml.description "some description"
        xml.externalid "AUTO-#{object.payment.id}"
        xml.basecurr "USD"
        xml.currency "USD"
        xml.exchratetype "Intacct Daily Rate"
        xml.customfields {
          xml.customfield {
            xml.customfieldname "CLAIM_NUMBER_ACD"
            xml.customfieldvalue object.payment.claim.dlnumber
          }
          xml.customfield {
            xml.customfieldname "CLAIM_NUMBER_CLIENT"
            xml.customfieldvalue object.payment.claim.claimnumber
          }
          xml.customfield {
            xml.customfieldname "VEHICLE_YEAR"
            xml.customfieldvalue object.payment.claim.vehicle.year
          }
          xml.customfield {
            xml.customfieldname "VEHICLE_MAKE"
            xml.customfieldvalue object.payment.claim.vehicle.make
          }
          xml.customfield {
            xml.customfieldname "VEHICLE_MODEL"
            xml.customfieldvalue object.payment.claim.vehicle.model
          }
          xml.customfield {
            xml.customfieldname "VEHICLE_TYPE"
            xml.customfieldvalue object.payment.claim.appraisal_type
          }
          xml.customfield {
            xml.customfieldname "NAME_OWNER"
            xml.customfieldvalue object.payment.claim.owner.full_name
          }
          xml.customfield {
            xml.customfieldname "NAME_INSURED"
            xml.customfieldvalue object.payment.claim.owner.insuredorclaimant=="INSURED" ? object.payment.claim.owner.full_name : object.payment.claim.insured_full_name
          }
          xml.customfield {
            xml.customfieldname "NAME_CLAIMANT"
            xml.customfieldvalue object.payment.claim.owner.insuredorclaimant=="CLAIMANT" ? object.payment.claim.owner.full_name : ""
          }
          xml.customfield {
            xml.customfieldname "LOCATION_CITY"
            xml.customfieldvalue object.payment.claim.vehicle.address.city
          }
          xml.customfield {
            xml.customfieldname "LOCATION_STATE"
            xml.customfieldvalue object.payment.claim.vehicle.address.state
          }
          xml.customfield {
            xml.customfieldname "LOCATION_ZIP"
            xml.customfieldvalue object.payment.claim.vehicle.address.zipcode
          }
          xml.customfield {
            xml.customfieldname "MILEAGE_RT_BILLABLE"
            xml.customfieldvalue 100
          }
          xml.customfield {
            xml.customfieldname "MILEAGE_RT_TOTAL"
            xml.customfieldvalue 100
          }
          xml.customfield {
            xml.customfieldname "MILEAGE_RATE"
            xml.customfieldvalue object.payment.mileage_rate
          }
          xml.customfield {
            xml.customfieldname "NAME_ADJUSTER"
            xml.customfieldvalue "#{object.payment.claim.adjuster.last_name}, #{object.payment.claim.adjuster.first_name}"
          }
          xml.customfield {
            xml.customfieldname "CLAIM_CREATED_DATE"
            xml.customfieldvalue object.payment.claim.dtcreated.strftime("%m/%d/%Y")
          }
          xml.customfield {
            xml.customfieldname "NAME_PROCESSOR"
            xml.customfieldvalue object.payment.creator.full_name
          }
          if object.payment.claim.dtloss.present?
            xml.customfield {
              xml.customfieldname "LOSS_DATE"
              xml.customfieldvalue object.payment.claim.dtloss.strftime("%m/%d/%Y")
            }
          end
          xml.customfield {
            xml.customfieldname "LOSS_CATEGORY"
            xml.customfieldvalue object.payment.claim.coveragetype
          }
          if object.payment.claim.estimate_id.present?
            xml.customfield {
              xml.customfieldname "LOSS_ESTIMATE_AMOUNT"
              xml.customfieldvalue object.payment.claim.estimate.estimate_amt
            }
            xml.customfield {
              xml.customfieldname "LOSS_FINAL_AMOUNT"
              xml.customfieldvalue object.payment.claim.estimate.estimate_final_amt
            }
          end
          xml.customfield {
            xml.customfieldname "ASSIGNMENT_TYPE"
            xml.customfieldvalue object.payment.type
          }
        }
      end
      bill_item_fields do |xml|
        xml.billitems {
          #set amount
          xml.lineitem {
            xml.glaccountno 4040
            xml.amount 100
            xml.memo object.payment.note
            xml.locationid "ACDCorp"
            xml.customerid object.customer.intacct_system_id
            xml.vendorid object.vendor.intacct_system_id
            xml.employeeid
            xml.classid "A100" #hardcoded = will always be A100
          }
          #set mileage amount if exists
          if object.payment.mileage_amt!=0
            xml.lineitem {
              xml.glaccountno 4040
              xml.amount 100
              xml.memo object.payment.note
              xml.locationid "ACDCorp"
              xml.customerid object.customer.intacct_system_id
              xml.vendorid object.vendor.intacct_system_id
              xml.employeeid
              xml.classid "A100" #hardcoded = will always be A100
            }
          end
        }
      end
    end
  end
end
