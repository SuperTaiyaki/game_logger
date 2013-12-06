#!/usr/bin/ruby

require 'erubis'
require 'tilt/erubis'

Camping.goes :Members
module Members
    set :views, File.dirname(__FILE__) + '/views'
end


module Members::Models
    class User < Base
        has_many :histories, :through => :players
        has_many :players
    end

    class Game < Base
        has_many :histories
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

            User.create(:name => "Test Player", :handle => "Haaandle")
            Game.create(:name => "Test game")
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
            @user = User.find(id)
            render :member_edit
        end
    end
    class UserCreate
        def get
            @user = User.new()
            render :member_edit
        end
        def post
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
            @game = Game.find(id)
            render :game_edit
        end
    end
    class GameCreate
        def get()
            @game = Game.new()
            render :game_edit
        end
        def post()
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
            @table = History.new()
            @games = Game.all()
            render :table_edit
        end
        def post()
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
            # TODO: Link up the currently active game and players
            @table = History.find(id)
            @games = Game.all()
            render :table_edit
        end
    end
    class TableAddPlayer
        def post()
            Player.create(:history_id => @input.table_id, :user_id => @input.user)
            redirect TableViewN, @input.table_id
        end
    end

end

module Members::Views
end

def Members.create
    Members::Models.create_schema
end

