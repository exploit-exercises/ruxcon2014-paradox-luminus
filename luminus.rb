require 'sinatra'
require 'sinatra/synchrony'

require 'haml'
require 'sqlite3'
require 'securerandom'
require 'digest/md5'
require 'thin'
require 'fileutils'

use Rack::CommonLogger

set :session_secret, SecureRandom.urlsafe_base64 + SecureRandom.urlsafe_base64
enable :sessions

set :public_folder, File.dirname(__FILE__) + '/public'

def setup_session
  File.rm(session[:database]) if session[:database] rescue nil
  session.clear
  session[:flash] = "You have $5 to spend, just for this session."
  session[:cash] = 5.0

  session[:database] = "/tmp/#{SecureRandom.urlsafe_base64}.db"
  FileUtils.cp("database.db", session[:database])
end

def check_session
  if session[:cash].nil?
    setup_session
    return
  end

  exists = File.exists?(session[:database])

  unless exists
    setup_session
    session[:flash] = "Your session has expired"
  end

  exists
end

def with_database(&blk) 
  #db = Amalgalite::Database.new(session[:database])
  db = SQLite3::Database.new(session[:database])
  yield db
  db.close
end

get '/restart' do
  setup_session
  redirect to('/')
end

get '/' do
  check_session

  credits = nil

  with_database do |db|
    rows = db.execute("SELECT credit FROM account WHERE id = 1")
    #puts "rows #{rows} #{rows.inspect}"
    credits = 0 if rows.nil? or rows.empty?
    #puts "credits is now #{credits}"
    credits ||= rows[0][0]
    #puts "credits is now #{credits}"
  end

  html = haml(:index, :locals => { :flash => session[:flash], :cash => session[:cash], :credits => credits})
  session.delete(:flash)
  html
end

def credit_cost(wanted)
  # 500 = $1
  # 1500 = $2.50
  # 3500 = $5

  fivers = (wanted / 3500)
  wanted = wanted % 3500

  twofiddies = (wanted / 1500)
  wanted = wanted % 1500

  onners = (wanted / 500)
  wanted = wanted % 500

  fraction = wanted

  #puts "fivers = #{fivers}, twofiddies = #{twofiddies}, onners = #{onners}, fraction = #{fraction}"
  value = (fivers * 5) + (twofiddies * 2.5) + (onners * 1) + (fraction * 0.0021)
  #puts "and value = #{value}"

  value
end

get '/purchase/:amount' do
  unless check_session
    redirect to('/')
  end

  amount = params[:amount].to_i

  if amount <= 0
    session[:flash] = "You need to buy a positive amount of credits :-)"
    redirect to('/')
    return
  end

  cost = credit_cost(amount)
  if cost > session[:cash]
    session[:flash] = "You do not have enough money to buy #{params[:amount]} tokens"
    redirect to('/')
    return
  end

  # Okay, it's purchasable.

  session[:cash] -= cost

  with_database do |db|
    query = "UPDATE account SET credit = credit + #{amount} WHERE id = 1"
    row = db.execute(query)
  end

  # if row.nil? or row.empty?
  #   session[:flash] = "Failed to log in"
  #   redirect to('/')
  # else
  #   session[:userid] = row[0][0]
  #   redirect to('/secret')
  # end

  redirect to('/')
end

get '/buyatoken' do
  unless check_session
    redirect to('/')
  end
  
  allowed = false

  with_database do |db|
    rows = db.execute("SELECT credit FROM account WHERE id = 1")
    credits = rows[0][0].to_i

    if credits >= 7000
      allowed = true
    end
  end
 
  if not allowed
    session[:flash] = "You do not have enough credits to buy a token :("
    redirect to('/')
    return
  end

  # Looks like we're allowed, so display the credit screen.

  html = haml(:secret, :locals => { :flash => session[:flash]  })
  session.delete(:flash)
  html
end

post '/buyatoken' do
  allowed = false

  unless check_session
    session[:flash] = "Your session disappeared"
    redirect to('/')
    return
  end

  with_database do |db|
    db.execute("UPDATE account SET tokens = tokens + 1, credit = credit - 7000 where id = 1 AND credit >= 7000")
    rows = db.execute("SELECT tokens FROM account WHERE id = 1");
    if(rows and rows[0])
      allowed = (rows[0][0].to_i > 0)
    end
  end

  if not allowed 
    session[:flash] = "Your account does not have enough credits :( - nice try though!"
    redirect to('/')
    return
  end

  session[:flash] = "Your token is RUXCTF{4646a01b-efe6-4c4c-8565-cf49a73b7c37}"
  redirect to('/') 

end
