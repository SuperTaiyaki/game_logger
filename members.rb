#!/usr/bin/ruby

require 'date'
require 'erubis'
# require 'tilt/erubis'
require 'tilt'
require 'cgi' # HTTP url parsing
require 'camping'
require 'camping/session'
require './bgg'

Camping.goes :Members


# Apparently the standard way for HTML forms to work is enctype=x-www-form-urlencoded. Nowhere in the rack/camping stack
# is fixing this up, so Japanese text goes funny (gets HTML entities instead of straight text).
module POSTCleanup
    class Fixer
        def initialize(app)
            @app = app
        end

        def unescape(data)
            CGI.unescapeHTML(data)
        end

        def call(env)
            # Hrm, is this going to go weird if there's a multiselect in a POST?
            rq = Rack::Request.new(env)
            if rq.post?
                rq.params.each_pair do |k, v|
                    rq.update_param(k, unescape(v))
                end
            end
            @app.call(env)
        end
    end

    def self.included(app)
        app.use Fixer
    end
end

module Members
    set :views, File.dirname(__FILE__) + '/views'
    set :secret, "notreallysecret"
    include Camping::Session
    include POSTCleanup
end

require './members/models'

module Members::Controllers

    class Index < R '/'
        def get
            @tables = History.includes(:game).where(:active => true).order(:created_at)
            render :index
        end
    end

    class UserViewN
        def get(id)
            @user = User.find(id)
            # Total hours played
            hours = Player.where(:user_id => id).select("date_trunc('second', SUM(end_time - created_at)) AS total_time").take
            @total_time = hours.total_time
            # Play history
            # SELECT players WHERE players.user_id = ?
            # ... JOIN histories ON players.history_id = histories.id
            # ... JOIN games ON games.id = histories.game_id
            # ... to select out game title
            # Hrm, join or just eager load?
            #history = Player.joins(history: :game).where(:user_id => id)
            history = Player.includes(history: :game).where(:user_id => id)
            @history = history
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
            alert("User created")
            if @input.has_key?('save_new')
                redirect(UserCreate)
            else
                redirect(UserViewN, user.id)
            end
        end
    end

    class UserList
        def get
            @users = User.where(active: true).order(:handle)
            render :user_list
        end
    end

    class GameViewN
        def get(id)
            @game = Game.find(id)
            # Total time played:
            # SELECT SUM(end_time - created_at) FROM History WHERE game_id = ?
            # Total number of plays:
            # SELECT COUNT(*) FROM History WHERE game_id = ?
            # Total number of players
            # SELECT COUNT(*) FROM History RIGHT JOIN Players ON Player.history_id = History.id WHERE game_id = ?
            time_search = History.select("date_trunc('second', SUM(end_time - created_at)) AS total_time").where(:active => false, :game_id => id).take
            @total_time = time_search.total_time
            @play_count = History.where(:active => false, :game_id => id).count
            # TODO: Trim out the H:m:d bit
            @most_recent = History.where(:active => false, :game_id => id).select("date_trunc('day', MAX(created_at)) as when").take
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

    class GameSync
        def get
            admin_check           

            @games_new = []
            @games_keep = []
            @games_delete = []
            if @input.has_key?('list_id')
                download_list(@input['list_id'])
                list = show_list()

                list.each do |g|
                    ent = Game.where(bgg_id: g[:bgg_id])
                    if ent.size == 0
                        @games_new.push(g)
                    else
                        @games_keep.push(g)
                    end
                end
                @games_new = list
                @games_keep = @games_delete = []
            end
            render :game_sync
        end

        def post()
            admin_check
            if @input.has_key?('update')
                list = show_list()
                list.each do |g|
                    ent = Game.where(bgg_id: g[:bgg_id])
                    if ent.size == 0
                        g = Game.create(name: g[:name], bgg_id: g[:bgg_id])
                    end
                end
            end
            redirect(Index)
        end
    end


    # Maybe this needs to be authenticated too?
    class TableViewN
        def get(id)
            @table = History.find(id)
            @players = @table.users
            @all_players = User.where(active: true).where.not(id: @players).order(:handle)
            @all_games = Game.where(active: true).order(:name)

            render :table_view
        end
    end
    class TableCreate
        def get()
            admin_check

            @table = History.new()
            @games = Game.where(active: true).order(:name)
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
            @games = Game.where(active: true).order(:name)
            render :table_edit
        end
    end
    class TableUpdate
        def post()
            admin_check

            if @input.has_key?('add')
                # Multiselect stuff
                @input['user'].each do |uid|
                    Player.create(:history_id => @input.table_id, :user_id => uid)
                end
                redirect TableViewN, @input.table_id
            elsif @input.has_key?('change')
                table = History.find(@input['table_id'])
                new_table = History.create(:game_id => @input['game'])
                @input.keys.each do |k|
                    if k =~ /player_(\d+)/
                        new_table.players.create(:user_id => $1)
                    end
                end
                table.close()
                table.save()
                redirect TableViewN, new_table.id
            elsif @input.has_key?('end')
                table = History.find(@input['table_id'])
                table.close()
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
            @games = History.includes(:game).select("members_histories.game_id, count(game_id) as plays").group(:game_id)
            @games = @games.order("plays DESC")
            if !(@input.has_key?('date_start') || @input.has_key?('date_end'))
                # TODO: Plug in last month or something
            else
                if @input.has_key?('date_start') && @input['date_start'].length > 0
                    @games = @games.where("members_histories.created_at >= ?", @input['date_start'])
                end
                if @input.has_key?('date_end') && @input['date_end'].length > 0
                    @games = @games.where("members_histories.created_at <= ?", @input['date_end'])
                end
            end

            if @input.has_key?('limit')
                @games = @games.limit(@input['limit'])
            else
                @games = @games.limit(15)
            end


            render :game_rankings
        end
    end

    class GameFilter
        def get
            # TODO: Fit in a default filter so this doesn't take too long to load
            
            query = History.includes(:users, :game).order(:created_at).where(:active => false)
            if @input.has_key?('games')
                query = query.where(game_id: @input['games'])
            end
            # Changed 'players' to 'p' to shorten the GET request - stops the request overflowing
            if @input.has_key?('p')
                # Uggghhh activerecord, get out of my way...
                # TODO: Kill the members_ bit of the table names and fix this
                # Want all the games where a player was in a game. Subquery is more straightforward than joins because
                # the WHERE needs to filter on players, but the result needs all the players.
                query = query.where("members_histories.id IN (SELECT members_histories.id FROM members_histories INNER JOIN members_players ON members_players.history_id = members_histories.id WHERE members_players.user_id IN (?))", @input['p'])
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

            @selected_players = @input.has_key?('p') ? @input['p'].map { |x| x.to_i } : []
            @selected_games = @input.has_key?('games') ? @input['games'].map { |x| x.to_i } : []
            # Fill in the dropdowns
            @all_games = Game.where(active: true).order(:name)
            @all_users = User.where(active: true).order(:handle)
            render :game_filter
        end
    end

    class GameList
        def get
            @games = Game.where(active: true).order(:name)
            render :game_list
        end
    end

    class Login
        def get
            render :login
        end
        def post
            # TODO: THIS IS DUMB AND WRONG
            # Postgres is missing pgcrypt on the openshift gear, fix later
            check = Admin.where(:username => @input['username'], :password => Digest::SHA2.base64digest(@input['password']))
            if check.count > 0
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
            alert("Login required.")
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

    def alert(message)
        alert_raw(CGI.escapeHTML(message))
    end

    def alert_raw(message)
        if !@state.has_key?('alert')
            @state['alert'] = []
        end
        @state['alert'].push(message)
    end

    def alerts
        if @state.has_key?('alert')
            @state['alert']
        else
            []
        end
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
    #
    Camping::Models::Base.logger = Logger.new(STDOUT)
    Camping::Models::Base.clear_active_connections!

    Camping::Models::Base.establish_connection(ENV['OPENSHIFT_POSTGRESQL_DB_URL'] + '/gamelog')
else
    print "No database set"
    exit
end

