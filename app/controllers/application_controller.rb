require './config/environment'
require 'json'

class ApplicationController < Sinatra::Base
  include Recaptcha::Adapters::ControllerMethods
  include Recaptcha::Adapters::ViewMethods

  configure do
    set :public_folder, 'public'
    set :views, 'app/views'
  end

  configure :test do
    set :raise_errors, true
    set :dump_errors, false
    set :show_exceptions, false
  end

  helpers do
    def protected!
      return if authorized?
      headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
      halt 401, "Not authorized\n"
    end

    def authorized?
      @auth ||=  Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == ['admin', ENV.fetch('ADMIN_PASSWORD')]
    end
  end

  before do
    if ENV['SINATRA_ENV'] == 'production'
      redirect request.url.sub('http', 'https') unless request.secure?
    end
  end

  get "/" do
    erb :welcome
  end

  post "/send" do
    content_type :json

    unless verify_recaptcha
      error 403, 'mailer-captcha-failed'
    end

    validator = Mailgun::Address.new ENV.fetch('MAILGUN_VALIDATION_KEY')

    to = Recipient.new(params[:to]).email
    unless validator.validate(to)
      error 400, 'mailer-bad-to'
    end

    reply_to = params[:from]
    unless validator.validate(reply_to)
      error 400, 'mailer-bad-from'
    end

    unless params[:text] =~ /^(?!\s*$).+/ # non-blank, non-whitespace string
      error 400, 'mailer-message-blank'
    end

    unless params[:subject] =~ /^(?!\s*$).+/
      error 400, 'mailer-subject-blank'
    end

    project_name = ENV.fetch('NAME')
    from_address = ENV.fetch('FROM')

    if params[:name] =~ /^(?!\s*$).+/
      from = "#{params[:name]} via #{project_name} <#{from_address}>"
    else
      from = "#{project_name} <#{from_address}>"
    end

    introduction = params[:introduction]
    text = erb(:message, locals: {text: params[:text], introduction: introduction}, layout: nil)
    client = Mailgun::Client.new ENV.fetch('MAILGUN_API_KEY')

    message = Mailgun::MessageBuilder.new
    message.from(from)
    message.add_recipient(:to, to)
    message.reply_to(reply_to)
    message.subject(params[:subject])
    message.body_text(text)

    result = client.send_message(ENV.fetch('DOMAIN'), message)

    if result.code != 200
      halt 500, {status: 'error', message: 'mailer-mail-failed', mailgun_error: result.to_h['message']}.to_json
    end

    {status: 'success', message: 'mailer-message-sent', text: text}.to_json
  end

  get "/decrypt" do
    protected!
    erb :decrypt
  end

  get "/compose" do
    protected!
    erb :compose
  end

  get "/process_decrypt" do
    protected!
    unless verify_recaptcha
      halt 403, 'Captcha failed'
    end

    begin
      Recipient.new(params[:recipient]).cleartext
    rescue ArgumentError => e
      e.message
    end
  end

  private

  def error code, message
    halt code, {status: 'error', message: message}.to_json
  end

end
