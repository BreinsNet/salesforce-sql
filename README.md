# Salesforce::Sql

TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

    gem 'salesforce-sql'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install salesforce-sql

## Usage

This gem is in a very early stage, please use under your own risk:

copy a table:


```
require 'salesforce/sql'

# Crednetials:
src_credentials = {
  :host           => 'test.salesforce.com',
  :username       => 'user@example.com.source',
  :password       => 'pass',
  :client_id      => 'client_id',
  :client_secret  => 'client_secret'
}

dst_credentials  = {
  :host           => 'test.salesforce.com',
  :username       => 'user@example.com.destination',
  :password       => 'pass',
  :client_id      => 'client_id',
  :client_secret  => 'client_secret'
}

# Initialize sql objects
src = Salesforce::Sql::App.new src_credentials
dst = Salesforce::Sql::App.new dst_credentials

account_ignore_fields = [ 
  'Status__c',
  'Other__c',
]

# Delete current Account content
dst.delete 'Account'

# Copy src Accounts to Destination
dst.copy_object source: src, 
  object: 'Account',
  ignore_fields: account_ignore_fields

# Delete contact table
dst.delete 'Contact'

# Copy contacts preserving IDs
dst.copy_object source: src, 
  object: 'Contact',
  object_ids: contact_ids,
  ignore_fields: contact_ignore_fields,
  dependencies: [
    {
      dependency_object: 'Account',
      dependency_object_pk: 'Name',
      object_fk_field: 'AccountId',
    },
  ]

```

You could also do partial copy specifying ids:

```
account_ids = File.read('ids.txt').split("\n").sort.uniq
dst.copy_object source: src,
  object: 'Account',
  object_ids: account_ids,
  ignore_fields: account_ignore_fields


```

## Contributing

1. Fork it ( https://github.com/[my-github-username]/salesforce-sql/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
