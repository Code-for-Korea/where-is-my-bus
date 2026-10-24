# frozen_string_literal: true

# loading config/traccar.yml
Rails.configuration.x.traccar = Rails.application.config_for(:traccar)
