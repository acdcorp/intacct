# Intacct

TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

    gem 'intacct'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install intacct

## Usage

TODO: Write usage instructions here

## Object Interface Requirements

Each domain class wraps a plain Ruby object. The gem calls methods on that object via `respond_to?` — implement only what you need.

---

### `Intacct::Vendor.new(vendor_object)`

| Method | Required? | Notes |
|---|---|---|
| `id` | Required | Used in vendorid: `vendor_prefix + id` |
| `name` | Required | Vendor display name |
| `intacct_system_id` | Required | `nil` for new; Intacct ID string after create. Must persist. |
| `intacct_system_id=` | Required | Written after create; cleared after delete |
| `contactname` | Required | e.g. `"#{last_name}, #{first_name} (#{id})"` |
| `full_name` | Required | Used in `printas` |
| `first_name` | Required | |
| `last_name` | Required | |
| `email` | Required | |
| `tax_number` | Optional | |
| `company_name` | Optional | |
| `business_phone` | Optional | |
| `cell_phone` | Optional | |
| `billing_address` | Optional | Must respond to `address1`, `address2`, `city`, `state`, `zipcode` |
| `ach_routing_number` | Optional | If present, ACH block is included |
| `ach_account_number` | Conditional | Required if `ach_routing_number` present |
| `ach_account_type` | Conditional | `"savings"` or `"checking"` |
| `ach_account_classification` | Conditional | `"business"` or `"personal"` |
| `intacct_object_id` | Optional | Override vendorid (default: `vendor_prefix + id`) |
| `intacct_key` | Optional | Recommended — gem writes back via `respond_to?` |
| `intacct_key=` | Optional | Recommended |

**Required-fields validation** is configured in `Intacct.setup`, not on the domain object:

```ruby
Intacct.setup do |config|
  # Gem default — used when neither of the below is set (default: [:id, :name])
  config.intacct_vendor_required_fields = [:id, :name]

  # If only create is set, it applies to both create and update.
  # If both are set, each applies to its respective operation.
  # If only update is set, create falls back to intacct_vendor_required_fields.
  config.intacct_vendor_create_required_fields = [:id, :name, :email]
  config.intacct_vendor_update_required_fields = [:id, :name]
end
```

Resolution order:
- **create** → `intacct_vendor_create_required_fields` || `intacct_vendor_required_fields`
- **update** → `intacct_vendor_update_required_fields` || `intacct_vendor_create_required_fields` || `intacct_vendor_required_fields`

**Hooks:**

```ruby
vendor = Intacct::Vendor.new(my_vendor)

# Append extra XML after the default body
vendor.on(:custom_vendor_fields) do |xml|
  xml.some_custom_field "value"
end

# Replace the entire body with a custom block
vendor.content_xml do |xml|
  xml.name "Custom Name"
  xml.vendtype "Custom Type"
  xml.contactinfo { xml.contact { xml.contactname "Custom Contact" } }
end

vendor.create
```

**Inspect the default field hash:**

```ruby
vendor.content_xml
# => { name: "Acme Corp", vendtype: "Appraiser", ..., contactinfo: { ... } }
```

---

### `Intacct::Invoice.new(invoice: obj, vendor: obj, customer: obj)`

**`invoice_obj`:**

| Method | Required? | Notes |
|---|---|---|
| `id` | Required | |
| `created_at` | Required | Must respond to `strftime` |
| `intacct_system_id` | Required | |
| `intacct_system_id=` | Required | |
| `intacct_key` / `intacct_key=` | Recommended | |
| `intacct_object_id` | Optional | Override invoiceno |

`customer_obj` and `vendor_obj` follow the same interfaces as their standalone `new` calls above.

**Hooks:**

```ruby
invoice = Intacct::Invoice.new(invoice: my_invoice, vendor: my_vendor, customer: my_customer)
invoice.on(:custom_invoice_fields) do |xml|
  xml.some_custom_field "value"
end
```

---

### `Intacct::Bill.new(bill: obj, vendor: obj, customer: obj)`

Same composite pattern as Invoice — `bill_obj` follows the same shape as `invoice_obj`.

---

### `Intacct::Customer.new(customer_object)`

| Method | Required? | Notes |
|---|---|---|
| `id` | Required | Used in customerid: `customer_prefix + id` |
| `name` | Required | Customer display name |
| `intacct_system_id` | Required | `nil` for new; Intacct ID string after create. Must persist. |
| `intacct_system_id=` | Required | Written after create; cleared after delete |
| `intacct_object_id` | Optional | Override customerid (default: `customer_prefix + id`) |
| `intacct_key` | Optional | Recommended — gem writes back via `respond_to?` |
| `intacct_key=` | Optional | Recommended |

**Required-fields validation** follows the same setup pattern as Vendor:

```ruby
Intacct.setup do |config|
  config.intacct_customer_required_fields        = [:id, :name]          # gem default
  config.intacct_customer_create_required_fields = [:id, :name]
  config.intacct_customer_update_required_fields = [:id, :name]
end
```

Resolution order:
- **create** → `intacct_customer_create_required_fields` || `intacct_customer_required_fields`
- **update** → `intacct_customer_update_required_fields` || `intacct_customer_create_required_fields` || `intacct_customer_required_fields`

**`get` fields** — controls which fields are fetched from Intacct when calling `customer.get`. Defaults to a standard set; override in setup to fetch only what you need:

```ruby
Intacct.setup do |config|
  config.customer_fields = [
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
```

You can also pass fields directly to `get` to override the setup value for a single call:

```ruby
Intacct::Customer.new(my_customer).get(:customerid, :name, :termname)
```

**Hooks:**

```ruby
customer = Intacct::Customer.new(my_customer)

# Append extra XML after the default body (instance-level)
customer.custom_customer_fields do |xml|
  xml.some_custom_field "value"
end

# Or register at the class level in an initializer — fires for every instance
module Intacct
  class Customer
    custom_customer_fields do |xml|
      xml.some_custom_field "value"
    end
  end
end

# Replace the entire body with a custom block
customer.content_xml do |xml|
  xml.name "Custom Name"
  xml.status "active"
end

customer.create
```

**Inspect the default field hash:**

```ruby
customer.content_xml
# => { name: "Acme Corp", comments: nil, status: "active" }
```

---

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
