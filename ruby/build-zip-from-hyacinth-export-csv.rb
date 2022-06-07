#!/usr/bin/env ruby

MINIMUM_RUBY_VERSION = '3.0'
REQUIRED_COLUMN_HEADINGS = ['_asset_data.original_filename', '_asset_data.access_copy_location']

raise "This script requires ruby #{MINIMUM_RUBY_VERSION} or later." if RUBY_VERSION < MINIMUM_RUBY_VERSION

require 'rubygems'
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'rubyzip', '~> 2.3'
end

require 'csv'
require 'zip'

hyacinth_csv_file_path = ARGV[0]
zip_output_file_path = ARGV[1]

if hyacinth_csv_file_path.nil? || zip_output_file_path.nil?
  puts <<~USAGE

    usage:
      ruby #{$0} ./path_to_hyacinth_export_csv_file.csv ./path_to_output_zip_file.zip"
      The provided CSV must contain the following headers: #{REQUIRED_COLUMN_HEADINGS.join(', ')}

  USAGE

  exit
end

raise "File not found: #{hyacinth_csv_file_path}" unless File.exist?(hyacinth_csv_file_path)

puts "Reading #{hyacinth_csv_file_path} ..."

# Even though Hyacinth 2 exports double-header CSV files, this script expects only single-header
# files. So double header files need to be cleaned up before they're processed by this script
# (i.e. the human-readable header row just needs to be deleted).
# We'll verify this by ensuring that the CSV file we're given has all required column headings
# in the first row, which is an additional requirement anyway.

csv_is_valid = false
CSV.foreach(hyacinth_csv_file_path) do |row|
  csv_is_valid = true if (row & REQUIRED_COLUMN_HEADINGS).length == 2
end

raise "This CSV is not compatible with this script.  "\
      "It must contain all of the following column headings in the first row: " +
      REQUIRED_COLUMN_HEADINGS.join(', ') unless csv_is_valid

      access_copy_locations_to_file_names = {}

# Keep an eye out for duplicate values (and warn, if we find them)
access_copy_locations = Set.new
new_file_names = Set.new

CSV.foreach(hyacinth_csv_file_path, headers: true) do |row|
  original_filename = row["_asset_data.original_filename"]
  access_copy_location = row["_asset_data.access_copy_location"]
  raise "Error: No original filename available in spreadsheet for #{access_copy_location}" if original_filename.nil? || original_filename.empty?

  # To generate new filename, replace original filename extension with access copy extension
  new_file_name = File.basename(original_filename).gsub(File.extname(original_filename), File.extname(access_copy_location))

  raise "Error: Encountered duplicate access copy location: #{access_copy_location}" if access_copy_locations.include?(access_copy_location)
  access_copy_locations << access_copy_location

  raise "Error: Encountered duplicate original file name: #{original_filename}" if new_file_names.include?(new_file_name)
  new_file_names << original_filename

  access_copy_locations_to_file_names[access_copy_location] = new_file_name
end

puts "Found #{access_copy_locations_to_file_names.length} records"

# If zip output file already exists, prompt to delete
if File.exist?(zip_output_file_path)
  print "An existing file was found at: #{zip_output_file_path}.  Okay to delete it? (y/n) "
  if(STDIN.gets.strip != 'y')
    puts 'A value other than "y" was entered.  Exiting.'
    exit
  end
  puts "Deleted #{zip_output_file_path}"
  File.delete(zip_output_file_path)
end

puts "Writing assets to #{zip_output_file_path} ..."

Zip::File.open(zip_output_file_path, Zip::File::CREATE) do |zipfile|
  access_copy_locations_to_file_names.each do |file_path, new_filename_in_archive|
    # Two arguments:
    # - The name of the file as it will appear in the archive
    # - The original file, including the path to find it
    puts "Adding: #{file_path} as #{new_filename_in_archive}"
    zipfile.add(new_filename_in_archive, file_path)
  end
end

puts "Done!"
