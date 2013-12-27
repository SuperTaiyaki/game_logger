# No idea why this works automatically on openshift
# use Rack::Static, :urls => ["/scripts"], :root => File.expand_path(File.dirname(__FILE__))
use Rack::Static, :urls => ["/scripts", "/css", "/img"], :root => './public/'

require './members'
Members.create
run Members

