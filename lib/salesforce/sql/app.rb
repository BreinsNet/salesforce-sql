module Salesforce
  module Sql
    class App

      attr_accessor :debug
      attr_accessor :username
      attr_accessor :step

      def initialize credentials

        # Login credentials
        @restforce_client = restforce_rest_login credentials
        @salesforce_bulk_client = salesforce_bulk_login credentials[:username], credentials[:password], credentials[:host]
        @username = credentials[:username]

        # Default variables:
        @bulk_api_step = 10000
        @debug = false
        @step = 100
        @default_ignore_fields = [
          'Id',
          'IsDeleted',
          'MasterRecordId',
          'RecordTypeId',
          'ParentId',
          'OwnerId',
          'CreatedById',
          'CreatedDate',
          'LastModifiedDate',
          'LastModifiedById', 
          'SystemModstamp',
          'LastActivityDate',
        ]

      end

      def get_fields object

        fields = @restforce_client.describe(object)['fields'].select do |field| 
          field['name'][-4..-1] != '__pc' && field['calculated'] != true  
        end
        fields.map {|f| f['name']}

      end

      def query_select_in query, ids = []
        retval = []
        if ids.empty?
          retval = normalize_query @restforce_client.query(query)
        else
          (0..(ids.size-1)).step(@step).each do |n|

            # Create the query
            ids_string = ids[n..(n+@step-1)].map {|i| "'#{i}'"}.join ','
            stepped_query =  query + " IN (#{ids_string})" 

            # run it and add it to the result
            retval += normalize_query @restforce_client.query(stepped_query)
          end
        end

        retval
      end

      def query query, ids = []

        retval = []
        if ids.empty?
          retval = normalize_query @restforce_client.query(query)
        else
          (0..(ids.size-1)).step(@step).each do |n|

            # Create the query
            ids_string = ids[n..(n+@step-1)].map {|i| "'#{i}'"}.join ','
            stepped_query =  query + " WHERE Id IN (#{ids_string})" 

            # run it and add it to the result
            retval += normalize_query @restforce_client.query(stepped_query)
          end
        end

        retval

      end

      def delete object

        query = "Select Id FROM #{object}" 
        bulk_delete_records = normalize_query @restforce_client.query(query)

        print_debug "#{bulk_delete_records.size} #{object} records added to delete on #{self.username}"

        bulk_delete object, bulk_delete_records if !bulk_delete_records.empty?

      end

      # Description: Copy an object from one source to target
      # Parameters:
      #   object: The object to copy
      #   object_ids: An array of object ids to limit the query
      #   ignore_fields: An array of fields to ignore
      #   dependencies: When trying to copy a TABLE with DEPENDENCIES
      #     dependency_object: The DEPENDENCY object name
      #     dependency_object_pk: the DEPENENCY field to be used as primary key 
      #     object_fk_field: The foreign key field name in the TABLE

      def copy_object source:, object:, object_ids: [], ignore_fields: [], dependencies: []

        # Remove well known problematic fields and merge them with user requirements:
        ignore_fields = (ignore_fields + @default_ignore_fields).uniq
        
        # Get all the fields from source and destination removing __pc and calculated ones
        source_object_fields = get_fields object
        target_object_fields = source.get_fields object

        # Get common fields
        object_fields = source_object_fields & target_object_fields

        # Get all the records from the source sandbox and store them in bulk_import_records
        bulk_import_records = source.query "Select #{object_fields.join(',')} FROM #{object}", object_ids

        # Dependencies ID Matching:
        dependencies.each do |dep|

          # Export the dependency object ids from the source sandbox
          dependency_ids = bulk_import_records.map{|row| row[dep[:object_fk_field]]}.sort.uniq

          # Use those Ids to get the object records from source including the dependency_object_pk
          source_object = source.query "Select Id,#{dep[:dependency_object_pk]} FROM #{dep[:dependency_object]}", dependency_ids

          # Get the dependency_object_pk values and export the IDs from the target object
          dependency_object_pk_values = source_object.map {|row| row[dep[:dependency_object_pk]].gsub("'", %q(\\\'))}
          target_object = self.query_select_in "Select Id,#{dep[:dependency_object_pk]} FROM #{dep[:dependency_object]} WHERE #{dep[:dependency_object_pk]}", dependency_object_pk_values

          # Now we have source_object and target_object ids and values, we can do the mapping on bulk_import_records
          source_object.each do |row|
            source_id = row['Id']
            target_id = target_object.select{|r| r[dep[:dependency_object_pk]] == row[dep[:dependency_object_pk]]}.first['Id']
            bulk_import_records.each {|r| r[dep[:object_fk_field]] = target_id if r[dep[:object_fk_field]] == source_id}
          end

        end

        # Remove ignored fields
        bulk_import_records.each do |row|
          ignore_fields.each {|f| row.delete f}
        end

        print_debug "#{bulk_import_records.size} #{object} records added to import on #{self.username}"

        # Import the data using salesforce_bulk
        if !bulk_import_records.empty?
          bulk_insert object, bulk_import_records
        end

      end

      private

      def bulk_insert object, records
        (0..(records.size-1)).step(@bulk_api_step).each do |n|
          job = @salesforce_bulk_client.create object, records[n..n+@bulk_api_step-1]
          salesforce_bulk_job_status job
        end
      end

      def bulk_delete object, records
        (0..(records.size-1)).step(@bulk_api_step).each do |n|
          job = @salesforce_bulk_client.delete object, records[n..n+@bulk_api_step-1]
          salesforce_bulk_job_status job
        end
      end

      def normalize_query records
        records.to_a.each do |row| 
          row.delete 'attributes'
          row.delete 'IsPersonAccount'
        end
      end

      def delete_ignored_fields set
        set.to_a.each do |row|
          @default_ignore_fields.each {|field| row.delete field }
        end
      end

      def salesforce_bulk_job_status job
        sleep 1 while job.check_batch_status.match(/InProgress|Queued/)
        print_debug "Bulk job status: #{job.check_batch_status}"
        job.check_batch_status == "Completed" ? true : false
      end

      def print_debug message
        puts "DEBUG: #{message[0..TermInfo.screen_size.last]}" if @debug
      end

      def restforce_rest_login credentials
        begin
          client = Restforce.new :host          => credentials[:host],
                                 :username      => credentials[:username],
                                 :password      => credentials[:password],
                                 :client_id     => credentials[:client_id],
                                 :client_secret => credentials[:client_secret]
          client.authenticate!
          client
        rescue => e
          puts "Error trying to login rest API using: #{credentials[:username]} "
          puts e
          exit 1
        end
      end

      def salesforce_bulk_login user, pass, host
        begin
          sandbox = host.match(/login/) ? nil : true
          SalesforceBulk::Api.new(user,pass,sandbox)
        rescue => e
          puts "Error trying to login bulk API using: #{user} "
          puts e
          exit 1
        end
      end

    end
  end
end
