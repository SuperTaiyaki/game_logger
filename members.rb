#!/usr/bin/ruby

require 'erubis'
require 'tilt/erubis'
require 'cgi' # HTTP url parsing
require 'camping/session'

Camping.goes :Members
module Members
    set :views, File.dirname(__FILE__) + '/views'
    set :secret, "notreallysecret"
    include Camping::Session
end

module Members::Models
    # Enable the SQL logging
    Base.logger = Logger.new(STDOUT)
    Base.clear_active_connections!

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
                t.string :game_id 
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
end

module Members::Controllers


    class Index < R '/'
        def get

            @users = User.all()
            @games = Game.all()

            @tables = History.includes(:game).all()

            render :index
        end
    end

    class Page2 < R '/2/(.*)'
        def get(args)
            "Args are #{args}"
        end
    end

    class Members
        def get
            @users = User.all(:select => "handle")
            render :list
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
            admin_check2
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
            @all_players = User.all()
            render :table_view
        end
    end
    class TableCreate
        def get()
            admin_check

            @table = History.new()
            @games = Game.all()
            render :table_edit
        end
        def post()
            admin_Check

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
            @games = Game.all()
            render :table_edit
        end
    end
    class TableAddPlayer
        def post()
            admin_check
            Player.create(:history_id => @input.table_id, :user_id => @input.user)
            redirect TableViewN, @input.table_id
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
            @games = History.select("game_id, count(game_id) as plays, created_at").group(:game_id)
            if @input.has_key?('date_start') && @input['date_start'].length > 0
                @games = @games.where("created_at >= ?", @input['date_start'])
            end
            if @input.has_key?('date_end') && @input['date_end'].length > 0
                @games = @games.where("created_at <= ?", @input['date_end'])
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

            query = History.includes(:users, :game).order(:created_at)
            if request['games'].length > 0
                query = query.where(game_id: request['games'])
            end
            if request['players'].length > 0
                # Uggghhh activerecord, get out of my way...
                # TODO: Kill the members_ bit of the table names and fix this
                query = query.where(members_users: {id: request['players']})
            end
            # date_start and _end aren't multiselects, so back to @input
            if @input.has_key?('date_start') && @input['date_start'].length > 0
                query = query.where("created_at >= ?", @input['date_start'])
            end
            if @input.has_key?('date_end') && @input['date_end'].length > 0
                query = query.where("created_at <= ?", @input['date_end'])
            end
            # @args = @input.to_s
            @games = query
            @count = query.size
            @args = request.to_s
            @rq = @env['QUERY_STRING'].to_s

            # Fill in the dropdowns
            @all_games = Game.all()
            @all_users = User.all()
            render :game_filter
        end
    end

    class Login
        def get()
            @state['admin'] = true
            redirect Index
        end
    end
    class Logout
        def get()
            @state.delete('admin')
            redirect Index
        end
    end


end
module Members::Helpers
    def admin_check
        # Huh, @state doesn't refer to anything at this point, and yet it works?
        if !@state.has_key?('admin')
            # TODO: Some sort of error message
            redirect Index
            throw :halt
        end
    end

    # To be called from the templates
    def is_admin
        @state.has_key?('admin')
    end

    # Could define the erb 'h' here too, apparently
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

