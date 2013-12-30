
module Members::Models
    # Enable the SQL logging

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

        def close
            # UPDATE Players SET end_time = now() WHERE history_id = ?
            self.players.update_all(end_time: DateTime.now)
            self.update(active: false, end_time: DateTime.now)
            # No implicit save
        end
    end

    class Player < Base
        belongs_to :user
        belongs_to :history
    end

    class Admin < Base
    end

    class Option < Base
    end
# {{{ Migrations
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

    class Fields3 < V 1.2
        def self.up
            create_table Admin.table_name do |t|
                t.string :username
                t.string :password
            end
        end
    end

    class Fields4 < V 1.4
        def self.up
            change_table Player.table_name do |t|
                t.timestamp :end_time
            end
            change_table History.table_name do |t|
                t.timestamp :end_time
            end
        end
    end

    class Fields5 < V 1.5
       def self.up
           change_table Game.table_name do |t|
               t.integer :bgg_id
               t.integer :bgg_updated
           end
           change_table Player.table_name do |t|
               t.timestamps
           end
           create_table Option.table_name do |t|
               t.string :name
               t.string :value
           end
       end
    end

    class Fields6 < V 1.6
        def self.up
            change_table Game.table_name do |t|
                t.boolean :active, default: true
            end
        end

    end
    # }}}
end

