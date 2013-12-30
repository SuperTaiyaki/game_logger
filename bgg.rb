#!/usr/bin/ruby

require 'rexml/document'
require 'net/http'

# Boardgamegeek data import

TARGET_LIST=153822 # Cafe Meeple board game collection
SEARCH_URL='http://www.boardgamegeek.com/xmlapi/geeklist/' # append list ID to the end
TEMP_FILENAME="gamelist.xml"
FILENAME=File.join(ENV['OPENSHIFT_DATA_DIR'], TEMP_FILENAME)

def download_list(url)
    #return # DEBUG Don't hammer the server
    data = Net::HTTP.get(URI(SEARCH_URL + url))
    f = File.open(FILENAME, mode="w")
    f.write(data)
    f.close
end

def load_xml()
    f = File.open(FILENAME)
    doc = REXML::Document.new(f)
    f.close()

    if doc.find("geeklist") == nil
        return "Error: Not a valid list"
    end
    doc
end

def last_update()
    doc = load_xml

    doc.elements['geeklist/editdate_timestamp'].text
end

def show_list()

    doc = load_xml

    games = []

    doc.elements.each('geeklist/item') do |game|
        games.push({:name => game.attributes['objectname'],
                         :bgg_id => game.attributes['objectid']})
    end
    games
end

