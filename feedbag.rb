#!/usr/local/bin/ruby
#
# Feed Bag - A RSS Feed Archiver
#
# USAGE
#   feedbag [OPTIONS] [RSS_URL ...]
#
# ARGUMENTS
#
#   When provided, the RSS_URL will be read, added to the database and
#   scanned for next run.
#
#   When no arguments are provided, all the existing feeds in the database
#   will be scanned for new items.
#
# OPTIONS
#   -d   --db       Use the given SQLite3 database
#   -C   --clean    Destroy the database and rebuild (be careful!)
#   -l   --list     List all the feeds
#   -h   --help     Show a help message
#
# AUTHOR
#   Mark D. Reid <mark.reid@anu.edu.au>
#   
#   Updated by Sebastian Beschke <sebastian@sbeschke.de>
#
# CREATED
#   2008-01-18

require 'rubygems'
require 'feed-normalizer'
require 'sequel'
require 'optparse'

dbFile = "feedbag.db"
optListFeeds = false
optClean = false


def clean_feeds
  DB.drop_table? (:feeds)
end

def clean_entries
  DB.drop_table?(:entries)
end

# Wipes the entire database clean.
def clean
  clean_entries
  clean_feeds
end

def initFeedTable
  DB.create_table? :feeds do
    primary_key   :id
    text          :name
    text          :url
    time          :last_checked
    time          :created
  end
end

def initEntryTable
  DB.create_table? :entries do
    primary_key   :id
    text          :url
    text          :title
    text          :content
    text          :description
    time          :time

    foreign_key   :feed_id, :table => :feeds
    index         :url
  end
end

def scan(feed)
  feedin = FeedNormalizer::FeedNormalizer.parse open(feed.url)
  feedin.items.each do |item|
    if item.date_published > feed.last_checked
      puts "\t#{item.title}"
      entry = Entry.new
      entry.url = item.url
      entry.title = item.title
      entry.content = item.content
      entry.description = item.description unless item.description == item.content
      entry.time = item.date_published
      entry.feed_id = feed.id
      entry.save
    else
      print "."
    end
  end
  feed.tick
end

# Parse the command-line options and clean database if necessary
opts = OptionParser.new
opts.banner = "Usage: feedbag.rb [options] [feed_url]+"
opts.on('-d', '--db DB', 'Use feed database DB') do |db| 
  dbFile = db
end
opts.on('-l', '--list', 'List all the feeds') do
  optListFeeds = true
end
opts.on('-C', '--clean', 'Wipes the current feed DB') do
  optClean = true
end
opts.on_tail("-h", "--help", "Show this message") do
  puts opts
  exit
end
opts.parse!

# Open the given file as an SQLite database using Sequel and the models
DB = Sequel.sqlite(dbFile)
puts "Using #{dbFile} for Feed DB"

require_relative 'models'

if optClean
  clean
  initFeedTable
  initEntryTable
  puts "Cleaned DB!"
  exit
end

# Build up the tables after a clean or on first run
initFeedTable
initEntryTable

if optListFeeds
  Feed.each { |feed| puts "#{feed.id}: #{feed.name} (Checked: #{feed.last_checked}) - #{feed.entries.count}\n" }
  exit
end


# Add any feeds if they appear as arguments
if ARGV.empty?
  Feed.each { |feed| puts "\nScanning #{feed.name}"; scan feed }
else
  # Add RSS URLs to the databases
  ARGV.each do |arg|
    existing = Feed.where {:url == arg}
    if existing.empty?
      puts "Creating new feed for #{arg}"
      feed = Feed.new
      feed.set(:url => arg)
      feed.save
    else
      feed = existing.first
      puts "Feed entitled '#{feed.name}' already exists for #{arg}"
    end
  end
end


