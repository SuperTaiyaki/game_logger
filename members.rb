#!/usr/bin/ruby

require 'erubis'
require 'tilt/erubis'
require 'cgi' # HTTP url parsing
require 'camping'
require 'camping/session'

Camping.goes :Members

#require 'active_record'

module Members
    set :views, File.dirname(__FILE__) + '/views'
    set :secret, "notreallysecret"
    include Camping::Session
end

module Members::Models
    # Why does Osaka get an entry?
    # For now, this causes .created_at to become Nil
    # Base.default_timezone = 'Osaka'
    # Enable the SQL logging

    # http://blog.evanweaver.com/2006/09/17/make-camping-connect-to-mysql/ ?

    #Base.logger = Logger.new(STDOUT)
    #Base.clear_active_connections!
    
    class User < Base
        has_many :histories, :through => :players
        has_many :players
    end

    class Game < Base
        has_many :histories
        # Unfortunately this doesn't work - R not defined, GameViewN not defined... 
        def link(obj)
            return "<a href='#{R(obj, self.id)}'>#{self.name}</a>"
        end
    end

    class History < Base
        belongs_to :game # This probably isn't quite the right relation, but it works
        #has_many :users
        has_many :players
        has_many :users, :through => :players
    end

    class Player < Base
        belongs_to :user
        belongs_to :history
    end

    class BasicFields1 < V 1.0
        def self.up
            create_table User.table_name do |t|
                t.string :name
                t.string :handle
                t.timestamps
            end

            create_table Game.table_name do |t|
                t.string :name
            end

            create_table History.table_name do |t|
                t.timestamps
                t.integer :game_id
            end

            # Join table, this really shouldn't have an index
            create_table Player.table_name do |t|
                t.integer :history_id
                t.integer :user_id
            end

            #User.create(:name => "Test Player", :handle => "Haaandle")
            #Game.create(:name => "Test game")
        end

        def self.down
            drop_table User.table_name
            drop_table Game.table_name
            drop_table History.table_name
            drop_table Players.table_name
        end
    end

    class Fields2 < V 1.1
        def self.up
            change_table History.table_name do |t|
                t.boolean :active, default: true
            end
            change_table User.table_name do |t|
                t.boolean :active, default: true
            end
        end
    end

end

