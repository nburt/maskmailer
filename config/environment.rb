ENV['SINATRA_ENV'] ||= "development"

require 'bundler/setup'
Bundler.require(:default, ENV['SINATRA_ENV'])

Dotenv.load

require './app/controllers/application_controller'
require './lib/recipient'

require_all 'app'
