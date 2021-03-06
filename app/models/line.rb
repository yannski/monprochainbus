class NoNextArrivals < StandardError; end

class Line
  include ActiveModel::Model
  include ActiveModel::Serialization

  attr_accessor :name, :mode, :stop, :line_directions

  def stop_id
    stop.slug
  end

  def id
    [stop.slug, name].join("-").parameterize
  end

  def self.fetch(stop: stop, number: 1)
    code = stop.code
    response = SoapClient.new.call(:recherche_prochaines_arrivees_web,
      message: { code_arret: code, nb_horaires: number}
    ) do
       advanced_typecasting false
    end
    response = response.body[:recherche_prochaines_arrivees_web_response]
    res = response[:recherche_prochaines_arrivees_web_result][:liste_arrivee].try(:[], :arrivee)
    raise NoNextArrivals if res.blank?
    res = [res] unless res.is_a? Array

    now_parent = Time.zone.now

    ary = res.inject({}){|memo, obj|
      now = now_parent.dup
      hour, min, sec = obj[:horaire].split(":")
      scheduled_remaining_time = now.change(hour: hour, min: min, sec: sec)
      scheduled_remaining_time += 1.day if obj[:est_apres_minuit] == "true" && now <= now.end_of_day && now >= (now.end_of_day - 3.hours)
      mode = obj[:mode].to_s.downcase
      head, *tail = obj[:destination].split(" ")
      line_name = head
      direction_name = tail.join(" ")

      if (line = memo[ line_name ]).blank?
        line_direction = LineDirection.new(line: line, name: direction_name, mode: mode, scheduled_times: [ scheduled_remaining_time ])
        line = Line.new stop: stop, mode: mode, name: line_name, line_directions: [ line_direction ]
        line.line_directions.first.line = line
        memo[ line_name ] = line
      else
        if (already_existing_line_direction = line.line_directions.detect{|x| x.mode == mode && x.name == direction_name }).blank?
          line.line_directions << LineDirection.new(line: line, name: direction_name, mode: mode, scheduled_times: [ scheduled_remaining_time ])
        else
          already_existing_line_direction.scheduled_times << scheduled_remaining_time
        end
      end
      memo
    }.values

    ary.sort!{|x,y| x.name <=> y.name }

    ary.each{|x|
      x.line_directions.sort!{|x,y| x.name <=> y.name }
    }
  end
end