module Members::Controllers

    class Index < R '/'
        def get

            #@users = User.all()
            #@games = Game.all()

            @tables = History.includes(:game).where(:active => true).order(:created_at)

            render :index
        end
    end

    class UserViewN
        def get(id)
            @user = User.find(id)
            render :member_view
        end
    end
    class UserEditN
        def get(id)
            admin_check
            @user = User.find(id)
            render :member_edit
        end
    end
    class UserCreate
        def get
            admin_check

            @user = User.new()
            render :member_edit
        end
        def post
            admin_check

            if @input.id
                user = User.find(@input.id)
            else
                user = User.new()
            end
            user.name = @input.name
            user.handle = @input.handle
            user.save()
            redirect(UserViewN, user.id)
        end
    end

    class GameViewN
        def get(id)
            @game = Game.find(id)
            render :game_view
        end
    end
    class GameEditN
        def get(id)
            admin_check

            @game = Game.find(id)
            render :game_edit
        end
    end
    class GameCreate

        def get()
            admin_check
            @game = Game.new()
            render :game_edit
        end
        def post()
            admin_check
            if @input.id
                game = Game.find(@input.id)
            else
                game = Game.new()
            end
            game.name = @input.name
            game.save()
            redirect(GameViewN, game.id)
        end
    end

    # Maybe this needs to be authenticated too?
    class TableViewN
        def get(id)
            @table = History.find(id)
            @players = @table.users
            #@all_players = User.all()
            @all_players = User.where.not(id: @players).order(:handle)
            @all_games = Game.all.order(:name)

            render :table_view
        end
    end
    class TableCreate
        def get()
            admin_check

            @table = History.new()
            @games = Game.all().order(:name)
            render :table_edit
        end
        def post()
            admin_check

            if @input.id
                table = History.find(@input.id)
            else
                table = History.new()
            end

            table.game_id = @input.game

            table.save()

            redirect(TableViewN, table.id)
        end
    end
    class TableEditN
        def get(id)
            admin_check
            # TODO: Link up the currently active game and players
            @table = History.find(id)
            @games = Game.all().order(:name)
            render :table_edit
        end
    end
    class TableUpdate
        def post()
            admin_check

            if @input.has_key?('add')
                Player.create(:history_id => @input.table_id, :user_id => @input.user)
                redirect TableViewN, @input.table_id
            elsif @input.has_key?('change')
                table = History.find(@input['table_id'])
                new_table = History.create(:game_id => @input['game'])
                @input.keys.each do |k|
                    if k =~ /player_(\d+)/
                        new_table.players.create(:user_id => $1)
                    end
                end
                table.active = false
                table.save
                redirect TableViewN, new_table.id
            elsif @input.has_key?('end')
                table = History.find(@input['table_id'])
                table.active = false
                table.save()
                redirect Index
            end
        end
    end

    class GameRanking
        def get()
            # Most popular games within given timeframe
            # Popularity = number of games played = entries in the History table for each game
            # SQL is something like
            # SELECT game_id, count(game_id) FROM members_histories GROUP BY game_id ORDER BY count(game_id) desc;
            #@games = Game.
            # .count() does... something I don't want, a number comes out at the end instead of regular results
            @games = History.select("members_histories.game_id, count(game_id) as plays").group(:game_id)
            if @input.has_key?('date_start') && @input['date_start'].length > 0
                @games = @games.where("members_histories.created_at >= ?", @input['date_start'])
            end
            if @input.has_key?('date_end') && @input['date_end'].length > 0
                @games = @games.where("members_histories.created_at <= ?", @input['date_end'])
            end
            if @input.has_key?('limit')
                @games = @games.limit(@input['limit'])
            end

            # TODO: Add in the .where bit. Looks like:
            # Client.where(created_at: (Time.now.midnight - 1.day)..Time.now.midnight)
            render :game_rankings
        end
    end

    class GameFilter
        def get()
            # TODO: Fit in a default filter so this doesn't take too long to load
            # Camping seems not to deal with multi select forms - they get crunched:
            # Query: date_start=&date_end=&games=1&games=2&games=3&games=4&filter=Filter
            # Data: {"date_start"=>"", "date_end"=>"", "games"=>"4", "filter"=>"Filter"}
            # Break it up with stdlib CGI instead
            parts = @env['QUERY_STRING']
            request = CGI.parse(parts)

            query = History.includes(:users, :game).order(:created_at).where(:active => false)
            if request['games'].length > 0
                query = query.where(game_id: request['games'])
            end
            # Changed 'players' to 'p' to shorten the GET request - stops the request overflowing
            if request['p'].length > 0
                # Uggghhh activerecord, get out of my way...
                # TODO: Kill the members_ bit of the table names and fix this
                # Want all the games where a player was in a game. Subquery is more straightforward than joins because
                # there WERE needs to filter on players, but the result needs all the players.
                query = query.where("members_histories.id IN (SELECT members_histories.id FROM members_histories INNER JOIN members_players ON members_players.history_id = members_histories.id WHERE members_players.user_id IN (?))", request['p'])
            end
            # date_start and _end aren't multiselects, so back to @input
            if @input.has_key?('date_start') && @input['date_start'].length > 0
                query = query.where("members_histories.created_at >= ?", @input['date_start'])
            end
            if @input.has_key?('date_end') && @input['date_end'].length > 0
                query = query.where("members_histories.created_at <= ?", @input['date_end'])
            end
            @games = query
            @count = query.size

            @selected_players = request['p'].map { |x| x.to_i }
            @selected_games = request['games'].map { |x| x.to_i }
            # Fill in the dropdowns
            @all_games = Game.all().order(:name)
            @all_users = User.all().order(:handle)
            render :game_filter
        end
    end

    class Login
        def get
            render :login
        end
        def post
            if @input['password'] == 'password'
                @state['admin'] = true
                redirect Index
            else
                # TODO: Error messages!
                redirect Login
            end
        end
    end
    class Logout
        def get
            @state.delete('admin')
            redirect Index
        end
    end

end
module Members::Helpers
    def admin_check
        # Huh, @state doesn't refer to anything at this point, and yet it works?
        if !is_admin
            # TODO: Some sort of error message
            redirect Index
            throw :halt
        end
    end

    # To be called from the templates
    def is_admin
        @state.has_key?('admin')
    end

    def ts(time)
        time.localtime.strftime("%Y-%m-%d %H:%M")
    end

    # Could define the erb 'h' here too, apparently, and remove the dependency on erubis
end


module Members::Views
    #def layout(&block)
    #    @is_admin = @state.has_key?('admin')
    #    render :layout_html, &block
    #end
end

def Members.create
    Members::Models.create_schema
end

if ENV.has_key?('OPENSHIFT_POSTGRESQL_DB_USERNAME')
    #Camping::Base.establish_connection(:adapter => 'postgresql',
    #    :database => 'meeple',
    #    :username => 'user',
    #    :password => 'password')
    Camping::Models::Base.establish_connection(ENV['OPENSHIFT_POSTGRESQL_DB_URL'] + '/gamelog')
end

